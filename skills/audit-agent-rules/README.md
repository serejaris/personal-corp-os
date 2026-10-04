# Audit Agent Rules

Checks the agent rules in your folder and tells you what to improve. Works with Claude Code, Codex, Cursor and any agent that reads `AGENTS.md`.

What it checks, by four measures:

1. **Every line is a route, a boundary or a standing behavior.** Step-by-step procedures move to a skill or `docs/`, decision history stays in git, reference material goes to `docs/`, a rule for one subfolder goes to that subfolder's `AGENTS.md`.
2. **A file stays under 200 lines.** Codex reads the whole `AGENTS.md` chain within 32 KiB of UTF-8 bytes and cuts the rest; Cyrillic letters take 2 bytes each.
3. **`AGENTS.md` is a navigator.** Details live in their own files and skills; every nested `AGENTS.md` has a route from the root file.
4. **A skill description answers "when do I use this".** It says what the skill does and when, stays short and does not overlap with other skills. The skill counts the total size of all descriptions: Codex limits the start-up skill list to 2% of the context window (8,000 characters when the window is unknown).

You get a report table: where, what is wrong, which measure, what to do. Then the agent asks "rewrite?" and changes nothing until you say yes. After the edits it measures again and asks you to check a rule in a fresh session.

The bundled `scripts/scan.py` (Python 3, standard library only) counts lines, bytes, the Codex chain, missing routes and the skill catalog. It only reads.

Install: point your agent to https://github.com/serejaris/personal-corp-os/tree/main/skills/audit-agent-rules and ask it to install the skill, then say "аудит правил" or "check my AGENTS.md".

Русская версия: [README.ru.md](README.ru.md)
