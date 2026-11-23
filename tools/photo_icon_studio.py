#!/usr/bin/env python3
"""Cut out the new tomato photos (white studio background, neutral grey shadow) and build a comparison sheet."""
import glob, os, sys
from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

SRC, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)


def th(ch, lo, hi=255):
    return ch.point(lambda v: 255 if lo <= v <= hi else 0)


def mul(*ms):
    r = ms[0]
    for m in ms[1:]:
        r = ImageChops.multiply(r, m)
    return r


def keep(mask, xy):
    m = mask.copy()
    ImageDraw.floodfill(m, xy, 128)
    return m.point(lambda v: 255 if v == 128 else 0)


def fill_holes(mask):
    w, h = mask.size
    pad = Image.new("L", (w + 4, h + 4), 0)
    pad.paste(mask, (2, 2))
    ImageDraw.floodfill(pad, (0, 0), 64)
    return pad.crop((2, 2, w + 2, h + 2)).point(lambda v: 0 if v == 64 else 255)


def cut(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    k = max(1, round(w / 400))                      # kernel scale: the photos are 554 or 800 px
    H, S, V = im.convert("HSV").split()
    c = (w // 2, int(h * 0.6))
    # fruit: strongly saturated (background and shadow are neutral grey, S < 30)
    fruit = mul(th(S, 110), th(V, 50))
    fruit = keep(fruit.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3)), c)
    fruit = fill_holes(fruit)
    fruit = fruit.filter(ImageFilter.MinFilter(4 * k + 1)).filter(ImageFilter.MaxFilter(4 * k + 1))
    fruit = keep(fruit.filter(ImageFilter.GaussianBlur(2 * k)).point(lambda v: 255 if v >= 128 else 0), c)
    # calyx: any colored pixel (the sepals are a muted grey-green with whitish highlights)
    colored = mul(th(S, 40), th(V, 25, 250))
    # faint sepals (S ~20) only above the fruit's shoulders: green hue and darker than the white
    # background; the shadow there is neutral grey (hue 0), so the hue test keeps it out
    top = fruit.getbbox()[1]
    region = Image.new("L", (w, h), 0)
    ImageDraw.Draw(region).rectangle((0, 0, w, top + 10 * k), fill=255)
    faint = mul(th(H, 30, 110), th(S, 12), th(V, 25, 228), region)
    colored = ImageChops.lighter(colored, faint)
    calyx = colored.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))
    joined = keep(ImageChops.lighter(fruit, calyx.filter(ImageFilter.MaxFilter(2 * k + 1))), c)
    mask = fill_holes(ImageChops.lighter(fruit, mul(calyx, joined)))
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))   # shave 1 px fringe
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


names = {
    "WhatsApp Image 2026-11-09 at 11.07.04.jpeg": "1_yellow_orange_oval",
    "WhatsApp Image 2026-11-09 at 11.07.04 (1).jpeg": "2_orange_long",
    "WhatsApp Image 2026-11-09 at 11.07.04 (2).jpeg": "3_red_long_curls",
    "WhatsApp Image 2026-11-09 at 11.07.04 (3).jpeg": "4_red_round",
    "WhatsApp Image 2026-11-09 at 11.07.05.jpeg": "5_red_oval",
}
tiles = []
for f, n in names.items():
    sq = square(cut(os.path.join(SRC, f)))
    sq.save(f"{OUT}/{n}_cutout.png")
    icon(sq, 360).save(f"{OUT}/{n}_360.png")
    icon(sq, 54).save(f"{OUT}/{n}_54.png")
    tiles.append((n, icon(sq, 240), icon(sq, 54)))
cur = Image.open("/home/emira/Projects/pomodorino/docs/icons/photo/your_yellow_cutout.png")
tiles.append(("current", icon(cur, 240), icon(cur, 54)))

font = ImageFont.truetype("/usr/share/fonts/noto/NotoSans-Regular.ttf", 22)
small = ImageFont.truetype("/usr/share/fonts/noto/NotoSans-Regular.ttf", 16)
cw = 280
sheet = Image.new("RGB", (cw * len(tiles), 420), "black")
d = ImageDraw.Draw(sheet)
for i, (n, big, s54) in enumerate(tiles):
    x = i * cw + 20
    sheet.paste(big, (x, 10), big)
    sheet.paste(s54, (x, 280), s54)
    d.text((x + 64, 293), "Pomodorino", fill="white", font=font)
    s2 = s54.resize((27, 27), Image.LANCZOS)     # also at half size, to judge the silhouette
    sheet.paste(s2, (x + 13, 345), s2)
    d.text((x, 390), n, fill=(170, 170, 170), font=small)
sheet.save(f"{OUT}/sheet.png")
print("ok")
