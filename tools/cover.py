#!/usr/bin/env python3
"""Connect IQ Store cover images (500x500), one per watch style: that style's rings around the edge,
the app name curved along the top in the style's font, the launcher-icon tomato in the middle.

Usage: cover.py OUT_DIR        -> OUT_DIR/cover_<style>.png + OUT_DIR/cover_sheet.png
The tomato is the launcher-icon cutout (photo: Luc Viatour, CC BY-SA 3.0).
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = f"{ROOT}/tools/fonts"
NOTO = "/usr/share/fonts/noto"
OUT = sys.argv[1]
S = 500
SS = 3                     # draw at 3x, then downsample for smooth edges
N = S * SS
C = N // 2

FOCUS = 0xFF5544           # Theme.FOCUS
GOAL = 0xFFB000            # Theme.GOAL
DIM = 0x8A8A8A
CREAM = 0xFAF4EC
GOAL_N, TODAY = 8, 5       # example data, as in the mockups


def rgb(c, f=1.0):
    return tuple(min(255, int(((c >> s) & 0xFF) * f)) for s in (16, 8, 0))


def u(v):
    """Watch pixels (390 px screen) -> canvas pixels."""
    return v * N / 390


def arc(d, r, pen, a0, a1, col):
    """CIQ-style: degrees CCW from 3 o'clock, drawn clockwise from a0 down to a1; the stroke covers r..r+pen."""
    R = r + pen / 2
    d.arc((C - R, C - R, C + R, C + R), -a0, -a1, fill=col, width=int(pen))


def ring(d, r, pen, col):
    R = r + pen / 2
    d.ellipse((C - R, C - R, C + R, C + R), outline=col, width=int(pen))


def dot(d, x, y, r, col):
    d.ellipse((x - r, y - r, x + r, y + r), fill=col)


def polar(r, deg):
    a = math.radians(deg)
    return C + r * math.cos(a), C - r * math.sin(a)


def vfont(path, size, var=None):
    f = ImageFont.truetype(path, int(size))
    if var:
        f.set_variation_by_name(var)
    return f


def curved(img, text, font, radius, color, spacing):
    """Text along the top of a circle, centred at 12 o'clock, reading left to right;
    `radius` is where the middle of the letters sits."""
    widths = [font.getlength(ch) for ch in text]
    total = sum(widths) + spacing * (len(text) - 1)
    if os.environ.get("COVER_DEBUG"):
        print(f"  {text!r}: spans {math.degrees(total / radius):.0f} deg")
    ang = -total / 2 / radius
    size = int(font.size * 2)
    for ch, w in zip(text, widths):
        mid = ang + w / 2 / radius
        glyph = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(glyph).text((size / 2, size / 2), ch, font=font, fill=color, anchor="mm")
        glyph = glyph.rotate(-math.degrees(mid), resample=Image.BICUBIC, center=(size / 2, size / 2))
        x = C + radius * math.sin(mid)
        y = C - radius * math.cos(mid)
        img.alpha_composite(glyph, (int(x - size / 2), int(y - size / 2)))
        ang += (w + spacing) / radius


