#!/usr/bin/env bash
# Put the h1n054ur theme on a Jellyfin 10.11 server through its API.
#   apply.sh               save the current branding, then apply the theme and read it back
#   apply.sh --dry-run     print the plan and the sizes, change nothing, contact nothing
#   apply.sh --no-backup   apply without saving the current branding first
# Environment: JELLYFIN_URL (the server itself, not a proxy with a body size limit),
# JELLYFIN_API_KEY (an admin API key), SERVER_NAME (default h1n054ur),
# JELLYFIN_THEME_BACKUP_DIR (where the pre-apply backup goes, see backup/README.md).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
css="$here/dist/theme.css"
disclaimer="$here/src/login-disclaimer.html"
splash="$here/assets/splash.png"
server_name="${SERVER_NAME:-h1n054ur}"

die() { printf 'apply.sh: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
size() { wc -c < "$1" | tr -d ' '; }
sha() { sha256sum | cut -c1-16; }

dry=0
backup=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    --no-backup) backup=0 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option '$arg'" ;;
  esac
done

command -v jq >/dev/null || die "jq is needed"
command -v curl >/dev/null || die "curl is needed"

# Local checks first: a stale or broken build never reaches the server.
"$here/build.sh" --check || die "refusing to apply a stale or broken dist/theme.css"
[ -s "$disclaimer" ] || die "missing $disclaimer"
[ -s "$splash" ] || die "missing assets/splash.png"
[ "$(head -c8 "$splash" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a ] || die "assets/splash.png is not a PNG"
[ -n "$server_name" ] || die "SERVER_NAME is empty"

# The disclaimer is sent without its final newline, the way the dashboard stores it.
disclaimer_text="$(cat "$disclaimer")"
css_sha="$(sha < "$css")"
disclaimer_sha="$(printf '%s' "$disclaimer_text" | sha)"
splash_sha="$(sha < "$splash")"

backup_dir=""
if [ "$backup" = 0 ]; then
  backup_note="skipped (--no-backup)"
elif [ -n "${JELLYFIN_THEME_BACKUP_DIR:-}" ]; then
  backup_dir="$JELLYFIN_THEME_BACKUP_DIR"
  backup_note="save current branding, server name and custom splash to \$JELLYFIN_THEME_BACKUP_DIR"
else
  [ "$dry" = 1 ] || die "JELLYFIN_THEME_BACKUP_DIR is not set (set it, or pass --no-backup)"
  backup_note="NOT SET: a real run refuses without JELLYFIN_THEME_BACKUP_DIR or --no-backup"
fi

say "Plan:"
say "  1. backup: $backup_note"
say "  2. POST /System/Configuration/Branding"
say "       CustomCss        dist/theme.css            $(size "$css") bytes  sha256 $css_sha"
say "       LoginDisclaimer  src/login-disclaimer.html  ${#disclaimer_text} bytes  sha256 $disclaimer_sha"
say "       SplashscreenEnabled true"
say "  3. POST /Branding/Splashscreen  assets/splash.png  $(size "$splash") bytes (sent base64)  sha256 $splash_sha"
say "  4. POST /System/Configuration   ServerName '$server_name', every other field as read"
say "  5. read everything back and compare hashes"

if [ "$dry" = 1 ]; then
  say "Dry run: nothing sent."
  exit 0
fi

[ -n "${JELLYFIN_URL:-}" ] || die "JELLYFIN_URL is not set"
[ -n "${JELLYFIN_API_KEY:-}" ] || die "JELLYFIN_API_KEY is not set"
url="${JELLYFIN_URL%/}"

# The API key goes into a mode 600 header file, so it never shows up in a process list.
work="$(umask 077 && mktemp -d)"
trap 'rm -rf "$work"' EXIT
hdr="$work/auth.hdr"
(umask 077 && printf 'Authorization: MediaBrowser Token="%s"\n' "$JELLYFIN_API_KEY" > "$hdr")

# api METHOD PATH [curl args...]: body on stdout, fails on any non 2xx answer.
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

version="$(api GET /System/Info | jq -r '.Version')"
say "Server version $version"
case "$version" in 10.11.*) ;; *) say "warning: built and tested for 10.11, this server runs $version" ;; esac

