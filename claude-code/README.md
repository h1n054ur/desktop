# Claude Code, h1n054ur style

Claude Code in the same palette as the rest of the desktop: dark `#06090a`, green `#39ff14` and cyan `#00e5ff` accents.

![A Claude Code session with the h1n054ur theme: task sidebar on the right, agent tabs above the prompt, status line below](https://gist.githubusercontent.com/h1n054ur/62088b2015b822272d51d9dc269ea478/raw/session.png)

| Part | File | What it does |
|---|---|---|
| Theme | [`themes/h1n054ur.json`](themes/h1n054ur.json) | A custom Claude Code theme from the Noctalia palette: text, borders, success and error colours, the prompt box, diffs, subagent colours. The built-in task list follows it too. |
| Status line | [`statusline.sh`](statusline.sh) | The starship prompt's segments and colours on one line (`[user@host]`, directory, git branch and status), then the model, context use, session time and clock. |
| Task sidebar | [`mods/task-sidebar`](mods/task-sidebar) | The session's task list as a pane docked on the right, grouped into running, pending, blocked and done. |
| Agent tabs | [`mods/agent-tabs`](mods/agent-tabs) | A tab bar above the prompt, one tab per agent: its task, how long it has run, its tokens and its state. The agent on screen gets the highlighted tab. |

| Task sidebar | Agent tabs (running, then done) |
|---|---|
| ![Task sidebar grouped into running, pending, blocked and done](https://gist.githubusercontent.com/h1n054ur/62088b2015b822272d51d9dc269ea478/raw/sidebar.png) | ![Agent tabs while two agents run, and after they finish](https://gist.githubusercontent.com/h1n054ur/62088b2015b822272d51d9dc269ea478/raw/agent-tabs.png) |

![Status line: user and host, repo, branch and status, model, context use, session time, clock](https://gist.githubusercontent.com/h1n054ur/62088b2015b822272d51d9dc269ea478/raw/statusline.png)

## Install

```bash
./install.sh
```

It links the theme and both mods into `~/.claude` (or `$CLAUDE_CONFIG_DIR`), then sets the theme, the status line and `CLAUDE_CODE_PLUGIN_DIRS` in `settings.json`, keeping a backup. It needs `jq`. Start a new Claude Code session afterwards.

The status line uses the same ANSI colour names as the starship config, so both come out in the terminal's own colours. Icons need a Nerd Font (CaskaydiaCove in kitty here).

## Notes

- The mods use the hooks API from Claude Code 2.1.295, which is still early access and may change between releases.
- Switching agents stays with Claude Code's own footer. A mod can see which agent is on screen but can't switch it, so the tabs follow your pick rather than make it.
