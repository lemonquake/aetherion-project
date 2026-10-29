# Match flow, networking config and lobby/menu in Aetherion (read-only mapping)

All paths are under `A:/Python/aetherion-project/game/` unless stated otherwise. I edited no files.

## (a) How a match starts, end to end

**1. Menu** (`src/ui/main_menu.gd`)
- **PLAY NOW** → `_quick_match()` :588-599.
  - Calls `Net.host()` on the default port 27415. This is a real ENet server, not an offline mode.
  - Sets config `name`, `teams=5`, `team_size=4`, `bots=true`.
  - Calls `Game.show_lobby()`, then a 0.3 s timer calls `Game.start_match()`.
- **HOST GAME** → `_host_custom()` :602-612. Calls `Net.host()`, copies the `_create` dict into `Net.set_config` (name, teams, team_size, bots, zone_speed), then `Game.show_lobby()`.
- **Join** → `_join(addr, port)` :615.
  - `Net.join` (net.gd:89), then `_on_connected` (net.gd:190) sends `_hello.rpc_id(1, name, VERSION, platform, look, profile_id, level)`.
  - Server side, `_hello` (net.gd:212-253) checks the version, handles reconnect by matching name, checks capacity, dedupes the name and calls `_first_free_team`. It then sends `_welcome` (:256), which emits `connected_to_server`, which runs `Game.show_lobby()` (game.gd:48).
  - If the server is already loading or in a match, `Game.on_peer_joined` (game.gd:389) sends `_load_match` to the late joiner.
- **Command line**: `Game.boot()` (game.gd:62-107) handles `--server` (dedicated), `--host` and `--join`. `_apply_arg_config()` :110-131 handles `--mode`, `--teams`, `--team_size`, `--bots`, `--seed`, `--zone_speed` and `--autostart`; `_autostart` is at :134.

**2. Lobby** (`src/ui/lobby_ui.gd`). The host's START MATCH button (:79) calls `Game.start_match()`. There is no ready or min-players gate: `rules.json` `lobby.min_players_to_start` and `countdown_s` are never read.

**3. `Game.start_match()`** (game.gd:191-217, server only)
- `Net.remove_bots()`.
- If `config.bots`: shuffle `BOT_NAMES`, `room = Net.slot_count() - Net.humans()` (capped by `--bots`), then `Net.add_bot(name, Outfit.random_look(...))` per seat.
- `Net.assign_teams()` (net.gd:373), then `players[*].in_match = true`.
- `match_seed = randi()` (or `--match_seed`). `_load_timer = rules.loading_timeout_s` (90).
- `_load_match.rpc(Net.config, match_seed)`, plus a local call.

**4. `_load_match(cfg, seed)`** (game.gd:220-235, reliable RPC on `/root/Game`)
- Sets `Net.config = cfg` on clients, state `"loading"`, `teardown_world()`, then `WorldScript.new()` named `"World"`.
- `world.build(cfg, seed)` (world.gd:60-107):
  - `MapBuilder.new()` and `map.build(self, cfg.map_seed, match_seed)` are hard-coded at :73-74.
  - Then acoustics and SoundSys; then interaction and grenades; Effects/Ambience/Hud/Announcer if not headless; on the server, ProjectileServer and `MatchServer.setup(self)` (:102-107).
- The client then sends `_client_loaded.rpc_id(1, map.fingerprint)`. The server compares fingerprints and toasts on a mismatch (:238-251).

**5. Waiting for peers.** `_on_peer_loaded` → `_check_all_loaded` (:254-269) → `_begin_match()` (:272). If loading takes too long, the timeout in `_process` (:372-377) starts the match anyway.

**6. `_begin_match()`**
- State `"match"`, `_match_started.rpc()` (clients run `world.client_match_started`).
- `world.server_start_match()` (world.gd:120) → `match_server.start()` (match_server.gd:41-85):
  - Builds the plane path from `Game.match_seed`.
  - Spawns every `Net.players` entry with `server_spawn_character(pid, team, name, plane.a, Motor.PLANE)`.
  - `_loadout(ch)` gives only the flashlight from `loot.json` `starting_loadout`.
  - Fills `stats[eid] = {pid, name, team, kills, damage, downs, alive_t, placed, bot}` and `initial_teams`.
  - Sets `phase = "plane"` and the zone to `{i:-1, state:"wait", r0: PLAY_HALF*1.25}`, then `_broadcast()`.
