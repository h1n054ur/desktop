#!/usr/bin/env bash
# Install and start the OxiCloud rclone mount as a systemd user service.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dry_run=0

usage() {
  printf 'Usage: %s [--dry-run]\n' "${0##*/}"
}

case "${1:-}" in
  "") ;;
  --dry-run) dry_run=1 ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { usage >&2; exit 2; }

credentials_file="$HOME/.config/oxicloud/credentials"
config_file="$HOME/.config/oxicloud/rclone.conf"
helper_file="$HOME/.local/libexec/oxicloud-files-mount"
unit_file="$HOME/.config/systemd/user/oxicloud-files.service"
mount_dir="$HOME/Files"
cache_dir="$HOME/.cache/rclone/oxicloud"
syncthing_ignore="$HOME/.stignore"

say() {
  printf '%-8s %s\n' "$1" "$2"
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'filesmount: required command is missing: %s\n' "$1" >&2
    exit 1
  }
}

validate_credentials() {
  [ -f "$credentials_file" ] || {
    printf 'filesmount: create %s first, as described in README.md\n' "$credentials_file" >&2
    exit 1
  }
  [ "$(stat -c '%a' "$credentials_file")" = 600 ] || {
    printf 'filesmount: credential file must be mode 600: %s\n' "$credentials_file" >&2
    exit 1
  }
  awk 'NR > 2 || $0 == "" { bad = 1 } END { exit bad || NR != 2 }' "$credentials_file" || {
    printf 'filesmount: credential file must contain username and app password on two non-empty lines\n' >&2
    exit 1
  }
}

install_dir() {
  local mode=$1 path=$2
  if [ "$dry_run" = 1 ]; then
    say "would" "install -d -m $mode $path"
  else
    install -d -m "$mode" "$path"
    say "ready" "$path"
  fi
}

install_file() {
  local mode=$1 source=$2 target=$3
  if [ "$dry_run" = 1 ]; then
    say "would" "install -m $mode $source $target"
  else
    install -m "$mode" "$source" "$target"
    say "installed" "$target"
  fi
}

ensure_syncthing_ignore() {
  if grep -Fqx '/Files' "$syncthing_ignore" 2>/dev/null; then
    say "ready" "$syncthing_ignore ignores /Files"
    return
  fi
  if [ "$dry_run" = 1 ]; then
    say "would" "add /Files to $syncthing_ignore before starting the mount"
    return
  fi

  if [ ! -e "$syncthing_ignore" ]; then
    install -m 644 /dev/null "$syncthing_ignore"
  elif [ ! -f "$syncthing_ignore" ]; then
    printf 'filesmount: Syncthing ignore path is not a regular file: %s\n' "$syncthing_ignore" >&2
    exit 1
  fi
  if [ -s "$syncthing_ignore" ] && [ -n "$(tail -c 1 "$syncthing_ignore")" ]; then
    printf '\n' >> "$syncthing_ignore"
  fi
  printf '\n// OxiCloud mount, managed by ~/desktop/filesmount\n/Files\n' >> "$syncthing_ignore"
  say "updated" "$syncthing_ignore ignores /Files"
}

for command_name in rclone fusermount3 systemctl install stat awk; do
  need_command "$command_name"
done

if [ "$dry_run" = 0 ]; then
  validate_credentials
  systemctl --user show-environment >/dev/null 2>&1 || {
    printf 'filesmount: the systemd user manager is not available\n' >&2
    exit 1
  }
else
  say "dry-run" "no files, services or mounts will be changed"
fi

install_dir 700 "$HOME/.config/oxicloud"
install_dir 755 "$HOME/.local/libexec"
install_dir 755 "$HOME/.config/systemd/user"
install_dir 700 "$mount_dir"
install_dir 700 "$cache_dir"

install_file 600 "$here/rclone.conf" "$config_file"
install_file 755 "$here/bin/oxicloud-files-mount" "$helper_file"
install_file 644 "$here/systemd/oxicloud-files.service" "$unit_file"
ensure_syncthing_ignore

if [ "$dry_run" = 1 ]; then
  say "would" "$helper_file --check"
  say "would" "systemctl --user daemon-reload"
  say "would" "systemctl --user enable oxicloud-files.service"
  say "would" "systemctl --user restart oxicloud-files.service"
  exit 0
fi

"$helper_file" --check
systemctl --user daemon-reload
systemctl --user enable oxicloud-files.service
systemctl --user restart oxicloud-files.service
say "mounted" "$mount_dir"
