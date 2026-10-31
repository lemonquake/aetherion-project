extends RefCounted
## r17 checks on a listen host (`--autotest=r17 [--r17_end=score|time]`), Deathmatch on Malasugue Mall in a respawn
## round:
##   godot --path game -- --host --game_mode=deathmatch --map=malasugue_mall --teams=3 --bots=20 --dm_win=score
##     --dm_score=30 --day_len=120 --autostart=1 --autotest=r17 --shots=<dir>
## night: the match starts at night, the mall never lights its sun, the host's night/day length is the clock's.
## floors: the three teams started on Levels 1, 3 and 5, one floor each. squeeze: a bot pinned by the closing field
## against the mall's outer wall takes heavy damage that grows until it dies (not at once, not never). respawn: that
## bot comes back at its team's spawn floor after respawn_s with full health; a field death scores nothing. score:
## an enemy killed by the player adds one to the player's team on the server and on the HUD's team bar. local: the
## player killed comes back too (the HUD counts down, then a new body under the player's control). end: the round
## ends on the score limit (or on the clock with --r17_end=time) with the right winner and the scores in the results.

const DayCycle := preload("res://src/world/day_cycle.gd")

var t = null
var world = null
var measure := {}


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func _phys(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


func run() -> void:
	if str(Game.arg("r17_only", "")) == "stairs":
		await t._wait(3.0)
		if t.ch.mode != Motor.GROUND:
			world.server_set_mode(t.ch, Motor.GROUND)
			await t._wait(0.5)
		await _stair_sweep()
		var fs := FileAccess.open(t.out_dir + "/r17_stairs.json", FileAccess.WRITE)
		if fs:
			fs.store_string(JSON.stringify(measure, "  ", false))
		return
	if str(Game.arg("r17_only", "")) == "kerbs":
		await t._wait(3.0)
		await _kerb_sweep()
		var fk := FileAccess.open(t.out_dir + "/r17_kerbs.json", FileAccess.WRITE)
		if fk:
			fk.store_string(JSON.stringify(measure, "  ", false))
		return
	if str(Game.arg("r17_only", "")) == "vault":
		await t._wait(3.0)
		if t.ch.mode != Motor.GROUND:
			world.server_set_mode(t.ch, Motor.GROUND)   # Classic: straight out of the aircraft for the survey
			await t._wait(0.5)
		await _vault_survey()
		var fv := FileAccess.open(t.out_dir + "/r17_vault.json", FileAccess.WRITE)
		if fv:
			fv.store_string(JSON.stringify(measure, "  ", false))
		return
	_night()
	_floors()
	_freeze_zone()
	await t._wait(1.0)
	await t._shot("r17_start_hud")
	await _squeeze_and_respawn()
	await _score()
	await _local_respawn()
	await _end()
	var f := FileAccess.open(t.out_dir + "/r17_measure.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  ", false))


func _night() -> void:
	var L = world.map.lighting
	var mt: float = L.match_time()
	var mall := str(Net.config.get("map", "")) == "malasugue_mall"
	var want_len := float(Net.config.get("day_len", 300))
	measure["night"] = {"match_time": mt, "daylight": DayCycle.daylight(mt), "night_only": DayCycle.night_only, "night_s": DayCycle.night_s(),
		"day_offset": world.match_info.get("day_offset", -1), "lit_at_450": DayCycle.daylight(450.0)}
	t._check("r17_starts_at_night", DayCycle.daylight(mt) == 0.0 and float(world.match_info.get("day_offset", 0.0)) == 0.0,
		"match time %.1f s, daylight %.2f, day offset %s" % [mt, DayCycle.daylight(mt), str(world.match_info.get("day_offset"))])
	if mall:
		var lit := 0.0
		for s in [30.0, 150.0, 450.0, 900.0, 1500.0]:
			lit = maxf(lit, DayCycle.daylight(s))
		t._check("r17_mall_night_only", DayCycle.night_only and lit == 0.0 and DayCycle.next_change(10.0)[0] == INF,
			"night_only %s, brightest daylight over 25 min %.2f, next sun change %s" % [DayCycle.night_only, lit, str(DayCycle.next_change(10.0)[0])])
	else:
		t._check("r17_day_length", is_equal_approx(DayCycle.night_s(), want_len) and DayCycle.daylight(want_len + 30.0) > 0.9,
			"host chose %.0f s: night %.0f s, daylight at %.0f s = %.2f" % [want_len, DayCycle.night_s(), want_len + 30.0, DayCycle.daylight(want_len + 30.0)])


# ------------------------------------------------------------------ vaulting (--r17_only=vault)

func _freeze_bots() -> void:
	for eid in world.bots.keys():
		world.bots.erase(eid)
		world._bot_dt.erase(eid)
		world._queues[eid] = []
		if world.characters.has(eid):
			world.characters[eid].last_cmd = {}