- `--end_after` and `--autotest` hooks run at :277-283.

**7. Each tick.** `world._physics_process` (:352-417) calls `match_server.tick` (:101).
- Phase `"plane"`: `_plane_tick` (:126-151) handles jumps (`team_jump` :154). Once nobody is aboard, phase becomes `"playing"` and `_next_zone()` runs.
- Phase `"playing"`: `_zone_tick` (:215) and `_check_end` (:397).

**8. End.** `_check_end` → `Game.end_match_to_results(_summary(winner))` → results → lobby (see (e)).

## (b) `Net.config`, how it reaches clients, and where `mode`/`map` should go

**Defaults** (net.gd:39):
```
{"name":"", "mode":"squad", "teams":5, "team_size":4, "bots":true, "bot_count":20, "map_seed":1729, "zone_speed":1.0}
```
- `MAX_TEAMS := 7`, `MAX_TEAM_SIZE := 4` (:41-42).
- `slot_count()` = `clamp(teams, 1, 7) * team_size()` (:136).
- `team_size()` = `clamp(config.team_size or rules.modes.<mode>.team_size, 1, MAX_TEAM_SIZE)` (:369).
- The ENet server allows `MAX_TEAMS*MAX_TEAM_SIZE+4` peers (:68), and `_hello` kicks when `humans() >= slot_count()` (:235).

What each key does:
- **`mode`** is already taken: it means solo/duo/squad. `set_config("team_size", v)` overwrites `config.mode` (:353-354), and `set_config("mode", v)` overwrites `team_size` from `rules.json` `modes.<v>.team_size` (:355-356). `--mode=solo|duo|squad` is documented in README.md:232. A new key such as `game_mode` (`"classic"`/`"deathmatch"`) avoids this.
- **`bot_count`** is set only by `--bots` (game.gd:120). `start_match` uses `arg("bots")` and `slot_count - humans`, never `config.bot_count`.
- **`map_seed`** is fixed at 1729 unless `--seed` is passed. It is read in world.gd:74 and drives the layout. `match_seed` is per match and drives loot, doors, props and lights; it reaches clients only as the `_load_match` argument.
- **`zone_speed`** divides each zone phase's wait and shrink times in `_next_zone` (match_server.gd:208-209), read from global `Net.config`.

**How config travels**
- Only the server mutates it, via `Net.set_config(key, value)` (:349-366; it returns early if not server).
- On teams/team_size changes it bumps players that no longer fit back to team -1, then `_broadcast_lobby()` (:270).
- `_broadcast_lobby` sends `_lobby_state.rpc(players, config)` (reliable), and clients replace both dicts wholesale (:278-282).
- Config is sent again in `_load_match(cfg, seed)` (game.gd:216, 222) and in late-join and reconnect `_load_match.rpc_id` (:392, :398).
- There is no client→server config RPC.

**Where new keys belong**
- Add `"game_mode": "classic"` and `"map": "kalinaw"` to the defaults at net.gd:39.
- Validate in `Net.set_config`, the single choke point used by the lobby, the menu and `_apply_arg_config`: whitelist values and, for deathmatch, force `teams=2` and `team_size<=10`.
- `MAX_TEAM_SIZE` must rise to 10. It is also used by the ENet peer cap (:68) and by `_apply_arg_config` clamps (game.gd:114-116).
- Add CLI switches in `_apply_arg_config`.
- Per-mode and per-map data can go in `rules.json` (`Defs.rule("a.b.c", default)` does dotted lookup, defs.gd:133).
- Consume `cfg.map` in `world.build` (world.gd:73) to pick the builder, and `Net.config.game_mode` in `MatchServer.start`.
- Add both to `Online.game_info()` (online.gd:89-100). The master server stores the POST body unfiltered (master_server.gd:152), so the new fields reach the stats-server game list. Show them in the menu's game list (main_menu.gd:426).

