extends RefCounted
## r12 checks on a listen host (`--autotest=r12`, `--r12_only=bandage,accel,brake,turn,jump,fall,ledge,slide,sim,ab,
## fieldvis,field,fieldhouse`):
##   godot --path game -- --host --game_mode=deathmatch --bots=20 --autostart=1 --autotest=r12 --shots=<dir>
## Mechanics run on a test course floating 400 m up, 250 m south of the map centre (inside the edge the off-map
## failsafe watches; fixed wall heights, nothing else near). The numbers each check needs are in work/lemondev/r12/CONTRACT.md; every measurement also goes to
## <shots>/r12_measure.json. ab: the same scripted routes with the r11 motor (Motor.legacy) and the new one, filmed
## from the side, for the blind review. fieldvis: the boundary on the map, old haze and new field. field: the field
## carries the player in on open ground, crushes a dummy behind a wall, and a bot behind a wall gets round it.

var t = null
var world = null
const O := Vector3(0.0, 400.0, 250.0)   # course origin (floor top)
var measure := {}
var _side_cam: Camera3D
var _body_saved := []


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("r12_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 40.0)
	await t._wait(1.5)
	if not is_instance_valid(t.ch):
		t._check("r12_spawn", false, "no local character")
		return
	world.map.lighting.forced_time = 450.0
	for b in world.bots.values():
		b._dm_hold = 9999.0
	if world.match_server and not world.match_server.zone.is_empty():
		_freeze_zone()   # no closing circle, and no boundary wall in the course captures (old haze vs new field)
	if bool(Settings.get_value("controls", "crouch_toggle")):
		Settings.set_value("controls", "crouch_toggle", false)
	if want.call("bandage"):
		await _bandage()
		t.ch.health.reset()   # the bandaged leg is still hurt, and a hurt leg slows the run
		t.ch.health.dirty = true
		await _phys(5)
	await _build_course()
	var steps := {"accel": _accel, "brake": _brake, "turn": _turn, "jump": _jump, "fall": _fall, "ledge": _ledge, "slide": _slide,
		"sim": _sim, "ab": _ab}
	for n in steps:
		if want.call(n):
			await (steps[n] as Callable).call()
			_release_all()
			t.ch.health.reset()
			t.ch.health.dirty = true
	if want.call("fieldvis"):
		await _fieldvis()
	if want.call("field"):
		await _field()
	if want.call("fieldhouse"):
		await _fieldhouse()
	var f := FileAccess.open(t.out_dir + "/r12_measure.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


# ------------------------------------------------------------------ helpers

func _phys(n: int) -> void:
	for i in n:
		await t.get_tree().physics_frame


func _hs() -> float:
	return Vector2(t.ch.velocity.x, t.ch.velocity.z).length()


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch", "walk", "aim", "heal"]:
		t._act_release(a)


func _at(x: float, y: float, z: float) -> Vector3:
	return O + Vector3(x, y, z)


func _box(centre: Vector3, size: Vector3, col: Color) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = Defs.PHYS_WORLD
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	mi.material_override = m
	mi.layers = Defs.RENDER_WORLD
	sb.add_child(mi)
	world.add_child(sb)
	sb.global_position = centre


func _wall(x0: float, x1: float, z0: float, z1: float, h: float, col: Color) -> void:
	_box(_at((x0 + x1) * 0.5, h * 0.5, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), h, absf(z1 - z0)), col)


func _build_course() -> void:
	## Floor 80 x 80 m; walls facing +z (the player runs toward -z, yaw 0) at z = -10:
	## W1 x -17..-13, 2.2 m, 3 m deep; W2 x -3..3, 2.0 m, 0.25 m thick, open ground behind; W3 x 13..17, 3.0 m deep;
	## W4 x 28..32, 4.5 m. A 4.5 m block at x 27..33, z 22..28 (drop with and without a roll). Field: the crush
	## wall x -28..-22 and the long wall x 6..16 at z 1..2 (6 m and 3.5 m high).
	_box(O + Vector3(0, -0.5, 0), Vector3(80, 1, 80), Color(0.42, 0.42, 0.4))
	_wall(-17, -13, -10, -13, 2.2, Color(0.6, 0.55, 0.5))
	_wall(-3, 3, -10, -10.25, 2.0, Color(0.65, 0.6, 0.52))
	_wall(13, 17, -10, -13, 3.0, Color(0.55, 0.58, 0.62))
	_wall(28, 32, -10, -13, 4.5, Color(0.5, 0.5, 0.56))
	_wall(27, 33, 22, 28, 4.5, Color(0.58, 0.52, 0.46))
	_wall(-28, -22, 1, 2, 6.0, Color(0.45, 0.47, 0.5))
	_wall(6, 16, 1, 2, 3.5, Color(0.5, 0.45, 0.42))
	await _phys(2)


func _go(x: float, z: float, yaw: float = 0.0, y: float = 0.05) -> void:
	_release_all()
	await _phys(2)
	t._teleport(_at(x, y, z), yaw)
	await _phys(12)


# ------------------------------------------------------------------ C1 movement

func _accel() -> void:
	await _go(-30, 30)
	t._act_press("move_forward")
	t._act_press("sprint")
	var curve := []
	var s03 := 0.0
	var s14 := 0.0
	for i in 100:
		await _phys(1)
		if i % 3 == 0:
			curve.append(snappedf(_hs(), 0.01))
		if i == 18:
			s03 = _hs()
		if i == 84:
			s14 = _hs()
	measure["accel_curve_every_3_ticks"] = curve
	var sp := Defs.move("sprint_speed")
	t._check("r12_accel", s03 < sp * 0.7 and s14 >= sp * 0.95, "sprint from rest: %.2f m/s at 0.3 s (< %.2f), %.2f m/s at 1.4 s (>= %.2f)" % [s03, sp * 0.7, s14, sp * 0.95])


func _brake() -> void:
	await _go(-30, 30)
	t._act_press("move_forward")
	t._act_press("sprint")
	await _phys(120)
	var v0 := _hs()
	var p0: Vector3 = t.ch.global_position
	_release_all()
	var s015 := -1.0
	var stop_t := -1.0
	for i in 120:
		await _phys(1)
		if i == 9:
			s015 = _hs()
		if stop_t < 0.0 and _hs() < 0.2:
			stop_t = (i + 1) / 60.0
	var d := Vector2(t.ch.global_position.x - p0.x, t.ch.global_position.z - p0.z).length()
	measure["brake"] = {"from": v0, "at_0.15": s015, "stop_s": stop_t, "dist": d}
	t._check("r12_brake", s015 > 0.5 and stop_t > 0.0 and stop_t <= 1.1 and d >= 0.8 and d <= 3.5,
		"letting go at %.2f m/s: %.2f m/s after 0.15 s, stopped after %.2f s, %.2f m" % [v0, s015, stop_t, d])


func _turn() -> void:
	await _go(-30, 30)
	t._act_press("move_forward")
	t._act_press("sprint")
	await _phys(120)
	t.ctl.yaw -= PI * 0.5   # snap 90 degrees to the right
	await _phys(15)
	var fwd: Vector3 = -Basis(Vector3.UP, t.ctl.yaw).z
	var along: float = t.ch.velocity.dot(fwd)
	var sp := Defs.move("sprint_speed")
	# A gentle curve: 45 degrees a second for 2 s at a sprint.
	await _go(-30, 30)
	t._act_press("move_forward")
	t._act_press("sprint")
	await _phys(120)
	var low := INF
	for i in 120:
		t.ctl.yaw -= deg_to_rad(45.0) / 60.0
		await _phys(1)
		low = minf(low, _hs())
	measure["turn"] = {"snap90_along_after_0.25": along, "curve45_min_speed": low}
	t._check("r12_turn", along < sp * 0.6 and low >= sp * 0.9, "90 degree snap at a sprint: %.2f m/s along the new heading 0.25 s later (< %.2f); 45 deg/s curve keeps %.2f m/s (>= %.2f)" % [along, sp * 0.6, low, sp * 0.9])


func _hop(action: String) -> float:
	## A standing jump with the stick held; returns the distance along that way from take-off to landing.
	await _go(-30, 0)
	var p0: Vector3 = t.ch.global_position
	t._act_press(action)
	t._act_press("jump")
	await _phys(4)
	t._act_release("jump")
	await t._until(func(): return not t.ch.is_on_floor(), 1.0)
	await t._until(func(): return t.ch.is_on_floor(), 2.0)
	var p1: Vector3 = t.ch.global_position
	t._act_release(action)
	return (p0.z - p1.z) if action == "move_forward" else (p1.z - p0.z)


func _jump() -> void:
	var f := await _hop("move_forward")
	var b := await _hop("move_back")
	measure["jump_carry"] = {"forward": f, "back": b}
	t._check("r12_jump_carry", f >= 0.6 and b >= 0.4, "standing jump holding forward lands %.2f m ahead (>= 0.6), holding back %.2f m behind (>= 0.4)" % [f, b])


func _drop(h: float, roll: bool) -> float:
	await _go(5, 25, 0.0, h + 0.02)
	t.ch.health.reset()
	t.ch.health.dirty = true
	var h0: float = t.ch.health.health
	if roll:
		await _phys(4)
		t._act_press("crouch")
	await t._until(func(): return t.ch.is_on_floor(), 3.0)
	await _phys(50)
	t._act_release("crouch")
	await _phys(20)
	return h0 - float(t.ch.health.health)


func _fall() -> void:
	var r := {}
	for h in [2.5, 3.5, 6.0, 4.5]:
		r[str(h)] = await _drop(h, false)
	r["4.5_roll"] = await _drop(4.5, true)
	r["8.0"] = await _drop(8.0, false)
	r["8.0_roll"] = await _drop(8.0, true)
	measure["fall_damage"] = r
	t._check("r12_fall", float(r["2.5"]) == 0.0 and float(r["3.5"]) == 0.0 and float(r["6.0"]) < 30.0 and float(r["4.5_roll"]) < float(r["4.5"]) + 0.001 \
		and float(r["8.0_roll"]) < float(r["8.0"]), "damage by drop height: %s" % str(r))


# ------------------------------------------------------------------ C2 parkour

func _approach(x: float, sprint: bool, jump_at: float, start_z: float = -4.0) -> Dictionary:
	## Run (or sprint) at the wall face at z = -10, jump when the body is jump_at metres from it, keep pushing
	## forward. Returns {grabbed, grab_rel (edge above the feet), climbed_to (feet when done), t_grab, t_done}.
	await _go(x, start_z)
	t._act_press("move_forward")
	if sprint:
		t._act_press("sprint")
	var face := O.z - 10.0
	var reached: bool = await t._until(func(): return t.ch.global_position.z - face < jump_at + Defs.move("radius"), 4.0)
	if not reached:
		var c = t.ch
		print("[r12] approach at x %.0f never reached the wall: at %s, velocity %s, mode %d, forward held %s, paused %s, results %s, crouching %s, injury %.2f" % [x,
			str((c.global_position - O).snapped(Vector3.ONE * 0.01)), str(c.velocity.snapped(Vector3.ONE * 0.01)), c.mode, str(Input.is_action_pressed("move_forward")),
			str(t.ctl.paused), str(t.ctl.results), str(c.crouching), c.injury_speed])
	var jump_speed := _hs()
	t._act_press("jump")
	await _phys(5)
	t._act_release("jump")
	var out := {"grabbed": false, "t_grab": -1.0, "t_done": -1.0, "jump_speed": jump_speed, "reached": reached}
	var tt := 0.0
	var done_floor := 0
	while tt < 3.0:
		await _phys(1)
		tt += 1.0 / 60.0
		if t.ch.ledge_t >= 0.0 and not out.grabbed:
			out.grabbed = true
			out.t_grab = tt
			out.grab_feet_y = t.ch.global_position.y - O.y
		if out.grabbed and t.ch.ledge_t < 0.0 and t.ch.vault_t < 0.0 and t.ch.is_on_floor():
			done_floor += 1
			if done_floor > 6:
				out.t_done = tt
				break
		if not out.grabbed and tt > 1.5:
			break
	out.end = t.ch.global_position - O
	_release_all()
	return out


func _ledge() -> void:
	var w1 := await _approach(-15, false, 1.1)
	t._check("r12_ledge_2_2m", w1.grabbed and float(w1.t_done) > 0.0 and float(w1.t_done) - float(w1.t_grab) <= 1.5 and absf((w1.end as Vector3).y - 2.2) < 0.15,
		"2.2 m wall, run and jump: grabbed %s at %.2f s, on top after %.2f s more, feet at %s" % [w1.grabbed, w1.t_grab, float(w1.t_done) - float(w1.t_grab), str((w1.end as Vector3).snapped(Vector3.ONE * 0.01))])
	var w2 := await _approach(0, false, 1.1)
	var e2: Vector3 = w2.end
	t._check("r12_over_2m", w2.grabbed and e2.z < -10.4 and absf(e2.y) < 0.1, "2.0 m garden wall: grabbed %s, ended at %s (past z -10.25, on the ground)" % [w2.grabbed, str(e2.snapped(Vector3.ONE * 0.01))])
	var w3a := await _approach(15, false, 1.0)
	var w3b := await _approach(15, true, 0.55, -0.5)   # in front of the field test's long wall (z 1..2)
	t._check("r12_ledge_3m", not w3a.grabbed and w3b.grabbed and absf((w3b.end as Vector3).y - 3.0) < 0.15,
		"3.0 m wall: plain jump at %.1f m/s grabbed %s; sprint run-up at %.1f m/s grabbed %s, ended at %s" % [w3a.jump_speed, w3a.grabbed, w3b.jump_speed, w3b.grabbed, str((w3b.end as Vector3).snapped(Vector3.ONE * 0.01))])
	var w4 := await _approach(30, true, 0.55, 2.0)
	t._check("r12_ledge_4_5m", not w4.grabbed, "4.5 m wall, sprint run-up at %.1f m/s: grabbed %s" % [w4.jump_speed, w4.grabbed])
	measure["ledge"] = {"w1": w1, "w2": w2, "w3_plain": w3a, "w3_sprint": w3b, "w4": w4}


func _slide() -> void:
	await _go(-30, 30)
	t._act_press("move_forward")
	t._act_press("sprint")
	await _phys(110)
	var v0 := _hs()
	t._act_press("crouch")
	await _phys(2)
	var p0: Vector3 = t.ch.global_position
	var seen := false
	var low_h := 9.0
	var p1 := p0
	for i in 90:
		await _phys(1)
		if t.ch.slide_t >= 0.0:
			seen = true
			low_h = minf(low_h, t.ch.height())
			p1 = t.ch.global_position
	var d := Vector2(p1.x - p0.x, p1.z - p0.z).length()
	var crouched: bool = t.ch.crouching
	_release_all()
	measure["slide"] = {"from": v0, "dist": d, "height": low_h, "crouched_after": crouched}
	t._check("r12_slide", seen and d >= 2.0 and low_h < Defs.move("crouch_height") + 0.05 and crouched,
		"crouch at %.1f m/s: slid %s, %.2f m, body %.2f m tall, crouched after: %s" % [v0, seen, d, low_h, crouched])


# ------------------------------------------------------------------ movement simulation gate

func _sim() -> void:
	## 10,000 fixed 60 Hz steps of a second body under random input on the course: every state finite, no move
	## state stuck on. Counts the moves it made.
	var c2 := Character.new()
	c2.world = world
	c2.pid = 0
	c2.set_meta("climb_ok", true)
	world.add_child(c2)
	c2.global_position = _at(-15, 0.05, -5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1212
	var cmd := {"mx": 0.0, "my": 1.0, "yaw": 0.0, "pitch": 0.0, "btn": 0, "tick": Net.tick}
	var counts := {}
	var bad := ""
	var resets := 0
	var max_t := {"vault": 0.0, "ledge": 0.0, "slide": 0.0, "roll": 0.0}
	var starts := [Vector3(-15, 0.05, -5), Vector3(0, 0.05, -5), Vector3(15, 0.05, -4), Vector3(30, 0.05, -3), Vector3(30, 4.55, 25), Vector3(-30, 0.05, 20)]
	for step in 10000:
		if step % 30 == 0:
			cmd.mx = [-1.0, 0.0, 0.0, 1.0][rng.randi() % 4] * (1.0 if rng.randf() < 0.5 else 0.0)
			cmd.my = [1.0, 1.0, 0.0, -1.0][rng.randi() % 4]
			var b := 0
			if rng.randf() < 0.55:
				b |= Motor.B_SPRINT
			if rng.randf() < 0.12:
				b |= Motor.B_CROUCH
			if rng.randf() < 0.08:
				b |= Motor.B_WALK
			if rng.randf() < 0.08:
				b |= Motor.B_AIM
			cmd.btn = b
			if rng.randf() < 0.1:
				cmd.yaw = float(cmd.yaw) + rng.randf_range(-PI, PI)
		cmd.yaw = float(cmd.yaw) + rng.randf_range(-0.03, 0.03)
		if rng.randf() < 0.04:
			cmd.btn = int(cmd.btn) | Motor.B_JUMP
		elif rng.randf() < 0.3:
			cmd.btn = int(cmd.btn) & ~Motor.B_JUMP
		cmd.tick = Net.tick
		if step % 700 == 0 or c2.global_position.y < O.y - 15.0 or absf(c2.global_position.x - O.x) > 45.0 or absf(c2.global_position.z - O.z) > 45.0:
			if step > 0:
				resets += 1
			var s: Vector3 = starts[rng.randi() % starts.size()]
			c2.set_state({"pos": _at(s.x, s.y, s.z), "vel": Vector3.ZERO, "mode": Motor.GROUND, "crouch": 0.0, "crouching": false})
			cmd.yaw = 0.0
		c2.events.clear()
		Motor.step(c2, cmd, Defs.TICK_DT)
		for e in c2.events:
			counts[e[0]] = int(counts.get(e[0], 0)) + 1
		var p: Vector3 = c2.global_position
		var v: Vector3 = c2.velocity
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z) and is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
			bad = "non-finite state at step %d: %s %s" % [step, str(p), str(v)]
			break
		max_t.vault = maxf(max_t.vault, c2.vault_t)
		max_t.ledge = maxf(max_t.ledge, c2.ledge_t)
		max_t.slide = maxf(max_t.slide, c2.slide_t)
		max_t.roll = maxf(max_t.roll, c2.roll_t)
		if c2.vault_t > 3.0 or c2.ledge_t > Defs.move("hang_max_s") + 0.2 or c2.slide_t > Defs.move("slide_s") + 0.2 or c2.roll_t > Defs.move("roll_s") + 0.2:
			bad = "a move state stuck on at step %d: vault %.2f ledge %.2f slide %.2f roll %.2f" % [step, c2.vault_t, c2.ledge_t, c2.slide_t, c2.roll_t]
			break
		if step % 100 == 99:
			await t.get_tree().process_frame
	c2.queue_free()
	measure["sim"] = {"events": counts, "resets": resets, "max_t": max_t, "bad": bad}
	t._check("r12_sim_10k", bad == "", "10,000 random-input steps: %s; moves %s; resets %d; longest vault %.2f s, hang %.2f s, slide %.2f s, roll %.2f s" % [
		"all finite, nothing stuck" if bad == "" else bad, str(counts), resets, max_t.vault, max_t.ledge, max_t.slide, max_t.roll])


# ------------------------------------------------------------------ C6 bandage

func _bandage() -> void:
	var ch = t.ch
	ch.inv.add({"id": "bandage", "n": 3}, true)
	ch.health.reset()
	ch.health.apply_simple(40.0, "test", "leg_l")
	ch.health.dirty = true
	await _phys(10)
	var h0: float = ch.health.health
	var leg0: float = ch.health.parts.leg_l
	var n0: int = ch.inv.count("bandage")
	t.ctl.pitch = -0.15
	t._act_press("heal")
	await _phys(3)
	t._act_release("heal")
	var t0 := -1.0
	var t1 := -1.0
	var tt := 0.0
	var shot := false
	while tt < 4.0:
		await _phys(1)
		tt += 1.0 / 60.0
		var on: bool = (ch.flags & Character.F_HEAL) != 0
		if on and t0 < 0.0:
			t0 = tt
		if t0 >= 0.0 and not on and t1 < 0.0:
			t1 = tt
			break
		if on and not shot and tt - t0 > 1.0:
			shot = true
			await t._shot("bandage_fp")
	var dur := t1 - t0
	var h1: float = ch.health.health
	var leg1: float = ch.health.parts.leg_l
	measure["bandage"] = {"dur": dur, "health": [h0, h1], "leg_l": [leg0, leg1], "used": n0 - ch.inv.count("bandage")}
	t._check("r12_bandage", absf(dur - 2.0) <= 0.1 and h1 > h0 + 10.0 and leg1 > leg0 + 10.0 and n0 - ch.inv.count("bandage") == 1,
		"bandage took %.2f s (2.0 +- 0.1); health %.0f -> %.0f; left leg %.0f -> %.0f; bandages used %d" % [dur, h0, h1, leg0, leg1, n0 - ch.inv.count("bandage")])
	# Another player bandaging, seen from in front.
	var mate = null
	for b in world.bots.values():
		if b.ch.team == ch.team and b.ch.mode == Motor.GROUND:
			mate = b
			break
	if mate == null:
		return
	mate.test_idle = true
	var mc = mate.ch
	mc.inv.add({"id": "bandage", "n": 2}, true)
	mc.health.apply_simple(30.0, "test", "arm_l")
	world.interaction.start_treatment(mc, "bandage")
	var eye: Vector3 = mc.global_position + Vector3.UP * 1.35
	var fwd: Vector3 = -Basis(Vector3.UP, mc.yaw).z
	_side_camera(eye + fwd * 2.3 + Vector3.UP * 0.1, eye - Vector3.UP * 0.15)
	await _phys(50)
	await t._shot("bandage_tp")
	_end_side_camera()
	mate.test_idle = false


# ------------------------------------------------------------------ before/after captures (blind review)

func _side_camera(from: Vector3, look: Vector3) -> void:
	if _side_cam == null:
		_side_cam = Camera3D.new()
		_side_cam.fov = 60.0
		_side_cam.far = 1200.0
		_side_cam.cull_mask = Defs.RENDER_WORLD | Defs.RENDER_CHARACTERS | Defs.RENDER_INTERIOR | Defs.RENDER_INTERIOR_PROPS | Defs.RENDER_LOCAL_BODY
		world.add_child(_side_cam)
	_side_cam.global_position = from
	_side_cam.look_at(look, Vector3.UP)
	_side_cam.current = true
	# Own body: drawn for this camera (normally shadows only).
	_body_saved = []
	if t.ch.visual:
		for gi in t.ch.visual.find_children("*", "GeometryInstance3D", true, false):
			_body_saved.append([gi, gi.cast_shadow])
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _end_side_camera() -> void:
	for e in _body_saved:
		if is_instance_valid(e[0]):
			e[0].cast_shadow = e[1]
	_body_saved = []
	if t.ctl.cam:
		t.ctl.cam.current = true


func _grab_frame() -> Image:
	await RenderingServer.frame_post_draw
	var img = t.get_viewport().get_texture().get_image()
	img.resize(640, 360, Image.INTERPOLATE_BILINEAR)
	return img


func _save_strip(name: String, frames: Array) -> void:
	var cols := 3
	var rows := int(ceil(frames.size() / float(cols)))
	var strip := Image.create(640 * cols, 360 * rows, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var f: Image = frames[i]
		f.convert(Image.FORMAT_RGBA8)
		strip.blit_rect(f, Rect2i(0, 0, 640, 360), Vector2i((i % cols) * 640, (i / cols) * 360))
	var dir: String = t.out_dir + "/ab"
	DirAccess.make_dir_recursive_absolute(dir)
	strip.save_png("%s/%s.png" % [dir, name])
	print("[autotest] strip %s/%s.png" % [dir, name])


func _film(name: String, frame_ticks: Array, route: Callable) -> void:
	## Runs route (a coroutine taking the tick counter dictionary) while grabbing a frame at each listed tick. The
	## body's horizontal speed and height at each frame go to measure.ab_frames (for the reviewers, both builds alike).
	var frames := []
	var at := []
	var clock := {"tick": 0, "done": false}
	route.call(clock)
	var k := 0
	var guard := 0
	while k < frame_ticks.size() and guard < 600:
		await t.get_tree().physics_frame
		guard += 1
		clock.tick = int(clock.tick) + 1
		if int(clock.tick) >= int(frame_ticks[k]):
			at.append({"speed": snappedf(_hs(), 0.01), "feet_y": snappedf(t.ch.global_position.y - O.y, 0.01)})
			frames.append(await _grab_frame())
			k += 1
	_save_strip(name, frames)
	if not measure.has("ab_frames"):
		measure["ab_frames"] = {}
	measure.ab_frames[name] = at
	while not bool(clock.done) and guard < 900:
		await t.get_tree().physics_frame
		guard += 1


func _r_start_stop(clock: Dictionary) -> void:
	t._act_press("move_forward")
	t._act_press("sprint")
	while int(clock.tick) < 75:
		await t.get_tree().physics_frame
	_release_all()
	while int(clock.tick) < 150:
		await t.get_tree().physics_frame
	clock.done = true


func _r_turn(clock: Dictionary) -> void:
	t._act_press("move_forward")
	t._act_press("sprint")
	while int(clock.tick) < 90:
		await t.get_tree().physics_frame
	t.ctl.yaw -= PI * 0.5
	while int(clock.tick) < 160:
		await t.get_tree().physics_frame
	_release_all()
	clock.done = true


func _r_wall(clock: Dictionary) -> void:
	t._act_press("move_forward")
	var face := O.z - 10.0
	while t.ch.global_position.z - face > 1.1 + Defs.move("radius") and int(clock.tick) < 200:
		await t.get_tree().physics_frame
	t._act_press("jump")
	for i in 5:
		await t.get_tree().physics_frame
	t._act_release("jump")
	while int(clock.tick) < 200:
		await t.get_tree().physics_frame
	_release_all()
	clock.done = true


func _r_drop(clock: Dictionary) -> void:
	t._act_press("move_forward")
	t._act_press("walk")
	while t.ch.is_on_floor() and int(clock.tick) < 200:
		await t.get_tree().physics_frame
	t._act_press("crouch")
	while int(clock.tick) < 160:
		await t.get_tree().physics_frame
	_release_all()
	clock.done = true


func _ab() -> void:
	var legacy := preload("res://src/debug/legacy/motor_r11.gd")
	for mode in ["r11", "r12"]:
		Motor.legacy = legacy if mode == "r11" else null
		# Sprint start and stop, from the side.
		await _go(-30, 25)
		_side_camera(_at(-22.0, 1.6, 21.0), _at(-30.0, 0.9, 21.0))
		await _phys(6)
		await _film("start_stop_" + mode, [6, 24, 48, 80, 96, 130], _r_start_stop)
		# A hard turn at a sprint, from above and behind.
		await _go(-30, 30)
		_side_camera(_at(-34.0, 9.0, 30.0), _at(-27.0, 0.0, 18.0))
		await _phys(6)
		await _film("hard_turn_" + mode, [60, 90, 102, 114, 130, 158], _r_turn)
		# A run and jump at the 2.2 m wall, from the side, then the same in first person.
		await _go(-15, -7)
		_side_camera(_at(-9.0, 2.2, -8.5), _at(-15.0, 1.4, -9.5))
		await _phys(6)
		await _film("wall_side_" + mode, [25, 45, 58, 75, 95, 125], _r_wall)
		_end_side_camera()
		await _go(-15, -7)
		await _phys(6)
		await _film("wall_fp_" + mode, [25, 45, 58, 75, 95, 125], _r_wall)
		# Walking off a 4.5 m block with Crouch pressed in the air.
		await _go(30, 23.2, 0.0, 4.55)
		_side_camera(_at(37.0, 2.4, 19.5), _at(30.0, 1.2, 20.5))
		await _phys(6)
		await _film("drop_roll_" + mode, [15, 45, 70, 90, 100, 115], _r_drop)
		_end_side_camera()
	Motor.legacy = null
	t._check("r12_ab_captured", true, "before/after strips in %s/ab" % t.out_dir)


# ------------------------------------------------------------------ C4 forcefield

func _set_zone(c: Vector2, r0: float, r1: float, secs: float, state: String = "shrink") -> void:
	var ms = world.match_server
	ms.zone = {"i": 1, "state": state, "t0": Net.tick, "t1": Net.tick + int(secs * Defs.TICK_RATE), "c0": c, "r0": r0, "c1": c, "r1": r1,
		"dps": 0.0, "shrink_s": secs}
	ms._broadcast()


func _freeze_zone() -> void:
	var ms = world.match_server
	ms.zone = {"i": 0, "state": "wait", "t0": Net.tick, "t1": Net.tick + 100000000, "c0": Vector2.ZERO, "r0": 9000.0, "c1": Vector2.ZERO, "r1": 9000.0,
		"dps": 0.0, "shrink_s": 60.0}
	ms._broadcast()


func _fieldvis() -> void:
	## The boundary on the map, 14 m ahead of the player at the spawn, in daylight and at night; old haze and new field.
	var ms = world.match_server
	var spawn: Vector3 = ms.spawn_info.get(t.ch.team, {}).get("anchor", t.ch.global_position) if not ms.spawn_info.is_empty() else t.ch.global_position
	var p := Vector3(spawn.x, world.map.layout.surface_y(Vector2(spawn.x, spawn.z)) + 0.1, spawn.z)
	Field.test_only = [t.ch.eid]
	for legacy in [true, false]:
		Field.legacy_haze = legacy
		world.effects.refresh_zone_shader()
		var tag := "r11" if legacy else "r12"
		for when in [450.0, 150.0]:
			world.map.lighting.forced_time = when
			_release_all()
			t._teleport(p, 0.0)
			# Edge 14 m ahead (north): centre far to the south.
			_set_zone(Vector2(p.x, p.z + 286.0), 300.0, 300.0, 9999.0, "wait")
			t.ctl.pitch = 0.05
			await _phys(40)
			await t._shot("boundary_%s_%s" % [tag, "day" if when == 450.0 else "night"])
		# From inside it, looking back in.
		t._teleport(p + Vector3(0, 0, -17.0), PI)
		await _phys(20)
		await t._shot("boundary_inside_%s" % tag)
		if not legacy and Game.arg("r12_isolate") != null:   # debugging: the screen overlay alone, the wall alone
			world.effects._zone_wall.visible = false
			await _phys(3)
			await t._shot("inside_overlay_only")
			world.effects._zone_wall.visible = true
			world.hud.field_fx.material.set_shader_parameter("amount", 0.0)
			world.hud.field_fx.visible = false
			world.hud.set_process(false)
			await _phys(3)
			await t._shot("inside_wall_only")
			world.hud.set_process(true)
	Field.legacy_haze = false
	world.effects.refresh_zone_shader()
	world.map.lighting.forced_time = 450.0
	Field.test_only = []
	_freeze_zone()
	await _phys(5)
	t._check("r12_fieldvis_captured", true, "boundary captures taken")


func _field() -> void:
	## On the course: the edge 2 m behind, closing at 3 m/s. The player on open ground is carried in, unhurt; a bot
	## dummy behind a 6 m wall is crushed; a live bot behind the middle of a 10 m wall gets round its end.
	var ms = world.match_server
	var c := Vector2(O.x, 0.0)
	var dummy = null
	var runner = null
	for b in world.bots.values():
		if b.ch.mode != Motor.GROUND or b.ch.team != t.ch.team:
			continue
		if dummy == null:
			dummy = b
		elif runner == null:
			runner = b
	if dummy == null or runner == null:
		t._check("r12_field", false, "need two bots")
		return
	dummy.test_idle = true
	var dummy_health = dummy.ch.health   # RefCounted: still readable after the body is freed
	runner._dm_hold = 0.0
	Field.test_only = [t.ch.eid, dummy.ch.eid, runner.ch.eid]
	await _go(5, 4)
	dummy.ch.global_position = _at(-25, 0.05, 4)
	dummy.ch.velocity = Vector3.ZERO
	runner.ch.global_position = _at(11, 0.05, 4)
	runner.ch.velocity = Vector3.ZERO
	runner.goal = Vector3.INF
	t.ch.health.reset()
	var h0: float = t.ch.health.health
	await _phys(3)
	_set_zone(c, O.z + 6.0, O.z - 54.0, 20.0)
	var max_pen := -INF
	var p_start: Vector3 = t.ch.global_position
	var frames := []
	var dummy_dead_t := -1.0
	for i in 300:
		await _phys(1)
		var fi := Field.at(world, t.ch.global_position, float(Net.tick))
		max_pen = maxf(max_pen, float(fi.pen))
		if i in [60, 120, 200]:
			frames.append(await _grab_frame())
		if dummy_dead_t < 0.0 and (not is_instance_valid(dummy.ch) or dummy.ch.mode == Motor.DEAD or dummy.ch.health.dead):
			dummy_dead_t = (i + 1) / 60.0
	var moved: float = p_start.z - t.ch.global_position.z
	var edge_moved := 3.0 * 5.0
	var alive: bool = t.ch.mode == Motor.GROUND and not t.ch.health.dead
	var runner_ok: bool = is_instance_valid(runner.ch) and runner.ch.mode == Motor.GROUND and not runner.ch.health.dead
	var rp: Vector3 = runner.ch.global_position - O if is_instance_valid(runner.ch) else Vector3.ZERO
	var dummy_cause: String = str(dummy_health.last_cause)
	measure["field"] = {"max_pen": max_pen, "moved": moved, "edge_moved": edge_moved, "health": [h0, t.ch.health.health], "dummy_dead_t": dummy_dead_t,
		"dummy_cause": dummy_cause, "runner_alive": runner_ok, "runner_end": rp}
	_save_strip("field_push_fp", frames)
	t._check("r12_field_push", alive and float(t.ch.health.health) >= h0 and max_pen < 0.6 and moved >= edge_moved - 4.0,
		"open ground, edge closing at 3 m/s for 5 s: alive %s, health %.0f -> %.0f, deepest %.2f m inside it, carried %.1f m in (edge %.1f m minus the 2 m start gap)" % [alive, h0, t.ch.health.health, max_pen, moved, edge_moved])
	t._check("r12_field_crush", dummy_dead_t > 0.0 and dummy_cause == "field", "dummy behind a 6 m wall: dead after %.2f s, cause %s" % [dummy_dead_t, dummy_cause])
	# Out of the field's way: round an end of the wall (x 6..16), or over it with the hands on the top (r13: the parkour
	# climb counts; the wall is 3.5 m, within a sprint run-up's reach).
	var how := "round its end" if absf(rp.x - 11.0) > 5.0 else ("over it" if rp.z < 1.0 else "still behind it")
	t._check("r12_field_bot_escapes", runner_ok and how != "still behind it", "bot behind the middle of a 10 m wall: alive %s, ended at %s (%s)" % [runner_ok, str(rp.snapped(Vector3.ONE * 0.1)), how])
	Field.test_only = []
	_freeze_zone()


func _fieldhouse() -> void:
	## C5: a bot standing in the middle of a house on the map, with no door remembered, as the field comes (8 s of
	## warning, then the edge closing at about 3 m/s from 18 m away). It must be out of the building before the edge
	## reaches it, and alive. Four houses near the team's spawn (or house ids from --r12_houses=16,2), the field coming
	## from behind the house and from the side its door is on in turn. A failure prints the bot's trace.
	var BB := preload("res://src/ai/bot_brain.gd")
	var bot = null
	for b in world.bots.values():
		if b.ch.mode == Motor.GROUND and b.ch.team == t.ch.team:
			bot = b
			break
	if bot == null:
		t._check("r12_fieldhouse", false, "no bot")
		return
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var ms0 = world.match_server
	var anchor: Vector3 = ms0.spawn_info.get(t.ch.team, {}).get("anchor", Vector3.ZERO) if not ms0.spawn_info.is_empty() else Vector3.ZERO
	var only_ids := []
	for s in str(Game.arg("r12_houses", "")).split(",", false):
		only_ids.append(int(s))
	var picks := []
	for bd in world.map.buildings:
		var doors: Array = BB.doors_by_bid.get(bd.id, [])
		if doors.is_empty():
			continue
		var o: Vector3 = (bd.xf as Transform3D).origin
		var dist := Vector2(o.x - anchor.x, o.z - anchor.z).length()
		if not only_ids.is_empty():
			if not (int(bd.id) in only_ids):
				continue
		elif dist < 25.0 or dist > 160.0:
			continue
		var door: Dictionary = doors[0]
		var dc: Vector3 = (door.xf as Transform3D) * Vector3(float(door.w) * 0.5, 0.0, 0.0)
		var p := Vector3(o.x, dc.y + 0.05, o.z)
		if world.map.acoustics.zone_at(p + Vector3.UP * 0.5) == 0 or Vector2(p.x - dc.x, p.z - dc.z).length() < 3.0:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.7
		q.shape = cap
		q.transform = Transform3D(Basis(), p + Vector3.UP * 0.92)
		q.collision_mask = Defs.MOVE_MASK
		if not space.intersect_shape(q, 1).is_empty():
			continue
		var out: Vector3 = door.outward
		out.y = 0.0
		picks.append({"p": p, "out": out.normalized(), "bid": int(bd.id)})
		if picks.size() >= 4:
			break
	if picks.is_empty():
		t._check("r12_fieldhouse", false, "no house with a clear middle near the spawn")
		return
	var res := []
	var ok := true
	for k in picks.size():
		var pk: Dictionary = picks[k]
		var p: Vector3 = pk.p
		var side := 1.0 if k % 2 == 0 else -1.0   # even: centre beyond the door (field from behind); odd: field on the door side
		if Game.arg("r12_side") != null:
			side = -1.0 if str(Game.arg("r12_side")) == "door" else 1.0
		bot.ch.global_position = p
		bot.ch.velocity = Vector3.ZERO
		bot.ch.health.reset()
		bot._house_exit = []
		bot._house_exit_door = -1
		bot.plan = []
		bot.state = "roam"
		bot.goal = Vector3.INF
		bot.target_eid = -1
		Field.test_only = [bot.ch.eid]
		var c3: Vector3 = p + (pk.out as Vector3) * 90.0 * side
		var ms = world.match_server
		ms.zone = {"i": 1, "state": "wait", "t0": Net.tick, "t1": Net.tick + int(8.0 * Defs.TICK_RATE), "c0": Vector2(c3.x, c3.z), "r0": 108.0,
			"c1": Vector2(c3.x, c3.z), "r1": 30.0, "dps": 0.0, "shrink_s": 25.0}
		ms._broadcast()
		var out_t := -1.0
		var out_pen := 0.0
		var tt := 0.0
		var dead := false
		var trace := []
		while tt < 22.0:
			await _phys(6)
			tt += 0.1
			if not is_instance_valid(bot.ch) or bot.ch.mode == Motor.DEAD or bot.ch.health.dead:
				dead = true
				break
			if int(round(tt * 10.0)) % 5 == 0:
				var stp: Dictionary = bot.plan[bot.plan_i] if bot.plan_i < bot.plan.size() else {}
				trace.append("%.1f %s step %d/%d -> %s at %s in %s exit %d stuck %.1f field %.1f" % [tt, bot.state, bot.plan_i, bot.plan.size(),
					str((stp.get("p", bot.goal) as Vector3).round()) if not stp.is_empty() or bot.goal != Vector3.INF else "-",
					str(bot.ch.global_position.round()), str(world.map.acoustics.zone_at(bot.ch.global_position + Vector3.UP * 0.5) != 0),
					bot._house_exit.size(), bot._stuck_t, float(Field.at(world, bot.ch.global_position, float(Net.tick)).pen)])
			if out_t < 0.0 and world.map.acoustics.zone_at(bot.ch.global_position + Vector3.UP * 0.5) == 0:
				out_t = tt
				out_pen = float(Field.at(world, bot.ch.global_position, float(Net.tick)).pen)
		var good := not dead and out_t >= 0.0 and out_pen < 0.0
		ok = ok and good
		if not good:
			print("[r12] fieldhouse failed in house %d at %s, door facing %s:
  %s" % [int(pk.bid), str(p.round()), str((pk.out as Vector3).snapped(Vector3.ONE * 0.01)), "
  ".join(trace)])
			var probe = null
			for b3 in world.bots.values():
				if is_instance_valid(b3.ch):
					probe = b3
					break
			if probe != null:
				for dw in probe._house_doorways(int(pk.bid)):
					var c: Vector3 = dw.c
					print("  doorway at %s n %s door %d; walk from the start clear %s" % [str(c.snapped(Vector3.ONE * 0.1)), str((dw.n as Vector3).snapped(Vector3.ONE * 0.01)), int(dw.door),
						str(probe._walk_clear(p, c + (dw.n as Vector3) * 0.6)) + "/" + str(probe._walk_clear(p, c - (dw.n as Vector3) * 0.6))])
		res.append("house %d, %s: out after %s s (%.1f m from the edge), %s" % [int(pk.bid), "field from behind" if side > 0.0 else "field on the door side",
			("%.1f" % out_t) if out_t >= 0.0 else "never", -out_pen, "crushed" if dead else "alive"])
		measure["fieldhouse_%d" % k] = {"house": pk.bid, "p": p, "out_t": out_t, "out_pen": out_pen, "dead": dead}
		Field.test_only = []
		_freeze_zone()
		if dead:
			var my_team: int = t.ch.team if is_instance_valid(t.ch) else 0
			for b2 in world.bots.values():   # the next house needs a live bot
				if b2 != bot and b2.ch != null and is_instance_valid(b2.ch) and b2.ch.mode == Motor.GROUND and b2.ch.team == my_team:
					bot = b2
					break
		await _phys(30)
	t._check("r12_fieldhouse", ok, "bot in the middle of a house, no door remembered, field coming: " + "; ".join(res))
