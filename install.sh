#!/usr/bin/env bash
# shellcheck disable=SC2016  # bash -c '...' _ "$arg": values go in as positional arguments, never pasted into code
# h1n054ur desktop: install CachyOS (Hyprland edition), then run this. Sets up the whole two-screen desktop,
# or only the pieces you pick.
#   ./install.sh                       interactive: pick components, pick your main screen, watch it install
#   ./install.sh theme plugins --yes   only those components, no questions
#   ./install.sh all --yes             everything
#   ./install.sh --dry-run             walk through it without changing anything
#   ./install.sh --list                show the components
# Straight from GitHub:  curl -fsSL https://raw.githubusercontent.com/h1n054ur/desktop/main/install.sh | bash
# Every file it replaces is backed up next to the original as <name>.bak-<date>. Log: ~/.cache/h1n054ur-setup/
set -uo pipefail

# Run from a checkout; when piped from curl, clone first and start again from there
HERE=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)
if [ ! -f "$HERE/splits.toml" ]; then
  DEST="$HOME/.local/share/h1n054ur-desktop"
  command -v git >/dev/null || sudo pacman -S --needed --noconfirm git
  if [ -d "$DEST/.git" ]; then git -C "$DEST" pull --quiet --ff-only; else git clone --quiet https://github.com/h1n054ur/desktop "$DEST"; fi
  exec bash "$DEST/install.sh" "$@" < /dev/tty
fi

UI_ROOT="$HERE/setup"
# shellcheck source=SCRIPTDIR/setup/lib/ui.sh
. "$HERE/setup/lib/ui.sh"

STAMP=$(date +%Y%m%d-%H%M%S)
ORDER=(packages screens hyprland theme plugins claude lock login terminal kitty)
declare -A DESC PICK
DESC[packages]="the software, by group (asks which groups)"
DESC[screens]="detect your screens; pick the main (left) one"
DESC[hyprland]="Hyprland config: 1-5 left, 6-10 right, keybinds, border"
DESC[theme]="Noctalia look: floating pills, panels, palette, glow icons"
DESC[plugins]="bar plugins: stats, weather, volume, network, titles"
DESC[claude]="Claude Code sessions in the right screen's bar"
DESC[lock]="lock screen + session menu (Super+L, Super+Alt+C)"
DESC[login]="login screen for greetd (needs sudo; easy to revert)"
DESC[terminal]="welcome banner, fastfetch, starship prompt"
DESC[kitty]="kitty, yazi, rmpc music, cava"

DRY=0 YES=0
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;; --yes|-y) YES=1 ;;
    --list) for c in "${ORDER[@]}"; do printf '%-9s %s\n' "$c" "${DESC[$c]}"; done; exit 0 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    all) for c in "${ORDER[@]}"; do PICK[$c]=1; done ;;
    *) [ -n "${DESC[$a]:-}" ] || { echo "unknown component: $a (see --list)"; exit 2; }; PICK[$a]=1 ;;
  esac
done

LOG_DIR="$HOME/.cache/h1n054ur-setup"; mkdir -p "$LOG_DIR"; LOG="$LOG_DIR/desktop-$STAMP.log"
act() {  # act <description> <command...>: run it, or in a dry run only log it
  printf '%s\n' "$1" >> "$LOG"
  if [ "$DRY" = 1 ]; then printf '  %s·%s %s %s(dry run)%s\n' "$DIM" "$R" "$1" "$DIM" "$R"; return 0; fi
  shift; "$@" >> "$LOG" 2>&1
}
backup() {  # backup <path>: move it aside as <path>.bak-<stamp> if it exists (a symlink is just removed)
  local p=$1
  if [ -L "$p" ]; then act "unlink $p" rm "$p"
  elif [ -e "$p" ]; then act "back up $p -> $(basename "$p").bak-$STAMP" mv "$p" "$p.bak-$STAMP"; fi
}
link() {  # link <target> <path>: point path at a file or folder in this checkout, backing up what was there
  [ "$(readlink -f "$2" 2>/dev/null)" = "$(readlink -f "$1")" ] && return 0
  backup "$2"; act "link $2 -> $1" bash -c 'mkdir -p "$(dirname "$2")" && ln -s "$1" "$2"' _ "$1" "$2"
}

