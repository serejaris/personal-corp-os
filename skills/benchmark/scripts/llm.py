#!/usr/bin/env python3
"""Run the LLM variants of a benchmark task through the task's pipeline adapter.

    python3 llm.py --task task.json --out runs/<name> [--only id1,id2] [--force]

The skill does not know your pipeline. The task names an adapter script
(task["llm"]["adapter"]) that runs one variant end to end:

    python3 <adapter> --task task.json --variant variant.json --out runs/<name>/llm/<id> --stage all|author|judge

and writes runs/<name>/llm/<id>/result.json. `--stage author` runs the author step and code checks,
`--stage judge` adds judges to an existing result (useful when the judge's key lives on another
machine); `--stage all` does both. Result format:

    {"steps":  [{"name", "role": "author|fixer|judge", "provider", "model", "wall_s",
                 "usage": {...}, "model_usage": {...}, "cost_usd_reported", "ok"}],
     "checks_first": [{"name", "ok"}],   # code checks right after the author step
     "checks_final": [{"name", "ok"}],   # after the fix rounds
     "fix_rounds": 0, "checks_ok": true,
     "judges": [{"provider", "model", "verdict", "critical", "major", "minor", "summary"}],
     "artifacts": {"...": "sizes, counts"}}

Adapters use claude_step.run_step() so every model runs in the same harness.
Rule: a judge is never the author's model (the script refuses such a variant).
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import Meter, load_task, read_json, task_path, utc_now, write_json  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--task", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--only", help="comma-separated variant ids")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--stage", choices=["all", "author", "judge"], default="all",
                    help="author: author+checks only; judge: judges on an existing author run (other machine/key)")
    args = ap.parse_args()

    task = load_task(args.task)
    llm = task["llm"]
    adapter = task_path(task, llm["adapter"])
    only = set(args.only.split(",")) if args.only else None
    for v in llm["variants"]:
        if (only and v["id"] not in only) or v.get("skip"):
            continue
        author = (v["author"]["provider"], v["author"]["model"])
        if any((j["provider"], j["model"]) == author for j in v.get("judges", [])):
            print(f"{v['id']}: judge equals author model, refusing", file=sys.stderr)
            return 2
        out = args.out / "llm" / v["id"]
        meta_path = out / ("meta-judge.json" if args.stage == "judge" else "meta.json")
        if meta_path.exists() and read_json(meta_path).get("status") == "ok" and not args.force:
            print(f"{v['id']}: already ok, skip")
            continue
        out.mkdir(parents=True, exist_ok=True)
        write_json(out / "variant.json", v)
        meta = {"id": v["id"], "author": v["author"], "judges": v.get("judges", []), "started_at": utc_now()}
        print(f"{v['id']}: start", flush=True)
        with Meter() as m:
            p = subprocess.run([args.python, str(adapter), "--task", str(args.task), "--variant", str(out / "variant.json"),
                                "--out", str(out), "--stage", args.stage], capture_output=True, text=True)
        (out / f"adapter-{args.stage}.log").write_text(p.stdout + "\n--- stderr ---\n" + p.stderr[-8000:], encoding="utf-8")
        ok = p.returncode == 0 and (out / "result.json").exists()
        meta.update(status="ok" if ok else "error", wall_s=m.wall_s, exit=p.returncode, finished_at=utc_now(),
                    error=None if ok else (p.stderr or p.stdout)[-400:])
        write_json(meta_path, meta)
        print(f"{v['id']}: {meta['status']} {m.wall_s}s", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
