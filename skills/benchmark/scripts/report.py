#!/usr/bin/env python3
"""Render results.json as one static HTML page (tables with inline bars, light and dark).

    python3 report.py --results runs/<name>/results.json --out report.html [--title "..."] [--notes notes.md]

The page shows only aggregate numbers: no transcript text, so it is safe to share
when the recording itself is private. --notes adds a short markdown-ish list
(one bullet per line starting with "- ") under the tables.
"""

from __future__ import annotations

import argparse
import html
import json
from pathlib import Path

CSS = """
/* layout: one reading column, wide tables scroll inside their own box; bars are drawn to one scale per column */
:root{--bg:#f7f8f6;--fg:#1b211e;--muted:#5f6b65;--line:#dde3df;--bar:#2f6f8f;--bar2:#a65a3a;--ok:#2d7a4b;--bad:#b0403a;--chip:#e9eeeb;
--display:"PT Serif",Georgia,serif;--body:"PT Sans","Helvetica Neue",Arial,sans-serif;--mono:"PT Mono",ui-monospace,Menlo,monospace}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#141816;--fg:#e6ebe8;--muted:#98a39d;--line:#2c3430;--bar:#78b3d0;--bar2:#dd9270;--ok:#6fc392;--bad:#ef8079;--chip:#212824;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#141816;--fg:#e6ebe8;--muted:#98a39d;--line:#2c3430;--bar:#78b3d0;--bar2:#dd9270;--ok:#6fc392;--bad:#ef8079;--chip:#212824;color-scheme:dark}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.55 var(--body)}
main{max-width:1180px;margin:0 auto;padding-block:32px 64px;padding-inline:16px}
h1{font:700 28px/1.2 var(--display);margin:0 0 6px;text-wrap:balance}h2{font:700 19px/1.3 var(--display);margin:36px 0 6px;text-wrap:balance}
.sub{color:var(--muted);margin:0 0 16px;max-width:75ch}.wrap{overflow-x:auto;border-top:1px solid var(--line)}
table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}th,td{padding:7px 10px;border-bottom:1px solid var(--line);text-align:right;vertical-align:top;white-space:nowrap}
td{font-family:var(--mono);font-size:13px}td.l{font-family:var(--body);font-size:14px}
th{font-weight:700;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.05em}td.l,th.l{text-align:left;white-space:normal;min-width:160px}
.bar{display:inline-block;height:8px;background:var(--bar);border-radius:1px;margin-left:6px;vertical-align:middle}.bar.b2{background:var(--bar2)}
.ok{color:var(--ok)}.bad{color:var(--bad)}.muted{color:var(--muted)}.chip{background:var(--chip);border-radius:3px;padding:1px 6px;font-size:12px;font-family:var(--body)}
ul{padding-left:20px;max-width:80ch}li{margin:6px 0}code{font-family:var(--mono);background:var(--chip);padding:0 4px;border-radius:3px}
"""


def esc(x) -> str:
    return html.escape("" if x is None else str(x))


def num(x, fmt="{:.2f}") -> str:
    return "—" if x is None else fmt.format(x)


def grp(n: int) -> str:
    return f"{n:,}".replace(",", "\u202f")


def bar(value, vmax, cls="") -> str:
    if value is None or not vmax:
        return ""
    return f'<span class="bar {cls}" style="width:{max(2, int(80 * value / vmax))}px"></span>'


def asr_table(rows: list[dict]) -> str:
    ok = [r for r in rows if r.get("status") == "ok"]
    wmax = max([r["wer"] for r in ok] or [0])
    cmax = max([r.get("rub_per_hour") or 0 for r in rows] or [0])
    out = ['<div class="wrap"><table><tr><th class="l">Движок</th><th>Время, мин</th><th>× реального</th>'
           '<th>₽ за час</th><th>$ за час</th><th class="l">Основа цены</th><th>WER</th><th>CER</th>'
           '<th>WER без терминов</th><th>Термины верно</th><th>Полнота терминов</th></tr>']
    for r in rows:
        if r.get("status") != "ok":
            out.append(f'<tr><td class="l">{esc(r["id"])}<br><span class="muted">{esc(r.get("error"))}</span></td>'
                       f'<td>—</td><td>—</td><td>{num(r.get("rub_per_hour"), "{:.1f}")}</td><td>{num(r.get("usd_per_hour"), "{:.3f}")}</td>'
                       f'<td class="l muted">{esc(r.get("cost_basis"))}</td><td colspan="5" class="l muted">не прогнан</td></tr>')
            continue
        out.append(
            f'<tr><td class="l">{esc(r["id"])}</td><td>{num(r["wall_s"] / 60, "{:.1f}")}</td><td>{num(r.get("rtf"), "{:.3f}")}</td>'
            f'<td>{num(r.get("rub_per_hour"), "{:.1f}")}{bar(r.get("rub_per_hour"), cmax, "b2")}</td>'
            f'<td>{num(r.get("usd_per_hour"), "{:.3f}")}</td><td class="l muted">{esc(r.get("cost_basis"))}</td>'
            f'<td>{num(r["wer"] * 100, "{:.1f}")}%{bar(r["wer"], wmax)}</td><td>{num(r["cer"] * 100, "{:.1f}")}%</td>'
            f'<td>{num(r["wer_termnorm"] * 100, "{:.1f}")}%</td>'
            f'<td>{num((r.get("term_accuracy") or 0) * 100, "{:.0f}")}% <span class="muted">({r.get("term_canon")}/{(r.get("term_canon") or 0) + (r.get("term_distortions") or 0)})</span></td>'
            f'<td>{num((r.get("term_recall") or 0) * 100, "{:.0f}")}%</td></tr>')
    out.append("</table></div>")
    return "".join(out)


