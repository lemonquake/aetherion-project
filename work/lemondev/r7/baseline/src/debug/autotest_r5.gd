extends RefCounted
## --autotest=r5: measured checks for the 2026-10-28 r5 run.
##   godot --path game -- --host --bots=11 --autostart=1 --autotest=r5 --shots=<dir> --port=27515   [--r5_only=ragdoll]
##   [--r5_fast=1] skips the parachute deploy and drops the player straight on to the ground (iterating only).
##
## ragdoll: kills 36+ characters in varied places (open ground, slopes, river banks, ground-floor rooms, upper floors,
## stairs, against walls, crouched, downed, falling, running), waits for the bodies to settle and measures, for every
## ragdoll part and every vertex of the skinned body the player sees, how far it ends up inside the ground, floors,
## stair treads or walls; that the bodies stop and stay still; that the joints held; and that a client copy fed the
## server's pose stream ends up where the server's body is. Settled bodies are captured from a player's eye height.

const Corpse := preload("res://src/props/corpse.gd")

const SINK_MAX := 0.03       # PASS: nothing more than 3 cm under the surface beneath it
const STILL_MAX := 0.002     # PASS: no part or bone moves more than 2 mm in the 1.5 s after the body settled
const SURF := Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS

var t = null
var world = null
var log_lines: PackedStringArray = []
var _terrain_cache: Dictionary = {}
var _corpse_rids: Array = []
var _bot_turn := 0


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("r5_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	if Game.arg("r5_fast") != null:
		await _drop_in()
	else:
		await t._deploy()
	if not is_instance_valid(t.ch):
		return
	if want.call("ragdoll"):
		world.map.lighting.forced_time = 450.0
		await _ragdoll()
		world.map.lighting.forced_time = -1.0


func _drop_in() -> void:
	## Straight on to the ground near the plane's path (no freefall or canopy): for iterating on a section.
	await t._wait(1.0)
	var p := Vector3(40, 0, 40)
	world.server_set_mode(t.ch, Motor.GROUND)
	t._teleport(Vector3(p.x, world.map.ground_height(p.x, p.z) + 0.3, p.z), 0.0)
	await t._wait(1.0)


func _log(s: String) -> void:
	log_lines.append(s)
	print("[r5] " + s)


# ------------------------------------------------------------------ ragdoll

func _ragdoll() -> void:
	var scen := _scenarios()
	var kinds := {}
	for s in scen:
		kinds[s.kind] = int(kinds.get(s.kind, 0)) + 1
	_log("scenarios: %d %s" % [scen.size(), str(kinds)])
	var dyn = world.map.dyn
	var done: Array = []   # [scenario, corpse id, spawn msec]
	var real_kills := 0
	for s in scen:
		var bot = _pick_bot(s.get("real", false))
		if bot == null and s.get("real", false):
			s.real = false
			bot = _pick_bot(false)
		if bot == null:
			_log("no character left to kill for %s" % s.kind)
			continue
		var before: Array = dyn.corpses.keys()
		var keep_pos: Vector3 = bot.global_position
		var keep_mode: int = bot.mode
		bot.global_position = s.pos
		bot.yaw = s.yaw
		bot.velocity = s.vel
		bot.crouch = s.crouch
		if s.downed:
			bot.mode = Motor.DOWNED
		elif bot.mode != Motor.GROUND:
			bot.mode = Motor.GROUND
		if s.get("real", false) and keep_mode == Motor.GROUND:
			# The real path: lethal damage through the server, the bot is removed and its body spawned.
			for i in 2:
				if not world.characters.has(bot.eid):
					break
				var res: Dictionary = bot.health.apply_simple(9999.0, "test", "torso", t.ch.eid)
				world._after_damage(bot, res, t.ch.eid)
				if bot.mode == Motor.DOWNED and world.characters.has(bot.eid):
					# Squads go down first: lay them where the scenario says before the finishing hit.
					bot.global_position = s.pos
			real_kills += 1
		else:
			world.map.server_spawn_corpse(bot, s.impulse)
			bot.mode = keep_mode
			bot.crouch = 0.0
			bot.velocity = Vector3.ZERO
			bot.global_position = keep_pos
		var cid := -1
		for k in dyn.corpses.keys():
			if k not in before:
				cid = k
		if cid < 0:
			_log("no body for %s" % s.kind)
			continue
		var c = dyn.corpses[cid]
		s.spawn_pen = _part_depths(c).max
		done.append([s, cid, Time.get_ticks_msec()])
		await t.world.get_tree().physics_frame
	_corpse_rids.clear()
	for e in done:
		for rb in _parts(dyn.corpses[e[1]]):
			_corpse_rids.append(rb.get_rid())
	# Client copies of a few bodies, fed the pose stream the way a client receives it.
	var mirrors := {}
	for i in range(0, done.size(), maxi(done.size() / 6, 1)):
		var c = dyn.corpses[done[i][1]]
		var m := Corpse.new()
		dyn.root.add_child(m)
		m.setup_client(world, 900000 + int(done[i][1]), c.pname, c.team, c.pose())
		# On a real client the copy lives in another process; here its static parts must not touch the server's.
		for part in m.visuals:
			(m.visuals[part] as CollisionObject3D).collision_layer = 0
		mirrors[done[i][1]] = m
	# Wait for every body to settle, timing each.
	var settle := {}
	var feed_t := 0.0
	var t0 := Time.get_ticks_msec()
	while settle.size() < done.size() and Time.get_ticks_msec() - t0 < 9000:
		await t.world.get_tree().physics_frame
		feed_t += 1.0 / 60.0
		for e in done:
			var c = dyn.corpses[e[1]]
			if c.settled and not settle.has(e[1]):
				settle[e[1]] = (Time.get_ticks_msec() - int(e[2])) / 1000.0
				if mirrors.has(e[1]):
					mirrors[e[1]].client_pose(_xforms(c), true)
		if feed_t >= 1.0 / 12.0:
			feed_t = 0.0
			for id in mirrors:
				if not settle.has(id):
					mirrors[id].client_pose(_xforms(dyn.corpses[id]), false)
	await t._wait(0.5)
	var snap0 := {}
	for e in done:
		snap0[e[1]] = _points(dyn.corpses[e[1]])
	await t._wait(1.5)
	# Measure.
	var n_sink := 0
	var n_mesh := 0
	var n_move := 0
	var n_joint := 0
	var n_skinned := 0
	var n_unsettled := 0
	var worst_sink := 0.0
	var worst_mesh := 0.0
	var worst_move := 0.0
	var n_hover := 0
	var worst_hover := 0.0
	var times := []
	var by_kind := {}
	for e in done:
		var s: Dictionary = e[0]
		var c = dyn.corpses[e[1]]
		var st: float = settle.get(e[1], 99.0)
		times.append(st)
		if st > 4.0:
			n_unsettled += 1
		var pd := _part_depths(c)
		var below := _parts_below(c, s)
		var sink: float = maxf(pd.max, below.max)
		var mv := _moved(snap0[e[1]], _points(c))
		var md := _mesh_depths(c, s)
		var jd := _joint_gap(c)
		if md.has("n"):
			n_skinned += 1
			worst_hover = maxf(worst_hover, float(md.hover))
			if float(md.hover) > SINK_MAX:
				n_hover += 1
		if sink > SINK_MAX:
			n_sink += 1
		if float(md.get("max", 0.0)) > SINK_MAX:
			n_mesh += 1
		if mv > STILL_MAX:
			n_move += 1
		if jd > 0.03:
			n_joint += 1
		worst_sink = maxf(worst_sink, sink)
		worst_mesh = maxf(worst_mesh, float(md.get("max", 0.0)))
		worst_move = maxf(worst_move, mv)
		var k: String = s.kind
		if not by_kind.has(k):
			by_kind[k] = [0, 0.0]
		by_kind[k][0] += 1
		by_kind[k][1] = maxf(by_kind[k][1], maxf(sink, float(md.get("max", 0.0))))
		var pel: Vector3 = c.center()
		_log("body %d %-10s at %s: spawn overlap %.3f, settle %.2f s, part overlap %.3f (%s), below surface %.3f (%s), mesh %s, moved %.4f, joint gap %.3f, pelvis drop %.2f; fit: %s" % [e[1], s.kind,
			str((s.pos as Vector3).snapped(Vector3.ONE * 0.1)), float(s.spawn_pen), st, pd.max, pd.part, below.max, below.part, _fmt_mesh(md), mv, jd, float(s.floor_y) - pel.y, str(c.get("fit_note"))])
	var clients := []
	var client_err := 0.0
	for id in mirrors:
		var err := _mirror_error(dyn.corpses[id], mirrors[id])
		client_err = maxf(client_err, err)
		clients.append("%d: %.4f m" % [id, err])
	times.sort()
	var med: float = times[times.size() / 2] if not times.is_empty() else 99.0
	var kind_s := []
	for k in by_kind:
		kind_s.append("%s %d (worst %.3f)" % [k, by_kind[k][0], by_kind[k][1]])
	_log("by kind: " + ", ".join(kind_s))
	t._check("ragdoll_deaths", done.size() >= 30, "%d bodies (%d through the real kill path) in %d kinds of place" % [done.size(), real_kills, by_kind.size()])
	t._check("ragdoll_parts_above_surface", n_sink == 0, "%d of %d bodies have a ragdoll part > %.0f cm inside the surface under it or a wall; worst %.3f m" % [n_sink, done.size(), SINK_MAX * 100, worst_sink])
	t._check("ragdoll_mesh_above_surface", n_skinned > 0 and n_mesh == 0, "%d of %d skinned bodies have skin or clothing > %.0f cm under the ground, a floor or a stair tread; worst %.3f m" % [n_mesh, n_skinned, SINK_MAX * 100, worst_mesh])
	t._check("ragdoll_mesh_touches_ground", n_skinned > 0 and n_hover == 0, "%d of %d bodies float: lowest skin or clothing more than %.0f cm over the surface; worst %.3f m" % [n_hover, n_skinned, SINK_MAX * 100, worst_hover])
	# Most bodies come to rest in 2-3 s; one still rolling down a slope may take a little longer (none over 5 s).
	t._check("ragdoll_settles", med <= 3.0 and (times.is_empty() or times[-1] <= 5.0), "median settle %.2f s, slowest %.2f s, %d over 4 s" % [med, times[-1] if not times.is_empty() else 99.0, n_unsettled])
	t._check("ragdoll_still_after_settle", n_move == 0, "%d bodies moved more than %.0f mm in the 1.5 s after settling; worst %.4f m" % [n_move, STILL_MAX * 1000, worst_move])
	t._check("ragdoll_joints_hold", n_joint == 0, "%d bodies with a joint pulled apart > 3 cm" % n_joint)
	t._check("ragdoll_skinned_body", n_skinned == done.size(), "%d of %d bodies drawn as the character's own skinned, dressed body" % [n_skinned, done.size()])
	t._check("ragdoll_client_matches", not mirrors.is_empty() and client_err < 0.01, "client copies vs server: %s" % ", ".join(clients))
	await _ragdoll_shots(done)
	await _steps_shots(done)
	var f := FileAccess.open(t.out_dir + "/ragdoll.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))


func _fmt_mesh(md: Dictionary) -> String:
	if not md.has("n"):
		return "-"
	return "%.3f at %s (%d of %d verts deep; terrain %.3f, visual terrain %.3f, treads %.3f, in solids %d), lowest skin %.3f m over the surface" % [md.max, md.where, md.deep, md.n, md.terrain, md.vis_terrain, md.tread, md.solid, md.hover]


func _pick_bot(real: bool):
	## A living bot (on the ground when the kill is real), a different one each time so the bodies wear different
	## outfits.
	var cands := []
	for o in world.characters.values():
		if o == t.ch or not world.bots.has(o.eid):
			continue
		if real and o.mode != Motor.GROUND:
			continue
		if o.mode in [Motor.DEAD, Motor.SPECTATE]:
			continue
		cands.append(o)
	if cands.is_empty():
		return null
	_bot_turn += 1
	return cands[_bot_turn % cands.size()]


# ------------------------------------------------------------------ places

func _scenarios() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51505
	var m = world.map
	var half: float = m.layout.HALF
	var out := []
	var open := []
	var slopes := []
	var banks := []
	for i in 6000:
		if open.size() >= 9 and slopes.size() >= 4 and banks.size() >= 2:
			break
		var x := rng.randf_range(-half * 0.85, half * 0.85)
		var z := rng.randf_range(-half * 0.85, half * 0.85)
		var gy: float = m.ground_height(x, z)
		if m.water_height(x, z) > gy - 0.2:
			continue
		var surf := _surface_at(Vector3(x, gy + 40.0, z), 50.0)
		if surf.is_empty() or not _is_terrain(surf) or absf(float(surf.y) - gy) > 0.3:
			continue
		if not _clear_around(Vector3(x, float(surf.y), z), 2.5):
			continue
		var gx: float = m.ground_height(x + 1.0, z) - m.ground_height(x - 1.0, z)
		var gz: float = m.ground_height(x, z + 1.0) - m.ground_height(x, z - 1.0)
		var slope := Vector2(gx, gz).length() * 0.5
		var near_water := false
		for a in 8:
			var d := Vector2(cos(TAU * a / 8.0), sin(TAU * a / 8.0)) * 4.0
			if m.water_height(x + d.x, z + d.y) > -INF:
				near_water = true
		var p := Vector3(x, float(surf.y), z)
		if near_water and banks.size() < 2:
			banks.append(p)
		elif slope > 0.22 and slopes.size() < 4:
			# Face across or down the slope (the body falls downhill), alternately.
			var down := atan2(gx, gz)
			slopes.append([p, down if slopes.size() % 2 == 0 else down + PI * 0.5])
		elif slope < 0.1 and open.size() < 9:
			open.append(p)
	for i in open.size():
		var p: Vector3 = open[i]
		var s := _scen("open", p, rng.randf() * TAU, p.y)
		if i == 1 or i == 2:
			s.kind = "crouched"
			s.crouch = 1.0
		elif i == 3:
			s.kind = "downed"
			s.downed = true
		elif i == 4 or i == 5:
			s.kind = "running"
			s.vel = Basis(Vector3.UP, s.yaw) * Vector3(0, 0, -6.5)
		elif i == 6:
			s.kind = "falling"
			s.pos = p + Vector3.UP * 2.5
			s.vel = Vector3(0, -7.0, 0) + Basis(Vector3.UP, s.yaw) * Vector3(0, 0, -2.0)
		elif i == 7:
			s.real = true
		out.append(s)
	for sl in slopes:
		out.append(_scen("slope", sl[0], sl[1], (sl[0] as Vector3).y))
	for b in banks:
		out.append(_scen("bank", b, rng.randf() * TAU, (b as Vector3).y))
	# Rooms near the player first (the captures go there), then across the map.
	var ground_rooms := []
	var upper_rooms := []
	var rooms: Array = m.rooms.duplicate()
	var me: Vector3 = t.ch.global_position
	rooms.sort_custom(func(a, b): return (a.xf as Transform3D).origin.distance_squared_to(me) < (b.xf as Transform3D).origin.distance_squared_to(me))
	for r in rooms:
		if ground_rooms.size() >= 10 and upper_rooms.size() >= 5:
			break
		var sz: Vector2 = r.size
		if sz.x < 2.2 or sz.y < 2.2 or str(r.type) == "cr":
			continue
		var xf: Transform3D = r.xf
		var o := xf.origin
		var up_floor = o.y - m.ground_height(o.x, o.z) > 1.8
		if (up_floor and upper_rooms.size() >= 5) or (not up_floor and ground_rooms.size() >= 10):
			continue
		var spot := _free_floor(xf, sz)
		if spot == Vector3.INF:
			continue
		if up_floor:
			upper_rooms.append([spot, xf, sz])
		else:
			ground_rooms.append([spot, xf, sz])
	for i in ground_rooms.size():
		var g: Array = ground_rooms[i]
		var s := _scen("room", g[0], rng.randf() * TAU, (g[0] as Vector3).y)
		if i == 1:
			s.kind = "crouched"
			s.crouch = 1.0
		elif i == 2:
			s.kind = "downed"
			s.downed = true
		elif i == 3:
			s.kind = "running"
			s.vel = Basis(Vector3.UP, s.yaw) * Vector3(0, 0, -5.0)
		elif i == 4:
			s.real = true
		elif i >= 5:
			# Against the wall: back to the nearest wall, 0.3 m from it, shot toward it.
			var w := _wall_spot(g[0])
			if w.is_empty():
				continue
			s = _scen("wall", w.pos, w.yaw, (g[0] as Vector3).y)
			s.impulse = (w.normal as Vector3) * -4.0
			if i == 6:
				s.kind = "wall_downed"
				s.downed = true
			elif i == 7:
				s.kind = "wall_crouch"
				s.crouch = 1.0
		out.append(s)
	for i in upper_rooms.size():
		var u: Array = upper_rooms[i]
		var s := _scen("upper", u[0], rng.randf() * TAU, (u[0] as Vector3).y)
		if i == 1:
			s.kind = "upper_downed"
			s.downed = true
		out.append(s)
	# Stairs: half way up real flights, facing up or down them.
	var flights: Array = m.stairs
	var got := 0
	for k in 60:
		if got >= 5 or flights.is_empty():
			break
		var f: Dictionary = flights[(k * 37) % flights.size()]
		var dir: Vector3 = f.dir
		var foot: Vector3 = f.foot
		var top: Vector3 = f.top
		var run: float = (top - foot).dot(dir)
		var mid := foot + dir * (0.5 + (run - 0.5) * 0.5)
		var exp_y := foot.y + (top.y - foot.y) * 0.5
		var hit := _surface_at(Vector3(mid.x, exp_y + 0.6, mid.z), 1.2)
		if hit.is_empty() or absf(float(hit.y) - exp_y) > 0.35:
			continue
		var yaw := atan2(-dir.x, -dir.z) + (PI if got % 2 == 1 else 0.0)
		var s := _scen("stairs", Vector3(mid.x, float(hit.y), mid.z), yaw, float(hit.y))
		if got == 2:
			s.kind = "stairs_downed"
			s.downed = true
		elif got == 3:
			s.kind = "stairs_crouch"
			s.crouch = 1.0
		s.flight = f
		out.append(s)
		got += 1
	return out


func _scen(kind: String, pos: Vector3, yaw: float, floor_y: float) -> Dictionary:
	var imp := Basis(Vector3.UP, yaw) * Vector3(0, 0, 3.0)   # shot from the front: pushed backward
	return {"kind": kind, "pos": pos, "yaw": yaw, "floor_y": floor_y, "crouch": 0.0, "downed": false, "vel": Vector3.ZERO, "impulse": imp}


func _space() -> PhysicsDirectSpaceState3D:
	return world.get_world_3d().direct_space_state


func _is_terrain(hit: Dictionary) -> bool:
	var c = hit.get("collider")
	return c != null and c is Node and str(c.name) == "Terrain"


func _surface_at(from: Vector3, length: float) -> Dictionary:
	## First surface straight down from a point (world geometry, props, glass; never bodies), as {y, collider, rid}.
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length, SURF)
	q.hit_back_faces = false
	q.exclude = _corpse_rids
	var r := _space().intersect_ray(q)
	if r.is_empty():
		return {}
	return {"y": (r.position as Vector3).y, "collider": r.collider, "rid": r.rid, "normal": r.normal}


func _clear_around(p: Vector3, r: float) -> bool:
	for a in 8:
		var d := Vector3(cos(TAU * a / 8.0), 0, sin(TAU * a / 8.0))
		for h in [0.3, 1.0]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * h, p + Vector3.UP * h + d * r, SURF | Defs.PHYS_BLOCKER)
			if not _space().intersect_ray(q).is_empty():
				return false
	return true


