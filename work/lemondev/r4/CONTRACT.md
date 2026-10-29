# Run r4 — effects, destruction, announcer, menu/online, outfits (2026-10-27)

User request (summary): realism, gameplay and performance improvements; a particle system; bullet impacts that leave
holes; destructible props, tables, chairs, objects and doors with visible chunk-by-chunk damage; a loud outdoor
loudspeaker man warning everyone before every day/night change (60 s, 30 s, then a 10 s countdown, then a 7 s siren);
a total remake of the main menu with real textures, easy game setup for PC and phones (default 20 bots = 5 teams of
4, up to 7 teams, humans join any team), a lobby listing online players and joinable games, custom hosted games, a
dedicated server for global stats and a leaderboard, levelling profiles that gain XP per match; a customizable player
model with at least 4 unique models for each body part (helmet, boots, inner shirt, jacket, hands, elbow pads, face
attachment, and more); build the EXE and APK.

Engine / platform: Godot 4.7.2, Forward+ (PC) and Mobile renderer (Android, Vulkan / GL). Test PC RTX 4060.
Baseline / rollback: git commit 5f35ddf (0.5.0, clean tree at start). Version 0.5.0 → 0.6.0 (netcode, rules,
models change). Budget: 8 build/review passes per component.

## Components

| ID | Artifact / files | Acceptance (frozen before candidates) |
|---|---|---|
| C1 particles | new `fx/particles.gd` (pooled emitters), `fx/effects.gd` | Impacts per material (concrete/plaster dust and chips, wood splinters, metal sparks, glass shards, dirt, water, flesh), muzzle smoke, destruction dust, explosion use pooled emitters created and warmed at load: no node or material is created per impact; a same-view capture before/after an impact shows the effect (luma or pixel difference in the impact area); 60 impacts in one second add < 1.5 ms to the frame on the PC |
| C2 bullet holes | `fx/effects.gd`, `tools/make_impact_textures.py` → `assets/fx/holes/` | Material-specific entry and exit holes with normal maps (concrete, wood, metal, glass, plaster, fabric/plastic); holes on doors and moving props stay attached when they move; a capture shows holes on at least 5 materials; pool size by quality (PC ≥ 400, phone ≥ 150) |
| C3 destruction | new `world/destruct.gd` (chunking), `world/dynamics.gd`, `world/door.gd`, `props/physics_prop.gd`, `match/world.gd` RPCs | Breakable props (tables, chairs, cabinets, crates, boxes, plastic chairs…) and doors lose visible chunks one at a time where they are hit (chunk falls off as debris), then collapse; a door shot through has holes bullets and sight pass through, and once destroyed the doorway is passable; server-authoritative and identical on a client (net test) and for a late joiner; first chunking of a model < 40 ms, cached |
| C4 announcer | `audio/announcer.gd`, `tools/make_announcer.py` (Windows male TTS + loudspeaker processing), speaker horns on poles in the map | Before every ignition and every dusk: spoken warning at 60 s and 30 s, spoken countdown 10…1, then a 7 s siren starting at the change; heard from the nearest loudspeaker poles (positional, very loud, far range) plus an outdoor bed so it carries everywhere; HUD shows the countdown; the cue schedule is checked against forced match times on host and client |
| C5 menu + online | `ui/main_menu.gd` (new), `ui/lobby_ui.gd` (new), `ui/menu_*`, `online/*` (master server, client, profile), `net/net.gd` team slots, `core/game.gd` results/XP | Textured, designed menu: Home (profile card, level, XP), Play (Practice, Browse games: LAN + server list, Create game, Join by address), Locker, Profile & stats, Leaderboard, Settings; lobby with teams 2–7 (default 5) × size 1–4 (default 4), bots fill free slots (default 20), humans pick any team; online players list; `--master` stats server: presence, game list, match results, profiles, leaderboard, saved to disk; XP and level per match shown on results. Readable, unclipped captures at 1920×1080, 3840×2160 and the phone profile (2400×1080 at 1.5×); scripted check: master running, two clients see each other online, a hosted game appears in the browser and is joined by its button, a finished match updates profile XP and the leaderboard |
| C6 outfits | `tools/blender/make_gear.py` → `assets/models/gear/gear.glb`, `data/cosmetics.json`, `player/outfit.gd`, `ui/locker.gd`, character visual | ≥ 4 unique models for each of: helmet/headwear, face, jacket, inner shirt, gloves, elbow pads, knee pads, pants, boots, backpack, with colourways; skinned to the existing rig and animated; Locker with a turning 3D preview; looks replicated to everyone (bots get varied looks); a character costs ≤ 3 draw calls per pass (was 8); renders of every item and an in-match capture of different outfits |
| C7 realism / gameplay / speed | as found (shell casings, suppression, warm-up, decal and particle budgets, …) | Each change measured: perf A/B against 0.5.0 on the same benchmark (`--autotest=perf`), no regression > 1 ms median on the ground phases; gameplay changes covered by a check |
| C8 release | builds/windows, builds/android | EXE and both APKs from the final revision; EXE runs the new checks with a clean exit; APK installs and starts on the emulator |

## Benchmarks

- Visual (C1–C3, C5, C6): no commercial reference captures are on disk (PUBG/Fortnite lobbies, impacts). The blind
  A/B is against the 0.5.0 build's own captures of the same scenes (old menu, old impacts, old body). This shows
  improvement over the previous build, not parity with a commercial title; the commercial gate stays UNVERIFIED.
- Mechanics (C3, C4, C5): automated checks and the network test, not the critic.
- Performance: `--autotest=perf` on this PC, 1600×900, vsync off, the same seed and bots as the 0.5.0 numbers in
  docs/PERFORMANCE.md; measured A/B on the same machine state where possible.

## Deviations / decisions

- Teams: the user's model (teams × team size, bots fill free slots, max 7 teams of up to 4) caps a match at 28
  players, down from the 50-player cap of 0.5.0. Recorded here and reported.
- Stats server trust: results are posted by the hosting game; there is no anti-cheat or account system (names +
  generated profile ids). Reported as a limitation.
- Speech is synthesised offline with the Windows "Microsoft David" voice and processed into a loudspeaker sound; no
  recorded human voice is available.