func _try_vault(feet: Vector3, facing: Vector3) -> Dictionary:
	## Stand here facing this way and ask the movement code for a vault, as a Jump press would.
	var ch = t.ch
	var yaw := atan2(-facing.x, -facing.z)
	t._teleport(feet + Vector3.UP * 0.05, yaw)
	ch.yaw = yaw
	ch.vault_t = -1.0
	ch.crouching = false
	ch.apply_height()
	await _phys(2)
	ch.global_position = feet + Vector3.UP * 0.02
	ch.yaw = yaw
	ch.velocity = Vector3.ZERO
	await _phys(1)
	var v := Vault.find(ch)
	return {"ok": not v.is_empty(), "why": Vault.why, "drop": float(v.get("drop", 0.0)), "top": float(v.get("top", 0.0))}


func _drop_below(p: Vector3) -> float:
	var space = world.get_world_3d().direct_space_state
	var h = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.3, p + Vector3.DOWN * 60.0, Defs.MOVE_MASK))
	return p.y - (h.position as Vector3).y if not h.is_empty() else 60.0


func _vault_survey() -> void:
	## Every kind of thing a player should be able to vault: open windows (upper floors with a drop behind them, and
	## ground floors), and on Malasugue Mall the balustrades round the courts on Levels 2-5. Counts how many the
	## movement code accepts, with the reasons for the ones it refuses.
	_freeze_zone()
	_freeze_bots()
	t.ch.health.test_invulnerable = true
	var space = world.get_world_3d().direct_space_state
	var L = world.map.layout
	var cases := []   # [kind, feet, facing]
	var types := {}
	for wnd in world.map.dyn.windows:
		types[str(wnd.type)] = int(types.get(str(wnd.type), 0)) + 1
		if str(wnd.type) == "plate" or float(wnd.w) < 0.7 or float(wnd.h) < 0.85:
			continue   # glass: break it first
		var out: Vector3 = wnd.outward
		out.y = 0.0
		if out.length() < 0.5:
			continue
		out = out.normalized()
		var sill: Vector3 = (wnd.xf as Transform3D).origin - Vector3.UP * float(wnd.h) * 0.5
		var inside = space.intersect_ray(PhysicsRayQueryParameters3D.create(sill - out * 0.75 + Vector3.UP * 0.3, sill - out * 0.75 + Vector3.DOWN * 1.6, Defs.MOVE_MASK))
		var through = space.intersect_ray(PhysicsRayQueryParameters3D.create(sill - out * 0.4 + Vector3.UP * 0.45, sill + out * 1.3 + Vector3.UP * 0.45, Defs.MOVE_MASK))
		if inside.is_empty() or not through.is_empty():
			continue
		var h: float = sill.y - (inside.position as Vector3).y
		if h < 0.45 or h > 1.45:
			continue
		var drop := _drop_below(sill + out * 0.9)
		cases.append(["window_upper" if drop > 2.0 else "window_ground", inside.position, out, drop, wnd])
	cases.shuffle()
	var by_kind := {}
	for c in cases:
		by_kind[c[0]] = int(by_kind.get(c[0], 0)) + 1
	var keep := []
	var taken := {}
	for c in cases:
		if int(taken.get(c[0], 0)) < int(Game.arg("r17_vault_n", 40)):
			taken[c[0]] = int(taken.get(c[0], 0)) + 1
			keep.append(c)
	if L.has_method("dm_floor_spawns"):
		# Balustrades: round the Grand Atrium, the West Court and the East Court on Levels 2-5.
		for lv in range(1, L.LEVELS):
			for i in 18:
				var a := TAU * i / 18.0
				var dirs := [[L.GRAND_C, L.GRAND_R], [L.EAST_C, Vector2(L.EAST_R, L.EAST_R)]]
				for d in dirs:
					var c2: Vector2 = d[0]
					var rr: Vector2 = d[1]
					var e := c2 + Vector2(rr.x * cos(a), rr.y * sin(a))
					var n := (e - c2).normalized()   # away from the void
					var stand := e + n * 0.75
					if not L.floor_at(lv, stand) or L.in_tongue(e) or absf(e.y) < 4.2:
						continue
					keep.append(["mall_rail", Vector3(stand.x, L.level_y(lv), stand.y), Vector3(-n.x, 0, -n.y), L.level_y(lv)])
			for zz in [-9.0, -5.0, 5.0, 9.0]:
				for side in [-1.0, 1.0]:
					var wc: Rect2 = L.WEST_COURT
					var ex := wc.position.x if side < 0.0 else wc.end.x
					var st := Vector2(ex + side * 0.75, zz)
					if L.floor_at(lv, st):
						keep.append(["mall_rail", Vector3(st.x, L.level_y(lv), st.y), Vector3(-side, 0, 0), L.level_y(lv)])
	var res := {}
	var whys := {}
	var fails := []
	world.map.lighting.forced_time = 450.0   # daylight outside, for the captures of refused cases
	for c in keep:
		if c.size() > 4 and str(c[4].type) == "shutter" and c[4].get("door") != null:
			c[4].door.server_use(c[1], c[2])   # a closed shutter has to be opened first, like a door
			await t._wait(1.2)
		var r = await _try_vault(c[1], c[2])
		var k: String = c[0]
		if not res.has(k):
			res[k] = [0, 0]
		res[k][1] += 1
		if r.ok:
			res[k][0] += 1
		else:
			var w := str(r.why).split(" (")[0]
			whys[k + ": " + w] = int(whys.get(k + ": " + w, 0)) + 1
			fails.append([k, str((c[1] as Vector3).snapped(Vector3.ONE * 0.01)), str((c[2] as Vector3).snapped(Vector3.ONE * 0.01)), str(r.why),
				str(c[4].type) if c.size() > 4 else "rail", snappedf(float(c[4].door.angle), 0.01) if c.size() > 4 and c[4].get("door") != null and "angle" in c[4].door else ""])
			if fails.size() <= 6:
				t.ctl.pitch = -0.15
				await t._shot("vault_refused_%d" % fails.size())
	measure["vault_survey"] = {"map": str(Net.config.get("map", "")), "window_types": types, "found": by_kind, "result": res, "refused": whys, "fails": fails}
	var parts := []
	for k in res:
		parts.append("%s %d/%d" % [k, int(res[k][0]), int(res[k][1])])
	var all_ok := true
	for k in res:
		if float(res[k][0]) < float(res[k][1]) * 0.85:
			all_ok = false
	t._check("r17_vault_survey", all_ok and not res.is_empty(), "vaults found: %s; refused: %s" % [", ".join(parts), str(whys)])


