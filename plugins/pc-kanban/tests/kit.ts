import type { On } from 'claude-code'
import { mock } from 'claude-code/testing'

export const NOW = Date.parse('2026-10-19T12:00:00Z')
export const DAY = 86_400_000

/** Файл — текст или текст со временем правки; путь с `/` в конце — пустая папка. */
export type Files = Record<string, string | { text: string; mtimeMs: number }>

export const PANE = {
  plugin: 'pc-kanban',
  component: 'Pane',
  requestId: 'pc-kanban',
  props: {
    title: 'Personal Corp',
    isFocused: false,
    bodyColumns: 140,
    placement: 'dock' as const,
    scroll: { offset: 0, bodyRows: 60 },
    view: {},
  },
} as const

/** То, что в сессии отвечает движок: старт, команда, панель, тосты, часы, хранилище. */
export function engine(on: On) {
  const clock = mock.clock(on, { now: NOW })
  mock.store(on)
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('command.register', ($, e) => ({ value: { command: e.name } }))
  on('ui.open', () => ({ value: { isPlaced: true as const } }))
  on('ui.toast', () => ({ value: undefined }))

  return clock
}

function parent(path: string): string {
  return path.replace(/\/[^/]+$/, '') || '/'
}

/** Файловая система из памяти под `$.fs`: exists, stat, list и read; `reads` — прочитанные файлы. */
export function fakeFs(on: On, files: Files, mtimeMs = NOW - DAY) {
  const reads: string[] = []
  const dirs = new Set<string>(['/'])
  const texts = new Map<string, { text: string; mtimeMs: number }>()
  const addDirs = (dir: string) => {
    for (let at = dir; !dirs.has(at); at = parent(at)) dirs.add(at)
  }
  for (const [path, value] of Object.entries(files)) {
    if (path.endsWith('/')) {
      addDirs(path.slice(0, -1))
      continue
    }
    texts.set(path, typeof value === 'string' ? { text: value, mtimeMs } : value)
    addDirs(parent(path))
  }
  const missing = (path: string) => new Error(`ENOENT: ${path}`)

  on('fs.exists', ($, e) => ({ value: dirs.has(e.path) || texts.has(e.path) }))
  on('fs.stat', ($, e) => {
    const file = texts.get(e.path)
    if (file) return { value: { kind: 'file' as const, size: file.text.length, mtimeMs: file.mtimeMs, isLink: false } }
    if (dirs.has(e.path)) return { value: { kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false } }
    throw missing(e.path)
  })
  on('fs.list', ($, e) => {
    if (!dirs.has(e.path)) throw missing(e.path)
    const children = [...dirs, ...texts.keys()].filter(path => path !== e.path && parent(path) === e.path)

    return {
      value: children.map(path => {
        const file = texts.get(path)

        return {
          name: path.split('/').pop() ?? path,
          kind: file ? ('file' as const) : ('dir' as const),
          size: file?.text.length ?? 0,
          mtimeMs: file?.mtimeMs ?? 0,
          isLink: false,
        }
      }),
    }
  })
  on('fs.read', ($, e) => {
    const file = texts.get(e.path)
    if (!file) throw missing(e.path)
    reads.push(e.path)

    return { value: file.text }
  })

  return { reads }
}
