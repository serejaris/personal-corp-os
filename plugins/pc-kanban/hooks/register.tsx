import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Board, Card, Kind, Project, Projects, Source } from '../types'
import { parseJson, toCards, toProjects } from './beads'
import { ago, bar, baseName, cardsPerColumn, columns, parentOf, plural, pool, relative, short, sortProjects } from './board'
import { isTaskFile, toDeptProject, toTaskCard } from './tasks'

const PANE = 'pc-kanban'
const TITLE = 'Personal Corp'
// Сколько строк панель просит над полем ввода: доска и список проектов под ней.
const PANE_ROWS = 30
const EPICS = ['эпик', 'эпика', 'эпиков'] as const
const IN_DEPTS = ['отделе', 'отделах', 'отделах'] as const
const DEPTS = ['отдел', 'отдела', 'отделов'] as const
const PROJECTS_FOLDED = 8

const kindAtom = atom({ plugin: 'pc-kanban', key: 'kind' } as const, null)
const boardAtom = atom({ plugin: 'pc-kanban', key: 'board' } as const, null)
const projectsAtom = atom({ plugin: 'pc-kanban', key: 'projects' } as const, null)
const sourceAtom = atom({ plugin: 'pc-kanban', key: 'source' } as const, null)
const loadingAtom = atom({ plugin: 'pc-kanban', key: 'isLoading' } as const, false)
const allAtom = atom({ plugin: 'pc-kanban', key: 'isAllProjects' } as const, false)

const TONE = { open: 'text', in_progress: 'suggestion', blocked: 'error', closed: 'success' } as const

/** Слова панели: у бидов под доской эпики, у task-файлов — отделы. */
const WORDS = {
  bd: { home: 'все биды', back: 'Все биды папки', section: 'Проекты', reading: 'читаю графы отделов…', empty: 'открытых эпиков нет' },
  tasks: { home: 'все задачи', back: 'Назад', section: 'Отделы', reading: 'читаю задачи отделов…', empty: 'задач в отделах нет' },
} as const

type $ = EngineInterface

// Задаются в register и session.start: настройки мода, папка сессии и папка отделов.
const config = { bd: 'bd', root: '', source: 'auto', autoOpen: true }
let cwd = ''
let root = ''
let isBusy = false
// Панель открыта или её просили: только тогда доска перечитывается после хода.
let isLive = false
// Источник и кэш читаются в фоне, чтобы мод не задерживал старт сессии; refresh их ждёт.
let booted: Promise<void> = Promise.resolve()

async function bd($: $, folder: string, args: string[]): Promise<unknown> {
  const { exitCode, stdout, stderr } = await $.process.run([config.bd, ...args], { cwd: folder, timeoutMs: 60_000 })
  const data = parseJson(stdout)
  if (data && typeof data === 'object' && !Array.isArray(data) && 'error' in data) {
    throw new Error(String((data as { error: unknown }).error).split('\n')[0])
  }
  if (data === undefined) {
    throw new Error(stderr.trim().split('\n').pop() || `bd вышел с кодом ${exitCode}`)
  }

  return data
}

function homeSource(kind: Kind): Source {
  return { folder: cwd, dept: baseName(cwd), epicId: '', title: WORDS[kind].home }
}

async function resolveRoot($: $): Promise<string> {
  const wanted = config.root.replace(/\/+$/, '')
  if (wanted === '~' || wanted.startsWith('~/')) return `${(await $.env.get('HOME')) ?? ''}${wanted.slice(1)}`
  if (wanted) return wanted

  // Сессию открыли в папке над штабом: отделы лежат прямо в ней.
  return (await $.fs.exists(`${cwd}/hq`)) ? cwd : parentOf(cwd)
}

/** Отделы — соседние папки с `.beads` или `tasks/`; worktree (где `.git` — файл) повторяет соседа и пропускается. */
async function departments($: $, kind: Kind): Promise<string[]> {
  const marker = kind === 'bd' ? '.beads' : 'tasks'
  const entries = await $.fs.list(root)
  const found = await Promise.all(entries.map(async entry => {
    if (entry.kind !== 'dir' || entry.name.startsWith('.')) return ''
    const folder = `${root}/${entry.name}`
    if (!(await $.fs.exists(`${folder}/${marker}`))) return ''
    // Граф bd живёт в репо, а папка отдела с задачами бывает и без git.
    if (!(await $.fs.exists(`${folder}/.git`))) return kind === 'tasks' ? folder : ''
    const git = await $.fs.stat(`${folder}/.git`)

    return git.kind === 'dir' ? folder : ''
  }))

  return found.filter(Boolean)
}

