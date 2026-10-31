extends RefCounted
## Freight Delight checks, on a listen host (`--autotest=freight`, `--freight_only=build,stairs,routes`):
##   godot --path game -- --host --game_mode=deathmatch --map=freight_delight --bots=23 --autostart=1 --autotest=freight --shots=<dir>
## build: the map came in whole (two teams of 12+ spawns, three stair links, both walk grids, the bots' waypoints on both
## floors, the lamps the map hands to Lighting). stairs: walking straight up each of the three flights reaches the second floor. routes: one
## bot (invulnerable, the others frozen and the enemies parked under the yard) is ordered through the whole map in
## turn: every stair top, both ends of the deck, the crane platform, the Taas rooms and balcony, the container homes,
## the Bodega, the Talyer, the canyon, the alleys and both spawns. Each leg must arrive in time without the bot
## standing stuck against a wall; the legs, their times and the stalls go to <shots>/freight_routes.json.

const LEGS := [
	["Stair A top: Bodega mezzanine", Vector3(-34.0, 3.2, -12.6)],
	["Deck, west end", Vector3(-34.5, 3.2, -28.4)],
	["Deck, over the west passage", Vector3(-10.6, 3.2, -28.6)],
	["Deck, middle", Vector3(1.5, 3.2, -28.4)],
	["Crane platform", Vector3(2.6, 3.2, 0.0)],
	["Taas corridor", Vector3(8.0, 3.2, 17.3)],
	["Taas east room", Vector3(10.5, 3.2, 20.8)],
	["Taas balcony (Stair C top)", Vector3(-4.0, 3.2, 23.7)],
	["Courtyard", Vector3(0.0, 0.0, 29.0)],
	["Alley C, east", Vector3(30.0, 0.0, 34.5)],
	["Through-shanty, east", Vector3(36.2, 0.09, 19.0)],
	["Talyer floor", Vector3(32.5, 0.03, 0.0)],
	["Talyer office", Vector3(40.0, 0.03, 8.0)],
	["Stair B landing", Vector3(39.7, 3.2, -20.0)],
	["Container leg by the Talyer", Vector3(37.6, 3.2, -15.0)],
	["Deck, east end", Vector3(33.5, 3.2, -28.4)],
	["Canyon, east", Vector3(40.0, 0.0, -36.0)],
	["Through-home in the inner row", Vector3(21.2, 0.42, -28.6)],
	["Plaza, videoke", Vector3(16.0, 0.0, -3.0)],
	["Canyon, west", Vector3(-40.0, 0.0, -36.0)],
	["Container home", Vector3(-32.5, 0.42, -27.3)],
	["Sari-sari store", Vector3(-18.0, 0.0, 5.0)],
	["Through-shanty, west", Vector3(-36.2, 0.09, 19.0)],
	["Bodega floor", Vector3(-34.5, 0.03, 0.0)],
	["West spawn", Vector3(-52.0, 0.0, 0.0)],
	["East spawn", Vector3(51.0, 0.0, 8.0)],
]

