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

# --- speak-hooks: focus check, Claude Code hook, OpenCode plugin (added by the hooks task) ---

# --- end speak-hooks ---

# --- speak-bar: Noctalia bar plugin (added by the bar task) ---

# --- end speak-bar ---

echo
echo "Next step (run it yourself once):"
echo "  systemctl --user enable --now speak-tts"