def background():
    """Near-black with a warm glow, like the hero images."""
    img = Image.new("RGBA", (N, N), (12, 10, 10, 255))
    glow = Image.new("L", (N, N), 0)
    ImageDraw.Draw(glow).ellipse((C - N * 0.40, C - N * 0.40, C + N * 0.40, C + N * 0.40), fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(N * 0.12))
    return Image.composite(Image.new("RGBA", (N, N), (120, 32, 18, 255)), img, glow.point(lambda v: v * 150 // 255))


TOM = Image.open(f"{ROOT}/docs/icons/photo/vine_single_cutout.png").convert("RGBA")
TOM = TOM.crop(TOM.getbbox())


def tomato(img, size, dy=6.0):
    """The tomato, centred on its visual weight (the fruit, not the leaves' bounding box), dy below centre."""
    ts = int(u(size))
    tom = TOM.resize((ts, int(ts * TOM.height / TOM.width)), Image.LANCZOS)
    a = tom.split()[3]
    tot = mx = my = 0
    for yy in range(0, tom.height, 3):
        for xx in range(0, tom.width, 3):
            v = a.getpixel((xx, yy))
            tot += v; mx += v * xx; my += v * yy
    tx, ty = int(C - mx / tot), int(C + u(dy) - my / tot)
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow = Image.new("RGBA", tom.size, (0, 0, 0, 0))
    shadow.putalpha(a.point(lambda v: v * 150 // 255))
    sh.alpha_composite(shadow, (tx, ty + int(u(6))))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(u(7))))
    img.alpha_composite(tom, (tx, ty))


# ---------------------------------------------------------------------------
# One cover per style. Each draws onto the background.

def ember(img):
    """Segmented goal ring + gradient progress arc with a glowing tip, cycle pips under the tomato."""
    d = ImageDraw.Draw(img)
    rG = C - u(12)
    span, gap = 360 / GOAL_N, 4
    for i in range(GOAL_N):
        a = 90 - i * span - gap / 2
        arc(d, rG, u(7), a, a - (span - gap), rgb(GOAL) if i < TODAY else rgb(GOAL, .22))
    rS, pen, p = C - u(40), u(14), 0.62
    ring(d, rS, pen, rgb(FOCUS, .16))
    sw = 360 * p
    arc(d, rS - u(5), pen + u(10), 90, 90 - sw, rgb(FOCUS, .14))
    n = int(p * 60) + 1
    for i in range(n):
        arc(d, rS, pen, 90 - sw * i / n, 90 - sw * (i + 1) / n - .8, rgb(FOCUS, .3 + .7 * (i + 1) / n))
    x, y = polar(rS + pen / 2, 90)
    dot(d, x, y, pen / 2, rgb(FOCUS, .3))
    x, y = polar(rS + pen / 2, 90 - sw)
    dot(d, x, y, pen / 2 + u(6), rgb(FOCUS, .4))
    dot(d, x, y, pen / 2 + u(1), rgb(FOCUS))
    dot(d, x, y, pen / 4, (255, 255, 255))
    tomato(img, 150, dy=10)
    d = ImageDraw.Draw(img)
    py = C + u(118)
    for i in range(4):
        x = C + (i - 1.5) * u(22)
        if i < 1:
            dot(d, x, py, u(8), rgb(FOCUS, .35))
            dot(d, x, py, u(5), rgb(FOCUS))
        elif i == 1:
            d.ellipse((x - u(6), py - u(6), x + u(6), py + u(6)), outline=rgb(FOCUS), width=int(u(2)))
            dot(d, x, py, u(2.5), rgb(FOCUS))
        else:
            d.ellipse((x - u(5), py - u(5), x + u(5), py + u(5)), outline=rgb(DIM, .6), width=int(u(2)))
    curved(img, "POMODORINO", vfont(f"{NOTO}/NotoSans-CondensedBold.ttf", u(32)), rS - u(24), rgb(CREAM), u(5))


def drain(img):
    """Thin gold goal ring with a dot, a thick red ring that drains away, the goal count in Bebas."""
    d = ImageDraw.Draw(img)
    col = 0xFF4B3E
    rG, rS, pen, p = C - u(9), C - u(34), u(12), 0.40
    ring(d, rG, u(3), rgb(GOAL, .2))
    gs = 360 * TODAY / GOAL_N
    arc(d, rG, u(3), 90, 90 - gs, rgb(GOAL))
    x, y = polar(rG + u(1.5), 90 - gs)
    dot(d, x, y, u(5), rgb(GOAL))
    ring(d, rS, pen, rgb(col, .1))
    a0, rem = 90 - 360 * p, 360 * (1 - p)
    arc(d, rS, pen, a0, a0 - rem, rgb(col))
    for a in (a0, a0 - rem):
        x, y = polar(rS + pen / 2, a)
        dot(d, x, y, pen / 2, rgb(col))
    tomato(img, 148, dy=6)
    bebas = f"{FONTS}/BebasNeue-Regular.ttf"
    d = ImageDraw.Draw(img)
    d.text((C, C + u(116)), f"{TODAY} / {GOAL_N} TODAY", font=vfont(bebas, u(26)), fill=rgb(GOAL), anchor="mm")
    curved(img, "POMODORINO", vfont(bebas, u(44)), rS - u(30), rgb(CREAM), u(5))


def mono(img):
    """Hairline ring with ticks, a thin arc with a donut knob, monospace name, goal squares."""
    d = ImageDraw.Draw(img)
    col, p = 0xFF5F57, 0.58
    rS = C - u(26)
    ring(d, rS, u(2), rgb(0x333333))
    for a in (90, 0, 270, 180):
        d.line([polar(rS - u(8), a), polar(rS + u(10), a)], fill=rgb(0x555555), width=int(u(2)))
    sw = 360 * p
    arc(d, rS - u(1), u(4), 90, 90 - sw, rgb(col))
    x, y = polar(rS + u(1), 90 - sw)
    dot(d, x, y, u(12), rgb(col))
    dot(d, x, y, u(5), (0, 0, 0))
    tomato(img, 150, dy=8)
    d = ImageDraw.Draw(img)
    sq, g = u(10), u(6)
    x0 = C - (GOAL_N * sq + (GOAL_N - 1) * g) / 2
    y0 = C + u(108)
    for i in range(GOAL_N):
        x = x0 + i * (sq + g)
        if i < TODAY:
            d.rectangle((x, y0, x + sq, y0 + sq), fill=rgb(GOAL))
        else:
            d.rectangle((x, y0, x + sq, y0 + sq), outline=rgb(0x555555), width=int(u(1)))
    jb = f"{FONTS}/JetBrainsMono-VF.ttf"
    curved(img, "pomodorino_", vfont(jb, u(30), "Medium"), rS - u(34), rgb(CREAM), u(2))


def liquid(img):
    """Segmented goal ring, a glass ring that fills with rippling liquid behind the tomato."""
    d = ImageDraw.Draw(img)
    col, p, t = FOCUS, 0.42, 0.3
    rG, rS = C - u(10), C - u(36)
    span, gap = 360 / GOAL_N, 4
    for i in range(GOAL_N):
        a = 90 - i * span - gap / 2
        arc(d, rG, u(6), a, a - (span - gap), rgb(GOAL) if i < TODAY else rgb(GOAL, .22))
    rIn = rS - u(4)
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).ellipse((C - rIn, C - rIn, C + rIn, C + rIn), fill=255)
    liq = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ld = ImageDraw.Draw(liq)
    level = C + rIn - 2 * rIn * p
    for amp, ph, f in ((7, .5, .22), (6, 0, .5)):
        pts = [(x, level + u(amp) * math.sin(2 * math.pi * ((x - C) / (rIn * 1.2) + t + ph)))
               for x in range(int(C - rIn), int(C + rIn) + 1, 6)]
        pts += [(C + rIn, C + rIn), (C - rIn, C + rIn)]
        ld.polygon(pts, fill=rgb(col, f) + (255,))
    clip = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    clip.paste(liq, (0, 0), mask)
    img.alpha_composite(clip)
    d = ImageDraw.Draw(img)
    ring(d, rS, u(3), rgb(col, .7))
    tomato(img, 152, dy=6)
    curved(img, "POMODORINO", vfont(f"{FONTS}/Outfit-VF.ttf", u(30), "SemiBold"), rS - u(28), rgb(CREAM), u(3))


def classic(img):
    """One dot per minute around the edge, little tomatoes for the goal along the bottom, serif name."""
    d = ImageDraw.Draw(img)
    tom_c, cream, sage = 0xE4573D, 0xF4E9D8, 0x8FB996
    rS, p = C - u(44), 0.62
    lit = p * 25
    for i in range(25):
        x, y = polar(rS, 90 - i * 360 / 25)
        if i < int(lit):
            dot(d, x, y, u(5), rgb(tom_c))
        elif i == int(lit):
            dot(d, x, y, u(8), rgb(tom_c, .35))
            dot(d, x, y, u(5), rgb(cream))
        else:
            dot(d, x, y, u(3), rgb(0x4A4038))
    for i in range(GOAL_N):
        a = 270 + (i - (GOAL_N - 1) / 2) * 11
        x, y = polar(C - u(16), a)
        dot(d, x, y, u(7), rgb(tom_c) if i < TODAY else rgb(0x3A2E28))
        lc = rgb(sage) if i < TODAY else rgb(0x2E3A30)
        d.polygon([(x - u(5), y - u(6)), (x, y - u(3)), (x + u(5), y - u(6)), (x, y - u(9))], fill=lc)
    tomato(img, 140, dy=14)
    curved(img, "Pomodorino", vfont(f"{FONTS}/PlayfairDisplay-VF.ttf", u(36), "SemiBold"), rS - u(30),
           rgb(cream), u(1))


STYLES = [("ember", ember), ("drain", drain), ("mono", mono), ("liquid", liquid), ("classic", classic)]

os.makedirs(OUT, exist_ok=True)
covers = []
for name, fn in STYLES:
    img = background()
    fn(img)
    out = img.resize((S, S), Image.LANCZOS).convert("RGB")
    path = f"{OUT}/cover_{name}.png"
    out.save(path, optimize=True)
    covers.append((name, out))
    print("wrote", path, os.path.getsize(path) // 1024, "KB")

# comparison sheet
label = vfont(f"{FONTS}/Outfit-VF.ttf", 26, "Medium")
sheet = Image.new("RGB", (len(covers) * 520 + 20, 580), (30, 30, 30))
sd = ImageDraw.Draw(sheet)
for i, (name, im) in enumerate(covers):
    sheet.paste(im, (20 + i * 520, 20))
    sd.text((20 + i * 520 + 250, 550), f"{i + 1} · {name.capitalize()}", font=label, fill=(220, 220, 220), anchor="mm")
sheet.save(f"{OUT}/cover_sheet.png", optimize=True)
print("wrote", f"{OUT}/cover_sheet.png")
