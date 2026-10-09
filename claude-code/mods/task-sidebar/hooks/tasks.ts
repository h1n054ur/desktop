import type { SidebarStatus, SidebarTask } from '../types'

export type RowKind = 'running' | 'pending' | 'blocked' | 'done'

export type Row = {
  id: string
  kind: RowKind
  mark: string
  label: string
  subject: string
  suffix: string
}

export type Counts = { running: number; pending: number; done: number }

const MARKS: Record<RowKind, string> = {
  running: '●',
  pending: '○',
  blocked: '⧗',
  done: '✓',
}

const STATUSES: readonly SidebarStatus[] = ['pending', 'in_progress', 'completed']

const byId = (a: SidebarTask, b: SidebarTask) => {
  const x = Number(a.id)
  const y = Number(b.id)
  if (Number.isFinite(x) && Number.isFinite(y) && x !== y) return x - y
  return a.id.localeCompare(b.id)
}

export function parseTask(text: string): SidebarTask | undefined {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return undefined
  }
  if (typeof raw !== 'object' || raw === null) return undefined
  const o = raw as Record<string, unknown>
  const status = o.status as SidebarStatus
  if (typeof o.id !== 'string' || typeof o.subject !== 'string') return undefined
  if (!STATUSES.includes(status)) return undefined
  const meta = o.metadata as Record<string, unknown> | undefined
  if (meta?._internal === true) return undefined
  const blockedBy = Array.isArray(o.blockedBy)
    ? o.blockedBy.filter((b): b is string => typeof b === 'string')
    : []
  const task: SidebarTask = { id: o.id, subject: o.subject, status, blockedBy }
  if (typeof o.owner === 'string' && o.owner !== '') task.owner = o.owner
  return task
}

export function openBlockers(task: SidebarTask, all: readonly SidebarTask[]): string[] {
  const done = new Set(all.filter(t => t.status === 'completed').map(t => t.id))
  const known = new Set(all.map(t => t.id))
  return task.blockedBy.filter(id => known.has(id) && !done.has(id))
}

export function kindOf(task: SidebarTask, all: readonly SidebarTask[]): RowKind {
  if (task.status === 'completed') return 'done'
  if (task.status === 'in_progress') return 'running'
  return openBlockers(task, all).length > 0 ? 'blocked' : 'pending'
}

const RANK: Record<RowKind, number> = { running: 0, pending: 1, blocked: 2, done: 3 }

export function ordered(all: readonly SidebarTask[]): SidebarTask[] {
  return [...all].sort((a, b) => RANK[kindOf(a, all)] - RANK[kindOf(b, all)] || byId(a, b))
}

export function counts(all: readonly SidebarTask[]): Counts {
  const c: Counts = { running: 0, pending: 0, done: 0 }
  for (const t of all) {
    if (t.status === 'in_progress') c.running += 1
    else if (t.status === 'completed') c.done += 1
    else c.pending += 1
  }
  return c
}

const chars = (s: string) => Array.from(s)

export function clip(text: string, width: number): string {
  const cs = chars(text.replace(/\s+/g, ' ').trim())
  if (cs.length <= width) return cs.join('')
  if (width <= 0) return ''
  return cs.slice(0, width - 1).join('') + '…'
}

export function toRow(task: SidebarTask, all: readonly SidebarTask[], width: number): Row {
  const kind = kindOf(task, all)
  const label = `#${task.id}`
  const parts: string[] = []
  if (kind === 'blocked') parts.push(`waits for ${openBlockers(task, all).map(id => `#${id}`).join(', ')}`)
  if (task.owner !== undefined) parts.push(`@${task.owner}`)
  const head = 2 + chars(label).length + 1
  let suffix = parts.length > 0 ? ` ${parts.join(' ')}` : ''
  const minSubject = Math.min(12, chars(task.subject).length)
  if (head + minSubject + chars(suffix).length > width) {
    suffix = clip(suffix, Math.max(0, width - head - minSubject))
    if (suffix !== '' && !suffix.startsWith(' ')) suffix = ` ${suffix}`
  }
  const subject = clip(task.subject, Math.max(1, width - head - chars(suffix).length))
  return { id: task.id, kind, mark: MARKS[kind], label, subject, suffix }
}

export function rows(all: readonly SidebarTask[], width: number): Row[] {
  return ordered(all).map(t => toRow(t, all, width))
}

const GROUP_NAME: Record<RowKind, string> = {
  running: 'Running',
  pending: 'Pending',
  blocked: 'Blocked',
  done: 'Done',
}

export type Group = { kind: RowKind; title: string; rule: string; rows: Row[] }

// Rows split by kind, each group under a title line "─ Running 2 ──────" cut to the width
export function groups(all: readonly SidebarTask[], width: number): Group[] {
  const out: Group[] = []
  for (const row of rows(all, width)) {
    const last = out[out.length - 1]
    if (last !== undefined && last.kind === row.kind) last.rows.push(row)
    else out.push({ kind: row.kind, title: '', rule: '', rows: [row] })
  }
  for (const g of out) {
    g.title = `${GROUP_NAME[g.kind]} ${g.rows.length}`
    g.rule = '─'.repeat(Math.max(0, width - chars(g.title).length - 3))
  }
  return out
}

export function sameTasks(a: readonly SidebarTask[], b: readonly SidebarTask[]): boolean {
  return JSON.stringify(a) === JSON.stringify(b)
}
