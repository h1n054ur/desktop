#!/usr/bin/env bash
# shellcheck disable=SC2206,SC2086  # package lists are space-separated on purpose and split into words
# h1n054ur setup: installs the desktop's software on CachyOS (or Arch with the CachyOS repos), by group.
#   ./install.sh                         interactive: pick groups with the arrow keys and Space
#   ./install.sh dev apps --yes          install those groups without questions
#   ./install.sh all --yes               everything
#   ./install.sh --dry-run               walk through it without installing anything
#   ./install.sh --list                  show the groups
# Repo packages come from pacman; AUR ones from paru (preinstalled on CachyOS). A failing AUR build never
# stops the run. Everything is logged to ~/.cache/h1n054ur-setup/. Safe to run again (--needed).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)

# ── groups ──────────────────────────────────────────────────────────────────────────────────────────
ORDER=(desktop terminal media dev apps winapps mail network gaming)
declare -A REPO AUR DESC
DESC[desktop]="Hyprland, Noctalia, greetd, Quickshell, rofi, clipboard, audio"
REPO[desktop]="hyprland hypridle hyprlock hyprpaper hyprpolkitagent hyprshot cachyos-hypr-noctalia noctalia-greeter greetd quickshell rofi cliphist wtype playerctl swaync easyeffects pavucontrol blueman"
DESC[terminal]="kitty, yazi, starship, fastfetch, neovim, lazygit, fonts"
REPO[terminal]="kitty yazi starship fastfetch zoxide ripgrep fd fzf bat eza btop glances neovim micro lazygit lazydocker figlet lolcat cmatrix ttf-cascadia-code-nerd ttf-meslo-nerd noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra"
DESC[media]="MPD, rmpc, cava, mpv, VLC, FreeTube, OBS, GIMP, HandBrake"
REPO[media]="mpd rmpc cava mpv yt-dlp vlc vlc-plugins-all jellyfin-mpv-shim handbrake obs-studio gimp avidemux-qt"
AUR[media]="mpv-uosc freetube-bin stremio ff2mpv-rust"
DESC[dev]="Docker, Bun, uv, VS Code, opencode, Claude Code, gitleaks"
REPO[dev]="git github-cli docker docker-compose docker-buildx nvidia-container-toolkit uv nvm rbenv opencode cmake ninja shellcheck caddy cloudflared dbeaver mysql-workbench meld gitleaks"
AUR[dev]="bun-bin visual-studio-code-bin ngrok"
DESC[apps]="Chrome, Zen, Ferdium, Vesktop, Obsidian, Bitwarden, Calibre"
REPO[apps]="zen-browser-bin vesktop-bin obsidian bitwarden rbw rofi-rbw calibre teamspeak3 filezilla remmina mission-center dolphin kate gwenview thunar"
AUR[apps]="google-chrome ferdium-bin figma-linux"
DESC[winapps]="Docker, FreeRDP, KVM/QEMU for Windows apps (see README)"
REPO[winapps]="docker docker-compose freerdp qemu-full virt-manager libvirt edk2-ovmf swtpm dnsmasq"
DESC[mail]="aerc, himalaya, notmuch, khal, newsboat, qutebrowser, zathura"
REPO[mail]="aerc himalaya isync notmuch khal calcurse newsboat qutebrowser python-adblock w3m zathura zathura-pdf-mupdf"
AUR[mail]="timg yt-x"
DESC[network]="Tailscale, Syncthing, rclone, WireGuard, WARP, Surfshark"
REPO[network]="tailscale syncthing syncthingtray rclone wireguard-tools cloudflare-warp-bin"
AUR[network]="surfshark-client"
DESC[gaming]="Steam"
REPO[gaming]="steam"

# ── look and spinners (shared with the desktop installer) ───────────────────────────────────────────
UI_ROOT="$HERE"
# shellcheck source=SCRIPTDIR/lib/ui.sh
. "$HERE/lib/ui.sh"

