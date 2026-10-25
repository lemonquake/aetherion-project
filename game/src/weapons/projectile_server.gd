extends RefCounted
## Authoritative projectile simulation (server only).
##
## Hit registration model ("shooter's view, server flight"): a shot is created at the muzzle position and direction
## the shooter's command carried. It then flies under gravity and drag on the server, one tick at a time, and is
## tested against world geometry at the current time and against characters as the shooter saw them: each
## character's recorded state at (view_tick + flight ticks), where view_tick is the tick the shooter was rendering
## when they fired (clamped to max_rewind). This favours the shooter by at most max_rewind seconds and never lets a
## bullet hit someone the shooter could not have seen at that moment.

const HitZones := preload("res://src/player/hitzones.gd")

var world = null
var space: PhysicsDirectSpaceState3D
var list: Array = []
var _next_id := 1
var stats := {"spawned": 0, "world_hits": 0, "char_hits": 0, "penetrations": 0, "ricochets": 0, "expired": 0}


func _init(w) -> void:
	world = w


func spawn(shooter, shot: Dictionary, view_tick: int, tick: int) -> int:
	var ammo_id := str(shot.ammo)
	var ammo := Defs.ammo(ammo_id)
	var v0 := float(shot.velocity)
	var mass := float(ammo.get("mass", 0.008))
	var e0 := Ballistics.energy(mass, v0)
	var pellets := int(shot.get("pellets", 1))
	var spread := float(ammo.get("spread_deg", 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(shot.seed)
	var id := _next_id
	_next_id += 1
	var max_rewind := int(float(Defs.rule("net.max_rewind_s", 0.3)) * Defs.TICK_RATE)
	view_tick = clampi(view_tick, tick - max_rewind, tick)
	for i in pellets:
		var dir: Vector3 = shot.dir
		if pellets > 1:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * spread * 0.5
			var side := dir.cross(Vector3.UP)
			if side.length_squared() < 1e-6:
				side = Vector3.RIGHT
			side = side.normalized()
			var up := side.cross(dir).normalized()
			dir = (dir + (side * cos(a) + up * sin(a)) * tan(deg_to_rad(r))).normalized()
		list.append({
			"id": id, "pellet": i, "shooter": shooter.eid if shooter else -1, "pos": shot.origin, "vel": dir * v0,
			"mass": mass, "k": float(ammo.get("drag_k", 0.001)), "ammo": ammo_id, "e0": e0, "pen": float(ammo.get("armor_pen", 1.0)),
			"view_tick": view_tick, "age": 0, "dist": 0.0, "ricochets": 0, "seed": int(shot.seed) + i * 7919,
			"flyby": {}, "ignore_eid": shooter.eid if shooter else -1,
		})
		stats.spawned += 1
	return id


func step(dt: float, tick: int) -> void:
	if list.is_empty():
		return
	space = world.get_world_3d().direct_space_state
	var max_t := float(Defs.ballistics.get("max_lifetime_s", 4.0))
	var max_d := float(Defs.ballistics.get("max_distance_m", 1600.0))
	var min_v := float(Defs.ballistics.get("min_lethal_speed", 60.0))
	for i in range(list.size() - 1, -1, -1):
		var p: Dictionary = list[i]
		var alive := _advance(p, dt, tick)
		p.age += 1
		if not alive or p.age * dt > max_t or p.dist > max_d or (p.vel as Vector3).length() < min_v:
			if alive:
				stats.expired += 1
			list.remove_at(i)


func _advance(p: Dictionary, dt: float, tick: int) -> bool:
	var r := Ballistics.integrate(p.pos, p.vel, p.k, dt, int(Defs.ballistics.get("sim_substeps", 2)))
	var to: Vector3 = r[0]
	var new_vel: Vector3 = r[1]
	var from: Vector3 = p.pos
	# Up to 4 interactions (penetrations / ricochets) inside one tick's segment.
	for guard in 4:
		var seg := to - from
		var seg_len := seg.length()
		if seg_len < 1e-5:
			break
		var dir := seg / seg_len
		# Water surface: bullets stop within a metre or so.
		var ws: float = world.water_height(to.x, to.z)
		if ws != -INF and to.y < ws and from.y >= ws - 0.05:
			var f := (from.y - ws) / maxf(from.y - to.y, 1e-5)
			var hit_w := from.lerp(to, clampf(f, 0.0, 1.0))
			world.server_impact(hit_w, Vector3.UP, "water", "splash", p.shooter, p.id)
			return false
		var wq := PhysicsRayQueryParameters3D.create(from, to, Defs.SHOT_MASK)
		var wh := space.intersect_ray(wq)
		var world_t := INF
		if not wh.is_empty():
			world_t = from.distance_to(wh.position) / seg_len
		var ch_hit := _test_characters(p, from, to, tick)
		if not ch_hit.is_empty() and float(ch_hit.t) < world_t:
			_flybys(p, from, from.lerp(to, ch_hit.t))
			var res: Dictionary = world.server_projectile_hit_character(ch_hit.ch, ch_hit.part, p, dir, ch_hit.pos, ch_hit.normal)
			stats.char_hits += 1
			var e_left: float = res.get("energy_left", 0.0)
			if e_left <= 1.0:
				return false
			p.ignore_eid = ch_hit.ch.eid
			from = ch_hit.pos + dir * 0.45
			new_vel = dir * Ballistics.speed_for_energy(p.mass, e_left)
			p.vel = new_vel
			continue
		if wh.is_empty():
			_flybys(p, from, to)
			p.dist += seg_len
			p.pos = to
			p.vel = new_vel
			return true
		_flybys(p, from, wh.position)
		stats.world_hits += 1
		var hit_pos: Vector3 = wh.position
		var normal: Vector3 = wh.normal
		var col = wh.collider
		var mat_id := "default"
		if col and col.has_meta("mat"):
			mat_id = str(col.get_meta("mat"))
		var mat := Defs.material(mat_id)
		var speed := new_vel.length()
		var e := Ballistics.energy(p.mass, speed)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(p.seed) + guard * 31 + int(p.age) * 131
		# Glass shatters and barely slows the round.
		if mat_id == "glass":
			world.server_glass_hit(col, hit_pos, dir, e)
			from = hit_pos + dir * 0.05
			new_vel *= 0.92
			p.vel = new_vel
			to = from + new_vel.normalized() * maxf(seg_len * (1.0 - from.distance_to(wh.position) / seg_len), 0.1)
			continue
		if col and col.has_meta("prop_id"):
			world.server_prop_hit(int(col.get_meta("prop_id")), hit_pos, dir, e, p.mass * speed)
		if col and col.has_meta("corpse_id"):
			world.server_corpse_hit(int(col.get_meta("corpse_id")), hit_pos, dir, normal)
		# Ricochet: shallow angles off hard surfaces, at most one per projectile.
		var grazing := 90.0 - rad_to_deg(acos(clampf(-dir.dot(normal), -1.0, 1.0)))
		var ric_deg := float(mat.get("ricochet_deg", 0.0))
		if p.ricochets < 1 and grazing < ric_deg and rng.randf() < float(mat.get("ricochet_chance", 0.0)) * (1.0 - grazing / maxf(ric_deg, 0.01)):
			p.ricochets += 1
			stats.ricochets += 1
			var out_dir := dir.bounce(normal).normalized()
			out_dir = (out_dir + Vector3(rng.randf_range(-1, 1), rng.randf_range(0, 1), rng.randf_range(-1, 1)) * 0.06).normalized()
			var keep := rng.randf_range(0.3, 0.55)
			world.server_impact(hit_pos, normal, str(mat.get("impact", "concrete")), "ricochet", p.shooter, p.id)
			p.ignore_eid = -1
			from = hit_pos + normal * 0.02
			new_vel = out_dir * speed * sqrt(keep)
			p.vel = new_vel
			to = from + new_vel * dt * 0.5
			continue
		# Penetration: measure thickness by casting back from beyond the surface.
		var max_th := float(mat.get("max_thickness_cm", 30.0)) / 100.0
		var back_from := hit_pos + dir * max_th
		var bq := PhysicsRayQueryParameters3D.create(back_from, hit_pos - dir * 0.001, Defs.SHOT_MASK)
		var bh := space.intersect_ray(bq)
		var thickness := max_th
		var exit_pos := back_from
		if not bh.is_empty():
			exit_pos = bh.position
			thickness = hit_pos.distance_to(exit_pos)
		var pen_factor := pow(clampf(float(p.pen), 0.4, 3.5), 0.6)
		var loss := float(mat.get("resist", 600.0)) * thickness * 100.0 / pen_factor
		world.server_impact(hit_pos, normal, str(mat.get("impact", "concrete")), "hole", p.shooter, p.id)
		if e > loss and thickness < max_th * 0.999:
			stats.penetrations += 1
			e -= loss
			var nspeed := Ballistics.speed_for_energy(p.mass, e)
			var dev := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * (0.02 + thickness * 0.2)
			var ndir := (dir + dev).normalized()
			world.server_impact(exit_pos, dir, str(mat.get("impact", "concrete")), "exit", p.shooter, p.id)
			from = exit_pos + ndir * 0.01
			new_vel = ndir * nspeed
			p.vel = new_vel
			var remain := maxf(seg_len - (wh.position as Vector3).distance_to(p.pos), 0.05)
			to = from + ndir * remain
			continue
		return false
	p.dist += (to - p.pos).length()
	p.pos = to
	p.vel = new_vel
	return true


func _test_characters(p: Dictionary, from: Vector3, to: Vector3, tick: int) -> Dictionary:
	var best := {}
	var best_t := INF
	var eval_tick: int = mini(int(p.view_tick) + int(p.age), tick)
	for ch in world.characters.values():
		if ch.eid == p.ignore_eid or ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
			continue
		var st: Dictionary = world.history_state(ch.eid, eval_tick)
		if st.is_empty():
			continue
		var c: Vector3 = st.pos + Vector3.UP * 0.9
		if _seg_point_dist(from, to, c) > 2.2:
			continue
		var caps := HitZones.capsules(st.pos, st.yaw, st.pitch, st.crouch, st.mode, st.armed)
		var h := HitZones.intersect(caps, from, to)
		if not h.is_empty() and float(h.t) < best_t:
			best_t = h.t
			h.ch = ch
			best = h
	return best


func _flybys(p: Dictionary, from: Vector3, to: Vector3) -> void:
	## Rounds passing close to someone's head produce a crack / whiz for that player only.
	for ch in world.characters.values():
		if ch.eid == p.shooter or ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE] or p.flyby.has(ch.eid):
			continue
		var head: Vector3 = ch.eye_position()
		var d := _seg_point_dist(from, to, head)
		if d < 3.5:
			p.flyby[ch.eid] = true
			var cp := _closest_on_seg(from, to, head)
			world.server_flyby(ch, cp, (p.vel as Vector3).length(), d)


static func _closest_on_seg(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return a
	return a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)


static func _seg_point_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	return p.distance_to(_closest_on_seg(a, b, p))
