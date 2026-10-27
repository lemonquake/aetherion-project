"""Weapon variety (user, 2026-10-27): twelve more guns sharing calibres like PUBG (SCAR-L, AR-15 and M416 all take
5.56, ammunition coloured the same per calibre), hard recoil kept, a .50 AE pistol, frag grenades.

Idempotent: sets entries by id in weapons.json, items.json and ballistics.json.
"""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, 'game', 'data')


def load(name):
    raw = open(os.path.join(DATA, name), 'rb').read()
    return json.loads(raw.decode('utf-8')), b'\r\n' in raw


def save(name, d, crlf):
    out = json.dumps(d, indent=1, ensure_ascii=False) + '\n'
    if crlf:
        out = out.replace('\n', '\r\n')
    open(os.path.join(DATA, name), 'wb').write(out.encode('utf-8'))


W, wcrlf = load('weapons.json')
guns = W['weapons']
RIFLE_ATT = list(guns['rifle_556']['attachments'])
SMG_ATT = list(guns['smg_9']['attachments'])
DMR_ATT = list(guns['marksman_308']['attachments'])
BOLT_ATT = [a for a in guns['bolt_308']['attachments']]


def gun(base, **kw):
    g = json.loads(json.dumps(guns[base]))
    for k in ('hold', 'mounts'):
        g.pop(k, None)
    rec = kw.pop('recoil', {})
    g.update(kw)
    g['recoil'] = dict(g['recoil'], **rec)
    return g


# Familiar names for the guns already in the game (ids unchanged: saves, loot and bots keep working).
NAMES = {'pistol_9': 'P92', 'pistol_45': 'P1911', 'revolver_357': 'R1895 Revolver', 'shotgun_pump': 'S1897 Pump',
         'smg_9': 'MP5K', 'machine_pistol': 'Micro UZI', 'rifle_556': 'AR-15', 'rifle_762': 'AKM', 'bolt_308': 'M24',
         'shotgun_double': 'S686', 'sumpak': 'Sumpak', 'marksman_308': 'SLR'}
for k, n in NAMES.items():
    guns[k]['name'] = n
# Sounds from work/sounds (tools/add_work_sounds.py) for the existing guns that get one.
guns['pistol_9']['sound'] = 'p92'
guns['pistol_45']['sound'] = 'p1911'
guns['shotgun_double']['sound'] = 's686'
guns['bolt_308']['sound'] = 'm24'
guns['marksman_308']['sound'] = 'slr'

guns['rifle_scar'] = gun('rifle_556', name='SCAR-L', model='rifle_scar', sound='scar', rpm=625, muzzle_velocity=870, mass=3.6,
    reload_time=2.6, reload_empty_time=3.2, value=7.2,
    recoil={'kick_up': 1.45, 'kick_side': 0.5, 'climb': 0.16, 'recovery': 12, 'max_climb': 9, 'pattern': [0.2, -0.4, 0.5, 0.1, -0.6, 0.4, 0.7, -0.2]})
guns['rifle_m416'] = gun('rifle_556', name='M416', model='rifle_m416', sound='m416', rpm=700, muzzle_velocity=880, mass=3.5,
    reload_time=2.4, reload_empty_time=3.0, value=7.6, attachments=RIFLE_ATT + ['stock_tactical'],
    recoil={'kick_up': 1.35, 'kick_side': 0.45, 'climb': 0.14, 'recovery': 13, 'max_climb': 9, 'pattern': [0.3, -0.3, 0.4, -0.1, 0.6, -0.5, 0.2, 0.5]})
guns['lmg_m249'] = gun('rifle_556', name='M249', **{'class': 'lmg'}, model='lmg_m249', sound='m249', mag_size=100, fire_modes=['auto'],
    rpm=800, muzzle_velocity=915, mass=7.5, draw_time=1.2, ads_time=0.45, reload_time=7.0, reload_empty_time=8.0,
    spread_hip=3.2, spread_ads=0.12, move_spread=2.6, value=7.5,
    attachments=['sight_reddot', 'sight_holo', 'scope_2x', 'scope_3x', 'scope_4x', 'scope_6x', 'weapon_light', 'laser_sight'],
    recoil={'kick_up': 1.25, 'kick_side': 0.7, 'climb': 0.1, 'recovery': 9, 'max_climb': 10, 'pattern': [0.5, -0.4, 0.6, -0.7, 0.3, 0.8, -0.5, 0.2]})
guns['lmg_m249'].pop('mag_ext', None)
guns['dmr_mini14'] = gun('marksman_308', name='Mini 14', model='dmr_mini14', sound='mini14', ammo='556', mag_size=20, mag_ext=30,
    rpm=400, muzzle_velocity=990, mass=3.0, spread_ads=0.03, value=6.4,
    recoil={'kick_up': 2.4, 'kick_side': 0.5, 'climb': 0.05, 'recovery': 12, 'max_climb': 8, 'pattern': [0.3, -0.4, 0.2]})
guns['rifle_m762'] = gun('rifle_762', name='Beryl M762', model='rifle_m762', sound='m762', rpm=700, muzzle_velocity=715, mass=3.9,
    attachments=RIFLE_ATT, value=7.4,
    recoil={'kick_up': 2.3, 'kick_side': 1.05, 'climb': 0.24, 'recovery': 9, 'max_climb': 12, 'pattern': [-0.6, 0.7, -0.9, 0.9, -0.4, 1.1, -0.8]})
