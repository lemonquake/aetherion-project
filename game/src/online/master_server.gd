extends Node
## The stats server: who is online, which games are open, every reported match, profiles and the leaderboard.
## A small HTTP/JSON service in the game itself, so a dedicated server runs it with one flag:
##   godot --headless --path game -- --master [--master_port=27420] [--data=<dir>]
##   godot --headless --path game -- --server --stats ...      (a dedicated match server that is also the stats server)
## It also announces itself on the local network (UDP broadcast), so phones and PCs on the same Wi-Fi find it without
## typing an address. Records are saved to <data>/stats.json (default user://master).
##
## API (all JSON):
##   POST /hello   {id, name, platform, level, status, game}  -> {ok, online: [...], games: [...]}   presence, every 5 s
##   POST /game    {game, name, host, port, players, max, teams, team_size, state, version, address?}  open game, every 3 s
##   POST /result  {game, version, players: [{id, name, kills, damage, place, winner, time, xp}]}   a finished match
##   GET  /profile?id=<id>        GET /leaderboard?by=xp|wins|kills&n=50        GET /status
## There are no accounts: a profile is a random id made on the player's device. Anyone who can reach the server can
## post results; run it for friends, not for strangers.

const PORT := 27420
const BEACON_PORT := 27416
const PRESENCE_S := 20.0
const GAME_S := 12.0

var port := PORT
var data_dir := "user://master"
var profiles: Dictionary = {}   # id -> {name, xp, matches, wins, top5, kills, deaths, damage, time_s, best_place, platform, last_seen}
var online: Dictionary = {}     # id -> {name, platform, level, status, game, t}
var games: Dictionary = {}      # game id -> {..., address, t}
var matches := 0
var _tcp := TCPServer.new()
var _conns: Array = []          # {peer: StreamPeerTCP, buf: PackedByteArray, t}
var _dirty := false
var _save_t := 0.0
var _beacon := PacketPeerUDP.new()
var _beacon_t := 0.0
var _clock := 0.0


func start(p: int = PORT, dir: String = "") -> Error:
	port = p
	if dir != "":
		data_dir = dir
	DirAccess.make_dir_recursive_absolute(data_dir)
	_load()
	var err := _tcp.listen(port)
	if err != OK:
		push_error("[master] cannot listen on %d (%d)" % [port, err])
		return err
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", BEACON_PORT)
	print("[master] stats server on port %d, %d profiles, data in %s" % [port, profiles.size(), ProjectSettings.globalize_path(data_dir)])
	return OK


func _process(dt: float) -> void:
	_clock += dt
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		_conns.append({"peer": peer, "buf": PackedByteArray(), "t": 0.0})
	for i in range(_conns.size() - 1, -1, -1):
		var c: Dictionary = _conns[i]
		c.t += dt
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or c.t > 5.0:
			peer.disconnect_from_host()
			_conns.remove_at(i)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var r := peer.get_data(mini(n, 65536))
			if r[0] == OK:
				var b: PackedByteArray = c.buf
				b.append_array(r[1])
				c.buf = b
		var req := _parse(c.buf)
		if req.is_empty():
			if (c.buf as PackedByteArray).size() > 262144:
				peer.disconnect_from_host()
				_conns.remove_at(i)
			continue
		var res := _handle(req, peer.get_connected_host())
		var body := JSON.stringify(res[1]).to_utf8_buffer()
		var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n" % [
			res[0], "OK" if res[0] == 200 else "Error", body.size()]
		peer.put_data(head.to_utf8_buffer())
		peer.put_data(body)
		peer.disconnect_from_host()
		_conns.remove_at(i)
	# Expire presence and games.
	for k in online.keys():
		if _clock - float(online[k].t) > PRESENCE_S:
			online.erase(k)
	for k in games.keys():
		if _clock - float(games[k].t) > GAME_S:
			games.erase(k)
	_beacon_t -= dt
	if _beacon_t <= 0.0:
		_beacon_t = 1.0
		_beacon.put_packet(JSON.stringify({"t": "master", "port": port, "v": Net.VERSION}).to_utf8_buffer())
	_save_t -= dt
	if _dirty and _save_t <= 0.0:
		_save()


