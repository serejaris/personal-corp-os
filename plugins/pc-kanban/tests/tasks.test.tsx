import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

import { isTaskFile, parseTask, toIsoDate, toStatus } from '../hooks/tasks'
import { DAY, NOW, PANE, engine, fakeFs } from './kit'

const CORP = '/home/student/corp'

// Образец файла задачи из урока PC3 L2: строка «Статус:» сразу под заголовком.
const LESSON = `# Письмо клиенту с итогами встречи 25.09

Статус: в работе

## Результат

Черновик письма клиенту: три договорённости со встречи и срок следующего шага.

## Как проверить

- [x] В письме три договорённости со встречи, каждая одной строкой.
- [ ] Обращение в первой строке по имени клиента.

## Следующий шаг

Агент правит обращение в первой строке по замечанию и снова отдаёт черновик на проверку.
`

/** Задача по шаблону отдела templates/department/tasks/_template.md. */
function task(title: string, status: string, closed = '') {
  return `# ${title}

## Результат

Одно проверяемое изменение.

## Состояние

- Статус: ${status}
- Создана: 2026-10-01
- Завершена: ${closed}

## Следующий шаг

Один конкретный шаг.
`
}

const FILES = {
  [`${CORP}/hq/AGENTS.md`]: '# Правила штаба',
  // Файл дня скилла daily: строки «Статус:» нет, это не задача.
  [`${CORP}/hq/tasks/2026-10-19.md`]: '# 2026-10-19\n\n## В работе\n- content · Пост про запуск\n',
  [`${CORP}/content/tasks/README.md`]: '# Задачи отдела\n\n- Статус: описание папки, не задача\n',
  [`${CORP}/content/tasks/_template.md`]: task('Название задачи', 'новая'),
  [`${CORP}/content/tasks/2026-09-25-письмо.md`]: LESSON,
  [`${CORP}/content/tasks/2026-10-01-пост.md`]: task('Пост про запуск', 'на приёмке'),
  [`${CORP}/content/tasks/2026-10-05-рилс.md`]: task('Рилс про отдел', 'новая'),
  [`${CORP}/content/tasks/2026-10-10-обложка.md`]: task('Обложка урока', 'завершена', '2026-10-17'),
  [`${CORP}/content/tasks/2026-09-01-старое.md`]: task('Старый пост', 'завершена', '01.09.2026'),
  [`${CORP}/sales/tasks/2026-10-12-кп.md`]: '# КП для школы\n\n**Статус:** заблокирована — ждём реквизиты\n',
  [`${CORP}/sales/tasks/2026-10-14-звонок.md`]: { text: task('Звонок партнёру', 'снята'), mtimeMs: NOW - 2 * DAY },
  [`${CORP}/notes/README.md`]: '# Заметки',
  // worktree отдела повторяет его задачи
  [`${CORP}/content-wt/.git`]: 'gitdir: /home/student/corp/content/.git/worktrees/content-wt',
  [`${CORP}/content-wt/tasks/2026-10-01-пост.md`]: task('Пост про запуск', 'на приёмке'),
}

function prompts(on: On) {
  const filled: string[] = []
  on('prompt.fill', ($, e) => {
    filled.push(e.text)

    return { isFilled: true }
  })

  return filled
}

