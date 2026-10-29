extends RefCounted
## Open ground for fights that move: the looban courtyards left in dense blocks, junk barricades across lanes, and
## low yard walls in the mixed district. Everything here is built to be vaulted (Vault: tops between 0.45 and 1.5 m,
## climbed on to when deep): crate stacks that step up to a kiosk roof, hip-high hollow-block walls, sandbag rows,
## drums, and the life of the courtyard - a hand pump, washing, a basketball ring, a tricycle, a bulb on a wire.
## Solid things here are taken out of the bots' walking grid, so they go round what they cannot vault.

var mb = null
var L = null
var sink = null
var dyn = null
var rng := RandomNumberGenerator.new()
var stats := {"loobans": 0, "crate_stacks": 0, "low_walls": 0, "sandbags": 0, "kiosks": 0, "barricades": 0, "yard_walls": 0}


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	sink = mb.sink
	dyn = mb.dyn
	rng.seed = L.rng.seed + 911


func build() -> void:
	for lb in mb.loobans:
		_looban(lb)
	for b in mb.barricades:
		_barricade(b)
	for y in mb.yard_walls:
		_yard_wall(y)
	_vacant_lots()
	print("[looban] ", stats)


func _pick(a: Array):
	return a[rng.randi_range(0, a.size() - 1)]


func _gy(p: Vector2) -> float:
	return L.ground_height(p.x, p.y)


func _solid(p: Vector2, half: Vector2, ang: float) -> void:
	## Takes the footprint out of the bots' grid (2 m cells).
	L.reserve_rect(p, half, ang, 2)


func _crate(p: Vector2, yaw: float, size: Vector3, base_y: float, mat: String = "") -> void:
	mb.vault_spots.append({"pos": Vector3(p.x, base_y + size.y, p.y), "size": size, "yaw": yaw})
	var m = mat if mat != "" else _pick(["planks", "planks_dark", "osb", "plywood", "planks_peel"])
	sink.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, base_y + size.y * 0.5, p.y)), size, m, {"dirt": 0.9, "phys": "wood"})
	# Slats on a wooden crate's sides, so it reads as a crate and not a block.
	if m != "osb" and size.x > 0.6:
		for k in [-1.0, 1.0]:
			sink.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, base_y + size.y * (0.5 + 0.3 * k), p.y)), Vector3(size.x + 0.03, 0.07, size.z + 0.03), "timber",
				{"dirt": 1.0, "collide": false})


# ------------------------------------------------------------------ courtyards

