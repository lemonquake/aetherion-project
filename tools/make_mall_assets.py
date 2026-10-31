"""r15: the 2D art of Malasugue Mall (the second Deathmatch map): shop signs, LED screen adverts, hanging sale banners,
wayfinding signs, shop posters and the printed faces of stocked shelves, clothes rails and book spines.

    python -I tools/make_mall_assets.py      (then bash tools/import.sh)

Writes game/assets/mall/:
  signs.png + game/data/maps/malasugue_shops.json  every shop's fascia sign (4 x 32 tiles of 512 x 128) and the catalogue
                                                  the map builder reads (name, line, kind, floor, colours, tile)
  ads.png        8 LED-screen adverts (2 x 4 frames of 1024 x 512)
  banners.png    8 hanging banners (8 x 1 of 256 x 768)
  wayfind.png    16 wayfinding signs (4 x 4 of 256 x 128)
  posters.png    16 shop posters (4 x 4 of 256 x 256)
  goods.png      4 shelf faces (1 x 4 rows of 1024 x 256): groceries, toys, boxes, bottles
  rails.png      clothes on rails / folded stacks / shoes / book spines (4 rows of 1024 x 256)
Fonts are Windows system fonts rendered into the images (no font files ship). Names are the user's shops plus
invented Filipino ones; no real brands.
"""
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'game' / 'assets' / 'mall'
DATA = ROOT / 'game' / 'data' / 'maps' / 'malasugue_shops.json'
FONTS = 'C:/Windows/Fonts/'

