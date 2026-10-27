# Run loot-2026-10-26: weapon, item and attachment drops, loot boxes, scopes, bot looting

Orchestrator record (not part of any critic packet).

## User outcome (2026-10-26)

"Design all Weapon/Item/Attachments 3D model drops that are pickable and scatter and fill the map with them so
players can loot. There will also be Loot boxes, lots and lots of em in the map particularly inside houses. Let the
AI know that they have to loot a weapon, a suitable ammo for the weapon, suitable attachments etc. There will be
attachments of Scopes just like PUBG, and more. do more. then build the game."

Scope exclusions: melee weapons, throwables (grenades), vehicles, new animation rigs. No downloads: every new model is
built procedurally in Blender from code (the user said "design"); existing processed models are kept.

## Engine / platform

Godot 4.7.2, Forward+ on PC and Mobile renderer on phones; RTX 4060 PC at 1600x900 for captures; phone profile
`--mobile --rendering-method mobile`. Cross-play: a map or rules change bumps `application/config/version`.

## Components

| ID | Component | Owner files | Interface |
|---|---|---|---|
| C1 | Data: weapons, attachments, items, loot tables | game/data/weapons.json, items.json, loot.json | Defs.weapons / Defs.attachments / Defs.items / Defs.loot |
| C2 | Procedural models (items, attachments, ammo per calibre, loot boxes, new weapons) | tools/blender/make_loot_models.py, tools/make_loot_labels.py, game/assets/models/loot/ | GLB per id, `<id>.glb`; loot boxes `<id>.glb` + `<id>_open.glb` |
| C3 | Ground loot scatter + loot boxes in houses | game/src/world/dresser.gd, sites.gd, dynamics.gd, map_builder.gd | Dynamics.add_loot_box / add_loot_spot, node-less item bodies |
| C4 | Attachment effects + rendering + scope view | weapon_state.gd, viewmodel.gd, character_visual.gd, reticle.gd, new src/weapons/attachments.gd, new src/ui/scope_overlay.gd | WeaponState queries (zoom, ads_mult, recoil/spread/loudness/mag mults), Attachments.mounts(weapon) |
| C5 | Bot looting intelligence | src/ai/bot_brain.gd, new src/ai/loot_sense.gd, interaction.gd (bot_take_all) | LootSense.value(ch, entry) / wants(ch, entry) |
| C6 | Pickup flow + SmarTab attachment slots + prompts | interaction.gd (give/auto-attach), smartab_ui.gd, hud.gd | inventory requests attach/detach |
| C7 | Integration: tests, captures, perf, builds | src/debug/autotest.gd, docs | `--autotest=tour`, `--autotest=loot`, `--autotest=perf`, bot match log |

## Mandatory invariants (frozen before candidate inspection)

1. Every item id that can drop (every id in any loot table, every attachment, every weapon) has a non-placeholder
   model (no grey BoxMesh fallback): checked by `--autotest=loot` model census, 0 placeholders.
2. Ground items rest on the surface they were placed on (no floating > 3 cm, no sinking below floor) and inside the
   play area: census of rest heights against a down-ray.
3. Loot boxes: at least 1 per furnished house on average across the map, at least 2,000 on the full map; each is a
   searchable container (Use opens it in the SmarTab, the lid opens for everyone, a late joiner sees it opened).
4. Floor loot: weapons, ammo, attachments, meds and gear appear on the ground in houses; count reported by census.
5. Attachments: each attachment kind changes the stated stat in WeaponState (zoom, ADS time, recoil, spread,
   loudness, magazine size, reload time) measured in a headless test; attachments are drawn on the first-person and
   third-person weapon; magnified scopes show a scope view whose reticle centre equals the bullet line (shot direction
   within 0.05 deg of the reticle centre with no recoil).
6. Picking up an attachment mounts it on a compatible weapon when the slot is free or the new one is better.
7. Bots: after looting, a bot with a gun carries ammo for it; bots do not carry ammo for no weapon they hold beyond a
   small allowance; bots mount compatible attachments; measured in a 40-bot headless match log
   (`[lootstats]` line): share of armed bots with matching ammo >= 90% at 120 s.
8. No duplication: an item or container entry taken by one player is gone for all (server authority unchanged).
9. Performance: `--autotest=perf` ground phases stay within 10% of the pre-change baseline measured in the same
   session on the same load (machine is under heavy background CPU load today, so absolute fps are not comparable to
   docs/PERFORMANCE.md).
10. Cold start: `tools/check.sh` 0 failed; `tools/import.sh` imports the new GLBs; exported EXE runs the tour.

## Benchmark

PUBG: Battlegrounds attachment/scope system is the named reference (user's words "just like PUBG"). No PUBG captures
are on this machine and none will be downloaded, so the commercial A/B visual gate is UNVERIFIED for this run. Mechanics
are checked against the invariants above. Any independent review is a defect review of our own captures, not a
commercial comparison.

## Budget

Max 8 build/review passes per component. Baseline revision: working tree on top of eba1a8f (uncommitted changes from
earlier sessions), snapshot taken as `git stash create` hash recorded in ledger.md.
