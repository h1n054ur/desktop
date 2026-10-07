#!/usr/bin/env python3
"""Recolour rose glow icons to the h1n054ur green-to-cyan gradient.

Usage: recolor.py SRC_DIR DST_DIR [--heat]

Every PNG in SRC_DIR is written to DST_DIR. Rose pixels (hue 330-30 degrees) move
to a left-to-right gradient from #39ff14 to #00e5ff, keeping their brightness and
alpha. Strong reds (error crosses, alerts) are left alone. With --heat, files
named *-3.png, *-4.png (or *l3.png, *l4.png) are copied unchanged so warm heat levels stay warm.
Weather icons keep their own colours and are copied unchanged.
"""
import colorsys, os, re, shutil, sys
from PIL import Image

WEATHER = set(("clear-night cloudy cold fog freezing haze heavy-rain hot humidity mild moon-phase "
               "mostly-sunny overcast partly-cloudy partly-cloudy-night rain sleet snow sunny sunrise "
               "sunset thunderstorm uv-index warm wind wind-direction windy air-quality").split())
G1, G2 = 107, 186  # hue of #39ff14 and #00e5ff in degrees


def recolor(src, dst, max_sat):
    im = Image.open(src).convert("RGBA")
    px = im.load()
    w = im.width
    for y in range(im.height):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            hd = h * 360
            if (hd >= 330 or hd < 30) and 0.03 < s < max_sat:
                t = x / max(1, w - 1)
                nr, ng, nb = colorsys.hsv_to_rgb((G1 + (G2 - G1) * t) / 360, min(1, s * 4), min(1, v * 1.05))
                px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    im.save(dst)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    src, dst, heat = sys.argv[1], sys.argv[2], "--heat" in sys.argv
    os.makedirs(dst, exist_ok=True)
    for name in sorted(os.listdir(src)):
        if not name.endswith(".png"):
            continue
        s, d = os.path.join(src, name), os.path.join(dst, name)
        stem = name[:-4]
        if stem in WEATHER or (heat and re.search(r"(-|l)[34]$", stem)):
            shutil.copy2(s, d)
            continue
        # heat sets and warning states keep a lower cut-off, so warm tones and red
        # crosses (mute, error, disconnected) are not mistaken for rose
        warn = re.search(r"mute|error|disconnected|off|warning|no-signal|limited|no-link", stem)
        recolor(s, d, 0.38 if heat or warn else 0.62)


if __name__ == "__main__":
    main()
