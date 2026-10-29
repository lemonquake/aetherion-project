# r6 run (2026-10-28) — handoff

Status: **IMPLEMENTED — mostly VERIFIED on PC and the phone profile** for bob, blood, SmarTab and sound coverage/timing;
**UNVERIFIED**: sounds by ear, any commercial benchmark or blind critic review, real phones, the Vulkan APK on a device.
Revision: working tree on `master` (uncommitted; r4, r5 and r6 all uncommitted on top of 5f35ddf). Version 0.7.0.
Rollback: r5's baseline copy in `../r5/baseline/`; patch scripts `tools/patches/r6_*.py`.

**r5 was not finished** (no r5 handoff existed). Still open from its contract: first-person arms (open sleeve cuffs on
the pistol, a large arm when racking a slide, grey untextured arms when downed — seen in `gates/r4/19_realism_firing.png`),
the map sweep (`../r5/mapscan/dbg4.log`: 12 of 16 checks failing), gun models/animations review, ragdolls (2 of 34
bodies float 3.5 cm), builds. r6 only lowered the left shoulder's rifle stance (the sleeve dome in the corner).

## What changed

| Area | Files |
|---|---|
| Walk/run bob x0.5 | `player/player_controller.gd` (`GAIT_BOB`), `player/viewmodel.gd` (gun bob) |
| Sounds | `tools/build_r6_sounds.py` (fetch / events / build), `assets/audio/r6/*.wav` + `CREDITS.json`, `data/sounds.json`; reload steps as cues in `player/weapon_anims.gd` (`CUES`, `cues()`, `clip_name()`), played by `player/viewmodel.gd`; others' reloads: `match/world.gd` `_reload_sounds` -> `_ev_clip` -> `fx/effects.gd` `gun_cues`; material sounds `MAT_SOUND`, helmet/vest, shotgun shells, body falls (`corpse.gd` -> `effects.body_fell`), weapon draw |
| Blood | `tools/make_blood_textures.py` -> `assets/fx/blood_*.png`; `fx/blood.gd` (extends `fx/holes.gd`, which gained `place_xf` / `set_mark_xf`); `fx/effects.gd` (body hits, corpse hits); `props/corpse.gd` (`_bleed_out` pool on settle); `match/world.gd` (corpse impacts carry -dir); `fx/particles.gd` (finer blood mist) |
| Cards hidden behind collision | blood and hole shaders pull vertices 6 cm toward the eye along the view ray |
| SmarTab | `player/viewmodel.gd` (device/screen x2, hand placement, `test_hide_arms`), `player/fp_arms.gd` (`tablet` grip), `ui/smartab_ui.gd` (`MIN_TEXT`, shorter ammo line), `ui/settings_ui.gd` (text slider to 2.0) |
| Tests | `debug/autotest_r6.gd` (`--autotest=r6`), `audio/sound_system.gd` (`trace`), `debug/autotest_r4.gd` (screen-rect scaling fix) |
| Docs | README (blood, sounds, r6 tests, rebuild commands), docs/ASSET_MANIFEST.md (133 sound credits + blood atlas), docs/CHECKLIST.md |

## Evidence

- Final revision: `gates2/r6d.log` 20/20 (bob 0.028/0.018 m vs 0.050/0.036; reload steps in order; bot reload heard;
  SmarTab 61 % of view, 0 arm pixels on screen; blood 0.52 % of view, wall 892 px, feet 369 px, drip trail 10, pool,
  corpse 71 marks, 0.61 ms per hit), `gates2/r6_phone.log` 9/9 (Mobile renderer, phone profile),
  `gates2/tour.log` 26/26, `gates2/fixes_grab.log` 8/8 (grab, work sounds used).
- First batch (`gates/`, same session, before the SmarTab/test fixes): r3 19/19, net 17/17, fixes 24/26, r4 18/21, r5 8/9.
- Known failing: r4 `holes_wall` (holes visible in `gates2/r4/06_holes_after_wood.png`, but < 2.5 luma on dark wood),
  r4 `suppression` (flaky), r5 `ragdoll_mesh_touches_ground` (r5).
- Captures: `r6f/sheet.png` (blood), `smartab_before_after.png`, `snd/all_takes.png` (every sound take's waveform),
  `snd/mech_sheet.png` (how the reload recordings were cut).

## Largest remaining gaps

1. Nobody has listened to the new sounds; selection was by licence, popularity, waveform and spectrum only.
2. CC BY sounds (12) need in-game credits before release (only in docs/ASSET_MANIFEST.md now).
3. r5's open components (above).
4. Builds (rebuilt after the run, `build/`, `exe/`): EXE 1.29 GB, r6 14/14 and exit code 0 (`exe/r6.log`); both APKs
   416 MB, versionCode 7; the OpenGL APK opened the menu and started a practice match on the emulator
   (`build/emu_menu.png`, `build/emu_match.png`), map #49929ca0 as on PC. Old EXE kept as
   `builds/windows/Aetherion-0.6.0.exe`. Build script: `work/lemondev/r6/build_all.sh`.

## Commands

    godot --path game -- --host --bots=11 --autostart=1 --autotest=r6 --shots=<dir> [--r6_only=sounds,bob,cues,smartab,blood] [--r6_fast=1]
    python -I tools/build_r6_sounds.py fetch | events <id> | build      (then bash tools/import.sh)
    python -I tools/make_blood_textures.py --preview work/blood_preview.png
    bash work/lemondev/r6/run_gates.sh ; bash work/lemondev/r6/run_gates2.sh