# name, line under it, kind (how the inside is dressed), floor (0 = Level 1 .. 4 = Level 5; -1 anchors placed by name),
# background, text colour, font file, style (plain | box | script | neon | serif)
SHOPS = [
    # the user's shops
    ("Azrin & Azrael's", 'Fashion House', 'fashion_lux', 0, '#0d0d0f', '#e3c27a', 'BOD_R.TTF', 'serif'),
    ('Toys by EZ-RR', 'Toys · Games · Gifts', 'toys', 3, '#ffd23f', '#d62246', 'comicbd.ttf', 'box'),
    ('Quake Team', 'Esports Arena', 'esports', -1, '#08080c', '#ff3b30', 'impact.ttf', 'neon'),
    ('TCD Vapes', 'Vape Lounge', 'vape', 2, '#101820', '#36f1cd', 'bahnschrift.ttf', 'neon'),
    ('OGA Whales', 'Hobby & Collectibles', 'hobby', 2, '#0b3c5d', '#f2f4f3', 'BRLNSDB.TTF', 'plain'),
    ("Airah's Collections", 'Bags · Shoes · Accessories', 'bags', -1, '#f6e1e1', '#8c2f39', 'ITCEDSCR.TTF', 'script'),
    ('Alex Jackie', 'Department Store', 'department', -1, '#15233f', '#ffffff', 'GILSANUB.TTF', 'plain'),
    ('Buchokan', 'Restaurant & Bar', 'restaurant', -1, '#2b1d14', '#f3b562', 'GOUDOSB.TTF', 'serif'),
    # anchors and big rooms
    ('Malasugue Supermart', 'Fresh · Grocery · Home', 'supermarket', -1, '#1f7a3a', '#ffffff', 'arialbd.ttf', 'plain'),
    ('Malasugue Cineplex', 'Now Showing', 'cinema', -1, '#140a1f', '#ffcc33', 'BROADW.TTF', 'neon'),
    ('Kidz Kingdom', 'Play Land', 'kids_play', -1, '#2ab7ca', '#fff3b0', 'comicbd.ttf', 'box'),
    ('Bayanihan Books', 'Books · Stationery', 'books', -1, '#5c3d2e', '#f5ead7', 'GARABD.TTF', 'serif'),
    ('Takbo Fitness', 'Gym · Open 24 Hours', 'gym', -1, '#111111', '#c6ff00', 'impact.ttf', 'plain'),
    # Level 1: fashion and everyday
    ('Lemon Threads', 'Everyday Wear', 'fashion', 0, '#ffe45e', '#1c1c1c', 'segoeuib.ttf', 'plain'),
    ('Kapa Denim', 'Jeans & Jackets', 'fashion', 0, '#1e3a5f', '#e8eef5', 'ROCKB.TTF', 'plain'),
    ('Habi Weaves', 'Filipino Textiles', 'fashion', 0, '#7b2d26', '#f2e3c6', 'georgiab.ttf', 'serif'),
    ('Barong & Co.', 'Formalwear', 'fashion', 0, '#f4efe6', '#3b2f2f', 'BOD_B.TTF', 'serif'),
    ("Kuya's Kicks", 'Sneakers', 'shoes', 0, '#ff6b35', '#ffffff', 'impact.ttf', 'plain'),
    ('Sampaguita Scents', 'Perfume & Beauty', 'beauty', 0, '#ffffff', '#3d5a40', 'segoesc.ttf', 'script'),
    ('Ginto Jewels', 'Gold & Diamonds', 'jewelry', 0, '#111111', '#d4af37', 'CASTELAR.TTF', 'serif'),
    ('Kalinaw Coffee', 'Roasters · Since 2019', 'cafe', 0, '#3e2723', '#f1e3d3', 'georgiai.ttf', 'script'),
    ('Botika Malasugue', 'Pharmacy', 'pharmacy', 0, '#ffffff', '#c62828', 'arialbd.ttf', 'plain'),
    ('Sari-Sari Mart', 'Open 24/7', 'convenience', 0, '#d32f2f', '#ffffff', 'BRLNSDB.TTF', 'plain'),
    ('Isla Swim', 'Swim & Surf', 'fashion', 0, '#00a6a6', '#ffffff', 'ERASBD.TTF', 'plain'),
    ('Remit Express', 'Padala · Bills', 'service', 0, '#ffb703', '#023047', 'arialbd.ttf', 'plain'),
    ('Ukay Couture', 'Pre-loved Fashion', 'fashion', 0, '#2d2a32', '#ddd92a', 'ROCKB.TTF', 'plain'),
    # Level 2: fashion and beauty
    ('Ate Bebang Boutique', 'Ladies Wear', 'fashion', 1, '#c08497', '#ffffff', 'georgiaz.ttf', 'serif'),
    ('Tita Baby Bridal', 'Gowns & Barong', 'bridal', 1, '#fffaf0', '#8a6d3b', 'ITCEDSCR.TTF', 'script'),
    ('Kids Kloset', 'Kids Fashion', 'fashion_kids', 1, '#7bdff2', '#ff477e', 'comicbd.ttf', 'box'),
    ('Sapatos Republic', 'Shoes for Everyone', 'shoes', 1, '#2b2d42', '#edf2f4', 'segoeuib.ttf', 'plain'),
    ('Tsinelas Station', 'Slippers & Sandals', 'shoes', 1, '#06d6a0', '#073b4c', 'BRLNSDB.TTF', 'box'),
    ('Relos Hub', 'Watches', 'jewelry', 1, '#0f0f0f', '#c0c0c0', 'GILSANUB.TTF', 'plain'),
    ('Ganda Beauty', 'Cosmetics', 'beauty', 1, '#ffc8dd', '#5a189a', 'segoeuib.ttf', 'plain'),
    ('Kulot Salon', 'Hair · Nails · Lashes', 'salon', 1, '#e0aaff', '#240046', 'segoesc.ttf', 'script'),
    ('Gupit Kuya', 'Barbershop', 'barber', 1, '#1b263b', '#e0e1dd', 'ALGER.TTF', 'serif'),
    ('Halo-Halo Haven', 'Desserts', 'cafe', 1, '#ff99c8', '#5f0f40', 'comicbd.ttf', 'box'),
    ('Bubble Bay Tea', 'Milk Tea', 'cafe', 1, '#bde0fe', '#3a0ca3', 'ERASBD.TTF', 'box'),
    ('Lolo Pepe Tailoring', 'Made to Measure', 'tailor', 1, '#3d405b', '#f2cc8f', 'BOD_R.TTF', 'serif'),
    ('Bulsa Bags', 'Bags & Luggage', 'bags', 1, '#e76f51', '#ffffff', 'segoeuib.ttf', 'plain'),
    ('Optika Linaw', 'Eyewear', 'optical', 1, '#ffffff', '#1d3557', 'GILSANUB.TTF', 'plain'),
    # Level 3: tech, games and hobbies
    ('Lemon PC', 'Computers & Parts', 'tech', 2, '#ffe600', '#141414', 'bahnschrift.ttf', 'plain'),
    ('Mabuhay Mobile', 'Phones · Repairs', 'tech', 2, '#0077b6', '#ffffff', 'segoeuib.ttf', 'plain'),
    ('AzAz Games', 'Console · PC · Mobile', 'games', 2, '#1a1a2e', '#e94560', 'impact.ttf', 'neon'),
    ('Pixel Kodakan', 'Cameras & Prints', 'tech', 2, '#222222', '#ffbe0b', 'AGENCYB.TTF', 'plain'),
    ('Tunog Music', 'Instruments', 'music', 2, '#3c1518', '#f2f3ae', 'ROCKB.TTF', 'plain'),
    ('Signal Gadgets', 'Smart Home · Audio', 'tech', 2, '#003049', '#fcbf49', 'bahnschrift.ttf', 'plain'),
    ('Kable King', 'Chargers & Cases', 'tech', 2, '#7209b7', '#ffffff', 'impact.ttf', 'box'),
    ('Kuryente Appliances', 'Home Appliances', 'appliances', 2, '#e63946', '#ffffff', 'arialbd.ttf', 'plain'),
    ('Lakbay Travel', 'Tours & Tickets', 'service', 2, '#2a9d8f', '#ffffff', 'segoeuib.ttf', 'plain'),
    ('Kape Ulap', 'Coffee Bar', 'cafe', 2, '#283618', '#fefae0', 'georgiai.ttf', 'script'),
    # Level 4: kids, home and wellness
    ('Banig Home', 'Furniture & Decor', 'home', 3, '#e9c46a', '#264653', 'GARABD.TTF', 'serif'),
    ('Kusina Living', 'Kitchen & Dining', 'home', 3, '#f4a261', '#ffffff', 'segoeuib.ttf', 'plain'),
    ('Unan & Kama', 'Bed & Bath', 'home', 3, '#cdb4db', '#2b2d42', 'segoesc.ttf', 'script'),
    ('Hilot Spa', 'Massage · Wellness', 'spa', 3, '#606c38', '#fefae0', 'georgiai.ttf', 'script'),
    ('Paw Palace', 'Pets & Grooming', 'pets', 3, '#ffbe0b', '#3a86ff', 'comicbd.ttf', 'box'),
    ('Bisikleta Bikes', 'Bikes & Parts', 'sports', 3, '#0a9396', '#ffffff', 'impact.ttf', 'plain'),
    ('Takbo Sports', 'Sportswear', 'sports', 3, '#d00000', '#ffffff', 'impact.ttf', 'plain'),
    ('Lola Basyang Books', 'Storybooks', 'books', 3, '#386641', '#f2e8cf', 'GOUDOSB.TTF', 'serif'),
    ('Ngiti Dental', 'Dental Clinic', 'clinic', 3, '#ffffff', '#00b4d8', 'segoeuib.ttf', 'plain'),
    ('Linis Laundry', 'Wash · Dry · Fold', 'service', 3, '#90e0ef', '#03045e', 'ERASBD.TTF', 'box'),
    ('Pasalubong Center', 'Gifts from Home', 'gifts', 3, '#bc6c25', '#fefae0', 'GOUDOSB.TTF', 'serif'),
    # Level 5: food
    ("Tito Boy's Lechon", 'Lechon · Since 1985', 'food', 4, '#9d0208', '#ffba08', 'COOPBL.TTF', 'plain'),
    ('Sizzle Sisig', 'Sizzling Plates', 'food', 4, '#ff5400', '#ffffff', 'impact.ttf', 'plain'),
    ('Lugaw Lab', 'Congee & Tokwa', 'food', 4, '#fefae0', '#bc6c25', 'comicbd.ttf', 'box'),
    ("Mang Isko's Siomai", 'Siomai · Rice', 'food', 4, '#ffd60a', '#003566', 'BRLNSDB.TTF', 'box'),
    ('Pandesal Republic', 'Bakery', 'bakery', 4, '#ddb892', '#582f0e', 'georgiab.ttf', 'serif'),
    ('Kakanin Corner', 'Rice Cakes', 'food', 4, '#80b918', '#ffffff', 'comicbd.ttf', 'box'),
    ('Ihaw-Ihaw Grill', 'Barbecue', 'food', 4, '#370617', '#faa307', 'ROCKB.TTF', 'plain'),
    ('Pancit Palace', 'Noodles', 'food', 4, '#f77f00', '#ffffff', 'COOPBL.TTF', 'plain'),
    ('Inasal Nation', 'Chicken Inasal', 'food', 4, '#ffb703', '#7f0000', 'impact.ttf', 'plain'),
    ('Ramen Ramon', 'Ramen Bar', 'food', 4, '#000000', '#ffffff', 'BRLNSDB.TTF', 'plain'),
    ('Burger Bayan', 'Burgers', 'food', 4, '#ee6c4d', '#ffffff', 'COOPBL.TTF', 'box'),
    ('Taho Tambayan', 'Taho · Sago', 'food', 4, '#e9edc9', '#6f4518', 'comicbd.ttf', 'box'),
    ('Ice Scramble Co.', 'Frozen Treats', 'cafe', 4, '#ffafcc', '#023e8a', 'comicbd.ttf', 'box'),
    ('Kare-Kare Kitchen', 'Home Cooking', 'food', 4, '#606c38', '#fefae0', 'GOUDOSB.TTF', 'serif'),
    # spares (shops a floor runs short of)
    ('Sombrero Hats', 'Caps & Hats', 'fashion', 1, '#4a4e69', '#f2e9e4', 'ROCKB.TTF', 'plain'),
    ('Tsokolate Haus', 'Chocolates', 'cafe', 2, '#4a2c2a', '#f5cb5c', 'georgiaz.ttf', 'serif'),
    ('Laro Arcade', 'Games & Prizes', 'arcade', 3, '#3a0ca3', '#f72585', 'impact.ttf', 'neon'),
    ('Kodigo Prints', 'Printing · Photocopy', 'service', 2, '#ffffff', '#000000', 'consolab.ttf', 'plain'),
    ('Coming Soon', 'Opening This Season', 'closed', -1, '#d9d9d9', '#555555', 'arialbd.ttf', 'plain'),
    # more of every level
    ('Lakad Sneaker Lab', 'Run · Court · Street', 'shoes', 0, '#14213d', '#fca311', 'impact.ttf', 'plain'),
    ('Mabango Body Shop', 'Soaps & Lotions', 'beauty', 0, '#d8f3dc', '#1b4332', 'segoesc.ttf', 'script'),
    ("Aling Nena's Tindahan", 'Snacks · Load · Ice', 'convenience', 0, '#ffd166', '#7a2e00', 'comicbd.ttf', 'box'),
    ('Sinag Sunglasses', 'Shades', 'optical', 0, '#000000', '#ffd60a', 'GILSANUB.TTF', 'plain'),
    ('Payong & Co.', 'Umbrellas · Raincoats', 'bags', 0, '#264653', '#e9c46a', 'GARABD.TTF', 'serif'),
    ('Kape Barako Express', 'Coffee to Go', 'cafe', 0, '#6f1d1b', '#ffe6a7', 'ROCKB.TTF', 'plain'),
    ('Bilis Phone Repair', 'While You Wait', 'tech', 0, '#2b9348', '#ffffff', 'bahnschrift.ttf', 'plain'),
    ('Moda Manila', 'Womenswear', 'fashion', 1, '#212529', '#f8f9fa', 'BOD_B.TTF', 'serif'),
    ("Baro't Saya", 'Heritage Fashion', 'fashion', 1, '#9e2a2b', '#fff3b0', 'georgiaz.ttf', 'serif'),
    ('Kuwintas', 'Pearls & Silver', 'jewelry', 1, '#f1faee', '#457b9d', 'CASTELAR.TTF', 'serif'),
    ('Pila Nail Bar', 'Nails · Spa', 'salon', 1, '#ffcad4', '#9d4edd', 'segoeuib.ttf', 'plain'),
    ('Sapin-Sapin Socks', 'Socks & Basics', 'fashion', 1, '#7400b8', '#ffd6ff', 'comicbd.ttf', 'box'),
    ('Bituin Comics', 'Comics & Manga', 'hobby', 2, '#ef233c', '#ffffff', 'impact.ttf', 'box'),
    ('Pindot Keyboards', 'Mechanical Keyboards', 'tech', 2, '#111827', '#22d3ee', 'consolab.ttf', 'neon'),
    ('Retro Laro', 'Classic Games', 'games', 2, '#3d348b', '#f7b801', 'AGENCYB.TTF', 'plain'),
    ('Kwento Cards', 'Trading Cards', 'hobby', 2, '#003566', '#ffc300', 'BRLNSDB.TTF', 'plain'),
    ('Sulat Stationery', 'Pens & Paper', 'books', 2, '#fefae0', '#283618', 'georgiab.ttf', 'serif'),
    ('Dagitab Lighting', 'Lamps & Lights', 'home', 2, '#000000', '#fff3b0', 'bahnschrift.ttf', 'neon'),
    ('Lakas Gym Gear', 'Weights & Supplements', 'sports', 2, '#2b2d42', '#ef233c', 'impact.ttf', 'plain'),
    ('Halaman Plant Shop', 'Plants & Pots', 'plants', 3, '#2d6a4f', '#d8f3dc', 'georgiai.ttf', 'script'),
    ('Lutong Bahay Cookware', 'Pots & Pans', 'home', 3, '#e85d04', '#ffffff', 'segoeuib.ttf', 'plain'),
    ('Tulog Mattress', 'Sleep Better', 'home', 3, '#023e8a', '#caf0f8', 'ERASBD.TTF', 'plain'),
    ('Bata Bata Kids', 'Clothes for Kids', 'fashion_kids', 3, '#ffbe0b', '#8338ec', 'comicbd.ttf', 'box'),
    ('Musika Music School', 'Piano · Guitar · Voice', 'music', 3, '#3c096c', '#ffd60a', 'georgiab.ttf', 'serif'),
    ('Sining Art Supplies', 'Paint · Canvas', 'books', 3, '#f8f9fa', '#e63946', 'comicbd.ttf', 'box'),
    ('Sinigang Station', 'Sour Soups', 'food', 4, '#99d98c', '#1e6091', 'COOPBL.TTF', 'box'),
    ('Lumpia Lane', 'Fresh & Fried', 'food', 4, '#ffd166', '#ef476f', 'comicbd.ttf', 'box'),
    ('Bibingka Bakery', 'Rice Cakes · Puto', 'bakery', 4, '#f4a261', '#3d0c02', 'georgiab.ttf', 'serif'),
    ('Kwek-Kwek Corner', 'Street Food', 'food', 4, '#ff7b00', '#000000', 'impact.ttf', 'plain'),
    ('Brew Lab Coffee', 'Specialty Coffee', 'cafe', 4, '#1b1b1e', '#d8c99b', 'bahnschrift.ttf', 'plain'),
    # the mall's own name, over the entrances and on the facades
    ('Malasugue Mall', 'Open Daily · 10 AM – 10 PM', 'sign', -2, '#15233f', '#ffffff', 'GILSANUB.TTF', 'plain'),
]


