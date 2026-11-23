#!/usr/bin/env python3
"""Render 8 design variants of the main screen as animated GIFs + an HTML comparison page.

Usage: variants.py FONT_DIR OUT_DIR
FONT_DIR holds the downloaded Google Fonts (OFL); Noto comes from /usr/share/fonts/noto.
The animation is sped up: one GIF loop = one whole session.
"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFont

FD, OUT = sys.argv[1], sys.argv[2]
NOTO = "/usr/share/fonts/noto/"
SS = 2
W = 390 * SS
C = W // 2
FRAMES = 40


def font(path, size, var=None):
    f = ImageFont.truetype(path, size)
    if var:
        try:
            f.set_variation_by_name(var.encode())
        except Exception:
            f.set_variation_by_name(var)
    return f


def digit_font(path, digit_h, var=None):
    size = digit_h
    for _ in range(20):
        f = font(path, size, var)
        b = f.getbbox("0")
        h = b[3] - b[1]
        if h == digit_h:
            break
        size = max(4, round(size * digit_h / h))
    return font(path, size, var)


def rgb(c, f=1.0):
    return tuple(min(255, int(((c >> s) & 0xFF) * f)) for s in (16, 8, 0))


def arc(d, r, pen, a0, a1, col):
    """CIQ-style: degrees CCW from 3 o'clock, drawn clockwise from a0 down to a1, pen centered on r."""
    if a0 - a1 >= 360:
        a1 = a0 - 359.99
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


def text(d, xy, s, f, col, anchor="mm"):
    d.text(xy, s, font=f, fill=col, anchor=anchor)


def radial(img, s, r, top, col, f):
    """Text along a circle, like dc.drawRadialText (top reads clockwise, bottom counter-clockwise)."""
    size = f.size
    total = f.getlength(s)
    span = total / r
    a = math.pi / 2 + span / 2 if top else -math.pi / 2 - span / 2
    for ch in s:
        w = f.getlength(ch)
        da = w / r
        mid = a - da / 2 if top else a + da / 2
        g = Image.new("RGBA", (int(w) + 4 * SS, int(size * 1.6)), (0, 0, 0, 0))
        ImageDraw.Draw(g).text((2 * SS, size * 0.8), ch, font=f, fill=col, anchor="lm")
        g = g.rotate(math.degrees(mid) - 90 if top else math.degrees(mid) + 90, expand=True, resample=Image.BICUBIC)
        x, y = C + r * math.cos(mid), C - r * math.sin(mid)
        img.alpha_composite(g, (int(x - g.width / 2), int(y - g.height / 2)))
        a = a - da if top else a + da


def mmss(p, mins=25):
    sec = int(round((1 - p) * mins * 60))
    return f"{sec // 60:02d}:{sec % 60:02d}"


LABEL = font(NOTO + "NotoSans-CondensedBold.ttf", 19 * SS)        # stand-in for watch Roboto Condensed Bold
SMALL = font(NOTO + "NotoSans-Condensed.ttf", 17 * SS)
TODAY, GOAL_N, STREAK = 5, 8, 3

# ---------------------------------------------------------------------------
# Variants: each draws one frame for progress p (0..1) and animation time t (0..1 per "second")


