"""Joins the gear check renders into one sheet per slot: work/gear/sheet_<slot>.png (front row, back row)."""
import glob
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, 'work', 'gear')
for slot in ['hair', 'shirt', 'jacket', 'pants', 'boots', 'gloves', 'elbow', 'knee', 'helmet', 'face', 'pack']:
    fronts = sorted(glob.glob(os.path.join(D, slot + '_*_front.png')))
    if not fronts:
        continue
    w, h = Image.open(fronts[0]).size
    sheet = Image.new('RGB', (w * len(fronts), h * 2 + 24), (30, 30, 32))
    dr = ImageDraw.Draw(sheet)
    for i, f in enumerate(fronts):
        sheet.paste(Image.open(f).convert('RGB'), (i * w, 24))
        b = f.replace('_front.png', '_back.png')
        if os.path.exists(b):
            sheet.paste(Image.open(b).convert('RGB'), (i * w, 24 + h))
        dr.text((i * w + 6, 6), os.path.basename(f).replace('_front.png', ''), fill=(230, 230, 230))
    sheet.save(os.path.join(D, 'sheet_%s.png' % slot))
    print('sheet', slot, len(fronts))
