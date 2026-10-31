extends RefCounted
## Authoritative projectile simulation (server only).
##
## Hit registration model ("shooter's view, server flight"): a shot is created at the muzzle position and direction
## the shooter's command carried. It then flies under gravity and drag on the server, one tick at a time, and is
## tested against world geometry at the current time and against characters as the shooter saw them: each
## character's recorded state at (view_tick + flight ticks), where view_tick is the tick the shooter was rendering
## when they fired (clamped to max_rewind). This favours the shooter by at most max_rewind seconds and never lets a
## bullet hit someone the shooter could not have seen at that moment.
##
## (r22) Every round in flight tests every character, every tick, so a big firefight (a few hundred rounds in the air,
## most of them misses flying on for seconds) cost a listen host 80+ ms a frame on Freight Delight. Once per tick the
## characters a round can meet are gathered with the bounds of where each has been over the rewind window and where its
## eyes are now; a round only looks up history and hit capsules for a character whose bounds come within reach of its
## segment, and only works out a fly-by for one whose eyes are within 3.5 m of the segment's box. The same hits and
## fly-bys as before, without the lookups that could never have counted. A round that has left the map (40 m past its
## edge and past everyone, heading further out: nothing it could still meet) is dropped then, not after 4 s and 1.6 km
## (on Freight Delight, 70 m to the edge, a miss used to fly on for twenty times as long as it was over the map).

const HitZones := preload("res://src/player/hitzones.gd")

var world = null
var space: PhysicsDirectSpaceState3D
var list: Array = []
var _next_id := 1
var stats := {"spawned": 0, "world_hits": 0, "char_hits": 0, "penetrations": 0, "ricochets": 0, "expired": 0}
# (r22) this tick's characters (see the top): the character, the box of its rewound chest points, its eyes now
var _cands: Array = []
var _lo := PackedVector3Array()
var _hi := PackedVector3Array()
var _eye := PackedVector3Array()
const HIT_REACH := 2.2      # _test_characters: a chest point further than this from the segment cannot be hit
const FLYBY_REACH := 3.5    # _flybys: the crack / whiz is heard within this of the head
const OUT_MARGIN := 40.0    # a round this far past the map's edge (and past everyone) and heading out is gone
var _edge := INF            # this tick's: the map's half size or the furthest character, plus OUT_MARGIN


func _init(w) -> void:
	world = w


func spawn(shooter, shot: Dictionary, view_tick: int, tick: int) -> int:
	var ammo_id := str(shot.ammo)
	var ammo := Defs.ammo(ammo_id)
	var v0 := float(shot.velocity)
	var mass := float(ammo.get("mass", 0.008))
	var e0 := Ballistics.energy(mass, v0)
	var pellets := int(shot.get("pellets", 1))
	var spread := float(ammo.get("spread_deg", 0.0)) * float(shot.get("pellet_mult", 1.0))
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
	_gather(tick)
	for i in range(list.size() - 1, -1, -1):
		var p: Dictionary = list[i]
		var alive := _advance(p, dt, tick)
		p.age += 1
		if alive and _gone(p.pos, p.vel):
			alive = false
			stats.expired += 1
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
			if col and col.has_meta("door_id"):
				world.server_door_hit(col, hit_pos, dir, e)   # (r15) a glass door bursts (Malasugue Mall)
			from = hit_pos + dir * 0.05
			new_vel *= 0.92
			p.vel = new_vel
			to = from + new_vel.normalized() * maxf(seg_len * (1.0 - from.distance_to(wh.position) / seg_len), 0.1)
			continue
		if col and col.has_meta("prop_id"):
			world.server_prop_hit(int(col.get_meta("prop_id")), hit_pos, dir, e, p.mass * speed)
		if col and (col.has_meta("door_id") or col.has_meta("shutter_id")):
			world.server_door_hit(col, hit_pos, dir, e)
		var att := _attach_code(col)
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
			world.server_impact(hit_pos, normal, str(mat.get("impact", "concrete")), "ricochet", p.shooter, p.id, mat_id, att)
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
		world.server_impact(hit_pos, normal, str(mat.get("impact", "concrete")), "hole", p.shooter, p.id, mat_id, att)
		if e > loss and thickness < max_th * 0.999:
			stats.penetrations += 1
			e -= loss
			var nspeed := Ballistics.speed_for_energy(p.mass, e)
			var dev := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * (0.02 + thickness * 0.2)
			var ndir := (dir + dev).normalized()
			world.server_impact(exit_pos, dir, str(mat.get("impact", "concrete")), "exit", p.shooter, p.id, mat_id, att)
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