def v_ember(img, d, p, t):
    """Current design: gradient arc, glowing breathing tip, segmented goal ring."""
    col, s = 0xFF5544, SS
    rG, rT, rS, pen = C - 8 * s, C - 33 * s, C - 58 * s, 14 * s
    span, gap = 360 / GOAL_N, 4
    for i in range(GOAL_N):
        a = 90 - i * span - gap / 2
        arc(d, rG, 7 * s, a, a - (span - gap), rgb(0xFFB000) if i < TODAY else rgb(0xFFB000, .22))
    ring(d, rS, pen, rgb(col, .16))
    sw = 360 * p
    arc(d, rS, pen + 10 * s, 90, 90 - sw, rgb(col, .14))
    n = int(p * 60) + 1
    for i in range(n):
        arc(d, rS, pen, 90 - sw * i / n, 90 - sw * (i + 1) / n - .8, rgb(col, .3 + .7 * (i + 1) / n))
    dot(d, C, C - rS, pen / 2, rgb(col, .3))
    x, y = polar(rS, 90 - sw)
    dot(d, x, y, pen / 2 + (4 + 3 * math.sin(2 * math.pi * t)) * s, rgb(col, .4))
    dot(d, x, y, pen / 2 + s, rgb(col))
    dot(d, x, y, pen / 4, (255, 255, 255))
    radial(img, "F O C U S", rT, True, rgb(col), LABEL)
    radial(img, f"{TODAY} / {GOAL_N} TODAY  ·  {STREAK} DAY STREAK", rT, False, rgb(0xFFB000, .85), LABEL)
    d = ImageDraw.Draw(img)
    pips(d, C - 50 * s, col)
    text(d, (C, C), mmss(p), digit_font(NOTO + "NotoSans-CondensedLight.ttf", 56 * s), (255, 255, 255))
    text(d, (C, C + 50 * s), "UNTIL 14:25", SMALL, rgb(0x8A8A8A))


def v_orbit(img, d, p, t):
    """Sci-fi: hairline track, comet with a fading tail, goal as glowing dots."""
    col, cyan, s = 0xFF2D6F, 0x2DE2FF, SS
    rG, rT, rS = C - 12 * s, C - 36 * s, C - 60 * s
    for i in range(GOAL_N):
        x, y = polar(rG, 90 - i * 360 / GOAL_N)
        if i < TODAY:
            dot(d, x, y, 8 * s, rgb(cyan, .25))
            dot(d, x, y, 4.5 * s, rgb(cyan))
        else:
            d.ellipse((x - 4 * s, y - 4 * s, x + 4 * s, y + 4 * s), outline=rgb(cyan, .6), width=2 * s)
    ring(d, rS, 2 * s, rgb(0x2A2A2A))
    sw = 360 * p
    arc(d, rS, 2 * s, 90, 90 - sw, rgb(col, .45))
    tail = min(sw, 70)
    for i in range(24):
        f = (i + 1) / 24
        a0 = 90 - sw + tail * (1 - (i) / 24)
        a1 = 90 - sw + tail * (1 - (i + 1) / 24) - .5
        arc(d, rS, (2 + 8 * f) * s, a0, a1, rgb(col, .15 + .85 * f))
    x, y = polar(rS, 90 - sw)
    flick = 1 + .25 * math.sin(2 * math.pi * t * 2)
    dot(d, x, y, 11 * s * flick, rgb(col, .35))
    dot(d, x, y, 6 * s, (255, 255, 255))
    lab = font(f"{FD}/Michroma-Regular.ttf", 15 * s)
    radial(img, "F O C U S", rT, True, rgb(cyan), lab)
    radial(img, f"{TODAY}/{GOAL_N}  ·  STREAK {STREAK}", rT, False, rgb(cyan, .8), lab)
    d = ImageDraw.Draw(img)
    for i in range(4):
        x = C + (i - 1.5) * 20 * s
        y = C - 48 * s
        pts = [(x, y - 5 * s), (x + 5 * s, y), (x, y + 5 * s), (x - 5 * s, y)]
        d.polygon(pts, fill=rgb(col) if i < 1 else None, outline=rgb(col) if i == 1 else rgb(0x555555))
    text(d, (C, C), mmss(p), digit_font(f"{FD}/Orbitronwght.ttf", 44 * s, "Medium"), (255, 255, 255))
    text(d, (C, C + 46 * s), "UNTIL 14:25", font(f"{FD}/Michroma-Regular.ttf", 12 * s), rgb(0x8A8A8A))


