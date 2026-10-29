"""Tileable cloth and leather textures for the first-person sleeves and gloves (greyscale, tinted in the game).

    python -I tools/make_fp_arms_textures.py

Writes game/assets/models/fp_arms/{fabric,fabric_n,leather,leather_n}.png (256 px, seamless).
"""
import math
import os
import random

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'assets', 'models', 'fp_arms')
N = 256


def tile_noise(seed, scale, octaves=4):
    rnd = random.Random(seed)
    acc = [[0.0] * N for _ in range(N)]
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cells = scale * (2 ** o)
        grid = [[rnd.random() for _ in range(cells)] for _ in range(cells)]
        for y in range(N):
            gy = y * cells / N
            y0 = int(gy) % cells
            y1 = (y0 + 1) % cells
            fy = gy - int(gy)
            fy = fy * fy * (3 - 2 * fy)
            for x in range(N):
                gx = x * cells / N
                x0 = int(gx) % cells
                x1 = (x0 + 1) % cells
                fx = gx - int(gx)
                fx = fx * fx * (3 - 2 * fx)
                a = grid[y0][x0] + (grid[y0][x1] - grid[y0][x0]) * fx
                b = grid[y1][x0] + (grid[y1][x1] - grid[y1][x0]) * fx
                acc[y][x] += (a + (b - a) * fy) * amp
        tot += amp
        amp *= 0.5
    return [[v / tot for v in row] for row in acc]


def height_to_normal(h, strength):
    img = Image.new('RGB', (N, N))
    px = img.load()
    for y in range(N):
        for x in range(N):
            dx = (h[y][(x + 1) % N] - h[y][(x - 1) % N]) * strength
            dy = (h[(y + 1) % N][x] - h[(y - 1) % N][x]) * strength
            l = math.sqrt(dx * dx + dy * dy + 1.0)
            px[x, y] = (int((-dx / l * 0.5 + 0.5) * 255), int((-dy / l * 0.5 + 0.5) * 255), int((1.0 / l * 0.5 + 0.5) * 255))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    # Cloth: a fine twill weave (diagonal ribs every 4 px) over soft mottling.
    mott = tile_noise(11, 4)
    h = [[0.0] * N for _ in range(N)]
    img = Image.new('L', (N, N))
    px = img.load()
    for y in range(N):
        for x in range(N):
            rib = 0.5 + 0.5 * math.sin((x + y) * 2 * math.pi / 4.0)
            warp = 0.5 + 0.5 * math.sin(y * 2 * math.pi / 2.0)
            h[y][x] = rib * 0.7 + warp * 0.3
            v = 0.78 + 0.12 * (rib - 0.5) + 0.25 * (mott[y][x] - 0.5)
            px[x, y] = max(0, min(255, int(v * 255)))
    img.save(os.path.join(OUT, 'fabric.png'))
    height_to_normal(h, 1.6).save(os.path.join(OUT, 'fabric_n.png'))
    # Leather: pebbled grain and creases.
    grain = tile_noise(23, 32, 2)
    crease = tile_noise(37, 6, 3)
    img = Image.new('L', (N, N))
    px = img.load()
    h = [[0.0] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            c = abs(crease[y][x] - 0.5) * 2.0
            v = 0.72 + 0.18 * (grain[y][x] - 0.5) - 0.18 * max(0.0, 0.12 - c) / 0.12
            h[y][x] = grain[y][x] * 0.6 + c * 0.4
            px[x, y] = max(0, min(255, int(v * 255)))
    img.filter(ImageFilter.SMOOTH).save(os.path.join(OUT, 'leather.png'))
    height_to_normal(h, 3.0).save(os.path.join(OUT, 'leather_n.png'))
    print('wrote', OUT)


if __name__ == '__main__':
    main()
