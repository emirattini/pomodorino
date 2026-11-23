#!/usr/bin/env python3
"""8 simple, original icon drafts for Pomodorino. Writes docs/icons/simple/."""
import math, os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
C = S // 2
OUT = "docs/icons/simple"
os.makedirs(OUT, exist_ok=True)

RED, RED_D, RED_L = (232, 52, 40), (170, 28, 24), (255, 120, 100)
GREEN, GREEN_D = (70, 175, 80), (40, 120, 55)
WHITE, CREAM, DARK = (255, 255, 255), (250, 238, 214), (34, 34, 38)


def catmull(pts, per=12):
    out, n = [], len(pts)
    for i in range(n):
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        for k in range(per):
            t = k / per
            out.append(tuple(0.5 * (2 * p1[j] + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t * t
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t ** 3) for j in (0, 1)))
    return out


def tomato_shape(cx, cy, r, squash=0.88):
    pts = []
    for i in range(240):
        a = 2 * math.pi * i / 240
        top = math.atan2(math.sin(a + math.pi / 2), math.cos(a + math.pi / 2))
        rr = r * (1 - 0.035 * math.cos(2 * top) + 0.012 * math.cos(4 * top) - 0.08 * math.exp(-(top / 0.33) ** 2))
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a) * squash))
    return pts


def sepals(d, cx, cy, r, col=GREEN, n=5, inner=0.32):
    pts = []
    for i in range(2 * n):
        rr = r if i % 2 == 0 else r * inner
        a = math.radians(-90 + i * 180 / n)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a) * 0.62))
    d.polygon(catmull(pts, 6), fill=col)


def stem(d, cx, top, h, w, col=GREEN_D):
    d.rounded_rectangle((cx - w / 2, top, cx + w / 2, top + h), radius=w / 2, fill=col)


def tomato(img, cx, cy, r, body=RED, leaf=GREEN, highlight=True):
    d = ImageDraw.Draw(img)
    d.polygon(tomato_shape(cx, cy, r), fill=body)
    if highlight:
        hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(hl).ellipse((cx - r * 0.62, cy - r * 0.62, cx - r * 0.12, cy - r * 0.28), fill=(255, 255, 255, 70))
        img.alpha_composite(hl.filter(ImageFilter.GaussianBlur(r * 0.06)))
        d = ImageDraw.Draw(img)
    stem(d, cx, cy - r * 1.02, r * 0.3, r * 0.1)
    sepals(d, cx, cy - r * 0.78, r * 0.5, leaf)
    return d


def canvas():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def badge(img, col):
    ImageDraw.Draw(img).ellipse((24, 24, S - 24, S - 24), fill=col)


def hand(d, cx, cy, ang, length, w, col=WHITE):
    a = math.radians(ang)
    x, y = cx + length * math.cos(a), cy - length * math.sin(a)
    d.line([(cx, cy), (x, y)], fill=col, width=int(w))
    d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=col)
    d.ellipse((cx - w * 0.8, cy - w * 0.8, cx + w * 0.8, cy + w * 0.8), fill=col)


# 1 Clock tomato: the tomato is the clock face.
def clock():
    img = canvas()
    d = tomato(img, C, 560, 400)
    for k in range(4):
        a = math.radians(90 - k * 90)
        x, y = C + 290 * math.cos(a), 560 - 250 * math.sin(a)
        d.ellipse((x - 22, y - 22, x + 22, y + 22), fill=(255, 255, 255, 230))
    hand(d, C, 575, 90, 190, 50)
    hand(d, C, 575, 0, 150, 50)
    return img


# 2 Ring: the app's progress ring, with the leaf in the gap at the top.
def ring():
    img = canvas()
    badge(img, DARK)
    d = ImageDraw.Draw(img)
    r, w = 330, 110
    d.ellipse((C - r - w / 2, 560 - r - w / 2, C + r + w / 2, 560 + r + w / 2), outline=(70, 30, 30), width=w)
    d.arc((C - r - w / 2, 560 - r - w / 2, C + r + w / 2, 560 + r + w / 2), -60, 240, fill=RED, width=w)
    for ang in (-60, 240):
        a = math.radians(ang)
        x, y = C + r * math.cos(a), 560 + r * math.sin(a)
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=RED)
    stem(d, C, 150, 120, 46)
    sepals(d, C, 250, 230)
    d.ellipse((C - 60, 500, C + 60, 620), fill=WHITE)
    return img