# ------------------------------------------------------------------ kerbs (--r17_only=kerbs)

func _cross(from: Vector3, dir: Vector3, dist: float, sprint: bool) -> Dictionary:
	## Run straight from here for dist metres (Forward held, as a player does): how far it got, the longest stop,
	## the longest stretch below half the expected speed, and the biggest single-tick jump up.
	var ch = t.ch
	t._teleport(from + Vector3.UP * 0.05, atan2(-dir.x, -dir.z))
	ch.yaw = atan2(-dir.x, -dir.z)
	await t._wait(0.35)
	var p0: Vector3 = ch.global_position
	t._act_press("move_forward")
	if sprint:
		t._act_press("sprint")
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var el := 0.0
	var slow := 0.0
	var worst_slow := 0.0
	var still := 0.0
	var worst_still := 0.0
	var pop := 0.0
	var last: Vector3 = p0
	var slow_at := Vector3.INF
	var expect := Defs.move("sprint_speed") if sprint else Defs.move("run_speed")
	var trace := []
	var tick := 0
	while el < dist / expect * 2.5 + 1.5:
		await t.get_tree().physics_frame
		el += dt
		var p: Vector3 = ch.global_position
		var adv := Vector2(p.x - last.x, p.z - last.z).dot(Vector2(dir.x, dir.z)) / dt
		pop = maxf(pop, p.y - last.y)
		tick += 1
		if tick % 3 == 0:
			trace.append([snappedf(el, 0.01), snappedf(Vector2(p.x - p0.x, p.z - p0.z).dot(Vector2(dir.x, dir.z)), 0.01), snappedf(p.y, 0.01),
				snappedf(Vector2(ch.velocity.x, ch.velocity.z).length(), 0.1), int(ch.is_on_floor()), ch.mode])
		if el > 0.8:   # past the run-up (speed builds up over the first steps)
			if adv < expect * 0.5:
				slow += dt
				if slow > worst_slow:
					worst_slow = slow
					slow_at = p
			else:
				slow = 0.0
			if adv < 0.3:
				still += dt
				worst_still = maxf(worst_still, still)
			else:
				still = 0.0
		last = p
		if Vector2(p.x - p0.x, p.z - p0.z).dot(Vector2(dir.x, dir.z)) >= dist or worst_still > 1.0:
			break
	t._act_release("move_forward")
	t._act_release("sprint")
	var got := Vector2(last.x - p0.x, last.z - p0.z).dot(Vector2(dir.x, dir.z))
	# What the body is caught on: the ground ahead, and the slide contacts of the last tick.
	var probe := []
	var space = world.get_world_3d().direct_space_state
	for i in 13:
		var q := last + dir * (i * 0.1)
		var h = space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 0.8, q + Vector3.DOWN * 0.8, Defs.MOVE_MASK))
		probe.append([snappedf(i * 0.1, 0.01), snappedf((h.position as Vector3).y, 0.001) if not h.is_empty() else null,
			(str(h.collider.get_meta("what")) if h.collider is Object and h.collider.has_meta("what") else (h.collider.get_class() if not h.is_empty() else "-")) if not h.is_empty() else "-"])
	var contacts := []
	for i in ch.get_slide_collision_count():
		var c: KinematicCollision3D = ch.get_slide_collision(i)
		contacts.append([(c.get_normal() as Vector3).snapped(Vector3.ONE * 0.01), (c.get_position() - last).snapped(Vector3.ONE * 0.01)])
	return {"probe": probe, "contacts": contacts, "corr": t.ctl.stats.corrections, "got": got, "still": worst_still, "slow": worst_slow, "pop": pop, "slow_at": slow_at, "end_y": last.y, "trace": trace}