# ── system check ────────────────────────────────────────────────────────────────────────────────────
sysinfo() {
  local os kern gpu paru disk
  # shellcheck source=/dev/null
  os=$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")
  kern=$(uname -r)
  gpu=$(lspci 2>/dev/null | sed -n 's/.*VGA compatible controller: //p' | head -1 | cut -c1-44)
  if command -v paru >/dev/null; then paru="${GRN}found${R}"; else paru="${RED}missing${R} ${DIM}(AUR packages will be skipped)${R}"; fi
  disk=$(df -h --output=avail / 2>/dev/null | tail -1 | tr -d ' ')
  box "sys.check" \
    "${CYN}os    ${FG}$os${R}" "${CYN}kernel${FG} $kern${R}" "${CYN}gpu   ${FG} ${gpu:-unknown}${R}" \
    "${CYN}paru  ${R} $paru" "${CYN}free  ${FG} $disk on /${R}"
  echo
  command -v pacman >/dev/null || { printf '  %sthis needs pacman (CachyOS or Arch)%s\n' "$RED" "$R"; exit 1; }
}

# ── group picker ────────────────────────────────────────────────────────────────────────────────────
declare -A PICK
count() { local a=(${REPO[$1]:-} ${AUR[$1]:-}); echo ${#a[@]}; }
draw_menu() {
  local i g mark cur
  for i in "${!ORDER[@]}"; do
    g=${ORDER[$i]}
    if [ "${PICK[$g]:-0}" = 1 ]; then mark="${GRN}[■]${R}"; else mark="${DIM}[ ]${R}"; fi
    if [ "$i" = "$SEL" ]; then cur="${GRN}❯${R}"; else cur=" "; fi
    printf '  %s %s %s%-9s%s %s%3s pkgs%s  %s%s%s\e[K\n' "$cur" "$mark" "$B$FG" "$g" "$R" "$CYN" "$(count "$g")" "$R" "$DIM" "${DESC[$g]}" "$R"
  done
  printf '\n  %s↑↓ move · space pick · a all · n none · enter go · q quit%s\e[K\n' "$DIM" "$R"
}
pick_groups() {
  SEL=0; local key rest n=$(( ${#ORDER[@]} + 2 ))
  printf '  %s%s%s\n\n' "$B" "$(gradline 'pick what to install')" "$R"
  hide_cursor; draw_menu
  while true; do
    IFS= read -rsn1 key
    if [ "$key" = $'\e' ]; then IFS= read -rsn2 -t 0.01 rest; key+=$rest; fi
    case $key in
      $'\e[A'|k) (( SEL = (SEL + ${#ORDER[@]} - 1) % ${#ORDER[@]} )) ;;
      $'\e[B'|j) (( SEL = (SEL + 1) % ${#ORDER[@]} )) ;;
      ' ') local g=${ORDER[$SEL]}; if [ "${PICK[$g]:-0}" = 1 ]; then PICK[$g]=0; else PICK[$g]=1; fi ;;
      a) for g in "${ORDER[@]}"; do PICK[$g]=1; done ;;
      n) for g in "${ORDER[@]}"; do PICK[$g]=0; done ;;
      '') break ;;
      q) show_cursor; printf '\n  %snothing installed%s\n' "$DIM" "$R"; exit 0 ;;
    esac
    printf '\e[%dA' "$n"; draw_menu
  done
  show_cursor; echo
}

# ── main ────────────────────────────────────────────────────────────────────────────────────────────
DRY=0 YES=0 ARGS=()
for a in "$@"; do
  case $a in
    --dry-run) DRY=1 ;; --yes|-y) YES=1 ;;
    --list) for g in "${ORDER[@]}"; do printf '%-9s %3s packages  %s\n' "$g" "$(count "$g")" "${DESC[$g]}"; done; exit 0 ;;
    -h|--help) sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    all) for g in "${ORDER[@]}"; do PICK[$g]=1; done ;;
    *) [ -n "${DESC[$a]:-}" ] || { echo "unknown group: $a (see --list)"; exit 2; }; PICK[$a]=1; ARGS+=("$a") ;;
  esac
done

clear 2>/dev/null; banner; sysinfo

