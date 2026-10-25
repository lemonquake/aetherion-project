extends RefCounted
## Fills each district with houses. Every district kind has its own street pattern:
##  dense        - jittered blocks split by eskinitas (1.3-2.6 m alleys), houses packed along every alley, tiny loobans
##  rail         - two rows of shacks facing the track, eaves almost touching the rails
##  stilt_creek  - shanties on stilts facing the estero across a plank walk, roofs nearly closing over the water
##  stilt_river  - a row of stilt houses along each river bank with a boardwalk over the water in front
##  mixed        - concrete streets, bigger lots, hollow-block houses with yards and gates
##  fishing      - piers into the bay lined with stilt houses
##  workshops    - open-fronted sheds and talyers
##  subdivision  - a walled street of two-storey concrete houses
##  under_highway- shacks squeezed between the expressway pillars
##  port, dump   - warehouses / scavenger shacks (sites handle the big structures)

var mb = null  # MapBuilder
var L = null   # Layout
var rng := RandomNumberGenerator.new()
var count := 0


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	rng.seed = L.rng.seed + 101


func build_all(only: Array = []) -> void:
	for d in L.districts:
		if not only.is_empty() and not (d.name in only):
			continue
		match str(d.kind):
			"dense":
				_dense(d)
			"rail":
				_rail(d)
			"stilt_creek":
				_creek(d)
			"stilt_river":
				_river_bank(d)
			"mixed":
				_mixed(d)
			"fishing":
				_fishing(d)
			"workshops":
				_workshops(d)
			"subdivision":
				_subdivision(d)
			"under_highway":
				_under_highway(d)
			"dump":
				_dump(d)


# ------------------------------------------------------------------ helpers

static func basis_facing(front2d: Vector2) -> Basis:
	## Houses face local -Z; return a basis whose -Z points along front2d (x, z).
	var f := Vector3(front2d.x, 0, front2d.y).normalized()
	var z := -f
	var x := Vector3.UP.cross(z).normalized()
	return Basis(x, Vector3.UP, z)


func place(center: Vector2, front2d: Vector2, w: float, d: float, opts: Dictionary) -> bool:
	## Validates and builds one house. Returns false if the lot is blocked.
	var yaw := atan2(front2d.x, front2d.y)
	var ang := -atan2(front2d.y, front2d.x) - PI * 0.5
	var basis := basis_facing(front2d)
	var xa := Vector2(basis.x.x, basis.x.z)
	var rect_ang := atan2(xa.y, xa.x)
	var allow_water: bool = opts.get("allow_water", false)
	if not L.rect_free(center, Vector2(w * 0.5, d * 0.5), rect_ang, allow_water, float(opts.get("margin", 0.08))):
		return false
	if not L.in_play_area(center):
		return false
	# Ground: sample corners; slopes and water mean stilts or a raised plinth.
	var hs := []
	var corners := [Vector2(-w, -d), Vector2(w, -d), Vector2(w, d), Vector2(-w, d), Vector2.ZERO]
	var wet := 0
	for c in corners:
		var p: Vector2 = center + xa * c.x * 0.5 + Vector2(basis.z.x, basis.z.z) * c.y * 0.5
		hs.append(L.ground_height(p.x, p.y))
		if L.is_water(p.x, p.y):
			wet += 1
	var hmin: float = hs.min()
	var hmax: float = hs.max()
	var stilts: bool = opts.get("stilts", false) or wet > 0 or hmax - hmin > 0.7
	var base_y := hmax + 0.08
	if stilts:
		base_y = maxf(float(opts.get("deck_y", L.LAND_Y + 0.35)), hmax + 0.15)
	var spec := {
		"xf": Transform3D(basis, Vector3(center.x, base_y, center.y)), "w": w, "d": d,
		"floors": int(opts.get("floors", 1)), "style": str(opts.get("style", "wood")), "kind": str(opts.get("kind", "house")),
		"stilts": stilts, "ground_y": hmin, "front": str(opts.get("front", "door")), "seed": rng.randi(),
		"district": str(opts.get("district", "")), "can_overhang": bool(opts.get("can_overhang", true)),
	}
	if not stilts and hmax - hmin > 0.12:
		# Plinth down to the lowest corner so the house does not float.
		mb.sink.box(Transform3D(basis, Vector3(center.x, (base_y + hmin) * 0.5 - 0.1, center.y)), Vector3(w + 0.04, base_y - hmin + 0.2, d + 0.04), "chb2", {"dirt": 1.0})
	mb.shanty(spec)
	L.reserve_rect(center, Vector2(w * 0.5, d * 0.5), rect_ang, 3)
	count += 1
	return true


