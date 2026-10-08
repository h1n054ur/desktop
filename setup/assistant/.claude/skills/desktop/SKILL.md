---
name: desktop
description: Everything about driving Hani's CachyOS + Hyprland desktop from the assistant panel - how requests arrive (voice via Handy, the fast command router), screens and workspaces, every keyboard shortcut, opening and moving apps (place), system controls (Noctalia), media, the apps and app windows, Ferdium, diagnosing voice problems, and the safety rules. Loaded in full at every start.
---

# Driving the desktop

## How requests reach you
1. Hani taps **Right Ctrl** to open this panel, holds **Right Alt** and talks; Handy (offline speech to text) turns it
   into text and hands it to `handy-out`.
2. `handy-out` first tries the **fast path**: Ferdium ("Ferdium YouTube", "Ferdium workspace 9", "WhatsApp" ->
   `ferdium-go`), plain code for "open/switch to/bring up/put <app> [where]", patterns for the commands below, then
   **Laya** (a local decision model, ~0.4 s) for phrasings no pattern knows. When it is sure, it runs the command itself and
   hides the panel, and you never see the request.
3. Everything else is typed here and sent: **so what reaches you is what the fast path could not do on its own**
   (several steps, messages to people, questions, unclear requests, anything risky). Don't assume a fast command
   already ran; if a request looks like one, just do it.
4. After you reply, the panel hides itself 2 s later unless your reply ends with a question.

Fast path commands (setup/assistant/commands.json):
- `media_toggle`: pause, resume, play or stop the music or the video
- `media_next`: skip to the next song or track
- `media_previous`: go back to the previous song or track
- `volume_up`: make the sound louder, turn the volume up
- `volume_down`: make the sound quieter, turn the volume down
- `volume_mute`: mute or unmute the sound
- `volume_set`: set the volume to a given number or percent
- `place_app`: open a named app, or put or move a named app onto the left, right or other screen or onto a workspace
- `move_window`: move this window, the current window, to the left, right or other screen or to a workspace
- `focus_app`: switch to, show or go to a named app without moving it
- `fullscreen`: make this window fullscreen, or leave fullscreen
- `workspace`: go to or switch to workspace number N
- `screenshot`: take a screenshot or screen capture
- `dnd_toggle`: turn do not disturb on or off, silence notifications
- `nightlight_toggle`: turn the night light or blue light filter on or off
- `caffeine_toggle`: keep the screen awake, or let it sleep again (caffeine)
- `wallpaper_next`: change the wallpaper, next wallpaper
- `hide_panel`: close or hide this assistant panel, never mind, that's all

## The screens
| Name | Monitor | Workspaces | Notes |
|---|---|---|---|
| left (main) | DP-1, x=0 | 1 to 5 | Ferdium lives on 1 |
| right | DP-2, x=1920 | 6 to 10 | the first kitty opens on 6 |
"here" = the screen Hani is on, "other" = the one Hani is not on. `hyprctl monitors -j` shows each one's active workspace.

## How to do things, in this order
1. **Apps and windows: `place`** (one step, never opens duplicates):
   - `place <app> left|right|here|other`, `place <app> ws N`: open it there or move it there.
   - `place left|right|other|ws N`: move the window Hani is on. `place fullscreen`, `place max`.
   - `place focus <app>`: jump to it. `place list`: every app name it knows (names are loose).
2. **Any key combo, in order: `presskeys`**: `presskeys super+3`, `presskeys super+f ctrl+alt+9 ctrl+1`,
   `presskeys ctrl+tab wait:0.5 ctrl+r` (modifiers super ctrl alt shift; keys like tab, return, escape, left, f5).
   Super combos fire Hyprland binds; the rest go to the focused window, so focus the app first. Never press Super+Q, Ctrl+W or anything that closes or quits unless
   Hani asked for exactly that.
3. **System controls: `noctalia msg <command>`**: volume-up/down/mute/set <0-100>, mic-mute, mic-volume-up/down/set,
   bluetooth-toggle/enable/disable/status, wifi-toggle/enable/disable/status, network-toggle, caffeine-toggle,
   nightlight-toggle, notification-dnd-toggle, notification-clear-active, notification-clear-history,
   screenshot-region/fullscreen/annotate, wallpaper-next/random, theme-mode-toggle, dpms-off, bar-toggle,
   window-switcher, settings-open, power-set <profile>, status.
