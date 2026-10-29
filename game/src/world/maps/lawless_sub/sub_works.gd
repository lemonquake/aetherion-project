extends RefCounted
## Lawless Sub's civil works: the canal and basin walls with the walk and planter strip along them, ladders down
## to the water, the culvert headwall at the estero's end, the bridges (road decks with parapets, the steel
## footbridge, the pipe crossing), the subdivision walls with their breaches, collapsed stretch and arch gate, and
## the map's edge: a perimeter wall with the city beyond it.

const StreetDetail := preload("res://src/world/maps/lawless_sub/street_detail.gd")

var mb = null
var L = null
var sink = null
var rng := RandomNumberGenerator.new()
var _pilasters := {}
var stats := {"wall_boxes": 0, "apron_boxes": 0, "ladders": 0, "bridges": 0, "panels": 0, "backdrop": 0}


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	sink = mb.sink
	rng.seed = L.rng.seed + 1301


func build() -> void:
	for k in L.water_polys.size():
		_canal_walls(k)
	_ladders()
	_culvert_heads()
	for b in L.bridges:
		match str(b.type):
			"road_bridge":
				_road_bridge(b)
			"footbridge":
				_footbridge(b)
			"pipe":
				_pipe_crossing(b)
		stats.bridges += 1
	for w in L.walls:
		_wall(w)
	_gate(L.plan.get("gate", {}))
	_perimeter()
	_backdrop()
	var detail := StreetDetail.new(mb)
	detail.build()
	stats.detail = detail.stats


# ------------------------------------------------------------------ canals

func _canal_walls(k: int) -> void:
	var wp: Dictionary = L.water_polys[k]
	var pts: PackedVector2Array = wp.pts
	var n := pts.size()
	var area := 0.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var orient := signf(area)
	var bed: float = float(wp.bed) - 0.25
	var top_wall: float = L.LAND_Y + L.WALL_TOP
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var len := a.distance_to(b)
		if len < 0.05:
			continue
		var d := (b - a) / len
		var nrm := Vector2(-d.y, d.x)
		var mid := (a + b) * 0.5
		if L._inside(mid + nrm * 0.3, pts):
			nrm = -nrm
		# Off the map: no wall.
		if absf(mid.x) > L.HALF + 2.0 or absf(mid.y) > L.HALF + 2.0:
			continue
		var prev := pts[(i - 1 + n) % n]
		var nxt := pts[(i + 2) % n]
		var convex_a := signf((a - prev).cross(d)) == orient
		var convex_b := signf(d.cross(nxt - b)) == orient
		var ext_a = L.WALL_T if convex_a else 0.0
		var ext_b = L.WALL_T if convex_b else 0.0
		var ang := atan2(-d.y, d.x)
		var basis := Basis(Vector3.UP, ang)   # local x along the edge
		# The wall: its face to the water, its coping flush with the walk.
		var wl = len + ext_a + ext_b
		var wc = mid + d * (ext_b - ext_a) * 0.5 + nrm * L.WALL_T * 0.5
		var wh := top_wall - bed
		var lz := Vector3(nrm.x, 0, nrm.y)   # world outward
		sink.box(Transform3D(basis, Vector3(wc.x, bed + wh * 0.5, wc.y)), Vector3(wl, wh, L.WALL_T), "canal_wall",
			{"faces": 55, "dirt": 0.75, "occlude": true, "what": "canal_wall", "base_y": L.WATER_Y - 0.3})
		stats.wall_boxes += 1
		# The walk (pavers) then the planter strip (grass), both down to the bed so the terrain's ramp stays hidden.
		var alt := 0.003 * float(i % 2)
		var walk_w := 2.6
		var ext2 = L.APRON if convex_b else 0.0
		for part in [[L.WALL_T, L.WALL_T + walk_w, "pavers"], [L.WALL_T + walk_w, L.APRON, "lawn_leafy"]]:
			var o0: float = part[0]
			var o1: float = part[1]
			var top: float = L.LAND_Y + L.APRON_TOP + alt + (0.06 if part[2] == "lawn_leafy" else 0.0)
			var pl = len + ext2
			var pc = mid + d * ext2 * 0.5 + nrm * (o0 + o1) * 0.5
			# Where a road or a bridge crosses the walk, the road surface is the walk: a strip under it lay in the same
			# plane as the asphalt (the planter's grass showed through at both ends of the Canal Bridge).
			for run in _uncovered(pc - d * pl * 0.5, d, pl, nrm * (o1 - o0) * 0.5):
				var rc: Vector2 = pc + d * ((float(run[0]) + float(run[1])) * 0.5 - pl * 0.5)
				sink.box(Transform3D(basis, Vector3(rc.x, (top + bed) * 0.5, rc.y)), Vector3(float(run[1]) - float(run[0]), top - bed, o1 - o0), str(part[2]),
					{"faces": 4 if part[2] == "pavers" else 1 | 2 | 4 | _face_toward(basis, lz), "dirt": 0.4, "phys": "concrete" if part[2] == "pavers" else "dirt", "what": "canal_walk"})
				stats.apron_boxes += 1
		# The planter's low kerb on the walk side (not across a road either).
		var kc = mid + d * ext2 * 0.5 + nrm * (L.WALL_T + walk_w)
		for run in _uncovered(kc - d * (len + ext2) * 0.5, d, len + ext2, Vector2.ZERO):
			var kr: Vector2 = kc + d * ((float(run[0]) + float(run[1])) * 0.5 - (len + ext2) * 0.5)
			sink.box(Transform3D(basis, Vector3(kr.x, L.LAND_Y + 0.07, kr.y)), Vector3(float(run[1]) - float(run[0]), 0.16, 0.14), "concrete", {"faces": 55, "dirt": 0.6, "collide": false})
		mb.canal_edges.append({"a": a, "b": b, "n": nrm, "d": d, "len": len})


