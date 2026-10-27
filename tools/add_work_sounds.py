"""Adds the sounds in work/sounds to the game and sets the door and radio sounds asked for on 2026-10-27.

    python -I tools/add_work_sounds.py          (then bash tools/import.sh)

Copies every work/sounds/<group>/<name>.mp3 to game/assets/audio/work/<group>/ and merges these ids into
game/data/sounds.json (run it again after tools/build_audio.py, which rewrites that file):
- one gunshot per gun model (shot_<sound>), with the distant and suppressed variants of its calibre family;
- reload sequences per weapon class, the magazine seating click, the attachment click;
- bullet impacts (dirt, metal, walls, wood) added to the existing impact sets;
- player hit, headshot and death sounds; menu select / back; grenade explosions (near and far);
- radio_click for team pings; door open and close at 60 % of their former level (-4.4 dB).
"""
import json, os, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'work', 'sounds')
GAME = os.path.join(ROOT, 'game')
DST = os.path.join(GAME, 'assets', 'audio', 'work')
SOUNDS = os.path.join(GAME, 'data', 'sounds.json')


def f(group, name):
    return 'assets/audio/work/%s/%s.mp3' % (group, name)


# gun sound id -> (files, calibre family whose distant / suppressed sounds it uses)
SHOTS = {
    'scar': (['rifle_shoot'], 'rifle_556'), 'm416': (['rifle_shoot2'], 'rifle_556'),
    'm249': (['rifle_shoot', 'rifle_shoot2'], 'rifle_556'), 'mini14': (['sniper_shoot4'], 'rifle_556'),
    'm762': (['ak47_shoot'], 'rifle_762'), 'sks': (['sniper_shoot3'], 'rifle_762'),
    'kar98': (['sniper_shoot1'], 'rifle_308'), 'm24': (['sniper_shoot2'], 'rifle_308'), 'slr': (['sniper_shoot5'], 'rifle_308'),
    'ump45': (['smg_shoot1'], 'smg_9'), 'vector': (['smg_shoot1'], 'smg_9'), 'tommy': (['smg_shoot1'], 'smg_9'),
    'saiga': (['shotgun_shoot1'], 'shotgun'), 's686': (['shotgun_shoot2'], 'shotgun'),
    'deagle': (['desert_eagle_shoot'], 'revolver_357'), 'p92': (['pistol_shoot1'], 'pistol_9'),
    'p1911': (['pistol_shoot2'], 'pistol_45'),
}
DOOR_SCALE_DB = -4.437  # 20 * log10(0.6)


def main():
    for group in os.listdir(SRC):
        os.makedirs(os.path.join(DST, group), exist_ok=True)
        for name in os.listdir(os.path.join(SRC, group)):
            if name.endswith('.mp3'):
                shutil.copyfile(os.path.join(SRC, group, name), os.path.join(DST, group, name))
    raw = open(SOUNDS, 'rb').read()
    crlf = b'\r\n' in raw
    doc = json.loads(raw.decode('utf-8'))
    s = doc['sounds']
    for sid, (files, fam) in SHOTS.items():
        near = dict(s['shot_' + fam])
        near['files'] = [f('guns', n) for n in files]
        s['shot_' + sid] = near
        if 'shot_%s_sup' % fam in s:
            s['shot_%s_sup' % sid] = dict(s['shot_%s_sup' % fam])
    for cls in ['pistol', 'rifle', 'smg', 'sniper']:
        s['reload_' + cls] = {'files': [f('guns', 'reload_' + cls)], 'db': -3.0, 'dist': 18.0, 'pitch': 0.03, 'prio': 4, 'unit': 4.0}
    s['reload_finish'] = {'files': [f('guns', 'reload_finish')], 'db': -4.0, 'dist': 16.0, 'pitch': 0.04, 'prio': 4, 'unit': 4.0}
    s['attach'] = {'files': [f('guns', 'attachment1')], 'db': -6.0, 'dist': 8.0, 'pitch': 0.05, 'prio': 3, 'unit': 3.0}
    for sid, names in {'impact_dirt': ['dirt_hit1', 'dirt_hit2'], 'impact_metal': ['metal_hit1', 'metal_hit2', 'metal_hit3'],
                       'impact_concrete': ['wall_hit1', 'wall_hit2', 'wall_hit3', 'wall_hit4'], 'impact_wood': ['wood_hit1', 'wood_hit2']}.items():
        keep = [x for x in s[sid]['files'] if not x.startswith('assets/audio/work/')]
        s[sid]['files'] = keep + [f('guns', n) for n in names]
    s['player_hit'] = {'files': [f('player', 'hit%d' % i) for i in (1, 2, 3)], 'db': 0.0, 'dist': 30.0, 'pitch': 0.06, 'prio': 6, 'unit': 4.0}
    s['headshot'] = {'files': [f('player', 'headshot%d' % i) for i in (1, 2)], 'db': 2.0, 'dist': 40.0, 'pitch': 0.04, 'prio': 7, 'unit': 4.0}
    s['death'] = {'files': [f('player', 'death%d' % i) for i in (1, 2, 3, 4)], 'db': 0.0, 'dist': 40.0, 'pitch': 0.05, 'prio': 6, 'unit': 4.0}
    s['ui_select'] = {'files': [f('buttons', 'select_okay')], 'db': -8.0, 'dist': 5.0, 'pitch': 0.0, 'prio': 2, 'unit': 4.0}
    s['ui_back'] = {'files': [f('buttons', 'select_cancel')], 'db': -8.0, 'dist': 5.0, 'pitch': 0.0, 'prio': 2, 'unit': 4.0}
    s['explosion'] = {'files': [f('guns', 'grenade1'), f('guns', 'grenade2')], 'db': 8.0, 'dist': 650.0, 'pitch': 0.05, 'prio': 9,
                      'unit': 18.0, 'far': 'explosion_far', 'far_from': 90.0}
    s['explosion_far'] = {'files': [f('guns', 'bomb_explosion'), f('guns', 'bomb_explosion2')], 'db': 4.0, 'dist': 650.0, 'pitch': 0.05,
                          'prio': 8, 'unit': 60.0}
    s['grenade_pin'] = {'files': ['assets/audio/sleep/foley/switch_click.ogg'], 'db': -4.0, 'dist': 10.0, 'pitch': 0.1, 'prio': 4, 'unit': 3.0}
    # Team ping: the radio's own squelch click, heard by anyone close by (enemies too).
    s['radio_click'] = {'files': ['assets/audio/synth/radio_on.wav'], 'db': -2.0, 'dist': 18.0, 'pitch': 0.04, 'prio': 6, 'unit': 2.0}
    # Doors at 60 % of their old level (only once: the old level is recorded).
    for sid in ('door_open', 'door_close'):
        base = float(s[sid].get('db_full', s[sid]['db']))
        s[sid]['db_full'] = base
        s[sid]['db'] = round(base + DOOR_SCALE_DB, 2)
    doc['_doc'] = doc['_doc'].split(' work/sounds:')[0] + ' work/sounds: merged by tools/add_work_sounds.py (rerun it after build_audio.py).'
    out = json.dumps(doc, indent=1, ensure_ascii=False) + '\n'
    if crlf:
        out = out.replace('\n', '\r\n')
    open(SOUNDS, 'wb').write(out.encode('utf-8'))
    print('sounds.json: %d ids; copied work/sounds to %s' % (len(s), os.path.relpath(DST, ROOT)))


if __name__ == '__main__':
    main()
