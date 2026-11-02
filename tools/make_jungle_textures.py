"""Textures for Hidden Forest (r27), the ancient jungle map:

1. "jungle/..." map textures (map files' brushes, game/assets/maps/textures/jungle/): temple stone, slopes, stairs,
   floors, red and white stucco, tezontle, cliff rock, wood, from Poly Haven (CC0) sets graded for an overgrown ruin;
   carved reliefs drawn here (step-fret mosaic, feathered-serpent scales, skull rack, day-sign glyphs, the sun disc)
   and laid on that stone; the torch wrap; the hanging vine strand (RGBA).
2. Terrain3D texture sets for the ground (game/maps/hidden_forest/terrain/tex/): each set channel-packed the way
   Terrain3D wants it, <name>_ah.png (albedo RGB, height A) and <name>_nr.png (OpenGL normal RGB with the AO baked
   in as Terrain3D's packer does, roughness A), 1024 px.

    python -I tools/make_jungle_textures.py [--only=name,name] [--terrain-only] [--maps-only]

Then `bash tools/import.sh`. Poly Haven displacement maps (for the height channel) are downloaded once into
tools/cache/ph_disp/.
"""
import importlib.util
import json
import math
import os
import sys
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
spec = importlib.util.spec_from_file_location("freight_tex", HERE / "make_freight_textures.py")
ft = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ft)
col, mix, noise, smooth, blobs, blur = ft.col, ft.mix, ft.noise, ft.smooth, ft.blobs, ft.blur

PH = ROOT / "game" / "assets" / "thirdparty" / "polyhaven" / "textures"
DISP = ROOT / "tools" / "cache" / "ph_disp"
TERRAIN_OUT = ROOT / "game" / "maps" / "hidden_forest" / "terrain" / "tex"
S = 1024
UA = {"User-Agent": "AetherionProject/0.1 (asset fetch; contact via project owner)"}


# ------------------------------------------------------------------ loading

def load_rgb(pid, name="albedo", size=S):
    for ext in ("jpg", "png"):
        p = PH / pid / f"{name}.{ext}"
        if p.exists():
            im = Image.open(p).convert("RGB")
            if im.size != (size, size):
                im = im.resize((size, size), Image.LANCZOS)
            return np.asarray(im).astype(np.float32) / 255.0
    raise FileNotFoundError(f"{pid}/{name}")


def load_gray(pid, name, size=S, default=None):
    for ext in ("jpg", "png"):
        p = PH / pid / f"{name}.{ext}"
        if p.exists():
            im = Image.open(p).convert("L")
            if im.size != (size, size):
                im = im.resize((size, size), Image.LANCZOS)
            return np.asarray(im).astype(np.float32) / 255.0
    return default


def disp(pid, size=S):
    """The Poly Haven displacement (height) map at 1k, downloaded once; None if the set has none."""
    DISP.mkdir(parents=True, exist_ok=True)
    out = DISP / f"{pid}.png"
    if not out.exists():
        try:
            req = urllib.request.Request(f"https://api.polyhaven.com/files/{pid}", headers=UA)
            files = json.load(urllib.request.urlopen(req, timeout=60))
            d = files.get("Displacement", {}).get("1k", {})
            e = d.get("png") or d.get("jpg")
            if not e:
                return None
            req = urllib.request.Request(e["url"], headers=UA)
            data = urllib.request.urlopen(req, timeout=120).read()
            tmp = out.with_suffix(".part")
            tmp.write_bytes(data)
            os.replace(tmp, out)
        except Exception as ex:  # keep going: height from luminance
            print("  no displacement for", pid, ex)
            return None
    im = Image.open(out).convert("L")
    if im.size != (size, size):
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0


def normal_rgb(pid, size=S):
    for ext in ("jpg", "png"):
        p = PH / pid / f"normal.{ext}"
        if p.exists():
            im = Image.open(p).convert("RGB")
            if im.size != (size, size):
                im = im.resize((size, size), Image.LANCZOS)
            return np.asarray(im).astype(np.float32) / 255.0
    return None


def grade(a, sat=1.0, gain=1.0, tint=(1.0, 1.0, 1.0), gamma=1.0):
    lum = (a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114)[..., None]
    out = lum + (a - lum) * sat
    out = np.clip(out * gain * np.array(tint, np.float32), 0, 1)
    return out ** gamma


def save_png(arr, path, mode):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8), mode).save(path, optimize=True)


