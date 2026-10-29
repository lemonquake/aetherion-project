"""r7 Game Setup gun pictures: key the flat grey background out of the r5 item renders
(work/lemondev/r5/items/<id>.png, made by tools/blender/process_items.py), crop to the gun and fit it into a
512x224 transparent PNG under game/assets/ui/r7/guns/<id>.png. Background removal is a flood fill from the
border (so grey metal inside the gun stays), then a 1 px soft edge."""
import os, sys
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..', '..'))
SRC = os.path.join(ROOT, 'work', 'lemondev', 'r5', 'items')
DST = os.path.join(ROOT, 'game', 'assets', 'ui', 'r7', 'guns')
W, H, PAD = 512, 224, 10


def one(gid):
    im = np.asarray(Image.open(os.path.join(SRC, gid + '.png')).convert('RGB')).astype(np.float32)
    bg = np.median(np.concatenate([im[0], im[-1], im[:, 0], im[:, -1]]), axis=0)
    d = np.sqrt(((im - bg) ** 2).sum(-1))
    near = d < 14.0
    lab, _ = ndimage.label(near)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    back = np.isin(lab, list(border))
    # Enclosed pockets (trigger guards, stock holes): the render's background is perfectly flat, so a sizeable
    # region within a few levels of it is background too.
    flat = d < 5.0
    lab2, n2 = ndimage.label(flat)
    if n2:
        sizes = ndimage.sum(np.ones_like(d), lab2, index=np.arange(1, n2 + 1))
        big = np.where(sizes > 60)[0] + 1
        back |= ndimage.binary_dilation(np.isin(lab2, big), iterations=1) & near
    gun = ~back
    gun = ndimage.binary_opening(gun, iterations=1)
    a = gun.astype(np.float32)
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255.0
    a = np.minimum(a * 1.4, 1.0) * gun.astype(np.float32) + a * (~gun) * 0.6
    ys, xs = np.where(a > 0.05)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgba = np.dstack([im, a * 255.0]).clip(0, 255).astype(np.uint8)[y0:y1, x0:x1]
    crop = Image.fromarray(rgba, 'RGBA')
    s = min((W - 2 * PAD) / crop.width, (H - 2 * PAD) / crop.height)
    crop = crop.resize((max(1, int(crop.width * s)), max(1, int(crop.height * s))), Image.LANCZOS)
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    out.alpha_composite(crop, ((W - crop.width) // 2, (H - crop.height) // 2))
    out.save(os.path.join(DST, gid + '.png'))
    return crop.size, float(gun.mean())


def main():
    os.makedirs(DST, exist_ok=True)
    ids = sys.argv[1:] or sorted(f[:-4] for f in os.listdir(SRC) if f.endswith('.png') and not f.endswith('_parts.png') and not f.startswith('grid'))
    for gid in ids:
        sz, cover = one(gid)
        print('%-16s %4dx%-4d cover %.2f' % (gid, sz[0], sz[1], cover))


if __name__ == '__main__':
    main()