func _looban(lb: Dictionary) -> void:
	stats.loobans += 1
	var c: Vector2 = lb.c
	var half: Vector2 = lb.half
	var ang: float = lb.ang
	var xa := Vector2(cos(ang), sin(ang))
	var za := Vector2(-sin(ang), cos(ang))
	var at := func(u: float, v: float) -> Vector2: return c + xa * u + za * v
	var yaw0 := -ang
	# Worn concrete slabs over part of the ground: an old basketball court, a wash area.
	var sw := half.x * rng.randf_range(1.0, 1.5)
	var sd := half.y * rng.randf_range(0.9, 1.4)
	var sc: Vector2 = at.call(rng.randf_range(-0.2, 0.2) * half.x, rng.randf_range(-0.2, 0.2) * half.y)
	var sy := _gy(sc)
	sink.box(Transform3D(Basis(Vector3.UP, yaw0), Vector3(sc.x, sy - 0.01, sc.y)), Vector3(sw, 0.06, sd), _pick(["concrete_cracked", "concrete_dirty", "cement"]),
		{"dirt": 1.0, "faces": 4 | 1 | 2 | 16 | 32, "phys": "concrete"})
	# 1. A kiosk (sari-sari store or a shed) with a flat roof you can get on to from a crate stack beside it.
	var ku := (half.x - 1.6) * (1.0 if rng.randf() < 0.5 else -1.0)
	var kv := (half.y - 1.4) * (1.0 if rng.randf() < 0.5 else -1.0)
	var kp: Vector2 = at.call(ku, kv)
	var front := (c - kp).normalized()
	var kw := rng.randf_range(2.4, 3.0)
	var kd := rng.randf_range(2.0, 2.4)
	var basis := _basis_facing(front)
	var ky := _gy(kp) + 0.08
	var spec := {"xf": Transform3D(basis, Vector3(kp.x, ky, kp.y)), "w": kw, "d": kd, "floors": 1, "style": "chb", "kind": "store", "stilts": false,
		"ground_y": ky - 0.08, "front": "store", "seed": rng.randi(), "district": str(lb.get("district", "")), "can_overhang": false,
		"roof_deck": true, "ladder": false, "parapet": false, "front_gy": ky - 0.08}
	var out: Dictionary = mb.shanty(spec)
	L.reserve_rect(kp, Vector2(kw * 0.5, kd * 0.5), atan2(basis.x.z, basis.x.x), 3)
	stats.kiosks += 1
	var roof_top: float = ky + float(out.get("h0", 2.4)) + 0.14
	# Steps up: a low crate, then a tall one against the kiosk's side wall.
	var sidev := Vector2(basis.x.x, basis.x.z)
	if sidev.dot(c - kp) < 0.0:
		sidev = -sidev   # the steps go on the courtyard side of the kiosk
	var s1: Vector2 = kp + sidev * (kw * 0.5 + 0.5)
	var tall := clampf(roof_top - _gy(s1) - 1.2, 0.95, 1.45)
	_crate(s1, atan2(-sidev.y, sidev.x), Vector3(1.2, tall, 1.0), _gy(s1))
	var s2: Vector2 = s1 + sidev * 1.15 + Vector2(-sidev.y, sidev.x) * 0.15
	_crate(s2, atan2(-sidev.y, sidev.x) + 0.1, Vector3(1.15, minf(tall * 0.55, 0.8), 1.0), _gy(s2))
	_solid((s1 + s2) * 0.5, Vector2(1.0, 0.6), atan2(sidev.y, sidev.x))
	stats.crate_stacks += 1
	# 2. Two or three more crate stacks: steps of 0.5, 0.9 and 1.4 m to move over and fight from.
	for i in rng.randi_range(2, 3):
		var p: Vector2 = at.call(rng.randf_range(-0.55, 0.55) * half.x, rng.randf_range(-0.55, 0.55) * half.y)
		if p.distance_to(kp) < 3.2:
			continue
		var yaw := rng.randf() * TAU
		var q := Vector2(cos(yaw), -sin(yaw))
		var heights := [0.5, 0.92, 1.38]
		if rng.randf() < 0.3:
			heights = [0.92, 1.38, 0.5]
		for k in 3:
			var pk: Vector2 = p + q * (k - 1) * 1.2
			_crate(pk, yaw + rng.randf_range(-0.08, 0.08), Vector3(1.18, float(heights[k]), 0.9), _gy(pk))
		_solid(p, Vector2(1.5, 0.5), atan2(q.y, q.x))
		stats.crate_stacks += 1
	# 3. A hip-high hollow-block wall, often an L: cover you can vault.
	for i in rng.randi_range(1, 2):
		var p2: Vector2 = at.call(rng.randf_range(-0.5, 0.5) * half.x, rng.randf_range(-0.5, 0.5) * half.y)
		if p2.distance_to(kp) < 3.0:
			continue
		var la := rng.randf_range(2.2, 3.8)
		var yaw2 := yaw0 + (0.0 if rng.randf() < 0.5 else PI * 0.5)
		_low_wall(p2, yaw2, la, rng.randf_range(0.95, 1.12))
		if rng.randf() < 0.55:
			var dirv := Vector2(cos(yaw2), -sin(yaw2))
			var corner := p2 + dirv * la * 0.5
			var nrm := Vector2(-dirv.y, dirv.x)
			_low_wall(corner + nrm * 1.0 - dirv * 0.06, yaw2 + PI * 0.5, 2.0, rng.randf_range(0.95, 1.12))
	# 4. A row of sandbags.
	if rng.randf() < 0.6:
		var p3: Vector2 = at.call(rng.randf_range(-0.4, 0.4) * half.x, rng.randf_range(-0.4, 0.4) * half.y)
		if p3.distance_to(kp) > 3.0:
			_sandbags(p3, yaw0 + rng.randf_range(-0.4, 0.4), rng.randf_range(2.0, 3.2))
	# 5. Drums, a tricycle, a hand pump, a basketball ring, washing, a bulb on a wire, rubbish, loot.
	for i in rng.randi_range(2, 5):
		var dp: Vector2 = at.call(rng.randf_range(-0.8, 0.8) * half.x, rng.randf_range(-0.8, 0.8) * half.y)
		dyn.add_prop_spec(_pick(["drum_blue", "oil_drum", "drum", "crate_plastic", "bucket", "jerrycan"]), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(dp.x, _gy(dp), dp.y)))
	if rng.randf() < 0.5:
		var tp: Vector2 = at.call(rng.randf_range(-0.6, 0.6) * half.x, rng.randf_range(-0.6, 0.6) * half.y)
		if tp.distance_to(kp) > 3.0:
			dyn.add_static_prop(_pick(["tricycle_a", "tricycle_b"]), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(tp.x, _gy(tp) + 0.05, tp.y)))
			_solid(tp, Vector2(1.2, 0.7), 0.0)
	var pp: Vector2 = at.call(-ku * 0.6, -kv * 0.7)
	_hand_pump(pp)
	if rng.randf() < 0.65:
		var rp: Vector2 = at.call(-ku * 0.9, rng.randf_range(-0.3, 0.3) * half.y)
		_ring(rp, (c - rp).normalized())
	for i in rng.randi_range(1, 3):
		var a0: Vector2 = at.call(-half.x + 0.3, rng.randf_range(-0.7, 0.7) * half.y)
		var a1: Vector2 = at.call(half.x - 0.3, rng.randf_range(-0.7, 0.7) * half.y)
		_washing(Vector3(a0.x, _gy(a0) + 2.3, a0.y), Vector3(a1.x, _gy(a1) + 2.3, a1.y))
	var lp: Vector2 = at.call(rng.randf_range(-0.3, 0.3) * half.x, rng.randf_range(-0.3, 0.3) * half.y)
	var r := rng.randf()
	dyn.add_light({"pos": Vector3(lp.x, _gy(lp) + 3.1, lp.y), "kind": "bulb", "color": Color(1.0, 0.72, 0.42), "energy": 1.0, "range": 9.0,
		"fault": "" if r < 0.5 else ("flicker" if r < 0.8 else "sag"), "dead": rng.randf() < 0.2, "outdoor": true})
	for i in rng.randi_range(1, 3):
		var hp: Vector2 = at.call(_pick([-1.0, 1.0]) * (half.x - 0.5), rng.randf_range(-0.8, 0.8) * half.y)
		dyn.add_static_prop(_pick(["heap_small_a", "heap_small_b", "heap_medium_a", "litter_a", "litter_b"]), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(hp.x, _gy(hp), hp.y)))
	for i in rng.randi_range(2, 3):
		var lt: Vector2 = at.call(rng.randf_range(-0.7, 0.7) * half.x, rng.randf_range(-0.7, 0.7) * half.y)
		dyn.add_loot_spot(Vector3(lt.x, _gy(lt) + 0.03, lt.y), "floor_street", -1)
	if rng.randf() < 0.7:
		var bp: Vector2 = at.call(rng.randf_range(-0.6, 0.6) * half.x, rng.randf_range(-0.6, 0.6) * half.y)
		if bp.distance_to(kp) > 2.5:
			dyn.add_loot_box(_pick(["lootbox_balikbayan", "lootbox_bin", "lootbox_cooler"]), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(bp.x, _gy(bp), bp.y)),
				_pick(["box_balikbayan", "box_bin", "box_cooler"]), -1)
	mb.alleys.append({"a": at.call(-half.x, 0.0), "b": at.call(half.x, 0.0), "w": half.y * 2.0, "kind": "looban"})


