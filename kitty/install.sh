#!/usr/bin/env bash
# Installs kitty, yazi, rmpc, MPD, cava, the fonts and this config.
# Works on Arch / CachyOS (pacman), Debian / Ubuntu / WSL (apt) and macOS (Homebrew).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# The Noto fonts carry the emoji and the symbols Claude Code draws (U+23BF and friends)
case "$(uname -s)" in
  Darwin)
    OS=macos
    command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh"; exit 1; }
    brew install --cask kitty font-caskaydia-cove-nerd-font font-noto-sans-symbols font-noto-sans-symbols-2
    brew install yazi fd ripgrep fzf zoxide rmpc mpd cava yt-dlp jq ffmpeg sevenzip poppler imagemagick resvg
    ;;
  Linux)
    if command -v pacman >/dev/null; then
      OS=arch
      sudo pacman -S --needed kitty yazi fd ripgrep fzf zoxide rmpc mpd cava yt-dlp python-mutagen bun wl-clipboard \
        ffmpeg 7zip poppler imagemagick jq resvg ttf-cascadia-code-nerd noto-fonts noto-fonts-emoji
    elif command -v apt-get >/dev/null; then
      OS=debian   # includes WSL; kitty runs through WSLg there
      sudo apt-get update
      sudo apt-get install -y kitty fd-find ripgrep fzf zoxide mpd cava yt-dlp jq ffmpeg p7zip-full poppler-utils \
        imagemagick wl-clipboard fonts-noto fonts-noto-color-emoji
      echo "Note: yazi, rmpc and the CaskaydiaCove Nerd Font are not in apt; install them from their release pages."
    else
      echo "Unsupported Linux: needs pacman or apt"; exit 1
    fi
    ;;
  *) echo "Unsupported system: $(uname -s)"; exit 1 ;;
esac

# sed -i differs between GNU and BSD (macOS)
sedi() { if [ "$OS" = macos ]; then sed -i '' "$@"; else sed -i "$@"; fi; }

mkdir -p "$HOME/.local/bin" "$HOME/.config/kitty" "$HOME/.config/yazi"
install -m755 "$here/bin/ytm" "$HOME/.local/bin/ytm"

for f in kitty.conf ansi.conf smart_paste.py; do
  [ -f "$HOME/.config/kitty/$f" ] && cp "$HOME/.config/kitty/$f" "$HOME/.config/kitty/$f.bak"
  cp "$here/config/kitty/$f" "$HOME/.config/kitty/$f"
done
# Without Noctalia (macOS, WSL, other desktops) there is no themes/noctalia.conf: drop that include
[ -f "$HOME/.config/kitty/themes/noctalia.conf" ] || sedi '/^include themes\/noctalia.conf/d' "$HOME/.config/kitty/kitty.conf"

for f in yazi.toml init.lua keymap.toml theme.toml package.toml; do
  [ -f "$HOME/.config/yazi/$f" ] && cp "$HOME/.config/yazi/$f" "$HOME/.config/yazi/$f.bak"
  cp "$here/config/yazi/$f" "$HOME/.config/yazi/$f"
done
command -v ya >/dev/null && (cd "$HOME/.config/yazi" && ya pkg install)
rc="$HOME/.bashrc"; [ "$OS" = macos ] && rc="$HOME/.zshrc"
grep -q 'yazi-cwd' "$rc" 2>/dev/null || { echo; cat "$here/bashrc.snippet"; } >> "$rc"

# Music: rmpc (MPD client with album art and YouTube) + MPD as a user service + cava visualizer
mkdir -p "$HOME/Music" "$HOME/.local/state/mpd/playlists" "$HOME/.cache/rmpc" \
         "$HOME/.config/mpd" "$HOME/.config/rmpc/themes" "$HOME/.config/cava" "$HOME/.config/yt-dlp"
for f in mpd/mpd.conf rmpc/config.ron rmpc/themes/catppuccin-mocha.ron cava/config yt-dlp/config; do
  [ -f "$HOME/.config/$f" ] && cp "$HOME/.config/$f" "$HOME/.config/$f.bak"
  cp "$here/config/$f" "$HOME/.config/$f"
done
# Use the Chrome login for YouTube Premium when that browser profile exists
for prof in "$HOME/.config/google-chrome" "$HOME/Library/Application Support/Google/Chrome"; do
  [ -d "$prof" ] && sedi 's/^#--cookies-from-browser chrome/--cookies-from-browser chrome/' "$HOME/.config/yt-dlp/config"
done
if [ "$OS" = macos ]; then
  brew services start mpd
else
  systemctl --user disable --now mpd.socket 2>/dev/null || true
  systemctl --user enable --now mpd.service
fi

echo "Done. Open a new shell and start kitty (y for yazi, rmpc or Ctrl+Shift+M for music)"
