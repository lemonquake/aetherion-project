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
##
## r3 additions: narrow lanes in the dense districts are roofed over in runs (lagusan: tunnels lined with house
## fronts, see lagusan.gd), some blocks are left open as loobans (courtyards with vault cover, see looban.gd), some
## lanes are cut by junk barricades you vault, concrete houses get flat roof decks (many with a ladder), neighbours
## knock crawl-through holes into each other's houses, and stretches of the estero boardwalk are roofed over.

var mb = null  # MapBuilder
var L = null   # Layout
var rng := RandomNumberGenerator.new()
var count := 0


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	rng.seed = L.rng.seed + 101


func build_all(only: Array = []) -> void:
	var di := 0
	for d in L.districts:
		di += 1
		if not only.is_empty() and not (d.name in only):
			continue
		if Game.loading_screen:
			Game.load_progress(lerpf(0.16, 0.7, float(di - 1) / maxf(L.districts.size(), 1)), "Building %s (%d of %d)" % [str(d.name).capitalize(), di, L.districts.size()])
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
	var fp: Vector2 = center + front2d.normalized() * (d * 0.5 + 0.45)
	var spec := {
		"xf": Transform3D(basis, Vector3(center.x, base_y, center.y)), "w": w, "d": d,
		"floors": int(opts.get("floors", 1)), "style": str(opts.get("style", "wood")), "kind": str(opts.get("kind", "house")),
		"stilts": stilts, "ground_y": hmin, "front": str(opts.get("front", "door")), "seed": rng.randi(),
		"district": str(opts.get("district", "")), "can_overhang": bool(opts.get("can_overhang", true)),
		"covered": bool(opts.get("covered", false)), "roof_deck": bool(opts.get("roof_deck", false)), "ladder": bool(opts.get("ladder", false)),
		"parapet": bool(opts.get("parapet", true)), "side_holes": opts.get("side_holes", []), "back_blocked": bool(opts.get("back_blocked", false)),
		"front_lane_w": float(opts.get("front_lane_w", 9.0)),
		"front_gy": float(opts.get("deck_y", -INF)) if stilts else L.ground_height(fp.x, fp.y),
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
	## About a fifth of a dense looban is three storeys: rooms added on top as families grow.
	var r := rng.randf()
	if r < 0.28 / density:
		return 1
	if r < 0.78:
		return 2
	return 3


func _deck_opts(style: String, floors: int, covered: bool, opts: Dictionary) -> Dictionary:
	## Hollow-block and concrete houses often have a flat slab roof people use; most of those have a ladder up the
	## front (not under a lane roof, and not three storeys up).
	if covered or not (style in ["chb", "concrete"]) or rng.randf() > 0.34:
		return opts
	opts.roof_deck = true
	opts.ladder = floors <= 2 and rng.randf() < 0.72
	return opts


# ------------------------------------------------------------------ dense looban

func _dense(D: Dictionary) -> void:
	var c: Vector2 = D.c
	var half: Vector2 = D.half
	var ang: float = D.ang
	var xa := Vector2(cos(ang), sin(ang))
	var za := Vector2(-sin(ang), cos(ang))
	var us := [-half.x]
	while us[-1] < half.x:
		us.append(us[-1] + rng.randf_range(14.0, 22.0))
	var vs := [-half.y]
	while vs[-1] < half.y:
		vs.append(vs[-1] + rng.randf_range(11.0, 17.0))
	var aw_u := []
	for i in us.size():
		aw_u.append(rng.randf_range(1.2, 2.0) if rng.randf() < 0.8 else rng.randf_range(2.6, 3.4))
	var aw_v := []
	for i in vs.size():
		aw_v.append(rng.randf_range(1.2, 2.0) if rng.randf() < 0.8 else rng.randf_range(2.6, 3.4))
	for i in us.size():
		var a: Vector2 = c + xa * float(us[i]) + za * (-half.y)
		var b: Vector2 = c + xa * float(us[i]) + za * half.y
		mb.alleys.append({"a": a, "b": b, "w": float(aw_u[i]), "kind": "alley"})
	for j in vs.size():
		var a2: Vector2 = c + xa * (-half.x) + za * float(vs[j])
		var b2: Vector2 = c + xa * half.x + za * float(vs[j])
		mb.alleys.append({"a": a2, "b": b2, "w": float(aw_v[j]), "kind": "alley"})
	# Lagusan: stretches of the narrow lanes roofed over from house to house, in runs of one to four blocks.
	var covered := {}
	for j in range(1, vs.size() - 1):
		if float(aw_v[j]) > 2.25:
			continue
		var run := 0
		for i in us.size() - 1:
			var p := (0.2 if run == 0 else 0.6) * float(D.density)
			if run < 4 and rng.randf() < p:
				covered[Vector2i(i, j)] = true
				run += 1
			else:
				run = 0
	for key in covered:
		var i: int = key.x
		var j: int = key.y
		var ua: float = us[i] + aw_u[i] * 0.5
		var ub: float = us[i + 1] - aw_u[i + 1] * 0.5
		mb.tunnels.append({"a": c + xa * ua + za * float(vs[j]), "b": c + xa * ub + za * float(vs[j]), "w": float(aw_v[j]), "kind": "lane", "district": D.name})
	for i in us.size() - 1:
		for j in vs.size() - 1:
			var u0: float = us[i] + aw_u[i] * 0.5
			var u1: float = us[i + 1] - aw_u[i + 1] * 0.5
			var v0: float = vs[j] + aw_v[j] * 0.5
			var v1: float = vs[j + 1] - aw_v[j + 1] * 0.5
			# A few blocks stay open: the looban, where the neighbourhood washes, plays and argues.
			if u1 - u0 > 9.0 and v1 - v0 > 8.0 and not covered.has(Vector2i(i, j)) and not covered.has(Vector2i(i, j + 1)) \
					and rng.randf() < 0.075:
				mb.loobans.append({"c": c + xa * ((u0 + u1) * 0.5) + za * ((v0 + v1) * 0.5), "half": Vector2((u1 - u0) * 0.5, (v1 - v0) * 0.5),
					"ang": ang, "district": D.name})
				continue
			_fill_block(c, xa, za, u0, u1, v0, v1, D, covered.has(Vector2i(i, j)), covered.has(Vector2i(i, j + 1)), float(aw_v[j]), float(aw_v[j + 1]))
	# Junk barricades across some open lanes: vault them, or go round.
	for j in range(1, vs.size() - 1):
		for i in us.size() - 1:
			if covered.has(Vector2i(i, j)) or rng.randf() > 0.07:
				continue
			var ua2: float = us[i] + aw_u[i] * 0.5 + 1.5
			var ub2: float = us[i + 1] - aw_u[i + 1] * 0.5 - 1.5
			if ub2 <= ua2:
				continue
			var t := rng.randf_range(ua2, ub2)
			mb.barricades.append({"c": c + xa * t + za * float(vs[j]), "along": xa, "w": float(aw_v[j]), "district": D.name})


func _fill_block(c: Vector2, xa: Vector2, za: Vector2, u0: float, u1: float, v0: float, v1: float, D: Dictionary,
		cov0: bool = false, cov1: bool = false, lane0: float = 9.0, lane1: float = 9.0) -> void:
	var bv := v1 - v0
	var bu := u1 - u0
	if bu < 3.0 or bv < 3.0:
		return
	# Two rows back to back fill the block; now and then a small looban (courtyard) is left in the middle.
	var courtyard := rng.randf() < 0.1 and bv > 12.0
	var depth := bv * 0.5 - (rng.randf_range(1.5, 2.5) if courtyard else 0.05)
	if bv < 8.0:
		depth = bv
	depth = minf(depth, 8.5)
	var rows := [[v0, -1.0]]
	if bv >= 8.0:
		rows.append([v1, 1.0])
	for row in rows:
		var edge: float = row[0]
		var face: float = row[1]  # -1: faces the alley at v0 (front toward -za)
		var row_cov: bool = cov0 if face < 0.0 else cov1
		var u := u0
		var hole_p := Vector2.INF   # a hole knocked through from the previous house, at this world point
		while u < u1 - 2.8:
			var w := rng.randf_range(3.0, 5.6)
			if u + w > u1:
				w = u1 - u
				if w < 2.8:
					break
			var d := depth * rng.randf_range(0.9, 1.0)
			var setback := rng.randf_range(0.0, 0.2)
			if not row_cov and d > 4.6 and rng.randf() < 0.18:
				# Set back from the lane: a stoop, a bench, a strip of yard. The lane's edge is never a straight line.
				setback = rng.randf_range(0.5, 1.0)
				d -= setback   # shallower, so its back stays on the block's middle line (no overlap with the house behind)
			var vc: float = edge - face * (d * 0.5 + setback)
			var uc := u + w * 0.5
			var center := c + xa * uc + za * vc
			var front := za * face
			# Slight misalignment: nothing in a looban is square.
			var jitter := rng.randf_range(-0.05, 0.05)
			front = front.rotated(jitter)
			if rng.randf() < 0.03:
				u += w + rng.randf_range(0.8, 1.6)  # a gap: someone's yard or a collapsed shack
				hole_p = Vector2.INF
				continue
			var front_kind := "door"
			if rng.randf() < 0.07:
				front_kind = "store"
			var floors := _floors_dense(float(D.density))
			var style := _style_dense()
			var opts := {"floors": floors, "style": style, "front": front_kind,
				"kind": "store" if front_kind == "store" else "house", "district": D.name, "covered": row_cov,
				# Two rows back to back: the back wall stands against the house behind (no back door into it).
				"back_blocked": bv >= 8.0 and not courtyard, "front_lane_w": lane0 if face < 0.0 else lane1}
			_deck_opts(style, floors, row_cov, opts)
			var holes := []
			if hole_p != Vector2.INF:
				holes.append(hole_p)
			var next_hole := Vector2.INF
			if rng.randf() < 0.2:
				# Through the wall into the next house down the row, in the front room.
				next_hole = c + xa * (u + w) + za * (edge - face * (minf(d, 6.0) * 0.32 + setback))
				holes.append(next_hole)
			opts.side_holes = holes
			if not place(center, front, w - 0.1, d, opts):
				next_hole = Vector2.INF
			hole_p = next_hole
			u += w + rng.randf_range(0.0, 0.12)
	# Side lots along the u edges when the block is deep enough.
	if courtyard and bu > 8.0:
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
		var cov_run := 0
		var cov_start := Vector2.INF
		var prev_walk := Vector2.INF
		while x < x1:
			var w := rng.randf_range(3.0, 5.4)
			var d := rng.randf_range(4.0, 6.0)
			var z: float = L.estero_z(x + w * 0.5)
			var dz: float = L.estero_z(x + w * 0.5 + 1.0) - z
			var tang := Vector2(1.0, dz).normalized()
			var nrm = Vector2(-tang.y, tang.x) * side
			# Walk 1.3 m wide on the bank edge; houses behind it facing the water. Stretches of it run under the
			# houses' own roofs, extended out over the walk: a dark arcade along the water.
			var cov := rng.randf() < (0.62 if cov_run > 0 else 0.22) and cov_run < 7
			var off: float = L.estero_w * 0.5 + 1.5 + d * 0.5
			var center = Vector2(x + w * 0.5, z) + nrm * off
			if rng.randf() > 0.07:
				place(center, -nrm, w - 0.1, d, {"floors": 2 if rng.randf() < 0.6 else 1, "style": _style_dense(), "district": D.name,
					"stilts": true, "deck_y": deck, "allow_water": true, "covered": cov})
			var wp: Vector2 = Vector2(x + w * 0.5, z) + nrm * (L.estero_w * 0.5 + 0.78)
			walk_pts.append(wp)
			if cov:
				if cov_run == 0:
					cov_start = Vector2(x, L.estero_z(x)) + nrm * (L.estero_w * 0.5 + 0.7)
				cov_run += 1
			elif cov_run > 0:
				mb.tunnels.append({"a": cov_start, "b": Vector2(x, L.estero_z(x)) + nrm * (L.estero_w * 0.5 + 0.7), "w": 1.3, "kind": "walk",
					"y": deck, "house_side": nrm, "district": D.name})
				cov_run = 0
			x += w + rng.randf_range(0.0, 0.3)
		if cov_run > 0:
			mb.tunnels.append({"a": cov_start, "b": Vector2(x, L.estero_z(x) + side * (L.estero_w * 0.5 + 0.7)),
				"w": 1.3, "kind": "walk", "y": deck, "house_side": Vector2(0, side), "district": D.name})
		# Wide enough to reach the house fronts (it stopped 15-40 cm short of the doors, over the water).
		_boardwalk(walk_pts, 1.5, deck - 0.05)
		for k in range(0, walk_pts.size() - 1, 3):
			mb.alleys.append({"a": walk_pts[k], "b": walk_pts[mini(k + 3, walk_pts.size() - 1)], "w": 1.3, "kind": "walk", "y": deck})


func _boardwalk(pts: Array, width: float, y: float) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := b - a
		var len := seg.length()
		if len < 0.2 or len > 13.0:
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
		walk_pts.append(Vector2(cx, z + w * 0.5) + nrm * (hw - 0.5))
		z += w + rng.randf_range(0.0, 0.4)
	# Up to the house fronts (they stand 0.4 m back from the bank's edge: the doors opened on to the river).
	_boardwalk(walk_pts, 1.9, deck - 0.05)
	for k in range(0, walk_pts.size() - 1, 3):
		mb.alleys.append({"a": walk_pts[k], "b": walk_pts[mini(k + 3, walk_pts.size() - 1)], "w": 1.4, "kind": "walk", "y": deck})


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
				var fl := 1 if rng.randf() < 0.4 else (2 if rng.randf() < 0.8 else 3)
				var mopts := {"floors": fl, "style": style, "district": D.name, "front": "store" if rng.randf() < 0.08 else "door"}
				_deck_opts(style, fl, false, mopts)
				if place(center, za * face, w - 0.6, dd, mopts) and rng.randf() < 0.45:
					# A hip-high front wall round the yard, with a gap for the gate: cover you can vault.
					mb.yard_walls.append({"c": center + za * face * (dd * 0.5 + 0.55), "along": xa, "len": w - 0.7, "district": D.name})
				u += w + rng.randf_range(0.3, 1.5)
		var sv := v + depth * 2.0 + 2.2
		mb.alleys.append({"a": c + xa * (-half.x) + za * sv, "b": c + xa * half.x + za * sv, "w": 4.0, "kind": "street"})
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
		var r := rng.randf_range(0.64, 1.22) * float(L.dump_r)
		var p := c + Vector2(cos(a), sin(a)) * r
		place(p, (c - p).normalized() * -1.0, rng.randf_range(3.0, 4.5), rng.randf_range(3.0, 4.5),
			{"floors": 1, "style": "patch", "district": D.name, "can_overhang": false})
