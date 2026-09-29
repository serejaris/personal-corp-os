# corp-new

Creates a new department of your HQ: a folder with a rules file and a skills folder, a private GitHub repository, and a two-way link with the HQ in the rules. If there is no HQ yet, it first installs one from [agent-starter](https://github.com/serejaris/agent-starter) and uses its `hq` skill.

```
/corp-new
```

Or ask: "create a department", "new department", "add a department for sales".

- Finds the HQ folder (the one with `me.md` or `stack/harness.md`); installs it from agent-starter if missing.
- Picks a `corp-<domain>` name and checks that the folder, repository, and map entry do not already exist.
- Sets up the skeleton: `AGENTS.md` with empty places for you to fill, `CLAUDE.md` and `.claude/skills` symlinks, `git init`.
- Creates a private repository through `gh` and links the HQ and the department in each other's rules.
- Reports a table of steps with ✓/✗ and what to fill in next.

It does not write department rules for you and does not touch other files. The skill text is in Russian.

Русская версия: [README.ru.md](README.ru.md)
