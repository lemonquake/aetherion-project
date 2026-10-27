"""Builds the game's sound set and data/sounds.json.

    python -I tools/build_audio.py

- Cuts single shots out of the CC0 Free Firearm Sound Library recordings (96 kHz / 24-bit multi-shot takes),
  normalises them and makes a distant variant of each (low-passed, quieter, with a slap-back echo off buildings).
- Copies selected Kenney CC0 sounds, Wikimedia Commons glass breaks, and audio from the owner's Sleep project
  (footsteps, doors, gun foley, impacts, night ambience) with their original credits.
- Synthesises what no library had: radio clicks and static, SmarTab handling, flashlight and battery clicks,
  bullet cracks and whizzes, parachute sounds, the haze warning chime, splashes and thuds.
- Writes data/sounds.json: id -> {files, db, dist, pitch, prio, unit, far, far_from, loop}.

All output is 48 kHz 16-bit mono WAV (Godot imports it directly), except copied OGG files.
"""
import json
import re
import sys
import os
import shutil
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, 'game')
OUT = os.path.join(GAME, 'assets', 'audio')
CACHE = os.path.join(ROOT, 'tools', 'cache')
FIRE = os.path.join(CACHE, 'audio_libs', 'firearms', 'Prepared SFX Library')
KEN = os.path.join(CACHE, 'kenney')
SLEEP = 'A:/3rd Harmonik/interior/game/assets/audio'
SR = 48000
RNG = np.random.default_rng(1729)
SOUNDS = {}


# ------------------------------------------------------------------ io

def read_wav(path):
    with wave.open(path) as w:
        ch, sw, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        x = (b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16))
        x = np.where(x & 0x800000, x - 0x1000000, x).astype(np.float64) / 8388608.0
    elif sw == 2:
        x = np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0
    elif sw == 4:
        x = np.frombuffer(raw, dtype=np.int32).astype(np.float64) / 2147483648.0
    else:
        x = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    x = x.reshape(-1, ch).mean(axis=1)
    if sr != SR:
        x = resample(x, sr, SR)
    return x


def resample(x, sr_in, sr_out):
    if sr_in == sr_out:
        return x
    if sr_in == 2 * sr_out:
        n = len(x) // 2 * 2
        return 0.5 * (x[:n:2] + x[1:n:2])
    t = np.arange(0, len(x) * sr_out / sr_in) * sr_in / sr_out
    return np.interp(t, np.arange(len(x)), x)


def write_wav(path, x, peak=0.89):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    m = np.max(np.abs(x)) if len(x) else 0.0
    if m > 0:
        x = x / m * peak
    pcm = np.clip(x * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def rel(path):
    return os.path.relpath(path, GAME).replace('\\', '/')


def define(sid, files, db=0.0, dist=40.0, pitch=0.05, prio=2, unit=4.0, **extra):
    d = {'files': [rel(f) for f in files], 'db': db, 'dist': dist, 'pitch': pitch, 'prio': prio, 'unit': unit}
    d.update(extra)
    SOUNDS[sid] = d


def source_json(folder, rec):
    os.makedirs(folder, exist_ok=True)
    rec.setdefault('retrieved', '2026-10-26')
    with open(os.path.join(folder, 'source.json'), 'w', encoding='utf-8') as f:
        json.dump(rec, f, indent=2, ensure_ascii=False)


# ------------------------------------------------------------------ dsp

def lowpass(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def lowpass_fast(x, cutoff, passes=2):
    # Repeated moving average approximates a gentle low-pass without a Python loop.
    k = max(int(SR / cutoff / 2.0), 1)
    y = x
    for _ in range(passes):
        y = np.convolve(y, np.ones(k) / k, mode='same')
    return y


def highpass_fast(x, cutoff):
    return x - lowpass_fast(x, cutoff)


def env(n, attack, decay, sustain=0.0, curve=4.0):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) * curve / max(decay, 1e-4))
    return a * (sustain + (1 - sustain) * d)


def noise(n):
    return RNG.standard_normal(n)


def fade(x, ms_in=2.0, ms_out=40.0):
    n_in = int(SR * ms_in / 1000)
    n_out = int(SR * ms_out / 1000)
    y = x.copy()
    if n_in:
        y[:n_in] *= np.linspace(0, 1, n_in)
    if n_out and n_out < len(y):
        y[-n_out:] *= np.linspace(1, 0, n_out)
    return y