clear 2>/dev/null; banner
printf '  %sinstall CachyOS (Hyprland edition), then this: the whole two-screen desktop, or any piece of it%s\n\n' "$DIM" "$R"
command -v pacman >/dev/null || { printf '  %sthis needs CachyOS or Arch (pacman)%s\n' "$RED" "$R"; exit 1; }

chosen=(); for c in "${ORDER[@]}"; do [ "${PICK[$c]:-0}" = 1 ] && chosen+=("$c"); done
if [ ${#chosen[@]} -eq 0 ]; then
  [ -t 0 ] || { echo "no components given and no terminal to ask: ./install.sh <component>... --yes"; exit 2; }
  for c in "${ORDER[@]}"; do PICK[$c]=1; done   # everything ticked; untick what you don't want
  checklist "pick what to set up" ORDER DESC PICK
  for c in "${ORDER[@]}"; do [ "${PICK[$c]:-0}" = 1 ] && chosen+=("$c"); done
  [ ${#chosen[@]} -eq 0 ] && { printf '  %snothing picked%s\n' "$DIM" "$R"; exit 0; }
fi
want() { [ "${PICK[$1]:-0}" = 1 ]; }

# ── packages ────────────────────────────────────────────────────────────────────────────────────────
if want packages; then
  args=(); [ "$DRY" = 1 ] && args+=(--dry-run); [ "$YES" = 1 ] && args+=(desktop terminal --yes)
  NO_ANIM=1 bash "$HERE/setup/install.sh" "${args[@]}" || printf '  %ssome packages failed, carrying on%s\n' "$RED" "$R"
  printf '\n'
fi

# ── screens: which one is the main (left) screen ────────────────────────────────────────────────────
MAIN_DESC="" SIDE_DESC="" MAIN_W=1920 SINGLE=0
detect_screens() {
  command -v hyprctl >/dev/null && hyprctl monitors -j >/dev/null 2>&1 || return 1
  mapfile -t MONS < <(hyprctl monitors -j | python3 -c '
import json,sys
for m in sorted(json.load(sys.stdin), key=lambda m: m["x"]):
    print("\t".join([m["name"], m["description"], str(m["width"]), str(m["height"]), "%.0f" % m["refreshRate"]]))')
  [ ${#MONS[@]} -gt 0 ]
}
if want screens || want hyprland || want login; then
  if detect_screens; then
    if [ ${#MONS[@]} -eq 1 ]; then
      SINGLE=1; IFS=$'\t' read -r _ MAIN_DESC MAIN_W _ _ <<< "${MONS[0]}"
      box "screens" "${CYN}one screen${R} ${FG}$MAIN_DESC${R}" "${DIM}all ten workspaces share it${R}"
    else
      opts=(); for m in "${MONS[@]}"; do IFS=$'\t' read -r n d w h r <<< "$m"; opts+=("$n  ${w}x${h}@${r}  $d"); done
      if [ "$YES" = 1 ] || [ ! -t 0 ]; then idx=0; else choose "which screen is your main one? it goes on the left" idx "${opts[@]}"; fi
      IFS=$'\t' read -r _ MAIN_DESC MAIN_W _ _ <<< "${MONS[$idx]}"
      side=$(( idx == 0 ? 1 : 0 )); IFS=$'\t' read -r _ SIDE_DESC _ _ _ <<< "${MONS[$side]}"
      box "screens" "${GRN}main (left)${R}  ${FG}$MAIN_DESC${R}" "${CYN}right${R}        ${FG}$SIDE_DESC${R}" \
        "${DIM}workspaces 1-5 on the main screen, 6-10 on the right${R}"
    fi
  else
    box "screens" "${DIM}Hyprland isn't running, so screens can't be detected yet.${R}" \
      "${DIM}Log in to Hyprland once, then run: ./install.sh screens${R}"
  fi
  echo
fi

write_host_file() {
  local f host
  host=$(cat /etc/hostname 2>/dev/null || hostname); f="$HOME/.config/hypr/host/$host.lua"
  [ -n "$MAIN_DESC" ] || return 0
  local body
  if [ "$SINGLE" = 1 ]; then
    body=$(printf -- '-- written by h1n054ur install.sh (%s): one screen\nMONITOR1 = "desc:%s"\nMONITOR2 = MONITOR1\nMONITOR3 = ""\nPRIMARY_MONITOR = MONITOR1\nKITTY_WORKSPACE = "2"\n' "$STAMP" "$MAIN_DESC")
  else
    body=$(printf -- '-- written by h1n054ur install.sh (%s): MONITOR2 is the main screen on the left, MONITOR1 the right one\nMONITOR1 = "desc:%s"\nMONITOR2 = "desc:%s"\nMONITOR3 = ""\nPRIMARY_MONITOR = MONITOR1\n\nhl.monitor({ output = MONITOR2, mode = "preferred", position = "0x0", scale = "1" })\nhl.monitor({ output = MONITOR1, mode = "preferred", position = "%sx0", scale = "1" })\n' "$STAMP" "$SIDE_DESC" "$MAIN_DESC" "$MAIN_W")
  fi
  [ -e "$f" ] && backup "$f"
  act "write $f" bash -c 'mkdir -p "$(dirname "$1")" && printf "%s\n" "$2" > "$1"' _ "$f" "$body"
}

# ── the rest ────────────────────────────────────────────────────────────────────────────────────────
step() { printf '\n  %s%s%s\n' "$B" "$(gradline "$1")" "$R"; }

if want hyprland; then
  step "hyprland"
  if [ -d "$HOME/.config/hypr" ] && [ ! -f "$HOME/.config/hypr/.h1n054ur" ]; then backup "$HOME/.config/hypr"; fi
  act "copy the Hyprland config to ~/.config/hypr" bash -c 'mkdir -p ~/.config/hypr && cp -r "$1"/hyprland.lua "$1"/config "$1"/host "$1"/KEYBINDS.md ~/.config/hypr/ && touch ~/.config/hypr/.h1n054ur' _ "$HERE/hyprland"
  write_host_file
elif want screens; then
  step "screens"; write_host_file
fi

if want theme; then
  step "theme"
  link "$HERE/noctalia-theme/noctalia/palettes/h1n054ur.json" "$HOME/.config/noctalia/palettes/h1n054ur.json"
  link "$HERE/noctalia-theme/icons/glow" "$HOME/.local/share/glow-icons"
  cfg="$HOME/.config/noctalia/config.toml"
  inc="files = [ \"$HERE/noctalia-theme/noctalia/h1n054ur.toml\" ]"
  if [ -f "$cfg" ] && grep -q 'noctalia-theme/noctalia/h1n054ur.toml' "$cfg"; then :
  else
    [ -f "$cfg" ] && act "back up $cfg" cp "$cfg" "$cfg.bak-$STAMP"
    act "include the theme from $cfg" bash -c 'mkdir -p "$(dirname "$1")"; { printf "[include]\n%s\n\n" "$2"; cat "$1" 2>/dev/null; } > "$1.new" && mv "$1.new" "$1"' _ "$cfg" "$inc"
  fi
  if [ -n "$SIDE_DESC" ] && ! grep -q 'h1n054ur right screen' "$cfg" 2>/dev/null; then
    right_end='[ "tray" ]'; right_start='[ "workspaces" ]'; want claude && right_start='[ "workspaces", "claude" ]'
    act "give the right screen its own bar" bash -c 'printf "\n# h1n054ur right screen: workspaces 6-10, Claude sessions, window title, tray\n[bar.default.monitor.right]\nmatch = \"%s\"\nstart = %s\ncenter = [ \"gw_title\" ]\nend = %s\n" "$2" "$3" "$4" >> "$1"' _ "$cfg" "$SIDE_DESC" "$right_start" "$right_end"
  fi
fi

if want plugins; then
  step "plugins"
  for p in glow-panel glow-stats glow-weather glow-window; do
    link "$HERE/noctalia-glow-plugins/$p" "$HOME/.local/share/noctalia/plugins/$p"
    act "enable hani/$p" bash -c 'noctalia msg plugins enable "hani/$1" || true' _ "$p"
  done
fi
if want claude; then
  step "claude sessions"
  link "$HERE/noctalia-claude-sessions/claude-sessions" "$HOME/.local/share/noctalia/plugins/claude-sessions"
  act "enable hani/claude-sessions" bash -c 'noctalia msg plugins enable hani/claude-sessions || true'
fi

if want lock; then
  step "lock screen + session menu"
  link "$HERE/quickshell/shell" "$HOME/.config/quickshell/h1n054ur"
  hi="$HOME/.config/hypr/hypridle.conf"
  [ -f "$hi" ] && ! grep -q 'h1n054ur' "$hi" && backup "$hi"
  act "write $hi (lock before sleep)" bash -c 'printf "# h1n054ur: lock with the h1n054ur lock screen before sleep\ngeneral {\n    lock_cmd = quickshell -c h1n054ur ipc call lock lock\n    before_sleep_cmd = quickshell -c h1n054ur ipc call lock lock && sleep 1\n    after_sleep_cmd = noctalia msg dpms-on\n}\n" > "$1"' _ "$hi"
fi

if want login; then
  step "login screen"
  ok=1
  if [ "$YES" = 0 ] && [ -t 0 ] && [ "$DRY" = 0 ]; then
    printf '  %s❯%s replace the login screen? you can undo it with %ssudo quickshell/greeter/install.sh revert%s %s[y/N]%s ' "$GRN" "$R" "$CYN" "$R" "$DIM" "$R"
    read -r ans; case $ans in y|Y|yes) ;; *) ok=0; printf '  %sskipped%s\n' "$DIM" "$R" ;; esac
  fi
  if [ "$ok" = 1 ]; then
    mon="$HERE/quickshell/greeter/monitors.lua"
    if [ -n "$SIDE_DESC" ]; then
      act "write the login screen's screen layout" bash -c 'printf "hl.monitor({ output = \"desc:%s\", mode = \"preferred\", position = \"0x0\", scale = \"1\" })\nhl.monitor({ output = \"desc:%s\", mode = \"preferred\", position = \"%sx0\", scale = \"1\" })\n" "$2" "$3" "$4" > "$1"' _ "$mon" "$MAIN_DESC" "$SIDE_DESC" "$MAIN_W"
    fi
    act "install the login screen (sudo)" sudo "$HERE/quickshell/greeter/install.sh" install
    act "make it the login screen (sudo)" sudo "$HERE/quickshell/greeter/install.sh" enable
  fi
fi

if want terminal; then
  step "terminal"
  if [ "$DRY" = 1 ]; then act "terminal/install.sh" true; else run_step "welcome banner, fastfetch, starship" 0 '' bash "$HERE/terminal/install.sh" "$USER"; fi
fi
if want kitty; then
  step "kitty"
  if [ "$DRY" = 1 ]; then act "kitty/install.sh" true; else run_step "kitty, yazi, rmpc, cava" 0 '' bash "$HERE/kitty/install.sh"; fi
fi

echo
lines=("${GRN}set up:${R} ${FG}${chosen[*]}${R}")
[ "$DRY" = 1 ] && lines=("${GRN}dry run finished, nothing was changed${R}" "${DIM}would set up: ${chosen[*]}${R}")
lines+=("${DIM}backups: *.bak-$STAMP next to each replaced file${R}" "${DIM}log: ${LOG/#$HOME/\~}${R}")
box "done" "${lines[@]}"
printf '\n  %snext: log out and back in (or reboot, for the login screen). Super+/ shows every keybind.%s\n\n' "$DIM" "$R"