static func _basis_facing(front2d: Vector2) -> Basis:
	var f := Vector3(front2d.x, 0, front2d.y).normalized()
	var z := -f
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)


func _low_wall(p: Vector2, yaw: float, length: float, h: float) -> void:
	var y := _gy(p)
	var mat: String = _pick(["chb", "chb2", "plaster_damaged", "concrete_dirty"])
	sink.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y + h * 0.5 - 0.05, p.y)), Vector3(length, h + 0.1, 0.16), mat, {"dirt": 1.0, "phys": "hollow_block"})
	# A cap of cement and a broken-bottle or rebar top on some.
	sink.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y + h + 0.02, p.y)), Vector3(length + 0.04, 0.05, 0.2), "cement", {"dirt": 1.0, "collide": false})
	_solid(p, Vector2(length * 0.5, 0.2), -yaw)
	stats.low_walls += 1


func _sandbags(p: Vector2, yaw: float, length: float) -> void:
	var y := _gy(p)
	var dirv := Vector3(cos(yaw), 0, -sin(yaw))
	for row in 3:
		var n := int(length / 0.55)
		for i in n:
			var o := (i - (n - 1) * 0.5) * 0.55 + (0.27 if row % 2 == 1 else 0.0)
			var q := Vector3(p.x, y + 0.13 + row * 0.24, p.y) + dirv * o
			sink.box(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.08, 0.08)) * Basis(Vector3.FORWARD, rng.randf_range(-0.05, 0.05)), q), Vector3(0.55, 0.24, 0.36),
				"hessian", {"dirt": 1.0, "collide": false, "tint": Color(0.75, 0.68, 0.5), "paint": 0.4})
	sink.col_box(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y + 0.38, p.y)), Vector3(length + 0.3, 0.76, 0.4), "fabric")
	_solid(p, Vector2(length * 0.5, 0.25), -yaw)
	stats.sandbags += 1


