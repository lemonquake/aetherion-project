"""Bake repeatable PBR texture arrays and street signs for Lawless Sub.

Uses the project's credited Poly Haven sources. Each 512px slice has its own
mip chain, so repeated UVs never bleed into another material. No runtime bake.
"""
from pathlib import Path
import hashlib
import json
import math
import re
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/urban'
SRC = ROOT / 'game/assets/thirdparty/polyhaven/textures'
SIZE = 512


def imported_array(path, cols, rows, normal=False):
    rel = 'res://' + path.relative_to(ROOT / 'game').as_posix()
    digest = hashlib.md5(rel.encode()).hexdigest()
    stem = f'res://.godot/imported/{path.name}-{digest}'
    path.with_suffix(path.suffix + '.import').write_text(f'''[remap]
importer="2d_array_texture"
type="CompressedTexture2DArray"
path.s3tc="{stem}.s3tc.ctexarray"
path.etc2="{stem}.etc2.ctexarray"
metadata={{"imported_formats": ["s3tc_bptc", "etc2_astc"], "vram_texture": true}}

[deps]
source_file="{rel}"
dest_files=["{stem}.s3tc.ctexarray", "{stem}.etc2.ctexarray"]

[params]
compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/hdr_compression=1
compress/channel_pack={2 if normal else 0}
mipmaps/generate=true
mipmaps/limit=-1
slices/horizontal={cols}
slices/vertical={rows}
''')


def load_tex(folder, channel, default):
    for ext in ['jpg', 'png']:
        p = SRC / folder / f'{channel}.{ext}'
        if p.exists():
            return np.asarray(Image.open(p).convert('RGB').resize((SIZE, SIZE), Image.Resampling.LANCZOS), dtype=np.float32) / 255
    return np.full((SIZE, SIZE, 3), default, dtype=np.float32)


