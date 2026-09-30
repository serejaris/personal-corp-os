#!/usr/bin/env python3
"""Score a benchmark run: quality, time and cost per variant -> results.json + results.csv.

    python3 score.py --task task.json --out runs/<name> --prices prices.json

ASR quality (reference = a checked transcript of the same recording):
    wer, cer            word / character error rate after normalisation (lower case, ё→е,
                        punctuation and speaker tags removed)
    wer_termnorm        WER after the terms list's known distortions are replaced by the
                        canonical spelling in both texts: spelling of terms stops counting
    term_accuracy       of all term mentions in the output, share written canonically:
                        canon / (canon + known distortions); needs no reference
    term_recall         canonical term mentions found vs. the reference (after its own
                        distortions are fixed), per term capped at the reference count

    asr_pairwise_wer    WER of engine B's text taken as reference for engine A: distance between
                        engines that does not depend on the reference

LLM quality comes from the adapter's result.json: code checks before and after fixes,
judges' verdicts (critical / major / minor).

Cost per hour of recording, USD and RUB, from prices.json (every price carries source and
date). Basis is written next to every number: api_price, tokens, server_share, reported.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import load_task, read_json, task_path, utc_now, write_json  # noqa: E402

SECONDS_PER_MONTH = 30.44 * 86400


# --- text --------------------------------------------------------------------

def norm(text: str) -> str:
    text = re.sub(r"\[S\d+\]", " ", text).lower().replace("ё", "е")
    text = re.sub(r"[^\w]+|_", " ", text)
    return " ".join(text.split())


def load_reference(task: dict) -> str:
    raw = task_path(task, task["reference"]).read_text(encoding="utf-8")
    raw = re.sub(r"<!--.*?-->", " ", raw, flags=re.S)
    lines = [l for l in raw.splitlines() if not l.lstrip().startswith("#")]
    text = "\n".join(lines)
    for pattern in task.get("reference_drop_regex", []):
        text = re.sub(pattern, " ", text, flags=re.M)
    return text


def pattern(s: str, stem: bool = False) -> re.Pattern:
    body = re.escape(s.lower()).replace(r"\*", r"\w*").replace(r"\ ", r"[\s\-]+")
    if stem:
        body += r"\w*"
    return re.compile(rf"(?<!\w){body}(?!\w)", re.I)


def load_terms(task: dict) -> list[dict]:
    path = task_path(task, task.get("terms"))
    if not path:
        return []
    out = []
    for t in read_json(path).get("terms", []):
        out.append({"canon": t["canon"], "re": pattern(t["canon"], stem=t.get("lang") == "ru"),
                    "variants": [pattern(v) for v in sorted(t.get("variants", []), key=len, reverse=True)]})
    return out


def fix_terms(text: str, terms: list[dict]) -> str:
    for t in sorted(terms, key=lambda t: len(t["canon"]), reverse=True):
        for v in t["variants"]:
            text = v.sub(t["canon"], text)
    return text


def term_counts(text: str, terms: list[dict]) -> dict:
    return {t["canon"]: {"canon": len(t["re"].findall(text)), "variants": sum(len(v.findall(text)) for v in t["variants"])}
            for t in terms}


# --- cost --------------------------------------------------------------------

def fx(prices: dict) -> tuple[float, float]:
    f = prices["fx"]
    return f["USD_RUB"], f["EUR_RUB"]


def tokens_cost(item: dict, usage: dict) -> float:
    p = item["usd_per_mtok"]
    return (usage.get("input_tokens", 0) * p["in"]
            + usage.get("cache_creation_input_tokens", 0) * p.get("cache_write", p["in"])
            + usage.get("cache_read_input_tokens", 0) * p.get("cache_read", p["in"])
            + usage.get("output_tokens", 0) * p["out"]) / 1e6


def server_share_usd(prices: dict, cpu_s: float) -> float:
    s = prices["items"]["self_hosted"]
    usd_rub, eur_rub = fx(prices)
    eur = cpu_s / (s["threads"] * SECONDS_PER_MONTH) * s["eur_per_month"]
    return eur * eur_rub / usd_rub


def asr_cost(meta: dict, v: dict, prices: dict) -> tuple[float | None, str]:
    """USD for this run (not per hour yet) and the basis."""
    key = v.get("price")
    item = prices["items"].get(key or "", {})
    hours = meta["audio_s"] / 3600
    usd_rub, _ = fx(prices)
    if key == "self_hosted":
        cpu = (meta.get("usage") or {}).get("host_cpu_s") or meta.get("cpu_s") or 0
        return server_share_usd(prices, cpu), f"server_share: {cpu:.0f} CPU-s"
    if item.get("kind") == "per_hour":
        usd = item["usd"] if "usd" in item else item["rub"] / usd_rub
        return usd * hours, f"api_price: {item.get('source', '')}"
    if item.get("kind") == "tokens":
        u = meta.get("usage") or {}
        if u.get("cost_usd_reported"):
            return u["cost_usd_reported"], "reported by provider"
        p = item["usd_per_mtok"]
        if u.get("prompt_tokens"):
            return (u["prompt_tokens"] * p.get("audio_in", p["in"]) + u.get("completion_tokens", 0) * p["out"]) / 1e6, "tokens"
        if item.get("audio_tokens_per_sec"):
            est = (meta["audio_s"] * item["audio_tokens_per_sec"] * p.get("audio_in", p["in"])
                   + hours * item.get("est_out_tokens_per_hour", 0) * p["out"]) / 1e6
            return est, "estimate: audio tokens/s × price"
    return None, "no price"


def step_usage(step: dict) -> dict:
    """Token totals of a step; modelUsage (includes sub-agents) wins over main-thread usage."""
    mu = step.get("model_usage") or {}
    if mu:
        return {"input_tokens": sum(m.get("inputTokens", 0) for m in mu.values()),
                "cache_creation_input_tokens": sum(m.get("cacheCreationInputTokens", 0) for m in mu.values()),
                "cache_read_input_tokens": sum(m.get("cacheReadInputTokens", 0) for m in mu.values()),
                "output_tokens": sum(m.get("outputTokens", 0) for m in mu.values())}
    return step.get("usage") or {}


def step_cost(step: dict, prices: dict) -> tuple[float | None, str]:
    prov, model = step["provider"], step["model"]
    if prov.startswith("anthropic"):
        if step.get("cost_usd_reported") is not None:
            return step["cost_usd_reported"], "reported: Claude Code at Anthropic list prices"
        return None, "no price"
    item = prices["items"].get(f"{prov}.{model}")
    if not item:
        return None, "no price"
    return tokens_cost(item, step_usage(step)), f"tokens × {prov} list price"


# --- main --------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--task", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--prices", required=True, type=Path)
    args = ap.parse_args()

    import jiwer

    task = load_task(args.task)
    prices = read_json(args.prices)
    usd_rub, _ = fx(prices)
    terms = load_terms(task)
    ref_raw = load_reference(task)
    ref = norm(ref_raw)
    ref_tn = norm(fix_terms(ref_raw, terms))
    ref_terms = term_counts(fix_terms(ref_raw, terms), terms)

    asr_rows, audio_s = [], None
    for v in task.get("asr", []):
        meta_path = args.out / "asr" / v["id"] / "meta.json"
        if not meta_path.exists():
            continue
        meta = read_json(meta_path)
        audio_s = audio_s or meta.get("audio_s")
        row = {"stage": "asr", "id": v["id"], "engine": v["engine"], "model": v.get("model"), "status": meta["status"],
               "error": meta.get("error"), "wall_s": meta.get("wall_s"),
               "cpu_s": (meta.get("usage") or {}).get("host_cpu_s") or meta.get("cpu_s")}
        usd, basis = asr_cost(meta, v, prices) if meta.get("audio_s") else (None, "")
        if meta["status"] != "ok" and v.get("price") == "self_hosted":
            usd, basis = None, "not measured"
        hours = (meta.get("audio_s") or 3600) / 3600
        if usd is not None:
            row.update(usd_per_hour=round(usd / hours, 4), rub_per_hour=round(usd / hours * usd_rub, 2))
        row["cost_basis"] = basis
        if meta["status"] == "ok":
            hyp_raw = (args.out / "asr" / v["id"] / "transcript.txt").read_text(encoding="utf-8")
            hyp = norm(hyp_raw)
            tc = term_counts(hyp_raw, terms)
            canon = sum(c["canon"] for c in tc.values())
            wrong = sum(c["variants"] for c in tc.values())
            ref_total = sum(c["canon"] for c in ref_terms.values())
            recall = sum(min(tc[k]["canon"], ref_terms[k]["canon"]) for k in tc) / ref_total if ref_total else None
            row.update(
                rtf=round(meta["wall_s"] / meta["audio_s"], 4),
                words=len(hyp.split()), ref_words=len(ref.split()),
                wer=round(jiwer.wer(ref, hyp), 4), cer=round(jiwer.cer(ref, hyp), 4),
                wer_termnorm=round(jiwer.wer(ref_tn, norm(fix_terms(hyp_raw, terms))), 4),
                term_canon=canon, term_distortions=wrong,
                term_accuracy=round(canon / (canon + wrong), 4) if canon + wrong else None,
                term_recall=round(recall, 4) if recall is not None else None,
                credits_used=(meta.get("usage") or {}).get("credits_used"),
                terms_detail={k: c for k, c in tc.items() if c["canon"] or c["variants"] or ref_terms[k]["canon"]},
            )
        asr_rows.append(row)

    # Pairwise WER between engines: tells how far engines are from each other without
    # trusting the reference (useful when the reference came from one of the engines).
    texts = {r["id"]: norm((args.out / "asr" / r["id"] / "transcript.txt").read_text(encoding="utf-8"))
             for r in asr_rows if r["status"] == "ok"}
    pairwise = {a: {b: round(jiwer.wer(texts[a], texts[b]), 4) for b in texts if b != a} for a in texts}

    for n in task.get("not_run", []):
        item = prices["items"].get(n.get("price", ""), {})
        usd = item.get("usd") if "usd" in item else (item["rub"] / usd_rub if "rub" in item else None)
        asr_rows.append({"stage": "asr", "id": n["id"], "status": "not_run", "error": n["reason"],
                         "usd_per_hour": round(usd, 4) if usd else None,
                         "rub_per_hour": round(usd * usd_rub, 2) if usd else None,
                         "cost_basis": f"api_price: {item['source']}" if item.get("source") else "not measured"})

    llm_rows = []
    hours = (audio_s or 3600) / 3600
    for v in (task.get("llm") or {}).get("variants", []):
        d = args.out / "llm" / v["id"]
        if not (d / "result.json").exists():
            continue
        res = read_json(d / "result.json")
        author_steps = [s for s in res["steps"] if s["role"] in ("author", "fixer")]
        judge_steps = [s for s in res["steps"] if s["role"] == "judge"]
        a_usd, a_basis = 0.0, set()
        for s in author_steps:
            c, b = step_cost(s, prices)
            a_basis.add(b)
            a_usd = a_usd + c if c is not None and a_usd is not None else None
        judges = []
        for j in res.get("judges", []):
            st = [s for s in judge_steps if s["provider"] == j["provider"] and s["model"] == j["model"]]
            c, b = step_cost(st[-1], prices) if st else (None, "")
            judges.append({**j, "wall_s": st[-1]["wall_s"] if st else None,
                           "usd": round(c, 4) if c is not None else None, "cost_basis": b})
        first_fail = [c["name"] for c in res.get("checks_first", []) if not c["ok"]]
        final_fail = [c["name"] for c in res.get("checks_final", []) if not c["ok"]]
        models = sorted({m for s in author_steps for m in (s.get("model_usage") or {})}) or [v["author"]["model"]]
        llm_rows.append({
            "stage": "llm", "id": v["id"], "author": f"{v['author']['provider']}/{v['author']['model']}",
            "author_models": models, "status": "ok" if res.get("artifacts") else "error",
            "error": "; ".join(res.get("errors", []))[:400] or None,
            "author_wall_s": round(sum(s["wall_s"] for s in author_steps), 1),
            "canon_wall_s": next((s["wall_s"] for s in author_steps if s["name"] == "canon"), None),
            "author_turns": sum(s.get("num_turns") or 0 for s in author_steps),
            "tokens": {k: sum(step_usage(s).get(k, 0) for s in author_steps) for k in
                       ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")},
            "usd_run": round(a_usd, 4) if a_usd is not None else None,
            "usd_per_hour": round(a_usd / hours, 4) if a_usd is not None else None,
            "rub_per_hour": round(a_usd / hours * usd_rub, 2) if a_usd is not None else None,
            "cost_basis": "; ".join(sorted(a_basis)),
            "checks_first_failed": first_fail, "fix_rounds": res.get("fix_rounds"),
            "checks_final_failed": final_fail, "checks_ok": res.get("checks_ok"),
            "judges": judges, "artifacts": res.get("artifacts", {}),
        })

    results = {"task": task.get("name"), "generated_at": utc_now(), "audio_s": audio_s,
               "fx": prices["fx"], "prices_checked_at": prices.get("checked_at"),
               "reference": {"words": len(ref.split()), "note": task.get("reference_note", "")},
               "asr": asr_rows, "asr_pairwise_wer": pairwise, "llm": llm_rows}
    write_json(args.out / "results.json", results)

    cols = ["stage", "id", "engine", "model", "author", "status", "wall_s", "rtf", "cpu_s", "author_wall_s",
            "usd_per_hour", "rub_per_hour", "cost_basis", "wer", "cer", "wer_termnorm", "term_accuracy", "term_recall",
            "term_canon", "term_distortions", "credits_used", "checks_first_failed", "fix_rounds", "checks_ok",
            "judge_verdicts", "error"]
    with (args.out / "results.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore", lineterminator="\n")
        w.writeheader()
        for row in asr_rows + llm_rows:
            flat = dict(row)
            if "judges" in row:
                flat["judge_verdicts"] = " | ".join(
                    f"{j['provider']}/{j['model']}: {j['verdict']} c{j['critical']} M{j['major']} m{j['minor']}"
                    for j in row["judges"])
            for k in ("checks_first_failed",):
                if isinstance(flat.get(k), list):
                    flat[k] = ", ".join(flat[k])
            w.writerow(flat)
    print(f"results: {args.out / 'results.json'}, {args.out / 'results.csv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
