#!/usr/bin/env bash
# Take the theme off a Jellyfin 10.11 server: put back the branding, splash and server name
# from a backup, then read them back.
#   rollback.sh [--dry-run] [SOURCE]
# SOURCE is a pre-apply-<time>.json written by apply.sh, or a snapshot folder holding
# branding.json, server-name.txt and optionally custom.css, login-disclaimer.html and splash.png.
# Without SOURCE: $JELLYFIN_THEME_BACKUP_DIR itself when it holds branding.json, else the newest
# pre-apply-*.json in it. --dry-run prints the plan and sizes and contacts nothing.
# Environment: JELLYFIN_URL, JELLYFIN_API_KEY (admin), JELLYFIN_THEME_BACKUP_DIR.
set -euo pipefail

die() { printf 'rollback.sh: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
size() { wc -c < "$1" | tr -d ' '; }
sha() { sha256sum | cut -c1-16; }

dry=0
src=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option '$arg'" ;;
    *) [ -z "$src" ] || die "give one SOURCE only"; src="$arg" ;;
  esac
done

command -v jq >/dev/null || die "jq is needed"
command -v curl >/dev/null || die "curl is needed"

if [ -z "$src" ]; then
  dir="${JELLYFIN_THEME_BACKUP_DIR:-}"
  [ -n "$dir" ] || die "give a SOURCE or set JELLYFIN_THEME_BACKUP_DIR"
  [ -d "$dir" ] || die "JELLYFIN_THEME_BACKUP_DIR is not a folder: $dir"
  if [ -f "$dir/branding.json" ]; then
    src="$dir"
  else
    # pre-apply-<UTC stamp>.json sorts by time, the last one is the newest.
    src="$(find "$dir" -maxdepth 1 -name 'pre-apply-*.json' | LC_ALL=C sort | tail -n1)"
    [ -n "$src" ] || die "no branding.json and no pre-apply-*.json in $dir"
  fi
fi

work="$(umask 077 && mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Normalise either layout into: $work/branding.json (the three dashboard fields), $name, $splash.
splash=""
if [ -d "$src" ]; then
  layout="snapshot folder"
  [ -f "$src/branding.json" ] || die "$src has no branding.json"
  [ -f "$src/server-name.txt" ] || die "$src has no server-name.txt"
  jq -e 'type == "object" and has("LoginDisclaimer") and has("CustomCss") and has("SplashscreenEnabled")' \
    "$src/branding.json" > /dev/null || die "$src/branding.json lacks LoginDisclaimer, CustomCss or SplashscreenEnabled"
  # The loose copies must agree with branding.json (final newlines aside), or the snapshot is not trusted.
  if [ -f "$src/custom.css" ] && [ "$(cat "$src/custom.css")" != "$(jq -r '.CustomCss // ""' "$src/branding.json")" ]; then
    die "$src/custom.css differs from CustomCss in branding.json"
  fi
  if [ -f "$src/login-disclaimer.html" ] && [ "$(cat "$src/login-disclaimer.html")" != "$(jq -r '.LoginDisclaimer // ""' "$src/branding.json")" ]; then
    die "$src/login-disclaimer.html differs from LoginDisclaimer in branding.json"
  fi
  name="$(cat "$src/server-name.txt")"
  for f in splash.png splashscreen.png; do
    if [ -f "$src/$f" ]; then splash="$src/$f"; break; fi
  done
  jq '{LoginDisclaimer, CustomCss, SplashscreenEnabled}' "$src/branding.json" > "$work/branding.json"
elif [ -f "$src" ]; then
  layout="pre-apply backup"
  jq -e 'type == "object" and has("LoginDisclaimer") and has("CustomCss") and has("SplashscreenEnabled") and has("ServerName")' \
    "$src" > /dev/null || die "$src is not a pre-apply backup from apply.sh"
  name="$(jq -r '.ServerName' "$src")"
  f="$(jq -r '.SplashscreenFile // ""' "$src")"
  if [ -n "$f" ]; then
    splash="$(dirname "$src")/$f"
    [ -f "$splash" ] || die "the backup names splash file $f, but it is missing"
  fi
  jq '{LoginDisclaimer, CustomCss, SplashscreenEnabled}' "$src" > "$work/branding.json"
else
  die "no such file or folder: $src"
