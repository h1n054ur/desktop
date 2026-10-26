#!/bin/sh
# sessions.sh: open OpenCode sessions as one JSON array on stdout:
# [{id, title, cwd, status, since, waitingFor, tool, pid, terminal, provider, model}],
# status busy | waiting | idle.
#
# Usage: sessions.sh [--keep-unknown] [--codex] [PROVIDER_PATTERN]
#   PROVIDER_PATTERN  a regex (jq/Oniguruma, ERE syntax works) matched against each session's provider
#                     id, e.g. '^openai$'; empty or left out = every session. This is how the Codex and
#                     Muse widgets split OpenCode's sessions between them.
#   --keep-unknown    also keep sessions whose provider cannot be told at all (see below).
#   --codex           also list Codex CLI sessions (see the end of this comment). Only the Codex widget
#                     passes it, so the Muse widget never shows them.
# provider/model come from the session's own model (Session.Info.model = {providerID, id}, set when a
# model is picked, so it is already in the list call). A brand new session can have none yet: then it
# runs on OpenCode's default model, read from the config the service resolved for its directory
# (GET /api/config, the last config document with a `model`). Only when that is missing too is the
# provider unknown ("") and the session kept only with --keep-unknown.
#
# Everything comes from the OpenCode background service's own HTTP API (`opencode serve --service`,
# the server `opencode api` talks to), read-only:
#   GET /api/session?parentID=null   root sessions, newest first (title, directory, times)
#   GET /api/session/active          sessions running right now (busy)
#   GET /api/permission/request      pending permission requests, per directory  -> waiting
#   GET /api/form                    pending questions (forms), per directory    -> waiting
#   GET /api/session/ID/message      the newest assistant message of a busy session, for its tool
#   GET /api/config                  the default model, only for sessions that have no model yet
# The service writes its URL and password to ~/.local/state/opencode/service.json. The password goes to
# curl in a config on stdin (never on a command line) and is not printed.
#
# Which sessions are "open": the API does not say which session a terminal shows, so every running
# OpenCode TUI (an `opencode` process that is not the server or a one-shot command) claims one: the
# session given with -s/--session, else the newest root session in its working directory. Claimed
# sessions are shown with that process's pid (for focus.sh); busy or waiting sessions are shown even
# with no TUI (`opencode run`, the web app). No service running prints [] (plus any Codex sessions).
#
# Codex CLI sessions (--codex, for example the ones Claude Code's codex plugin starts through
# `codex app-server`) come from Codex's own rollout files, $CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl,
# read-only. Only the day folders of today and yesterday are looked at, and in them only the 10 newest
# files changed in the last $CODEX_RECENT_MIN minutes. Of each file: the first lines (session_meta for
# id, cwd and provider, the first real user prompt for the title, cut to 80 characters) and the last MiB
# (turn_context for the model, task_started and task_complete or turn_aborted for the turn state). A
# turn that started and has not ended is busy, unless the file has not changed for $CODEX_STALE_MIN
# minutes or no codex process runs (a crashed run). No message text is printed beyond the title.
# These sessions have no terminal (pid and terminal are null) and carry app = "codex".
keep_unknown=false
codex=false
while :; do
  case ${1:-} in
    --keep-unknown) keep_unknown=true; shift ;;
    --codex) codex=true; shift ;;
    *) break ;;
  esac
done
pattern=${1:-}

CODEX_RECENT_MIN=120 # idle Codex sessions show for this long after their last change
CODEX_STALE_MIN=15   # a turn with no file change for this long no longer counts as busy

