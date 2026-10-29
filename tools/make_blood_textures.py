"""Blood mark atlas for fx/blood.gd: fresh, wet, red liquid marks drawn as metaball fields.

    python -I tools/make_blood_textures.py [--preview work/blood_preview.png]

Writes game/assets/fx/blood_albedo.png (RGB colour, A coverage) and blood_normal.png (RGB normal, A roughness),
a 4 x 4 atlas of 512 px cells. Cells (CELLS in fx/blood.gd must match):
  0-3   drops that fell straight down: round body, crown spikes, satellites
  4-7   directional spatter: a drop that hit at an angle, tail pointing the way it flew (+V, down the image)
  8-9   wall burst: a fan of droplets from one point, runs dripping down (+V)
  10    fine mist
  11    heavy burst (shotgun, head): dense centre, long streaks, runs
  12-13 pools: thick, glossy, smooth-edged
  14    smear / drag mark along +U
  15    drip trail: a line of drops along +V
Thickness drives colour (thin film bright red, thick nearly black-red), the edge meniscus drives the normal, and the
whole mark is wet (low roughness). Owner-made, procedural; no inputs.
"""
import math, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "fx")
S = 512          # cell size in the atlas
W = 1024         # working size (2x supersampling)
rng = np.random.default_rng(7177)
YY, XX = np.mgrid[0:W, 0:W].astype(np.float32) / W   # 0..1, y down


