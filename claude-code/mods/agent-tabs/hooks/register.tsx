import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { TabAgent, TabState } from '../types'
import { MARKS, clip, merge, meta, sameAgents } from './tabs'

const TICK_MS = 1000
const DESCRIPTION_COLUMNS = 28

const agents = atom({ plugin: 'agent-tabs', key: 'agents' } as const, [] as TabAgent[])
const now = atom({ plugin: 'agent-tabs', key: 'now' } as const, 0)

// Theme keys, so the tabs follow the h1n054ur theme (or whichever theme is set)
const MARK_COLOR: Record<TabState, string> = {
  starting: 'inactive',
  running: 'claude',
  waiting: 'warning',
  done: 'success',
  failed: 'error',
}
const ACTIVE_BG = 'claude'
const ACTIVE_FG = 'inverseText'
const TAB_BG = 'userMessageBackground'

// Kept outside $.state: only the merge reads them, and a reload starting them empty costs one tick
const spawnedAt = new Map<string, number>()
const tokens = new Map<string, number>()

let ticking: Promise<void> | undefined

async function tick($: EngineInterface): Promise<void> {
  if (ticking !== undefined) return ticking
  ticking = (async () => {
    try {
      const t = await $.clock.now()
      const listed = await $.agent.list()
      await update($, agents, held => {
        const next = merge(held, listed, t, spawnedAt, tokens)
        return sameAgents(held, next) ? held : next
      })
      if ((await read($, agents)).some(a => a.endedAt === undefined)) await update($, now, () => t)
    } finally {
      ticking = undefined
    }
  })()
  return ticking
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await tick($).catch(() => undefined)
    $.clock.every(TICK_MS, () => void tick($).catch(() => undefined))
    return next(e)
  })

  on('agent.spawn', async ($, e, next) => {
    const r = await next(e)
    if ('agentId' in r && r.agentId !== undefined) {
      spawnedAt.set(r.agentId, await $.clock.now())
      await tick($).catch(() => undefined)
    }
    return r
  }).catch(($, e, next) => next(e))

  // An agent's tokens: its latest model call's context plus what it wrote, as the footer counts them
  on('turn.step', async function* ($, e, next) {
    const r = yield* next(e)
    const u = r?.usage
    if (e.agentId !== undefined && u != null) {
      tokens.set(
        e.agentId,
        u.input_tokens + u.cache_read_input_tokens + u.cache_creation_input_tokens + u.output_tokens,
      )
    }
    return r
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const all = await read($, agents)
    if (e.props.hasSurvey || all.length === 0) return next(e)
    const t = (await read($, now)) || (await $.clock.now())
    const viewed = e.props.view.agentId
    const { Box, Text } = $.ui.resolve(e)

    const tab = (key: string, isActive: boolean, body: JSX.Element[]) => (
      <Box key={key} flexDirection="row" paddingX={1} backgroundColor={isActive ? ACTIVE_BG : TAB_BG}>
        {body}
      </Box>
    )

    return (
      <Box flexDirection="row" flexWrap="wrap" columnGap={1}>
        {tab('tab-main', viewed === undefined, [
          <Text key="label" bold color={viewed === undefined ? ACTIVE_FG : 'text'}>
            main
          </Text>,
        ])}
        {all.map(a => {
          const isActive = viewed === a.id
          const isOver = a.endedAt !== undefined
          return tab(`tab-${a.id}`, isActive, [
            <Text key="mark" color={isActive ? ACTIVE_FG : MARK_COLOR[a.state]}>
              {MARKS[a.state]}{' '}
            </Text>,
            <Text key="label" bold={isActive} dimColor={isOver && !isActive} color={isActive ? ACTIVE_FG : 'text'}>
              {clip(a.description || a.id, DESCRIPTION_COLUMNS)}{' '}
            </Text>,
            <Text key="meta" color={isActive ? ACTIVE_FG : 'inactive'}>
              {meta(a, t)}
            </Text>,
          ])
        })}
      </Box>
    )
  })
}