static func _attach_code(col) -> int:
	## What a bullet mark should hang on so it moves with it: a door, a shutter or a loose prop (see World).
	if col == null:
		return 0
	if col.has_meta("door_id"):
		return (1 << 24) | int(col.get_meta("door_id"))
	if col.has_meta("shutter_id"):
		return (2 << 24) | int(col.get_meta("shutter_id"))
	if col.has_meta("prop_id"):
		return (3 << 24) | int(col.get_meta("prop_id"))
	return 0


func _gather(tick: int) -> void:
	## (r22) Once per tick: who a round can meet, the box of where each was over the rewind window (every state
	## history_state can return for this tick's rounds, the first one before the window included) lifted to the chest
	## point the hit test starts from, and its eyes now (nobody moves while a tick's rounds fly).
	_cands.clear()
	_lo.resize(0)
	_hi.resize(0)
	_eye.resize(0)
	var oldest := tick - int(float(Defs.rule("net.max_rewind_s", 0.3)) * Defs.TICK_RATE) - 1
	var chest := Vector3.UP * 0.9
	var far := float(world.map.layout.HALF) if world.map and world.map.layout else INF
	for ch in world.characters.values():
		if ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
			continue
		var lo: Vector3 = ch.global_position
		var hi := lo
		var h: Dictionary = world._history.get(ch.eid, {})
		if not h.is_empty():
			var ticks: Array = h.ticks
			var states: Array = h.states
			var n := ticks.size()
			for k in n:
				var j := (int(h.i) - 1 - k + n * 2) % n
				var t := int(ticks[j])
				if t < 0:
					break
				var sp: Vector3 = states[j].pos
				lo = lo.min(sp)
				hi = hi.max(sp)
				if t < oldest:
					break
		_cands.append(ch)
		_lo.append(lo + chest)
		_hi.append(hi + chest)
		_eye.append(ch.eye_position())
		far = maxf(far, maxf(maxf(absf(lo.x), absf(hi.x)), maxf(absf(lo.z), absf(hi.z))))
	_edge = far + OUT_MARGIN


func _gone(pos: Vector3, vel: Vector3) -> bool:
	## Past the edge on an axis and still heading out on it (drag slows a round but never turns it): it can only get
	## further from everything in the map.
	return (pos.x > _edge and vel.x > 0.0) or (pos.x < -_edge and vel.x < 0.0) 		or (pos.z > _edge and vel.z > 0.0) or (pos.z < -_edge and vel.z < 0.0)


static func _near_box(from: Vector3, to: Vector3, lo: Vector3, hi: Vector3, reach: float) -> bool:
	## Whether the box lo..hi comes within reach of the segment's own box (cheap, never false when a point of the box is
	## within reach of the segment).
	var a := from.min(to)
	var b := from.max(to)
	return lo.x <= b.x + reach and hi.x >= a.x - reach and lo.y <= b.y + reach and hi.y >= a.y - reach 		and lo.z <= b.z + reach and hi.z >= a.z - reach


func _test_characters(p: Dictionary, from: Vector3, to: Vector3, tick: int) -> Dictionary:
	var best := {}
	var best_t := INF
	var eval_tick: int = mini(int(p.view_tick) + int(p.age), tick)
	for k in _cands.size():
		var ch = _cands[k]
		if not is_instance_valid(ch) or ch.eid == p.ignore_eid or ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
			continue
		if not _near_box(from, to, _lo[k], _hi[k], HIT_REACH):
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
	for k in _cands.size():
		var ch = _cands[k]
		var head: Vector3 = _eye[k]
		if not _near_box(from, to, head, head, FLYBY_REACH):
			continue
		if not is_instance_valid(ch) or ch.eid == p.shooter or ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE] or p.flyby.has(ch.eid):
			continue
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
