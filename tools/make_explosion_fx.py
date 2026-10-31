"""Renders the frag grenade's explosion and smoke flipbooks (r14), from code: no downloaded art.

    python -I tools/make_explosion_fx.py [--preview]

Each flipbook is 8 x 8 frames of 128 px (1024 px square), played once over a particle's life. Every frame is a small
volume (noise-displaced fireball / smoke puff on a 3D grid) lit from above (optical depth summed down the grid), with
the fire's own glow lighting the smoke round it, then integrated front to back along the view axis.

  game/assets/fx/explosion_albedo.png   RGB: soot / smoke colour (lit), A: opacity
  game/assets/fx/explosion_emit.png     RGB: fire light (divided by opacity, so it survives alpha blending)
  game/assets/fx/smoke_albedo.png       RGB: lit grey smoke, A: opacity (lingering cloud, dust ring tinted brown)
  work/r14/fx/*_sheet.png               previews on a mid-grey background
"""
import os, sys
import numpy as np
from multiprocessing import Pool
from scipy import ndimage
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'assets', 'fx')
PREV = os.path.join(ROOT, 'work', 'r14', 'fx')
N = 104          # volume grid per side
F = 8            # frames per side of the sheet
PX = 128         # pixels per frame
TILE = 40        # noise tile size


def _noise_tile(seed):
    rng = np.random.default_rng(seed)
    t = rng.random((TILE, TILE, TILE)).astype(np.float32)
    # Smooth the white noise once: value noise with softer cells reads as billows, not grain.
    t = ndimage.gaussian_filter(t, 0.8, mode='wrap')
    t = ((t - t.min()) / (t.max() - t.min())).astype(np.float32)
    # Cubic B-spline coefficients: smooth lookups (linear ones leave straight creases along the cell edges).
    return ndimage.spline_filter(t, order=3, mode='grid-wrap').astype(np.float32)


def fbm(tile, pts, octaves=5, lac=2.03, gain=0.52):
    """pts: (3, M) noise-space coordinates. Returns values roughly in [-1, 1]."""
    out = np.zeros(pts.shape[1], np.float32)
    amp, tot, p = 1.0, 0.0, pts
    for o in range(octaves):
        v = ndimage.map_coordinates(tile, p, order=3, mode='grid-wrap', prefilter=False)
        out += amp * (v - 0.5) * 2.0
        tot += amp
        amp *= gain
        p = p * lac + 7.31 * (o + 1)
    return out / tot * 1.6