func _kerb_sweep() -> void:
	## Lawless Sub: on to a sidewalk from the road, across it and off its far side, and back the other way; square on
	## and 35 degrees off; walking and sprinting. A crossing fails if it stops for 0.25 s, crawls below half speed for
	## 0.3 s, or is popped up more than 0.25 m in one tick.
	_freeze_zone()
	_freeze_bots()
	t.ch.health.test_invulnerable = true
	world.map.lighting.forced_time = 450.0
	var L = world.map.layout
	var space = world.get_world_3d().direct_space_state
	var cases := []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Game.arg("r17_seed", 7))
	for rd in L.roads:
		var sw := float(rd.sidewalk)
		if sw <= 0.0:
			continue
		var s := float(rd.lo) + 8.0 + rng.randf() * 10.0
		while s < float(rd.hi) - 8.0:
			for side in [-1.0, 1.0]:
				var hw := float(rd.w) * 0.5
				var across := Vector2(0, side) if int(rd.axis) == 0 else Vector2(side, 0)
				var along := Vector2(1, 0) if int(rd.axis) == 0 else Vector2(0, 1)
				var road_pt: Vector2 = (Vector2(s, float(rd.c)) if int(rd.axis) == 0 else Vector2(float(rd.c), s)) + across * (hw - 2.0)
				var far_pt := road_pt + across * (2.0 + sw + 1.6)
				if not L.in_play_area(road_pt) or not L.in_play_area(far_pt):
					continue
				# Something standing on or just behind the sidewalk (a wall, a post, a parked car): not this spot.
				var blocked := false
				for hh in [0.6, 1.2]:
					var a3 := Vector3(road_pt.x, L.surface_y(road_pt) + hh, road_pt.y)
					var b3 := Vector3(far_pt.x, L.surface_y(far_pt) + hh, far_pt.y) + Vector3(across.x, 0, across.y) * 0.6
					if not space.intersect_ray(PhysicsRayQueryParameters3D.create(a3, b3, Defs.MOVE_MASK)).is_empty():
						blocked = true
				if blocked:
					continue
				for ang in [0.0, 35.0]:
					var d2 := across.rotated(deg_to_rad(ang) * (1.0 if rng.randf() < 0.5 else -1.0))
					var dist := (2.0 + sw + 1.6) / cos(deg_to_rad(ang))
					var start_on := road_pt - (d2 - across) * 0.0
					cases.append({"road": str(rd.name), "from": Vector3(start_on.x, L.surface_y(start_on), start_on.y), "dir": Vector3(d2.x, 0, d2.y), "dist": dist, "way": "on", "ang": ang})
					var back := road_pt + d2 * dist
					cases.append({"road": str(rd.name), "from": Vector3(back.x, L.surface_y(back), back.y), "dir": Vector3(-d2.x, 0, -d2.y), "dist": dist, "way": "off", "ang": ang})
			s += 40.0 + rng.randf() * 20.0
	cases.shuffle()
	if Game.arg("r17_kerb_road") != null:
		cases = cases.filter(func(c): return str(c.road) == str(Game.arg("r17_kerb_road")).replace("_", " ") and str(c.way) == str(Game.arg("r17_kerb_way", c.way)) and float(c.ang) == float(Game.arg("r17_kerb_ang", c.ang)))
	cases = cases.slice(0, int(Game.arg("r17_kerb_n", 80)))
	var fails := []
	var stats := {"n": 0, "fail": 0}
	var k := 0
	for c in cases:
		k += 1
		var r := await _cross(c.from, c.dir, float(c.dist), k % 2 == 0)
		stats.n += 1
		var bad: bool = float(r.still) > 0.25 or float(r.slow) > 0.3 or float(r.pop) > 0.25 or float(r.got) < float(c.dist) - 0.6
		if bad:
			stats.fail += 1
			fails.append({"road": c.road, "way": c.way, "ang": c.ang, "sprint": k % 2 == 0, "from": (c.from as Vector3).snapped(Vector3.ONE * 0.1),
				"got": snappedf(float(r.got), 0.01), "dist": snappedf(float(c.dist), 0.01), "still": snappedf(float(r.still), 0.01),
				"slow": snappedf(float(r.slow), 0.01), "pop": snappedf(float(r.pop), 0.01), "slow_at": (r.slow_at as Vector3).snapped(Vector3.ONE * 0.1) if r.slow_at != Vector3.INF else null,
				"trace": r.trace.slice(-12) if fails.size() < 3 else [], "probe": r.probe if fails.size() < 4 else [], "contacts": r.contacts, "corr": r.corr})
			if fails.size() <= 4:
				t.ctl.pitch = -0.5
				t._teleport((r.slow_at if r.slow_at != Vector3.INF else c.from) - (c.dir as Vector3) * 1.5, atan2(-c.dir.x, -c.dir.z))
				t.ctl.pitch = -0.5
				await t._wait(0.4)
				await t._shot("kerb_fail_%d" % fails.size())
	measure["kerbs"] = {"stats": stats, "fails": fails}
	t._check("r17_kerb_crossings", stats.fail == 0 and stats.n >= 20, "%d crossings on to and off sidewalks, %d failed: %s" % [stats.n, stats.fail, str(fails.slice(0, 5))])