func _uncovered(start: Vector2, d: Vector2, length: float, half_across: Vector2) -> Array:
	## Runs [t0, t1] along a strip (from start, in direction d) that no road with its sidewalks, and no bridge, covers.
	var rects := []
	for rd in L.roads:
		rects.append(L.road_rect(rd, float(rd.w) * 0.5 + float(rd.sidewalk)))
	rects.append_array(L.bridge_rects)
	var out := []
	var run0 := -1.0
	var t := 0.0
	while t <= length + 0.125:
		var tt := minf(t, length)
		var p := start + d * tt
		var hit := false
		for r in rects:
			if (r as Rect2).has_point(p) or (r as Rect2).has_point(p + half_across) or (r as Rect2).has_point(p - half_across):
				hit = true
				break
		if not hit and run0 < 0.0:
			run0 = tt
		elif hit and run0 >= 0.0:
			if tt - run0 > 0.05:
				out.append([run0, tt])
			run0 = -1.0
		t += 0.25
	if run0 >= 0.0 and length - run0 > 0.05:
		out.append([run0, length])
	return out


func _face_toward(basis: Basis, world_dir: Vector3) -> int:
	## The box face bit (+z 16 or -z 32) whose normal points along world_dir.
	return 16 if (basis * Vector3(0, 0, 1)).dot(world_dir) > 0.0 else 32


