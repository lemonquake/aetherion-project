"""Bullet-hole atlas and particle textures for the impact system (no downloads, all procedural).

    python -I tools/make_impact_textures.py          (then bash tools/import.sh)

game/assets/fx/holes_albedo.png  4x4 atlas of 128 px cells, RGBA (alpha = where the mark shows)
game/assets/fx/holes_normal.png  same layout, RGB = tangent-space normal, A = roughness
    cells: 0 concrete A, 1 concrete B, 2 concrete exit (spall), 3 plaster/paint, 4 wood A, 5 wood B, 6 wood exit,
           7 metal A, 8 metal B, 9 metal exit (petals), 10 glass, 11 fabric/plastic, 12 dirt, 13 tile/ceramic,
           14 scorch (blast), 15 brick/hollow block
game/assets/fx/fx_smoke.png      soft puff (white, alpha), tinted per effect
game/assets/fx/fx_spark.png      a hot streak for sparks (additive)
game/assets/fx/fx_drop.png       a small soft droplet / mist dot
work/impact_textures_preview.png checks
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'assets', 'fx')
N = 128
RNG = np.random.default_rng(907)

yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
CX = CY = (N - 1) / 2.0
DX, DY = xx - CX, yy - CY
R = np.hypot(DX, DY)
ANG = np.arctan2(DY, DX)


def fbm(scale, octaves=4, seed=0):
    rng = np.random.default_rng(seed)
    out = np.zeros((N, N))
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        s = max(int(scale * 2 ** o), 2)
        g = rng.random((s + 1, s + 1))
        # bilinear upsample of a periodic-ish grid
        gx = xx / (N - 1) * s
        gy = yy / (N - 1) * s
        x0 = np.floor(gx).astype(int)
        y0 = np.floor(gy).astype(int)
        fx = gx - x0
        fy = gy - y0
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        x1 = np.minimum(x0 + 1, s)
        y1 = np.minimum(y0 + 1, s)
        v = (g[y0, x0] * (1 - fx) * (1 - fy) + g[y0, x1] * fx * (1 - fy) + g[y1, x0] * (1 - fx) * fy + g[y1, x1] * fx * fy)
        out += v * amp
        tot += amp
        amp *= 0.5
    return out / tot


def ang_noise(k, seed, amp):
    """Irregular radius as a function of angle (a few harmonics)."""
    rng = np.random.default_rng(seed)
    r = np.zeros_like(ANG)
    for h in range(2, 2 + k):
        r += rng.uniform(-1, 1) * np.cos(h * ANG + rng.uniform(0, 6.283)) / h
    return 1.0 + amp * r


def cracks(n, seed, length, width=1.0, jag=0.25):
    """Thin radial cracks from the centre, tapering, slightly kinked."""
    rng = np.random.default_rng(seed)
    m = np.zeros((N, N))
    for i in range(n):
        a = rng.uniform(0, 6.283)
        L = length * rng.uniform(0.55, 1.0)
        px, py = CX, CY
        steps = 24
        for s in range(steps):
            a += rng.normal(0, jag)
            seg = L / steps
            nx, ny = px + np.cos(a) * seg, py + np.sin(a) * seg
            t = s / steps
            w = width * (1.0 - t * 0.8)
            # distance from pixels to the segment
            vx, vy = nx - px, ny - py
            l2 = vx * vx + vy * vy + 1e-9
            u = np.clip(((xx - px) * vx + (yy - py) * vy) / l2, 0, 1)
            d = np.hypot(xx - (px + u * vx), yy - (py + u * vy))
            m = np.maximum(m, np.clip(1.0 - d / max(w, 0.35), 0, 1) * (1.0 - t * 0.6))
            px, py = nx, ny
    return m


def smooth(x, k=1):
    for _ in range(k):
        x = (x + np.roll(x, 1, 0) + np.roll(x, -1, 0) + np.roll(x, 1, 1) + np.roll(x, -1, 1)) / 5.0
    return x


def normal_from_height(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = np.ones_like(h)
    l = np.sqrt(gx * gx + gy * gy + nz * nz)
    # OpenGL convention (Godot): +Y up in the texture means green = up.
    return np.stack([(-gx / l) * 0.5 + 0.5, (gy / l) * 0.5 + 0.5, nz / l * 0.5 + 0.5], -1)


def cell(rgb, a, h, rough, strength=6.0):
    a = np.clip(a, 0, 1)
    n = normal_from_height(h, strength)
    # outside the mark the normal is flat
    n = n * a[..., None] + np.array([0.5, 0.5, 1.0]) * (1 - a[..., None])
    return np.dstack([np.clip(rgb, 0, 1), a]), np.dstack([n, np.clip(rough, 0, 1)])


def crater(seed, core, rad, rim_col, in_col, depth=1.0, rough=0.9, crack_n=5, crack_len=52, speck=0.25):
    edge = rad * ang_noise(6, seed, 0.35) * (0.9 + 0.2 * fbm(6, 3, seed + 1))
    t = np.clip(R / edge, 0, 2)
    inside = t < 1.0
    nz = fbm(10, 4, seed + 2)
    h = np.where(inside, -depth * np.clip(1 - t, 0, 1) ** 1.4, 0.0) - np.where(R < core, 1.5, 0.0)
    h += (nz - 0.5) * 0.25 * inside
    col = np.zeros((N, N, 3))
    k = np.clip((t - 0.15) / 0.85, 0, 1)[..., None]
    col[:] = in_col
    col = col * (0.75 + 0.5 * nz[..., None])
    col = col * (1 - k) + np.array(rim_col) * k * (0.85 + 0.3 * nz[..., None])
    sp = (fbm(40, 2, seed + 3) > 1 - speck) * inside
    col = col * (1 - 0.35 * sp[..., None])
    hole = np.clip(1 - (R - core * 0.6) / (core * 0.8), 0, 1) * ang_noise(5, seed + 4, 0.3).clip(0.7, 1.3) ** 0
    col = col * (1 - hole[..., None]) + np.array([0.012, 0.011, 0.01]) * hole[..., None]
    a = np.clip(1.15 - t, 0, 1) ** 0.6
    # dust halo: a faint lighter ring beyond the crater
    halo = np.clip(1 - (R - edge) / (rad * 0.6), 0, 1) * (R > edge) * 0.35 * fbm(14, 3, seed + 5)
    col = col * (1 - halo[..., None]) + np.array(rim_col) * 1.1 * halo[..., None]
    a = np.maximum(a, halo)
    if crack_n:
        c = cracks(crack_n, seed + 6, crack_len, 1.1)
        col = col * (1 - 0.8 * c[..., None]) + np.array([0.04, 0.04, 0.04]) * 0.8 * c[..., None]
        a = np.maximum(a, c * 0.9)
        h -= c * 0.3
    return cell(col, a, smooth(h, 1), rough * np.ones((N, N)) - 0.1 * hole)


def wood(seed, exit=False):
    grain = fbm(4, 3, seed) * 0.6 + 0.4 * np.sin(xx * 0.55 + fbm(3, 2, seed + 1) * 9.0) * 0.5 + 0.5
    ry = 1.0 if not exit else 1.0
    # elongated along the grain (texture Y)
    re = np.hypot(DX * 1.35, DY * 0.8)
    rad = (16 if not exit else 30) * ang_noise(7, seed + 2, 0.45)
    t = np.clip(re / rad, 0, 2)
    inside = t < 1
    fibres = np.clip(np.sin(xx * 2.3 + fbm(8, 2, seed + 3) * 14) * 0.5 + 0.5, 0, 1)
    raw = np.array([0.62, 0.48, 0.3]) * (0.75 + 0.35 * grain[..., None])
    col = np.zeros((N, N, 3)) + raw
    col = col * (0.8 + 0.25 * fibres[..., None])
    core = 6.5 if not exit else 10.0
    hole = np.clip(1 - (np.hypot(DX * 1.2, DY * 0.85) - core * 0.6) / (core * 0.7), 0, 1)
    col = col * (1 - hole[..., None]) + np.array([0.02, 0.015, 0.01]) * hole[..., None]
    # splinters: streaks along Y out of the hole
    spl = np.zeros((N, N))
    rng = np.random.default_rng(seed + 9)
    for i in range(10 if not exit else 18):
        x0 = CX + rng.normal(0, 6 if not exit else 10)
        ln = rng.uniform(14, 34 if not exit else 50)
        sg = 1 if rng.random() < 0.5 else -1
        w = rng.uniform(0.8, 2.0)
        d = np.abs(xx - x0 - (yy - CY) * rng.normal(0, 0.08))
        along = (yy - CY) * sg
        m = np.clip(1 - d / w, 0, 1) * (along > 0) * np.clip(1 - along / ln, 0, 1)
        spl = np.maximum(spl, m)
    col = col * (1 - 0.3 * spl[..., None]) + np.array([0.78, 0.64, 0.44]) * 0.3 * spl[..., None]
    a = np.maximum(np.clip(1.1 - t, 0, 1) ** 0.5, spl * 0.95)
    edge_dark = np.clip(1 - np.abs(t - 0.95) / 0.12, 0, 1) * 0.5
    col = col * (1 - edge_dark[..., None])
    h = np.where(inside, -np.clip(1 - t, 0, 1) ** 1.2, 0) - hole * 1.5 + spl * (0.4 if exit else -0.2) + (fibres - 0.5) * 0.15 * inside
    return cell(col, a, smooth(h, 1), 0.85 * np.ones((N, N)), 5.0)


def metal(seed, exit=False):
    core = 7.0
    if exit:
        # petals torn outward
        petal = np.clip(np.cos(ANG * 5 + RNG.uniform(0, 6)) * 0.5 + 0.5, 0, 1) ** 2
        edge = core * (1.3 + 1.6 * petal)
    else:
        edge = core * ang_noise(4, seed, 0.12)
    hole = np.clip(1 - (R - edge * 0.85) / 1.5, 0, 1)
    ring_w = 6.0 if not exit else 9.0
    ring = np.clip(1 - np.abs(R - edge - ring_w * 0.5) / ring_w, 0, 1)
    chips = np.clip(1 - (R - edge) / (ring_w * 2.4 * ang_noise(8, seed + 1, 0.5)), 0, 1) * (R > edge)
    bare = np.array([0.72, 0.71, 0.68])
    paint = np.array([0.36, 0.36, 0.34])
    scr = fbm(30, 2, seed + 2)
    col = np.zeros((N, N, 3)) + paint
    col = col * (1 - chips[..., None]) + bare * (0.8 + 0.3 * scr[..., None]) * chips[..., None]
    col = col * (1 - hole[..., None]) + np.array([0.01, 0.01, 0.01]) * hole[..., None]
    a = np.maximum(chips, hole)
    a = np.maximum(a, ring * 0.8)
    a = np.clip(a, 0, 1)
    h = -np.clip(1 - R / (edge + ring_w * 2), 0, 1) ** 2 * (0.8 if not exit else -0.8) - hole * 1.0 + ring * 0.3
    rough = np.where(chips > 0.3, 0.3, 0.6)
    return cell(col, a, smooth(h, 1), rough, 7.0)


def glass(seed):
    c = cracks(9, seed, 60, 0.9, 0.12)
    rings = np.zeros((N, N))
    for rr in (14, 26, 40):
        w = np.clip(1 - np.abs(R - rr * ang_noise(5, seed + rr, 0.15)) / 0.9, 0, 1)
        sect = (np.sin(ANG * 9 + rr) > -0.2)
        rings = np.maximum(rings, w * sect * np.clip(1 - R / 62, 0, 1))
    hole = np.clip(1 - (R - 5) / 2, 0, 1)
    frost = np.clip(1 - R / 13, 0, 1) * 0.6
    m = np.maximum(np.maximum(c, rings * 0.8), frost)
    col = np.zeros((N, N, 3)) + np.array([0.85, 0.9, 0.9])
    col = col * (1 - hole[..., None]) + 0.02 * hole[..., None]
    a = np.maximum(m * 0.85, hole)
    return cell(col, a, -m * 0.2 - hole, 0.1 * np.ones((N, N)), 3.0)


def fabric(seed):
    edge = 6.0 * ang_noise(9, seed, 0.5)
    hole = np.clip(1 - (R - edge) / 1.5, 0, 1)
    fray = np.clip(1 - (R - edge) / 9.0, 0, 1) * (R > edge) * (fbm(30, 2, seed) > 0.45)
    ring = np.clip(1 - (R - edge) / 16.0, 0, 1) * 0.35
    col = np.zeros((N, N, 3)) + 0.05
    col = col * (1 - fray[..., None]) + np.array([0.55, 0.53, 0.5]) * fray[..., None]
    a = np.maximum(np.maximum(hole, fray * 0.9), ring)
    return cell(col, a, -hole - ring, 0.95 * np.ones((N, N)), 4.0)


def dirt(seed):
    col_in = np.array([0.12, 0.09, 0.06])
    col_rim = np.array([0.32, 0.25, 0.18])
    t = crater(seed, 5.0, 24, col_rim, col_in, depth=1.2, rough=1.0, crack_n=0)
    return t


def scorch(seed):
    nz = fbm(6, 4, seed)
    rad = 60 * ang_noise(7, seed + 1, 0.3)
    t = np.clip(R / rad, 0, 1.5)
    a = np.clip(1 - t, 0, 1) ** 0.7 * (0.65 + 0.5 * nz)
    col = np.zeros((N, N, 3)) + 0.03 + 0.05 * nz[..., None]
    return cell(col, np.clip(a, 0, 0.95), -a * 0.2, 0.95 * np.ones((N, N)), 2.0)


def build():
    os.makedirs(OUT, exist_ok=True)
    cells = [
        crater(11, 6.0, 30, [0.64, 0.62, 0.58], [0.5, 0.48, 0.45]),
        crater(12, 6.5, 26, [0.6, 0.58, 0.54], [0.44, 0.42, 0.4], crack_n=3),
        crater(13, 10.0, 52, [0.66, 0.64, 0.6], [0.5, 0.48, 0.45], depth=1.4, crack_n=7, crack_len=60),
        crater(14, 6.0, 30, [0.9, 0.89, 0.86], [0.7, 0.68, 0.64], crack_n=2, speck=0.1),
        wood(21), wood(22), wood(23, exit=True),
        metal(31), metal(32), metal(33, exit=True),
        glass(41), fabric(51), dirt(61),
        crater(71, 6.0, 22, [0.82, 0.8, 0.76], [0.55, 0.5, 0.44], crack_n=8, crack_len=58, speck=0.05),
        scorch(81),
        crater(91, 6.0, 30, [0.62, 0.42, 0.34], [0.46, 0.34, 0.28]),
    ]
    alb = np.zeros((N * 4, N * 4, 4))
    nrm = np.zeros((N * 4, N * 4, 4))
    for i, (a, n) in enumerate(cells):
        r, c = divmod(i, 4)
        # keep a 2 px transparent border so mip levels don't bleed into the neighbour
        a[:2, :, 3] = 0
        a[-2:, :, 3] = 0
        a[:, :2, 3] = 0
        a[:, -2:, 3] = 0
        alb[r * N:(r + 1) * N, c * N:(c + 1) * N] = a
        nrm[r * N:(r + 1) * N, c * N:(c + 1) * N] = n
    Image.fromarray((alb * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'holes_albedo.png'))
    Image.fromarray((nrm * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'holes_normal.png'))

    # Soft smoke puff
    S = 128
    y, x = np.mgrid[0:S, 0:S] / (S - 1) * 2 - 1
    r = np.hypot(x, y)
    n2 = fbm(5, 5, 5)
    puff = np.clip(1 - r, 0, 1) ** 1.6 * (0.55 + 0.6 * n2)
    puff = np.clip(puff, 0, 1)
    rgb = np.ones((S, S, 3)) * (0.85 + 0.15 * n2[..., None])
    Image.fromarray((np.dstack([rgb, puff]) * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'fx_smoke.png'))
    # Spark streak (tall)
    W, H = 16, 64
    sy, sx = np.mgrid[0:H, 0:W]
    u = (sx - (W - 1) / 2) / (W / 2)
    v = (sy - (H - 1) / 2) / (H / 2)
    core = np.clip(1 - np.abs(u) * 1.6, 0, 1) ** 2 * np.clip(1 - np.abs(v), 0, 1) ** 0.6
    Image.fromarray((np.dstack([np.ones((H, W, 3)), core]) * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'fx_spark.png'))
    # Droplet
    D = 32
    dy, dx = np.mgrid[0:D, 0:D] / (D - 1) * 2 - 1
    dd = np.clip(1 - np.hypot(dx, dy), 0, 1) ** 1.2
    Image.fromarray((np.dstack([np.ones((D, D, 3)), dd]) * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'fx_drop.png'))

    # Preview: atlas over grey and over dark wood, normals beside.
    os.makedirs(os.path.join(ROOT, 'work'), exist_ok=True)
    bg = np.ones((N * 4, N * 4, 3)) * 0.55
    comp = alb[..., :3] * alb[..., 3:4] + bg * (1 - alb[..., 3:4])
    prev = np.concatenate([comp, nrm[..., :3]], 1)
    Image.fromarray((prev * 255).astype(np.uint8)).save(os.path.join(ROOT, 'work', 'impact_textures_preview.png'))
    print('wrote', OUT)


if __name__ == '__main__':
    build()
