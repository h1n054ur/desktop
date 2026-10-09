import { describe, expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { FsEntry, On, RenderElement } from 'claude-code'

import type { SidebarTask } from '../types'
import { clip, groups, ordered, rows, toRow } from '../hooks/tasks'

const SESSION = 'sess-1'
const DIR = `/home/t/.claude/tasks/${SESSION}`

const task = (id: string, status: SidebarTask['status'], extra: Partial<SidebarTask> = {}): SidebarTask => ({
  id,
  subject: `Task ${id}`,
  status,
  blockedBy: [],
  ...extra,
})

function fakeDisk(on: On, initial: SidebarTask[]) {
  const files = new Map<string, { text: string; mtimeMs: number }>()
  let tick = 1
  const put = (t: SidebarTask) =>
    files.set(`${t.id}.json`, { text: JSON.stringify({ description: '', blocks: [], ...t }), mtimeMs: tick++ })
  initial.forEach(put)
  files.set('.lock', { text: '', mtimeMs: 0 })
  mock.env(on, { HOME: '/home/t' })
  on('session.id', () => ({ value: SESSION }))
  on('fs.list', (_$, e) => {
    if (e.path !== DIR) throw new Error('ENOENT')
    return {
      value: [...files].map(
        ([name, f]): FsEntry => ({ name, kind: 'file', size: f.text.length, mtimeMs: f.mtimeMs, isLink: false }),
      ),
    }
  })
  on('fs.read', (_$, e) => {
    const f = files.get(e.path.slice(DIR.length + 1))
    if (f === undefined) throw new Error('ENOENT')
    return { value: f.text }
  })
  return { put }
}

function fakeHost(on: On) {
  const opened: string[] = []
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  on('ui.panes', () => ({ value: [] }))
  on('ui.open', (_$, e) => {
    opened.push(e.id)
    return { value: { isPlaced: true as const } }
  })
  return { opened }
}

const start = ($: Engine) => $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })

const pane = ($: Engine, bodyRows = 30, bodyColumns = 40) =>
  $.ui.mount({
    plugin: 'task-sidebar',
    surface: 'terminal',
    component: 'Pane',
    requestId: 'task-sidebar',
    props: {
      title: 'Tasks',
      isFocused: false,
      bodyColumns,
      placement: 'dock',
      scroll: { offset: 0, bodyRows },
      view: {},
    },
    viewport: { columns: 160, rows: 40, isFullscreen: true },
  })

describe('ordering and rows', () => {
  test('running, then unblocked pending, then blocked, then done', () => {
    const all = [
      task('1', 'completed'),
      task('2', 'pending', { blockedBy: ['3'] }),
      task('3', 'in_progress'),
      task('4', 'pending'),
      task('5', 'pending', { blockedBy: ['1'] }),
      task('10', 'pending'),
    ]
    expect(ordered(all).map(t => t.id)).toEqual(['3', '4', '5', '10', '2', '1'])
  })

  test('a blocked task says what it waits for, only open blockers', () => {
    const all = [task('1', 'completed'), task('2', 'pending'), task('3', 'pending', { blockedBy: ['1', '2'] })]
    const row = toRow(all[2]!, all, 60)
    expect(row.kind).toBe('blocked')
    expect(row.mark).toBe('⧗')
    expect(row.suffix).toBe(' waits for #2')
  })

  test('long subjects are cut to the width with an ellipsis, owner kept', () => {
    const t = task('7', 'in_progress', { subject: 'x'.repeat(100), owner: 'alice' })
    const row = toRow(t, [t], 30)
    expect(row.suffix).toBe(' @alice')
    expect(row.subject.endsWith('…')).toBe(true)
    expect(Array.from(`${row.mark} ${row.label} ${row.subject}${row.suffix}`).length).toBe(30)
    expect(clip('short', 10)).toBe('short')
  })

  test('rows are grouped by kind under a titled rule', () => {
    const all = [task('1', 'completed'), task('2', 'in_progress'), task('3', 'pending'), task('4', 'pending')]
    const gs = groups(all, 30)
    expect(gs.map(g => g.title)).toEqual(['Running 1', 'Pending 2', 'Done 1'])
    expect(Array.from(`─ ${gs[1]!.title} ${gs[1]!.rule}`).length).toBe(30)
  })

  test('every task gets a row, however many', () => {
    const all = Array.from({ length: 50 }, (_, i) => task(String(i + 1), 'pending'))
    expect(rows(all, 30)).toHaveLength(50)
  })
})