func _hand_pump(p: Vector2) -> void:
	var y := _gy(p)
	sink.box(Transform3D(Basis(), Vector3(p.x, y + 0.08, p.y)), Vector3(1.0, 0.16, 1.0), "cement", {"dirt": 1.0, "phys": "concrete"})
	sink.cylinder(Vector3(p.x, y + 0.16, p.y), Vector3.UP, 0.9, 0.07, "metal_paint", {"sides": 8, "tint": Color(0.2, 0.35, 0.25), "paint": 0.7, "collide": true, "phys": "steel"})
	sink.cylinder(Vector3(p.x, y + 0.95, p.y), Vector3(1, 0.35, 0).normalized(), 0.7, 0.02, "metal_rust", {"sides": 6})
	sink.cylinder(Vector3(p.x, y + 0.75, p.y), Vector3(0, -0.2, 1).normalized(), 0.25, 0.03, "metal_rust", {"sides": 6})
	dyn.add_prop_spec("bucket", Transform3D(Basis(), Vector3(p.x, y + 0.16, p.y + 0.3)))


func _ring(p: Vector2, face: Vector2) -> void:
	var y := _gy(p)
	sink.box(Transform3D(Basis(), Vector3(p.x, y + 1.6, p.y)), Vector3(0.12, 3.2, 0.12), "timber", {"dirt": 1.0, "phys": "wood"})
	var b := _basis_facing(face)
	sink.box(Transform3D(b, Vector3(p.x, y + 3.1, p.y) + b.z * -0.12), Vector3(1.1, 0.75, 0.03), "plywood", {"dirt": 1.0, "collide": false, "tint": Color(0.9, 0.9, 0.86), "paint": 0.6})
	var rc := Vector3(p.x, y + 2.95, p.y) - b.z * 0.38
	for k in 10:
		var a0 := TAU * k / 10.0
		var a1 := TAU * (k + 1) / 10.0
		var p0 := rc + Vector3(cos(a0), 0, sin(a0)) * 0.23
		var p1 := rc + Vector3(cos(a1), 0, sin(a1)) * 0.23
		sink.box(Transform3D(Basis.looking_at((p1 - p0).normalized(), Vector3.UP), (p0 + p1) * 0.5), Vector3(0.015, 0.015, p0.distance_to(p1)), "metal_paint",
			{"collide": false, "tint": Color(0.8, 0.3, 0.1), "paint": 0.8, "layer": "mid"})
	_solid(p, Vector2(0.3, 0.3), 0.0)


