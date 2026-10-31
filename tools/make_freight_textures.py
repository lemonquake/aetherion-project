"""Freight Delight's own textures: a squatter settlement grown inside an old container yard by the port, at night.

Every image is drawn here from noise and simple shapes (nothing downloaded, nothing from another game), so the set is
new and can be regenerated or restyled. Writes, under game/assets/maps/:
    textures/freight/<name>.png         albedo (what TrenchBroom shows; the .map names them "freight/<name>")
    normals/freight/<name>_normal.png   tangent-space normal map (OpenGL / Godot convention, green up)
    roughness/freight/<name>_rough.png  roughness (only the wet and polished surfaces)
    surfaces.json                       per material: physical material (bullets, footsteps), roughness, metal,
                                        emission, alpha, size in metres of one texture repeat

    python -I tools/make_freight_textures.py [--only=name,name] [--sheet]
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "maps"
FONTS = ROOT / "game" / "assets" / "fonts"
N = 512

SURFACES: dict = {}


# ------------------------------------------------------------------ noise and helpers

def noise(shape=(N, N), beta=2.0, seed=0, ax=1.0, ay=1.0, lo=0.0, hi=0.0):
    """Tileable fractal noise in [0, 1] (white noise shaped in frequency: wraps on both axes by construction).
    ax / ay stretch it: ax > ay gives streaks running down the image."""
    if isinstance(shape, int):
        shape = (shape, shape)
    h, w = shape
    r = np.random.default_rng(seed)
    F = np.fft.fft2(r.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None] * h
    fx = np.fft.fftfreq(w)[None, :] * w
    f = np.sqrt((fx * ax) ** 2 + (fy * ay) ** 2)
    f[0, 0] = 1.0
    amp = 1.0 / f ** (beta * 0.5)
    if lo > 0:
        amp[f < lo] = 0.0
    if hi > 0:
        amp *= np.exp(-(f / hi) ** 2)
    amp[0, 0] = 0.0
    o = np.real(np.fft.ifft2(F * amp))
    o -= o.min()
    o /= max(o.max(), 1e-9)
    return o


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def col(*c):
    return np.array(c, dtype=np.float64) / 255.0


def mix(a, b, t):
    t = np.asarray(t)
    if t.ndim == 2:
        t = t[..., None]
    return a * (1 - t) + b * t


def fill(shape, c):
    h, w = shape
    return np.ones((h, w, 3)) * np.asarray(c)


def blur(a, r):
    if r <= 0:
        return a
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    # wrap: blur a 3x3 tiling and cut the middle, so the result still tiles
    w, h = im.size
    big = Image.new(im.mode, (w * 3, h * 3))
    for i in range(3):
        for j in range(3):
            big.paste(im, (i * w, j * h))
    big = big.filter(ImageFilter.GaussianBlur(r)).crop((w, h, 2 * w, 2 * h))
    return np.asarray(big).astype(np.float64) / 255.0


def mask_from_draw(shape, fn, r=0.0, wrap=True):
    """A [0,1] mask drawn with PIL (fn(draw, w, h)); drawn on a 3x3 tiling when wrap so strokes cross the edges."""
    h, w = shape
    if wrap:
        im = Image.new("L", (w * 3, h * 3), 0)
        d = ImageDraw.Draw(im)
        fn(d, w, h, w, h)
        if r > 0:
            im = im.filter(ImageFilter.GaussianBlur(r))
        im = im.crop((w, h, 2 * w, 2 * h))
    else:
        im = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(im)
        fn(d, w, h, 0, 0)
        if r > 0:
            im = im.filter(ImageFilter.GaussianBlur(r))
    return np.asarray(im).astype(np.float64) / 255.0


def cracks(shape, n, seed, length=(40, 160), width=1):
    r = np.random.default_rng(seed)

    def fn(d, w, h, ox, oy):
        for _ in range(n):
            x, y = r.uniform(0, w), r.uniform(0, h)
            a = r.uniform(0, math.tau)
            pts = [(x, y)]
            for _ in range(int(r.uniform(*length) / 6)):
                a += r.normal(0, 0.45)
                x += math.cos(a) * 6
                y += math.sin(a) * 6
                pts.append((x, y))
            for dx in (-w, 0, w):
                for dy in (-h, 0, h):
                    d.line([(p[0] + ox + dx, p[1] + oy + dy) for p in pts], fill=255, width=width)
    return mask_from_draw(shape, fn)


def blobs(shape, n, seed, rad=(10, 40), soft=6.0):
    r = np.random.default_rng(seed)

    def fn(d, w, h, ox, oy):
        for _ in range(n):
            x, y = r.uniform(0, w), r.uniform(0, h)
            rr = r.uniform(*rad)
            ry = rr * r.uniform(0.5, 1.0)
            for dx in (-w, 0, w):
                for dy in (-h, 0, h):
                    d.ellipse([x - rr + ox + dx, y - ry + oy + dy, x + rr + ox + dx, y + ry + oy + dy], fill=255)
    return mask_from_draw(shape, fn, r=soft)


def normal_from(hgt, strength):
    dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 0.5
    dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 0.5
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(hgt)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5


def font(size, name="BarlowCondensed-SemiBold.ttf"):
    return ImageFont.truetype(str(FONTS / name), size)


def save(name, alb, hgt=None, strength=4.0, **surf):
    """Write the maps and record the surface. alb (h,w,3 or h,w,4) in [0,1]; hgt (h,w) height in texels-ish units;
    surf.rough is a number, or an array for a roughness map (its mean is recorded too)."""
    rough = None
    if isinstance(surf.get("rough"), np.ndarray):
        rough = surf["rough"]
        surf["rough"] = round(float(np.mean(rough)), 3)
    (OUT / "textures" / "freight").mkdir(parents=True, exist_ok=True)
    (OUT / "normals" / "freight").mkdir(parents=True, exist_ok=True)
    (OUT / "roughness" / "freight").mkdir(parents=True, exist_ok=True)
    a = np.clip(alb, 0, 1)
    mode = "RGBA" if a.shape[-1] == 4 else "RGB"
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), mode).save(OUT / "textures" / "freight" / f"{name}.png", optimize=True)
    if hgt is not None:
        nm = normal_from(hgt, strength)
        Image.fromarray((nm * 255 + 0.5).astype(np.uint8), "RGB").save(OUT / "normals" / "freight" / f"{name}_normal.png", optimize=True)
    if rough is not None:
        Image.fromarray((np.clip(rough, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save(OUT / "roughness" / "freight" / f"{name}_rough.png", optimize=True)
    rec = {"phys": "concrete", "rough": 0.8, "metal": 0.0, "size": 2.0}
    rec.update(surf)
    rec["normal"] = hgt is not None
    rec["rough_map"] = rough is not None
    rec["px"] = [int(a.shape[1]), int(a.shape[0])]
    SURFACES["freight/" + name] = rec


# ------------------------------------------------------------------ corrugated iron (yero)

def yero(name, seed, paint=None, flake=0.0, rusty=0.5):
    """Galvanised corrugated sheet, ridges running down the sheet (26 per 2 m tile), rust bleeding from the nail rows
    and the laps; painted ones flake back to rust and zinc."""
    y, x = np.mgrid[0:N, 0:N] / N
    ridge = np.sin(x * math.tau * 26) * 0.5 + 0.5
    n1 = noise(seed=seed, beta=2.2)
    n2 = noise(seed=seed + 1, beta=1.6)
    streak = noise(seed=seed + 2, beta=2.0, ax=6.0, ay=0.6)   # long vertical runs
    zinc = mix(col(118, 124, 128), col(160, 165, 166), n2 ** 1.5)
    zinc *= (0.85 + 0.25 * noise(seed=seed + 3, beta=0.6, hi=200)[..., None])  # spangle
    ra = 0.75 - rusty * 0.3
    rust_amt = smooth(n1 * 0.7 + streak * 0.5 + (1 - ridge) * 0.12, ra, ra + 0.3)
    nails = np.zeros((N, N))
    for ry in (0.06, 0.56):
        nails += smooth(1 - np.abs(y - ry) * 60, 0.0, 1.0) * (ridge > 0.85)
    bleed = np.clip(smooth(streak, 0.35, 0.9) * (np.clip(1 - np.abs(((y - 0.06) % 0.5) - 0.12) * 4.5, 0, 1)), 0, 1)
    rust_amt = np.clip(rust_amt + bleed * 0.5 * rusty + nails * 0.7, 0, 1)
    rust = mix(col(96, 46, 22), col(150, 78, 34), noise(seed=seed + 4, beta=1.2))
    rust = mix(rust, col(60, 32, 20), smooth(n2, 0.6, 0.9))
    base = zinc
    if paint is not None:
        pc = mix(np.asarray(paint), np.asarray(paint) * 1.25 + 0.05, noise(seed=seed + 5, beta=1.5))
        pc = mix(pc, col(170, 170, 160), 0.25 * streak)   # sun-faded
        peel = smooth(noise(seed=seed + 6, beta=2.4) + streak * 0.2, 0.75 - flake * 0.3, 0.8 - flake * 0.3)
        base = mix(pc, zinc, peel)
        rust_amt = rust_amt * (0.12 + 0.88 * peel)
    alb = mix(base, rust, rust_amt)
    alb *= (0.78 + 0.3 * ridge)[..., None]                  # baked shading on the ridges
    alb *= (0.88 + 0.12 * blur(noise(seed=seed + 7, beta=2.0), 2))[..., None]
    hgt = ridge * 7.0 + n2 * 0.6 + rust_amt * 0.4
    save(name, alb, hgt, 3.0, phys="sheet_metal", rough=0.55, metal=0.35 if paint is None else 0.15, size=2.0)


# ------------------------------------------------------------------ wood

def plywood(name, seed):
    """Two weathered plywood sheets side by side (1.22 x 2.44 m each, the tile is 2.44 m square): grain down the
    sheet, grey sun-bleach, water tide marks, nail lines at the studs."""
    y, x = np.mgrid[0:N, 0:N] / N
    grain = noise(seed=seed, beta=2.0, ax=0.3, ay=8.0)
    ring = np.sin((x * 40 + grain * 6) * math.tau) * 0.5 + 0.5
    base = mix(col(150, 118, 82), col(112, 86, 60), ring * 0.6 + grain * 0.4)
    grey = noise(seed=seed + 1, beta=2.2)
    base = mix(base, col(118, 112, 102), smooth(grey, 0.3, 0.8) * 0.75)
    stain = smooth(noise(seed=seed + 2, beta=2.6, ax=2.0, ay=0.5), 0.55, 0.8)
    base = mix(base, col(58, 46, 36), stain * 0.6)
    seam = np.zeros((N, N))
    for sx in (0.0, 0.5, 1.0):
        seam = np.maximum(seam, smooth(1 - np.abs(x - sx) * 260, 0, 1))
    seam = np.maximum(seam, smooth(1 - np.abs(y - 0.0) * 260, 0, 1))
    seam = np.maximum(seam, smooth(1 - np.abs(y - 1.0) * 260, 0, 1))
    base = mix(base, col(30, 24, 20), seam)
    nails = np.zeros((N, N))
    for sx in (0.012, 0.488, 0.512, 0.988, 0.25, 0.75):
        for k in range(10):
            ny = (k + 0.5) / 10
            nails += smooth(1 - np.hypot(x - sx, y - ny) * 220, 0, 1)
    base = mix(base, col(70, 50, 38), np.clip(nails, 0, 1))
    hgt = grain * 1.5 + ring * 0.5 - seam * 4 - nails * 1.0
    save(name, base, hgt, 2.0, phys="plywood", rough=0.85, size=2.44)


def planks(name, seed, paints):
    """Mismatched shack planks, nailed across: each board its own width and tone, some with old paint, dark gaps."""
    r = np.random.default_rng(seed)
    y, x = np.mgrid[0:N, 0:N] / N
    alb = np.zeros((N, N, 3))
    hgt = np.zeros((N, N))
    yy = 0
    rows = []
    while yy < N:
        h = int(r.uniform(44, 78))
        if N - yy - h < 36:
            h = N - yy
        rows.append((yy, h))
        yy += h
    grain = noise(seed=seed, beta=2.0, ax=8.0, ay=0.3)
    for i, (y0, h) in enumerate(rows):
        tone = mix(col(118, 86, 56), col(84, 62, 44), r.random())
        tone = mix(tone, col(126, 120, 108), r.uniform(0.2, 0.7))
        sl = slice(y0, y0 + h)
        g = grain[sl]
        c = mix(tone, tone * 0.7, g)
        if r.random() < 0.55:
            p = np.asarray(paints[r.integers(len(paints))])
            peel = smooth(noise((h, N), seed=seed + 10 + i, beta=2.2), 0.45, 0.6)
            c = mix(p * (0.8 + 0.2 * g[..., None]), c, peel)
        edge = np.minimum(np.arange(h), np.arange(h)[::-1])[:, None] / 3.0
        c *= np.clip(0.55 + edge * 0.15, 0, 1)[..., None] ** 0.5
        alb[sl] = c
        hgt[sl] = np.clip(edge, 0, 1) * 3 + g
        gap = min(3, h // 10)
        alb[y0:y0 + gap] = col(14, 11, 9)
        hgt[y0:y0 + gap] = -2
    for sx in (0.2, 0.7):
        for (y0, h) in rows:
            for dy in (0.3, 0.7):
                cy = (y0 + h * dy) / N
                m = smooth(1 - np.hypot(x - sx, y - cy) * 300, 0, 1)
                alb = mix(alb, col(60, 40, 30), m)
    alb *= (0.85 + 0.2 * noise(seed=seed + 3, beta=2.0))[..., None]
    save(name, alb, hgt, 2.5, phys="wood", rough=0.82, size=2.0)


# ------------------------------------------------------------------ masonry

def chb(name, seed, paint=None):
    """Hollow-block (CHB) wall, 40 x 20 cm blocks in running bond (5 x 10 per 2 m tile). Raw: grey blocks, sloppy
    mortar, efflorescence and black mould. Painted: plastered over, faded colour, peeling, mildew streaks."""
    y, x = np.mgrid[0:N, 0:N] / N
    row = np.floor(y * 10)
    xo = (x * 5 + (row % 2) * 0.5) % 1.0
    yo = (y * 10) % 1.0
    mort = np.maximum(smooth(1 - np.minimum(xo, 1 - xo) * 26, 0.2, 1), smooth(1 - np.minimum(yo, 1 - yo) * 13, 0.2, 1))
    n1 = noise(seed=seed, beta=2.0)
    n2 = noise(seed=seed + 1, beta=1.3)
    cell = (np.floor(x * 5 + (row % 2) * 0.5) * 7 + row * 13) % 10 / 10.0
    block = mix(col(128, 126, 120), col(96, 95, 92), cell * 0.5 + n2 * 0.5)
    block *= (0.85 + 0.3 * noise(seed=seed + 2, beta=0.8, hi=180))[..., None]
    alb = mix(block, col(150, 146, 136), mort)
    mould = smooth(noise(seed=seed + 3, beta=2.4, ax=3.0, ay=0.6), 0.55, 0.85)
    alb = mix(alb, col(40, 44, 36), mould * 0.7)
    eff = smooth(n1, 0.7, 0.9)
    alb = mix(alb, col(200, 198, 190), eff * 0.35)
    hgt = (1 - mort) * 3 + n2 * 0.8
    if paint is not None:
        pc = np.asarray(paint)
        plaster = mix(pc, pc * 0.82, noise(seed=seed + 4, beta=1.6))
        plaster = mix(plaster, col(175, 172, 160), smooth(noise(seed=seed + 5, beta=2.0, ax=4.0, ay=0.5), 0.5, 0.9) * 0.4)
        peel = smooth(noise(seed=seed + 6, beta=2.6), 0.66, 0.7)
        alb2 = mix(plaster, alb, peel)
        alb2 *= (1 - mort * 0.08)[..., None]                 # block joints show through the plaster
        alb2 = mix(alb2, col(38, 40, 34), mould * 0.55)
        cr = blur(cracks((N, N), 5, seed + 7, (60, 200), 1), 0.6)
        alb2 = mix(alb2, col(50, 46, 40), cr * 0.8)
        # tags: loose spray-paint scribbles
        r = np.random.default_rng(seed + 8)

        def tag(d, w, h, ox, oy):
            for _ in range(3):
                cx, cy = r.uniform(0.1, 0.9) * w, r.uniform(0.3, 0.8) * h
                pts = []
                a = r.uniform(0, 6)
                for k in range(26):
                    a += r.normal(0, 1.1)
                    cx += math.cos(a) * 9
                    cy += math.sin(a) * 6
                    pts.append((cx + ox, cy + oy))
                d.line(pts, fill=255, width=4, joint="curve")
        tg = mask_from_draw((N, N), tag, r=0.8)
        tcol = [col(30, 30, 34), col(150, 30, 40), col(30, 60, 140)][seed % 3]
        alb = mix(alb2, tcol, tg * 0.85)
        hgt = hgt * 0.25 * peel + (1 - peel) * 1.5 + n1 * 0.4 - cr * 1.5
        save(name, alb, hgt, 2.0, phys="hollow_block", rough=0.9, size=2.0)
    else:
        save(name, alb, hgt, 2.5, phys="hollow_block", rough=0.92, size=2.0)


def concrete_rough(name, seed):
    n1 = noise(seed=seed, beta=2.0)
    n2 = noise(seed=seed + 1, beta=1.0, hi=200)
    alb = mix(col(122, 120, 114), col(88, 86, 82), n1)
    alb *= (0.85 + 0.25 * n2)[..., None]
    holes = smooth(noise(seed=seed + 2, beta=0.4, hi=220), 0.78, 0.82)
    alb = mix(alb, col(50, 48, 46), holes)
    alb = mix(alb, col(48, 52, 44), smooth(noise(seed=seed + 3, beta=2.5, ax=3, ay=0.5), 0.6, 0.85) * 0.5)
    save(name, alb, n1 * 2 + n2 - holes * 2, 2.0, phys="concrete", rough=0.9, size=2.0)


# ------------------------------------------------------------------ ground

def concrete_wet(name, seed):
    """The yard's slab after rain: 2 m bays (joints), cracks, oil and rust stains, puddles that mirror the lamps."""
    y, x = np.mgrid[0:N, 0:N] / N
    n1 = noise(seed=seed, beta=2.0)
    n2 = noise(seed=seed + 1, beta=1.0, hi=220)
    alb = mix(col(128, 126, 120), col(90, 89, 85), n1)
    alb *= (0.82 + 0.3 * n2)[..., None]
    joint = np.maximum(smooth(1 - np.minimum(x % 0.5, 0.5 - x % 0.5) * 300, 0, 1), smooth(1 - np.minimum(y % 0.5, 0.5 - y % 0.5) * 300, 0, 1))
    alb = mix(alb, col(30, 30, 30), joint * 0.85)
    cr = blur(cracks((N, N), 14, seed + 2, (40, 220), 1), 0.5)
    alb = mix(alb, col(26, 26, 26), cr * 0.9)
    oil = blobs((N, N), 9, seed + 3, (10, 46), 9) * noise(seed=seed + 4, beta=1.4)
    alb = mix(alb, col(24, 22, 22), smooth(oil, 0.1, 0.5) * 0.85)
    rust = blobs((N, N), 4, seed + 5, (20, 60), 14) * noise(seed=seed + 6, beta=1.8)
    alb = mix(alb, col(110, 64, 34), smooth(rust, 0.2, 0.6) * 0.5)
    pud = smooth(noise(seed=seed + 7, beta=2.8) + n1 * 0.15, 0.62, 0.68)
    wet = smooth(noise(seed=seed + 7, beta=2.8) + n1 * 0.15, 0.5, 0.66)
    alb = alb * (1 - wet[..., None] * 0.32)
    rough = 0.82 - wet * 0.55 - pud * 0.22 + n2 * 0.08
    hgt = n1 * 1.2 + n2 * 0.6 - joint * 2 - cr * 2 - pud * 0.8
    save(name, alb, hgt, 2.0, rough=rough, phys="concrete", size=4.0)


