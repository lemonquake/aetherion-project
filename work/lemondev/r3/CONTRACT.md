# Run r3 — "big polish" (2026-10-27)

User request (verbatim intent): artificial-sun day/night loop (5 min night, 5 min day); a much richer slum map with
intent (covered tunnel pathways like the Sleep warren, 3rd floors, rooftops, side ladders, vault boxes and vault
windows, vandalism, eerie, dirty, rusty, lights in covered paths that force flashlights even by day); default 20
bots and 40–50 player matches with performance first (mobile first); horizontal compass with numbers under the
minimap; radio voice that nearby players can overhear, with key clicks; build EXE + APK; delete temp files.

Engine / platform: Godot 4.7.2, Forward+ (PC) and Mobile renderer (Android, Vulkan / GL). Test PC RTX 4060.
Baseline / rollback: `work/lemondev/r3/baseline/` (src, data, project.godot copied before any change). Version 0.4.0 → 0.5.0.
Budget: 8 build/review passes per component.

## Components

| ID | Artifact / files | Acceptance (frozen before candidates) |
|---|---|---|
| C1 day cycle | `world/lighting.gd`, `world/night_sky.gdshader`, `match/world.gd` (time), HUD notice | Same view captured at night and at midday: midday mean luma clearly higher (>2.5x); a covered tunnel and a closed room stay dark at midday (luma < 30% of the open lane); cycle 300 s night / 300 s day from match start, same on every machine (driven by the server tick); phone path keeps interiors and tunnels unlit by the sun without shadow maps |
| C2 map | `world/districts.gd`, `world/shanty.gd`, new `world/lagusan.gd` (tunnels), `world/rooftops.gd`, `world/vandal.gd`, `tools/make_vandal_atlas.py` | Counted in the build: tunnels with roofs and lamps, 3-storey houses, walkable roof decks reachable by ladder or crate stacks, ladders, vault crate clusters and vault windows, decals per building; player-view captures by day and night; existing checks (`--autotest=fixes` stairs/doors/vault/loot) still pass |
| C3 ladders | `player/motor.gd`, `player/ladder.gd`, map ladder registry | A scripted player climbs a ladder to a roof and climbs down again; prediction matches the server (net test) |
| C4 compass | `ui/compass.gd`, `ui/hud.gd` | Visible under the minimap at 1600×900, 1920×1080, 3840×2160 and the phone profile; centre number equals the camera bearing (0 = north, clockwise) within 1° |
| C5 radio voice | `audio/voice.gd`, `core/game.gd`, `net/net.gd`, rules | Teammates hear the speaker through a radio filter with key-up and key-down clicks; a non-teammate within the eavesdrop radius of the speaker or of a teammate's radio receives the voice positionally from that radio; one beyond it receives nothing (net test with three clients) |
| C6 scale | `net/net.gd` config, `data/rules.json`, lobby, perf | Default 20 bots; lobby up to 50; 49-bot host and phone-profile frame times measured and recorded; server tick measured with 49 bots |
| C7 release | builds/windows, builds/android | Both built from the final revision, EXE play-through passes, APK installs/starts on the emulator; temp files removed |

Benchmark for C2/C1 visuals: the user's own Sleep project captures (`A:\3rd Harmonik\interior\docs\canal\*.png`,
`docs\warren-v18\*.png`) — the user named it as the reference ("just like my interior (Sleep) project"). Compared by a
fresh-context critic on neutral A/B packets. Mechanics are judged by the automated checks, not by the critic.

Deviation from the original brief (§7), at the user's request: radio speech is now audible to anyone near a keyed or
receiving radio (eavesdropping), not only the click. Range is a rule (`rules.json` radio.eavesdrop_radius).