def periodic_noise(rng, scale):
    im = Image.fromarray(rng.integers(0, 255, (scale, scale), dtype=np.uint8))
    # Repeat the small field before upscaling, then crop a central period.
    im = Image.fromarray(np.tile(np.asarray(im), (3, 3)))
    im = im.resize((SIZE * 3, SIZE * 3), Image.Resampling.BICUBIC)
    return np.asarray(im.crop((SIZE, SIZE, SIZE * 2, SIZE * 2)), dtype=np.float32) / 255


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    src = (ROOT / 'game/src/world/materials.gd').read_text()
    matches = re.findall(r'"([\w]+)": \{"tex": "([\w]+)"[^\n]+', src)
    names = sorted(dict(matches))
    folders = dict(matches)
    cols, rows = 8, math.ceil(len(names) / 8)
    sheets = [Image.new('RGB', (SIZE * cols, SIZE * rows), c) for c in [(128, 128, 128), (128, 128, 255), (255, 200, 0)]]
    manifest = {}
    yy, xx = np.mgrid[:SIZE, :SIZE] / SIZE
    for index, name in enumerate(names):
        rng = np.random.default_rng(int(hashlib.md5(name.encode()).hexdigest()[:8], 16))
        alb = load_tex(folders[name], 'albedo', .5)
        nrm = load_tex(folders[name], 'normal', .5)
        rough = load_tex(folders[name], 'roughness', .8)[:, :, 1]
        ao = load_tex(folders[name], 'ao', 1)[:, :, 0]
        macro = periodic_noise(rng, 8)
        fine = periodic_noise(rng, 48)
        road = name in ['road_asphalt', 'road_asphalt2', 'lot_asphalt', 'asphalt', 'asphalt2']
        if road:
            # Tropical asphalt: dark aggregate, pale worn grains, irregular old
            # tar seams rather than the previous continuous pale concrete sheet.
            lum = np.mean(alb, axis=2)
            alb *= .48 if name != 'lot_asphalt' else .57
            alb *= (.8 + macro[:, :, None] * .36)
            cracks = Image.new('L', (SIZE, SIZE), 0)
            d = ImageDraw.Draw(cracks)
            for k in range(5):
                points = [(int(x), int((.15 + .16 * k + .035 * math.sin(x * .035 + k)) * SIZE)) for x in range(-20, SIZE + 21, 8)]
                d.line(points, fill=190, width=2)
            crack = np.asarray(cracks.filter(ImageFilter.GaussianBlur(.5)), dtype=np.float32) / 255
            alb *= (1 - crack[:, :, None] * .7)
            rough = np.clip(.76 + fine * .17 - crack * .2, .5, 1)
        elif name == 'pavement':
            # Residential concrete roads are distinct from warm paving stones.
            grey = np.mean(alb, axis=2) * .73
            alb = grey[:, :, None] * np.array([.94, .97, 1.0])
            alb *= .9 + macro[:, :, None] * .18
            rough = np.clip(.76 + fine * .15, .65, 1)
        elif any(k in name for k in ['wall', 'plaster', 'concrete', 'cement', 'facade', 'brick', 'sidewalk', 'pavers', 'driveway']):
            alb *= (.84 + .26 * macro[:, :, None])
            # Preserve texture colour; reduce the featureless bright wash.
            rough = np.clip(rough * .85 + fine * .12 + .12, .5, 1)
            ao = np.minimum(ao, .88 + macro * .12)
        elif any(k in name for k in ['metal', 'yero', 'factory', 'container', 'shutter']):
            alb *= .83 + macro[:, :, None] * .22
            rough = np.clip(rough + (fine - .5) * .24, .24, 1)
        elif 'roof' in name:
            alb *= .85 + macro[:, :, None] * .2
        orm = np.stack([ao, rough, np.zeros_like(rough)], axis=2)
        for sheet, array in zip(sheets, [alb, nrm, orm]):
            sheet.paste(Image.fromarray(np.uint8(np.clip(array, 0, 1) * 255)), ((index % cols) * SIZE, (index // cols) * SIZE))
        manifest[name] = index
    for sheet, name in zip(sheets, ['albedo', 'normal', 'orm']):
        path = OUT / f'surfaces_{name}.png'
        sheet.save(path, optimize=True)
        imported_array(path, cols, rows, name == 'normal')
    (OUT / 'surfaces.json').write_text(json.dumps(manifest, indent=2) + '\n')
    signs()
    print(json.dumps({'layers':len(names), 'slice_size':SIZE, 'sheet_size':[SIZE*cols,SIZE*rows], 'source':'existing credited Poly Haven sets'}))


def signs():
    labels = [('Reyes', 'Bakery'), ('Laundry', 'Wash & Fold'), ('Repair Shop', 'Parts & Service'), ('Sari-sari Store', 'Cold Drinks'), ('Lutong Bahay', 'Rice & Meals'), ('Fresh Produce', 'Fruit & Vegetables'), ('Barber Shop', 'Haircuts'), ('Water Station', 'Refill & Delivery'), ('Lawless Mart', 'Groceries & Supplies'), ('Canal Flats', 'Apartments'), ('Community Hall', 'Lawless Subdivision'), ('Lawless Plastics', 'Factory & Warehouse'), ('Chapel', 'Visitors Welcome'), ('Lawless Fuel', 'Fuel & Service'), ('Clinic', 'Health Centre'), ('Lawless Sub', 'Pedestrian Crossing')]
    atlas = Image.new('RGBA', (2048, 1024), (0, 0, 0, 0))
    fontpath = Path('C:/Windows/Fonts/arialbd.ttf')
    subpath = Path('C:/Windows/Fonts/arial.ttf')
    palette = ['#204f52','#873c30','#c3ab73','#34474f','#6b6d45','#8c633d','#274a6f','#49656b']
    for i, (label, sub) in enumerate(labels):
        im = Image.new('RGBA', (512, 256), palette[i % len(palette)])
        d = ImageDraw.Draw(im)
        d.rectangle((12, 12, 499, 243), outline='#d9d1b7', width=4)
        fs = 54
        while d.textbbox((0,0),label,font=ImageFont.truetype(str(fontpath),fs))[2] > 460:
            fs -= 2
        d.text((256, 95), label, font=ImageFont.truetype(str(fontpath),fs), anchor='mm', fill='#fff4da')
        d.line((76, 143, 436, 143), fill='#c9bc98',width=2)
        d.text((256, 183), sub, font=ImageFont.truetype(str(subpath),29), anchor='mm', fill='#e6dcc5')
        # Baked subtle chipped edges, never a separate transparent overlay.
        rng = np.random.default_rng(700+i)
        for _ in range(140):
            x,y = int(rng.integers(10,502)),int(rng.integers(10,246))
            if x < 22 or x > 490 or y < 24 or y > 232:
                d.line((x,y,x+int(rng.integers(1,9)),y),fill=(130,122,104,255),width=1)
        atlas.alpha_composite(im, ((i%4)*512,(i//4)*256))
    atlas.save(OUT/'signs.png',optimize=True)
    (OUT/'signs.json').write_text(json.dumps([x[0] for x in labels],indent=2)+'\n')


if __name__ == '__main__':
    main()