func _ladders() -> void:
	for s in L.ladder_spots:
		var x := float(s[0])
		var z := float(s[1])
		var dir := float(s[2])
		var n := Vector3(dir, 0, 0)
		var face := Vector3(x, 0, z)
		var foot_y: float = L.terrain_height(x + dir * 0.42, z)
		var top_y: float = L.LAND_Y + L.WALL_TOP
		var hgt := top_y + 0.9 - foot_y
		var side := Vector3(0, 0, 1)
		for sx in [-0.22, 0.22]:
			sink.box(Transform3D(Basis(), face + n * 0.09 + side * sx + Vector3(0, foot_y + hgt * 0.5, 0)), Vector3(0.05, hgt, 0.05), "metal_paint",
				{"dirt": 0.5, "collide": false, "tint": Color(0.75, 0.62, 0.2), "paint": 0.7})
		var y := foot_y + 0.3
		while y < top_y + 0.8:
			sink.box(Transform3D(Basis(), face + n * 0.09 + Vector3(0, y, 0)), Vector3(0.035, 0.035, 0.44), "metal_paint", {"dirt": 0.5, "collide": false})
			y += 0.3
		mb.ladders.append({"base": face + n * 0.42 + Vector3(0, foot_y, 0), "top_y": top_y, "n": n, "w": 0.5})
		stats.ladders += 1


func _culvert_heads() -> void:
	## A concrete headwall where the estero runs out of its culvert at the subdivision wall.
	for e in L.esteros:
		var a: Vector2 = e.a
		var hw: float = float(e.hw) + float(e.bank)
		var c := Vector2(a.x - 2.0, a.y)
		var bot: float = float(e.bed) - 0.3
		var top: float = L.LAND_Y + 0.35
		sink.box(Transform3D(Basis(), Vector3(c.x, (top + bot) * 0.5, c.y)), Vector3(1.0, top - bot, hw * 2.0 + 1.0), "concrete_dirty", {"dirt": 0.9, "occlude": true})
		# The pipe's mouth: a dark disc in the wall.
		sink.cylinder(Vector3(c.x + 0.52, float(e.bed) + 0.85, c.y), Vector3(1, 0, 0), 0.02, 0.8, "black", {"sides": 12})


# ------------------------------------------------------------------ bridges

func _road_for(name: String) -> Dictionary:
	for rd in L.roads:
		if str(rd.name) == name:
			return rd
	return {}


func _road_bridge(b: Dictionary) -> void:
	var r: Rect2 = b.rect
	var rd := _road_for(str(b.get("road", "")))
	if rd.is_empty():
		return
	var axis := int(rd.axis)
	var y0: float = L.LAND_Y
	var road_top: float = y0 + L.ROAD_TOP
	var c := r.get_center()
	# Structural slab, then the wearing course on top (the road's own surface).
	sink.box(Transform3D(Basis(), Vector3(c.x, y0 - 0.35, c.y)), Vector3(r.size.x, 0.6 + L.ROAD_TOP - 0.01, r.size.y), "concrete",
		{"faces": 55, "dirt": 0.7, "occlude": false, "what": "bridge"})
	var hw := float(rd.w) * 0.5
	var p0: Vector3
	var p1: Vector3
	var p2: Vector3
	var p3: Vector3
	if axis == 0:
		p0 = Vector3(r.position.x, road_top, float(rd.c) - hw)
		p1 = Vector3(r.end.x, road_top, float(rd.c) - hw)
		p2 = Vector3(r.end.x, road_top, float(rd.c) + hw)
		p3 = Vector3(r.position.x, road_top, float(rd.c) + hw)
	else:
		p0 = Vector3(float(rd.c) - hw, road_top, r.position.y)
		p1 = Vector3(float(rd.c) + hw, road_top, r.position.y)
		p2 = Vector3(float(rd.c) + hw, road_top, r.end.y)
		p3 = Vector3(float(rd.c) - hw, road_top, r.end.y)
	sink.quad(p0, p1, p2, p3, str(rd.mat), {"collide": true, "phys": "concrete", "dirt": 0.3, "facing": Vector3.UP, "what": "bridge_deck"})
	# Raised walks on the deck and parapets at its outer edges.
	var sw := float(rd.sidewalk)
	for side in [-1.0, 1.0]:
		if sw > 0.0:
			var oc = float(rd.c) + side * (hw + sw * 0.5)
			var wc := Vector3(c.x, y0 + L.WALK_TOP * 0.5, oc) if axis == 0 else Vector3(oc, y0 + L.WALK_TOP * 0.5, c.y)
			var wsz := Vector3(r.size.x, L.WALK_TOP, sw) if axis == 0 else Vector3(sw, L.WALK_TOP, r.size.y)
			sink.box(Transform3D(Basis(), wc), wsz, "sidewalk", {"faces": 55, "dirt": 0.4, "phys": "concrete", "what": "bridge_walk"})
		var po = float(rd.c) + side * (hw + sw + 0.15)
		var ptop = y0 + L.WALK_TOP + 1.05
		var pbot := y0 - 0.65
		var pc := Vector3(c.x, (ptop + pbot) * 0.5, po) if axis == 0 else Vector3(po, (ptop + pbot) * 0.5, c.y)
		var psz := Vector3(r.size.x, ptop - pbot, 0.3) if axis == 0 else Vector3(0.3, ptop - pbot, r.size.y)
		sink.box(Transform3D(Basis(), pc), psz, "concrete", {"dirt": 0.8, "occlude": true, "tint": Color(0.86, 0.85, 0.8), "paint": 0.4, "what": "parapet"})