func _style_dense() -> String:
	var r := rng.randf()
	if r < 0.32:
		return "wood"
	if r < 0.55:
		return "chb"
	if r < 0.72:
		return "patch"
	if r < 0.88:
		return "yero"
	return "bamboo"


func _floors_dense(density: float) -> int:
	var r := rng.randf()
	if r < 0.36 / density:
		return 1
	if r < 0.9:
		return 2
	return 3


# ------------------------------------------------------------------ dense looban

func _dense(D: Dictionary) -> void:
	var c: Vector2 = D.c
	var half: Vector2 = D.half
	var ang: float = D.ang
	var xa := Vector2(cos(ang), sin(ang))
	var za := Vector2(-sin(ang), cos(ang))
	var us := [-half.x]
	while us[-1] < half.x:
		us.append(us[-1] + rng.randf_range(16.0, 25.0))
	var vs := [-half.y]
	while vs[-1] < half.y:
		vs.append(vs[-1] + rng.randf_range(13.0, 21.0))
	var aw_u := []
	for i in us.size():
		aw_u.append(rng.randf_range(1.3, 2.4) if rng.randf() < 0.8 else rng.randf_range(2.8, 3.6))
	var aw_v := []
	for i in vs.size():
		aw_v.append(rng.randf_range(1.3, 2.4) if rng.randf() < 0.8 else rng.randf_range(2.8, 3.6))
	for i in us.size() - 1:
		for j in vs.size() - 1:
			var u0: float = us[i] + aw_u[i] * 0.5
			var u1: float = us[i + 1] - aw_u[i + 1] * 0.5
			var v0: float = vs[j] + aw_v[j] * 0.5
			var v1: float = vs[j + 1] - aw_v[j + 1] * 0.5
			# Occasionally merge: a block with no alley through it forces long detours.
			_fill_block(c, xa, za, u0, u1, v0, v1, D)


func _fill_block(c: Vector2, xa: Vector2, za: Vector2, u0: float, u1: float, v0: float, v1: float, D: Dictionary) -> void:
	var bv := v1 - v0
	var bu := u1 - u0
	if bu < 3.0 or bv < 3.0:
		return
	var depth := minf(rng.randf_range(4.2, 7.0), bv * 0.5 if bv > 9.0 else bv)
	var rows := [[v0, -1.0]]
	if bv > 9.0:
		rows.append([v1, 1.0])
	for row in rows:
		var edge: float = row[0]
		var face: float = row[1]  # -1: faces the alley at v0 (front toward -za)
		var u := u0
		while u < u1 - 2.8:
			var w := rng.randf_range(3.0, 6.2)
			if u + w > u1:
				w = u1 - u
				if w < 2.8:
					break
			var d := depth * rng.randf_range(0.82, 1.0)
			var setback := rng.randf_range(0.0, 0.35)
			var vc: float = edge - face * (d * 0.5 + setback)
			var uc := u + w * 0.5
			var center := c + xa * uc + za * vc
			var front := za * face
			# Slight misalignment: nothing in a looban is square.
			var jitter := rng.randf_range(-0.05, 0.05)
			front = front.rotated(jitter)
			if rng.randf() < 0.06:
				u += w + rng.randf_range(0.8, 1.6)  # a gap: someone's yard or a collapsed shack
				continue
			var front_kind := "door"
			if rng.randf() < 0.07:
				front_kind = "store"
			place(center, front, w - 0.1, d, {"floors": _floors_dense(float(D.density)), "style": _style_dense(), "front": front_kind,
				"kind": "store" if front_kind == "store" else "house", "district": D.name})
			u += w + rng.randf_range(0.0, 0.25)
	# Side lots along the u edges when the block is deep enough.
	if bv > 9.0 + 2.0 * depth * 0.5 and bu > 8.0:
		for side in [[u0, -1.0], [u1, 1.0]]:
			var v := v0 + depth + 0.3
			while v < v1 - depth - 2.8:
				var w2 := rng.randf_range(3.0, 5.0)
				var d2 := rng.randf_range(3.6, minf(5.6, bu * 0.4))
				var uc2: float = side[0] - side[1] * (d2 * 0.5 + 0.1)
				var center2 := c + xa * uc2 + za * (v + w2 * 0.5)
				place(center2, xa * side[1], w2 - 0.1, d2, {"floors": _floors_dense(float(D.density)), "style": _style_dense(), "district": D.name})
				v += w2 + 0.1


