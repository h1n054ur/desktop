# speak

Reads coding agent replies aloud on the desktop. It runs [Pocket TTS](https://github.com/kyutai-labs/pocket-tts) locally on the CPU, so nothing leaves the machine.

Every reply to a prompt you typed is spoken, whether its window has focus or not. A reply from a window you are not looking at starts with where it came from, such as "Workspace 3, Codex in desktop." Each model gets its own voice. Speech starts about a fifth of a second after the reply ends and streams as it is made.

## Install

```sh
uv tool install pocket-tts
./install.sh
systemctl --user enable --now speak-tts
```

`install.sh` links `speak` into `~/.local/bin`, links the `speak-tts` user unit and copies `config.example.toml` to `~/.config/speak/config.toml` if there is none yet. The server listens on `127.0.0.1:8777` and runs at low priority with a memory cap.

## Use

```sh
echo "All tests pass." | speak say --voice claude --source "claude-code: desktop" --intro "Workspace 3, Claude in desktop."
speak voice-for anthropic/claude-opus    # prints claude
echo "**Ada:** Done." | speak voice-from-reply --tool claude --session <id>   # {"voice": "ada", "name": "Ada", "from": "label"}
speak mute | unmute | toggle | stop | replay
speak status --json
```

`say` cleans the text first. Code blocks, tables, emoji and lines that are only paths, commands or links are dropped, and bullets become sentences. A path, command or link inside a sentence becomes "the file", "the command" or "the link", so the sentence still reads well. Only the first `max_sentences` sentences are read, followed by "Rest is on screen." when more was cut. `say` returns at once and replies queue up in order.

`--intro` is read before the reply as it is, without cleaning. The bar and `replay` keep only the reply.

`--strip-label` leaves a leading name label (see Config) out of the speech. The bar still shows the whole reply with the label.

`say` never says the same reply twice. With `--id <reply id>` it drops a reply whose id it already saw in the last day, also when several processes call it at once (one marker per id under `ids/`). It also drops the same text from the same source within 30 seconds.

`stop` ends the current reply and clears the queue. `mute` also stops. `replay` reads the last reply again, even while muted.

## Config

`~/.config/speak/config.toml` maps voice names to Pocket TTS voices and OpenCode models to voice names. A voice can be a built-in name like `alba` or `marius`, an `hf://` or `https://` URL, or an absolute path to a `.wav` or `.safetensors` file. Keep your own voice files in `~/.local/share/speak/voices`.

Local files are uploaded with each request, since the server does not load local paths. A `.safetensors` voice loads right away. A `.wav` voice is encoded on every request and needs the voice cloning weights, which are gated on Hugging Face.

Name labels: when a reply starts with `**Name:**`, `**Name**:` or `Name:` and the name (in any case) is a key in `[voices]`, that voice reads it and the label is not read out. Anything else at the start, or a label further in, is read as it is. A reply without a label can still get a voice: `[labels] state_dir` names a folder of `<tool>-<session>.json` files of the form `{"persona": "ada"}`, written by whatever picks a name per session. `tool` is `claude` or `opencode`. `speak voice-from-reply --tool <tool> --session <id>` does this lookup for both hooks and prints the voice and name as JSON, or `{}` when neither is found. `[labels] enabled = false` turns it all off.

```toml
[voices]
ada = "alba"

[labels]
enabled = true
state_dir = "~/.local/state/names/sessions"
```

`SPEAK_SERVER` overrides the server URL and `SPEAK_PLAYER` the player command (default `pw-play -`).

## State

Everything lives in `~/.local/state/speak/`: `state.json` (what the bar reads), the `muted` flag, the queue and `speak.log`. When the server is down, `say` still returns at once and the failure goes to the log.

## Bar

The Noctalia bar plugin `glow-speak` shows the state and has the mute, stop and replay actions.

Left click mutes or unmutes, right click stops the current reply, middle click replays the last one. The icon is dim when idle, pulses while speaking and shows the mute mark when muted.

## Hooks

Every reply that answers a prompt you typed is read aloud. The auto "update" prompts and other prompts that did not come from a person stay quiet, and so do subagents, child sessions and Claude Code runs nobody is typing in (`claude -p` and SDK runs). `SPEAK_OFF=1` in the environment of Claude Code or of the OpenCode service keeps them quiet too. When the reply's window is not the focused one, an intro goes first: "Workspace 3, Claude in desktop." The label is the name from the reply's name label or the session's saved name (see Config). Without one it is "Claude" for Claude Code, and for OpenCode the voice name, or the short model name when the model has the default voice. The last part is the project folder. When the workspace cannot be found the intro is just "Claude in desktop."

- `bin/speak-where` prints the intro, or nothing when the window is focused, and always exits 0.
  It takes `--kitty-pid`, `--kitty-window`, `--agent claude|opencode`, `--voice`, `--model`,
  `--name` and `--project`. A non-empty `--name` is the label. Focused means kitty reports the OS window focused, its tab active and the window
  active and focused, and under Hyprland the active window belongs to that kitty. One kitty
  process can own several OS windows, so it finds the OS window that holds the kitty window with
  `kitten @ ls`, then the Hyprland client of that kitty whose title matches, and reads its
  workspace. A named workspace is read by its name. It needs kitty remote control on
  `listen_on unix:@kitty-{kitty_pid}`, plus `jq`, and takes about 40 ms.
- `hooks/claude-stop.sh` is a Claude Code `Stop` hook. It stays quiet when `stop_hook_active` is
  set, when the last prompt did not come from a person (plugin prompts such as the auto "update",
  task notifications, slash commands), when the prompt is just "update", and when the session
  is not interactive. Claude Code marks every transcript entry with an `entrypoint`, also set in
  `CLAUDE_CODE_ENTRYPOINT`: `cli` for the interactive CLI and `sdk-cli` for `claude -p` (also
  when started from inside an interactive session), `sdk-ts` or `sdk-py` for SDK runs. The hook
  reads it from the prompt's entry, else from the environment, and speaks only `cli` or no
  entrypoint at all. Otherwise it picks the voice and name with `speak voice-from-reply`, asks
  `speak-where` with the session's `KITTY_PID` and `KITTY_WINDOW_ID` and sends
  `last_assistant_message` to `speak say --voice <voice, else claude> --source "claude-code: <folder>"
  --id claude:<session>:<hash> --intro <intro> --strip-label`. Subagents fire `SubagentStop`, so they never
  speak. It prints nothing and always exits 0.
- `opencode/speak.ts` is an OpenCode plugin (V2 API). When a top-level session finishes a run
  that answered a typed prompt (not "update"), it picks the voice with
  `speak voice-from-reply --tool opencode --session <session id>`, else
  `speak voice-for <provider>/<model>`, asks `speak-where` and calls
  `speak say --voice <voice> --source "opencode: <folder>" --id opencode:<message id> --strip-label --intro <intro>`.
  Sessions from `opencode run` are spoken like any other: the session tells the plugin nothing
  about which kind of client started it.
  Child sessions and interrupted or failed runs stay quiet. OpenCode runs the plugin setup once
  per open folder and each copy sees every event, so the copies share one dedupe state in the
  process and the `--id` covers the rest.
- The plugin runs inside the background `opencode serve --service` process, so its own kitty
  variables belong to whatever started the service. It looks for the TUI that shows the session
  instead: every `opencode` process that is not another command, read from `/proc` (only
  `KITTY_PID`, `KITTY_WINDOW_ID` and `HYPRLAND_INSTANCE_SIGNATURE` are read from its
  environment). A TUI started with `--session <id>` for this session wins, else the one TUI whose
  working folder is the session's folder. OpenCode 2.0.26 gives plugins no way to ask which
  session a TUI has open, so two TUIs in the same folder count as unknown: the reply gets the
  intro without the workspace.

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
