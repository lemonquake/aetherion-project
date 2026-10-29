"""Menu textures (procedural): nine-slice panels and buttons with grain and wear, a grain tile, hazard tape, and
the outfit card thumbnails from the gear check renders.

    python -I tools/make_ui_textures.py        (after tools/blender/render_gear.py for thumbnails; then bash tools/import.sh)

Writes game/assets/ui/*.png and game/assets/ui/gear/<item>.png.
"""
import glob
import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'game', 'assets', 'ui')
RNG = np.random.default_rng(31)


def rounded_mask(w, h, r):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    cx = np.clip(x, r, w - 1 - r)
    cy = np.clip(y, r, h - 1 - r)
    d = np.hypot(x - cx, y - cy)
    return np.clip(r - d + 0.5, 0, 1)


def noise(w, h, s=1.0):
    n = RNG.standard_normal((h, w))
    img = Image.fromarray(((n * 0.5 + 0.5).clip(0, 1) * 255).astype(np.uint8))
    if s > 0:
        img = img.filter(ImageFilter.GaussianBlur(s))
    return np.asarray(img).astype(np.float64) / 255.0


def save(name, rgba):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, name))


def plate(w, h, base, alpha, r, border=0.07, top=0.08, brushed=True, accent=None):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    m = rounded_mask(w, h, r)
    inner = rounded_mask(w - 2, h - 2, r - 1)
    inner = np.pad(inner, 1)
    edge = np.clip(m - inner, 0, 1)
    g = 1.0 + 0.06 * (1 - y / h)                       # lighter at the top
    n = noise(w, h, 0.6) - 0.5
    col = np.zeros((h, w, 3)) + np.array(base)[None, None, :] / 255.0
    col *= g[..., None]
    col += n[..., None] * 0.035
    if brushed:
        b = noise(w, h, 0) - 0.5
        b = np.asarray(Image.fromarray(((b + 0.5) * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(0)).resize((w, h))).astype(float) / 255 - 0.5
        streak = np.repeat(noise(w, 1, 0)[0:1, :], h, 0) - 0.5
        col += streak[..., None] * 0.02
    a = m * alpha
    col = col * (1 - edge[..., None]) + (col + border) * edge[..., None]
    a = np.maximum(a, edge * min(alpha + 0.15, 1.0))
    topl = (y < 2.5) * m * top
    col += topl[..., None]
    if accent is not None:
        stripe = (x < 4) * m
        col = col * (1 - stripe[..., None]) + np.array(accent)[None, None, :] / 255.0 * stripe[..., None]
    return np.dstack([col, a])


def button_primary(w, h, c0, c1, r):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    m = rounded_mask(w, h, r)
    t = y / h
    col = np.array(c0)[None, None, :] / 255.0 * (1 - t[..., None]) + np.array(c1)[None, None, :] / 255.0 * t[..., None]
    stripes = ((x + y) % 14 < 6) * 0.05
    col = col * (1 - stripes[..., None]) + stripes[..., None] * 0.95
    col += (noise(w, h, 0.5) - 0.5)[..., None] * 0.04
    col += ((y < 2.5) * 0.12)[..., None]
    col -= ((y > h - 3.5) * 0.12)[..., None]
    return np.dstack([col, m])


def main():
    save('panel.png', plate(96, 96, (16, 19, 24), 0.86, 12))
    save('panel_light.png', plate(96, 96, (28, 32, 38), 0.92, 12, border=0.09))
    save('panel_accent.png', plate(96, 96, (22, 25, 30), 0.92, 12, accent=(242, 163, 58)))
    save('button.png', plate(64, 48, (32, 36, 43), 0.95, 9, border=0.1, top=0.1))
    save('button_hover.png', plate(64, 48, (46, 52, 60), 0.97, 9, border=0.16, top=0.14, accent=(242, 163, 58)))
    save('button_pressed.png', plate(64, 48, (58, 50, 38), 0.98, 9, border=0.2, top=0.05, accent=(255, 190, 90)))
    save('button_primary.png', button_primary(64, 64, (255, 186, 82), (224, 128, 26), 10))
    save('button_primary_hover.png', button_primary(64, 64, (255, 206, 120), (240, 150, 46), 10))
    save('button_primary_pressed.png', button_primary(64, 64, (226, 150, 50), (196, 108, 20), 10))
    # tab underline
    w, h = 32, 48
    tab = np.zeros((h, w, 4))
    tab[h - 4:, :, :3] = np.array([242, 163, 58]) / 255.0
    tab[h - 4:, :, 3] = 1.0
    tab[: h - 4, :, :3] = 1.0
    tab[: h - 4, :, 3] = np.linspace(0.0, 0.08, h - 4)[:, None]
    save('tab_active.png', tab)
    # grain tile
    g = noise(256, 256, 0.0)
    save('grain.png', np.dstack([g, g, g, np.full_like(g, 1.0)]))
    # hazard tape
    hy, hx = np.mgrid[0:16, 0:64].astype(np.float64)
    band = ((hx + hy) % 16) < 8
    hz = np.zeros((16, 64, 4))
    hz[..., :3] = np.where(band[..., None], np.array([242, 163, 58]) / 255.0, np.array([20, 20, 22]) / 255.0)
    hz[..., 3] = 1.0
    save('hazard.png', hz)
    # Outfit card thumbnails from the gear check renders (front views), cropped and shrunk.
    src = os.path.join(ROOT, 'work', 'gear')
    dst = os.path.join(OUT, 'gear')
    os.makedirs(dst, exist_ok=True)
    n = 0
    for f in sorted(glob.glob(os.path.join(src, '*_front.png'))):
        stem = os.path.basename(f).replace('_front.png', '')
        if stem.startswith('pack_'):
            f = f.replace('_front.png', '_back.png')   # a backpack is seen from behind
        im = Image.open(f).convert('RGB')
        w0, h0 = im.size
        head = stem.split('_')[0] in ('helmet', 'face', 'hair')
        box = (int(w0 * 0.12), int(h0 * 0.12), int(w0 * 0.88), int(h0 * 0.72)) if head else (int(w0 * 0.08), 0, int(w0 * 0.92), h0)
        im = im.crop(box).resize((180, 220) if not head else (180, 160), Image.LANCZOS)
        im.save(os.path.join(dst, stem + '.png'))
        n += 1
    print('ui textures written,', n, 'thumbnails')


if __name__ == '__main__':
    main()