# ------------------------------------------------------------------ guns

GUNS = {
    'pistol_9': 'Walther PPQ', 'pistol_45': '1911', 'revolver_357': 'Smith & Wesson 642', 'shotgun': 'Mossberg',
    'smg_9': 'Carl Gustav M45', 'rifle_556': 'AR-15', 'rifle_762': 'AK-47', 'rifle_308': 'Tikka',
}
GUN_DIST = {'pistol_9': 520, 'pistol_45': 520, 'revolver_357': 650, 'shotgun': 800, 'smg_9': 560, 'rifle_556': 950,
            'rifle_762': 950, 'rifle_308': 1150}


def onsets(x, min_gap=0.09):
    e = np.abs(x)
    k = int(SR * 0.002)
    e = np.convolve(e, np.ones(k) / k, mode='same')
    thr = 0.3 * e.max()
    out = []
    i = 0
    gap = int(SR * min_gap)
    while i < len(e):
        if e[i] > thr:
            out.append(i)
            i += gap
        else:
            i += 1
    return out


def cut_shots(x, n_want=4):
    on = onsets(x)
    shots = []
    for j, o in enumerate(on):
        nxt = on[j + 1] if j + 1 < len(on) else len(x)
        start = max(o - int(SR * 0.004), 0)
        isolated = (nxt - o) > SR * 0.7
        length = int(SR * 1.3) if isolated else max(nxt - o - int(SR * 0.004), int(SR * 0.06))
        seg = x[start:start + length]
        if not isolated:
            # Inside a burst: give the single shot its own decaying tail.
            tail_n = int(SR * 0.9)
            tail = lowpass_fast(noise(tail_n), 900) * env(tail_n, 0.002, 0.5) * np.abs(seg).max() * 0.25
            seg = np.concatenate([seg, np.zeros(tail_n)])
            seg[-tail_n - int(SR * 0.02):-int(SR * 0.02)] += tail[:tail_n]
        shots.append((0 if isolated else 1, seg))
    shots.sort(key=lambda s: s[0])
    return [fade(s[1], 0.5, 120.0) for s in shots[:n_want]]


