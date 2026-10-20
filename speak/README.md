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

`say` cleans the text first. Code blocks, tables, paths, commands, links and emoji are dropped, and bullets become sentences. Only the first `max_sentences` sentences are read, followed by "Rest is on screen." when more was cut. `say` returns at once and replies queue up in order.

`stop` ends the current reply and clears the queue. `mute` also stops. `replay` reads the last reply again, even while muted.

## Config

`~/.config/speak/config.toml` maps voice names to Pocket TTS voices and OpenCode models to voice names. A voice can be a built-in name like `alba` or `marius`, an `hf://` or `https://` URL, or an absolute path to a `.wav` or `.safetensors` file. Keep your own voice files in `~/.local/share/speak/voices`.

Local files are uploaded with each request, since the server does not load local paths. A `.safetensors` voice loads right away. A `.wav` voice is encoded on every request and needs the voice cloning weights, which are gated on Hugging Face.

`SPEAK_SERVER` overrides the server URL and `SPEAK_PLAYER` the player command (default `pw-play -`).

## State

Everything lives in `~/.local/state/speak/`: `state.json` (what the bar reads), the `muted` flag, the queue and `speak.log`. When the server is down, `say` still returns at once and the failure goes to the log.

## Bar

The Noctalia bar plugin `glow-speak` shows the state and has the mute, stop and replay actions.

<!-- speak-bar: click list goes here -->
