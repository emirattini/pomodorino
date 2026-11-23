#!/usr/bin/env python3
"""Cut tomato photos out of their (plain) backgrounds and turn them into launcher-icon candidates.

Usage: photo_icon.py PHOTOS_DIR OUT_DIR
PHOTOS_DIR/<name>/src.jpg + PHOTOS_DIR/credits.json (from the Wikimedia download step).
Background removal: flood-fill from the image border with a color tolerance, keep only the
connected part under the chosen center point, then soften the edge.
"""
import json, os, sys
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter

PH, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
MAGIC = (255, 0, 254)

# name -> (source, crop box as fractions (x0, y0, x1, y1), center to keep (fractions of the crop),
#          min saturation 0-255, min brightness 0-255, (brightness, color) boost)
CUTS = {
    "your_yellow": ("docs/icons/real/image.png", (0, 0, 1, 1), (0.49, 0.55), 175, 60, (1.0, 1.0)),
    "orange_datterino": ("orange_datterino", (0, 0, 1, 1), (0.5, 0.5), 175, 60, (1.0, 1.0)),
    "orange_pile": ("orange_pile", (0, 0, 1, 1), (0.5, 0.5), 160, 60, (1.0, 1.0)),
    "red_datterino": ("red_datterino", (0, 0, 1, 1), (0.49, 0.45), 90, 40, (1.35, 1.25)),
    "red_ciliegino": ("red_ciliegino", (0.04, 0.22, 0.38, 0.74), (0.5, 0.5), 120, 50, (1.0, 1.05)),
    "vine_single": ("vine_ciliegini", (0.06, 0.45, 0.28, 0.82), (0.5, 0.62), 60, 40, (1.0, 1.0)),
    "vine_bunch": ("vine_ciliegini", (0.25, 0.08, 0.88, 0.75), (0.55, 0.55), 60, 40, (1.0, 1.0)),
}


BRIGHT_RULE = set()             # photos whose shadow is darker than the fruit
ON_WHITE = {"your_yellow"}      # use the dedicated fruit + calyx cutout


def cutout(src, box, center, s_min, v_min, bright_rule=False):
    im = Image.open(src).convert("RGB")
    W, H = im.size
    im = im.crop((int(box[0] * W), int(box[1] * H), int(box[2] * W), int(box[3] * H)))
    w, h = im.size
    Hh, S, V = im.convert("HSV").split()
    fg = ImageChops.multiply(S.point(lambda v: 255 if v >= s_min else 0), V.point(lambda v: 255 if v >= v_min else 0))
    # green parts (stem, calyx) are never shadow: keep them with a much lower saturation bar
    green = ImageChops.multiply(Hh.point(lambda v: 255 if 50 <= v <= 125 else 0), S.point(lambda v: 255 if v >= 45 else 0))
    fg = ImageChops.lighter(fg, ImageChops.multiply(green, V.point(lambda v: 255 if v >= 25 else 0)))
    # bright, moderately colored pixels are fruit (shadows are darker)
    bright = ImageChops.multiply(S.point(lambda v: 255 if v >= 100 else 0), V.point(lambda v: 255 if v >= 205 else 0))
    if bright_rule:
        fg = ImageChops.lighter(fg, bright)
    fg = fg.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))   # drop specks
    # keep only the part connected to the center
    cx, cy = int(center[0] * w), int(center[1] * h)
    if fg.getpixel((cx, cy)) == 0:
        raise SystemExit(f"center of {src} is background; adjust its center point")
    ImageDraw.floodfill(fg, (cx, cy), 128)
    fg = fg.point(lambda v: 255 if v == 128 else 0)
    # fill holes (white highlights enclosed by the fruit): flood the outside from a padded border
    pad = Image.new("L", (w + 4, h + 4), 0)
    pad.paste(fg, (2, 2))
    ImageDraw.floodfill(pad, (0, 0), 64)
    fg = pad.crop((2, 2, w + 2, h + 2)).point(lambda v: 0 if v == 64 else 255)
    fg = fg.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(5))
    fg = fg.filter(ImageFilter.GaussianBlur(1.5)).point(lambda v: 255 if v >= 120 else 0)   # smooth jaggies
    fg = fg.filter(ImageFilter.GaussianBlur(1.0))
    out = im.convert("RGBA")
    out.putalpha(fg)
    return out.crop(fg.getbbox())


def fill_holes(mask):
    w, h = mask.size
    pad = Image.new("L", (w + 4, h + 4), 0)
    pad.paste(mask, (2, 2))
    ImageDraw.floodfill(pad, (0, 0), 64)
    return pad.crop((2, 2, w + 2, h + 2)).point(lambda v: 0 if v == 64 else 255)


