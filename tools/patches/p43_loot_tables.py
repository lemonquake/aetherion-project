"""Loot tables for the loot run (2026-10-26): attachments everywhere, more weapons on the floor, loot-box tables, and
ammunition that comes with a weapon.

    python -I tools/patches/p43_loot_tables.py
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'data', 'loot.json')
d = json.load(open(p, encoding='utf-8'))
T = d['tables']

BAT = lambda w, n=(1, 2), c=(0.3, 1.0): ['battery', w, list(n), list(c)]

T['wardrobe']['entries'] += [['sight_reddot', 3, [1, 1]], ['mag_ext_light', 3, [1, 1]], ['scope_2x', 2, [1, 1]], ['laser_sight', 1.5, [1, 1]]]
T['under_bed']['entries'] += [['sumpak', 5, [1, 1]], ['shotgun_double', 4, [1, 1]], ['sight_holo', 2, [1, 1]], ['mag_quick_light', 2, [1, 1]],
                              ['suppressor_light', 1.5, [1, 1]], ['compensator', 2, [1, 1]]]
T['store_counter']['entries'] += [['sight_reddot', 4, [1, 1]], ['weapon_light', 4, [1, 1]], ['grip_half', 3, [1, 1]], ['ammo_45acp', 6, [7, 14]]]
T['toolbox']['entries'] += [['compensator', 5, [1, 1]], ['flash_hider', 5, [1, 1]], ['choke', 4, [1, 1]], ['grip_vertical', 3, [1, 1]],
                            ['laser_sight', 3, [1, 1]], ['bullet_loops', 3, [1, 1]], ['stock_tactical', 2, [1, 1]]]
T['weapon_locker']['entries'] += [['scope_2x', 4, [1, 1]], ['scope_3x', 3, [1, 1]], ['grip_vertical', 4, [1, 1]], ['mag_ext_rifle', 4, [1, 1]],
                                  ['mag_ext_light', 4, [1, 1]], ['suppressor_light', 2, [1, 1]], ['marksman_308', 3, [1, 1]], ['ammo_308', 4, [10, 20]]]
T['military_crate']['entries'] += [['scope_6x', 4, [1, 1]], ['scope_8x', 2, [1, 1]], ['suppressor_rifle', 4, [1, 1]], ['mag_extquick_rifle', 4, [1, 1]],
                                   ['grip_angled', 4, [1, 1]], ['compensator', 4, [1, 1]], ['marksman_308', 6, [1, 1]], ['cheek_pad', 3, [1, 1]]]
T['crate']['entries'] += [['mag_quick_rifle', 2, [1, 1]], ['flash_hider', 2, [1, 1]], ['sumpak', 2, [1, 1]]]

T['floor_household'] = {'rolls': [1, 2], 'entries': [
    ['nothing', 22], BAT(14, (1, 1), (0.2, 0.9)), ['bandage', 6, [1, 2]], ['painkillers', 3, [1, 1]], ['flashlight', 3, [1, 1]],
    ['ammo_9x19', 7, [8, 20]], ['ammo_45acp', 3, [7, 14]], ['ammo_357', 2, [6, 12]], ['ammo_12buck', 6, [4, 8]], ['ammo_556', 3, [15, 30]],
    ['ammo_762x39', 3, [15, 30]], ['ammo_308', 1, [5, 10]],
    ['pistol_9', 4, [1, 1]], ['pistol_45', 2, [1, 1]], ['revolver_357', 2, [1, 1]], ['sumpak', 4, [1, 1]], ['shotgun_double', 2, [1, 1]],
    ['shotgun_pump', 1.5, [1, 1]], ['machine_pistol', 1.2, [1, 1]], ['smg_9', 0.8, [1, 1]], ['rifle_762', 0.4, [1, 1]],
    ['sight_reddot', 2.5, [1, 1]], ['sight_holo', 1.5, [1, 1]], ['scope_2x', 1.5, [1, 1]], ['scope_3x', 0.6, [1, 1]], ['mag_ext_light', 2, [1, 1]],
    ['mag_quick_light', 1.5, [1, 1]], ['mag_ext_rifle', 1, [1, 1]], ['compensator', 1, [1, 1]], ['flash_hider', 1, [1, 1]], ['grip_vertical', 1, [1, 1]],
    ['grip_half', 1, [1, 1]], ['laser_sight', 1, [1, 1]], ['weapon_light', 1.5, [1, 1]], ['choke', 1, [1, 1]], ['bullet_loops', 1, [1, 1]],
    ['suppressor_light', 0.5, [1, 1]], ['backpack_small', 1, [1, 1]], ['vest_light', 0.6, [1, 1]], ['helmet_light', 0.6, [1, 1]]]}
T['floor_street'] = {'rolls': [1, 1], 'entries': [
    ['nothing', 45], BAT(12, (1, 1), (0.05, 0.7)), ['ammo_9x19', 6, [5, 12]], ['ammo_12buck', 6, [2, 6]], ['ammo_556', 2, [10, 20]],
    ['ammo_762x39', 2, [10, 20]], ['bandage', 4, [1, 1]], ['sumpak', 3, [1, 1]], ['pistol_9', 2, [1, 1]], ['revolver_357', 1, [1, 1]],
    ['shotgun_double', 1, [1, 1]], ['sight_reddot', 1.5, [1, 1]], ['mag_ext_light', 1, [1, 1]], ['compensator', 0.8, [1, 1]],
    ['grip_half', 0.8, [1, 1]], ['flash_hider', 0.8, [1, 1]], ['scope_2x', 0.8, [1, 1]]]}
T['floor_contested']['entries'] += [['marksman_308', 6, [1, 1]], ['scope_4x', 5, [1, 1]], ['scope_6x', 3, [1, 1]], ['scope_8x', 1.5, [1, 1]],
                                    ['suppressor_rifle', 3, [1, 1]], ['mag_extquick_rifle', 3, [1, 1]], ['grip_angled', 3, [1, 1]], ['sight_holo', 4, [1, 1]]]
T['floor_contested']['rolls'] = [1, 2]

# Loot boxes (visible containers placed in houses, shops, docks and sites).
T['box_balikbayan'] = {'rolls': [1, 3], 'entries': [
    ['nothing', 10], BAT(20, (1, 3), (0.5, 1.0)), ['flashlight', 6, [1, 1]], ['bandage', 8, [1, 3]], ['painkillers', 6, [1, 2]],
    ['backpack_small', 6, [1, 1]], ['backpack_large', 2, [1, 1]], ['vest_light', 3, [1, 1]], ['helmet_light', 2, [1, 1]], ['pistol_9', 3, [1, 1]],
    ['revolver_357', 2, [1, 1]], ['ammo_9x19', 6, [10, 25]], ['ammo_12buck', 4, [4, 10]], ['sight_reddot', 3, [1, 1]], ['scope_2x', 2, [1, 1]],
    ['mag_ext_light', 2, [1, 1]], ['weapon_light', 2, [1, 1]]]}
T['box_bin'] = {'rolls': [1, 2], 'entries': [
    ['nothing', 14], BAT(18, (1, 2), (0.3, 1.0)), ['bandage', 8, [1, 2]], ['painkillers', 4, [1, 1]], ['ammo_9x19', 8, [10, 25]],
    ['ammo_12buck', 6, [4, 10]], ['ammo_45acp', 4, [7, 14]], ['ammo_357', 3, [6, 12]], ['flashlight', 4, [1, 1]], ['sumpak', 3, [1, 1]],
    ['shotgun_double', 2, [1, 1]], ['sight_holo', 2, [1, 1]], ['grip_half', 2, [1, 1]], ['compensator', 2, [1, 1]], ['mag_quick_light', 2, [1, 1]]]}
T['box_ammocan'] = {'rolls': [1, 3], 'entries': [
    ['ammo_9x19', 14, [15, 40]], ['ammo_556', 12, [20, 60]], ['ammo_762x39', 12, [20, 60]], ['ammo_308', 6, [10, 20]], ['ammo_12buck', 10, [6, 16]],
    ['ammo_12slug', 5, [4, 8]], ['ammo_45acp', 6, [10, 21]], ['ammo_357', 4, [8, 18]], ['mag_ext_rifle', 4, [1, 1]], ['mag_quick_rifle', 3, [1, 1]],
    ['mag_extquick_rifle', 1.5, [1, 1]], ['mag_ext_light', 3, [1, 1]], ['mag_extquick_light', 1.5, [1, 1]], ['mag_ext_sniper', 1.5, [1, 1]],
    ['bullet_loops', 2, [1, 1]]]}
T['box_footlocker'] = {'rolls': [2, 3], 'entries': [
    ['pistol_45', 5, [1, 1]], ['revolver_357', 4, [1, 1]], ['shotgun_pump', 5, [1, 1]], ['smg_9', 4, [1, 1]], ['machine_pistol', 4, [1, 1]],
    ['rifle_556', 2, [1, 1]], ['rifle_762', 2, [1, 1]], ['marksman_308', 1.2, [1, 1]], ['bolt_308', 1, [1, 1]], ['vest_light', 6, [1, 1]],
    ['helmet_light', 5, [1, 1]], ['backpack_large', 4, [1, 1]], ['ammo_9x19', 5, [15, 30]], ['ammo_45acp', 3, [10, 21]], ['ammo_556', 3, [20, 40]],
    ['ammo_762x39', 3, [20, 40]], ['ammo_12buck', 3, [6, 12]], ['sight_holo', 3, [1, 1]], ['scope_3x', 2, [1, 1]], ['scope_4x', 1.2, [1, 1]],
    ['suppressor_light', 1.5, [1, 1]], ['grip_vertical', 2, [1, 1]], ['grip_angled', 1.5, [1, 1]], ['stock_tactical', 1.5, [1, 1]],
    ['cheek_pad', 1.5, [1, 1]]]}
T['box_toolbox'] = {'rolls': [1, 3], 'entries': [
    ['nothing', 8], BAT(22, (1, 3), (0.4, 1.0)), ['flashlight', 8, [1, 1]], ['weapon_light', 6, [1, 1]], ['laser_sight', 4, [1, 1]],
    ['compensator', 5, [1, 1]], ['flash_hider', 5, [1, 1]], ['choke', 4, [1, 1]], ['grip_vertical', 3, [1, 1]], ['grip_half', 3, [1, 1]],
    ['grip_angled', 2, [1, 1]], ['stock_tactical', 2, [1, 1]], ['cheek_pad', 2, [1, 1]], ['bullet_loops', 3, [1, 1]], ['mag_quick_light', 2, [1, 1]],
    ['splint', 3, [1, 1]], ['sight_reddot', 2, [1, 1]]]}
T['box_medcase'] = {'rolls': [2, 3], 'entries': [
    ['nothing', 6], ['first_aid', 18, [1, 1]], ['bandage', 26, [2, 4]], ['painkillers', 18, [1, 3]], ['splint', 14, [1, 2]], BAT(4, (1, 1), (0.5, 1.0))]}
T['box_riflecase'] = {'rolls': [1, 2], 'guaranteed': [
    ['rifle_556', 8, [1, 1]], ['rifle_762', 8, [1, 1]], ['marksman_308', 6, [1, 1]], ['bolt_308', 6, [1, 1]], ['shotgun_pump', 5, [1, 1]],
    ['smg_9', 4, [1, 1]]], 'entries': [
    ['scope_3x', 6, [1, 1]], ['scope_4x', 6, [1, 1]], ['scope_6x', 4, [1, 1]], ['scope_8x', 2, [1, 1]], ['sight_holo', 5, [1, 1]],
    ['sight_reddot', 5, [1, 1]], ['suppressor_rifle', 3, [1, 1]], ['mag_extquick_rifle', 3, [1, 1]], ['cheek_pad', 4, [1, 1]],
    ['bullet_loops', 3, [1, 1]], ['mag_ext_sniper', 3, [1, 1]], ['grip_vertical', 3, [1, 1]]]}
T['box_cooler'] = {'rolls': [1, 2], 'entries': [
    ['nothing', 25], BAT(14, (1, 2), (0.3, 1.0)), ['bandage', 8, [1, 2]], ['painkillers', 6, [1, 1]], ['ammo_12buck', 8, [4, 10]],
    ['ammo_9x19', 6, [10, 20]], ['sumpak', 4, [1, 1]], ['shotgun_double', 2, [1, 1]], ['flashlight', 4, [1, 1]], ['first_aid', 3, [1, 1]],
    ['sight_reddot', 2, [1, 1]], ['scope_2x', 2, [1, 1]]]}

d['weapon_ammo'] = {'chance': 0.8, 'counts': {'9x19': [10, 30], '45acp': [7, 21], '357': [6, 18], '12buck': [4, 10], '12slug': [3, 6],
                                              '556': [15, 45], '762x39': [15, 45], '308': [5, 15]}}
d['weapon_attachment_chance'] = 0.2
d['_doc'] = ("Loot tables. Each container type rolls `rolls` times (inclusive range) and picks a weighted entry; 'nothing' is a valid "
             "entry. `guaranteed` (optional) is one extra weighted roll that never comes up empty. count is an inclusive range. charge is a "
             "battery charge range. Weapons spawn with a random partial magazine and, with probability weapon_ammo.chance, a stack of their "
             "own ammunition beside them (weapon_ammo.counts per calibre); weapon_attachment_chance is the chance a weapon comes with one "
             "compatible attachment already fitted. box_* tables are the visible loot boxes; floor_* tables are items lying in the open.")

ids = set()
W = json.load(open(os.path.join(ROOT, 'game', 'data', 'weapons.json'), encoding='utf-8'))
I = json.load(open(os.path.join(ROOT, 'game', 'data', 'items.json'), encoding='utf-8'))
known = set(W['weapons']) | set(W['attachments']) | set(I['items']) | {'nothing'}
for name, t in T.items():
    for e in t.get('entries', []) + t.get('guaranteed', []):
        assert e[0] in known, (name, e[0])
json.dump(d, open(p, 'w', encoding='utf-8', newline='\n'), indent=1, ensure_ascii=False)
print('tables', len(T))
