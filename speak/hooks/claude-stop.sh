#!/bin/sh
# Claude Code Stop hook: read the finished reply aloud through `speak`.
#
# Speaks every reply that answers a prompt a person typed, focused or not. Stays quiet when:
#   - SPEAK_OFF=1 is set in the environment
#   - the session is not interactive: `claude -p` and SDK runs. Claude Code sets the entrypoint
#     to "sdk-cli" (or "sdk-ts", "sdk-py") for those and writes it on every transcript entry and in
#     CLAUDE_CODE_ENTRYPOINT. Only "cli" (the interactive CLI) or no entrypoint at all is spoken.
#   - the turn was continued by a stop hook (stop_hook_active is true)
#   - the prompt did not come from a person: a plugin prompt such as the auto "update", a task
#     notification, a slash command, or the literal text "update"
# Subagents fire SubagentStop, not Stop, so registering this on Stop only keeps them quiet.
# A reply that starts with a name label ("**Name:**") naming a voice in the speak config speaks in
# that voice, without the label (see `speak voice-from-reply`). When this session's kitty window
# is not focused, speak-where adds an intro such as "Workspace 3, Claude in desktop." before the
# reply, with the label's name in place of "Claude".
#
# It never blocks Claude: it prints nothing, always exits 0 and hands the text to `speak say`
# in the background. Env SPEAK_WHERE overrides the speak-where command (tests).

[ "${SPEAK_OFF:-}" = 1 ] && exit 0

input=$(cat)

# Prints the reply text to speak, or nothing when the turn should stay quiet.
text=$(printf '%s' "$input" | python3 -I -c '
import json, os, sys

try:
    hook = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if hook.get("stop_hook_active"):
    sys.exit(0)

AUTO_PREFIXES = (
    "<task-notification>", "<command-name>", "<command-message>", "<local-command",
    "<bash-input>", "<bash-stdout>", "<user-prompt-submit-hook>", "[Request interrupted",
    "The auto-update plugin sent a message",
)

def prompt_text(entry):
    """Text of a user prompt entry, or None when the entry is a tool result or meta line."""
    if entry.get("type") != "user" or entry.get("isMeta") or entry.get("isSidechain"):
        return None
    content = (entry.get("message") or {}).get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in content):
            return None
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        return "\n".join(parts) if parts else None
    return None

def typed_by_person(entry, text):
    origin = entry.get("origin")
    if isinstance(origin, dict) and origin.get("kind"):
        if origin.get("kind") != "human":
            return False
    elif text.lstrip().startswith(AUTO_PREFIXES):
        return False
    return text.strip().lower() != "update"

def lines_from_end(path, chunk=1 << 20):
    """Yield the lines of a file last first, reading it backwards so big transcripts stay fast."""
    with open(path, "rb") as f:
        pos = f.seek(0, 2)
        rest = b""
        while pos > 0:
            step = min(chunk, pos)
            pos -= step
            f.seek(pos)
            parts = (f.read(step) + rest).split(b"\n")
            rest = parts.pop(0)
            for raw in reversed(parts):
                yield raw.decode("utf-8", "replace")
        if rest:
            yield rest.decode("utf-8", "replace")

def find_turn(path):
    """Return (prompt entry, prompt text, assistant texts newest first) for the last turn."""
    assistant_after = []
    for line in lines_from_end(path):
        if "\"user\"" not in line and "\"assistant\"" not in line:
            continue
        try:
            entry = json.loads(line)
        except Exception:
            continue
        if entry.get("type") == "assistant" and not entry.get("isSidechain"):
            content = (entry.get("message") or {}).get("content")
            if isinstance(content, list):
                blocks = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
                if blocks:
                    assistant_after.append("\n".join(blocks))
            continue
        text = prompt_text(entry)
        if text is not None:
            return entry, text, assistant_after
    return None

try:
    turn = find_turn(hook.get("transcript_path") or "")
except Exception:
    sys.exit(0)
if turn is None:
    sys.exit(0)
entry, ptext, assistant_after = turn

if not typed_by_person(entry, ptext):
    sys.exit(0)

# Print mode and SDK runs are not someone at the keyboard. The prompt entry says how this turn
# was started, the environment covers transcripts without the field.
entrypoint = entry.get("entrypoint") or os.environ.get("CLAUDE_CODE_ENTRYPOINT") or ""
if entrypoint and entrypoint != "cli":
    sys.exit(0)

reply = hook.get("last_assistant_message")
if not isinstance(reply, str) or not reply.strip():
    # Fallback for versions without the field: the last assistant text of this turn.
    reply = assistant_after[0] if assistant_after else ""
if reply.strip():
    sys.stdout.write(reply)
' 2>/dev/null)

[ -n "$text" ] || exit 0

cwd=$(printf '%s' "$input" | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd") or "")
except Exception: pass' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
source="claude-code: $(basename "$cwd")"

# The session id plus a hash of the reply names this reply, so `speak say` drops it if the hook
# fires again for the same turn.
session=$(printf '%s' "$input" | python3 -I -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id") or "")
except Exception: pass' 2>/dev/null)
hash=$(printf '%s' "$text" | sha1sum | cut -c1-16)
id="claude:${session:-nosession}:$hash"

# Voice and name from the reply's label or the session's saved persona, else the claude voice.
picked=$(printf '%s' "$text" | speak voice-from-reply --tool claude --session "$session" 2>/dev/null)
voice=$(printf '%s' "$picked" | jq -r '.voice // empty' 2>/dev/null)
name=$(printf '%s' "$picked" | jq -r '.name // empty' 2>/dev/null)

intro=$(${SPEAK_WHERE:-speak-where} --kitty-pid "${KITTY_PID:-}" --kitty-window "${KITTY_WINDOW_ID:-}" \
  --agent claude --name "$name" --project "$cwd" 2>/dev/null)

printf '%s' "$text" | speak say --voice "${voice:-claude}" --source "$source" --id "$id" --intro "$intro" \
  --strip-label >/dev/null 2>&1 &
exit 0
