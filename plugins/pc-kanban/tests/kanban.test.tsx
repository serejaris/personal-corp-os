import { expect, test } from 'claude-code/testing'

import { cardsPerColumn, plural } from '../hooks/board'
import { DAY, NOW, PANE, engine, fakeFs } from './kit'

const ROOT = '/corp'

function issues(now: number) {
  return [
    { id: 'hq-1', title: 'Открытая задача', status: 'open', priority: 1, issue_type: 'task', updated_at: '2026-10-19T10:00:00Z' },
    { id: 'hq-2', title: 'Задача в работе', status: 'in_progress', priority: 0, issue_type: 'task', assignee: 'producer' },
    { id: 'hq-3', title: 'Закрыта давно', status: 'closed', priority: 2, issue_type: 'task', closed_at: new Date(now - 30 * DAY).toISOString() },
    { id: 'hq-4', title: 'Закрыта вчера', status: 'closed', priority: 2, issue_type: 'task', closed_at: new Date(now - DAY).toISOString() },
    { id: 'hq-e', title: 'Эпик штаба', status: 'open', priority: 0, issue_type: 'epic' },
    { id: 'hq-m', title: 'Вопрос владельцу', status: 'open', priority: 1, issue_type: 'message' },
  ]
}

const EPICS: Record<string, unknown[]> = {
  [`${ROOT}/hq`]: [{ epic: { id: 'hq-e', title: 'Эпик штаба', status: 'open', priority: 0 }, total_children: 4, closed_children: 2 }],
  [`${ROOT}/crm`]: [{ epic: { id: 'crm-1', title: 'Продажи', status: 'open', priority: 1 }, total_children: 3, closed_children: 0 }],
}

// Два графа bd, worktree графа (где .git — файл), папка без графа и скрытая папка.
const REPOS = {
  [`${ROOT}/hq/.beads/`]: '',
  [`${ROOT}/hq/.git/`]: '',
  [`${ROOT}/crm/.beads/`]: '',
  [`${ROOT}/crm/.git/`]: '',
  [`${ROOT}/hq-wt/.beads/`]: '',
  [`${ROOT}/hq-wt/.git`]: 'gitdir: /corp/hq/.git/worktrees/hq-wt',
  [`${ROOT}/notes/README.md`]: '# Заметки',
  [`${ROOT}/.cache/.beads/`]: '',
}

function ran(stdout: unknown, exitCode = 0) {
  return { value: { exitCode, stdout: JSON.stringify(stdout), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
}

test('доска делит биды по статусам, проекты собираются из отделов, клик кладёт бид в поле ввода', async ($, on) => {
  const clock = engine(on)
  fakeFs(on, REPOS)
  const calls: string[] = []
  const filled: string[] = []

  on('process.run', ($, e) => {
    const cwd = String(e.init?.cwd)
    calls.push(`${cwd}: ${e.argv.slice(1).join(' ')}`)
    const data = e.argv[1] === 'epic' ? EPICS[cwd] ?? [] : issues(NOW).filter(i => !e.argv.includes('--parent') || i.id === 'hq-1')

    return ran(data)
  })
  on('prompt.fill', ($, e) => {
    filled.push(e.text)

    return { isFilled: true }
  })

  await $.session.start({ cwd: `${ROOT}/hq`, surface: 'desktop', isInteractive: true })
  await clock.advance(10)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })

    expect(await ui.find({ type: 'Text', text: /hq · все биды/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Открыто · 1/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /В работе · 1/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Заблокировано · 0/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Готово за 7 дней · 1/ })).toBeDefined()
    expect(await ui.find({ key: 'take:hq-e' })).toBeUndefined()
    expect(await ui.find({ key: 'take:hq-m' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /Проекты · 2 эпика в 2 отделах/ })).toBeDefined()

    await ui.unmount()
  }

  // worktree, папка без бидов и скрытая папка не читаются
  expect(calls.some(c => /^\/corp\/(hq-wt|notes|\.cache)/.test(c))).toBe(false)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  await ui.press({ key: 'take:hq-2' })
  expect(filled).toEqual(['Возьми в работу бид hq-2: Задача в работе'])

  await ui.press({ key: `project:${ROOT}/crm:crm-1` })
  expect(calls).toContain(`${ROOT}/crm: list --all --json --limit 0 --parent crm-1`)
  expect(await ui.find({ type: 'Text', text: /crm · Продажи/ })).toBeDefined()

  await ui.press({ key: 'take:hq-1' })
  expect(filled[1]).toBe(`Возьми в работу бид hq-1 (граф ${ROOT}/crm): Открытая задача`)

  await ui.press({ key: 'home' })
  expect(await ui.find({ type: 'Text', text: /hq · все биды/ })).toBeDefined()
  await ui.unmount()
})

test('auto берёт bd и в папке без графа, если граф есть у соседей', async ($, on) => {
  const clock = engine(on)
  fakeFs(on, REPOS)
  const folders: string[] = []
  on('process.run', ($, e) => {
    folders.push(String(e.init?.cwd))

    return ran([])
  })

  await $.session.start({ cwd: `${ROOT}/notes`, surface: 'desktop', isInteractive: true })
  await clock.advance(10)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /notes · все биды/ })).toBeDefined()
  expect(folders).toContain(`${ROOT}/notes`)
  await ui.unmount()
})

test('ошибка bd видна на доске', { options: { source: 'bd' } }, async ($, on) => {
  const clock = engine(on)
  fakeFs(on, { [`${ROOT}/empty/`]: '' })
  on('process.run', () => ran({ error: 'no beads database found' }, 1))

  await $.session.start({ cwd: `${ROOT}/empty`, surface: 'desktop', isInteractive: true })
  await clock.advance(10)

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect(await ui.find({ type: 'Text', text: /bd: no beads database found/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /открытых эпиков нет/ })).toBeDefined()
  await ui.unmount()
})

test('форма слова по числу', () => {
  const forms = ['эпик', 'эпика', 'эпиков'] as const
  expect([1, 2, 5, 11, 12, 21, 22, 92, 111].map(n => `${n} ${plural(n, forms)}`)).toEqual([
    '1 эпик', '2 эпика', '5 эпиков', '11 эпиков', '12 эпиков', '21 эпик', '22 эпика', '92 эпика', '111 эпиков',
  ])
})

test('в низкой панели карточек меньше, чтобы проекты оставались на виду', () => {
  expect([
    cardsPerColumn(0, 4, 5),
    cardsPerColumn(60, 4, 5),
    cardsPerColumn(30, 4, 5),
    cardsPerColumn(17, 4, 5),
    cardsPerColumn(30, 2, 5),
    cardsPerColumn(10, 1, 5),
  ]).toEqual([6, 6, 5, 1, 2, 1])
})
