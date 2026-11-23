#!/usr/bin/env python3
"""Draw 8 launcher-icon sketches, each in the style of a different artist (original drawings,
not copies of specific works). Writes docs/icons/*.png and docs/icons/index.html."""
import math, os, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
C = S // 2
OUT = "docs/icons"
os.makedirs(OUT, exist_ok=True)


def new(bg):
    img = Image.new("RGBA", (S, S), bg)
    return img, ImageDraw.Draw(img)


def blob(cx, cy, r, wob=0.0, k=5, phase=0.0, n=240, squash=0.9, seed=0):
    rnd = random.Random(seed)
    extra = [(rnd.uniform(-1, 1) * wob * 0.5, rnd.randint(7, 13), rnd.uniform(0, 6)) for _ in range(3)]
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        rr = r * (1 + wob * math.sin(k * a + phase) + sum(e[0] * math.sin(e[1] * a + e[2]) for e in extra))
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a) * squash))
    return pts


def tomato_shape(cx, cy, r, squash=0.86, n=240):
    """Smooth tomato: wider than tall, gentle lobes, a dip at the stem."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        rr = r * (1 + 0.025 * math.cos(5 * a) - 0.10 * math.exp(-((math.atan2(math.sin(a + math.pi / 2), math.cos(a + math.pi / 2))) / 0.32) ** 2))
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a) * squash))
    return pts


def star(cx, cy, r_out, r_in, n=5, rot=-90):
    pts = []
    for i in range(2 * n):
        r = r_out if i % 2 == 0 else r_in
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def tomato(d, cx, cy, r, body, leaf, outline=None, ow=0, squash=0.88):
    d.polygon(tomato_shape(cx, cy, r, squash), fill=body, outline=outline, width=ow)
    d.polygon(star(cx, cy - r * squash * 0.86, r * 0.42, r * 0.14, 5), fill=leaf, outline=outline, width=max(1, ow // 2))
    d.rectangle((cx - r * 0.05, cy - r * squash * 1.12, cx + r * 0.05, cy - r * squash * 0.86), fill=leaf, outline=outline, width=max(1, ow // 2))


def hands(d, cx, cy, r, col, w):
    d.line([(cx, cy), (cx, cy - r * 0.62)], fill=col, width=w)
    d.line([(cx, cy), (cx + r * 0.42, cy + r * 0.18)], fill=col, width=w)
    d.ellipse((cx - w, cy - w, cx + w, cy + w), fill=col)


# 1 Mondrian: primary blocks and black grid; the red block is the tomato.
def mondrian():
    img, d = new((246, 243, 234, 255))
    d.rectangle((300, 300, 780, 820), fill=(221, 34, 34))
    d.rectangle((440, 150, 640, 300), fill=(40, 140, 70))
    d.rectangle((0, 820, 300, S), fill=(250, 205, 30))
    d.rectangle((780, 0, S, 300), fill=(20, 60, 160))
    d.rectangle((780, 820, S, S), fill=(20, 20, 20))
    for x in (300, 440, 640, 780):
        d.rectangle((x - 14, 0 if x in (300, 780) else 150, x + 14, S if x in (300, 780) else 300), fill=(15, 15, 15))
    for y in (150, 300, 820):
        d.rectangle((0 if y != 150 else 440, y - 14, S if y != 150 else 640, y + 14), fill=(15, 15, 15))
    d.rectangle((0, 560, 300, 588), fill=(15, 15, 15))
    return img


# 2 Kandinsky: concentric rings on deep blue, with floating geometric accents.
def kandinsky():
    img, d = new((22, 30, 72, 255))
    cols = [(226, 60, 40), (245, 150, 40), (180, 30, 60), (250, 215, 70), (30, 140, 130), (200, 40, 40)]
    for i, r in enumerate((380, 315, 255, 195, 135, 75)):
        d.ellipse((C - r, 580 - r, C + r, 580 + r), fill=cols[i])
    d.ellipse((C - 30, 550, C + 30, 610), fill=(15, 15, 15))
    d.polygon([(C - 20, 205), (C + 150, 120), (C + 60, 250)], fill=(60, 170, 80))
    d.polygon([(C + 10, 210), (C - 160, 110), (C - 70, 245)], fill=(40, 130, 60))
    d.ellipse((780, 110, 880, 210), fill=(150, 80, 190))
    d.line([(90, 300), (420, 140)], fill=(240, 240, 230), width=10)
    d.line([(650, 960), (980, 700)], fill=(15, 15, 15), width=12)
    d.arc((120, 120, 360, 360), 200, 340, fill=(250, 215, 70), width=12)
    return img


# 3 Matisse: paper cut-outs on ultramarine: a wobbly red tomato, leafy green, white fronds.
def matisse():
    img, d = new((30, 62, 170, 255))
    for (x, y, rot, sc) in ((180, 230, 20, 1.0), (850, 800, -30, 0.9), (170, 820, 60, 0.8), (860, 210, -10, 0.7)):
        pts = []
        for i in range(7):
            a = math.radians(rot + i * 360 / 7)
            for j, rr in enumerate((110 * sc, 40 * sc)):
                b = a + j * math.pi / 7
                pts.append((x + rr * math.cos(b), y + rr * math.sin(b)))
        d.polygon(pts, fill=(250, 248, 240))
    d.polygon(blob(C, 580, 330, 0.06, 4, 1.0, squash=0.86, seed=3), fill=(226, 52, 40))
    for i, a in enumerate(range(-150, -20, 26)):
        rad = math.radians(a)
        bx, by = C + 70 * math.cos(rad), 300 + 40 * math.sin(rad)
        tip = (C + 260 * math.cos(rad), 300 + 170 * math.sin(rad))
        d.polygon([(bx - 30, by), tip, (bx + 30, by)], fill=(30, 150, 70))
    d.ellipse((C - 70, 250, C + 70, 340), fill=(30, 150, 70))
    d.polygon(blob(650, 480, 70, 0.12, 2, squash=0.45, seed=9), fill=(250, 248, 240))
    return img


# 4 Warhol: four silkscreen panels, the same tomato in clashing pop colors, misregistered outline.
def warhol():
    img, d = new((0, 0, 0, 255))
    combos = [((255, 60, 150), (255, 220, 0), (30, 200, 90)),
              ((255, 215, 0), (40, 90, 230), (255, 90, 30)),
              ((0, 200, 220), (240, 40, 40), (250, 240, 60)),
              ((255, 120, 20), (150, 40, 200), (0, 220, 160))]
    for i, (bg, body, leaf) in enumerate(combos):
        x0, y0 = (i % 2) * C, (i // 2) * C
        d.rectangle((x0, y0, x0 + C, y0 + C), fill=bg)
        cx, cy = x0 + C // 2, y0 + C // 2 + 20
        tomato(d, cx, cy, 175, body, leaf)
        sub = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        sd = ImageDraw.Draw(sub)
        tomato(sd, cx + 14, cy - 10, 175, None, None, outline=(10, 10, 10), ow=12)
        img.alpha_composite(sub)
        d = ImageDraw.Draw(img)
    d.rectangle((C - 6, 0, C + 6, S), fill=(10, 10, 10))
    d.rectangle((0, C - 6, S, C + 6), fill=(10, 10, 10))
    return img


# 5 Lichtenstein: comic panel, Ben-Day dots, black ink outlines, a "POM!" burst.
def lichtenstein():
    img, d = new((210, 235, 250, 255))
    for y in range(0, S, 36):
        for x in range((y // 36) % 2 * 18, S, 36):
            d.ellipse((x - 9, y - 9, x + 9, y + 9), fill=(70, 140, 220))
    d.polygon(star(760, 260, 260, 150, 12, -75), fill=(255, 228, 0), outline=(10, 10, 10), width=12)
    try:
        f = ImageFont.truetype("/usr/share/fonts/noto/NotoSans-CondensedBlack.ttf", 130)
    except OSError:
        f = ImageFont.load_default()
    d.text((770, 250), "POM!", font=f, fill=(225, 30, 40), anchor="mm", stroke_width=8, stroke_fill=(10, 10, 10))
    tomato(d, 450, 600, 300, (228, 35, 40), (40, 170, 70), outline=(10, 10, 10), ow=20)
    dots = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    for y in range(360, 900, 28):
        for x in range(160 + (y // 28) % 2 * 14, 760, 28):
            dd.ellipse((x - 6, y - 6, x + 6, y + 6), fill=(255, 120, 120, 255))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(tomato_shape(450, 600, 290, 0.88), fill=255)
    img.paste(dots, (0, 0), Image.composite(dots.split()[3], Image.new("L", (S, S), 0), mask))
    d = ImageDraw.Draw(img)
    d.polygon(blob(340, 500, 70, 0.1, 3, squash=0.55, seed=4), fill=(255, 255, 255), outline=(10, 10, 10), width=8)
    return img


# 6 Hokusai: ukiyo-e indigo wave with foam claws; the tomato rises as the sun.
def hokusai():
    img, d = new((238, 226, 196, 255))
    rnd = random.Random(1)
    for _ in range(1500):
        x, y = rnd.randrange(S), rnd.randrange(S)
        d.point((x, y), fill=(220, 205, 170))
    tomato(d, 700, 330, 190, (210, 45, 35), (50, 120, 70))
    def wave(base, amp, col, shift):
        pts = [(0, S)]
        for x in range(0, S + 1, 16):
            pts.append((x, base - amp * math.exp(-((x - 300 - shift) / 260) ** 2) - 40 * math.sin(x / 90 + shift / 50)))
        pts.append((S, S))
        d.polygon(pts, fill=col)
        return pts
    wave(820, 120, (120, 160, 200), 400)
    crest = wave(900, 420, (28, 48, 100), 0)
    wave(980, 260, (60, 100, 160), 150)
    for x, y in crest[5:30:2]:
        for k in range(3):
            r = 22 - k * 6
            d.ellipse((x + k * 14 - r, y - k * 10 - r, x + k * 14 + r, y - k * 10 + r), fill=(250, 248, 240))
    d.arc((90, 380, 520, 820), 200, 330, fill=(250, 248, 240), width=18)
    return img


# 7 Klimt: gold mosaic, spirals and eye motifs; the tomato is jewel-like and ornamented.
def klimt():
    img, d = new((196, 154, 48, 255))
    rnd = random.Random(7)
    for _ in range(420):
        x, y = rnd.randrange(S), rnd.randrange(S)
        w, h = rnd.randint(14, 40), rnd.randint(14, 40)
        d.rectangle((x, y, x + w, y + h), fill=rnd.choice([(232, 196, 80), (160, 120, 30), (240, 215, 120), (20, 20, 20)]))
    for x, y in ((150, 160), (880, 170), (130, 880), (900, 880), (520, 120)):
        for k in range(4):
            r = 60 - k * 14
            d.arc((x - r, y - r, x + r, y + r), k * 60, k * 60 + 300, fill=(30, 25, 20), width=7)
    d.polygon(tomato_shape(C, 590, 320, 0.88), fill=(150, 20, 30), outline=(20, 15, 10), width=10)
    for i in range(26):
        a = rnd.uniform(0, 2 * math.pi)
        rr = rnd.uniform(0, 250)
        x, y = C + rr * math.cos(a), 590 + rr * math.sin(a) * 0.85
        for k, col in enumerate(((240, 210, 100), (20, 20, 20), (230, 190, 70), (120, 20, 30))):
            r = 30 - k * 8
            d.ellipse((x - r, y - r, x + r, y + r), fill=col)
    d.polygon(star(C, 320, 150, 52, 5), fill=(60, 120, 60), outline=(20, 15, 10), width=8)
    for x, y in ((C - 70, 300), (C + 60, 310), (C, 260)):
        d.ellipse((x - 14, y - 14, x + 14, y + 14), fill=(240, 210, 100))
    return img


# 8 Dalí: a tomato-clock melting over a ledge in a dreamlike desert.
def dali():
    img, d = new((0, 0, 0, 255))
    for y in range(S):
        t = y / 640
        col = (int(40 + 200 * t), int(80 + 120 * t), int(160 - 40 * t)) if y < 640 else (196, 150, 90)
        d.line([(0, y), (S, y)], fill=col)
    d.ellipse((780, 120, 900, 240), fill=(255, 240, 200))
    d.polygon([(0, 640), (S, 640), (S, 660), (0, 670)], fill=(170, 120, 70))
    d.rectangle((0, 560, 600, S), fill=(120, 80, 50))
    d.rectangle((0, 560, 600, 590), fill=(150, 105, 65))
    # melting tomato: dome on the ledge, drape over the edge with drips
    pts = []
    for i in range(0, 181, 4):
        a = math.radians(180 + i)
        pts.append((380 + 300 * math.cos(a), 560 + 220 * math.sin(a)))
    pts += [(690, 600), (720, 760), (700, 900), (660, 930), (640, 820), (610, 700), (600, 600)]
    for x in range(600, 60, -20):
        drip = 70 * math.exp(-((x - 200) / 40) ** 2) + 30 * math.exp(-((x - 420) / 30) ** 2)
        pts.append((x, 590 + drip))
    pts.append((80, 590))
    d.polygon(pts, fill=(214, 48, 40))
    d.polygon([(330, 340), (380, 300), (440, 345), (400, 360), (380, 330), (350, 365)], fill=(60, 130, 60))
    d.ellipse((260, 400, 500, 560), fill=(245, 232, 200))
    for k in range(12):
        a = math.radians(k * 30)
        d.line([(380 + 100 * math.cos(a), 480 + 66 * math.sin(a)), (380 + 112 * math.cos(a), 480 + 74 * math.sin(a))], fill=(60, 40, 30), width=6)
    d.line([(380, 480), (380, 425)], fill=(30, 20, 15), width=9)
    d.line([(380, 480), (450, 500)], fill=(30, 20, 15), width=9)
    d.line([(820, 900), (820, 700)], fill=(60, 40, 30), width=12)
    d.line([(820, 720), (900, 640)], fill=(60, 40, 30), width=10)
    return img


SKETCHES = [
    ("mondrian", "Piet Mondrian", "De Stijl: primary color blocks on a black grid. The red block is the tomato.", mondrian),
    ("kandinsky", "Wassily Kandinsky", "Concentric rings of color on deep blue, with floating geometric accents.", kandinsky),
    ("matisse", "Henri Matisse", "Paper cut-outs: a wobbly red tomato with leafy green on ultramarine.", matisse),
    ("warhol", "Andy Warhol", "Pop-art silkscreen: four panels of the same tomato in clashing colors.", warhol),
    ("lichtenstein", "Roy Lichtenstein", "Comic panel: Ben-Day dots, black ink outlines, a \"POM!\" burst.", lichtenstein),
    ("hokusai", "Katsushika Hokusai", "Ukiyo-e: an indigo wave with foam, the tomato rising like the sun.", hokusai),
    ("klimt", "Gustav Klimt", "Golden mosaic, spirals and eye motifs; an ornamented, jewel-like tomato.", klimt),
    ("dali", "Salvador Dalí", "Surrealist: a tomato-clock melting over a ledge in a dreamlike desert.", dali),
]

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse((0, 0, S - 1, S - 1), fill=255)
for key, *_rest, fn in SKETCHES:
    art = fn()
    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.paste(art, (0, 0), mask)
    icon.resize((256, 256), Image.LANCZOS).save(f"{OUT}/{key}_256.png")
    icon.resize((54, 54), Image.LANCZOS).save(f"{OUT}/{key}_54.png")
    print("drew", key)

cards = "\n".join(f"""
  <figure>
    <div class="row"><img src="{k}_256.png" width="256" height="256" alt="{name} style icon">
      <div class="small"><img src="{k}_54.png" width="54" height="54" alt=""><span>real size</span></div></div>
    <figcaption><h2>{i + 1} · {name}</h2><p>{desc}</p></figcaption>
  </figure>""" for i, (k, name, desc, _) in enumerate(SKETCHES))
with open(f"{OUT}/index.html", "w") as f:
    f.write(f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Pomodorino icon sketches</title>
<style>
  body {{ background:#111; color:#ddd; font-family:system-ui,sans-serif; margin:2rem; }}
  .intro {{ color:#999; max-width:60rem; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(380px,1fr)); gap:2rem; margin-top:2rem; }}
  figure {{ margin:0; background:#1b1b1b; border-radius:16px; padding:1.2rem; }}
  .row {{ display:flex; align-items:flex-end; gap:1.5rem; }}
  .small {{ display:flex; flex-direction:column; align-items:center; gap:.4rem; color:#777; font-size:.8rem; }}
  h2 {{ margin:.9rem 0 .2rem; font-size:1.15rem; color:#fff; }} p {{ margin:.3rem 0; line-height:1.4; }}
</style></head><body>
<h1>Pomodorino: icon sketches</h1>
<p class="intro">Eight launcher icons, each drawn in the spirit of a different artist (original drawings, not copies of
specific works). The small one is the real size on the Forerunner 165 (54×54 px) on black, which is what matters most.</p>
<div class="grid">{cards}
</div></body></html>""")
print("wrote", f"{OUT}/index.html")
