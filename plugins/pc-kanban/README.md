# pc-kanban

[![en](https://img.shields.io/badge/lang-en-blue.svg)](README.md)
[![ru](https://img.shields.io/badge/lang-ru-green.svg)](README.ru.md)

A Claude Code mod for Personal Corp. When a session starts it opens a panel: your tasks in four columns by status and, below them, the neighbouring departments with progress bars. A click on a card puts "take this task" into the prompt. `/kanban` opens the panel again. The panel speaks Russian.

![pc-kanban in a student HQ: tasks of three departments by status, departments with progress bars below](assets/panel.png)

*A terminal session in a student HQ. The HQ has no tasks of its own, so the board gathers the task files of all departments.*

## Two task sources

| Source | Where tasks live | The board | Under the board |
|---|---|---|---|
| `bd` | the beads graph of a repository (`.beads/`) | beads of the session folder: open, in progress, blocked, done in the last 7 days | open epics of neighbouring repositories with `.beads`, closed children as the bar |
| task files | `tasks/*.md` in department folders, one file per task | task files of the session folder; in an HQ without tasks of its own, the tasks of all departments | departments with task files, closed tasks as the bar |

The `source` option picks one: `auto` (default), `bd` or `tasks`. `auto` takes `bd` when the session folder has `.beads`, task files when it has `tasks/`, otherwise `bd` when a neighbour has `.beads`, and task files in every other case.

## Task files

The format is the one from the Personal Corp lessons and [`templates/department/tasks/_template.md`](../../templates/department/tasks/_template.md):

```markdown
# Письмо клиенту с итогами встречи 25.09

Статус: в работе

## Результат

Черновик письма клиенту: три договорённости со встречи и срок следующего шага.
```

- A task is a file `tasks/<name>.md` with a status line: `Статус: …`, `- Статус: …`, `**Статус:** …` or `Status: …`. Files without one (day files, retros) are skipped, so are `README.md`, `_template.md` and hidden files.
- The card shows the first `#` heading and the file name.
- The status goes to a column by its first words; text after a dash or a comma is a comment.

| Column | Statuses |
|---|---|
| Открыто (open) | `новая` and any word the panel does not know |
| В работе (in progress) | `в работе`, `на приёмке`, `на проверке` |
| Заблокировано (blocked) | `заблокирована` |
| Готово за 7 дней (done in 7 days) | `завершена`, `принято`, `снята`, `готово`; the date comes from `Завершена:` or the file's change time |

A status the column names differently stays on the card: `на приёмке`, `снята`, `принято`.

The click puts `Возьми в работу задачу ../content/tasks/<file>.md: <title>` into the prompt, the path relative to the session folder. In `bd` mode it is `Возьми в работу бид <id>: <title>`.

## Departments

Departments are the folders next to the session folder, or inside the `root` option. When the session folder holds `hq/`, the session was opened above the HQ and that folder is the root. Worktrees (where `.git` is a file) repeat a neighbour and are skipped. In `bd` mode only git repositories with `.beads` count.

## Install

The mod is a separate plugin in the `personal-corp-os` marketplace, for Claude Code only. In a terminal:

```bash
claude plugin marketplace add serejaris/personal-corp-os
claude plugin install pc-kanban@personal-corp-os
```

Or at the Claude Code prompt in a terminal, with the marketplace already added:

```text
/plugin install pc-kanban@personal-corp-os
```

Without the marketplace, one line adds it and installs the mod:

```text
/plugin install pc-kanban --marketplace serejaris/personal-corp-os
```

The install shows the options screen; the defaults work. For the Claude desktop app, install from a terminal at the user scope (the commands above): the panel then opens in the app's Code sessions too.

## Options

| Option | Default | What it does |
|---|---|---|
| `source` | `auto` | task source: `auto`, `bd`, `tasks` |
| `root` | empty | folder with the HQ and the departments; empty means the folder above the session folder (`~` works) |
| `bd` | `bd` | path to `bd` when it is not in `PATH` |
| `autoOpen` | `true` | open the panel when a session starts |

Change them with `/plugin configure pc-kanban@personal-corp-os`.

## Limits

- A mod cannot change the app's start screen before a session, hence the panel.
- On a terminal narrower than 144 columns the panel opened at start waits; `/kanban` opens it at any width.
- In `claude -p` there is nothing to draw the panel, so the board is not read until `/kanban` asks.
- `bd` mode runs `bd list` in the session folder and `bd epic status` in each neighbour with `.beads`, eight at a time.

## Development

```bash
claude plugin validate plugins/pc-kanban
claude plugin test plugins/pc-kanban
claude --plugin-dir plugins/pc-kanban
```

The tests run both sources on an in-memory file system (`tests/kit.ts`) and a fake `bd`. The function hooks API is early access: checked on Claude Code 2.1.301 and 2.1.304.