func _free_floor(xf: Transform3D, sz: Vector2) -> Vector3:
	## A bare patch of floor in a room with standing room for a body (no furniture under or around it).
	for off in [Vector2(0, 0), Vector2(0.25, 0.2), Vector2(-0.25, -0.2), Vector2(0.3, -0.3), Vector2(-0.3, 0.3), Vector2(0.15, -0.35), Vector2(-0.15, 0.35)]:
		var p := xf * Vector3(off.x * sz.x, 0.0, off.y * sz.y)
		var hit := _surface_at(p + Vector3.UP * 1.0, 1.4)
		if hit.is_empty() or absf(float(hit.y) - p.y) > 0.12 or (hit.collider != null and hit.collider is RigidBody3D):
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.9, 1.5, 0.9)
		q.shape = b
		q.transform = Transform3D(xf.basis, Vector3(p.x, float(hit.y) + 0.85, p.z))
		q.collision_mask = SURF | Defs.PHYS_BLOCKER
		if _space().intersect_shape(q, 1).is_empty():
			return Vector3(p.x, float(hit.y), p.z)
	return Vector3.INF


func _wall_spot(p: Vector3) -> Dictionary:
	## The nearest wall from a spot in a room, and a place 0.3 m in front of it with the back to it.
	var best := {}
	for a in 8:
		var d := Vector3(cos(TAU * a / 8.0), 0, sin(TAU * a / 8.0))
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.UP * 1.0 + d * 3.0, Defs.PHYS_WORLD)
		var r := _space().intersect_ray(q)
		if r.is_empty() or absf((r.normal as Vector3).y) > 0.3:
			continue
		var dist := (r.position as Vector3).distance_to(p + Vector3.UP * 1.0)
		if best.is_empty() or dist < float(best.dist):
			best = {"dist": dist, "hit": r.position, "normal": r.normal}
	if best.is_empty():
		return {}
	var n: Vector3 = best.normal
	n.y = 0.0
	n = n.normalized()
	var spot := Vector3((best.hit as Vector3).x, p.y, (best.hit as Vector3).z) + n * 0.3
	var hit := _surface_at(spot + Vector3.UP * 1.0, 1.4)
	if hit.is_empty() or absf(float(hit.y) - p.y) > 0.12:
		return {}
	# Facing away from the wall (-Z forward), so the shot from the front throws the body back against it.
	return {"pos": Vector3(spot.x, float(hit.y), spot.z), "yaw": atan2(-n.x, -n.z), "normal": n}


