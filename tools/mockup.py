#!/usr/bin/env python3
"""Approximate preview of the main screen (390x390) using the same geometry as MainView.mc.
Curved text uses Noto Sans Condensed Bold as a stand-in for the watch's Roboto Condensed Bold."""
import math, sys
from PIL import Image, ImageDraw, ImageFont

SS = 3                      # supersampling for anti-aliasing
W = 390 * SS
cx = cy = W // 2
FOCUS, SHORT, LONG, GOAL, DIM = 0xFF5544, 0x44DD88, 0x44AAFF, 0xFFB000, 0x8A8A8A
def rgb(c, f=1.0): return tuple(int(((c >> s) & 0xFF) * f) for s in (16, 8, 0))

def arc(d, r, pen, a0, a1, col):   # a0 > a1, CIQ degrees (CCW from 3 o'clock), drawn clockwise
    box = (cx - r, cy - r, cx + r, cy + r)
    d.arc(box, -a0, -a1, fill=col, width=pen)  # PIL: clockwise from 3 o'clock

def radial(img, text, r, top, col, size):
    font = ImageFont.truetype("/usr/share/fonts/noto/NotoSans-CondensedBold.ttf", size)
    total = font.getlength(text)
    ang = (total / r)
    a = math.pi / 2 + ang / 2 if top else -math.pi / 2 - ang / 2
    for ch in text:
        w = font.getlength(ch)
        da = w / r
        mid = a - da / 2 if top else a + da / 2
        g = Image.new("RGBA", (int(w) + 4 * SS, int(size * 1.6)), (0, 0, 0, 0))
        ImageDraw.Draw(g).text((2 * SS, size * 0.8), ch, font=font, fill=rgb(col), anchor="lm")
        rot = math.degrees(mid) - 90 if top else math.degrees(mid) + 90
        g = g.rotate(rot, expand=True, resample=Image.BICUBIC)
        x, y = cx + r * math.cos(mid), cy - r * math.sin(mid)
        img.alpha_composite(g, (int(x - g.width / 2), int(y - g.height / 2)))
        a = a - da if top else a + da

def render(out, phase="FOCUS", col=FOCUS, frac=0.62, time="09:31", today=5, goal=8, streak=3, done=1, every=4, status="UNTIL 14:25"):
    img = Image.new("RGBA", (W, W), (0, 0, 0, 255)); d = ImageDraw.Draw(img)
    s = SS
    rGoal, rText, rSess = cx - 8 * s, cx - 33 * s, cx - 58 * s
    # goal segments
    span = 360 / goal; gap = 4 if goal <= 12 else 2.5
    for i in range(goal):
        st = 90 - i * span - gap / 2
        arc(d, rGoal + 3 * s, 7 * s, st, st - (span - gap), rgb(GOAL) if i < today else rgb(GOAL, 0.22))
    # session
    pen = 14 * s
    arc(d, rSess + pen // 2, pen, 90, -270, rgb(col, 0.16))
    sweep = 360 * frac
    arc(d, rSess + (pen + 10 * s) // 2, pen + 10 * s, 90, 90 - sweep, rgb(col, 0.14))
    steps = int(frac * 60) + 1
    for i in range(steps):
        a0 = 90 - sweep * i / steps; a1 = 90 - sweep * (i + 1) / steps - 0.8
        arc(d, rSess + pen // 2, pen, a0, a1, rgb(col, 0.3 + 0.7 * (i + 1) / steps))
    def dot(x, y, r, c): d.ellipse((x - r, y - r, x + r, y + r), fill=c)
    dot(cx, cy - rSess, pen // 2, rgb(col, 0.3))
    a = math.radians(90 - sweep); tx, ty = cx + rSess * math.cos(a), cy - rSess * math.sin(a)
    dot(tx, ty, pen // 2 + 5 * s, rgb(col, 0.4)); dot(tx, ty, pen // 2 + s, rgb(col)); dot(tx, ty, pen // 4, (255, 255, 255))
    # curved labels
    radial(img, " ".join(phase), rText, True, col, 19 * s)
    bottom = f"{today} / {goal} TODAY" + (f"  ·  {streak} DAY STREAK" if streak else "")
    radial(img, bottom, rText, False, GOAL if today >= goal else rgb_int(GOAL, 0.8), 19 * s)
    d = ImageDraw.Draw(img)
    # pips
    y = cy - 50 * s; g = 22 * s; r = 5 * s; x0 = cx - (every - 1) * g / 2
    for i in range(every):
        x = x0 + i * g
        if i < done: dot(x, y, r + 3 * s, rgb(FOCUS, 0.35)); dot(x, y, r, rgb(FOCUS))
        elif i == done and phase == "FOCUS":
            d.ellipse((x - r - s, y - r - s, x + r + s, y + r + s), outline=rgb(FOCUS), width=2 * s); dot(x, y, r // 2, rgb(FOCUS))
        else: d.ellipse((x - r, y - r, x + r, y + r), outline=rgb(DIM, 0.6), width=2 * s)
    # time (same font as the watch)
    tf = ImageFont.truetype("/usr/share/fonts/noto/NotoSans-CondensedLight.ttf", 75 * s)
    d.text((cx, cy), time, font=tf, fill=(255, 255, 255), anchor="mm")
    sf = ImageFont.truetype("/usr/share/fonts/noto/NotoSans-Condensed.ttf", 17 * s)
    d.text((cx, cy + 50 * s), status, font=sf, fill=rgb(DIM), anchor="mm")
    # round mask
    mask = Image.new("L", (W, W), 0); ImageDraw.Draw(mask).ellipse((0, 0, W, W), fill=255)
    bg = Image.new("RGBA", (W, W), (40, 40, 40, 255)); bg.paste(img, (0, 0), mask)
    bg.resize((390, 390), Image.LANCZOS).convert("RGB").save(out)

def rgb_int(c, f): return sum(int(((c >> sh) & 0xFF) * f) << sh for sh in (16, 8, 0))

render("docs/mockup_focus.png")
render("docs/mockup_break.png", phase="SHORT BREAK", col=SHORT, frac=0.3, time="03:29", today=8, goal=8, streak=4, done=4, status="UNTIL 14:35")
