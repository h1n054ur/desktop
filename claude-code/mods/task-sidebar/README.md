# task-sidebar

A Claude Code mod that shows the session's task list as a full-height pane docked on the right of the transcript,
instead of the few lines Claude Code draws above the prompt.

![The task sidebar in the h1n054ur theme](https://gist.githubusercontent.com/h1n054ur/62088b2015b822272d51d9dc269ea478/raw/sidebar.png)

## What it shows

```
Tasks 2 running · 3 pending · 2 done

─ Running 2 ────────────────────────
● #4 Wire the export button   @alice
● #7 Write migration for orders
─ Pending 2 ────────────────────────
○ #5 Add empty state to report page
○ #9 Update the changelog
─ Blocked 1 ────────────────────────
⧗ #6 Release notes waits for #4
─ Done 2 ───────────────────────────
✓ #1 Scaffold the module
✓ #2 Add the schema
```

- One task per line, grouped under a titled rule with its count, top to bottom: running (●, bold on a tinted row), then pending (○), then blocked (⧗, with what it waits for), then done
  (✓, dimmed) at the bottom. Within a group, by id.
- A task is blocked while any task in its `blockedBy` is still open. Once the blocker is done it moves up to pending.
- The subject is cut to the pane's width with an ellipsis. The owner (`@name`) and "waits for #n" stay visible.
- The header counts running, pending and done tasks. When there are more tasks than rows, the line under the header
  says how many are below. Every task is still drawn and the pane scrolls: focus it with `ctrl+x tab`, then use the
  arrow keys.
- Colours are theme keys (`claude`, `warning`, `success`, `inactive`, `subtle`), so it follows whichever theme is set,
  light or dark.

## Where it gets the tasks

Claude Code keeps the task list as one JSON file per task under `~/.claude/tasks/<list id>/`. The list id is the
session id, or `CLAUDE_CODE_TASK_LIST_ID` when that's set, and the config folder follows `CLAUDE_CONFIG_DIR`. The mod
reads that folder:

- when the session starts,
- right after every `TaskCreate`, `TaskUpdate` and `TaskList` call (from the main agent or a subagent), and
- every 1.5 seconds, when a file's size or modified time has changed. This catches teammates or other sessions
  writing to the same list.

The plugin API has no call that lists tasks directly, so reading the files is the only way to see the whole list,
including owners and blockers.

## Opening and closing it

- In the fullscreen terminal layout the pane opens by itself the first time the session draws, if the terminal is at
  least 144 columns wide. On a narrower terminal it waits until the terminal gets wider. It does not open by itself on
  the main-screen layout, where it would sit above the prompt instead of beside the transcript.
- `/task-sidebar` shows or hides it at any width. The name isn't `/tasks` because Claude Code already has a `/tasks`
  command (background tasks), and a plugin can't replace a built-in command.
- `ctrl+x x` or the close mark also closes it.

## The built-in task list

The mod can't hide the list Claude Code draws above the prompt. The plugin API only lets a mod redraw certain
components through `ui.render`, and the task list isn't one of them in Claude Code 2.1.294. Press `ctrl+t` to hide it
yourself. If a later release adds that component, the mod can draw nothing there.

## Install

```
/plugin install task-sidebar --marketplace <owner>/<repo>
```

Answer `y` to add the marketplace, then pick a scope (user scope loads it in every session).

To try it from a local folder without installing:

```
claude --plugin-dir /path/to/task-sidebar
```

or set `CLAUDE_CODE_PLUGIN_DIRS=/path/to/task-sidebar` in the environment or in the `env` block of
`~/.claude/settings.json`.

## Development

```
claude plugin validate .
claude plugin test .
tsc -p .            # once Claude Code has loaded the mod and written .claude-plugin/types/
```

The ordering and formatting logic is in `hooks/tasks.ts`. The hooks (pane, command, tool calls, polling) are in
`hooks/register.tsx`. The tests in `tests/sidebar.test.ts` cover ordering, blocked rows, overflow, the `TaskUpdate`
refresh, the poll and the auto-open.
