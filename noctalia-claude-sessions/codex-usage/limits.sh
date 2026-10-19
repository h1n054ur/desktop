#!/bin/sh
# limits.sh fetch [DB]: print ChatGPT plan (Codex) limits as [{label, percent, resets_at}] using
# OpenCode's own OpenAI sign-in, read from the active `openai` row of the `credential` table in
# OpenCode's SQLite store (DB, default ~/.local/share/opencode/opencode.db). The row's value is
# JSON: {type: "oauth", methodID, access, refresh, expires (epoch ms), metadata: {accountID}}.
# Read-only: we never refresh the token (OpenCode owns it and refreshes it itself); if it has
# expired we just fail until OpenCode refreshes it. The token goes to curl on stdin, so it never
# appears in the process list, and is never printed.
# Only the legacy Codex sign-ins (chatgpt-browser, chatgpt-headless) can read usage. OpenCode's
# default "Sign in with ChatGPT" (chatgpt-token-sharing) token is admitted only on the Responses
# API, so wham/usage refuses it (401 no_matching_rule); that case exits 2 with a hint.
# limits.sh plan [DB]: print the plan name (Plus, Pro, ...) from the same response.
mode="${1:-fetch}"
db="${2:-$HOME/.local/share/opencode/opencode.db}"
command -v sqlite3 >/dev/null || { echo "sqlite3 not found" >&2; exit 2; }
[ -r "$db" ] || { echo "no OpenCode database at $db" >&2; exit 2; }
cred=$(sqlite3 -readonly "$db" \
  "select value from credential where integration_id = 'openai' order by active desc limit 1" 2>/dev/null)
token=$(printf '%s' "$cred" | jq -r 'select(.type == "oauth") | .access // empty' 2>/dev/null)
[ -n "$token" ] || { echo "no OpenCode OpenAI sign-in in $db" >&2; exit 2; }
method=$(printf '%s' "$cred" | jq -r '.methodID // empty')
if [ "$method" = chatgpt-token-sharing ]; then
  echo "OpenCode's 'Sign in with ChatGPT' cannot read usage; sign in with 'Codex browser (legacy)'" >&2
  exit 2
fi
expires=$(printf '%s' "$cred" | jq -r '.expires // 0')
[ "$expires" -gt "$(($(date +%s) * 1000))" ] || { echo "OAuth token expired" >&2; exit 3; }
account=$(printf '%s' "$cred" | jq -r '.metadata.accountID // empty')
cred=""
# Body and status code come back together; the last line is the code.
resp=$( { printf 'header = "Authorization: Bearer %s"\n' "$token"
          [ -n "$account" ] && printf 'header = "ChatGPT-Account-Id: %s"\n' "$account"; } \
  | curl -sS --max-time 15 -K - -w '\n%{http_code}' \
      -H 'User-Agent: codex-usage-noctalia' -H 'Accept: application/json' \
      https://chatgpt.com/backend-api/wham/usage) || exit 1
token=""
code=$(printf '%s' "$resp" | tail -n 1)
body=$(printf '%s' "$resp" | sed '$d')
case "$code" in
  200) ;;
  401) if printf '%s' "$body" | jq -e '.error.type == "rejected_by_access_enforcement"' >/dev/null 2>&1; then
         echo "this OpenCode sign-in cannot read usage; sign in with 'Codex browser (legacy)'" >&2; exit 2
       fi
       echo "OAuth token rejected (401)" >&2; exit 3 ;;
  *) echo "usage request failed: HTTP $code" >&2; exit 1 ;;
esac
if [ "$mode" = plan ]; then
  printf '%s' "$body" | jq -r '.plan_type // empty | (.[:1] | ascii_upcase) + .[1:]'
  exit 0
fi
printf '%s' "$body" | jq -c '
  # Window length decides the label: 5h and 7d for the usual pair, hours or days otherwise.
  def span: if . == 18000 then "5h" elif . == 604800 then "7d"
            elif . % 86400 == 0 then "\(. / 86400)d" else "\(. / 3600 | floor)h" end;
  def windows($prefix): [.primary_window, .secondary_window] | map(select(. != null) | {
    label: ($prefix + (.limit_window_seconds | span)),
    percent: .used_percent,
    resets_at: (if (.reset_at // 0) > 0 then (.reset_at | todate) else null end) });
  ((.rate_limit // {}) | windows(""))
  + ([.additional_rate_limits // [] | .[] | (.rate_limit // {}) as $r
      | (.limit_name // .metered_feature // "?") as $n | $r | windows($n + " ")] | add // [])'
