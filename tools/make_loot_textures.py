"""Generates the textures used by the procedural loot models (tools/blender/make_loot_models.py).

    python -I tools/make_loot_textures.py

Writes PNGs to tools/cache/loot_tex/. Everything is drawn here from noise and text (Barlow, OFL, already shipped in
game/assets/fonts); no external images. Brand names on packaging are invented.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'tools', 'cache', 'loot_tex')
FONTS = os.path.join(ROOT, 'game', 'assets', 'fonts')
RNG = np.random.default_rng(4242)


def font(size, kind='SemiBold'):
    name = {'SemiBold': 'Barlow-SemiBold.ttf', 'Medium': 'Barlow-Medium.ttf', 'Cond': 'BarlowCondensed-SemiBold.ttf',
            'Mono': 'ShareTechMono-Regular.ttf'}[kind]
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def noise(w, h, scale, octaves=4):
    """Value noise in 0..1, tileable enough for small props."""
    out = np.zeros((h, w))
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        s = max(int(scale / (2 ** o)), 1)
        g = RNG.random((h // s + 2, w // s + 2))
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w + 2 * s, h + 2 * s), Image.BICUBIC)
        out += np.asarray(img, dtype=float)[s:s + h, s:s + w] / 255.0 * amp
        tot += amp
        amp *= 0.5
    return out / tot


def tint(base, n, amount):
    a = np.asarray(base, dtype=float)
    return np.clip(a[None, None, :] * (1.0 + (n[..., None] - 0.5) * amount), 0, 255)


def save(name, arr_or_img):
    img = arr_or_img if isinstance(arr_or_img, Image.Image) else Image.fromarray(np.asarray(arr_or_img).astype(np.uint8))
    img.save(os.path.join(OUT, name + '.png'))


def surface(name, color, size=256, scale=48, amount=0.25, speck=0.0, wear=None):
    n = noise(size, size, scale)
    a = tint(color, n, amount)
    if speck > 0:
        m = RNG.random((size, size)) < speck
        a[m] *= 0.75
    if wear is not None:
        w = noise(size, size, 24) > 0.72
        a[w] = a[w] * 0.5 + np.asarray(wear, dtype=float) * 0.5
    save(name, a)


def wood(name, color, w=512, h=256):
    x = np.linspace(0, 1, w)[None, :]
    y = np.linspace(0, 1, h)[:, None]
    warp = noise(w, h, 64) * 6.0
    rings = 0.5 + 0.5 * np.sin((y * 16.0 + warp * 0.35 + noise(w, h, 128) * 1.5) * np.pi)
    fine = noise(w, h, 4, 2)
    v = 0.84 + rings * 0.09 + (fine - 0.5) * 0.10
    a = np.clip(np.asarray(color, dtype=float)[None, None, :] * v[..., None], 0, 255)
    save(name, a)


def fabric(name, color, size=256):
    yy, xx = np.mgrid[0:size, 0:size]
    weave = 0.5 + 0.25 * np.sin(xx * np.pi / 1.5) * np.sin(yy * np.pi / 1.5)
    n = noise(size, size, 32)
    v = 0.86 + (weave - 0.5) * 0.18 + (n - 0.5) * 0.2
    save(name, np.clip(np.asarray(color, dtype=float)[None, None, :] * v[..., None], 0, 255))


def cardboard(name, size=512, print_fn=None):
    n = noise(size, size, 64)
    fib = noise(size, size, 3, 2)
    a = tint((176, 136, 92), n * 0.7 + fib * 0.3, 0.3)
    img = Image.fromarray(a.astype(np.uint8))
    if print_fn:
        print_fn(ImageDraw.Draw(img), size)
    save(name, img.filter(ImageFilter.GaussianBlur(0.6)))


# ------------------------------------------------------------------ labels

def ammo_label(name, band, title, sub, count, kind='box'):
    """512x512 atlas: top label in the upper half, side band in the lower half. The whole box is the calibre's
    colour (items.json "color"), the same on every box of it, so ammunition is told apart at a glance."""
    W = 512
    band = tuple(band)
    dark = tuple(int(c * 0.55) for c in band)
    img = Image.new('RGB', (W, W), band)
    d = ImageDraw.Draw(img)
    # top: brand strip, calibre, count
    d.rectangle([0, 0, W, 60], fill=dark)
    d.text((20, 6), 'KALAW', font=font(44), fill=(245, 240, 228))
    d.text((200, 18), 'AMMUNITION', font=font(28, 'Cond'), fill=(245, 240, 228))
    d.text((20, 78), title, font=font(92), fill=(250, 248, 240))
    d.text((24, 182), sub, font=font(32, 'Medium'), fill=(240, 236, 226))
    d.rectangle([0, 236, W, 256], fill=dark)
    d.text((W - 150, 186), '%d' % count, font=font(48), fill=(250, 248, 240))
    # side: solid band with text
    d.rectangle([0, 256, W, W], fill=band)
    d.text((20, 300), title, font=font(70), fill=(245, 240, 228))
    d.text((20, 400), '%d %s' % (count, 'SHELLS' if kind == 'shell' else 'CARTRIDGES'), font=font(40, 'Cond'), fill=(235, 228, 210))
    n = noise(W, W, 64)
    a = tint((255, 255, 255), n, 0.12) / 255.0 * np.asarray(img, dtype=float)
    save(name, a)


def calibre_colors():
    import json
    items = json.load(open(os.path.join(ROOT, 'game', 'data', 'items.json'), encoding='utf-8'))['items']
    return {k: v['color'] for k, v in items.items() if v.get('kind') == 'ammo' and 'color' in v}


def grenade_body():
    """Olive drab frag body with a yellow band (fragmentation filler marking)."""
    W = 256
    n = noise(W, W, 24)
    a = tint((72, 82, 52), n, 0.25)
    img = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 96, W, 112], fill=(214, 180, 40))
    d.text((12, 130), 'FRAG  M67', font=font(30, 'Cond'), fill=(214, 180, 40))
    save('grenade_body', img)


def paper_pack(name, title):
    W = 512
    n = noise(W, W, 48)
    a = tint((150, 118, 80), n, 0.35)
    img = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.text((24, 60), title, font=font(84, 'Cond'), fill=(40, 30, 22))
    d.text((24, 170), '20 PCS  LOT 07-31', font=font(36, 'Mono'), fill=(50, 38, 28))
    d.rectangle([0, 256, W, 300], fill=(120, 92, 60))
    d.text((24, 330), title, font=font(70, 'Cond'), fill=(40, 30, 22))
    save(name, img)


def battery_wrap():
    W, H = 512, 256
    img = Image.new('RGB', (W, H), (24, 24, 26))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 150, W, H], fill=(200, 150, 40))
    d.text((20, 24), 'LAKAS', font=font(88), fill=(220, 170, 50))
    d.text((340, 70), 'HEAVY DUTY', font=font(30, 'Cond'), fill=(200, 200, 200))
    d.text((20, 168), 'D  1.5V', font=font(64), fill=(24, 24, 26))
    d.text((300, 180), 'R20', font=font(48, 'Cond'), fill=(24, 24, 26))
    save('battery_wrap', img)


def pill_label():
    W, H = 512, 256
    img = Image.new('RGB', (W, H), (238, 238, 232))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 50], fill=(30, 110, 170))
    d.text((16, 2), 'GAMOT', font=font(40), fill=(255, 255, 255))
    d.text((16, 70), 'PARACETAMOL', font=font(56), fill=(30, 40, 60))
    d.text((16, 140), '500 mg  ·  100 tablets', font=font(34, 'Medium'), fill=(60, 70, 90))
    d.rectangle([0, 206, W, H], fill=(30, 110, 170))
    save('pill_label', img)


def bandage_tex():
    W = 256
    n = noise(W, W, 16)
    yy, xx = np.mgrid[0:W, 0:W]
    weave = 0.5 + 0.5 * np.sin(xx * np.pi / 2.0) * np.sin(yy * np.pi / 2.0)
    v = 0.85 + (weave - 0.5) * 0.15 + (n - 0.5) * 0.15
    save('bandage', np.clip(np.asarray((214, 190, 160), float)[None, None, :] * v[..., None], 0, 255))


def balikbayan_print(d, size):
    ink = (40, 54, 120)
    d.rectangle([20, 20, size - 20, 120], outline=ink, width=6)
    d.text((36, 34), 'BALIKBAYAN BOX', font=font(54), fill=ink)
    d.text((40, 150), 'PADALA CARGO', font=font(52, 'Cond'), fill=(170, 40, 40))
    d.text((40, 215), 'door to door  ·  Luzon Visayas Mindanao', font=font(26, 'Medium'), fill=ink)
    # arrows "this side up"
    for i, x in enumerate([60, 160]):
        d.polygon([(x, 380), (x + 30, 330), (x + 60, 380)], fill=ink)
        d.rectangle([x + 20, 380, x + 40, 430], fill=ink)
    d.text((250, 350), 'THIS SIDE UP', font=font(40, 'Cond'), fill=ink)
    d.text((250, 400), 'FRAGILE', font=font(40, 'Cond'), fill=(170, 40, 40))
    # handwritten-ish name block
    d.rectangle([20, 450, size - 20, 500], outline=ink, width=3)
    d.text((30, 455), 'TO: FAM. DELA CRUZ  Brgy. 14', font=font(30, 'Mono'), fill=(20, 20, 20))


def medkit_lid():
    W = 512
    n = noise(W, W, 48)
    a = tint((236, 236, 230), n, 0.08)
    img = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.rectangle([96, 96, 416, 416], fill=(20, 140, 70))
    d.rectangle([226, 136, 286, 376], fill=(250, 250, 250))
    d.rectangle([136, 226, 376, 286], fill=(250, 250, 250))
    d.text((150, 430), 'FIRST AID', font=font(54), fill=(20, 140, 70))
    save('medkit_lid', img)


def stencil(name, base, text_lines, ink=(220, 190, 60), size=512):
    n = noise(size, size, 48)
    a = tint(base, n, 0.3)
    w = noise(size, size, 20) > 0.74
    a[w] = a[w] * 0.6 + np.asarray((120, 110, 90), float) * 0.4
    img = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(img)
    y = 40
    for line, sz in text_lines:
        d.text((30, y), line, font=font(sz, 'Cond'), fill=ink)
        y += int(sz * 1.25)
    save(name, img)


def cooler_tex():
    W = 512
    n = noise(W, W, 48)
    a = tint((190, 40, 36), n, 0.15)
    img = Image.fromarray(a.astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.text((40, 300), 'ICEBOX', font=font(80), fill=(245, 245, 240))
    d.text((44, 400), '45 L', font=font(40, 'Cond'), fill=(245, 245, 240))
    save('cooler', img)


def scope_reticle_preview():
    pass


def main():
    os.makedirs(OUT, exist_ok=True)
    surface('metal_dark', (58, 58, 60), amount=0.3, speck=0.02)
    surface('metal_black', (30, 30, 32), amount=0.25, speck=0.02)
    surface('metal_olive', (78, 84, 52), amount=0.35, wear=(110, 106, 92))
    surface('metal_red', (160, 30, 26), amount=0.25, wear=(90, 80, 74))
    surface('metal_galv', (150, 152, 150), amount=0.45, speck=0.05)
    surface('polymer_black', (26, 26, 28), amount=0.2)
    surface('polymer_tan', (150, 128, 96), amount=0.2)
    surface('plastic_white', (232, 232, 226), amount=0.1)
    surface('plastic_blue', (50, 90, 150), amount=0.12)
    surface('plastic_grey', (130, 136, 140), amount=0.12)
    surface('foam_black', (34, 34, 36), scale=8, amount=0.35)
    surface('foam_grey', (70, 70, 72), scale=8, amount=0.35)
    surface('rubber', (22, 22, 22), scale=6, amount=0.3)
    surface('tape_black', (16, 16, 18), scale=64, amount=0.15)
    surface('splint_orange', (230, 110, 30), scale=12, amount=0.2)
    surface('splint_blue', (40, 80, 150), scale=12, amount=0.2)
    surface('brass', (190, 150, 70), amount=0.2)
    surface('shell_red', (150, 26, 24), amount=0.15)
    surface('shell_yellow', (200, 160, 30), amount=0.15)
    wood('wood_walnut', (110, 70, 42))
    wood('wood_raw', (170, 130, 86))
    wood('wood_green', (60, 78, 52))
    fabric('nylon_navy', (36, 48, 78))
    fabric('nylon_olive', (74, 80, 52))
    fabric('nylon_black', (30, 30, 32))
    fabric('nylon_grey', (90, 92, 96))
    cardboard('cardboard', 512)
    cardboard('balikbayan', 512, balikbayan_print)
    col = calibre_colors()
    ammo_label('ammo_9x19', col['ammo_9x19'], '9mm Luger', '115 gr FMJ', 50)
    ammo_label('ammo_45acp', col['ammo_45acp'], '.45 ACP', '230 gr FMJ', 50)
    ammo_label('ammo_357', col['ammo_357'], '.357 MAG', '158 gr JSP', 50)
    ammo_label('ammo_12buck', col['ammo_12buck'], '12 GA 00', 'Buckshot 2 3/4"', 25, 'shell')
    ammo_label('ammo_12slug', col['ammo_12slug'], '12 GA SLUG', 'Rifled slug 1 oz', 25, 'shell')
    ammo_label('ammo_556', col['ammo_556'], '5.56x45', '55 gr FMJ', 20)
    ammo_label('ammo_762x39', col['ammo_762x39'], '7.62x39', '123 gr FMJ', 20)
    ammo_label('ammo_308', col['ammo_308'], '.308 WIN', '150 gr SP', 20)
    ammo_label('ammo_50ae', col['ammo_50ae'], '.50 AE', '300 gr JHP', 20)
    grenade_body()
    battery_wrap()
    pill_label()
    bandage_tex()
    medkit_lid()
    stencil('ammocan', (78, 84, 52), [('CARTRIDGES', 64), ('LINKED  M27', 48), ('LOT 2207-14', 40)])
    stencil('riflecase', (34, 34, 36), [('', 10)], ink=(90, 90, 90))
    cooler_tex()
    print('wrote', len(os.listdir(OUT)), 'textures to', OUT)


if __name__ == '__main__':
    main()
