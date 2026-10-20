import type { Card, Project, Status } from '../types'

/** Что знает о задаче её task-файл: заголовок, статус словами и дата закрытия. */
export type TaskFile = { title: string; phrase: string; closedAt: string }

export type FileInfo = { path: string; name: string; dept: string; mtimeMs: number }

// Строка статуса: «Статус: в работе» из урока, «- Статус: новая» из шаблона отдела, «**Статус:** …».
const STATUS_LINE = /^(?:[-*+]\s+)?(?:статус|status)\s*:\s*(.*)$/i
const CLOSED_LINE = /^(?:[-*+]\s+)?(?:завершена|закрыта|принята|снята|closed|done)\s*:\s*(.*)$/i
const FENCE = /^\s*(```|~~~)/

// Слова статусов из шаблона отдела и уроков PC3. Незнакомый статус остаётся открытым.
const CLOSED = /^(заверш|принят|сделан|закрыт|снят|отмен|done|closed|accepted|complete|cancel|dropped)/
const BLOCKED = /^(заблок|блок|blocked)/
const ACTIVE = /^(в работе|на приемке|на проверке|in progress|in review|review|doing)/
// Так статус называет сама колонка: на карточке его не повторяем.
const PLAIN = new Set([
  'новая', 'новое', 'новый', 'открыта', 'открыто', 'new', 'open', 'todo',
  'в работе', 'in progress',
  'заблокирована', 'заблокировано', 'заблокирован', 'blocked',
  'завершена', 'завершено', 'завершен', 'done', 'closed',
])

const SUMMARY: readonly (readonly [Status, string])[] = [
  ['in_progress', 'в работе'],
  ['blocked', 'заблокировано'],
  ['open', 'открыто'],
]

/** Файлы `tasks/`, которые не задачи: описание папки, шаблон, скрытые. */
export function isTaskFile(name: string): boolean {
  return name.endsWith('.md') && !name.startsWith('_') && !name.startsWith('.') && name.toLowerCase() !== 'readme.md'
}

function normalize(text: string): string {
  return text.toLowerCase().replace(/ё/g, 'е').replace(/\s+/g, ' ').trim()
}

/** Статус до пояснения: «в работе — жду клиента» → «в работе». */
function cut(text: string): string {
  return (text.split(/\s[—–-]\s|[—–;,(]|\.\s|\.$/)[0] ?? '').trim()
}

/** Дата из `ГГГГ-ММ-ДД` или `ДД.ММ.ГГГГ`, иначе пусто. */
export function toIsoDate(text: string): string {
  const iso = /(\d{4})-(\d{2})-(\d{2})/.exec(text)
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`
  const ru = /(\d{1,2})\.(\d{1,2})\.(\d{4})/.exec(text)
  if (ru) return `${ru[3]}-${(ru[2] ?? '').padStart(2, '0')}-${(ru[1] ?? '').padStart(2, '0')}`

  return ''
}

export function toStatus(phrase: string): Status {
  const text = normalize(phrase)
  if (CLOSED.test(text) || /^готов[оаы]?$/.test(text)) return 'closed'
  if (BLOCKED.test(text)) return 'blocked'
  if (ACTIVE.test(text)) return 'in_progress'

  return 'open'
}

/** Файл без строки «Статус:» — не задача: файл дня, ретро, заметка. */
export function parseTask(text: string): TaskFile | undefined {
  let title = ''
  let phrase: string | undefined
  let closedAt = ''
  let isCode = false

  for (const raw of text.split('\n')) {
    if (FENCE.test(raw)) {
      isCode = !isCode
      continue
    }
    if (isCode) continue
    const line = raw.replace(/[*`]/g, '').trim()
    if (!title && /^#\s+/.test(line)) title = line.replace(/^#\s+/, '').trim()
    const status = phrase === undefined ? STATUS_LINE.exec(line) : null
    if (status) phrase = cut(status[1] ?? '')
    const closed = closedAt ? null : CLOSED_LINE.exec(line)
    if (closed) closedAt = toIsoDate(closed[1] ?? '')
  }

  return phrase === undefined ? undefined : { title, phrase, closedAt }
}

export function toTaskCard(text: string, file: FileInfo): Card | undefined {
  const task = parseTask(text)
  if (!task) return undefined
  const status = toStatus(task.phrase)
  const id = file.name.replace(/\.md$/, '')

  return {
    id,
    title: task.title || id,
    status,
    priority: 2,
    assignee: '',
    // Закрытой задаче дата из «Завершена:», остальным — когда файл правили.
    changedAt: (status === 'closed' && task.closedAt) || new Date(file.mtimeMs).toISOString(),
    path: file.path,
    dept: file.dept,
    note: !task.phrase || PLAIN.has(normalize(task.phrase)) ? '' : task.phrase,
  }
}

/** Что открыто в отделе: «в работе 1 · открыто 2». */
export function summary(cards: readonly Card[]): string {
  const parts = SUMMARY.flatMap(([status, word]) => {
    const n = cards.filter(card => card.status === status).length

    return n > 0 ? [`${word} ${n}`] : []
  })

  return parts.join(' · ') || 'всё закрыто'
}

/** Отдел в списке под доской: открытая работа словами и полоса закрытых задач. */
export function toDeptProject(cards: readonly Card[], dept: string, folder: string): Project | undefined {
  if (cards.length === 0) return undefined

  return {
    dept,
    folder,
    id: '',
    title: summary(cards),
    priority: 2,
    total: cards.length,
    closed: cards.filter(card => card.status === 'closed').length,
  }
}