def llm_table(rows: list[dict]) -> str:
    out = ['<div class="wrap"><table><tr><th class="l">Автор конспекта</th><th>Время, мин</th><th>Ходов</th>'
           '<th>Токены вход / кэш / выход</th><th>₽ за час</th><th>$ за час</th><th class="l">Проверки кодом</th>'
           '<th class="l">Судьи (critical / major / minor)</th><th>Конспект</th></tr>']
    for r in rows:
        t = r.get("tokens", {})
        first = r.get("checks_first_failed") or []
        checks = ('<span class="ok">с первого раза</span>' if r.get("checks_ok") and not first else
                  (f'<span class="ok">после {r.get("fix_rounds")} исправл.</span><br><span class="muted">сначала: {esc(", ".join(first))}</span>'
                   if r.get("checks_ok") else f'<span class="bad">не прошли</span><br><span class="muted">{esc(", ".join(r.get("checks_final_failed") or first))}</span>'))
        judges = "<br>".join(
            f'<span class="chip">{esc(j["model"] if j["model"] != "default" else "Claude")}</span> '
            f'<span class="{"ok" if j.get("verdict") == "pass" else "bad"}">{esc(j.get("verdict"))}</span> '
            f'{j.get("critical")} / {j.get("major")} / {j.get("minor")}' for j in r.get("judges", [])) or "—"
        a = r.get("artifacts", {})
        out.append(
            f'<tr><td class="l">{esc(r["author"])}<br><span class="muted">{esc(", ".join(r.get("author_models", [])))}</span></td>'
            f'<td>{num((r.get("author_wall_s") or 0) / 60, "{:.1f}")}</td><td>{esc(r.get("author_turns"))}</td>'
            f'<td>{grp(t.get("input_tokens", 0))} / {grp(t.get("cache_read_input_tokens", 0) + t.get("cache_creation_input_tokens", 0))} / {grp(t.get("output_tokens", 0))}</td>'
            f'<td>{num(r.get("rub_per_hour"), "{:.1f}")}</td><td>{num(r.get("usd_per_hour"), "{:.3f}")}</td>'
            f'<td class="l">{checks}</td><td class="l">{judges}</td>'
            f'<td>{esc(a.get("lesson_kb"))} КБ, {esc(a.get("sections"))} разд., {esc(a.get("chapters"))} глав</td></tr>')
    out.append("</table></div>")
    return "".join(out).replace(",", " ").replace("  ", ", ")


def pairwise_table(pw: dict) -> str:
    if not pw:
        return ""
    ids = list(pw)
    out = ['<h2>Движки друг против друга</h2><p class="sub">WER, если текст движка в столбце считать эталоном для движка в строке. '
           'Не зависит от эталонного транскрипта.</p><div class="wrap"><table><tr><th class="l"></th>']
    out += [f"<th>{esc(i)}</th>" for i in ids] + ["</tr>"]
    for a in ids:
        out.append(f'<tr><td class="l">{esc(a)}</td>')
        out += [f"<td>{'—' if a == b else num(pw[a].get(b, 0) * 100, '{:.1f}') + '%'}</td>" for b in ids]
        out.append("</tr>")
    out.append("</table></div>")
    return "".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--results", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--title", default="Бенчмарк пайплайна")
    ap.add_argument("--notes", type=Path)
    ap.add_argument("--fragment", action="store_true", help="no doctype/html/body wrapper (for hosts that add their own)")
    args = ap.parse_args()
    res = json.loads(args.results.read_text(encoding="utf-8"))
    audio_min = (res.get("audio_s") or 0) / 60
    fx = res.get("fx", {})
    notes = ""
    if args.notes and args.notes.exists():
        items = [l[2:].strip() for l in args.notes.read_text(encoding="utf-8").splitlines() if l.startswith("- ")]
        notes = "<h2>Как читать</h2><ul>" + "".join(f"<li>{esc(i)}</li>" for i in items) + "</ul>"
    fonts = ('<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=PT+Mono&family=PT+Sans:wght@400;700'
             '&family=PT+Serif:wght@700&display=swap">')
    head = f"<title>{esc(args.title)}</title>{fonts}<style>{CSS}</style>"
    body = f"""<main>
<h1>{esc(args.title)}</h1>
<p class="sub">Задача <code>{esc(res.get("task"))}</code> · запись {audio_min:.0f} мин · цены на {esc(res.get("prices_checked_at"))},
курс ЦБ {esc(fx.get("USD_RUB"))} ₽ за $ ({esc(fx.get("date"))}) · собрано {esc(res.get("generated_at"))}</p>
<h2>Распознавание: звук в текст</h2>
<p class="sub">Цена и время приведены к часу записи. WER и CER считаются против эталонного транскрипта ({esc(res.get("reference", {}).get("words"))} слов); меньше лучше.</p>
{asr_table(res.get("asr", []))}
<h2>Разбор: транскрипт в конспект</h2>
<p class="sub">Один и тот же транскрипт, один харнес (Claude Code, headless), меняется только модель. Судья всегда другой модели, чем автор.</p>
{llm_table(res.get("llm", []))}
{pairwise_table(res.get("asr_pairwise_wer", {}))}
{notes}
</main>
"""
    page = head + body if args.fragment else (
        '<!doctype html><html lang="ru"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">' + head + "</head><body>" + body + "</body></html>")
    args.out.write_text(page, encoding="utf-8")
    print(f"report: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
