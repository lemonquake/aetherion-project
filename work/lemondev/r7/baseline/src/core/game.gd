extends Node
## Scene flow: main menu -> lobby -> loading -> match -> results -> lobby (rematch).
## Owns the World node (/root/Game/World) and the UI layer (/root/Game/UI).

signal state_changed(state: String)

const WorldScript := preload("res://src/match/world.gd")
const MenuScript := preload("res://src/ui/main_menu.gd")
const LobbyScript := preload("res://src/ui/lobby_ui.gd")
const Outfit := preload("res://src/player/outfit.gd")
const MasterServer := preload("res://src/online/master_server.gd")

var master: Node = null      # the stats server when this process runs one (--master, or --server --stats)
var last_xp: Dictionary = {} # {xp, level_before, level_after} from the last match, for the results screen

const BOT_NAMES := [
	"Kuya Bert", "Aling Nena", "Tito Boy", "Mang Kanor", "Pareng Jun", "Tsong Ramil", "Bossing Dodong",
	"Lolo Pepe", "Ate Bebang", "Kapitan Tikoy", "Totoy Bibo", "Inday Tsismis", "Mang Tani", "Dodong Lechon",
	"Ka Pedring", "Bunso Badong", "Tita Baby", "Kumpare Ambo", "Aling Puring", "Utoy Kalabaw",
	"Junjun Tisoy", "Ising Batingaw", "Kulot Sabaw", "Toto Pancit",
	"Manong Guard", "Ate Siomai", "Kuya Tricycle", "Lola Basyang", "Mang Tomas", "Bebot Karaoke", "Pinsan Gardo",
	"Tito Videoke", "Aling Taho", "Boy Pickup", "Mang Isko", "Kapitbahay Lito", "Tsong Balut", "Nanay Kakanin",
	"Bayaw Erning", "Tatay Kulas", "Ate Load", "Kuya Fishball", "Lolo Kalesa", "Mang Jolo",
	"Mang Tomas Ketchup", "Kuya Wifi", "Ate Load Dito", "Tito Karaoke King", "Lola Basyang Jr", "Pareng Pandesal", "Kumareng Marites", "Totoy Kulot", "Bossing Barbecue", "Inday Rice Cooker"
]

var state := "boot"
var world: Node3D = null
var ui: CanvasLayer
var screen: Control = null
var args := {}
var match_seed := 0
var _loaded_peers := {}
var _load_timer := -1.0
## Voice transmission bookkeeping on the server: pid -> seconds since last packet.
var _talking := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)
	_parse_args()
	Net.connection_failed.connect(_on_net_failed)
	Net.disconnected.connect(_on_net_failed)
	Net.connected_to_server.connect(func(): show_lobby())


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true


func arg(key: String, default_value = null):
	return args.get(key, default_value)


func boot() -> void:
	## Called by the boot scene once autoloads are ready.
	if Settings.is_mobile():
		# Menus and HUD drawn half as large again: buttons laid out for a monitor are a few millimetres tall on a phone.
		get_tree().root.content_scale_factor = 1.5
	if OS.get_name() == "Android" and not "android.permission.RECORD_AUDIO" in OS.get_granted_permissions():
		# Ask for the microphone (team radio) at the menu, not when the first match starts.
		OS.request_permission("android.permission.RECORD_AUDIO")
	if arg("ui_tour"):
		var tour: Node = load("res://src/debug/ui_tour.gd").new()
		tour.name = "UiTour"
		add_child(tour)
	if arg("shot"):
		# --shot=<png> [--shot_after=<s>]: save the screen and quit (menus and lobby at any window size).
		get_tree().create_timer(float(arg("shot_after", 3.0))).timeout.connect(func():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(str(arg("shot")))
			print("[game] shot %s" % str(arg("shot")))
			get_tree().quit())
	if arg("name"):
		Settings.set_value("player", "name", str(arg("name")))
	if arg("master") or arg("stats"):
		master = MasterServer.new()
		master.name = "Master"
		add_child(master)
		master.start(int(arg("master_port", MasterServer.PORT)), str(arg("data", "")))
		if arg("master") and not arg("server"):
			print("[master] running (no match server in this process)")
			return
	if arg("server"):
		Net.host(int(arg("port", Net.DEFAULT_PORT)), true)
		_apply_arg_config()
		show_lobby()
		print("[server] dedicated server listening on %d" % int(arg("port", Net.DEFAULT_PORT)))
		return
	if arg("host"):
		if Net.host(int(arg("port", Net.DEFAULT_PORT))) == OK:
			_apply_arg_config()
			show_lobby()
			return
	if arg("join"):
		Net.join(str(arg("join")), int(arg("port", Net.DEFAULT_PORT)))
		show_screen(MenuScript.new())
		screen.call("show_status", "Connecting to %s…" % str(arg("join")))
		return
	show_menu()


