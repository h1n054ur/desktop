#!/usr/bin/env bash
# Install recorder: link the CLI, create the recordings and data folders.
# Safe to run again. It never starts anything.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="$HOME/.local/bin"
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/recorder"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/recorder"

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
link "$here/bin/recorder" "$bin_dir/recorder"
link "$here/bin/recorder-player" "$bin_dir/recorder-player"

# Folders
for d in "$HOME/Recordings" "$HOME/Recordings/.trash" "$data_dir" "$state_dir"; do
  if [ -d "$d" ]; then
    echo "ok      $d"
  else
    mkdir -p "$d"
    echo "created $d"
  fi
done
