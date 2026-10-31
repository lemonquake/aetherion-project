"""Builds Malasugue Mall's "after the outbreak" decal atlas: blood drag trails, bloody footprints and handprints, wall
spatter, survivors' spray-painted warnings and blood writing, taped notices, hazard tape, the department store's
hanging signs, restroom signs, and floor and ceiling damage (scattered papers, broken glass, plaster dust, scorch
marks, water stains, ceiling holes, cracked glass, bullet holes).

    python -I tools/make_mall_apoc.py        (then bash tools/import.sh)

Output: game/assets/mall/apoc.png (2048 x 4096, RGBA) and game/assets/mall/apoc.json ({size: [w, h], cells: [{name,
kind, rect: [x, y, w, h] in pixels, aspect}]}). Drawn here (PIL), the project's Barlow fonts for printed signs and
PIL's bundled font for paint; no third-party art.
"""
import json, math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_vandal_atlas as V   # spray_text, stencil, noise_mask, blotch, handprints (seeded on import)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'assets', 'mall')
FONTS = os.path.join(ROOT, 'game', 'assets', 'fonts')
W, H = 2048, 4096
R = random.Random(20261030)
BLOOD = (86, 6, 8)
BLOOD_DRY = (52, 8, 6)


def bfont(sz, cond=True):
    return ImageFont.truetype(os.path.join(FONTS, 'BarlowCondensed-SemiBold.ttf' if cond else 'Barlow-SemiBold.ttf'), sz)


def rgba(w, h):
    return Image.new('RGBA', (w, h), (0, 0, 0, 0))


def colour_layer(w, h, col, alpha):
    img = Image.new('RGBA', (w, h), col + (0,))
    img.putalpha(alpha)
    return img


def edge_fade(w, h, k=0.12):
    """A mask that is 255 inside and falls to 0 over k of the size at every edge (no hard cell outline)."""
    g = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(g)
    mx, my = int(w * k), int(h * k)
    d.rectangle([mx, my, w - mx, h - my], fill=255)
    return g.filter(ImageFilter.GaussianBlur(max(mx, my) * 0.6))


# ------------------------------------------------------------------ printed signs

def dept_sign(text, bg=(21, 35, 63), fg=(255, 255, 255), rule=(205, 168, 92)):
    w, h = 508, 128
    img = Image.new('RGBA', (w, h), bg + (255,))
    d = ImageDraw.Draw(img)
    sz = 74
    f = bfont(sz)
    while d.textbbox((0, 0), text, font=f)[2] > w * 0.86 and sz > 20:
        sz -= 2
        f = bfont(sz)
    bb = d.textbbox((0, 0), text, font=f)
    d.text(((w - (bb[2] - bb[0])) / 2 - bb[0], (h - (bb[3] - bb[1])) / 2 - bb[1] - 6), text, fill=fg + (255,), font=f)
    d.rectangle([w * 0.3, h - 18, w * 0.7, h - 14], fill=rule + (255,))
    d.rectangle([0, 0, w - 1, h - 1], outline=(10, 16, 30, 255), width=3)
    return img


def figure(d, cx, top, s, col, dress=False):
    """A pictogram person (restroom signs): head, body, legs."""
    d.ellipse([cx - s * 0.16, top, cx + s * 0.16, top + s * 0.32], fill=col)
    if dress:
        d.polygon([(cx - s * 0.16, top + s * 0.38), (cx + s * 0.16, top + s * 0.38), (cx + s * 0.32, top + s * 0.86), (cx - s * 0.32, top + s * 0.86)], fill=col)
    else:
        d.rectangle([cx - s * 0.2, top + s * 0.38, cx + s * 0.2, top + s * 0.8], fill=col)
    d.rectangle([cx - s * 0.16, top + s * 0.8 if not dress else top + s * 0.86, cx - s * 0.04, top + s * 1.3], fill=col)
    d.rectangle([cx + s * 0.04, top + s * 0.8 if not dress else top + s * 0.86, cx + s * 0.16, top + s * 1.3], fill=col)


