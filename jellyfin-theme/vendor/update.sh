#!/usr/bin/env bash
# Re-vendor ElegantFin and Cascadia Code, then rebuild dist/theme-<base>.css for every base.
#   vendor/update.sh <elegantfin-commit> [cascadia-version]
# <elegantfin-commit> is a full 40 character commit sha of github.com/lscambo13/ElegantFin.
# [cascadia-version] is the @fontsource/cascadia-code npm version (default 5.3.0).
# Needs bash, curl and python3 (stdlib only). Works from any directory.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'update.sh: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
[ $# -ge 1 ] && [ $# -le 2 ] || die "usage: update.sh <elegantfin-commit> [cascadia-version]"
commit="$1"
cascadia="${2:-5.3.0}"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "the ElegantFin commit must be a full 40 character sha"
[[ "$cascadia" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the Cascadia version must look like 5.3.0"
for tool in curl python3; do
  command -v "$tool" >/dev/null || die "$tool is not installed"
done

# -I: isolated mode, so nothing next to the downloads can shadow a stdlib module.
python3 -I "$here/update.py" "$here" "$commit" "$cascadia"
# VERSIONS goes into the header of every dist file, so every base is rebuilt.
for base in elegantfin abyss; do
  "$here/../build.sh" --base "$base"
done
