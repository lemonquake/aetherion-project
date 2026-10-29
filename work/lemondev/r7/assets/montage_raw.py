import sys, os, glob
from PIL import Image, ImageDraw
d = sys.argv[1]; out = sys.argv[2]; names = sys.argv[3:]
rows = []
for n in names:
    ims = [Image.open(os.path.join(d, '_%s_%d.png' % (n, i))).convert('RGB').resize((300, 240)) for i in range(3)]
    row = Image.new('RGB', (900, 260), (30, 30, 30))
    for i, im in enumerate(ims):
        row.paste(im, (i * 300, 20))
    ImageDraw.Draw(row).text((4, 4), n + '   views: from +X | from -Y | from +Z (top)', fill=(255, 255, 0))
    rows.append(row)
sheet = Image.new('RGB', (900, 260 * len(rows)))
for i, r in enumerate(rows):
    sheet.paste(r, (0, i * 260))
sheet.save(out)
