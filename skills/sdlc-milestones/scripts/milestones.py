#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ARTIFACTS = [
    (1, "Plan", "intent.md", "владелец задачи принимает intent.md"),
    (2, "Design", "spec.md", "владелец задачи решает спорные места spec.md"),
    (3, "Build", "plan.md", "планировщик-лид сверяет plan.md, высокий риск — владелец"),
]


def git(repo, *args):
    out = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else ""


def commits_oldest_first(repo, path):
    log = git(repo, "log", "--follow", "--reverse", "--format=%h|%cI|%an", "--", str(path))
    return [tuple(line.split("|", 2)) for line in log.splitlines() if line]


def pushed(repo, sha):
    return bool(git(repo, "branch", "-r", "--contains", sha))


def hours(a, b):
    delta = datetime.fromisoformat(b) - datetime.fromisoformat(a)
    return f"{delta.total_seconds() / 3600:.1f} ч"


def pr_state(ref):
    repo, num = ref.split("#")
    out = subprocess.run(
        ["gh", "pr", "view", num, "--repo", repo, "--json", "state,mergedAt,url"],
        capture_output=True, text=True,
    )
    return json.loads(out.stdout) if out.returncode == 0 else None


def main():
    ap = argparse.ArgumentParser(
        description="Статус вех AI-native SDLC по git-истории папки intent/<дата>-<slug>/.",
    )
    ap.add_argument("folder")
    ap.add_argument("--pr", help="owner/repo#N")
    args = ap.parse_args()
    if args.pr and (args.pr.count("#") != 1 or "/" not in args.pr.split("#")[0]):
        sys.exit(f"--pr ждёт owner/repo#N, получено {args.pr!r}")

    folder = Path(args.folder).resolve()
    if not folder.is_dir():
        sys.exit(f"нет папки {folder}")
    repo = git(folder, "rev-parse", "--show-toplevel")
    if not repo:
        sys.exit(f"{folder} не в git-репо")

    first, first_sha = {}, {}
    next_gate = None
    for num, stage, name, gate in ARTIFACTS:
        path = folder / name
        hist = commits_oldest_first(repo, path) if path.exists() else []
        if not hist:
            status = "нет файла" if not path.exists() else "не закоммичен"
            print(f"✗ {num} {stage:<8} {name:<10} {status}")
            next_gate = next_gate or f"веха {num}: {name} → {gate}"
            continue
        sha0, t0, author = hist[0]
        sha1, t1, _ = hist[-1]
        first[name] = t0
        first_sha[name] = sha0
        mark = "✓" if pushed(repo, sha1) else "…"
        tail = "" if mark == "✓" else "  (не запушен)"
        print(f"{mark} {num} {stage:<8} {name:<10} {sha0} {t0[:16]} {author}; правок {len(hist)}, последняя {sha1}{tail}")
        if mark != "✓":
            next_gate = next_gate or f"веха {num}: push {name}"

    merged_at = None
    if args.pr:
        pr = pr_state(args.pr)
        if pr is None:
            print(f"? 4-5 PR      {args.pr} не прочитан через gh")
        else:
            merged_at = pr.get("mergedAt")
            mark = "✓" if merged_at else "…"
            print(f"{mark} 4-5 PR      {pr['state']} {merged_at or ''} {pr['url']}")
            if not merged_at:
                next_gate = next_gate or "вехи 4-5: вывод проверки в PR, одобрение ревьюера, вливает владелец"
    else:
        next_gate = next_gate or "вехи 4-5: открыть PR и передать --pr"

    print()
    print("Показатели:")
    if "intent.md" in first and "spec.md" in first:
        print(f"  intent → spec: {hours(first['intent.md'], first['spec.md'])}")
    if "spec.md" in first and "plan.md" in first:
        print(f"  spec → plan:   {hours(first['spec.md'], first['plan.md'])}")
        later = git(repo, "rev-list", "--count", f"{first_sha['plan.md']}..HEAD", "--", str(folder / "spec.md"))
        print(f"  правок spec.md после plan.md: {later or 0}")
    if "plan.md" in first and merged_at:
        print(f"  plan → мерж:   {hours(first['plan.md'], merged_at.replace('Z', '+00:00'))}")

    print()
    print(f"Следующие ворота: {next_gate or 'все вехи пройдены; инцидент открывает новый intent.md'}")


if __name__ == "__main__":
    main()
