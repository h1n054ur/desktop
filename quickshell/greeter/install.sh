#!/usr/bin/env bash
# h1n054ur greeter for greetd. Run with sudo.
#   install   copy the greeter to /etc/greetd/h1n054ur and create its cache folder
#   enable    make it the login screen (the previous command stays in config.toml, commented)
#   revert    go back to the previous login screen
# Test by logging out after "enable": if the greeter's Hyprland fails, launch.sh starts Noctalia Greeter instead.
# Logs: journalctl -t h1n054ur-greeter    Crashes: coredumpctl list Hyprland
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
DST=/etc/greetd/h1n054ur
CONF=/etc/greetd/config.toml
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

case "${1:-}" in
  install)
    rm -rf "$DST"
    mkdir -p "$DST/assets"
    install -m 644 "$SRC"/*.qml "$SRC/qmldir" "$SRC/hyprland.lua" "$DST/"
    # your screen layout (kept out of git); see monitors.example.lua
    [ -f "$SRC/monitors.lua" ] && install -m 644 "$SRC/monitors.lua" "$DST/" || echo "no monitors.lua: screens are placed automatically"
    install -m 755 "$SRC/launch.sh" "$SRC/run-greeter.sh" "$DST/"
    # the account the greeter signs in: the one that ran sudo, or GREETER_USER=name
    echo "${GREETER_USER:-${SUDO_USER:-$(logname 2>/dev/null)}}" > "$DST/user"
    install -m 644 "$SRC"/assets/* "$DST/assets/"
    install -d -o greeter -g greeter -m 750 /var/cache/h1n054ur-greeter
    echo "installed to $DST"
    ;;
  enable)
    [ -f "$CONF.bak-h1n054ur" ] || cp "$CONF" "$CONF.bak-h1n054ur"
    old=$(grep -E '^command *=' "$CONF.bak-h1n054ur" | head -1)
    cat > "$CONF" <<TOML
[terminal]
vt = 1

[default_session]
# h1n054ur greeter (Quickshell on a minimal Hyprland, falls back to Noctalia Greeter on failure);
# the previous login screen was:
# $old
command = "$DST/launch.sh"
user = "greeter"
TOML
    echo "enabled; log out to see it (sudo $0 revert to undo)"
    ;;
  revert)
    [ -f "$CONF.bak-h1n054ur" ] && cp "$CONF.bak-h1n054ur" "$CONF" && echo "restored previous login screen" || echo "no backup found"
    ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