**Net version**: `Net.VERSION = "aetherion-" + application/config/version` (net.gd:18), currently `"aetherion-0.7.0"` from project.godot:7.
- `_hello` (:217) refuses a mismatch, and the menu disables Join for another version (main_menu.gd:420, :431).
- Bump it whenever RPCs, map or rules change. RPC signatures must match on every peer, and every machine builds the map itself.

## (c) Character spawn API and direct ground spawns

**Signature**:
```
world.server_spawn_character(pid: int, team: int, pname: String, pos: Vector3, mode: int) -> Character
```
(world.gd:177)
- Allocates an eid, then `_make_character` (:195-234). That creates WeaponState, FlashlightState, Health and Inventory, plus a visual if not headless. If `pid == Net.local_pid` it creates the PlayerController (the camera lives there) and calls `hud.set_character`.
- Sends `_spawn_char.rpc(eid, pid, team, pname, pos, mode)` to every peer.
- Creates a BotBrain if `Net.is_bot(pid)` (pid ≤ -1000).

**Motor modes**: `enum { PLANE, FREEFALL, CHUTE, GROUND, DOWNED, DEAD, SPECTATE }` (src/player/motor.gd:5).
- `server_set_mode(ch, mode)` (world.gd:241) sends `_char_mode(eid, mode, pos, vel)`. For the owner it snaps position and velocity and calls `controller.on_mode_forced` (:246-258).
- `SPECTATE` is never assigned anywhere; it appears only in filters.
- `DEAD` is set just before the character is removed (world.gd:758-761).

**Spawning directly on the ground** already works:
- Call `server_spawn_character(pid, team, name, Vector3(x, y + 0.3, z), Motor.GROUND)`.
- Autotests do the equivalent with `server_set_mode(ch, GROUND)` plus a teleport using `world.map.ground_height(x, z)` (autotest_r6.gd:28-31, autotest_r5.gd:46-52).
- `map.ground_height` is terrain height only, so indoor or upper-floor spawns need spawn points from the map.

**Loadout on spawn**
- `world.interaction.give(ch, entry)` (interaction.gd:160-196):
  - A weapon goes to `wpn.slot_for(id)`. Handguns go to slot 3; long guns to the first free of 1/2. A full slot drops the old gun.
  - Armour goes through `inv.equip_gear`.
  - Everything else goes to the bag.
- Entry formats:
  - Weapon: `{"id": wid, "n": 1, "w": WeaponState.new_instance(wid, null, 1.0)}` (weapon_state.gd:125).
  - Armour: `{"id": "helmet_heavy", "n": 1, "d": <durability>}` (dynamics.gd:837-838). **`d` is required**: health.gd:160 ignores armour with `d <= 0`.
  - Ammo: `ch.inv.add({"id": Defs.ammo_item(wid), "n": N}, true)`, where `force` ignores capacity.
- Weapon slots: `[HOLSTER, PRIMARY, SECONDARY, HANDGUN]` = 0..3 (weapon_state.gd:9). SECONDARY is a second long gun; handguns live in slot 3. To place guns deterministically, write `ch.wpn.slots[i]` directly.
- Call `ch.inv.mark_dirty()` afterwards. The owner then gets everything through `_owner_state` every 0.1 s (world.gd:818-833); weapons travel inside the `inv.to_dict()` field `"w"`.
- Armour items: `vest_light`, `vest_heavy`, `helmet_light`, `helmet_heavy` ("Heavy-Plate Helmet", the likely "full helmet") in items.json.

**Spawn gotchas**
- `_spawn_char` carries no yaw. The owner's controller copies `ch.yaw` (0 on clients) at setup (player_controller.gd:84), and its first command overwrites the server's yaw. A facing direction needs an extra RPC argument.
- `BotBrain._init` → `_pick_landing()` (bot_brain.gd:122-161) reads `world.match_server.plane`. With no plane it aims at buildings near (0,0); bots in GROUND mode then run normal AI (:203+).

## (d) Death, downed, dead, spectate

