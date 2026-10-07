#!/usr/bin/env bash
# Installs the h1n054ur terminal: animated welcome banner, fastfetch panel, starship prompt.
# Usage: ./install.sh [handle]      (handle defaults to your username; used for the banner)
# Linux (apt, dnf or pacman, sudo once) and macOS (Homebrew). Hooks bash and, if it is your shell, zsh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
HANDLE=${1:-$USER}
FF_VER=2.69.0

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

mkdir -p "$HOME/.local/bin" "$HOME/.config/welcome" "$HOME/.config/fastfetch"

if command -v brew >/dev/null; then
  say "brew: figlet lolcat cmatrix fastfetch starship pipx"
  brew install figlet lolcat cmatrix fastfetch starship pipx
elif command -v apt-get >/dev/null; then
  say "apt: figlet lolcat cmatrix pipx curl unzip"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y figlet lolcat cmatrix pipx curl unzip
  # The distro package first (Debian 13+, Ubuntu 25.04+); otherwise the release .deb for this architecture
  command -v fastfetch >/dev/null || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y fastfetch >/dev/null 2>&1 || true
  if ! command -v fastfetch >/dev/null; then
    case $(dpkg --print-architecture) in
      amd64) ff_arch=amd64 ;; arm64) ff_arch=aarch64 ;; armhf) ff_arch=armv7l ;; i386) ff_arch=i686 ;;
      *) ff_arch=$(dpkg --print-architecture) ;;
    esac
    say "fastfetch $FF_VER ($ff_arch)"
    tmp=$(mktemp -d)
    curl -sLo "$tmp/fastfetch.deb" "https://github.com/fastfetch-cli/fastfetch/releases/download/$FF_VER/fastfetch-linux-$ff_arch.deb"
    sudo dpkg -i "$tmp/fastfetch.deb"
    rm -rf "$tmp"
  fi
  if ! command -v starship >/dev/null && [ ! -x "$HOME/.local/bin/starship" ]; then
    say "starship (user-local)"
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
  fi
elif command -v dnf >/dev/null; then
  say "dnf (EPEL): figlet lolcat fastfetch pipx curl unzip"
  sudo dnf install -y epel-release
  sudo dnf install -y figlet lolcat fastfetch pipx curl unzip
  if ! command -v starship >/dev/null && [ ! -x "$HOME/.local/bin/starship" ]; then
    say "starship (user-local)"
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
  fi
elif command -v pacman >/dev/null; then
  say "pacman: figlet lolcat cmatrix fastfetch starship python-pipx curl unzip"
  sudo pacman -S --needed --noconfirm figlet lolcat cmatrix fastfetch starship python-pipx curl unzip
else
  echo "need Homebrew, apt-get, dnf or pacman" >&2; exit 1
fi

say "terminaltexteffects + pyfiglet (pipx, user-local)"
pipx install terminaltexteffects >/dev/null 2>&1 || pipx upgrade terminaltexteffects >/dev/null
pipx install pyfiglet >/dev/null 2>&1 || true

say "configs"
install -m 755 "$HERE/bin/welcome" "$HOME/.local/bin/welcome"
install -m 644 "$HERE/config/fastfetch/welcome.jsonc" "$HOME/.config/fastfetch/welcome.jsonc"
if [ "$(uname)" = Darwin ]; then
  sed -i '' 's/"namePrefix": "eth"/"namePrefix": "en"/; s/"namePrefix": "tailscale"/"namePrefix": "utun"/' "$HOME/.config/fastfetch/welcome.jsonc"
fi
[ -f "$HOME/.config/starship.toml" ] && cp "$HOME/.config/starship.toml" "$HOME/.config/starship.toml.bak"
install -m 644 "$HERE/config/starship.toml" "$HOME/.config/starship.toml"
echo "$HANDLE" > "$HOME/.config/welcome/handle"
"$HOME/.local/bin/pyfiglet" -f ansi_shadow "$HANDLE" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' > "$HOME/.config/welcome/banner.txt"

hook() {  # $1 rc file, $2 shell name
  if ! grep -q '>>> h1n054ur-terminal >>>' "$1" 2>/dev/null; then
    say "$2 hook in $1"
    printf '\n' >> "$1"
    sed "s/starship init bash/starship init $2/" "$HERE/bashrc.snippet" >> "$1"
  fi
}
hook "$HOME/.bashrc" bash
case ${SHELL:-} in */zsh) hook "$HOME/.zshrc" zsh ;; esac

say "done. open a new terminal, or run: welcome"
