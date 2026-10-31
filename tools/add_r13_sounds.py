"""Adds the sounds in audio/ (the user's set of 2026-10-29) to the game.

    python -I tools/add_r13_sounds.py          (then bash tools/import.sh)

Each audio/<name>.mp3 is decoded with ffmpeg (imageio-ffmpeg), trimmed of the silence after it, peak-normalised by
kind and written to game/assets/audio/r13/<name>.ogg. Then these ids are merged into game/data/sounds.json (run it
again after tools/build_audio.py or tools/add_work_sounds.py, which rewrite that file):
- radio voice lines (vox_<line>_<n>): affirmative, negative, enemy_spotted, in_position, man_down, need_help,
  radio_basic_kill, radio_headshot_kill, follow_me; bots and players say them on the team radio (data/bot_radio.json
  "recorded", rewritten here from the files present);
- radio_static: the static of a transmitting radio, heard by enemies near it (World.server_radio_static); levelled by
  loudness, not peak. The synth hiss loop it replaces keeps its own id, radio_hiss;
- gunshots: kar98 and m24 replace their guns' near shots; awp (the new AWP) and sumpak get their own;
- grenade_explosion joins the near explosion; player_death replaces the death cry;
- bullet impacts join their sets: hit_cement (concrete), hit_metal, hit_wood, body_hit (flesh), headshot_hit (head);
- footsteps join their sets by surface: footstep_on_cement (concrete), footstep_on_dirt, footstep_on_metal_ and the
  grating (metal); any footstep_on_<surface> or hit_<surface> added later goes to its surface's set.
"""
import json, os, subprocess
import numpy as np
import imageio_ffmpeg

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'audio')
GAME = os.path.join(ROOT, 'game')
DST = os.path.join(GAME, 'assets', 'audio', 'r13')
SOUNDS = os.path.join(GAME, 'data', 'sounds.json')
LINES_JSON = os.path.join(GAME, 'data', 'bot_radio.json')
FF = imageio_ffmpeg.get_ffmpeg_exe()
RATE = 44100

VOICE = ['affirmative', 'negative', 'enemy_spotted', 'in_position', 'man_down', 'need_help', 'radio_basic_kill',
         'radio_headshot_kill', 'follow_me']
# recording -> the radio line it says (data/bot_radio.json lines; tools/make_bot_radio.py RECORDED)
VOICE_LINE = {'enemy_spotted': 'contact', 'radio_basic_kill': 'kill', 'radio_headshot_kill': 'headshot_kill', 'man_down': 'down'}
# recording -> the words shown on screen when it plays (one caption for all of a line's recordings)
VOICE_TEXT = {'affirmative': 'Affirmative.', 'negative': 'Negative.', 'enemy_spotted': 'Enemy spotted!', 'in_position': 'In position.',
              'man_down': 'Man down!', 'need_help': 'Need help!', 'radio_basic_kill': 'Enemy down!', 'radio_headshot_kill': 'Headshot!',
              'follow_me': 'Follow me!'}
# surface word in a file name -> the game's surface (step_<surface>, impact_<surface>)
SURFACE = {'cement': 'concrete', 'concrete': 'concrete', 'metal': 'metal', 'dirt': 'dirt', 'wood': 'wood', 'grass': 'grass',
           'carpet': 'carpet', 'water': 'water', 'glass': 'glass', 'plastic': 'plastic', 'fabric': 'fabric'}
# name prefix -> peak target (dBFS)
PEAK = {'footstep': -4.0, 'player_death': -1.5, 'hit_': -1.5, 'body_hit': -1.5, 'headshot_hit': -1.0}
# name (without its number) -> loudness target (dBFS RMS) for steady sounds whose peaks say little; peaks stay under -1
RMS = {'radio_static': -20.0}


