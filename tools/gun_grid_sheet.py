"""Contact sheet of the processed guns with a u/v grid for writing part boxes in process_items.py.

    python -I tools/gun_grid_sheet.py [--parts] [id ...]

Reads work/lemondev/r5/items/<id>.png (or <id>_parts.png) and <id>.view.json from process_items.py and draws the grid:
u in tenths from the muzzle (left) to the butt, v in tenths from the bottom. Writes work/lemondev/r5/items/grid_*.png.
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, 'work', 'lemondev', 'r5', 'items')


def gridded(gid, parts):
    v = json.load(open(os.path.join(D, gid + '.view.json')))
    im = Image.open(os.path.join(D, gid + ('_parts.png' if parts else '.png'))).convert('RGB')
    W, H = im.size
    s = W / v['ortho']
    lo, hi = v['lo'], v['hi']
    dr = ImageDraw.Draw(im)

    def px(y, z):
        return W / 2 - y * s, H / 2 - z * s

    for i in range(11):
        y = hi[1] - (hi[1] - lo[1]) * i / 10
        x0, y0 = px(y, lo[2])
        x1, y1 = px(y, hi[2])
        dr.line([(x0, y0 + 8), (x1, y1 - 8)], fill=(255, 60, 60) if i % 5 == 0 else (255, 160, 160), width=1)
        dr.text((x0 - 6, y0 + 10), str(i), fill=(255, 255, 0))
        z = lo[2] + (hi[2] - lo[2]) * i / 10
        a = px(lo[1], z)
        b = px(hi[1], z)
        dr.line([(a[0] - 8, a[1]), (b[0] + 8, b[1])], fill=(60, 120, 255) if i % 5 == 0 else (150, 190, 255), width=1)
        dr.text((b[0] + 10, b[1] - 6), str(i), fill=(120, 255, 255))
    dr.text((6, 6), gid, fill=(255, 255, 0))
    return im


def main():
    args = sys.argv[1:]
    parts = '--parts' in args
    ids = [a for a in args if not a.startswith('--')] or sorted(f[:-10] for f in os.listdir(D) if f.endswith('.view.json'))
    for i in range(0, len(ids), 6):
        chunk = ids[i:i + 6]
        S = Image.new('RGB', (2000, 500 * ((len(chunk) + 1) // 2)), (30, 30, 30))
        for k, gid in enumerate(chunk):
            S.paste(gridded(gid, parts), ((k % 2) * 1000, (k // 2) * 500))
        out = os.path.join(D, 'grid_%s%d.png' % ('p' if parts else '', i // 6))
        S.save(out)
        print(out)


if __name__ == '__main__':
    main()
