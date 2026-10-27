# Handoff: loot run 2026-10-26

Status: IMPLEMENTED — UNVERIFIED (commercial benchmark and independent review gates not run; component and
integration checks pass on this machine; phone not measured)

Scope and revision: working tree on top of eba1a8f (uncommitted), game version 0.3.0, patches
tools/patches/p42-p67 plus new files listed below. Builds from the final revision: builds/windows/Aetherion.exe
(1.12 GB, 23:01), builds/android/Aetherion.apk (343 MB, 23:05), builds/android/Aetherion-opengl.apk (23:06).
The APKs were not run on a device or emulator this session.

## What changed and where

- Models (made in code): tools/make_loot_textures.py, tools/blender/make_loot_models.py -> game/assets/models/loot/
  (25 attachments, battery, bandage, painkillers, splint, 2 backpacks, 8 ammunition boxes, double-barrel shotgun,
  sumpak, .308 marksman rifle, 8 loot boxes + open-lid variants). Check renders: work/loot_models/.
- Data: game/data/weapons.json (27 attachments with effects, 12 weapons with compatibility, mag_ext, hold, value),
  items.json (attachments come from weapons.json), loot.json (24 tables incl. box_* and floor_street; weapon_ammo).
- Engine: src/weapons/attachments.gd, attach_visual.gd; weapon_state.gd (effects, break action); viewmodel.gd and
  character_visual.gd (attachments drawn, ADS on the sight, laser dot); src/ui/scope_overlay.gd, reticle.gd;
  dynamics.gd (node-less ground items, loot boxes, surface snapping, dispose); dresser.gd / sites.gd /
  street_dress.gd (placement); interaction.gd (auto-fit, wanted-only bot taking, box lids); smartab_ui.gd (Weapons
  page); hud.gd (prompts); effects.gd + tools/build_audio.py --suppressed (suppressed shots); snapshot.gd /
  character.gd / world.gd (attachment mask replication, item deltas for late joiners, box lid events).
- Bots: src/ai/loot_sense.gd, bot_brain.gd (detours to seen items, fetch site boxes and street loot, junk dropping,
  range-based gun choice, idle reload), match_server.gd ([lootstats]).
- Tests: src/debug/autotest.gd --autotest=loot (29-30 checks), perf "loot" toggle; autotest_net.gd fix.
- Fixed in passing: Poly Haven guns held sideways; hidden MultiMesh instances stretching cell bounds; RIDs leaked
  on match teardown.

## Gate results

| Gate | Result | Evidence |
|---|---|---|
| Compile | 67 scripts, 0 failed | tools/check.sh |
| Loot play-through (editor, before p63/p64) | 29/29 | work/screens/loot4 |
| Loot play-through on the exported EXE (final revision) | 29/29, exit 0 | work/screens/loot_exe2/results.json |
| Tour regression on the exported EXE (final revision) | 26/26, exit 0 (one earlier run with two games at once: team_cluster 73.5 m > 60 m) | work/screens/t26_exe, t25_exe |
| Quit crash found during integration | Fixed: EXE exited 0xC0000374 while ground-item render instances were alive at quit; map now frees them on tree exit | loot_exe (crash) vs loot_exe2 (clean) |
| Network (server + 2 clients) | 14/14 | work/screens/net |
| Bot match, 40 bots | ammo for gun 89-95% of armed bots, 0 unusable rounds, winner at 389 s | botmatch/run5.log |
| Performance | loot = ~0.9 ms at densest spot; fixed spots within +-10% of baseline | perf_before, perf_after2, perf_attrib |
| Commercial benchmark (PUBG) | UNVERIFIED: no reference captures on disk | - |
| Independent blind review | UNVERIFIED: no subagents without an explicit request; self-checks only | ledger.md |
| Phone | UNVERIFIED: not run on a device | - |

## Largest remaining gap

Bots arm slowly (about half of 40 bots armed after 2-4 minutes): 5-8 bots at a time are stuck in river channels and
many door approaches fail. This is bot navigation, outside the loot components.

## Next action to resume

Bot navigation: a way out of river channels (nearest bank with a walkable exit) and door approach retries; then
re-run a 40-bot match and compare the [lootstats] armed share.