# ------------------------------------------------------------------ measuring

func _parts(c) -> Array:
	var out := []
	var src: Dictionary = c.bodies if c.server else c.visuals
	for k in src:
		out.append(src[k])
	return out


func _xforms(c) -> Array:
	var out := []
	for part in c.ORDER:
		out.append((c.bodies[part] as Node3D).global_transform)
	return out


func _shapes(body: Node) -> Array:
	var out := []
	for cs in body.get_children():
		if cs is CollisionShape3D:
			out.append(cs)
	return out


func _part_depths(c) -> Dictionary:
	## Deepest overlap of any ragdoll part with world geometry (ground, floors, walls, furniture) from contact pairs.
	var worst := 0.0
	var worst_part := "-"
	for body in _parts(c):
		for cs in _shapes(body):
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cs.shape
			q.transform = cs.global_transform
			q.collision_mask = SURF
			q.exclude = _corpse_rids
			var pts := _space().collide_shape(q, 32)
			for i in range(0, pts.size() - 1, 2):
				var d: float = (pts[i] as Vector3).distance_to(pts[i + 1])
				if d > worst:
					worst = d
					worst_part = str(body.name)
	return {"max": worst, "part": worst_part}


func _low_points(cs: CollisionShape3D) -> Array:
	## The bottom of a part's shape: [centre, radius] of the capsule end caps (and its middle) or the box corners
	## within 5 cm of its lowest one (the top of an upright part is not "on" anything).
	var xf := cs.global_transform
	var sh = cs.shape
	var pts := []
	if sh is CapsuleShape3D:
		var hh: float = maxf(sh.height * 0.5 - sh.radius, 0.0)
		pts = [[xf * Vector3(0, hh, 0), sh.radius], [xf * Vector3(0, -hh, 0), sh.radius], [xf.origin, sh.radius]]
	elif sh is BoxShape3D:
		var e: Vector3 = sh.size * 0.5
		for sx in [-1, 1]:
			for sy in [-1, 1]:
				for sz in [-1, 1]:
					pts.append([xf * Vector3(e.x * sx, e.y * sy, e.z * sz), 0.0])
	elif sh is SphereShape3D:
		pts = [[xf.origin, sh.radius]]
	else:
		pts = [[xf.origin, 0.0]]
	var low := INF
	for q in pts:
		low = minf(low, (q[0] as Vector3).y - float(q[1]))
	return pts.filter(func(q): return (q[0] as Vector3).y - float(q[1]) <= low + 0.05)


