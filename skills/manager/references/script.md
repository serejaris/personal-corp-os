# Скрипт gh_issue.sh

Справочник уровня 2. Читать перед первой записью в issue: команды, правила, которые скрипт держит сам, конфиг, след агента, картинки в записи о работе, результат в PR, таблица эпика.

## Оглавление

- Зачем скрипт
- Конфиг
- Команды
- Правила, которые скрипт держит сам
- След агента
- Картинка в записи о работе
- Результат в PR
- Таблица эпика
- Примеры

## Зачем скрипт

Каждую запись в issue агент делает скриптом `scripts/gh_issue.sh` из папки скилла. Руками `gh issue edit`, `gh issue close`, `gh project item-edit` и `gh api` не вызываются: рецепты в [write-mode.md](write-mode.md) остаются запасными на случай поломки скрипта.

- Ссылка на issue: `owner/repo#N`. Неделя: `--week W44`. Статус: `Backlog`, `Ready`, `In progress`, `In review`, `Done`.
- Скрипт печатает одну строку JSON на любом выходе, ошибки вызова тоже. Смотри поля `ok`, `result`, `actions`, `warnings`, `error`. Код выхода: 0 готово или `noop`, 1 ошибка API или проверки, 2 ошибка вызова (нет файла, флаг без значения, плохая ссылка).
- `result: noop` значит, что всё уже сделано. Не повторяй команду и не делай то же руками.
- `ok: false` значит, что скрипт остановился. Перескажи `error` человеку, обходить его руками нельзя.
- Каждый пункт `warnings` закрой отдельной командой или назови в ответе.
- Повторный запуск любой команды безопасен: скрипт делает только то, чего не хватает.
- Перед первой записью в сессии прогони команду с `--dry-run`: скрипт напечатает мутации в stderr и ничего не отправит. Общие флаги `--dry-run` и `--force` ставь в любом месте строки.

Зависимости: `gh` с авторизацией, `jq`, `git`, bash 3.2 и новее. Таблицу эпика строит `scripts/board.jq` рядом со скриптом. Справка: `gh_issue.sh --help`.

## Конфиг

Доска, поле `Status` и опции статусов не зашиты в скрипт. Скопируй [../config.example.json](../config.example.json) в `config.json` рядом со скиллом или в `~/.config/manager/config.json` и подставь свои значения:

```bash
gh project view 1 --owner your-github-handle --format json --jq .id         # project.id
gh project field-list 1 --owner your-github-handle --format json            # status_field_id и id опций
```

Порядок поиска: переменная `MANAGER_CONFIG` → `config.json` в папке скилла → `${XDG_CONFIG_HOME:-~/.config}/manager/config.json`. Переменные окружения перекрывают конфиг: `MANAGER_PROJECT_ID`, `MANAGER_PROJECT_NUMBER`, `MANAGER_STATUS_FIELD_ID`, `MANAGER_STATUS_OPTIONS` (JSON `{"Backlog":"id",…}`), `MANAGER_CLONE_ROOTS` (папки с клонами через `:`).

Доски нет или в конфиге остались заглушки `<…>`: `read`, `comment`, `shot`, `now`, `close`, `block`, `board` работают как обычно, `ensure` и `create` ставят W-label, исполнителя и эпик, а место на доске пропускают с предупреждением.

Id доски, поля и опций живут только в `config.json`: в `SKILL.md` и справочники их не переписывай. `config.json` со своими id в публичный репозиторий не коммить.

## Команды

| Действие | Команда | Вызовов API |
|---|---|---|
| Прочитать состояние 1–20 issues | `read REF REF …` | 1 |
| Создать задачу | `create --repo O/R --title T --body-file F --week W44 --parent REF [--status S]` | 3 |
| Довести issue до инвариантов 1–5 | `ensure REF --week W44 [--parent REF] [--status S]` | 1–3 |
| Запись о работе | `comment REF --body-file F [--image-url URL]` | 2 |
| Положить картинку и получить ссылку по SHA | `shot REF --image shot.png [--dir docs/shots]` | 3 |
| Заменить секцию `## Сейчас` | `now REF --text "…"` | 2 |
| Закрыть с Proof | `close REF --proof-file F [--reason not_planned]` | 3 |
| A ждёт B | `block A --by B` | 2 |
| Пересобрать таблицу эпика | `board EPIC` | 2 |

## Правила, которые скрипт держит сам

- `create` не создаёт дубль: при открытом issue с тем же заголовком он доводит найденный через `ensure`.
- `ensure` не перетирает исполнителя и не меняет чужого эпика. Эпик меняет только флаг `--replace-parent`. Статус `In review` и `Done` не понижает без `--force`.
- У эпика 100 подзадач: скрипт останавливается, от 90 предупреждает. Что делать: [parent-epic.md](parent-epic.md) → «Полный эпик».
- `close` не закрывает issue с открытыми подзадачами без `--force`. После закрытия проверяет, что Proof лежит в таймлайне. На уже закрытом issue без Proof добавляет Proof и не переоткрывает. Шаблон Proof: [templates.md](templates.md) → «Proof при закрытии».
- Остаток rate limit меньше 200 очков (`GH_ISSUE_RATE_MIN`): скрипт останавливается с `Project lane pending: rate limit`.

