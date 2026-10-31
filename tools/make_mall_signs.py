"""r11: shop signs for Lawless Mall, in the style of the street sign atlas (tools/build_urban_surfaces.py signs()).

    python -I tools/make_mall_signs.py      (then bash tools/import.sh)

Writes game/assets/urban/signs_mall.png (4 x 4 tiles of 512 x 256) and signs_mall.json (labels in tile order).
Tile 0 is the main sign over the entrance; the rest go over the storefronts and anchors (facade_detail.gd _mall_signs).
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent / 'game' / 'assets' / 'urban'
LABELS = [('Lawless Mall', 'Open Daily · 10 AM - 9 PM'), ('Bayani Shoes', 'Footwear'), ('Kalye Mobile', 'Phones & Repairs'),
          ('Kape Lawless', 'Coffee & Bread'), ('Ukay Fashion', 'Clothing'), ('Tindahan Plus', 'Home & Kitchen'),
          ('Arcade Zone', 'Games & Prizes'), ('Food Court', 'Eat Here'), ('Supermarket', 'Fresh & Frozen'),
          ('Botika', 'Pharmacy'), ('Optika', 'Eyeglasses'), ('Bookstore', 'School Supplies'), ('Toy World', 'Toys & Gifts'),
          ('Management', 'Office'), ('Restrooms', 'This Way'), ('Lucky Gold', 'Jewellery')]
PALETTE = ['#1d3f6e', '#8a2f2a', '#2f5d3a', '#6b4a2b', '#5a2d63', '#2b5f66', '#7d5b18', '#3a3f45']


def main():
    atlas = Image.new('RGBA', (2048, 1024), (0, 0, 0, 0))
    bold = 'C:/Windows/Fonts/arialbd.ttf'
    reg = 'C:/Windows/Fonts/arial.ttf'
    for i, (label, sub) in enumerate(LABELS):
        bg = '#f2efe6' if i == 0 else PALETTE[i % len(PALETTE)]
        fg = '#16324f' if i == 0 else '#fff6e0'
        im = Image.new('RGBA', (512, 256), bg)
        d = ImageDraw.Draw(im)
        d.rectangle((10, 10, 501, 245), outline='#c9b98f' if i else '#16324f', width=5)
        fs = 66 if i == 0 else 58
        while d.textbbox((0, 0), label, font=ImageFont.truetype(bold, fs))[2] > 462:
            fs -= 2
        d.text((256, 100), label, font=ImageFont.truetype(bold, fs), anchor='mm', fill=fg)
        d.line((86, 150, 426, 150), fill='#c9b98f', width=2)
        d.text((256, 190), sub, font=ImageFont.truetype(reg, 28), anchor='mm', fill=fg)
        rng = np.random.default_rng(900 + i)
        for _ in range(110):
            x, y = int(rng.integers(10, 502)), int(rng.integers(10, 246))
            if x < 22 or x > 490 or y < 24 or y > 232:
                d.line((x, y, x + int(rng.integers(1, 9)), y), fill=(120, 112, 96, 255), width=1)
        atlas.alpha_composite(im, ((i % 4) * 512, (i // 4) * 256))
    atlas.save(OUT / 'signs_mall.png', optimize=True)
    (OUT / 'signs_mall.json').write_text(json.dumps([x[0] for x in LABELS], indent=2) + '\n')
    print('wrote', OUT / 'signs_mall.png')


if __name__ == '__main__':
    main()