# 3 Stopwatch: the stem becomes the stopwatch crown.
def stopwatch():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((C - 60, 70, C + 60, 190), radius=24, fill=(200, 200, 205))
    d.rounded_rectangle((C - 30, 170, C + 30, 230), radius=10, fill=(160, 160, 168))
    d.polygon([(700, 300), (765, 235), (805, 275), (740, 340)], fill=(200, 200, 205))
    d = tomato(img, C, 590, 380)
    d.ellipse((C - 230, 590 - 210, C + 230, 590 + 210), fill=WHITE)
    for k in range(12):
        a = math.radians(90 - k * 30)
        r0, r1 = (160, 195) if k % 3 == 0 else (175, 195)
        d.line([(C + r0 * math.cos(a), 590 - r0 * 0.91 * math.sin(a)), (C + r1 * math.cos(a), 590 - r1 * 0.91 * math.sin(a))],
               fill=DARK, width=18 if k % 3 == 0 else 10)
    hand(d, C, 590, 50, 150, 34, RED_D)
    return img


# 4 Slice: a cut tomato whose seeds sit where the hours are.
def slice_():
    img = canvas()
    d = ImageDraw.Draw(img)
    d.ellipse((60, 60, S - 60, S - 60), fill=RED)
    d.ellipse((130, 130, S - 130, S - 130), fill=(250, 90, 70))
    for k in range(8):
        a = math.radians(90 - k * 45)
        x, y = C + 255 * math.cos(a), C - 255 * math.sin(a)
        rot = 90 - k * 45
        pts = []
        for i in range(24):
            t = 2 * math.pi * i / 24
            px, py = 34 * math.cos(t), 54 * math.sin(t) * (1 if math.sin(t) > 0 else 0.7)
            rr = math.radians(-rot + 90)
            pts.append((x + px * math.cos(rr) - py * math.sin(rr), y + px * math.sin(rr) + py * math.cos(rr)))
        d.polygon(pts, fill=CREAM)
    d.ellipse((C - 120, C - 120, C + 120, C + 120), fill=(255, 140, 120))
    hand(d, C, C, 90, 150, 44)
    hand(d, C, C, 20, 110, 44)
    return img


# 5 Play: tomato with a start button.
def play():
    img = canvas()
    d = tomato(img, C, 570, 400)
    tri = [(C - 95, 570 - 150), (C + 165, 570), (C - 95, 570 + 150)]
    d.polygon(catmull(tri, 10), fill=WHITE)
    return img


# 6 Hourglass: two tomato bulbs, sand running from the top one into the bottom one.
def hourglass():
    img = canvas()
    d = ImageDraw.Draw(img)
    frame = (150, 100, 60)
    d.rounded_rectangle((170, 50, 854, 120), radius=35, fill=frame)
    d.rounded_rectangle((170, 904, 854, 974), radius=35, fill=frame)
    for x in (215, 809):
        d.rounded_rectangle((x - 22, 100, x + 22, 924), radius=22, fill=frame)
    glass = (90, 90, 100)
    d.ellipse((265, 120, 759, 520), fill=glass)
    d.ellipse((265, 504, 759, 904), fill=glass)
    d.rectangle((477, 470, 547, 560), fill=glass)
    d.chord((265, 120, 759, 520), 25, 155, fill=RED)            # what's left on top
    d.line([(C, 500), (C, 640)], fill=RED, width=22)             # falling stream
    d.polygon(tomato_shape(C, 735, 170, 0.85), fill=RED)          # tomato forming below
    stem(d, C, 570, 45, 20)
    sepals(d, C, 612, 95)
    return img


