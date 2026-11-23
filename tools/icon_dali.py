#!/usr/bin/env python3
"""Three livelier takes on the Dalí-style icon (original drawings). Writes docs/icons/dali/."""
import math, os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = "docs/icons/dali"
os.makedirs(OUT, exist_ok=True)

RED, RED_D, RED_L = (214, 44, 36), (150, 22, 22), (245, 110, 90)
LEAF, LEAF_D = (62, 140, 66), (36, 90, 44)
CREAM, INK = (246, 234, 204), (40, 26, 18)


def catmull(pts, per=16, closed=True):
    """Smooth closed curve through control points (Catmull-Rom)."""
    out = []
    n = len(pts)
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                    + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    return out


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sky(img, swirl=False):
    d = ImageDraw.Draw(img)
    stops = [(0, (18, 40, 110)), (300, (70, 140, 200)), (520, (190, 210, 200)), (640, (245, 200, 120))]
    for y in range(640):
        for (y0, c0), (y1, c1) in zip(stops, stops[1:]):
            if y0 <= y <= y1:
                d.line([(0, y), (S, y)], fill=lerp(c0, c1, (y - y0) / (y1 - y0)))
    sun = (820, 190)
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((sun[0] - 170, sun[1] - 170, sun[0] + 170, sun[1] + 170), fill=(255, 230, 170, 120))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(50)))
    d = ImageDraw.Draw(img)
    if swirl:
        sw = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        swd = ImageDraw.Draw(sw)
        for k in range(10):
            r = 100 + k * 58
            a0 = 95 + k * 17
            c = lerp((255, 240, 200), (150, 190, 230), k / 10)
            swd.arc((sun[0] - r, sun[1] - r * 0.75, sun[0] + r, sun[1] + r * 0.75), a0, a0 + 150,
                    fill=c + (150 - k * 9,), width=12 - k)
        img.alpha_composite(sw.filter(ImageFilter.GaussianBlur(2)))
        d = ImageDraw.Draw(img)
    else:
        clouds = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        cd = ImageDraw.Draw(clouds)
        for x, y, w in ((120, 210, 380), (420, 120, 300), (300, 330, 460)):
            cd.ellipse((x, y, x + w, y + 26), fill=(255, 245, 225, 170))
        img.alpha_composite(clouds.filter(ImageFilter.GaussianBlur(9)))
    d.ellipse((sun[0] - 62, sun[1] - 62, sun[0] + 62, sun[1] + 62), fill=(255, 244, 214))


def ground(img):
    d = ImageDraw.Draw(img)
    for y in range(640, S):
        d.line([(0, y), (S, y)], fill=lerp((214, 170, 104), (150, 100, 58), (y - 640) / (S - 640)))
    # far cliffs on the horizon
    d.polygon([(560, 640), (640, 600), (700, 612), (770, 570), (860, 596), (940, 560), (S, 590), (S, 640)], fill=(170, 120, 80))
    d.polygon([(600, 640), (700, 625), (800, 632), (900, 615), (S, 625), (S, 640)], fill=(140, 96, 64))
    # long shadow of the ledge and the drip, raking to the right
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(640, 660), (S, 720), (S, 860), (700, 900)], fill=(60, 30, 15, 110))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(6)))


def ledge(d):
    d.polygon([(0, 600), (650, 572), (668, 590), (668, S), (0, S)], fill=(118, 76, 46))
    d.polygon([(0, 600), (650, 572), (668, 590), (0, 622)], fill=(156, 108, 66))
    d.line([(668, 590), (668, S)], fill=(84, 52, 30), width=6)


def melting_tomato(img, d, long_drip=True):
    pts = [(70, 604), (88, 470), (200, 352), (360, 318), (520, 350), (640, 445), (700, 560),
           (722, 640), (734, 760), (738 if long_drip else 730, 870 if long_drip else 800),
           (722, 912 if long_drip else 842), (700, 916 if long_drip else 846), (686, 880 if long_drip else 812),
           (690, 800 if long_drip else 760), (676, 712), (662, 668), (648, 712), (646, 790), (630, 816), (614, 788),
           (618, 690), (600, 628), (540, 622), (500, 648), (482, 712), (462, 734), (444, 712), (432, 650), (392, 626),
           (300, 628), (272, 668), (256, 690), (240, 668), (230, 632), (160, 626), (122, 656), (106, 668), (94, 646)]
    shape = catmull(pts)
    d.polygon(shape, fill=RED)
    # shading: darker underside on the front, highlight on the dome
    shade = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    sd.polygon(shape, fill=(0, 0, 0, 0))
    sd.ellipse((80, 520, 720, 760), fill=(110, 10, 10, 120))
    sd.ellipse((180, 360, 420, 470), fill=(255, 170, 150, 110))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(shape, fill=255)
    blurred = shade.filter(ImageFilter.GaussianBlur(30))
    img.paste(blurred, (0, 0), Image.composite(blurred.split()[3], Image.new("L", (S, S), 0), mask))
    d = ImageDraw.Draw(img)
    # falling drop
    if long_drip:
        drop = catmull([(712, 942), (728, 978), (712, 996), (696, 978)], 12)
        d.polygon(drop, fill=RED)
        d.ellipse((704, 966, 712, 974), fill=RED_L)
    return d


