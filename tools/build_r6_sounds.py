"""r6 sounds: bullet impacts for every material, flesh and head hits, ricochets, fly-bys, casings, body falls and every
step of every reload, from Creative Commons recordings on Freesound and OpenGameArt (downloaded, cut and layered here).

    python -I tools/build_r6_sounds.py fetch            download the sources (tools/cache/freesound/), check licences
    python -I tools/build_r6_sounds.py events <id>...   split a source into takes, plot them (work/lemondev/r6/snd/)
    python -I tools/build_r6_sounds.py build            write game/assets/audio/r6/*.wav and merge ids into sounds.json
    (then bash tools/import.sh). Run build again after tools/build_audio.py, which rewrites sounds.json.

Only CC0 and CC BY sounds are used (each one's licence is read from its own Freesound page at fetch time and kept in
tools/cache/freesound/<id>.json); credits go to game/assets/audio/r6/CREDITS.json and docs/ASSET_MANIFEST.md.
Freesound gives anonymous visitors its high-quality previews (Ogg Vorbis ~192 kbit/s), which is what is fetched.

Recipes (RECIPES below): each output sound is a set of takes. A take is one event cut from a source (onset detection),
optionally layered with another (a bullet's crack over a material's own hit), filtered, faded and peak-normalised to
48 kHz mono 16-bit WAV.
"""
import json, math, os, re, sys, time, urllib.parse, urllib.request
import numpy as np
import soundfile as sf

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_audio as ba

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, 'tools', 'cache', 'freesound')
OUT = os.path.join(ROOT, 'game', 'assets', 'audio', 'r6')
PLOTS = os.path.join(ROOT, 'work', 'lemondev', 'r6', 'snd')
SOUNDS = os.path.join(ROOT, 'game', 'data', 'sounds.json')
SR = ba.SR
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
RNG = np.random.default_rng(606)

