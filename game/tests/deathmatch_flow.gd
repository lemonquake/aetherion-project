extends Node
## godot --headless --path game res://tests/deathmatch_flow.tscn -- --profile=dm_flow_test
## Add --ui_only --capture=<absolute.png> for a rendered results-screen check without building the map.

const Results := preload("res://src/ui/results_ui.gd")
var checks := 0
var failures := 0
var world
var ms


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[dm-flow] FAIL " + detail)


func _run() -> void:
	Settings.data.gameplay.bot_learning = false
	if Game.arg("ui_only"):
		if Game.arg("ui_actions"):
			Net.host(27542)
			Net.set_config("practice", true)
			Net.set_config("game_mode", "deathmatch")
			Net.set_config("map", "malasugue_mall")
			Net.set_config("bots", false)
		await _results_ui()
		if Game.arg("ui_actions"):
			await _actions_ui()
		_finish()
		return
	_check(Net.config.dm_win == "wipe" and Net.config.dm_score == 10 and not Net.config.dm_field, "fresh defaults")
	_check(Profile.MATCH_OPT_DEFAULTS.dm_win == "wipe" and not Profile.MATCH_OPT_DEFAULTS.dm_field, "profile defaults")
	_check(Net.host(27541, true) == OK, "host started")
	Net.set_config("game_mode", "deathmatch")
	Net.set_config("map", "malasugue_mall")
	Net.set_config("team_size", 2)
	Net.set_config("bots", true)
	Game.args.match_seed = 1729
	Game.start_match()
	world = Game.world
	ms = world.match_server
	world.set_physics_process(false)
	world.grenades.set_physics_process(false)
	for bot in world.bots.values():
		bot.test_idle = true
	_check(world.characters.size() == 6 and ms.initial_teams == 3, "three teams start with two players each")
	_check(ms._state().zone.is_empty() and not Field.live(ms._state().zone), "disabled field has no replicated boundary or force")
	_check(not Field.at(world, Vector3(9999, 0, 9999), Net.tick).on, "disabled field applies no force outside map")
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	Net.set_config("dm_field", true)
	ms._reset_dm_field(rng)
	var initial_radius: float = ms.zone.r0
	var initial_center: Vector2 = ms.zone.c0
	var wait: float = float(Defs.rule("deathmatch.zone.phases", [])[0].wait) / ms.zone_speed()
	_check(is_equal_approx(float(ms.zone.t1 - Net.tick) / Defs.TICK_RATE, wait), "enabled field keeps the original first countdown")
	_check(ms.zone.state == "wait" and ms.zone.i == 0, "enabled field waits before closing")
	for step in 16:
		_check(float(ms.zone.r0) >= initial_radius * 0.5 - 0.01 and float(ms.zone.r1) >= initial_radius * 0.5 - 0.01, "field radius never below half")
		_check((ms.zone.c0 as Vector2).is_equal_approx(initial_center) and (ms.zone.c1 as Vector2).is_equal_approx(initial_center), "capped field keeps its center")
		if ms.zone.state == "hold":
			break
		Net.tick = int(ms.zone.t1)
		ms._zone_tick(0.0)
	_check(ms.zone.state == "hold" and is_equal_approx(ms.zone.r0, initial_radius * 0.5), "enabled field stops at 50%")
	_check(Field.live(ms.zone), "enabled field remains solid after reaching its limit")
	ms._reset_dm_field(rng)
	_check(ms.zone.state == "wait" and ms.zone.i == 0 and ms.zone.r0 > ms._hold_r, "reset restores full boundary and countdown")
	Net.set_config("dm_field", false)
	ms._reset_dm_field(rng)
	ms._broadcast()
	for limit in Net.DM_SCORES:
		ms.score_limit = limit
		ms.team_score = {0: 0, 1: limit - 2, 2: 0}
		_kill_team(0, 1)
		ms._check_end()
		_check(ms.phase == "playing" and ms.team_score[1] == limit - 2, "eliminating one of three teams does not award a point")
		_kill_team(2, 1)
		ms._check_end()
		_check(ms.phase == "round_end" and ms.team_score[1] == limit - 1, "last standing team earns exactly one point")
		_check(ms._respawn_at.is_empty() and not ms.respawns(), "eliminated players wait for next round")
		var round_before: int = ms.round_number
		var next_tick: int = ms._next_round_at
		ms.tick(0.1)
		_check(ms.round_number == round_before and ms.team_score[1] == limit - 1, "round break does not award duplicate points")
		Net.tick = next_tick
		ms.tick(0.0)
		await get_tree().process_frame
		_check(ms.phase == "playing" and world.characters.size() == 6 and ms.round_number == round_before + 1, "all players return next round")
		_check(ms._state().zone.is_empty(), "disabled field stays absent after round reset")
		for ch in world.characters.values():
			_check(ch.health.health == 100.0 and ch.mode == Motor.GROUND and not ch.wpn.current_id().is_empty(), "new round restores health and loadout")
		_kill_team(0, 1)
		_kill_team(2, 1)
		ms._check_end()
		_check(ms.phase == "ended" and Game.state == "results" and ms.team_score[1] == limit, "match ends at the selected target %d" % limit)
		var summary: Dictionary = ms._summary(1)
		_check(summary.rows.size() == 6 and summary.rows.filter(func(r): return r.winner).size() == 2, "match totals include every player exactly once")
		_check(summary.rows.reduce(func(total, r): return total + int(r.kills), 0) >= 8, "kills carry across rounds")
		Game._set_state("match")
		ms._start_next_round()
		await get_tree().process_frame
	# A simultaneous wipe has no last team standing, so no point is awarded.
	ms.team_score = {0: 0, 1: 0, 2: 0}
	for ch in world.characters.values():
		world.server_remove_character(ch)
	ms._check_end()
	_check(ms.phase == "round_end" and ms.team_score == {0: 0, 1: 0, 2: 0}, "simultaneous wipe is a draw")
	ms._start_next_round()
	# Existing respawn rules remain available.
	for rule in ["score", "time", "elim"]:
		ms.win_by = rule
		_check(ms.respawns() == (rule in ["score", "time"]), "respawn policy for " + rule)
	ms.win_by = "wipe"
	ms.force_end()
	await get_tree().create_timer(26.0).timeout
	_check(Game.state == "results" and is_instance_valid(Game.world), "results remain after the former automatic return deadline")
	# Return to the lobby while keeping this player's standalone results visible.
	Game.show_screen(Results.new(ms._summary(1)))
	var results_screen = Game.screen
	Game._return_to_lobby()
	_check(Game.state == "lobby" and Game.world == null and Game.screen == results_screen and Game._viewing_results, "room can return to lobby without removing results")
	await _results_ui()
	_finish()