**Downed** (health.gd:247-261)
- At HP ≤ 0, a character goes down if `world.server_can_be_downed(ch)` (world.gd:688-694): `Net.team_size() > 1` and a teammate in GROUND/FREEFALL/CHUTE who is not downed.
- Downed state: health 1, bleedout `downed_bleedout_s` = 90 (items.json `health`). Otherwise the character dies.
- `_after_damage` (world.gd:737-746) sets mode DOWNED, holsters, turns the light off, drops held objects and calls `match_server.on_downed`.
- Bleedout pauses while `revive_progress > 0` (health.gd:292-293).

**Revive**
- A teammate aims at a same-team DOWNED character (interaction.gd:55-56) and holds Use.
- `server_use_held` (:116-129): after `revive_time_s` = 6 within reach + 0.6 m, `health.revive()` (health 22) and `server_set_mode(GROUND)`.
- `_check_end` (match_server.gd:398-402) kills downed players whose team has nobody standing ("bled out").

**Death** (world.gd:747-761)
- Death sound, drop held object, `map.server_spawn_corpse` (the inventory goes into the corpse), `server_set_mode(DEAD)`, `match_server.on_killed`, `server_remove_character`.
- The character is destroyed on every peer.
- On the owner, `_remove_char` → `controller.on_local_died()` (player_controller.gd:400-407): `ch = null`, the HUD shows "You died.", then `_pick_spectate()`.

**Spectating today**
- `_pick_spectate` (:410-420) picks the first living teammate, otherwise any living character, including enemies.
- `_spectate_camera` (:512-531) is a third-person orbit 3.2 m behind the target with mouse look and a collision ray. The HUD shows "Watching X" (hud.gd:203).
- There is no input to change targets and no free cam. A new target is picked only when the current one disappears. The minimap hides (minimap.gd:39) and touch controls hide (touch_controls.gd:62).
- Server snapshot relevance for a dead viewer uses `spectate_target(pid)` (world.gd:775, :789-794): the first character of the viewer's team, else `characters.keys()[0]`. It is not the client's chosen target. `world.spectate_eid` (:40) is unused.
- Dead players stay on the team radio: `voice_targets` (:911-913) has no alive check.
- Late joiners have no character, so no PlayerController or camera is created (world.gd:226-233). I found no fallback camera.