# ------------------------------------------------------------------ house stairs (--r17_only=stairs)

func _walk_to(goal: Vector3, secs: float, y_goal: float = INF) -> Dictionary:
	## Hold Forward, steering at goal (as a player aims with the mouse), until within 0.35 m of it on the flat (or,
	## with y_goal, until that height is reached). Returns {ok, t, stuck (longest stop, s)}.
	var ch = t.ch
	t._act_press("move_forward")
	var el := 0.0
	var still := 0.0
	var worst := 0.0
	var last: Vector3 = ch.global_position
	var ok := false
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	while el < secs:
		var to: Vector3 = goal - ch.global_position
		t.ctl.yaw = atan2(-to.x, -to.z)
		await t.get_tree().physics_frame
		el += dt
		var p: Vector3 = ch.global_position
		if p.distance_to(last) < 0.012:
			still += dt
			worst = maxf(worst, still)
		else:
			still = 0.0
		last = p
		if y_goal != INF:
			if absf(p.y - y_goal) < 0.25 and Vector2(p.x - goal.x, p.z - goal.z).length() < 0.9:
				ok = true
				break
		elif Vector2(p.x - goal.x, p.z - goal.z).length() < 0.35 and absf(p.y - goal.y) < 0.5:
			ok = true
			break
		if worst > 1.2:
			break
	t._act_release("move_forward")
	return {"ok": ok, "t": el, "stuck": worst, "at": ch.global_position}


func _stair_sweep() -> void:
	## Every flight in a sample: up from the floor in front of its foot, out on to the landing at the top, then back
	## down to the floor, steering like a player. A leg fails if it does not get there or stops for over 0.5 s.
	_freeze_zone()
	_freeze_bots()
	t.ch.health.test_invulnerable = true
	world.map.lighting.forced_time = 450.0
	var flights: Array = world.map.stairs.duplicate()
	flights.shuffle()
	var n := 0
	var fails := []
	var times := []
	var widths := {}
	for f in flights:
		if n >= int(Game.arg("r17_stairs_n", 30)):
			break
		if not f.has("start") or not f.has("top"):
			continue
		var w := snappedf(float(f.get("w", 0.0)), 0.01)
		widths[str(w)] = int(widths.get(str(w), 0)) + 1
		var dir: Vector3 = f.dir
		dir.y = 0.0
		dir = dir.normalized()
		var start: Vector3 = f.start
		var top: Vector3 = f.top
		var rise := float(f.rise)
		var run := float(f.run)
		var tread_top: Vector3 = start + dir * (run - 0.15) + Vector3.UP * rise
		var floor_in := start - dir * 0.55   # (a shallow house has under a metre in front of the flight)
		n += 1
		# up: from the floor in front of the foot to the top tread, then out on to the landing
		t._teleport(floor_in + Vector3.UP * 0.05, atan2(-dir.x, -dir.z))
		await t._wait(0.3)
		var up := await _walk_to(tread_top, 6.0, tread_top.y)
		var out := {"ok": false, "t": 0.0, "stuck": 0.0, "at": t.ch.global_position}
		if up.ok:
			out = await _walk_to(top, 3.0)
		# down: from the landing back on to the top tread, then down to the floor at the foot
		t._teleport(top + Vector3.UP * 0.05, 0.0)
		await t._wait(0.3)
		var back := await _walk_to(tread_top, 3.0)
		var down := {"ok": false, "t": 0.0, "stuck": 0.0, "at": t.ch.global_position}
		if back.ok:
			down = await _walk_to(floor_in, 6.0, floor_in.y)
		var legs := {"up": up, "out": out, "in": back, "down": down}
		var bad := []
		if not bool(out.ok) and fails.size() < 4:
			t.ctl.pitch = -0.2
			t._teleport(out.at, t.ctl.yaw)
			await t._wait(0.3)
			await t._shot("stair_exit_%d" % (fails.size() + 1))
		for k in legs:
			var r: Dictionary = legs[k]
			if not bool(r.ok) or float(r.stuck) > 0.5:
				bad.append("%s %s at %s (stuck %.1f s)" % [k, "failed" if not r.ok else "stopped", str((r.at as Vector3).snapped(Vector3.ONE * 0.1)), float(r.stuck)])
		times.append(float(up.t) + float(down.t))
		if not bad.is_empty():
			fails.append({"foot": (start as Vector3).snapped(Vector3.ONE * 0.1), "w": w, "rise": snappedf(rise, 0.01), "run": snappedf(run, 0.01), "legs": bad})
			if fails.size() <= 4:
				t.ctl.pitch = -0.3
				await t._shot("stair_fail_%d" % fails.size())
	measure["stairs"] = {"map": str(Net.config.get("map", "")), "n": n, "widths": widths, "fails": fails, "mean_up_down_s": (times.reduce(func(a, b): return a + b, 0.0) / maxf(times.size(), 1.0))}
	t._check("r17_house_stairs", fails.is_empty() and n >= 10, "%d flights up, out, in and down; %d failed: %s" % [n, fails.size(), str(fails.slice(0, 5))])