def mud(name, seed):
    n1 = noise(seed=seed, beta=2.2)
    n2 = noise(seed=seed + 1, beta=0.9, hi=210)
    alb = mix(col(104, 88, 68), col(72, 60, 47), n1)
    alb *= (0.8 + 0.35 * n2)[..., None]
    stones = smooth(noise(seed=seed + 2, beta=0.3, hi=150), 0.8, 0.84)
    alb = mix(alb, col(120, 116, 108), stones * 0.8)
    r = np.random.default_rng(seed + 3)
    lit = np.zeros((N, N, 3))
    litm = np.zeros((N, N))
    for _ in range(26):   # litter: wrappers, sachets, bottle caps
        cx, cy = r.integers(0, N, 2)
        w, h = r.integers(3, 12, 2)
        c = [col(200, 40, 40), col(230, 200, 60), col(40, 120, 200), col(230, 230, 230), col(40, 160, 70)][r.integers(5)]
        ys = np.arange(cy, cy + h) % N
        xs = np.arange(cx, cx + w) % N
        lit[np.ix_(ys, xs)] = c * r.uniform(0.5, 0.9)
        litm[np.ix_(ys, xs)] = 1.0
    alb = mix(alb, lit, litm * 0.85)
    pud = smooth(noise(seed=seed + 4, beta=3.0) + n1 * 0.2, 0.66, 0.72)
    wet = smooth(noise(seed=seed + 4, beta=3.0) + n1 * 0.2, 0.52, 0.7)
    alb = mix(alb * (1 - wet[..., None] * 0.4), col(34, 30, 26), pud * 0.6)
    rough = 0.9 - wet * 0.5 - pud * 0.3
    save(name, alb, n1 * 2.5 + n2 + stones * 1.5 - pud, 2.5, rough=rough, phys="dirt", size=3.0)