test('в штабе без своих задач доска собирает task-файлы всех отделов', async ($, on) => {
  const clock = engine(on)
  fakeFs(on, FILES)
  const filled = prompts(on)

  await $.session.start({ cwd: `${CORP}/hq`, surface: 'desktop', isInteractive: true })
  await clock.advance(10)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })

    expect(await ui.find({ type: 'Text', text: /corp · задачи всех отделов/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Открыто · 1/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /В работе · 2/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Заблокировано · 1/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Готово за 7 дней · 2/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /content · 2026-10-01-пост · на приёмке/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /sales · 2026-10-14-звонок · снята/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^sales · 2026-10-12-кп$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Отделы · 2 отдела с задачами/ })).toBeDefined()
    expect((await ui.find({ key: `project:${CORP}/content:` }))?.text).toMatch(/content в работе 2 · открыто 1 ▰▰▰▱▱▱▱▱ 2\/5/)
    expect((await ui.find({ key: `project:${CORP}/sales:` }))?.text).toMatch(/sales заблокировано 1 ▰▰▰▰▱▱▱▱ 1\/2/)

    // шаблон, README, файл дня, давно закрытое и копия в worktree не карточки
    for (const path of [
      `${CORP}/content/tasks/_template.md`,
      `${CORP}/content/tasks/README.md`,
      `${CORP}/hq/tasks/2026-10-19.md`,
      `${CORP}/content/tasks/2026-09-01-старое.md`,
      `${CORP}/content-wt/tasks/2026-10-01-пост.md`,
    ]) {
      expect(await ui.find({ key: `take:${path}` })).toBeUndefined()
    }
    await ui.unmount()
  }

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: `take:${CORP}/content/tasks/2026-10-01-пост.md` })
  expect(filled).toEqual(['Возьми в работу задачу ../content/tasks/2026-10-01-пост.md: Пост про запуск'])

  await ui.press({ key: `project:${CORP}/sales:` })
  expect(await ui.find({ type: 'Text', text: /sales · все задачи/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^2026-10-12-кп$/ })).toBeDefined()
  expect((await ui.find({ key: `project:${CORP}/sales:` }))?.text).toMatch(/^▸ sales/)

  await ui.press({ key: 'home' })
  expect(await ui.find({ type: 'Text', text: /corp · задачи всех отделов/ })).toBeDefined()
  expect(await ui.find({ key: 'home' })).toBeUndefined()
  await ui.unmount()
})

test('в отделе доска показывает его задачи, путь в промпте от папки сессии', async ($, on) => {
  const clock = engine(on)
  fakeFs(on, FILES)
  const filled = prompts(on)

  await $.session.start({ cwd: `${CORP}/content`, surface: 'desktop', isInteractive: true })
  await clock.advance(10)

  const low = await $.ui.mount({ ...PANE, surface: 'terminal', props: { ...PANE.props, scroll: { offset: 0, bodyRows: 13 } } })
  expect(await low.find({ type: 'Text', text: /\+ ещё 1/ })).toBeDefined()
  expect(await low.find({ type: 'Text', text: /Отделы · 2 отдела с задачами/ })).toBeDefined()
  await low.unmount()

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /content · все задачи/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /\+ ещё/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /Открыто · 1/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /В работе · 2/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Заблокировано · 0/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Готово за 7 дней · 1/ })).toBeDefined()
  expect((await ui.find({ key: `project:${CORP}/content:` }))?.text).toMatch(/^▸ content/)

  await ui.press({ key: `take:${CORP}/content/tasks/2026-09-25-письмо.md` })
  expect(filled).toEqual(['Возьми в работу задачу tasks/2026-09-25-письмо.md: Письмо клиенту с итогами встречи 25.09'])
  await ui.unmount()
})

test('сессия в папке над штабом читает отделы в ней самой', async ($, on) => {
  const clock = engine(on)
  fakeFs(on, FILES)
  const filled = prompts(on)

  await $.session.start({ cwd: CORP, surface: 'desktop', isInteractive: true })
  await clock.advance(10)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /corp · задачи всех отделов/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Отделы · 2 отдела с задачами/ })).toBeDefined()
  await ui.press({ key: `take:${CORP}/sales/tasks/2026-10-12-кп.md` })
  expect(filled).toEqual(['Возьми в работу задачу sales/tasks/2026-10-12-кп.md: КП для школы'])
  await ui.unmount()
})

test('настройка source: tasks сильнее .beads, root с ~ читается от HOME', { options: { source: 'tasks', root: '~/corp' } }, async ($, on) => {
  const clock = engine(on)
  mock.env(on, { HOME: '/home/student' })
  fakeFs(on, { ...FILES, '/work/site/.beads/': '', '/work/site/.git/': '' })
  const filled = prompts(on)
  const runs: string[] = []
  on('process.run', ($, e) => {
    runs.push(e.argv.join(' '))

    return { value: { exitCode: 1, stdout: '', stderr: 'bd не нужен', isStdoutTruncated: false, isStderrTruncated: false } }
  })

  await $.session.start({ cwd: '/work/site', surface: 'desktop', isInteractive: true })
  await clock.advance(10)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /corp · задачи всех отделов/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /Отделы · 2 отдела с задачами/ })).toBeDefined()
  expect(runs).toEqual([])
  await ui.press({ key: `take:${CORP}/content/tasks/2026-10-05-рилс.md` })
  expect(filled).toEqual([`Возьми в работу задачу ${CORP}/content/tasks/2026-10-05-рилс.md: Рилс про отдел`])
  await ui.unmount()
})

