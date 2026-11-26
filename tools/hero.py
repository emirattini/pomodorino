#!/usr/bin/env python3
"""Connect IQ Store hero image (1440x720): title, tagline, feature pills, and two watch screens.

Usage: hero.py OUT.png [FRONT BACK]   styles: ember drain mono liquid classic (default: ember liquid)
       hero.py OUT.png --tasks         the Todoist banner: today's tasks in front (the simulator screenshot
                                        docs/store/screens/screen_7_tasks.png), Drain behind
The style screens are the design mockups from tools/variants.py (rendered here at 2x for sharpness),
not simulator screenshots. The tomato is the launcher-icon cutout (photo: Luc Viatour, CC BY-SA 3.0).
"""
import math, os, sys
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1]
TASKS = sys.argv[2:3] == ["--tasks"]
FRONT, BACK = (sys.argv[2], sys.argv[3]) if len(sys.argv) > 3 else ("ember", "liquid")
# mockup progress (p) and animation phase (t) that look good for each style
POSE = {"ember": (0.62, 0.25), "drain": (0.40, 0.25), "mono": (0.58, 0.25), "liquid": (0.55, 0.40), "classic": (0.62, 0.25)}
FONTS = f"{ROOT}/tools/fonts"
HW, HH = 1440, 720

# Load the variant drawing functions from variants.py without running its main part.
src = open(f"{ROOT}/tools/variants.py").read()
ns = {"__name__": "variants"}
# variants.py used the Google Fonts download names; point them at the copies in tools/fonts.
ALIAS = {"Outfitwght.ttf": "Outfit-VF.ttf", "JetBrainsMonowght.ttf": "JetBrainsMono-VF.ttf",
         "PlayfairDisplaywght.ttf": "PlayfairDisplay-VF.ttf", "BebasNeue-Regular.ttf": "BebasNeue-Regular.ttf"}
FD = os.path.join(os.environ.get("TMPDIR", "/tmp"), "pomodorino-hero-fonts")
os.makedirs(FD, exist_ok=True)
for a, real in ALIAS.items():
    if not os.path.exists(f"{FD}/{a}"):
        os.symlink(f"{FONTS}/{real}", f"{FD}/{a}")
sys.argv = ["variants.py", FD, "/nonexistent"]
exec(src[: src.index("os.makedirs(OUT")], ns)
W = ns["W"]                                   # 780: the mockups draw at 2x


def screen(name, p, t):
    """One watch screen as RGBA, round, at 780 px."""
    img = Image.new("RGBA", (W, W), (0, 0, 0, 255))
    ns[name](img, ImageDraw.Draw(img), p, t)
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, W - 1, W - 1), fill=255)
    img.putalpha(mask)
    return img


def capture(name):
    """A 390 px simulator screenshot from docs/store/screens/ as a round RGBA face at 780 px."""
    img = Image.open(f"{ROOT}/docs/store/screens/{name}.png").convert("RGBA").resize((W, W), Image.LANCZOS)
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, W - 1, W - 1), fill=255)
    img.putalpha(mask)
    return img


