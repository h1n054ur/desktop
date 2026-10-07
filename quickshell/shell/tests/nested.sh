#!/usr/bin/env bash
# Test the lock screen inside a nested Hyprland window, never on the real session.
#   tests/nested.sh deny    lock, type a password PAM rejects: must stay locked and say "wrong password"
#   tests/nested.sh allow   lock, type a password PAM accepts: must unlock
# Prints the shell's h1n-lock log lines and leaves a screenshot of the window in $OUT.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-deny}"
OUT="${OUT:-/tmp/h1n-nested}"
mkdir -p "$OUT"
export H1N_NESTED_CMD="env H1N_LOCK_AUTOLOCK=1 H1N_LOCK_AUTOTYPE=test-password H1N_LOCK_PAM_DIR=$HERE/pam H1N_LOCK_PAM=$MODE quickshell -p $HERE/../shell.qml > $OUT/qs-$MODE.log 2>&1"
Hyprland -c "$HERE/nested.lua" > "$OUT/hyprland-$MODE.log" 2>&1 &
HPID=$!
sleep 6
grim -g "$(hyprctl clients -j | python3 -c 'import json,sys
c=[c for c in json.load(sys.stdin) if c["class"].startswith("wlroots") or c["title"].startswith("wlroots") or "aquamarine" in c["class"].lower()]
print("%d,%d %dx%d" % (c[0]["at"][0],c[0]["at"][1],c[0]["size"][0],c[0]["size"][1]) if c else "0,0 10x10")')" "$OUT/window-$MODE.png" 2>/dev/null
grep -h 'h1n-lock' "$OUT/qs-$MODE.log"
kill "$HPID" 2>/dev/null; sleep 1; kill -9 "$HPID" 2>/dev/null
echo "screenshot: $OUT/window-$MODE.png"
