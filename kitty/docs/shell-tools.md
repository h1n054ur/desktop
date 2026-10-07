# Shell tools

Small command-line tools installed alongside yazi. They work in any shell, not just kitty. The `y` function, the zoxide hook and the fzf key bindings come from [`bashrc.snippet`](../bashrc.snippet), which `install.sh` appends to `~/.bashrc`.

| Tool | What it is |
|---|---|
| [zoxide](https://github.com/ajeetdsouza/zoxide) | Remembers the folders you visit; `z part-of-name` jumps there |
| [fzf](https://github.com/junegunn/fzf) | Fuzzy finder behind `zi`, `Ctrl+T`, `Ctrl+R`, `Alt+C` and yazi's `z` |
| [fd](https://github.com/sharkdp/fd) | Fast file-name search (yazi `s`) |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Fast content search (yazi `S`) |
| `ytm` | This repo's helper: queue YouTube Music links in rmpc (`bin/ytm`, see [music](music.md)) |
| wl-clipboard | Read and write the Wayland clipboard (`wl-copy`, `wl-paste`) |

## Commands

| Command | Does |
|---|---|
| `y` | yazi; quitting with `q` moves the shell to the folder you were in |
| `yazi [dir]` | yazi without the cd-on-quit |
| `z <part of a path>` | Jump to a frequently used folder (zoxide) |
| `zi` | Pick a folder interactively with fzf |
| `zoxide query -l` / `zoxide remove <dir>` | List / forget remembered folders |
| `fd <name>` | Find files by name (fast `find`) |
| `rg <text>` | Search file contents (ripgrep) |
| `fzf` | Fuzzy finder |
| `Ctrl+T` / `Ctrl+R` / `Alt+C` | In bash: pick a file into the command line / search history / cd into a folder (fzf bindings from `bashrc.snippet`) |
| `xdg-open <file>` | Open with the desktop's default app |
| `cmd \| wl-copy` | Copy command output to the clipboard |
| `wl-paste` / `wl-paste -l` | Print the clipboard / list what types it holds (what `Ctrl+V` will do) |

---

[Back to the README](../README.md)