func _footbridge(b: Dictionary) -> void:
	var a: Vector2 = b.a
	var e: Vector2 = b.b
	var w := float(b.get("w", 2.2))
	var len := a.distance_to(e)
	var d := (e - a) / len
	var basis := Basis(Vector3.UP, atan2(-d.y, d.x))
	var c := (a + e) * 0.5
	var top: float = L.LAND_Y + 0.22
	sink.box(Transform3D(basis, Vector3(c.x, top - 0.12, c.y)), Vector3(len, 0.24, w), "metal_plate", {"dirt": 0.5, "phys": "steel", "what": "footbridge"})
	var side := Vector2(-d.y, d.x)
	for s in [-1.0, 1.0]:
		var rc = c + side * s * (w * 0.5 - 0.04)
		sink.box(Transform3D(basis, Vector3(rc.x, top + 1.0, rc.y)), Vector3(len, 0.06, 0.06), "metal_paint", {"tint": Color(0.2, 0.42, 0.3), "paint": 0.8, "collide": false})
		sink.col_box(Transform3D(basis, Vector3(rc.x, top + 0.55, rc.y)), Vector3(len, 1.1, 0.08), "steel", "rail")
		var k := 0.0
		while k <= len:
			var pp = a + d * k + side * s * (w * 0.5 - 0.04)
			sink.box(Transform3D(basis, Vector3(pp.x, top + 0.5, pp.y)), Vector3(0.05, 1.0, 0.05), "metal_paint", {"tint": Color(0.2, 0.42, 0.3), "paint": 0.8, "collide": false})
			k += 1.6
	# Abutment steps are not needed: the deck is 0.2 m above the banks.


func _pipe_crossing(b: Dictionary) -> void:
	var a: Vector2 = b.a
	var e: Vector2 = b.b
	var len := a.distance_to(e)
	var d := (e - a) / len
	var y: float = L.LAND_Y + 0.1
	for s in [-0.42, 0.42]:
		var off = Vector2(-d.y, d.x) * s
		sink.cylinder(Vector3(a.x + off.x, y + 0.3, a.y + off.y), Vector3(d.x, 0, d.y), len, 0.3, "metal_rust", {"sides": 10, "collide": true, "phys": "steel"})
	# Saddles on the banks.
	for t in [0.06, 0.94]:
		var p := a.lerp(e, t)
		sink.box(Transform3D(Basis(Vector3.UP, atan2(-d.y, d.x)), Vector3(p.x, y - 0.1, p.y)), Vector3(0.6, 0.6, 1.6), "concrete_dirty", {"dirt": 0.9})


# ------------------------------------------------------------------ subdivision walls and gate