def far_variant(x):
    y = lowpass_fast(x, 1400, passes=3) * 0.55
    d = int(SR * 0.13)
    echo = np.zeros(len(y) + d)
    echo[:len(y)] += y
    echo[d:] += lowpass_fast(y, 800) * 0.35
    tail_n = int(SR * 1.2)
    rv = lowpass_fast(noise(tail_n), 500) * env(tail_n, 0.01, 1.0) * np.abs(y).max() * 0.12
    out = np.concatenate([echo, np.zeros(tail_n // 2)])
    out[:min(len(out), tail_n)] += rv[:min(len(out), tail_n)]
    return fade(out, 1.0, 200.0)


def build_guns():
    folder = os.path.join(OUT, 'guns')
    for sid, src in GUNS.items():
        files = sorted(f for f in os.listdir(os.path.join(FIRE, src)) if f.endswith('.wav'))
        near_files, far_files = [], []
        k = 0
        for f in files:
            x = read_wav(os.path.join(FIRE, src, f))
            for s in cut_shots(x, 3):
                p = os.path.join(folder, f'{sid}_near_{k}.wav')
                write_wav(p, highpass_fast(s, 40))
                near_files.append(p)
                pf = os.path.join(folder, f'{sid}_far_{k}.wav')
                write_wav(pf, far_variant(s), peak=0.6)
                far_files.append(pf)
                k += 1
                if k >= 5:
                    break
            if k >= 5:
                break
        define('shot_' + sid, near_files, db=4.0, dist=GUN_DIST[sid], pitch=0.03, prio=8, unit=14.0, far='shot_' + sid + '_far', far_from=110.0)
        define('shot_' + sid + '_far', far_files, db=0.0, dist=GUN_DIST[sid], pitch=0.03, prio=7, unit=40.0)
        print('guns', sid, len(near_files))
    source_json(folder, {
        'source': 'The Free Firearm Sound Library (Prepared SFX Library), via OpenGameArt',
        'title': 'Single shots cut from the library recordings; distant variants derived from them',
        'url': 'https://opengameart.org/content/the-free-firearm-sound-library',
        'authors': ['Ben Jaszczak', 'Brian Nelson', 'Kevin Heras', 'Matthew Nanney'],
        'license': 'CC0-1.0', 'license_url': 'https://creativecommons.org/publicdomain/zero/1.0/', 'attribution_required': False,
        'kind': 'audio', 'modifications': 'Single shots cut, mixed to mono, resampled to 48 kHz, normalised; *_far files low-passed with a slap-back echo and synthetic tail; *_sup files: suppressed variants (high-passed, short envelope, synthetic gas puff and action click) (tools/build_audio.py)',
        'mapping': GUNS})


def suppressed_variant(x):
    """A suppressed shot: the supersonic crack and action noise stay, the muzzle blast's boom and long tail go."""
    y = highpass_fast(x, 350) * 0.55
    n = len(y)
    e = env(n, 0.0005, 0.09, sustain=0.0, curve=5.0)
    y = y * e
    # The "thwip" of gas leaving the can: short band-limited noise.
    k = int(SR * 0.05)
    puff = highpass_fast(lowpass_fast(noise(k), 2500), 500) * env(k, 0.001, 0.035) * np.abs(y).max() * 0.6
    y[:k] += puff
    # Mechanical action a few milliseconds later.
    c = int(SR * 0.012)
    m = int(SR * 0.004)
    click = highpass_fast(noise(m), 2000) * env(m, 0.0002, 0.003) * np.abs(y).max() * 0.5
    y[c:c + m] += click
    return fade(y[:int(SR * 0.45)], 0.3, 120.0)


def build_suppressed():
    """Suppressed variants of every gun's near shots (shot_<sid>_sup): about a third of the reach, no distant echo."""
    folder = os.path.join(OUT, 'guns')
    for sid in GUNS:
        files = []
        for k in range(5):
            src = os.path.join(folder, f'{sid}_near_{k}.wav')
            if not os.path.exists(src):
                break
            dst = os.path.join(folder, f'{sid}_sup_{k}.wav')
            write_wav(dst, suppressed_variant(read_wav(src)), peak=0.7)
            files.append(dst)
        if files:
            define('shot_' + sid + '_sup', files, db=-1.0, dist=round(GUN_DIST[sid] * 0.3), pitch=0.04, prio=7, unit=6.0)
            print('suppressed', sid, len(files))


# ------------------------------------------------------------------ copied libraries

def copy_group(sid, srcs, sub, **kw):
    out = []
    for s in srcs:
        if not os.path.exists(s):
            continue
        d = os.path.join(OUT, sub, os.path.basename(s))
        os.makedirs(os.path.dirname(d), exist_ok=True)
        shutil.copyfile(s, d)
        out.append(d)
    if out:
        define(sid, out, **kw)
    return out


def kenney(pack, name, count):
    """First `count` files of a Kenney sound family; packs name them name_000.ogg, name_1.ogg or name1.ogg."""
    base = os.path.join(KEN, pack, 'Audio')
    pat = re.compile(re.escape(name) + r'_?\d+\.ogg$')
    files = sorted(f for f in os.listdir(base) if pat.match(f))
    return [os.path.join(base, f) for f in files[:count]]


def build_copied():
    S = SLEEP
    fs = lambda kind: [f'{S}/footsteps/footstep_{kind}_{i:03d}.ogg' for i in range(5)]
    copy_group('step_wood', fs('wood'), 'sleep/footsteps', db=-2.0, dist=26.0, pitch=0.08, prio=4, unit=2.0)
    copy_group('step_concrete', fs('concrete'), 'sleep/footsteps', db=-3.0, dist=24.0, pitch=0.08, prio=4, unit=2.0)
    copy_group('step_dirt', fs('dirt'), 'sleep/footsteps', db=-4.0, dist=20.0, pitch=0.08, prio=4, unit=2.0)
    copy_group('step_metal', fs('metal'), 'sleep/footsteps', db=0.0, dist=30.0, pitch=0.08, prio=4, unit=2.5)
    copy_group('step_carpet', fs('carpet'), 'sleep/footsteps', db=-8.0, dist=12.0, pitch=0.08, prio=3, unit=1.5)
    copy_group('step_grass', fs('grass'), 'sleep/footsteps', db=-6.0, dist=16.0, pitch=0.08, prio=3, unit=1.5)
    copy_group('door_open', [f'{S}/nichols/door_open_{c}.ogg' for c in 'abcd'], 'sleep/doors', db=-2.0, dist=35.0, prio=5, unit=3.0)
    copy_group('door_close', [f'{S}/nichols/door_close_{c}.ogg' for c in 'ab'], 'sleep/doors', db=0.0, dist=45.0, prio=5, unit=3.0)
    copy_group('switch_click', [f'{S}/nichols/switch_click.ogg'], 'sleep/foley', db=-6.0, dist=10.0)
    copy_group('dry_fire', [f'{S}/sfx/gun_dry.ogg'], 'sleep/guns', db=-4.0, dist=10.0, prio=4)
    copy_group('mag_out', [f'{S}/sfx/gun_mag_out.ogg'], 'sleep/guns', db=-6.0, dist=14.0, prio=4)
    copy_group('mag_in', [f'{S}/sfx/gun_mag_in.ogg'], 'sleep/guns', db=-6.0, dist=14.0, prio=4)
    copy_group('pump_cycle', [f'{S}/sfx/gun_rack.ogg'], 'sleep/guns', db=-2.0, dist=22.0, prio=5)
    copy_group('bolt_cycle', [f'{S}/sfx/gun_rack.ogg'], 'sleep/guns', db=-4.0, dist=18.0, prio=5, pitch=0.1)
    copy_group('ricochet', [f'{S}/sfx/gun_ricochet.ogg'], 'sleep/impacts', db=0.0, dist=80.0, prio=6)
    copy_group('impact_wood', [f'{S}/sfx/hit_wood.ogg'] + kenney('impact-sounds', 'impactWood_light', 3), 'impacts', db=-2.0, dist=60.0, prio=5)
    copy_group('impact_concrete', [f'{S}/sfx/hit_stone.ogg'] + kenney('impact-sounds', 'impactMining', 3), 'impacts', db=-2.0, dist=60.0, prio=5)
    copy_group('impact_metal', [f'{S}/sfx/hit_metal.ogg'] + kenney('impact-sounds', 'impactMetal_light', 3), 'impacts', db=0.0, dist=70.0, prio=5)
    copy_group('impact_dirt', [f'{S}/sfx/hit_dirt.ogg'] + kenney('impact-sounds', 'impactSoft_medium', 2), 'impacts', db=-4.0, dist=40.0, prio=4)
    copy_group('impact_water', [f'{S}/sfx/hit_water.ogg'], 'impacts', db=-2.0, dist=50.0, prio=4)
    copy_group('impact_glass', [f'{S}/sfx/hit_glass.ogg'] + kenney('impact-sounds', 'impactGlass_light', 3), 'impacts', db=0.0, dist=60.0, prio=5)
    copy_group('impact_plastic', kenney('impact-sounds', 'impactPlank_medium', 3), 'impacts', db=-4.0, dist=35.0, prio=4)
    copy_group('impact_fabric', kenney('impact-sounds', 'impactSoft_heavy', 3), 'impacts', db=-6.0, dist=25.0, prio=3)
    copy_group('impact_flesh', kenney('impact-sounds', 'impactPunch_heavy', 3), 'impacts', db=-2.0, dist=35.0, prio=6)
    copy_group('impact_foliage', kenney('impact-sounds', 'impactSoft_medium', 3), 'impacts', db=-10.0, dist=20.0, prio=2)
    copy_group('impact_armor', kenney('impact-sounds', 'impactPlate_heavy', 3), 'impacts', db=2.0, dist=50.0, prio=6)
    copy_group('impact_soft', kenney('impact-sounds', 'impactSoft_heavy', 3), 'impacts', db=-6.0, dist=25.0, prio=3)
    copy_group('break_wood', kenney('impact-sounds', 'impactWood_heavy', 5), 'impacts', db=2.0, dist=60.0, prio=5)
    copy_group('break_plastic', kenney('impact-sounds', 'impactPlank_medium', 3), 'impacts', db=0.0, dist=45.0, prio=5)
    copy_group('break_metal', kenney('impact-sounds', 'impactMetal_heavy', 5), 'impacts', db=2.0, dist=70.0, prio=5)
    copy_group('scrape_heavy', [f'{S}/siege/scrape.ogg'], 'sleep/foley', db=2.0, dist=45.0, prio=5, unit=3.0)
    copy_group('scrape_light', [f'{S}/siege/scrape.ogg'], 'sleep/foley', db=-6.0, dist=25.0, prio=4, pitch=0.15)
    copy_group('door_kick', [f'{S}/siege/bang_{c}.ogg' for c in 'abcd'], 'sleep/foley', db=4.0, dist=110.0, prio=7, unit=6.0)
    copy_group('door_burst', [f'{S}/siege/bang_a.ogg', f'{S}/siege/rattle.ogg'], 'sleep/foley', db=6.0, dist=120.0, prio=7, unit=6.0)
    copy_group('door_locked', [f'{S}/siege/rattle.ogg'], 'sleep/foley', db=-2.0, dist=25.0, prio=5)
    copy_group('door_bump', kenney('impact-sounds', 'impactWood_medium', 3), 'impacts', db=-2.0, dist=30.0, prio=4)
    copy_group('door_unlock', [f'{S}/sfx/lock_turn.ogg'], 'sleep/foley', db=-6.0, dist=12.0, prio=4)
    copy_group('search_drawer', [f'{S}/sfx/drawer_open.ogg'], 'sleep/foley', db=-4.0, dist=16.0, prio=4)
    copy_group('search_box', kenney('rpg-audio', 'cloth', 4), 'kenney/rpg', db=-6.0, dist=12.0, prio=3)
    copy_group('search_cabinet', kenney('rpg-audio', 'doorOpen', 2), 'kenney/rpg', db=-6.0, dist=16.0, prio=4)
    copy_group('search_soft', kenney('rpg-audio', 'cloth', 4), 'kenney/rpg', db=-8.0, dist=10.0, prio=3)
    copy_group('pickup', [f'{S}/sfx/ammo_pickup.ogg'] + kenney('rpg-audio', 'handleSmallLeather', 2), 'kenney/rpg', db=-8.0, dist=10.0, prio=3)
    copy_group('grab', kenney('rpg-audio', 'cloth', 4), 'kenney/rpg', db=-8.0, dist=10.0, prio=3)
    copy_group('shutter_open', kenney('rpg-audio', 'creak', 3), 'kenney/rpg', db=-4.0, dist=20.0, prio=4)
    copy_group('smartab_tap', kenney('interface-sounds', 'tick', 3), 'kenney/ui', db=-14.0, dist=4.0, prio=2)
    copy_group('impact_metal_light', kenney('impact-sounds', 'impactTin_medium', 5), 'impacts', db=-4.0, dist=35.0, prio=4)
    # Prop impacts used by PhysicsProp: impact_<family>
    copy_group('impact_glass_prop', kenney('impact-sounds', 'impactGlass_medium', 5), 'impacts', db=0.0, dist=45.0, prio=5)
    # Night ambience (Commons recordings processed in Sleep)
    for n in ['cricket_field', 'cricket_gryllus', 'frog_chorus', 'frog_chorus_b', 'frog_kaloula', 'gecko_tokay', 'toad_bufo',
              'dog_bark_a', 'dog_bark_b', 'dog_bark_c', 'dog_bark_d', 'dog_bark_e', 'dog_pack', 'owl_tawny', 'nightjar']:
        copy_group('amb_' + n, [f'{S}/night/{n}.ogg'], 'sleep/night', db=-6.0, dist=200.0, prio=1, unit=20.0)
    for sub in ['sleep/footsteps', 'sleep/doors', 'sleep/foley', 'sleep/guns', 'sleep/impacts', 'sleep/night']:
        source_json(os.path.join(OUT, sub), {
            'source': "Owner's Sleep project (game/assets/audio)", 'title': f'{sub} sounds',
            'url': 'local: A:/3rd Harmonik/interior/game/assets/audio',
            'authors': ['Kenney (CC0) and Wikimedia Commons recordists credited in Sleep/game/licenses (NIGHT_SOUNDS.md, NICHOLS_SOUNDS.md, CANAL.md)', 'Aljay Leodones (synthesised and processed in Sleep)'],
            'license': 'Mixed: CC0 (Kenney footsteps), CC BY 4.0 (Gravity Sound doors, drawer), CC BY-SA 3.0/4.0 (night recordings), owner-made synthesis',
            'license_url': 'see docs/SOUND_CREDITS.md', 'attribution_required': True, 'kind': 'audio', 'modifications': 'Copied unchanged from Sleep'})
    for sub in ['impacts', 'kenney/rpg', 'kenney/ui']:
        source_json(os.path.join(OUT, sub), {'source': 'Kenney (kenney.nl) impact-sounds, rpg-audio and interface-sounds packs; some files from Sleep (see impacts list)',
            'title': f'{sub}', 'url': 'https://kenney.nl/assets', 'authors': ['Kenney', 'Aljay Leodones (Sleep synthesised hits)'],
            'license': 'CC0-1.0', 'license_url': 'https://creativecommons.org/publicdomain/zero/1.0/', 'attribution_required': False,
            'kind': 'audio', 'modifications': 'none'})


def build_glass():
    folder = os.path.join(OUT, 'commons')
    files = []
    for i, f in enumerate(sorted(os.listdir(os.path.join(CACHE, 'commons')))):
        p = os.path.join(CACHE, 'commons', f)
        wavs = [x for x in os.listdir(p) if x.endswith('.wav')] if os.path.isdir(p) else []
        for wv in wavs:
            x = read_wav(os.path.join(p, wv))
            e = np.abs(x)
            start = max(int(np.argmax(e > 0.1 * e.max())) - int(SR * 0.01), 0)
            seg = fade(x[start:start + int(SR * 2.2)], 1.0, 300.0)
            out = os.path.join(folder, f'glass_break_{i}.wav')
            write_wav(out, seg)
            files.append(out)
    define('glass_break', files, db=4.0, dist=90.0, prio=7, unit=5.0)
    define('break_glass', files, db=2.0, dist=70.0, prio=6, unit=4.0)
    define('impact_glass_bottle', files, db=-2.0, dist=60.0, prio=6, unit=3.0)
    source_json(folder, {'source': 'Wikimedia Commons', 'title': 'Glass breaking 1-4 (Gravity Sound)',
        'url': 'https://commons.wikimedia.org/wiki/File:Glass_breaking_(Gravity_Sound).wav', 'authors': ['Gravity Sound'],
        'license': 'CC BY 4.0', 'license_url': 'https://creativecommons.org/licenses/by/4.0/', 'attribution_required': True,
        'kind': 'audio', 'modifications': 'trimmed to the break, mono, 48 kHz, normalised'})


# ------------------------------------------------------------------ synthesis

def synth(name, x, peak=0.85):
    p = os.path.join(OUT, 'synth', name + '.wav')
    write_wav(p, x, peak)
    return p


def build_synth():
    n = lambda s: int(SR * s)
    t = lambda s: np.arange(n(s)) / SR
    # Radio: a keyed transceiver - short click, brief squelch burst, faint carrier.
    click = np.concatenate([np.zeros(n(0.002)), np.ones(n(0.0015)), -0.6 * np.ones(n(0.001)), np.zeros(n(0.01))])
    sq = highpass_fast(lowpass_fast(noise(n(0.12)), 3500), 400) * env(n(0.12), 0.003, 0.09) * 0.35
    on = np.concatenate([click, sq])
    define('radio_on', [synth('radio_on', on)], db=-8.0, dist=float(json.load(open(os.path.join(GAME, 'data', 'rules.json')))['radio']['cue_radius']), prio=6, unit=1.2)
    off = np.concatenate([np.zeros(n(0.005)), 0.7 * np.ones(n(0.001)), np.zeros(n(0.004)), highpass_fast(noise(n(0.05)), 900) * env(n(0.05), 0.001, 0.04) * 0.3])
    define('radio_off', [synth('radio_off', off)], db=-9.0, dist=14.0, prio=6, unit=1.2)
    st = highpass_fast(lowpass_fast(noise(n(2.0)), 2600), 500)
    st *= 0.25 + 0.1 * np.sin(2 * np.pi * 0.7 * t(2.0))
    st = fade(st, 30, 30)
    define('radio_static', [synth('radio_static', st, 0.4)], db=-16.0, dist=10.0, prio=5, unit=1.0, loop=True)
    # SmarTab handling: strap rustle and a soft two-note wake chime / sleep tone.
    rust = lowpass_fast(noise(n(0.22)), 2500) * env(n(0.22), 0.04, 0.15) * 0.4
    chime = np.sin(2 * np.pi * 1320 * t(0.12)) * env(n(0.12), 0.005, 0.08) * 0.25
    up = rust.copy()
    up[n(0.08):n(0.08) + len(chime)] += chime
    define('smartab_up', [synth('smartab_up', up)], db=-10.0, dist=5.0, prio=2)
    down = rust[::-1].copy() * 0.8
    define('smartab_down', [synth('smartab_down', down)], db=-12.0, dist=5.0, prio=2)
    # Flashlight tail-cap click; battery out (cap unscrew + cells sliding) and in (cells, cap tightening, click).
    fc = np.concatenate([np.zeros(n(0.001)), np.sin(2 * np.pi * 3200 * t(0.012)) * env(n(0.012), 0.0003, 0.01), np.zeros(n(0.02))])
    fc += highpass_fast(noise(len(fc)), 2000) * env(len(fc), 0.0002, 0.008) * 0.6
    define('flashlight_click', [synth('flashlight_click', fc)], db=-6.0, dist=9.0, prio=4, unit=1.0)
    fizz = np.concatenate([fc, highpass_fast(noise(n(0.25)), 3000) * env(n(0.25), 0.01, 0.2) * 0.15])
    define('flashlight_die', [synth('flashlight_die', fizz)], db=-8.0, dist=6.0, prio=4)
    cells = []
    for k in range(3):
        cells.append(np.zeros(n(0.05 + 0.03 * k)))
        cells.append(highpass_fast(noise(n(0.03)), 1500) * env(n(0.03), 0.001, 0.02) * 0.5)
    bout = np.concatenate([lowpass_fast(noise(n(0.25)), 3000) * env(n(0.25), 0.02, 0.2) * 0.3] + cells)
    define('battery_out', [synth('battery_out', bout)], db=-6.0, dist=8.0, prio=4)
    bin_ = np.concatenate(cells + [lowpass_fast(noise(n(0.3)), 3000) * env(n(0.3), 0.02, 0.25) * 0.3, fc])
    define('battery_in', [synth('battery_in', bin_)], db=-6.0, dist=8.0, prio=4)
    # Supersonic crack (N-wave) and subsonic whiz.
    nw = np.concatenate([np.linspace(0, 1, n(0.0002)), np.linspace(1, -1, n(0.0008)), np.linspace(-1, 0, n(0.0002)), np.zeros(n(0.05))])
    crack = nw + highpass_fast(noise(len(nw)), 3000) * env(len(nw), 0.0005, 0.02) * 0.3
    define('flyby_crack', [synth('flyby_crack', crack)], db=2.0, dist=8.0, prio=7, unit=3.0)
    sweep = highpass_fast(lowpass_fast(noise(n(0.35)), 2500), 300) * env(n(0.35), 0.12, 0.2) * np.linspace(1.0, 0.4, n(0.35))
    define('flyby_whiz', [synth('flyby_whiz', sweep)], db=-2.0, dist=8.0, prio=7, unit=3.0)
    # The haze warning: two low notes from the SmarTab, restrained.
    def tone(f, d, a=0.3):
        return np.sin(2 * np.pi * f * t(d)) * env(n(d), 0.01, d * 0.8) * a + np.sin(2 * np.pi * f * 2 * t(d)) * env(n(d), 0.01, d * 0.5) * a * 0.2
    define('zone_warning', [synth('zone_warning', np.concatenate([tone(392, 0.35), tone(311, 0.6)]))], db=-10.0, dist=5.0, prio=3)
    define('zone_move', [synth('zone_move', np.concatenate([tone(262, 0.5), tone(196, 0.9)]))], db=-8.0, dist=5.0, prio=3)
    # Water steps and splashes.
    def splash(d, cut):
        return lowpass_fast(noise(n(d)), cut) * env(n(d), 0.005, d * 0.6)
    define('step_water', [synth(f'step_water_{i}', splash(0.25 + 0.05 * i, 1800 + 300 * i)) for i in range(4)], db=-2.0, dist=24.0, prio=4, unit=2.0)
    # Parachute: canopy opening crack and flutter; collapse; jump wind.
    flap = lowpass_fast(noise(n(1.2)), 1200) * (env(n(1.2), 0.01, 0.6) * (0.6 + 0.4 * np.sin(2 * np.pi * 14 * t(1.2))))
    define('chute_open', [synth('chute_open', flap)], db=4.0, dist=140.0, prio=5, unit=8.0)
    define('chute_collapse', [synth('chute_collapse', lowpass_fast(noise(n(0.8)), 900) * env(n(0.8), 0.02, 0.5))], db=0.0, dist=40.0, prio=4)
    define('jump_wind', [synth('jump_wind', lowpass_fast(noise(n(2.0)), 700) * env(n(2.0), 0.3, 1.5))], db=-2.0, dist=60.0, prio=3)
    # Landings and drops.
    def thud(d, f):
        return (np.sin(2 * np.pi * f * t(d) * np.exp(-t(d) * 6)) * env(n(d), 0.002, d * 0.5) + lowpass_fast(noise(n(d)), 600) * env(n(d), 0.001, 0.05) * 0.5)
    define('land_soft', [synth('land_soft', thud(0.25, 90))], db=-4.0, dist=22.0, prio=4)
    define('land_hard', [synth('land_hard', thud(0.4, 70))], db=2.0, dist=40.0, prio=5)
    define('throw', [synth('throw', highpass_fast(noise(n(0.25)), 500) * env(n(0.25), 0.06, 0.12) * 0.4)], db=-8.0, dist=10.0, prio=3)
    # Treatment: tearing a bandage, opening a kit.
    rip = highpass_fast(noise(n(0.6)), 1200) * (0.5 + 0.5 * (RNG.random(n(0.6)) > 0.7)) * env(n(0.6), 0.02, 0.5, 0.3)
    define('treat_bandage', [synth('treat_bandage', rip)], db=-6.0, dist=12.0, prio=4)
    zipper = highpass_fast(noise(n(0.5)), 2500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 60 * t(0.5)))) * env(n(0.5), 0.02, 0.45, 0.4) * 0.6
    define('treat_kit', [synth('treat_kit', zipper)], db=-6.0, dist=12.0, prio=4)
    define('revive_start', [synth('revive_start', rust)], db=-6.0, dist=12.0, prio=4)
    define('revive_done', [synth('revive_done', thud(0.3, 110))], db=-6.0, dist=14.0, prio=4)
    # Injured: a ragged exhale.
    breath = lowpass_fast(noise(n(0.9)), 1100) * env(n(0.9), 0.15, 0.6) * (0.6 + 0.4 * np.sin(2 * np.pi * 3 * t(0.9)))
    define('downed', [synth('downed', breath)], db=-2.0, dist=25.0, prio=6)
    define('armor_break', [synth('armor_break', thud(0.3, 300) + highpass_fast(noise(n(0.3)), 2000) * env(n(0.3), 0.001, 0.1) * 0.4)], db=2.0, dist=40.0, prio=6)
    # Transport aircraft overhead: four turboprops - a low drone with slowly beating harmonics and a broad rush.
    # Every partial completes whole cycles in 6 s and the noise is crossfaded tail-into-head, so the file loops cleanly.
    T = 6.0
    tt = t(T)
    drone = np.zeros(n(T))
    for f, a, ph in [(57.0, 0.5, 0.0), (58.5, 0.45, 1.0), (114.0, 0.3, 2.0), (171.0, 0.18, 0.5), (228.0, 0.12, 1.4), (342.0, 0.06, 0.3), (91.5, 0.1, 0.8)]:
        drone += np.sin(2 * np.pi * f * tt + ph) * a
    drone *= 0.85 + 0.15 * np.sin(2 * np.pi * 0.5 * tt)
    xf = n(0.5)
    raw = lowpass_fast(noise(n(T) + xf), 700)
    rush = raw[:n(T)].copy()
    w = np.linspace(0, 1, xf)
    rush[:xf] = rush[:xf] * w + raw[n(T):] * (1 - w)
    define('plane_engine', [synth('plane_engine', drone + rush * 0.6)], db=2.0, dist=1500.0, prio=8, unit=90.0, pitch=0.0, loop=True)
    source_json(os.path.join(OUT, 'synth'), {'source': 'Synthesised for this project by tools/build_audio.py', 'title': 'Procedural sound effects',
        'url': 'local', 'authors': ['Aetherion Project'], 'license': 'Project-original', 'attribution_required': False,
        'kind': 'audio', 'modifications': 'n/a'})


def main():
    if '--suppressed' in sys.argv:
        # Only the suppressed shots, merged into the existing sounds.json.
        build_suppressed()
        path = os.path.join(GAME, 'data', 'sounds.json')
        data = json.load(open(path, encoding='utf-8'))
        data['sounds'].update(SOUNDS)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=1)
        print('sounds:', len(data['sounds']))
        return
    build_guns()
    build_suppressed()
    build_copied()
    build_glass()
    build_synth()
    with open(os.path.join(GAME, 'data', 'sounds.json'), 'w', encoding='utf-8') as f:
        json.dump({'_doc': 'Generated by tools/build_audio.py. dist = audible radius (m), unit = distance with no attenuation, db = base gain, prio = voice-stealing priority, far = distant variant id used beyond far_from metres.',
                   'sounds': SOUNDS}, f, indent=1)
    print('sounds:', len(SOUNDS))


if __name__ == '__main__':
    main()
