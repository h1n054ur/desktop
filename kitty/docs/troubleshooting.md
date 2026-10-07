# Troubleshooting and lessons learned

General issues hit while building this setup. Tool-specific fixes live in [yazi](yazi.md#troubleshooting) and [music](music.md#troubleshooting).

## Launching

- **kitty does not open from the app launcher after moving off WSL**: a leftover `~/.local/share/applications/kitty.desktop` (or `~/.local/bin/kitty` link) from the old per-user install pointed at the deleted `~/.local/kitty.app`. User entries override `/usr/share/applications/kitty.desktop`, so delete them and the system kitty takes over.
- **`Super+Enter` does nothing**: Hyprland runs `uwsm app -- kitty`. Run the same thing by hand with `hyprctl dispatch 'hl.dsp.exec_cmd("uwsm app -- kitty")'` and read `journalctl --user -b | grep -i kitty`.

## Window and colours

- **No colours / wrong colours**: `themes/noctalia.conf` is written by Noctalia's kitty template. Turn it on in Noctalia; it also keeps the `include themes/noctalia.conf` line in `kitty.conf` and reloads kitty (`SIGUSR1`) when the palette changes.
- **Prompt, fastfetch or `ls` colours look washed out** (green shows as lavender, cyan as grey): Noctalia maps the 16 ANSI colours to its pastel palette. `ansi.conf`, included after the Noctalia line, puts Catppuccin Mocha's text and ANSI colours back on top.
- **Too see-through**: raise `background_opacity` (0.6 is the CachyOS default). Hyprland's terminal window rule keeps its own opacity at 1.0 so kitty's setting wins.
- **Font changes need a full restart** of kitty. `Ctrl+Shift+F5` reloads most other settings.

## Fonts and glyphs

- **Missing Claude Code glyphs** (blank `⎿` under tool calls, `⏵⏵` for accept edits, `⧉`, `⧗`): neither the Nerd Font nor DejaVu has them. `noto-fonts` adds Noto Sans Symbols, Symbols 2 and Math.
- **`⏺ ⏸ ⏹` drawn as colour emoji**: their only other font is Noto Color Emoji. `kitty.conf` pins `U+23BF`, `U+23F4-U+23FA`, `U+29C9` and `U+29D7` to the Noto symbol fonts with `symbol_map`, so they stay monochrome in the text colour.
- **Find which font has a glyph:** `fc-list ":charset=23bf" family` (hex code point). Empty output means nothing covers it; add a font and map it with `symbol_map`.

## Keys

- **Screenshots do not paste into Claude Code**: kitty's own paste only handles text. `smart_paste.py` checks `wl-paste --list-types` and sends a real `Ctrl+V` through when the clipboard holds an image, so Claude Code reads it with `wl-paste` itself.
- **Pasting did nothing**: kitty's paste key is `Ctrl+Shift+V`, not `Ctrl+V`, so `kitty.conf` maps `Ctrl+V`, `Ctrl+C` (copy or interrupt) and right click.
- The custom split keys shadow some kitty defaults; see [Defaults this config replaces](kitty.md#defaults-this-config-replaces).
- `kitty --debug-config` does not exist in 0.49. Use `Ctrl+Shift+F6`, or `kitty +runpy` with `kitty.config.load_config` to inspect the parsed config (that is how the shortcut tables here were generated).

---

[Back to the README](../README.md)