func _wall(w: Dictionary) -> void:
	var a: Vector2 = w.a
	var b: Vector2 = w.b
	var len := a.distance_to(b)
	var d := (b - a) / len
	var basis := Basis(Vector3.UP, atan2(-d.y, d.x))
	var h := float(w.get("h", 2.4))
	var panel := 3.0
	var n := maxi(int(round(len / panel)), 1)
	var pw := len / n
	var cream := Color(0.86, 0.83, 0.74)
	for i in n:
		var t0 := pw * i
		var t1 := pw * (i + 1)
		var tm := (t0 + t1) * 0.5
		var gap: String = L.wall_open_at(w, tm)
		var coord: float = L.wall_coord(w, tm)
		var collapsed := false
		for cs in w.get("collapsed", []):
			if coord >= minf(float(cs[0]), float(cs[1])) and coord <= maxf(float(cs[0]), float(cs[1])):
				collapsed = true
		var m := a + d * tm
		var g: float = L.ground_height(m.x, m.y)
		if gap != "":
			if gap == "breach":
				# Broken ends and rubble in the gap.
				_rubble(m, 1.2)
			continue
		var ph := h
		if collapsed:
			ph = rng.randf_range(0.55, 1.05)
			_rubble(m + Vector2(-d.y, d.x) * rng.randf_range(-1.5, 1.5), 1.0)
		sink.box(Transform3D(basis, Vector3(m.x, g - 0.2 + (ph + 0.2) * 0.5, m.y)), Vector3(pw, ph + 0.2, 0.2), "wall_grey",
			{"dirt": 0.8, "occlude": ph > 1.5, "tint": cream, "paint": 0.55, "what": "perimeter_wall"})
		stats.panels += 1
		# Pilaster at the panel's start (and the wall's end).
		for pt in ([t0, t1] if i == n - 1 else [t0]):
			var pp := a + d * float(pt)
			if L.wall_open_at(w, clampf(float(pt), 0.0, len)) != "" and not collapsed:
				continue
			# Walls share their corner points: one pilaster there (two identical boxes z-fight).
			var pk := Vector2i(roundi(pp.x * 10.0), roundi(pp.y * 10.0))
			if _pilasters.has(pk):
				continue
			_pilasters[pk] = true
			var gp: float = L.ground_height(pp.x, pp.y)
			var phh := (ph + 0.15) if not collapsed else ph
			sink.box(Transform3D(basis, Vector3(pp.x, gp - 0.2 + (phh + 0.2) * 0.5, pp.y)), Vector3(0.34, phh + 0.2, 0.34), "wall_grey",
				{"dirt": 0.8, "tint": cream, "paint": 0.55, "what": "perimeter_wall"})


func _rubble(p: Vector2, r: float) -> void:
	var g: float = L.ground_height(p.x, p.y)
	var name := "rubble_a" if rng.randf() < 0.5 else "rubble_b"
	mb.dyn.add_static_prop(name, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, g, p.y)))
	mb.obstacles_add(p, r)


