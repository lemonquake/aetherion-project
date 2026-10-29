"""Writes game/src/world/maps/lawless_sub/paint.png: worn white road paint (RGBA, tinted per vertex in the game).

Alpha carries the wear: mostly solid paint with scuffed patches, cracks and grit where the asphalt shows through.
Tiles in both directions, so lane dashes and stalls can repeat it.
"""
import random
import sys
from pathlib import Path

from PIL import Image, ImageFilter

SIZE = 256
OUT = Path(__file__).resolve().parent.parent / "game/src/world/maps/lawless_sub/paint.png"


def noise_layer(rng, cells, size):
    small = Image.new("L", (cells, cells))
    small.putdata([rng.randint(0, 255) for _ in range(cells * cells)])
    # Tile seamlessly: wrap by pasting a 3x3 mosaic, scale, then crop the centre.
    big = Image.new("L", (cells * 3, cells * 3))
    for i in range(3):
        for j in range(3):
            big.paste(small, (i * cells, j * cells))
    big = big.resize((size * 3, size * 3), Image.BICUBIC)
    return big.crop((size, size, size * 2, size * 2))


def main():
    rng = random.Random(7)
    coarse = noise_layer(rng, 8, SIZE)
    mid = noise_layer(rng, 24, SIZE)
    fine = noise_layer(rng, 96, SIZE)
    px = []
    for c, m, f in zip(coarse.getdata(), mid.getdata(), fine.getdata()):
        wear = c * 0.5 + m * 0.35 + f * 0.15
        a = 255 if wear < 150 else max(0, 255 - int((wear - 150) * 4.0))
        if f > 236:
            a = int(a * 0.3)  # grit
        v = 236 + int((m - 128) * 0.06)
        px.append((v, v, v - 4, a))
    img = Image.new("RGBA", (SIZE, SIZE))
    img.putdata(px)
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print("wrote", OUT)


if __name__ == "__main__":
    sys.exit(main())