func _floors() -> void:
	var ms = world.match_server
	var L = world.map.layout
	if not L.has_method("dm_floor_spawns"):
		return
	var levels := []
	var bad := []
	var per_team := {}
	for team in Net.dm_teams():
		var lv := int(ms.spawn_info.get(team, {}).get("level", -1))
		levels.append(lv)
		per_team[team] = {"level": lv, "ys": []}
	for c in world.characters.values():
		var lv := int(per_team.get(c.team, {}).get("level", -1))
		(per_team[c.team].ys as Array).append(snappedf(c.global_position.y, 0.01))
		if lv < 0 or absf(c.global_position.y - L.level_y(lv)) > 1.2:
			bad.append("%s team %d at y %.1f" % [c.pname, c.team, c.global_position.y])
	var distinct := {}
	for lv in levels:
		distinct[lv] = true
	measure["floors"] = per_team
	var floors_txt := ", ".join(levels.map(func(lv): return "Level %d" % (int(lv) + 1)))
	t._check("r17_floor_spawns", distinct.size() == levels.size() and levels.all(func(lv): return lv in [0, 2, 4]) and bad.is_empty(),
		"teams on %s; %d characters, off their floor: %s" % [floors_txt, world.characters.size(), ", ".join(bad) if not bad.is_empty() else "none"])


func _freeze_zone() -> void:
	var ms = world.match_server
	ms.zone = {"i": 0, "state": "wait", "t0": Net.tick, "t1": Net.tick + 100000000, "c0": Vector2.ZERO, "r0": 9000.0, "c1": Vector2.ZERO, "r1": 9000.0,
		"dps": 0.0, "shrink_s": 60.0}
	ms._broadcast()


func _enemy_bot(alive_only: bool = true):
	for b in world.bots.values():
		if b.ch.team != t.ch.team and (not alive_only or b.ch.mode == Motor.GROUND):
			return b
	return null


