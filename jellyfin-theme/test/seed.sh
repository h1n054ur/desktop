#!/usr/bin/env bash
# Seed the throwaway test Jellyfin: download a few free films, start the container,
# finish the setup wizard, add libraries, scan, make an API key, mark one film half watched.
# Safe to run again: every step checks whether it is already done.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE=${JF_TEST_STATE:-$HOME/.cache/jellyfin-theme-test}
MEDIA=${JF_TEST_MEDIA:-$STATE/media}
URL=${JF_TEST_URL:-http://127.0.0.1:8097}
ADMIN=test
AUTH_BASE='MediaBrowser Client="theme-test-seed", Device="seed", DeviceId="theme-test-seed", Version="1.0"'
UA='jellyfin-theme-test-seed/1.0'

log() { printf '== %s\n' "$*"; }
die() { printf 'seed: %s\n' "$*" >&2; exit 1; }
for c in curl jq docker; do command -v "$c" >/dev/null || die "needs $c"; done

# ---- 1. media (public domain and Creative Commons, about 270 MB in total) ----
# dest|url
FILES=(
  "movies/Big Buck Bunny (2008)/Big Buck Bunny (2008).mp4|https://archive.org/download/BigBuckBunny_124/Content/big_buck_bunny_720p_surround.mp4"
  "movies/Sintel (2010)/Sintel (2010).mp4|https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4"
  "movies/Sintel (2010)/poster.jpg|https://archive.org/download/Sintel/Poster.jpg"
  "movies/Tears of Steel (2012)/Tears of Steel (2012).mp4|https://archive.org/download/Tears-of-Steel/tears_of_steel_720p.mp4"
  "movies/Tears of Steel (2012)/poster.jpg|https://archive.org/download/Tears-of-Steel/tos-poster.jpg"
  "movies/The Count (1916)/The Count (1916).mp4|https://archive.org/download/CC_1916_09_04_TheCount/CC_1916_09_04_TheCount_512kb.mp4"
  "shows/Caminandes (2013)/poster.png|https://archive.org/download/Caminandes/Caminandes.png"
  "shows/Caminandes (2013)/Season 01/Caminandes S01E01.ogv|https://archive.org/download/caminandes-1-llama-drama/1_Caminandes1_Llama_Drama_720p_vp8.ogv"
  "shows/Caminandes (2013)/Season 01/Caminandes S01E02.ogv|https://archive.org/download/caminandes-2-gran-dillama/1_Caminandes2_Gran_Dillama_720p_vp8.ogv"
)
log "media in $MEDIA"
mkdir -p "$STATE" "$MEDIA/movies" "$MEDIA/shows"
for entry in "${FILES[@]}"; do
  dest="$MEDIA/${entry%%|*}" src="${entry#*|}"
  [[ -s "$dest" ]] && continue
  mkdir -p "$(dirname "$dest")"
  printf '   fetching %s\n' "${entry%%|*}"
  curl -fsSL --retry 3 -A "$UA" -o "$dest.part" "$src" || die "download failed: $src"
  mv "$dest.part" "$dest"
done
du -sh "$MEDIA" | sed 's/^/   total /'

# ---- 2. container ----
log "starting container"
JF_TEST_MEDIA="$MEDIA" docker compose -f "$HERE/compose.yaml" up -d >/dev/null
for _ in $(seq 1 90); do
  curl -fsS "$URL/System/Info/Public" >/dev/null 2>&1 && break
  sleep 2
done
info=$(curl -fsS "$URL/System/Info/Public") || die "server did not answer on $URL"

api() { # api METHOD PATH [json-body]
  local args=(-fsS -X "$1" -H "Authorization: $AUTH" "$URL$2")
  [[ $# -ge 3 ]] && args+=(-H 'Content-Type: application/json' -d "$3")
  curl "${args[@]}"
}

# ---- 3. setup wizard ----
umask 077
if [[ $(jq -r .StartupWizardCompleted <<<"$info") != true ]]; then
  log "running the setup wizard"
  [[ -s "$STATE/admin.txt" ]] || head -c 24 /dev/urandom | base64 | tr -d '/+=' >"$STATE/admin.txt"
  pw=$(<"$STATE/admin.txt")
  AUTH=$AUTH_BASE
  # The wizard endpoints need a few seconds after first boot before they accept writes.
  for _ in $(seq 1 30); do api GET /Startup/User >/dev/null 2>&1 && break; sleep 2; done
  api POST /Startup/Configuration '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' >/dev/null
  api GET /Startup/User >/dev/null
  api POST /Startup/User "$(jq -nc --arg n "$ADMIN" --arg p "$pw" '{Name:$n,Password:$p}')" >/dev/null
  api POST /Startup/RemoteAccess '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}' >/dev/null
  api POST /Startup/Complete >/dev/null
fi
chmod 600 "$STATE/admin.txt"

log "signing in as $ADMIN"
AUTH=$AUTH_BASE
login=$(api POST /Users/AuthenticateByName "$(jq -nc --arg n "$ADMIN" --arg p "$(<"$STATE/admin.txt")" '{Username:$n,Pw:$p}')") \
  || die "sign-in failed (delete the volumes and $STATE/admin.txt to start over)"
AUTH="$AUTH_BASE, Token=\"$(jq -r .AccessToken <<<"$login")\""
USER_ID=$(jq -r .User.Id <<<"$login")

# ---- 4. server name ----
cfg=$(api GET /System/Configuration)
if [[ $(jq -r .ServerName <<<"$cfg") != h1n054ur ]]; then
  log "setting server name"
  api POST /System/Configuration "$(jq -c '.ServerName="h1n054ur"' <<<"$cfg")" >/dev/null
fi

# ---- 5. libraries ----
existing=$(api GET /Library/VirtualFolders | jq -r '.[].Name')
add_lib() { # name type path
  grep -qx "$1" <<<"$existing" && return 0
  log "adding library $1"
  local opts='{"LibraryOptions":{"EnableRealtimeMonitor":false,"EnableChapterImageExtraction":false,"EnableTrickplayImageExtraction":false,"SaveLocalMetadata":false}}'
  api POST "/Library/VirtualFolders?name=$1&collectionType=$2&paths=$(jq -rn --arg p "$3" '$p|@uri')&refreshLibrary=false" "$opts" >/dev/null
}
add_lib Movies movies /media/movies
add_lib Shows tvshows /media/shows

log "scanning"
api POST /Library/Refresh >/dev/null
count() { api GET "/Items?userId=$USER_ID&Recursive=true&IncludeItemTypes=$1&Fields=ImageTags" ; }
for _ in $(seq 1 90); do
  running=$(api GET /ScheduledTasks | jq -r '[.[] | select(.Key=="RefreshLibrary") | .State][0]')
  movies=$(count Movie | jq .TotalRecordCount)
  episodes=$(count Episode | jq .TotalRecordCount)
  [[ $running == Idle && $movies -ge 4 && $episodes -ge 2 ]] && break
  sleep 3
done

# A scan does not pick up a poster added next to an item that already exists, so refresh items still missing one.
for id in $(count Movie,Series | jq -r '.Items[] | select(.ImageTags.Primary|not) | .Id'); do
  log "refreshing images for $id"
  api POST "/Items/$id/Refresh?metadataRefreshMode=FullRefresh&imageRefreshMode=FullRefresh&replaceAllImages=false" >/dev/null
done

# ---- 6. API key ----
if ! { [[ -s "$STATE/apikey" ]] && curl -fsS -o /dev/null -H "Authorization: MediaBrowser Token=\"$(<"$STATE/apikey")\"" "$URL/System/Info"; }; then
  log "creating API key"
  api GET /Auth/Keys | jq -e '.Items[] | select(.AppName=="theme-test")' >/dev/null 2>&1 || api POST "/Auth/Keys?app=theme-test" >/dev/null
  api GET /Auth/Keys | jq -r '[.Items[] | select(.AppName=="theme-test")][0].AccessToken' >"$STATE/apikey"
fi
chmod 600 "$STATE/apikey"

# ---- 7. one film half watched, so "Continue watching" shows ----
item=$(count Movie | jq -c '[.Items[] | select(.Name=="Big Buck Bunny")][0] // empty')
if [[ -n $item ]]; then
  id=$(jq -r .Id <<<"$item")
  ticks=$(api GET "/Items/$id?userId=$USER_ID" | jq '.RunTimeTicks // 0')
  if [[ $ticks -gt 0 ]]; then
    log "marking Big Buck Bunny half watched"
    api POST "/UserItems/$id/UserData?userId=$USER_ID" \
      "$(jq -nc --argjson t "$((ticks / 2))" --arg d "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{PlaybackPositionTicks:$t,Played:false,LastPlayedDate:$d}')" >/dev/null
  fi
fi

# ---- summary ----
log "done"
for t in Movie Series Episode; do
  count "$t" | jq -r --arg t "$t" '"   \($t): \(.TotalRecordCount) items, \([.Items[] | select(.ImageTags.Primary)] | length) with a poster"'
done
api GET "/UserItems/Resume?userId=$USER_ID" | jq -r '"   continue watching: \([.Items[].Name] | join(", "))"'
printf '   open %s (user %s, password in %s/admin.txt)\n' "$URL" "$ADMIN" "$STATE"