func _washing(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 1.0:
		return
	var n := int(len / 0.45)
	var dir := d / len
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).orthonormalized()
	sink.box(Transform3D(basis, (a + b) * 0.5 + Vector3.DOWN * 0.12), Vector3(len, 0.012, 0.012), "wire", {"collide": false, "layer": "mid"})
	for i in n:
		if rng.randf() < 0.4:
			continue
		var t := (i + 0.5) / n
		var p := a.lerp(b, t) + Vector3.DOWN * 0.18 * 4.0 * t * (1.0 - t)
		var cw := rng.randf_range(0.28, 0.55)
		var ch := rng.randf_range(0.3, 0.75)
		sink.box(Transform3D(basis * Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), p + Vector3.DOWN * ch * 0.5), Vector3(cw, ch, 0.01), _pick(["cloth", "gingham"]),
			{"collide": false, "faces": 16 | 32, "tint": mb.mats.PAINTS[rng.randi_range(0, mb.mats.PAINTS.size() - 1)], "paint": 1.0, "dirt": 0.15, "layer": "mid"})


# ------------------------------------------------------------------ vacant lots

func _vacant_lots() -> void:
	## The open ground between districts: what is left of houses that burned or were torn down (broken hollow-block
	## walls, some with window holes), rubbish heaps, a dead tricycle, weeds. Cover to run between by day.
	stats.vacant = 0
	var tries := int(2600 * L.MAP_SCALE * L.MAP_SCALE)
	for i in tries:
		if stats.vacant >= 80:
			break
		var p := Vector2(rng.randf_range(-L.PLAY_HALF, L.PLAY_HALF), rng.randf_range(-L.PLAY_HALF, L.PLAY_HALF))
		if not L.in_play_area(p) or L.is_water(p.x, p.y) or not L.rect_free(p, Vector2(4.5, 4.5), 0.0, false, 0.5):
			continue
		var yaw := rng.randf() * TAU
		var dirv := Vector2(cos(yaw), -sin(yaw))
		var nrm := Vector2(-dirv.y, dirv.x)
		# A ruin: two or three broken wall stubs on an old footprint, one with a window hole at vaulting height.
		var w := rng.randf_range(3.5, 6.0)
		var d := rng.randf_range(3.5, 5.5)
		var y := _gy(p)
		sink.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y - 0.02, p.y)), Vector3(w, 0.1, d), _pick(["cement", "concrete_cracked", "tiles_floor"]),
			{"dirt": 1.0, "faces": 4 | 1 | 2 | 16 | 32, "phys": "concrete"})
		var walls := [[p + nrm * d * 0.5, yaw, w], [p - dirv * w * 0.5, yaw + PI * 0.5, d]]
		if rng.randf() < 0.5:
			walls.append([p - nrm * d * 0.5, yaw, w * rng.randf_range(0.4, 0.8)])
		for wl in walls:
			var c: Vector2 = wl[0]
			var h := rng.randf_range(0.7, 2.2)
			if h > 1.5 and rng.randf() < 0.6:
				# Tall enough to keep a window hole: wall either side and below it.
				var len := float(wl[2])
				var hy := _gy(c)
				var wy := float(wl[1])
				var along := Vector2(cos(wy), -sin(wy))
				var side_len := (len - 1.1) * 0.5
				for sgn in [-1.0, 1.0]:
					var sc: Vector2 = c + along * sgn * (0.55 + side_len * 0.5)
					sink.box(Transform3D(Basis(Vector3.UP, wy), Vector3(sc.x, hy + h * 0.5 - 0.05, sc.y)), Vector3(side_len, h + 0.1, 0.15), "chb2", {"dirt": 1.0, "phys": "hollow_block"})
				sink.box(Transform3D(Basis(Vector3.UP, wy), Vector3(c.x, hy + 0.85 * 0.5 - 0.05, c.y)), Vector3(1.1, 0.95, 0.15), "chb2", {"dirt": 1.0, "phys": "hollow_block"})
				_solid(c, Vector2(len * 0.5, 0.2), -wy)
			else:
				_low_wall(c, float(wl[1]), float(wl[2]) * rng.randf_range(0.5, 1.0), h)
		dyn.add_static_prop(_pick(["heap_medium_a", "heap_medium_b", "heap_small_a", "rubble_a", "rubble_b"]), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y, p.y) + Vector3(dirv.x, 0, dirv.y) * rng.randf_range(-1.0, 1.0)))
		if rng.randf() < 0.25:
			var tp := p + nrm * (d * 0.5 + 2.0)
			if L.rect_free(tp, Vector2(1.2, 1.2), 0.0, false, 0.0):
				dyn.add_static_prop(_pick(["tricycle_a", "tricycle_b"]), Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, rng.randf_range(-0.3, 0.3)), Vector3(tp.x, _gy(tp), tp.y)))
				_solid(tp, Vector2(1.0, 0.6), 0.0)
		for k in rng.randi_range(2, 5):
			var gp := p + Vector2(rng.randf_range(-w, w), rng.randf_range(-d, d)) * 0.6
			dyn.add_static_prop(_pick(["weeds", "grass_clump", "fern", "shrub"]), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(gp.x, _gy(gp), gp.y)))
		if rng.randf() < 0.5:
			dyn.add_loot_spot(Vector3(p.x, y + 0.05, p.y), "floor_street", -1)
		L.reserve_rect(p, Vector2(w * 0.5, d * 0.5), -yaw, 4)
		stats.vacant += 1


