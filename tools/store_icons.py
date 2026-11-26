#!/usr/bin/env python3
"""Icons for the Connect IQ store on the watch ("App Store on Device"): 128x128, one per kind of screen.

Usage: tools/store_icons.py      -> docs/store/device_icons/icon_128_<n>colors.png

The tomato is the launcher icon's source (docs/icons/photo/vine_single_360.png; photo: Luc Viatour,
CC BY-SA 3.0), on black like the watch, with each icon reduced to the colors its screens can show:
  full      AMOLED: every color
  64        MIP (Fenix 7, Forerunner 255/955, Enduro): red, green and blue at 0, 85, 170, 255
  16        older screens: the 14 named Connect IQ colors (Graphics.COLOR_*), plus 2 spare reds
  8         red, green and blue each on or off: a flat red tomato with green leaves
  2         black and white: a white tomato with black leaves
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "docs/icons/photo/vine_single_360.png")
OUT = os.path.join(ROOT, "docs/store/device_icons")
SIZE = 128
MARGIN = 6  # px of black around the tomato, so it doesn't touch the edge


def palette(colors):
    """A Pillow palette image holding exactly these RGB colors."""
    flat = [v for c in colors for v in ((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF)]
    flat += flat[:3] * (256 - len(colors))  # pad with the first color; never chosen twice
    p = Image.new("P", (1, 1))
    p.putpalette(flat)
    return p


LEVELS4 = (0x00, 0x55, 0xAA, 0xFF)
PALETTES = {
    64: [(r << 16) | (g << 8) | b for r in LEVELS4 for g in LEVELS4 for b in LEVELS4],
    16: [0xFFFFFF, 0xAAAAAA, 0x555555, 0x000000, 0xFF0000, 0xAA0000, 0xFF5500, 0xFFAA00,
         0x00FF00, 0x00AA00, 0x00AAFF, 0x0000FF, 0xAA00FF, 0xFF00FF, 0x550000, 0xFF5555],
    8: [(r << 16) | (g << 8) | b for r in (0, 0xFF) for g in (0, 0xFF) for b in (0, 0xFF)],
    2: [0x000000, 0xFFFFFF],
}


def flat(body, leaves):
    """The tomato in two flat colors (for screens with too few colors to shade it): the photo's shape, the
    leaves picked out by their green hue."""
    src = Image.open(SOURCE).convert("RGBA").resize((SIZE - 2 * MARGIN,) * 2, Image.LANCZOS)
    hsv = src.convert("RGB").convert("HSV")
    icon = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    px = icon.load()
    for y in range(src.height):
        for x in range(src.width):
            if src.getpixel((x, y))[3] < 128:
                continue
            h, sat, v = hsv.getpixel((x, y))
            green = 40 <= h <= 130 and sat > 60  # Pillow hue 0-255: green is about 85
            px[x + MARGIN, y + MARGIN] = leaves if green else body
    return icon


def main():
    os.makedirs(OUT, exist_ok=True)
    tomato = Image.open(SOURCE).convert("RGBA").resize((SIZE - 2 * MARGIN,) * 2, Image.LANCZOS)
    icon = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    icon.paste(tomato, (MARGIN, MARGIN), tomato)
    icon.save(os.path.join(OUT, "icon_128_full.png"), optimize=True)
    print("full")
    for n, colors in PALETTES.items():
        if n >= 16:
            # Enough colors to keep the photo's shading, mixed by dithering.
            out = icon.quantize(palette=palette(colors), dither=Image.Dither.FLOYDSTEINBERG)
        else:
            body, leaves = ((255, 0, 0), (0, 255, 0)) if n == 8 else ((255, 255, 255), (0, 0, 0))
            out = flat(body, leaves).quantize(palette=palette(colors), dither=Image.Dither.NONE)
        out.save(os.path.join(OUT, f"icon_128_{n}colors.png"), optimize=True)
        print(f"{n} colors: {len(out.getcolors())} used")


if __name__ == "__main__":
    main()