# Freesound sources: id -> (user, what it is used for). The licence is read from the sound's page at fetch time.
FS = {
    # bullet impacts (generic cracks and thuds)
    150837: ('toxicwafflezz', 'bullet impact'), 150838: ('toxicwafflezz', 'bullet impact'), 150839: ('toxicwafflezz', 'bullet impact'),
    423107: ('OGsoundFX', 'bullet impact'), 423106: ('OGsoundFX', 'bullet impact'), 144444: ('pushkin', 'bullet impacts'),
    161001: ('deleted_user_13710', 'bullet hits'), 116645: ('Woodingp', 'bullet hits'), 789388: ('modusmogulus', 'bullet into ground'),
    # materials
    179365: ('lolamadeus', 'rock and stone hits'), 536803: ('egomassive', 'stone'), 567251: ('iwanPlays', 'stones falling'),
    554148: ('Nox_Sound', 'stone debris'), 319226: ('worthahep88', 'rock on wood'), 319228: ('worthahep88', 'rock on wood'),
    319227: ('worthahep88', 'rock on wood'), 319223: ('worthahep88', 'rock on wood'), 449955: ('Breviceps', 'wooden thud'),
    351422: ('Diramus', 'wood crack'), 421929: ('micahlg', 'chopping wood'), 182263: ('martian', 'bullet hit metal'),
    399550: ('BorekPL', 'bullet hits a car'), 351371: ('wilhellboy', 'heavy bullet ping'), 530486: ('Rickplayer', 'metal impact'),
    244983: ('ani_music', 'pipe hit'), 319229: ('worthahep88', 'rock on dirt'), 319222: ('worthahep88', 'rock on dirt'),
    325268: ('deleted_user_2104797', 'brick on soil'), 683788: ('Elements-Libraries', 'hard impact on sand'),
    398032: ('swordofkings12', 'splash'), 166325: ('deleted_user_2104797', 'water drop'), 533146: ('mattfinarelli', 'water drop'),
    50623: ('vibe_crc', 'water splashes'), 418194: ('deleted_user_3654113', 'hard glass impact'), 221528: ('unfa', 'glass break'),
    244238: ('chewiesmissus', 'glass smash'), 233607: ('abstraktgenerierung', 'breaking glass'), 190396: ('JoyDreamerJourney', 'pillow punch'),
    388035: ('saturdaysoundguy', 'pillow hit'), 344669: ('daymonjlong', 'pillow smash'), 496187: ('JonasTisell', 'body thud on clothing'),
    629977: ('Flem0527', 'clothed body hit'), 401773: ('oztrum', 'plastic cup'), 532139: ('j1987', 'wet plastic hit'),
    505963: ('jedg', 'small plastic impacts'), 321294: ('goldendiaphragm', 'plastic boxes'), 106113: ('j1987', 'bush hit'),
    178615: ('Montacue', 'bush rustle'), 327894: ('Kreastricon62', 'bush cut'), 235754: ('elliotlp', 'dry leaf'),
    538152: ('Fupicat', 'leaves'), 583310: ('Fission9', 'tile breaking'), 554367: ('Nox_Sound', 'tiles smash'),
    128286: ('rebeat', 'plate stack hit'), 565642: ('jc.sg', 'plate break'),
    # flesh, heads, armour
    423301: ('u1769092', 'visceral bullet impacts'), 452155: ('bananplyte', 'bullets hitting gore'), 276600: ('insanity54', 'body hit'),
    500912: ('Bertsz', 'squish impact'), 641040: ('magnuswaker', 'gross impact'), 360942: ('gprosser', 'splat'),
    55234: ('SlykMrByches', 'splat'), 453769: ('kyles', 'blood squirt'), 511194: ('Pablobd', 'headshot'),
    660769: ('MadPanCake', 'headshot'), 697829: ('magnuswaker', 'skull crush'), 470585: ('SilverIllusionist', 'headshot'),
    470586: ('SilverIllusionist', 'headshot'), 453756: ('kyles', 'plastic helmet hit'),
    # ricochets and fly-bys
    30932: ('aust_paul', 'ricochet'), 148840: ('cedarstudios', 'ricochet'), 213925: ('Diboz', 'ricochet'), 392975: ('morganpurkis', 'ricochet'),
    634884: ('harrisonlace', 'ricochet'), 148827: ('cedarstudios', '.22 ricochets'), 505238: ('Daleonfire', 'whizz-by'),
    730351: ('GO_s0unds123', 'bullet fly-bys'), 855248: ('qubodup', 'real bullet fly-by'), 789222: ('modusmogulus', 'subsonic whizz'),
    123222: ('CGEffex', 'bullet whizz'), 90782: ('kMoon', 'bullet fly-by'), 90783: ('kMoon', 'bullet fly-by'), 90784: ('kMoon', 'bullet fly-by'),
    134024: ('Audionautics', 'bullet pass-bys'),
    # casings, bodies
    210102: ('GrayJoy', 'brass casings on concrete'), 205126: ('Danwardvs', '.30 case bouncing'), 580287: ('kmmediafactory', 'bullet shells'),
    370805: ('LilMati', 'shell on a table'), 620929: ('Metrolynn', 'shotgun shells hitting ground'), 773860: ('MrGungus', '12 gauge shell drop'),
    436070: ('rammbostein', '12 gauge shell drop'), 417994: ('DylanTheFish', 'body fall'), 504626: ('leonelmail', 'body fall on dirt'),
    346694: ('deleted_user_2104797', 'body fall'), 395331: ('ihitokage', 'body falling'), 364690: ('alegemaate', 'human impact on ground'),
    504617: ('NeoSpica', 'body falling'),
    # gun mechanics
    725397: ('seroutonin', 'M16 empty reload sequence'), 674742: ('seroutonin', 'AK-47 unload and reload'),
    677160: ('seroutonin', 'Uzi empty reload sequence'), 456195: ('e9118586020', 'handgun mag out and in'), 263513: ('wadaltmon', 'AR15 sounds'),
    815879: ('qubodup', 'assault rifle reload'), 432141: ('MaximBomba', 'rifle reload'), 432139: ('MaximBomba', 'pistol reload'),
    396331: ('nioczkus', '1911 reload'), 677159: ('seroutonin', 'revolver handling'), 693125: ('seroutonin', 'revolver ejecting'),
    177863: ('Dredile', 'revolver reload'), 139001: ('jhka', 'revolver chamber spin'), 402790: ('acidsnowflake', 'cocking a revolver'),
    370345: ('Zott820', 'Mosin Nagant bolt cycle'), 204204: ('Danwardvs', '.22 bolt'), 725398: ('seroutonin', 'M1 Garand clip'),
    370344: ('Zott820', 'pump shotgun cycle'), 233044: ('klangfabrik', 'pump shotgun takes'), 200966: ('Paul368', 'shotgun cock'),
    537724: ('yeet2020202020', 'shotgun cocking'), 108793: ('CeebFrack', 'shell load'), 379976: ('morganpurkis', 'inserting shell'),
    500293: ('Bratish', 'shotgun shell load'), 379977: ('morganpurkis', 'inserting magazine'), 104407: ('Nanashi', 'mag remove'),
    444402: ('MootMcnoodles', 'magazine hitting surface'), 52202: ('sentryx86', 'single barrel shotgun loading'),
    722902: ('tkane0512', 'break-top revolver'), 154934: ('KlawyKogut', 'empty gun'), 104412: ('Nanashi', 'trigger and hammer'),
    427603: ('michorvath', 'rifle clip empty'), 377145: ('nioczkus', 'pistol draw'), 688765: ('qubodup', 'unholster gun'),
    415304: ('nioczkus', 'revolver unholster'), 107795: ('j1987', 'gun fiddle'),
}


