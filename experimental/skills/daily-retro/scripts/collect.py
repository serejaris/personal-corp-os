#!/usr/bin/env python3
"""Daily retro collector: what your agents did today and what they left open.

Reads the local session logs of installed agent harnesses (Claude Code, Codex),
groups sessions by project, and adds git state of every touched repository:
commits of the day, uncommitted files, unpushed commits. Prints markdown.

Standard library only. Nothing leaves the machine.

    python3 collect.py                 # today, local time
    python3 collect.py --date 2026-10-29
    python3 collect.py --json          # machine-readable
"""
import argparse
import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys

HOME = pathlib.Path.home()
CLAUDE_DIR = HOME / ".claude" / "projects"
CODEX_DIR = HOME / ".codex" / "sessions"
SECRET = re.compile(r"(sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|xox[abp]-[A-Za-z0-9-]{10,}|\d{8,10}:[A-Za-z0-9_-]{30,}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,})")
NOISE = re.compile(r"<(system-reminder|command-[a-z-]+|local-command-[a-z-]+|task-notification)>.*?</\1>", re.S)
TEXT_LIMIT = 220


def clean(text):
    """One line, no harness noise, no secrets, bounded length."""
    text = NOISE.sub(" ", text or "")
    text = SECRET.sub("[secret]", text)
    text = " ".join(text.split())
    return text if len(text) <= TEXT_LIMIT else text[: TEXT_LIMIT - 1] + "…"


def day_bounds(day):
    start = dt.datetime.combine(day, dt.time.min).astimezone()
    return start, start + dt.timedelta(days=1)


def parse_ts(value):
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") in ("text", "input_text", "output_text"))
    return ""


def new_session(harness, path):
    return {"harness": harness, "file": str(path), "cwd": None, "title": None,
            "first_prompt": None, "last_reply": None, "last_role": None,
            "prompts": 0, "start": None, "end": None}


def touch(session, ts):
    session["start"] = min(filter(None, [session["start"], ts]), default=ts)
    session["end"] = max(filter(None, [session["end"], ts]), default=ts)


def read_claude(path, lo, hi):
    s = new_session("claude-code", path)
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        kind = d.get("type")
        if kind == "custom-title":
            s["title"] = clean(d.get("customTitle") or d.get("title"))
            continue
        if kind not in ("user", "assistant"):
            continue
        ts = parse_ts(d.get("timestamp"))
        if not ts or not (lo <= ts < hi):
            continue
        s["cwd"] = s["cwd"] or d.get("cwd")
        msg = d.get("message") or {}
        text = clean(text_of(msg.get("content")))
        if not text:
            continue
        touch(s, ts)
        s["last_role"] = kind
        if kind == "user":
            s["prompts"] += 1
            s["first_prompt"] = s["first_prompt"] or text
        else:
            s["last_reply"] = text
    return s


def read_codex(path, lo, hi):
    s = new_session("codex", path)
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        p = d.get("payload") or {}
        if d.get("type") in ("session_meta", "turn_context"):
            s["cwd"] = s["cwd"] or p.get("cwd")
            continue
        ts = parse_ts(d.get("timestamp"))
        if not ts or not (lo <= ts < hi):
            continue
        if d.get("type") == "response_item" and p.get("type") == "message" and p.get("role") in ("user", "assistant"):
            text = clean(text_of(p.get("content")))
            if not text or text.startswith(("## Memory", "<environment_context", "# AGENTS.md")):
                continue
            touch(s, ts)
            s["last_role"] = p["role"]
            if p["role"] == "user":
                s["prompts"] += 1
                s["first_prompt"] = s["first_prompt"] or text
            else:
                s["last_reply"] = text
        elif d.get("type") == "event_msg" and p.get("type") == "task_complete" and p.get("last_agent_message"):
            touch(s, ts)
            s["last_reply"] = clean(p["last_agent_message"])
            s["last_role"] = "assistant"
    return s


