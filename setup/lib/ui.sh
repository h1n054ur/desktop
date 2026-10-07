# shellcheck shell=bash disable=SC2034  # colour variables are used by the scripts that source this
# h1n054ur installer UI: the h1n054ur-terminal palette, the gradient banner, boxed panels, spinners and progress bars.
# Source it, then set LOG (a file) and DRY (0 or 1) before calling run_step. UI_ROOT points at the folder that
# holds assets/banner.txt (defaults to this file's parent folder).
UI_ROOT=${UI_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

# ── look: the h1n054ur-terminal palette ─────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  E=$'\e'; R="${E}[0m"; B="${E}[1m"; DIM="${E}[38;2;125;143;138m"; FG="${E}[38;2;230;241;238m"
  GRN="${E}[38;2;57;255;20m"; CYN="${E}[38;2;77;232;255m"; RED="${E}[38;2;255;92;122m"; LINE="${E}[38;2;29;42;38m"
else
  R='' B='' DIM='' FG='' GRN='' CYN='' RED='' LINE=''
fi
grad() {  # grad <col> <width> -> colour escape on the #39ff14 -> #00e5ff gradient
  [ -z "$R" ] && return
  local t=$(( $1 * 1000 / ($2 > 1 ? $2 - 1 : 1) ))
  printf '\e[38;2;%d;%d;%dm' $(( 57 - 57 * t / 1000 )) $(( 255 - 26 * t / 1000 )) $(( 20 + 235 * t / 1000 ))
}
gradline() {  # print a string with the gradient across its width
  local s=$1 w=${2:-${#1}} i
  for (( i = 0; i < ${#s}; i++ )); do printf '%s%s' "$(grad "$i" "$w")" "${s:i:1}"; done; printf '%s' "$R"
}
hide_cursor() { [ -t 1 ] && printf '\e[?25l'; }
show_cursor() { [ -t 1 ] && printf '\e[?25h'; }
trap 'show_cursor; stty echo 2>/dev/null; printf "%s\n" "$R"' EXIT
trap 'exit 130' INT

box() {  # box <title> <line>...  a panel in the terminal identity; long lines wrap at word boundaries
  local title=$1; shift; local w=66 l plain
  printf '  %s┌─[ %s%s%s ]%s┐%s\n' "$LINE" "$CYN" "$title" "$LINE" "$(printf '─%.0s' $(seq 1 $(( w - ${#title} - 5 ))))" "$R"
  for l in "$@"; do
    plain=$(printf '%s' "$l" | sed 's/\x1b\[[0-9;]*m//g')
    if (( ${#plain} <= w - 2 )); then
      printf '  %s│%s %s%*s%s│%s\n' "$LINE" "$R" "$l" $(( w - ${#plain} - 1 )) '' "$LINE" "$R"
    else  # wrap the plain text (colour is dropped on wrapped lines)
      local word cur=""
      for word in $plain; do
        if (( ${#cur} + ${#word} + 1 > w - 2 )); then
          printf '  %s│%s %s%s%*s%s│%s\n' "$LINE" "$R" "$FG" "$cur" $(( w - ${#cur} - 1 )) '' "$LINE" "$R"; cur="  $word"
        else cur="${cur:+$cur }$word"; fi
      done
      printf '  %s│%s %s%s%*s%s│%s\n' "$LINE" "$R" "$FG" "$cur" $(( w - ${#cur} - 1 )) '' "$LINE" "$R"
    fi
  done
  printf '  %s└%s┘%s\n' "$LINE" "$(printf '─%.0s' $(seq 1 "$w"))" "$R"
}

banner() {  # reveal the banner left to right, then settle in the gradient
  local f="$UI_ROOT/assets/banner.txt" lines=() w=0 l c n
  [ -f "$f" ] || { printf '\n  %s\n\n' "$(gradline 'h1n054ur setup')"; return; }
  mapfile -t lines < "$f"
  for l in "${lines[@]}"; do (( ${#l} > w )) && w=${#l}; done
  n=${#lines[@]}
  if [ -t 1 ] && [ -z "${NO_ANIM:-}" ]; then
    for (( c = 0; c <= w; c += 4 )); do
      for l in "${lines[@]}"; do printf '  %s%s%s\e[K\n' "$(gradline "${l:0:c}" "$w")" "$DIM" "$(printf '%s' "${l:c}" | tr -c ' \n' '░')"; done
      printf '%s\e[%dA' "$R" "$n"; sleep 0.012
    done
  fi
  for l in "${lines[@]}"; do printf '  %s\e[K\n' "$(gradline "$l" "$w")"; done
  printf '  %ssetup · the software behind the h1n054ur desktop%s\n\n' "$DIM" "$R"
}

# ── running steps with a spinner ────────────────────────────────────────────────────────────────────
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
bar() {  # bar <done> <total> <width>
  local d=$1 t=$2 w=$3 f i out=""
  f=$(( t > 0 ? d * w / t : 0 ))
  for (( i = 0; i < w; i++ )); do
    if (( i < f )); then out+="$(grad "$i" "$w")█"; else out+="${LINE}░"; fi
  done
  printf '%s%s' "$out" "$R"
}
elapsed() { local s=$(( SECONDS - $1 )); printf '%d:%02d' $(( s / 60 )) $(( s % 60 )); }

# run_step <label> <total> <progress-regex> <command...>: runs the command in the background, logs its
# output, and shows a spinner, a bar and the elapsed time; progress is read from "(n/m)" lines when total>0
run_step() {
  local label=$1 total=$2 rx=$3; shift 3
  local start=$SECONDS i=0 done_n=0 now rc
  printf '\n### %s\n' "$label" >> "$LOG"
  if [ "$DRY" = 1 ]; then ( for (( k = 1; k <= total; k++ )); do echo "($k/$total) installing pkg$k"; sleep 0.08; done; sleep 0.4 ) >> "$LOG" 2>&1 &
  else "$@" >> "$LOG" 2>&1 & fi
  local pid=$!
  hide_cursor
  while kill -0 "$pid" 2>/dev/null; do
    if (( total > 0 )); then
      now=$(tail -n 40 "$LOG" | grep -oE "$rx" | tail -1 | grep -oE '^\(?[0-9]+' | tr -d '(')
      [ -n "$now" ] && done_n=$now
    fi
    printf '\r  %s%s%s %-30s ' "$GRN" "${SPIN[i++ % 10]}" "$R" "$label"
    (( total > 0 )) && printf '%s %s%3d/%-3d%s ' "$(bar "$done_n" "$total" 22)" "$DIM" "$done_n" "$total" "$R"
    printf '%s%s%s\e[K' "$DIM" "$(elapsed "$start")" "$R"
    sleep 0.1
  done
  wait "$pid"; rc=$?
  if [ "$rc" = 0 ]; then
    printf '\r  %s✔%s %-30s ' "$GRN" "$R" "$label"
    (( total > 0 )) && printf '%s %s%3d/%-3d%s ' "$(bar "$total" "$total" 22)" "$DIM" "$total" "$total" "$R"
  else
    printf '\r  %s✘%s %-30s %sfailed (exit %d), see the log%s ' "$RED" "$R" "$label" "$RED" "$rc" "$R"
  fi
  printf '%s%s%s\e[K\n' "$DIM" "$(elapsed "$start")" "$R"
  show_cursor
  return "$rc"
}


# ── checklist and pick-one ──────────────────────────────────────────────────────────────────────────
# checklist <title> <ids-array-name> <desc-assoc-name> <pick-assoc-name>
#   arrow keys / j k move, Space toggles, a all, n none, Enter confirms, q quits the script
checklist() {
  local title=$1; local -n _ids=$2 _desc=$3 _pick=$4
  local sel=0 key rest i id mark cur n=$(( ${#_ids[@]} + 2 ))
  printf '  %s%s%s\n\n' "$B" "$(gradline "$title")" "$R"
  _draw() {
    for i in "${!_ids[@]}"; do
      id=${_ids[$i]}
      if [ "${_pick[$id]:-0}" = 1 ]; then mark="${GRN}[■]${R}"; else mark="${DIM}[ ]${R}"; fi
      if [ "$i" = "$sel" ]; then cur="${GRN}❯${R}"; else cur=" "; fi
      printf '  %s %s %s%-10s%s %s%s%s\e[K\n' "$cur" "$mark" "$B$FG" "$id" "$R" "$DIM" "${_desc[$id]}" "$R"
    done
    printf '\n  %s↑↓ move · space pick · a all · n none · enter go · q quit%s\e[K\n' "$DIM" "$R"
  }
  hide_cursor; _draw
  while true; do
    IFS= read -rsn1 key
    if [ "$key" = $'\e' ]; then IFS= read -rsn2 -t 0.01 rest; key+=$rest; fi
    case $key in
      $'\e[A'|k) (( sel = (sel + ${#_ids[@]} - 1) % ${#_ids[@]} )) ;;
      $'\e[B'|j) (( sel = (sel + 1) % ${#_ids[@]} )) ;;
      ' ') id=${_ids[$sel]}; if [ "${_pick[$id]:-0}" = 1 ]; then _pick["$id"]=0; else _pick["$id"]=1; fi ;;
      a) for id in "${_ids[@]}"; do _pick["$id"]=1; done ;;
      n) for id in "${_ids[@]}"; do _pick["$id"]=0; done ;;
      '') break ;;
      q) show_cursor; printf '\n  %snothing changed%s\n' "$DIM" "$R"; exit 0 ;;
    esac
    printf '\e[%dA' "$n"; _draw
  done
  show_cursor; echo
}

# choose <title> <result-var-name> <option>...   one of several, arrow keys and Enter; sets the result to the index
choose() {
  local title=$1; local -n _out=$2; shift 2
  local opts=("$@") sel=0 key rest i n=$(( $# + 1 ))
  printf '  %s%s%s\n\n' "$B" "$(gradline "$title")" "$R"
  _drawc() {
    for i in "${!opts[@]}"; do
      if [ "$i" = "$sel" ]; then printf '  %s❯ %s%s\e[K\n' "$GRN" "${opts[$i]}" "$R"; else printf '    %s%s%s\e[K\n' "$DIM" "${opts[$i]}" "$R"; fi
    done
    printf '\n'
  }
  hide_cursor; _drawc
  while true; do
    IFS= read -rsn1 key
    if [ "$key" = $'\e' ]; then IFS= read -rsn2 -t 0.01 rest; key+=$rest; fi
    case $key in
      $'\e[A'|k) (( sel = (sel + ${#opts[@]} - 1) % ${#opts[@]} )) ;;
      $'\e[B'|j) (( sel = (sel + 1) % ${#opts[@]} )) ;;
      '') break ;;
    esac
    printf '\e[%dA' "$n"; _drawc
  done
  show_cursor; _out=$sel
}