func _kill_team(team: int, attacker_team: int) -> void:
	var attacker := -1
	for ch in world.characters.values():
		if ch.team == attacker_team:
			attacker = ch.eid
			break
	for ch in world.characters.values():
		if ch.team == team:
			world.server_set_mode(ch, Motor.DEAD)
			ms.on_killed(ch, attacker)
			world.server_remove_character(ch)


func _results_ui() -> void:
	var rows := []
	for i in 21:
		rows.append({"pid": 100 + i, "name": Game.BOT_NAMES[i], "bot": i > 0, "team": i % 3, "kills": 20 - i,
			"damage": 2000 - i * 63, "time": 600 - i * 10, "winner": i % 3 == 1})
	Game._viewing_results = true
	Game._set_state("results")
	Game.show_screen(Results.new({"game_mode": "deathmatch", "winner_team": 1, "winner_name": "East Team",
		"team_names": ["North Team", "East Team", "South Team"], "score": {0: 8, 1: 10, 2: 7}, "duration": 600, "rows": rows}))
	await get_tree().process_frame
	await get_tree().process_frame
	var buttons := Game.screen.find_children("*", "Button", true, false)
	for text in ["BACK TO MAIN MENU", "RESTART MATCH", "CHANGE GAME MODE", "CHANGE LOADOUT", "CHANGE TEAM"]:
		_check(buttons.any(func(b): return b.text == text), "results action: " + text)
	_check(Game.screen.find_children("*", "Label", true, false).any(func(l): return l.text == Game.BOT_NAMES[20] + " (bot)"), "results contain all 21 players")
	if Game.arg("capture") and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(str(Game.arg("capture")))


func _actions_ui() -> void:
	var result := Game.screen
	var button: Button = result.find_children("*", "Button", true, false).filter(func(b): return b.text == "CHANGE LOADOUT")[0]
	button.pressed.emit()
	_check(Game.state == "lobby" and Game.screen._game_setup != null, "Change Loadout opens the gun picker")
	await _results_ui()
	button = Game.screen.find_children("*", "Button", true, false).filter(func(b): return b.text == "CHANGE TEAM")[0]
	button.pressed.emit()
	_check(Game.state == "lobby" and Game.screen.has_method("open_game_setup"), "Change Team opens the team lobby")
	Net.request_team(1)
	_check(int(Net.players[1].team) == 1, "team can be changed after results")
	await _results_ui()
	button = Game.screen.find_children("*", "Button", true, false).filter(func(b): return b.text == "CHANGE GAME MODE")[0]
	button.pressed.emit()
	Net.request_config("game_mode", "classic")
	_check(Game.state == "lobby" and Net.config.game_mode == "classic", "Change Game Mode allows host to change mode")
	Net.set_config("game_mode", "deathmatch")
	Net.set_config("map", "malasugue_mall")
	Net.set_config("teams", 2)
	Net.set_config("team_size", 1)
	await _results_ui()
	button = Game.screen.find_children("*", "Button", true, false).filter(func(b): return b.text == "RESTART MATCH")[0]
	_check(not button.disabled, "host can restart")
	button.pressed.emit()
	_check(Game.state == "match" and Game.world.match_server.round_number == 1 and Game.world.match_server.team_score == {0: 0, 1: 0}, "Restart Match starts a fresh match")
	Game.world.match_server.force_end()
	button = Game.screen.find_children("*", "Button", true, false).filter(func(b): return b.text == "BACK TO MAIN MENU")[0]
	button.pressed.emit()
	_check(Game.state == "menu" and not Net.online and Game.world == null, "Back to Main Menu leaves the room")
	await get_tree().process_frame


func _finish() -> void:
	print("[dm-flow] %d checks, %d failed" % [checks, failures])
	Net.shutdown()
	get_tree().quit(0 if failures == 0 else 1)