# ------------------------------------------------------------------ along the railway

func _rail(D: Dictionary) -> void:
	var x0: float = (D.c as Vector2).x - (D.half as Vector2).x
	var x1: float = (D.c as Vector2).x + (D.half as Vector2).x
	for side in [-1.0, 1.0]:
		var x := x0
		while x < x1:
			var w := rng.randf_range(3.0, 5.8)
			var d := rng.randf_range(3.8, 6.0)
			var z: float = L.rail_z(x + w * 0.5)
			var dz: float = L.rail_z(x + w * 0.5 + 1.0) - z
			var tang := Vector2(1.0, dz).normalized()
			var nrm = Vector2(-tang.y, tang.x) * side
			var off := rng.randf_range(3.0, 3.8) + d * 0.5
			var center = Vector2(x + w * 0.5, z) + nrm * off
			if rng.randf() > 0.08:
				place(center, -nrm, w - 0.1, d, {"floors": 1 if rng.randf() < 0.7 else 2, "style": _style_dense(), "district": D.name, "can_overhang": false})
			x += w + rng.randf_range(0.0, 0.6)


# ------------------------------------------------------------------ estero

func _creek(D: Dictionary) -> void:
	var x0: float = (D.c as Vector2).x - (D.half as Vector2).x
	var x1: float = minf((D.c as Vector2).x + (D.half as Vector2).x, L.estero[-1].x - 14.0)
	var deck: float = L.WATER_Y + 1.55
	for side in [-1.0, 1.0]:
		var x := x0
		var walk_pts := []
		while x < x1:
			var w := rng.randf_range(3.0, 5.4)
			var d := rng.randf_range(4.0, 6.0)
			var z: float = L.estero_z(x + w * 0.5)
			var dz: float = L.estero_z(x + w * 0.5 + 1.0) - z
			var tang := Vector2(1.0, dz).normalized()
			var nrm = Vector2(-tang.y, tang.x) * side
			# Walk 1.3 m wide on the bank edge; houses behind it facing the water.
			var off: float = L.estero_w * 0.5 + 1.5 + d * 0.5
			var center = Vector2(x + w * 0.5, z) + nrm * off
			if rng.randf() > 0.07:
				place(center, -nrm, w - 0.1, d, {"floors": 2 if rng.randf() < 0.6 else 1, "style": _style_dense(), "district": D.name,
					"stilts": true, "deck_y": deck, "allow_water": true})
			walk_pts.append(Vector2(x + w * 0.5, z) + nrm * (L.estero_w * 0.5 + 0.7))
			x += w + rng.randf_range(0.0, 0.3)
		_boardwalk(walk_pts, 1.3, deck - 0.05)


func _boardwalk(pts: Array, width: float, y: float) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := b - a
		var len := seg.length()
		if len < 0.2 or len > 9.0:
			continue
		var ang := atan2(-seg.y, seg.x)
		var basis := Basis(Vector3.UP, ang)
		var mid := (a + b) * 0.5
		var n := int(len / 0.24)
		for k in n:
			var p := a + seg * ((k + 0.5) / n)
			var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.03, 0.03))
			mb.sink.box(Transform3D(basis * Basis(Vector3.UP, PI * 0.5) * tilt, Vector3(p.x, y + rng.randf_range(-0.015, 0.015), p.y)),
				Vector3(width + rng.randf_range(-0.1, 0.1), 0.04, 0.2), "planks", {"dirt": 0.8, "collide": false, "layer": "ext"})
		mb.sink.col_box(Transform3D(basis, Vector3(mid.x, y - 0.02, mid.y)), Vector3(len + 0.1, 0.08, width), "wood")
		# Posts every couple of metres down to the bed.
		var g: float = L.ground_height(mid.x, mid.y)
		var ph := y - g + 0.3
		if ph > 0.3:
			for sgn in [-1.0, 1.0]:
				var off = Vector2(-seg.y, seg.x).normalized() * width * 0.45 * sgn
				mb.sink.box(Transform3D(Basis(), Vector3(a.x + off.x, y - ph * 0.5, a.y + off.y)), Vector3(0.09, ph, 0.09), "timber", {"dirt": 1.0, "collide": false})