# ------------------------------------------------------------------ map textures (brushes)

SURF = {}


def ph_map(name, pid, phys="concrete", size=2.0, sat=1.0, gain=1.0, tint=(1, 1, 1), moss=0.0, seed=0, rough=0.88,
           red=0.0, white=0.0):
    """A Poly Haven set as a map texture: graded, with moss in the low parts (moss), patches of red stucco (red) or
    lime wash (white) where the set is high, its own normal map kept."""
    a = grade(load_rgb(pid), sat, gain, tint)
    h = disp(pid)
    if h is None:
        h = blur(a.mean(axis=2), 2.0)
    if moss > 0:
        m = smooth(noise((S, S), beta=2.0, seed=seed) * 0.6 + (1 - h) * 0.7, 0.55, 0.85) * moss
        mc = mix(col(48, 62, 30), col(78, 96, 42), noise((S, S), beta=1.2, seed=seed + 1))
        a = mix(a, mc * (0.6 + 0.6 * a.mean(axis=2, keepdims=True)), m)
    if red > 0 or white > 0:
        # Stucco holds on in patches; where it has flaked off, the stone shows. The paint takes the stone's shading.
        nk = noise((S, S), beta=2.4, seed=seed + 5)
        keep = smooth(nk * 0.85 + (h - h.mean()) * 0.6, 0.42, 0.52)
        paint = col(128, 40, 28) if red > 0 else col(206, 198, 180)
        amt = red if red > 0 else white
        shade = 0.55 + 0.9 * (a.mean(axis=2, keepdims=True) / max(float(a.mean()), 1e-3)) * 0.5
        pv = paint * shade * (0.8 + 0.3 * noise((S, S), beta=0.9, seed=seed + 6)[..., None])
        stain = smooth(noise((S, S), beta=1.6, seed=seed + 7, ax=0.4, ay=3.0), 0.55, 0.85)
        pv = mix(pv, pv * col(70, 74, 60) * 2.2, stain * 0.5)
        a = mix(a, pv, keep * amt)
    ft.FOLDER = "jungle"
    out = ft.OUT
    save_png(a, out / "textures" / "jungle" / f"{name}.png", "RGB")
    n = normal_rgb(pid)
    if n is not None:
        save_png(n, out / "normals" / "jungle" / f"{name}_normal.png", "RGB")
    r = load_gray(pid, "roughness")
    if r is not None:
        save_png(np.clip(r * 0.9 + 0.1, 0, 1), out / "roughness" / "jungle" / f"{name}_rough.png", "L")
    SURF["jungle/" + name] = {"phys": phys, "rough": rough, "metal": 0.0, "size": size, "normal": n is not None,
                              "rough_map": r is not None, "px": [S, S]}


def relief_map(name, base_pid, height, size, strength=6.0, pigment=None, moss=0.25, seed=0, phys="concrete",
               tint=(0.95, 0.95, 0.92), fit=False):
    """A carved relief on stone: height (S x S, 0 = background face, 1 = raised) shades the grooves (ambient
    occlusion), bends the stone's own normals, keeps old pigment in the recesses."""
    stone = grade(load_rgb(base_pid), 0.75, 1.0, tint)
    sh = disp(base_pid)
    if sh is None:
        sh = blur(stone.mean(axis=2), 2.0)
    hb = blur(height, 1.6)
    cav = np.clip(blur(hb, 9.0) - hb, 0, 1)                   # recesses beside raised parts
    edge = np.clip(hb - blur(hb, 3.0), 0, 1)                 # worn highlights on the carving's edges
    a = stone * (1.0 - np.clip(cav * 2.6, 0, 0.62))[..., None]
    a = a + edge[..., None] * 0.22
    if pigment is not None:
        pm = smooth(cav * 3.0 + noise((S, S), beta=2.0, seed=seed) * 0.4, 0.35, 0.7)
        a = mix(a, np.array(pigment, np.float32) / 255.0 * (0.7 + 0.4 * stone.mean(axis=2, keepdims=True)), pm * 0.55)
    if moss > 0:
        m = smooth(cav * 2.5 + noise((S, S), beta=1.8, seed=seed + 3) * 0.6, 0.55, 0.9) * moss
        a = mix(a, col(52, 66, 32) * (0.7 + 0.5 * stone.mean(axis=2, keepdims=True)), m)
    total = hb * 1.0 + sh * 0.25
    nm = ft.normal_from(total * 40.0, strength)
    ft.FOLDER = "jungle"
    save_png(a, ft.OUT / "textures" / "jungle" / f"{name}.png", "RGB")
    save_png(nm, ft.OUT / "normals" / "jungle" / f"{name}_normal.png", "RGB")
    rec = {"phys": phys, "rough": 0.86, "metal": 0.0, "size": size, "normal": True, "rough_map": False, "px": [S, S]}
    if fit:
        rec["fit"] = True
    SURF["jungle/" + name] = rec


