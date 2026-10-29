# r7 run — handoff (session 2, 2026-10-29)

Status: **Deathmatch on Lawless Sub is playable end to end** (menu → lobby with Game Setup → spawn with both guns,
plate carrier and heavy helmet → fight → spectate teammates → results → lobby). Verified on PC (editor build).
**Not done**: the 200 fps target (measured 128–160), phone-profile perf, EXE/APK builds, a blind critique of the map
against the reference image, in-game credits for the new textures.
Revision: working tree on `master`, uncommitted (r4–r7 all on top of 5f35ddf). Session 1 built the modes, menu, DM
rules, assets and the map modules, then stopped before the map was wired in.

## What session 2 changed

| Area | Files |
|---|---|
| Lawless Sub wired in | `world/map_builder.gd` (`_build_sub`, `obstacles_add`, `stall_spots`, `canal_edges`, `_sub_ground`), `match/world.gd` (passes `map`), `world/maps/lawless_sub/sub_layout.gd` (`dump_c`/`dump_r`), `tools/make_road_paint.py` → `maps/lawless_sub/paint.png` |
| Real houses | `maps/lawless_sub/houses.gd` (two-storey, bungalow, shophouse plans through `MapBuilder.house()`; mirrored at random) |
| Big buildings | new `maps/lawless_sub/big_plans.gd` (tower, flats, clubhouse, chapel, mart, strip shops, factory with mezzanine, warehouse, guardhouse/booth; switchback stair cores), `big_buildings.gd` dispatch |
| Furniture | `world/dresser.gd` `_plan_room`, `_aisles`, `_factory_floor` (r7 props: sofas, dining sets, store shelves/chillers, conveyors, forklifts…) |
| Cars | `maps/lawless_sub/sub_dress.gd` uses the 30 downloaded r7 car models (parked) and wrecks |
| Lawns | `world/ground.gdshader` (`lush`), Poly Haven `grass_ground` + `aerial_grass_rock` (CC0, `tools/fetch_r7.py`), `materials.gd` `lawn_leafy` |
| Z-fighting (user report) | `world/building_kit.gd` (frames, wall tops, slabs, posts, plates, patches, stringers, plank floors), `world/house_plan.gd` (`_joint` partition joints, floor finish to clear rect, balcony tiles), `world/geo_sink.gd` (skips identical boxes; face dump), `world/street_dress.gd` (drains), `world/shanty.gd` (roof laps), `world/decal.gdshader` (pull toward the eye), `maps/lawless_sub/sub_works.gd` (one pilaster per corner), `big_buildings.gd` (kiosk floor), `model_lib.gd` (banig) |
| Bots on Lawless | `ai/nav_grid.gd` (walls block, canal edges eroded, estero wadeable at cost 5, no jump-point search there), `ai/bot_brain.gd` (`_escape_water`, `_in_canal`), `player/ladder.gd` (bots with meta `ladder_ok`) |
| User reports | own DM vest visible → `match/world.gd` `_dm_vest_visual` local-body layer; arm cut end → `player/weapon_anims.gd` `_charge` (rifle off the cheek), `player/viewmodel.gd` handgun shoulders; `ui/hud.gd` team label clipped |
| Tests/tools | new `debug/autotest_dm.gd` (`--autotest=dm`), `debug/autotest.gd` (DM perf phases), `tools/zfight_faces.py`, `tools/map_preview.gd` (`--map`, sub views, `room`/`lot` views, `--zfight`, `--dumpfaces`, ortho full-detail), `tools/viewmodel_lab.gd` (`--bones`, sprint frames, frame cap), `match/match_server.gd` (wet bot positions in lootstats) |

## Evidence

- Map: builds in 10–12 s; 256 buildings, 1970 doors, 2518 containers, 2480 props, `#f9b648fc`. Captures `map/p3_sheet.png`
  (buildings and interiors), `map/p6_sheet.png`, `map/p2/sub_top_t450.png`.
- Z-fighting: coplanar overlapping face pairs Lawless 76 233 → 7 554, Kalinaw 168 692 → 30 660 (`zf/*.txt`); the rest
  are small slivers (stair nosings, roof sheets). Kalinaw fingerprint unchanged `#49929ca0` (`zf/fp6.log`).
  Before/after: `map/zfight_before_after.png`.
- Bots: 10 v 10 rounds on seeds 11/22/33 end with a winner in 229–240 s, both teams win (`dm/seed*.log`).
- `--autotest=dm`: 7/7 PASS (`dm/t1.log`, `dm/t2.log`); own body: 10 sampled pixels change when it is hidden.
- Perf (editor build, 1600x900, 20 players, RTX 4060): 128–160 fps, p99 9–13 ms, GPU 2.1–2.5 ms, render CPU ~2 ms;
  CPU/script bound (`perf/sub2.log`).
- Gates (`run_gates.sh`, one revision): Classic tour 26/26, fixes 26/26, r3 19/19 on Sitio Kalinaw; Deathmatch on the
  phone profile (Mobile renderer) 7/7; Deathmatch on PC 6/7 at first, where `dm_no_own_body` counted the body's own
  shadow and the minimap (daytime round). The check now switches shadows and the HUD off for its two frames: 0 pixels
  (`gates/dm_body.log`). r6 18/19: `walk_bob_halved` is flaky at its limit (two identical reruns at the same spot,
  0.034 m against a 0.034 m bound: one PASS, one FAIL; `gates/bob1.log`, `gates/bob2.log`). The gate run's 0.036 m
  sideways came from a walk that drifted 0.3 m sideways (something brushed the player); the bob code was not changed in
  this session. No script errors in any suite.

## Largest remaining gaps

1. 200 fps on high-end PCs: frames are 6.2–7.8 ms with the GPU at ~2.3 ms; profile scripts (`tools/prof_instrument.py`).
2. Phone profile perf and the GL APK on Lawless Sub; EXE and APK builds of this revision.
3. Blind critique of the top-down map against `benchmark/lawless_reference.webp`.
4. Small z-fight slivers left (stair nosing tiles, shophouse neighbours' slab edges, canal lawn ends).
5. The lawn colour is olive (photographed turf); a greener lawn needs another texture or a stronger tint.

## Commands

    godot --path game -- --host --game_mode=deathmatch --bots=19 --autostart=1 --autotest=dm --shots=<dir>
    godot --path game -- --host --game_mode=deathmatch --map=lawless_sub --bots=19 --autostart=1 --autotest=perf --shots=<dir>
    godot --headless --path game -- --server --game_mode=deathmatch --bots=20 --autostart=1 --expect_players=0 --match_seed=11 --quit_after_results=1
    godot --path game res://tools/map_preview.tscn -- --map=lawless_sub --out=<dir> --views=sub_top,sub_houses,in_sala --times=450
    godot --headless --path game res://tools/map_preview.tscn -- [--map=lawless_sub] --dumpfaces=<file> ; python -I tools/zfight_faces.py <file> --verbose
    godot --path game res://tools/viewmodel_lab.tscn -- --out=<dir> --guns=rifle_m416 --look=tee --full --bones
    bash work/lemondev/r7/run_gates.sh
