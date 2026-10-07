# corp-new

[![en](https://img.shields.io/badge/lang-en-blue.svg)](README.md)
[![ru](https://img.shields.io/badge/lang-ru-green.svg)](README.ru.md)

Create a department when you regularly do the same kind of work and keep explaining its rules to your agent. `corp-new` sets up the folder and links it to your HQ: from HQ, the agent sees the system map; from the department, it reads the rules for that area.

![Skill diagram](assets/illustration-en.svg)

A department is a folder next to your HQ with its own rules, skills and tasks, for example `corp-sales`. It needs no GitHub: the department lives in a local folder.

```
/corp-new
```

Or ask: "create a department", "new department", "add a department for sales".

- Finds the HQ folder (the one with `me.md` or `stack/harness.md`). If there is no HQ, installs one from [agent-starter](https://github.com/serejaris/agent-starter) and runs its `hq` skill.
- Picks a `corp-<domain>` name and checks that the folder and the entry in the department map do not already exist.
- Sets up the skeleton: `AGENTS.md` with empty places for you to fill, a skills folder and a `tasks/` folder, `CLAUDE.md` and `.claude/skills` symlinks, `git init`.
- For a research department, offers a ready template: eight rules, an `INDEX.md` report catalog a `tags.md` tag dictionary and the department skill `corp-research`. Templates live in [`templates/`](templates/).
- Explains how to add a skill to the department: paths and invocation for Claude Code and Codex, links for macOS, Linux and Windows.
- Links the HQ and the department in each other's rules. Creates a private GitHub repository through `gh` only if you ask.
- Reports a table of steps with ✓/✗ and what to fill in next: the department's purpose and its canon, which file is responsible for what. You fill them in yourself or with the agent through `/mp-grill-me`.

It does not write department rules for you, except for the ready templates, does not touch other files and does not discard uncommitted work. The skill text is in Russian.