def asphalt(name, seed):
    n1 = noise(seed=seed, beta=2.0)
    agg = noise(seed=seed + 1, beta=0.2, hi=240)
    alb = mix(col(54, 54, 56), col(36, 36, 38), n1)
    alb = mix(alb, col(110, 108, 104), smooth(agg, 0.7, 0.85) * 0.6)
    patch = smooth(noise(seed=seed + 2, beta=3.2), 0.6, 0.62)
    alb = mix(alb, col(26, 26, 28), patch * 0.8)
    cr = blur(cracks((N, N), 10, seed + 3, (60, 260), 2), 0.7)
    alb = mix(alb, col(14, 14, 14), cr)
    wet = smooth(noise(seed=seed + 4, beta=2.8), 0.55, 0.7)
    rough = 0.85 - wet * 0.5
    save(name, alb * (1 - wet[..., None] * 0.35), n1 + agg * 1.5 - cr * 2, 2.0, rough=rough, phys="concrete", size=4.0)


def water(name, seed):
    n1 = noise(seed=seed, beta=2.4)
    n2 = noise(seed=seed + 1, beta=1.4)
    alb = mix(col(18, 24, 22), col(30, 36, 28), n1)
    scum = smooth(n2, 0.72, 0.82)
    alb = mix(alb, col(60, 62, 44), scum * 0.6)
    save(name, alb, n1 * 1.5 + n2 * 0.5, 1.5, rough=0.06, phys="water", size=6.0)