/** auto: bd, где есть граф bd; task-файлы, где есть `tasks/`; иначе bd, если граф есть у соседей. */
async function detect($: $): Promise<Kind> {
  if (config.source === 'bd' || config.source === 'tasks') return config.source
  if (await $.fs.exists(`${cwd}/.beads`)) return 'bd'
  if (await $.fs.exists(`${cwd}/tasks`)) return 'tasks'
  const graphs = await departments($, 'bd').catch(() => [] as string[])

  return graphs.length > 0 ? 'bd' : 'tasks'
}

/** Задачи папки — `tasks/*.md` со строкой «Статус:». */
async function readTasks($: $, folder: string): Promise<Card[]> {
  const dir = `${folder}/tasks`
  if (!(await $.fs.exists(dir))) return []
  const files = (await $.fs.list(dir)).filter(entry => entry.kind === 'file' && isTaskFile(entry.name))
  const cards = await pool(files, 8, async file => {
    const path = `${dir}/${file.name}`
    const text = await $.fs.read(path).catch(() => '')

    return toTaskCard(text, { path, name: file.name, dept: baseName(folder), mtimeMs: file.mtimeMs })
  })

  return cards.filter((card): card is Card => card !== undefined)
}

async function boardCards($: $, kind: Kind, chosen: Source | null): Promise<{ source: Source; cards: Card[] }> {
  const source = chosen ?? homeSource(kind)
  if (kind === 'bd') {
    const args = ['list', '--all', '--json', '--limit', '0']
    if (source.epicId) args.push('--parent', source.epicId)

    return { source, cards: toCards(await bd($, source.folder, args)) }
  }

  const own = await readTasks($, source.folder)
  if (chosen || own.length > 0) return { source, cards: own }
  // В папке сессии своих задач нет, обычно это штаб: на доске задачи всех отделов.
  const folders = await departments($, 'tasks')
  const lists = await pool(folders, 8, folder => readTasks($, folder).catch(() => [] as Card[]))

  return { source: { folder: root, dept: baseName(root), epicId: '', title: 'задачи всех отделов' }, cards: lists.flat() }
}

async function loadBoard($: $, kind: Kind, chosen: Source | null) {
  let board: Board
  try {
    const { source, cards } = await boardCards($, kind, chosen)
    board = { kind, source, cards, error: '', loadedAt: await $.clock.now() }
  } catch (err) {
    const error = err instanceof Error ? err.message : String(err)
    board = { kind, source: chosen ?? homeSource(kind), cards: [], error, loadedAt: await $.clock.now() }
  }
  await update($, boardAtom, () => board)
  if (!chosen) await $.store.set(`board:${kind}:${cwd}`, board)
}

async function loadProjects($: $, kind: Kind) {
  const folders = await departments($, kind).catch(() => [] as string[])
  const failed: string[] = []
  const lists = await pool(folders, 8, async folder => {
    try {
      if (kind === 'bd') return toProjects(await bd($, folder, ['epic', 'status', '--json']), baseName(folder), folder)
      const project = toDeptProject(await readTasks($, folder), baseName(folder), folder)

      return project ? [project] : []
    } catch {
      failed.push(baseName(folder))

      return [] as Project[]
    }
  })
  const projects: Projects = {
    kind,
    list: sortProjects(lists.flat()),
    failed: failed.sort(),
    scanned: folders.length,
    loadedAt: await $.clock.now(),
  }
  await update($, projectsAtom, () => projects)
  await $.store.set(`projects:${kind}:${root}`, projects)
}

async function refresh($: $, withProjects: boolean) {
  await booted
  const kind = await read($, kindAtom)
  if (!kind || isBusy) return
  isBusy = true
  await update($, loadingAtom, () => true)
  try {
    const chosen = await read($, sourceAtom)
    await Promise.all([loadBoard($, kind, chosen), withProjects ? loadProjects($, kind) : undefined])
  } finally {
    isBusy = false
    await update($, loadingAtom, () => false)
  }
}

async function choose($: $, source: Source | null) {
  await booted
  const kind = await read($, kindAtom)
  if (!kind) return
  await update($, sourceAtom, () => source)
  await update($, loadingAtom, () => true)
  try {
    await loadBoard($, kind, source)
  } finally {
    await update($, loadingAtom, () => false)
  }
}