# ------------------------------------------------------------------ barricades and yard walls

func _barricade(b: Dictionary) -> void:
	## Junk piled across a lane to keep someone out: crates, a door on its side, a corrugated sheet, tyres. About
	## 1.2 m high - you vault it (and make noise doing it) or go round.
	var c: Vector2 = b.c
	var along: Vector2 = b.along
	var w := float(b.w)
	var across := Vector2(-along.y, along.x)
	if not dyn.door_swing_clear(c, Vector2(0.6, w * 0.5), atan2(along.y, along.x)):
		return
	var y := _gy(c)
	var yaw := atan2(-across.y, across.x)
	var h := rng.randf_range(1.12, 1.32)
	# The bulk: crates side by side across the lane.
	var n := maxi(int(ceil(w / 0.85)), 1)
	for i in n:
		var p := c + across * ((i - (n - 1) * 0.5) * (w / n))
		_crate(p, yaw + rng.randf_range(-0.12, 0.12), Vector3(w / n - 0.04, h * rng.randf_range(0.6, 0.85), 0.55), y)
	# On top and in front: a door on its side, a sheet, tyres.
	sink.box(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, rng.randf_range(-0.1, 0.1)), Vector3(c.x, y + h - 0.12, c.y)), Vector3(w + 0.1, 0.24, 0.05),
		_pick(["planks_blue", "planks_paint", "plywood"]), {"dirt": 1.0, "collide": false})
	sink.corrugated(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5 - 0.25), Vector3(c.x, y + h * 0.45, c.y) + Vector3(along.x, 0, along.y) * 0.33), h * 0.9, w * 0.9,
		"yero_rust", {"dirt": 1.0, "collide": false})
	dyn.add_static_prop("old_tyre", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(c.x, y + h * 0.75, c.y) + Vector3(across.x, 0, across.y) * w * 0.25))
	sink.col_box(Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y + h * 0.5, c.y)), Vector3(w + 0.3, h, 0.6), "wood")
	_solid(c, Vector2(w * 0.5 + 0.2, 0.4), atan2(across.y, across.x))
	mb.vandal_spots.append({"pos": Vector3(c.x, y + 0.6, c.y), "n": Vector3(along.x, 0, along.y), "kind": "barricade"})
	stats.barricades += 1


func _yard_wall(yw: Dictionary) -> void:
	var c: Vector2 = yw.c
	var along: Vector2 = yw.along
	var len := float(yw.len)
	if L.is_water(c.x, c.y) or not L.in_play_area(c):
		return
	# A gate gap off centre.
	var gap_at := rng.randf_range(-0.25, 0.25) * len
	var gw := 1.0
	var yaw := atan2(-along.y, along.x)
	var h := rng.randf_range(0.95, 1.15)
	for part in [[-len * 0.5, gap_at - gw * 0.5], [gap_at + gw * 0.5, len * 0.5]]:
		var l := float(part[1]) - float(part[0])
		if l < 0.4:
			continue
		var mid := c + along * (float(part[0]) + float(part[1])) * 0.5
		if not dyn.door_swing_clear(mid, Vector2(l * 0.5, 0.2), atan2(along.y, along.x)):
			continue
		_low_wall(mid, yaw, l, h)
	stats.yard_walls += 1