# codex_sessions: Codex CLI sessions as a JSON array in the same shape as the OpenCode ones.
codex_sessions() {
  root=${CODEX_HOME:-$HOME/.codex}/sessions
  files=$(find "$root/$(date +%Y/%m/%d)" "$root/$(date -d yesterday +%Y/%m/%d)" -maxdepth 1 \
    -name 'rollout-*.jsonl' -mmin -"$CODEX_RECENT_MIN" -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -n 10 | cut -d' ' -f2-)
  [ -n "$files" ] || { echo '[]'; return; }
  running=false
  pgrep -x codex >/dev/null && running=true
  now=$(date +%s)
  printf '%s\n' "$files" | while IFS= read -r f; do
    mtime=$(stat -c %Y "$f") || continue
    head=$(head -n 40 "$f" | jq -cR 'fromjson? | select(.type == "session_meta"
        or (.type == "response_item" and .payload.type == "message" and .payload.role == "user")
        or .type == "turn_context")
      | if .type == "session_meta" then {meta: (.payload | {id, cwd, provider: .model_provider})}
        elif .type == "turn_context" then {model: .payload.model}
        else {text: ([.payload.content[]? | select(.type == "input_text") | .text] | first // "")} end' \
      | jq -sc '{meta: (map(.meta // empty) | first),
          model: (map(.model // empty) | first),
          title: (map(.text // empty
            | select(startswith("# AGENTS.md instructions") or startswith("<") | not)
            | gsub("\\s+"; " ") | ltrimstr(" ") | .[0:80]) | first)}')
    tail -c 1048576 "$f" \
      | grep -E '"type":"(task_started|task_complete|turn_aborted|turn_context|custom_tool_call|custom_tool_call_output|function_call|function_call_output)"' \
      | jq -cR 'fromjson?' \
      | jq -sc --argjson h "$head" --argjson mt "$mtime" --argjson now "$now" --argjson run "$running" \
          --argjson stale "$CODEX_STALE_MIN" '
        def ms: sub("\\.[0-9]+Z$"; "Z") as $s | ($s | fromdateiso8601) * 1000
          + ((capture("\\.(?<f>[0-9]{3})") | .f | tonumber) // 0);
        ([.[] | select(.type == "event_msg"
            and (.payload.type | IN("task_started", "task_complete", "turn_aborted")))] | last) as $turn
        | ([.[] | select(.type == "turn_context") | .payload.model] | last // $h.model // "") as $model
        | ($turn != null and $turn.payload.type == "task_started" and $run
            and ($now - $mt) < $stale * 60) as $busy
        # The tool of the newest call in the running turn that has no output yet.
        | (if $busy then
            ([.[] | select(.type == "response_item")] | . as $items
              | [.[] | select(.payload.type | IN("custom_tool_call", "function_call"))] | last
              | select(. != null)
              | .payload as $c
              | if [$items[] | select(.payload.call_id == $c.call_id
                  and (.payload.type | endswith("_output")))] | length > 0 then "" else $c.name end)
             // ""
           else "" end) as $tool
        | select($h.meta != null)
        | {
            id: $h.meta.id,
            title: ($h.title // "Untitled"),
            cwd: $h.meta.cwd,
            status: (if $busy then "busy" else "idle" end),
            since: (if $turn != null then ($turn.timestamp | ms) else $mt * 1000 end),
            waitingFor: "",
            tool: ($tool // ""),
            pid: null,
            terminal: null,
            provider: ($h.meta.provider // "openai"),
            model: $model,
            app: "codex"
          }'
  done | jq -sc --arg pat "$pattern" 'map(select($pat == "" or (.provider | test($pat))))'
}
cdx='[]'
[ "$codex" = true ] && cdx=$(codex_sessions)

state=${XDG_STATE_HOME:-$HOME/.local/state}/opencode/service.json
[ -r "$state" ] || { printf '%s\n' "$cdx"; exit 0; }
spid=$(jq -r '.pid // empty' "$state" 2>/dev/null)
if [ -z "$spid" ] || ! kill -0 "$spid" 2>/dev/null; then printf '%s\n' "$cdx"; exit 0; fi

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

# Sessions with no model yet run on the default model of their directory's config: one /api/config
# per such directory (none at all while every session has a model, the usual case).
defaults=$(printf '%s' "$roots" | jq -r '[.data[] | select(.model.providerID == null) | .location.directory]
  | unique | .[]' | while IFS= read -r d; do
  [ -n "$d" ] || continue
  get /api/config "$d" | jq -c --arg d "$d" '[.[]?.info.model | select(. != null)] | last // empty
    | {key: $d, value: {provider: .providerID, model: .model}}'
done | jq -sc from_entries)

# Every root session with its provider and model, and whether it belongs to this widget.
roots=$(printf '%s' "$roots" | jq -c --argjson def "$defaults" --arg pat "$pattern" --argjson ku "$keep_unknown" '
  .data |= map(
    (if .model.providerID then {provider: .model.providerID, model: .model.id}
     else ($def[.location.directory] // {provider: "", model: ""}) end) as $m
    | . + {provider: ($m.provider // ""), modelName: ($m.model // "")}
    | .mine = (if .provider == "" then ($pat == "" or $ku) else ($pat == "" or (.provider | test($pat))) end))') \
  || { echo "opencode: bad provider pattern: $pattern" >&2; exit 1; }

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
dirs=$(printf '%s' "$roots" | jq -r '[.data[] | select(.mine) | .location.directory] | unique | .[]')
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

# The tool the newest assistant message is running, for this widget's busy sessions: "shell: git status".
tools=$(printf '%s' "$active" | jq -r --argjson roots "$roots" '
  ([$roots.data[] | select(.mine == false) | .id]) as $other | .data | keys[] | select(. as $i | $other | index($i) | not)' | while IFS= read -r sid; do
  get "/api/session/$sid/message?limit=1&order=desc&type=assistant" | jq -c --arg s "$sid" '
    [.data[0].content[]? | select(.type == "tool")] | last // empty
    | .state.input as $i
    | {id: $s, tool: ([.name, ($i.command // $i.description // $i.filePath // $i.path // $i.pattern // $i.url // empty
        | tostring | gsub("\\s+"; " ") | .[0:80])] | join(": "))}'
done | jq -sc 'map({key: .id, value: .tool}) | from_entries')

jq -nc --argjson roots "$roots" --argjson active "$active" --argjson tuis "$tuis" \
  --argjson pending "$pending" --argjson tools "$tools" --argjson codex "$cdx" '
  ($roots.data | map(select(.time.archived == null))) as $all
  # Each TUI claims one session: its -s id, else the newest unclaimed root session in its cwd. Claims
  # run over the sessions of every provider, so a TUI on a Muse session never claims an older OpenAI one.
  | (reduce $tuis[] as $t ({};
      . as $c
      | (if $t.session != "" then $t.session
         else ([$all[] | select(.location.directory == $t.cwd) | .id | select(. as $i | $c | has($i) | not)][0] // null) end) as $id
      | if $id == null then . else . + {($id): $t} end)) as $claimed
  | [$all[]
      | select(.mine)
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
          terminal: (if $claimed[$s.id] == null then null elif $claimed[$s.id].kitty then "kitty" else "terminal" end),
          provider: .provider,
          model: .modelName
        }] + $codex'