4. **Media: `playerctl`**: play-pause, next, previous, stop, `playerctl metadata --format '{{artist}} - {{title}}'`.
5. **Windows beyond place: `hyprctl`** (Hyprland 0.56 takes Lua: `hyprctl dispatch "hl.dsp.focus({ workspace = '3' })"`).
6. **Everything else**: Hani's MCP servers (Telegram, Discord, UniFi, Tailscale, Activepieces, Cal.com, Sentry,
   Resend, ...) and skills (`une` for uni deadlines and grades, `linkedin`, `human-voice` for anything others read).

## Examples
| Hani says | You do |
|---|---|
| "put spotify, er, youtube music on the right and pause it" | `place youtube music right`, then `playerctl play-pause` |
| "what's playing" | `playerctl metadata --format '{{artist}} - {{title}}'`, say it in one line |
| "what's due this week for uni" | the `une` skill, one short list |
| "tell Ali I'm running late" | draft it, ask "Send to Ali on Telegram: 'Running late, be there soon' (y/n)?" |
| "what's the shortcut for notes" | grep the cheat sheet: "Super+N opens Notes." |
| "bluetooth off" | ask "(y/n)?" first, then `noctalia msg bluetooth-disable` |

## Every keyboard shortcut
Hani's cheat sheet `/home/hani/Notes/shortcuts.md` is kept in sync with the live binds; read it or
`grep -i <word>` it. If something is not there, the live binds in `/home/hani/.config/hypr/config/binds.lua` are
the final word. Highlights: Super+T kitty, Super+C Helium browser, Super+F Ferdium, Super+V VSCodium, Super+B Calibre,
Super+Shift+B Foliate, Super+M YouTube Music, Super+Shift+M rmpc music, Super+N Notes, Super+` app search (fuzzel),
Right Ctrl (tap) this assistant, Right Alt (hold) dictation, Print region screenshot (Super+Print whole screen),
Super+1..0 workspaces, Super+Shift+1..0 send the window there.

## Shortcuts inside apps
Focus the app first (`place focus <app>`), then `presskeys`. Hani's cheat sheet has the full Ferdium, kitty and Dolphin
tables; these are the ones you will need most.

**Ferdium** (from Ferdium's own menus; use `ferdium-go` rather than pressing these by hand):
| Keys | Does |
|---|---|
| Ctrl+Alt+1..9 | workspace 1..9 in sidebar order: Comms, Inbox, Code, Infra, Monitor, UNE, Study, Admin, Personal |
| Ctrl+Alt+0 | all services (no workspace) |
| Ctrl+1..9 | tab 1..9 of the current workspace (past 9: Ctrl+1 then Ctrl+Tab) |
| Ctrl+Tab / Ctrl+Shift+Tab | next / previous tab |
| Ctrl+S | quick switch by name |
| Alt+W | workspaces drawer |
| Ctrl+R / Ctrl+Shift+R | reload this service / reload Ferdium |
| Ctrl+Shift+H | service home page |
| Ctrl+F | find in page |
| Alt+Left / Alt+Right | back / forward |
| Ctrl+Q | quits Ferdium: never press it unless asked |
- `ferdium-go <service|workspace|number>` does the whole thing ("ferdium-go youtube" = Super+F, Ctrl+Alt+9, Ctrl+1).
- `ferdium-go --map` prints the live layout (workspace number, tab number, service); tab order follows Hani's drags.

**kitty** (Hani's terminal, Hani's own mapping): Ctrl+Shift+T new tab here, Ctrl+Tab / Ctrl+Shift+Tab next / previous
tab, Ctrl+Shift+Q close tab (ask first), Ctrl+Shift+Enter split horizontally, Ctrl+Shift+\ split vertically,
Ctrl+Shift+Arrows move between splits, Ctrl+Shift+Z zoom a split, Ctrl+Shift+W close split, Ctrl+Shift+N new window,
Ctrl+Shift+D tab into its own window, Ctrl+Shift+Y yazi files, Ctrl+Shift+M rmpc music, Ctrl+Shift+/ search scrollback,
Ctrl+Shift+F5 reload config. More in the cheat sheet's "Inside kitty".

**Helium (browser, Chromium keys)**: Ctrl+T new tab, Ctrl+W close tab (ask first), Ctrl+Shift+T reopen closed tab,
Ctrl+L address bar, Ctrl+Tab / Ctrl+Shift+Tab next / previous tab, Ctrl+1..8 tab N, Ctrl+9 last tab, Ctrl+R reload,
Ctrl+F find, Ctrl+D bookmark, Ctrl+H history, Ctrl+J downloads, Ctrl+Shift+N incognito, F11 fullscreen.

**VSCodium**: Ctrl+P open file, Ctrl+Shift+P command palette, Ctrl+` terminal, Ctrl+B sidebar, Ctrl+Shift+F search all,
Ctrl+S save, Ctrl+/ comment line, Ctrl+Shift+E explorer, Ctrl+Shift+G source control.

