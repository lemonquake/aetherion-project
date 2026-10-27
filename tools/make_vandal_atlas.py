"""Builds the wall/ground decal atlas: vandalism, signs, posters and grime, all in one texture so every decal in a
map chunk is one draw call.

    python -I tools/make_vandal_atlas.py        (then bash tools/import.sh)

Output: game/assets/fx/vandal_atlas.png (2048 x 2048, RGBA) and game/assets/fx/vandal_atlas.json
({cells: [{name, kind, rect: [x, y, w, h] in pixels, aspect}]}). Kinds: tag, throw, sign, census, graffiti (the
Sleep project's art, packed as is), stencil, eerie, poster, stain, streak, damp, ground.

Everything is drawn here: random strokes, PIL's bundled default font (Aileron, CC0), no third-party art. Names on
posters are invented.
"""
import json, math, os, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAGS = os.path.join(ROOT, 'game', 'assets', 'models', 'sleep', 'tags')
OUT = os.path.join(ROOT, 'game', 'assets', 'fx')
SIZE = 2048
R = random.Random(20261027)


def font(sz):
    return ImageFont.load_default(size=sz)


def noise_mask(w, h, density=0.5, blur=1.2):
    m = Image.effect_noise((w, h), 80).point(lambda v: 255 if v > 255 * (1 - density) else 0)
    return m.filter(ImageFilter.GaussianBlur(blur))