func _gate(gt: Dictionary) -> void:
	if gt.is_empty():
		return
	var x := float(gt.x)
	var z := float(gt.z)
	var span := float(gt.get("span", 11))
	var g: float = L.ground_height(x, z)
	var cream := Color(0.9, 0.86, 0.76)
	for s in [-1.0, 1.0]:
		var pz = z + s * (span * 0.5 + 0.45)
		sink.box(Transform3D(Basis(), Vector3(x, g + 2.3, pz)), Vector3(0.9, 4.8, 0.9), "wall_painted", {"dirt": 0.6, "tint": cream, "paint": 0.7, "occlude": true, "what": "gate_pillar"})
		sink.box(Transform3D(Basis(), Vector3(x, g + 4.85, pz)), Vector3(1.1, 0.3, 1.1), "concrete", {"dirt": 0.6, "collide": false})
		mb.obstacles_add(Vector2(x, pz), 0.7)
	# The arch beam with the estate's name board (blank, sun-bleached).
	sink.box(Transform3D(Basis(), Vector3(x, g + 4.95, z)), Vector3(0.7, 0.6, span + 1.8), "wall_painted", {"dirt": 0.6, "tint": cream, "paint": 0.7, "collide": false})
	sink.box(Transform3D(Basis(), Vector3(x - 0.38, g + 4.95, z)), Vector3(0.06, 0.45, span * 0.6), "metal_paint", {"tint": Color(0.18, 0.32, 0.22), "paint": 0.9, "collide": false})
	# Boom barrier across the inbound lane, stuck half up.
	var bz := z - span * 0.25
	sink.box(Transform3D(Basis(), Vector3(x + 1.2, g + 0.55, z - span * 0.5 + 0.6)), Vector3(0.35, 1.1, 0.35), "metal_paint", {"tint": Color(0.8, 0.7, 0.2), "paint": 0.8})
	var arm := Basis(Vector3.RIGHT, 0.45)
	sink.box(Transform3D(arm, Vector3(x + 1.2, g + 1.0 + sin(0.45) * span * 0.25, bz + 0.2)), Vector3(0.1, 0.1, span * 0.55), "metal_paint",
		{"tint": Color(0.9, 0.85, 0.8), "paint": 0.9, "collide": false})
	mb.obstacles_add(Vector2(x + 1.2, z - span * 0.5 + 0.6), 0.5)


# ------------------------------------------------------------------ edge of the map

