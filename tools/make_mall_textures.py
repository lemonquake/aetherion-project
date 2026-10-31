"""r15: material textures made for Malasugue Mall (no download has them): the polished cream porcelain of the
concourses (the reference mall's floor), the same in warm grey for accent bands, and the window grid of the city
blocks round the site (with a lit-window emission map).

    python -I tools/make_mall_textures.py      (then bash tools/import.sh)

Writes game/assets/mall/tex/<name>/{albedo,roughness,normal}.png (and emission.png for city_windows). Each floor
texture covers 2.4 m: 4 x 4 tiles of 0.6 m with 2 mm grout (the atrium: 2 x 2 of 1.2 m).
"""
from pathlib import Path

import numpy as np
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / 'game' / 'assets' / 'mall' / 'tex'
N = 1024


def noise(n, scale, seed):
    rng = np.random.default_rng(seed)
    g = rng.random((n // scale + 2, n // scale + 2))
    # bilinear upsample of a coarse random grid, tileable by wrapping
    g[-2:, :] = g[:2, :]
    g[:, -2:] = g[:, :2]
    y, x = np.mgrid[0:n, 0:n] / scale
    x0 = x.astype(int)
    y0 = y.astype(int)
    fx = x - x0
    fy = y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    a = g[y0, x0] * (1 - fx) + g[y0, x0 + 1] * fx
    b = g[y0 + 1, x0] * (1 - fx) + g[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def fbm(n, seed, octaves=5, base=256):
    out = np.zeros((n, n))
    amp = 1.0
    tot = 0.0
    s = base
    for o in range(octaves):
        out += noise(n, max(s, 2), seed + o) * amp
        tot += amp
        amp *= 0.5
        s //= 2
    return out / tot


def tiles(name, base, var, vein_col, vein_amt, grout_col, rough_tile, tiles_per=3, seed=1):
    n = N
    t = n // tiles_per
    grout_px = 3
    yy, xx = np.mgrid[0:n, 0:n]
    gx = (xx % t) < grout_px
    gy = (yy % t) < grout_px
    grout = gx | gy
    rng = np.random.default_rng(seed)
    alb = np.zeros((n, n, 3))
    tile_id = (yy // t) * tiles_per + (xx // t)
    shade = rng.normal(0, var, tiles_per * tiles_per)
    for c in range(3):
        alb[..., c] = base[c] + shade[tile_id]
    # marble veining: thin bands of a turbulent noise
    f = fbm(n, seed + 10, 6, 256)
    veins = np.abs(np.sin((xx * 0.004 + yy * 0.0025 + f * 6.0) * np.pi))
    veins = np.clip(1.0 - veins * 9.0, 0, 1) * vein_amt
    cloud = (fbm(n, seed + 30, 4, 128) - 0.5) * 10.0
    for c in range(3):
        alb[..., c] = alb[..., c] * (1 - veins) + vein_col[c] * veins + cloud
    for c in range(3):
        alb[..., c] = np.where(grout, grout_col[c], alb[..., c])
    alb = np.clip(alb, 0, 255).astype(np.uint8)
    rough = np.where(grout, 0.7, rough_tile + (fbm(n, seed + 50, 3, 64) - 0.5) * 0.08 + veins * 0.05)
    rough = (np.clip(rough, 0, 1) * 255).astype(np.uint8)
    # normal: grout grooves only (the tiles are flat)
    h = np.where(grout, 0.0, 1.0)
    h = np.minimum(h, np.roll(h, 1, 0) * 0.5 + 0.5)
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 2.0
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 2.0
    nz = np.ones_like(h)
    ln = np.sqrt(dx * dx + dy * dy + nz * nz)
    nrm = np.stack([(-dx / ln) * 0.5 + 0.5, (dy / ln) * 0.5 + 0.5, (nz / ln) * 0.5 + 0.5], -1)
    nrm = (nrm * 255).astype(np.uint8)
    d = OUT / name
    d.mkdir(parents=True, exist_ok=True)
    Image.fromarray(alb).save(d / 'albedo.png')
    Image.fromarray(rough).convert('RGB').save(d / 'roughness.png')
    Image.fromarray(nrm).save(d / 'normal.png')
    print('wrote', d)


def city_windows():
    n = 512
    cols, rows = 8, 8
    rng = np.random.default_rng(4)
    alb = np.zeros((n, n, 3), np.uint8)
    emi = np.zeros((n, n, 3), np.uint8)
    alb[:] = (172, 168, 160)
    cw = n // cols
    rh = n // rows
    for r in range(rows):
        for c in range(cols):
            x0 = c * cw + 7
            y0 = r * rh + 10
            x1 = (c + 1) * cw - 7
            y1 = (r + 1) * rh - 14
            glass = (38, 48, 58) if rng.random() < 0.7 else (60, 74, 86)
            alb[y0:y1, x0:x1] = glass
            alb[y1:y1 + 3, x0 - 2:x1 + 2] = (140, 136, 130)
            if rng.random() < 0.38:
                warm = rng.choice([(255, 214, 150), (255, 236, 200), (210, 230, 255)])
                emi[y0 + 2:y1 - 2, x0 + 2:x1 - 2] = warm
                alb[y0 + 2:y1 - 2, x0 + 2:x1 - 2] = (120, 110, 90)
    d = OUT / 'city_windows'
    d.mkdir(parents=True, exist_ok=True)
    Image.fromarray(alb).save(d / 'albedo.png')
    Image.fromarray(emi).save(d / 'emission.png')
    print('wrote', d)


def main():
    tiles('floor_cream', (228, 220, 205), 3.0, (196, 186, 170), 0.35, (205, 199, 188), 0.12, 4, 1)
    tiles('floor_band', (92, 92, 96), 2.0, (140, 140, 146), 0.4, (80, 80, 84), 0.14, 4, 2)
    tiles('floor_atrium', (238, 232, 222), 2.5, (176, 160, 140), 0.55, (210, 202, 190), 0.08, 2, 3)
    city_windows()


if __name__ == '__main__':
    main()