def gravel(name, seed):
    n = noise(seed=seed, beta=0.2, hi=200)
    n1 = noise(seed=seed + 1, beta=2.0)
    alb = mix(col(84, 80, 74), col(132, 126, 116), smooth(n, 0.4, 0.7))
    alb *= (0.8 + 0.3 * n1)[..., None]
    save(name, alb, smooth(n, 0.3, 0.8) * 3, 3.0, phys="sand", rough=0.95, size=2.0)


# ------------------------------------------------------------------ shipping containers

CONTAINER_COLOURS = {
    "red": (128, 38, 30), "blue": (34, 66, 112), "green": (40, 92, 62), "orange": (176, 92, 36), "grey": (120, 122, 118),
    "yellow": (176, 140, 40),
}


def container_side(name, seed, paint):
    """A container's long side, one tile = 2.9 m high (the high-cube's full height) by 2.9 m: trapezoid ribs running
    up the side, the top and bottom rails, paint faded in bands, rust at the rails and the dents, scratches."""
    y, x = np.mgrid[0:N, 0:N] / N
    pitch = 1.0 / 10.0
    u = (x % pitch) / pitch
    rib = np.clip(np.minimum(u, 1 - u) * 6.0 - 0.6, 0, 1)            # trapezoid: flats with sloped flanks
    rail = (y < 0.055) | (y > 0.945)
    pc = np.asarray(paint)
    fade = noise(seed=seed, beta=2.4, ax=0.4, ay=3.0)
    alb = mix(pc, pc * 1.35 + 0.06, fade * 0.6)
    alb = mix(alb, col(150, 148, 140), smooth(noise(seed=seed + 1, beta=2.0), 0.6, 0.9) * 0.25)
    rust_n = noise(seed=seed + 2, beta=1.8)
    streak = noise(seed=seed + 3, beta=2.0, ax=6.0, ay=0.5)
    rustm = smooth(rust_n * 0.6 + streak * 0.5 + rail * 0.5 + smooth(0.08 - np.minimum(y, 1 - y), 0, 0.08) * 0.6, 0.62, 0.85)
    rust = mix(col(92, 44, 24), col(140, 70, 32), noise(seed=seed + 4, beta=1.2))
    alb = mix(alb, rust, rustm)
    scr = blur(cracks((N, N), 12, seed + 5, (20, 60), 1), 0.3)
    alb = mix(alb, col(150, 140, 128), scr * 0.5)
    shade = 0.82 + 0.25 * rib
    alb *= np.where(rail, 0.7, shade)[..., None]
    dent = smooth(noise(seed=seed + 6, beta=3.0), 0.7, 0.9)
    hgt = np.where(rail, 7.0, rib * 5.0) - dent * 2.0 + rust_n * 0.3
    save(name, alb, hgt, 2.0, phys="steel", rough=0.6, metal=0.25, size=2.9)


