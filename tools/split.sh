#!/usr/bin/env bash
# Split every folder listed in splits.toml into its own history and push it to that folder's repo.
#   tools/split.sh                 split and push main (CI, on every push to main)
#   tools/split.sh --tag <folder>/vX.Y.Z   also push tag vX.Y.Z to that folder's repo
#   tools/split.sh --dry-run       split only, print the commits, push nothing
#   tools/split.sh --force         overwrite the split repos (after this repo's history was rewritten)
# Needs: splitsh-lite, git, and SPLIT_URL (e.g. https://user:token@git.example/owner) unless --dry-run.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
DRY=0 TAG="" FORCE=""
while [ $# -gt 0 ]; do
  case $1 in --dry-run) DRY=1 ;; --force) FORCE=+ ;; --tag) TAG=$2; shift ;; *) echo "unknown option: $1" >&2; exit 2 ;; esac
  shift
done

# folder<TAB>repo pairs from splits.toml (simple [[split]] tables with quoted values)
pairs=$(awk -F'"' '/^folder *=/ {f=$2} /^repo *=/ {print f "\t" $2}' splits.toml)
[ -n "$pairs" ] || { echo "no splits found in splits.toml" >&2; exit 1; }

while IFS=$'\t' read -r folder repo; do
  [ -d "$folder" ] || { echo "missing folder: $folder" >&2; exit 1; }
  sha=$(splitsh-lite --prefix="$folder/" 2>/dev/null | tail -1)
  printf '%-26s -> %-26s %s\n' "$folder" "$repo" "$sha"
  [ "$DRY" = 1 ] && continue
  git push --quiet "$SPLIT_URL/$repo.git" "$FORCE$sha:refs/heads/main"
  if [ -n "$TAG" ] && [ "${TAG%%/*}" = "$folder" ]; then
    git push --quiet "$SPLIT_URL/$repo.git" "$sha:refs/tags/${TAG#*/}"
    echo "  tagged ${TAG#*/}"
  fi
done <<< "$pairs"