func _parts_below(c, s: Dictionary) -> Dictionary:
	## How far the lowest point of each part is under the surface straight beneath it: the first surface found by a
	## ray from just above the part (started under any ceiling, furniture top or upper floor over it), the terrain
	## height field itself, and the visible stair treads (the collision of a flight is a ramp under them).
	var worst := 0.0
	var worst_part := "-"
	for body in _parts(c):
		for cs in _shapes(body):
			for lp in _low_points(cs):
				var p: Vector3 = lp[0]
				var bottom := p.y - float(lp[1])
				var d := _below_at(p, bottom, body)
				if d > worst:
					worst = d
					worst_part = str(body.name)
	return {"max": worst, "part": worst_part}


func _below_at(p: Vector3, bottom: float, body) -> float:
	var d := 0.0
	var start := p + Vector3.UP * 0.45
	var up := PhysicsRayQueryParameters3D.create(p, start, SURF)
	up.hit_back_faces = false
	up.exclude = _corpse_rids
	var u := _space().intersect_ray(up)
	if not u.is_empty():
		start = (u.position as Vector3) - Vector3.UP * 0.005
	var hit := _surface_at(start, 2.0)
	if not hit.is_empty():
		d = maxf(d, float(hit.y) - bottom)
	d = maxf(d, _terrain_y(p.x, p.z) - bottom)
	d = maxf(d, _tread_depth(Vector3(p.x, bottom, p.z)))
	return d


