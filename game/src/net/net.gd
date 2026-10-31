extends Node
## Connection management, lobby replication, clock estimation and raw packet routing.
## The server is authoritative; clients only send intentions (inputs and requests).
##
## Node path /root/Net exists on every peer, so the RPCs below resolve everywhere.

signal lobby_changed
signal connected_to_server
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal snapshot_received(bytes: PackedByteArray)
## kind 0: your own team's radio (2D); 1: overheard from a teammate radio of the speaker (src_eid); 2: the speaker's
## own voice nearby (src_eid).
signal voice_received(from_pid: int, bytes: PackedByteArray, src_eid: int, kind: int)
## r7: a player's Deathmatch loadout ({"primary": id, "secondary": id}) reached the server.
signal loadout_received(pid: int)

## Players must run the same build: the map is generated on every machine. Raise application/config/version in
## project.godot whenever the map, rules or netcode change.
var VERSION: String = "aetherion-" + str(ProjectSettings.get_setting("application/config/version", "0"))
const DEFAULT_PORT := 27415
const CH_RELIABLE := 0
const CH_SNAPSHOT := 1
const CH_INPUT := 2
const CH_VOICE := 3
const BOT_ID_BASE := -1000
const Attach := preload("res://src/weapons/attachments.gd")

var peer: ENetMultiplayerPeer
var is_server := false
var dedicated := false
var online := false
var local_pid := 0

## pid -> {name, team, ready, bot, connected, in_match}
var players: Dictionary = {}
## Match configuration chosen in the lobby by the host.
# bot_count 20 by default (the owner's choice, 2026-10-27), on phones and PCs alike; the lobby takes up to 50 players
# (rules.json max_players), which is what matches are built and measured for (40-50 players).
## teams x team_size slots (5 x 4 by default, up to 7 teams of up to 4); humans pick any team and bots fill the slots
## left when "bots" is on (20 bots in a practice match: 5 squads of 4, one of them yours).
var config: Dictionary = {"name": "", "game_mode": "classic", "map": "kalinaw", "mode": "squad", "teams": 5, "team_size": 4, "bots": true, "bot_count": 20, "map_seed": 1729, "zone_speed": 1.0,
	"day_len": 300, "dm_win": "wipe", "dm_score": 10, "dm_time": 14, "dm_field": false, "bot_skill": "normal"}
## (r17) The host's choices: the length of one night and one day (s); how a Deathmatch is won (a team score limit,
## the best score when the timer runs out, or the last team standing) with the limit for each.
const DAY_LENS := [120, 300, 600]
const DM_WINS := ["wipe", "score", "time", "elim"]
const DM_SCORES := [10, 20, 30, 50]
const DM_TIMES := [10, 14, 30]
## (r22) How well the bots play (config.bot_skill, read by the bot brain), Classic and Deathmatch alike.
const BOT_SKILLS := ["easy", "normal", "hard", "pro"]
var port := DEFAULT_PORT
const MAX_TEAMS := 7
const MAX_TEAM_SIZE := 4      # Classic squads
const DM_MAX_TEAM_SIZE := 7   # Deathmatch: two or three teams of up to 7 (r11)
const DM_MAX_TEAMS := 3
const GAME_MODES := ["classic", "deathmatch"]
const MAPS := ["kalinaw", "lawless_sub", "malasugue_mall", "freight_delight"]

## Server tick (authoritative on the server, estimated on clients).
var tick: int = 0
var _tick_float: float = 0.0
var _last_snapshot_tick: int = -1
var rtt_s: float = 0.0
var _ping_timer: float = 0.0
var _next_bot := BOT_ID_BASE
var _join_seq := 0   # (r15) join order: on a dedicated server the earliest human still here runs the lobby
## (r15) What the lobby's host may change from their own game (Net.request_config). Official servers keep their mode.
const ROOM_KEYS := ["game_mode", "map", "teams", "team_size", "mode", "bots", "zone_speed", "day_len", "dm_win", "dm_score", "dm_time", "dm_field", "bot_skill"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not reach the host."))
	multiplayer.server_disconnected.connect(func(): _drop("The host closed the game."))


# ------------------------------------------------------------------ hosting / joining

func host(port: int = DEFAULT_PORT, as_dedicated: bool = false) -> Error:
	shutdown()
	self.port = port
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, maxi(MAX_TEAMS * MAX_TEAM_SIZE, DM_MAX_TEAMS * DM_MAX_TEAM_SIZE) + 4, 4)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	dedicated = as_dedicated
	online = true
	local_pid = 1
	tick = 0
	players.clear()
	_join_seq = 0
	if not dedicated:
		players[1] = _new_player(Settings.player_name(), false)
		players[1].join = _next_join()
		players[1].platform = platform()
		players[1].look = Profile.look
		players[1].profile = Profile.id
		players[1].level = Profile.level()
		players[1].team = _first_free_team(1)
	_broadcast_lobby()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	shutdown()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, 4)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = false
	online = false
	return OK


