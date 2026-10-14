#!/usr/bin/env bash
# Re-vendor the Abyss Jellyfin theme at a pinned commit into vendor/abyss/.
#   vendor/abyss/update.sh <abyss-commit>
# <abyss-commit> is a full 40 character commit sha of github.com/AumGupta/abyss-jellyfin.
# Needs bash, curl and python3 (stdlib only). Works from any directory. Does not run build.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'update-abyss: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
[ $# -eq 1 ] || die "usage: update.sh <abyss-commit>"
commit="$1"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "the Abyss commit must be a full 40 character sha"
for tool in curl python3; do
  command -v "$tool" >/dev/null || die "$tool is not installed"
done

# -I: isolated mode, so nothing next to the downloads can shadow a stdlib module.
python3 -I "$here/update.py" "$here" "$commit"
