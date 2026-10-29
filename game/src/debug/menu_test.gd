extends Node
## r10 menu flow check (`--menu_test --shots=<dir> [--loadshot=<dir>/loading.png]`): the main menu, PLAY NOW, which
## must bring up the lobby and not start a match; then START MATCH, the loading screen, and the match. Prints
## [menutest] PASS/FAIL lines and quits.

var out_dir := "user://menutest"
var fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	out_dir = str(Game.arg("shots", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("[menutest] shot %s/%s.png" % [out_dir, name])


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("[menutest] %s %s: %s" % ["PASS" if ok else "FAIL", name, detail])


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	await _shot("1_menu")
	var menu = Game.screen
	_check("menu_shown", menu != null and menu.has_method("_quick_match"), "screen %s" % str(menu))
	if menu == null or not menu.has_method("_quick_match"):
		get_tree().quit(1)
		return
	menu._quick_match()
	await get_tree().create_timer(2.5).timeout
	await _shot("2_after_play_now")
	_check("play_now_opens_lobby", Game.state == "lobby" and Net.is_server and Game.world == null, "state %s, hosting %s, world %s" % [Game.state, str(Net.is_server), str(Game.world)])
	Net.set_config("bots", true)
	# From an ordinary frame, as a button press is: _shot() resumed us inside the renderer's frame_post_draw, where
	# the loading screen's forced redraws do nothing.
	await get_tree().create_timer(0.3).timeout
	Game.start_match()
	var t := 0.0
	while Game.state != "match" and t < 120.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	_check("match_started", Game.state == "match", "after %.0f s" % t)
	await get_tree().create_timer(4.0).timeout
	await _shot("3_in_match")
	get_tree().quit(1 if fails > 0 else 0)
