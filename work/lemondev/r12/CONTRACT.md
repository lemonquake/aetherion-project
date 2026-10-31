# r12 — movement rework, parkour, the forcefield, bandages (contract, frozen before candidate inspection)

Baseline: r11 working tree (0.11.0, base commit 430ea9e, uncommitted r11 changes; `git stash create` snapshot in
baseline_stash.txt). Baseline build for A/B: builds/windows/Aetherion.exe 0.11.0 (copied to work/lemondev/r12/base_exe
before the new build overwrites it). Engine Godot 4.7.2, PC (Forward+) and Android (Mobile / OpenGL). Machine CPU was
at 100 % load from other jobs when the run started: frame-rate numbers from it are labelled as such.

## User outcome (2026-10-29)

1. The haze becomes an electric white forcefield. No damage. It pushes anyone caught in it toward the centre, as if
   the wall were squeezing them in. Someone it pins against a wall, or who is stuck on a wall while it passes over
   them, dies at once. Bots know this: when the field is about to close they get out of buildings and stay inside the
   safe area, away from the edge.
2. Bandages heal injuries, take 2 s, and have an animation.
3. Running feels like a real body: speed builds up to the top speed; stopping takes a short brake, not an instant
   stop; a hard turn loses the built-up speed; a jump forward or backward carries the body that way; small falls do
   not hurt (much less fall damage overall).
4. Parkour, researched and applied: jumping at the edge of a wall, the hands grab it and the player can pull up and
   over. More of the same family (see PARKOUR.md).
5. A new EXE and APK; old builds deleted.

## Components (one owner per file set; all built by the Orchestrator in this session, reviewed by a fresh critic)

| ID | Component | Files |
|---|---|---|
| C1 | Ground movement: acceleration curve, braking, turn loss, jump carry, coyote time, jump buffer, landing | motor.gd, character.gd, snapshot.gd, player_controller.gd (camera only), rules.json movement |
| C2 | Parkour: ledge grab + hang + shimmy + climb up / over, wall run-up, slide, landing roll, speed vault | parkour.gd (new), vault.gd, motor.gd, viewmodel.gd/fp arms (hands), character_visual.gd (remote pose) |
| C3 | Fall damage | world.gd `_server_motion_event`, items.json health |
| C4 | Forcefield: push in Motor (predicted), crush death on the server, wall shader, screen overlay, sound, texts | field.gd (new), motor.gd, match_server.gd, effects.gd, field_wall.gdshader (new), hud.gd, sounds |
| C5 | Bots and the field | bot_brain.gd |
| C6 | Bandage healing + animation | items.json, health.gd, interaction.gd, viewmodel.gd, character_visual.gd |
| C7 | Builds: EXE + APKs at 0.12.0, old builds removed | build_all.sh, builds/ |

## Mandatory invariants (checked by `--autotest=r12`, numbers fixed here)

- C1 accel: from rest, holding forward + sprint on flat ground: speed < 70 % of sprint speed at 0.3 s, >= 95 % by 1.4 s.
- C1 brake: releasing all keys at full sprint: still moving after 0.15 s, stopped (< 0.2 m/s) within 1.1 s, travels
  0.8–3.5 m.
- C1 turn: at full sprint, snapping the view 90 degrees: speed along the new heading 0.25 s later < 60 % of sprint.
  A gentle 45 deg/s curve keeps >= 90 % of the speed.
- C1 jump carry: a standing jump holding forward lands >= 0.6 m ahead; holding back >= 0.4 m behind.
- C3: a drop of 2.5 m and of 3.5 m does no damage; 6 m does less than 30; a 4.5 m drop with the landing roll does
  less than without it.
- C2 ledge: running and jumping at a 2.2 m wall with a flat top grabs it (hands on the edge, body hanging); holding
  forward climbs on top within 1.5 s. A 2.0 m garden wall with open ground behind is climbed over to the far side.
  A 3.0 m wall is reached only with the sprint wall run-up. A 4.5 m wall is never grabbed.
- C2 slide: crouch at full sprint slides >= 2 m, at crouch height, and ends in a crouch.
- C4 push: standing in open ground as the edge passes: carried inward at least as fast as the edge, alive, no damage.
- C4 crush: standing against a wall whose far side faces the centre as the edge reaches it: killed, cause "field".
- C4 prediction: a client predicting its own push has a mean position error < 0.1 m against the server (net test).
- C5: headless bot matches (2 seeds, DM 3x7, zone speed 2): 0 bots killed by the field while standing in the open
  safe area; bots inside a building when the field starts closing leave it; field deaths reported per match.
- C6: a bandage use lasts 2.0 s (±0.1), heals health and limb damage, stops bleeding, and is drawn in first person
  (capture: hands with the bandage visible) and on other players (F_HEAL pose).
- Regression: `--autotest=dm` 7/7, `--autotest=r11 --r11_only=teams,cage,kerbs,stairs` pass; no script errors.
- Movement simulation gate: 10,000 fixed 60 Hz steps of scripted random input on the motor, all states finite,
  no vault/ledge/slide state stuck on.

## Blind review

Criterion: "Which build's movement and parkour look more like a real person moving through this space?" A/B clips
(frame strips) of the same scripted routes (sprint start/stop, hard turn, jump at a wall, drop from a roof) from the
0.11.0 EXE and the new build; second packet: the boundary as seen from inside and outside, old haze vs new field
("Which boundary is easier to see and reads as an electric forcefield?"). Max 8 passes per component.
