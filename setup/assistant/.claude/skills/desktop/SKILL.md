---
name: desktop
description: Everything about driving Hani's CachyOS + Hyprland desktop - screens and workspaces, every keyboard shortcut, opening and moving apps (place), triggering shortcuts, volume, media, Bluetooth, Wi-Fi, screenshots, notifications, night light, wallpaper, Ferdium and the app windows. Use it for any request about windows, apps, screens, shortcuts or system controls.
---

# Driving the desktop

## The screens
| Name | Monitor | Workspaces | Notes |
|---|---|---|---|
| left (main) | DP-1, x=0 | 1 to 5 | Ferdium lives on 1 |
| right | DP-2, x=1920 | 6 to 10 | the first kitty opens on 6 |
"here" = the screen Hani is on, "other" = the one Hani is not on. `hyprctl monitors -j` shows the active workspace of each.

## How to do things, in this order
1. **Apps and windows: `place`** (fast, one step, never opens duplicates):
   - `place <app> left|right|here|other`, `place <app> ws N`: open it there or move it there.
   - `place left|right|other|ws N`: move the window Hani is on. `place fullscreen`, `place max`.
   - `place focus <app>`: jump to it. `place list`: every app name it knows.
2. **A shortcut Hani describes** ("do what Super+3 does"): press it with wtype. Modifiers: logo (Super), ctrl, shift, alt.
   - Super+3: `wtype -M logo -k 3 -m logo`. Super+Shift+Left: `wtype -M logo -M shift -k Left -m shift -m logo`.
   - Never press Super+Q, Ctrl+W or anything that closes or quits unless Hani asked for exactly that.
3. **System controls: `noctalia msg <command>`**: volume-up, volume-down, volume-mute, volume-set <0-100>, mic-mute,
   mic-volume-up/down/set, bluetooth-toggle/enable/disable/status, wifi-toggle/enable/disable/status, network-toggle,
   caffeine-toggle (keep awake), nightlight-toggle, notification-dnd-toggle, notification-clear-active,
   notification-clear-history, screenshot-region, screenshot-fullscreen, screenshot-annotate, wallpaper-next,
   wallpaper-random, theme-mode-toggle, dpms-off (screens off), bar-toggle, window-switcher, panel-toggle <panel>,
   settings-open, power-set <profile>, status.
4. **Media: `playerctl`**: play-pause, next, previous, stop, `playerctl metadata --format '{{artist}} - {{title}}'`.
5. **Anything else about windows**: `hyprctl` (Hyprland 0.56 takes Lua: `hyprctl dispatch "hl.dsp.focus({ workspace = '3' })"`).

## Every keyboard shortcut
The full list, kept in sync with the live binds, is Hani's cheat sheet `/home/hani/Notes/shortcuts.md`. Read it or
`grep -i <word>` it when Hani asks "what's the shortcut for X" or wants something a shortcut does. If something is not
there, the live binds in `/home/hani/.config/hypr/config/binds.lua` are the final word. Highlights:
Super+T kitty, Super+C Helium browser, Super+F Ferdium, Super+V VSCodium, Super+B Calibre, Super+Shift+B Foliate,
Super+M YouTube Music, Super+Shift+M rmpc music, Super+N Notes, Super+` app search (fuzzel), Super+Space this
assistant, Right Alt (hold) dictation, Print region screenshot (Super+Print whole screen), Super+1..0 workspaces,
Super+Shift+1..0 send the window there.

## Apps
- Desktop apps: kitty, Helium (browser), VSCodium, Ferdium, Dolphin (files), Kate, Calibre, Foliate (ebooks),
  Zotero, OnlyOffice, Audacity, mpv, LocalSend, the Craft suite (PhotoCraft, VectorCraft, FilmCraft, LightCraft,
  PrintCraft, EffectCraft, DesignCraft), Meetily (meeting notes), Handy (dictation), Mission Center.
- App windows (Helium `--app`, open with place by name): YouTube Music (media), Microsoft Teams (work), Zoom (work), Notes (SilverBullet) (home), Jellyfin (media), Seerr (media), Sonarr (media), Radarr (media), Lidarr (media), Prowlarr (media), Bazarr (media), SABnzbd (media), qBittorrent (media), Jellystat (media), ErsatzTV (media), Dispatcharr (media), Immich (home), Paperless (home), n8n (home), Sink (bts.ad) (home), Vaultwarden (home), FreshRSS (home), SearXNG (tools), IT-Tools (tools), ExcaliDash (tools), draw.io (tools), OpenSpeedTest (tools), Kasm (tools), Neko (tools), Arcane (infra), Authentik (infra), AdGuard Home (infra), Headlamp (k3s) (infra), Proxmox (infra), UniFi (infra), Tailscale (infra), Grafana (monitor), Dozzle (monitor), Beszel (monitor), Uptime Kuma (monitor), Pulse (monitor), ntopng (infra), Activepieces (home), Stirling PDF (home).
- Ferdium (Super+F) holds the web inboxes and chats in workspaces: Comms (WhatsApp, Discord, Telegram, Slack, Teams),
  Inbox (Outlook, Gmail x3, Proton, Cal.com, LinkedIn, Upwork), Code, Infra, Monitor, UNE, Study, Admin, Personal.
  Ferdium has no command line: open it with `place focus ferdium` and tell Hani which workspace to pick.

## Reply style
One short line after acting ("Jellyfin is on the right screen."). If it failed, say what failed in one line.

## Safety
Ask "(y/n)?" before sending any message, email or post, deleting anything, sudo, closing windows Hani did not name,
power or network changes (Wi-Fi off, Bluetooth off, power profile), and anything on servers or the router.
Voice transcripts can be wrong: if a request is unclear, ask one short question instead of guessing.