# ------------------------------------------------------------------ river banks

func _river_bank(D: Dictionary) -> void:
	var side := float(D.side)
	var z := float(D.z0)
	var deck: float = L.WATER_Y + 1.6
	var walk_pts := []
	while z < float(D.z1):
		var w := rng.randf_range(3.2, 5.6)
		var d := rng.randf_range(4.2, 6.2)
		var cx: float = L.river_x(z + w * 0.5)
		var hw: float = L.river_hw(z + w * 0.5)
		var dx: float = L.river_x(z + w * 0.5 + 1.0) - cx
		var tang := Vector2(dx, 1.0).normalized()
		var nrm := Vector2(tang.y, -tang.x) * side
		if nrm.x * side < 0:
			nrm = -nrm
		var off := hw + 0.4 + d * 0.5
		var center := Vector2(cx, z + w * 0.5) + nrm * off
		if rng.randf() > 0.08:
			place(center, -nrm, w - 0.1, d, {"floors": 2 if rng.randf() < 0.55 else 1, "style": _style_dense(), "district": D.name,
				"stilts": true, "deck_y": deck, "allow_water": true})
		walk_pts.append(Vector2(cx, z + w * 0.5) + nrm * (hw - 0.6))
		z += w + rng.randf_range(0.0, 0.4)
	_boardwalk(walk_pts, 1.4, deck - 0.05)


# ------------------------------------------------------------------ mixed (Kalinaw Proper)

func _mixed(D: Dictionary) -> void:
	var c: Vector2 = D.c
	var half: Vector2 = D.half
	var ang: float = D.ang
	var xa := Vector2(cos(ang), sin(ang))
	var za := Vector2(-sin(ang), cos(ang))
	var v := -half.y
	while v < half.y - 8.0:
		var depth := rng.randf_range(7.0, 10.0)
		for face in [-1.0, 1.0]:
			var u := -half.x
			while u < half.x - 5.0:
				var w := rng.randf_range(5.5, 9.0)
				var dd := depth * rng.randf_range(0.75, 0.95)
				var vc := v + (dd * 0.5 + 0.6 if face < 0 else depth * 2.0 + 0.6 - dd * 0.5)
				var center := c + xa * (u + w * 0.5) + za * vc
				var style := "chb" if rng.randf() < 0.55 else ("concrete" if rng.randf() < 0.6 else "wood")
				place(center, za * face, w - 0.6, dd, {"floors": 1 if rng.randf() < 0.45 else 2, "style": style, "district": D.name,
					"front": "store" if rng.randf() < 0.08 else "door"})
				u += w + rng.randf_range(0.3, 1.5)
		v += depth * 2.0 + rng.randf_range(4.0, 5.0)  # a street between double rows


# ------------------------------------------------------------------ fishing village

