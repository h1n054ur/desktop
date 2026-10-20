# speak

Reads coding agent replies aloud on the desktop. It runs [Pocket TTS](https://github.com/kyutai-labs/pocket-tts) locally on the CPU, so nothing leaves the machine.

A reply is spoken only when it answers a prompt you typed and that agent's terminal window has focus. Each model gets its own voice. Speech starts about a fifth of a second after the reply ends and streams as it is made.

## Install

```sh
uv tool install pocket-tts
./install.sh
systemctl --user enable --now speak-tts
```

`install.sh` links `speak` into `~/.local/bin`, links the `speak-tts` user unit and copies `config.example.toml` to `~/.config/speak/config.toml` if there is none yet. The server listens on `127.0.0.1:8777` and runs at low priority with a memory cap.

## Use

```sh
echo "All tests pass." | speak say --voice claude --source "claude-code: desktop"
speak voice-for anthropic/claude-opus    # prints claude
speak mute | unmute | toggle | stop | replay
speak status --json
```

`say` cleans the text first. Code blocks, tables, emoji and lines that are only paths, commands or links are dropped, and bullets become sentences. A path, command or link inside a sentence becomes "the file", "the command" or "the link", so the sentence still reads well. Only the first `max_sentences` sentences are read, followed by "Rest is on screen." when more was cut. `say` returns at once and replies queue up in order.

`say` never says the same reply twice. With `--id <reply id>` it drops a reply whose id it already saw in the last day, also when several processes call it at once (one marker per id under `ids/`). It also drops the same text from the same source within 30 seconds.

`stop` ends the current reply and clears the queue. `mute` also stops. `replay` reads the last reply again, even while muted.

## Config

`~/.config/speak/config.toml` maps voice names to Pocket TTS voices and OpenCode models to voice names. A voice can be a built-in name like `alba` or `marius`, an `hf://` or `https://` URL, or an absolute path to a `.wav` or `.safetensors` file. Keep your own voice files in `~/.local/share/speak/voices`.

Local files are uploaded with each request, since the server does not load local paths. A `.safetensors` voice loads right away. A `.wav` voice is encoded on every request and needs the voice cloning weights, which are gated on Hugging Face.

`SPEAK_SERVER` overrides the server URL and `SPEAK_PLAYER` the player command (default `pw-play -`).

## State

Everything lives in `~/.local/state/speak/`: `state.json` (what the bar reads), the `muted` flag, the queue and `speak.log`. When the server is down, `say` still returns at once and the failure goes to the log.

## Bar

The Noctalia bar plugin `glow-speak` shows the state and has the mute, stop and replay actions.

Left click mutes or unmutes, right click stops the current reply, middle click replays the last one. The icon is dim when idle, pulses while speaking and shows the mute mark when muted.

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
  `speak say --voice claude --source "claude-code: <folder>" --id claude:<session>:<hash>`. Subagents fire `SubagentStop`, so
  they never speak. It prints nothing and always exits 0.
- `opencode/speak.ts` is an OpenCode plugin (V2 API). When a top-level session finishes a run
  that answered a typed prompt (not "update"), it checks focus, picks the voice with
  `speak voice-for <provider>/<model>` and calls
  `speak say --voice <voice> --source "opencode: <folder>" --id opencode:<message id>`.
  Child sessions and interrupted or failed runs stay quiet. OpenCode runs the plugin setup once
  per open folder and each copy sees every event, so the copies share one dedupe state in the
  process and the `--id` covers the rest.

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
