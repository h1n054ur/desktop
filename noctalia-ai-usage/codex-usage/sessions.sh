#!/bin/sh
# sessions.sh: open OpenCode sessions as one JSON array on stdout:
# [{id, title, cwd, status, since, waitingFor, tool, pid, terminal}], status busy | waiting | idle.
#
# Everything comes from the OpenCode background service's own HTTP API (`opencode serve --service`,
# the server `opencode api` talks to), read-only:
#   GET /api/session?parentID=null   root sessions, newest first (title, directory, times)
#   GET /api/session/active          sessions running right now (busy)
#   GET /api/permission/request      pending permission requests, per directory  -> waiting
#   GET /api/form                    pending questions (forms), per directory    -> waiting
#   GET /api/session/ID/message      the newest assistant message of a busy session, for its tool
# The service writes its URL and password to ~/.local/state/opencode/service.json. The password goes to
# curl in a config on stdin (never on a command line) and is not printed.
#
# Which sessions are "open": the API does not say which session a terminal shows, so every running
# OpenCode TUI (an `opencode` process that is not the server or a one-shot command) claims one: the
# session given with -s/--session, else the newest root session in its working directory. Claimed
# sessions are shown with that process's pid (for focus.sh); busy or waiting sessions are shown even
# with no TUI (`opencode run`, the web app). No service running prints [].
state=${XDG_STATE_HOME:-$HOME/.local/state}/opencode/service.json
[ -r "$state" ] || { echo '[]'; exit 0; }
spid=$(jq -r '.pid // empty' "$state" 2>/dev/null)
if [ -z "$spid" ] || ! kill -0 "$spid" 2>/dev/null; then echo '[]'; exit 0; fi

# get PATH [DIRECTORY]: GET a service path, scoped to DIRECTORY when given (x-opencode-directory).
get() {
  jq -r --arg p "$1" --arg d "${2:-}" '
    "user = \("opencode:\(.password)" | tojson)",
    "url = \("\(.url)\($p)" | tojson)",
    (if $d != "" then "header = \("x-opencode-directory: \($d)" | tojson)" else empty end)' "$state" \
    | curl -sf --max-time 5 -K -
}

roots=$(get '/api/session?parentID=null&limit=30&order=desc') || { echo 'opencode: session list failed' >&2; exit 1; }
active=$(get /api/session/active) || active='{"data":{}}'

# Running TUIs as [{pid, cwd, session, kitty, started}], newest first.
tuis=$(for pid in $(pgrep -x opencode); do
  args=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null) || continue
  sub=$(printf '%s\n' "$args" | sed -n '2{/^-/d;p;}')
  case $sub in serve|api|acp|run|session|auth|mcp|models|stats|debug|service|plugin|pair|reload|upgrade|update|uninstall) continue ;; esac
  sid=$(printf '%s\n' "$args" | sed -n '/^\(-s\|--session\)$/{n;p;q;}')
  cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null) || continue
  kitty=false
  tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q '^KITTY_WINDOW_ID=' && kitty=true
  started=$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)
  jq -nc --argjson p "$pid" --arg c "$cwd" --arg s "$sid" --argjson k "$kitty" --argjson t "${started:-0}" \
    '{pid: $p, cwd: $c, session: $s, kitty: $k, started: $t}'
done | jq -sc 'sort_by(-.started)')

# Pending permissions and questions for every directory that has a root session in the list.
dirs=$(printf '%s' "$roots" | jq -r '[.data[].location.directory] | unique | .[]')
pending=$(printf '%s\n' "$dirs" | while IFS= read -r d; do
  [ -n "$d" ] || continue
  get /api/permission/request "$d" | jq -c '.data[]? | {sessionID, text: ([.action, (.resources[0] // empty)] | join(" "))}'
  get /api/form "$d" | jq -c '.data[]? | {sessionID, text: .title}'
done | jq -sc .)

# Requests raised by subagent sessions belong to their root session: walk parentID up (3 levels).
known=$(printf '%s' "$roots" | jq -c '[.data[].id]')
pending=$(printf '%s' "$pending" | jq -c '.[]' | while IFS= read -r p; do
  sid=$(printf '%s' "$p" | jq -r .sessionID)
  n=0
  while [ $n -lt 3 ] && ! printf '%s' "$known" | jq -e --arg s "$sid" 'index($s)' >/dev/null; do
    parent=$(get "/api/session/$sid" | jq -r '.parentID // empty')
    [ -n "$parent" ] || break
    sid=$parent; n=$((n + 1))
  done
  printf '%s' "$p" | jq -c --arg s "$sid" '.sessionID = $s'
done | jq -sc .)

# The tool the newest assistant message is running, for busy sessions: "shell: git status".
tools=$(printf '%s' "$active" | jq -r '.data | keys[]' | while IFS= read -r sid; do
  get "/api/session/$sid/message?limit=1&order=desc&type=assistant" | jq -c --arg s "$sid" '
    [.data[0].content[]? | select(.type == "tool")] | last // empty
    | .state.input as $i
    | {id: $s, tool: ([.name, ($i.command // $i.description // $i.filePath // $i.path // $i.pattern // $i.url // empty
        | tostring | gsub("\\s+"; " ") | .[0:80])] | join(": "))}'
done | jq -sc 'map({key: .id, value: .tool}) | from_entries')

jq -nc --argjson roots "$roots" --argjson active "$active" --argjson tuis "$tuis" \
  --argjson pending "$pending" --argjson tools "$tools" '
  ($roots.data | map(select(.time.archived == null))) as $all
  # Each TUI claims one session: its -s id, else the newest unclaimed root session in its cwd.
  | (reduce $tuis[] as $t ({};
      . as $c
      | (if $t.session != "" then $t.session
         else ([$all[] | select(.location.directory == $t.cwd) | .id | select(. as $i | $c | has($i) | not)][0] // null) end) as $id
      | if $id == null then . else . + {($id): $t} end)) as $claimed
  | [$all[]
      | . as $s
      | ([$pending[] | select(.sessionID == $s.id)]) as $wait
      | (if ($wait | length) > 0 then "waiting" elif ($active.data | has($s.id)) then "busy" else "idle" end) as $status
      | select($claimed[$s.id] != null or $status != "idle")
      | {
          id: .id,
          title: (.title // "Untitled"),
          cwd: .location.directory,
          status: $status,
          since: (if $status == "idle" then (.time.idle // .time.updated) else .time.updated end),
          waitingFor: ($wait[0].text // ""),
          tool: ($tools[$s.id] // ""),
          pid: ($claimed[$s.id].pid // null),
          terminal: (if $claimed[$s.id] == null then null elif $claimed[$s.id].kitty then "kitty" else "terminal" end)
        }]'
