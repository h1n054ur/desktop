import type { AgentStatus } from 'claude-code'

import type { TabAgent, TabState } from '../types'

// A finished agent keeps its tab this long, then drops off
export const LINGER_MS = 60_000

export type Listed = { id: string; description: string; status: AgentStatus }

export function stateOf(status: AgentStatus): TabState {
  switch (status) {
    case 'pending':
      return 'starting'
    case 'running':
      return 'running'
    case 'waiting':
    case 'idle':
      return 'waiting'
    case 'completed':
      return 'done'
    case 'failed':
    case 'killed':
      return 'failed'
  }
}

const isOver = (s: TabState) => s === 'done' || s === 'failed'

// Folds the engine's agent list into the tabs: keeps start times, stops the clock of a finished agent,
// remembers agents the engine already dropped until they have lingered long enough
export function merge(
  held: readonly TabAgent[],
  listed: readonly Listed[],
  now: number,
  spawnedAt: ReadonlyMap<string, number>,
  tokens: ReadonlyMap<string, number>,
): TabAgent[] {
  const before = new Map(held.map(a => [a.id, a]))
  const seen = new Set<string>()
  const out: TabAgent[] = []
  for (const l of listed) {
    seen.add(l.id)
    const old = before.get(l.id)
    const state = stateOf(l.status)
    const a: TabAgent = {
      id: l.id,
      description: l.description,
      state,
      startedAt: old?.startedAt ?? spawnedAt.get(l.id) ?? now,
      tokens: tokens.get(l.id) ?? old?.tokens ?? 0,
    }
    if (isOver(state)) a.endedAt = old?.endedAt ?? now
    out.push(a)
  }
  for (const old of held) {
    if (seen.has(old.id)) continue
    out.push(old.endedAt === undefined ? { ...old, state: isOver(old.state) ? old.state : 'done', endedAt: now } : old)
  }
  return out.filter(a => a.endedAt === undefined || now - a.endedAt < LINGER_MS)
}

export function sameAgents(a: readonly TabAgent[], b: readonly TabAgent[]): boolean {
  return JSON.stringify(a) === JSON.stringify(b)
}

export function elapsed(a: TabAgent, now: number): string {
  const s = Math.max(0, Math.floor(((a.endedAt ?? now) - a.startedAt) / 1000))
  if (s < 60) return `${s}s`
  const m = Math.floor(s / 60)
  if (m < 60) return `${m}m${String(s % 60).padStart(2, '0')}s`
  return `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}m`
}

export function shortTokens(n: number): string {
  if (n < 1000) return String(n)
  if (n < 1_000_000) return `${(n / 1000).toFixed(n < 10_000 ? 1 : 0)}k`
  return `${(n / 1_000_000).toFixed(1)}M`
}

export const MARKS: Record<TabState, string> = {
  starting: '◌',
  running: '●',
  waiting: '◐',
  done: '✓',
  failed: '✗',
}

export function clip(text: string, width: number): string {
  const cs = Array.from(text.replace(/\s+/g, ' ').trim())
  if (cs.length <= width) return cs.join('')
  if (width <= 1) return '…'
  return cs.slice(0, width - 1).join('') + '…'
}

export function meta(a: TabAgent, now: number): string {
  return a.tokens > 0 ? `${elapsed(a, now)} · ${shortTokens(a.tokens)}` : elapsed(a, now)
}
