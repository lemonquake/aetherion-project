# r13 — death camera and killer card, radio voice lines, voice commands, laser reactions; radio static, canal exits, speed bursts

Status: see **Gates** and **Builds** below. Version 0.13.0 (r12 and r13 ship together; both change network messages and
the snapshot format, so 0.12/0.13 builds cannot join each other). Nothing is committed (base 430ea9e).

The run was continued on 2026-10-30 from an unfinished session. The r13 contract items D1-D5 (CONTRACT.md) were in
the tree and passed their own checks (`int/`). This session added the user's new recordings, fixed three bugs the user
reported while it ran, fixed a bot regression the final regression found, then built and tested the builds.

## What changed (r13)

- **Death camera and killer card** (`world.gd` `_send_death_report`, `player_controller.gd` `_death_camera`,
  `ui/death_card.gd`): on death the camera pulls out to third person over the body. A card names the killer, the
  weapon, the distance and where the last hit landed. A headshot adds a crosshair-on-a-head badge and blood
  effects. Spectating follows after 6 s.
- **The user's recordings** (`tools/add_r13_sounds.py`, `assets/audio/r13/`, 89 files from `audio/`):
  - Radio lines: affirmative, negative, enemy spotted, in position, man down, need help, kill, headshot kill and (new
    this session) **follow me**. They play instead of the text-to-speech voices. Each recorded line has one
    caption ("Follow me!", "Enemy spotted!" ...); before, a recording could be captioned with a different phrasing.
  - Gunshots: AWP (new rifle), Kar98, M24 and sumpak. Also a grenade explosion, death cries, bullet impacts by
    surface and footsteps by surface.
  - **Radio static** (new this session, `World.server_radio_static`): when someone transmits, the user's static
    comes out of their radio and every living teammate's. Only **enemies** within 14 m of one of those radios get
    it: players hear it, and bots turn toward it and investigate. It plays on every voice line (bots' callouts and
    players' voice commands) and on voice chat: at key down, then every 1.5 s while talking. Teammates keep the
    faint hiss near a transmitting teammate. Rules: `radio.static`, `static_radius`, `static_interval_s`.
- **Radio lines from bots**: a teammate bot confirms the player's kill (headshot kill for a headshot), bots call their
  own kills, a teammate's death ("man down"), calls for help when hurt in a fight, and "in position" on arrival.
- **Voice commands** (SmarTab Voice page): Need help!, Follow me, Let's go!, Fall back!, Enemy spotted, In position,
  Affirmative, Negative. Teammate bots in reach answer "affirmative" and do it, or "negative" when they can't (in a
  close fight).
- **Laser reactions**: teammate bots look at what the player's laser points at; the nearest two that are not camping or
  sniping go and check it and say "clear".

## Fixes this session

- **Stuck in the canals** (user report with a screenshot):
  - Cause: the walled canal is 0.9 m deep with its coping 2.45 m above the bed. In water deeper than 0.6 m you
    cannot jump, and a ledge grab needs the top within 1.65 m of the feet. So the only ways out were 6 ladders on
    848 m of wall. Along the channel a sprint jump into the wall happened to work, because the 2 m water grid
    counted the strip against the wall as dry. Along the basin's straight walls even that was wet, so it was a trap.
  - **Haul-out** (`Parkour.water_grab`, `Motor._ground`): in water too deep to jump from, pushing into a wall (or
    Jump) catches its top when the arms reach it from the water (1.65 m + up to 1 m above the feet). The usual hang
    and climb-up follow. This is shared movement code, so prediction and the server agree.
  - Water depth now follows the canal's exact outline in the wall-edge cells (`sub_layout.water_height`). The map
    and its fingerprint are unchanged (#b1fba961).
  - Bots use a ladder within 12 m, otherwise they climb out at the nearest wall (`_escape_water`). Before, they
    waded up to 90 m to a ladder.
- **Bursts of speed out of the water and on stairs** (user report):
  - Cause: the step-up (`Character._try_step`). The estero bank's slope made the body cover less ground across the
    map, which was read as a kerb in the way every tick, and the body was placed a full probe ahead (0.26 m per
    tick, 15.8 m/s). On stairs, each step-up added a whole tick's distance on top of the slide (6.5 m/s while
    running at 4.4).
  - Now only a real stop counts as a step: a wall-like contact, a deflection, or under half the expected motion. A
    step adds only the distance the tick still owes, and more only when the edge needs it, in short increments.
  - Kerbs: the step lab still climbs every ledge up to 0.46 m at 0/35/65 degrees in every gait (unchanged).
- **Bots crushed behind a wall by the field** (found by the final regression; it last passed early in r12):
  - Cause: a late r12 rule kept a bot on its zone path while the field was more than 1 m off, even when that path
    ran through a wall the walk grid doesn't know about.
  - The rule now needs the way to the next waypoint to be open. The bot then gets out, over the 3.5 m test wall with
    the r12 climb. The check `r12_field_bot_escapes` now accepts "round its end or over it" (it only accepted round
    the end).