def v_dial(img, d, p, t):
    """Stopwatch dial: 60 ticks light up, the newest one flashes."""
    col, s = 0xFF6A3D, SS
    rG, rS = C - 8 * s, C - 64 * s
    span, gap = 360 / GOAL_N, 3
    for i in range(GOAL_N):
        a = 90 - i * span - gap / 2
        arc(d, rG, 4 * s, a, a - (span - gap), rgb(0xFFB000) if i < TODAY else rgb(0xFFB000, .2))
    lit = int(p * 60)
    for i in range(60):
        a = 90 - i * 6
        long_ = i % 5 == 0
        r0, r1 = rS - (14 if long_ else 9) * s, rS + 6 * s
        if i == lit:
            r0, r1 = rS - 20 * s, rS + 10 * s
            c = rgb(0xFFFFFF, .6 + .4 * abs(math.sin(math.pi * t)))
            w = 4 * s
        elif i < lit:
            c, w = rgb(col, .45 + .55 * i / 60), (3 if long_ else 2) * s
        else:
            c, w = rgb(0x333333), (3 if long_ else 2) * s
        d.line([polar(r0, a), polar(r1, a)], fill=c, width=int(w))
    radial(img, f"{TODAY} / {GOAL_N} TODAY  ·  {STREAK} DAY STREAK", C - 28 * s, False, rgb(0xFFB000, .85), LABEL)
    d = ImageDraw.Draw(img)
    text(d, (C, C - 52 * s), "FOCUS", font(f"{FD}/Rajdhani-SemiBold.ttf", 28 * s), rgb(col))
    text(d, (C, C + 2 * s), mmss(p), digit_font(f"{FD}/Rajdhani-SemiBold.ttf", 62 * s), (255, 255, 255))
    text(d, (C, C + 52 * s), "UNTIL 14:25", font(f"{FD}/Rajdhani-SemiBold.ttf", 20 * s), rgb(0x8A8A8A))


def v_drain(img, d, p, t):
    """Bold: a thick ring that drains away as time runs out."""
    col, gold, s = 0xFF4B3E, 0xFFB000, SS
    rG, rS, pen = C - 9 * s, C - 46 * s, 26 * s
    ring(d, rG, 3 * s, rgb(gold, .2))
    gs = 360 * TODAY / GOAL_N
    arc(d, rG, 3 * s, 90, 90 - gs, rgb(gold))
    x, y = polar(rG, 90 - gs)
    dot(d, x, y, 5 * s, rgb(gold))
    ring(d, rS, pen, rgb(col, .1))
    rem = 360 * (1 - p)
    if rem > 0.5:
        a_start = 90 - 360 * p
        arc(d, rS, pen, a_start, a_start - rem + 0.01 if rem < 360 else a_start - 359.9, rgb(col))
        for a in (a_start, 90 - 359.99):
            x, y = polar(rS, a)
            dot(d, x, y, pen / 2, rgb(col))
    bebas = f"{FD}/BebasNeue-Regular.ttf"
    text(d, (C, C - 58 * s), "FOCUS", font(bebas, 30 * s), rgb(col))
    text(d, (C, C + 4 * s), mmss(p), digit_font(bebas, 70 * s), (255, 255, 255))
    text(d, (C, C + 60 * s), f"{TODAY} / {GOAL_N} TODAY", font(bebas, 26 * s), rgb(gold))


