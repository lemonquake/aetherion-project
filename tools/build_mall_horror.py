"""Build the mall's PBR atlas from original ImageGen artwork (see docs/MALL_HORROR.md).

The source artwork is retained in work/r19/source. This performs technical packing,
wrap-edge padding and height/normal/roughness derivation; no network access is needed.
"""
from pathlib import Path
import json
import shutil
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'work/r19/source'
OUT = ROOT / 'game/assets/mall/horror'
N = 1024
PAD = 8
NAMES = ['porcelain', 'granite', 'marble', 'mosaic', 'plaster', 'ceiling',
         'steel', 'tread', 'oak', 'rubber', 'carpet', 'leather', 'concrete',
         'bathroom', 'teal_metal', 'dead_foliage']


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    source = Image.open(SRC / 'materials.png').convert('RGB')
    atlas = [Image.new('RGB', (N * 4, N * 4)) for _ in range(3)]
    roughs = [.42, .38, .37, .62, .88, .94, .36, .57, .63, .86, .97, .7, .94, .49, .66, .95]
    for i, name in enumerate(NAMES):
        x, y = i % 4, i // 4
        cell = source.crop((round(x * source.width / 4), round(y * source.height / 4),
                            round((x+1) * source.width / 4), round((y+1) * source.height / 4)))
        if name in ['porcelain', 'plaster']:
            cell = Image.open(SRC / (name + '.png')).convert('RGB')
        cell = cell.resize((N - PAD*2, N - PAD*2), Image.Resampling.LANCZOS)
        rgb = np.asarray(cell).astype(np.float32) / 255
        lum = rgb @ np.array([.2126, .7152, .0722], dtype=np.float32)
        blur = np.asarray(cell.convert('L').filter(ImageFilter.GaussianBlur(2))).astype(np.float32)/255
        # Height is deliberately shallow. Wide stains must not become raised geometry.
        height = (lum - blur) * .6 + lum * .12
        gy, gx = np.gradient(height)
        norm = np.dstack((-gx*5, gy*5, np.ones_like(lum)))
        norm /= np.linalg.norm(norm, axis=2, keepdims=True)
        normal = np.clip((norm*.5+.5)*255, 0, 255).astype('uint8')
        rough = np.clip(roughs[i] + (1-lum)*.16 + abs(lum-blur)*.45, .15, 1)
        ao = np.clip(.85 + lum*.15, .65, 1)
        orm = np.dstack((ao, rough, np.full_like(lum, 1 if i in [6,7,14] else 0)))
        for target, arr in zip(atlas, [np.asarray(cell), normal, (orm*255).astype('uint8')]):
            # Wrap padding prevents adjacent materials leaking through filtered edges.
            arr = np.pad(arr, ((PAD,PAD), (PAD,PAD), (0,0)), mode='wrap')
            target.paste(Image.fromarray(arr), (x*N, y*N))
    for im, name in zip(atlas, ['albedo', 'normal', 'orm']):
        im.save(OUT / (name + '.png'), optimize=True)
    (OUT / 'materials.json').write_text(json.dumps(dict(enumerate(NAMES)), indent=2)+'\n')
    print('Built sixteen 1024px material cells in three 4096px PBR atlases.')


def build_variants():
    names = ['ivory_paint','sage_paint','buff_render','brick','terrazzo','green_marble','geometric_tile','cement_repair']
    atlas = [Image.new('RGB',(N*4,N*2)) for _ in range(3)]
    for i,name in enumerate(names):
        sheet=Image.open(SRC/('wall_finishes.png' if i<4 else 'floor_finishes.png')).convert('RGB')
        k=i%4; x=k%2; y=k//2
        cell=sheet.crop((round(x*sheet.width/2),round(y*sheet.height/2),round((x+1)*sheet.width/2),round((y+1)*sheet.height/2))).resize((N-PAD*2,N-PAD*2),Image.Resampling.LANCZOS)
        rgb=np.asarray(cell).astype(np.float32)/255
        lum=rgb@np.array([.2126,.7152,.0722],dtype=np.float32)
        blur=np.asarray(cell.convert('L').filter(ImageFilter.GaussianBlur(2))).astype(np.float32)/255
        gy,gx=np.gradient((lum-blur)*.5+lum*.08)
        norm=np.dstack((-gx*4,gy*4,np.ones_like(lum))); norm/=np.linalg.norm(norm,axis=2,keepdims=True)
        rough=[.82,.8,.9,.95,.55,.32,.6,.9][i]
        orm=np.dstack((.9+lum*.1,np.clip(rough+(1-lum)*.1,.2,1),np.zeros_like(lum)))
        for target,arr in zip(atlas,[np.asarray(cell),((norm*.5+.5)*255).astype('uint8'),(orm*255).astype('uint8')]):
            target.paste(Image.fromarray(np.pad(arr,((PAD,PAD),(PAD,PAD),(0,0)),mode='wrap')),((i%4)*N,(i//4)*N))
    for im,name in zip(atlas,['albedo','normal','orm']):
        im.save(OUT/(name+'_variants.png'),optimize=True)
    (OUT/'variants.json').write_text(json.dumps({str(i+16):n for i,n in enumerate(names)},indent=2)+'\n',encoding='utf8')
    print('Built eight distinct wall/floor finishes in three 4096x2048 atlases.')


if __name__ == '__main__':
    build()
    build_variants()