func _terrain_y(x: float, z: float) -> float:
	## The height field's own surface (through any floors or roofs above it), cached on a 5 cm grid.
	var key := Vector2i(floori(x * 20.0), floori(z * 20.0))
	if _terrain_cache.has(key):
		return _terrain_cache[key]
	var gy: float = world.map.ground_height(x, z)
	var from := Vector3(x, gy + 30.0, z)
	var excl: Array = _corpse_rids.duplicate()
	var y := -INF
	for i in 12:
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(x, gy - 30.0, z), Defs.PHYS_WORLD)
		q.exclude = excl
		q.hit_back_faces = false
		var r := _space().intersect_ray(q)
		if r.is_empty():
			break
		if r.collider is Node and str(r.collider.name) == "Terrain":
			y = (r.position as Vector3).y
			break
		excl.append(r.rid)
	_terrain_cache[key] = y
	return y


func _visual_terrain_y(x: float, z: float) -> float:
	## The drawn ground: the same 2 m height samples as the collision, split into triangles the way
	## map_builder._terrain indexes its chunks.
	var lay = world.map.layout
	var half: float = lay.HALF
	var fx := (x + half) / 2.0
	var fz := (z + half) / 2.0
	var ix := floori(fx)
	var iz := floori(fz)
	var u := fx - ix
	var v := fz - iz
	var x0 := -half + ix * 2.0
	var z0 := -half + iz * 2.0
	var h00: float = lay.ground_height(x0, z0)
	var h10: float = lay.ground_height(x0 + 2.0, z0)
	var h01: float = lay.ground_height(x0, z0 + 2.0)
	var h11: float = lay.ground_height(x0 + 2.0, z0 + 2.0)
	if u + v <= 1.0:
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	return h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)