guns['dmr_sks'] = gun('marksman_308', name='SKS', model='dmr_sks', sound='sks', ammo='762x39', mag_size=10, mag_ext=20,
    rpm=350, muzzle_velocity=735, mass=3.9, spread_ads=0.035, value=6.4,
    recoil={'kick_up': 3.2, 'kick_side': 0.8, 'climb': 0.08, 'recovery': 10, 'max_climb': 9, 'pattern': [-0.5, 0.6, -0.2]})
guns['bolt_kar98'] = gun('bolt_308', name='Kar98k', model='bolt_kar98', sound='kar98', cycle_time=1.1, muzzle_velocity=760, mass=4.1,
    attachments=[a for a in BOLT_ATT if a != 'mag_ext_sniper'], value=6.2,
    recoil={'kick_up': 6.0, 'kick_side': 1.0, 'recovery': 9, 'max_climb': 10})
guns['bolt_kar98'].pop('mag_ext', None)
guns['smg_ump45'] = gun('smg_9', name='UMP45', model='smg_ump45', sound='ump45', ammo='45acp', mag_size=25, mag_ext=35,
    rpm=650, muzzle_velocity=280, mass=2.5, value=5.2,
    recoil={'kick_up': 1.05, 'kick_side': 0.5, 'climb': 0.1, 'recovery': 14, 'max_climb': 7, 'pattern': [0.3, -0.2, 0.5, -0.4, 0.2, 0.6, -0.3]})
guns['smg_vector'] = gun('smg_9', name='Vector', model='smg_vector', sound='vector', mag_size=19, mag_ext=33,
    rpm=1100, muzzle_velocity=380, mass=2.7, value=5.3, attachments=SMG_ATT + ['stock_tactical'],
    recoil={'kick_up': 0.85, 'kick_side': 0.6, 'climb': 0.12, 'recovery': 15, 'max_climb': 7, 'pattern': [-0.4, 0.5, -0.2, 0.6, -0.6, 0.3]})
guns['smg_tommy'] = gun('smg_9', name='Tommy Gun', model='smg_tommy', sound='tommy', ammo='45acp', mag_size=30, mag_ext=50,
    rpm=700, muzzle_velocity=285, mass=4.9, value=4.6,
    attachments=['suppressor_light', 'mag_ext_light', 'mag_quick_light', 'mag_extquick_light', 'grip_vertical'],
    recoil={'kick_up': 1.2, 'kick_side': 0.7, 'climb': 0.12, 'recovery': 12, 'max_climb': 8, 'pattern': [0.6, -0.3, 0.7, -0.5, 0.4, 0.8]})
guns['shotgun_saiga'] = gun('shotgun_pump', name='S12K', model='shotgun_saiga', sound='saiga', feed='mag', mag_size=5, mag_ext=8,
    fire_modes=['semi'], rpm=300, reload_time=2.8, reload_empty_time=3.3, value=5.0,
    attachments=['weapon_light', 'sight_reddot', 'sight_holo', 'choke', 'mag_ext_rifle', 'mag_quick_rifle', 'mag_extquick_rifle', 'compensator'],
    recoil={'kick_up': 7.0, 'kick_side': 1.6, 'recovery': 10, 'max_climb': 11, 'pattern': [0.5, -0.6, 0.3]})
for k in ('cycle_time', 'reload_start', 'reload_end'):
    guns['shotgun_saiga'].pop(k, None)
guns['pistol_deagle'] = gun('pistol_45', name='Deagle', model='pistol_deagle', sound='deagle', ammo='50ae', mag_size=7, mag_ext=10,
    rpm=200, muzzle_velocity=470, mass=2.0, loudness=750, value=3.0,
    recoil={'kick_up': 6.5, 'kick_side': 1.4, 'climb': 0.0, 'recovery': 10, 'max_climb': 9, 'pattern': [0.7, -0.5, 0.4]})
save('weapons.json', W, wcrlf)

I, icrlf = load('items.json')
items = I['items']
# One colour per calibre, used on every box of that ammunition and on the label of every gun that fires it.
COLORS = {'9x19': [226, 176, 34], '45acp': [52, 104, 214], '357': [128, 128, 136], '12buck': [222, 96, 28],
          '12slug': [150, 56, 20], '556': [64, 156, 64], '762x39': [196, 48, 38], '308': [120, 70, 170], '50ae': [32, 156, 160]}
for k, it in items.items():
    if it.get('kind') == 'ammo' and it.get('ammo') in COLORS:
        it['color'] = COLORS[it['ammo']]
items['ammo_50ae'] = {'name': '.50 AE rounds', 'kind': 'ammo', 'ammo': '50ae', 'mass': 0.03, 'stack': 35, 'model': 'ammo_50ae',
                      'color': COLORS['50ae']}
items['frag_grenade'] = {'name': 'Frag grenade', 'kind': 'throwable', 'mass': 0.6, 'stack': 4, 'model': 'frag_grenade',
                         'fuse_s': 4.0, 'radius_m': 9.0, 'damage': 130, 'throw_speed': 17.0}
I['_doc'] = I['_doc'].split(' Ammunition colour:')[0] + ' Ammunition colour: color is the calibre\'s RGB, shared by every box of it and every gun that fires it.'
save('items.json', I, icrlf)

B, bcrlf = load('ballistics.json')
B['ammo']['50ae'] = {'name': '.50 AE', 'mass': 0.0195, 'drag_k': 0.0013, 'damage': 62, 'pellets': 1, 'armor_pen': 1.6, 'tracer_brightness': 0.6}
save('ballistics.json', B, bcrlf)
print('weapons: %d, ammo colours set, ammo_50ae and frag_grenade added' % len(guns))