def candidate_files(root, pattern, lo):
    if not root.exists():
        return []
    since = lo.timestamp() - 3600
    return [p for p in root.glob(pattern) if p.stat().st_mtime >= since]


def sessions_for(day):
    lo, hi = day_bounds(day)
    found = []
    for path in candidate_files(CLAUDE_DIR, "*/*.jsonl", lo):
        found.append(read_claude(path, lo, hi))
    for path in candidate_files(CODEX_DIR, "**/rollout-*.jsonl", lo):
        found.append(read_codex(path, lo, hi))
    return [s for s in found if s["prompts"]]


def git(cwd, *args):
    r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def repo_state(root, day):
    lo, hi = day_bounds(day)
    commits = git(root, "log", "--all", f"--since={lo.isoformat()}", f"--until={hi.isoformat()}", "--format=%h %s")
    dirty = git(root, "status", "--porcelain")
    unpushed = git(root, "log", "@{u}..", "--format=%h %s")
    return {"commits": [clean(c) for c in commits.splitlines()],
            "dirty": len(dirty.splitlines()),
            "unpushed": [clean(c) for c in unpushed.splitlines()],
            "branch": git(root, "branch", "--show-current")}


def project_of(cwd):
    if not cwd or not os.path.isdir(cwd):
        return cwd or "(unknown)", None
    root = git(cwd, "rev-parse", "--show-toplevel")
    return (root or cwd), (root or None)


def collect(day):
    projects = {}
    for s in sessions_for(day):
        name, root = project_of(s["cwd"])
        p = projects.setdefault(name, {"root": root, "sessions": []})
        p["sessions"].append(s)
    for p in projects.values():
        p["sessions"].sort(key=lambda s: s["start"])
        p["git"] = repo_state(p["root"], day) if p["root"] else None
    return projects


def tails(p):
    """Open ends: things a human must close or consciously drop."""
    out = []
    g = p["git"]
    if g and g["dirty"]:
        out.append(f"{g['dirty']} uncommitted file(s) on `{g['branch']}`")
    if g and g["unpushed"]:
        out.append(f"{len(g['unpushed'])} unpushed commit(s) on `{g['branch']}`")
    for s in p["sessions"]:
        if s["last_role"] == "user":
            out.append(f"session «{label(s)}» ended on your message, no reply")
        elif s["last_reply"] and s["last_reply"].rstrip().endswith("?"):
            out.append(f"session «{label(s)}» ended with a question to you")
    return out


def label(s):
    return s["title"] or s["first_prompt"] or "untitled"


def hhmm(ts):
    return ts.astimezone().strftime("%H:%M") if ts else "?"


def render(day, projects):
    lines = [f"# Daily retro {day.isoformat()}", ""]
    total = sum(len(p["sessions"]) for p in projects.values())
    lines.append(f"{total} session(s) in {len(projects)} project(s).")
    for name, p in sorted(projects.items(), key=lambda kv: -len(kv[1]["sessions"])):
        lines += ["", f"## {pathlib.Path(name).name}", f"`{name}`", ""]
        for s in p["sessions"]:
            lines.append(f"- {hhmm(s['start'])}–{hhmm(s['end'])} {s['harness']}, {s['prompts']} prompt(s): **{label(s)}**")
            if s["last_reply"]:
                lines.append(f"  - last reply: {s['last_reply']}")
        g = p["git"]
        if g and g["commits"]:
            lines.append(f"- commits today: {len(g['commits'])}")
            lines += [f"  - {c}" for c in g["commits"][:10]]
        open_ends = tails(p)
        if open_ends:
            lines.append("- **tails:**")
            lines += [f"  - {t}" for t in open_ends]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--date", type=dt.date.fromisoformat, default=dt.date.today())
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    projects = collect(args.date)
    if args.json:
        for p in projects.values():
            p["tails"] = tails(p)
        print(json.dumps(projects, default=str, ensure_ascii=False, indent=2))
    else:
        sys.stdout.write(render(args.date, projects))


if __name__ == "__main__":
    main()
