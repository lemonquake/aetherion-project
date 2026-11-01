extends RefCounted
## Speed bursts (`--autotest=bursts [--bursts_only=flat,stairs,water]`; on Malasugue Mall: `mall`): the player's horizontal speed every physics
## tick (server-authoritative on a listen host) while running on flat ground (reference), up house stairs, and out of
## the estero up its bank. A burst: a tick over twice the speed asked for (run 4.4, sprint 6.3 m/s: a teleport), or a
## 0.1 s stretch over 1.2x it (a surge). Every run also gives its sharpest speed rise over 0.25 s. Profiles go to
## <shots>/bursts_measure.json.
##   godot --path game -- --host --game_mode=deathmatch --bots=4 --autostart=1 --autotest=bursts --shots=<dir>

var t = null
var world = null
var L = null
var measure := {}


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 40.0)
	await t._wait(1.0)
	L = world.map.layout
	var ms = world.match_server
	if ms and not ms.zone.is_empty():
		ms.zone = {"i": 0, "state": "wait", "t0": Net.tick, "t1": Net.tick + 100000000, "c0": Vector2.ZERO, "r0": 9000.0, "c1": Vector2.ZERO,
			"r1": 9000.0, "dps": 0.0, "shrink_s": 60.0}
		ms._broadcast()
	for b in world.bots.values():
		b.test_idle = true
		b.ch.global_position = Vector3(150.0 + b.ch.eid, 1.5, -150.0)
	var only := str(Game.arg("bursts_only", "")).split(",", false)
	var names := ["mall"] if L.get("escalators") != null else ["flat", "stairs", "water"]
	for n in names:
		if only.is_empty() or n in only:
			await (Callable(self, "_" + n)).call()
	var f := FileAccess.open(t.out_dir + "/bursts_measure.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


func _drive(start: Vector3, dir: Vector3, secs: float, sprint: bool) -> Dictionary:
	## Holds forward (and sprint) facing dir from start; per-tick horizontal speeds and heights.
	for a in ["move_forward", "sprint", "jump", "crouch"]:
		t._act_release(a)
	t._teleport(start, atan2(-dir.x, -dir.z))
	t.ch.health.reset()
	await t._wait(0.5)
	var yaw := atan2(-dir.x, -dir.z)
	t._act_press("move_forward")
	if sprint:
		t._act_press("sprint")
	var sp := []
	var ys := []
	var depth := []
	var prev: Vector3 = t.ch.global_position
	Character.step_trace.clear()
	Character.step_trace_on = true
	for i in int(secs * 60.0):
		t.ctl.yaw = yaw
		t.ctl.pitch = 0.0
		await t.get_tree().physics_frame
		var p: Vector3 = t.ch.global_position
		sp.append(Vector2(p.x - prev.x, p.z - prev.z).length() * 60.0)
		ys.append(p.y)
		depth.append(t.ch.water_depth())
		prev = p
	for a in ["move_forward", "sprint"]:
		t._act_release(a)
	Character.step_trace_on = false
	var steps: Array = Character.step_trace.filter(func(e): return int(e[0]) == t.ch.eid)
	return {"sp": sp, "y": ys, "depth": depth, "steps": steps}


func _stats(r: Dictionary, cap: float) -> Dictionary:
	var sp: Array = r.sp
	var bursts := 0
	var top := 0.0
	var top_i := -1
	var win := 0.0
	var rise := 0.0
	for i in sp.size():
		if i < 3:
			continue   # the first ticks after the teleport
		if float(sp[i]) > top:
			top = float(sp[i])
			top_i = i
		if float(sp[i]) > cap * 2.0:
			bursts += 1
		if i >= 6:
			var s := 0.0
			for k in 6:
				s += float(sp[i - k])
			win = maxf(win, s / 6.0)
			if s / 6.0 > cap * 1.2:
				bursts += 1
		if i >= 18:
			var a := 0.0
			var b := 0.0
			for k in 3:
				a += float(sp[i - 15 - k])
				b += float(sp[i - k])
			rise = maxf(rise, (b - a) / 3.0)
	var st: Array = r.get("steps", [])
	return {"bursts": bursts, "top_tick": snappedf(top, 0.01), "top_at": top_i, "top_0.1s": snappedf(win, 0.01), "rise_0.25s": snappedf(rise, 0.01),
		"step_ups": st.size(), "steps": st.slice(0, 5)}


func _flat() -> void:
	## Reference: a straight run and sprint on open ground.
	var spot := _open_ground()
	var out := {}
	for g in [["run", false, Defs.move("run_speed")], ["sprint", true, Defs.move("sprint_speed")]]:
		var r := await _drive(spot.p, spot.d, 3.0, g[1])
		out[g[0]] = _stats(r, float(g[2]))
	measure["flat"] = out
	t._check("bursts_flat", int(out.run.bursts) == 0 and int(out.sprint.bursts) == 0, "open ground: run %s, sprint %s" % [str(out.run), str(out.sprint)])


func _open_ground() -> Dictionary:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for rd in L.roads:
		var a: Vector2 = rd.pts[0]
		var b: Vector2 = rd.pts[1]
		if a.distance_to(b) < 60.0:
			continue
		var d2 := (b - a).normalized()
		var c := (a + b) * 0.5 + Vector2(-d2.y, d2.x) * float(rd.w) * 0.25   # in a lane, clear of a median
		var p := Vector3(c.x, L.ground_height(c.x, c.y) + 0.1, c.y)
		return {"p": p, "d": Vector3(d2.x, 0.0, d2.y)}
	return {"p": Vector3(0, 1, 0), "d": Vector3(1, 0, 0)}


func _stairs() -> void:
	## House flights from the first tread, 3 s at a run (and the first three again at a sprint).
	var picks := []
	for f in world.map.stairs:
		if (f.top as Vector3).y - (f.foot as Vector3).y > 2.0 and float(f.get("w", 1.0)) >= 0.85:
			picks.append(f)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var chosen := []
	for i in mini(10, picks.size()):
		chosen.append(picks.pop_at(rng.randi_range(0, picks.size() - 1)))
	var runs := []
	var worst := {"bursts": 0, "top_tick": 0.0, "top_0.1s": 0.0}
	var n_burst := 0
	for i in chosen.size():
		var f = chosen[i]
		var dir: Vector3 = f.dir
		dir.y = 0.0
		dir = dir.normalized()
		var start: Vector3 = (f.foot as Vector3) + dir * 0.4 + Vector3.UP * 0.3
		for g in ([["run", false, Defs.move("run_speed")]] + ([["sprint", true, Defs.move("sprint_speed")]] if i < 3 else [])):
			var r := await _drive(start, dir, 3.0, g[1])
			var s := _stats(r, float(g[2]))
			s["gait"] = g[0]
			s["foot"] = str((f.foot as Vector3).snapped(Vector3.ONE * 0.1))
			s["climbed"] = snappedf(float(r.y[-1]) - (f.foot as Vector3).y, 0.01)
			runs.append(s)
			print("[bursts] stairs %s %s: %s" % [s.foot, g[0], str(s)])
			if int(s.bursts) > 0:
				n_burst += 1
			worst.bursts = maxi(int(worst.bursts), int(s.bursts))
			worst.top_tick = maxf(float(worst.top_tick), float(s.top_tick))
			worst["top_0.1s"] = maxf(float(worst["top_0.1s"]), float(s["top_0.1s"]))
	measure["stairs"] = runs
	t._check("bursts_stairs", n_burst == 0, "%d stair runs, %d with bursts; worst tick %.1f m/s, worst 0.1 s %.1f m/s (run 4.4, sprint 6.3)" % [runs.size(), n_burst, worst.top_tick, worst["top_0.1s"]])


func _water() -> void:
	## From the estero's middle up its bank on to the land, at a run; and out of the walled canal over the coping.
	var runs := []
	var n_burst := 0
	var worst_rise := 0.0
	for e in L.esteros:
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var d := (b - a).normalized()
		var nrm := Vector2(-d.y, d.x)
		for k in [40.0, 80.0, 130.0, 180.0]:
			var q = a + d * k
			for side in [1.0, -1.0]:
				var start := Vector3(q.x, L.terrain_height(q.x, q.y) + 0.05, q.y)
				var r := await _drive(start, Vector3(nrm.x * side, 0.0, nrm.y * side), 4.0, false)
				var s := _stats(r, Defs.move("run_speed"))
				s["from"] = str(Vector2(q.x, q.y).round())
				s["side"] = side
				runs.append(s)
				print("[bursts] estero %s side %d: %s" % [s.from, int(side), str(s)])
				if int(s.bursts) > 0:
					n_burst += 1
				worst_rise = maxf(worst_rise, float(s["rise_0.25s"]))
				if runs.size() == 1:
					measure["water_profile"] = {"speed": (r.sp as Array).map(func(x): return snappedf(float(x), 0.01)),
						"depth": (r.depth as Array).map(func(x): return snappedf(float(x), 0.01))}
	measure["water"] = runs
	t._check("bursts_water", n_burst == 0 and worst_rise <= 2.6, "%d runs out of the estero, %d with bursts; sharpest speed rise %.2f m/s in 0.25 s (run 4.4 m/s)" % [runs.size(), n_burst, worst_rise])

func _mall() -> void:
	## Malasugue Mall: up every fire-stair flight of the first storey, the department store's stopped escalators and
	## the running up escalators, at a run and at a sprint, from a metre before the foot. Besides the horizontal
	## bursts, the speed along the flight (3D, climbing) over 0.1 s must stay within 1.2x the gait (a burst up a
	## slope reads as climbing faster than running on the flat). Also at 32 degrees across a flight (r25: the
	## ramp ahead was taken for a step and the body shoved up it at 8-9 m/s).
	var flights := []
	for f in world.map.stairs:
		if float((f.foot as Vector3).y) < 4.0:
			for ang in [0.0, -32.0, 32.0]:
				flights.append({"kind": "stairs", "foot": f.foot, "top": f.top, "ang": ang})
	for e in L.escalators:
		if bool(e.up) and int(e.t) == 0:
			flights.append({"kind": "escalator", "foot": (e.a as Vector3) - (e.dir as Vector3) * 0.0, "top": e.b})
	var runs := []
	var n_burst := 0
	var worst3 := 0.0
	for f in flights:
		var foot: Vector3 = f.foot
		var top: Vector3 = f.top
		var dir := Vector3(top.x - foot.x, 0.0, top.z - foot.z).normalized().rotated(Vector3.UP, deg_to_rad(float(f.get("ang", 0.0))))
		var along := Vector3(top.x - foot.x, 0.0, top.z - foot.z).normalized()
		# from the landing, straight on and at 32 degrees (the flights have open sides: an angled run climbs a way and
		# drops off the side, so only climbing counts toward the 3D speed)
		var start := foot - along * (1.0 if f.kind == "stairs" else 1.8) + Vector3.UP * 0.3
		for g in [["run", false, Defs.move("run_speed")], ["sprint", true, Defs.move("sprint_speed")]]:
			var r := await _drive(start, dir, 2.2, g[1])
			var s := _stats(r, float(g[2]))
			var ys: Array = r.y
			var sp: Array = r.sp
			var top3 := 0.0
			for i in range(9, sp.size()):
				var d3 := 0.0
				for k in 6:
					var dy := maxf(float(ys[i - k]) - float(ys[i - k - 1]), 0.0) * 60.0   # climbing only
					d3 += sqrt(float(sp[i - k]) * float(sp[i - k]) + dy * dy)
				top3 = maxf(top3, d3 / 6.0)
			# the escalator's own belt adds up to its speed on top of the gait
			var cap3 := float(g[2]) * 1.2 + (0.75 if f.kind == "escalator" else 0.0)
			s["kind"] = f.kind
			s["gait"] = g[0]
			s["foot"] = str(foot.snapped(Vector3.ONE * 0.1))
			s["ang"] = float(f.get("ang", 0.0))
			s["top3d_0.1s"] = snappedf(top3, 0.01)
			s["climbed"] = snappedf(float(ys[-1]) - foot.y, 0.01)
			s["top_y"] = snappedf((ys as Array).max() - foot.y, 0.01)
			s["start"] = str(start.snapped(Vector3.ONE * 0.1))
			s["end"] = str(t.ch.global_position.snapped(Vector3.ONE * 0.1))
			runs.append(s)
			print("[bursts] mall %s %s %s: %s" % [f.kind, s.foot, g[0], str(s)])
			if int(s.bursts) > 0 or top3 > cap3:
				n_burst += 1
			worst3 = maxf(worst3, top3)
	measure["mall"] = runs
	t._check("bursts_mall", n_burst == 0, "%d mall runs up stairs and escalators, %d with bursts; worst 3D speed over 0.1 s %.1f m/s (run 4.4, sprint 6.3)" % [runs.size(), n_burst, worst3])