describe('the pane', () => {
  test('draws the header counts and every task in order', async ($, on) => {
    fakeDisk(on, [task('1', 'completed'), task('2', 'in_progress', { owner: 'bob' }), task('3', 'pending', { blockedBy: ['2'] }), task('4', 'pending')])
    fakeHost(on)
    await start($)
    const ui = await pane($)
    expect((await ui.find({ key: 'header' }))?.text).toContain('1 running · 2 pending · 1 done')
    const keys = (await ui.findAll({ type: 'Box' })).map(b => b.key).filter(k => k?.startsWith('task-'))
    expect(keys).toEqual(['task-2', 'task-4', 'task-3', 'task-1'])
    expect((await ui.find({ key: 'task-2' }))?.text).toContain('● #2 Task 2 @bob')
    expect((await ui.find({ key: 'task-3' }))?.text).toContain('⧗ #3 Task 3 waits for #2')
    expect((await ui.find({ key: 'task-1' }))?.text).toContain('✓ #1')
    await ui.unmount()
  })

  test('more tasks than rows: all are drawn and the overflow is said', async ($, on) => {
    fakeDisk(on, Array.from({ length: 12 }, (_, i) => task(String(i + 1), 'pending')))
    fakeHost(on)
    await start($)
    const ui = await pane($, 6)
    const keys = (await ui.findAll({ type: 'Box' })).map(b => b.key).filter(k => k?.startsWith('task-'))
    expect(keys).toHaveLength(12)
    expect((await ui.find({ key: 'hint' }))?.text).toContain('↕ 9 more')
    await ui.unmount()
  })

  test('a TaskUpdate redraws the pane from the task files', async ($, on) => {
    const disk = fakeDisk(on, [task('1', 'pending'), task('2', 'pending', { blockedBy: ['1'] })])
    fakeHost(on)
    on('tool.call', (_$, e) => {
      if (e.tool === 'TaskUpdate') disk.put(task(e.taskId, 'completed'))
      return { result: { success: true, taskId: '1', updatedFields: ['status'] } }
    })
    await start($)
    const ui = await pane($)
    expect((await ui.find({ key: 'task-2' }))?.text).toContain('waits for #1')
    await $.tool.call({ tool: 'TaskUpdate', taskId: '1', status: 'completed' })
    expect((await ui.find({ key: 'task-1' }))?.text).toContain('✓ #1')
    expect((await ui.find({ key: 'task-2' }))?.text).toContain('○ #2')
    expect((await ui.find({ key: 'header' }))?.text).toContain('0 running · 1 pending · 1 done')
    await ui.unmount()
  })

  test('a change written elsewhere shows on the next poll', async ($, on) => {
    const clock = mock.clock(on)
    const disk = fakeDisk(on, [task('1', 'pending')])
    fakeHost(on)
    await start($)
    const ui = await pane($)
    disk.put(task('2', 'in_progress', { subject: 'Written by a teammate' }))
    await clock.advance(1600)
    expect((await ui.find({ key: 'task-2' }))?.text).toContain('● #2 Written by a teammate')
    await ui.unmount()
  })

  test('opens itself once when the terminal docks panes', async ($, on) => {
    const clock = mock.clock(on)
    fakeDisk(on, [])
    const host = fakeHost(on)
    on('ui.render', { component: 'PromptHint' }, ($h, e) => {
      const { Text } = $h.ui.resolve(e)
      return h(Text, {}, 'hint') as RenderElement
    })
    await start($)
    const hint = await $.ui.mount({
      plugin: 'task-sidebar',
      surface: 'terminal',
      component: 'PromptHint',
      props: { isDraft: false, isWorking: false, hint: '? for shortcuts' },
      viewport: { columns: 160, rows: 40, isFullscreen: true },
    })
    await clock.advance(10)
    expect(host.opened).toEqual(['task-sidebar'])
    await hint.unmount()
  })
})