def wc_sign(text, icons, w=508, h=128):
    img = Image.new('RGBA', (w, h), (32, 36, 44, 255))
    d = ImageDraw.Draw(img)
    x = 18
    for ic in icons:
        if ic == 'wheel':
            d.ellipse([x + 14, 66, x + 64, 116], outline=(255, 255, 255, 255), width=7)
            d.ellipse([x + 22, 12, x + 42, 32], fill=(255, 255, 255, 255))
            d.line([(x + 32, 34), (x + 34, 74), (x + 66, 76), (x + 74, 104)], fill=(255, 255, 255, 255), width=8)
        else:
            figure(d, x + 34, 14, 76, (255, 255, 255, 255), ic == 'f')
        x += 70
    f = bfont(64)
    bb = d.textbbox((0, 0), text, font=f)
    tx = x + (w - x - (bb[2] - bb[0])) / 2 - bb[0]
    d.text((tx, (h - (bb[3] - bb[1])) / 2 - bb[1] - 4), text, fill=(255, 255, 255, 255), font=f)
    return img


def out_of_order(w=256, h=320):
    """A sheet of paper taped on: OUT OF ORDER, hand-written underneath."""
    img = Image.new('RGBA', (w, h), (238, 234, 222, 255))
    d = ImageDraw.Draw(img)
    f = bfont(56)
    for i, ln in enumerate(['OUT OF', 'ORDER']):
        bb = d.textbbox((0, 0), ln, font=f)
        d.text(((w - bb[2]) / 2, 30 + i * 62), ln, fill=(170, 20, 20, 255), font=f)
    f2 = V.font(26)
    d.text((24, 200), 'sira po. pasensya', fill=(30, 30, 90, 255), font=f2)
    d.text((24, 236), '- admin', fill=(30, 30, 90, 255), font=f2)
    for cx, cy in [(10, 6), (w - 50, 6)]:
        d.rectangle([cx, cy, cx + 40, cy + 18], fill=(230, 220, 160, 170))
    return _crumple(img)


def notice(title, lines, band=(170, 20, 20), w=256, h=352):
    img = Image.new('RGBA', (w, h), (236, 233, 224, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, 58], fill=band + (255,))
    f = bfont(40 if len(title) < 14 else 32)
    bb = d.textbbox((0, 0), title, font=f)
    d.text(((w - bb[2]) / 2, (58 - (bb[3] - bb[1])) / 2 - bb[1]), title, fill=(255, 255, 255, 255), font=f)
    f2 = bfont(22, cond=False)
    y = 74
    for ln in lines:
        d.text((16, y), ln, fill=(30, 28, 26, 255), font=f2)
        y += 30
    # fine print as grey bars
    while y < h - 40:
        d.rectangle([16, y + 6, 16 + R.randint(120, w - 32), y + 12], fill=(120, 118, 112, 255))
        y += 18
    for cx, cy in [(6, 4), (w - 46, 4), (6, h - 22), (w - 46, h - 22)]:
        d.rectangle([cx, cy, cx + 40, cy + 18], fill=(225, 215, 150, 160))
    return _crumple(img)


def _crumple(img):
    w, h = img.size
    shade = V.noise_mask(w, h, 0.5, 9).point(lambda v: 255 - v // 5)
    r, g, b, a = img.split()
    r = ImageChops.multiply(r, shade)
    g = ImageChops.multiply(g, shade)
    b = ImageChops.multiply(b, shade)
    return Image.merge('RGBA', (r, g, b, a))


def tape(text, col=(240, 200, 20), w=768, h=64):
    img = Image.new('RGBA', (w, h), col + (255,))
    d = ImageDraw.Draw(img)
    for x in range(-h, w + h, 72):
        d.polygon([(x, 0), (x + 30, 0), (x + 30 - h, h), (x - h, h)], fill=(20, 20, 20, 255))
    f = bfont(44)
    x = 30
    while x < w:
        bb = d.textbbox((0, 0), text, font=f)
        d.rectangle([x - 8, 8, x + bb[2] + 8, h - 8], fill=col + (255,))
        d.text((x, (h - (bb[3] - bb[1])) / 2 - bb[1]), text, fill=(20, 20, 20, 255), font=f)
        x += bb[2] + 120
    a = Image.new('L', (w, h), 235)
    return Image.merge('RGBA', img.split()[:3] + (a,))


# ------------------------------------------------------------------ blood

def blood_colour(mask, wet=0.6):
    """Blood from a coverage mask: dark at the heavy middle, brighter and thinner at the edges, a little uneven."""
    w, h = mask.size
    inner = mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(3))
    base = Image.new('RGBA', (w, h), BLOOD + (0,))
    dark = Image.new('RGBA', (w, h), BLOOD_DRY + (0,))
    base.putalpha(mask)
    dark.putalpha(inner.point(lambda v: int(v * wet)))
    return Image.alpha_composite(base, dark)


