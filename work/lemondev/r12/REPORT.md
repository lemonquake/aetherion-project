# r12 — movement rework, parkour, the forcefield, bandages

Status: **IMPLEMENTED**, shipped with r13 as 0.13.0. The r12 session ended before this report, the final gate run and
the builds; they were done on 2026-10-30 at the end of r13 (`../r13/REPORT.md`, `../r13/final2/r12/`).

## What changed

- **The forcefield** replaces the haze at the edge of the safe area (`src/match/field.gd`, `src/fx/field_wall.gdshader`,
  HUD overlay in `hud.gd`, sounds `assets/audio/r12/field_*`):
  - It does no damage. Anyone in it is pushed toward the centre, a little faster than its edge moves (0.6 m/s more,
    plus 4 m/s per metre of depth, at most 9 m/s), and nothing moves outward inside it. The push is part of the
    shared movement simulation, so the owner's prediction and the bots run the same code as the server.
  - Anyone it holds 0.55 m or more inside it for 0.2 s, because a wall, a fence or a corner stops the push, is
    crushed (killed at once, cause "the field" in the kill feed). Being pushed into another person does not count
    until the last few metres of the circle.
  - It is a white-blue electric sheet: a hex lattice, bands of charge climbing it, arcs, a bright seam where it cuts
    the ground and walls, and a hum and crackle near it. Inside it the screen edges crackle (red when it is pinning
    you) with the text "The field is pushing you in. Keep clear of walls." The field toasts were reworded.
- **Running like a body** (`Motor.run`, `rules.json` movement): speed builds from 13 m/s² at rest to 2 m/s² near
  the top (about 0.5 s to a run, 1.2 s to a full sprint). Letting go brakes over a step or two. A hard turn sheds
  the speed that is not along the new heading. A standing jump with a direction held carries the body that way.
  Coyote time (0.12 s) and a jump buffer (0.15 s) were added, and air control was reduced (2.5 to 1.2 m/s²).
- **Parkour** (`src/player/parkour.gd`, research notes in `PARKOUR.md`):
  - Ledge grab: a wall top 0.95-1.65 m above the feet when the body meets it.
  - Hang and shimmy.
  - Climb up, or over a thin wall to the far side.
  - Sprint wall run-up (one step up the wall, about 1.5 m higher).
  - Slide: Crouch at a sprint.
  - Landing roll: hold Crouch on a drop over 1.6 m.
  - First-person hands on the edge, and a push-off hand on vaults. Third-person hands are planted on the edge by
    IK, and the rifle is slung across the back while the hands are busy.
- **Less fall damage** (`World.fall_damage`, `items.json`): drops up to 3.5 m are free. Damage rises steeply to
  lethal at 14 m (6 m costs about 10). A roll counts as 2.5 m less, then 60 % of that.
- **Bandages** (`items.json`, `health.gd`, `viewmodel.gd`, `character_visual.gd`, `hud.gd`):
  - They take 2.0 s (was 3.2) and heal 15 health and 40 % of each unbroken limb.
  - They can be used on any wound, not only a bleeding one.
  - In first person the left forearm comes up and the right hand winds the roll round it, the dressing growing
    along the arm. Others see the forearm held across the chest with the other hand winding round it. A
    "Bandaging 1.2 s" countdown shows.
- **Bots and the field** (`bot_brain.gd`, `bot_team.gd`):
  - They leave earlier for the next circle, and much earlier when indoors.
  - Within a few metres of a closing edge they run for open ground, jump or climb what is in the way, never into a
    building, and they keep to a path for the circle that is already heading in.
  - Indoors with no remembered door, they pick a way out (doors and open doorways on this floor). It is scored by
    the indoor route length, which side the next circle is on, and doors that just failed. They route through the
    rooms' doorways (the walk grid does not reach indoors).
  - They start exits clear of a door's swing and open shut doors on the way out.
  - A new path starts at the furthest of its first waypoints in plain sight, which stopped bots walking back into
    the house they had just left.
  - Match log: `[field watch]` per circle and `[field death]` with the bot's last 30 s.

## Gates (contract numbers)

Final tree (r13's, 2026-10-30), `--autotest=r12`: 17 of 18.

- Pass: bandage 1.97 s (60 -> 75 health, leg 12 -> 36); accel 3.07 m/s at 0.3 s, 6.30 at 1.4 s; brake stopped in
  0.60 s; turn 2.52 m/s along the new heading after a 90 degree snap; jump carry 1.38 m ahead / 1.15 m back; fall
  damage 0 up to 3.5 m, 9.6 at 6 m, 27.3 at 8 m (4.4 rolled); ledges 2.2 m and 2.0 m (over), 3.0 m only with the
  sprint run-up, 4.5 m never; slide 4.36 m; 10,000 random steps finite; field push carries the player 13.1 m
  unhurt; the dummy behind a 6 m wall is crushed in 1.22 s; the live bot gets round the 10 m wall.
- The bot escape had regressed after this run's late bot fixes: a zone path through a wall the walk grid does not
  know kept the bot pressed into it. Fixed in r13. The check now also accepts climbing over the wall.
- `r12_fieldhouse` is flaky. It passed in two of three final-tree runs. In the failed run the field never closed on
  house 23 (it stayed about 20 m off for 8 s), so the bot had no reason to leave. Reruns of house 23 alone:
  `../r13/final2/house23_*`.

## Blind reviews

Packets were made (`critic_move1-3`, `critic_field1-2`, private mappings beside them). No verdicts were recorded and
none were run afterwards.

## Builds

Not built in r12. The 0.13.0 EXE and APKs from the r13 tree include everything above (`../r13/REPORT.md`).
