# r4 run (2026-10-27) — handoff

Status: **IMPLEMENTED — mostly VERIFIED on PC and the phone layout; frame-time A/B, real phones and the voice by ear
UNVERIFIED; outfits STOPPED — PLATEAU at review pass 2 (artifacts fixed afterwards, not re-reviewed).**
Revision: working tree on `master` (uncommitted, on top of 5f35ddf), game version 0.6.0. Rollback point: commit
5f35ddf (clean tree at the start of the run). Patch scripts: `tools/patches/r4_*.py`.

## What changed

| Area | Files |
|---|---|
| Particles | `fx/particles.gd` (pooled GPU particles, 21 kinds, warmed at load), `fx/effects.gd` (impacts, muzzle smoke, casings, explosion, chunk and panel debris, suppression hook) |
| Bullet holes | `fx/holes.gd` (MultiMesh cards, attached to doors/props), `tools/make_impact_textures.py` → `assets/fx/holes_*.png`, `fx_*.png`; impacts carry material + what they hang on (`weapons/projectile_server.gd`, `match/world.gd`) |
| Destruction | `world/destruct.gd` (chunk cutting, door panels), `props/physics_prop.gd`, `world/door.gd`, `world/dynamics.gd`, `world/map_builder.gd` (`server_blast`, late-join sync), `weapons/grenades.gd` (blast now hits props and doors; the old loop never matched a body) |
| Loudspeakers | `audio/announcer.gd`, `world/pa_system.gd`, `world/day_cycle.gd` (`next_change`), `ui/hud.gd` (countdown), `tools/make_announcer.py` → `assets/audio/announcer/` |
| Menu, lobby, online | `ui/main_menu.gd`, `ui/lobby_ui.gd`, `ui/locker.gd`, `ui/menu_bg.gd`, `ui/icons.gd`, `ui/ui_theme.gd`, `ui/settings_ui.gd` (Online tab), `online/profile.gd`, `online/online.gd`, `online/master_server.gd`, `net/net.gd` (teams × squad size, looks, profiles), `core/game.gd` (bots fill slots, XP, `--master`/`--stats`), `match/match_server.gd` (damage, place), `tools/make_ui_textures.py`, key art `assets/ui/*_bg.jpg` |
| Outfits | `tools/blender/make_gear.py` → `assets/models/gear/gear.glb`, `tools/make_gear_textures.py`, `data/cosmetics.json`, `player/outfit.gd`, `player/character_visual.gd` |
| Realism / speed | casings (`tools/add_r4_sounds.py`), suppression (`ui/hud.gd`, `player/player_controller.gd`), cached sound paths (`audio/sound_system.gd`), 2 draw surfaces per character |
| Tests and tools | `debug/autotest_r4.gd`, `debug/ui_tour.gd`, `tools/online_test.sh`, `tools/outfit_lineup.tscn`, `tools/blender/render_gear.py`, `tools/gear_contact_sheet.py` |

## Evidence (logs and captures under `work/lemondev/r4/`)

- Loudspeakers: `pa3.log` / `final/r4.log` — both schedules 15/15 cues on time, each heard from a horn.
- Effects and destruction: `final/r4.log`, `final/r4b.log` (+ captures in the same-named folders).
- Online: `final/online.log` 5/5 (presence, open game, join, XP 508 each, leaderboard, saved).
- UI: `ui/t2` (1920×1080 and 3840×2160), `ui/t5` (phone layout) — no control off screen.
- Regressions: `final/r3.log` 19/19, `final/tour.log` 26/26, `final/net.log` 17/17, `final/fixes.log` 24/26 in
  the full run (`use_takes_items` and one stair flight, both landing-spot dependent) and 8/8 on the re-run
  (`final/fixes_b.log`: 24/24 flights, items taken with E).
- r4 re-run (`final/r4b.log`) 15/17: the two misses were test framing (the wall shot framed a bench; the near-miss
  round hit a wall first; the second check now looks for a clear line).
- Builds (all from the final game revision): `builds/windows/Aetherion.exe` (1.18 GB) passes `--autotest=r4`
  outfits/loudspeakers/chunks/doors/blast 15/15 (`exe/r4.log`), no crash at exit. `builds/android/Aetherion.apk`
  and `Aetherion-opengl.apk` (376 MB each; contain the gear model and ETC2 texture arrays, the new scripts and
  audio): the OpenGL APK installed on the `aetherion_test` emulator and showed the new menu (`emu_menu.png`).
- Benchmark: `final/perf.log` (19 bots, editor, CPU at 100% from other work: not comparable with 0.5.0).
- Blind reviews: `critic/packet` (what reviewers saw), `critic/MAPPING_private.json` (labels).
  - Menus/lobby vs 0.5.0: new won, clear advantage. Gap: large empty areas, orphaned fifth team card (cards centred
    afterwards).
  - Characters vs 0.5.0, pass 1: new won, clear advantage; mandatory "no broken-looking geometry" borderline →
    REJECT (holes under shirts, jagged open fronts, skin tone, boot shafts).
  - Pass 2: new won, clear advantage; mandatory FAIL on boot shafts / ankle rings → same area as pass 1 →
    **plateau stop**. Fixed afterwards (boot shafts made from the leg's shape, rings removed, a catalogue bug that
    had dropped the new shafts); result `critic/old/lineup_new7.png`, not reviewed again.

## Not verified / largest remaining gaps

1. Frame-time A/B against 0.5.0 (machine loaded by other jobs; no 0.5.0 build kept). Draw surfaces per character
   fell from 8 to 2; impacts cost ≤0.4 ms GPU at one per frame.
2. Outfits: low-poly hair caps; the face texture is darker than the hands (bare skin is the average); open-front
   shirts are straight cuts; no first-person sleeves/gloves on the viewmodel arms.
3. Stats server has no accounts or anti-cheat; the speech is Windows TTS output (check its licence before a
   commercial release).
4. Cabinets, beds and other static furniture are not destructible; glass props still shatter whole.
5. Real phones, 28 human players, the Join button clicked by a script.
6. FIXED after the builds: on the OpenGL fallback the night sky's reflection (cubemap) pass failed to compile
   (0.5.0 bug: `day_sky()` read `AT_CUBEMAP_PASS`, which GLES3 defines only inside `sky()`; it is now passed in as a
   parameter). PC OpenGL run: 31 error lines before (`sky_old_gl.log`), none after (`sky_gl_compatibility.log`);
   Vulkan still clean (`sky_forward_plus.log`). The EXE and APKs in `builds/` predate this fix; re-export them to
   ship it. Outfits render on the OpenGL renderer (`lineup_gl.png`); the emulator reached a night match
   (`emu_ground.png`).

## Commands

    godot --path game -- --host --bots=11 --autostart=1 --autotest=r4 --shots=<dir>      [--r4_only=...]
    bash tools/online_test.sh
    godot --path game -- --ui_tour=<dir> --ui_sizes=1920x1080,3840x2160
    godot --path game -- --mobile --ui_tour=<dir> --ui_sizes=1800x810
    godot --path game res://tools/outfit_lineup.tscn -- --mode=new --out=<png>
    godot --headless --path game -- --master --data=<dir>
