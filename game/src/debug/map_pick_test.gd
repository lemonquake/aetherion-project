extends Node
## r16 Deathmatch map choice (`--map_pick_test=practice|client [--shots=<dir>]`): practice: from the main menu, PLAY NOW
## in Deathmatch, then in the lobby press the Map row's "Malasugue Mall" button the way a player does; client: the same
## as the lobby's host on an official (dedicated) server joined with --join. Then START MATCH, and check the map that
## was actually built. home: pick the map on the main menu's Home page (Deathmatch), then PLAY NOW: the lobby and the
## match must already be on it. Prints [mappick] PASS/FAIL lines and quits.

var role := ""
var out_dir := "user://mappick"
var fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	role = str(Game.arg("map_pick_test", ""))
	out_dir = str(Game.arg("shots", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	if role in ["client", "official_home"]:
		if role == "official_home":
			Profile.dm_map = "malasugue_mall"   # as picked on Home (not saved)
		Net.connected_to_server.connect(func(): _run.call_deferred())
	else:
		_run.call_deferred()


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("[mappick] %s %s %s: %s" % [role, "PASS" if ok else "FAIL", name, detail])


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, role, name])


func _buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_buttons(c, out)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	await _wait(2.0)
	if role == "home":
		await _home()
		return
	if role == "official_home":
		var t0 := 0.0
		while not (Game.state == "lobby" and Net.is_room_host() and str(Net.config.get("map", "")) == "malasugue_mall") and t0 < 15.0:
			await _wait(0.5)
			t0 += 0.5
		_check("official_lobby_takes_home_map", str(Net.config.get("map", "")) == "malasugue_mall", "host %s, lobby map %s" % [str(Net.is_room_host()), str(Net.config.get("map", ""))])
		Profile.dm_map = ""
		_finish()
		return
	if role == "practice":
		Profile.set_game_mode("deathmatch")
		var menu = Game.screen
		if menu == null or not menu.has_method("_quick_match"):
			_check("menu", false, "no main menu (%s)" % str(menu))
			_finish()
			return
		menu._quick_match()
	var t := 0.0
	while not (Game.state == "lobby" and Net.is_room_host() and Game.screen != null) and t < 20.0:
		await _wait(0.5)
		t += 0.5
	await _wait(1.0)
	_check("in_lobby_as_host", Game.state == "lobby" and Net.is_room_host(), "state %s, host %s, mode %s, map %s" % [Game.state, str(Net.is_room_host()),
		str(Net.config.get("game_mode")), str(Net.config.get("map"))])
	await _shot("1_lobby")
	var all := []
	_buttons(Game.screen, all)
	var target: Button = null
	for b in all:
		if b.text == "Malasugue Mall" and b.is_visible_in_tree():
			target = b
	_check("map_button_shown", target != null, "visible buttons: %s" % ", ".join(all.filter(func(b): return b.is_visible_in_tree()).map(func(b): return b.text)))
	if target == null:
		_finish()
		return
	target.pressed.emit()
	t = 0.0
	while str(Net.config.get("map", "")) != "malasugue_mall" and t < 5.0:
		await _wait(0.25)
		t += 0.25
	await _wait(0.6)
	_check("map_set", str(Net.config.get("map", "")) == "malasugue_mall", "lobby map now %s" % str(Net.config.get("map", "")))
	await _shot("2_mall_picked")
	Net.request_start()
	t = 0.0
	while not (Game.state == "match" and Game.world and Game.world.map) and t < 120.0:
		await _wait(0.5)
		t += 0.5
	await _wait(2.0)
	var built := ""
	if Game.world and Game.world.map and Game.world.map.layout:
		built = str(Game.world.map.layout.get("MAP_ID"))
	_check("match_on_mall", built == "malasugue_mall", "match state %s, map built: %s" % [Game.state, built])
	await _shot("3_match")
	_finish()


func _home() -> void:
	Profile.set_dm_map("")
	var menu = Game.screen
	menu._set_mode("deathmatch")
	await _wait(1.0)
	menu = Game.screen
	var all := []
	_buttons(menu, all)
	var target: Button = null
	for b in all:
		if b.text == "Malasugue Mall" and b.is_visible_in_tree():
			target = b
	_check("home_map_button", target != null, "visible buttons: %s" % ", ".join(all.filter(func(b): return b.is_visible_in_tree()).map(func(b): return b.text)))
	if target == null:
		_finish()
		return
	target.pressed.emit()
	await _wait(1.0)
	await _shot("1_home")
	_check("home_map_saved", Profile.dm_map == "malasugue_mall", "profile map %s" % Profile.dm_map)
	Game.screen._quick_match()
	var t := 0.0
	while Game.state != "lobby" and t < 20.0:
		await _wait(0.5)
		t += 0.5
	await _wait(1.0)
	await _shot("2_lobby")
	_check("lobby_on_mall", str(Net.config.get("map", "")) == "malasugue_mall", "lobby map %s" % str(Net.config.get("map", "")))
	Net.request_start()
	t = 0.0
	while not (Game.state == "match" and Game.world and Game.world.map) and t < 120.0:
		await _wait(0.5)
		t += 0.5
	await _wait(1.5)
	var built := str(Game.world.map.layout.get("MAP_ID")) if Game.world and Game.world.map and Game.world.map.layout else ""
	_check("match_on_mall", built == "malasugue_mall", "map built: %s" % built)
	Profile.set_dm_map("")
	_finish()


func _finish() -> void:
	print("[mappick] %s done: %d failed" % [role, fails])
	get_tree().quit(1 if fails > 0 else 0)
