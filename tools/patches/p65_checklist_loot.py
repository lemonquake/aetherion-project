"""Checklist: loot run results (2026-10-26).

    python -I tools/patches/p65_checklist_loot.py "<perf row text>"
"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'docs', 'CHECKLIST.md')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')
perf_row = sys.argv[1] if len(sys.argv) > 1 else 'not run'


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''yet; **Incomplete** and **Blocked** say what is missing. Updated 2026-10-26 (furnished rooms, 30–40 player map,
bot level of detail).''', '''yet; **Incomplete** and **Blocked** say what is missing. Updated 2026-10-26 (furnished rooms, 30–40 player map,
bot level of detail; loot, loot boxes, weapon attachments and scopes, bot looting — version 0.3.0).''')
rep('''| `tools/check.sh` (compile all scripts) | 63 scripts, 0 failed |''', '''| `tools/check.sh` (compile all scripts) | 67 scripts, 0 failed |
| Loot play-through `--autotest=loot` (loot4, 11 bots) | 29 checks, 0 failed: model census, loot boxes and floor loot counts, items resting on surfaces, ten attachment-effect checks, pickups, a loot box opening, sights on the bullet line, scope views, another player's attachments and laser |''')
rep('''| Host play-through `--autotest=tour` (t22, 31 bots) | 26 checks, 0 failed (adds `flashlight_lights_room`: the same view must get clearly brighter when the flashlight comes on) |''',
    '''| Host play-through `--autotest=tour` (t23, 31 bots, after the loot work) | 26 checks, 0 failed (includes `flashlight_lights_room`: the same view must get clearly brighter when the flashlight comes on) |''')
rep('''| Two-client network test `tools/net_test.sh` | 14 checks, 0 failed (dedicated server + two separate client processes, same PC); run before the wall-winding fix below, which changes rendering only |''',
    '''| Two-client network test `tools/net_test.sh` | 14 checks, 0 failed (dedicated server + two separate client processes, same PC), rerun after the loot work (ground items are now physics/render resources without scene nodes) |''')
rep('''| Attachments shown on weapons | Incomplete | Attachments work in data; not drawn on the models |''',
    '''| Attachments shown on weapons | Tested | 27 attachments over six mounts, drawn on the first-person and third-person gun at mount points found from each model's shape (captures loot3/loot4); other players see them (`observer_attachments`: 5 of 5 drawn from the replicated mask) |
| Attachment effects | Tested | `att_*` checks: 4x zoom, aim time x1.06 with 4x + angled grip, vertical kick 1.68 -> 1.34 (compensator) -> 1.14 deg (+ vertical grip), hip spread 2.40 -> 1.56 deg (laser), magazine 30 -> 40, reload 2.50 -> 1.75 s, suppressor loudness x0.30 / flash x0.10 / suppressed sound, choke pattern x0.65 |
| Scopes like PUBG (1x, 2x, 3x, 4x, 6x, 8x) | Tested | Red dot 0.4 px and holographic 0.9 px from where the bullets go while aiming; 4x and 6x scope views with field of view 20.0 / 13.3 deg and the gun hidden; reticles: dot, holo ring, 2x circle-dot, 3x chevron, 4x ACOG ladder, 6x mil-dot, 8x duplex |
| More guns | Tested (captures) | Double-barrel shotgun (break action, both barrels reload together: `break_action_reload`), the sumpak (improvised 12-gauge) and a .308 marksman rifle, modelled in code |
| Guns held the right way | Fixed | The Poly Haven 9 mm pistol and bolt rifle are modelled along x: the pistol was held sideways and the rifle stood on end on the ground; both now point forward (t23 `gun_pistol_9`, loot lineup) |''')
rep('''## Health, bodies, looting

| Requirement | Status | Evidence / notes |
|---|---|---|''', '''## Health, bodies, looting

| Requirement | Status | Evidence / notes |
|---|---|---|
| Every drop has a real model | Tested | `loot_models_census`: 59 droppable ids, no placeholder boxes. New models made in code (tools/blender/make_loot_models.py): 25 attachments, battery, bandage, painkillers, splint, two backpacks, eight calibre-labelled ammunition boxes, three guns, eight loot boxes with open lids |
| Loot scattered across the map | Tested | 6,574–6,641 items on the ground at the start (about 1,100 guns, 2,500 ammunition stacks, 1,200 attachments); a gun found loose usually has its ammunition beside it |
| Loot boxes, many, mostly in houses | Tested | 3,832 loot boxes (3,737 inside buildings, for 2,072 houses, shops and apartments): balikbayan boxes, storage bins, footlockers, rifle cases, iceboxes, toolboxes, ammo cans, first aid cases; Use opens the contents on the SmarTab and the lid opens for everyone; late joiners get the opened lids |
| Items rest on what is under them | Tested | `floor_items_rest`: 941 of 941 sampled items 0-5 cm above a surface (each item settles on the surface under it when the match is set up; spots with nothing solid under them get no loot) |
| Picking up fits attachments; ammunition named for your gun | Tested | `pickup_fits_scope`, `pickup_ammo_named`, `gun_takes_bag_attachments`; SmarTab Weapons page with Fit / Off per mount |''')
rep('''| Arm themselves and fight | Incomplete | Guns are rare in household loot and bots search slowly; bot-only matches mostly end in the zone |''',
    '''| Loot what they need | Tested | `[lootstats]` (run5, 40 bots): 89-95% of armed bots carry ammunition for their gun (18 of 19 at 120 s), 0 rounds of unusable ammunition carried, attachments fitted by bots, 60+ loose items picked up on detours. Bots value a gun first, then its ammunition, attachments that improve it, armour, a bigger bag, medicine and batteries |
| Arm themselves and fight | Incomplete | About half of 40 bots are armed after 2-4 minutes; 5-8 bots at a time are stuck in river channels and many door approaches fail (bot navigation, not loot); bot-only matches mostly end in the zone (run5: 34 shots in 389 s) |''')
rep('''## Known limitations
''', '''## Known limitations

- The loot models are made in code: clean but simple next to the processed photo-scanned guns. There is no PUBG
  capture on this machine to compare the scope views or attachments against, so that comparison is not done.
- Frame cost of the loot: ''' + perf_row + '''
''')
rep('''- The holographic sight model carries a manufacturer's logo in its texture.''',
    '''- The red dot and holographic sights are now made in code (the downloaded holographic sight carried a
  manufacturer's logo and is no longer used); the 4x prism scope is still the processed download.''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())
print('ok')