def fbm(scale, octaves=4, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros((W, W), np.float32)
    amp = 1.0
    for o in range(octaves):
        n = int(scale * 2 ** o) + 2
        g = r.standard_normal((n, n)).astype(np.float32)
        up = np.array(Image.fromarray(g).resize((W, W), Image.BICUBIC))
        out += up * amp
        amp *= 0.5
    return out / 1.9


def blob(F, cx, cy, r, w=1.0, ang=0.0, stretch=1.0):
    """Gaussian metaball at (cx, cy) (0..1), radius r, stretched along angle ang (radians, 0 = +x, pi/2 = +y down)."""
    x0, x1 = int(max(0, (cx - r * stretch * 3) * W)), int(min(W, (cx + r * stretch * 3) * W) + 1)
    y0, y1 = int(max(0, (cy - r * stretch * 3) * W)), int(min(W, (cy + r * stretch * 3) * W) + 1)
    if x1 <= x0 or y1 <= y0:
        return
    dx = XX[y0:y1, x0:x1] - cx
    dy = YY[y0:y1, x0:x1] - cy
    c, s = math.cos(ang), math.sin(ang)
    u = dx * c + dy * s
    v = -dx * s + dy * c
    d2 = (u / stretch) ** 2 + v ** 2
    F[y0:y1, x0:x1] += w * np.exp(-d2 / (2 * r * r))


def drop_with_tail(F, cx, cy, r, ang, length, taper=0.55):
    """An elongated drop at (cx, cy) whose tail streams off in direction ang, ending in a small bead."""
    blob(F, cx, cy, r, 1.25, ang, 1.0 + length * 0.6)
    n = max(3, int(length * 7))
    for i in range(1, n + 1):
        f = i / n
        rr = r * (1.0 - f * (1.0 - taper * 0.35)) * 0.55
        px = cx + math.cos(ang) * r * (1.2 + length * 2.6 * f)
        py = cy + math.sin(ang) * r * (1.2 + length * 2.6 * f)
        blob(F, px, py, max(rr, 0.0018), 1.1, ang, 1.6)
    ex = cx + math.cos(ang) * r * (1.6 + length * 2.9)
    ey = cy + math.sin(ang) * r * (1.6 + length * 2.9)
    blob(F, ex, ey, r * 0.42, 1.3)


def run_down(F, x, y, r, length):
    """A run of blood flowing down a wall (+y) from (x, y), wobbling, with a bead at its foot."""
    steps = max(6, int(length * W / 6))
    px = x
    for i in range(steps):
        f = i / steps
        px += rng.normal(0, 0.0008)
        rr = r * (0.75 - 0.25 * f + 0.1 * math.sin(f * 17.0))
        blob(F, px, y + length * f, max(rr, 0.0015), 1.05, math.pi / 2, 1.8)
    blob(F, px, y + length, r * 1.05, 1.35)


def crown(F, cx, cy, r, n, spike):
    for k in range(n):
        a = k / n * math.tau + rng.uniform(-0.12, 0.12)
        L = spike * rng.uniform(0.4, 1.2)
        for i in range(4):
            f = (i + 1) / 4
            blob(F, cx + math.cos(a) * r * (0.95 + L * f), cy + math.sin(a) * r * (0.95 + L * f),
                 r * 0.11 * (1.25 - f * 0.6), 1.0, a, 1.7)
        if rng.random() < 0.45:   # a bead thrown off the spike tip
            d = r * (1.15 + L * 1.5 + rng.uniform(0.05, 0.4))
            blob(F, cx + math.cos(a) * d, cy + math.sin(a) * d, r * rng.uniform(0.05, 0.11), 1.2)


def satellites(F, cx, cy, r0, r1, n, size, ang=None, spread=math.pi):
    for _ in range(n):
        a = rng.uniform(-math.pi, math.pi) if ang is None else ang + rng.uniform(-spread, spread)
        d = rng.uniform(r0, r1)
        sz = size * rng.uniform(0.35, 1.0) ** 1.5
        if rng.random() < 0.5:
            drop_with_tail(F, cx + math.cos(a) * d, cy + math.sin(a) * d, sz, a, rng.uniform(0.2, 1.0))
        else:
            blob(F, cx + math.cos(a) * d, cy + math.sin(a) * d, sz, 1.25)


# ------------------------------------------------------------------ cells

def cell_drop(seed):
    F = np.zeros((W, W), np.float32)
    r = 0.1 + 0.04 * rng.random()
    blob(F, 0.5, 0.5, r, 1.5, rng.uniform(0, math.pi), rng.uniform(1.0, 1.25))
    for _ in range(8):   # lumpy body
        a = rng.uniform(0, math.tau)
        blob(F, 0.5 + math.cos(a) * r * 0.5, 0.5 + math.sin(a) * r * 0.5, r * rng.uniform(0.35, 0.75), 0.75)
    crown(F, 0.5, 0.5, r * 1.15, int(rng.integers(14, 26)), rng.uniform(0.35, 0.7))
    satellites(F, 0.5, 0.5, r * 1.9, 0.46, int(rng.integers(6, 14)), 0.012)
    return F, 0.18, 0.8


def cell_directional(seed):
    F = np.zeros((W, W), np.float32)
    r = 0.05 + 0.02 * rng.random()
    cx, cy = 0.5, 0.24
    blob(F, cx, cy, r, 1.5, math.pi / 2, 1.45)   # the drop's body, stretched the way it flew
    for k in range(int(rng.integers(6, 12))):    # scalloped rim, spines thrown forward
        a = math.pi / 2 + rng.uniform(-1.5, 1.5)
        blob(F, cx + math.cos(a) * r * 1.05, cy + math.sin(a) * r * 1.4, r * rng.uniform(0.1, 0.17), 1.0, a, 1.9)
    L = rng.uniform(0.25, 0.5)
    steps = 36
    x = cx
    for i in range(steps):
        f = i / steps
        x += rng.normal(0, 0.0006)
        blob(F, x, cy + r * 1.2 + L * f, max(r * 0.3 * (1.0 - f * 0.75), 0.003), 1.15, math.pi / 2, 2.0)
    blob(F, x, cy + r * 1.25 + L + 0.012, r * 0.33, 1.4)
    satellites(F, x, cy + r * 1.3 + L, 0.03, 0.16, int(rng.integers(2, 6)), 0.008, math.pi / 2, 0.3)
    return F, 0.2, 0.75


def cell_burst(seed, heavy=False):
    F = np.zeros((W, W), np.float32)
    cx, cy = 0.5, 0.36
    r = 0.06 if not heavy else 0.09
    blob(F, cx, cy, r, 1.5)
    for _ in range(6 if not heavy else 10):
        a = rng.uniform(0, math.tau)
        blob(F, cx + math.cos(a) * r * 0.7, cy + math.sin(a) * r * 0.7, r * rng.uniform(0.4, 0.75), 0.9)
    n = 70 if not heavy else 120
    for _ in range(n):
        a = rng.normal(0.0, 1.3)          # fan biased toward +x (the shot's direction across the wall)
        d = r * 1.1 + abs(rng.normal(0, 0.17 if not heavy else 0.22))
        sz = max(0.004, 0.022 * (1.0 - min(d / 0.5, 0.92)) * rng.uniform(0.4, 1.1))
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
        if 0.03 < x < 0.97 and 0.03 < y < 0.97:
            drop_with_tail(F, x, y, sz, a, rng.uniform(0.3, 1.6))
    for _ in range(int(rng.integers(3, 6)) + (3 if heavy else 0)):   # runs dripping down the wall
        x = cx + rng.uniform(-r * 1.4, r * 1.4)
        run_down(F, x, cy + r * 0.4, rng.uniform(0.008, 0.013), rng.uniform(0.18, 0.5))
    mist(F, cx, cy, 160 if not heavy else 260, 0.32)
    return F, 0.2, 0.85


def mist(F, cx, cy, n, spread):
    for _ in range(n):
        a = rng.normal(0.0, 1.5)
        d = abs(rng.normal(0, spread))
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
        if 0.02 < x < 0.98 and 0.02 < y < 0.98:
            blob(F, x, y, 0.0018 + 0.004 * rng.random() ** 3, 1.3)


def cell_mist(seed):
    F = np.zeros((W, W), np.float32)
    mist(F, 0.5, 0.5, 900, 0.2)
    satellites(F, 0.5, 0.5, 0.05, 0.35, 25, 0.008)
    return F, 0.22, 0.6


def cell_pool(seed):
    F = np.zeros((W, W), np.float32)
    for _ in range(int(rng.integers(7, 12))):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0, 0.13)
        blob(F, 0.5 + math.cos(a) * d, 0.5 + math.sin(a) * d * 0.85, rng.uniform(0.08, 0.12), 1.0)
    # A couple of lobes that ran off along the floor's slope.
    for _ in range(int(rng.integers(1, 4))):
        a = rng.uniform(0, math.tau)
        blob(F, 0.5 + math.cos(a) * 0.22, 0.5 + math.sin(a) * 0.22, rng.uniform(0.035, 0.06), 0.9, a, 1.7)
    satellites(F, 0.5, 0.5, 0.33, 0.42, 6, 0.011)
    return F, 0.35, 1.0


