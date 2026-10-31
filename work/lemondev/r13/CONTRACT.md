# r13 — death camera and killer card, radio voice lines, voice commands bots obey, laser reactions

Baseline: the r12 tree (uncommitted, base commit 430ea9e). Same engine and targets as r12. Version 0.13.0 (r12 and
r13 ship in one build; both change network messages).

## User outcome (2026-10-29, mid-run of r12)

1. When the player dies: third-person camera on their body, and an impactful text saying who killed them, with the
   killer's name and where they were last hit. A headshot gets a special-effects text with a headshot icon (a
   crosshair on a head) and bloody effects.
2. When the player kills someone, a teammate bot says a radio_basic_kill line (radio_headshot_kill for a headshot).
   Bots say the same lines for their own kills.
3. Use every sound in `audio/` according to its name: enemy_spotted when bots spot an enemy, and so on.
4. A new SmarTab tab of instant voice commands ("Need help!", "Follow me", "Let's go!", "Fall back!", and the
   rest). Bots react to them and use them too. A bot that answers "affirmative" really does the task.
5. Bots react to the player's laser: they look at what it points at, and bots near it go and check it unless they
   are camping or sniping.

## Components

| ID | Component | Files |
|---|---|---|
| D1 | Death report and camera; killer card with headshot badge and blood | world.gd (`_send_death_report`), player_controller.gd (`_death_camera`), ui/death_card.gd (new), hud.gd |
| D2 | The user's audio: convert, level, register; AWP rifle; sumpak sound | tools/add_r13_sounds.py (new), assets/audio/r13, sounds.json, weapons.json, loot.json, rules.json, dresser.gd |
| D3 | Radio lines (recorded voice where it exists, TTS otherwise); kill, headshot kill, man down, need help, in position | tools/make_bot_radio.py, bot_radio.json, bot_brain.gd (`say`, `radio_sid`, `reply`), bot_team.gd |
| D4 | Voice commands: SmarTab Voice page; server; bots take orders and answer | smartab_ui.gd, hud.gd, world.gd (`server_voice`), bot_team.gd (`on_voice`), bot_brain.gd (orders) |
| D5 | Teammate laser: look, and the nearest two not camping or sniping go and check | bot_brain.gd (`on_laser`), bot_team.gd (`laser_claim`) |

## Checks (`--autotest=r13`, numbers fixed here)

- Every recorded line and new gunshot loads; the AWP has a model; the sumpak has its own shot.
- Follow me: at least one bot within 70 m says affirmative and follows.
- Need help!: a bot 55 m away says affirmative and comes at least 20 m closer within 14 s.
- Let's go!: a bot next to the player moves at least 10 m toward where the player looks, within 9 s.
- Fall back!: a bot 30 m away ends within 12 m of the player within 10 s.
- Negative: when the only bot in reach is in a close fight, it says negative and takes no order.
- Laser: a roaming bot 14 m from the lasered spot gets there and says "clear"; a camping bot takes no check.
- Kill radio: the player's headshot kill is confirmed by a teammate bot (headshot_kill); a bot's own kill (kill); a
  teammate's death (down: man_down).
- Death: the camera is in third person (1-7 m from the body, at least 0.8 m above it) from 1 s on. The card names
  the killer, the weapon, the distance and the hit part, and shows the headshot badge. Spectating follows after 6 s.
- Regression on the final tree: r12 mechanics and field checks, `--autotest=dm`, `--autotest=r11` subset, net test.
