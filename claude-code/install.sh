#!/usr/bin/env bash
# Installs the h1n054ur look for Claude Code: the theme, the status line and the two mods
# (task sidebar, agent tabs). Links everything to this checkout, so a pull updates it.
# Needs jq. Start a new Claude Code session afterwards.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$cfg/settings.json"
stamp=$(date +%Y%m%d-%H%M%S)

command -v jq >/dev/null || { echo "jq is needed to edit $settings"; exit 1; }

# link <target> <path>: point path at this checkout, moving aside a real file that was there
link() {
  mkdir -p "$(dirname "$2")"
  if [ -L "$2" ]; then rm "$2"; elif [ -e "$2" ]; then mv "$2" "$2.bak-$stamp"; fi
  ln -s "$1" "$2"
  echo "  linked $2"
}

link "$here/themes/h1n054ur.json" "$cfg/themes/h1n054ur.json"
mods=()
for m in task-sidebar agent-tabs; do
  link "$here/mods/$m" "$cfg/mods/$m"
  mods+=("$cfg/mods/$m")
done

# Theme, status line, and the mods added to CLAUDE_CODE_PLUGIN_DIRS (keeping any already there)
[ -f "$settings" ] || echo '{}' > "$settings"
cp "$settings" "$settings.bak-$stamp"
jq --arg line "$here/statusline.sh" --arg mods "$(IFS=:; echo "${mods[*]}")" '
  .theme = "custom:h1n054ur"
  | .statusLine = { type: "command", command: $line, refreshInterval: 30 }
  | .env.CLAUDE_CODE_PLUGIN_DIRS = (
      [ (.env.CLAUDE_CODE_PLUGIN_DIRS // "" | split(":")[]), ($mods | split(":")[]) ]
      | map(select(. != "")) | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end) | join(":")
    )
' "$settings.bak-$stamp" > "$settings"
echo "  updated $settings (backup: settings.json.bak-$stamp)"
echo "Done. Start a new Claude Code session to load the theme and the mods."