async function take($: $, kind: Kind, card: Card, source: Source) {
  const where = source.folder === cwd ? '' : ` (граф ${source.folder})`
  const text = kind === 'bd'
    ? `Возьми в работу бид ${card.id}${where}: ${card.title}`
    : `Возьми в работу задачу ${relative(card.path, cwd)}: ${card.title}`
  await $.prompt.fill({ text })
  $.ui.toast(`${card.id} — в поле ввода`)
}

/** Источник, кэш прошлой сессии и панель; в голом `claude -p` её некому рисовать, и доска там не читается. */
async function boot($: $, surface: unknown) {
  root = await resolveRoot($).catch(() => parentOf(cwd))
  const kind = await detect($).catch((): Kind => 'tasks')
  if ((await read($, kindAtom)) !== kind) {
    // Сменился источник: выбор и доска прошлого источника не годятся.
    await update($, sourceAtom, () => null)
    await update($, boardAtom, () => null)
    await update($, projectsAtom, () => null)
    await update($, kindAtom, () => kind)
  }

  const cachedBoard = (await $.store.get(`board:${kind}:${cwd}`)) as Board | undefined
  if (cachedBoard?.kind === kind && Array.isArray(cachedBoard.cards) && !(await read($, sourceAtom))) {
    await update($, boardAtom, () => cachedBoard)
  }
  const cachedProjects = (await $.store.get(`projects:${kind}:${root}`)) as Projects | undefined
  if (cachedProjects?.kind === kind && Array.isArray(cachedProjects.list)) await update($, projectsAtom, () => cachedProjects)

  const live = () => {
    isLive = true
    void refresh($, true)
  }
  if (config.autoOpen) void $.ui.open({ id: PANE, title: TITLE, rows: PANE_ROWS }).then(live, () => undefined)
  else if (surface || (await $.session.surfaces()).length > 0) live()
}