test('без task-файлов панель подсказывает формат задачи', async ($, on) => {
  const clock = engine(on)
  fakeFs(on, { [`${CORP}/hq/AGENTS.md`]: '# Правила штаба' })

  await $.session.start({ cwd: `${CORP}/hq`, surface: 'desktop', isInteractive: true })
  await clock.advance(10)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /Задача — файл tasks\/имя\.md со строкой «Статус: …» внутри/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /задач в отделах нет/ })).toBeDefined()
  await ui.unmount()
})

test('в claude -p без поверхности доска не читается, пока не попросят /kanban', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  mock.store(on)
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('command.register', ($, e) => ({ value: { command: e.name } }))
  on('ui.open', () => {
    throw new Error('no-surface: no surface is attached')
  })
  const fs = fakeFs(on, FILES)

  await $.session.start({ cwd: `${CORP}/hq`, surface: null, isInteractive: false })
  await clock.advance(10)
  expect(fs.reads).toEqual([])

  const { text } = await $.command.run({ command: 'kanban', args: '', origin: { kind: 'sdk' }, presentation: { isFullscreen: false, columns: 120 } })
  await clock.advance(10)
  expect(text).toBe('Канбан рисуется панелью, а этой сессии её негде показать.')
  expect(fs.reads).toContain(`${CORP}/content/tasks/2026-10-01-пост.md`)
})

test('autoOpen: false не открывает панель, но доска готова к /kanban', { options: { autoOpen: false } }, async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  mock.store(on)
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('command.register', ($, e) => ({ value: { command: e.name } }))
  const opened: string[] = []
  on('ui.open', ($, e) => {
    opened.push(e.id)

    return { value: { isPlaced: true as const } }
  })
  const fs = fakeFs(on, FILES)

  await $.session.start({ cwd: `${CORP}/content`, surface: 'terminal', isInteractive: true })
  await clock.advance(10)
  expect(opened).toEqual([])
  expect(fs.reads).toContain(`${CORP}/content/tasks/2026-09-25-письмо.md`)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await ui.find({ type: 'Text', text: /В работе · 2/ })).toBeDefined()
  await ui.unmount()
})

test('статус словами раскладывается по колонкам', () => {
  const statuses = ['новая', 'в работе', 'На приёмке', 'заблокирована', 'Завершена', 'принято', 'снята', 'Готово', 'in progress', 'done', 'своё слово']
  expect(statuses.map(toStatus)).toEqual([
    'open', 'in_progress', 'in_progress', 'blocked', 'closed', 'closed', 'closed', 'closed', 'in_progress', 'closed', 'open',
  ])
})

test('из task-файла берутся заголовок, статус и дата закрытия', () => {
  expect(parseTask(LESSON)).toEqual({ title: 'Письмо клиенту с итогами встречи 25.09', phrase: 'в работе', closedAt: '' })
  expect(parseTask(task('Обложка', 'завершена', '17.10.2026'))).toEqual({ title: 'Обложка', phrase: 'завершена', closedAt: '2026-10-17' })
  expect(parseTask('# Пост\n\n- **Статус:** в работе, жду обложку\n')?.phrase).toBe('в работе')
  expect(parseTask('# Пост\n\nСтатус:\n')?.phrase).toBe('')
  expect(parseTask('# 2026-10-19\n\n## В работе\n- пост\n')).toBeUndefined()
  expect(parseTask('# Формат\n\n```\nСтатус: в работе\n```\n')).toBeUndefined()
  expect(['README.md', '_template.md', '.draft.md', 'notes.txt', '2026-10-01-пост.md'].map(isTaskFile)).toEqual([false, false, false, false, true])
  expect(['2026-10-17', '1.9.2026', 'ГГГГ-ММ-ДД'].map(toIsoDate)).toEqual(['2026-10-17', '2026-09-01', ''])
})
