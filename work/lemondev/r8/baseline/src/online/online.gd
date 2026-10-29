extends Node
## Online services for the menus: presence (who is online), open games (from the stats server and from the local
## network), match results and the leaderboard. Everything is optional: with no stats server the menus still list
## games on the same Wi-Fi/LAN (hosts broadcast a beacon) and the profile keeps counting XP on this device.
##
## Stats server address: Settings online.server ("host" or "host:port"); else the one heard on the local network;
## else this computer (a dedicated server started here with --master or --stats).

signal changed            # online players, games or connection state changed

const MasterServer := preload("res://src/online/master_server.gd")
const BEACON_PORT := 27416

var online_players: Array = []   # from the stats server
var server_games: Array = []     # from the stats server
var lan_games: Dictionary = {}   # "ip:port" -> {info, t}
var connected := false           # last request to the stats server succeeded
var status := "Looking for the stats server…"
var lan_master := ""             # "ip:port" heard on the network
var game_id := ""
var leaderboard_cache: Dictionary = {}   # by -> rows

var _hello_t := 0.0
var _game_t := 0.0
var _beacon_t := 0.0
var _clock := 0.0
var _udp := PacketPeerUDP.new()
var _udp_ok := false
var _send := PacketPeerUDP.new()
var _busy := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" and not Game.arg("autotest") and not Game.arg("stats_server"):
		return
	_udp_ok = _udp.bind(BEACON_PORT, "0.0.0.0") == OK
	_send.set_broadcast_enabled(true)
	_send.set_dest_address("255.255.255.255", BEACON_PORT)
	game_id = Crypto.new().generate_random_bytes(6).hex_encode()


func server_address() -> String:
	var s := str(Game.arg("stats_server", Settings.get_value("online", "server"))).strip_edges()
	if s == "":
		s = lan_master if lan_master != "" else "127.0.0.1"
	if not s.contains(":"):
		s += ":%d" % MasterServer.PORT
	return s


func _process(dt: float) -> void:
	_clock += dt
	# Beacons from hosts and stats servers on this network.
	while _udp_ok and _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if not (d is Dictionary):
			continue
		if str(d.get("t", "")) == "master":
			lan_master = "%s:%d" % [ip, int(d.get("port", MasterServer.PORT))]
		elif str(d.get("t", "")) == "game" and str(d.get("game", "")) != game_id:
			d.address = ip
			lan_games["%s:%d" % [ip, int(d.get("port", Net.DEFAULT_PORT))]] = {"info": d, "t": _clock}
			changed.emit()
	for k in lan_games.keys():
		if _clock - float(lan_games[k].t) > 4.0:
			lan_games.erase(k)
			changed.emit()
	if DisplayServer.get_name() == "headless":
		return
	_hello_t -= dt
	if _hello_t <= 0.0:
		_hello_t = 5.0
		_hello()
	var hosting := Net.is_server and Net.online and not Net.dedicated and Game.state in ["lobby", "loading", "match"]
	if hosting:
		_beacon_t -= dt
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			_send.put_packet(JSON.stringify(game_info()).to_utf8_buffer())
		_game_t -= dt
		if _game_t <= 0.0:
			_game_t = 3.0
			_post("/game", game_info(), "game")


func game_info() -> Dictionary:
	var humans := 0
	for pid in Net.players:
		if not Net.players[pid].bot:
			humans += 1
	var gname := str(Net.config.get("name", "")).strip_edges()
	if gname == "":
		gname = "%s's game" % Settings.player_name()
	return {"t": "game", "game": game_id, "name": gname, "host": Settings.player_name(),
		"port": Net.port, "players": humans, "max": Net.slot_count(), "teams": int(Net.config.get("teams", 5)),
		"team_size": Net.team_size(), "bots": bool(Net.config.get("bots", true)), "state": Game.state, "version": Net.VERSION,
		"platform": Net.platform(), "game_mode": str(Net.config.get("game_mode", "classic")), "map": str(Net.config.get("map", "kalinaw"))}


func status_text() -> String:
	match Game.state:
		"lobby":
			return "In a lobby"
		"loading", "match":
			return "In a match"
		"results":
			return "Match results"
	return "In the menu"


func _hello() -> void:
	_post("/hello", {"id": Profile.id, "name": Settings.player_name(), "platform": Net.platform(), "level": Profile.level(),
		"status": status_text(), "game": game_id if Net.is_server and Net.online else ""}, "hello", func(ok: bool, d: Dictionary):
			var was := connected
			connected = ok
			if ok:
				online_players = d.get("online", [])
				server_games = d.get("games", [])
				status = "Stats server online · %d player%s" % [online_players.size(), "" if online_players.size() == 1 else "s"]
				if d.get("profile") is Dictionary and not (d.profile as Dictionary).is_empty():
					Profile.merge_server(d.profile)
			else:
				online_players = []
				server_games = []
				status = "Stats server offline · local games only"
			changed.emit())


func games() -> Array:
	## Every open game we know of: the stats server's list plus local-network beacons (deduplicated).
	var out := {}
	for g in server_games:
		if str(g.get("game", "")) != game_id:
			out["%s:%d" % [str(g.get("address", "")), int(g.get("port", Net.DEFAULT_PORT))]] = g.duplicate()
	for k in lan_games:
		var g2: Dictionary = (lan_games[k].info as Dictionary).duplicate()
		g2.lan = true
		out[k] = g2
	var arr := out.values()
	arr.sort_custom(func(a, b): return int(a.get("players", 0)) > int(b.get("players", 0)))
	return arr


func post_result(rows: Array) -> void:
	## Host: the finished match, every human's line (profile id, kills, damage, place, XP).
	var players := []
	for r in rows:
		if r.get("bot", false) or str(r.get("profile", "")) == "":
			continue
		players.append({"id": r.profile, "name": r.name, "platform": r.get("platform", "PC"), "kills": r.kills, "damage": r.get("damage", 0.0),
			"place": r.get("place", 99), "winner": r.winner, "time": r.time, "xp": r.get("xp", 0)})
	if not players.is_empty():
		_post("/result", {"game": game_id, "version": Net.VERSION, "players": players}, "result")


func fetch_leaderboard(by: String, cb: Callable) -> void:
	_http_get("/leaderboard?by=%s&n=50" % by, "lb_" + by, func(ok: bool, d: Dictionary):
		if ok:
			leaderboard_cache[by] = d.get("rows", [])
		cb.call(ok, d.get("rows", leaderboard_cache.get(by, []))))


# ------------------------------------------------------------------ http

func _post(path: String, body: Dictionary, tag: String, cb: Callable = Callable()) -> void:
	_request(path, HTTPClient.METHOD_POST, JSON.stringify(body), tag, cb)


func _http_get(path: String, tag: String, cb: Callable = Callable()) -> void:
	_request(path, HTTPClient.METHOD_GET, "", tag, cb)


func _request(path: String, method: int, body: String, tag: String, cb: Callable) -> void:
	if _busy.get(tag, false):
		return
	_busy[tag] = true
	var h := HTTPRequest.new()
	h.timeout = 4.0
	add_child(h)
	h.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray):
		_busy[tag] = false
		h.queue_free()
		var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
		var d = JSON.parse_string(data.get_string_from_utf8()) if ok else null
		if cb.is_valid():
			cb.call(ok and d is Dictionary, d if d is Dictionary else {}))
	var err := h.request("http://%s%s" % [server_address(), path], ["Content-Type: application/json"], method, body)
	if err != OK:
		_busy[tag] = false
		h.queue_free()
		if cb.is_valid():
			cb.call(false, {})
