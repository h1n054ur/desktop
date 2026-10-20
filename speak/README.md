# speak

## Hooks

Agent replies are read aloud only when the turn answered a prompt you typed and that session's
kitty window is the focused window.

- `bin/speak-focused` exits 0 when the kitty window named by `KITTY_PID` and `KITTY_WINDOW_ID` is
  focused: kitty reports its OS window focused, its tab active and the window active, and under
  Hyprland the active window belongs to that kitty. It needs kitty remote control on
  `listen_on unix:@kitty-{kitty_pid}`, plus `jq`. It takes about 40 ms.
- `hooks/claude-stop.sh` is a Claude Code `Stop` hook. It stays quiet when `stop_hook_active` is
  set, when the last prompt did not come from a person (plugin prompts such as the auto "update",
  task notifications, slash commands), when the prompt is just "update", and when the window is
  not focused. Otherwise it sends `last_assistant_message` to
  `speak say --voice claude --source "claude-code: <folder>"`. Subagents fire `SubagentStop`, so
  they never speak. It prints nothing and always exits 0.
- `opencode/speak.ts` is an OpenCode plugin (V2 API). When a top-level session finishes a run
  that answered a typed prompt (not "update"), it checks focus, picks the voice with
  `speak voice-for <provider>/<model>` and calls `speak say --voice <voice> --source "opencode: <folder>"`.
  Child sessions and interrupted or failed runs stay quiet.

Claude Code settings (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "~/desktop/speak/hooks/claude-stop.sh", "timeout": 5 }
        ]
      }
    ]
  }
}
```

OpenCode loads the plugin from `~/.config/opencode/plugins/speak.ts` (a link made by `install.sh`).
