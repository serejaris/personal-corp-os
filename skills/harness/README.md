# Harness

Sets how the agent works for the rest of the session with one header at the start of a message: role (orchestrator, executor, critic), subagent model, effort, and the subagent limit.

```
/harness
режим: оркестратор, критик
модель: <модель>
эффорт: низкий
макс: 3 субагента
```

- **режим** (mode) — executor does the work itself; orchestrator only plans and hands tasks to subagents; critic checks the result against files, screenshots, and checks before showing it to you.
- **модель** (model) — the subagent model. Defaults to the current session's model; everyone sets their own.
- **эффорт** (effort) — low, medium, or high depth of work.
- **макс** (max) — how many subagents run at once.

Any line can be omitted; its default applies. The mode holds until the end of the session or the next `/harness` header. The skill text is in Russian.

Русская версия: [README.ru.md](README.ru.md)
