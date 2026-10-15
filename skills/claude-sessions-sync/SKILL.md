---
name: claude-sessions-sync
description: Sync Claude Code session records between two Anthropic accounts in the Claude desktop app on macOS. Use when switching accounts (for example when one hits usage limits) and old sessions disappear from the picker, or to mirror records before/after a switch.
---

# Claude sessions sync (between desktop-app accounts)

How it works (verified 2026-10-01…07, Claude Code 2.1.286, macOS):

- Session records live in `~/Library/Application Support/Claude/claude-code-sessions/<accountUuid>/<orgUuid>/local_*.json`. The second path level is the **organization** UUID; the app lists only the current account+org pair, which is why switching accounts hides the other side's sessions.
- Transcripts live in `~/.claude/projects/` and are shared across all accounts — never touch them. A record points at its transcript through the `cliSessionId` field.
- Active account: `~/Library/Application Support/Claude/config.json` → `lastKnownAccountUuid`. The active org folder is the one holding the freshest record (mtime).
- Account switches may leave empty race folders `<old-account>/<new-org>` — ignore them.

## Procedure

1. The app must be fully closed: `pgrep -f "/Applications/Claude.app/Contents/MacOS"` is empty; otherwise `osascript -e 'quit app "Claude"'` and wait. Copying while the app is alive can be rolled back by its in-memory list cache (`LSS-cached-sessions`) and record rewrites.
2. Identify both working folders: under each account UUID take the subfolder with the most `local_*.json` records (or the freshest one).
3. Run a bidirectional newest-wins sync of `local_*.json` — the script below. A one-way copy leaves drift: sessions you continued on one side go stale on the other.
4. Merge `archived-sessions.idx`: union the `archived` lists of both folders, write the same file into both.
5. Copy missing `deleted_*` markers in both directions, otherwise deleted sessions resurrect in the picker.
6. Do NOT sync `scheduled-tasks.json` or `backlog/` — each account+org pair keeps its own.
7. Reopen the app, switch the login to the target account, verify the record count in the picker.

## Script (edit FIRST/SECOND, app closed)

```python
import os, json, shutil

SESS = os.path.expanduser("~/Library/Application Support/Claude/claude-code-sessions")
FIRST  = f"{SESS}/<account-uuid-1>/<org-uuid-1>"
SECOND = f"{SESS}/<account-uuid-2>/<org-uuid-2>"

def records(d):
    return {f: os.path.getmtime(os.path.join(d, f))
            for f in os.listdir(d) if f.startswith("local_") and f.endswith(".json")}

f_rec, s_rec = records(FIRST), records(SECOND)
for f, m in s_rec.items():
    if f not in f_rec or m > f_rec[f]:
        shutil.copy2(os.path.join(SECOND, f), os.path.join(FIRST, f))
for f, m in f_rec.items():
    if f not in s_rec or m > s_rec[f]:
        shutil.copy2(os.path.join(FIRST, f), os.path.join(SECOND, f))

arch = set()
for d in (FIRST, SECOND):
    p = os.path.join(d, "archived-sessions.idx")
    if os.path.exists(p):
        try: arch |= set(json.load(open(p)).get("archived", []))
        except Exception: pass
idx = {"v": 1, "archived": sorted(arch)}
for d in (FIRST, SECOND):
    json.dump(idx, open(os.path.join(d, "archived-sessions.idx"), "w"))

for a, b in ((FIRST, SECOND), (SECOND, FIRST)):
    for f in os.listdir(a):
        if f.startswith("deleted_") and not os.path.exists(os.path.join(b, f)):
            shutil.copy2(os.path.join(a, f), os.path.join(b, f))
```

## Gotchas

- Claude Code cleans old transcripts (about a month back by default): such records return to the picker but open empty. There is nothing to restore from.
- Copies drift apart while you work on one account — rerun the sync on every switch.
- Continuing a moved session sends its transcript to the current account (privacy note for personal-vs-work orgs).
- There is no official cross-account migration (anthropics/claude-code#48511 closed as not planned); terminal `claude --resume <id>` sees all local sessions under any login.

Background write-up: https://sereja.tech/blog/claude-code-sessions-between-accounts/
