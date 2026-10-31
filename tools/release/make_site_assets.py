"""Website fonts, screenshots and link-preview card from the game's own assets (docs/HOSTING.md).

    python -I tools/release/make_site_assets.py

Writes website/assets/fonts/ (Barlow, Barlow Condensed and Share Tech Mono from game/assets/fonts, subset to Latin and
saved as WOFF), website/assets/img/ (key art and screenshots as WebP) and website/assets/og.jpg (the 1200x630 card chat
apps show for a shared link). Screenshots come from the release captures in work/release_shots (--autotest=tour and
--ui_tour); retake those before a release that changes how the game looks.
"""
import shutil
from pathlib import Path

from fontTools import subset
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONTS = ROOT / "game" / "assets" / "fonts"
SHOTS = ROOT / "work" / "release_shots"
WEB = ROOT / "website" / "assets"

FONT_FILES = ["Barlow-Regular", "Barlow-Medium", "Barlow-SemiBold", "BarlowCondensed-SemiBold", "ShareTechMono-Regular"]
# Basic Latin, Latin-1, general punctuation (dashes, quotes, ellipsis, middle dot), arrows.
UNICODES = "U+0020-007E,U+00A0-00FF,U+2010-2027,U+2030-203A,U+2190-2193,U+2212,U+20B1"

# (output name, source, caption is in index.html)
SCREENS = [
    # 0.22.0: Deathmatch Game Setup with attachments (--ui_tour_r7, work/r22/ui/tour)
    ("loadout", SHOTS / "ui" / "1920x1080_game_setup_picked.png"),
    # 0.21.0: Freight Delight, always night (tools/map_preview.tscn --map=freight_delight --cams=..., docs/FREIGHT_DELIGHT.md)
    ("freight", SHOTS / "freight" / "crane2.png"),
    ("freight-canyon", SHOTS / "freight" / "canyon.png"),
    ("freight-alley", SHOTS / "freight" / "alley.png"),
    ("freight-taas", SHOTS / "freight" / "taas.png"),
    # r17: the mall stays dark all match, so its shots are taken at night (map_preview --times=30)
    ("mall", SHOTS / "mall_night" / "west_escalators_t30.png"),
    ("mall-shops", SHOTS / "mall_night" / "atrium_l1_t30.png"),
    ("mall-tree", SHOTS / "mall" / "east_tree_l3_t450.png"),
    ("menu", SHOTS / "ui" / "1920x1080_menu_home.png"),
    ("lobby", SHOTS / "ui" / "1920x1080_lobby.png"),
    ("street", SHOTS / "tour" / "17_gun_rifle_556.png"),
    ("smartab", SHOTS / "tour" / "21_smartab_status.png"),
    ("drop", SHOTS / "tour" / "03_canopy_team.png"),
    ("flashlight", SHOTS / "tour" / "06_room_flashlight.png"),
]


def fonts() -> None:
    out = WEB / "fonts"
    out.mkdir(parents=True, exist_ok=True)
    for name in FONT_FILES:
        opts = subset.Options()
        opts.flavor = "woff"
        opts.layout_features = ["kern", "liga", "tnum", "lnum"]
        f = subset.load_font(str(FONTS / (name + ".ttf")), opts)
        s = subset.Subsetter(opts)
        s.populate(unicodes=subset.parse_unicodes(UNICODES))
        s.subset(f)
        subset.save_font(f, str(out / (name + ".woff")), opts)
    shutil.copy2(FONTS / "OFL.txt", out / "OFL-Barlow.txt")
    shutil.copy2(FONTS / "OFL_ShareTechMono.txt", out / "OFL-ShareTechMono.txt")


def webp(src: Path, dest: Path, width: int, quality: int = 80) -> None:
    im = Image.open(src).convert("RGB")
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(dest, "WEBP", quality=quality, method=6)


def images() -> None:
    out = WEB / "img"
    out.mkdir(parents=True, exist_ok=True)
    key = ROOT / "game" / "assets" / "ui" / "menu_bg.jpg"
    webp(key, out / "hero.webp", 2400, 78)
    webp(key, out / "hero-small.webp", 1000, 74)
    for name, src in SCREENS:
        webp(src, out / (name + ".webp"), 1600, 82)
        webp(src, out / (name + "-thumb.webp"), 640, 76)


