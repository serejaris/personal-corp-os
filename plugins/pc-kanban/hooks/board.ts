import type { Card, Project, Status } from '../types'

const DAY = 86_400_000

export const COLUMNS: readonly { status: Status; title: string }[] = [
  { status: 'open', title: 'Открыто' },
  { status: 'in_progress', title: 'В работе' },
  { status: 'blocked', title: 'Заблокировано' },
  { status: 'closed', title: 'Готово за 7 дней' },
]

// Карточка — рамка в две строки, строка с id и строка заголовка.
const CARD_ROWS = 4

/** Карточек в колонке столько, чтобы список проектов под доской остался в панели. */
export function cardsPerColumn(bodyRows: number, perRow: number, belowRows: number): number {
  const most = perRow === 4 ? 6 : 4
  if (!bodyRows) return most
  const rowsOfColumns = Math.ceil(COLUMNS.length / perRow)
  // шапка с отступом, заголовок и «+ ещё» у каждого ряда колонок, отступы между рядами
  const fixed = 2 + rowsOfColumns * 3 + belowRows
  const fit = Math.floor((bodyRows - fixed) / rowsOfColumns / CARD_ROWS)

  return Math.max(1, Math.min(most, fit))
}

export function columns(cards: readonly Card[], now: number) {
  const since = now - 7 * DAY

  return COLUMNS.map(col => {
    const list = cards.filter(card => card.status === col.status)
    const sorted = col.status === 'closed'
      ? list.filter(card => Date.parse(card.changedAt) >= since).sort((a, b) => b.changedAt.localeCompare(a.changedAt))
      : list.sort((a, b) => a.priority - b.priority || b.changedAt.localeCompare(a.changedAt))

    return { ...col, cards: sorted }
  })
}

/** Сначала важные, среди равных — где больше незакрытой работы. */
export function sortProjects(list: readonly Project[]): Project[] {
  return [...list].sort((a, b) =>
    a.priority - b.priority || (b.total - b.closed) - (a.total - a.closed) || a.dept.localeCompare(b.dept),
  )
}

export function bar(closed: number, total: number, width = 8): string {
  const full = total > 0 ? Math.round((closed / total) * width) : 0

  return '▰'.repeat(full) + '▱'.repeat(width - full)
}

export function ago(ms: number): string {
  const min = Math.floor(ms / 60_000)
  if (min < 1) return 'только что'
  if (min < 60) return `${min} мин назад`
  const hours = Math.floor(min / 60)

  return hours < 24 ? `${hours} ч назад` : `${Math.floor(hours / 24)} дн назад`
}

/** Форма слова по числу: 1 эпик, 2 эпика, 5 эпиков. */
export function plural(n: number, forms: readonly [string, string, string]): string {
  const mod10 = n % 10
  const mod100 = n % 100
  if (mod10 === 1 && mod100 !== 11) return forms[0]
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return forms[1]

  return forms[2]
}

export function short(text: string, max: number): string {
  return text.length > max ? `${text.slice(0, max - 1)}…` : text
}

export function baseName(folder: string): string {
  return folder.split('/').filter(Boolean).pop() ?? folder
}

export function parentOf(folder: string): string {
  return folder.replace(/\/+[^/]+\/*$/, '') || '/'
}

/** Путь для промпта: от папки сессии, к соседнему отделу через `../`. */
export function relative(path: string, from: string): string {
  if (path.startsWith(`${from}/`)) return path.slice(from.length + 1)
  const up = parentOf(from)
  if (up !== '/' && path.startsWith(`${up}/`)) return `../${path.slice(up.length + 1)}`

  return path
}

/** Не больше `limit` вызовов сразу: через ssh-туннель параллельные bd рвутся. */
export async function pool<T, R>(items: readonly T[], limit: number, fn: (item: T) => Promise<R>): Promise<R[]> {
  const out: R[] = []
  let next = 0
  const worker = async () => {
    while (next < items.length) {
      const index = next++
      out[index] = await fn(items[index] as T)
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker))

  return out
}