func shutdown() -> void:
	if peer:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_server = false
	online = false
	players.clear()
	local_pid = 0
	_last_snapshot_tick = -1


func _new_player(pname: String, bot: bool) -> Dictionary:
	return {"name": pname, "team": -1, "ready": bot, "bot": bot, "connected": true, "in_match": false, "look": {}, "profile": "", "level": 1, "laser": "red"}


func add_bot(pname: String, look: Dictionary = {}) -> int:
	_next_bot -= 1
	players[_next_bot] = _new_player(pname, true)
	players[_next_bot].look = look
	_broadcast_lobby()
	return _next_bot


func _first_free_team(pid: int) -> int:
	if is_dm():
		# Deathmatch: join the smallest team.
		var nt := dm_teams()
		var c := []
		c.resize(nt)
		c.fill(0)
		for q in players:
			var tq := int(players[q].team)
			if q != pid and tq >= 0 and tq < nt:
				c[tq] += 1
		var tm := 0
		for t in nt:
			if int(c[t]) < int(c[tm]):
				tm = t
		return tm if int(c[tm]) < team_size() else -1
	for t in clampi(int(config.get("teams", 5)), 1, MAX_TEAMS):
		var n := 0
		for q in players:
			if q != pid and players[q].team == t:
				n += 1
		if n < team_size():
			return t
	return -1


func slot_count() -> int:
	return clampi(int(config.get("teams", 5)), 1, MAX_TEAMS) * team_size()


func humans() -> int:
	var n := 0
	for pid in players:
		if not players[pid].bot:
			n += 1
	return n


func remove_bots() -> void:
	for pid in players.keys():
		if players[pid].bot:
			players.erase(pid)
	_broadcast_lobby()


func is_bot(pid: int) -> bool:
	return pid <= BOT_ID_BASE


func human_peers() -> Array:
	var out := []
	for pid in players:
		if not players[pid].bot and players[pid].connected and pid != 1:
			out.append(pid)
	return out


# ------------------------------------------------------------------ events

func _on_peer_connected(id: int) -> void:
	# Building the map blocks the main thread (and with it ENet's keep-alives) for 30-45 s; ENet's default timeout
	# would drop the connection in the middle of loading. Allow up to three minutes of silence.
	if peer and peer.host:
		for p in peer.host.get_peers():
			p.set_timeout(64, 90000, 180000)
	# then wait for _hello


func _on_peer_disconnected(id: int) -> void:
	if not is_server:
		return
	if players.has(id):
		if players[id].in_match:
			players[id].connected = false  # keep the slot so the player can reconnect
		else:
			players.erase(id)
	_broadcast_lobby()
	Game.on_peer_left(id)


func _on_connected() -> void:
	local_pid = multiplayer.get_unique_id()
	_hello.rpc_id(1, Settings.player_name(), VERSION, platform(), Profile.look, Profile.id, Profile.level())


func _fail(reason: String) -> void:
	shutdown()
	connection_failed.emit(reason)


func _drop(reason: String) -> void:
	shutdown()
	disconnected.emit(reason)


static func platform() -> String:
	## Shown in the lobby: phones and PCs play in the same matches.
	if OS.has_feature("mobile") or Settings.is_mobile():
		return "Mobile"
	return "PC"