func _tread_top(p: Vector3) -> float:
	## Top of the drawn stair tread under a point (no deeper than 0.35 m below it), or -INF.
	var d := _tread_depth(p + Vector3.DOWN * 0.34)
	return p.y - 0.34 + d if d > 0.0 else -INF


func _tread_depth(p: Vector3) -> float:
	## How far a point is under the top of a drawn stair tread (shanty._stair: treads of rise/steps over the run).
	var best := 0.0
	for f in world.map.stairs:
		var foot: Vector3 = f.foot
		if Vector2(foot.x - p.x, foot.z - p.z).length() > 6.0:
			continue
		var top: Vector3 = f.top
		var dir: Vector3 = f.dir
		var side := dir.cross(Vector3.UP).normalized()
		var sw: float = absf((top - foot).dot(side))
		var run: float = (top - foot).dot(dir) - 0.05
		var rise: float = top.y - foot.y
		if run <= 0.2 or rise <= 0.2 or sw < 0.3:
			continue
		var centre := foot + dir * 0.5
		var along := (p - centre).dot(dir)
		var across := absf((p - foot).dot(side))
		if along < 0.0 or along > run or across > sw * 0.5:
			continue
		var steps := int(ceil(rise / 0.21))
		var sd := run / steps
		# Each drawn tread is 4 cm deeper than its step (2 cm over each neighbour): the highest one over the point.
		var i := clampi(int((along + 0.02) / sd), 0, steps - 1)
		var tread := foot.y + rise / steps * (i + 1)
		var d := tread - p.y
		if d > 0.0 and d < 0.35:
			best = maxf(best, d)
	return best


