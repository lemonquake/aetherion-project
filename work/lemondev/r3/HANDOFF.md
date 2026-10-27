# r3 polish run (2026-10-27) — handoff

Status: **IMPLEMENTED — VERIFIED on PC and the phone profile; real phones and 50 human players UNVERIFIED.**
Revision: working tree on `master` (uncommitted), game version 0.5.0. Rollback point: `baseline/` (src, data,
project.godot as they were before this run). Patch scripts used: `patches/`.

## What changed

| Area | Files |
|---|---|
| Artificial sun (5 min night / 5 min day loop, server clock) | `world/day_cycle.gd`, `world/lighting.gd` (sun, sky fill, fog/ambient blend, shadowless-moon dimming), `world/night_sky.gdshader` (day sky, sun disc with ring), `ui/hud.gd` (notices), `ai/bot_brain.gd` (day sight 75 m) |
| Map | `world/lagusan.gd` (roofed lanes and estero arcades), `world/looban.gd` (courtyards, kiosks, crate steps, low walls, sandbags, barricades, yard walls, vacant-lot ruins), `world/vandal.gd` + `tools/make_vandal_atlas.py` (decals), `world/shanty.gd` (covered fronts on the Interior layer, roof decks, front ladders, vault windows, crawl-through holes, wider stair openings), `world/districts.gd` (tunnel runs, loobans, barricades, decks, more 3-storey, lane setbacks), `world/map_builder.gd` (registries, ladder grid, lane splat paint, minimap tunnels, shader warm-up), `world/model_lib.gd` (Sleep kit rubbish materials: were white), `world/ground.gdshader` |
| Ladders | `player/ladder.gd`, `player/motor.gd` |
| Compass | `ui/compass.gd` |
| Radio | `audio/voice.gd`, `audio/sound_system.gd` (Radio bus), `match/world.gd` (`voice_targets`, `radio_sources`, clicks), `core/game.gd`, `net/net.gd` (voice RPC carries source and kind), rules `radio.*` |
| 20 bots, 50 players | `net/net.gd`, `ui/lobby_ui.gd`, `ui/main_menu.gd`, `core/game.gd` (more bot names), rules `max_players` 50 |
| Speed | `player/character_visual.gd` (animation LOD), tunnel lights `no_shadow`, no fog volumes by day, constant sky fill, warm-up |
| Tests | `debug/autotest_r3.gd` (`--autotest=r3`), perf phases (tunnel, day), `debug/autotest_net.gd` (`ladder_predicted`), grab test picks a prop with nothing beside it |

## Evidence (final revision)

- `--autotest=fixes`: 26/26 (`fixes_final.log`). Two map bugs found by it and fixed: stair openings too short for
  second flights (head hit the floor edge), set-back houses overlapping the house behind.
- `--autotest=r3`: 20/20 in the editor (`r3_final.log`), 19/19 on the exported EXE with a clean exit (`exe_r3.log`),
  day/tunnel/ladder/crate/compass also pass on the phone profile.
- Network test: 17/17 (`net_final.log`), including `ladder_predicted` (0 corrections) and voice packets.
- Benchmarks: `perf_*.log`; summary in docs/PERFORMANCE.md (2026-10-27 r3 section).
- Blind review: `critic/` (packet, private mapping). Criterion fixed in advance; reviewer chose the candidate set (B)
  over the owner's Sleep captures (A) with a clear advantage. Its single gap concerned A (benchmark frames too dark
  to navigate). Isolation was by instruction only (shared filesystem); it reported reading only the 16 packet images.
- Android: both APKs built; OpenGL APK installed on the `aetherion_test` emulator, practice match started with 20
  bots, map built in 32 s, fingerprint #1375a694 = PC (`emu_match.png`).

## Not verified / largest remaining gaps

1. Real phone frame rate and a match with 40–50 human players (only 49 bots on one host and 2 human clients tested).
2. Airborne frames cost 1–3 ms more than 0.4.0 on the PC host with 49 bots (cause not isolated).
3. One isolated 160 ms frame on the phone profile (likely first-time particles; the warm-up covers map materials only).
4. Radio speech was never listened to (routing and playback objects tested; no microphone in the tests).
5. Bots do not climb ladders and do not vault; they go round crates, walls and barricades (taken out of their grid).

## Commands

    godot --path game -- --host --bots=20 --autostart=1 --autotest=r3 --shots=<dir>
    godot --path game -- --host --bots=3 --autostart=1 --autotest=fixes --autotest_timeout=1000 --shots=<dir>
    bash tools/net_test.sh
    powershell -ExecutionPolicy Bypass -File tools/perf_exe.ps1 -Exe builds\windows\Aetherion.exe -Tag <tag> -Bots 49
    godot --path game res://tools/map_preview.tscn -- --views=tunnel1,looban2,deck0 --times=0,450 --out=<dir>
