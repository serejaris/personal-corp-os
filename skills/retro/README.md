# retro

The HQ weekly retro. Reads tasks from every department and writes `tasks/retro-YYYY-WNN.md` in the HQ: what got done, what got stuck, what keeps repeating.

```
/retro
```

Or ask: "retro", "how did the week go", "week results".

- Takes the current ISO week, or the week you name.
- Finds where each department keeps its tasks from the HQ rules file (`CLAUDE.md` or `AGENTS.md`); if the rules do not say, it stops and suggests one line per department.
- Sorts the week's tasks into done (accepted this week), stuck, and dropped, with a link to each task.
- Marks a repeat only when it has at least two cases: the same blocker, the same kind of work, or one decision of yours that several tasks wait for.
- Answers with 3-5 lines of conclusions, the path to the retro file, and one question: what to drop, simplify, or continue.

It does not change department tasks, does not hide what got stuck, and does not plan the next week. The skill text is in Russian.

Русская версия: [README.ru.md](README.ru.md)