func _mesh_depths(c, s: Dictionary) -> Dictionary:
	## Every 2nd vertex of the skinned body as the player sees it (the skeleton's current pose applied to the
	## outfit and head meshes): depth under the terrain (collision and drawn), under a stair tread, and inside
	## solid geometry by more than the threshold in every direction.
	var sk = c.get("skel")
	if sk == null or not is_instance_valid(sk):
		return {}
	var meshes: Array = []
	for mi in sk.get_children():
		if mi is MeshInstance3D and mi.visible and mi.mesh and mi.skin:
			meshes.append(mi)
	if meshes.is_empty():
		return {}
	var out := {"n": 0, "deep": 0, "max": 0.0, "terrain": 0.0, "vis_terrain": 0.0, "tread": 0.0, "solid": 0, "hover": 9.0}
	var all_pts := []
	var pq := PhysicsPointQueryParameters3D.new()
	pq.collision_mask = SURF
	pq.exclude = _corpse_rids
	var dirs := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	out.where = "-"
	for mi in meshes:
		var names := []
		var pts := _skinned(mi, sk, 2, names)
		for vi in pts.size():
			var p: Vector3 = pts[vi]
			all_pts.append(p)
			out.n += 1
			var tdep: float = _terrain_y(p.x, p.z) - p.y
			var vdep := _visual_terrain_y(p.x, p.z) - p.y
			# Only where the drawn ground is the surface (not under a floor built over it).
			if tdep > 0.5:
				tdep = 0.0
				vdep = 0.0
			var trd := _tread_depth(p)
			var solid := 0.0
			pq.position = p
			if not _space().intersect_point(pq, 1).is_empty():
				# Inside something: how far to the nearest way out (the first step that escapes in any direction).
				for r in [SINK_MAX, 0.06, 0.1, 0.16, 0.25]:
					var all_in := true
					for dv in dirs:
						pq.position = p + dv * r
						if _space().intersect_point(pq, 1).is_empty():
							all_in = false
							break
					if not all_in:
						break
					solid = r + 0.001
				if solid > 0.0:
					out.solid += 1
			out.terrain = maxf(out.terrain, tdep)
			out.vis_terrain = maxf(out.vis_terrain, vdep)
			out.tread = maxf(out.tread, trd)
			var d := maxf(maxf(tdep, vdep), maxf(trd, solid))
			if d > out.max:
				out.max = d
				out.where = names[vi]
			if d > SINK_MAX:
				out.deep += 1
	# Hovering: how high the lowest point of skin or clothing is over whatever is under it (the body should touch
	# the ground somewhere). Checked for the low points only.
	var low := INF
	for p in all_pts:
		low = minf(low, (p as Vector3).y)
	for p in all_pts:
		var v: Vector3 = p
		if v.y > low + 0.35:
			continue
		var q := PhysicsRayQueryParameters3D.create(v + Vector3.UP * 0.02, v + Vector3.DOWN * 1.0, SURF)
		q.hit_back_faces = false
		q.exclude = _corpse_rids
		var r := _space().intersect_ray(q)
		var under := -INF if r.is_empty() else (r.position as Vector3).y
		under = maxf(under, _terrain_y(v.x, v.z))
		under = maxf(under, _tread_top(v))
		if under > -INF:
			out.hover = minf(out.hover, maxf(v.y - under, 0.0))
	return out


func _skinned(mi: MeshInstance3D, sk: Skeleton3D, stride: int, names: Array = []) -> PackedVector3Array:
	## Vertex positions with the skeleton's current pose applied (as the GPU skins them), and in names the bone
	## that weighs most on each.
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var out := PackedVector3Array()
	if v.is_empty() or bo.is_empty():
		return out
	var nw := bo.size() / v.size()
	var skin: Skin = mi.skin
	var mats := []
	var sg := sk.global_transform
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = sk.find_bone(skin.get_bind_name(b))
		mats.append(sg * sk.get_bone_global_pose(maxi(bone, 0)) * skin.get_bind_pose(b))
	var bnames := []
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		bnames.append(skin.get_bind_name(b) if bone < 0 else sk.get_bone_name(bone))
	for i in range(0, v.size(), stride):
		var p := Vector3.ZERO
		var top := 0
		var tw := 0.0
		for k in nw:
			var ww := w[i * nw + k]
			if ww > 0.0:
				p += ((mats[bo[i * nw + k]] as Transform3D) * v[i]) * ww
				if ww > tw:
					tw = ww
					top = bo[i * nw + k]
		out.append(p)
		names.append(bnames[top])
	return out


func _points(c) -> Array:
	## Part origins and (when there is a skinned body) bone positions, for the stillness check.
	var out := []
	for body in _parts(c):
		out.append((body as Node3D).global_position)
	var sk = c.get("skel")
	if sk != null and is_instance_valid(sk):
		for i in sk.get_bone_count():
			out.append(sk.global_transform * sk.get_bone_global_pose(i).origin)
	return out