def _canvas():
    im = Image.new("L", (S, S), 0)
    return im, ImageDraw.Draw(im)


def h_fret():
    """Step-fret mosaic (xicalcoliuhqui): rows of stepped hooks, each row mirrored, framed by raised bands. Tiles
    both ways (one repeat = two rows)."""
    im, d = _canvas()
    rows = 2
    rh = S // rows
    for r in range(rows):
        y0 = r * rh
        d.rectangle([0, y0, S, y0 + 40], fill=255)
        d.rectangle([0, y0 + rh - 40, S, y0 + rh], fill=255)
        cells = 4
        cw = S // cells
        for c in range(cells):
            x0 = c * cw
            flip = (c + r) % 2 == 1
            t = 34
            # the stepped ramp
            steps = 4
            for k in range(steps):
                sx = x0 + 30 + k * (cw - 60) // (steps * 2)
                sy = y0 + rh - 70 - k * (rh - 160) // steps
                d.rectangle([sx, sy, sx + (cw - 60) // (steps * 2) + t, y0 + rh - 70], fill=255)
            # the hook (a squared spiral) at the top of the ramp
            cx = x0 + cw // 2 + 40
            cy = y0 + rh // 2 - 10
            sz = 120
            for k in range(3):
                s = sz - k * 40
                if s <= 10:
                    break
                d.rectangle([cx - s, cy - s, cx + s, cy - s + t], fill=255)
                d.rectangle([cx + s - t, cy - s, cx + s, cy + s], fill=255)
                d.rectangle([cx - s + 40, cy + s - t, cx + s, cy + s], fill=255)
            if flip:
                box = (x0, y0 + 40, x0 + cw, y0 + rh - 40)
                part = im.crop(box).transpose(Image.FLIP_LEFT_RIGHT)
                im.paste(part, box)
                d = ImageDraw.Draw(im)
    return np.asarray(im).astype(np.float32) / 255.0


def h_scales():
    """A feathered serpent's body: overlapping scale rows, a band of feathers every third row."""
    im, d = _canvas()
    sc = 128
    for r in range(-1, S // (sc // 2) + 2):
        y = r * sc // 2
        off = (r % 2) * sc // 2
        feather = r % 6 == 0
        for c in range(-1, S // sc + 2):
            x = c * sc + off
            if feather:
                for k in range(5):
                    fx = x + k * sc // 5
                    d.polygon([(fx, y), (fx + sc // 10, y + sc // 2 + 10), (fx + sc // 5, y)], fill=200)
            else:
                d.pieslice([x, y - sc // 2, x + sc, y + sc // 2], 0, 180, fill=255)
                d.pieslice([x + 14, y - sc // 2 + 6, x + sc - 14, y + sc // 2 - 14], 0, 180, fill=150)
    return np.asarray(im.filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32) / 255.0


def h_skulls():
    """A tzompantli wall: rows of carved skulls, 4 x 4 a repeat, slightly irregular."""
    im, d = _canvas()
    n = 4
    cs = S // n
    rng = np.random.default_rng(31)
    for r in range(n):
        for c in range(n):
            x0 = c * cs + (cs // 2 if r % 2 else 0)
            y0 = r * cs
            for wrap in (0, -S):
                cx = (x0 + cs // 2 + wrap) % (S + cs) - (cs // 2 if r % 2 and c == n - 1 else 0)
                cx = x0 + cs // 2 + wrap
                cy = y0 + cs // 2 + int(rng.integers(-6, 7))
                w = cs * 0.36
                d.ellipse([cx - w, cy - w * 1.05, cx + w, cy + w * 0.75], fill=235)            # cranium
                d.rectangle([cx - w * 0.62, cy + w * 0.35, cx + w * 0.62, cy + w * 1.05], fill=220)  # jaw
                for ex in (-1, 1):
                    d.ellipse([cx + ex * w * 0.42 - w * 0.24, cy - w * 0.12, cx + ex * w * 0.42 + w * 0.24, cy + w * 0.3], fill=40)
                d.polygon([(cx, cy + w * 0.3), (cx - w * 0.12, cy + w * 0.55), (cx + w * 0.12, cy + w * 0.55)], fill=60)
                for k in range(-3, 4):
                    tx = cx + k * w * 0.16
                    d.line([(tx, cy + w * 0.68), (tx, cy + w * 1.0)], fill=110, width=5)
    return np.asarray(im.filter(ImageFilter.GaussianBlur(2.0))).astype(np.float32) / 255.0


def h_glyphs():
    """Day-sign cartouches: a grid of framed glyphs (sun, wind, house, flint, movement, water), 3 x 3 a repeat."""
    im, d = _canvas()
    n = 3
    cs = S // n
    kinds = ["sun", "wind", "house", "flint", "move", "water", "eye", "house", "sun"]
    for i in range(n * n):
        r, c = divmod(i, n)
        x0, y0 = c * cs, r * cs
        m = 18
        d.rectangle([x0 + m, y0 + m, x0 + cs - m, y0 + cs - m], fill=255)
        d.rectangle([x0 + m + 26, y0 + m + 26, x0 + cs - m - 26, y0 + cs - m - 26], fill=60)
        cx, cy = x0 + cs // 2, y0 + cs // 2
        k = kinds[i]
        rr = cs * 0.28
        if k == "sun":
            for a in range(8):
                ang = a * math.pi / 4
                d.polygon([(cx + math.cos(ang) * rr * 1.25, cy + math.sin(ang) * rr * 1.25),
                           (cx + math.cos(ang + 0.25) * rr * 0.6, cy + math.sin(ang + 0.25) * rr * 0.6),
                           (cx + math.cos(ang - 0.25) * rr * 0.6, cy + math.sin(ang - 0.25) * rr * 0.6)], fill=230)
            d.ellipse([cx - rr * 0.6, cy - rr * 0.6, cx + rr * 0.6, cy + rr * 0.6], fill=250)
            d.ellipse([cx - rr * 0.3, cy - rr * 0.3, cx + rr * 0.3, cy + rr * 0.3], fill=120)
        elif k == "wind":
            for s in range(4):
                d.arc([cx - rr + s * 12, cy - rr + s * 12, cx + rr - s * 12, cy + rr - s * 12], 30 + s * 60, 300 + s * 20, fill=240, width=14)
        elif k == "house":
            d.polygon([(cx - rr, cy), (cx, cy - rr), (cx + rr, cy)], fill=240)
            d.rectangle([cx - rr * 0.8, cy, cx + rr * 0.8, cy + rr], fill=230)
            d.rectangle([cx - rr * 0.25, cy + rr * 0.3, cx + rr * 0.25, cy + rr], fill=70)
        elif k == "flint":
            d.polygon([(cx, cy - rr * 1.1), (cx + rr * 0.6, cy), (cx, cy + rr * 1.1), (cx - rr * 0.6, cy)], fill=240)
            d.line([(cx - rr * 0.3, cy), (cx + rr * 0.3, cy)], fill=80, width=10)
            d.ellipse([cx - rr * 0.15, cy - rr * 0.5, cx + rr * 0.15, cy - rr * 0.2], fill=90)
        elif k == "move":
            d.ellipse([cx - rr * 0.4, cy - rr * 0.4, cx + rr * 0.4, cy + rr * 0.4], fill=240)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    d.rectangle([cx + sx * rr * 0.55 - rr * 0.3, cy + sy * rr * 0.55 - rr * 0.3,
                                 cx + sx * rr * 0.55 + rr * 0.3, cy + sy * rr * 0.55 + rr * 0.3], fill=215)
        elif k == "water":
            for s in range(3):
                y = cy - rr * 0.7 + s * rr * 0.7
                pts = [(cx - rr + t * rr / 8, y + math.sin(t * 1.3) * 14) for t in range(17)]
                d.line(pts, fill=240, width=16)
        elif k == "eye":
            d.ellipse([cx - rr, cy - rr * 0.55, cx + rr, cy + rr * 0.55], fill=240)
            d.ellipse([cx - rr * 0.35, cy - rr * 0.35, cx + rr * 0.35, cy + rr * 0.35], fill=70)
    return np.asarray(im.filter(ImageFilter.GaussianBlur(1.6))).astype(np.float32) / 255.0


def h_sun_disc():
    """The sun stone for a disc's face (fit once): rings of glyphs round a face, eight rays."""
    im, d = _canvas()
    c = S // 2
    for rad, val in ((500, 210), (470, 120), (440, 230), (380, 140), (350, 225), (250, 130), (225, 240), (120, 120)):
        d.ellipse([c - rad, c - rad, c + rad, c + rad], fill=val)
    for k in range(40):
        a = k * math.tau / 40
        x, y = c + math.cos(a) * 455, c + math.sin(a) * 455
        d.ellipse([x - 12, y - 12, x + 12, y + 12], fill=90)
    for k in range(20):
        a = k * math.tau / 20 + 0.1
        x, y = c + math.cos(a) * 300, c + math.sin(a) * 300
        d.rectangle([x - 26, y - 26, x + 26, y + 26], fill=245)
        d.rectangle([x - 12, y - 12, x + 12, y + 12], fill=110)
    for k in range(8):
        a = k * math.tau / 8
        d.polygon([(c + math.cos(a) * 360, c + math.sin(a) * 360), (c + math.cos(a + 0.12) * 240, c + math.sin(a + 0.12) * 240),
                   (c + math.cos(a - 0.12) * 240, c + math.sin(a - 0.12) * 240)], fill=250)
    # the face at the centre
    d.ellipse([c - 105, c - 105, c + 105, c + 105], fill=235)
    for ex in (-1, 1):
        d.ellipse([c + ex * 45 - 20, c - 40, c + ex * 45 + 20, c - 10], fill=80)
    d.polygon([(c - 30, c + 40), (c + 30, c + 40), (c, c + 85)], fill=90)
    return np.asarray(im.filter(ImageFilter.GaussianBlur(2.0))).astype(np.float32) / 255.0


def torch_wrap():
    n1 = noise((512, 512), beta=1.2, seed=71)
    y, x = np.mgrid[0:512, 0:512] / 512.0
    strips = np.sin((y * 9 + x * 2.5) * math.tau) * 0.5 + 0.5
    a = mix(col(34, 26, 18), col(66, 50, 32), n1 * 0.6 + strips * 0.4)
    char = smooth(noise((512, 512), beta=1.8, seed=72) + y * 0.4, 0.55, 0.8)
    a = mix(a, col(14, 11, 9), char)
    ft.FOLDER = "jungle"
    ft.save("torch_wrap", a, strips * 3 + n1, 2.0, phys="wood", rough=0.95, size=0.5)


def vine_strand():
    """A climbing vine for the vines pieces: a twisting stem down the middle, heart-shaped leaves alternating,
    smaller toward the tip; RGBA (alpha cut out), 256 x 1024, the strand hangs from the top."""
    W, H = 256, 1024
    big = 2
    im = Image.new("RGBA", (W * big, H * big), (0, 0, 0, 0))
    hm = Image.new("L", (W * big, H * big), 0)
    d = ImageDraw.Draw(im)
    dh = ImageDraw.Draw(hm)
    rng = np.random.default_rng(5)
    pts = []
    for k in range(0, H * big + 1, 8):
        t = k / (H * big)
        pts.append((W * big / 2 + math.sin(t * 9.0) * 14 * big + math.sin(t * 23) * 4 * big, k))
    d.line(pts, fill=(70, 62, 34, 255), width=6 * big)
    dh.line(pts, fill=200, width=6 * big)
    y = 30 * big
    side = 1
    while y < H * big - 20:
        t = y / (H * big)
        size = (46 - 22 * t) * big * rng.uniform(0.8, 1.15)
        sx = W * big / 2 + math.sin(t * 9.0) * 14 * big
        ang = side * rng.uniform(0.5, 1.0)
        cx = sx + side * size * 0.55
        cy = y + size * 0.55
        g = rng.uniform(0.75, 1.15)
        base = (int(34 * g * rng.uniform(0.9, 1.2)), int(74 * g), int(26 * g), 255)
        # heart-shaped leaf: two lobes and a tip, a midrib, the petiole to the stem
        leaf = Image.new("RGBA", (int(size * 2.4), int(size * 2.4)), (0, 0, 0, 0))
        lh = Image.new("L", leaf.size, 0)
        ld = ImageDraw.Draw(leaf)
        lhd = ImageDraw.Draw(lh)
        L = size
        o = leaf.size[0] / 2
        # a heart-shaped leaf (philodendron / pothos): the tip down, two lobes and a notch at the stalk
        half = [(0, L), (0.16, 0.78), (0.34, 0.45), (0.46, 0.1), (0.5, -0.18), (0.44, -0.42), (0.3, -0.56), (0.14, -0.55), (0, -0.42)]
        wv = rng.uniform(0.85, 1.1)
        poly = [(o + x * L * wv, o + y * L) for x, y in half] + [(o - x * L * wv, o + y * L) for x, y in reversed(half[1:-1])]
        ld.polygon(poly, fill=base)
        lhd.polygon(poly, fill=170)
        rib = (min(base[0] + 40, 255), min(base[1] + 55, 255), min(base[2] + 22, 255), 255)
        ld.line([(o, o - L * 0.42), (o, o + L * 0.92)], fill=rib, width=max(2, int(size / 16)))
        lhd.line([(o, o - L * 0.42), (o, o + L * 0.92)], fill=230, width=max(2, int(size / 16)))
        for v in range(4):
            vy = o - L * 0.3 + v * L * 0.3
            for s in (-1, 1):
                ld.line([(o, vy), (o + s * L * 0.4 * wv, vy + L * 0.22)], fill=(base[0] + 18, base[1] + 26, base[2] + 10, 255), width=max(1, int(size / 28)))
                lhd.line([(o, vy), (o + s * L * 0.4 * wv, vy + L * 0.22)], fill=205, width=max(1, int(size / 28)))
        # a lighter, glossier half where the leaf catches light
        hl = Image.new("RGBA", leaf.size, (0, 0, 0, 0))
        hd = ImageDraw.Draw(hl)
        hd.polygon([(o, o - L * 0.42)] + [(o + x * L * wv, o + y * L) for x, y in half[1:-1]] + [(o, o + L)], fill=(30, 40, 10, 60))
        leaf = Image.alpha_composite(leaf, hl)
        rot = side * rng.uniform(25, 65)
        leaf = leaf.rotate(rot, resample=Image.BICUBIC, expand=False)
        lh = lh.rotate(rot, resample=Image.BICUBIC, expand=False)
        im.alpha_composite(leaf, (int(cx - leaf.size[0] / 2), int(cy - leaf.size[1] / 2)))
        hm.paste(lh, (int(cx - lh.size[0] / 2), int(cy - lh.size[1] / 2)), lh)
        d.line([(sx, y), (cx - side * size * 0.3, cy - size * 0.5)], fill=(60, 70, 32, 255), width=3 * big)
        y += size * rng.uniform(0.55, 0.8)
        side = -side
    im = im.resize((W, H), Image.LANCZOS)
    hm = hm.resize((W, H), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    # Bleed the leaf colour into the cut-out so mipmaps do not fringe dark.
    rgb = a[..., :3].copy()
    alpha = a[..., 3]
    fill = np.asarray(Image.fromarray((rgb * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255.0
    w = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32)[..., None] / 255.0
    bleed = np.where(w > 1e-3, fill / np.maximum(w, 1e-3), col(40, 70, 30))
    rgb = np.where(alpha[..., None] > 0.02, rgb, np.clip(bleed, 0, 1))
    out = np.concatenate([rgb, alpha[..., None]], axis=2)
    hgt = np.asarray(hm).astype(np.float32) / 255.0
    ft.FOLDER = "jungle"
    save_png(out, ft.OUT / "textures" / "jungle" / "vine_strand.png", "RGBA")
    save_png(ft.normal_from(hgt * 6.0, 2.5), ft.OUT / "normals" / "jungle" / "vine_strand_normal.png", "RGB")
    SURF["jungle/vine_strand"] = {"phys": "foliage", "rough": 0.7, "metal": 0.0, "size": 1.0, "normal": True,
                                  "rough_map": False, "px": [W, H], "alpha": "scissor", "two_sided": True}


def cenote_water():
    """The Moon Well's water far below: black-green, a skin of floating leaves and scum, glossy."""
    n1 = noise((512, 512), beta=2.4, seed=91)
    n2 = noise((512, 512), beta=1.0, seed=92)
    a = mix(col(6, 16, 14), col(14, 30, 24), n1)
    scum = smooth(noise((512, 512), beta=2.0, seed=93), 0.7, 0.85)
    a = mix(a, col(40, 52, 26), scum * 0.6)
    leaves = smooth(n2, 0.86, 0.9)
    a = mix(a, col(70, 54, 26), leaves * 0.7)
    ft.FOLDER = "jungle"
    ft.save("cenote_water", a, n1 * 0.4 + scum * 1.5 + leaves * 2.0, 1.2, phys="water", rough=0.06, size=4.0)


def maps(only=None):
    jobs = {
        # walls and fronts: grey limestone ashlar going green
        "temple_stone": lambda: ph_map("temple_stone", "japanese_stone_wall", size=3.0, sat=0.7, gain=0.92, tint=(1.0, 0.98, 0.9), moss=0.35, seed=1),
        # the pyramids' sloping tiers (talud): coursed stone, moss in every joint
        "temple_talud": lambda: ph_map("temple_talud", "mossy_stone_wall", size=3.0, sat=0.85, gain=1.05, moss=0.15, seed=2),
        "temple_rubble": lambda: ph_map("temple_rubble", "castle_wall_slates", size=2.5, sat=0.6, gain=0.9, tint=(1.0, 0.97, 0.88), moss=0.4, seed=3),
        "temple_cobble": lambda: ph_map("temple_cobble", "medieval_blocks_02", size=2.5, sat=0.55, gain=0.9, tint=(0.95, 0.95, 0.9), moss=0.35, seed=4),
        "temple_floor": lambda: ph_map("temple_floor", "monastery_stone_floor", size=4.0, sat=0.6, gain=1.05, tint=(0.95, 0.98, 0.95), moss=0.3, seed=5),
        "temple_steps": lambda: ph_map("temple_steps", "stone_tiles_02", size=2.0, sat=0.6, gain=0.8, tint=(1.0, 0.98, 0.92), moss=0.25, seed=6),
        "temple_paving": lambda: ph_map("temple_paving", "mossy_cobblestone", size=3.0, sat=0.8, gain=0.9, seed=7),
        "tezontle": lambda: ph_map("tezontle", "mossy_brick_floor", size=2.0, sat=0.95, gain=0.85, tint=(1.05, 0.9, 0.85), moss=0.2, seed=8),
        "basalt": lambda: ph_map("basalt", "volcanic_rock_tiles", size=2.0, sat=0.6, gain=1.1, moss=0.25, seed=9),
        "stucco_red": lambda: ph_map("stucco_red", "old_sandstone_02", size=3.0, sat=0.4, gain=0.8, moss=0.25, seed=10, red=0.85),
        "stucco_white": lambda: ph_map("stucco_white", "old_sandstone_02", size=3.0, sat=0.35, gain=1.0, moss=0.3, seed=11, white=0.7),
        "cliff": lambda: ph_map("cliff", "rock_wall_02", phys="concrete", size=6.0, sat=0.9, gain=1.0, seed=12),
        "rock_face": lambda: ph_map("rock_face", "rock_face_03", phys="concrete", size=5.0, sat=0.55, gain=0.75, tint=(0.95, 1.0, 0.92), moss=0.45, seed=13),
        "rubble_wall": lambda: ph_map("rubble_wall", "stacked_stone_wall", size=2.5, sat=0.55, gain=0.85, tint=(0.95, 0.95, 0.9), moss=0.4, seed=14),
        "planks": lambda: ph_map("planks", "weathered_planks", phys="wood", size=2.0, sat=0.8, gain=0.95, moss=0.2, seed=15),
        "wood_moss": lambda: ph_map("wood_moss", "moss_wood", phys="wood", size=2.0, sat=0.8, gain=0.8, seed=16),
        "torch_wood": lambda: ph_map("torch_wood", "bark_brown_02", phys="wood", size=1.0, sat=0.7, gain=0.7, seed=17),
        "fret_panel": lambda: relief_map("fret_panel", "japanese_stone_wall", h_fret(), 1.6, pigment=(140, 44, 30), seed=20),
        "serpent_scales": lambda: relief_map("serpent_scales", "japanese_stone_wall", h_scales(), 1.4, pigment=(46, 96, 80), seed=21),
        "skull_rack": lambda: relief_map("skull_rack", "old_sandstone_02", h_skulls(), 1.8, pigment=(150, 40, 28), moss=0.3, seed=22, tint=(0.9, 0.9, 0.86)),
        "glyph_panel": lambda: relief_map("glyph_panel", "japanese_stone_wall", h_glyphs(), 2.4, pigment=(40, 90, 100), seed=23),
        "sun_disc": lambda: relief_map("sun_disc", "old_sandstone_02", h_sun_disc(), 3.6, pigment=(150, 48, 30), moss=0.15, seed=24, fit=True),
        "torch_wrap": torch_wrap,
        "vine_strand": vine_strand,
        "cenote_water": cenote_water,
    }
    for k, fn in jobs.items():
        if only and k not in only:
            continue
        fn()
        print("  jungle/" + k)
    ft.SURFACES.update(SURF)
    path = ft.OUT / "surfaces.json"
    old = json.loads(path.read_text()) if path.exists() else {}
    old.update(ft.SURFACES)
    path.write_text(json.dumps(dict(sorted(old.items())), indent=1))
    print("surfaces.json:", len(SURF) + len([k for k in ft.SURFACES if k not in SURF]), "jungle entries written")


# ------------------------------------------------------------------ Terrain3D sets (the ground)

TERRAIN = [
    # name, Poly Haven id, uv scale hint (repeats per metre, Terrain3D's uv_scale), grade
    ("litter", "leaves_forest_ground", {"sat": 0.75, "gain": 0.7, "tint": (0.92, 0.98, 0.86)}),
    ("sprouts", "brown_mud_leaves_01", {"sat": 0.9, "gain": 0.9}),
    ("soil", "mud_forest", {"sat": 1.0, "gain": 1.0}),
    ("roots", "roots", {"sat": 0.8, "gain": 0.62, "tint": (0.95, 0.9, 0.82)}),
    ("trail", "forest_ground_04", {"sat": 0.85, "gain": 0.8}),
    ("lichen_rock", "mossy_rock", {"sat": 0.8, "gain": 0.75}),
    ("cliff", "rock_wall_02", {"sat": 0.9, "gain": 0.95}),
    ("flagstones", "monastery_stone_floor", {"sat": 0.55, "gain": 0.95, "tint": (0.95, 0.98, 0.95)}),
    ("leaf_grass", "forest_leaves_02", {"sat": 1.05, "gain": 0.72, "tint": (0.72, 1.0, 0.55)}),   # greener: a jungle, not autumn
]


def terrain(only=None):
    TERRAIN_OUT.mkdir(parents=True, exist_ok=True)
    listing = []
    for name, pid, g in TERRAIN:
        if only and name not in only:
            continue
        a = grade(load_rgb(pid), g.get("sat", 1.0), g.get("gain", 1.0), g.get("tint", (1, 1, 1)))
        h = disp(pid)
        if h is None:
            h = blur(a.mean(axis=2), 1.5)
        lo, hi = np.percentile(h, 1), np.percentile(h, 99)
        h = np.clip((h - lo) / max(hi - lo, 1e-3), 0, 1)
        n = normal_rgb(pid)
        if n is None:
            n = ft.normal_from(h * 30.0, 4.0)
        ao = load_gray(pid, "ao", default=np.ones((S, S), np.float32))
        r = load_gray(pid, "roughness", default=np.full((S, S), 0.9, np.float32))
        # Terrain3D's packer: AO baked into the normal's length (normalized * (sqrt(ao) * 0.5 + 0.5))
        v = n * 2.0 - 1.0
        v /= np.maximum(np.linalg.norm(v, axis=2, keepdims=True), 1e-4)
        v *= (np.sqrt(ao) * 0.5 + 0.5)[..., None]
        nr = np.concatenate([v * 0.5 + 0.5, r[..., None]], axis=2)
        ah = np.concatenate([a, h[..., None]], axis=2)
        save_png(ah, TERRAIN_OUT / f"{name}_ah.png", "RGBA")
        save_png(nr, TERRAIN_OUT / f"{name}_nr.png", "RGBA")
        listing.append({"name": name, "source": pid})
        print("  terrain/" + name, "<-", pid)
    if not only:
        (TERRAIN_OUT / "sets.json").write_text(json.dumps(listing, indent=1))


if __name__ == "__main__":
    only = None
    for arg in sys.argv[1:]:
        if arg.startswith("--only="):
            only = set(arg.split("=", 1)[1].split(","))
    if "--terrain-only" not in sys.argv:
        maps(only)
    if "--maps-only" not in sys.argv:
        terrain(only)