def v_mono(img, d, p, t):
    """Minimal dev: hairline ring, sliding donut knob, monospace text, blinking cursor."""
    col, s = 0xFF5F57, SS
    rS = C - 40 * s
    ring(d, rS, 2 * s, rgb(0x333333))
    for a in (90, 0, 270, 180):
        d.line([polar(rS - 8 * s, a), polar(rS + 8 * s, a)], fill=rgb(0x555555), width=2 * s)
    sw = 360 * p
    arc(d, rS, 4 * s, 90, 90 - sw, rgb(col))
    x, y = polar(rS, 90 - sw)
    dot(d, x, y, 12 * s, rgb(col))
    dot(d, x, y, 5 * s, (0, 0, 0))
    jb = f"{FD}/JetBrainsMonowght.ttf"
    lab = font(jb, 18 * s, "Regular")
    cur = "_" if t < .5 else " "
    text(d, (C, C - 60 * s), "// focus" + cur, lab, rgb(col))
    text(d, (C, C), mmss(p), digit_font(jb, 50 * s, "Light"), (255, 255, 255))
    text(d, (C, C + 44 * s), "ends 14:25", font(jb, 15 * s, "Regular"), rgb(0x8A8A8A))
    sq, g = 10 * s, 6 * s
    x0 = C - (GOAL_N * sq + (GOAL_N - 1) * g) / 2
    y0 = C + 74 * s
    for i in range(GOAL_N):
        x = x0 + i * (sq + g)
        if i < TODAY:
            d.rectangle((x, y0, x + sq, y0 + sq), fill=rgb(0xFFB000))
        else:
            d.rectangle((x, y0, x + sq, y0 + sq), outline=rgb(0x555555), width=s)
    text(d, (C, y0 + 30 * s), f"streak={STREAK}", font(jb, 14 * s, "Regular"), rgb(0x8A8A8A))


def v_liquid(img, d, p, t):
    """Liquid: the dial fills up like a glass, with rippling waves."""
    col, s = 0xFF5544, SS
    rG, rT, rS = C - 8 * s, C - 33 * s, C - 54 * s
    span, gap = 360 / GOAL_N, 4
    for i in range(GOAL_N):
        a = 90 - i * span - gap / 2
        arc(d, rG, 6 * s, a, a - (span - gap), rgb(0xFFB000) if i < TODAY else rgb(0xFFB000, .22))
    rIn = rS - 4 * s
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).ellipse((C - rIn, C - rIn, C + rIn, C + rIn), fill=255)
    liquid = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ld = ImageDraw.Draw(liquid)
    level = C + rIn - 2 * rIn * p
    for layer, (amp, ph, f) in enumerate(((7, .5, .22), (6, 0, .5))):
        pts = []
        for x in range(C - rIn, C + rIn + 1, 4 * s):
            pts.append((x, level + amp * s * math.sin(2 * math.pi * ((x - C) / (rIn * 1.2) + t + ph))))
        pts += [(C + rIn, C + rIn), (C - rIn, C + rIn)]
        ld.polygon(pts, fill=rgb(col, f))
    img.paste(liquid, (0, 0), Image.composite(liquid, Image.new("RGBA", (W, W)), mask).split()[3])
    d = ImageDraw.Draw(img)
    ring(d, rS, 3 * s, rgb(col, .7))
    radial(img, "F O C U S", rT, True, rgb(col), LABEL)
    radial(img, f"{TODAY} / {GOAL_N} TODAY  ·  {STREAK} DAY STREAK", rT, False, rgb(0xFFB000, .85), LABEL)
    d = ImageDraw.Draw(img)
    of = f"{FD}/Outfitwght.ttf"
    text(d, (C, C), mmss(p), digit_font(of, 60 * s, "ExtraLight"), (255, 255, 255))
    text(d, (C, C + 52 * s), "UNTIL 14:25", font(of, 16 * s, "Regular"), rgb(0xDDDDDD))


def v_sport(img, d, p, t):
    """Sporty gauge: 270° segmented speedometer, inner goal gauge, numbers in the gap."""
    col, gold, s = 0xFF3B30, 0xFFB000, SS
    rS, rG = C - 22 * s, C - 52 * s
    a_start, total = 225, 270
    blocks, gap = 30, 2.2
    lit = p * blocks
    for i in range(blocks):
        a0 = a_start - i * total / blocks
        a1 = a0 - total / blocks + gap
        if i < int(lit):
            c = rgb(col, .45 + .55 * i / blocks)
        elif i == int(lit):
            c = rgb(col, .5 + .5 * abs(math.sin(math.pi * t)))
        else:
            c = rgb(0x262626)
        arc(d, rS, 20 * s, a0, a1, c)
    arc(d, rG, 6 * s, a_start, a_start - total, rgb(gold, .18))
    arc(d, rG, 6 * s, a_start, a_start - total * TODAY / GOAL_N, rgb(gold))
    ox = f"{FD}/Oxaniumwght.ttf"
    text(d, (C, C - 56 * s), "FOCUS", font(ox, 22 * s, "SemiBold"), rgb(col))
    text(d, (C, C - 2 * s), mmss(p), digit_font(ox, 56 * s, "SemiBold"), (255, 255, 255))
    text(d, (C, C + 44 * s), "UNTIL 14:25", font(ox, 15 * s, "Medium"), rgb(0x8A8A8A))
    text(d, (C, C + 118 * s), f"{TODAY}/{GOAL_N}", font(ox, 30 * s, "Bold"), rgb(gold))
    text(d, (C, C + 146 * s), f"TODAY · {STREAK}D STREAK", font(ox, 13 * s, "Medium"), rgb(gold, .8))