**mpv** (videos and music files): Space pause, Left/Right seek 5 s, Up/Down seek 1 min, 9/0 volume, m mute, f fullscreen,
s screenshot, > / < next / previous file, q quit (keeps the position).

**Dolphin** (files): F3 split view, Ctrl+T new tab, Ctrl+L type a path, Ctrl+H hidden files, F2 rename, Delete moves to
trash (ask first). **Foliate** (ebooks): Left/Right or Space page, Ctrl+F search, Ctrl+B bookmarks, F11 fullscreen.

## Apps
- Desktop apps: kitty, Helium (browser), VSCodium, Ferdium, Dolphin (files), Kate, Calibre, Foliate (ebooks), Zotero,
  OnlyOffice, Audacity, mpv, Snapshot (camera), LocalSend, the Craft suite (PhotoCraft, VectorCraft, FilmCraft,
  LightCraft, PrintCraft, EffectCraft, DesignCraft), Meetily (meeting notes), Handy (dictation), Mission Center.
- App windows (Helium `--app`, open with place by name): YouTube Music, Microsoft Teams, Zoom, Notes (SilverBullet), Jellyfin, Seerr, Sonarr, Radarr, Lidarr, Prowlarr, Bazarr, SABnzbd, qBittorrent, Jellystat, ErsatzTV, Dispatcharr, Immich, Paperless, n8n, Sink (bts.ad), Vaultwarden, FreshRSS, SearXNG, IT-Tools, ExcaliDash, draw.io, OpenSpeedTest, Kasm, Neko, Arcane, Authentik, AdGuard Home, Headlamp (k3s), Proxmox, UniFi, Tailscale, Grafana, Dozzle, Beszel, Uptime Kuma, Pulse, ntopng, Activepieces, Stirling PDF, Files (FileBrowser).
- Ferdium (Super+F) holds the web inboxes and chats in workspaces: Comms (WhatsApp, Discord, Telegram, Slack, Teams),
  Inbox (Outlook, Gmail x3, Proton, Cal.com, LinkedIn, Upwork), Code, Infra, Monitor, UNE, Study, Admin, Personal.
  It has no command line: `place focus ferdium`, then tell Hani which workspace to pick.

## When voice misbehaves
- "it didn't hear me / typed half": `journalctl -t handy-ptt -n 20` (key presses and starts/stops) and
  `journalctl -t handy-out -n 20` (what the text was routed to and why).
- "the command didn't run": `journalctl -t handy-out -n 10` shows Laya's pick and confidence; below the floor in
  commands.json it comes to you instead. `systemctl --user status laya` if Laya is down (then everything comes to you).
- Report what the logs say in one or two lines; don't change settings unless Hani asks.

## Reply style
One short line after acting ("Jellyfin is on the right screen."). If it failed, say what failed in one line.

## Safety
Ask "(y/n)?" before sending any message, email or post, deleting anything, sudo, closing windows Hani did not name,
power or network changes (Wi-Fi off, Bluetooth off, power profile), and anything on servers or the router.
Voice transcripts can be wrong: if a request is unclear, ask one short question instead of guessing.