def load(path):
    out = subprocess.run([FF, '-v', 'quiet', '-i', path, '-ac', '1', '-ar', str(RATE), '-f', 's16le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.int16).astype(np.float32) / 32768.0


def save_ogg(x, path):
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype(np.int16).tobytes()
    subprocess.run([FF, '-v', 'quiet', '-y', '-f', 's16le', '-ar', str(RATE), '-ac', '1', '-i', '-', '-c:a', 'libvorbis',
                    '-q:a', '6', path], input=pcm, check=True)


def trim(x):
    # Cut the silence after the sound (and before it, beyond 10 ms), leaving a short natural tail.
    win = RATE // 50
    n = len(x) // win
    if n == 0:
        return x
    env = np.sqrt((x[:n * win].reshape(n, win) ** 2).mean(1))
    db = 20 * np.log10(env / (env.max() + 1e-9) + 1e-9)
    on = np.where(db > -45)[0]
    if len(on) == 0:
        return x
    a = max(on[0] * win - RATE // 100, 0)
    b = min((on[-1] + 1) * win + RATE // 8, len(x))
    y = x[a:b].copy()
    fade = min(RATE // 50, len(y))
    y[-fade:] *= np.linspace(1.0, 0.0, fade)
    return y


def peak_for(name):
    if any(name.startswith(v) for v in VOICE):
        return -1.0
    for k, v in PEAK.items():
        if name.startswith(k):
            return v
    return -1.0


def convert():
    os.makedirs(DST, exist_ok=True)
    made = {}
    for f in sorted(os.listdir(SRC)):
        if not f.lower().endswith('.mp3'):
            continue
        name = os.path.splitext(f)[0]
        x = trim(load(os.path.join(SRC, f)))
        p = np.abs(x).max()
        base = name.rstrip('0123456789').rstrip('_')
        if base in RMS and p > 0:
            x = x * (10 ** (RMS[base] / 20.0) / (np.sqrt((x ** 2).mean()) + 1e-9))
            p = np.abs(x).max()
            if p > 10 ** (-1.0 / 20.0):
                x = x * (10 ** (-1.0 / 20.0) / p)
        elif p > 0:
            x = x * (10 ** (peak_for(name) / 20.0) / p)
        save_ogg(x, os.path.join(DST, name + '.ogg'))
        made[name] = len(x) / RATE
    return made


def r(name):
    return 'assets/audio/r13/%s.ogg' % name


def group(made, prefix):
    return [r(n) for n in sorted(made) if n.rstrip('0123456789').rstrip('_') == prefix.rstrip('_')]


def merge(made):
    raw = open(SOUNDS, 'rb').read()
    doc = json.loads(raw.decode('utf-8'))
    s = doc['sounds']
    # Radio voice lines.
    for line in VOICE:
        files = group(made, line)
        for i, fp in enumerate(files):
            s['vox_%s_%d' % (line, i)] = {'files': [fp], 'db': 0.0, 'dist': 14.0, 'pitch': 0.0, 'prio': 7, 'unit': 2.5}
    # Gunshots.
    s['shot_kar98']['files'] = [r('kar98_gunshot')]
    s['shot_m24']['files'] = [r('m24_gunshot'), r('m24_gunshot2')]
    awp = dict(s['shot_m24'])
    awp['files'] = [r('awp_gunshot')]
    awp['db'] = float(s['shot_m24'].get('db', 4.0)) + 1.0
    s['shot_awp'] = awp
    if 'shot_m24_sup' in s:
        s['shot_awp_sup'] = dict(s['shot_m24_sup'])
    sump = dict(s['shot_shotgun'])
    sump['files'] = [r('sumpak')]
    s['shot_sumpak'] = sump
    if 'shot_shotgun_sup' in s:
        s['shot_sumpak_sup'] = dict(s['shot_shotgun_sup'])
    # Radio static: one burst per transmitting radio (World.server_radio_static), heard by enemies close to it.
    if s.get('radio_static', {}).get('loop') and 'radio_hiss' not in s:
        s['radio_hiss'] = s['radio_static']
    s['radio_static'] = {'files': group(made, 'radio_static'), 'db': -3.0, 'dist': 15.0, 'pitch': 0.04, 'prio': 6, 'unit': 1.6}
    # Explosion and death.
    keep = [x for x in s['explosion']['files'] if not x.startswith('assets/audio/r13/')]
    s['explosion']['files'] = keep + [r('grenade_explosion1')]
    s['death']['files'] = group(made, 'player_death')
    # Impacts and footsteps join their sets, by the surface in the name (hit_<surface>, footstep_on_<surface>).
    add = {}
    for n in sorted(made):
        if n.startswith('footstep_on_'):
            surf = n[len('footstep_on_'):].rstrip('0123456789').rstrip('_')
            sid = 'step_' + SURFACE.get(surf.split('_')[0], surf.split('_')[0])
        elif n.startswith('hit_'):
            surf = n[len('hit_'):].rstrip('0123456789').rstrip('_')
            sid = 'impact_' + SURFACE.get(surf, surf)
        elif n.startswith('body_hit'):
            sid = 'impact_flesh'
        elif n.startswith('headshot_hit'):
            for sid2 in ('impact_flesh_head', 'headshot'):
                add.setdefault(sid2, []).append(r(n))
            continue
        else:
            continue
        add.setdefault(sid, []).append(r(n))
    for sid, files in add.items():
        if sid not in s:
            print('  no sound set %s for %s: skipped' % (sid, files))
            continue
        keep = [x for x in s[sid]['files'] if not x.startswith('assets/audio/r13/')]
        s[sid]['files'] = keep + files
        print('  %-18s +%d' % (sid, len(files)))
    out = json.dumps(doc, indent=1, ensure_ascii=False).encode('utf-8')
    if b'\r\n' in raw:
        out = out.replace(b'\n', b'\r\n')
    open(SOUNDS, 'wb').write(out)
    # The radio lines that play a recording instead of the text-to-speech voices.
    lines = json.loads(open(LINES_JSON, 'rb').read().decode('utf-8'))
    rec = {}
    for name in VOICE:
        n = len(group(made, name))
        if n > 0:
            rec[VOICE_LINE.get(name, name)] = {'name': name, 'n': n, 'text': VOICE_TEXT.get(name, name.replace('_', ' ').capitalize() + '.')}
    lines['recorded'] = rec
    with open(LINES_JSON, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(lines, f, indent=1, ensure_ascii=False)


if __name__ == '__main__':
    made = convert()
    merge(made)
    print('converted %d sounds into %s; sounds.json updated' % (len(made), DST))
    for line in VOICE:
        print('  vox %-22s %d' % (line, len(group(made, line))))
