#!/bin/sh
# limits.sh fetch: print Muse Code plan limits as [{label, percent, resets_at}].
# First source: the usage file the OpenCode plugin open-muse writes after each Muse request
# (${XDG_STATE_HOME:-~/.local/state}/open-muse/usage.json). Reading it is cheap and starts nothing.
# Fallback when that file is missing or unreadable: ask a short-lived `muse serve` session host
# (MSP v1, newline-delimited JSON-RPC over stdio) for `usage/read`. The host is started with
# memory-only sessions, no shell and no workspace writes, never starts a session or a turn, and
# exits as soon as its stdin closes, so this makes no model request and costs no plan usage. It
# runs under `timeout`, which kills it if it hangs. `usage/read` only returns what that host has
# observed itself, and a fresh host observes nothing until it talks to the model: so that path
# usually prints [] (with a note on stderr) and the panel shows "no usage yet".
# Both sources carry the same usage object, mapped by the same jq below. A window whose reset
# time has passed has reset, so it shows as 0 with no reset time instead of its old percentage.
# Sign-in comes from Muse itself (`account/read`, state loggedOut), never from auth.json values.
# limits.sh plan: print the plan tier from the same source (empty when nothing was observed).
mode="${1:-fetch}"
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

# One usage object in, the plan tier or the window list out.
emit() {
  if [ "$mode" = plan ]; then
    # The tier id is verbatim from the provider; show it as words (everyday -> Everyday).
    # An all-digit tier is an opaque id, not a name, so print nothing and the panel says "Muse Code".
    printf '%s' "$1" | jq -r '(.tier // "" | tostring) | if test("^[0-9]+$") then "" else . end
      | gsub("[_-]"; " ") | ascii_downcase
      | split(" ") | map(select(. != "") | (.[:1] | ascii_upcase) + .[1:]) | join(" ")'
    return
  fi
  printf '%s' "$1" | jq -c '
    # Window length decides the label: 5h for the usual block, hours, days or minutes otherwise.
    def span: if . % 1440 == 0 then "\(. / 1440)d" elif . % 60 == 0 then "\(. / 60)h" else "\(.)m" end;
    # A reset time in the past means the window has started over since this was observed.
    def entry($label): if (.resetsAtMs // 0) > 0 and .resetsAtMs <= (now * 1000)
      then {label: $label, percent: 0, resets_at: null}
      else {label: $label, percent: .usedPercent,
            resets_at: (if (.resetsAtMs // 0) > 0 then (.resetsAtMs / 1000 | floor | todate) else null end)}
      end;
    [ (.window | objects | select(.usedPercent | numbers) | entry(.windowDurationMins // 300 | span)),
      (.weekly | objects | select(.usedPercent | numbers) | entry("7d")) ]'
}

file="${XDG_STATE_HOME:-$HOME/.local/state}/open-muse/usage.json"
if [ -r "$file" ] && usage=$(jq -ce 'objects' "$file" 2>/dev/null); then
  emit "$usage"
  exit 0
fi

command -v muse >/dev/null || { echo "muse not installed" >&2; exit 2; }
auth="${MUSE_AUTH_PATH:-${XDG_CONFIG_HOME:-$HOME/.config}/muse/auth.json}"
[ -e "$auth" ] || { echo "no Muse sign-in at $auth; run: muse login" >&2; exit 2; }
# The host answers every request, then exits on end of input. account/read needs the
# experimental surface; usage/read is stable. MUSE_NO_AUTO_UPDATE stops the launcher from
# starting a background update check on every poll.
err=$(mktemp) || exit 1
trap 'rm -f "$err"' EXIT
out=$(cd / && printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"muse_usage_noctalia","version":"1"},"capabilities":{"experimentalApi":true,"userInputDialogs":false}}}' \
  '{"jsonrpc":"2.0","method":"initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"account/read"}' \
  '{"jsonrpc":"2.0","id":3,"method":"usage/read"}' \
  | MUSE_NO_AUTO_UPDATE=1 timeout -k 2 15 muse serve --no-session-log --disable-shell --disable-write 2>"$err")
rc=$?
if [ "$rc" -ne 0 ]; then
  # Muse's own message can quote the auth file, so it is classified here, never printed.
  if grep -q 'auth file' "$err"; then echo "Muse could not read its sign-in; run: muse login" >&2; exit 2; fi
  echo "muse serve failed (exit $rc)" >&2
  exit 1
fi
reply() { printf '%s\n' "$out" | jq -c --argjson id "$1" 'select(.id == $id)' 2>/dev/null; }
account=$(reply 2)
usage=$(reply 3)
[ -n "$usage" ] || { echo "muse serve gave no usage/read answer" >&2; exit 1; }
if printf '%s' "$usage" | jq -e '.error' >/dev/null; then
  echo "usage/read failed: $(printf '%s' "$usage" | jq -r '.error.message')" >&2
  exit 1
fi
state=$(printf '%s' "$account" | jq -r '.result.state // empty')
[ "$state" != loggedOut ] || { echo "Muse is signed out; run: muse login" >&2; exit 2; }
usage=$(printf '%s' "$usage" | jq -c '.result.usage // empty')
if [ -z "$usage" ]; then
  echo "Muse has not reported usage yet (it only does with a model request)" >&2
  [ "$mode" = plan ] || echo '[]'
  exit 0
fi
emit "$usage"
