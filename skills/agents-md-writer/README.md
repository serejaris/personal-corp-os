# AGENTS.md Writer

![Skill illustration](assets/illustration.png)

Writes and trims an agent rules file, `AGENTS.md`, for a repository, a headquarters folder, or a department.

## Problem

Rules files grow: procedures, decision history and subfolder rules pile up. A second file, `CLAUDE.md`, appears next to it, and Claude Code and Codex end up reading different rules. Codex reads the `AGENTS.md` chain with a 32 KB byte budget and silently truncates whatever does not fit. Russian text uses that budget about 1.5 times faster than English.

## What it does

- One rules file per folder: `AGENTS.md`. Merges and removes `CLAUDE.md` and `.claude/rules/` after confirmation.
- Every line is a route, a boundary, or a standing behavior. Procedures go to skills, reference material to `docs/`, history to git.
- Size: start at 40–60 lines, ceiling 200 lines and 32 KB for the whole chain from the repo root.
- Subfolder rules go to a nested `AGENTS.md` with a route line in the root.
- A department's first line links to the headquarters, which holds the global rules.

## Install

```bash
ln -s "$(pwd)/skills/agents-md-writer" ~/.claude/skills/agents-md-writer
```

Invoke with `/agents-md-writer`.

## Formerly

The skill was called `claude-md-writer` and built `CLAUDE.md` with `.claude/rules/`. Since Claude Code now reads `AGENTS.md` natively, it was rewritten around one file for every harness.