export const register: Register = (on, options) => {
  config.bd = String(options.bd || 'bd')
  config.root = String(options.root || '')
  config.source = String(options.source || 'auto')
  config.autoOpen = options.autoOpen !== false

  on('session.start', async ($, e, next) => {
    cwd = e.cwd
    await $.command.register({ name: 'kanban', description: 'Канбан Personal Corp: биды или task-файлы отделов' })
    booted = boot($, e.surface).catch(() => undefined)

    return next(e)
  })

  on('command.run', { command: 'kanban' }, async $ => {
    const isOpen = await $.ui.open({ id: PANE, title: TITLE, rows: PANE_ROWS }).then(() => true, () => false)
    isLive = true
    void refresh($, true)

    return { text: isOpen ? 'Канбан Personal Corp открыт.' : 'Канбан рисуется панелью, а этой сессии её негде показать.' }
  })

  // Задачи чаще всего меняет сам агент: после хода доска перечитывает свой источник.
  on('turn.complete', async ($, e, next) => {
    const board = await read($, boardAtom)
    if (isLive && (!board || (await $.clock.now()) - board.loadedAt > 15_000)) void refresh($, false)

    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const kind = (await read($, kindAtom)) ?? 'bd'
    const words = WORDS[kind]
    const board = await read($, boardAtom)
    const projects = await read($, projectsAtom)
    const chosen = await read($, sourceAtom)
    const source = chosen ?? board?.source ?? homeSource(kind)
    const isLoading = await read($, loadingAtom)
    const isAll = await read($, allAtom)
    const now = await $.clock.now()

    const width = e.props.bodyColumns || e.viewport?.columns || 120
    const perRow = width >= 110 ? 4 : width >= 56 ? 2 : 1
    const colWidth = `${Math.floor(100 / perRow)}%`
    const cols = columns(board?.cards ?? [], now)
    const shown = projects ? (isAll ? projects.list : projects.list.slice(0, PROJECTS_FOLDED)) : []
    const isHint = kind === 'tasks' && board !== null && !board.error && board.cards.length === 0
    // Под доской: строка ошибки или подсказки, отступ, заголовок проектов, их строки и «не прочитались».
    const belowRows = (board?.error || isHint ? 2 : 0) + 2 + Math.max(1, shown.length) + (projects?.failed.length ? 1 : 0)
    // В узкой или низкой панели карточек меньше, чтобы проекты оставались на виду.
    const perColumn = cardsPerColumn(e.props.scroll.bodyRows, perRow, belowRows)
    const count = projects?.list.length ?? 0
    const section = !projects
      ? words.section
      : kind === 'bd'
        ? `${words.section} · ${count} ${plural(count, EPICS)} в ${projects.scanned} ${plural(projects.scanned, IN_DEPTS)}`
        : `${words.section} · ${count} ${plural(count, DEPTS)} с задачами`

    return (
      <Box flexDirection="column" gap={1}>
        <Box flexDirection="row" justifyContent="space-between">
          <Text bold>
            {source.dept} · {short(source.title, 60)}
          </Text>
          <Box flexDirection="row" gap={2}>
            <Text dimColor>
              {isLoading ? 'обновляю…' : board ? `обновлено ${ago(now - board.loadedAt)}` : ''}
            </Text>
            {chosen ? <Button key="home" label={words.back} onPress={() => choose($, null)} /> : null}
            <Button key="refresh" label="Обновить" onPress={() => refresh($, true)} />
          </Box>
        </Box>

        {board?.error ? <Text color="error">{kind === 'bd' ? `bd: ${board.error}` : board.error}</Text> : null}
        {isHint ? (
          <Text dimColor>Задача — файл tasks/имя.md со строкой «Статус: …» внутри.</Text>
        ) : null}

        <Box flexDirection="row" flexWrap="wrap" rowGap={1}>
          {cols.map(col => (
            <Box key={`col:${col.status}`} flexDirection="column" width={colWidth} paddingRight={1}>
              <Text bold color={TONE[col.status]}>
                {col.title} · {col.cards.length}
              </Text>
              {col.cards.length === 0 ? <Text dimColor>пусто</Text> : null}
              {col.cards.slice(0, perColumn).map(card => (
                <Box key={`card:${card.path || card.id}`} flexDirection="column" borderStyle="round" borderDimColor paddingX={1}>
                  {kind === 'bd' ? (
                    <Text dimColor>
                      <Text color={card.priority === 0 ? 'error' : card.priority === 1 ? 'warning' : 'subtle'}>P{card.priority}</Text>
                      {' '}{card.id}{card.assignee ? ` · ${card.assignee}` : ''}
                    </Text>
                  ) : (
                    <Text dimColor>
                      {card.dept !== source.dept ? `${card.dept} · ` : ''}{card.id}{card.note ? ` · ${card.note}` : ''}
                    </Text>
                  )}
                  <Button key={`take:${card.path || card.id}`} plain onPress={() => take($, kind, card, source)}>
                    {short(card.title, 90)}
                  </Button>
                </Box>
              ))}
              {col.cards.length > perColumn ? (
                <Text dimColor>+ ещё {col.cards.length - perColumn}</Text>
              ) : null}
            </Box>
          ))}
        </Box>

        <Box flexDirection="column">
          <Box flexDirection="row" justifyContent="space-between">
            <Text bold>{section}</Text>
            {projects && projects.list.length > PROJECTS_FOLDED ? (
              <Button
                key="all"
                label={isAll ? 'Свернуть' : `Все ${projects.list.length}`}
                onPress={() => update($, allAtom, value => !value)}
              />
            ) : null}
          </Box>
          {!projects ? <Text dimColor>{words.reading}</Text> : null}
          {projects && projects.list.length === 0 ? <Text dimColor>{words.empty}</Text> : null}
          {shown.map(project => {
            const isOn = project.id === source.epicId && project.folder === source.folder

            return (
              <Button
                key={`project:${project.folder}:${project.id}`}
                plain
                onPress={() => choose($, {
                  folder: project.folder,
                  dept: project.dept,
                  epicId: project.id,
                  title: kind === 'bd' ? project.title : words.home,
                })}
              >
                {isOn ? '▸ ' : '  '}
                {kind === 'bd' ? <Text dimColor>{project.dept}</Text> : project.dept}{' '}
                {kind === 'bd' ? short(project.title, 80) : <Text dimColor>{project.title}</Text>}{' '}
                <Text dimColor>
                  {bar(project.closed, project.total)} {project.closed}/{project.total}
                </Text>
              </Button>
            )
          })}
          {projects && projects.failed.length > 0 ? (
            <Text dimColor>не прочитались: {projects.failed.join(', ')}</Text>
          ) : null}
        </Box>
      </Box>
    )
  })
}
