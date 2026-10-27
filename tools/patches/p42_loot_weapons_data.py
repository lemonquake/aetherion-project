"""Weapons data for the loot run (2026-10-26): attachment effects, per-weapon compatibility, three new guns.

    python -I tools/patches/p42_loot_weapons_data.py
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'data', 'weapons.json')
d = json.load(open(p, encoding='utf-8'))
W = d['weapons']

W['pistol_9'].update({'attachments': ['sight_reddot', 'suppressor_light', 'mag_ext_light', 'mag_quick_light', 'mag_extquick_light', 'weapon_light'], 'mag_ext': 21, 'value': 2.0})
W['pistol_45'].update({'attachments': ['sight_reddot', 'suppressor_light', 'mag_ext_light', 'mag_quick_light', 'mag_extquick_light', 'weapon_light'], 'mag_ext': 12, 'value': 2.2})
W['revolver_357'].update({'attachments': ['sight_reddot'], 'value': 2.5})
W['shotgun_pump'].update({'attachments': ['weapon_light', 'sight_reddot', 'sight_holo', 'choke', 'bullet_loops'], 'value': 4.0})
W['smg_9'].update({'attachments': ['weapon_light', 'sight_reddot', 'sight_holo', 'scope_2x', 'scope_3x', 'suppressor_light', 'compensator', 'flash_hider',
                                   'grip_vertical', 'grip_angled', 'grip_half', 'laser_sight', 'mag_ext_light', 'mag_quick_light', 'mag_extquick_light'],
                   'mag_ext': 40, 'value': 5.0})
W['machine_pistol'].update({'attachments': ['weapon_light', 'sight_reddot', 'sight_holo', 'suppressor_light', 'compensator', 'laser_sight', 'mag_ext_light',
                                            'mag_quick_light', 'mag_extquick_light', 'stock_tactical'], 'mag_ext': 45, 'value': 3.5})
AR = ['weapon_light', 'sight_reddot', 'sight_holo', 'scope_2x', 'scope_3x', 'scope_4x', 'scope_6x', 'suppressor_rifle', 'compensator', 'flash_hider',
      'laser_sight', 'mag_ext_rifle', 'mag_quick_rifle', 'mag_extquick_rifle']
W['rifle_556'].update({'attachments': AR + ['grip_vertical', 'grip_angled', 'grip_half'], 'mag_ext': 40, 'value': 7.0})
W['rifle_762'].update({'attachments': list(AR), 'mag_ext': 40, 'value': 7.0})
W['bolt_308'].update({'attachments': ['sight_reddot', 'sight_holo', 'scope_2x', 'scope_3x', 'scope_4x', 'scope_6x', 'scope_8x', 'suppressor_rifle',
                                      'cheek_pad', 'bullet_loops', 'mag_ext_sniper'], 'mag_ext': 8, 'value': 6.0})
W['shotgun_double'] = {
    "name": "Double-Barrel Shotgun", "class": "shotgun", "slot": "long", "ammo": "12buck", "alt_ammo": "12slug",
    "feed": "break", "mag_size": 2, "chamber": True, "fire_modes": ["semi"], "rpm": 400, "muzzle_velocity": 395,
    "mass": 3.2, "draw_time": 0.75, "ads_time": 0.28, "reload_time": 2.6, "reload_empty_time": 2.6,
    "spread_hip": 2.6, "spread_ads": 0.7, "move_spread": 1.6, "sight_zoom": 1.12, "loudness": 900,
    "recoil": {"kick_up": 8.0, "kick_side": 1.8, "camera_share": 0.6, "climb": 0.0, "recovery": 10, "max_climb": 11, "pattern": [0.6, -0.5]},
    "attachments": ["choke", "bullet_loops"], "model": "shotgun_double", "sound": "shotgun", "handed": "rifle", "hold": [0.62, 0.27], "value": 3.0}
W['sumpak'] = {
    "name": "Sumpak (improvised 12 gauge)", "class": "shotgun", "slot": "long", "ammo": "12buck", "alt_ammo": "12slug",
    "feed": "break", "mag_size": 1, "chamber": True, "fire_modes": ["semi"], "rpm": 60, "muzzle_velocity": 330,
    "mass": 1.7, "draw_time": 0.6, "ads_time": 0.3, "reload_time": 3.2, "reload_empty_time": 3.2,
    "spread_hip": 3.4, "spread_ads": 1.5, "move_spread": 2.0, "sight_zoom": 1.05, "loudness": 950,
    "recoil": {"kick_up": 9.0, "kick_side": 2.4, "camera_share": 0.65, "climb": 0.0, "recovery": 8, "max_climb": 12, "pattern": [0.9]},
    "attachments": [], "model": "sumpak", "sound": "shotgun", "handed": "rifle", "hold": [0.8, 0.14], "value": 1.5}
W['marksman_308'] = {
    "name": ".308 Marksman Rifle", "class": "marksman", "slot": "long", "ammo": "308",
    "feed": "mag", "mag_size": 20, "chamber": True, "fire_modes": ["semi"], "rpm": 320, "muzzle_velocity": 850,
    "mass": 4.6, "draw_time": 0.85, "ads_time": 0.34, "reload_time": 2.8, "reload_empty_time": 3.4,
    "spread_hip": 2.8, "spread_ads": 0.035, "move_spread": 2.2, "sight_zoom": 1.2, "loudness": 1150,
    "recoil": {"kick_up": 3.8, "kick_side": 0.8, "camera_share": 0.55, "climb": 0.08, "recovery": 10, "max_climb": 9, "pattern": [0.4, -0.6, 0.2, -0.3]},
    "attachments": ["sight_reddot", "sight_holo", "scope_2x", "scope_3x", "scope_4x", "scope_6x", "scope_8x", "suppressor_rifle", "compensator",
                    "flash_hider", "cheek_pad", "mag_ext_sniper"],
    "mag_ext": 30, "model": "marksman_308", "sound": "rifle_308", "handed": "rifle", "hold": [0.66, 0.38], "value": 6.5}

A = {
    "sight_reddot": {"name": "Red Dot Sight", "kind": "sight", "zoom": 1.3, "ads_time_mult": 1.0, "axis": 0.03, "reticle": "dot", "mass": 0.12},
    "sight_holo": {"name": "Holographic Sight", "kind": "sight", "zoom": 1.3, "ads_time_mult": 1.0, "axis": 0.034, "reticle": "holo", "mass": 0.32},
    "scope_2x": {"name": "2x Scope", "kind": "sight", "zoom": 2.0, "ads_time_mult": 1.1, "axis": 0.034, "reticle": "circle_dot", "scope": True, "mass": 0.3},
    "scope_3x": {"name": "3x Prism Scope", "kind": "sight", "zoom": 3.0, "ads_time_mult": 1.15, "axis": 0.038, "reticle": "chevron", "scope": True, "mass": 0.36},
    "scope_4x": {"name": "4x Prism Scope", "kind": "sight", "zoom": 4.0, "ads_time_mult": 1.25, "axis_f": 0.62, "reticle": "acog", "scope": True, "mass": 0.45},
    "scope_6x": {"name": "6x Rifle Scope", "kind": "sight", "zoom": 6.0, "ads_time_mult": 1.32, "axis": 0.05, "reticle": "mildot", "scope": True, "mass": 0.6},
    "scope_8x": {"name": "8x Rifle Scope", "kind": "sight", "zoom": 8.0, "ads_time_mult": 1.4, "axis": 0.056, "reticle": "duplex", "scope": True, "mass": 0.75},
    "suppressor_light": {"name": "Pistol/SMG Suppressor", "kind": "muzzle", "loudness_mult": 0.3, "flash_mult": 0.1, "suppressed": True, "recoil_up_mult": 0.95, "sway_mult": 1.05, "rank": 3.0, "mass": 0.2},
    "suppressor_rifle": {"name": "Rifle Suppressor", "kind": "muzzle", "loudness_mult": 0.35, "flash_mult": 0.1, "suppressed": True, "recoil_up_mult": 0.92, "sway_mult": 1.08, "rank": 3.0, "mass": 0.5},
    "compensator": {"name": "Compensator", "kind": "muzzle", "recoil_up_mult": 0.8, "recoil_side_mult": 0.8, "loudness_mult": 1.1, "flash_mult": 1.15, "rank": 2.2, "mass": 0.1},
    "flash_hider": {"name": "Flash Hider", "kind": "muzzle", "flash_mult": 0.25, "recoil_up_mult": 0.92, "recoil_side_mult": 0.9, "rank": 1.8, "mass": 0.08},
    "choke": {"name": "Shotgun Choke", "kind": "muzzle", "pellet_spread_mult": 0.65, "rank": 2.0, "mass": 0.06},
    "grip_vertical": {"name": "Vertical Foregrip", "kind": "grip", "recoil_up_mult": 0.85, "sway_mult": 0.9, "rank": 2.2, "mass": 0.1},
    "grip_angled": {"name": "Angled Foregrip", "kind": "grip", "ads_time_mult": 0.85, "recoil_side_mult": 0.82, "rank": 2.0, "mass": 0.08},
    "grip_half": {"name": "Half Grip", "kind": "grip", "recoil_up_mult": 0.92, "recoil_side_mult": 0.92, "recovery_mult": 1.15, "rank": 2.0, "mass": 0.07},
    "laser_sight": {"name": "Laser Sight", "kind": "grip", "spread_hip_mult": 0.65, "move_spread_mult": 0.85, "laser": True, "rank": 1.6, "mass": 0.1},
    "weapon_light": {"name": "Weapon Light", "kind": "light", "rank": 2.5, "mass": 0.12},
    "mag_ext_light": {"name": "Extended Pistol/SMG Magazine", "kind": "mag", "ext": True, "rank": 2.0, "mass": 0.15},
    "mag_quick_light": {"name": "Quickdraw Pistol/SMG Magazine", "kind": "mag", "reload_mult": 0.7, "rank": 1.5, "mass": 0.12},
    "mag_extquick_light": {"name": "Extended Quickdraw Pistol/SMG Magazine", "kind": "mag", "ext": True, "reload_mult": 0.78, "rank": 3.0, "mass": 0.17},
    "mag_ext_rifle": {"name": "Extended Rifle Magazine", "kind": "mag", "ext": True, "rank": 2.0, "mass": 0.25},
    "mag_quick_rifle": {"name": "Quickdraw Rifle Magazine", "kind": "mag", "reload_mult": 0.7, "rank": 1.5, "mass": 0.3},
    "mag_extquick_rifle": {"name": "Extended Quickdraw Rifle Magazine", "kind": "mag", "ext": True, "reload_mult": 0.78, "rank": 3.0, "mass": 0.3},
    "mag_ext_sniper": {"name": "Extended Marksman Magazine", "kind": "mag", "ext": True, "rank": 2.0, "mass": 0.2},
    "stock_tactical": {"name": "Tactical Stock", "kind": "stock", "sway_mult": 0.75, "recoil_up_mult": 0.9, "recovery_mult": 1.2, "rank": 2.0, "mass": 0.35},
    "cheek_pad": {"name": "Cheek Pad", "kind": "stock", "sway_mult": 0.8, "recoil_up_mult": 0.9, "recovery_mult": 1.15, "rank": 2.0, "mass": 0.08},
    "bullet_loops": {"name": "Bullet Loops", "kind": "stock", "reload_mult": 0.75, "rank": 1.6, "mass": 0.1},
}
d['attachments'] = A
if 'Attachments:' not in d['_doc']:
    d['_doc'] += (" Attachments: kind is the slot (sight, muzzle, grip, mag, stock, light; one of each per weapon). *_mult fields multiply the"
                  " weapon's value (recoil_up, recoil_side, recovery, spread_hip, move_spread, sway, ads_time, reload, loudness, flash, pellet_spread)."
                  " ext switches to the weapon's mag_ext capacity. Sights: zoom; axis = optical axis height above the rail in metres (axis_f: fraction"
                  " of the model height); reticle style; scope = magnified, drawn as a scope view while aiming. rank orders same-slot attachments when"
                  " picking up. Weapons: value ranks weapons for bots; hold = [grip, fore-end] as fractions of the length from the muzzle; mounts"
                  " overrides the automatic mount points.")
for wid, w in W.items():
    for a in w.get('attachments', []):
        assert a in A, (wid, a)
json.dump(d, open(p, 'w', encoding='utf-8', newline='\n'), indent=2, ensure_ascii=False)
print('weapons', len(W), 'attachments', len(A))
