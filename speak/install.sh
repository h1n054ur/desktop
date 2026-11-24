#!/usr/bin/env bash
# Install speak: link the CLI and the TTS unit, copy the example config once.
# Safe to run again. It never enables or starts the unit.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$HOME/.local/bin"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/speak"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
voice_dir="${XDG_DATA_HOME:-$HOME/.local/share}/speak/voices"

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "ok      $dst"
    return
  fi
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$dst.bak-$(date +%Y%m%d%H%M%S)"
    echo "backup  $dst"
  fi
  ln -sfn "$src" "$dst"
  echo "linked  $dst"
}

# CLI
link "$here/bin/speak" "$bin_dir/speak"

# Config, only when missing so local voices and edits stay
mkdir -p "$config_dir" "$voice_dir"
if [ -e "$config_dir/config.toml" ]; then
  echo "ok      $config_dir/config.toml (kept)"
else
  cp "$here/config.example.toml" "$config_dir/config.toml"
  echo "copied  $config_dir/config.toml"
fi

# TTS server unit
link "$here/systemd/speak-tts.service" "$unit_dir/speak-tts.service"
systemctl --user daemon-reload 2>/dev/null || true

# --- speak-hooks: where helper, Claude Code hook, OpenCode plugin ---
ln -sfn "$here/bin/speak-where" "$HOME/.local/bin/speak-where"
# speak-focused was replaced by speak-where: drop an old link to it.
if [ -L "$HOME/.local/bin/speak-focused" ]; then rm -f "$HOME/.local/bin/speak-focused"; fi
mkdir -p "$HOME/.config/opencode/plugins"
ln -sfn "$here/opencode/speak.ts" "$HOME/.config/opencode/plugins/speak.ts"
# Claude Code reads the Stop hook from its settings. Preserve every existing setting and hook.
claude_settings="$HOME/.claude/settings.json"
if command -v jq >/dev/null; then
  mkdir -p "$(dirname "$claude_settings")"
  if [ -L "$claude_settings" ]; then
    claude_settings=$(readlink -f "$claude_settings")
  fi
  if [ ! -e "$claude_settings" ]; then
    printf '{}\n' > "$claude_settings"
  fi
  if jq empty "$claude_settings" >/dev/null 2>&1; then
    hook="$here/hooks/claude-stop.sh"
    tmp=$(mktemp "$(dirname "$claude_settings")/.speak-settings.XXXXXX")
    jq --arg command "$hook" '
      .hooks = (.hooks // {}) |
      .hooks.Stop = (.hooks.Stop // []) |
      if ([.hooks.Stop[]?.hooks[]?.command] | index($command)) then .
      else .hooks.Stop += [{"hooks":[{"type":"command","command":$command,"timeout":5}]}]
      end
    ' "$claude_settings" > "$tmp"
    chmod --reference="$claude_settings" "$tmp"
    mv "$tmp" "$claude_settings"
    echo "hooked  $claude_settings"
  else
    echo "warning $claude_settings is not valid JSON, so the Claude Code hook was not changed" >&2
  fi
else
  echo "warning jq is missing, so the Claude Code hook was not installed" >&2
fi

# --- end speak-hooks ---

# --- speak-bar: Noctalia bar plugin ---
mkdir -p "$HOME/.local/share/noctalia/plugins"
ln -sfn "$here/../noctalia-glow-plugins/glow-speak" "$HOME/.local/share/noctalia/plugins/glow-speak"
echo "Enable the bar button: noctalia msg plugins enable hani/glow-speak"

# --- end speak-bar ---

echo
echo "Next step (run it yourself once):"
echo "  systemctl --user enable --now speak-tts"
