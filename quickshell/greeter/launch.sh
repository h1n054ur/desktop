#!/usr/bin/env bash
# greetd runs this as the greeter user. It starts a minimal Hyprland that shows the h1n054ur greeter.
# On this machine Hyprland segfaults while exiting (aquamarine DRM teardown, hyprwm/aquamarine#430), so
# Hyprland's own exit status says nothing. run-greeter.sh records Quickshell's status instead:
#   0           you signed in and greetd is starting your session: just exit
#   missing/!0  the greeter never worked: fall back to Noctalia Greeter so there is always a login screen
DIR=/etc/greetd/h1n054ur
CACHE=/var/cache/h1n054ur-greeter
STATUS="$CACHE/qs-status"

# The account to sign in (written by install.sh)
H1N_GREETER_USER="$(cat "$DIR/user" 2>/dev/null)"
export H1N_GREETER_USER
export HOME="$CACHE"
export XDG_CACHE_HOME="$CACHE/.cache"
export XDG_STATE_HOME="$CACHE/.local/state"
export XDG_DATA_HOME="$CACHE/.local/share"
mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" 2>/dev/null
rm -f "$STATUS"

# Core dumps on, so a crash leaves a backtrace for coredumpctl
ulimit -c unlimited 2>/dev/null

# Clear the greeter VT's leftover boot text (greetd may start this without a controlling tty, so fall back
# to stdout, like dms-greeter does); done before the greeter draws and again after it closes
clear_vt() {
    local seq=$'\033[2J\033[H\033[3J\033[?25l'
    # braces so a failed open of /dev/tty prints nothing on the VT (bash reports it before 2>/dev/null applies)
    { printf '%s' "$seq" >/dev/tty; } 2>/dev/null || printf '%s' "$seq" 2>/dev/null
}
clear_vt

log() { systemd-cat -t h1n054ur-greeter -p info 2>/dev/null || cat >/dev/null; }

start-hyprland -- --config "$DIR/hyprland.lua" > >(log) 2>&1
hypr=$?
clear_vt
qs=$(cat "$STATUS" 2>/dev/null || echo missing)
echo "greeter hyprland exited with $hypr, quickshell status $qs" | log

if [ "$qs" != "0" ]; then
    echo "greeter failed, falling back to noctalia-greeter-session" | log
    exec /usr/bin/noctalia-greeter-session
fi
