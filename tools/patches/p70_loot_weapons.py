"""Weapons lying in the open and in loot boxes (user, 2026-10-27: "no weapons anywhere, even balikbayan boxes").

    python -I tools/patches/p70_loot_weapons.py

Idempotent: rebuilds the floor_weapon table from FLOOR_WEIGHTS (every gun in weapons.json must have a weight) and
sets the share of weapon rolls in each box table, replacing whatever weapon entries the table had.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LOOT = os.path.join(ROOT, 'game', 'data', 'loot.json')
WEAPONS = os.path.join(ROOT, 'game', 'data', 'weapons.json')

# Relative odds of each gun on the floor (common sidearms and shotguns, rarer rifles, rare precision rifles).
FLOOR_WEIGHTS = {
    'pistol_9': 10, 'pistol_45': 6, 'revolver_357': 5, 'pistol_glock': 8, 'pistol_deagle': 2,
    'shotgun_pump': 8, 'shotgun_double': 7, 'sumpak': 7, 'shotgun_saiga': 3,
    'smg_9': 7, 'machine_pistol': 7, 'smg_vector': 4, 'smg_ump45': 6, 'smg_tommy': 4,
    'rifle_556': 6, 'rifle_762': 6, 'rifle_scar': 5, 'rifle_m416': 5, 'rifle_m762': 3, 'rifle_qbz': 4,
    'lmg_m249': 1, 'marksman_308': 2.5, 'dmr_mini14': 3, 'dmr_sks': 3, 'bolt_308': 1.5, 'bolt_kar98': 1.5,
}

# Fraction of each box table's rolls that come up a gun.
BOX_SHARE = {
    'box_balikbayan': 0.32, 'box_bin': 0.16, 'box_cooler': 0.12, 'box_footlocker': 0.45, 'box_toolbox': 0.06,
    'under_bed': 0.3, 'wardrobe': 0.14, 'store_counter': 0.16, 'weapon_locker': 0.4, 'military_crate': 0.3,
    'floor_household': 0.12, 'floor_street': 0.06,
}
# Frag grenade weight per table (relative to that table's entries).
FRAG = {'box_footlocker': 4, 'box_ammocan': 6, 'military_crate': 6, 'weapon_locker': 5, 'box_balikbayan': 2,
        'floor_household': 2, 'floor_contested': 4, 'box_bin': 1.5}
# Box tables that only carry certain classes (military crates: long guns only).
CLASS_FILTER = {'military_crate': {'rifle', 'marksman', 'precision', 'lmg'}}


def main():
    weapons = json.load(open(WEAPONS, encoding='utf-8'))['weapons']
    missing = [w for w in weapons if w not in FLOOR_WEIGHTS]
    if missing:
        sys.exit('no floor weight for: %s' % missing)
    raw = open(LOOT, 'rb').read()
    crlf = b'\r\n' in raw
    loot = json.loads(raw.decode('utf-8'))
    tables = loot['tables']
    tables['floor_weapon'] = {'rolls': [1, 1],
                              'entries': [[w, FLOOR_WEIGHTS[w], [1, 1]] for w in weapons]}
    for name, share in BOX_SHARE.items():
        t = tables[name]
        rest = [e for e in t['entries'] if e[0] not in weapons]
        other = sum(float(e[1]) for e in rest)
        allowed = [w for w in weapons if weapons[w].get('class') in CLASS_FILTER[name]] if name in CLASS_FILTER else list(weapons)
        wsum = sum(FLOOR_WEIGHTS[w] for w in allowed)
        target = share * other / (1.0 - share)
        add = [[w, round(FLOOR_WEIGHTS[w] * target / wsum, 3), [1, 1]] for w in allowed]
        t['entries'] = rest + add
    # Frag grenades: a few per box table and on floors (count range per roll).
    for name, wgt in FRAG.items():
        t = tables[name]
        t['entries'] = [e for e in t['entries'] if e[0] != 'frag_grenade'] + [['frag_grenade', wgt, [1, 2]]]
    for name, wgt in {'box_ammocan': 3, 'box_footlocker': 1.5, 'floor_household': 0.6, 'weapon_locker': 1.5}.items():
        t = tables[name]
        t['entries'] = [e for e in t['entries'] if e[0] != 'ammo_50ae'] + [['ammo_50ae', wgt, [7, 14]]]
    # A gun always comes with some of its own rounds, enough for a couple of magazines.
    wa = loot['weapon_ammo']
    wa['chance'] = 1.0
    wa['counts'].update({'9x19': [20, 45], '45acp': [14, 35], '357': [12, 24], '12buck': [8, 15], '12slug': [5, 10],
                         '556': [30, 60], '762x39': [30, 60], '308': [10, 20], '50ae': [7, 21], '762x54': [10, 20]})
    out = json.dumps(loot, indent=1, ensure_ascii=False) + '\n'
    if crlf:
        out = out.replace('\n', '\r\n')
    open(LOOT, 'wb').write(out.encode('utf-8'))
    print('floor_weapon: %d guns; box shares set for %d tables' % (len(weapons), len(BOX_SHARE)))


if __name__ == '__main__':
    main()
