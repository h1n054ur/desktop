#!/usr/bin/env bash
# h1n054ur status line for Claude Code: the starship prompt's segments and colours on one line.
#   [user@host]  dir  branch status  model  ctx%  session time        HH:MM
# Uses the same ANSI colour names as terminal/config/starship.toml, so both render alike in kitty.
# Claude Code pipes session JSON on stdin; see https://code.claude.com/docs/en/statusline
set -u

in=$(cat)
j() { jq -r "$1 // empty" <<<"$in"; }

E=$'\e'
R="$E[0m"
GREEN="$E[1;32m" RED="$E[1;31m" YELLOW="$E[1;33m" PURPLE="$E[1;35m" CYAN="$E[1;36m"
BCYAN="$E[1;96m" BWHITE="$E[1;97m" DIM="$E[2;37m" DIMYELLOW="$E[2;33m"
# Nerd Font icons, the same code points as starship.toml
I_DIR=$'\uf07c' I_BRANCH=$'\ue725' I_MODEL=$'\U000f06a9' I_TIME=$'\uf252'

dir=$(j '.workspace.current_dir')
[ -n "$dir" ] || dir=$(j '.cwd')
[ -n "$dir" ] || dir=$PWD

out="${GREEN}[${R}${BWHITE}${USER:-$(id -un)}${R}${DIM}@${R}${CYAN}$(hostname -s 2>/dev/null || cat /etc/hostname)${R}${GREEN}]${R}"

# Directory as starship shows it: from the repo root inside a repo, else ~ and the last 4 parts
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$root" ]; then
  shown="$(basename "$root")${dir#"$root"}"
else
  shown=${dir/#$HOME/\~}
  IFS=/ read -ra parts <<<"$shown"
  if [ "${#parts[@]}" -gt 4 ]; then
    shown=$(IFS=/; echo "${parts[*]: -4}")
  fi
fi
out+=" ${BCYAN}${I_DIR} ${shown}${R}"

# Git branch and status, in starship's all_status order
if [ -n "$root" ]; then
  branch=""
  ahead=0 behind=0 conflicted=0 deleted=0 modified=0 staged=0 untracked=0
  while IFS= read -r line; do
    case $line in
      '# branch.head '*) branch=${line#\# branch.head } ;;
      '# branch.ab '*)
        read -r _ _ a b <<<"$line"
        ahead=${a#+} behind=${b#-} ;;
      'u '*) conflicted=$((conflicted + 1)) ;;
      '? '*) untracked=$((untracked + 1)) ;;
      [12]' '*)
        xy=${line:2:2}
        [ "${xy:0:1}" != . ] && staged=$((staged + 1))
        case ${xy:1:1} in
          M | T) modified=$((modified + 1)) ;;
          D) deleted=$((deleted + 1)) ;;
        esac ;;
    esac
  done < <(git -C "$dir" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
  stashed=$(git -C "$dir" stash list 2>/dev/null | wc -l)

  [ "$branch" = "(detached)" ] && branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
  out+=" ${PURPLE}${I_BRANCH} ${branch}${R}"

  st=""
  [ "$conflicted" -gt 0 ] && st+="=${conflicted}"
  [ "$stashed" -gt 0 ] && st+="*${stashed}"
  [ "$deleted" -gt 0 ] && st+="✘${deleted}"
  [ "$modified" -gt 0 ] && st+="!${modified}"
  [ "$staged" -gt 0 ] && st+="+${staged}"
  [ "$untracked" -gt 0 ] && st+="?${untracked}"
  if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    st+="⇕⇡${ahead}⇣${behind}"
  elif [ "$ahead" -gt 0 ]; then
    st+="⇡${ahead}"
  elif [ "$behind" -gt 0 ]; then
    st+="⇣${behind}"
  fi
  [ -n "$st" ] && out+=" ${YELLOW}${st}${R}"
fi

# Claude's own segments: model, context use, session time
model=$(j '.model.display_name')
[ -n "$model" ] && out+="  ${GREEN}${I_MODEL} ${model}${R}"

pct=$(j '.context_window.used_percentage')
if [ -n "$pct" ]; then
  p=${pct%.*}
  if [ "$p" -ge 80 ]; then c=$RED; elif [ "$p" -ge 50 ]; then c=$YELLOW; else c=$GREEN; fi
  out+=" ${DIM}ctx${R} ${c}${p}%${R}"
fi

ms=$(j '.cost.total_duration_ms')
if [ -n "$ms" ]; then
  s=$((${ms%.*} / 1000))
  if [ "$s" -ge 3600 ]; then d="$((s / 3600))h$(((s % 3600) / 60))m"
  elif [ "$s" -ge 60 ]; then d="$((s / 60))m"
  else d="${s}s"
  fi
  out+=" ${DIMYELLOW}${I_TIME} ${d}${R}"
fi

out+="  ${DIM}$(date +%H:%M)${R}"
printf '%s\n' "$out"
