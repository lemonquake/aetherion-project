extends Node
## Run three headless instances with --role=server|host|guest and a separate --profile for each.
## Exercises round replication, a guest leaving results for setup, and the host restarting the room.

var checks := 0
var failures := 0
var role := ""


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[dm-net %s] FAIL %s" % [role, label])


func _until(predicate: Callable, timeout: float = 60.0) -> bool:
	var start := Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec() - start < timeout * 1000:
		await get_tree().create_timer(0.1).timeout
	return predicate.call()


func _run() -> void:
	Settings.data.gameplay.bot_learning = false
	role = str(Game.arg("role", "server"))
	get_tree().create_timer(150.0).timeout.connect(func(): _check(false, "watchdog"); _finish())
	if role == "server":
		await _server()
	else:
		await _client()
	_finish()


func _server() -> void:
	_check(Net.host(27543, true) == OK, "dedicated server starts")
	Net.set_config("practice", true)
	Net.set_config("game_mode", "deathmatch")
	Net.set_config("map", "malasugue_mall")
	Net.set_config("teams", 2)
	Net.set_config("team_size", 2)
	Game.show_lobby()
	if not await _until(func(): return Net.humans() == 2):
		_check(false, "two clients connected")
		return
	Game.start_match()
	if not await _until(func(): return Game.state == "match"):
		_check(false, "all peers loaded")
		return
	var w = Game.world
	var ms = w.match_server
	w.set_physics_process(false)
	ms.score_limit = 2 # Shorten this network test; selectable targets are covered by deathmatch_flow.
	ms._broadcast()
	for round_index in 2:
		await get_tree().create_timer(1.5).timeout
		for ch in w.characters.values():
			if ch.team == 0:
				w.server_set_mode(ch, Motor.DEAD)
				ms.on_killed(ch, -1)
				w.server_remove_character(ch)
		ms._check_end()
		if round_index == 0:
			_check(ms.team_score[1] == 1 and ms.phase == "round_end", "server awards one round point")
			ms._start_next_round()
			w.set_physics_process(false)
	_check(Game.state == "results", "server ends match")
	_check(await _until(func(): return Game.state == "lobby"), "guest can open setup after match")
	_check(await _until(func(): return Net.players.values().any(func(p): return str(p.name) == "DM guest test" and str(p.get("loadout", {}).get("primary", "")) == "smg_9")), "guest finishes changing loadout before restart")
	Net.set_config("network_test_stage", "guest_in_lobby")
	_check(await _until(func(): return Game.state == "match"), "host can restart from retained results")
	_check(Game.world.match_server.team_score == {0: 0, 1: 0} and Game.world.match_server.round_number == 1, "restart clears scores and rounds")
	await get_tree().create_timer(1.5).timeout


func _client() -> void:
	Settings.data.player.name = "DM host test" if role == "host" else "DM guest test"
	if role == "guest":
		await get_tree().create_timer(1.0).timeout
	else:
		await get_tree().create_timer(0.5).timeout
	_check(Net.join("127.0.0.1", 27543) == OK, "client connects")
	if not await _until(func(): return Game.state == "match" and Game.world != null and int(Game.world.match_info.get("round", 0)) == 1):
		_check(false, "received first round")
		return
	_check(Game.world.match_info.zone.is_empty() and not Game.world.match_info.field_enabled, "disabled field replicates")
	var first_eid: int = Game.world.local_char.eid
	_check(await _until(func(): return Game.world != null and int(Game.world.match_info.get("round", 0)) == 2), "received next round")
	_check(Game.world.local_char != null and Game.world.local_char.eid != first_eid, "new character replicates on next round")
	_check(Game.world.match_info.score[1] == 1 and not Game.world.match_info.has("respawn_s"), "round points and elimination policy replicate")
	_check(await _until(func(): return Game._viewing_results and int(Game._last_summary.get("score", {}).get(1, -1)) == 2), "received match results")
	_check(Game._last_summary.score[1] == 2 and Game._viewing_results, "received final stats")
	if role == "guest":
		Game.results_action("loadout")
		_check(await _until(func(): return Game.state == "lobby" and not Game._viewing_results), "guest opens setup")
		Net.request_team(1)
		Net.request_loadout({"primary": "smg_9", "secondary": "pistol_9"})
		_check(await _until(func(): return str(Net.players.get(Net.local_pid, {}).get("loadout", {}).get("primary", "")) == "smg_9"), "guest loadout change reaches server")
	else:
		_check(await _until(func(): return str(Net.config.get("network_test_stage", "")) == "guest_in_lobby"), "room returned to lobby")
		_check(Game._viewing_results and Game.world == null and Game._last_summary.score[1] == 2, "host keeps results while guest opens setup")
		Game.results_action("restart")
	_check(await _until(func(): return Game.state == "match" and int(Game.world.match_info.get("round", 0)) == 1), "client enters restarted match")
	_check(not Game._viewing_results and int(Game.world.match_info.get("round", 0)) == 1, "restart dismisses old results")
	await get_tree().create_timer(4.0 if role == "guest" else 5.0).timeout


func _finish() -> void:
	print("[dm-net %s] %d checks, %d failed" % [role, checks, failures])
	Net.shutdown()
	get_tree().quit(0 if failures == 0 else 1)
