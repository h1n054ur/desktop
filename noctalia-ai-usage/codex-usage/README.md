# Codex Usage for Noctalia

Your ChatGPT plan limits for Codex in the [Noctalia](https://github.com/noctalia-dev/noctalia) bar: how much of the 5-hour and weekly windows you have used, and when each one resets. It sits next to [Claude Sessions](../claude-sessions/README.md) and looks the same, but shows limits only (no sessions).

It reads the ChatGPT sign-in that [OpenCode](https://opencode.ai) already keeps, so there is nothing extra to log in to.

## What it shows

- On the bar: the OpenAI icon, then a meter and a percentage per window. The colour turns amber from 70% and red from 90%.
- Hover: every window with its reset countdown, and when the numbers were last fetched.
- Click: a floating panel with one meter per window, the reset times, your plan name (Plus, Pro and so on) and any error.
- Right-click: fetch fresh numbers now (at most once every 30 seconds).
- Extra windows that ChatGPT reports (for example a per-model limit) show up in the panel, and on the bar when `Bar limits` is set to all windows.

If a fetch fails, the bar keeps the last numbers it had and the panel says how old they are. The icon only turns red when there is nothing to show.

## Sign in first

The widget needs OpenCode signed in to ChatGPT with the Codex browser method:

```sh
opencode auth login openai --method chatgpt-browser
```

OpenCode's default "Sign in with ChatGPT" works for chatting, but its token is only accepted by the Responses API. The usage endpoint refuses it (HTTP 401), so with that sign-in the panel tells you to run the command above. The Codex browser sign-in (and the headless one, `chatgpt-headless`) can read usage.

## Install

The widget comes from the same plugin source as Claude Sessions. See the [install steps](../README.md#install) in the top README, then add it to a bar:

```toml
[widget.codex]
type = "hani/codex-usage:bar"

[bar.default]
start = [ "workspaces", "claude", "codex" ]
```

Requirements: OpenCode signed in as above, `sqlite3`, `jq` and `curl`.

## Settings

| Setting | Default | What it does |
|---|---|---|
| Bar limits | 5-hour window | Which windows the bar shows: 5-hour, 7-day, both, all, or hidden (icon only) |
| Bar limits style | Linear bar | A small bar or a ring for each window |

## What it reads and sends

- OpenCode's credential row for OpenAI in `~/.local/share/opencode/opencode.db` (the active `openai` row of the `credential` table). The database is opened read-only, and no other row or file is read.
- The access token goes to `curl` on stdin, so it never shows in the process list. It is never printed, logged or written to disk.
- The widget never refreshes the token. OpenCode owns it and refreshes it when you use OpenCode. If it has expired, the panel says so until OpenCode refreshes it.
- One network call: `GET https://chatgpt.com/backend-api/wham/usage`, at most every 5 minutes (when the panel opens or the timer runs), or on a right-click.

`limits.sh` does the work and can be run by hand:

```sh
./limits.sh fetch   # [{"label":"5h","percent":42,"resets_at":"..."}, ...]
./limits.sh plan    # Plus, Pro, ...
```

It exits 2 when there is no usable sign-in, 3 when the token has expired or was rejected, and 1 for any other failure, with the reason on stderr.

## IPC

```sh
noctalia msg plugin hani/codex-usage:bar focused click     # open or close the panel
noctalia msg plugin hani/codex-usage:poller all refresh    # fetch fresh numbers now
```

## Troubleshooting

| What you see | What to do |
|---|---|
| Not signed in to ChatGPT in OpenCode | Run `opencode auth login openai --method chatgpt-browser` |
| ChatGPT sign-in expired | Open OpenCode once so it refreshes the token, then right-click the bar |
| Could not fetch Codex limits: HTTP ... | ChatGPT returned an error. Run `./limits.sh fetch` to see the reason, and try again later |
| sqlite3 not found | Install `sqlite3` |
| no OpenCode database | OpenCode keeps its data somewhere else. `limits.sh` takes the path as a second argument, for example `./limits.sh fetch /path/to/opencode.db` |

Noctalia's log has the last error as well: look for lines starting with `codex-usage:`.

## Licence

MIT, see [LICENSE](../LICENSE).