def container_door(name, seed, paint):
    """The door end (fit to the 2.44 x 2.9 m face): two leaves, four locking bars with their cams and handles, the
    hinge posts, the corner castings, faded stencilled marks (a made-up owner code)."""
    W, H = 432, 512
    y, x = np.mgrid[0:H, 0:W]
    xu, yu = x / W, y / H
    pc = np.asarray(paint)
    fade = noise((H, W), seed=seed, beta=2.4, ax=0.4, ay=3.0)
    alb = mix(pc, pc * 1.3 + 0.05, fade * 0.5)
    rib = (np.sin(yu * math.tau * 5) * 0.5 + 0.5) ** 2                 # shallow horizontal swages on the leaves
    hgt = rib * 1.5
    frame = (xu < 0.04) | (xu > 0.96) | (yu < 0.05) | (yu > 0.95)
    gap = np.abs(xu - 0.5) < 0.004
    alb = np.where(frame[..., None], alb * 0.72, alb * (0.9 + 0.1 * rib)[..., None])
    hgt = np.where(frame, 5.0, hgt)
    for bx in (0.13, 0.37, 0.63, 0.87):
        bar = (np.abs(xu - bx) < 0.012) & (yu > 0.06) & (yu < 0.94)
        alb = np.where(bar[..., None], col(70, 70, 66) * (0.8 + 0.3 * noise((H, W), seed=seed + 7, beta=1.0))[..., None], alb)
        hgt = np.where(bar, 8.0, hgt)
        for hy in (0.46,):
            hd = (np.abs(xu - bx - 0.03) < 0.035) & (np.abs(yu - hy) < 0.008)
            alb = np.where(hd[..., None], col(60, 60, 58), alb)
            hgt = np.where(hd, 9.0, hgt)
    alb = np.where(gap[..., None], col(15, 15, 15), alb)
    hgt = np.where(gap, -3.0, hgt)
    rustm = smooth(noise((H, W), seed=seed + 2, beta=1.8) * 0.7 + frame * 0.4, 0.6, 0.85)
    alb = mix(alb, col(110, 56, 28), rustm * 0.8)
    im = Image.fromarray((np.clip(alb, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    f1, f2 = font(30), font(17)
    r = np.random.default_rng(seed)
    code = "FDLU %06d %d" % (r.integers(100000, 999999), r.integers(0, 9))
    d.text((W * 0.55, H * 0.1), code, fill=(225, 222, 210), font=f1)
    d.text((W * 0.55, H * 0.17), "45G1", fill=(225, 222, 210), font=f1)
    d.text((W * 0.55, H * 0.75), "MAX GROSS 32,500 KG", fill=(220, 218, 205), font=f2)
    d.text((W * 0.55, H * 0.79), "TARE     3,940 KG", fill=(220, 218, 205), font=f2)
    d.text((W * 0.08, H * 0.1), "FREIGHT DELIGHT", fill=(225, 222, 210), font=f2)
    d.text((W * 0.08, H * 0.135), "LOGISTICS", fill=(225, 222, 210), font=f2)
    alb = np.asarray(im).astype(np.float64) / 255.0
    alb = mix(alb, mix(pc, col(160, 156, 146), 0.5), smooth(noise((H, W), seed=seed + 9, beta=2.0), 0.55, 0.9) * 0.55)   # faded text
    save(name, alb, hgt, 1.6, phys="steel", rough=0.6, metal=0.25, size=2.9, fit=True)


def container_roof(name, seed):
    y, x = np.mgrid[0:N, 0:N] / N
    swage = (np.sin(y * math.tau * 8) * 0.5 + 0.5) ** 3
    n1 = noise(seed=seed, beta=2.2)
    alb = mix(col(108, 104, 96), col(84, 80, 74), n1)
    rust = smooth(noise(seed=seed + 1, beta=2.6) + swage * 0.1, 0.55, 0.75)
    alb = mix(alb, col(104, 52, 26), rust * 0.8)
    pud = smooth(noise(seed=seed + 2, beta=3.0), 0.68, 0.72)
    alb = mix(alb, col(40, 36, 32), pud * 0.5)
    save(name, alb * (0.85 + 0.15 * swage)[..., None], swage * 3 + n1, 2.0, rough=np.clip(0.75 - pud * 0.5, 0, 1), phys="steel", metal=0.2, size=2.44)


# ------------------------------------------------------------------ steel

def tread_plate(name, seed):
    y, x = np.mgrid[0:N, 0:N] / N
    k = 16
    u = (x * k) % 1.0
    v = (y * k) % 1.0
    row = np.floor(y * k) % 2
    a = np.where(row == 0, ((u - 0.5) * 0.9 + (v - 0.5) * 0.4), ((u - 0.5) * 0.9 - (v - 0.5) * 0.4))
    lug = smooth(0.09 - np.abs(a), 0.0, 0.05) * smooth(0.42 - np.abs(v - 0.5), 0, 0.1)
    n1 = noise(seed=seed, beta=2.0)
    base = mix(col(70, 70, 70), col(110, 108, 104), n1)
    rust = smooth(noise(seed=seed + 1, beta=2.2), 0.45, 0.75)
    base = mix(base, col(100, 50, 26), rust * 0.85)
    worn = smooth(noise(seed=seed + 2, beta=2.5, ax=0.4, ay=2.5), 0.6, 0.8)
    alb = mix(base, col(150, 148, 140), lug * (0.3 + 0.6 * worn))
    save(name, alb, lug * 4 + n1 * 0.4, 2.0, rough=np.clip(0.7 - lug * worn * 0.4, 0, 1), phys="steel", metal=0.6, size=1.0)


def steel_paint(name, seed, paint, rustk=0.5):
    n1 = noise(seed=seed, beta=2.0)
    streak = noise(seed=seed + 1, beta=2.0, ax=6.0, ay=0.6)
    pc = np.asarray(paint)
    alb = mix(pc, pc * 1.3, n1 * 0.6)
    rust = smooth(noise(seed=seed + 2, beta=2.2) * 0.7 + streak * 0.4, 1.0 - rustk * 0.6, 1.15 - rustk * 0.6)
    alb = mix(alb, mix(col(90, 44, 22), col(140, 72, 34), n1), rust)
    alb = mix(alb, col(40, 36, 32), smooth(streak, 0.75, 0.95) * 0.4)
    save(name, alb, n1 + rust * 0.8, 2.0, phys="steel", rough=0.65, metal=0.3, size=1.5)


def hazard(name, seed):
    y, x = np.mgrid[0:N, 0:N] / N
    s = ((x + y) * 8) % 1.0 < 0.5
    alb = np.where(s[..., None], col(190, 150, 30), col(24, 24, 22))
    n1 = noise(seed=seed, beta=2.0)
    alb = mix(alb, col(110, 60, 30), smooth(n1, 0.65, 0.85) * 0.7)
    alb = mix(alb, col(70, 66, 60), smooth(noise(seed=seed + 1, beta=1.5), 0.6, 0.8) * 0.4)
    save(name, alb, n1, 1.0, phys="steel", rough=0.6, metal=0.2, size=1.0)


def grate(name, seed):
    """Steel bar grating (walkways, stair treads): 30 x 100 mm openings, see-through (alpha)."""
    y, x = np.mgrid[0:N, 0:N] / N
    bars = (x * 32 % 1.0) < 0.22
    cross = (y * 10 % 1.0) < 0.06
    solid = bars | cross
    n1 = noise(seed=seed, beta=2.0)
    alb = mix(col(60, 60, 58), col(96, 92, 86), n1)
    alb = mix(alb, col(100, 50, 26), smooth(noise(seed=seed + 1, beta=2.0), 0.55, 0.8) * 0.8)
    a = np.concatenate([alb, solid[..., None].astype(np.float64)], -1)
    save(name, a, solid * 3.0 + n1 * 0.3, 2.0, phys="steel", rough=0.6, metal=0.5, size=1.0, alpha="scissor", two_sided=True)


def chain_link(name, seed):
    y, x = np.mgrid[0:N, 0:N] / N
    k = 20
    u = (x * k) % 1.0
    v = (y * k) % 1.0
    d1 = np.abs(u - v)
    d2 = np.abs(u + v - 1)
    wire = (np.minimum(d1, 1 - d1) < 0.06) | (np.minimum(d2, 1 - d2) < 0.06)
    n1 = noise(seed=seed, beta=2.0)
    alb = mix(col(120, 124, 124), col(150, 80, 40), smooth(n1, 0.55, 0.8))
    a = np.concatenate([alb, wire[..., None].astype(np.float64)], -1)
    save(name, a, wire * 2.0, 2.0, phys="blocker", rough=0.5, metal=0.6, size=2.0, alpha="scissor", two_sided=True)


# ------------------------------------------------------------------ fabric, plastic, rubber, refuse

def tarp(name, seed, c1):
    y, x = np.mgrid[0:N, 0:N] / N
    weave = ((np.sin(x * math.tau * 128) * np.sin(y * math.tau * 128)) * 0.5 + 0.5)
    crease = noise(seed=seed, beta=2.6)
    folds = np.abs(noise(seed=seed + 1, beta=2.2, lo=2) - 0.5) * 2
    alb = mix(np.asarray(c1), np.asarray(c1) * 0.6, smooth(folds, 0.0, 0.25) * 0.4 + crease * 0.4)
    alb *= (0.95 + 0.05 * weave)[..., None]
    dirt = smooth(noise(seed=seed + 2, beta=2.2, ax=0.5, ay=2.0), 0.55, 0.85)
    alb = mix(alb, col(60, 56, 48), dirt * 0.55)
    hgt = crease * 3 + (1 - smooth(folds, 0, 0.2)) * 1.5 + weave * 0.2
    save(name, alb, hgt, 2.0, phys="fabric", rough=0.7, size=3.0, two_sided=True)


def banner(name, seed, lines, bg, fg, accent):
    """A printed tarpaulin banner, sun-faded and creased (fit to its face). Made-up businesses and a barangay fiesta."""
    W, H = 768, 384
    im = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, W, 54], fill=accent)
    d.rectangle([0, H - 40, W, H], fill=accent)
    yy = 70
    for txt, size, c in lines:
        f = font(size)
        tw = d.textlength(txt, font=f)
        d.text(((W - tw) / 2, yy), txt, fill=c if c else fg, font=f)
        yy += int(size * 1.08)
    for gx in (14, W - 14):   # grommets
        for gy in (14, H - 14):
            d.ellipse([gx - 7, gy - 7, gx + 7, gy + 7], fill=(190, 190, 180))
    alb = np.asarray(im).astype(np.float64) / 255.0
    fade = noise((H, W), seed=seed, beta=2.0)
    alb = mix(alb, col(200, 196, 186), smooth(fade, 0.4, 1.0) * 0.45)
    crease = np.abs(noise((H, W), seed=seed + 1, beta=2.2, lo=2) - 0.5) * 2
    alb *= (0.8 + 0.2 * smooth(crease, 0, 0.3))[..., None]
    alb = mix(alb, col(70, 64, 54), smooth(noise((H, W), seed=seed + 2, beta=2.4, ax=0.5, ay=3), 0.6, 0.9) * 0.5)
    save(name, alb, smooth(crease, 0, 0.3) * 2.0, 1.5, phys="fabric", rough=0.75, size=3.0, fit=True, two_sided=True)


def sign(name, seed, lines, bg, fg, w=640, h=256, board="metal", border=None):
    """A hand-painted shop sign (fit to its face)."""
    im = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(im)
    if border:
        d.rectangle([6, 6, w - 7, h - 7], outline=border, width=8)
    tot = sum(int(s * 1.05) for _, s, _ in lines)
    yy = (h - tot) / 2
    for txt, size, c in lines:
        f = font(size)
        tw = d.textlength(txt, font=f)
        d.text(((w - tw) / 2, yy), txt, fill=c if c else fg, font=f)
        yy += int(size * 1.05)
    alb = np.asarray(im).astype(np.float64) / 255.0
    n1 = noise((h, w), seed=seed, beta=2.0)
    alb = mix(alb, col(110, 100, 86), smooth(n1, 0.55, 0.95) * 0.45)
    rust = smooth(noise((h, w), seed=seed + 1, beta=2.2, ax=0.5, ay=3.0), 0.62, 0.85)
    alb = mix(alb, col(100, 54, 28) if board == "metal" else col(70, 56, 40), rust * 0.75)
    save(name, alb, n1 + rust, 1.5, phys="sheet_metal" if board == "metal" else "plywood", rough=0.7, size=2.0, fit=True)


def neon(name, c):
    alb = fill((64, 64), np.asarray(c))
    save(name, alb, None, phys="glass", rough=0.2, emit=6.0, size=1.0, unshaded=True)


def flat(name, c, phys, rough=0.8, size=1.0, seed=0, metal=0.0, var=0.15):
    n1 = noise(seed=seed, beta=2.0)
    alb = mix(np.asarray(c) * (1 - var), np.asarray(c) * (1 + var), n1)
    save(name, alb, n1 * 0.5, 1.0, phys=phys, rough=rough, size=size, metal=metal)


def sack(name, seed):
    y, x = np.mgrid[0:N, 0:N] / N
    weave = (np.sin(x * math.tau * 90) * 0.5 + 0.5) * (np.sin(y * math.tau * 90 + 1.0) * 0.5 + 0.5)
    n1 = noise(seed=seed, beta=2.2)
    alb = mix(col(196, 188, 164), col(150, 140, 116), n1)
    band = (np.abs(y - 0.5) < 0.08)
    alb = np.where(band[..., None], mix(col(40, 90, 40), alb, 0.45), alb)
    alb = mix(alb, col(90, 76, 56), smooth(noise(seed=seed + 1, beta=2.5), 0.6, 0.85) * 0.6)
    alb *= (0.85 + 0.15 * weave)[..., None]
    save(name, alb, weave * 0.6 + n1 * 2.0, 2.0, phys="sand", rough=0.9, size=1.0)


def pallet(name, seed):
    y, x = np.mgrid[0:N, 0:N] / N
    slat = (x * 5 % 1.0) < 0.72
    grain = noise(seed=seed, beta=2.0, ax=0.3, ay=8.0)
    alb = mix(col(160, 130, 90), col(120, 96, 66), grain)
    alb = mix(alb, col(110, 108, 100), smooth(noise(seed=seed + 1, beta=2.0), 0.4, 0.8) * 0.6)
    alb = np.where(slat[..., None], alb, col(12, 10, 8))
    save(name, alb, slat * 3 + grain, 2.0, phys="wood", rough=0.85, size=1.2)


def timber(name, seed):
    grain = noise(seed=seed, beta=2.0, ax=0.25, ay=10.0)
    n1 = noise(seed=seed + 1, beta=2.2)
    alb = mix(col(96, 76, 56), col(64, 50, 38), grain)
    alb = mix(alb, col(104, 100, 92), smooth(n1, 0.4, 0.8) * 0.5)
    save(name, alb, grain * 2, 2.0, phys="wood", rough=0.85, size=1.0)


def tire(name, seed):
    y, x = np.mgrid[0:N, 0:N] / N
    tread = ((x * 24 + np.abs(((y * 4) % 1.0) - 0.5) * 2) % 1.0) < 0.35
    n1 = noise(seed=seed, beta=2.0)
    alb = mix(col(22, 22, 22), col(40, 40, 40), n1)
    alb = np.where(tread[..., None], alb * 0.55, alb)
    alb = mix(alb, col(80, 70, 56), smooth(noise(seed=seed + 1, beta=2.0), 0.6, 0.85) * 0.5)
    save(name, alb, (~tread) * 2.0 + n1, 2.0, phys="fabric", rough=0.85, size=1.0)


def trash(name, seed):
    r = np.random.default_rng(seed)
    im = Image.new("RGB", (N, N), (40, 36, 30))
    d = ImageDraw.Draw(im)
    pal = [(30, 30, 34), (20, 60, 130), (180, 30, 30), (220, 220, 210), (60, 130, 60), (210, 180, 60), (90, 70, 50), (150, 150, 150)]
    for _ in range(700):
        cx, cy = r.uniform(-20, N + 20, 2)
        rw, rh = r.uniform(6, 36), r.uniform(4, 24)
        c = pal[r.integers(len(pal))]
        sh = r.uniform(0.4, 1.0)
        d.ellipse([cx - rw, cy - rh, cx + rw, cy + rh], fill=tuple(int(v * sh) for v in c))
    alb = np.asarray(im).astype(np.float64) / 255.0
    n1 = noise(seed=seed, beta=1.5)
    alb *= (0.6 + 0.5 * n1)[..., None]
    save(name, alb, n1 * 4, 2.0, phys="fabric", rough=0.75, size=2.0)


def curtain(name, seed, base, flower):
    W, H = 256, 512
    r = np.random.default_rng(seed)
    im = Image.new("RGB", (W, H), base)
    d = ImageDraw.Draw(im)
    for _ in range(60):
        cx, cy = r.uniform(0, W), r.uniform(0, H)
        rr = r.uniform(6, 14)
        for k in range(5):
            a = k * math.tau / 5
            d.ellipse([cx + math.cos(a) * rr - rr * 0.6, cy + math.sin(a) * rr - rr * 0.6, cx + math.cos(a) * rr + rr * 0.6, cy + math.sin(a) * rr + rr * 0.6], fill=flower)
        d.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], fill=(230, 210, 80))
    alb = np.asarray(im).astype(np.float64) / 255.0
    y, x = np.mgrid[0:H, 0:W] / np.array([H, W])[:, None, None]
    folds = np.sin(x * math.tau * 7 + noise((H, W), seed=seed, beta=2.0) * 2) * 0.5 + 0.5
    alb *= (0.65 + 0.35 * folds)[..., None]
    alb = mix(alb, col(60, 50, 40), smooth(noise((H, W), seed=seed + 1, beta=2.0), 0.6, 0.9) * 0.4)
    save(name, alb, folds * 3, 2.0, phys="fabric", rough=0.85, size=1.0, fit=True, two_sided=True)


