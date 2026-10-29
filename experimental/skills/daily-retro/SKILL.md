---
name: daily-retro
description: >-
  Experimental. Daily retro from your agents' own logs: reads today's Claude Code
  and Codex sessions on this machine, groups them by project, adds git state
  (commits, uncommitted files, unpushed commits) and lists the tails — what was
  done and what was left open. Then closes the tails the way the manager skill
  does: issue comment, commit or a conscious "drop". Runs by itself every evening
  as an automation. Triggers on "/daily-retro", "дневное ретро", "что сегодня
  сделали агенты", "подбей хвосты", "daily retro".
---

# Daily retro (experimental)

Part of the Personal Corp framework. Weekly retro answers "what did the week give". Daily retro answers a smaller question every evening: what did my agents do today, and what did they leave half-done. You do not remember twenty sessions in five repos; the logs do.

Experimental means: the shape may change, it is not in the plugin's active skill list, you copy it by hand (see README).

## What it reads

Only local files, nothing leaves the machine:

| Harness | Logs |
|---|---|
| Claude Code (CLI and desktop) | `~/.claude/projects/<project>/<session>.jsonl` |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` |

A harness that is not installed is skipped. Another harness: add a reader to `scripts/collect.py`, same output shape.

## Steps

1. **Collect.** `python3 <skill>/scripts/collect.py` (today) or `--date YYYY-MM-DD`. It prints a markdown digest: per project the sessions (time, harness, title or first prompt, last reply), commits of the day and **tails**: uncommitted files, unpushed commits, a session that ended on your message without a reply, a session that ended with a question to you. Secrets that look like tokens are masked.
2. **Read, do not retell.** Turn the digest into the retro file `retro/daily/YYYY-MM-DD.md` in your HQ (create the folder once):
   - **Done** — one line per result that exists outside the chat: a commit, a merged PR, a file, a sent message. No result outside the chat, no line.
   - **Tails** — every tail from the digest plus the promises you find in last replies ("will do after…", "waits for your word"). Each tail gets one owner action: *commit*, *push*, *answer the session*, *issue comment*, *drop* (with one reason).
   - **Tomorrow** — at most three tails that block something else.
3. **Close tails like the manager.** For a tail that belongs to a task: find its issue and leave a work-record comment (what was done, what is left, link to commit). If the manager skill is installed, use it: it owns the issue contract. Commit and push only your own paths; somebody else's uncommitted edits stay as a tail with the owner's name, you do not revert them.
4. **Report.** Three lines to the owner: how many sessions and projects, what got done, the three tails for tomorrow. In the automation run the report goes where the owner reads (Telegram, a note, the HQ dashboard) — whatever the HQ already uses.

## Automation

The point is that nobody has to remember to run it. Pick one, templates in `automation/`:

- **Claude Code desktop:** Scheduled tasks → new task, every day at 21:30, prompt `/daily-retro`, folder = your HQ.
- **macOS launchd:** `automation/daily-retro.plist` runs `claude -p "/daily-retro"` in the HQ folder at 21:30. Load it once: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/corp.daily-retro.plist`.
- **Linux systemd:** `automation/daily-retro.service` + `.timer`.

A run that finds zero sessions writes one line "no agent sessions today" and stops.

## Boundaries

- Reads logs, does not edit them. Does not send the raw digest anywhere: last replies may hold private context; the retro file is written in your own words.
- Does not merge, deploy, pay or post on its own. Such tails go to "Tomorrow" as the owner's decisions.
- The digest is a pointer, not proof. Before writing "done" check the commit, the PR or the file.
