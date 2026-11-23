#!/usr/bin/env python3
"""Render a TTF into a Connect IQ bitmap font (BMFont text .fnt + .png).

Digits get a fixed advance so a countdown doesn't jitter. The line height is
trimmed to the tallest/lowest glyph in the set, so VCENTER centers the text.

Usage:
  make_font.py FONT.ttf OUT_BASENAME (--digit PX | --em PX) [--var WEIGHT] [--chars STR]
  --digit: size so the "0" glyph is PX tall   --em: font size in PX
  --var:   named instance of a variable font (e.g. Light, ExtraLight)
"""
import argparse
from PIL import Image, ImageDraw, ImageFont

ap = argparse.ArgumentParser()
ap.add_argument("ttf")
ap.add_argument("out")
g = ap.add_mutually_exclusive_group(required=True)
g.add_argument("--digit", type=int)
g.add_argument("--em", type=int)
ap.add_argument("--var")
ap.add_argument("--chars", default="0123456789:")
a = ap.parse_args()


def load(size):
    f = ImageFont.truetype(a.ttf, size)
    if a.var:
        f.set_variation_by_name(a.var.encode())
    return f


size = a.em or a.digit
if a.digit:
    for _ in range(30):
        b = load(size).getbbox("0")
        h = b[3] - b[1]
        if h == a.digit:
            break
        size = max(4, round(size * a.digit / h))
font = load(size)

chars = list(dict.fromkeys(a.chars))       # unique, keep order
boxes = {ch: font.getbbox(ch) for ch in chars}
inked = [b for ch, b in boxes.items() if ch != " "]
top = min(b[1] for b in inked)
bottom = max(b[3] for b in inked)
pad = max(1, (bottom - top) // 20)
line_h = bottom - top + 2 * pad
digit_adv = max(font.getlength(d) for d in "0123456789")

glyphs = []
for ch in chars:
    bx0, by0, bx1, by1 = boxes[ch]
    w, h = max(1, bx1 - bx0), max(1, by1 - by0)
    img = Image.new("L", (w, h), 0)
    if ch != " ":
        ImageDraw.Draw(img).text((-bx0, -by0), ch, font=font, fill=255)
    if ch.isdigit():
        adv = digit_adv
        xoff = bx0 + (digit_adv - font.getlength(ch)) / 2
    else:
        adv = font.getlength(ch)
        xoff = bx0
    glyphs.append((ch, img, round(xoff), by0 - top + pad, round(adv)))

# Pack into rows of at most ~1024 px.
rows, row, x = [], [], 1
for gl in glyphs:
    if x + gl[1].width + 2 > 1024 and row:
        rows.append(row)
        row, x = [], 1
    row.append(gl)
    x += gl[1].width + 2
rows.append(row)
W = max(sum(gl[1].width + 2 for gl in r) for r in rows) + 1
row_h = max(gl[1].height for gl in glyphs) + 2
H = row_h * len(rows) + 1
lum = Image.new("L", (W, H), 0)
lines = []
for ri, r in enumerate(rows):
    x, y = 1, 1 + ri * row_h
    for ch, img, xoff, yoff, adv in r:
        lum.paste(img, (x, y))
        lines.append(f"char id={ord(ch)} x={x} y={y} width={img.width} height={img.height} "
                     f"xoffset={xoff} yoffset={yoff} xadvance={adv} page=0 chnl=15")
        x += img.width + 2

# Coverage in both the gray level and alpha, whichever the compiler reads.
Image.merge("RGBA", (lum, lum, lum, lum)).save(a.out + ".png")
name = a.out.rsplit("/", 1)[-1]
with open(a.out + ".fnt", "w") as f:
    f.write(f'info face="{name}" size={size} bold=0 italic=0 charset="" unicode=1 '
            f"stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1\n")
    f.write(f"common lineHeight={line_h} base={bottom - top + pad} scaleW={W} scaleH={H} pages=1 packed=0\n")
    f.write(f'page id=0 file="{name}.png"\n')
    f.write(f"chars count={len(glyphs)}\n")
    f.write("\n".join(lines) + "\n")
print(f"{a.out}: em={size}px line={line_h}px chars={len(glyphs)} atlas={W}x{H}")