var t = null
var world = null
var measure := {}
var _frozen := {}


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("freight_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 60.0)
	await t._wait(1.0)
	_freeze_bots(true)
	t.ch.health.test_invulnerable = true
	for n in ["build", "stairs", "routes"]:
		if want.call(n) and is_instance_valid(t.ch):
			await (Callable(self, "_" + n)).call()
	var f := FileAccess.open(t.out_dir + "/freight_routes.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


func _freeze_bots(on: bool) -> void:
	if on:
		for eid in world.bots.keys():
			_frozen[eid] = world.bots[eid]
			world.bots.erase(eid)
			world._bot_dt.erase(eid)
			world._queues[eid] = []
			if world.characters.has(eid):
				world.characters[eid].last_cmd = {}


func _L():
	return world.map.layout


func _build() -> void:
	var L = _L()
	var BT := preload("res://src/ai/bot_team.gd")
	var up := 0
	for s in L.bot_spots():
		if (s.p as Vector3).y > 1.0:
			up += 1
	measure.build = {"spawns": [L.spawns[0].size(), L.spawns[1].size()], "links": L.nav_links.size(), "nav_open": L.stats.get("nav_open", []),
		"spots": L.bot_spots().size(), "spots_upstairs": up, "team_spots": BT.spots.size(), "lights": world.map.dyn.lights.size()}
	t._check("freight_build", L.spawns[0].size() >= 12 and L.spawns[1].size() >= 12 and L.nav_links.size() == 3 and up > 20 and world.map.dyn.lights.size() > 60,
		"spawns %d / %d, stair links %d, walk cells %s, waypoints %d (%d upstairs), lamps %d" % [L.spawns[0].size(), L.spawns[1].size(), L.nav_links.size(),
		str(L.stats.get("nav_open", [])), L.bot_spots().size(), up, world.map.dyn.lights.size()])


func _stairs() -> void:
	## Straight up each flight from its foot, holding forward: on the second floor within 8 s.
	var L = _L()
	var res := []
	var all_ok := true
	if Game.arg("freight_noclip") != null:
		# experiment: the map without its clip brushes (the stair ramps, the bounds)
		for b in world.map.root.find_children("Col_clip_*", "StaticBody3D", true, false):
			(b as StaticBody3D).collision_layer = 0
	for f in L.flights:
		var foot: Vector3 = f.foot
		var d: Vector3 = f.dir
		t._teleport(Vector3(foot.x, 0.05, foot.z) - d * 0.4, atan2(-d.x, -d.z))
		await t._wait(0.4)
		t._act("move_forward", true)
		var t0 := Time.get_ticks_msec()
		var ok := false
		var trace := []
		while (Time.get_ticks_msec() - t0) < 8000:
			await t._wait(0.1)
			var c = t.ch
			if Game.arg("freight_trace") != null:
				var hits := []
				for i in c.get_slide_collision_count():
					var sc: KinematicCollision3D = c.get_slide_collision(i)
					var col = sc.get_collider()
					hits.append("%s n%s" % [str(col.name) if col else "?", str(sc.get_normal().snapped(Vector3.ONE * 0.01))])
				trace.append("%.1f pos %s vel %s floor %s %s" % [(Time.get_ticks_msec() - t0) / 1000.0, str(c.global_position.snapped(Vector3.ONE * 0.01)),
					str(c.velocity.snapped(Vector3.ONE * 0.01)), str(c.is_on_floor()), " ".join(hits)])
			if c.global_position.y > L.level_y(1) - 0.15:
				ok = true
				break
		t._act("move_forward", false)
		if not trace.is_empty():
			print("[freight] %s trace:\n  %s" % [f.name, "\n  ".join(trace)])
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		res.append({"stair": str(f.name), "ok": ok, "seconds": secs, "end": [snappedf(t.ch.global_position.x, 0.1), snappedf(t.ch.global_position.y, 0.1), snappedf(t.ch.global_position.z, 0.1)]})
		all_ok = all_ok and ok
		t._check("freight_stair_" + str(f.name).to_snake_case(), ok, "%s: walked up to y %.2f in %.1f s" % [f.name, t.ch.global_position.y, secs])
	measure.stairs = res
	t._teleport(Vector3(-52.0, 0.05, 0.0), -PI * 0.5)


func _routes() -> void:
	var eid := -1
	for k in _frozen.keys():
		if world.characters.has(k) and world.characters[k].team == t.ch.team:
			eid = k
			break
	if eid < 0:
		t._check("freight_bot_routes", false, "no teammate bot")
		return
	var ch = world.characters[eid]
	var b = _frozen[eid]
	# the enemies wait under the yard's slab (on the safety floor), out of sight and reach
	var i := 0
	for k in _frozen:
		var c = world.characters.get(k)
		if c and c.team != ch.team:
			c.global_position = Vector3(-30.0 + (i % 8) * 4.0, -2.9, -6.0 + (i / 8) * 4.0)
			c.velocity = Vector3.ZERO
			i += 1
	t.ch.global_position = Vector3(-30.0, -2.9, 10.0)   # the tester too: out of the bot's way
	ch.global_position = Vector3(-52.0, 0.05, 0.0)
	ch.velocity = Vector3.ZERO
	ch.health.test_invulnerable = true
	world._queues[eid] = []
	world.bots[eid] = b
	_frozen.erase(eid)
	var legs := []
	var passed := 0
	var stalls_total := 0
	for leg in LEGS:
		var goal: Vector3 = leg[1]
		var p0: Vector3 = ch.global_position
		var t0 := Time.get_ticks_msec()
		var ok := false
		var stalls := 0
		var stalled := false
		var worst := 0.0
		var stall_at := []
		var budget := 25.0 + p0.distance_to(goal) / 2.2
		b.take_order("go", null, goal)   # a new order at once (the last one is held where it arrived)
		while (Time.get_ticks_msec() - t0) < budget * 1000.0:
			if b.order.is_empty() or b.state != "order" or (b.order.p as Vector3) != goal:
				b.take_order("go", null, goal)
			await t._wait(0.25)
			var p: Vector3 = ch.global_position
			var np := float(b._no_prog)
			worst = maxf(worst, np)
			if np > 2.0 and not stalled:
				stalled = true
				stalls += 1
				stall_at.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1), b._ahead()])
			elif np < 0.5:
				stalled = false
			# there by the bot's own measure for an order ("go": within 4 m), and on the goal's floor
			if absf(p.y - goal.y) < 0.7 and Vector2(p.x - goal.x, p.z - goal.z).length() < 4.5:
				ok = true
				break
			if not is_instance_valid(ch) or ch.mode != Motor.GROUND:
				break
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		var pe: Vector3 = ch.global_position
		legs.append({"leg": leg[0], "ok": ok, "seconds": snappedf(secs, 0.1), "metres": snappedf(p0.distance_to(goal), 0.1), "stalls": stalls,
			"worst_stall": snappedf(worst, 0.1), "stalled_at": stall_at, "end": [snappedf(pe.x, 0.1), snappedf(pe.y, 0.1), snappedf(pe.z, 0.1)]})
		print("[freight] %s %s: %.1f s, %d stalls, ended at %s" % ["PASS" if ok else "FAIL", leg[0], secs, stalls, str(pe.snapped(Vector3.ONE * 0.1))])
		if ok:
			passed += 1
		else:
			# carry on from the goal so one bad leg does not fail the rest
			ch.global_position = goal + Vector3(0, 0.1, 0)
			ch.velocity = Vector3.ZERO
		stalls_total += stalls
	measure.routes = legs
	t._check("freight_bot_routes", passed == LEGS.size(), "bot reached %d of %d places across both floors, %d stalls" % [passed, LEGS.size(), stalls_total])
	t._check("freight_bot_no_wall_stalls", stalls_total <= 2, "%d stalls over the tour (no progress for 2 s or more)" % stalls_total)
