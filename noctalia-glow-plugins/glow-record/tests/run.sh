#!/usr/bin/env bash
# Check the library panel without Noctalia: turn the Luau-only syntax into Lua 5.x, syntax-check
# every file with luac -p, then run the harness (fake Noctalia API, canned recorder JSON).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="$(dirname "$here")"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

# Luau compound assignment `x += e` becomes `x = x + (e)`. Nothing else Luau-only is used.
to_lua() {
  sed -E 's/^([[:space:]]*)([A-Za-z_][A-Za-z0-9_.]*)[[:space:]]*([-+*/])=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1\2 = \2 \3 (\4)/' "$1"
}

mkdir -p "$out/lib"
to_lua "$plugin/panel.luau" > "$out/panel.lua"
to_lua "$plugin/lib/library.luau" > "$out/lib/library.lua"
for f in "$out/panel.lua" "$out/lib/library.lua"; do luac -p "$f"; done
echo "luac -p ok"
lua "$here/panel_test.lua" "$out"