# 7 Long shadow: flat tomato on a teal badge with a long diagonal shadow.
def longshadow():
    img = canvas()
    badge(img, (24, 120, 118))
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    base = tomato_shape(C - 20, 540, 300)
    for k in range(0, 520, 8):
        sd.polygon([(x + k, y + k) for x, y in base], fill=(14, 84, 82, 255))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse((24, 24, S - 24, S - 24), fill=255)
    img.paste(sh, (0, 0), Image.composite(sh.split()[3], Image.new("L", (S, S), 0), m))
    tomato(img, C - 20, 540, 300, highlight=False)
    return img


# 8 Kawaii: a happy, focused little tomato.
def kawaii():
    img = canvas()
    d = tomato(img, C, 570, 400)
    for x in (C - 140, C + 140):
        d.arc((x - 60, 520, x + 60, 620), 200, 340, fill=(60, 20, 20), width=26)
    d.arc((C - 55, 600, C + 55, 690), 20, 160, fill=(60, 20, 20), width=24)
    for x in (C - 215, C + 215):
        d.ellipse((x - 55, 640, x + 55, 690), fill=(255, 140, 140))
    return img


DRAFTS = [
    ("clock", "Clock tomato", "The tomato is the clock face: white hands and four hour dots."),
    ("ring", "Ring", "The app's own progress ring on a dark badge, with the leaf in the gap at the top. Matches the main screen."),
    ("stopwatch", "Stopwatch", "The stem becomes the stopwatch crown and button; white dial with ticks."),
    ("slice", "Slice", "A cut tomato whose seeds sit where the hours are, with clock hands in the middle."),
    ("play", "Play", "Tomato with a start button: \"press to start a pomodoro\"."),
    ("hourglass", "Hourglass", "A little tomato left in the top bulb, a full one forming in the bottom."),
    ("longshadow", "Long shadow", "Flat tomato on a teal badge with a long diagonal shadow; pops on black."),
    ("kawaii", "Kawaii", "A happy, focused little tomato with closed eyes and blush."),
]
FN = {"clock": clock, "ring": ring, "stopwatch": stopwatch, "slice": slice_, "play": play,
      "hourglass": hourglass, "longshadow": longshadow, "kawaii": kawaii}

for key, name, _ in DRAFTS:
    img = FN[key]()
    for px in (360, 54):
        img.resize((px, px), Image.LANCZOS).save(f"{OUT}/{key}_{px}.png")
    print("drew", key)

cards = "\n".join(f"""
  <figure>
    <div class="row"><img src="{k}_360.png" width="360" height="360" alt="{name} icon">
      <div class="small"><img src="{k}_54.png" width="54" height="54" alt=""><span>real size</span></div></div>
    <div class="watch"><img src="{k}_54.png" width="54" height="54" alt=""><span>Pomodorino</span></div>
    <figcaption><h2>{i + 1} · {name}</h2><p>{desc}</p></figcaption>
  </figure>""" for i, (k, name, desc) in enumerate(DRAFTS))
with open(f"{OUT}/index.html", "w") as f:
    f.write(f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Pomodorino icon drafts</title>
<style>
  body {{ background:#111; color:#ddd; font-family:system-ui,sans-serif; margin:2rem; }}
  .intro {{ color:#999; max-width:60rem; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(460px,1fr)); gap:2rem; margin-top:1.5rem; }}
  figure {{ margin:0; background:#1b1b1b; border-radius:16px; padding:1.2rem; }}
  .row {{ display:flex; align-items:flex-end; gap:1.5rem; }}
  .small {{ display:flex; flex-direction:column; align-items:center; gap:.4rem; color:#777; font-size:.8rem; }}
  .watch {{ display:flex; align-items:center; gap:14px; background:#000; border-radius:40px; padding:10px 22px; margin-top:1rem;
           width:fit-content; font-size:20px; color:#fff; }}
  h2 {{ margin:.9rem 0 .2rem; font-size:1.15rem; color:#fff; }} p {{ margin:.3rem 0; line-height:1.4; }}
</style></head><body>
<h1>Pomodorino: simple icon drafts</h1>
<p class="intro">Original designs, made to read at a glance. Each shows the large draft, the real size (54×54 px) and
how it looks in the watch's app list.</p>
<div class="grid">{cards}
</div></body></html>""")
print("wrote", f"{OUT}/index.html")
