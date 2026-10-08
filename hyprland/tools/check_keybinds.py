#!/usr/bin/env python3
"""Check that every key combo bound in config/binds.lua is listed in KEYBINDS.md.

Run from the hyprland/ folder:  python3 tools/check_keybinds.py
Exits 1 and lists the missing combos, so CI fails when the page drifts from the config.
Binds made in a loop over digits count as listed when the page shows that combo with "1".
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
binds = (ROOT / "config/binds.lua").read_text()
page = (ROOT / "KEYBINDS.md").read_text()

MODS = {"mainMod": "Super", "SUPER": "Super", "SHIFT": "Shift", "CONTROL": "Ctrl", "CTRL": "Ctrl", "ALT": "Alt"}
KEYS = {"Return": "Enter", "grave": "`", "period": ".", "slash": "/", "equal": "=", "Minus": "Minus", "Plus": "Plus",
        "mouse_up": "wheel", "mouse_down": "wheel", "mouse:272": "left mouse drag", "mouse:273": "right mouse drag",
        "code:82": "Minus", "code:86": "Plus", "Escape": "Escape", "Print": "Print"}
# hardware keys, mouse-only and other binds the page describes in words instead of key names
# Control_L/R: release-only helpers of the Ctrl+Space dictation row (handy-ptt up), not shortcuts of their own
SKIP = re.compile(r"XF86|switch:|code:(82|86)$|Control_[LR]\b")


def combo(expr: str) -> str:
    parts = [p.strip() for p in re.sub(r'["\s]', " ", expr.replace("..", " ")).replace("+", " ").split()]
    mods = [MODS[p] for p in parts if p in MODS]
    keys = [p for p in parts if p not in MODS]
    return "+".join(mods + [KEYS.get(k, k) for k in keys])


def listed(c: str) -> bool:
    text = page.replace(" + ", "+").replace("` + ", "+").replace("+Esc`", "+Escape`")
    if c in text:
        return True
    # "Super+Shift+Arrows", "Super+Ctrl+Left/Right", "Super+Minus / Super+Plus" style rows
    mods, _, key = c.rpartition("+")
    if key in ("Left", "Right", "Up", "Down") and (f"{mods}+Arrows" in text or f"{mods}+{key}" in text
                                                   or re.search(re.escape(mods) + r"\+[A-Za-z/]*" + key, text)):
        return True
    if key == "wheel" and (f"`{mods}+` mouse wheel" in page or f"`{mods}` + mouse wheel" in page):
        return True
    if key.endswith("mouse drag") and f"`{mods}` + {key.split()[0]} mouse drag" in page:
        return True
    return False


missing = []
lines = binds.splitlines()
in_loop = False
for line in lines:
    if line.startswith("for "):
        in_loop = True
    elif line.startswith("end"):
        in_loop = False
    m = re.search(r'hl\.bind\((.*?),\s*(hl\.dsp|function|focusOrLaunch)', line)
    if not m:
        continue
    expr = m.group(1)
    if "digitCode" in expr or in_loop:
        expr = re.sub(r"\.\.\s*digitCode\([^)]*\)", '"1"', expr)
    c = combo(expr)
    if SKIP.search(m.group(1)) or not c:
        continue
    if not listed(c):
        missing.append(c)

if missing:
    print("bound in config/binds.lua but missing from KEYBINDS.md:")
    for c in sorted(set(missing)):
        print("  " + c)
    sys.exit(1)
print(f"KEYBINDS.md covers every bind in config/binds.lua")
