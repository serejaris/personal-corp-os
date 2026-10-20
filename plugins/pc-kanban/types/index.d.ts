export type Status = 'open' | 'in_progress' | 'blocked' | 'closed'

/** Откуда доска берёт задачи: граф bd или task-файлы отделов `tasks/*.md`. */
export type Kind = 'bd' | 'tasks'

export type Card = {
  /** bd — id бида; task-файл — имя файла без `.md`. */
  id: string
  title: string
  status: Status
  /** У task-файла приоритета нет: 2, как у бида без приоритета. */
  priority: number
  assignee: string
  changedAt: string
  /** Task-файл: путь к файлу и папка его отдела; у бида пусто. */
  path: string
  dept: string
  /** Статус из файла, когда колонка называет его иначе: «на приёмке», «снята». */
  note: string
}

export type Project = {
  dept: string
  folder: string
  /** bd — id эпика; у отдела с task-файлами пусто. */
  id: string
  title: string
  priority: number
  total: number
  closed: number
}

/** Что на доске: папка отдела и, если выбран, эпик bd. */
export type Source = { folder: string; dept: string; epicId: string; title: string }

export type Board = { kind: Kind; source: Source; cards: Card[]; error: string; loadedAt: number }

export type Projects = { kind: Kind; list: Project[]; failed: string[]; scanned: number; loadedAt: number }

declare module 'claude-code' {
  interface PluginState {
    'pc-kanban': {
      kind: Kind | null
      board: Board | null
      projects: Projects | null
      source: Source | null
      isLoading: boolean
      isAllProjects: boolean
    }
  }
}