def font(name, size):
    try:
        return ImageFont.truetype(FONTS + name, size)
    except OSError:
        return ImageFont.truetype(FONTS + 'arialbd.ttf', size)


def hexc(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def fit(draw, text, fname, box_w, box_h, start):
    size = start
    while size > 10:
        f = font(fname, size)
        l, t, r, b = draw.textbbox((0, 0), text, font=f)
        if r - l <= box_w and b - t <= box_h:
            return f, (l, t, r, b)
        size -= 2
    f = font(fname, size)
    return f, draw.textbbox((0, 0), text, font=f)


def sign(name, line, bg, fg, fname, style):
    w, h = 512, 128
    im = Image.new('RGB', (w, h), hexc(bg))
    d = ImageDraw.Draw(im)
    fgc = hexc(fg)
    if style == 'box':
        d.rounded_rectangle((6, 6, w - 7, h - 7), 18, outline=fgc, width=5)
    if style == 'serif':
        d.line((40, h - 40, w - 40, h - 40), fill=fgc, width=1)
    f, bb = fit(d, name, fname, w - 56, 70 if line else 92, 84)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    y = (h - th) // 2 - bb[1] - (14 if line else 0)
    x = (w - tw) // 2 - bb[0]
    if style == 'neon':
        glow = Image.new('RGB', (w, h), (0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.text((x, y), name, font=f, fill=fgc)
        glow = glow.filter(ImageFilter.GaussianBlur(7))
        im = Image.blend(im, glow, 0.0)
        im.paste(Image.composite(glow, im, glow.convert('L')), (0, 0))
        d = ImageDraw.Draw(im)
    d.text((x, y), name, font=f, fill=fgc)
    if line:
        f2, bb2 = fit(d, line.upper() if style != 'script' else line, 'segoeuib.ttf' if style != 'serif' else 'georgia.ttf', w - 120, 20, 20)
        tw2 = bb2[2] - bb2[0]
        d.text(((w - tw2) // 2 - bb2[0], h - 34 - bb2[1] + (2 if style == 'serif' else 0)), line.upper() if style != 'script' else line, font=f2,
               fill=tuple(int(c * 0.85 + b * 0.15) for c, b in zip(fgc, hexc(bg))))
    return im


def signs():
    atlas = Image.new('RGB', (2048, 4096), (0, 0, 0))
    out = []
    for i, (name, line, kind, floor, bg, fg, fname, style) in enumerate(SHOPS):
        im = sign(name, line, bg, fg, fname, style)
        atlas.paste(im, ((i % 4) * 512, (i // 4) * 128))
        out.append({'name': name, 'line': line, 'kind': kind, 'floor': floor, 'bg': bg, 'fg': fg, 'tile': i, 'style': style})
    atlas.save(OUT / 'signs.png')
    DATA.write_text(json.dumps({'_doc': 'r15 Malasugue Mall shop catalogue, written by tools/make_mall_assets.py (sign tile i is '
                                'column i % 4, row i // 4 of assets/mall/signs.png, 4 x 32 tiles). floor: 0 = Level 1 .. 4 = Level 5, '
                                '-1 = placed by name (anchors).', 'cols': 4, 'rows': 32, 'shops': out}, indent=1))
    print('signs', len(out))


def gradient(w, h, c0, c1, vertical=False):
    im = Image.new('RGB', (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            t = (y / (h - 1)) if vertical else (x / (w - 1))
            px[x, y] = tuple(int(a + (b - a) * t) for a, b in zip(c0, c1))
    return im


def ad_frames():
    W, H = 1024, 512
    frames = []

    def text(d, xy, s, f, c, anchor='la'):
        d.text(xy, s, font=f, fill=c, anchor=anchor)

    # 1 phone launch (the reference mall's screen ran one)
    im = gradient(W, H, (10, 14, 40), (30, 90, 200))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((600, 70, 860, 470), 36, fill=(14, 16, 22), outline=(120, 140, 170), width=4)
    d.rounded_rectangle((618, 88, 842, 452), 26, fill=(40, 90, 210))
    for k, (cx, cy) in enumerate([(660, 130), (700, 130), (660, 170), (700, 170)]):
        d.ellipse((cx - 16, cy - 16, cx + 16, cy + 16), fill=(8, 8, 10), outline=(90, 90, 100), width=3)
    text(d, (70, 150), 'Lemon Phone X', font('segoeuib.ttf', 60), (255, 255, 255))
    text(d, (72, 250), 'Pre-order now.', font('segoeui.ttf', 40), (210, 225, 255))
    text(d, (72, 305), 'Freebies worth \u20b121,000', font('segoeui.ttf', 34), (210, 225, 255))
    text(d, (72, 400), 'Mabuhay Mobile \u00b7 Level 3', font('segoeuib.ttf', 30), (255, 230, 120))
    frames.append(im)
    # 2 the game itself
    im = gradient(W, H, (8, 8, 12), (60, 20, 30))
    d = ImageDraw.Draw(im)
    for k in range(40):
        x = random.randint(0, W)
        d.line((x, H, x + random.randint(-80, 80), random.randint(0, H)), fill=(80, 30, 40), width=1)
    text(d, (W // 2, 170), 'AETHERION PROJECT', font('impact.ttf', 96), (255, 255, 255), 'mm')
    text(d, (W // 2, 260), 'by Aljay Leodones \u00b7 AzAz Games', font('segoeui.ttf', 34), (230, 200, 200), 'mm')
    text(d, (W // 2, 360), 'Play free on PC and phone', font('segoeuib.ttf', 40), (255, 200, 80), 'mm')
    frames.append(im)
    # 3 fashion
    im = gradient(W, H, (20, 18, 16), (60, 50, 40), True)
    d = ImageDraw.Draw(im)
    d.ellipse((620, 60, 960, 400), fill=(170, 140, 90))
    d.polygon([(760, 150), (840, 150), (880, 470), (720, 470)], fill=(25, 22, 20))
    d.ellipse((770, 80, 830, 140), fill=(210, 180, 150))
    text(d, (70, 160), "AZRIN & AZRAEL'S", font('BOD_B.TTF', 50), (227, 194, 122))
    text(d, (72, 250), 'The Holiday Collection', font('georgiai.ttf', 42), (240, 230, 210))
    text(d, (72, 380), 'Level 1 \u00b7 Grand Atrium', font('georgia.ttf', 30), (200, 190, 170))
    frames.append(im)
    # 4 Buchokan
    im = gradient(W, H, (40, 20, 10), (120, 60, 20))
    d = ImageDraw.Draw(im)
    d.ellipse((620, 120, 940, 440), fill=(245, 240, 230))
    d.ellipse((660, 160, 900, 400), fill=(170, 90, 30))
    d.ellipse((700, 200, 860, 330), fill=(210, 140, 60))
    text(d, (70, 150), 'BUCHOKAN', font('GOUDOSB.TTF', 90), (243, 181, 98))
    text(d, (74, 260), 'Restaurant & Bar \u00b7 now open', font('georgia.ttf', 36), (250, 230, 200))
    text(d, (74, 380), 'Level 5', font('georgiab.ttf', 40), (255, 255, 255))
    frames.append(im)
    # 5 cinema
    im = gradient(W, H, (10, 5, 20), (50, 10, 60), True)
    d = ImageDraw.Draw(im)
    for k in range(12):
        d.rectangle((40 + k * 80, 30, 80 + k * 80, 60), fill=(255, 204, 51))
        d.rectangle((40 + k * 80, 452, 80 + k * 80, 482), fill=(255, 204, 51))
    text(d, (W // 2, 170), 'NOW SHOWING', font('BROADW.TTF', 60), (255, 204, 51), 'mm')
    text(d, (W // 2, 270), 'Kalinaw Nights', font('georgiaz.ttf', 70), (255, 255, 255), 'mm')
    text(d, (W // 2, 370), 'Malasugue Cineplex \u00b7 Level 5', font('segoeuib.ttf', 34), (220, 200, 255), 'mm')
    frames.append(im)
    # 6 the sale
    im = Image.new('RGB', (W, H), (214, 40, 40))
    d = ImageDraw.Draw(im)
    text(d, (W // 2, 120), 'THE SALE', font('impact.ttf', 90), (255, 255, 255), 'mm')
    text(d, (W // 2, 270), 'FLAT 50% OFF', font('impact.ttf', 150), (255, 255, 255), 'mm')
    text(d, (W // 2, 410), 'Alex Jackie \u00b7 all floors', font('segoeuib.ttf', 38), (255, 230, 230), 'mm')
    frames.append(im)
    # 7 toys
    im = gradient(W, H, (255, 210, 63), (255, 150, 60))
    d = ImageDraw.Draw(im)
    for k in range(9):
        x, y = random.randint(560, 960), random.randint(40, 460)
        r = random.randint(30, 70)
        d.ellipse((x - r, y - r, x + r, y + r), fill=random.choice([(214, 34, 70), (42, 183, 202), (255, 255, 255), (102, 46, 155)]))
    text(d, (70, 150), 'Toys by EZ-RR', font('comicbd.ttf', 76), (214, 34, 70))
    text(d, (74, 260), 'Holiday Toy Fair', font('comicbd.ttf', 50), (60, 20, 80))
    text(d, (74, 380), 'Level 4', font('comicbd.ttf', 40), (255, 255, 255))
    frames.append(im)
    # 8 the mall
    im = gradient(W, H, (0, 60, 50), (0, 30, 70))
    d = ImageDraw.Draw(im)
    text(d, (W // 2, 160), 'Maligayang Pasko!', font('segoesc.ttf', 80), (255, 230, 150), 'mm')
    text(d, (W // 2, 280), 'MALASUGUE MALL', font('GILSANUB.TTF', 70), (255, 255, 255), 'mm')
    text(d, (W // 2, 380), 'Open daily 10 AM \u2013 10 PM', font('segoeui.ttf', 36), (200, 240, 230), 'mm')
    frames.append(im)
    atlas = Image.new('RGB', (2048, 2048))
    for i, im in enumerate(frames):
        atlas.paste(im, ((i % 2) * W, (i // 2) * H))
    atlas.save(OUT / 'ads.png')


def banners():
    W, H = 256, 768
    specs = [('THE\nSALE', 'FLAT\n50%\nOFF', (214, 40, 40), (255, 255, 255)),
             ('HOLIDAY\nSALE', 'UP TO\n70%\nOFF', (180, 20, 30), (255, 235, 200)),
             ('MALIGAYANG\nPASKO', '\u2605', (10, 90, 60), (255, 220, 120)),
             ('NEW\nYEAR', 'BIG\nDEALS', (20, 40, 110), (255, 255, 255)),
             ('THE\nSALE', 'BUY 1\nTAKE 1', (214, 40, 40), (255, 255, 255)),
             ('LEVEL 5', 'FOOD\nHALL', (243, 181, 98), (60, 30, 10)),
             ('MALASUGUE', 'MALL', (21, 35, 63), (255, 255, 255)),
             ('THE\nSALE', 'EXTRA\n20%', (214, 40, 40), (255, 255, 255))]
    atlas = Image.new('RGB', (2048, 768))
    for i, (top, big, bg, fg) in enumerate(specs):
        im = Image.new('RGB', (W, H), bg)
        d = ImageDraw.Draw(im)
        d.rectangle((10, 10, W - 11, H - 11), outline=fg, width=3)
        d.multiline_text((W // 2, 150), top, font=font('impact.ttf', 44), fill=fg, anchor='mm', align='center', spacing=6)
        d.multiline_text((W // 2, 450), big, font=font('impact.ttf', 70 if len(big) > 2 else 160), fill=fg, anchor='mm', align='center', spacing=8)
        d.text((W // 2, H - 60), 'Malasugue Mall', font=font('segoeuib.ttf', 22), fill=fg, anchor='mm')
        atlas.paste(im, (i * W, 0))
    atlas.save(OUT / 'banners.png')


def running_man(d, x, y, s, c):
    # the exit pictogram, drawn with strokes
    d.ellipse((x + 0.55 * s, y, x + 0.75 * s, y + 0.2 * s), fill=c)
    w = max(int(s * 0.1), 3)
    d.line((x + 0.6 * s, y + 0.25 * s, x + 0.45 * s, y + 0.6 * s), fill=c, width=w)
    d.line((x + 0.45 * s, y + 0.6 * s, x + 0.65 * s, y + 0.8 * s), fill=c, width=w)
    d.line((x + 0.65 * s, y + 0.8 * s, x + 0.6 * s, y + s), fill=c, width=w)
    d.line((x + 0.45 * s, y + 0.6 * s, x + 0.25 * s, y + 0.85 * s), fill=c, width=w)
    d.line((x + 0.25 * s, y + 0.85 * s, x + 0.1 * s, y + 0.82 * s), fill=c, width=w)
    d.line((x + 0.57 * s, y + 0.32 * s, x + 0.8 * s, y + 0.45 * s), fill=c, width=w)
    d.line((x + 0.57 * s, y + 0.32 * s, x + 0.35 * s, y + 0.38 * s), fill=c, width=w)


def wayfinding():
    W, H = 256, 128
    green, white, dark = (0, 150, 70), (255, 255, 255), (30, 34, 40)
    tiles = []

    def tile(bg):
        im = Image.new('RGB', (W, H), bg)
        return im, ImageDraw.Draw(im)

    im, d = tile(green)  # 0 exit
    running_man(d, 18, 20, 88, white)
    d.text((170, 64), 'EXIT', font=font('arialbd.ttf', 52), fill=white, anchor='mm')
    tiles.append(im)
    im, d = tile(green)  # 1 fire exit
    running_man(d, 14, 22, 80, white)
    d.text((168, 50), 'FIRE', font=font('arialbd.ttf', 36), fill=white, anchor='mm')
    d.text((168, 90), 'EXIT', font=font('arialbd.ttf', 36), fill=white, anchor='mm')
    tiles.append(im)
    labels = [('Restrooms', '\u2192'), ('Escalator', '\u2191\u2193'), ('Cinema', '\u2192'), ('Food Hall', '\u2191'),
              ('Stairs', '\u2192'), ('Exit', '\u2190')]
    for t, arrow in labels:  # 2..7
        im, d = tile(dark)
        d.text((22, 64), t, font=font('segoeuib.ttf', 34), fill=white, anchor='lm')
        d.text((W - 26, 64), arrow, font=font('segoeuib.ttf', 46), fill=(255, 200, 60), anchor='rm')
        tiles.append(im)
    for lv in range(5):  # 8..12 level labels
        im, d = tile((240, 240, 236))
        d.text((W // 2, 50), 'LEVEL %d' % (lv + 1), font=font('GILSANUB.TTF', 46), fill=(21, 35, 63), anchor='mm')
        d.text((W // 2, 98), ['Fashion & Lifestyle', 'Style & Beauty', 'Tech & Hobbies', 'Kids, Home & Wellness', 'Food Hall & Cinema'][lv],
               font=font('segoeui.ttf', 22), fill=(60, 70, 90), anchor='mm')
        tiles.append(im)
    for t, bg, fg in [('PUSH', (230, 230, 230), (40, 40, 40)), ('PULL', (230, 230, 230), (40, 40, 40)), ('STAFF ONLY', (200, 30, 30), white)]:  # 13..15
        im, d = tile(bg)
        d.text((W // 2, H // 2), t, font=font('arialbd.ttf', 44), fill=fg, anchor='mm')
        tiles.append(im)
    atlas = Image.new('RGB', (1024, 512))
    for i, im in enumerate(tiles):
        atlas.paste(im, ((i % 4) * W, (i // 4) * H))
    atlas.save(OUT / 'wayfind.png')


def posters():
    S = 256
    rnd = random.Random(15)
    atlas = Image.new('RGB', (1024, 1024))
    words = ['NEW IN', 'SALE', 'HOLIDAY', 'BEST SELLER', 'COLLECTION', '30% OFF', 'JUST ARRIVED', 'GIFT IDEAS',
             'LIMITED', 'TRENDING', 'FRESH', 'PLAY', 'BIG DEALS', 'EXCLUSIVE', 'MADE HERE', 'SEASON']
    for i in range(16):
        bg = tuple(rnd.randint(30, 230) for _ in range(3))
        im = Image.new('RGB', (S, S), bg)
        d = ImageDraw.Draw(im)
        acc = tuple(255 - c for c in bg)
        k = i % 4
        if k == 0:  # a figure
            d.ellipse((98, 30, 158, 90), fill=acc)
            d.polygon([(80, 100), (176, 100), (196, 250), (60, 250)], fill=acc)
        elif k == 1:  # sneaker
            d.polygon([(30, 170), (120, 120), (170, 150), (230, 160), (230, 200), (30, 200)], fill=acc)
            d.rectangle((30, 196, 230, 212), fill=(240, 240, 240))
        elif k == 2:  # circles
            for j in range(5):
                r = rnd.randint(20, 70)
                x, y = rnd.randint(30, 220), rnd.randint(30, 160)
                d.ellipse((x - r, y - r, x + r, y + r), outline=acc, width=6)
        else:  # stripes
            for j in range(0, S, 32):
                d.line((j, 0, j - 120, S), fill=acc, width=10)
        d.rectangle((0, 196, S, S), fill=(250, 250, 250) if sum(bg) < 380 else (20, 20, 20))
        d.text((S // 2, 226), words[i], font=font('impact.ttf', 36), fill=(20, 20, 20) if sum(bg) < 380 else (250, 250, 250), anchor='mm')
        atlas.paste(im, ((i % 4) * S, (i // 4) * S))
    atlas.save(OUT / 'posters.png')


def goods():
    W, H = 1024, 256
    rnd = random.Random(7)
    atlas = Image.new('RGB', (W, 1024), (230, 230, 230))
    pal = [(220, 50, 47), (38, 139, 210), (133, 153, 0), (181, 137, 0), (211, 54, 130), (42, 161, 152), (250, 250, 245),
           (240, 160, 30), (90, 60, 160), (30, 30, 30)]
    for row in range(4):
        im = Image.new('RGB', (W, H), (205, 205, 200))
        d = ImageDraw.Draw(im)
        x = 6
        while x < W - 10:
            w = rnd.randint(28, 70) if row != 3 else rnd.randint(22, 34)
            h = rnd.randint(110, 230) if row != 1 else rnd.randint(90, 220)
            c = rnd.choice(pal)
            if row == 3:  # bottles
                d.rounded_rectangle((x, H - h, x + w, H - 4), 8, fill=c)
                d.rectangle((x + w // 3, H - h - 22, x + 2 * w // 3, H - h), fill=c)
                d.rectangle((x + 2, H - h + 40, x + w - 2, H - h + 80), fill=(250, 250, 240))
            else:
                d.rectangle((x, H - h, x + w, H - 4), fill=c)
                d.rectangle((x + 4, H - h + 12, x + w - 4, H - h + 34), fill=tuple(min(v + 70, 255) for v in c))
                if row == 1:  # toy boxes have a window
                    d.rectangle((x + 6, H - h + 44, x + w - 6, H - 30), fill=(180, 200, 220))
                    d.ellipse((x + w // 2 - 9, H - h + 60, x + w // 2 + 9, H - h + 78), fill=rnd.choice(pal))
            x += w + rnd.randint(1, 5)
        atlas.paste(im, (0, row * H))
    atlas.save(OUT / 'goods.png')


def rails():
    W, H = 1024, 256
    rnd = random.Random(11)
    atlas = Image.new('RGB', (W, 1024), (240, 240, 240))
    cloth = [(30, 30, 35), (240, 240, 235), (120, 20, 30), (25, 50, 100), (200, 170, 120), (90, 110, 70), (210, 120, 140),
             (60, 60, 60), (150, 180, 210), (230, 200, 60)]
    # row 0: hanging garments (transparent gaps are drawn as the shop's wall colour by the shader: here light grey)
    im = Image.new('RGB', (W, H), (232, 230, 226))
    d = ImageDraw.Draw(im)
    x = 0
    while x < W:
        w = rnd.randint(14, 26)
        c = rnd.choice(cloth)
        d.line((x + w // 2, 4, x + w // 2, 16), fill=(120, 120, 120), width=2)
        d.rectangle((x, 16, x + w, rnd.randint(150, 250)), fill=c)
        d.line((x, 16, x, 200), fill=tuple(max(v - 30, 0) for v in c), width=2)
        x += w + 1
    atlas.paste(im, (0, 0))
    # row 1: folded stacks on shelves
    im = Image.new('RGB', (W, H), (220, 214, 205))
    d = ImageDraw.Draw(im)
    for shelf in range(2):
        y0 = 20 + shelf * 120
        x = 8
        while x < W - 60:
            c = rnd.choice(cloth)
            for k in range(rnd.randint(4, 7)):
                d.rectangle((x, y0 + 100 - k * 14, x + 58, y0 + 112 - k * 14), fill=c, outline=tuple(max(v - 40, 0) for v in c))
            x += 70
        d.rectangle((0, y0 + 112, W, y0 + 118), fill=(160, 150, 140))
    atlas.paste(im, (0, H))
    # row 2: shoes on shelves
    im = Image.new('RGB', (W, H), (236, 236, 236))
    d = ImageDraw.Draw(im)
    for shelf in range(3):
        y0 = 10 + shelf * 82
        x = 10
        while x < W - 70:
            c = rnd.choice(cloth)
            d.polygon([(x, y0 + 70), (x + 20, y0 + 44), (x + 44, y0 + 52), (x + 64, y0 + 58), (x + 64, y0 + 70)], fill=c)
            d.rectangle((x, y0 + 68, x + 64, y0 + 73), fill=(250, 250, 250))
            x += 84
        d.rectangle((0, y0 + 74, W, y0 + 78), fill=(190, 190, 190))
    atlas.paste(im, (0, 2 * H))
    # row 3: book spines
    im = Image.new('RGB', (W, H), (60, 40, 30))
    d = ImageDraw.Draw(im)
    for shelf in range(2):
        y0 = 6 + shelf * 125
        x = 4
        while x < W - 10:
            w = rnd.randint(10, 26)
            h = rnd.randint(80, 116)
            c = rnd.choice(cloth + [(120, 60, 30), (20, 60, 40)])
            d.rectangle((x, y0 + 118 - h, x + w, y0 + 118), fill=c)
            d.rectangle((x + 2, y0 + 118 - h + 12, x + w - 2, y0 + 118 - h + 16), fill=(230, 200, 120))
            x += w + 1
    atlas.paste(im, (0, 3 * H))
    atlas.save(OUT / 'rails.png')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    random.seed(15)
    signs()
    ad_frames()
    banners()
    wayfinding()
    posters()
    goods()
    rails()
    print('wrote', OUT)


if __name__ == '__main__':
    main()