@rpc("any_peer", "reliable")
func _hello(pname: String, version: String, plat: String = "PC", look: Dictionary = {}, profile: String = "", level: int = 1) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if version != VERSION:
		_kick.rpc_id(id, "Version mismatch (host %s, you %s). Open the Aetherion Launcher to update." % [VERSION, version])
		peer.disconnect_peer(id)
		return
	pname = pname.strip_edges().substr(0, 20)
	if pname == "":
		pname = "Player"
	# Reconnect: a disconnected in-match slot with the same name is handed back.
	for pid in players.keys():
		var p: Dictionary = players[pid]
		if not p.bot and not p.connected and p.name == pname:
			players.erase(pid)
			p.connected = true
			players[id] = p
			_welcome.rpc_id(id, id)
			_broadcast_lobby()
			Game.on_peer_reconnected(id, pid)
			return
	if humans() >= slot_count():
		_kick.rpc_id(id, "The game is full.")
		peer.disconnect_peer(id)
		return
	var taken := players.values().map(func(p): return p.name)
	var base := pname
	var n := 2
	while pname in taken:
		pname = "%s %d" % [base, n]
		n += 1
	players[id] = _new_player(pname, false)
	players[id].join = _next_join()
	players[id].platform = plat
	players[id].look = look
	players[id].profile = profile.substr(0, 32)
	players[id].level = level
	players[id].team = _first_free_team(id)
	_welcome.rpc_id(id, id)
	_broadcast_lobby()
	Game.on_peer_joined(id)


@rpc("authority", "reliable")
func _welcome(pid: int) -> void:
	local_pid = pid
	online = true
	connected_to_server.emit()


@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	_drop(reason)


# ------------------------------------------------------------------ lobby

func _next_join() -> int:
	_join_seq += 1
	return _join_seq


func room_host() -> int:
	## (r15) Who runs the lobby: whoever hosts the game, or on a dedicated (official) server the first slot, the human
	## who has been in the lobby longest (the next one takes over when they leave). They change the match settings and
	## press Start; anyone else has a Ready button. 0: nobody (an empty official server).
	if not is_server:
		return int(config.get("room_host", 1))
	if not dedicated:
		return 1
	var best := 0
	var best_j := 1 << 30
	for pid in players:
		var p: Dictionary = players[pid]
		if not p.bot and p.connected and int(p.get("join", 0)) < best_j:
			best_j = int(p.get("join", 0))
			best = pid
	return best


func is_room_host() -> bool:
	return local_pid != 0 and room_host() == local_pid


func not_ready() -> Array:
	## Names of the humans in the lobby (besides its host) who have not pressed Ready: the host waits for them.
	var host_pid := room_host()
	var out := []
	for pid in players:
		var p: Dictionary = players[pid]
		if not p.bot and p.connected and pid != host_pid and not p.ready:
			out.append(str(p.name))
	return out


func request_start() -> void:
	## The lobby's Start button. Only its host may start, and only once every other human is Ready (alone, or with
	## nobody but bots, at once).
	if is_server:
		if is_room_host() and not_ready().is_empty():
			Game.start_match()
	else:
		_req_start.rpc_id(1)


@rpc("any_peer", "reliable")
func _req_start() -> void:
	if not is_server:
		return
	var pid := multiplayer.get_remote_sender_id()
	if pid != room_host() or not not_ready().is_empty():
		print("[net] start refused for %d (host %d, not ready: %s)" % [pid, room_host(), ", ".join(not_ready())])
		return
	print("[net] %s started the match" % str(players.get(pid, {}).get("name", pid)))
	Game.start_match()


func request_config(key: String, value) -> void:
	## A lobby setting from its host (the player hosting, or the first slot on an official server).
	if is_server:
		set_config(key, value)
	else:
		_req_config.rpc_id(1, key, value)


@rpc("any_peer", "reliable")
func _req_config(key: String, value) -> void:
	if not is_server or Game.state != "lobby":
		return
	if multiplayer.get_remote_sender_id() != room_host() or not key in ROOM_KEYS:
		return
	if key == "game_mode" and config.get("official", false):
		return   # an official server is listed as one mode
	set_config(key, value)


func _broadcast_lobby() -> void:
	if not is_server:
		return
	config.room_host = room_host()
	lobby_changed.emit()
	if online:
		_lobby_state.rpc(players, config)


@rpc("authority", "reliable")
func _lobby_state(p: Dictionary, cfg: Dictionary) -> void:
	players = p
	config = cfg
	lobby_changed.emit()


func request_set_ready(value: bool) -> void:
	if is_server:
		_apply_ready(local_pid, value)
	else:
		_req_ready.rpc_id(1, value)


@rpc("any_peer", "reliable")
func _req_ready(value: bool) -> void:
	if is_server:
		_apply_ready(multiplayer.get_remote_sender_id(), value)


func _apply_ready(pid: int, value: bool) -> void:
	if players.has(pid):
		players[pid].ready = value
		_broadcast_lobby()