def spray_text(text, w, h, col, size=None, drips=True, rot=0.0, wobble=True):
    """Spray-painted words (lines split on newline): soft core, overspray, a few drips."""
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    lines = text.split(chr(10))
    sz = size or int(h * 0.42 / max(1, len(lines)) * (1.4 if len(lines) > 1 else 1.0))

    def line_w(ln, f, sz):
        return sum(d.textbbox((0, 0), ch, font=f)[2] - d.textbbox((0, 0), ch, font=f)[0] + max(2, sz // 14) for ch in ln)

    f = font(sz)
    while (max(line_w(ln, f, sz) for ln in lines) > w * 0.86 or sz * 1.2 * len(lines) > h * 0.8) and sz > 10:
        sz = int(sz * 0.92)
        f = font(sz)
    y = (h - sz * 1.2 * len(lines)) / 2
    for ln in lines:
        x = (w - line_w(ln, f, sz)) / 2
        for ch in ln:
            cb = d.textbbox((0, 0), ch, font=f)
            dy = R.randint(-int(sz * 0.07), int(sz * 0.07)) if wobble else 0
            for k in range(3 if wobble else 1):
                d.text((x - cb[0] + R.randint(-1, 1), y - cb[1] + dy + R.randint(-1, 1)), ch, fill=255, font=f, stroke_width=max(1, sz // 18))
            x += cb[2] - cb[0] + max(2, sz // 14)
        y += sz * 1.2
    if drips:
        px = m.load()
        for _ in range(int(w / 18)):
            cx = R.randint(0, w - 1)
            col_hits = [yy for yy in range(h) if px[cx, yy] > 200]
            if not col_hits or R.random() < 0.55:
                continue
            ys = max(col_hits)
            ln = R.randint(int(h * 0.05), int(h * 0.3))
            d.line([(cx, ys), (cx + R.randint(-1, 1), min(h - 1, ys + ln))], fill=230, width=R.choice([1, 2, 2, 3]))
    core = m.filter(ImageFilter.GaussianBlur(0.8))
    over = m.filter(ImageFilter.GaussianBlur(sz * 0.12)).point(lambda v: int(v * 0.45))
    a = ImageChops.lighter(core, over)
    a = ImageChops.multiply(a, noise_mask(w, h, 0.85, 0.6).point(lambda v: 150 + v * 105 // 255))
    img.paste(Image.new('RGBA', (w, h), col + (255,)), (0, 0), a)
    if rot:
        img = img.rotate(rot, resample=Image.BICUBIC, expand=False)
    return img


def stencil(text, w, h, col, border=True):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    lines = text.split('\n')
    sz = int(h / (len(lines) + 0.6) * 0.78)
    f = font(sz)
    while max(d.textbbox((0, 0), ln, font=f)[2] for ln in lines) > w * 0.9 and sz > 10:
        sz = int(sz * 0.92)
        f = font(sz)
    y = (h - sz * len(lines) * 1.15) / 2
    for ln in lines:
        bb = d.textbbox((0, 0), ln, font=f)
        d.text(((w - (bb[2] - bb[0])) / 2 - bb[0], y - bb[1] + 2), ln, fill=255, font=f, stroke_width=max(1, sz // 16))
        y += sz * 1.15
    if border:
        d.rectangle([4, 4, w - 5, h - 5], outline=255, width=max(3, h // 40))
    # Stencil bridges and a worn, uneven coat.
    for _ in range(int(w / 40)):
        bx = R.randint(0, w)
        d.line([(bx, 0), (bx, h)], fill=0, width=2)
    a = ImageChops.multiply(m.filter(ImageFilter.GaussianBlur(0.7)), noise_mask(w, h, 0.7, 1.0).point(lambda v: 110 + v * 145 // 255))
    img.paste(Image.new('RGBA', (w, h), col + (255,)), (0, 0), a)
    return img


def poster(w, h, title, sub, band, paper=(222, 214, 190)):
    img = Image.new('RGBA', (w, h), paper + (255,))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, int(h * 0.28)], fill=band + (255,))
    f1 = font(int(h * 0.15))
    bb = d.textbbox((0, 0), title, font=f1)
    d.text(((w - bb[2]) / 2, h * 0.05), title, fill=(250, 245, 230), font=f1)
    # A head-and-shoulders silhouette: a candidate, or the missing person's photo.
    cx, cy = w * 0.5, h * 0.55
    d.ellipse([cx - w * 0.12, cy - h * 0.18, cx + w * 0.12, cy + h * 0.02], fill=(60, 52, 46))
    d.rectangle([cx - w * 0.24, cy + h * 0.02, cx + w * 0.24, cy + h * 0.2], fill=(60, 52, 46))
    f2 = font(int(h * 0.09))
    bb = d.textbbox((0, 0), sub, font=f2)
    d.text(((w - bb[2]) / 2, h * 0.8), sub, fill=(40, 30, 25), font=f2)
    # Sun-faded, rain-streaked, torn at the edges.
    fade = Image.new('RGBA', (w, h), (230, 225, 210, 0))
    fade.putalpha(noise_mask(w, h, 0.5, 6).point(lambda v: v // 3))
    img = Image.alpha_composite(img, fade)
    a = Image.new('L', (w, h), 255)
    ad = ImageDraw.Draw(a)
    for _ in range(14):
        ex = R.choice([0, w])
        ey = R.randint(0, h)
        ad.ellipse([ex - R.randint(8, 30), ey - 20, ex + R.randint(8, 30), ey + 20], fill=0)
    for _ in range(R.randint(1, 3)):
        tx = R.randint(0, w)
        ad.polygon([(tx, h), (tx + R.randint(20, 60), h), (tx + R.randint(-10, 40), h - R.randint(30, 90))], fill=0)
    img.putalpha(ImageChops.multiply(a, Image.new('L', (w, h), 235)))
    return img


def oval_sign(w, h, text, col, bg):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([6, 6, w - 6, h - 6], fill=bg + (240,), outline=col + (255,), width=5)
    f = font(int(h * 0.16))
    lines = text.split('\n')
    y = h / 2 - len(lines) * h * 0.1
    for ln in lines:
        bb = d.textbbox((0, 0), ln, font=f)
        d.text(((w - bb[2]) / 2, y), ln, fill=col + (255,), font=f)
        y += h * 0.2
    return img


def streak(w, h, col, n=9, from_top=True):
    """Rust or water running down from an edge."""
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    for _ in range(n):
        x = R.randint(int(w * 0.1), int(w * 0.9))
        ln = R.randint(int(h * 0.3), h)
        wd = R.randint(3, max(4, w // 12))
        for k in range(ln):
            a = int(200 * (1 - k / ln) ** 1.4)
            d.line([(x - wd // 2 + R.randint(-1, 1), k), (x + wd // 2, k)], fill=a)
            if R.random() < 0.05:
                x += R.choice([-1, 1])
    d.rectangle([0, 0, w, int(h * 0.06)], fill=210)
    m = m.filter(ImageFilter.GaussianBlur(2.0))
    m = ImageChops.multiply(m, noise_mask(w, h, 0.6, 1.5).point(lambda v: 120 + v * 135 // 255))
    if not from_top:
        m = m.transpose(Image.FLIP_TOP_BOTTOM)
    img = Image.new('RGBA', (w, h), col + (0,))
    img.putalpha(m)
    return img


def blotch(w, h, col, density=0.45, blur=10, edge=True):
    m = noise_mask(w, h, density, blur).point(lambda v: min(255, int(v * 1.6)))
    m = ImageChops.multiply(m, noise_mask(w, h, 0.55, blur * 0.35).point(lambda v: min(255, v * 2)))
    # Fade to nothing at the edges so the decal has no outline.
    g = Image.new('L', (w, h), 0)
    gd = ImageDraw.Draw(g)
    steps = 24
    for i in range(steps):
        a = int(255 * (i + 1) / steps)
        gd.ellipse([w * 0.5 * i / steps, h * 0.5 * i / steps, w - w * 0.5 * i / steps, h - h * 0.5 * i / steps], fill=a)
    g = g.filter(ImageFilter.GaussianBlur(w / 16))
    if edge:
        m = ImageChops.multiply(m, g)
    img = Image.new('RGBA', (w, h), col + (0,))
    img.putalpha(m)
    return img


def damp(w, h):
    """Rising damp at the foot of a wall: dark at the bottom, a ragged tide line, mould spots."""
    m = Image.new('L', (w, h), 0)
    px = m.load()
    tide = [h * (0.25 + 0.2 * math.sin(x * 0.03 + R.random()) + 0.1 * R.random()) for x in range(w)]
    for x in range(w):
        for y in range(h):
            t = 1.0 - y / h  # 1 at the top
            if y > tide[x]:
                px[x, y] = int(170 * min(1.0, (y - tide[x]) / (h * 0.5) + 0.35))
            elif y > tide[x] - 4:
                px[x, y] = 120
    m = m.filter(ImageFilter.GaussianBlur(2.5))
    m = ImageChops.multiply(m, noise_mask(w, h, 0.65, 2.0).point(lambda v: 140 + v * 115 // 255))
    img = Image.new('RGBA', (w, h), (22, 26, 16, 0))
    img.putalpha(m)
    return img


def handprints(w, h, col):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for _ in range(R.randint(2, 4)):
        m = Image.new('L', (w, h), 0)
        d = ImageDraw.Draw(m)
        cx, cy = R.randint(int(w * 0.2), int(w * 0.8)), R.randint(int(h * 0.3), int(h * 0.75))
        s = w * R.uniform(0.09, 0.13)
        d.ellipse([cx - s, cy - s * 0.9, cx + s, cy + s * 1.1], fill=230)
        for k, (ang, ln) in enumerate([(-50, 1.5), (-20, 1.9), (0, 2.0), (20, 1.8), (55, 1.2)]):
            a = math.radians(ang - 90)
            x1, y1 = cx + math.cos(a) * s * 0.8, cy + math.sin(a) * s * 0.8
            x2, y2 = cx + math.cos(a) * s * ln * 1.25, cy + math.sin(a) * s * ln * 1.25
            d.line([(x1, y1), (x2, y2)], fill=230, width=int(s * 0.42))
        # Dragged downward.
        drag = m.filter(ImageFilter.GaussianBlur(2))
        for k in range(1, 12):
            m = ImageChops.lighter(m, ImageChops.offset(drag, 0, k * 3).point(lambda v, k=k: int(v * (1 - k / 12) * 0.6)))
        m = ImageChops.multiply(m, noise_mask(w, h, 0.75, 0.8).point(lambda v: 120 + v * 135 // 255))
        layer = Image.new('RGBA', (w, h), col + (0,))
        layer.putalpha(m)
        img = Image.alpha_composite(img, layer)
    return img


def eye_symbol(w, h, col):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    cx, cy = w / 2, h / 2
    d.arc([w * 0.1, h * 0.28, w * 0.9, h * 0.95], 200, 340, fill=255, width=9)
    d.arc([w * 0.1, h * 0.05, w * 0.9, h * 0.72], 20, 160, fill=255, width=9)
    d.ellipse([cx - w * 0.11, cy - h * 0.11, cx + w * 0.11, cy + h * 0.11], fill=255)
    for k in range(7):
        a = math.radians(200 + k * 23)
        d.line([(cx + math.cos(a) * w * 0.36, cy + math.sin(a) * h * 0.3), (cx + math.cos(a) * w * 0.47, cy + math.sin(a) * h * 0.42)], fill=255, width=6)
    m = m.filter(ImageFilter.GaussianBlur(1.0))
    img.paste(Image.new('RGBA', (w, h), col + (255,)), (0, 0), m)
    return img


def tally(w, h, col):
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    x = w * 0.08
    groups = R.randint(4, 7)
    for g in range(groups):
        n = 5 if g < groups - 1 else R.randint(1, 4)
        for k in range(min(n, 4)):
            d.line([(x + k * 14, h * 0.25 + R.randint(-3, 3)), (x + k * 14 + R.randint(-3, 3), h * 0.75)], fill=255, width=5)
        if n == 5:
            d.line([(x - 6, h * 0.65), (x + 52, h * 0.32)], fill=255, width=5)
        x += 78
    img = Image.new('RGBA', (w, h), col + (0,))
    img.putalpha(m.filter(ImageFilter.GaussianBlur(0.8)))
    return img


def x_mark(w, h, col):
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    d.line([(w * 0.18, h * 0.15), (w * 0.82, h * 0.85)], fill=255, width=w // 11)
    d.line([(w * 0.82, h * 0.12), (w * 0.2, h * 0.88)], fill=255, width=w // 11)
    m = m.filter(ImageFilter.GaussianBlur(3))
    for _ in range(6):
        cx = R.randint(int(w * 0.2), int(w * 0.8))
        d2 = ImageDraw.Draw(m)
        d2.line([(cx, h * 0.6), (cx, h * R.uniform(0.75, 1.0))], fill=200, width=4)
    img = Image.new('RGBA', (w, h), col + (0,))
    img.putalpha(ImageChops.multiply(m, noise_mask(w, h, 0.8, 0.8).point(lambda v: 140 + v * 115 // 255)))
    return img


def build_cells():
    cells = []   # (name, kind, image)
    # The Sleep project's own art.
    for f in sorted(os.listdir(TAGS)):
        if not f.endswith('.png'):
            continue
        im = Image.open(os.path.join(TAGS, f)).convert('RGBA')
        kind = f.split('_')[0]
        tw, th = {'tag': (256, 256), 'throw': (512, 256), 'sign': (512, 256), 'census': (256, 128), 'graffiti': (512, 256)}[kind]
        cells.append((f[:-4], kind, im.resize((tw, th), Image.LANCZOS)))
    spray_cols = [(205, 40, 35), (30, 30, 32), (240, 235, 225), (40, 90, 200), (235, 190, 30), (40, 150, 60), (200, 60, 170), (230, 110, 30)]
    words = ['KALINAW', 'SIGE NA', 'BRGY BOYS', 'TROPA', 'PUROK 6', 'LODI', 'ANGAS', 'SPYKE', 'DOX', 'KRAS', 'BAHALA NA', 'TIBAY']
    for i, wd in enumerate(words):
        cells.append(('spray_%02d' % i, 'tag', spray_text(wd, 512, 256, R.choice(spray_cols), rot=R.uniform(-6, 6))))
    stencils = [('BAWAL UMIHI\nDITO', (180, 30, 25)), ('BAWAL MAGTAPON\nNG BASURA DITO', (30, 30, 30)), ('BAWAL ANG\nTAMBAY', (180, 30, 25)),
                ('MAY ASO', (30, 30, 30)), ('BAWAL PUMASOK', (180, 30, 25)), ('NO PARKING', (230, 230, 225)), ('KEEP OUT', (230, 200, 40)),
                ('PRIVATE\nPROPERTY', (30, 30, 30))]
    for i, (t, c) in enumerate(stencils):
        cells.append(('stencil_%02d' % i, 'stencil', stencil(t, 512, 256, c)))
    eerie = ['HUWAG KANG\nLALABAS SA GABI', 'NAKIKITA\nKA NAMIN', 'WALANG\nLIGTAS DITO', 'TULONG', 'SINO KA?', 'BUMALIK KA NA']
    for i, t in enumerate(eerie):
        im = spray_text(t, 512, 256, R.choice([(120, 15, 12), (20, 20, 20), (200, 195, 185)]), size=None, rot=R.uniform(-8, 8))
        cells.append(('eerie_%02d' % i, 'eerie', im))
    cells.append(('hands_red', 'eerie', handprints(256, 256, (95, 12, 10))))
    cells.append(('hands_black', 'eerie', handprints(256, 256, (18, 16, 14))))
    cells.append(('eye_red', 'eerie', eye_symbol(256, 256, (150, 20, 15))))
    cells.append(('eye_white', 'eerie', eye_symbol(256, 256, (215, 210, 200))))
    cells.append(('tally', 'eerie', tally(512, 128, (220, 215, 205))))
    cells.append(('x_red', 'eerie', x_mark(256, 256, (175, 25, 20))))
    cells.append(('x_white', 'eerie', x_mark(256, 256, (225, 220, 210))))
    posters = [('VOTE #7', 'KAP. DADO SALAZAR', (30, 70, 160)), ('IBOTO!', 'KGD. LITO MACARAEG', (170, 30, 30)),
               ('NAWAWALA', 'Huling nakita: Purok 6', (20, 20, 20)), ('BOXING', 'Covered Court - Sabado', (190, 120, 20)),
               ('PA-RENT', 'Room for rent, 1 pax', (40, 120, 60)), ('SALE!', 'Ukay-ukay sa Palengke', (180, 40, 120))]
    for i, (t, sb, band) in enumerate(posters):
        cells.append(('poster_%02d' % i, 'poster', poster(256, 256, t, sb, band)))
    cells.append(('god_bless', 'poster', oval_sign(256, 256, 'GOD BLESS\nOUR HOME', (30, 60, 140), (235, 228, 205))))
    cells.append(('jesus_lord', 'poster', stencil('JESUS IS\nLORD', 512, 256, (240, 240, 235), border=False)))
    cells.append(('load_dito', 'poster', stencil('LOAD DITO\nGCASH', 512, 256, (20, 90, 200), border=True)))
    cells.append(('ice_water', 'poster', stencil('ICE WATER\nP5', 256, 256, (30, 30, 30), border=False)))
    for i in range(4):
        cells.append(('rust_%d' % i, 'streak', streak(256, 512 if i < 2 else 256, (88, 40, 14), n=R.randint(6, 12))))
    for i in range(2):
        cells.append(('water_%d' % i, 'streak', streak(256, 512, (20, 22, 18), n=R.randint(5, 9))))
    for i in range(3):
        cells.append(('mould_%d' % i, 'stain', blotch(256, 256, (18, 24, 12), 0.5, 9)))
    cells.append(('soot', 'stain', streak(256, 512, (8, 8, 8), n=14, from_top=False)))
    for i in range(2):
        cells.append(('damp_%d' % i, 'damp', damp(512, 128)))
    for i in range(3):
        cells.append(('oil_%d' % i, 'ground', blotch(256, 256, (10, 9, 8), 0.55, 12)))
    for i in range(2):
        cells.append(('mud_%d' % i, 'ground', blotch(256, 256, (40, 30, 20), 0.5, 14)))
    return cells


def pack(cells, scale):
    """Shelf packing, tallest first; every cell scaled by `scale`. Returns (atlas, records) or None when full."""
    atlas = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    x = y = shelf = 0
    pad = 4
    out = []
    for name, kind, im in sorted(cells, key=lambda c: (-c[2].size[1], -c[2].size[0])):
        w, h = max(8, int(im.size[0] * scale)), max(8, int(im.size[1] * scale))
        if x + w > SIZE:
            x = 0
            y += shelf + pad
            shelf = 0
        if y + h > SIZE:
            return None
        atlas.paste(im.resize((w, h), Image.LANCZOS) if scale != 1.0 else im, (x, y))
        out.append({'name': name, 'kind': kind, 'rect': [x, y, w, h], 'aspect': round(w / h, 3)})
        x += w + pad
        shelf = max(shelf, h)
    return atlas, out, y + shelf


def main():
    cells = build_cells()
    scale = 1.0
    while True:
        r = pack(cells, scale)
        if r:
            break
        scale *= 0.94
    atlas, out, used = r
    print('scale %.2f' % scale)
    os.makedirs(OUT, exist_ok=True)
    atlas.save(os.path.join(OUT, 'vandal_atlas.png'))
    with open(os.path.join(OUT, 'vandal_atlas.json'), 'w', encoding='utf-8') as f:
        json.dump({'size': SIZE, 'cells': out}, f, indent=1)
    print('%d cells, %d px of %d used' % (len(out), used, SIZE))
    prev = Image.new('RGBA', (SIZE, SIZE), (92, 92, 88, 255))
    prev.alpha_composite(atlas)
    prev.convert('RGB').resize((1024, 1024)).save(os.path.join(ROOT, 'work', 'lemondev', 'r3', 'vandal_atlas_preview.jpg'), quality=85)


if __name__ == '__main__':
    main()