def v_classic(img, d, p, t):
    """Elegant: serif numerals, one dot per minute, tomato icons for the daily goal."""
    tomato, cream, sage, s = 0xE4573D, 0xF4E9D8, 0x8FB996, SS
    rS = C - 46 * s
    lit = p * 25
    for i in range(25):
        x, y = polar(rS, 90 - i * 360 / 25)
        if i < int(lit):
            dot(d, x, y, 5 * s, rgb(tomato))
        elif i == int(lit):
            dot(d, x, y, (6 + 3 * math.sin(2 * math.pi * t)) * s, rgb(tomato, .35))
            dot(d, x, y, 5 * s, rgb(cream))
        else:
            dot(d, x, y, 3 * s, rgb(0x4A4038))
    # tomatoes along the bottom
    for i in range(GOAL_N):
        a = 270 + (i - (GOAL_N - 1) / 2) * 11
        x, y = polar(C - 16 * s, a)
        c = rgb(tomato) if i < TODAY else rgb(0x3A2E28)
        dot(d, x, y, 7 * s, c)
        lc = rgb(sage) if i < TODAY else rgb(0x2E3A30)
        d.polygon([(x - 5 * s, y - 6 * s), (x, y - 3 * s), (x + 5 * s, y - 6 * s), (x, y - 9 * s)], fill=lc)
    pf = f"{FD}/PlayfairDisplaywght.ttf"
    text(d, (C, C - 58 * s), "Focus", font(pf, 26 * s, "Regular"), rgb(tomato))
    text(d, (C, C + 2 * s), mmss(p), digit_font(pf, 40 * s, "Regular"), rgb(cream))
    text(d, (C, C + 60 * s), f"{TODAY} of {GOAL_N} today  ·  {STREAK} day streak", font(pf, 15 * s, "Regular"), rgb(cream, .7))


def pips(d, y, col):
    s = SS
    for i in range(4):
        x = C + (i - 1.5) * 22 * s
        if i < 1:
            dot(d, x, y, 8 * s, rgb(col, .35))
            dot(d, x, y, 5 * s, rgb(col))
        elif i == 1:
            d.ellipse((x - 6 * s, y - 6 * s, x + 6 * s, y + 6 * s), outline=rgb(col), width=2 * s)
            dot(d, x, y, 2.5 * s, rgb(col))
        else:
            d.ellipse((x - 5 * s, y - 5 * s, x + 5 * s, y + 5 * s), outline=rgb(0x8A8A8A, .6), width=2 * s)