def ramp(t):
    """Black body-ish colour for heat t in [0, 1]."""
    keys = np.array([0.0, 0.18, 0.38, 0.6, 0.82, 1.0], np.float32)
    cols = np.array([[0, 0, 0], [0.45, 0.05, 0.01], [1.0, 0.26, 0.03], [1.0, 0.56, 0.14], [1.0, 0.82, 0.45], [1.0, 0.97, 0.86]], np.float32)
    out = np.empty(t.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(t, keys, cols[:, c])
    return out


def _grid():
    a = np.linspace(-1.0, 1.0, N, dtype=np.float32)
    z, y, x = np.meshgrid(a, a, a, indexing='ij')   # axis 0 = depth (view), 1 = y (down the image), 2 = x
    return x, -y, z


def render_frame(args):
    kind, u, seed = args
    tile_a = _noise_tile(seed)
    tile_b = _noise_tile(seed + 101)
    x, y, z = _grid()
    if kind == 'fire':
        R = 0.3 + 0.42 * (1.0 - (1.0 - u) ** 3.0)
        cy = -0.12 + 0.2 * u ** 1.3
        scroll = np.array([0.0, -1.2 * u, 0.3 * u], np.float32)
        freq = 2.4
        amp = 0.42 * R + 0.04
    else:
        R = 0.36 + 0.34 * (1.0 - (1.0 - u) ** 2.0)
        cy = -0.08 + 0.08 * u
        scroll = np.array([0.25 * u, -0.6 * u, 0.15 * u], np.float32)
        freq = 2.1
        amp = 0.44 * R + 0.04
    dx, dy, dz = x, y - cy, z
    r = np.sqrt(dx * dx + dy * dy + dz * dz)
    pts = np.stack([(dx * freq + scroll[0]).ravel(), (dy * freq + scroll[1]).ravel(), (dz * freq + scroll[2]).ravel()])
    # Domain warp, then billows (|noise|, rounded lumps) push the surface out: cauliflower clouds, not fuzzy balls.
    warp = np.stack([fbm(tile_b, pts * 0.6 + 11.0, 3), fbm(tile_b, pts * 0.6 + 23.0, 3), fbm(tile_b, pts * 0.6 + 37.0, 3)]) * 0.45
    n1 = fbm(tile_a, pts + warp).reshape(r.shape)
    billow = 1.0 - np.abs(n1)
    reff = r - amp * (billow - 0.45) * 1.6
    edge = 0.12 * R + 0.02
    dens = np.clip((R - reff) / edge, 0.0, 1.0)
    n2 = fbm(tile_b, pts * 1.7 + 3.0, octaves=4).reshape(r.shape)
    # Billows: denser lumps, thinner gaps; the whole cloud thins as it spreads.
    dens *= np.clip(0.62 + 0.55 * n2, 0.0, 1.3)
    window = np.clip((0.98 - np.sqrt(x * x + y * y + z * z)) / 0.12, 0.0, 1.0)
    dens *= window
    if kind == 'fire':
        # Late frames break up into wisps as the soot thins.
        dens *= np.clip(1.25 - 1.05 * u + 0.9 * n2, 0.0, 1.0)
        heat_t = np.clip(1.15 - 1.75 * u, 0.0, 1.0) ** 1.1
        T = np.clip(0.55 + 0.75 * n2 + 0.55 * (1.0 - r / R), 0.0, 1.0) * heat_t
        # Hot gas is thin; soot forms where it cools.
        sigma_k = 22.0 * (0.18 + 0.82 * (1.0 - T) ** 1.5)
        albedo = 0.07 + 0.2 * u
    else:
        dens *= np.clip(1.15 - 1.2 * u + 0.8 * n2, 0.0, 1.0) * 0.9
        T = np.zeros_like(dens)
        sigma_k = 13.0
        albedo = 0.55
    d = 2.0 / N
    sigma = dens * sigma_k
    # Light from above: optical depth summed from the top of the grid down (axis 1 runs top to bottom).
    tau_l = np.cumsum(sigma, axis=1) * d
    light = np.exp(-tau_l * 0.7) * 0.85 + 0.22
    emis = ramp(T) * (dens * (T ** 1.4))[..., None] * 14.0
    if kind == 'fire':
        glow = ndimage.gaussian_filter(emis.sum(-1), 3.0)
        glow_col = np.array([1.0, 0.45, 0.12], np.float32)
        scat = albedo * light[..., None] + glow[..., None] * glow_col * 0.9
    else:
        scat = albedo * light[..., None] * np.array([1.0, 0.99, 0.97], np.float32)
    # Front to back along axis 0 (camera at depth -1 looking toward +1).
    Tacc = np.ones((N, N), np.float32)
    col = np.zeros((N, N, 3), np.float32)
    em = np.zeros((N, N, 3), np.float32)
    for k in range(N):
        a = 1.0 - np.exp(-sigma[k] * d)
        col += (Tacc * a)[..., None] * scat[k]
        em += Tacc[..., None] * emis[k] * d
        Tacc *= 1.0 - a
    alpha = 1.0 - Tacc
    rgb = col / np.maximum(alpha, 1e-4)[..., None]
    em_u = em / np.maximum(alpha, 0.04)[..., None]
    return alpha, np.clip(rgb, 0, 1), np.clip(em_u, 0, 1)


def to_img(arr, mode):
    a = np.clip(arr * 255.0 + 0.5, 0, 255).astype(np.uint8)
    im = Image.fromarray(a, mode)
    return im.resize((PX, PX), Image.LANCZOS)


def sheet(kind, seed):
    jobs = [(kind, i / (F * F - 1), seed) for i in range(F * F)]
    with Pool(min(12, os.cpu_count() or 4)) as pool:
        frames = pool.map(render_frame, jobs)
    alb = Image.new('RGBA', (F * PX, F * PX))
    emi = Image.new('RGB', (F * PX, F * PX))
    for i, (alpha, rgb, em) in enumerate(frames):
        ox, oy = (i % F) * PX, (i // F) * PX
        rgba = np.concatenate([rgb, alpha[..., None]], -1)
        alb.paste(to_img(rgba, 'RGBA'), (ox, oy))
        emi.paste(to_img(em, 'RGB'), (ox, oy))
    return alb, emi


def preview(alb, emi, name):
    os.makedirs(PREV, exist_ok=True)
    bg = Image.new('RGB', alb.size, (90, 92, 96))
    a = np.asarray(alb).astype(np.float32) / 255.0
    e = np.asarray(emi).astype(np.float32) / 255.0 if emi is not None else 0.0
    b = np.asarray(bg).astype(np.float32) / 255.0
    out = b * (1 - a[..., 3:4]) + (a[..., :3] + e * 1.3) * a[..., 3:4]
    Image.fromarray(np.clip(out * 255, 0, 255).astype(np.uint8), 'RGB').save(os.path.join(PREV, name + '_sheet.png'))


if __name__ == '__main__':
    alb, emi = sheet('fire', 1414)
    alb.save(os.path.join(OUT, 'explosion_albedo.png'))
    emi.save(os.path.join(OUT, 'explosion_emit.png'))
    preview(alb, emi, 'explosion')
    salb, _ = sheet('smoke', 2828)
    salb.save(os.path.join(OUT, 'smoke_albedo.png'))
    preview(salb, None, 'smoke')
    print('wrote', OUT)