func _apply_arg_config() -> void:
	if arg("mode"):
		Net.set_config("mode", str(arg("mode")))
	if arg("teams") != null:
		Net.set_config("teams", clampi(int(arg("teams")), 1, Net.MAX_TEAMS))
	if arg("team_size") != null:
		Net.set_config("team_size", clampi(int(arg("team_size")), 1, Net.MAX_TEAM_SIZE))
	if arg("bots") != null:
		# --bots=N: room for N bots besides the humans expected (teams grow to fit, up to 7).
		var n := int(arg("bots"))
		Net.set_config("bot_count", n)
		Net.set_config("bots", n > 0)
		if arg("teams") == null:
			var want := n + maxi(int(arg("expect_players", 1)), 1)
			Net.set_config("teams", clampi(ceili(float(want) / Net.team_size()), 2, Net.MAX_TEAMS))
	if arg("seed") != null:
		Net.set_config("map_seed", int(arg("seed")))
	if arg("zone_speed") != null:
		Net.set_config("zone_speed", float(arg("zone_speed")))
	if arg("autostart"):
		var wait := float(arg("autostart_after", 0.0)) if str(arg("autostart")) == "true" else float(arg("autostart"))
		get_tree().create_timer(maxf(wait, 0.5)).timeout.connect(_autostart)


func _autostart() -> void:
	var expect := int(arg("expect_players", 1))
	var humans := 0
	for pid in Net.players:
		if not Net.players[pid].bot:
			humans += 1
	if humans < expect:
		get_tree().create_timer(0.5).timeout.connect(_autostart)
		return
	start_match()


# ------------------------------------------------------------------ screens

func show_screen(c: Control) -> void:
	if screen and is_instance_valid(screen):
		screen.queue_free()
	screen = c
	if c:
		ui.add_child(c)


func show_menu() -> void:
	_set_state("menu")
	teardown_world()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_screen(MenuScript.new())


func show_lobby() -> void:
	_set_state("lobby")
	teardown_world()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if DisplayServer.get_name() == "headless":
		show_screen(null)
		return
	show_screen(LobbyScript.new())


func leave_to_menu() -> void:
	Net.shutdown()
	show_menu()


func _on_net_failed(reason: String) -> void:
	show_menu()
	if screen and screen.has_method("show_status"):
		screen.call("show_status", reason)


func _set_state(s: String) -> void:
	state = s
	state_changed.emit(s)


# ------------------------------------------------------------------ match lifecycle (server)

