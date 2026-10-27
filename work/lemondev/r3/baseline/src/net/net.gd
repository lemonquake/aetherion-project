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
signal voice_received(from_pid: int, bytes: PackedByteArray)

## Players must run the same build: the map is generated on every machine. Raise application/config/version in
## project.godot whenever the map, rules or netcode change.
var VERSION: String = "aetherion-" + str(ProjectSettings.get_setting("application/config/version", "0"))
const DEFAULT_PORT := 27415
const CH_RELIABLE := 0
const CH_SNAPSHOT := 1
const CH_INPUT := 2
const CH_VOICE := 3
const BOT_ID_BASE := -1000

var peer: ENetMultiplayerPeer
var is_server := false
var dedicated := false
var online := false
var local_pid := 0

## pid -> {name, team, ready, bot, connected, in_match}
var players: Dictionary = {}
## Match configuration chosen in the lobby by the host.
# bot_count 31: a host alone fills the lobby to rules.json player_target (32). A phone hosting runs the server and
# every bot's AI on its own CPU, so it starts with 15; matches hosted on a PC or a dedicated server still fill to 32.
var config: Dictionary = {"mode": "squad", "bots": true, "bot_count": 15 if Settings.is_mobile() else 31, "map_seed": 1729, "zone_speed": 1.0}

## Server tick (authoritative on the server, estimated on clients).
var tick: int = 0
var _tick_float: float = 0.0
var _last_snapshot_tick: int = -1
var rtt_s: float = 0.0
var _ping_timer: float = 0.0
var _next_bot := BOT_ID_BASE


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
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, int(Defs.rule("max_players", 40)) + 2, 4)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	dedicated = as_dedicated
	online = true
	local_pid = 1
	tick = 0
	players.clear()
	if not dedicated:
		players[1] = _new_player(Settings.player_name(), false)
		players[1].platform = platform()
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
	return {"name": pname, "team": -1, "ready": bot, "bot": bot, "connected": true, "in_match": false}


func add_bot(pname: String) -> int:
	_next_bot -= 1
	players[_next_bot] = _new_player(pname, true)
	_broadcast_lobby()
	return _next_bot


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
	_hello.rpc_id(1, Settings.player_name(), VERSION, platform())


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
func _hello(pname: String, version: String, plat: String = "PC") -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if version != VERSION:
		_kick.rpc_id(id, "Version mismatch (host %s, you %s)." % [VERSION, version])
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
	if players.size() >= int(Defs.rule("max_players", 40)):
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
	players[id].platform = plat
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

func _broadcast_lobby() -> void:
	if not is_server:
		return
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
	if team >= 0 and count >= size:
		return
	players[pid].team = team
	_broadcast_lobby()


func set_config(key: String, value) -> void:
	if not is_server:
		return
	config[key] = value
	_broadcast_lobby()


func team_size() -> int:
	return int(Defs.rule("modes.%s.team_size" % config.get("mode", "squad"), 4))


func assign_teams() -> void:
	## Fill empty team slots: keep chosen teams, then pack the rest in join order.
	var size := team_size()
	var counts := {}
	for pid in players:
		var t: int = players[pid].team
		if t >= 0:
			counts[t] = counts.get(t, 0) + 1
	for pid in players:
		if players[pid].team >= 0 and counts[players[pid].team] <= size:
			continue
		var t := 0
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


func deliver_voice(to_pid: int, from_pid: int, bytes: PackedByteArray) -> void:
	if to_pid == local_pid:
		voice_received.emit(from_pid, bytes)
	else:
		_voice_down.rpc_id(to_pid, from_pid, bytes)


@rpc("authority", "unreliable_ordered", "call_remote", CH_VOICE)
func _voice_down(from_pid: int, bytes: PackedByteArray) -> void:
	voice_received.emit(from_pid, bytes)