- **Quieter forcefield** (user report: the barrier's sound was too distracting): the hum is 10 dB down (-16 dB) and
  heard within 25 m of the wall (was 45 m). The crackle near it is -13 dB (was -4, up to +2 close up), with half the
  close-up boost and 1.2-3.5 s apart (was 0.4-1.6 s). The crush sound is unchanged. Files: sounds.json,
  tools/make_r12_sounds.py, effects.gd. Not checked by ear.
- Smaller: HUD rows that a newer row pushed out no longer leave a timer pointing at a freed label (log noise).

## Was the static to blame for bot test failures? No

Mid-run, three voice-command checks failed once and the field escape failed. Each was run with `radio.static` on and
off (`ab/`, `ab_static.sh`):

| Check | Static on | Static off |
|---|---|---|
| Voice commands (follow, help, go, fall back, negative) | pass x2 | pass x2 |
| Field escape, before the bot fix | fail | fail |
| Field escape and fieldhouse, after the bot fix | pass | pass |

The voice failure was run-to-run bot variance: a firefight broke out next to the player in that run.

## Gates

Final tree, `final2/` (`regress2.sh`), 1280x720 listen host on Deathmatch with 20 bots unless noted:

| Suite | Result | Notes |
|---|---|---|
| `--autotest=r13` | 12/13 | New: `r13_static_bots`, `r13_static_player`, follow_me and static sounds load. The laser check failed once: the "camping" bot had joined a bot squad (follow) before the laser came. The test now re-camps it just before; 2/2 reruns pass (`laser_1`, `laser_2`). |
| `--autotest=r12` | 17/18 | Bot field escape passes. `r12_fieldhouse` failed once (the test's field never closed on house 23); house 23 alone 4/4 (`house23_*`, `house23_door_*`). |
| `--autotest=dm` | 7/7 | Map fingerprint #b1fba961, unchanged by the water fix. |
| `--autotest=r11` (teams, pa, cage, haze, kerbs, stairs) | 6/6 | Upper flights and kerbs with the new step-up. |
| `--autotest=canal` (new) | 4/4 | Channel 10/10, basin 19/19, estero 10/10 (bridge spans skipped), bots 4/4. Old code (`canal/base`): basin 8/19, channel only by a sprint wall run. |
| `--autotest=bursts` (new) | 3/3 | Flat run 4.4 / sprint 6.3 m/s. Stairs 13 runs, no bursts (was 6.5 m/s sustained running, one flight 15.6). Estero bank 8 runs, no bursts (was 15.8 m/s). |
| Step lab (kerbs) | 132 ok / 24 blocked | Same as before the change: every ledge to 0.46 m at 0/35/65 degrees in every gait. |
| `tools/net_test.sh` (dedicated server, 2 clients) | 19/19 | New: `radio_static_not_for_teammates` (0), `radio_static_from_enemy` (static and voice heard from an enemy bot 7 m away). |

## Builds

`build_all.sh` (rebuilt once more after the field-sound change), 0.13.0, signed with the SDK debug key:

| File | Size | Notes |
|---|---|---|
| `builds/windows/Aetherion.exe` | 1.81 GB | Carries the new sound levels (checked in the packed sounds.json). |
| `builds/android/Aetherion.apk` | 564 MB | Vulkan. Carries the new sound levels. |
| `builds/android/Aetherion-opengl.apk` | 564 MB | OpenGL (for the emulator). Differs from the Vulkan APK. |

Deleted as the user asked in r12: `Aetherion-0.9.0.exe`, both 0.10.0 APKs, `builds/r8-preview/`.

Multiplayer on the built EXE (`exe_net_test.sh`: dedicated server and two clients, 6 bots, Battle Royale map
#49929ca0):

| Run | Result |
|---|---|
| All EXE (`exe_net/`), first build | 19/19 |
| Server + Alpha EXE, Bravo from source (`exe_net_mix/`), first build | 19/20: `vault_predicted` found no window to vault where Alpha landed (prediction error 0.003 m, 0 corrections) |
| All EXE, final build | 18/20: window 2134 did not break, so the local and seen-by-other checks both failed. It is an upper-floor window the test shoots from the ground through a fence. It failed the same way in an r12 run; both clients agree on its state. |
| Server + Alpha EXE, Bravo from source, final build | 19/19 |

Every run: same map fingerprint on all three processes, prediction error at most 0.03 m with no corrections,
the forcefield predicted with zero error, and the radio static reached the enemy and not the teammate.

## Not verified

- By ear: the recordings and the static levels were set by loudness numbers (static at -20 dBFS RMS, -3 dB in game),
  not listened to.
- A real phone (frame rate, cross-play from a phone). The APKs were built but not run on a device or the emulator.
- Blind reviews: the r12 critic packets (`../r12/critic_*`) were made but no verdicts were recorded, and none were
  run for r13.
