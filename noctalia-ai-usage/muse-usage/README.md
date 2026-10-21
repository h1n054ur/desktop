# Muse Usage for Noctalia

Your Muse Code plan limits in the [Noctalia](https://github.com/noctalia-dev/noctalia) bar: how much of the 5-hour and weekly windows you have used, and when each one resets. Your open [OpenCode](https://opencode.ai) sessions that run on a Muse model show on it too. It sits next to [Claude Sessions](../claude-sessions/README.md) and [Codex Usage](../codex-usage/README.md) and looks the same, with the Meta icon in Facebook blue.

## What it shows

- On the bar: the Meta icon, one dot per open OpenCode session on Muse, then a meter and a percentage per window. Dots use the Claude widget's colours: red when a session waits for you (a permission or a question), accent while it works, grey when idle. The icon turns into a red bell while any session waits. The limit colour turns yellow from 70% and red from 90%.
- Hover: each session and what it is doing, every window with its reset countdown, and when the numbers were last fetched.
- Click: a floating panel with one meter per window, the reset times, your plan (Muse Code and its tier), any error, and the open sessions grouped as Needs you, Working and Idle. Clicking a card jumps to the terminal running that session (the exact tab in kitty). The copy button gives the command that reopens it (`opencode -s <id>`).
- Right-click: fetch fresh numbers now (at most once every 30 seconds).

Desktop notifications ("Muse needs you", "Muse finished") fire when a session starts waiting for you and when a long turn finishes, with the same settings as the Claude widget.

## The usage caveat

Muse keeps no usage on disk, and it only learns your usage when it talks to the model. The widget asks a short-lived `muse serve` host, which makes no model request and so costs nothing, but that host has not seen any usage yet. Until Muse shares usage some other way, the panel will often say "No usage yet: Muse reports it after a request" and the bar shows a dim dash where the percentage would be. That is not an error. The sessions part works either way.

## Requirements

- A Muse Code subscription.
- The `muse` CLI, signed in with `muse login`.
- OpenCode with the [open-muse](https://github.com/jaylamping/open-muse) plugin, which adds Muse as the OpenCode provider `muse`.
- `jq` and `curl`. Jumping to a session uses `kitty` remote control when the session runs in kitty, and Hyprland, niri or sway to focus the window.

## Install

The widget comes from the same plugin source as Claude Sessions. See the [install steps](../README.md#install) in the top README, then add it to a bar:

```toml
[widget.muse]
type = "hani/muse-usage:bar"

[bar.default]
start = [ "workspaces", "claude", "codex", "muse" ]
```

## Settings

| Setting | Default | What it does |
|---|---|---|
| Notify when a session needs you | on | Notification when a session starts waiting for a permission or an answer |
| Notify when a long turn finishes | on | Notification when a session goes from working to idle |
| Minimum turn length (minutes) | 2 | Only notify about turns that took at least this long |
| Hide sessions idle for (hours) | 0 | Hide open sessions idle longer than this. 0 shows all |
| OpenCode providers | `^muse$` | A regular expression for the OpenCode provider ids whose sessions show here. Empty shows every session |
| Bar style | One dot per session | Dots, or counts (`waiting` and `working/open`). More than 8 sessions always show as counts |
| Bar limits | 5-hour window | Which windows the bar shows: 5-hour, 7-day, both, all, or hidden (icon only) |
| Bar limits style | Linear bar | A small bar or a ring for each window |
| Accent colour | `#1877F2` | Colour of the icon, working dots, limit bars and panel highlights (Facebook blue). Empty uses the theme's primary colour |
| Warning colour | `#FFC53D` | Colour of a limit from 70% used (yellow) |
| Critical colour | `#FF4D4F` | Colour of a limit from 90% used (red). Empty uses the theme's error colour |

Sessions whose provider can't be told at all (a new session with no model and no default model set) stay on the Codex widget, not this one.

## What it reads and sends

For limits, `limits.sh` starts `muse serve` with memory-only sessions, no shell and no file writes, asks it for the account state and `usage/read`, and lets it exit. It never starts a session or a turn. Muse handles its own sign-in, and the widget never reads the values in Muse's auth file. This runs at most every 5 minutes, or on a right-click.

```sh
./limits.sh fetch   # [{"label":"5h","percent":42,"resets_at":"..."}, ...] or [] before any usage
./limits.sh plan    # the plan tier, empty before any usage
```

`limits.sh` exits 2 when Muse is not signed in, and 1 for any other failure, with the reason on stderr.

For sessions, `sessions.sh` reads the OpenCode background service's own API every 3 seconds, read-only, and keeps only sessions whose provider matches the setting:

```sh
./sessions.sh '^muse$'
```

`sessions.sh`, `focus.sh` and `wm.sh` are the same files as in [Codex Usage](../codex-usage/README.md), which explains what they read in detail. Noctalia plugins can't share files across folders, so each plugin carries a copy. Change both copies together.

## IPC

```sh
noctalia msg plugin hani/muse-usage:bar focused click     # open or close the panel
noctalia msg plugin hani/muse-usage:poller all refresh    # fetch fresh numbers and sessions now
```

## Troubleshooting

| What you see | What to do |
|---|---|
| Not signed in to Muse | Run `muse login` |
| No usage yet | See the usage caveat above |
| Could not fetch Muse limits | Run `./limits.sh fetch` to see the reason |
| A Muse session is missing | Run `./sessions.sh` and check its `provider`. If it isn't `muse`, change the OpenCode providers setting to match |
| Clicking a card does nothing | The session has no TUI open, or kitty remote control is off (`allow_remote_control` in kitty.conf) |

Noctalia's log has the last error as well: look for lines starting with `muse-usage:`.

## Licence

MIT, see [LICENSE](../LICENSE).
