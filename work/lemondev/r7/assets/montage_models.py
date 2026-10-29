import sys, os
from PIL import Image, ImageDraw
d = sys.argv[1]; out = sys.argv[2]; names = sys.argv[3:]
W, H = 400, 300
rows = []
for n in names:
    row = Image.new('RGB', (2 * W, H + 18), (25, 25, 25))
    for i, suf in enumerate(['', '_top']):
        p = os.path.join(d, n + suf + '.png')
        if os.path.exists(p):
            row.paste(Image.open(p).convert('RGB').resize((W, H)), (i * W, 18))
    ImageDraw.Draw(row).text((4, 3), n + '  (3/4 front-right | top, front = down; red ball = front)', fill=(255, 255, 0))
    rows.append(row)
cols = 2
sheet = Image.new('RGB', (cols * 2 * W, ((len(rows) + cols - 1) // cols) * (H + 18)))
for i, r in enumerate(rows):
    sheet.paste(r, ((i % cols) * 2 * W, (i // cols) * (H + 18)))
sheet.save(out)