func _moved(a: Array, b: Array) -> float:
	var m := 0.0
	for i in mini(a.size(), b.size()):
		m = maxf(m, (a[i] as Vector3).distance_to(b[i]))
	return m


func _joint_gap(c) -> float:
	## How far apart the two halves of each joint have pulled (0 when the corpse does not report its joints).
	if not c.has_method("joint_gaps"):
		return 0.0
	var m := 0.0
	for g in c.joint_gaps():
		m = maxf(m, float(g))
	return m


func _mirror_error(c, mirror) -> float:
	var m := 0.0
	for part in c.ORDER:
		m = maxf(m, (c.bodies[part] as Node3D).global_position.distance_to((mirror.visuals[part] as Node3D).global_position))
	var a = c.get("skel")
	var b = mirror.get("skel")
	if a != null and b != null and is_instance_valid(a) and is_instance_valid(b):
		for i in a.get_bone_count():
			var pa: Vector3 = a.global_transform * a.get_bone_global_pose(i).origin
			var pb: Vector3 = b.global_transform * b.get_bone_global_pose(i).origin
			m = maxf(m, pa.distance_to(pb))
	return m


# ------------------------------------------------------------------ captures

func _steps_shots(done: Array) -> void:
	## The ragdoll-only treads (Dynamics.corpse_steps_near) drawn in translucent red over two real flights, then the
	## same view without them: the red tops must sit on the drawn treads.
	var dyn = world.map.dyn
	var n := 0
	for e in done:
		var s: Dictionary = e[0]
		if n >= 2 or not s.has("flight"):
			continue
		var idx: int = world.map.stairs.find(s.flight)
		var body = dyn._corpse_steps.get(idx)
		if body == null:
			continue
		n += 1
		var f: Dictionary = s.flight
		var foot: Vector3 = f.foot
		var top: Vector3 = f.top
		var dir: Vector3 = (f.dir as Vector3).normalized()
		var across := Vector3.UP.cross(dir).normalized()
		var side: float = signf((top - foot).dot(across))
		var run: float = (top - foot).dot(dir)
		var mid := foot + dir * (0.5 + run * 0.45)
		var overlay := Node3D.new()
		world.add_child(overlay)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 0.1, 0.1, 0.35)
		for cs in body.get_children():
			if cs is CollisionShape3D:
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = (cs.shape as BoxShape3D).size
				mi.mesh = bm
				mi.material_override = mat
				overlay.add_child(mi)
				mi.global_transform = cs.global_transform
		# From the foot of the flight, looking up it.
		var stand := foot - dir * 0.6
		var hit := _surface_at(stand + Vector3.UP * 1.0, 1.5)
		if not hit.is_empty():
			stand.y = float(hit.y)
		t._teleport(stand + Vector3.UP * 0.05, 0.0)
		await t._wait(0.5)
		t._look_at(mid + Vector3.UP * ((top.y - foot.y) * 0.45))
		await t._wait(0.3)
		await t._shot("steps_overlay_%d" % idx)
		overlay.queue_free()
		await t._wait(0.2)
		await t._shot("steps_plain_%d" % idx)

func _ragdoll_shots(done: Array) -> void:
	## Settled bodies from a player's eye height, about 2 m away with a clear view: one of each kind of place.
	var ch = t.ch
	if not is_instance_valid(ch):
		return
	if not ch.light.on:
		await t._tap("flashlight")
	var seen := {}
	var shots := 0
	for e in done:
		if shots >= 12:
			break
		var s: Dictionary = e[0]
		if seen.has(s.kind):
			continue
		var c = world.map.dyn.corpses.get(e[1])
		if c == null:
			continue
		var cc: Vector3 = c.center()
		var fy: float = s.floor_y
		var spot := Vector3.INF
		for k in 16:
			var a := TAU * k / 16.0 + 0.3
			var cand := Vector3(cc.x, fy, cc.z) + Vector3(cos(a), 0, sin(a)) * 1.9
			var hit := _surface_at(cand + Vector3.UP * 1.2, 1.8)
			if hit.is_empty() or absf(float(hit.y) - fy) > 0.45:
				continue
			cand.y = float(hit.y)
			var eye := cand + Vector3.UP * 1.6
			var q := PhysicsRayQueryParameters3D.create(eye, cc + Vector3.UP * 0.1, SURF)
			var q2 := PhysicsRayQueryParameters3D.create(cand + Vector3.UP * 0.9, Vector3(cc.x, cand.y + 0.9, cc.z), SURF)
			if _space().intersect_ray(q).is_empty() and _space().intersect_ray(q2).is_empty():
				spot = cand
				break
		if spot == Vector3.INF:
			continue
		seen[s.kind] = true
		ch.health.health = maxf(ch.health.health, 90.0)
		t._teleport(spot + Vector3.UP * 0.05, 0.0)
		await t._wait(0.5)
		t._look_at(cc + Vector3.DOWN * 0.15)
		await t._wait(0.3)
		await t._shot("ragdoll_%s_%d" % [s.kind, e[1]])
		shots += 1
