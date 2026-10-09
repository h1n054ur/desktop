import { describe, expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { AgentInfo, On, RenderElement } from 'claude-code'

import type { TabAgent } from '../types'
import { LINGER_MS, elapsed, merge, shortTokens } from '../hooks/tabs'

const listed = (id: string, status: AgentInfo['status'], description = `Task ${id}`): AgentInfo => ({
  id,
  description,
  status,
  type: 'general-purpose',
})

const none = new Map<string, number>()

describe('merging the agent list', () => {
  test('keeps the start time, stops the clock when an agent finishes', () => {
    const first = merge([], [listed('a', 'running')], 1_000, new Map([['a', 500]]), none)
    expect(first[0]).toMatchObject({ state: 'running', startedAt: 500 })
    expect(first[0]!.endedAt).toBeUndefined()
    const done = merge(first, [listed('a', 'completed')], 9_000, none, none)
    expect(done[0]).toMatchObject({ state: 'done', startedAt: 500, endedAt: 9_000 })
    expect(elapsed(done[0]!, 50_000)).toBe('8s')
  })

  test('an agent the engine dropped stays as done, then goes after the linger time', () => {
    const held = merge([], [listed('a', 'running')], 0, none, none)
    const dropped = merge(held, [], 5_000, none, none)
    expect(dropped[0]).toMatchObject({ state: 'done', endedAt: 5_000 })
    expect(merge(dropped, [], 5_000 + LINGER_MS, none, none)).toHaveLength(0)
  })

  test('maps engine states to tab states', () => {
    const tabs = merge(
      [],
      [listed('p', 'pending'), listed('w', 'waiting'), listed('i', 'idle'), listed('f', 'failed'), listed('k', 'killed')],
      0,
      none,
      none,
    )
    expect(tabs.map(t => t.state)).toEqual(['starting', 'waiting', 'waiting', 'failed', 'failed'])
  })

  test('takes the latest token count', () => {
    const tabs = merge([], [listed('a', 'running')], 0, none, new Map([['a', 45_210]]))
    expect(tabs[0]!.tokens).toBe(45_210)
    expect(shortTokens(45_210)).toBe('45k')
    expect(shortTokens(4_210)).toBe('4.2k')
    expect(shortTokens(1_250_000)).toBe('1.3M')
  })

  test('time reads as seconds, then minutes, then hours', () => {
    const a: TabAgent = { id: 'a', description: '', state: 'running', startedAt: 0, tokens: 0 }
    expect(elapsed(a, 42_000)).toBe('42s')
    expect(elapsed(a, 134_000)).toBe('2m14s')
    expect(elapsed(a, 3_720_000)).toBe('1h02m')
  })
})

function host(on: On, list: AgentInfo[]) {
  const clock = mock.clock(on)
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('ui.render', { component: 'AbovePrompt' }, ($h, e) => {
    const { Text } = $h.ui.resolve(e)
    return h(Text, { key: 'engine' }, 'engine band') as RenderElement
  })
  on('agent.list', () => ({ value: list }))
  return clock
}

const band = ($: Engine, agentId?: string) =>
  $.ui.mount({
    plugin: 'agent-tabs',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: {
      hasSurvey: false,
      isWorking: true,
      maxRows: 6,
      bodyColumns: 120,
      scroll: { offset: 0, bodyRows: 6 },
      view: agentId === undefined ? {} : { agentId },
    },
    viewport: { columns: 160, rows: 40, isFullscreen: true },
  })

describe('the band', () => {
  test('draws main and one tab per agent, with task, time and state', async ($, on) => {
    const clock = host(on, [listed('a1', 'running', 'Fix the login form'), listed('a2', 'failed', 'Migrate orders')])
    await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
    await clock.advance(65_000)
    const ui = await band($)
    expect((await ui.find({ key: 'tab-main' }))?.text).toContain('main')
    expect((await ui.find({ key: 'tab-a1' }))?.text).toContain('● Fix the login form 1m05s')
    expect((await ui.find({ key: 'tab-a2' }))?.text).toContain('✗ Migrate orders 0s')
    await ui.unmount()
  })

  test('the agent on screen gets the highlighted tab', async ($, on) => {
    host(on, [listed('a1', 'running')])
    await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
    const ui = await band($, 'a1')
    const boxes = await ui.findAll({ type: 'Box' })
    const bg = (key: string) => boxes.find(b => b.key === key)?.props.backgroundColor
    expect(bg('tab-a1')).toBe('claude')
    expect(bg('tab-main')).toBe('userMessageBackground')
    await ui.unmount()
  })

  test('nothing to show without agents', async ($, on) => {
    host(on, [])
    await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
    const ui = await band($)
    expect(await ui.find({ key: 'tab-main' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: 'engine band' })).toBeDefined()
    await ui.unmount()
  })
})
