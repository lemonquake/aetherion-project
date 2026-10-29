# r6 run (2026-10-28) — component contract

User request (verbatim intent): continue; tone down the camera movement when walking and running (dizzying), maybe
by 50%; scour the internet for downloadable gun sounds and impact sounds, complete sounds for everything, every
impact type; blood splatters everywhere when players get hit, realistic red liquid on walls and the ground where they
stand, even on dead bodies and ragdolls.

Baseline: working tree at the end of the unfinished r5 run (no r5 handoff; r5 contract in `../r5/CONTRACT.md`).
Engine: Godot 4.7.2. Version 0.6.0 -> 0.7.0 (new reload-step event; r5 had planned 0.7.0 for its models and map).
Budget: at most 8 build/review passes per component.

| ID | Component | Files | Acceptance (measured) |
|---|---|---|---|
| B | Walk/run camera bob -50 % | `player/player_controller.gd`, `player/viewmodel.gd` | head bob, side sway and limp roll amplitudes halved (`GAIT_BOB`), gun bob halved; `walk_bob_halved`: camera sway while walking < 0.034 m up/down and < 0.024 m sideways (old 0.050 / 0.036) |
| S | Sounds | `tools/build_r6_sounds.py`, `assets/audio/r6/`, `data/sounds.json`, `fx/effects.gd`, `player/weapon_anims.gd` (cues), `player/viewmodel.gd`, `match/world.gd` (`_ev_clip`) | Only CC0 / CC BY sources, licence read from each source page; every material in ballistics.json and tile has its own bullet-impact set (>= 3 takes), plus flesh, head, helmet, armour, ricochet, fly-by, casings, shotgun shells, body falls; every reload step of every reload kind has a sound timed to the hands (`reload_step_sounds` in order) and a bot's reload is heard (`bot_reload_heard`); all ids exist and load (`sounds_complete`). By-ear quality: not testable here |
| D | Blood | `tools/make_blood_textures.py`, `assets/fx/blood_*.png`, `fx/blood.gd`, `fx/holes.gd` (shared cards), `fx/effects.gd`, `props/corpse.gd`, `match/world.gd` | Works on every renderer (cards, not decals). Three rifle hits on a bot in front of a light wall: >= 15 marks, blood-red pixels +0.25 % of the view, visible on the wall behind and the ground at their feet; pool under a body grows on screen; rounds into a body make >= 4 new marks; spray costs < 1 ms per hit |

Benchmark: no commercial captures on disk; the reference is the previous revision (small brown decals, generic
impact sounds, one reload clip per class). The commercial A/B gate stays UNVERIFIED; no blind critic was run.

Integration gate: `--autotest=r6`, `tour`, `fixes`, `r3`, `r4`, `r5 --r5_fast`, `tools/net_test.sh` on one revision.