def laundry(name, seed):
    r = np.random.default_rng(seed)
    im = Image.new("RGB", (N, N), (200, 200, 190))
    d = ImageDraw.Draw(im)
    x = 0
    pal = [(200, 40, 50), (40, 80, 170), (230, 230, 220), (240, 200, 60), (60, 150, 90), (230, 120, 160), (40, 40, 44), (120, 70, 140)]
    while x < N:
        w = int(r.uniform(40, 110))
        c = pal[r.integers(len(pal))]
        d.rectangle([x, 0, x + w, N], fill=c)
        if r.random() < 0.4:
            c2 = pal[r.integers(len(pal))]
            for yy in range(0, N, 24):
                d.rectangle([x, yy, x + w, yy + 9], fill=c2)
        x += w + int(r.uniform(4, 30))
    alb = np.asarray(im).astype(np.float64) / 255.0
    alb = mix(alb, col(180, 176, 166), 0.25)
    folds = noise(seed=seed, beta=2.4, ax=0.3, ay=3)
    alb *= (0.7 + 0.3 * folds)[..., None]
    save(name, alb, folds * 3, 2.0, phys="fabric", rough=0.85, size=2.0, two_sided=True)


def tool_tex(name, c, label, phys="none"):
    W = 128
    im = Image.new("RGB", (W, W), c)
    d = ImageDraw.Draw(im)
    for k in range(-W, W, 16):
        d.line([(k, 0), (k + W, W)], fill=tuple(int(v * 0.7) for v in c), width=4)
    f = font(28)
    tw = d.textlength(label, font=f)
    d.text(((W - tw) / 2, 46), label, fill=(255, 255, 255), font=f)
    save(name, np.asarray(im).astype(np.float64) / 255.0, None, phys=phys, size=2.0, tool=True)


