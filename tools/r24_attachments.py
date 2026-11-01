"""r24: new attachments (magazines, muzzle devices, grips, extras), a one-line description for every attachment (the
workbench's hover card), and which guns take them. Rewrites game/data/weapons.json in its own format (indent 1)
and adds the new ids to the loot tables beside their nearest existing relative. Safe to run twice.

    python -I tools/r24_attachments.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'game', 'data')

NEW = {
    # Magazines
    'mag_drum_rifle': {'name': 'Rifle Drum Magazine', 'kind': 'mag', 'cap_mult': 2.0, 'reload_mult': 1.4, 'ads_time_mult': 1.08,
                       'sway_mult': 1.08, 'rank': 2.6, 'mass': 0.95},
    'mag_drum_light': {'name': 'Pistol/SMG Drum Magazine', 'kind': 'mag', 'cap_mult': 1.8, 'reload_mult': 1.35, 'ads_time_mult': 1.06,
                       'sway_mult': 1.05, 'rank': 2.6, 'mass': 0.6},
    'mag_polymer_rifle': {'name': 'Lightweight Rifle Magazine', 'kind': 'mag', 'reload_mult': 0.88, 'ads_time_mult': 0.95,
                          'rank': 1.7, 'mass': 0.12},
    'mag_polymer_light': {'name': 'Lightweight Pistol/SMG Magazine', 'kind': 'mag', 'reload_mult': 0.88, 'ads_time_mult': 0.95,
                          'rank': 1.7, 'mass': 0.06},
    # Muzzle devices
    'suppressor_sniper': {'name': 'Marksman Suppressor', 'kind': 'muzzle', 'loudness_mult': 0.4, 'flash_mult': 0.1, 'suppressed': True,
                          'recoil_up_mult': 0.88, 'sway_mult': 1.1, 'ads_time_mult': 1.05, 'rank': 3.2, 'mass': 0.6},
    'muzzle_tactical': {'name': 'Tactical Compensator', 'kind': 'muzzle', 'recoil_side_mult': 0.72, 'recoil_up_mult': 0.9,
                        'loudness_mult': 1.15, 'flash_mult': 1.1, 'rank': 2.3, 'mass': 0.09},
    # Grips
    'grip_stubby': {'name': 'Stubby Grip', 'kind': 'grip', 'recoil_up_mult': 0.9, 'ads_time_mult': 0.92, 'recovery_mult': 1.08,
                    'rank': 2.1, 'mass': 0.06},
    'grip_heavy': {'name': 'Heavy Foregrip', 'kind': 'grip', 'recoil_up_mult': 0.78, 'recoil_side_mult': 0.85, 'sway_mult': 0.92,
                   'ads_time_mult': 1.1, 'rank': 2.3, 'mass': 0.2},
    # Extras (the "light" mount under the front of the barrel)
    'laser_green': {'name': 'Green Laser Module', 'kind': 'light', 'spread_hip_mult': 0.7, 'move_spread_mult': 0.9, 'laser': True,
                    'rank': 1.8, 'mass': 0.09},
    'rail_cover': {'name': 'Ergonomic Rail Covers', 'kind': 'light', 'sway_mult': 0.9, 'recovery_mult': 1.06, 'rank': 1.5, 'mass': 0.05},
    'sling_quick': {'name': 'Quick-Deploy Sling', 'kind': 'light', 'ads_time_mult': 0.9, 'sway_mult': 1.04, 'rank': 1.6, 'mass': 0.08},
}

DESC = {
    'sight_reddot': 'A lit dot on clear glass: quick to aim, a little magnification.',
    'sight_holo': 'A wide holographic window with a ring and dot, for close fights.',
    'sight_reflex': 'A small open reflex sight; the fastest to bring up.',
    'scope_2x': '2x magnification with an open circle-dot reticle.',
    'scope_3x': '3x prism scope with a lit chevron.',
    'scope_4x': '4x prism scope with a bullet-drop ladder under a lit chevron.',
    'scope_6x': '6x rifle scope with a mil-dot cross.',
    'scope_8x': '8x rifle scope with a duplex cross.',
    'scope_lpvo': 'Variable 1-4x: turn the ring with the mouse wheel while aiming.',
    'scope_night': '3x night vision: amplifies what little light there is.',
    'scope_thermal': '4x thermal: people show white hot, through smoke and darkness.',
    'scope_15x': '15x sniper scope with a holdover tree for long shots.',
    'suppressor_light': 'Quiets a pistol or SMG and hides the flash.',
    'suppressor_rifle': 'Quiets a rifle and hides the flash; a little heavier on the front.',
    'suppressor_sniper': 'A long can for marksman and sniper rifles: quiet, no flash, less kick.',
    'compensator': 'Ports gas up and sideways to hold the muzzle down. Louder.',
    'flash_hider': 'Hides the muzzle flash and softens the kick a little.',
    'muzzle_brake': 'Big side ports: much less vertical kick, but loud and bright.',
    'muzzle_tactical': 'Short compensator tuned against the sideways kick.',
    'choke': 'Tightens a shotgun\'s pellet spread.',
    'duckbill': 'Spreads shotgun pellets into a wide flat line.',
    'grip_vertical': 'A post to hold: less vertical recoil and sway.',
    'grip_angled': 'Angled grip: faster aiming and less sideways kick.',
    'grip_half': 'Half grip: a little less recoil both ways, faster recovery.',
    'grip_thumb': 'Thumb rest: faster aiming, slightly less vertical recoil.',
    'grip_light': 'Skeleton grip: quick recovery, steadier aim, a touch more kick.',
    'grip_ergonomic': 'Shaped for the hand: faster aiming and recovery.',
    'grip_stubby': 'Short stub grip: faster aiming and a little less recoil.',
    'grip_heavy': 'A heavy foregrip that drags the muzzle down: much less recoil, slower to aim.',
    'laser_sight': 'Laser on the grip mount: tighter hip fire and spread while moving.',
    'laser_green': 'A bright green laser module: tighter hip fire.',
    'weapon_light': 'A flashlight on the gun (F switches it).',
    'rail_cover': 'Rubber rail covers for a steadier hold.',
    'sling_quick': 'A sling that keeps the gun up and ready: faster aiming.',
    'mag_ext_light': 'More rounds in a pistol or SMG.',
    'mag_quick_light': 'A pull tab for faster pistol and SMG reloads.',
    'mag_extquick_light': 'More rounds and a faster reload for a pistol or SMG.',
    'mag_drum_light': 'A drum for a pistol or SMG: far more rounds, slower to reload.',
    'mag_polymer_light': 'A light polymer magazine: quicker reloads and aiming.',
    'mag_ext_rifle': 'More rounds in a rifle.',
    'mag_quick_rifle': 'Two magazines clamped together: much faster reloads.',
    'mag_extquick_rifle': 'More rounds and a faster rifle reload.',
    'mag_drum_rifle': 'A rifle drum: twice the rounds, heavy and slow to reload.',
    'mag_polymer_rifle': 'A light polymer rifle magazine: quicker reloads and aiming.',
    'mag_ext_sniper': 'More rounds for a marksman or sniper rifle.',
    'stock_tactical': 'Collapsible stock: steadier aim and less recoil.',
    'stock_heavy': 'Heavy fixed stock: very steady aim, slower to bring up.',
    'cheek_pad': 'A pad for the cheek weld: steadier aim and less recoil.',
    'bullet_loops': 'Spare shells on the stock: faster reloads.',
}


def add_where(weapons, have, new_ids, pred=None):
    """Adds new_ids to every gun that already takes `have` (and passes pred)."""
    for wid, w in weapons.items():
        atts = w.get('attachments', [])
        if have in atts and (pred is None or pred(w)):
            for a in new_ids:
                if a not in atts:
                    atts.append(a)


def main():
    p = os.path.join(ROOT, 'weapons.json')
    d = json.load(open(p, encoding='utf-8'))
    att = d['attachments']
    for k, v in NEW.items():
        att[k] = v
    for k, v in att.items():
        if k in DESC:
            v['desc'] = DESC[k]
    missing = [k for k in att if 'desc' not in att[k]]
    if missing:
        raise SystemExit('no description for %s' % missing)
    W = d['weapons']
    long_gun = lambda w: w.get('slot') == 'long'
    add_where(W, 'mag_ext_rifle', ['mag_drum_rifle', 'mag_polymer_rifle'])
    add_where(W, 'mag_ext_light', ['mag_drum_light', 'mag_polymer_light'])
    add_where(W, 'mag_ext_sniper', ['suppressor_sniper'])
    add_where(W, 'compensator', ['muzzle_tactical'])
    add_where(W, 'grip_vertical', ['grip_stubby', 'grip_heavy'])
    add_where(W, 'weapon_light', ['laser_green', 'rail_cover'], long_gun)
    add_where(W, 'weapon_light', ['laser_green'], lambda w: not long_gun(w))
    add_where(W, 'weapon_light', ['sling_quick'], long_gun)
    d['_doc'] = d['_doc'].replace('ext switches to the weapon\'s mag_ext capacity.',
                                  'ext switches to the weapon\'s mag_ext capacity; cap_mult multiplies the magazine (drums). desc is the workbench\'s one-line description.')
    s = json.dumps(d, indent=1)
    open(p, 'wb').write(s.encode('utf-8'))
    used = {a for w in W.values() for a in w.get('attachments', [])}
    print('attachments %d (new %d); unused by any gun: %s' % (len(att), len(NEW), sorted(set(att) - used)))
    # Loot: each new id next to its relative, with the same weight.
    rel = {'mag_drum_rifle': 'mag_ext_rifle', 'mag_polymer_rifle': 'mag_quick_rifle', 'mag_drum_light': 'mag_ext_light',
           'mag_polymer_light': 'mag_quick_light', 'suppressor_sniper': 'suppressor_rifle', 'muzzle_tactical': 'compensator',
           'grip_stubby': 'grip_thumb', 'grip_heavy': 'grip_vertical', 'laser_green': 'laser_sight', 'rail_cover': 'grip_light',
           'sling_quick': 'grip_ergonomic'}
    lp = os.path.join(ROOT, 'loot.json')
    raw = open(lp, 'rb').read()
    loot = json.loads(raw)
    indent = 1 if json.dumps(loot, indent=1).encode() == raw else None
    added = [0]

    def walk(o):
        if isinstance(o, dict):
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            if all(isinstance(x, str) for x in o):
                for new, old in rel.items():
                    if old in o and new not in o:
                        o.insert(o.index(old) + 1, new)
                        added[0] += 1
            else:
                for v in list(o):
                    walk(v)
                # weighted entries such as [id, weight] or {"id":..., "w":...}
                for new, old in rel.items():
                    for i, e in enumerate(list(o)):
                        if isinstance(e, list) and e and e[0] == old and not any(isinstance(x, list) and x and x[0] == new for x in o):
                            o.insert(i + 1, [new] + e[1:])
                            added[0] += 1
                        elif isinstance(e, dict) and e.get('id') == old and not any(isinstance(x, dict) and x.get('id') == new for x in o):
                            ne = dict(e)
                            ne['id'] = new
                            o.insert(i + 1, ne)
                            added[0] += 1
    walk(loot)
    if indent is None:
        raise SystemExit('loot.json is not in indent-1 format; not rewritten')
    open(lp, 'wb').write(json.dumps(loot, indent=1).encode('utf-8'))
    print('loot entries added %d' % added[0])


main()