chosen=(); for g in "${ORDER[@]}"; do [ "${PICK[$g]:-0}" = 1 ] && chosen+=("$g"); done
if [ ${#chosen[@]} -eq 0 ]; then
  [ -t 0 ] || { echo "no groups given and no terminal to ask: ./install.sh <group>... --yes"; exit 2; }
  pick_groups
  for g in "${ORDER[@]}"; do [ "${PICK[$g]:-0}" = 1 ] && chosen+=("$g"); done
  [ ${#chosen[@]} -eq 0 ] && { printf '  %snothing picked, nothing installed%s\n' "$DIM" "$R"; exit 0; }
fi

repo=() aur=() claude=0
for g in "${chosen[@]}"; do repo+=(${REPO[$g]:-}); aur+=(${AUR[$g]:-}); [ "$g" = dev ] && claude=1; done
mapfile -t repo < <(printf '%s\n' "${repo[@]}" | awk 'NF && !seen[$0]++')
mapfile -t aur < <(printf '%s\n' "${aur[@]}" | awk 'NF && !seen[$0]++')

LOG_DIR="$HOME/.cache/h1n054ur-setup"; mkdir -p "$LOG_DIR"; LOG="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
summary=("${CYN}groups ${FG} ${chosen[*]}${R}" "${CYN}repo   ${FG} ${#repo[@]} packages (pacman)${R}" "${CYN}aur    ${FG} ${#aur[@]} packages (paru, one at a time)${R}")
[ "$claude" = 1 ] && summary+=("${CYN}extra  ${FG} Claude Code (Anthropic's installer)${R}")
[ "$DRY" = 1 ] && summary+=("${GRN}dry run: nothing will be installed${R}")
summary+=("${CYN}log    ${DIM} ${LOG/#$HOME/\~}${R}")
box "plan" "${summary[@]}"; echo
if [ "$YES" = 0 ] && [ -t 0 ]; then
  printf '  %s❯%s go ahead? %s[Y/n]%s ' "$GRN" "$R" "$DIM" "$R"; read -r ans
  case $ans in n|N|no) printf '  %snothing installed%s\n' "$DIM" "$R"; exit 0 ;; esac
fi

# sudo once, kept alive for the run
if [ "$DRY" = 0 ]; then
  sudo -v || { printf '  %ssudo is needed to install packages%s\n' "$RED" "$R"; exit 1; }
  ( while kill -0 $$ 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
fi
echo

failed=()
if [ ${#repo[@]} -gt 0 ]; then
  run_step "repo packages" "${#repo[@]}" '\([0-9]+/[0-9]+\) installing' \
    sudo env LANG=C pacman -S --needed --noconfirm "${repo[@]}" || failed+=("some repo packages")
fi
if [ ${#aur[@]} -gt 0 ]; then
  if command -v paru >/dev/null || [ "$DRY" = 1 ]; then
    for p in "${aur[@]}"; do run_step "aur · $p" 0 '' paru -S --needed --noconfirm "$p" || failed+=("$p"); done
  else
    failed+=("${aur[@]}")
  fi
fi
if [ "$claude" = 1 ] && ! command -v claude >/dev/null; then
  run_step "claude code" 0 '' bash -c 'curl -fsSL https://claude.ai/install.sh | bash' || failed+=("claude code")
fi
docker_done=0
# shellcheck disable=SC2016  # $USER expands in the inner shell, on purpose
for g in "${chosen[@]}"; do
  case $g in
    dev|winapps) [ "$docker_done" = 1 ] && continue; docker_done=1; run_step "docker service + group" 0 '' bash -c 'sudo systemctl enable --now docker.service && sudo usermod -aG docker "$USER"' || failed+=("docker service") ;;
    network)     run_step "tailscale service" 0 '' sudo systemctl enable --now tailscaled.service || failed+=("tailscale service") ;;
  esac
done

echo
if [ ${#failed[@]} -eq 0 ]; then
  if [ "$DRY" = 1 ]; then done_msg="dry run finished, nothing was installed"; else done_msg="everything installed"; fi
  box "done" "${GRN}${done_msg}${R}" "${DIM}log: ${LOG/#$HOME/\~}${R}"
else
  box "done, with misses" "${RED}failed:${R} ${FG}${failed[*]}${R}" "${DIM}AUR builds fail now and then; run again later${R}" "${DIM}log: ${LOG/#$HOME/\~}${R}"
fi
printf '\n  %snext: log out and back in if you were added to the docker group%s\n\n' "$DIM" "$R"