# ------------------------------------------------------------------ the set

def build(only=None):
    jobs = {
        "yero_rust": lambda: yero("yero_rust", 11),
        "yero_old": lambda: yero("yero_old", 17, rusty=0.95),
        "yero_blue": lambda: yero("yero_blue", 23, col(46, 92, 130), 0.45),
        "yero_green": lambda: yero("yero_green", 29, col(54, 104, 70), 0.5),
        "yero_red": lambda: yero("yero_red", 31, col(130, 44, 34), 0.4),
        "plywood": lambda: plywood("plywood", 41),
        "planks": lambda: planks("planks", 43, [col(60, 110, 150), col(170, 60, 50), col(200, 200, 190), col(70, 130, 80)]),
        "planks_dark": lambda: planks("planks_dark", 47, [col(40, 40, 44), col(110, 50, 40)]),
        "chb_raw": lambda: chb("chb_raw", 51),
        "chb_mint": lambda: chb("chb_mint", 53, col(150, 190, 168)),
        "chb_pink": lambda: chb("chb_pink", 57, col(206, 150, 156)),
        "chb_yellow": lambda: chb("chb_yellow", 59, col(214, 186, 110)),
        "chb_white": lambda: chb("chb_white", 61, col(200, 198, 188)),
        "concrete_rough": lambda: concrete_rough("concrete_rough", 63),
        "concrete_wet": lambda: concrete_wet("concrete_wet", 67),
        "mud": lambda: mud("mud", 71),
        "asphalt": lambda: asphalt("asphalt", 73),
        "water": lambda: water("water", 79),
        "gravel": lambda: gravel("gravel", 83),
        "container_roof": lambda: container_roof("container_roof", 89),
        "tread_plate": lambda: tread_plate("tread_plate", 97),
        "steel_rust": lambda: steel_paint("steel_rust", 101, col(90, 52, 36), 0.9),
        "steel_yellow": lambda: steel_paint("steel_yellow", 103, col(200, 160, 40), 0.45),
        "steel_grey": lambda: steel_paint("steel_grey", 107, col(96, 100, 100), 0.5),
        "steel_blue": lambda: steel_paint("steel_blue", 109, col(40, 70, 110), 0.4),
        "hazard": lambda: hazard("hazard", 113),
        "grate": lambda: grate("grate", 127),
        "chain_link": lambda: chain_link("chain_link", 131),
        "tarp_blue": lambda: tarp("tarp_blue", 137, col(34, 86, 160)),
        "tarp_orange": lambda: tarp("tarp_orange", 139, col(196, 96, 36)),
        "tarp_green": lambda: tarp("tarp_green", 149, col(50, 110, 70)),
        "tarp_black": lambda: tarp("tarp_black", 151, col(30, 32, 34)),
        "sack": lambda: sack("sack", 157),
        "pallet": lambda: pallet("pallet", 163),
        "timber": lambda: timber("timber", 167),
        "tire": lambda: tire("tire", 173),
        "trash": lambda: trash("trash", 179),
        "plastic_white": lambda: flat("plastic_white", col(214, 214, 206), "fabric", 0.45, 1.0, 181),
        "plastic_blue": lambda: flat("plastic_blue", col(34, 80, 150), "fabric", 0.45, 1.0, 191),
        "plastic_red": lambda: flat("plastic_red", col(160, 36, 34), "fabric", 0.45, 1.0, 193),
        "rubber": lambda: flat("rubber", col(26, 26, 26), "fabric", 0.8, 1.0, 197),
        "paint_white": lambda: flat("paint_white", col(196, 194, 184), "concrete", 0.8, 1.0, 199),
        "wood_red": lambda: flat("wood_red", col(140, 40, 36), "wood", 0.7, 1.0, 211),
        "curtain_rose": lambda: curtain("curtain_rose", 223, (150, 40, 70), (230, 150, 170)),
        "curtain_blue": lambda: curtain("curtain_blue", 227, (40, 70, 140), (230, 230, 240)),
        "laundry": lambda: laundry("laundry", 229),
        "neon_pink": lambda: neon("neon_pink", col(255, 60, 170)),
        "neon_cyan": lambda: neon("neon_cyan", col(60, 230, 255)),
        "neon_green": lambda: neon("neon_green", col(80, 255, 110)),
        "glow_warm": lambda: neon("glow_warm", col(255, 190, 110)),
        "glow_cool": lambda: neon("glow_cool", col(210, 235, 255)),
        "glow_red": lambda: neon("glow_red", col(255, 40, 30)),
        "clip": lambda: tool_tex("clip", (150, 40, 150), "CLIP"),
        "skip": lambda: tool_tex("skip", (40, 120, 150), "SKIP"),
        # stair ramps: invisible but solid, sounding and stopping rounds like the steps they cover
        "clip_concrete": lambda: tool_tex("clip_concrete", (150, 90, 40), "RAMP", phys="concrete"),
        "clip_wood": lambda: tool_tex("clip_wood", (120, 80, 40), "RAMP", phys="wood"),
        "clip_steel": lambda: tool_tex("clip_steel", (90, 90, 120), "RAMP", phys="steel"),
    }
    for k, c in CONTAINER_COLOURS.items():
        jobs["container_" + k] = (lambda k=k, c=c: container_side("container_" + k, 300 + len(k) * 7, col(*c)))
        jobs["container_door_" + k] = (lambda k=k, c=c: container_door("container_door_" + k, 400 + len(k) * 7, col(*c)))
    banners = {
        "banner_fiesta": (["MALIGAYANG PIESTA!", 64, None], ["BRGY. KARGAMENTO", 72, (255, 240, 120)], ["MAYO 15 • PALIGSAHAN • SAYAWAN", 40, None], (150, 30, 40), (255, 255, 255), (30, 40, 110)),
        "banner_bigasan": (["BIGASAN NI ALING DORY", 70, None], ["PATAS NA TIMBANG", 52, (40, 40, 40)], ["DINORADO • SINANDOMENG • MALAGKIT", 34, None], (240, 220, 120), (150, 30, 30), (40, 110, 60)),
        "banner_lechon": (["LITSON MANOK", 84, None], ["P199 LANG!", 70, (255, 230, 80)], ["BUKAS HANGGANG 9 NG GABI", 38, None], (170, 60, 20), (255, 255, 255), (40, 30, 26)),
        "banner_paupahan": (["PAUPAHAN", 96, None], ["KUWARTO • TUBIG AT KURYENTE KASAMA", 38, None], ["MAGTANONG SA LOOB", 42, (255, 255, 255)], (230, 230, 220), (20, 60, 140), (20, 60, 140)),
    }
    for k, (l1, l2, l3, bg, fg, ac) in banners.items():
        jobs[k] = (lambda k=k, l1=l1, l2=l2, l3=l3, bg=bg, fg=fg, ac=ac: banner(k, 500 + len(k), [tuple(l1), tuple(l2), tuple(l3)], bg, fg, ac))
    signs = {
        "sign_sarisari": ([("SARI-SARI STORE", 88, None), ("ALING TESS", 52, (240, 220, 90))], (30, 90, 60), (250, 250, 240), "metal", (240, 220, 90)),
        "sign_videoke": ([("VIDEOKE", 110, None), ("P5 ISANG KANTA", 46, (255, 255, 255))], (110, 20, 90), (255, 200, 60), "wood", (255, 255, 255)),
        "sign_vulcanizing": ([("VULCANIZING", 92, None), ("24 ORAS • HANGIN LIBRE", 40, None)], (210, 200, 180), (170, 30, 30), "metal", None),
        "sign_bawal": ([("BAWAL TUMAMBAY", 84, None), ("DITO", 70, None)], (230, 226, 210), (180, 20, 20), "metal", (180, 20, 20)),
        "sign_eload": ([("E-LOAD DITO", 96, None), ("YELO • TUBIG • ICE CANDY", 42, (40, 40, 40))], (250, 210, 50), (30, 30, 120), "wood", None),
        "sign_yard": ([("FREIGHT DELIGHT", 82, None), ("CONTAINER YARD • NO ENTRY", 44, None), ("AUTHORIZED PERSONNEL ONLY", 36, (240, 210, 60))], (30, 50, 90), (240, 240, 235), "metal", (240, 210, 60)),
        "sign_talyer": ([("TALYER NI MANG BOY", 80, None), ("WELDING • PINTURA • KAHA", 42, None)], (30, 30, 30), (240, 200, 40), "metal", (240, 200, 40)),
        "sign_pier": ([("PANTALAN 3", 104, None), ("BAWAL MAGTAPON NG BASURA", 38, None)], (200, 200, 190), (20, 50, 110), "metal", (20, 50, 110)),
        "sign_shrine": ([("STO. NIÑO", 92, (255, 230, 120)), ("IPAGPANALANGIN MO KAMI", 40, None)], (40, 50, 120), (240, 240, 240), "wood", (255, 230, 120)),
    }
    for k, (lines, bg, fg, board, border) in signs.items():
        jobs[k] = (lambda k=k, lines=lines, bg=bg, fg=fg, board=board, border=border: sign(k, 600 + len(k), lines, bg, fg, board=board, border=border))
    for k, fn in jobs.items():
        if only and k not in only:
            continue
        fn()
        print("  " + k)
    # surfaces.json keeps entries for maps not rebuilt this run
    path = OUT / "surfaces.json"
    old = json.loads(path.read_text()) if path.exists() else {}
    old.update(SURFACES)
    path.write_text(json.dumps(dict(sorted(old.items())), indent=1))
    print("wrote %d surfaces to %s" % (len(SURFACES), path))


def contact_sheet(path):
    files = sorted((OUT / "textures" / "freight").glob("*.png"))
    cols = 8
    t = 160
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * t, rows * (t + 18)), (20, 20, 20))
    d = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB").resize((t, t))
        x, y = (i % cols) * t, (i // cols) * (t + 18)
        sheet.paste(im, (x, y))
        d.text((x + 3, y + t + 2), f.stem[:24], fill=(220, 220, 220), font=font(14, "Barlow-Regular.ttf"))
    sheet.save(path)
    print("sheet:", path)


if __name__ == "__main__":
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = set(a.split("=", 1)[1].split(","))
    build(only)
    for a in sys.argv[1:]:
        if a.startswith("--sheet"):
            contact_sheet(a.split("=", 1)[1] if "=" in a else str(ROOT / "work" / "freight_textures.png"))
