import type { Card, Project, Status } from '../types'

type Raw = Record<string, unknown>

const STATUSES: readonly string[] = ['open', 'in_progress', 'blocked', 'closed']
// Эпики идут в список проектов, сообщения — переписка ролей, не работа.
const NOT_CARDS = new Set(['epic', 'message', 'molecule', 'gate', 'event'])

export function parseJson(stdout: string): unknown {
  try {
    return JSON.parse(stdout.trim())
  } catch {
    return undefined
  }
}

function priority(value: unknown): number {
  return typeof value === 'number' ? value : 2
}

export function toCards(data: unknown): Card[] {
  if (!Array.isArray(data)) return []

  return (data as Raw[]).flatMap(raw => {
    const status = String(raw.status ?? '')
    if (!STATUSES.includes(status) || NOT_CARDS.has(String(raw.issue_type ?? ''))) return []

    return [{
      id: String(raw.id ?? ''),
      title: String(raw.title ?? ''),
      status: status as Status,
      priority: priority(raw.priority),
      assignee: String(raw.assignee ?? ''),
      changedAt: String(raw.closed_at ?? raw.updated_at ?? raw.created_at ?? ''),
      path: '',
      dept: '',
      note: '',
    }]
  })
}

/** Строки `bd epic status --json`: эпик и счёт его детей. */
export function toProjects(data: unknown, dept: string, folder: string): Project[] {
  if (!Array.isArray(data)) return []

  return (data as Raw[]).flatMap(row => {
    const epic = row.epic as Raw | undefined
    if (!epic || epic.status === 'closed') return []

    return [{
      dept,
      folder,
      id: String(epic.id ?? ''),
      title: String(epic.title ?? ''),
      priority: priority(epic.priority),
      total: Number(row.total_children ?? 0),
      closed: Number(row.closed_children ?? 0),
    }]
  })
}