func _parse(buf: PackedByteArray) -> Dictionary:
	## {method, path, query, body} once the whole request is in, else {}.
	var text := buf.get_string_from_utf8()
	var he := text.find("\r\n\r\n")
	if he < 0:
		return {}
	var lines := text.substr(0, he).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "/", "query": {}, "body": ""}
	var length := 0
	for l in lines:
		if l.to_lower().begins_with("content-length:"):
			length = int(l.substr(15).strip_edges())
	var body_bytes := buf.slice(he + 4)
	if body_bytes.size() < length:
		return {}
	var url := first[1]
	var q := {}
	var qi := url.find("?")
	if qi >= 0:
		for pair in url.substr(qi + 1).split("&"):
			var kv := pair.split("=")
			q[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else ""
		url = url.substr(0, qi)
	return {"method": first[0], "path": url, "query": q, "body": body_bytes.slice(0, length).get_string_from_utf8()}


func _handle(req: Dictionary, from: String) -> Array:
	var body = JSON.parse_string(req.body) if req.body != "" else {}
	if not (body is Dictionary):
		body = {}
	match [req.method, req.path]:
		["POST", "/hello"]:
			var pid := str(body.get("id", "")).substr(0, 32)
			if pid == "":
				return [400, {"ok": false, "error": "no id"}]
			online[pid] = {"id": pid, "name": str(body.get("name", "Player")).substr(0, 20), "platform": str(body.get("platform", "PC")),
				"level": int(body.get("level", 1)), "status": str(body.get("status", "menu")).substr(0, 40), "game": str(body.get("game", "")), "t": _clock}
			var p: Dictionary = profiles.get(pid, {})
			if not p.is_empty():
				p.name = online[pid].name
				p.last_seen = Time.get_unix_time_from_system()
			return [200, {"ok": true, "online": _online_list(), "games": _games_list(), "profile": p}]
		["POST", "/game"]:
			var gid := str(body.get("game", "")).substr(0, 32)
			if gid == "":
				return [400, {"ok": false}]
			var g: Dictionary = body.duplicate()
			g.t = _clock
			if str(g.get("address", "")) == "":
				g.address = from
			games[gid] = g
			return [200, {"ok": true}]
		["POST", "/result"]:
			return [200, _result(body)]
		["GET", "/profile"]:
			return [200, {"ok": true, "profile": profiles.get(str(req.query.get("id", "")), {})}]
		["GET", "/leaderboard"]:
			return [200, {"ok": true, "by": str(req.query.get("by", "xp")), "rows": leaderboard(str(req.query.get("by", "xp")), int(req.query.get("n", "50")))}]
		["GET", "/online"]:
			return [200, {"ok": true, "online": _online_list()}]
		["GET", "/games"]:
			return [200, {"ok": true, "games": _games_list()}]
		["GET", "/status"]:
			return [200, {"ok": true, "version": Net.VERSION, "profiles": profiles.size(), "online": online.size(), "games": games.size(), "matches": matches}]
	return [404, {"ok": false, "error": "unknown"}]


func _online_list() -> Array:
	var out := online.values().map(func(o): return {"id": o.id, "name": o.name, "platform": o.platform, "level": o.level, "status": o.status, "game": o.game})
	out.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


func _games_list() -> Array:
	var out := []
	for gid in games:
		var g: Dictionary = games[gid].duplicate()
		g.erase("t")
		g.game = gid
		out.append(g)
	return out


func _result(body: Dictionary) -> Dictionary:
	matches += 1
	var updated := []
	for r in body.get("players", []):
		if not (r is Dictionary) or str(r.get("id", "")) == "":
			continue
		var pid := str(r.id).substr(0, 32)
		var p: Dictionary = profiles.get(pid, {"name": "Player", "xp": 0, "matches": 0, "wins": 0, "top5": 0, "kills": 0, "deaths": 0,
			"damage": 0.0, "time_s": 0.0, "best_place": 0, "platform": "PC"})
		p.name = str(r.get("name", p.name)).substr(0, 20)
		p.platform = str(r.get("platform", p.get("platform", "PC")))
		p.xp = int(p.xp) + clampi(int(r.get("xp", 0)), 0, 5000)
		p.matches = int(p.matches) + 1
		var won := bool(r.get("winner", false))
		var place := int(r.get("place", 99))
		p.wins = int(p.wins) + (1 if won else 0)
		p.top5 = int(p.top5) + (1 if place <= 5 else 0)
		p.kills = int(p.kills) + clampi(int(r.get("kills", 0)), 0, 60)
		p.deaths = int(p.deaths) + (0 if won else 1)
		p.damage = float(p.damage) + clampf(float(r.get("damage", 0.0)), 0.0, 20000.0)
		p.time_s = float(p.time_s) + clampf(float(r.get("time", 0.0)), 0.0, 7200.0)
		if int(p.best_place) == 0 or place < int(p.best_place):
			p.best_place = place
		p.last_seen = Time.get_unix_time_from_system()
		profiles[pid] = p
		updated.append(pid)
	_dirty = true
	_save_t = minf(_save_t, 2.0) if _save_t > 0.0 else 2.0
	return {"ok": true, "updated": updated.size()}


func leaderboard(by: String, n: int) -> Array:
	var key: String = by if by in ["xp", "wins", "kills", "matches", "damage"] else "xp"
	var rows := []
	for pid in profiles:
		var p: Dictionary = profiles[pid]
		rows.append({"id": pid, "name": p.name, "platform": p.get("platform", "PC"), "level": Profile.level_of(int(p.xp)), "xp": int(p.xp),
			"wins": int(p.wins), "kills": int(p.kills), "matches": int(p.matches), "damage": int(float(p.damage)),
			"kd": snappedf(float(p.kills) / maxf(float(p.deaths), 1.0), 0.01)})
	rows.sort_custom(func(a, b): return float(a[key]) > float(b[key]) or (float(a[key]) == float(b[key]) and int(a.xp) > int(b.xp)))
	for i in rows.size():
		rows[i].rank = i + 1
	return rows.slice(0, clampi(n, 1, 200))


func _load() -> void:
	var f := FileAccess.open(data_dir.path_join("stats.json"), FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			profiles = d.get("profiles", {})
			matches = int(d.get("matches", 0))


func _save() -> void:
	_dirty = false
	_save_t = 5.0
	var tmp := data_dir.path_join("stats.json.tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"profiles": profiles, "matches": matches, "saved": Time.get_datetime_string_from_system(true)}))
	f.close()
	DirAccess.rename_absolute(tmp, data_dir.path_join("stats.json"))


func _exit_tree() -> void:
	if _dirty:
		_save()
	_tcp.stop()