VARIANTS = [
    ("1", "Ember", v_ember, "Noto Sans Condensed Light",
     "Gradient arc with a glowing tip that breathes; goal ring split into one segment per pomodoro; curved labels.",
     "Current design. Works as-is at 1 update/sec."),
    ("2", "Orbit", v_orbit, "Orbitron Medium + Michroma",
     "Hairline track with a comet head and fading tail; goal as glowing dots; magenta and cyan.",
     "1 update/sec is fine; the flicker needs faster redraws while the screen is on."),
    ("3", "Dial", v_dial, "Rajdhani SemiBold",
     "60 stopwatch ticks light up one by one; the newest tick flashes; thin segmented goal ring.",
     "Works at 1 update/sec (one tick ≈ 25 s for a 25-min focus)."),
    ("4", "Drain", v_drain, "Bebas Neue",
     "Thick ring that drains away as time runs out; continuous goal arc with a knob; bold condensed type.",
     "Works at 1 update/sec."),
    ("5", "Mono", v_mono, "JetBrains Mono Light",
     "Minimal hairline ring with a donut knob; goal as squares; blinking terminal cursor.",
     "Works at 1 update/sec (the cursor blinks once per second)."),
    ("6", "Liquid", v_liquid, "Outfit ExtraLight",
     "The dial fills up like a glass with two rippling waves; segmented goal ring; curved labels.",
     "The level rises at 1 update/sec; smooth ripples need faster redraws (more battery)."),
    ("7", "Sport", v_sport, "Oxanium SemiBold",
     "270° segmented gauge, like a speedometer; inner goal gauge; count shown in the bottom gap.",
     "Works at 1 update/sec; the leading block blinks."),
    ("8", "Classic", v_classic, "Playfair Display",
     "Serif numerals; one dot per minute around the dial; little tomatoes for the daily goal; warm cream palette.",
     "Works at 1 update/sec (one dot per minute)."),
]


def render(fn, p, t):
    img = Image.new("RGBA", (W, W), (0, 0, 0, 255))
    fn(img, ImageDraw.Draw(img), p, t)
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, W - 1, W - 1), fill=255)
    out = Image.new("RGB", (W, W), (24, 24, 24))
    out.paste(img.convert("RGB"), (0, 0), mask)
    return out.resize((390, 390), Image.LANCZOS)


os.makedirs(OUT, exist_ok=True)
for num, name, fn, *_ in VARIANTS:
    frames = []
    for k in range(FRAMES):
        p = 0.02 + 0.96 * k / (FRAMES - 1)
        t = (k % 10) / 10
        frames.append(render(fn, p, t).quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    frames[0].save(f"{OUT}/v{num}_{name.lower()}.gif", save_all=True, append_images=frames[1:], duration=110, loop=0)
    render(fn, 0.62, 0.25).save(f"{OUT}/v{num}_{name.lower()}.png")
    print("rendered", num, name)

cards = "\n".join(f"""
  <figure>
    <img src="v{n}_{nm.lower()}.gif" width="300" height="300" alt="{nm} variant">
    <figcaption><h2>{n} · {nm}</h2>
      <p class="font">{fnt}</p><p>{desc}</p><p class="note">{note}</p></figcaption>
  </figure>""" for n, nm, _, fnt, desc, note in VARIANTS)
with open(f"{OUT}/index.html", "w") as f:
    f.write(f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Pomodorino design variants</title>
<style>
  body {{ background:#111; color:#ddd; font-family:system-ui,sans-serif; margin:2rem; }}
  h1 {{ font-weight:600; }} .intro {{ color:#999; max-width:60rem; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(320px,1fr)); gap:2rem; margin-top:2rem; }}
  figure {{ margin:0; background:#1b1b1b; border-radius:16px; padding:1rem; }}
  img {{ display:block; margin:0 auto; border-radius:50%; }}
  h2 {{ margin:.8rem 0 .2rem; font-size:1.2rem; color:#fff; }}
  p {{ margin:.3rem 0; line-height:1.4; }} .font {{ color:#ffb000; }} .note {{ color:#888; font-size:.9rem; }}
</style></head><body>
<h1>Pomodorino: pick a design</h1>
<p class="intro">Each loop is one whole session, sped up. On the watch the ring moves once per second.
Example data: focus session, 5 of 8 pomodoros today, 3-day streak. Curved labels use a stand-in for the watch's
built-in Roboto Condensed. Timer fonts are the real ones, embedded as bitmap fonts. Mix and match is possible,
e.g. the Dial ring with the Bebas font.</p>
<div class="grid">{cards}
</div></body></html>""")
print("wrote", f"{OUT}/index.html")
