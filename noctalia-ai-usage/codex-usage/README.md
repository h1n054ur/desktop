# Codex Usage for Noctalia

Your ChatGPT plan limits for Codex in the [Noctalia](https://github.com/noctalia-dev/noctalia) bar: how much of the 5-hour and weekly windows you have used, and when each one resets. It sits next to [Claude Sessions](../claude-sessions/README.md) and looks the same. Your open [OpenCode](https://opencode.ai) sessions show on it the way Claude Code sessions show on the Claude widget.

It reads the ChatGPT sign-in that OpenCode already keeps, so there is nothing extra to log in to.

## What it shows

- On the bar: the OpenAI icon, one dot per open OpenCode session, then a meter and a percentage per window. Dots use the Claude widget's colours: red when a session waits for you (a permission or a question), accent while it works, grey when idle. The icon turns into a red bell while any session waits. The limit colour turns yellow from 70% and red from 90%.
- Hover: each session and what it is doing, every window with its reset countdown, and when the numbers were last fetched.
- Click: a floating panel with one meter per window, the reset times, your plan name (Plus, Pro and so on), any error, and the open sessions grouped as Needs you, Working and Idle. Each card shows the title, the project folder, how long ago it changed, and the tool it is running or what it is waiting for. Clicking a card jumps to the terminal running that session (the exact tab in kitty). The copy button gives the command that reopens it (`opencode -s <id>`).
- Right-click: fetch fresh numbers now (at most once every 30 seconds).
- Extra windows that ChatGPT reports (for example a per-model limit) show up in the panel, and on the bar when `Bar limits` is set to all windows.

Desktop notifications fire when a session starts waiting for you and when a long turn finishes, with the same settings as the Claude widget.

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

Requirements: OpenCode signed in as above, `sqlite3`, `jq` and `curl`. Jumping to a session uses `kitty` remote control when the session runs in kitty, and Hyprland, niri or sway to focus the window.

## Settings

| Setting | Default | What it does |
|---|---|---|
| Notify when a session needs you | on | Notification when a session starts waiting for a permission or an answer |
| Notify when a long turn finishes | on | Notification when a session goes from working to idle |
| Minimum turn length (minutes) | 2 | Only notify about turns that took at least this long |
| Hide sessions idle for (hours) | 0 | Hide open sessions idle longer than this. 0 shows all |
| OpenCode providers | `^openai$` | A regular expression for the OpenCode provider ids whose sessions show here. Sessions on other providers (for example Muse) can show on their own widget instead. Empty shows every session |
| Bar style | One dot per session | Dots, or counts (`waiting` and `working/open`). More than 8 sessions always show as counts |
| Bar limits | 5-hour window | Which windows the bar shows: 5-hour, 7-day, both, all, or hidden (icon only) |
| Bar limits style | Linear bar | A small bar or a ring for each window |
| Accent colour | `#E6E6E6` | Colour of the icon, working dots, limit bars and panel highlights (a greyish white). Empty uses the theme's primary colour. Limits switch to the warning colour from 70% and the critical colour from 90% |
| Warning colour | `#FFC53D` | Colour of a limit from 70% used (yellow) |
| Critical colour | `#FF4D4F` | Colour of a limit from 90% used (red). Empty uses the theme's error colour |

## What it reads and sends

- OpenCode's credential row for OpenAI in `~/.local/share/opencode/opencode.db` (the active `openai` row of the `credential` table). The database is opened read-only, and no other row or file is read.
- The access token goes to `curl` on stdin, so it never shows in the process list. It is never printed, logged or written to disk.
- The widget never refreshes the token. OpenCode owns it and refreshes it when you use OpenCode. If it has expired, the panel says so until OpenCode refreshes it.
- One network call: `GET https://chatgpt.com/backend-api/wham/usage`, at most every 5 minutes (when the panel opens or the timer runs), or on a right-click.

For sessions, `sessions.sh` asks the OpenCode background service (`opencode serve --service`, the one `opencode api` talks to) every 3 seconds, read-only:

- It reads the service's address and password from `~/.local/state/opencode/service.json`. The password goes to `curl` on stdin, the same way as the ChatGPT token, and is never printed.
- Calls, all on `127.0.0.1`: the root session list (`GET /api/session`), the sessions running now (`GET /api/session/active`), pending permission requests and questions for each project folder (`GET /api/permission/request`, `GET /api/form`), and the newest assistant message of a working session to see its tool. It never sends a prompt or changes a session.
- With no service running it prints `[]` straight away.

Each session goes to a widget by the provider of its model. The session list already carries the model a session last used, so this costs no extra call. A new session that has no model yet runs on OpenCode's default model, which the widget reads from the service's config (`GET /api/config`) for that folder. If no default is set either, the session stays on this widget. Each card shows the model name.

OpenCode does not say which session a terminal is showing, so each running OpenCode TUI counts as one open session: the one it was started with (`-s`), or else the newest session in the folder it runs in. That TUI's process is what a click brings to the front. Sessions that are working or waiting show even without a TUI (for example `opencode run` or the web app).

`limits.sh` does the work for limits and can be run by hand:

```sh
./limits.sh fetch   # [{"label":"5h","percent":42,"resets_at":"..."}, ...]
./limits.sh plan    # Plus, Pro, ...
```

```sh
./sessions.sh             # every session: [{"id":"ses_...","title":"...","status":"idle","provider":"openai","model":"gpt-5.6-sol", ...}]
./sessions.sh '^openai$'  # only sessions whose provider id matches the expression
```

`limits.sh` exits 2 when there is no usable sign-in, 3 when the token has expired or was rejected, and 1 for any other failure, with the reason on stderr.

## IPC

```sh
noctalia msg plugin hani/codex-usage:bar focused click     # open or close the panel
noctalia msg plugin hani/codex-usage:poller all refresh    # fetch fresh numbers and sessions now
```

## Troubleshooting

| What you see | What to do |
|---|---|
| Not signed in to ChatGPT in OpenCode | Run `opencode auth login openai --method chatgpt-browser` |
| ChatGPT sign-in expired | Open OpenCode once so it refreshes the token, then right-click the bar |
| Could not fetch Codex limits: HTTP ... | ChatGPT returned an error. Run `./limits.sh fetch` to see the reason, and try again later |
| No sessions, though OpenCode is open | Check that `opencode service status` prints an address and run `./sessions.sh` to see what it returns |
| A session is missing from this widget | Its model is on another provider. `./sessions.sh` shows each session's `provider`. Add it to the OpenCode providers setting, for example `^(openai\|azure)$` |
| Clicking a card does nothing | The session has no TUI open, or kitty remote control is off (`allow_remote_control` in kitty.conf). Other terminals are found through the window manager |
| sqlite3 not found | Install `sqlite3` |
| no OpenCode database | OpenCode keeps its data somewhere else. `limits.sh` takes the path as a second argument, for example `./limits.sh fetch /path/to/opencode.db` |

Noctalia's log has the last error as well: look for lines starting with `codex-usage:`.

## Licence

MIT, see [LICENSE](../LICENSE).