def cell_smear(seed):
    F = np.zeros((W, W), np.float32)
    streak = fbm(3, 3, seed + 11)
    # Striations run along the drag (+U): noise that changes fast across it and slowly along it.
    lines = np.array(Image.fromarray(rng.standard_normal((90, 6)).astype(np.float32)).resize((W, W), Image.BICUBIC))
    for i in range(48):
        f = i / 47
        blob(F, 0.26 + 0.52 * f, 0.5 + 0.04 * math.sin(f * 5.0), 0.07 * (1.0 - 0.55 * f) + 0.018, 0.5, 0.0, 1.5)
    F *= np.clip(0.8 + lines * 0.35 + streak * 0.2, 0.0, 2.0)
    satellites(F, 0.24, 0.5, 0.08, 0.16, 6, 0.01)
    return F, 0.25, 0.55


def cell_trail(seed):
    F = np.zeros((W, W), np.float32)
    y = 0.06
    while y < 0.94:
        x = 0.5 + rng.normal(0, 0.06)
        r = rng.uniform(0.012, 0.03)
        blob(F, x, y, r, 1.5)
        crown(F, x, y, r * 1.1, int(rng.integers(6, 11)), 0.5)
        y += rng.uniform(0.07, 0.15)
    return F, 0.2, 0.7


# ------------------------------------------------------------------ shading