def og_card() -> None:
    """1200x630 link preview: key art, the sun on the right, the name and the call to play on the left."""
    w, h = 1200, 630
    art = Image.open(ROOT / "game" / "assets" / "ui" / "menu_bg.jpg").convert("RGB")
    scale = max(w / art.width, h / art.height)
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
    x0 = art.width - w  # keep the right side, where the sun is
    card = art.crop((x0, (art.height - h) // 2, x0 + w, (art.height - h) // 2 + h)).convert("RGBA")
    shade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(shade)
    for x in range(w):
        a = int(235 * max(0.0, 1.0 - x / (w * 0.72)) ** 1.4)
        d.line([(x, 0), (x, h)], fill=(9, 10, 13, a))
    card = Image.alpha_composite(card, shade)
    d = ImageDraw.Draw(card)
    cond = str(FONTS / "BarlowCondensed-SemiBold.ttf")
    med = str(FONTS / "Barlow-Medium.ttf")
    amber = (242, 163, 59)
    # The name is "Aetherion Project", the byline "by Aljay Leodones" (as on the site and the launcher).
    d.text((72, 92), "OPEN PLAYTEST · PC + ANDROID", font=ImageFont.truetype(med, 28), fill=amber)
    title = ImageFont.truetype(cond, 124)
    d.text((68, 124), "AETHERION", font=title, fill=(236, 237, 230))
    d.text((68, 240), "PROJECT", font=title, fill=(236, 237, 230))
    d.text((72, 378), "by Aljay Leodones", font=ImageFont.truetype(med, 34), fill=amber)
    d.text((72, 450), "Battle royale and deathmatch on the official", font=ImageFont.truetype(med, 30), fill=(205, 210, 208))
    d.text((72, 490), "servers in Singapore. Download and play free.", font=ImageFont.truetype(med, 30), fill=(205, 210, 208))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rectangle([72, 560, 300, 566], fill=amber + (255,))
    card = Image.alpha_composite(card, glow.filter(ImageFilter.GaussianBlur(1)))
    card.convert("RGB").save(WEB / "og.jpg", quality=86, optimize=True, progressive=True)


def sister_game() -> None:
    """The "More from AzAz Games" card: Beyond Heroes art, crown and Cinzel title font from that game's own website
    (../beyond-heroes/launcher/downloads/assets). Skipped, keeping the files already here, when that checkout is absent."""
    bh = ROOT.parent / "beyond-heroes" / "launcher" / "downloads" / "assets"
    if not (bh / "boss.webp").exists():
        print("  (no %s: Beyond Heroes card art left as it is)" % bh)
        return
    # The Kethrax ritual circle, its title and the boss, without the HUD around the edges.
    Image.open(bh / "boss.webp").convert("RGB").crop((360, 100, 1590, 680)).save(
        WEB / "img" / "beyond-heroes.webp", "WEBP", quality=82, method=6)
    Image.open(bh / "crown.png").convert("RGBA").resize((112, 112), Image.LANCZOS).save(WEB / "img" / "beyond-heroes-crown.png")
    opts = subset.Options()
    opts.flavor = "woff"
    f = subset.load_font(str(bh / "cinzel.ttf"), opts)
    s = subset.Subsetter(opts)
    s.populate(unicodes=subset.parse_unicodes(UNICODES))
    s.subset(f)
    subset.save_font(f, str(WEB / "fonts" / "Cinzel.woff"), opts)
    shutil.copy2(bh / "cinzel-license.txt", WEB / "fonts" / "OFL-Cinzel.txt")


def main() -> None:
    WEB.mkdir(parents=True, exist_ok=True)
    fonts()
    images()
    og_card()
    sister_game()
    total = sum(p.stat().st_size for p in WEB.rglob("*") if p.is_file())
    print("site assets written to %s (%.1f MB)" % (WEB, total / 1e6))


if __name__ == "__main__":
    main()
