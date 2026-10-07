#!/usr/bin/env bash
# Re-renders the README GIFs. Needs vhs, ttyd, ffmpeg and the Nerd Font installed in fontconfig.
cd "$(dirname "$0")/.." && ls docs/tapes/*.tape | xargs -P 4 -I{} vhs {}