def shade(F, T, thick_gain, seed):
    """Field -> (albedo RGBA, normal RGBA) at W, then downsampled to S."""
    noise = fbm(6, 4, seed) * 0.06
    G = F + noise * np.clip(F * 3.0, 0, 1)
    inside = G > T
    # Anti-aliased coverage across the threshold.
    gy, gx = np.gradient(G)
    gl = np.sqrt(gx * gx + gy * gy) + 1e-6
    cov = np.clip(0.5 + (G - T) / gl / 1.2, 0.0, 1.0)
    dist = ndimage.distance_transform_edt(inside).astype(np.float32)
    # Thickness: how deep inside the field, shaped so small droplets are thin and pools thick.
    h = np.clip((G - T) / (T * 2.5) * thick_gain, 0.0, 1.0)
    h = np.maximum(h, np.clip(dist / 14.0, 0.0, 1.0) * thick_gain)
    h = np.clip(h, 0.0, 1.0)
    # Colour: thin film bright red, thick nearly black-red; a darker meniscus line at the very edge.
    # Linear albedo: real blood is dark (a thin film still reads red, a pool almost black-red); wetness comes from the
    # low roughness, not from brightness.
    thin = np.array([0.3, 0.022, 0.018], np.float32)
    mid = np.array([0.16, 0.005, 0.007], np.float32)
    dark = np.array([0.065, 0.0, 0.003], np.float32)
    t1 = np.clip(h * 3.0, 0, 1)[..., None]
    t2 = np.clip(h * 1.6 - 0.6, 0, 1)[..., None]
    col = thin * (1 - t1) + mid * t1
    col = col * (1 - t2) + dark * t2
    rim = np.exp(-dist / 2.5)[..., None] * 0.3
    col = col * (1.0 - rim)
    col *= (1.0 + fbm(14, 3, seed + 3)[..., None] * 0.08)
    a = cov * (0.8 + 0.2 * np.sqrt(h))
    # Height: meniscus (steep at the edge, then flat) scaled by thickness; normal from its slope.
    Hh = (1.0 - np.exp(-dist / 6.0)) * (0.35 + 0.65 * h)
    Hh = ndimage.gaussian_filter(Hh, 1.2)
    dy, dx = np.gradient(Hh)
    k = 7.0
    n = np.dstack([-dx * k, dy * k, np.ones_like(Hh)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    rough = 0.05 + 0.12 * (1.0 - h) + 0.08 * np.clip(1.0 - dist / 4.0, 0, 1)
    alb = np.dstack([np.clip(col, 0, 1) ** (1 / 2.2), a])          # sRGB colour
    nrm = np.dstack([n * 0.5 + 0.5, rough])
    alb[~(cov > 0)] = [0.4, 0.02, 0.02, 0.0]                         # colour outside, so mips don't bleed dark
    nrm[~(cov > 0)] = [0.5, 0.5, 1.0, 0.3]
    to = lambda x: Image.fromarray((np.clip(x, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").resize((S, S), Image.LANCZOS)
    return to(alb), to(nrm)


CELLS = [
    lambda s: cell_drop(s), lambda s: cell_drop(s), lambda s: cell_drop(s), lambda s: cell_drop(s),
    lambda s: cell_directional(s), lambda s: cell_directional(s), lambda s: cell_directional(s), lambda s: cell_directional(s),
    lambda s: cell_burst(s), lambda s: cell_burst(s), lambda s: cell_mist(s), lambda s: cell_burst(s, True),
    lambda s: cell_pool(s), lambda s: cell_pool(s), lambda s: cell_smear(s), lambda s: cell_trail(s),
]


def preview(alb, nrm, path):
    """Lit check render: each cell on concrete grey under a raking light, as the game would roughly show it."""
    A = np.asarray(alb).astype(np.float32) / 255
    N = np.asarray(nrm).astype(np.float32) / 255
    base = np.full(A.shape[:2] + (3,), 0.42, np.float32) * (0.9 + 0.1 * np.random.default_rng(1).random(A.shape[:2]))[..., None]
    lin = A[..., :3] ** 2.2
    n = N[..., :3] * 2 - 1
    L = np.array([-0.5, -0.45, 0.74]); L /= np.linalg.norm(L)
    V = np.array([0, 0, 1.0]); Hv = (L + V); Hv /= np.linalg.norm(Hv)
    ndl = np.clip((n * L).sum(-1), 0, 1)[..., None]
    rough = N[..., 3:4]
    shin = 2.0 / np.maximum(rough ** 4, 1e-4)
    spec = np.clip((n * Hv).sum(-1), 0, 1)[..., None] ** np.minimum(shin, 4000) * 0.9
    lit = lin * ndl * 1.1 + spec * A[..., 3:4]
    out = base ** 2.2 * (1 - A[..., 3:4]) + lit * A[..., 3:4] + base ** 2.2 * 0.0
    Image.fromarray((np.clip(out, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).save(path)


def main():
    alb = Image.new("RGBA", (S * 4, S * 4))
    nrm = Image.new("RGBA", (S * 4, S * 4))
    for i, f in enumerate(CELLS):
        F, T, gain = f(1000 + i)
        a, n = shade(F, T, gain, 1000 + i)
        alb.paste(a, ((i % 4) * S, (i // 4) * S))
        nrm.paste(n, ((i % 4) * S, (i // 4) * S))
        print("cell", i)
    alb.save(os.path.join(OUT, "blood_albedo.png"))
    nrm.save(os.path.join(OUT, "blood_normal.png"))
    if "--preview" in sys.argv:
        preview(alb, nrm, sys.argv[sys.argv.index("--preview") + 1])
    print("wrote", os.path.join(OUT, "blood_albedo.png"))


if __name__ == "__main__":
    main()
