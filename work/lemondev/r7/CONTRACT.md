# r7 run (2026-10-28) — component contract

User request (intent): the current mode becomes CLASSIC (battle royale: parachute in, loot weapons, survive the haze,
5-minute day/night). Add DEATHMATCH: team vs team, exactly 2 teams of up to 10 (bots fill). Game Setup asks each
player for a primary and a secondary gun; everyone starts with armour and a full plate helmet. No buying; players can
loot buildings and swap weapons. Dead players wait (spectate) until their team wins or is wiped out; the team that
eliminates the other wins. The haze still shrinks; day/night still changes every 5 minutes. New large map "Lawless
Sub" built from the user's top-down image: a subdivision whose houses have real interiors and vaultable windows, plus
big buildings (convenience store, factory, ...), following every existing map rule (physics props, destructible doors
and props, loot, acoustics). Download more models and real textures. 100+ fps on PC and mobile builds (200+ on high-end
PCs). Build the EXE and the APK.

Baseline: working tree at the end of r6 (uncommitted r4-r6 on top of 5f35ddf); source copy in `baseline/`.
Engine: Godot 4.7.2. Version 0.7.0 -> 0.8.0 (new modes, map and net messages). Budget: at most 8 build/review passes
per component. Design: `MAP_DESIGN.md`.

## Shared interfaces (frozen before building)

- `Net.config.game_mode`: `"classic"` (default) or `"deathmatch"`. `Net.config.map`: `"kalinaw"` or `"lawless_sub"`
  (classic -> kalinaw, deathmatch -> lawless_sub). Deathmatch forces `teams = 2`, `team_size` 1..10 (default 10).
  The existing `mode` key (solo/duo/squad) keeps its meaning for Classic.
- `Net.players[pid].loadout = {"primary": id, "secondary": id}`; clients send theirs with an RPC; the server
  validates against `rules.deathmatch.primary` / `.secondary` and falls back to the defaults; bots get random picks.
- `data/rules.json` `deathmatch` block: teams, team_size, primary/secondary lists and defaults, spare mags, gear
  (`vest_heavy` Plate Carrier, `helmet_heavy` Heavy-Plate Helmet), extras, `downed: false`, zone phases and centre
  jitter, day start.
- `MapBuilder.build(world, map_seed, match_seed, {"map": id})`; the Lawless Sub layout exposes the same members
  the rest of the game reads from `map.layout` (in_play_area, is_water, ground_height, water_height, PLAY_HALF, HALF,
  MAP_SCALE, roads, districts, sites, landmarks, ...) plus `spawns[team] -> Array[Vector3]` and
  `spawn_yaw[team]`.
- Match state broadcast gains `alive: {team: count}` and `game_mode`; Deathmatch spectating cycles teammates.

## Components

| ID | Component | Owner files | Acceptance (measured) |
|---|---|---|---|
| M | Modes + Game Setup | `ui/main_menu.gd`, `ui/lobby_ui.gd`, new `ui/game_setup.gd`, `online/profile.gd`, `net/net.gd`, `core/game.gd`, `online/online.gd` | Menu offers CLASSIC and DEATHMATCH with plain descriptions (Classic mentions parachute, looting, survival, day/night); Deathmatch lobby shows 2 teams x 10 and a Game Setup with primary and secondary pickers; choice persists; reaches the server (`loadout_received`); `--game_mode=deathmatch` works headless; UI readable at 1920x1080, 3840x2160 and the phone profile |
| R | Deathmatch rules | `match/match_server.gd`, `match/world.gd`, `ui/hud.gd`, `world/day_cycle.gd`, `player/health.gd` (downed rule only) | Everyone spawns on the ground at their team's spawn, armed with their picks + spare mags, plate carrier and heavy helmet on; no plane, no downed state; dead players spectate living teammates (cycle); round ends when one team has nobody standing -> results -> lobby; haze shrinks on the DM schedule; day/night offset synced; HUD shows alive counts per team |
| S | Lawless Sub map | new `world/maps/` (layout + builder + suburban house + big buildings), `world/map_builder.gd` (dispatch), `world/layout.gd` (only what a second layout needs), `world/materials.gd`, `world/model_lib.gd`, `world/dresser.gd` (new room types) | Builds deterministically (same fingerprint twice, PC == Mobile renderer); >= 120 houses with interiors (sala, kitchen, bedrooms, toilet, stairs); convenience store, factory, office tower, clubhouse + pool + court, chapel, gas station, shophouses, guardhouse gate; canal + basin + estero with crossings; roads with lane markings, zebra crossings, parking stalls; every ground-floor window vault-sized; doors/props/loot/acoustics registered; spawns clear of geometry; map scan (`mapscan`) finds no stuck spots at spawns; top-down capture reads like the reference layout |
| A | Downloaded assets | `tools/fetch_r7.py`, new processing script, `assets/models/r7/`, Poly Haven folders, docs/ASSET_MANIFEST.md, in-game credits list | Every asset CC0 or CC-BY with source.json; CC-BY credited; processed models at real scale with collision and <= budgeted triangles; used in the map |
| B | Deathmatch bots | `ai/bot_brain.gd` | Bots spawn armed, move toward the enemy/zone in groups, fight, stay in the zone, loot only when useful; a 10 v 10 bot round ends with a winner in < 10 minutes in 3 of 3 seeds |
| P | Performance | settings/view LOD/map budgets as needed | This PC (RTX 4060, Ryzen 7 5700X), 1600x900, vsync off, 20 players: High preset median >= 200 fps and p99 frame <= 10 ms on the ground; phone profile (Mobile renderer, `--mobile`) median >= 100 fps and p99 <= 12 ms; Classic not slower than baseline beyond noise. Real phone: UNVERIFIED (no device) |
| T | Tests | new `debug/autotest_dm.gd` | `--autotest=dm` checks all of the above that can be measured, with captures |

## Benchmark

Map composition: the user's reference image (`benchmark/lawless_reference.webp`). A fresh critic compares a
top-down capture of Lawless Sub with it under the blind protocol (criterion: a believable, readable urban
subdivision district with canals, a major intersection with zebra crossings, parking lots with stalls, tree-lined
walks and distinct buildings). No commercial reference exists for the mode's mechanics: those are gated by measured
invariants only.

## Integration gate

`--autotest=dm` (PC High, phone profile, gl_compatibility), Classic regression (`tour`, `fixes`, `r3`, `r4`, `r6`,
net test) on one revision; perf phases for both maps; EXE and both APKs built from that revision; the GL APK runs a
Deathmatch round on the emulator with the same map fingerprint as the PC.