# ------------------------------------------------------------------ fetch

def _get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def fetch():
    os.makedirs(CACHE, exist_ok=True)
    cands = {}
    for f in ('candidates.json', 'candidates2.json', 'candidates3.json'):
        p = os.path.join(CACHE, '_search', f)
        if os.path.exists(p):
            for cat in json.load(open(p, encoding='utf8')).values():
                for k, x in cat.items():
                    cands.setdefault(int(k), x)
    for sid, (user, what) in FS.items():
        meta_p = os.path.join(CACHE, '%d.json' % sid)
        ogg_p = os.path.join(CACHE, '%d.ogg' % sid)
        if os.path.exists(meta_p) and os.path.exists(ogg_p):
            continue
        c = cands.get(sid, {})
        page_url = 'https://freesound.org/people/%s/sounds/%d/' % (urllib.parse.quote(c.get('user', user)), sid)
        try:
            page = _get(page_url).decode('utf8', 'replace')
        except Exception as e:
            print('page failed', sid, e)
            continue
        lic = re.search(r'href="(https?://creativecommons\.org/(?:publicdomain/zero|licenses/[a-z-]+)/[0-9.]+/?)"', page)
        lic = lic.group(1) if lic else ''
        if 'publicdomain/zero' in lic:
            name = 'CC0-1.0'
        elif re.search(r'/licenses/by/[0-9.]+', lic):
            name = 'CC-BY-' + re.search(r'/by/([0-9.]+)', lic).group(1).rstrip('/')
        else:
            print('SKIP licence', sid, lic or 'not found')
            continue
        title = re.search(r'<meta property="og:title" content="([^"]*)"', page)
        prev = c.get('ogg') or ''
        if not prev:
            m = re.search(r'data-ogg="([^"]+)"', page)
            prev = m.group(1) if m else ''
        prev = prev.replace('-lq.ogg', '-hq.ogg')
        try:
            data = _get(prev)
        except Exception as e:
            print('audio failed', sid, e)
            continue
        open(ogg_p, 'wb').write(data)
        json.dump({'id': sid, 'title': title.group(1) if title else c.get('title', ''), 'author': c.get('user', user), 'url': page_url,
                   'license': name, 'license_url': lic, 'preview': prev, 'retrieved': time.strftime('%Y-%m-%d')},
                  open(meta_p, 'w', encoding='utf8'), indent=1)
        print('got', sid, name, len(data))
        time.sleep(0.4)


# ------------------------------------------------------------------ audio

def load(src):
    """Mono float at SR from a Freesound id or an OpenGameArt/other path under tools/cache."""
    p = os.path.join(CACHE, '%d.ogg' % src) if isinstance(src, int) else os.path.join(ROOT, src)
    x, sr = sf.read(p, always_2d=True)
    x = x.mean(axis=1).astype(np.float64)
    if sr != SR:
        x = ba.resample(x, sr, SR)
    return x


