extends Node
## r7 component R/B evidence run (not a pass/fail suite; --autotest=dm is that): captures a Deathmatch round on a
## listen host and prints measured values.
##   godot --path game -- --host --game_mode=deathmatch --map=kalinaw --bots=19 --autostart=1 --rules_capture=<dir>
##       --testcheats --port=27615 [--size=1600x900] [--rc_natural] (wait for the bots to finish instead of ending it)
## Shots: first-person spawn with the HUD, the team from the front, the team from above, spectating a teammate
## after dying, the next teammate, the results screen, the lobby afterwards.

var world = null
var out_dir := ""
var _n := 0


func _ready() -> void:
	out_dir = str(Game.arg("rules_capture"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	if Game.arg("size"):
		var p: PackedStringArray = str(Game.arg("size")).split("x")
		DisplayServer.window_set_size(Vector2i(int(p[0]), int(p[1])))
	_run()


func _say(s: String) -> void:
	print("[rcap] " + s)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [out_dir, _n, name]
	img.save_png(path)
	_say("shot %s" % path)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run() -> void:
	while Game.state != "match" or Game.world == null or Game.world.local_char == null:
		await _wait(0.5)
	world = Game.world
	await _wait(1.0)
	var me: Character = world.local_char
	var my_team: int = me.team
	var ms = world.match_server
	# Spawn evidence: teammates close by, everyone armed with the primary drawn, armour worn.
	var near := 0
	var mates := 0
	var armed := 0
	var drawn := 0
	var gear_ok := 0
	var enemies_far := INF
	for c in world.characters.values():
		if c.wpn.slots[1] != null and c.wpn.slots[3] != null:
			armed += 1
		if c.wpn.cur == 1:
			drawn += 1
		if c.inv.gear.get("vest") != null and c.inv.gear.get("helmet") != null and float(c.inv.gear.vest.get("d", 0)) > 0.0:
			gear_ok += 1
		if c.team == me.team and c != me:
			mates += 1
			if c.global_position.distance_to(me.global_position) < 20.0:
				near += 1
		elif c.team != me.team:
			enemies_far = minf(enemies_far, c.global_position.distance_to(me.global_position))
	_say("spawn: %d characters; teammates %d, within 20 m %d; nearest enemy %.0f m; both guns %d; primary drawn %d; vest+helmet %d; my guns %s / %s; ammo %d+%d; bandages %d"
		% [world.characters.size(), mates, near, enemies_far, armed, drawn, gear_ok, str(me.wpn.slots[1].id) if me.wpn.slots[1] else "-",
		str(me.wpn.slots[3].id) if me.wpn.slots[3] else "-", me.inv.count(Defs.ammo_item(str(me.wpn.slots[1].id))) if me.wpn.slots[1] else 0,
		me.inv.count(Defs.ammo_item(str(me.wpn.slots[3].id))) if me.wpn.slots[3] else 0, me.inv.count("bandage")])
	_say("match_info: phase %s, game_mode %s, alive %s, t0 %s, day_offset %s, match_time %.1f, zone i=%d r1=%.0f"
		% [str(world.match_info.get("phase")), str(world.match_info.get("game_mode")), str(world.match_info.get("alive")), str(world.match_info.get("t0")),
		str(world.match_info.get("day_offset")), world.map.lighting.match_time(), int(world.match_info.zone.i), float(world.match_info.zone.r1)])
	await _shot("spawn_first_person")
	# The team from the front, at eye height, 9 m ahead of the anchor.
	var cam := Camera3D.new()
	cam.cull_mask = Defs.RENDER_WORLD | Defs.RENDER_CHARACTERS | Defs.RENDER_INTERIOR | Defs.RENDER_INTERIOR_PROPS
	world.add_child(cam)
	var info: Dictionary = ms.spawn_info.get(me.team, {}) if ms else {}
	var yaw := float(info.get("yaw", me.yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var centre := Vector3.ZERO
	var k := 0
	for c in world.characters.values():
		if c.team == me.team:
			centre += c.global_position
			k += 1
	centre /= maxf(k, 1)
	cam.global_position = centre + fwd * 9.0 + Vector3.UP * 1.9
	cam.look_at(centre + Vector3.UP * 1.1)
	cam.fov = 62.0
	cam.current = true
	await _wait(0.6)
	await _shot("team_front")
	cam.global_position = centre + fwd * 3.0 + Vector3.UP * 1.7 + Vector3(-fwd.z, 0, fwd.x) * 1.5
	cam.look_at(centre + Vector3.UP * 1.4 - fwd * 2.0)
	cam.fov = 50.0
	await _wait(0.6)
	await _shot("team_close")
	# One teammate up close: the heavy-plate helmet and the plate carrier.
	var mate: Character = null
	for c in world.characters.values():
		if c.team == me.team and c != me:
			mate = c
			break
	if mate:
		var mf := Vector3(-sin(mate.yaw), 0, -cos(mate.yaw))
		cam.global_position = mate.global_position + mf * 2.0 + Vector3.UP * 1.45 + Vector3(-mf.z, 0, mf.x) * 0.6
		cam.look_at(mate.global_position + Vector3.UP * 1.25)
		cam.fov = 45.0
		await _wait(0.4)
		await _shot("teammate_gear")
	cam.global_position = centre + Vector3.UP * 28.0 + fwd * 12.0
	cam.look_at(centre)
	cam.fov = 60.0
	await _wait(0.6)
	await _shot("team_above")
	cam.current = false
	world.controller.cam.current = true
	cam.queue_free()
	await _wait(18.0)
	await _shot("hud_after_20s")
	# Die (lethal damage; no downed state in Deathmatch) and spectate.
	var res: Dictionary = me.health.apply_simple(9999.0, "test", "torso", -1)
	_say("lethal hit: downed %s killed %s" % [str(res.get("downed", false)), str(res.get("killed", false))])
	world._after_damage(me, res, -1)
	await _wait(2.5)
	var ctl = world.controller
	var t1 = world.characters.get(ctl.spectating)
	_say("spectating eid %d (%s, team %d; mine %d); candidates %d" % [ctl.spectating, t1.pname if t1 else "-", t1.team if t1 else -1,
		int(Net.players[Net.local_pid].team), ctl.spectate_candidates().size()])
	await _shot("spectate_teammate")
	var ev := InputEventAction.new()
	ev.action = "fire"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.1)
	ev = InputEventAction.new()
	ev.action = "fire"
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(2.0)
	var t2 = world.characters.get(ctl.spectating)
	_say("after fire: spectating eid %d (%s, team %d); server target %d" % [ctl.spectating, t2.pname if t2 else "-", t2.team if t2 else -1,
		world.spectate_target(Net.local_pid)])
	await _shot("spectate_next")
	if Game.arg("rc_natural") == null:
		# End the round: the enemy team falls.
		for c in world.characters.values().duplicate():
			if c.team != my_team and world.characters.has(c.eid):
				var r2: Dictionary = c.health.apply_simple(9999.0, "test", "torso", -1)
				world._after_damage(c, r2, -1)
		await _wait(0.3)
		await _shot("hud_enemy_out")
	var t_wait := 0.0
	while Game.state != "results" and t_wait < 900.0:
		await _wait(1.0)
		t_wait += 1.0
	await _wait(1.5)
	await _shot("results")
	while Game.state != "lobby" and t_wait < 960.0:
		await _wait(1.0)
		t_wait += 1.0
	await _wait(2.0)
	await _shot("lobby_after")
	_say("done")
	get_tree().quit()
