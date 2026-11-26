#!/usr/bin/env python3
"""Icons for the Connect IQ store on the watch ("App Store on Device"): 128x128, the two the upload form takes.

Usage: tools/store_icons.py      -> docs/store/device_icons/icon_128_full.png      24-bit color (AMOLED)
                                    docs/store/device_icons/icon_128_64colors.png  64 colors (MIP)

The tomato is the launcher icon's source (docs/icons/photo/vine_single_360.png; photo: Luc Viatour,
CC BY-SA 3.0), on black like the watch. The 64-color one uses Garmin's MIP palette (red, green and blue
each at 0, 85, 170, 255), dithered to keep the shading, and its PNG palette holds exactly those 64 colors.
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "docs/icons/photo/vine_single_360.png")
OUT = os.path.join(ROOT, "docs/store/device_icons")
SIZE = 128
MARGIN = 6  # px of black around the tomato, so it doesn't touch the edge

LEVELS = (0x00, 0x55, 0xAA, 0xFF)
MIP = [v for r in LEVELS for g in LEVELS for b in LEVELS for v in (r, g, b)]  # 64 RGB triples, flat


def main():
    os.makedirs(OUT, exist_ok=True)
    tomato = Image.open(SOURCE).convert("RGBA").resize((SIZE - 2 * MARGIN,) * 2, Image.LANCZOS)
    icon = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    icon.paste(tomato, (MARGIN, MARGIN), tomato)
    icon.save(os.path.join(OUT, "icon_128_full.png"), optimize=True)

    pal = Image.new("P", (1, 1))
    pal.putpalette(MIP + MIP[:3] * (256 - 64))  # Pillow wants 256 entries here; the extras repeat black
    mip = icon.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG)
    mip.putpalette(MIP)  # indexes stay below 64: write only the 64 real entries
    mip.save(os.path.join(OUT, "icon_128_64colors.png"))
    print(f"full: {len(icon.getcolors(1 << 24))} colors; 64colors: {len(mip.getcolors())} used")


if __name__ == "__main__":
    main()