func _squeeze_and_respawn() -> void:
	## Two bot dummies side by side outside the mall's north wall, the field closing on a centre straight through the
	## wall from them: the push is square into the wall, so they are stuck there (a pile of two: neither spares the
	## other).
	var ms = world.match_server
	var dummy = _enemy_bot()
	if dummy == null:
		t._check("r17_squeeze", false, "no enemy bot")
		return
	dummy.test_idle = true
	var pid: int = dummy.ch.pid
	var team: int = dummy.ch.team
	var hp = dummy.ch.health
	var score0: Dictionary = ms.team_score.duplicate()
	if str(Net.config.get("map", "")) != "malasugue_mall":
		# Another map: no known wall to pin against here; the field kills the dummy outright, to check the respawn.
		hp.catastrophic = true
		world._after_damage(dummy.ch, hp.apply_simple(999.0, "field"), -1)
		await _respawned(pid, team, hp, score0)
		return
	var mate = null
	for b in world.bots.values():
		if b != dummy and b.ch.mode == Motor.GROUND and b.ch.team != t.ch.team:
			mate = b
			break
	Field.test_only = [dummy.ch.eid]
	dummy.ch.global_position = Vector3(-30.0, 0.05, -47.6)
	dummy.ch.velocity = Vector3.ZERO
	var mate_hp = null
	if mate:
		mate.test_idle = true
		mate_hp = mate.ch.health
		Field.test_only.append(mate.ch.eid)
		mate.ch.global_position = Vector3(-29.3, 0.05, -47.6)
		mate.ch.velocity = Vector3.ZERO
	await _phys(2)
	var p0: Vector3 = dummy.ch.global_position
	# Centre 30 m inside the mall straight behind them; the edge 1 m past them now, closing 1.5 m/s.
	var c := Vector2(-29.65, -17.0)
	var d0 := Vector2(p0.x, p0.z).distance_to(c)
	ms.zone = {"i": 1, "state": "shrink", "t0": Net.tick, "t1": Net.tick + int(30.0 * Defs.TICK_RATE), "c0": c, "r0": d0 - 1.0,
		"c1": c, "r1": d0 - 46.0, "dps": 0.0, "shrink_s": 30.0}
	ms._broadcast()
	var trace := []
	var first_hurt := -1.0
	var dead_t := -1.0
	var min_hp := 100.0
	for i in 600:
		await _phys(1)
		var h := float(hp.health)
		if first_hurt < 0.0 and h < 99.9:
			first_hurt = i / 60.0
		if i % 15 == 0:
			trace.append([snappedf(i / 60.0, 0.01), snappedf(h, 0.1), snappedf(float(dummy.ch.field_pin) if is_instance_valid(dummy.ch) else -1.0, 0.01)])
		if hp.dead:
			dead_t = i / 60.0
			break
		min_hp = minf(min_hp, h)
		if i == 70:
			await t._shot("r17_squeeze_outside")
	if mate_hp != null and not mate_hp.dead:
		await t._until(func(): return mate_hp.dead, 3.0)
	Field.test_only = []
	_freeze_zone()
	var hurt_for := dead_t - first_hurt if dead_t > 0.0 and first_hurt >= 0.0 else -1.0
	var mate_ok: bool = mate_hp == null or (mate_hp.dead and str(mate_hp.last_cause) == "field")
	measure["squeeze"] = {"start": p0, "trace": trace, "first_hurt_s": first_hurt, "dead_s": dead_t, "hurt_for_s": hurt_for, "cause": str(hp.last_cause)}
	t._check("r17_squeeze", dead_t > 0.0 and str(hp.last_cause) == "field" and hurt_for >= 0.8 and hurt_for <= 5.0 and mate_ok,
		"two bots pinned against the outer wall: hurt from %.2f s, dead at %.2f s (%.2f s of squeezing), cause %s; the one beside it dead %s (%s); health trace %s" % [
		first_hurt, dead_t, hurt_for, str(hp.last_cause), str(mate_hp.dead) if mate_hp else "-", str(mate_hp.last_cause) if mate_hp else "-",
		str(trace.filter(func(r): return float(r[1]) < 100.0))])
	await _respawned(pid, team, hp, score0)


func _respawned(pid: int, team: int, hp, score0: Dictionary) -> void:
	# Back at its team's spawn after respawn_s, unhurt; the field death scored nothing.
	var ms = world.match_server
	var t0 := Time.get_ticks_msec()
	var back = await t._until(func(): return world.char_by_pid(pid) != null, 9.0)
	var wait_s := (Time.get_ticks_msec() - t0) / 1000.0
	var nc = world.char_by_pid(pid)
	var lv := int(ms.spawn_info.get(team, {}).get("level", -1))
	var on_floor: bool = nc != null and (lv < 0 or absf(nc.global_position.y - world.map.layout.level_y(lv)) < 1.2)
	measure["respawn"] = {"back": back, "wait_s": wait_s, "pos": nc.global_position if nc else Vector3.INF, "level": lv,
		"health": float(nc.health.health) if nc else -1.0, "score_before": score0, "score_after": ms.team_score.duplicate()}
	t._check("r17_respawn", back and on_floor and float(nc.health.health) >= 99.0 and nc.wpn.current_id() != "" and str(score0) == str(ms.team_score),
		"%s back after %.1f s at %s (team floor Level %d), health %.0f, holding %s; scores %s -> %s" % [str(nc.pname) if nc else "?", wait_s,
		str(nc.global_position.round()) if nc else "-", lv + 1, float(nc.health.health) if nc else 0.0, nc.wpn.current_id() if nc else "-", str(score0), str(ms.team_score)])
	if nc and world.bots.has(nc.eid):
		world.bots[nc.eid].test_idle = false