def watch(face, d):
    """Face of diameter d inside a plain dark bezel; returns RGBA of size d*1.16."""
    b = int(d * 0.08)
    size = d + 2 * b
    ss = 2
    big = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    g = ImageDraw.Draw(big)
    # bezel: vertical gradient ring with a thin light rim
    for i in range(size * ss // 2, 0, -1):
        k = i / (size * ss / 2)
        v = int(28 + 30 * (1 - k) ** 0.5) if k > (d / size) else 0
        if k > d / size:
            shade = (v, v, v + 2, 255)
            g.ellipse((size * ss / 2 - i, size * ss / 2 - i, size * ss / 2 + i, size * ss / 2 + i), fill=shade)
    g.ellipse((0, 0, size * ss - 1, size * ss - 1), outline=(90, 90, 95, 255), width=2 * ss)
    big = big.resize((size, size), Image.LANCZOS)
    f = face.resize((d, d), Image.LANCZOS)
    big.alpha_composite(f, (b, b))
    # glass highlight across the upper left
    gl = Image.new("L", (size, size), 0)
    ImageDraw.Draw(gl).ellipse((b, b, b + d, b + d), fill=255)
    sweep = Image.new("L", (size, size), 0)
    ImageDraw.Draw(sweep).ellipse((-size * 0.3, -size * 0.55, size * 0.9, size * 0.45), fill=22)
    sweep = sweep.filter(ImageFilter.GaussianBlur(size * 0.04))
    hl = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    hl.putalpha(ImageChops.multiply(gl, sweep))
    big.alpha_composite(hl)
    return big


def shadowed(canvas, img, xy, blur=28, alpha=170):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sh.putalpha(img.split()[3].point(lambda v: v * alpha // 255))
    pad = blur * 3
    big = Image.new("RGBA", (img.width + 2 * pad, img.height + 2 * pad), (0, 0, 0, 0))
    big.alpha_composite(sh, (pad, pad))
    big = big.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(big, (xy[0] - pad, xy[1] - pad + blur // 2))
    canvas.alpha_composite(img, xy)


def dim(img, k):
    rgb = img.convert("RGB").point(lambda v: int(v * k))
    out = rgb.convert("RGBA")
    out.putalpha(img.split()[3])
    return out


def outfit(size, weight):
    f = ImageFont.truetype(f"{FONTS}/Outfit-VF.ttf", size)
    f.set_variation_by_name(weight)
    return f


# ---- background: near-black with a warm tomato glow behind the watches ----
bg = Image.new("RGB", (HW, HH), (12, 10, 10))
glow = Image.new("L", (HW, HH), 0)
ImageDraw.Draw(glow).ellipse((700, 40, 1400, 700), fill=255)
glow = glow.filter(ImageFilter.GaussianBlur(160))
warm = Image.new("RGB", (HW, HH), (120, 32, 18))
bg = Image.composite(warm, bg, glow.point(lambda v: v * 150 // 255))
canvas = bg.convert("RGBA")

# ---- watches: one behind on the right, one in front ----
if TASKS:
    back = watch(screen("v_drain", *POSE["drain"]), 330)
    front = watch(capture("screen_7_tasks"), 390)
else:
    back = watch(screen("v_" + BACK, *POSE[BACK]), 330)
    front = watch(screen("v_" + FRONT, *POSE[FRONT]), 390)
shadowed(canvas, dim(back, 0.8), (HW - 28 - back.width, HH // 2 - back.height // 2 - 40))
fx = 1012 - front.width // 2
fy = HH // 2 - front.height // 2 + 10
shadowed(canvas, front, (fx, fy), blur=34, alpha=200)

# ---- text block ----
d = ImageDraw.Draw(canvas)
x0 = 90
tom = Image.open(f"{ROOT}/docs/icons/photo/vine_single_cutout.png").convert("RGBA")
tom = tom.resize((150, 150), Image.LANCZOS)
shadowed(canvas, tom, (x0 - 10, 78), blur=14, alpha=140)

title = outfit(104, b"Bold")
d.text((x0, 330), "Pomodorino", font=title, fill=(250, 244, 236), anchor="ls")
tag = outfit(46, b"Regular")
lines = ("Focus on today's", "tasks, on your wrist") if TASKS else ("The pomodoro timer", "for your wrist")
d.text((x0 + 4, 400), lines[0], font=tag, fill=(215, 205, 196), anchor="ls")
d.text((x0 + 4, 454), lines[1], font=tag, fill=(215, 205, 196), anchor="ls")

pill = outfit(34, b"Medium")
px, py = x0, 506
for label in (("Todoist", "Daily goal", "5 styles") if TASKS else ("Daily goal", "Streaks", "5 styles")):
    w = d.textlength(label, font=pill)
    box = (px, py, px + w + 44, py + 62)
    d.rounded_rectangle(box, radius=31, outline=(255, 176, 0), width=3)
    d.text(((box[0] + box[2]) / 2, (box[1] + box[3]) / 2 + 1), label, font=pill, fill=(255, 190, 60), anchor="mm")
    px = box[2] + 16

canvas.convert("RGB").save(OUT, optimize=True)
print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB")