func request_look(look: Dictionary) -> void:
	## The player changed their outfit in the Locker while in a lobby.
	if is_server:
		if players.has(local_pid):
			players[local_pid].look = look
			_broadcast_lobby()
	else:
		_req_look.rpc_id(1, look)


@rpc("any_peer", "reliable")
func _req_look(look: Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if is_server and players.has(pid) and JSON.stringify(look).length() < 2048:
		players[pid].look = look
		_broadcast_lobby()


func send_prefs() -> void:
	## This player's own choices everyone else needs to draw them (the laser pointer colour), to the host.
	if peer == null:
		return
	var prefs := {"laser": str(Settings.get_value("player", "laser_color"))}
	if is_server:
		_apply_prefs(local_pid, prefs)
	else:
		_req_prefs.rpc_id(1, prefs)


@rpc("any_peer", "reliable")
func _req_prefs(prefs: Dictionary) -> void:
	if is_server:
		_apply_prefs(multiplayer.get_remote_sender_id(), prefs)


func _apply_prefs(pid: int, prefs: Dictionary) -> void:
	if not players.has(pid):
		return
	var l := str(prefs.get("laser", "red"))
	players[pid].laser = l if Settings.LASER_COLORS.has(l) else "red"
	_broadcast_lobby()


func request_loadout(loadout: Dictionary) -> void:
	## The player picked their Deathmatch guns in Game Setup ({"primary": id, "secondary": id, (r22) "att_primary":
	## [attachment ids], "att_secondary": [...]}).
	if is_server:
		_apply_loadout(local_pid, loadout)
	else:
		_req_loadout.rpc_id(1, loadout)


@rpc("any_peer", "reliable")
func _req_loadout(loadout: Dictionary) -> void:
	if is_server:
		_apply_loadout(multiplayer.get_remote_sender_id(), loadout)


func _apply_loadout(pid: int, loadout: Dictionary) -> void:
	## Keeps only guns the Deathmatch rules allow; anything else falls back to the default pick. (r22) Attachments are
	## checked here too (never trust the client): known, fitting that gun, one per slot.
	if not players.has(pid):
		return
	var dm: Dictionary = Defs.rules.get("deathmatch", {})
	var prim := str(loadout.get("primary", ""))
	var sec := str(loadout.get("secondary", ""))
	if not prim in dm.get("primary", []):
		prim = str(dm.get("default_primary", "rifle_m416"))
	if not sec in dm.get("secondary", []):
		sec = str(dm.get("default_secondary", "pistol_9"))
	var ap = loadout.get("att_primary", [])
	var asec = loadout.get("att_secondary", [])
	players[pid].loadout = {"primary": prim, "secondary": sec, "att_primary": Attach.sanitize(prim, ap if ap is Array else []),
		"att_secondary": Attach.sanitize(sec, asec if asec is Array else [])}
	loadout_received.emit(pid)
	_broadcast_lobby()


func request_team(team: int) -> void:
	if is_server:
		_apply_team(local_pid, team)
	else:
		_req_team.rpc_id(1, team)


@rpc("any_peer", "reliable")
func _req_team(team: int) -> void:
	if is_server:
		_apply_team(multiplayer.get_remote_sender_id(), team)


func _apply_team(pid: int, team: int) -> void:
	if not players.has(pid):
		return
	var size := team_size()
	var count := 0
	for q in players:
		if q != pid and players[q].team == team:
			count += 1
	if team >= 0 and (count >= size or team >= int(config.get("teams", 5))):
		return
	players[pid].team = team
	_broadcast_lobby()


func is_dm() -> bool:
	return str(config.get("game_mode", "classic")) == "deathmatch"


func max_team_size() -> int:
	return dm_max_team_size() if is_dm() else MAX_TEAM_SIZE


func dm_teams() -> int:
	## Deathmatch team count: 2 or 3 (2 on a map that allows only two, Freight Delight).
	return clampi(int(config.get("teams", 3)), 2, dm_max_teams())


static func map_limit(map_id: String, key: String, fallback: int) -> int:
	## A Deathmatch map's own cap (rules.json deathmatch.map_limits.<map>.<key>), or fallback.
	var lim = Defs.rule("deathmatch.map_limits.%s" % map_id, {})
	return int(lim.get(key, fallback)) if lim is Dictionary else fallback


func dm_max_teams(map_id: String = "") -> int:
	return map_limit(map_id if map_id != "" else str(config.get("map", "")), "max_teams", DM_MAX_TEAMS)


func dm_max_team_size(map_id: String = "") -> int:
	## Deathmatch players per team: 7, or the map's own limit (Freight Delight: 12).
	return map_limit(map_id if map_id != "" else str(config.get("map", "")), "max_team_size", DM_MAX_TEAM_SIZE)


func dm_field_optional(map_id: String = "") -> bool:
	## Maps whose Deathmatch field is off unless the host turns it on (and then stops at half its radius).
	return (map_id if map_id != "" else str(config.get("map", ""))) in Defs.rule("deathmatch.field_optional_maps", ["malasugue_mall"])


func set_config(key: String, value) -> void:
	if not is_server:
		return
	if key == "game_mode":
		value = str(value) if str(value) in GAME_MODES else "classic"
		var was := str(config.get("game_mode", "classic"))
		config.game_mode = value
		if value != was:
			# Each mode has its own map and team layout; switching resets them to that mode's defaults.
			config.map = str(Defs.rule("game_modes.%s.map" % value, "kalinaw"))
			if value == "deathmatch":
				config.teams = clampi(int(Defs.rule("deathmatch.teams", 3)), 2, DM_MAX_TEAMS)
				config.team_size = int(Defs.rule("deathmatch.team_size", DM_MAX_TEAM_SIZE))
			else:
				config.teams = 5
				config.mode = "squad"
				config.team_size = int(Defs.rule("modes.squad.team_size", 4))
		key = "teams"  # re-seat players for the new team layout
	elif key == "map":
		# (r15) Each mode has its own maps (rules.json game_modes.<mode>.maps): Deathmatch picks Malasugue Mall (the default), Freight Delight or Lawless Sub.
		var mode := str(config.get("game_mode", "classic"))
		var allowed: Array = Defs.rule("game_modes.%s.maps" % mode, [Defs.rule("game_modes.%s.map" % mode, "kalinaw")])
		var was_map := str(config.get("map", ""))
		config.map = str(value) if str(value) in MAPS and str(value) in allowed else str(Defs.rule("game_modes.%s.map" % mode, "kalinaw"))
		if is_dm():
			# A map with its own team layout (Freight Delight: two teams, 12 a side) sets it when picked; leaving it
			# brings the sizes back within the other maps' limits.
			var def_size := map_limit(str(config.map), "team_size", 0)
			if def_size > 0 and str(config.map) != was_map:
				config.team_size = def_size
			config.teams = clampi(int(config.get("teams", 3)), 2, dm_max_teams())
			config.team_size = clampi(int(config.get("team_size", DM_MAX_TEAM_SIZE)), 1, dm_max_team_size())
			key = "teams"   # re-seat players for the new team layout
	elif is_dm() and key == "teams":
		config.teams = clampi(int(value), 2, dm_max_teams())
	elif is_dm() and key == "team_size":
		config.team_size = clampi(int(value), 1, dm_max_team_size())
	elif is_dm() and key == "mode":
		pass  # solo/duo/squad is a Classic setting
	elif key == "day_len":
		config.day_len = int(value) if int(value) in DAY_LENS else 300
	elif key == "dm_win":
		config.dm_win = str(value) if str(value) in DM_WINS else "wipe"
	elif key == "dm_score":
		config.dm_score = int(value) if int(value) in DM_SCORES else 10
	elif key == "dm_time":
		config.dm_time = int(value) if int(value) in DM_TIMES else 14
	elif key == "dm_field":
		config.dm_field = value == true or str(value).to_lower() in ["true", "1", "on"]
	elif key == "bot_skill":
		config.bot_skill = str(value).to_lower() if str(value).to_lower() in BOT_SKILLS else "normal"
	else:
		config[key] = value
	if key == "team_size" and not is_dm():
		config.mode = {1: "solo", 2: "duo"}.get(int(value), "squad")
	if key == "mode" and not is_dm():
		config.team_size = int(Defs.rule("modes.%s.team_size" % str(value), 4))
	if key in ["teams", "team_size"]:
		# Fewer or smaller teams: whoever no longer fits goes back to "no team yet".
		var counts := {}
		for pid in players:
			var t: int = players[pid].team
			if t >= int(config.teams) or (t >= 0 and int(counts.get(t, 0)) >= team_size()):
				players[pid].team = -1
			elif t >= 0:
				counts[t] = int(counts.get(t, 0)) + 1
	_broadcast_lobby()


func team_size() -> int:
	return clampi(int(config.get("team_size", Defs.rule("modes.%s.team_size" % config.get("mode", "squad"), 4))), 1, max_team_size())


func assign_teams() -> void:
	## Fill empty team slots: keep chosen teams, then pack the rest in join order (Deathmatch: into the smallest
	## team, so bots even them out).
	var size := team_size()
	var dm := is_dm()
	var counts := {}
	for pid in players:
		var t: int = players[pid].team
		if dm and t >= dm_teams():
			players[pid].team = -1
			continue
		if t >= 0:
			counts[t] = counts.get(t, 0) + 1
	for pid in players:
		if players[pid].team >= 0 and counts[players[pid].team] <= size:
			continue
		var t := 0
		if dm:
			for k in dm_teams():
				if int(counts.get(k, 0)) < int(counts.get(t, 0)):
					t = k
		while counts.get(t, 0) >= size:
			t += 1
		players[pid].team = t
		counts[t] = counts.get(t, 0) + 1
	_broadcast_lobby()


# ------------------------------------------------------------------ clock and transport

func _physics_process(delta: float) -> void:
	if is_server:
		tick += 1
	elif online and _last_snapshot_tick >= 0:
		_tick_float += delta * Defs.TICK_RATE
		tick = int(_tick_float)
	if online and not is_server:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 1.0
			_ping.rpc_id(1, Time.get_ticks_usec())


func on_snapshot_tick(server_tick: int) -> void:
	## Called by the world when a snapshot arrives; keeps the client's tick estimate close to the server's.
	if server_tick <= _last_snapshot_tick:
		return
	_last_snapshot_tick = server_tick
	var target := float(server_tick) + rtt_s * 0.5 * Defs.TICK_RATE
	if absf(_tick_float - target) > 12.0:
		_tick_float = target
	else:
		_tick_float = lerpf(_tick_float, target, 0.08)


func interp_tick() -> float:
	## The server tick remote entities are rendered at.
	return _tick_float - float(Defs.rule("net.interp_delay_s", 0.1)) * Defs.TICK_RATE if not is_server else float(tick)


@rpc("any_peer", "unreliable")
func _ping(t: int) -> void:
	_pong.rpc_id(multiplayer.get_remote_sender_id(), t)


@rpc("authority", "unreliable")
func _pong(t: int) -> void:
	var sample := (Time.get_ticks_usec() - t) / 1_000_000.0
	rtt_s = sample if rtt_s == 0.0 else lerpf(rtt_s, sample, 0.2)


func peer_rtt(pid: int) -> float:
	## Server-side round trip estimate for a peer (seconds).
	if not is_server or pid == 1 or is_bot(pid) or peer == null:
		return 0.0
	var p := peer.get_peer(pid)
	if p == null:
		return 0.0
	return p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 1000.0


func send_snapshot(pid: int, bytes: PackedByteArray) -> void:
	if pid == 1:
		return
	_snapshot.rpc_id(pid, bytes)


@rpc("authority", "unreliable_ordered", "call_remote", CH_SNAPSHOT)
func _snapshot(bytes: PackedByteArray) -> void:
	snapshot_received.emit(bytes)


func send_voice(bytes: PackedByteArray) -> void:
	if is_server:
		Game.relay_voice(local_pid, bytes)
	else:
		_voice_up.rpc_id(1, bytes)


@rpc("any_peer", "unreliable_ordered", "call_remote", CH_VOICE)
func _voice_up(bytes: PackedByteArray) -> void:
	if is_server and bytes.size() < 4096:
		Game.relay_voice(multiplayer.get_remote_sender_id(), bytes)


func deliver_voice(to_pid: int, from_pid: int, bytes: PackedByteArray, src_eid: int = -1, kind: int = 0) -> void:
	if to_pid == local_pid:
		voice_received.emit(from_pid, bytes, src_eid, kind)
	else:
		_voice_down.rpc_id(to_pid, from_pid, bytes, src_eid, kind)


@rpc("authority", "unreliable_ordered", "call_remote", CH_VOICE)
func _voice_down(from_pid: int, bytes: PackedByteArray, src_eid: int, kind: int) -> void:
	voice_received.emit(from_pid, bytes, src_eid, kind)
