# Manager Skill


Manager uses your local Manager Config for repositories and boards; the distributed skill contains no personal workspace logs.

![Skill illustration](assets/illustration.png)

Bidirectional bridge between the current session and GitHub Issues. Part of the Personal Corp framework.

## What it does

One skill, two modes:

- **Write mode (sync)** — at end of session: reads what was done, finds matching issues, updates bodies / adds labels, creates new ones only when nothing matches.
- **Read mode (query)** — anytime: «what about track X?», «is there an issue for Y?» → cross-repo search, condensed table of matches with labels, status, last activity.

GitHub Issues become your single source of truth for tasks; a GitHub Project board is the source of truth for what's active. The skill enforces a set of invariants per issue (parent epic via Sub-issues API, W-label, Project placement, work-record comment on real work) and a predictable no-prefix title formula.

Manager is the issue bridge in the operating cycle. `weekly-retro` reviews the past week, `weekly-planning` curates the week/day plans, and `manager` keeps GitHub issues, Projects, labels, parents, comments, and touched plan rows consistent during actual work.

## Why you'd want it

Without this bridge:
- End of session — you forget to record progress → tasks slip through.
- Start of session — you don't know what's open for a track → manual digging in the issue list.
- You create duplicates because you don't remember what already exists.
- Orphan issues without parent epic — a month later you can't tell what belongs to which track.

The skill closes all four gaps: pre-flight read of your priorities index, cross-repo search, parent-epic verification, human-readable plan + report.

## When to use

**Write mode** — at the end of a working session:
- Say "sync session" / `/manager` / "update issues for what I did"
- Skill infers artifacts from session context, shows the plan, executes.

**Read mode** — at the start or middle of a session:
- "What about track X?"
- "Status of Y?"
- "Is there an issue for Z?"

## What you get

**Write mode:** compact plan before execution + report after. Each line — what was updated, where, with which parent epic, which labels. If a track has no epic — the skill flags it in the plan, never silently creates an orphan.

**Read mode:** table of open issues for the track, with human-readable titles (no bare numbers), parent epic, W-label, last activity, status. Plus separate sections:
- Not covered (gaps) — what's mentioned in the index but has no issue yet
- Track health check — any issues missing parent, any without W-label
- Drift in index / epic state — where the index references CLOSED issues, where an epic is "stale-open" (100% sub-issues done but state=open)
- False positives — what was filtered and why

## Installation

Install the skill into your HQ, the folder that holds the HQ rules file. There is one copy of the skill, and both tools see it:

- `<hq>/.agents/skills/manager`: the skill folder itself, Codex reads it;
- `<hq>/.claude/skills`: a symbolic link to `../.agents/skills`, Claude Code sees the same skill through it.

A symbolic link works like a shortcut: the folder lives in one place and opens from two.

The easiest way is to hand the install to your agent, as in the lesson. Give it a link to the `skills/manager` folder in this repository and ask:

> Install it into the HQ, in .agents/skills, so that both Claude Code and Codex see it, via a symbolic link. Don't copy the files.

How to check:

- the file `<hq>/.agents/skills/manager/SKILL.md` is in place;
- `<hq>/.claude/skills` is a link, not a regular folder: `ls -l .claude` in the HQ folder shows `skills -> ../.agents/skills`;
- the file `.claude/skills/manager/SKILL.md` opens through the link.

The agent never starts the skill on its own. In Claude Code you call it with `/manager`: the line `disable-model-invocation: true` in `SKILL.md` sets this. In Codex you call it by writing `$manager` in your message: the line `allow_implicit_invocation: false` in `agents/openai.yaml` sets this.

To install the skill as a plugin, follow the root README of this repository.

## Setup

Add a `## Manager Config` section to your project's `AGENTS.md` (preferred) or `CLAUDE.md` (compatibility). If there is no agent config yet, run `corp-doctor` first.

| Config | Purpose |
|--------|---------|
| GitHub owner | Your username or org for cross-repo issue search |
| Repos to scan | List of repos to search for issues |
| Tasks index file (optional) | Path to your current-week priorities file (e.g. `tasks.md`) — read FIRST before any `gh search` |
| Tasks directory (optional) | Path to `tasks/WNN/YYYY-MM-DD.md` day plans created by `weekly-planning` |
| Domain → repo routing | Map task domains to repos (which type of issue lands where) |
| GitHub Projects integration | Your weekly Project board + status field/option — Project placement is an invariant |
| W-label convention (optional) | Whether to use weekly labels (`W18`, `W19`...) |
| Standing write authorization | `ask-each-time` (default) or `execute-after-plan` |
| CRM integration (optional) | Path to your CRM and pointer format used in issue bodies |

Full config template — in `SKILL.md`, section «Настройка: Manager Config».

Without config the skill still works, but less targeted: it'll ask for owner / repos on first run.

## How to invoke

**Write mode (after a session):**

> "sync session"

or

> `/manager`

or

> "update issues for what I did today, and create new ones where needed"

The skill:
1. Silent pre-flight — reads priorities index, checks `git status` of relevant repos
2. Shows a compact plan (5-15 lines): what to update / create / attach to which epic
3. Per configured authorization — executes or asks for confirmation
4. If it closes an issue, removes that issue from active day/week plans or replaces it with the next open child
5. Returns a short report — Done / Skipped / Plan cleanup

**Working mode:** by default manager orchestrates and critiques at low effort; a `/harness` header in the arguments overrides it (see [harness](../harness/)).

**Read mode (status query):**

> "what about track X?"

or

> "any issues for Y?"

or

> "status of track Z"

The skill:
1. Cross-repo search with multiple keys (track name, handle, slug)
2. Filters false positives, surfaces them in a separate section
3. Resolves the track's parent epic, checks sub_issues progress
4. Cross-references your priorities index
5. Returns the table + health check + drift signals

## Iron invariants

The skill enforces invariants for every issue it touches — the base three always, plus the Project and work-record invariants for active / current-week issues:

1. **W-label** (if convention enabled in config) — current or future week. Label missing in the repo? It creates it.
2. **Parent epic** — exactly one parent via GitHub Sub-issues API. If no epic exists for the track — surfaces this in the plan, never creates an orphan.
3. **Track differentiation via title + epic membership** — no track-labels (`<track-slug>`, `<client>-deal`). The track is recognized by title text and which epic the issue belongs to.
4. **Project placement** — an active issue must be on its domain Project board and the global weekly Project; a W-label without Project placement is flagged as drift.
5. **Project-visible parent** — for an active child, the visible root epic must itself be in the Project view with a non-empty status lane (not just an API `parent_issue_url`).
6. **Work-record comment** — when real work happened in the session, a mandatory timeline comment summarizing it + commit links. A status/label/Project change does not replace it.

## See also

- [SKILL.md](SKILL.md) — the "where tasks live" fork, level 1 (tasks in files), config and invariants; level 2 details live in [references/](references/): write/read mode algorithms, parent epic rules, W-label rules, title convention, output templates
- [README.ru.md](README.ru.md) — Russian version
- `corp-doctor` — creates or repairs the manager config
- `weekly-planning` — curates the week index and day plans
- `weekly-retro` — reviews the closing week and produces evidence/backlog
