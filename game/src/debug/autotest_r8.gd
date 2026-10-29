extends RefCounted
## Real match input and rendering checks. Also runs against a dedicated server
## with --join=127.0.0.1 --autotest=r8 to exercise prediction and snapshot state.

var t = null
var world = null


func _init(autotest) -> void:
	t = autotest
	world = t.world


func run() -> void:
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 25.0)
	await t._wait(2.0)
	if not is_instance_valid(t.ch):
		t._check("r8_spawn", false, "no local player")
		return
	var ch = t.ch
	var ws = ch.wpn
	t._check("r8_map", world.is_dm() and world.cfg.get("map", "") == "lawless_sub", world.map.fingerprint)
	if not ws.has_selector(ws.current_id()):
		await t._tap("weapon_1")
		await t._wait(1.0)
	t._check("r8_default_auto", ws.fire_mode() == "auto", ws.current_id() + ": " + ws.fire_mode())
	world.map.lighting.forced_time = 450.0
	if world.is_server:
		t._teleport(Vector3(-14, 1.2, -27), 0.0)
	else:
		world.test_cmd({"op": "teleport", "pos": Vector3(-14, 1.2, -27), "yaw": 0.0})
	await t._wait(1.0)
	t.ctl.pitch = 0.12
	await t._shot("auto")
	var before: int = ws.shots
	await t._hold("fire", 0.6)
	await t._wait(0.4)
	t._check("r8_auto_continuous", ws.shots - before >= 4, "%d shots held 0.6s" % (ws.shots - before))
	await _cycle()
	await t._wait(0.3)
	await _mode_check("semi")
	await t._shot("single")
	before = ws.shots
	await t._hold("fire", 0.5)
	await t._wait(0.4)
	t._check("r8_single_once", ws.shots - before == 1, "%d shots held 0.5s" % (ws.shots - before))
	await _cycle()
	await t._wait(0.3)
	await _mode_check("burst")
	await t._shot("burst")
	before = ws.shots
	await t._hold("fire", 0.65)
	await t._wait(0.4)
	t._check("r8_burst_three", ws.shots - before == 3, "%d shots held 0.65s" % (ws.shots - before))
	# Opening a menu must cancel queued shots on both client and server, and a
	# mouse held through Resume must not be mistaken for another trigger press.
	before = ws.shots
	t._act_press("fire")
	await t._until(func(): return ws.shots > before, 1.5)
	t.ctl._toggle_pause()
	await t._wait(0.45)
	t._check("r8_pause_cancels", ws.shots - before == 1 and ws.burst_left == 0, "%d shots, %d queued" % [ws.shots - before, ws.burst_left])
	await t._shot("pause")
	t.ctl._toggle_pause()
	await t._wait(0.35)
	t._check("r8_resume_release", ws.shots - before == 1, "%d shots with held trigger through Resume" % (ws.shots - before))
	t._act_release("fire")
	await t._wait(0.2)
	await _cycle()
	await t._wait(0.3)
	await _mode_check("auto")
	await t._shot("resumed_auto")
	if t.ctl.touch:
		var touch = t.ctl.touch
		var b: Dictionary = {}
		for button in touch.BUTTONS:
			if button.name == "fire_mode":
				b = button
		var centre: Vector2 = touch._centre(b)
		var radius: float = float(b.r) * touch._k()
		var sz: Vector2 = t.get_viewport().get_visible_rect().size
		t._check("r8_touch_visible", touch._visible_button(b) and centre.x > radius and centre.y > radius and centre.x + radius < sz.x and centre.y + radius < sz.y,
			"mode button %s, radius %.1f, viewport %s" % [centre, radius, sz])
		touch._touch_down(90, centre)
		touch._touch_up(90)
		await t._wait(0.3)
		await _mode_check("semi")
		await t._shot("touch_single")
	t._check("r8_network_acks", world.is_server or t.ctl.stats.acks > 15, "%d server snapshots" % t.ctl.stats.acks)
	if world.is_server:
		await _overpass_route()


func _cycle() -> void:
	if t.ctl.touch:
		var touch = t.ctl.touch
		for b in touch.BUTTONS:
			if b.name == "fire_mode":
				touch._touch_down(91, touch._centre(b))
				touch._touch_up(91)
				await t._wait(0.15)
				return
	await t._tap("fire_mode")


func _mode_check(expected: String) -> void:
	var actual: String = t.ch.wpn.fire_mode()
	var server_mode := int(t.ch.wpn.weapon().get("mode", -1))
	if not world.is_server:
		server_mode = int(t.ctl._snap_own.get("wpn", {}).get("mode", -1))
	var expected_index := ["auto", "semi", "burst"].find(expected)
	t._check("r8_mode_" + expected, actual == expected and server_mode == expected_index,
		"local %s, authoritative index %d" % [actual, server_mode])


func _overpass_route() -> void:
	t._teleport(Vector3(-30, 1.12, -34.25), 0.0)
	# Isolate walking from queued gun recoil and real mouse movement during
	# screenshot capture; all position changes still use the normal Motor.
	t.ctl._yaw_left = 0.0
	t.ctl._climb_left = 0.0
	t.ctl._mouse_delta = Vector2.ZERO
	await t._wait(0.4)
	var up: bool = await _walk_to("move_forward", func(): return t.ch.global_position.y > 7.2, 7.0)
	await t._wait(0.15)
	t._check("r8_overpass_climb", up and t.ch.global_position.y < 7.65, "actual player at %s" % t.ch.global_position)
	await t._shot("overpass_walk")
	if not up:
		return
	var across: bool = await _walk_to("move_right", func(): return t.ch.global_position.x > -10.3, 8.0)
	t._check("r8_overpass_cross", across and t.ch.global_position.y > 7.1, "actual player at %s" % t.ch.global_position)
	var down: bool = await _walk_to("move_back", func(): return t.ch.global_position.y < 1.55, 7.0)
	t._check("r8_overpass_descent", down and t.ch.global_position.z > -36.5, "actual player at %s" % t.ch.global_position)


func _walk_to(action: String, condition: Callable, timeout: float) -> bool:
	t._act_press(action)
	var elapsed := 0.0
	while not condition.call() and elapsed < timeout:
		t.ctl.yaw = 0.0
		t.ctl._mouse_delta = Vector2.ZERO
		await t.get_tree().physics_frame
		elapsed += 1.0 / 60.0
	t._act_release(action)
	return condition.call()