def events(x, min_gap=0.06, thresh_db=-30.0, pre=0.008, tail_db=-46.0):
    """Takes in a recording: [(start, end)] in samples, where the level rises well above the floor."""
    hop = int(SR * 0.004)
    n = len(x) // hop
    if n < 3:
        return [(0, len(x))]
    env = np.sqrt(np.mean(x[:n * hop].reshape(n, hop) ** 2, axis=1) + 1e-12)
    db = 20 * np.log10(env + 1e-9)
    peak = db.max()
    floor = np.percentile(db, 15)
    on_t = max(peak + thresh_db, floor + 10.0)
    off_t = max(peak + tail_db, floor + 4.0)
    out = []
    i = 0
    while i < n:
        if db[i] >= on_t:
            s = i
            j = i
            quiet = 0
            while j < n:
                if db[j] < off_t:
                    quiet += 1
                    if quiet * hop >= min_gap * SR:
                        break
                else:
                    quiet = 0
                j += 1
            e = j - quiet
            out.append((max(0, s * hop - int(pre * SR)), min(len(x), (e + 2) * hop)))
            i = j
        else:
            i += 1
    return out or [(0, len(x))]


def plot(src):
    from PIL import Image, ImageDraw
    x = load(src)
    ev = events(x)
    W, H = 1600, 260
    img = Image.new('RGB', (W, H), (16, 16, 20))
    d = ImageDraw.Draw(img)
    n = len(x)
    col = np.array_split(np.abs(x), W)
    for i, c in enumerate(col):
        a = float(c.max()) if len(c) else 0.0
        d.line([(i, H // 2 - a * H * 0.45), (i, H // 2 + a * H * 0.45)], fill=(120, 190, 240))
    for k, (s, e) in enumerate(ev):
        xs, xe = int(s / n * W), int(e / n * W)
        d.rectangle([xs, 4, max(xe, xs + 1), H - 4], outline=(250, 120, 60))
        d.text((xs + 2, 6), str(k), fill=(255, 220, 120))
    meta = json.load(open(os.path.join(CACHE, '%d.json' % src), encoding='utf8')) if isinstance(src, int) else {'title': src}
    d.text((6, H - 16), '%s  %s  %.2fs  %d takes' % (src, meta.get('title', '')[:70], n / SR, len(ev)), fill=(230, 230, 230))
    os.makedirs(PLOTS, exist_ok=True)
    img.save(os.path.join(PLOTS, '%s.png' % (src if isinstance(src, int) else os.path.basename(src))))
    print(src, ['%d:%.2f-%.2f' % (k, s / SR, e / SR) for k, (s, e) in enumerate(ev)])


def take(src, k=None, t=None):
    """One take: event k of the source, or the span t = (start s, end s), or the whole thing."""
    x = load(src)
    if t is not None:
        return x[int(t[0] * SR):int(t[1] * SR)]
    if k is None:
        s, e = events(x)[0][0], events(x)[-1][1]
        return x[s:e]
    ev = events(x)
    s, e = ev[k % len(ev)]
    return x[s:e]


def shape(x, hp=0.0, lp=0.0, gain=1.0, max_len=0.0, fade_out=30.0):
    if hp > 0:
        x = ba.highpass_fast(x, hp)
    if lp > 0:
        x = ba.lowpass_fast(x, lp)
    # Start on the sound, 4 ms before it first reaches 15 % of its peak: a cue timed to a hand's motion or an impact
    # timed to a bullet must not wait through silence.
    a = np.abs(x)
    if len(a):
        first = int(np.argmax(a > a.max() * 0.15))
        x = x[max(0, first - int(0.004 * SR)):]
    if max_len > 0 and len(x) > max_len * SR:
        x = x[:int(max_len * SR)]
    x = ba.fade(x, 1.5, fade_out)
    pk = np.max(np.abs(x)) + 1e-9
    return x / pk * gain


def mix(*layers):
    """[(signal, gain, delay s)] summed."""
    n = max(len(s) + int(d * SR) for s, g, d in layers)
    out = np.zeros(n)
    for s, g, d in layers:
        o = int(d * SR)
        out[o:o + len(s)] += s / (np.max(np.abs(s)) + 1e-9) * g
    return out


def all_takes(src, limit=99, min_len=0.03, max_len=4.0):
    x = load(src)
    out = []
    for s, e in events(x):
        if min_len * SR <= e - s <= max_len * SR:
            out.append(x[s:e])
        if len(out) >= limit:
            break
    return out


# ------------------------------------------------------------------ recipes

def snap(c):
    """The first instant of a bullet-impact recording: the round's sharp crack, without the recording's own debris."""
    c = shape(c, hp=1200)
    return ba.fade(c[:int(0.07 * SR)], 0.5, 45)


def impacts_layered(cracks, bodies, n, crack_gain=0.8, body_gain=1.0, hp=0.0, lp=0.0, max_len=1.2, body_delay=0.003, seed=0):
    """A bullet's crack over a material's own hit: n takes, each a different pairing (seed varies the pairing per
    material so two materials never share their cracks in the same order)."""
    out = []
    for i in range(n):
        c = cracks[(i * 5 + seed * 7) % len(cracks)]
        b = bodies[i % len(bodies)]
        out.append(shape(mix((snap(c), crack_gain, 0.0), (shape(b), body_gain, body_delay)), hp=hp, lp=lp, max_len=max_len))
    return out


def hits(src, starts, length):
    """Takes at known times in a recording whose noise floor hides the gaps from the detector."""
    return [take(src, t=(t, t + length)) for t in starts]


def recipes():
    """sound id -> (takes, sounds.json settings). Takes are numpy arrays."""
    R = {}
    crack = []
    for s in (150837, 150838, 150839, 423107, 423106):
        crack += all_takes(s, 2, max_len=1.0)
    crack += all_takes(144444, 12, max_len=4.0) + all_takes(161001, 8, max_len=4.0) + all_takes(116645, 8, max_len=4.0)
    stone = all_takes(179365, 10, max_len=1.2) + all_takes(536803, 2)
    debris = all_takes(554148, 4, max_len=1.5) + all_takes(567251, 2, max_len=1.5)
    R['impact_concrete'] = ([shape(mix((snap(c), 0.8, 0.0), (shape(s, hp=150), 1.0, 0.003), (shape(d, hp=400), 0.3, 0.05)), max_len=1.1)
                             for c, s, d in zip(crack[1::3] * 2, stone, debris * 3)][:8], dict(db=-2.0, dist=60.0, prio=5, unit=4.0))
    wood = all_takes(319226, 2) + all_takes(319228, 2) + all_takes(319227, 2) + all_takes(319223, 2) + all_takes(449955, 2) + all_takes(421929, 2)
    R['impact_wood'] = (impacts_layered(crack, wood + all_takes(351422, 2), 8, crack_gain=0.55, seed=1), dict(db=-2.0, dist=60.0, prio=5, unit=4.0))
    sheet = hits(182263, [0.08, 2.4, 4.42, 7.25, 10.55, 12.37, 14.34, 17.5], 0.75) + all_takes(399550, 1, max_len=1.6)
    R['impact_metal_sheet'] = ([shape(s, hp=120, max_len=1.4) for s in sheet[:10]], dict(db=0.0, dist=75.0, prio=5, unit=4.0))
    steel = all_takes(351371, 2) + all_takes(530486, 2) + all_takes(244983, 2)
    R['impact_metal'] = (impacts_layered(crack, steel + sheet[:4], 8, crack_gain=0.6, max_len=1.4, seed=2), dict(db=0.0, dist=70.0, prio=5, unit=4.0))
    dirt = all_takes(319229, 3) + all_takes(319222, 3) + all_takes(325268, 2) + all_takes(683788, 4) + all_takes(789388, 2)
    R['impact_dirt'] = (impacts_layered(crack, dirt, 8, crack_gain=0.45, lp=9000, max_len=1.0, seed=3), dict(db=-4.0, dist=40.0, prio=4, unit=4.0))
    water = all_takes(50623, 10, min_len=0.12, max_len=2.0) + all_takes(398032, 2) + all_takes(533146, 2) + all_takes(166325, 2)
    R['impact_water'] = ([shape(w, hp=100, max_len=1.4) for w in water[:8]], dict(db=-2.0, dist=50.0, prio=4, unit=4.0))
    glass = all_takes(418194, 2) + all_takes(221528, 2) + all_takes(244238, 2) + all_takes(233607, 2)
    R['impact_glass'] = (impacts_layered(crack, glass, 6, crack_gain=0.5, max_len=1.6, seed=4), dict(db=0.0, dist=60.0, prio=5, unit=4.0))
    soft = all_takes(190396, 4) + all_takes(388035, 2) + all_takes(344669, 2) + all_takes(496187, 2) + all_takes(629977, 2)
    R['impact_fabric'] = (impacts_layered(crack, soft, 7, crack_gain=0.25, lp=6000, max_len=0.8, seed=5), dict(db=-6.0, dist=25.0, prio=3, unit=4.0))
    R['impact_soft'] = R['impact_fabric']
    plastic = all_takes(505963, 10) + all_takes(401773, 2) + all_takes(532139, 2) + all_takes(321294, 2)
    R['impact_plastic'] = (impacts_layered(crack, plastic, 7, crack_gain=0.4, max_len=0.9, seed=6), dict(db=-4.0, dist=35.0, prio=4, unit=4.0))
    leaf = all_takes(106113, 3) + all_takes(178615, 2) + all_takes(327894, 2) + all_takes(235754, 2) + all_takes(538152, 2)
    R['impact_foliage'] = ([shape(l, hp=300, max_len=0.9) for l in leaf[:6]], dict(db=-10.0, dist=20.0, prio=2, unit=4.0))
    tile = all_takes(583310, 2) + all_takes(554367, 6, max_len=1.5) + all_takes(128286, 2) + all_takes(565642, 2)
    R['impact_tile'] = (impacts_layered(crack, tile, 7, crack_gain=0.6, max_len=1.3, seed=7), dict(db=-2.0, dist=60.0, prio=5, unit=4.0))
    flesh = all_takes(423301, 6) + all_takes(452155, 6) + all_takes(276600, 2) + all_takes(500912, 2) + all_takes(641040, 2) + all_takes(360942, 2)
    wet = all_takes(55234, 2) + all_takes(453769, 2) + all_takes(360942, 2)
    R['impact_flesh'] = ([shape(mix((shape(f), 1.0, 0.0), (shape(w, hp=500), 0.35, 0.02)), max_len=0.9) for f, w in zip(flesh, wet * 4)][:10],
                         dict(db=-1.0, dist=35.0, prio=6, unit=4.0))
    head = all_takes(511194, 2) + all_takes(660769, 2) + all_takes(697829, 2) + all_takes(470585, 2) + all_takes(470586, 2)
    R['impact_flesh_head'] = ([shape(mix((shape(h), 1.0, 0.0), (shape(f), 0.5, 0.004)), max_len=0.7) for h, f in zip(head, flesh[3:])][:6],
                              dict(db=1.0, dist=40.0, prio=7, unit=4.0))
    helmet = all_takes(453756, 3)
    R['impact_helmet'] = ([shape(mix((snap(c), 0.6, 0.0), (shape(h), 1.0, 0.002)), max_len=1.0) for c, h in zip(crack[2::3], helmet * 2)][:4],
                          dict(db=2.0, dist=50.0, prio=6, unit=4.0))
    ric = all_takes(30932, 1) + all_takes(148840, 1) + all_takes(213925, 1) + all_takes(392975, 1) + all_takes(634884, 1) + all_takes(148827, 4, max_len=2.5)
    R['ricochet'] = ([shape(r, hp=300, max_len=2.2, fade_out=120) for r in ric[:8]], dict(db=0.0, dist=80.0, prio=6, unit=4.0))
    whiz_sub = all_takes(505238, 1) + all_takes(789222, 1) + all_takes(123222, 1)
    whiz_sup = all_takes(855248, 1) + all_takes(90782, 1) + all_takes(90783, 1) + all_takes(90784, 1) + all_takes(730351, 6, max_len=1.5) + all_takes(134024, 6, max_len=1.5)
    R['flyby_whiz'] = ([shape(w, hp=200, max_len=1.6, fade_out=80) for w in whiz_sub + whiz_sup[4:6]], dict(db=-2.0, dist=8.0, prio=7, unit=3.0))
    R['flyby_crack'] = ([shape(w, hp=400, max_len=0.9, fade_out=60) for w in whiz_sup[:8]], dict(db=2.0, dist=8.0, prio=7, unit=3.0))
    brass = all_takes(210102, 10, max_len=1.2) + all_takes(205126, 4, max_len=1.5) + all_takes(580287, 6, max_len=1.2) + all_takes(370805, 1)
    R['casing_drop'] = ([shape(b, hp=600, max_len=1.0) for b in brass[:10]], dict(db=-14.0, dist=18.0, prio=1, unit=1.0))
    shells = all_takes(620929, 3) + all_takes(773860, 2) + all_takes(436070, 3)
    R['shell_drop'] = ([shape(s, hp=200, max_len=1.0) for s in shells[:6]], dict(db=-12.0, dist=18.0, prio=1, unit=1.0))
    falls = all_takes(417994, 1) + all_takes(504626, 1) + all_takes(346694, 1) + all_takes(395331, 1) + all_takes(364690, 1) + all_takes(504617, 1)
    R['bodyfall'] = ([shape(f, hp=60, max_len=1.6) for f in falls], dict(db=0.0, dist=30.0, prio=5, unit=4.0))
    R.update(mechanics())
    return R


def mechanics():
    """Each reload step from takes cut out of whole recorded sequences (see the plots) and single recordings."""
    M = {}
    for sid, picks in MECH_TAKES.items():
        takes = []
        for p in picks:
            src, k = p[0], p[1]
            if k is None:
                takes.append(shape(take(src), hp=120, max_len=1.2, fade_out=25))
            elif isinstance(k, tuple):
                takes.append(shape(take(src, t=k), hp=120, max_len=1.2, fade_out=25))
            else:
                takes.append(shape(take(src, k), hp=120, max_len=1.2, fade_out=25))
        M[sid] = (takes, dict(db=MECH_DB.get(sid, -6.0), dist=16.0 if sid != 'weapon_draw' else 10.0, prio=4, unit=3.0))
    # The pouch: cloth from the Kenney RPG pack already in the game.
    pouch = []
    for n in ('cloth1', 'cloth2', 'cloth3', 'cloth4'):
        p = 'game/assets/audio/kenney/rpg/%s.ogg' % n
        if os.path.exists(os.path.join(ROOT, p)):
            pouch.append(shape(load(p), hp=300, max_len=0.6))
    M['mag_pouch'] = (pouch, dict(db=-14.0, dist=8.0, prio=2, unit=2.0))
    return M


# Reload steps: sound id -> [(source, take index or (start s, end s))], read off the plots in work/lemondev/r6/snd
# (`events` above) and the recordists' own descriptions of their sequences (e.g. 263513: mag out, part in, home, out,
# in, charging handle, bolt catch; 370345: four hits per bolt cycle - up, back, forward, down; 370344: back and forward
# per pump; 177863: cylinder open, cases out, rounds in, close and spin; 52202: open, cock, dry fire, open, load, eject).
OGA = 'tools/cache/oga/'
WS = 'work/sounds/guns/'   # the owner's own sounds (2026-10-27): their reloads are cut into steps here too
MECH_TAKES = {
    'mag_out': [(WS + 'reload_rifle.mp3', 0), (WS + 'reload_smg.mp3', 0), (263513, 1), (263513, 4), (815879, 0), (674742, 0), (432141, 0), (725397, (0.16, 0.75))],
    'mag_in': [(WS + 'reload_rifle.mp3', 1), (WS + 'reload_smg.mp3', 1), (263513, 3), (263513, 5), (815879, 1), (674742, 1), (432141, 1), (677160, 1), (725397, (2.48, 2.84))],
    'mag_out_pistol': [(WS + 'reload_pistol.mp3', 0), (432139, 0), (456195, 0), (456195, 4), (677160, 0)],
    'mag_in_pistol': [(WS + 'reload_pistol.mp3', 1), (432139, 1), (456195, 2), (456195, 6), (456195, 9)],
    'charge_back': [(263513, (3.42, 3.6)), (725397, (4.12, 4.45)), (815879, 2), (677160, 2)],
    'charge_release': [(WS + 'reload_rifle.mp3', 2), (WS + 'reload_finish.mp3', None), (263513, (3.6, 3.9)), (725397, (4.6, 5.05)), (815879, 3), (677160, 3), (263513, 7)],
    'slide_back': [(432139, 2), (677160, 2), (815879, 2)],
    'slide_release': [(432139, 3), (263513, 7), (677160, 3)],
    'bolt_up': [(370345, (0.1, 0.33)), (370345, (2.18, 2.42)), (370345, (13.42, 13.62)), (204204, 0)],
    'bolt_back': [(WS + 'reload_sniper.mp3', 0), (370345, (0.36, 0.7)), (370345, (2.44, 2.7)), (370345, (13.62, 13.85)), (204204, (0.26, 0.38))],
    'bolt_fwd': [(WS + 'reload_sniper.mp3', 1), (370345, (0.78, 1.1)), (370345, (2.7, 2.95)), (370345, (13.85, 14.03)), (204204, (0.38, 0.5))],
    'bolt_down': [(370345, (1.15, 1.49)), (370345, (2.95, 3.15)), (370345, (14.03, 14.19)), (204204, 2)],
    'clip_in': [(OGA + 'clipload1.wav', None), (379977, 0), (OGA + 'reload.wav', None)],
    'pump_back': [(370344, (0.03, 0.4)), (370344, (2.46, 2.7)), (370344, (3.3, 3.6)), (370344, (6.72, 6.95))],
    'pump_fwd': [(370344, (0.42, 0.96)), (370344, (2.7, 2.98)), (370344, (3.6, 3.84)), (370344, (6.95, 7.17))],
    'pipe_slide': [(370344, (0.03, 0.4)), (370344, (3.6, 3.84)), (370344, (2.46, 2.7))],
    'shell_insert': [(108793, 0), (379976, 0), (500293, 0), (52202, 5), (OGA + 'singlebullet1.wav', None)],
    'cylinder_open': [(177863, 0), (722902, 0)],
    'cylinder_close': [(177863, 5), (722902, 3)],
    'round_insert': [(177863, 3), (177863, 2), (OGA + 'singlebullet1.wav', None), (379976, 0)],
    'cylinder_click': [(139001, (0.0, 0.22)), (677159, 1), (677159, 2), (677159, 0)],
    'break_open': [(52202, 0), (52202, 4), (722902, 0), (52202, 10)],
    'break_close': [(722902, 3), (52202, 7), (52202, 9)],
    'shell_eject': [(52202, 11), (693125, (0.0, 0.55)), (693125, (0.55, 1.1))],
    'weapon_draw': [(377145, 0), (688765, 0), (415304, 0)],
    'dry_fire': [(154934, 0), (104412, 0), (427603, 0), (677159, 0)],
}
MECH_DB = {'dry_fire': -4.0, 'weapon_draw': -8.0, 'cylinder_click': -8.0, 'shell_eject': -8.0, 'round_insert': -8.0}


# ------------------------------------------------------------------ build

OWNER_HITS = {'impact_dirt': ['dirt_hit1', 'dirt_hit2'], 'impact_metal': ['metal_hit1', 'metal_hit2', 'metal_hit3'],
              'impact_metal_sheet': ['metal_hit1', 'metal_hit2'], 'impact_concrete': ['wall_hit1', 'wall_hit2', 'wall_hit3', 'wall_hit4'],
              'impact_wood': ['wood_hit1', 'wood_hit2']}

def build():
    os.makedirs(OUT, exist_ok=True)
    R = recipes()
    defs = {}
    for sid, (takes, kw) in sorted(R.items()):
        files = []
        for i, x in enumerate(takes):
            if len(x) < int(0.02 * SR):
                continue
            p = os.path.join(OUT, '%s_%d.wav' % (sid, i))
            ba.write_wav(p, x, peak=0.89)
            files.append(ba.rel(p))
        if files:
            d = {'files': files, 'pitch': 0.04}
            d.update(kw)
            defs[sid] = d
        print('%-20s %d takes' % (sid, len(files)))
    # The owner's own bullet hits (work/sounds, added 2026-10-27) stay in the sets they were made for.
    for sid, names in OWNER_HITS.items():
        if sid in defs:
            defs[sid]['files'] += ['assets/audio/work/guns/%s.mp3' % n for n in names]
    with open(SOUNDS, encoding='utf-8') as fh:
        data = json.load(fh)
    data['sounds'].update(defs)
    with open(SOUNDS, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=1)
    credits = []
    for f in sorted(os.listdir(CACHE)):
        if f.endswith('.json') and f[:-5].isdigit():
            credits.append(json.load(open(os.path.join(CACHE, f), encoding='utf8')))
    json.dump(credits, open(os.path.join(OUT, 'CREDITS.json'), 'w', encoding='utf8'), indent=1)
    print('merged', len(defs), 'sounds;', len(credits), 'credited sources')


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'build'
    if cmd == 'fetch':
        fetch()
    elif cmd == 'events':
        for a in sys.argv[2:]:
            plot(int(a) if a.isdigit() else a)
    else:
        build()
