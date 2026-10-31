extends RefCounted
## Getting out of the water (`--autotest=canal [--canal_only=channel,basin,estero] [--canal_step=20]`): the player is
## dropped into the water every few metres along the walled canal, its basin and the estero, faces the nearest bank
## (and, in the channel and the estero, the other bank too) and does what a player would: holds forward (no sprint,
## so a sprinting wall run-up does not hide a trap) and taps Jump, for up to 8 s. Out = standing on dry land. Spots
## under a bridge are skipped (the way out there is along the water). bots: bots dropped in the canal far from a
## ladder get out by themselves within 25 s. Every attempt goes to <shots>/canal_measure.json; the first few stuck
## spots are captured. `--canal_haul=off` turns the haul-out off (the 0.12 behaviour).
##   godot --path game -- --host --game_mode=deathmatch --bots=4 --autostart=1 --autotest=canal --shots=<dir>

var t = null
var world = null
var L = null
var measure := {"attempts": []}
var _stuck_shots := 0


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 40.0)
	await t._wait(1.0)
	L = world.map.layout
	world.map.lighting.forced_time = 450.0
	var ms = world.match_server
	if ms and not ms.zone.is_empty():
		ms.zone = {"i": 0, "state": "wait", "t0": Net.tick, "t1": Net.tick + 100000000, "c0": Vector2.ZERO, "r0": 9000.0, "c1": Vector2.ZERO,
			"r1": 9000.0, "dps": 0.0, "shrink_s": 60.0}
		ms._broadcast()
	for b in world.bots.values():
		b.test_idle = true
		b.ch.global_position = Vector3(150.0 + b.ch.eid, 1.5, -150.0)
	Parkour.water_grab_off = str(Game.arg("canal_haul", "on")) == "off"
	if Game.arg("canal_probe") != null:
		# --canal_probe=x,z,dx,dz: what is round the wall top the hands reach for from there (debugging a trapped spot).
		var v := str(Game.arg("canal_probe")).split_floats(",")
		await _probe(Vector3(v[0], L.terrain_height(v[0], v[1]) + 0.05, v[1]), Vector3(v[2], 0.0, v[3]).normalized())
		return
	var only := str(Game.arg("canal_only", "")).split(",", false)
	var step := float(Game.arg("canal_step", 20.0))
	var sets := {"channel": _channel(step), "basin": _basin(step * 0.6), "estero": _estero(step)}
	var res := {}
	for name in sets.keys():
		sets[name] = (sets[name] as Array).filter(func(s): return not _under_bridge(s.p))
	for name in ["channel", "basin", "estero"]:
		if not only.is_empty() and not (name in only):
			continue
		var out := 0
		var spots := 0
		var trapped := []
		for s in sets[name]:
			var any := false
			for d in s.dirs:
				var r: Dictionary = await _attempt(name, s.p, d)
				any = any or bool(r.out)
			spots += 1
			if any:
				out += 1
			else:
				trapped.append(str(Vector2(s.p.x, s.p.z).round()))
		res[name] = {"spots": spots, "out": out, "trapped": trapped}
		t._check("canal_out_" + name, spots > 0 and out == spots,
			"%s: got out at %d of %d spots (holding forward toward a bank, tapping Jump, 8 s)%s" % [name, out, spots,
			("; trapped at " + ", ".join(trapped.slice(0, 8))) if not trapped.is_empty() else ""])
	if only.is_empty() or "bots" in only:
		res["bots"] = await _bots()
	measure["summary"] = res
	var f := FileAccess.open(t.out_dir + "/canal_measure.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


func _channel(step: float) -> Array:
	## The walled channel (x -85..-71) from the play edge to the basin, both banks.
	var out := []
	var z: float = -L.edge + 8.0
	while z < -24.0:
		if absf(z) > 14.0:   # not under the Canal Bridge
			out.append({"p": Vector3(-78.0, 0.0, z), "dirs": [Vector3(-1, 0, 0), Vector3(1, 0, 0)]})
		z += step
	return out


func _basin(step: float) -> Array:
	## Two metres in from each edge of the basin (the walled water south of the bridge), facing that edge.
	var out := []
	var wp: Dictionary = L.water_polys[0]
	var pts: PackedVector2Array = wp.pts
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		if minf(a.y, b.y) < 14.0:   # the channel and the bridge: covered above
			continue
		var len := a.distance_to(b)
		var d := (b - a) / len
		var nrm := Vector2(-d.y, d.x)
		if not L._inside((a + b) * 0.5 + nrm * 0.5, pts):
			nrm = -nrm
		var k := step * 0.5
		while k < len:
			var q := a + d * k + nrm * 2.0
			out.append({"p": Vector3(q.x, 0.0, q.y), "dirs": [Vector3(-nrm.x, 0, -nrm.y)]})
			k += step
	return out


func _estero(step: float) -> Array:
	var out := []
	for e in L.esteros:
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var len := a.distance_to(b)
		var d := (b - a) / len
		var nrm := Vector2(-d.y, d.x)
		var k := 10.0
		while k < len - 4.0:
			var q := a + d * k
			if absf(q.x) < L.edge - 4.0 and absf(q.y) < L.edge - 4.0:
				out.append({"p": Vector3(q.x, 0.0, q.y), "dirs": [Vector3(nrm.x, 0, nrm.y), Vector3(-nrm.x, 0, -nrm.y)]})
			k += step
	return out


func _attempt(set_name: String, p: Vector3, dir: Vector3) -> Dictionary:
	for a in ["move_forward", "sprint", "jump"]:
		t._act_release(a)
	var start := Vector3(p.x, L.terrain_height(p.x, p.z) + 0.05, p.z)
	t._teleport(start, atan2(-dir.x, -dir.z))
	t.ch.health.reset()
	await t._wait(0.4)
	var depth0: float = t.ch.water_depth()
	t._act_press("move_forward")
	var out := false
	var secs := 0.0
	var moves := {}
	var jt := 0.0
	var yaw := atan2(-dir.x, -dir.z)
	while secs < 8.0:
		t.ctl.yaw = yaw   # keep facing the bank (a stray mouse on the test window turned the view)
		t.ctl.pitch = 0.0
		await t.get_tree().physics_frame
		secs += 1.0 / 60.0
		jt += 1.0 / 60.0
		if jt > 0.5:
			jt = 0.0
			t._act_press("jump")
		elif jt > 0.1:
			t._act_release("jump")
		if t.ch.ledge_t >= 0.0:
			moves.hang = true
		if t.ch.vault_t >= 0.0:
			moves.climb = true
		var q: Vector3 = t.ch.global_position
		if t.ch.is_on_floor() and t.ch.water_depth() < 0.02 and q.y > L.LAND_Y - 0.3 and t.ch.vault_t < 0.0 and t.ch.ledge_t < 0.0:
			out = true
			break
	for a in ["move_forward", "sprint", "jump"]:
		t._act_release(a)
	var end: Vector3 = t.ch.global_position
	var r := {"set": set_name, "p": [snappedf(p.x, 0.1), snappedf(p.z, 0.1)], "dir": [dir.x, dir.z], "depth": snappedf(depth0, 0.01), "out": out,
		"secs": snappedf(secs, 0.01), "end": [snappedf(end.x, 0.1), snappedf(end.y, 0.1), snappedf(end.z, 0.1)], "moves": moves.keys()}
	measure.attempts.append(r)
	print("[canal] %s %s toward %s: %s in %.1f s, depth %.2f, end %s %s" % [set_name, str(Vector2(p.x, p.z).round()), str(Vector2(dir.x, dir.z)),
		"OUT" if out else "stuck", secs, depth0, str(end.snapped(Vector3.ONE * 0.1)), str(moves.keys())])
	if not out and _stuck_shots < 4:
		_stuck_shots += 1
		await t._shot("stuck_%s_%d" % [set_name, _stuck_shots])
	return r


func _probe(p: Vector3, fwd: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for hh in [-0.5, 0.0, 0.5, 0.75, 1.0, 1.25, 1.6, 2.0, 2.2, 2.4, 2.5, 2.6, 2.8, 3.0]:
		var a: Vector3 = p + Vector3.UP * float(hh)
		var q := PhysicsRayQueryParameters3D.create(a, a + fwd * 3.0, Defs.MOVE_MASK)
		var h := space.intersect_ray(q)
		print("[probe] fwd ray at +%.2f: %s" % [hh, ("hit %s n %s dist %.2f %s" % [str((h.position as Vector3).snapped(Vector3.ONE * 0.01)), str((h.normal as Vector3).snapped(Vector3.ONE * 0.01)), a.distance_to(h.position), str(h.collider.name if h.collider else "?")]) if not h.is_empty() else "nothing"])
	for k in [1.5, 1.6, 1.7, 1.8, 2.0, 2.2, 2.5, 3.0, 3.5]:
		var b: Vector3 = p + fwd * float(k)
		var q2 := PhysicsRayQueryParameters3D.create(b + Vector3.UP * 4.0, b + Vector3.DOWN * 0.5, Defs.MOVE_MASK)
		var h2 := space.intersect_ray(q2)
		print("[probe] down ray %.1f m ahead: %s" % [k, ("hit y %.3f n %s %s" % [(h2.position as Vector3).y, str((h2.normal as Vector3).snapped(Vector3.ONE * 0.01)), str(h2.collider.name if h2.collider else "?")]) if not h2.is_empty() else "nothing"])
	# At the wall, as a player pressed against it stands: find_ledge's steps one by one.
	var q0 := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.3, p + Vector3.UP * 0.3 + fwd * 10.0, Defs.MOVE_MASK)
	var hw := space.intersect_ray(q0)
	if hw.is_empty():
		print("[probe] no wall ahead")
		return
	var r := Defs.move("radius")
	var pw: Vector3 = Vector3(hw.position.x, p.y, hw.position.z) - fwd * (r + 0.02)
	t.ch.global_position = pw
	await t._wait(0.2)
	print("[probe] at the wall %s: water depth %.2f, on floor %s, radius %.2f" % [str(pw.snapped(Vector3.ONE * 0.01)), t.ch.water_depth(), str(t.ch.is_on_floor()), r])
	var hm: float = Parkour.HAND_MAX + minf(t.ch.water_depth(), Parkour.WATER_REACH)
	var ex := [t.ch.get_rid()]
	var face := INF
	var n := Vector3.ZERO
	for hh in [Parkour.HAND_MIN - 0.2, 1.25, hm - 0.05, hm + 0.25]:
		var a: Vector3 = pw + Vector3.UP * float(hh)
		var q := PhysicsRayQueryParameters3D.create(a, a + fwd * (r + Parkour.GRAB_REACH), Defs.MOVE_MASK)
		q.exclude = ex
		var h := space.intersect_ray(q)
		print("[probe]  face ray +%.2f: %s" % [hh, str(h.get("position", "-"))])
		if h.is_empty() or absf((h.normal as Vector3).y) > 0.5:
			continue
		var hn := Vector3((h.normal as Vector3).x, 0.0, (h.normal as Vector3).z).normalized()
		var d := (Vector3(h.position.x, pw.y, h.position.z) - pw).dot(-hn)
		if d < face:
			face = d
			n = hn
	print("[probe]  face %.3f n %s" % [face, str(n)])
	if face == INF:
		return
	var into := -n
	var probe := pw + into * (face + 0.1)
	var qd := PhysicsRayQueryParameters3D.create(Vector3(probe.x, pw.y + hm + 0.5, probe.z), Vector3(probe.x, pw.y + Parkour.HAND_MIN - 0.15, probe.z), Defs.MOVE_MASK)
	qd.exclude = ex
	var hd := space.intersect_ray(qd)
	print("[probe]  top ray from %.2f to %.2f: %s" % [pw.y + hm + 0.5, pw.y + Parkour.HAND_MIN - 0.15, str(hd.get("position", "-"))])
	if hd.is_empty():
		return
	var top: float = (hd.position as Vector3).y
	print("[probe]  top %.3f rel %.3f (hand max %.2f)" % [top, top - pw.y, hm])
	for up in [0.12, 0.45]:
		var a2 := Vector3(pw.x, top + float(up), pw.z)
		var qa := PhysicsRayQueryParameters3D.create(a2, a2 + into * (face + 0.3), Defs.MOVE_MASK)
		qa.exclude = ex
		print("[probe]  above +%.2f: %s" % [up, str(space.intersect_ray(qa).get("position", "clear"))])
	var L2: Dictionary = Parkour.find_ledge(t.ch, pw, fwd, hm)
	print("[probe] find_ledge: %s" % str(L2))
	print("[probe] can_grab %s (held %d, pk_cd %.2f, mode %d), on wall %s, prev_buttons %d, ledge_t %.2f, vault_t %.2f" % [str(Parkour.can_grab(t.ch)), t.ch.held_prop_id, t.ch.pk_cd, t.ch.mode, str(t.ch.is_on_wall()), t.ch.prev_buttons, t.ch.ledge_t, t.ch.vault_t])
	t.ctl.yaw = atan2(-fwd.x, -fwd.z)
	t.ch.yaw = t.ctl.yaw
	var ok: bool = Parkour.water_grab(t.ch, {"my": 1.0, "mx": 0.0, "btn": Motor.B_JUMP}, t.ch.water_depth())
	print("[probe] water_grab with Jump: %s, ledge_t %.2f" % [str(ok), t.ch.ledge_t])
	t.ch.ledge_t = -1.0
	# Pushing into it for real: forward held for a second.
	t._act_press("move_forward")
	for i in 60:
		await t.get_tree().physics_frame
		t.ctl.yaw = atan2(-fwd.x, -fwd.z)
		if i % 10 == 0:
			print("[probe]  pushing %d: pos %s on wall %s water %.2f ledge_t %.2f vault_t %.2f yaw %.2f" % [i, str(t.ch.global_position.snapped(Vector3.ONE * 0.01)), str(t.ch.is_on_wall()), t.ch.water_depth(), t.ch.ledge_t, t.ch.vault_t, t.ch.yaw])
	t._act_release("move_forward")


func _under_bridge(p: Vector3) -> bool:
	for r in L.bridge_rects:
		if (r as Rect2).grow(1.5).has_point(Vector2(p.x, p.z)):
			return true
	return false


func _bots() -> Dictionary:
	## Bots dropped into the water at the middle of a basin wall and halfway between two channel ladders: out by
	## themselves (a ladder close by, else over the coping) within 25 s.
	var spots := [Vector3(-50.0, 0.0, 48.0), Vector3(-114.0, 0.0, 40.0), Vector3(-78.0, 0.0, -140.0), Vector3(-80.0, 0.0, -100.0)]
	var bots := []
	for b in world.bots.values():
		if is_instance_valid(b.ch) and b.ch.mode == Motor.GROUND:
			bots.append(b)
	var res := {"out": 0, "n": 0, "each": []}
	for i in mini(spots.size(), bots.size()):
		var b = bots[i]
		var p: Vector3 = spots[i]
		b.test_idle = false
		b.ch.global_position = Vector3(p.x, L.terrain_height(p.x, p.z) + 0.05, p.z)
		b.ch.velocity = Vector3.ZERO
		b.goal = Vector3.INF
		b.path = []
		b.state = "roam"
		res.n += 1
		var secs := 0.0
		var out := false
		var hung := false
		while secs < 25.0:
			await t.get_tree().physics_frame
			secs += 1.0 / 60.0
			if not is_instance_valid(b.ch):
				break
			hung = hung or b.ch.ledge_t >= 0.0
			if b.ch.is_on_floor() and b.ch.water_depth() < 0.02 and b.ch.global_position.y > L.LAND_Y - 0.3:
				out = true
				break
		if out:
			res.out += 1
		var e: Vector3 = b.ch.global_position if is_instance_valid(b.ch) else Vector3.ZERO
		res.each.append({"from": [p.x, p.z], "out": out, "secs": snappedf(secs, 0.1), "hauled": hung, "end": str(e.snapped(Vector3.ONE * 0.1))})
		print("[canal] bot from %s: %s in %.1f s (over the coping %s), end %s" % [str(Vector2(p.x, p.z)), "OUT" if out else "stuck", secs, str(hung), str(e.snapped(Vector3.ONE * 0.1))])
		b.test_idle = true
		b.ch.global_position = Vector3(150.0 + b.ch.eid, 1.5, -150.0)
	t._check("canal_out_bots", res.n > 0 and res.out == res.n, "bots dropped in the canal away from ladders: %d of %d out within 25 s %s" % [res.out, res.n, str(res.each.map(func(x): return "%s %.0f s%s" % ["out" if x.out else "STUCK", x.secs, " (coping)" if x.hauled else ""]))])
	return res
