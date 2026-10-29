"""Fabric and surface layers for player outfits: one texture array (16 layers, 256 px, tileable), all procedural.

    python -I tools/make_gear_textures.py          (then bash tools/import.sh)

game/assets/models/gear/gear_albedo.png   256 x 4096: layers stacked top to bottom (imported as a Texture2DArray)
game/assets/models/gear/gear_normal.png   same, tangent-space normals (OpenGL convention)
work/gear_textures_preview.png            the layers side by side

Layers (the index is what tools/blender/make_gear.py writes into each vertex's second UV):
 0 skin, 1 cotton jersey, 2 denim twill, 3 leather, 4 nylon ripstop, 5 canvas, 6 rubber, 7 hard plastic,
 8 woodland camo, 9 athletic stripes, 10 knit, 11 sports mesh, 12 woven rice sack, 13 plaid flannel, 14 quilted,
 15 metal (painted, worn)
Albedo is mostly light grey so each item's colourway tints it; camo, stripes and plaid carry their own pattern.
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'assets', 'models', 'gear')
N = 256
yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)


def tile_noise(freq, seed, octaves=4):
    """Tileable value noise (periodic lattice), 0..1."""
    rng = np.random.default_rng(seed)
    out = np.zeros((N, N))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        f = freq * 2 ** o
        g = rng.random((f, f))
        gx = xx / N * f
        gy = yy / N * f
        x0 = np.floor(gx).astype(int) % f
        y0 = np.floor(gy).astype(int) % f
        x1 = (x0 + 1) % f
        y1 = (y0 + 1) % f
        fx = gx - np.floor(gx)
        fy = gy - np.floor(gy)
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        v = g[y0, x0] * (1 - fx) * (1 - fy) + g[y0, x1] * fx * (1 - fy) + g[y1, x0] * (1 - fx) * fy + g[y1, x1] * fx * fy
        out += v * amp
        tot += amp
        amp *= 0.5
    return out / tot


def layer(base, height, rough=None):
    return np.clip(base, 0, 1), height


def grey(v):
    return np.dstack([v, v, v])


def make():
    L = []
    # 0 skin: faint pores and blotches (tinted per skin tone)
    n = tile_noise(8, 1)
    L.append(layer(grey(0.86 + 0.08 * n), n * 0.3))
    # 1 cotton jersey: fine knit rows
    rows = 0.5 + 0.5 * np.sin(yy / N * 2 * np.pi * 96)
    n = tile_noise(16, 2)
    L.append(layer(grey(0.78 + 0.08 * rows + 0.08 * n), rows * 0.5 + n * 0.2))
    # 2 denim twill: diagonal weave, blue-ish white weft showing (tint gives the indigo)
    tw = 0.5 + 0.5 * np.sin((xx + yy) / N * 2 * np.pi * 64)
    n = tile_noise(8, 3)
    fade = tile_noise(4, 33, 3)
    L.append(layer(grey(0.62 + 0.18 * tw + 0.16 * n + 0.1 * fade), tw * 0.8))
    # 3 leather: grain cells and creases
    n = tile_noise(32, 4, 3)
    cr = tile_noise(6, 44)
    L.append(layer(grey(0.7 + 0.12 * n - 0.1 * (cr > 0.62)), n * 0.6 - (cr > 0.62) * 0.4))
    # 4 nylon ripstop: grid every 16 px over a smooth field
    grid = ((xx % 16) < 1.2) | ((yy % 16) < 1.2)
    n = tile_noise(8, 5)
    L.append(layer(grey(0.8 + 0.06 * n + 0.08 * grid), grid.astype(float) * 0.6))
    # 5 canvas: coarse plain weave
    w = (0.5 + 0.5 * np.sin(xx / N * 2 * np.pi * 48)) * (0.5 + 0.5 * np.sin(yy / N * 2 * np.pi * 48))
    n = tile_noise(8, 6)
    L.append(layer(grey(0.7 + 0.18 * w + 0.1 * n), w * 0.8))
    # 6 rubber: almost flat, a little mottling
    n = tile_noise(8, 7)
    L.append(layer(grey(0.75 + 0.08 * n), n * 0.15))
    # 7 hard plastic: smooth, faint scuffs
    sc = (tile_noise(64, 8, 2) > 0.8) * 0.12
    L.append(layer(grey(0.85 - sc), -sc))
    # 8 woodland camo: four colours in blotches
    a = tile_noise(4, 9)
    b = tile_noise(5, 10)
    cols = np.array([[0.32, 0.36, 0.22], [0.5, 0.45, 0.3], [0.2, 0.22, 0.15], [0.12, 0.1, 0.08]])
    idx = (a > 0.55).astype(int) + (b > 0.6).astype(int) * 2
    camo = cols[np.clip(idx, 0, 3)] * (0.92 + 0.08 * tile_noise(32, 11, 2))[..., None]
    L.append(layer(camo * 1.6, tile_noise(32, 12, 2) * 0.3))
    # 9 athletic stripes: white field with two side stripes per tile
    st = (((xx % 128) > 52) & ((xx % 128) < 62)) | (((xx % 128) > 68) & ((xx % 128) < 78))
    L.append(layer(np.dstack([0.92 - 0.6 * st, 0.92 - 0.6 * st, 0.92 - 0.6 * st]), st.astype(float) * 0.2))
    # 10 knit: chunky V stitches
    v = np.abs(((xx % 16) - 8) / 8.0) * 0.5 + 0.5 * np.sin(yy / N * 2 * np.pi * 32 + np.abs((xx % 16) - 8) * 0.4)
    L.append(layer(grey(0.65 + 0.3 * v), v))
    # 11 sports mesh: hex-ish holes
    hole = (np.sin(xx / N * 2 * np.pi * 40) * np.sin(yy / N * 2 * np.pi * 40)) > 0.55
    L.append(layer(grey(0.85 - 0.45 * hole), -hole.astype(float) * 0.6))
    # 12 woven rice sack: wide flat polypropylene strips, cream with a printed band
    w2 = ((xx % 12) < 9) ^ ((yy % 12) < 9)
    band = ((yy % 256) > 96) & ((yy % 256) < 128)
    sack = np.dstack([0.86 + 0.06 * w2, 0.84 + 0.06 * w2, 0.76 + 0.06 * w2])
    sack[band] = sack[band] * np.array([1.0, 0.45, 0.4])
    L.append(layer(sack, w2.astype(float) * 0.4))
    # 13 plaid flannel: crossing bands (red/black by default; tint shifts it)
    bx = (np.floor(xx / 32) % 2) + ((xx % 64) < 6)
    by = (np.floor(yy / 32) % 2) + ((yy % 64) < 6)
    p = (bx + by) / 4.0
    plaid = np.dstack([0.3 + 0.6 * (1 - p), 0.12 + 0.1 * (1 - p), 0.1 + 0.08 * (1 - p)])
    L.append(layer(plaid * 1.3, tile_noise(32, 13, 2) * 0.3))
    # 14 quilted: diamond stitch lines with puffed cells
    d1 = np.abs(((xx + yy) % 64) - 32) / 32.0
    d2 = np.abs(((xx - yy) % 64) - 32) / 32.0
    puff = np.minimum(d1, d2)
    L.append(layer(grey(0.6 + 0.35 * puff), puff * 1.2))
    # 15 metal: painted, edge wear and scratches
    n = tile_noise(8, 14)
    scr = (tile_noise(64, 15, 2) > 0.78)
    L.append(layer(grey(0.62 + 0.1 * n + 0.25 * scr), -scr.astype(float) * 0.2))

    alb = np.zeros((N * len(L), N, 3))
    nrm = np.zeros((N * len(L), N, 3))
    for i, (a, h) in enumerate(L):
        alb[i * N:(i + 1) * N] = a
        gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * 4.0
        gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * 4.0
        l = np.sqrt(gx * gx + gy * gy + 1)
        nrm[i * N:(i + 1) * N] = np.dstack([-gx / l * 0.5 + 0.5, gy / l * 0.5 + 0.5, 1 / l * 0.5 + 0.5])
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((alb * 255).astype(np.uint8)).save(os.path.join(OUT, 'gear_albedo.png'))
    Image.fromarray((nrm * 255).astype(np.uint8)).save(os.path.join(OUT, 'gear_normal.png'))
    # Godot imports these two as texture arrays (16 slices, top to bottom).
    for name in ['gear_albedo.png', 'gear_normal.png']:
        imp = os.path.join(OUT, name + '.import')
        if not os.path.exists(imp) or 'texture_2d_array' not in open(imp, encoding='utf-8').read():
            with open(imp, 'w', encoding='utf-8', newline='\n') as f:
                f.write('[remap]\n\nimporter="2d_array_texture"\ntype="CompressedTexture2DArray"\n\n[deps]\n\n'
                        'source_file="res://assets/models/gear/%s"\n\n[params]\n\ncompress/mode=2\ncompress/high_quality=false\n'
                        'compress/lossy_quality=0.7\ncompress/hdr_compression=1\ncompress/channel_pack=0\nmipmaps/generate=true\n'
                        'mipmaps/limit=-1\nslices/horizontal=1\nslices/vertical=%d\n# texture_2d_array\n' % (name, len(L)))
    prev = np.concatenate([alb[i * N:(i + 1) * N] for i in range(len(L))], 1)
    prev = prev[::2, ::2]
    os.makedirs(os.path.join(ROOT, 'work'), exist_ok=True)
    Image.fromarray((prev * 255).astype(np.uint8)).save(os.path.join(ROOT, 'work', 'gear_textures_preview.png'))
    print('layers', len(L))


if __name__ == '__main__':
    make()
