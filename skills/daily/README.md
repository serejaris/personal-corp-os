# daily

The HQ daily focus. Reads open tasks from every department and writes a day file `tasks/YYYY-MM-DD.md` in the HQ, with links back to the tasks.

```
/daily
```

Runs only by command: the agent does not call the skill on its own.

- Finds where each department keeps its tasks from the HQ rules file (`CLAUDE.md` or `AGENTS.md`); if the rules do not say, it stops and suggests one line per department.
- Reads local `tasks/*.md` files or an external source such as GitHub Issues, and skips accepted, finished, and dropped tasks.
- Puts each open task into one section: waiting for your decision, overdue or blocked, in progress, other open.
- Writes or updates the day file and keeps your own notes in it.
- Answers in up to 7 lines: what needs your decision, today's tasks per the priority rules section («Правила приоритета») of the HQ rules file, the path to the day file.

It does not change department tasks and does not invent tasks, dates, or paths. The skill text is in Russian.

Русская версия: [README.ru.md](README.ru.md)