fi
[ -n "$name" ] || die "the backup has an empty server name"
if [ -n "$splash" ]; then
  [ "$(head -c8 "$splash" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ] || die "$splash is not a PNG"
fi

css_sha="$(jq -j '.CustomCss // ""' "$work/branding.json" | sha)"
disc_sha="$(jq -j '.LoginDisclaimer // ""' "$work/branding.json" | sha)"
enabled="$(jq -r '.SplashscreenEnabled' "$work/branding.json")"

say "Restore from $src ($layout):"
say "  1. POST /System/Configuration/Branding"
say "       CustomCss        $(jq -j '.CustomCss // ""' "$work/branding.json" | wc -c | tr -d ' ') bytes  sha256 $css_sha"
say "       LoginDisclaimer  $(jq -j '.LoginDisclaimer // ""' "$work/branding.json" | wc -c | tr -d ' ') bytes  sha256 $disc_sha"
say "       SplashscreenEnabled $enabled"
if [ -n "$splash" ]; then
  splash_sha="$(sha < "$splash")"
  say "  2. POST /Branding/Splashscreen  $(basename "$splash")  $(size "$splash") bytes (sent base64)  sha256 $splash_sha"
else
  say "  2. DELETE /Branding/Splashscreen (the backup had no custom splash)"
fi
say "  3. POST /System/Configuration   ServerName '$name', every other field as read"
say "  4. read everything back and compare hashes"

if [ "$dry" = 1 ]; then
  say "Dry run: nothing sent."
  exit 0
fi

[ -n "${JELLYFIN_URL:-}" ] || die "JELLYFIN_URL is not set"
[ -n "${JELLYFIN_API_KEY:-}" ] || die "JELLYFIN_API_KEY is not set"
url="${JELLYFIN_URL%/}"

# The API key goes into a mode 600 header file, so it never shows up in a process list.
hdr="$work/auth.hdr"
(umask 077 && printf 'Authorization: MediaBrowser Token="%s"\n' "$JELLYFIN_API_KEY" > "$hdr")

api() {
  local method="$1" path="$2" code
  shift 2
  code="$(curl -sS -o "$work/resp" -w '%{http_code}' -X "$method" -H @"$hdr" "$@" "$url$path")" \
    || die "$method $path: request failed"
  case "$code" in
    2??) cat "$work/resp" ;;
    *) die "$method $path: HTTP $code $(head -c 300 "$work/resp")" ;;
  esac
}

say "Server version $(api GET /System/Info | jq -r '.Version')"

api POST /System/Configuration/Branding -H 'Content-Type: application/json' \
  --data-binary @"$work/branding.json" > /dev/null
say "Branding restored"

if [ -n "$splash" ]; then
  base64 -w0 "$splash" > "$work/splash.b64"
  api POST /Branding/Splashscreen -H 'Content-Type: image/png' --data-binary @"$work/splash.b64" > /dev/null
  say "Splash restored"
else
  api DELETE /Branding/Splashscreen > /dev/null
  say "Custom splash deleted"
fi

api GET /System/Configuration > "$work/system.json"
jq --arg name "$name" '.ServerName = $name' "$work/system.json" > "$work/system-new.json"
api POST /System/Configuration -H 'Content-Type: application/json' \
  --data-binary @"$work/system-new.json" > /dev/null
say "Server name restored"

fail=0
check() { # check LABEL WANT GOT
  if [ "$2" = "$3" ]; then say "  ok    $1  $3"; else say "  FAIL  $1  want $2, got $3"; fail=1; fi
}
api GET /System/Configuration/branding > "$work/after.json"
say "Read back:"
check "CustomCss          " "$css_sha" "$(jq -j '.CustomCss // ""' "$work/after.json" | sha)"
check "LoginDisclaimer    " "$disc_sha" "$(jq -j '.LoginDisclaimer // ""' "$work/after.json" | sha)"
check "SplashscreenEnabled" "$enabled" "$(jq -r '.SplashscreenEnabled' "$work/after.json")"
check "/Branding/Css      " "$css_sha" "$(api GET /Branding/Css | sha)"
check "ServerName         " "$name" "$(api GET /System/Configuration | jq -r '.ServerName')"
if [ -n "$splash" ]; then
  check "custom splash set  " "yes" "$(jq -r 'if (.SplashscreenLocation // "") != "" then "yes" else "no" end' "$work/after.json")"
else
  check "custom splash set  " "no" "$(jq -r 'if (.SplashscreenLocation // "") != "" then "yes" else "no" end' "$work/after.json")"
fi
[ "$fail" = 0 ] || die "read back does not match the backup"
say "Rolled back. Reload the browser to see it."
