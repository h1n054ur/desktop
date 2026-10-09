import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { SidebarTask } from '../types'
import { counts, groups, parseTask, sameTasks } from './tasks'
import type { RowKind } from './tasks'

const PANE = 'task-sidebar'
const TITLE = 'Tasks'
const DOCK_COLUMNS = 44
const POLL_MS = 1500

const tasks = atom({ plugin: 'task-sidebar', key: 'tasks' } as const, [] as SidebarTask[])
const autoOpened = atom({ plugin: 'task-sidebar', key: 'autoOpened' } as const, false)

// Theme keys, so the sidebar follows the h1n054ur theme (or whichever theme is set)
const MARK_COLOR: Record<RowKind, string> = {
  running: 'claude',
  pending: 'inactive',
  blocked: 'warning',
  done: 'success',
}
const RULE_COLOR = 'subtle'
const RUNNING_BG = 'selectionBg'

async function taskDir($: EngineInterface): Promise<string> {
  const listId = (await $.env.get('CLAUDE_CODE_TASK_LIST_ID')) || (await $.session.id())
  const config =
    (await $.env.get('CLAUDE_CONFIG_DIR')) || `${(await $.env.get('HOME')) ?? ''}/.claude`
  return `${config.replace(/\/+$/, '')}/tasks/${listId}`
}

let signature = ''
let running: Promise<void> | undefined
let again = false
let autoAsked = false

async function load($: EngineInterface, force: boolean): Promise<void> {
  const dir = await taskDir($)
  const entries = await $.fs.list(dir).catch(() => [])
  const files = entries
    .filter(f => f.kind === 'file' && f.name.endsWith('.json') && !f.name.startsWith('.'))
    .sort((a, b) => a.name.localeCompare(b.name))
  const sig = `${dir}|${files.map(f => `${f.name}:${f.size}:${f.mtimeMs}`).join(',')}`
  if (!force && sig === signature) return
  signature = sig
  const found: SidebarTask[] = []
  for (const f of files) {
    const text = await $.fs.read(`${dir}/${f.name}`).catch(() => undefined)
    const task = text === undefined ? undefined : parseTask(text)
    if (task !== undefined) found.push(task)
  }
  await update($, tasks, held => (sameTasks(held, found) ? held : found))
}

async function refresh($: EngineInterface, force = false): Promise<void> {
  if (running !== undefined) {
    again = again || force
    return running
  }
  running = (async () => {
    try {
      await load($, force)
      while (again) {
        again = false
        await load($, true)
      }
    } finally {
      running = undefined
    }
  })()
  return running
}

async function autoOpen($: EngineInterface): Promise<void> {
  if (await read($, autoOpened)) return
  await update($, autoOpened, () => true)
  if ((await $.ui.panes()).some(p => p.id === PANE)) return
  await $.ui.open({ id: PANE, title: TITLE, columns: DOCK_COLUMNS })
}

async function toggle($: EngineInterface) {
  const isOpen = (await $.ui.panes()).some(p => p.id === PANE)
  if (isOpen) {
    await $.ui.close({ id: PANE })
    return { text: 'Task sidebar closed.' }
  }
  await refresh($, true)
  await $.ui.open({ id: PANE, title: TITLE, columns: DOCK_COLUMNS })
  return { text: 'Task sidebar opened.' }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command
      .register({ name: 'task-sidebar', description: 'Show or hide the task list sidebar' })
      .catch(() => undefined)
    await refresh($, true).catch(() => undefined)
    $.clock.every(POLL_MS, () => void refresh($).catch(() => undefined))
    return next(e)
  })

  on('command.run', { command: 'task-sidebar' }, async $ => toggle($))

  on('tool.call', { tool: 'TaskCreate' }, async ($, e, next) => {
    const ran = await next(e)
    await refresh($, true).catch(() => undefined)
    return ran
  }).catch(($, e, next) => next(e))
  on('tool.call', { tool: 'TaskUpdate' }, async ($, e, next) => {
    const ran = await next(e)
    await refresh($, true).catch(() => undefined)
    return ran
  }).catch(($, e, next) => next(e))
  on('tool.call', { tool: 'TaskList' }, async ($, e, next) => {
    const ran = await next(e)
    await refresh($, true).catch(() => undefined)
    return ran
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'PromptHint' }, ($, e, next) => {
    if (!autoAsked && e.viewport?.isFullscreen === true) {
      autoAsked = true
      $.clock.after(0, () => void autoOpen($).catch(() => undefined))
    }
    return next(e)
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const all = await read($, tasks)
    const width = Math.max(12, e.props.bodyColumns)
    const list = groups(all, width)
    const c = counts(all)
    const headLines = 2
    const lines = list.reduce((n, g) => n + 1 + g.rows.length, 0)
    const overflow = lines + headLines - e.props.scroll.bodyRows
    const hint =
      overflow > 0
        ? e.props.isFocused
          ? `↕ ${overflow} more · arrows scroll`
          : `↕ ${overflow} more · ctrl+x tab, then arrows`
        : ''

    return (
      <Box flexDirection="column">
        <Box key="header" flexDirection="row">
          <Text bold color="claude">
            {TITLE}{' '}
          </Text>
          <Text color={MARK_COLOR.running}>{c.running} running</Text>
          <Text color={RULE_COLOR}> · </Text>
          <Text color={MARK_COLOR.pending}>{c.pending} pending</Text>
          <Text color={RULE_COLOR}> · </Text>
          <Text color={MARK_COLOR.done} wrap="truncate-end">
            {c.done} done
          </Text>
        </Box>
        <Box key="hint">
          <Text color="inactive" dimColor wrap="truncate-end">
            {all.length === 0 ? 'No tasks yet.' : hint || ' '}
          </Text>
        </Box>
        {list.flatMap(g => [
          <Box key={`group-${g.kind}`} flexDirection="row">
            <Text color={RULE_COLOR}>─ </Text>
            <Text bold color={MARK_COLOR[g.kind]}>
              {g.title}
            </Text>
            <Text color={RULE_COLOR} wrap="truncate-end">
              {' '}
              {g.rule}
            </Text>
          </Box>,
          ...g.rows.map(r => (
            <Box
              key={`task-${r.id}`}
              flexDirection="row"
              backgroundColor={r.kind === 'running' ? RUNNING_BG : undefined}
            >
              <Text color={MARK_COLOR[r.kind]} dimColor={r.kind === 'done'}>
                {r.mark}{' '}
              </Text>
              <Text color={RULE_COLOR}>{r.label} </Text>
              <Text bold={r.kind === 'running'} dimColor={r.kind === 'done'} wrap="truncate-end">
                {r.subject}
              </Text>
              {r.suffix !== '' && (
                <Text color={r.kind === 'blocked' ? 'warning' : 'inactive'}>{r.suffix}</Text>
              )}
            </Box>
          )),
        ])}
      </Box>
    )
  })
}