func start_match() -> void:
	if not Net.is_server or state == "loading" or state == "match":
		return
	# Bots fill the team slots the humans left open (5 teams of 4 by default: 20 slots).
	Net.remove_bots()
	if Net.config.get("bots", true):
		var names := BOT_NAMES.duplicate()
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in range(names.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = names[i]
			names[i] = names[j]
			names[j] = t
		var room := Net.slot_count() - Net.humans()
		if arg("bots") != null:
			room = mini(room, int(arg("bots")))
		for i in maxi(room, 0):
			Net.add_bot(names[i % names.size()], Outfit.random_look(rng.randi()))
	Net.assign_teams()
	for pid in Net.players:
		Net.players[pid].in_match = true
	match_seed = randi() if arg("match_seed") == null else int(arg("match_seed"))
	_loaded_peers.clear()
	_load_timer = float(Defs.rule("loading_timeout_s", 90))
	_load_match.rpc(Net.config, match_seed)
	_load_match(Net.config, match_seed)


@rpc("authority", "call_remote", "reliable")
func _load_match(cfg: Dictionary, seed_value: int) -> void:
	Net.config = cfg
	match_seed = seed_value
	_set_state("loading")
	show_screen(null)
	teardown_world()
	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	world.build(cfg, seed_value)
	print("[map] %s on %s" % [world.map.fingerprint, Net.platform()])
	if Net.is_server:
		_on_peer_loaded(1)
	else:
		_client_loaded.rpc_id(1, world.map.fingerprint)


@rpc("any_peer", "reliable")
func _client_loaded(fingerprint: String = "") -> void:
	if not Net.is_server:
		return
	var pid := multiplayer.get_remote_sender_id()
	if world and world.map and fingerprint != world.map.fingerprint:
		# Same version, different map: the client's doors, loot and props would not match the server's.
		var p: Dictionary = Net.players.get(pid, {})
		var msg := "%s (%s) built a different map: %s; server: %s" % [p.get("name", pid), p.get("platform", "?"), fingerprint, world.map.fingerprint]
		print("[map] MISMATCH " + msg)
		if world.match_server:
			world.match_server.log_event("map mismatch: " + msg)
		world.match_toast.rpc_id(pid, "Your game built a different map from the host's. Doors and loot may not line up.", "")
	_on_peer_loaded(pid)


func _on_peer_loaded(pid: int) -> void:
	_loaded_peers[pid] = true
	if world and state == "match":
		world.server_sync_late_peer(pid)
		return
	_check_all_loaded()


func _check_all_loaded() -> void:
	if state != "loading" or not Net.is_server:
		return
	for pid in Net.players:
		var p: Dictionary = Net.players[pid]
		if not p.bot and p.connected and pid != 1 and not _loaded_peers.has(pid):
			return
	_begin_match()


func _begin_match() -> void:
	_load_timer = -1.0
	_set_state("match")
	_match_started.rpc()
	world.server_start_match()
	if arg("end_after"):
		# Tests: end the match after this many seconds with whoever is standing.
		get_tree().create_timer(float(arg("end_after"))).timeout.connect(func():
			if world and world.match_server and state == "match":
				world.match_server.force_end())
	if arg("autotest") and not Net.dedicated:
		_add_autotest()


func _add_autotest() -> void:
	var scenario := str(arg("autotest"))
	var path := "res://src/debug/autotest_net.gd" if scenario.begins_with("net") else "res://src/debug/autotest.gd"
	var at: Node = load(path).new()
	print("[game] autotest %s" % scenario)
	at.name = "AutoTest"
	world.add_child(at)


@rpc("authority", "call_remote", "reliable")
func _match_started() -> void:
	_set_state("match")
	print("[game] match started (client)")
	if world:
		world.client_match_started()
		if arg("autotest"):
			_add_autotest()


func end_match_to_results(summary: Dictionary) -> void:
	## Server: called by the world when a winner is decided. Every human's row carries the XP it earned; the host
	## reports the match to the stats server.
	for r in summary.get("rows", []):
		r.xp = 0 if r.get("bot", false) else Profile.match_xp(r)
		var p: Dictionary = Net.players.get(int(r.get("pid", 0)), {})
		r.profile = str(p.get("profile", ""))
		r.platform = str(p.get("platform", "PC"))
	if master:
		master._result({"players": summary.rows.filter(func(r): return not r.get("bot", false) and str(r.profile) != "").map(func(r): return {
			"id": r.profile, "name": r.name, "platform": r.platform, "kills": r.kills, "damage": r.damage, "place": r.place, "winner": r.winner,
			"time": r.time, "xp": r.xp})})
	elif not Net.dedicated:
		Online.post_result(summary.get("rows", []))
	_show_results.rpc(summary)
	_show_results(summary)
	get_tree().create_timer(float(Defs.rule("results_s", 25))).timeout.connect(_return_to_lobby)


@rpc("authority", "call_remote", "reliable")
func _show_results(summary: Dictionary) -> void:
	_set_state("results")
	last_xp = {}
	if not Net.dedicated:
		for r in summary.get("rows", []):
			if int(r.get("pid", 0)) == Net.local_pid and not r.get("bot", false):
				r.teams = int(summary.get("teams", 0))
				last_xp = Profile.add_match(r)
				summary.me = r
				summary.me_xp = last_xp
	if world:
		world.show_results(summary)
	if arg("quit_after_results"):
		print("[game] results: %s" % JSON.stringify(summary.get("me", {})))
		get_tree().create_timer(4.0).timeout.connect(func(): get_tree().quit())


func _return_to_lobby() -> void:
	if not Net.is_server or state != "results":
		return
	for pid in Net.players.keys():
		var p: Dictionary = Net.players[pid]
		p.in_match = false
		p.ready = p.bot
		if not p.connected:
			Net.players.erase(pid)
	Net.remove_bots()
	_back_to_lobby.rpc()
	show_lobby()
	if arg("autostart") and arg("rematch"):
		get_tree().create_timer(3.0).timeout.connect(start_match)


@rpc("authority", "call_remote", "reliable")
func _back_to_lobby() -> void:
	show_lobby()


func teardown_world() -> void:
	if world and is_instance_valid(world):
		world.teardown()
		remove_child(world)
		world.free()
	world = null
	SoundSys.clear()


func _process(delta: float) -> void:
	if _load_timer > 0.0:
		_load_timer -= delta
		if _load_timer <= 0.0 and state == "loading":
			print("[server] loading timeout; starting without slow peers")
			_begin_match()
	if Net.is_server and not _talking.is_empty():
		for pid in _talking.keys():
			_talking[pid] += delta
			if _talking[pid] > 0.3:
				_talking.erase(pid)
				if world:
					world.server_radio_event(pid, "off")


# ------------------------------------------------------------------ peers during a match

func on_peer_joined(pid: int) -> void:
	if state in ["loading", "match", "results"] and world:
		# Late joiner: spectates the running match.
		_load_match.rpc_id(pid, Net.config, match_seed)


func on_peer_reconnected(new_pid: int, old_pid: int) -> void:
	if world:
		world.server_rebind_player(old_pid, new_pid)
		_load_match.rpc_id(new_pid, Net.config, match_seed)


func on_peer_left(pid: int) -> void:
	_loaded_peers.erase(pid)
	if world:
		world.server_peer_left(pid)
	if state == "loading":
		_check_all_loaded()


# ------------------------------------------------------------------ voice relay (server)

func relay_voice(from_pid: int, bytes: PackedByteArray) -> void:
	if not Net.players.has(from_pid):
		return
	var team: int = Net.players[from_pid].team
	if not _talking.has(from_pid) and world:
		world.server_radio_event(from_pid, "on")
	_talking[from_pid] = 0.0
	if world:
		for tg in world.voice_targets(from_pid):
			Net.deliver_voice(int(tg[0]), from_pid, bytes, int(tg[1]), int(tg[2]))
	else:
		for pid in Net.players:
			var p: Dictionary = Net.players[pid]
			if pid != from_pid and not p.bot and p.connected and p.team == team:
				Net.deliver_voice(pid, from_pid, bytes, -1, 0)