**"Dead players wait and spectate until the round ends"** is already the de-facto behaviour: no respawn, and results appear when `_alive_team_count() <= 1` (match_server.gd:382-412). With two teams, the whole team dying ends the match. What the new mode still needs:
1. Restrict spectating to the own team in deathmatch (remove the enemy fallback at player_controller.gd:417-420).
2. Add next/previous target input, plus a client→server RPC so `spectate_target` follows the watched character (otherwise enemies more than 180 m from the server's choice are culled, `relevance.enemy_radius`).
3. Optionally mute dead players' radio to stop ghosting.
4. Add a "waiting, N teammates alive" label (`spect_label`, hud.gd:99).
5. Give late joiners or dead reconnectors a spectator controller.
6. Decide whether downed/revive applies in deathmatch. With team_size 10 it applies automatically; a mode flag can be checked in `server_can_be_downed`.

## (e) Results, rematch, world reset

**Results**
- `Game.end_match_to_results(summary)` (game.gd:305-321) adds `xp` (`Profile.match_xp`), `profile` and `platform` to each row. It reports to the master (if this process runs one) or `Online.post_result`, then `_show_results.rpc` plus a local call.
- It arms a `rules.results_s` (25 s) timer for `_return_to_lobby`.
- `_show_results` (:324-339): state `"results"`, `Profile.add_match(row)` for the local player, `world.show_results` (world.gd:129) → `hud.show_results` (hud.gd:208-247) and `controller.set_results_mode(true)`.
- The HUD results table has columns Player, Team, Kills, Downs, Survived, shows the first 12 rows, and the headline "Last team standing: …".

**Summary format** from `_summary(winner)` (match_server.gd:432-444):
```
{winner_team, winners:[names], rows:[{pid,name,team,kills,downs,time,winner,bot,damage,place}], duration, teams}
```
`place` is 1 for the winning team, else `max(placed, 2)`.

**Return to lobby** (`_return_to_lobby`, game.gd:342-355)
- Clears `in_match`, sets `ready = bot`, erases disconnected players, `Net.remove_bots()`, `_back_to_lobby.rpc()`, `show_lobby()`.
- `show_lobby()` → `teardown_world()` (:363-369): `world.teardown()` (world.gd:110) then `free()`, `SoundSys.clear()`.
- Teams and looks persist. Bots are re-created with new names at the next start.

**Rematch**: there is no button; the host presses START again, or `--autostart --rematch` restarts after 3 s (:354-355). Every match rebuilds the whole World and map from scratch. The comment at net.gd:170 says that takes 30-45 s with the main thread blocked, which is why ENet timeouts are raised to 180 s (:172-174). There is no in-place reset of an existing World.

## (f) Main menu and lobby UI structure

**Main menu**
- Pages are listed in `PAGES` (main_menu.gd:10); each is built lazily by `_page_<id>()` and cached in `_pages` (:157-176). Content changes need manual show/hide or a rebuild.
- **Home** `_page_home` (:189-244): the PLAY NOW button (:205) and its "Practice: you and 19 bots…" line (:208). A CLASSIC/DEATHMATCH `UITheme.segmented` and a map picker fit just above it.
- **Play**: the host panel `_page_play` (:309-338) holds Game name, Teams stepper, Squad size segmented (1-4), bots toggle, Safe zone segmented, `_summary` and HOST GAME. Mode and Map fields go after the name; Teams and Squad size should hide for deathmatch. The `_create` dict is at :24; `_update_summary` at :391.

**Lobby**
- Header: Outfit (Locker), Settings, Leave (lobby_ui.gd:43-45).
- Team cards in an HFlowContainer: `_team_card` (:167-222), 300 px wide by `74 + size*52` tall. With 10 seats a card is 594 px tall.
- Host "Game Setup" panel: `_setup_panel` (:86-116). It is rebuilt only when `JSON.stringify(Net.config)+host` changes; non-hosts see read-only rows (:102-110). Mode and Map belong here.
- Bottom: tip, READY (clients), START MATCH (host) (:73-81).
- `_refresh` runs on every `Net.lobby_changed` (:82, :126-164).

**Loadout picker** (per player, so not in the host-only panel)
- Add a "Loadout" button beside Outfit that opens an overlay built like `_open_locker` (:253-274: full-rect layer, MenuBg, title and DONE).
- Sync it like the outfit: `request_look` / `_req_look` (net.gd:304-319) is the pattern. Add `Net.request_loadout(primary, secondary)` → `_req_loadout`, validated against `Defs.weapons` and `weapon.slot`, stored in `players[pid].loadout`, then `_broadcast_lobby`.
- Remember the choice locally in a new Settings section: add it to `DEFAULTS` (settings.gd:13-34); `get_value` falls back to DEFAULTS (:101).
- One-tap practice shows the lobby for only 0.3 s, so the saved loadout must be used there.

**Lobby state sync**
- `players[pid]` = `{name, team, ready, bot, connected, in_match, look, profile, level, platform}` (net.gd:113-114, :245-250). The whole dict and config are re-sent on every change.
- Ready: `request_set_ready` → `_req_ready` → `_apply_ready` (:285-301). It is cosmetic.
- Team: `request_team` → `_apply_team` (:322-346).
- Bots: `add_bot` / `remove_bots` each broadcast, so starting with 19 bots sends about 40 lobby broadcasts.

**Practice vs hosted vs joined**: practice is just hosting with bots and an immediate start. It still opens port 27415 and sends the LAN beacon, since `Online._process` hosting is `Net.is_server and Net.online and not dedicated` (online.gd:77). `Net.shutdown()` (net.gd:101-110) does not reset `config`, so the quick match must set `game_mode` and `map` explicitly or the previous host session's values leak in.

**LAN beacon** (`game_info`, online.gd:89-100): `{t:"game", game, name, host, port, players, max, teams, team_size, bots, state, version, platform}`. It is sent once a second over UDP 27416 and posted to `/game` every 3 s.

**Theme and widgets**
- `UITheme` (src/ui/ui_theme.gd): colours :6-18, including 7 `TEAM_COLORS`.
- Helpers: `label`, `button`, `primary`, `icon_button`, `hbox`, `vbox`, `spacer`, `panel(style: "panel"|"panel_light"|"panel_accent")`, `pill`, `section`, `stepper`, `segmented([[value, label]], current, cb)`, `toggle`, `bar`, `box` (:151-315).
- Button variations: `PrimaryButton`, `FlatButton`, `CardButton`.
- `Icons.texture(name, size, color)` (src/ui/icons.gd:7) draws icons procedurally: home, play, locker, profile, trophy, settings, globe, users, plus, refresh, link, phone, monitor, bot, star, check, dice, none, back, exit. There is no weapon icon.
- Phones draw the UI at 1.5x (game.gd:64-66). Layouts switch to compact below 1500 px wide (main_menu.gd:37, lobby_ui.gd:25).

## (g) HUD elements for teams and alive counts

There are no team or alive counters on the in-play HUD.
- `hud.on_match_state(info)` is an empty stub (hud.gd:175). `match_state` carries only `{phase, plane, zone}` (match_server.gd:449).
- The SmarTab Team page (smartab_ui.gd:437-469) lists your own team's status and "Players remaining: N" (all characters not DEAD/SPECTATE).
- The minimap (src/ui/minimap.gd) shows only you, the safe-zone circle and pings.
- Other HUD positions: toast CENTER_TOP y=90 (hud.gd:84-89), loudspeaker banner CENTER_TOP y=128 (:290-305), minimap and compass top-left (:121-130), frags bottom-right (:131-136), prompt, hint and spectate label at bottom centre -170/-110/-70.
- Mode hints are per Motor mode (:364-381). The loading overlay text "Sitio Kalinaw" is hard-coded (:151), as is the menu's "SITIO KALINAW · NIGHT" (main_menu.gd:195).
- Clients can count living players per team from `world.characters`, because every spawn, mode change and removal is broadcast reliably to all peers. Alternatively the server can add an `alive` map to `_state()` and rebroadcast on each death.

## Gotchas

- **Day/night clock**: `lighting.match_time()` (src/world/lighting.gd:425-436) is measured from `match_info.plane.t0`. With no plane it stays at 0, so it is night forever. The announcer (announcer.gd:25-27) and bots (bot_brain.gd:304) depend on it too. A plane dict kept only for its `t0` would make the aircraft render (effects.gd:587-595) and the SmarTab draw the flight line (smartab_ui.gd:419-421). A separate `t0` in `match_state` is safer.
  - The rules give 300 s night + 300 s day (`rules.json` `day_cycle`).
- **Match phase**: `_check_end` runs only in phase `"playing"`, and the zone advances only from `_next_zone()`, which is called when the plane empties. A deathmatch `start()` must set `"playing"` itself, call `_next_zone()` and then `_broadcast()`.
- **Zone damage** applies only when `zone.i > 0` or the zone is shrinking (match_server.gd:245). Zone radii are fractions of `PLAY_HALF*1.6`, so the new map's `PLAY_HALF` sets the scale.
- **Map facade**: a new map must supply what World, MatchServer and the UI read:
  - `layout.HALF`, `PLAY_HALF`, `MAP_SCALE`, `in_play_area`, `is_water`, `ground_height`, `landmarks`.
  - `dyn.*`, `acoustics`, `lighting`, `models`, `buildings`, `map_image`, `fingerprint`.
  - `water_height`, `ground_height`, `physics_tick`, `server_tick`, `client_interpolate`, `awake_props_near`, `warm_up`, `server_sync_peer`, `server_spawn_corpse`, `server_break_glass`, `server_prop_hit`, `server_corpse_hit`, `server_push_prop`, `client_prop_snapshot`.
  - `_rescue` and `_outside_world` (world.gd:554-588) use `layout.HALF` and `PLAY_HALF`.
- **XP in a two-team match**: `Profile.add_match` counts `place <= 5` as top 5 and `match_xp` gives place-2 teams 200 XP (profile.gd:54-85). Every two-team match would count as top 5 and pay losers 200 XP.
- **Existing tests assume the plane**: autotests `_deploy` from the plane, and `tools/net_test.sh` uses `--bots`/`--autostart`. Keep CLASSIC as the default.
- **Pre-existing bug**: the HUD text chat calls `world.send_text` (hud.gd:263), which does not exist anywhere, so pressing Y and sending a message errors at runtime.