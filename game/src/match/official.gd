extends Node
## An always-on official server (--official, docs/HOSTING.md): a dedicated server nobody hosts by hand.
##   godot --headless -- --server --official --game_mode=classic --public_address=<ip> [--stats_server=127.0.0.1:27420]
## (r15) The first player in the lobby is its host (Net.room_host): they pick the settings and press Start, at once
## when alone (bots fill the seats) or once everyone else is Ready. An idle host does not hold the server: it starts
## by itself host_wait_s after the first player arrived, never sooner than join_grace_s after the latest one. When
## the lobby empties, the settings go back to the server's own. Bots fill the open seats (--bots caps them). A match
## that every human has left ends after empty_match_s, so the server does not keep playing bots against bots.
## Late joiners spectate the running match (Game.on_peer_joined) and play the next one.
## The game is listed on the stats server as official every 3 s, with the public address players connect to.

var game_id := ""
var _countdown := -1.0
var _shown := -2
var _humans := 0
var _empty_t := 0.0
var _post_t := 0.0
var _http: HTTPRequest
var _busy := false
var _last_state := ""
var _defaults := {}   # the server's own match settings (a lobby host's changes last until the lobby empties)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_id = "official-%s-%d" % [str(Net.config.get("game_mode", "classic")), Net.port]
	Net.set_config("official", true)
	Net.set_config("region", str(Defs.rule("official.region", "")))
	_defaults = Net.config.duplicate()
	_http = HTTPRequest.new()
	_http.timeout = 3.0
	add_child(_http)
	_http.request_completed.connect(func(_r, _c, _h, _b): _busy = false)
	print("[official] %s on port %d, listed as %s" % [str(Net.config.get("game_mode", "classic")), Net.port, _address()])


func _process(dt: float) -> void:
	var humans := _connected_humans()
	if Game.state != _last_state:
		if _last_state not in ["", "lobby"] and Game.state == "lobby":
			_next_map()
		_last_state = Game.state
	if Game.state == "lobby":
		_lobby(dt, humans)
	else:
		_set_countdown(-1)
		_countdown = -1.0
	if Game.state == "match" and humans == 0 and Game.world and Game.world.match_server:
		_empty_t += dt
		if _empty_t >= float(Defs.rule("official.empty_match_s", 20)):
			print("[official] everyone left; ending the match")
			_empty_t = 0.0
			Game.world.match_server.force_end()
	else:
		_empty_t = 0.0
	_humans = humans
	_post_t -= dt
	if _post_t <= 0.0:
		_post_t = 3.0
		_post()


func _lobby(dt: float, humans: int) -> void:
	if humans == 0:
		_countdown = -1.0
		_set_countdown(-1)
		_restore_defaults()
		return
	if _countdown < 0.0:
		_countdown = float(Defs.rule("official.host_wait_s", 150))
	if humans > _humans:
		_countdown = maxf(_countdown, float(Defs.rule("official.join_grace_s", 15)))
	_countdown -= dt
	_set_countdown(ceili(maxf(_countdown, 0.0)))
	if _countdown <= 0.0:
		_countdown = -1.0
		_set_countdown(-1)
		print("[official] starting a match with %d human%s" % [humans, "" if humans == 1 else "s"])
		Game.start_match()


func _next_map() -> void:
	## (r16) Deathmatch takes its maps in turn: after each match the lobby moves to the next one (the host can still
	## pick), and an empty lobby keeps it.
	var maps: Array = Defs.rule("game_modes.%s.maps" % str(Net.config.get("game_mode", "classic")), [])
	if maps.size() < 2:
		return
	var nxt := str(maps[(maps.find(str(Net.config.get("map", ""))) + 1) % maps.size()])
	_defaults.map = nxt
	Net.set_config("map", nxt)
	_team_layout()
	print("[official] next map: %s (%d teams of %d)" % [nxt, Net.dm_teams() if Net.is_dm() else int(Net.config.get("teams", 5)), Net.team_size()])


func _restore_defaults() -> void:
	for k in Net.ROOM_KEYS:
		if k in ["teams", "team_size"]:
			continue
		if _defaults.has(k) and str(Net.config.get(k)) != str(_defaults[k]):
			print("[official] lobby empty: %s back to %s" % [k, str(_defaults[k])])
			Net.set_config(k, _defaults[k])
	_team_layout()


func _team_layout() -> void:
	## A map with its own team layout (Freight Delight: two teams of 12) keeps it; on every other map the server's own
	## teams and team size come back (a turn on Freight Delight must not leave the mall at two teams).
	var own := Net.map_limit(str(Net.config.get("map", "")), "team_size", 0) if Net.is_dm() else 0
	if own > 0:
		if Net.team_size() != own:
			Net.set_config("team_size", own)
		return
	for k in ["teams", "team_size"]:
		if _defaults.has(k) and str(Net.config.get(k)) != str(_defaults[k]):
			Net.set_config(k, _defaults[k])


func _set_countdown(s: int) -> void:
	## The lobby shows "Match starts in N s" from config.auto_start_in (-1: waiting for players).
	if s == _shown:
		return
	_shown = s
	Net.set_config("auto_start_in", s)


func _connected_humans() -> int:
	var n := 0
	for pid in Net.players:
		var p: Dictionary = Net.players[pid]
		if not p.bot and p.connected:
			n += 1
	return n


func _address() -> String:
	return str(Game.arg("public_address", "127.0.0.1"))


func info() -> Dictionary:
	var mode := str(Net.config.get("game_mode", "classic"))
	return {"game": game_id, "name": "Official %s · %s" % [str(UITheme.MODE_NAMES.get(mode, mode.capitalize())), str(Defs.rule("official.region", ""))],
		"host": "Aetherion", "official": true, "region": str(Defs.rule("official.region", "")), "address": _address(), "port": Net.port,
		"players": _connected_humans(), "max": Net.slot_count(), "teams": int(Net.config.get("teams", 5)), "team_size": Net.team_size(),
		"bots": bool(Net.config.get("bots", true)), "state": Game.state, "version": Net.VERSION, "platform": "Server", "game_mode": mode,
		"map": str(Net.config.get("map", "kalinaw")), "auto_start_in": int(Net.config.get("auto_start_in", -1))}


func _post() -> void:
	## Straight into this process's stats server when it has one (--stats), else over HTTP to the stats server.
	if Game.master:
		var g := info()
		g.t = Game.master._clock
		Game.master.games[game_id] = g
		return
	if _busy:
		return
	var addr := str(Game.arg("stats_server", "127.0.0.1:27420"))
	if not addr.contains("://"):
		addr = "http://" + addr
	_busy = _http.request(addr + "/game", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(info())) == OK