def drag_trail(w=1024, h=256, heavy=1.0):
    """A body dragged left to right: a broad smear that thins out, combed into lines, with drips beside it."""
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    cy = h * 0.5
    for x in range(w):
        t = x / w
        cy += R.uniform(-0.6, 0.6)
        cy = min(max(cy, h * 0.35), h * 0.65)
        half = h * (0.32 * heavy * (1 - t) ** 0.8 + 0.07) * (0.85 + 0.15 * math.sin(x * 0.05 + R.random()))
        a = int(235 * (1 - 0.55 * t))
        d.line([(x, cy - half), (x, cy + half)], fill=a)
    # combed: streaks along the drag
    comb = Image.effect_noise((w // 16, h), 120).resize((w, h), Image.BILINEAR).point(lambda v: 90 + v * 165 // 255)
    m = ImageChops.multiply(m, comb)
    m = m.filter(ImageFilter.GaussianBlur(1.2))
    # ragged ends and handprint smudges along the edge
    for _ in range(6):
        x = R.randint(0, int(w * 0.7))
        y = int(cy + R.choice([-1, 1]) * h * R.uniform(0.18, 0.3))
        d2 = ImageDraw.Draw(m)
        d2.ellipse([x - 14, y - 10, x + 14, y + 10], fill=170)
    for _ in range(40):
        x = R.randint(0, w - 1)
        y = int(h * 0.5 + R.uniform(-0.45, 0.45) * h)
        r = R.uniform(2, 6)
        ImageDraw.Draw(m).ellipse([x - r, y - r, x + r, y + r], fill=R.randint(150, 230))
    m = ImageChops.multiply(m, edge_fade(w, h, 0.03))
    return blood_colour(m)


def footprints(w=1024, h=256):
    """Bloody shoe prints walking left to right, fading as the blood runs out."""
    img = rgba(w, h)
    n = 9
    for i in range(n):
        x = 50 + i * (w - 100) / n
        y = h * (0.36 if i % 2 == 0 else 0.64)
        a = max(0.15, 1.0 - i / n)
        m = Image.new('L', (w, h), 0)
        d = ImageDraw.Draw(m)
        # sole: forefoot oval and heel, pointing +x
        d.ellipse([x + 10, y - 22, x + 70, y + 22], fill=255)
        d.ellipse([x - 40, y - 17, x, y + 17], fill=255)
        # tread lines
        for k in range(8):
            d.line([(x - 36 + k * 13, y - 24), (x - 36 + k * 13, y + 24)], fill=0, width=3)
        m = ImageChops.multiply(m, V.noise_mask(w, h, 0.55 + 0.4 * a, 1.0))
        m = m.point(lambda v, a=a: int(v * a))
        img = Image.alpha_composite(img, blood_colour(m, 0.3))
    return img


def wall_spatter(w=512, h=256):
    """Arterial spray across a wall: an arc of drops, each with its tail, and runs dripping down from the heavy ones."""
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    for i in range(160):
        t = i / 160
        x = w * (0.06 + 0.88 * t) + R.uniform(-8, 8)
        y = h * (0.42 - 0.22 * math.sin(t * math.pi * 1.1)) + R.uniform(-18, 18) * (1 + t)
        r = R.uniform(1.5, 7.0) * (1.3 - t * 0.7)
        d.ellipse([x - r, y - r, x + r, y + r], fill=230)
        d.line([(x, y), (x + r * 3, y - r * 0.6)], fill=200, width=max(1, int(r * 0.6)))
        if r > 5.5 and R.random() < 0.5:
            d.line([(x, y), (x + R.uniform(-2, 2), y + R.uniform(25, h * 0.55))], fill=210, width=max(2, int(r * 0.5)))
    m = m.filter(ImageFilter.GaussianBlur(0.8))
    return blood_colour(m, 0.25)


def pool_drag(w=384, h=384):
    """A pool where someone lay, and the smear where they were pulled away from it."""
    m = Image.new('L', (w, h), 0)
    pool = V.blotch(int(w * 0.62), int(h * 0.62), (0, 0, 0), density=0.7, blur=16).split()[3].point(lambda v: 255 if v > 70 else int(v * 3.6))
    m.paste(pool, (int(w * 0.06), int(h * 0.2)))
    d = ImageDraw.Draw(m)
    cy = h * 0.52
    for x in range(int(w * 0.4), w):
        t = (x - w * 0.4) / (w * 0.6)
        half = h * (0.12 * (1 - t) + 0.035)
        cy += R.uniform(-0.8, 0.8)
        d.line([(x, cy - half), (x, cy + half)], fill=int(220 * (1 - 0.6 * t)))
    comb = Image.effect_noise((w // 12, h), 120).resize((w, h), Image.BILINEAR).point(lambda v: 110 + v * 145 // 255)
    m = ImageChops.multiply(m, comb).filter(ImageFilter.GaussianBlur(1.0))
    m = ImageChops.multiply(m, edge_fade(w, h, 0.03))
    return blood_colour(m, 0.75)


def hand_smears(w=256, h=256):
    return V.handprints(w, h, BLOOD)


def blood_text(text):
    return V.spray_text(text, 448, 224, (110, 8, 10), drips=True)


# ------------------------------------------------------------------ the floor, the ceiling, glass and walls

def papers(w=384, h=384):
    """Scattered paper: receipts, flyers, pages, a few trodden."""
    img = rgba(w, h)
    for i in range(34):
        kind = R.random()
        if kind < 0.45:
            pw, ph, col = R.randint(26, 40), R.randint(60, 110), (238, 236, 228)
        elif kind < 0.8:
            pw, ph, col = R.randint(70, 96), R.randint(96, 128), R.choice([(240, 238, 230), (250, 226, 120), (240, 160, 170), (170, 210, 240)])
        else:
            pw, ph, col = R.randint(50, 70), R.randint(40, 60), (200, 170, 120)   # cardboard scrap
        p = Image.new('RGBA', (pw, ph), col + (255,))
        d = ImageDraw.Draw(p)
        for k in range(6, ph - 6, 8):
            if R.random() < 0.8 and kind < 0.8:
                d.line([(4, k), (pw - R.randint(4, 20), k)], fill=(120, 118, 112, 255), width=2)
        if R.random() < 0.35:   # a dirty shoe print across it
            d.ellipse([pw * 0.1, ph * 0.3, pw * 0.9, ph * 0.8], fill=(90, 80, 70, 120))
        p = p.rotate(R.uniform(0, 360), resample=Image.BICUBIC, expand=True)
        x, y = R.randint(0, w - p.width), R.randint(0, h - p.height)
        sh = Image.new('RGBA', p.size, (0, 0, 0, 0))
        sh.putalpha(p.split()[3].point(lambda v: v // 4))
        img.alpha_composite(sh, (min(x + 2, w - p.width), min(y + 2, h - p.height)))
        img.alpha_composite(p, (x, y))
    return img


def glass_shards(w=384, h=384):
    img = rgba(w, h)
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    for i in range(260):
        r = abs(R.gauss(0, w * 0.22))
        a = R.uniform(0, math.tau)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r * 0.8
        if not (6 < x < w - 6 and 6 < y < h - 6):
            continue
        s = R.uniform(2, 14) * (1.2 - min(r / (w * 0.5), 1.0))
        pts = [(x + math.cos(t) * s * R.uniform(0.4, 1.0), y + math.sin(t) * s * R.uniform(0.4, 1.0)) for t in sorted(R.uniform(0, math.tau) for _ in range(3 + R.randint(0, 1)))]
        d.polygon(pts, fill=(200, 225, 230, 110), outline=(245, 252, 255, 230))
    return img


def plaster_dust(w=384, h=384):
    """Under a fallen ceiling: pale dust spread out, chunks of board and tile in it."""
    img = V.blotch(w, h, (205, 202, 192), density=0.6, blur=14)
    a = img.split()[3].point(lambda v: min(255, int(v * 1.3)))
    img.putalpha(a)
    d = ImageDraw.Draw(img)
    for i in range(70):
        x, y = R.randint(int(w * 0.15), int(w * 0.85)), R.randint(int(h * 0.15), int(h * 0.85))
        s = R.uniform(3, 16)
        pts = [(x + math.cos(t) * s * R.uniform(0.5, 1.1), y + math.sin(t) * s * R.uniform(0.5, 1.1)) for t in [0, 1.4, 2.6, 3.9, 5.1]]
        g = R.randint(150, 235)
        d.polygon(pts, fill=(g, g, g - 6, 255), outline=(g - 60, g - 60, g - 64, 255))
    return img


def scorch(w=384, h=384):
    m = V.blotch(w, h, (0, 0, 0), density=0.75, blur=22).split()[3]
    m = m.point(lambda v: min(255, int(v * 1.5)))
    core = m.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.GaussianBlur(8))
    img = colour_layer(w, h, (58, 40, 26), m)
    return Image.alpha_composite(img, colour_layer(w, h, (12, 10, 9), core))


def grime(w=384, h=384):
    """Dirt tracked over a floor: a mottled stain and scuffed shoe marks."""
    img = V.blotch(w, h, (58, 50, 40), density=0.55, blur=12)
    a = img.split()[3].point(lambda v: int(v * 0.8))
    img.putalpha(a)
    d = ImageDraw.Draw(img)
    for i in range(16):
        x, y = R.randint(60, w - 60), R.randint(60, h - 60)
        ang = R.uniform(0, math.pi)
        dx, dy = math.cos(ang) * 30, math.sin(ang) * 30
        d.line([(x - dx, y - dy), (x + dx, y + dy)], fill=(30, 26, 22, 110), width=R.randint(6, 12))
    return img


def water_stain(w=256, h=256):
    m = V.blotch(w, h, (0, 0, 0), density=0.6, blur=10).split()[3]
    ring = ImageChops.subtract(m.point(lambda v: 255 if v > 60 else 0).filter(ImageFilter.GaussianBlur(3)),
                               m.point(lambda v: 255 if v > 120 else 0).filter(ImageFilter.GaussianBlur(5)))
    img = colour_layer(w, h, (120, 92, 52), m.point(lambda v: v // 3))
    return Image.alpha_composite(img, colour_layer(w, h, (92, 66, 34), ring))


def ceiling_hole(w=384, h=384):
    """Ceiling tiles torn out: the black void above, broken board edges round it, insulation hanging."""
    img = rgba(w, h)
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    pts = []
    n = 26
    for i in range(n):
        a = math.tau * i / n
        r = w * (0.3 + 0.1 * math.sin(a * 3 + 1.0) + R.uniform(-0.04, 0.05))
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r * 0.85))
    rim = [(cx + (x - cx) * 1.12, cy + (y - cy) * 1.12) for x, y in pts]
    d.polygon(rim, fill=(150, 146, 138, 255))
    d.polygon(pts, fill=(6, 6, 7, 255))
    for i in range(18):   # insulation fibres and wires hanging into view
        a = R.uniform(0, math.tau)
        x0, y0 = cx + math.cos(a) * w * 0.26, cy + math.sin(a) * h * 0.22
        col = (200, 170, 90, 255) if R.random() < 0.6 else (25, 25, 25, 255)
        d.line([(x0, y0), (x0 + R.uniform(-30, 30), y0 + R.uniform(-30, 30))], fill=col, width=R.randint(2, 6))
    a = img.split()[3].filter(ImageFilter.GaussianBlur(1.2))
    img.putalpha(a)
    return img


def cracked_glass(w=384, h=384, hole=True):
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    cx, cy = w * R.uniform(0.4, 0.6), h * R.uniform(0.4, 0.6)
    rays = []
    for i in range(16):
        a = math.tau * i / 16 + R.uniform(-0.15, 0.15)
        x, y = cx, cy
        pts = [(x, y)]
        ln = R.uniform(0.3, 0.55) * w
        steps = 8
        for k in range(steps):
            a += R.uniform(-0.2, 0.2)
            x += math.cos(a) * ln / steps
            y += math.sin(a) * ln / steps
            pts.append((x, y))
        rays.append(pts)
        d.line(pts, fill=230, width=2)
    for ring in [0.12, 0.22, 0.34]:
        for i in range(len(rays)):
            p = rays[i][int(ring * 8 / 0.45) if int(ring * 8 / 0.45) < 9 else 8]
            q = rays[(i + 1) % len(rays)][int(ring * 8 / 0.45) if int(ring * 8 / 0.45) < 9 else 8]
            if R.random() < 0.75:
                d.line([p, q], fill=200, width=1)
    if hole:
        d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=255)
    img = colour_layer(w, h, (235, 245, 248), m)
    if hole:
        ImageDraw.Draw(img).ellipse([cx - 5, cy - 5, cx + 5, cy + 5], fill=(30, 30, 30, 255))
    return img


def bullet_holes(w=256, h=256):
    img = rgba(w, h)
    d = ImageDraw.Draw(img)
    for i in range(9):
        x, y = R.randint(30, w - 30), R.randint(30, h - 30)
        r = R.uniform(9, 14)
        d.ellipse([x - r * 1.6, y - r * 1.6, x + r * 1.6, y + r * 1.6], fill=(200, 196, 188, 200))
        for k in range(6):
            a = R.uniform(0, math.tau)
            d.line([(x, y), (x + math.cos(a) * r * 2.6, y + math.sin(a) * r * 2.6)], fill=(70, 66, 62, 200), width=1)
        d.ellipse([x - r * 0.6, y - r * 0.6, x + r * 0.6, y + r * 0.6], fill=(18, 16, 15, 255))
    return img


def soot_plume(w=384, h=384):
    """Smoke-blackened wall above a burnt opening: heavy at the bottom middle, billowing up and out."""
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    for i in range(60):
        t = R.random()
        y = h * (1 - t * 0.95)
        x = w / 2 + R.gauss(0, w * (0.08 + 0.2 * t))
        r = w * (0.08 + 0.12 * t)
        d.ellipse([x - r, y - r, x + r, y + r], fill=int(220 * (1 - t * 0.6)))
    m = m.filter(ImageFilter.GaussianBlur(18))
    m = ImageChops.multiply(m, V.noise_mask(w, h, 0.6, 6).point(lambda v: 140 + v * 115 // 255))
    m = ImageChops.multiply(m, edge_fade(w, h, 0.04))
    return colour_layer(w, h, (14, 12, 11), m)


# ------------------------------------------------------------------ the atlas

def build_cells():
    cells = []
    add = lambda name, kind, img: cells.append((name, kind, img))
    for nm in ['Cosmetics', 'Fragrance', 'Bags & Accessories', 'Shoes', 'Ladies', 'Men', 'Kids', 'Home & Living', 'Bedding & Bath',
               'Appliances', 'Toys', 'Customer Service', 'Fitting Rooms', 'Clearance Sale']:
        add('dept_' + nm.lower().replace(' & ', '_').replace(' ', '_'), 'dept', dept_sign(nm))
    add('dept_staff', 'dept', dept_sign('Staff Only', bg=(150, 20, 24), rule=(255, 255, 255)))
    add('dept_escalator', 'dept', dept_sign('Escalator not running', bg=(230, 180, 20), fg=(20, 20, 20), rule=(20, 20, 20)))
    add('wc_restrooms', 'wc', wc_sign('Restrooms', ['m', 'f', 'wheel']))
    add('wc_ladies', 'wc', wc_sign('Ladies', ['f'], 320, 128))
    add('wc_gents', 'wc', wc_sign('Gents', ['m'], 320, 128))
    add('wc_out_of_order', 'notice', out_of_order())
    for i, (txt, col) in enumerate([("THEY'RE\nINSIDE", (180, 20, 20)), ('SAFE ZONE\n-> FOOD HALL', (240, 240, 235)), ('EVAC\nCANCELLED', (20, 20, 22)),
                                    ('STAY QUIET\nTHEY HEAR YOU', (240, 240, 235)), ("DON'T GO\nDOWNSTAIRS", (180, 20, 20)), ('INFECTED\nINSIDE', (20, 20, 22)),
                                    ('4 ALIVE\nCINEMA L5', (240, 240, 235)), ('NASAAN KA\nRAMON?', (30, 60, 160)), ('BITTEN\n= OUT', (180, 20, 20)),
                                    ('NO WAY\nOUT', (20, 20, 22)), ('LOOTED', (240, 200, 30)), ('WALA NANG\nPAGKAIN', (240, 240, 235)),
                                    ('HUWAG\nBUKSAN', (180, 20, 20)), ('ROOF\n= NO', (20, 20, 22))]):
        add('spray_%02d' % i, 'spray', V.spray_text(txt, 448, 224, col, drips=True))
    for i, txt in enumerate(['HELP US', 'DEAD INSIDE\nDO NOT OPEN', "MAMA I'M OK\nL3 CR", 'SORRY']):
        add('bloodtext_%d' % i, 'bloodtext', blood_text(txt))
    add('notice_evac', 'notice', notice('EVACUATION', ['All shoppers proceed to', 'the North Entrance.', 'Buses at 0600.', 'Bring ID. No pets.'], (180, 24, 24)))
    add('notice_closed', 'notice', notice('MALL CLOSED', ['Until further notice.', 'By order of the City', 'Health Office.', 'Salamat po.'], (21, 35, 63)))
    add('notice_relief', 'notice', notice('RELIEF GOODS', ['Food Hall, Level 5', '6 AM - 8 AM daily', 'One pack per family', 'Line up properly'], (30, 120, 60)))
    add('notice_missing', 'notice', notice('NAWAWALA', ['Lola Ising, 74', 'Last seen: Level 3', 'restrooms, Thursday', 'Call 0917 ...'], (200, 120, 20)))
    add('quarantine', 'stencil', V.stencil('QUARANTINE\nKEEP OUT', 512, 256, (230, 190, 20), border=True))
    add('tape_caution', 'tape', tape('CAUTION'))
    add('tape_police', 'tape', tape('POLICE LINE DO NOT CROSS'))
    add('blood_drag_0', 'blood', drag_trail())
    add('blood_drag_1', 'blood', drag_trail(heavy=0.7))
    add('blood_steps', 'blood', footprints())
    add('blood_pool_drag', 'blood', pool_drag())
    add('blood_spatter', 'blood', wall_spatter())
    add('blood_hands_0', 'blood', hand_smears())
    add('blood_hands_1', 'blood', hand_smears())
    add('floor_papers_0', 'floor', papers())
    add('floor_papers_1', 'floor', papers())
    add('floor_glass', 'floor', glass_shards())
    add('floor_dust', 'floor', plaster_dust())
    add('floor_scorch', 'floor', scorch())
    add('floor_grime_0', 'floor', grime())
    add('floor_grime_1', 'floor', grime())
    add('ceiling_hole', 'ceiling', ceiling_hole())
    add('ceiling_stain', 'ceiling', water_stain())
    add('glass_cracked_0', 'glass', cracked_glass())
    add('glass_cracked_1', 'glass', cracked_glass(hole=False))
    add('wall_bullets', 'wall', bullet_holes())
    add('wall_soot', 'wall', soot_plume())
    return cells


def pack(cells):
    """Shelf packing, tallest first, 2 px gutters."""
    order = sorted(range(len(cells)), key=lambda i: (-cells[i][2].height, -cells[i][2].width))
    atlas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    out = [None] * len(cells)
    x = y = 0
    row_h = 0
    for i in order:
        img = cells[i][2]
        if x + img.width > W:
            x = 0
            y += row_h + 2
            row_h = 0
        if y + img.height > H:
            raise SystemExit('apoc atlas full at ' + cells[i][0])
        atlas.alpha_composite(img, (x, y))
        out[i] = {'name': cells[i][0], 'kind': cells[i][1], 'rect': [x, y, img.width, img.height], 'aspect': round(img.width / img.height, 4)}
        x += img.width + 2
        row_h = max(row_h, img.height)
    print('apoc atlas: %d cells, %d px used of %d' % (len(cells), y + row_h, H))
    return atlas, out


def main():
    cells = build_cells()
    atlas, meta = pack(cells)
    os.makedirs(OUT, exist_ok=True)
    atlas.save(os.path.join(OUT, 'apoc.png'))
    with open(os.path.join(OUT, 'apoc.json'), 'w', encoding='utf-8') as f:
        json.dump({'size': [W, H], 'cells': meta}, f, indent=1)
    prev = Image.new('RGBA', atlas.size, (150, 150, 150, 255))
    prev.alpha_composite(atlas)
    prev.convert('RGB').resize((W // 4, H // 4)).save(os.path.join(ROOT, 'work', 'r16', 'apoc_preview.png'))


if __name__ == '__main__':
    main()
