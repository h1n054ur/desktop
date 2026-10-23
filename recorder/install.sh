#!/usr/bin/env bash
# Install recorder: link the CLI and the worker, link the worker's user unit, create the folders.
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

# CLI and transcription worker
link "$here/bin/recorder" "$bin_dir/recorder"
link "$here/bin/recorder-worker" "$bin_dir/recorder-worker"

# Worker user unit. Linked and loaded, never enabled or started: `recorder transcribe` starts it.
link "$here/systemd/recorder-worker.service" "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/recorder-worker.service"
if command -v systemctl >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
  systemctl --user daemon-reload
  echo "reload  systemd --user"
fi

# Folders
for d in "$HOME/Recordings" "$HOME/Recordings/.trash" "$data_dir" "$state_dir"; do
  if [ -d "$d" ]; then
    echo "ok      $d"
  else
    mkdir -p "$d"
    echo "created $d"
  fi
done
