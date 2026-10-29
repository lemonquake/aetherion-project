# r5 run (2026-10-28) — component contract

User request (verbatim intent): GRAND improvements to (1) first-person arms/hands from an actual human or downloaded
3D models, (2) reload animation and gun animation for every gun, (3) sweep the whole map for unpathable doors and
doorways blocked by objects, invisible walls by day (see-through walls) and other inconsistencies, (4) death physics:
bodies glitch into the ground, (5) legit 3D models for the ugly guns, (6) build EXE and APK.

Baseline: working tree at r4 end (0.6.0), copy of src/data/project.godot in `work/lemondev/r5/baseline/`.
Engine: Godot 4.7.2 (Forward+ PC, Mobile/OpenGL phones). Version will go to 0.7.0 (models and map change).
Budget: at most 8 build/review passes per component; plateau rule as in lemondev/SKILL.md.

## Components (one owner each)

| ID | Component | Files owned | Acceptance (measured) |
|---|---|---|---|
| G | Gun models | `tools/blender/process_items.py`, `tools/asset_sources.json`, `game/assets/models/items/*`, `game/assets/models/weapons/*` (new), dresser ITEM_MODELS | Every one of the 24 guns is a downloaded CC0/CC-BY model (no code-built or decimated-to-mush guns); side renders sheet shows no broken geometry; each gun has its moving parts (magazine / slide or bolt / pump / cylinder / break) as separate meshes with pivots in `weapon_parts.json`; triangles ≤ budget; credits in source.json + ASSET_MANIFEST |
| A | First-person arms | `game/assets/models/fp_arms/*` (new), `src/player/viewmodel.gd` arm code | Arms are a skinned human mesh with 5 jointed fingers per hand (downloaded, CC0/CC-BY), sleeves; hands wrap the grip/handguard in captures for every gun class; no stretched or broken limbs at hip, ADS, sprint, TAB device |
| N | Gun animations | `src/player/viewmodel.gd`, `src/player/weapon_anims.gd` (new), `src/player/character_visual.gd` (third-person reload pose only) | Every gun has a reload sequence matching its feed (mag swap, empty adds bolt/slide release, tube shell-by-shell, cylinder, break-open, belt box, bolt-action stripper/rounds) with the timing equal to the gun's reload_time; fire animation (recoil + slide/bolt cycling, pump/bolt cycling between shots for manual actions); draw and inspect-free idle sway; captured frame strips per gun show parts moving and hands on the parts |
| C | Death physics | `src/props/corpse.gd`, corpse functions in `src/world/dynamics.gd` | Dead bodies keep the real character mesh (outfit) driven by the ragdoll; in N≥30 scripted deaths (open ground, house floor, upper floor, stairs, crouched, downed, near walls) no part ends below the surface under it by >3 cm and nothing jitters after settle; client pose matches server |
| M | Map sweep | `src/world/*.gd` except dresser ITEM_MODELS | Scripted scan of every door and doorway: clear passage (character capsule sweep) with nothing blocking; scan for faces visible from only one side by day (see-through walls) and fixed; list of other inconsistencies found and fixed with before/after captures; `--autotest=fixes` and `--autotest=r3` still pass |
| B | Builds | `builds/` | EXE and both APKs exported from the final revision; EXE runs an autotest and exits cleanly; OpenGL APK starts on the emulator |

## Benchmarks (references)

No commercial captures are on disk. Benchmark for G/A/N is the previous revision (r4) plus a commercial-style
standard described in words to the Critic (hands visibly wrapping the weapon, magazine leaves the gun and a new one
goes in, fingers articulated). This is not commercial evidence; the commercial A/B gate stays UNVERIFIED.

## Integration gate

`--autotest=fixes`, `--autotest=r3`, `--autotest=r4`, `--autotest=tour`, `bash tools/net_test.sh`, a 20-bot match,
phone profile check, OpenGL renderer check, then builds.