func _score() -> void:
	## The player kills an enemy: their team scores, on the server and on the HUD.
	var ms = world.match_server
	var e = _enemy_bot()
	if e == null:
		t._check("r17_score", false, "no enemy bot")
		return
	var mine: int = t.ch.team
	var before := int(ms.team_score.get(mine, 0))
	e.ch.health.shield_until = -1
	var res: Dictionary = e.ch.health.apply_simple(999.0, "gunshot", "torso", t.ch.eid)
	world._after_damage(e.ch, res, t.ch.eid)
	await t._wait(0.5)
	var after := int(ms.team_score.get(mine, 0))
	var hud_n := -1
	if world.hud and mine < world.hud._team_labels.size():
		hud_n = int((world.hud._team_labels[mine][1] as Label).text)
	var goal: String = world.hud._goal_label.text if world.hud and world.hud._goal_label else ""
	measure["score"] = {"before": before, "after": after, "hud": hud_n, "goal": goal}
	t._check("r17_score", after == before + 1 and hud_n == after and goal != "",
		"team %d: %d -> %d on the server, HUD team bar %d, under it \"%s\"" % [mine, before, after, hud_n, goal])
	await t._shot("r17_score_hud")


func _local_respawn() -> void:
	## The player is killed by an enemy: the death card and a countdown, then a new body under the player's control.
	var ms = world.match_server
	var e = _enemy_bot()
	var killer: int = e.ch.eid if e else -1
	var old = t.ch
	var old_eid: int = old.eid
	var team: int = old.team
	var enemy_team: int = e.ch.team if e else -1
	var es_before := int(ms.team_score.get(enemy_team, 0))
	old.health.shield_until = -1
	var res: Dictionary = old.health.apply_simple(999.0, "gunshot", "torso", killer)
	world._after_damage(old, res, killer)
	await t._wait(1.5)
	var label: String = world.hud._respawn_label.text if world.hud and world.hud._respawn_label and world.hud._respawn_label.visible else ""
	await t._shot("r17_respawn_countdown")
	var back = await t._until(func(): return world.local_char != null and is_instance_valid(world.local_char) and world.local_char.eid != old_eid, 9.0)
	await t._wait(0.5)
	var nc = world.local_char
	var ctl_ok: bool = world.controller != null and world.controller.ch == nc
	var lv := int(ms.spawn_info.get(team, {}).get("level", -1))
	var on_floor: bool = nc != null and (lv < 0 or absf(nc.global_position.y - world.map.layout.level_y(lv)) < 1.2)
	var shielded: bool = nc != null and nc.health.shielded()
	measure["local_respawn"] = {"countdown": label, "back": back, "controller": ctl_ok, "pos": nc.global_position if nc else Vector3.INF, "shielded": shielded,
		"enemy_score": [es_before, int(ms.team_score.get(enemy_team, 0))]}
	t._check("r17_local_respawn", label.begins_with("Respawning") and back and ctl_ok and on_floor and int(ms.team_score.get(enemy_team, 0)) == es_before + 1,
		"countdown \"%s\"; back %s, controlled %s, at %s (team floor Level %d), spawn protection %s; the killer's team %d -> %d" % [label, back, ctl_ok,
		str(nc.global_position.round()) if nc else "-", lv + 1, shielded, es_before, int(ms.team_score.get(enemy_team, 0))])
	if nc:
		t.ch = nc
		t.ctl = world.controller
	await t._wait(1.0)
	await t._shot("r17_back_in")


func _end() -> void:
	var ms = world.match_server
	var mode := str(Game.arg("r17_end", "score"))
	var mine: int = t.ch.team
	if mode == "time":
		ms.win_by = "time"
		ms.team_score[mine] = int(ms.team_score.get(mine, 0)) + 5   # clearly ahead when the clock runs out
		ms.time_limit_s = ms.round_time() + 2.0
	else:
		ms.score_limit = int(ms.team_score.get(mine, 0)) + 1
		var e = _enemy_bot()
		if e:
			e.ch.health.shield_until = -1
			var res: Dictionary = e.ch.health.apply_simple(999.0, "gunshot", "torso", t.ch.eid)
			world._after_damage(e.ch, res, t.ch.eid)
	var ended = await t._until(func(): return ms.phase == "ended", 8.0)
	await t._wait(1.0)
	var res_text := ""
	if world.hud and world.hud.results:
		for l in world.hud.results.find_children("*", "Label", true, false):
			if "wins the round" in (l as Label).text or "Draw" in (l as Label).text:
				res_text = (l as Label).text
	measure["end"] = {"mode": mode, "ended": ended, "scores": ms.team_score.duplicate(), "results": res_text}
	t._check("r17_end_" + mode, ended and res_text.contains(str(ms.team_name(mine))),
		"ended %s on the %s rule; scores %s; results say \"%s\"" % [ended, mode, str(ms.team_score), res_text])
	await t._shot("r17_results_" + mode)