api GET /System/Configuration/branding > "$work/branding-before.json"
api GET /System/Configuration > "$work/system.json"

if [ -n "$backup_dir" ]; then
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$backup_dir"
  out="$backup_dir/pre-apply-$stamp.json"
  splash_file=""
  # A custom splash shows as a SplashscreenLocation. Keep a copy so rollback can put it back.
  if [ -n "$(jq -r '.SplashscreenLocation // ""' "$work/branding-before.json")" ]; then
    splash_file="pre-apply-$stamp-splash.png"
    api GET "/Branding/Splashscreen?format=Png" > "$backup_dir/$splash_file"
  fi
  (umask 077 && jq --arg name "$(jq -r '.ServerName' "$work/system.json")" --arg splash "$splash_file" \
    '{LoginDisclaimer, CustomCss, SplashscreenEnabled, ServerName: $name, SplashscreenFile: $splash}' \
    "$work/branding-before.json" > "$out")
  say "Saved the current branding to $out"
fi

# 2. Branding. Only the three dashboard fields are sent. 10.11 keeps the splash location itself.
jq -n --rawfile css "$css" --arg disc "$disclaimer_text" \
  '{LoginDisclaimer: $disc, CustomCss: $css, SplashscreenEnabled: true}' > "$work/branding.json"
api POST /System/Configuration/Branding -H 'Content-Type: application/json' \
  --data-binary @"$work/branding.json" > /dev/null
say "Branding sent ($(size "$work/branding.json") bytes)"

# 3. Splash. Jellyfin expects the image base64 encoded, with the image type as Content-Type.
base64 -w0 "$splash" > "$work/splash.b64"
api POST /Branding/Splashscreen -H 'Content-Type: image/png' --data-binary @"$work/splash.b64" > /dev/null
say "Splash uploaded"

# 4. Server name: write back the whole configuration with only ServerName changed.
jq --arg name "$server_name" '.ServerName = $name' "$work/system.json" > "$work/system-new.json"
api POST /System/Configuration -H 'Content-Type: application/json' \
  --data-binary @"$work/system-new.json" > /dev/null
say "Server name sent"

# 5. Read back.
fail=0
check() { # check LABEL WANT GOT
  if [ "$2" = "$3" ]; then say "  ok    $1  $3"; else say "  FAIL  $1  want $2, got $3"; fail=1; fi
}
api GET /System/Configuration/branding > "$work/branding-after.json"
say "Read back:"
check "CustomCss          " "$css_sha" "$(jq -j '.CustomCss // ""' "$work/branding-after.json" | sha)"
check "LoginDisclaimer    " "$disclaimer_sha" "$(jq -j '.LoginDisclaimer // ""' "$work/branding-after.json" | sha)"
check "SplashscreenEnabled" "true" "$(jq -r '.SplashscreenEnabled' "$work/branding-after.json")"
check "/Branding/Css      " "$css_sha" "$(api GET /Branding/Css | sha)"
check "ServerName         " "$server_name" "$(api GET /System/Configuration | jq -r '.ServerName')"
check "ServerName (public)" "$server_name" "$(api GET /System/Info/Public | jq -r '.ServerName')"
api GET "/Branding/Splashscreen?format=Png" > "$work/splash-after"
[ -s "$work/splash-after" ] || { say "  FAIL  Splashscreen         empty answer"; fail=1; }
got_splash="$(sha < "$work/splash-after")"
if [ "$got_splash" = "$splash_sha" ]; then
  say "  ok    Splashscreen         $got_splash"
else
  # The server may re-encode the image on the way out, so a different hash alone is not a failure.
  say "  note  Splashscreen         served $got_splash, sent $splash_sha (re-encoded by the server)"
fi
[ "$fail" = 0 ] || die "read back does not match what was sent"
say "Applied. Reload the browser to see the theme."
