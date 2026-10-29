"""Contact sheet of the same-scale cells rendered by process_r7.py --sheet (9 m across each cell)."""
import os, sys, re
from PIL import Image, ImageDraw
here = os.path.dirname(os.path.abspath(__file__))
log = open(os.path.join(here, 'sheet.log')).read().splitlines()
names = [l.split()[1] for l in log if l.startswith('[r7-sheet]') and 'MISSING' not in l]
dims = {l.split()[1]: ' '.join(l.split()[2:]) for l in log if l.startswith('[r7-sheet]')}
W, H, cols = 360, 300, 9
rows = (len(names) + cols - 1) // cols
sheet = Image.new('RGB', (cols * W, rows * (H + 16) + 28), (20, 20, 20))
d = ImageDraw.Draw(sheet)
d.text((6, 6), 'Aetherion r7 processed models - every cell the same orthographic scale (9 m across); blue figure = 1.8 m; front faces +Z (toward lower left)', fill=(255, 255, 255))
for i, n in enumerate(names):
    x, y = (i % cols) * W, 28 + (i // cols) * (H + 16)
    sheet.paste(Image.open(os.path.join(here, 'sheet', n + '.png')).convert('RGB'), (x, y + 16))
    d.text((x + 3, y + 2), '%s  %s m' % (n, dims[n]), fill=(255, 230, 0))
sheet.save(os.path.join(here, 'sheet.png'))
print(sheet.size, len(names))