def warped_clock(d, cx=410, cy=470, rx=128, ry=86):
    def warp(x, y):
        u = max(0.0, (x - cx) / rx)
        return x + 18 * u * u, y + 70 * u ** 2.2 + 10 * math.sin((x - cx) / 40)
    ring = [warp(cx + rx * math.cos(a), cy + ry * math.sin(a)) for a in [2 * math.pi * i / 120 for i in range(120)]]
    d.polygon(ring, fill=CREAM, outline=(200, 170, 120), width=6)
    for k in range(12):
        a = 2 * math.pi * k / 12
        p0 = warp(cx + rx * 0.80 * math.cos(a), cy + ry * 0.80 * math.sin(a))
        p1 = warp(cx + rx * 0.92 * math.cos(a), cy + ry * 0.92 * math.sin(a))
        d.line([p0, p1], fill=INK, width=7 if k % 3 == 0 else 4)
    # bent hands
    h1 = [warp(cx + t * 6, cy - t * 60) for t in [i / 10 for i in range(11)]]
    h2 = [warp(cx + t * 100, cy + t * 30 + 25 * t * t) for t in [i / 10 for i in range(11)]]
    d.line(h1, fill=INK, width=10, joint="curve")
    d.line(h2, fill=INK, width=8, joint="curve")
    d.ellipse((cx - 10, cy - 10, cx + 10, cy + 10), fill=INK)


def leaf(d, flying=False):
    if flying:
        # leaf blown off to the upper right, with motion streaks
        cx, cy = 640, 250
        pts = [(cx - 70, cy + 10), (cx - 10, cy - 30), (cx + 60, cy - 60), (cx + 20, cy), (cx + 80, cy + 30), (cx, cy + 20), (cx - 40, cy + 50)]
        d.polygon(catmull(pts, 8), fill=LEAF)
        for k, (x, y) in enumerate(((520, 280), (500, 250), (530, 225))):
            d.line([(x - 120 + k * 20, y + 18), (x, y)], fill=(250, 240, 220), width=6 - k)
        d.line(catmull([(360, 330), (380, 300), (430, 300), (450, 270)], 8, closed=False), fill=LEAF_D, width=12)
    else:
        pts = [(300, 330), (340, 300), (330, 250), (380, 290), (430, 260), (420, 310), (480, 330),
               (520, 380), (440, 352), (400, 360), (350, 352)]
        d.polygon(catmull(pts, 8), fill=LEAF)
        d.line(catmull([(390, 300), (400, 260), (440, 240), (470, 250), (460, 275)], 10, closed=False),
               fill=LEAF_D, width=12, joint="curve")


def elephant(d, x, y, sc=1.0):
    col = (60, 40, 30)
    body = [(x - 60 * sc, y), (x - 50 * sc, y - 40 * sc), (x, y - 52 * sc), (x + 55 * sc, y - 40 * sc), (x + 70 * sc, y - 10 * sc),
            (x + 95 * sc, y + 10 * sc), (x + 92 * sc, y + 40 * sc), (x + 80 * sc, y + 12 * sc), (x + 50 * sc, y + 10 * sc), (x - 50 * sc, y + 12 * sc)]
    d.polygon(catmull(body, 6), fill=col)
    for lx in (-40, -15, 25, 50):
        d.line([(x + lx * sc, y + 8 * sc), (x + (lx + 6) * sc, y + 230 * sc)], fill=col, width=max(2, int(4 * sc)))
    d.ellipse((x - 30 * sc, y - 100 * sc, x + 30 * sc, y - 50 * sc), fill=RED)
    d.polygon([(x - 8 * sc, y - 100 * sc), (x, y - 118 * sc), (x + 8 * sc, y - 100 * sc)], fill=LEAF)


def render(variant):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    sky(img, swirl=(variant == "B"))
    ground(img)
    d = ImageDraw.Draw(img)
    if variant == "C":
        elephant(d, 860, 470, 0.9)
    ledge(d)
    d = melting_tomato(img, d, long_drip=True)
    warped_clock(d)
    leaf(d, flying=(variant == "B"))
    return img


VARIANTS = [("A", "Drip", "Long drips over the ledge, a falling drop, a warped clock with bent hands, wispy clouds, raking shadows."),
            ("B", "Swirl", "Same melt under a swirling sky around the sun; the leaf is blown off with motion streaks."),
            ("C", "Dream", "The melt plus a long-legged elephant carrying a tomato across the distant desert.")]

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse((0, 0, S - 1, S - 1), fill=255)
for v, name, _ in VARIANTS:
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(render(v), (0, 0), mask)
    for px in (400, 54):
        icon.resize((px, px), Image.LANCZOS).save(f"{OUT}/dali_{v}_{px}.png")
    print("drew", v, name)

cards = "\n".join(f"""
  <figure>
    <div class="row"><img src="dali_{v}_400.png" width="400" height="400" alt="Dalí {name} icon">
      <div class="small"><img src="dali_{v}_54.png" width="54" height="54" alt=""><span>real size</span></div></div>
    <figcaption><h2>{v} · {name}</h2><p>{desc}</p></figcaption>
  </figure>""" for v, name, desc in VARIANTS)
with open(f"{OUT}/index.html", "w") as f:
    f.write(f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Pomodorino Dalí icons</title>
<style>
  body {{ background:#111; color:#ddd; font-family:system-ui,sans-serif; margin:2rem; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(500px,1fr)); gap:2rem; margin-top:1.5rem; }}
  figure {{ margin:0; background:#1b1b1b; border-radius:16px; padding:1.2rem; }}
  .row {{ display:flex; align-items:flex-end; gap:1.5rem; }}
  .small {{ display:flex; flex-direction:column; align-items:center; gap:.4rem; color:#777; font-size:.8rem; }}
  h2 {{ margin:.9rem 0 .2rem; font-size:1.15rem; color:#fff; }} p {{ margin:.3rem 0; line-height:1.4; }}
</style></head><body>
<h1>Pomodorino: Dalí, more movement</h1>
<div class="grid">{cards}
</div></body></html>""")
print("wrote", f"{OUT}/index.html")