func _fishing(D: Dictionary) -> void:
	var x0: float = (D.c as Vector2).x - (D.half as Vector2).x
	var x1: float = (D.c as Vector2).x + (D.half as Vector2).x
	var deck: float = L.WATER_Y + 1.7
	var x := x0
	while x < x1:
		var cz: float = L.coast_z(x)
		# Houses on the beach behind the coastal road.
		var w := rng.randf_range(3.5, 5.5)
		var d := rng.randf_range(4.0, 5.5)
		place(Vector2(x, cz - 24.0), Vector2(0, -1), w, d, {"floors": 1, "style": "wood" if rng.randf() < 0.6 else "bamboo", "district": D.name})
		x += w + rng.randf_range(0.5, 3.0)
	# Piers with stilt houses over the water.
	var px := x0 + 20.0
	while px < x1 - 10.0:
		var cz2: float = L.coast_z(px)
		var pts := []
		var length := rng.randf_range(36.0, 60.0)
		var zz := cz2 - 8.0
		while zz < cz2 + length:
			pts.append(Vector2(px + sin(zz * 0.07) * 1.5, zz))
			zz += 3.0
		_boardwalk(pts, 1.5, deck - 0.05)
		var zh := cz2 + 4.0
		while zh < cz2 + length - 4.0:
			for side in [-1.0, 1.0]:
				if rng.randf() < 0.8:
					var w2 := rng.randf_range(3.2, 5.0)
					var d2 := rng.randf_range(3.8, 5.0)
					place(Vector2(px + side * (0.75 + 0.2 + d2 * 0.5), zh + w2 * 0.5), Vector2(-side, 0), w2, d2,
						{"floors": 1, "style": "bamboo" if rng.randf() < 0.4 else "wood", "district": D.name, "stilts": true, "deck_y": deck, "allow_water": true})
			zh += rng.randf_range(5.0, 7.0)
		px += rng.randf_range(34.0, 52.0)


# ------------------------------------------------------------------ workshops, subdivision, highway, dump

func _workshops(D: Dictionary) -> void:
	var c: Vector2 = D.c
	var half: Vector2 = D.half
	var za := Vector2(-sin(D.ang), cos(D.ang))
	var xa := Vector2(cos(D.ang), sin(D.ang))
	var v := -half.y
	while v < half.y:
		var u := -half.x
		while u < half.x:
			var w := rng.randf_range(6.0, 10.0)
			var d := rng.randf_range(6.0, 9.0)
			place(c + xa * (u + w * 0.5) + za * (v + d * 0.5), Vector2(-1, 0).rotated(D.ang) if rng.randf() < 0.0 else -za, w, d,
				{"floors": 1, "style": "yero" if rng.randf() < 0.6 else "chb", "front": "open", "kind": "workshop", "district": D.name, "can_overhang": false})
			u += w + rng.randf_range(1.0, 3.0)
		v += rng.randf_range(14.0, 18.0)


func _subdivision(D: Dictionary) -> void:
	var c: Vector2 = D.c
	var half: Vector2 = D.half
	var v := -half.y
	while v < half.y - 10.0:
		for face in [-1.0, 1.0]:
			var u := -half.x
			while u < half.x - 9.0:
				var w := rng.randf_range(8.0, 10.0)
				var d := rng.randf_range(8.0, 9.5)
				var vc := v + (d * 0.5 + 3.0 if face < 0 else 26.0 - d * 0.5)
				place(c + Vector2(u + w * 0.5, vc), Vector2(0, face), w, d, {"floors": 2, "style": "concrete", "district": D.name, "can_overhang": false})
				u += w + rng.randf_range(2.0, 4.0)
		v += 32.0


func _under_highway(D: Dictionary) -> void:
	var z: float = (D.c as Vector2).y - (D.half as Vector2).y
	var z1: float = (D.c as Vector2).y + (D.half as Vector2).y
	while z < z1:
		var w := rng.randf_range(3.0, 5.0)
		var d := rng.randf_range(3.5, 5.0)
		if rng.randf() < 0.7:
			for side in [-1.0, 1.0]:
				if rng.randf() < 0.6:
					place(Vector2(L.highway_x + side * (2.6 + d * 0.5), z + w * 0.5), Vector2(-side, 0), w - 0.1, d,
						{"floors": 1, "style": "patch" if rng.randf() < 0.5 else "yero", "district": D.name, "can_overhang": false})
		z += w + rng.randf_range(0.2, 6.0)


func _dump(D: Dictionary) -> void:
	var c: Vector2 = D.c
	for i in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(50.0, 95.0)
		var p := c + Vector2(cos(a), sin(a)) * r
		place(p, (c - p).normalized() * -1.0, rng.randf_range(3.0, 4.5), rng.randf_range(3.0, 4.5),
			{"floors": 1, "style": "patch", "district": D.name, "can_overhang": false})
