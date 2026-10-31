# r15 (0.16.0): lobby host, phone stick, safe drop, Malasugue Mall, load times

User request (2026-10-30, @lemondev): first slot hosts online lobbies (start when everyone else is Ready, alone at
once); the phone move stick never sprinted and ran slowly; no damage at all from the Classic parachute landing; a
second Deathmatch map, "Malasugue Mall" (5 storeys, working escalators, emergency stairs, tons of named shops with
destructible glass doors, from the user's five reference photos); faster loading for all maps; build, update the
website and the launcher.

## What changed

- **Lobby host** (`net.gd` room_host / request_start / request_config, `lobby_ui.gd`, `official.gd`): on a dedicated
  server the earliest human still in the lobby is its host (Host pill, settings, Start). Start is refused until every
  other human is Ready; alone it starts at once with bots. Official servers keep their mode, fall back to starting
  by themselves after `official.host_wait_s` (150 s) for an idle host, and restore their own settings when the lobby
  empties. Deathmatch lobbies (and the custom-game page) pick the map: Lawless Sub or Malasugue Mall.
- **Phone stick** (`touch_controls.gd`, `player_controller.gd`): full run speed from 62% of the ring (was linear
  through a 25% dead zone: ~60% of run speed at 70% pull), sprint from 86% pushed forward (was a hidden pull past
  the ring), and the controller reads the stick directly (the Sprint toggle setting no longer flips on every drag).
- **Safe drop** (`match_server.deploy_safe`, `world._server_motion_event`): Classic, from the aircraft until 4 s after
  the first touch-down, no fall or landing damage or leg injury.
- **Malasugue Mall** (`src/world/maps/malasugue_mall/`): layout (plan, 114 units, escalators, stairs, spawns, per-level
  walk grids), builder (floors, court edges with fascias and glass balustrades, ceilings, shell, entrances, cores,
  restrooms, roof: disc ceiling, barrel vault, dome), shops (25 recipes, glass fronts and doors), escalators (16,
  moving steps shader, belts in `Motor`), decor (stage, Christmas tree, kiosks, banners, food hall). Art:
  `tools/make_mall_assets.py` (111 signs, 8 LED adverts, banners, wayfinding, posters, shelf goods),
  `tools/make_mall_textures.py` (floors, city windows); downloads `tools/fetch_r15.py` (17 textures, 27 models, CC0).
  Bots: `src/ai/nav_levels.gd` (AStar3D over 5 levels + escalator/stair links). Glass: plate windows and glass doors
  shatter (bullets, blasts).
- **Load time**: `GeoSink` box path (cached chunk lookups, int dedup key, precomputed axes, one append per collision
  box), headless servers build collision only (`sink.visual`), `mall_vc` batch material.

## Evidence (this machine: RTX 4060, editor build)

| Check | Result | Where |
|---|---|---|
| Lobby host (official DM + classic servers, 3 clients) | 13/13 PASS | `work/r15/room_test.sh`, `work/r15/room/` |
| Mall suite (`--autotest=mall`) | build, ride up 13.9 s, ride down 13.9 s, stairs, glass pane, glass door, bot L1 -> L5 in 29 s: 7/7 PASS | `work/r15/t4/` |
| Phone stick (`--mobile --rendering-method mobile`, mall) | 70% pull 4.4 m/s (run), ring 6.4 m/s sprinting: PASS | `work/r15/touch.log` |
| Safe drop (Classic, Kalinaw) | 14 m drop at 20 m/s after the jump 100 -> 100; same drop 6 s later 100 -> 1: PASS | `work/r15/chute.log` |
| Mall fingerprint server (headless) vs client | #64ec4447 both | `work/r15/mallnet/` |
| Network regression (Kalinaw, server + 2 clients) | 20/20 PASS, fingerprint #49929ca0 unchanged | `work/screens/net/` |
| Deathmatch regression (Lawless) | 7/7 on rerun (dm_no_own_body flaked once at the HUD corners) | `work/r15/dm*.log` |
| Mall frame rate (5 spots, 20 bots, spin) | 90-102 fps avg, p99 15.9-18.6 ms, 1219-1572 draws | `work/r15/perf2.log` |
| Build times headless (server) | Kalinaw 18.4 -> 10.1 s, Lawless 11.7 -> 6.8 s, mall 2.2 -> 1.3 s | this report |
| Build times windowed (client) | Kalinaw 21.2 s (~0.7 s saved by the sink rewrite); mall ~3.7 s | this report |

## State

- Lobby host, phone stick, safe drop: **VERIFIED** on PC (phone stick on the phone profile, not a real phone).
- Malasugue Mall mechanics (escalators, stairs, glass, bots across levels, spawns, fingerprint): **VERIFIED** by the
  suite above. Look and detail: **IMPLEMENTED - UNVERIFIED** against a benchmark (no blind critic run; judged from
  captures in `work/r15/shots*`, `work/release_shots/mall/`). Not measured on a phone (draw calls ~1,500 are high
  for phones).
- Load times: server builds roughly halved; client builds only slightly faster. Reusing the built map between
  rounds (the biggest remaining win) was not done: it needs every broken window, door, prop and item reset in place.

## Open gaps

- Mall on a real phone (frame rate, draw calls); bots mostly fight on Level 1 (they climb when sent, but rarely
  choose to); shop interiors are box-built (no bespoke models); the lobby screenshot on the site is still the old one.
