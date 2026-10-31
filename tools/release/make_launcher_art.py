"""Launcher and website art from the game's own key art (docs/HOSTING.md).

    python -I tools/release/make_launcher_art.py

The icon is the artificial sun over Sitio Kalinaw from the menu art (game/assets/ui/menu_bg.jpg): a hot core inside
its ring, over a dark skyline. Writes launcher/shared/ (icon PNGs for the macOS iconset, launcher background),
launcher/windows/Assets/app.ico and website/assets/ (favicon, social card source).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SHARED = ROOT / "launcher" / "shared"
WIN = ROOT / "launcher" / "windows" / "Assets"
WEB = ROOT / "website" / "assets"


def radial(size, cx, cy, r, color, alpha):
    """A soft radial glow layer."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(r * 0.45))


def icon(size=1024):
    s = size * 2  # supersampled
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    # Rounded dark tile with a warm haze toward the sun.
    tile = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    m = Image.new("L", (s, s), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * 0.22), fill=255)
    base = Image.new("RGBA", (s, s), (10, 12, 16, 255))
    grad = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(s):
        t = y / s
        gd.line([(0, y), (s, y)], fill=(int(24 + 10 * (1 - t)), int(18 + 6 * (1 - t)), int(14), int(120 * (1 - t))))
    base = Image.alpha_composite(base, grad)
    cx, cy = s * 0.5, s * 0.44
    base = Image.alpha_composite(base, radial(s, cx, cy, s * 0.42, (242, 140, 40), 150))
    base = Image.alpha_composite(base, radial(s, cx, cy, s * 0.26, (255, 175, 70), 200))
    d = ImageDraw.Draw(base)
    # The ring.
    r = s * 0.23
    ring = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 196, 110, 255), width=int(s * 0.028))
    base = Image.alpha_composite(base, ring.filter(ImageFilter.GaussianBlur(s * 0.012)))
    base = Image.alpha_composite(base, ring)
    # The core.
    base = Image.alpha_composite(base, radial(s, cx, cy, s * 0.12, (255, 236, 200), 255))
    c = s * 0.085
    d = ImageDraw.Draw(base)
    d.ellipse([cx - c, cy - c, cx + c, cy + c], fill=(255, 248, 232, 255))
    # Skyline of shanty roofs along the bottom, with a few window lights.
    sky = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sky)
    y0 = s * 0.80
    import random
    rng = random.Random(7)
    x = 0
    pts = [(0, s)]
    while x < s:
        w = s * rng.uniform(0.05, 0.11)
        h = s * rng.uniform(0.0, 0.07)
        pts += [(x, y0 - h), (x + w * 0.5, y0 - h - s * rng.uniform(0.0, 0.025)), (x + w, y0 - h)]
        x += w
    pts += [(s, y0), (s, s)]
    sd.polygon(pts, fill=(7, 8, 11, 255))
    for _ in range(26):
        lx, ly = rng.uniform(0.04, 0.96) * s, rng.uniform(0.84, 0.95) * s
        lr = s * 0.006
        sd.ellipse([lx - lr, ly - lr, lx + lr, ly + lr], fill=(255, 190, 110, 230))
    base = Image.alpha_composite(base, sky)
    img.paste(base, (0, 0), m)
    return img.resize((size, size), Image.LANCZOS)


def main():
    for d in (SHARED, WIN, WEB):
        d.mkdir(parents=True, exist_ok=True)
    big = icon(1024)
    big.save(SHARED / "icon_1024.png")
    for n in (16, 32, 64, 128, 256, 512):
        big.resize((n, n), Image.LANCZOS).save(SHARED / ("icon_%d.png" % n))
    big.save(WIN / "app.ico", sizes=[(16, 16), (20, 20), (24, 24), (32, 32), (40, 40), (48, 48), (64, 64), (128, 128), (256, 256)])
    big.resize((256, 256), Image.LANCZOS).save(WIN / "icon_256.png")
    big.resize((180, 180), Image.LANCZOS).save(WEB / "apple-touch-icon.png")
    big.resize((64, 64), Image.LANCZOS).save(WEB / "favicon.png")
    bg = Image.open(ROOT / "game" / "assets" / "ui" / "menu_bg.jpg").convert("RGB")
    bg.resize((1600, 900), Image.LANCZOS).save(SHARED / "background.jpg", quality=84, optimize=True, progressive=True)
    print("art written: %s, %s, %s" % (SHARED, WIN, WEB))


if __name__ == "__main__":
    main()
