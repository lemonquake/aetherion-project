| Component | Pass | Artifact revision | Evidence / reviewer ID | Winner / clear advantage | Verdict | Primary defect ID | Used budget / context | Next state |
|---|---|---|---|---|---|---|---|---|
| C2 models | 1 | make_loot_models.py first build | work/loot_models/sheet_all.png (self-check) | n/a (no benchmark capture) | REJECT (self) | text mirrored on side faces | 1/8 | fix UV direction |
| C2 models | 2 | + side_h UVs, boolean ports, bandage/backpack fixes | sheet_all.png, sheet_fix.png | n/a | accepted for integration (self-check) | - | 2/8 | integrate |
| C2 models | 3 | + clear red-dot/holo glass, closed tube | loot2/loot3 ADS captures | n/a | accepted (self-check) | red-dot lens opaque red (loot1) | 3/8 | done |
| C3 scatter | 1 | p45/p46 | loot1 floor_items_rest 917/941 | n/a | REJECT (invariant 2) | items under stair steps / over gaps | 1/8 | snap spots |
| C3 scatter | 2 | p57 spot snapping | loot2 929/949, loot3 933/940 | n/a | REJECT (invariant 2 strict) | jitter moves items off the snapped surface | 2/8 | snap each item |
| C3 scatter | 3 | p61 per-item snapping | loot4 941/941 | n/a | PASS (invariants 1-4) | - | 3/8 | done |
| C4 attachments | 1 | p49/p50 | loot1: att_* 10/10, reddot 0.1 px, holo 0.8 px, scope views | n/a | PASS (mechanics); visuals self-checked | - | 1/8 | lit captures in loot3 |
| C4 orientation | 1 | p57 | t23 gun_pistol_9, loot3 lineup | n/a | PASS | Poly Haven guns sideways (pre-existing) | 1/8 | done |
| C5 bots | 1 | p48 | run1 lootstats | n/a | REJECT | bots fetch far low-value loot, 34-79 unusable rounds | 1/8 | tune |
| C5 bots | 2 | p52/p55 | run2 trace (fetch stall at 6 m for 40 s) | n/a | REJECT | fetch unreachable items | 2/8 | LOS + progress |
| C5 bots | 3 | p58/p60 | run4 trace, run5 lootstats | n/a | PASS invariant 7 (18/19 armed carry ammo at 120 s; 0 unusable rounds) | largest gap: ~50% of bots armed by 4 min; 5-8 bots stuck in river channels (pre-existing navigation) | 3/8 | follow-up outside loot scope |
| C6 pickup/UI | 1 | p47/p53 | loot1-4 pickup_* checks | n/a | PASS | - | 1/8 | done |
| C7 integration | 1 | all patches | tour t23 26/26; loot4 29/29; net 13/14 (test bug: collider .name) | n/a | REJECT | net test reads .name from node-less item body | 1/8 | fix test, rerun |

Independent blind review: not run (subagents are not permitted in this session without an explicit user request);
all reviews above are labeled self-checks. Commercial (PUBG) benchmark captures: none on disk, gate UNVERIFIED.

Baseline: git stash a79f58b8 (tracked files) + copy of game/src, game/data, project.godot in baseline/. Baseline perf: perf_before/log.txt.
| C7 integration | 2 | p61-p67 | loot_exe2 29/29 exit 0; t26_exe 26/26 exit 0; net 14/14; perf_attrib loot 0.9 ms | n/a | PASS (component/integration gates on this PC) | quit crash 0xC0000374 found and fixed (p67 dispose on tree exit) | 2/8 | builds done |