## След агента

`create` дописывает в конец тела скрытый комментарий:

```
<!-- origin: harness=claude-code; model=…; folder=…; session=… -->
```

Харнес и сессию скрипт берёт из окружения (`CLAUDECODE`, `CLAUDE_CODE_SESSION_ID`, `CODEX_THREAD_ID`, `HERMES_SESSION_ID`), папку из корня git, модель передай флагом `--model`. По следу видно, какой агент и в какой сессии завёл задачу: на нём строят уведомления и аудит. Отключить: `--no-origin`.

## Картинка в записи о работе

Картинка нужна, когда результат визуальный: интерфейс, страница, схема. Результат скрипта или правила показывай текстом в самой записи: блок кода с выводом или таблица.

Картинку кладёт отдельная команда `shot`, запись о работе делает `comment`:

```bash
G=<папка скилла>/scripts/gh_issue.sh
$G shot your-github-handle/app#12 --image /tmp/sign-in.png
# {"ok":true,"result":"done","path":"docs/shots/2026-10-29-12-sign-in.png","sha":"<sha коммита>","url":"https://github.com/your-github-handle/app/blob/<sha коммита>/docs/shots/2026-10-29-12-sign-in.png?raw=true",…}
$G comment your-github-handle/app#12 --body-file /tmp/work.md --image-url "<url из shot>"
```

- `shot` кладёт картинку одним коммитом через Contents API в ветку по умолчанию репозитория задачи. Локальную ветку, рабочее дерево и `git push` он не трогает.
- Путь: `docs/shots/<дата>-<N>-<имя>.png`. Если путь под `.gitignore` локального клона, `shot` берёт `docs/status/`, потом первую отслеживаемую папку `docs/shots` или `docs/status`. Папку задаёт флаг `--dir`. Клон для проверки `.gitignore` скрипт ищет в текущей папке и в `clone_roots` конфига; без клона скрипт пишет предупреждение в `warnings`.
- `shot` печатает `path`, `sha` коммита, `url` и готовую строку `markdown`. Ссылка идёт по SHA коммита, поэтому переживает удаление любой ветки. Повторный `shot` той же картинки отдаёт `noop` и ту же ссылку.
- `comment` в репозиторий ничего не пишет: он вставляет в конец записи `![имя](URL)` для каждого `--image-url`.

## Результат в PR

PR показывает результат прямо в описании. Без него PR человеку на вливание не отдаётся.

- Визуальный результат (интерфейс, страница, схема): картинка. Ссылку дай из `shot` (по SHA коммита) или перетащи картинку в описание на GitHub, она станет вложением. Ссылку по имени ветки не ставь: после вливания и удаления ветки она битая.
- Скрипт, правила, справочник: текстовый вывод. Вставь вывод команды блоком кода или таблицу, картинка не нужна.

```bash
# в /tmp/pr-body.md:
# ![Страница входа](https://github.com/your-github-handle/app/blob/<sha коммита>/docs/shots/2026-10-29-12-sign-in.png?raw=true)
gh pr edit 57 --repo your-github-handle/app --body-file /tmp/pr-body.md
```

## Таблица эпика

`board EPIC` пишет в `## Сейчас` эпика таблицу открытых детей и блок «Как выглядит» между метками `<!-- board:start -->` и `<!-- board:end -->`. Вводный абзац секции и остальное тело не трогает.

- Колонки «Где» и «Ждёт» берутся из строк `Где:` и `Ждёт:` в `## Сейчас` ребёнка, их пиши командой `now`.
- Значок: 🟢 на проверке или готово, 🟡 в работе, ⚪ ждёт, 🔴 блокирует другую задачу.
- Картинка в «Как выглядит» берётся последняя из записей о работе ребёнка.
- Эпик обновляй командой `board` после каждого синка его детей.

Пример таблицы:

```markdown
| | Задача | Где | Ждёт |
|---|---|---|---|
| 🟢 | #12 Add sign-in page | `feat/sign-in` | владелец: проверить вход на превью |
| 🟡 | #13 Send welcome email | `feat/welcome-email` | ключ почтового сервиса |
| ⚪ | site#7 Landing page |  | после #12 |
| 🔴 | #14 Billing settings |  | решение по тарифам |
```

## Примеры

```bash
G=<папка скилла>/scripts/gh_issue.sh

# состояние задач одним запросом
$G read your-github-handle/app#12 your-github-handle/app#13

# новая задача под эпиком, сразу в работе
$G create --repo your-github-handle/app --title "Добавить страницу входа" \
  --body-file tasks/2026-10-29-sign-in.md --week W44 --parent your-github-handle/app#11 \
  --status "In progress" --model <модель>

# запись о работе с картинкой, строка «Сейчас», таблица эпика
$G shot your-github-handle/app#12 --image /tmp/sign-in.png      # url в поле url
$G comment your-github-handle/app#12 --body-file /tmp/work.md --image-url "<url из shot>"
$G now your-github-handle/app#12 --text $'Где: `feat/sign-in`\nЖдёт: владелец: проверить вход'
$G board your-github-handle/app#11

# закрытие с Proof
$G close your-github-handle/app#12 --proof-file /tmp/proof.md
```