def keep_component(mask, xy):
    m = mask.copy()
    ImageDraw.floodfill(m, xy, 128)
    return m.point(lambda v: 255 if v == 128 else 0)


def cutout_on_white(src, center):
    """For a fruit on a white background with a shadow on one side.
    Fruit: colored AND bright (the shadow is darker), then smoothed so nothing sticks out.
    Calyx (everything above the fruit's shoulders): anything that isn't white, so thin curls survive."""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    Hh, S, V = im.convert("HSV").split()
    fruit = ImageChops.multiply(S.point(lambda v: 255 if v >= 150 else 0), V.point(lambda v: 255 if v >= 200 else 0))
    fruit = keep_component(fruit.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3)), center)
    fruit = fill_holes(fruit)
    # smooth outline: open with a big kernel to cut bumps, then blur + threshold
    fruit = fruit.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.MaxFilter(9))
    fruit = fruit.filter(ImageFilter.GaussianBlur(3)).point(lambda v: 255 if v >= 128 else 0)
    fruit = keep_component(fruit, center)
    top = fruit.getbbox()[1]
    # calyx, only above the fruit's shoulders: green pixels, plus dark ones (the brown curl tips).
    # Excludes the white gaps inside the curls and the light beige shadow of the leaves.
    green = ImageChops.multiply(Hh.point(lambda v: 255 if 45 <= v <= 125 else 0),
                                ImageChops.multiply(S.point(lambda v: 255 if v >= 45 else 0), V.point(lambda v: 255 if v >= 20 else 0)))
    dark = ImageChops.multiply(V.point(lambda v: 255 if v < 130 else 0), S.point(lambda v: 255 if v >= 30 else 0))
    region = Image.new("L", (w, h), 0)
    ImageDraw.Draw(region).rectangle((0, 0, w, top + 30), fill=255)
    # vivid = the yellow-green band where calyx meets fruit (hue >= 29), or fruit-like pixels.
    # The leaf shadow is a more orange hue (24-26) and duller, so it stays out.
    vivid = ImageChops.lighter(
        ImageChops.multiply(Hh.point(lambda v: 255 if 29 <= v <= 125 else 0),
                            ImageChops.multiply(S.point(lambda v: 255 if v >= 120 else 0), V.point(lambda v: 255 if v >= 60 else 0))),
        ImageChops.multiply(S.point(lambda v: 255 if v >= 190 else 0), V.point(lambda v: 255 if v >= 200 else 0)))
    calyx = ImageChops.multiply(ImageChops.lighter(ImageChops.lighter(green, dark), vivid), region)
    calyx = calyx.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))   # join broken curls
    # what's attached to the fruit is decided on a slightly grown mask; the real pixels are kept
    joined = keep_component(ImageChops.lighter(fruit, calyx.filter(ImageFilter.MaxFilter(7))), center)
    mask = ImageChops.lighter(fruit, ImageChops.multiply(calyx, joined))
    alpha = mask.filter(ImageFilter.GaussianBlur(0.8))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    return out.crop(mask.getbbox())


def square(img, margin=0.06):
    side = int(max(img.size) * (1 + 2 * margin))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(img, ((side - img.width) // 2, (side - img.height) // 2), img)
    return sq


def icon(sq, px):
    small = sq.resize((px, px), Image.LANCZOS)
    if px <= 64:
        rgb = ImageEnhance.Color(small.convert("RGB")).enhance(1.15)
        rgb = rgb.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
        rgb.putalpha(small.split()[3])
        small = rgb
    return small


credits = {c["name"]: c for c in json.load(open(f"{PH}/credits.json"))}
done = []
for name, (src, box, center, s_min, v_min, (bri, col)) in CUTS.items():
    path = src if "/" in src else f"{PH}/{src}/src.jpg"
    if name in ON_WHITE:
        im = Image.open(path)
        cut = cutout_on_white(path, (int(center[0] * im.width), int(center[1] * im.height)))
    else:
        cut = cutout(path, box, center, s_min, v_min, name in BRIGHT_RULE)
    if (bri, col) != (1.0, 1.0):
        a = cut.split()[3]
        cut = ImageEnhance.Color(ImageEnhance.Brightness(cut.convert("RGB")).enhance(bri)).enhance(col).convert("RGBA")
        cut.putalpha(a)
    sq = square(cut)
    sq.save(f"{OUT}/{name}_cutout.png")
    icon(sq, 360).save(f"{OUT}/{name}_360.png")
    icon(sq, 54).save(f"{OUT}/{name}_54.png")
    done.append((name, credits.get(src, {"title": "your photo", "artist": "you", "license": "yours", "page": ""})))
    print("cut", name, cut.size)
json.dump([{**c, "name": n} for n, c in done], open(f"{OUT}/credits.json", "w"), indent=1)