func _perimeter() -> void:
	## A 3.4 m precast wall round the play area. Where a road or the water leaves the map, stacked containers and a
	## grille close it.
	var e: float = L.edge
	var corners := [Vector2(-e, -e), Vector2(e, -e), Vector2(e, e), Vector2(-e, e)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var len := a.distance_to(b)
		var d := (b - a) / len
		var basis := Basis(Vector3.UP, atan2(-d.y, d.x))
		var n := int(len / 4.0)
		for k in n:
			var m := a + d * (len * (k + 0.5) / n)
			var water: bool = L.is_water(m.x, m.y)
			var g: float = L.terrain_height(m.x, m.y) if water else L.ground_height(m.x, m.y)
			var road = L.reserved_at(m.x, m.y) == 1
			var h := 3.4
			if water:
				sink.box(Transform3D(basis, Vector3(m.x, (g + L.LAND_Y + 2.0) * 0.5, m.y)), Vector3(len / n, L.LAND_Y + 2.0 - g, 0.12), "grate", {"dirt": 0.5, "phys": "steel"})
				continue
			sink.box(Transform3D(basis, Vector3(m.x, g - 0.3 + (h + 0.3) * 0.5, m.y)), Vector3(len / n, h + 0.3, 0.3), "concrete_panels",
				{"dirt": 0.7, "occlude": true, "what": "edge_wall", "tint": Color(0.8, 0.8, 0.78), "paint": 0.2})
			if road and k % 2 == 0:
				# Containers stacked across the road's mouth, inside the wall.
				var inward := -Vector2(m.x, m.y).normalized()
				inward = Vector2(signf(inward.x), 0) if absf(inward.x) > absf(inward.y) else Vector2(0, signf(inward.y))
				var cc := m + inward * 1.6
				sink.box(Transform3D(basis, Vector3(cc.x, g + 1.3, cc.y)), Vector3(len / n * 2.0 - 0.2, 2.6, 2.44), "container",
					{"dirt": 0.5, "tint": [Color(0.6, 0.2, 0.15), Color(0.2, 0.35, 0.55), Color(0.3, 0.45, 0.3)][k % 3], "paint": 0.8, "occlude": true})
		stats.panels += n


func _backdrop() -> void:
	## The city past the wall: blocks of flats and offices from the wall to the map's edge (drawn near, and as far
	## blocks beyond), then a ring of far blocks on the skyline.
	var e: float = L.edge
	var mats := ["concrete_panels", "facade_tile", "wall_grey"]
	var tints := [Color(0.78, 0.76, 0.72), Color(0.62, 0.66, 0.7), Color(0.8, 0.72, 0.6), Color(0.55, 0.56, 0.58)]
	for side in 4:
		var t = -L.HALF + 4.0
		while t < L.HALF - 4.0:
			var fw := rng.randf_range(16.0, 30.0)
			var fd := rng.randf_range(18.0, 40.0)
			var hgt := rng.randf_range(9.0, 42.0)
			var depth0 := e + 6.0
			var cdep := depth0 + fd * 0.5
			var c: Vector2
			var size: Vector2
			if side == 0:
				c = Vector2(t + fw * 0.5, -cdep)
				size = Vector2(fw, fd)
			elif side == 1:
				c = Vector2(cdep, t + fw * 0.5)
				size = Vector2(fd, fw)
			elif side == 2:
				c = Vector2(t + fw * 0.5, cdep)
				size = Vector2(fw, fd)
			else:
				c = Vector2(-cdep, t + fw * 0.5)
				size = Vector2(fd, fw)
			t += fw + rng.randf_range(4.0, 12.0)
			if _clear_backdrop(c, size):
				var g: float = L.ground_height(c.x, c.y)
				var m: String = mats[rng.randi_range(0, mats.size() - 1)]
				var tint: Color = tints[rng.randi_range(0, tints.size() - 1)]
				var xf := Transform3D(Basis(), Vector3(c.x, g - 0.5 + (hgt + 0.5) * 0.5, c.y))
				sink.box(xf, Vector3(size.x, hgt + 0.5, size.y), m, {"faces": 55, "dirt": 0.8, "tint": tint, "paint": 0.5, "occlude": true, "what": "backdrop"})
				# Window bands on every face.
				var y := g + 3.2
				while y < g + hgt - 1.0:
					sink.box(Transform3D(Basis(), Vector3(c.x, y, c.y)), Vector3(size.x + 0.08, 1.1, size.y + 0.08), "metal_plate",
						{"faces": 51, "dirt": 0.2, "tint": Color(0.1, 0.12, 0.14), "paint": 0.95, "collide": false})
					y += 3.2
				sink.far_block(Transform3D(Basis(), Vector3(c.x, g + hgt * 0.5, c.y)), Vector3(size.x, hgt, size.y), tint * Color(0.55, 0.55, 0.55), Color(0.3, 0.3, 0.3))
				_city_detail(c, size, g, hgt, tint * Color(0.55, 0.55, 0.55), int(stats.backdrop), true)
				stats.backdrop += 1
	# Skyline ring.
	for i in 90:
		var a := TAU * i / 90.0 + rng.randf_range(-0.02, 0.02)
		var r := rng.randf_range(330.0, 720.0)
		var p := Vector2(cos(a), sin(a)) * r
		var s := Vector3(rng.randf_range(25, 60), rng.randf_range(20, 110), rng.randf_range(25, 60))
		var col: Color = [Color(0.32, 0.35, 0.37), Color(0.39, 0.37, 0.33), Color(0.3, 0.34, 0.34), Color(0.42, 0.4, 0.36)][i % 4]
		sink.far_block(Transform3D(Basis(), Vector3(p.x, L.LAND_Y + s.y * 0.5, p.y)), s, col, col * Color(0.7, 0.7, 0.7))
		_city_detail(p, Vector2(s.x, s.z), L.LAND_Y, s.y, col, i, false)


func _city_box(p: Vector3, size: Vector3, col: Color, mat: String, near: bool) -> void:
	## Every rooftop mass exists in both the normal and distant mesh. Distant details stay in the
	## same few wide vertex-colour batches; they never allocate individual nodes or materials.
	if near:
		sink.box(Transform3D(Basis(), p), size, mat, {"faces": 55, "collide": false, "tint": col,
			"paint": 0.75, "dirt": 0.45, "what": "city_rooftop"})
	sink.far_block(Transform3D(Basis(), p), size, col, col * Color(0.8, 0.8, 0.8))
	stats.skyline_parts = int(stats.get("skyline_parts", 0)) + 1


func _city_detail(c: Vector2, size: Vector2, g: float, h: float, col: Color, index: int, near: bool) -> void:
	var style := index % 4
	var roof := g + h
	var dark := Color(0.105, 0.16, 0.185) if style % 2 == 0 else Color(0.16, 0.175, 0.17)
	# The old far mesh had no facade information: broad, low-cost window bands and structural
	# spines now retain the architecture when the near facade stops at 220 m.
	var y := g + 3.2
	while y < roof - 1.0:
		sink.far_block(Transform3D(Basis(), Vector3(c.x, y, c.y)), Vector3(size.x + 0.12, 1.05, size.y + 0.12), dark, dark)
		y += 3.2 if near else 4.5
	var divider := col * Color(1.1, 1.1, 1.1)
	for off in [-0.29, 0.29]:
		_city_box(Vector3(c.x + size.x * off, g + h * 0.5, c.y), Vector3(0.38, h, size.y + 0.25), divider, "concrete_panels", near)
		if style != 3:
			_city_box(Vector3(c.x, g + h * 0.5, c.y + size.y * off), Vector3(size.x + 0.25, h, 0.38), divider, "concrete_panels", near)
	# A service core is deliberately offset, so the skyline no longer consists of identical cuboids.
	var core := Vector3(c.x + size.x * 0.27, roof + 1.6, c.y - size.y * 0.18)
	var core_size := Vector3(clampf(size.x * 0.22, 3.4, 8.0), 3.2, clampf(size.y * 0.27, 4.0, 8.5))
	_city_box(core, core_size, col * Color(0.8, 0.82, 0.83), "concrete_panels", near)
	_city_box(core + Vector3.UP * 1.68, Vector3(core_size.x + 0.3, 0.16, core_size.z + 0.3), divider, "concrete", near)
	if style == 0 or style == 2:
		var cap_h := 3.0 if style == 0 else 5.0
		_city_box(Vector3(c.x - size.x * 0.15, roof + cap_h * 0.5, c.y + size.y * 0.12),
			Vector3(size.x * 0.44, cap_h, size.y * 0.42), col * Color(0.87, 0.9, 0.94), "facade_tile", near)
		_city_box(Vector3(c.x - size.x * 0.15, roof + cap_h + 0.1, c.y + size.y * 0.12),
			Vector3(size.x * 0.48, 0.2, size.y * 0.46), divider, "concrete", near)
	else:
		# Mechanical plant with two short exhaust stacks, shared with the metal material batch.
		var plant := Vector3(c.x - size.x * 0.19, roof + 0.8, c.y + size.y * 0.1)
		_city_box(plant, Vector3(4.8, 1.6, 2.6), Color(0.22, 0.28, 0.28), "metal_paint", near)
		for dx in [-1.5, 1.5]:
			_city_box(plant + Vector3(dx, 1.65, 0), Vector3(0.55, 1.7, 0.55), Color(0.2, 0.23, 0.24), "metal_paint", near)
	if index % 3 == 0:
		# Antenna silhouette is coarse enough to survive distant rendering without shimmering wires.
		var mast := Vector3(core.x, roof + 3.2, core.z)
		_city_box(mast + Vector3.UP * 2.0, Vector3(0.18, 4.0, 0.18), dark, "metal_paint", near)
		for height in [1.8, 3.2]:
			_city_box(mast + Vector3.UP * height, Vector3(2.0, 0.1, 0.12), dark, "metal_paint", near)


func _clear_backdrop(c: Vector2, size: Vector2) -> bool:
	## Off roads and water.
	for i in 5:
		for j in 5:
			var p := c + Vector2((i / 4.0 - 0.5) * size.x, (j / 4.0 - 0.5) * size.y)
			if absf(p.x) > L.HALF or absf(p.y) > L.HALF:
				continue
			if L.is_water(p.x, p.y) or L.reserved_at(p.x, p.y) == 1:
				return false
			if L.water_sd(p).x < 8.0:
				return false
	return true
