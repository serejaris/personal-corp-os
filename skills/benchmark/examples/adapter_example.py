#!/usr/bin/env python3
"""Minimal LLM adapter for llm.py: transcript → notes.md → code checks → judge.

Copy it next to your task and change the three prompts and check_notes().
Input: the ASR run named in task["llm"]["input_asr"] (runs/<name>/asr/<id>/transcript.txt).

    BENCH_SKILL=<skill>/scripts python3 adapter_example.py --task task.json \
        --variant variant.json --out runs/<name>/llm/<id> --stage all
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, os.environ["BENCH_SKILL"])
from claude_step import run_step  # noqa: E402

AUTHOR = """Read {src}. Write {dst}: a summary for a participant who missed the meeting.
Sections: `## TL;DR`, `## Decisions`, `## Tasks` (who, what, when, only if said), `## Open questions`.
Every statement must be supported by the transcript. No names of participants. Do not touch other files."""

FIX = """{dst} failed these checks:
{failed}
Fix only what the checks name. Do not touch other files."""

JUDGE = """You check a meeting summary against its transcript. Do not edit files.
Summary: {dst}. Transcript (source of truth): {src}.
Find: unsupported claims, reversed meaning, invented tasks or dates, names of participants, major topics missing.
Severity: critical (false, reversed, invented, private data), major (notable inaccuracy or missing major topic), minor.
Write only JSON to {verdict} and print it:
{{"verdict": "pass" | "fail", "issues": [{{"severity": "...", "claim": "...", "evidence": "..."}}], "summary": "..."}}
fail if any critical or more than two major."""


def check_notes(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    checks = [
        ("file exists", bool(text)),
        ("has TL;DR", "## TL;DR" in text),
        ("has Tasks", "## Tasks" in text),
        ("no long dash", "—" not in text),
    ]
    return [{"name": n, "ok": ok} for n, ok in checks]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", required=True, type=Path)
    ap.add_argument("--variant", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--stage", default="all")
    a = ap.parse_args()
    task = json.loads(a.task.read_text(encoding="utf-8"))
    v = json.loads(a.variant.read_text(encoding="utf-8"))
    work = a.out / "run"
    src, dst, res_path = work / "transcript.txt", work / "notes.md", a.out / "result.json"

    if a.stage in ("all", "author"):
        if work.exists():
            shutil.rmtree(work)
        work.mkdir(parents=True)
        shutil.copyfile(a.out.parent.parent / "asr" / task["llm"]["input_asr"] / "transcript.txt", src)
        steps = []
        s = run_step(AUTHOR.format(src=src, dst=dst), cwd=work, log_dir=work / "logs", name="author", **v["author"])
        steps.append({**s, "role": "author"})
        first = check_notes(dst)
        final, rounds = first, 0
        if not all(c["ok"] for c in first):
            failed = "\n".join(f"- {c['name']}" for c in first if not c["ok"])
            s = run_step(FIX.format(dst=dst, failed=failed), cwd=work, log_dir=work / "logs", name="fix-1", **v["author"])
            steps.append({**s, "role": "fixer"})
            final, rounds = check_notes(dst), 1
        text = dst.read_text(encoding="utf-8") if dst.exists() else ""
        res_path.write_text(json.dumps({
            "steps": steps, "checks_first": first, "checks_final": final, "fix_rounds": rounds,
            "checks_ok": all(c["ok"] for c in final), "judges": [], "errors": [],
            "artifacts": {"notes_kb": round(len(text.encode()) / 1024, 1),
                          "sections": len(re.findall(r"(?m)^## ", text))},
        }, ensure_ascii=False, indent=2), encoding="utf-8")

    if a.stage in ("all", "judge"):
        res = json.loads(res_path.read_text(encoding="utf-8"))
        for j in v.get("judges", []):
            verdict_path = work / f"verdict-{j['provider']}-{j['model']}.json"
            s = run_step(JUDGE.format(dst=dst, src=src, verdict=verdict_path), cwd=work, log_dir=work / "logs",
                         name=f"judge-{j['provider']}-{j['model']}", **j)
            res["steps"].append({**s, "role": "judge"})
            try:
                data = json.loads(verdict_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                data = {"verdict": None, "issues": [], "summary": "judge wrote no JSON"}
            sev = [i.get("severity") for i in data.get("issues", [])]
            res["judges"].append({**j, "verdict": data.get("verdict"), "critical": sev.count("critical"),
                                  "major": sev.count("major"), "minor": sev.count("minor"),
                                  "summary": (data.get("summary") or "")[:300]})
        res_path.write_text(json.dumps(res, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
