import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from plib import patch

P = 'A:/Python/aetherion-project/game/src/world/districts.gd'
patch(P, [
("""##  port, dump   - warehouses / scavenger shacks (sites handle the big structures)
""", """##  port, dump   - warehouses / scavenger shacks (sites handle the big structures)
##
## r3 additions: narrow lanes in the dense districts are roofed over in runs (lagusan: tunnels lined with house
## fronts, see lagusan.gd), some blocks are left open as loobans (courtyards with vault cover, see looban.gd), some
## lanes are cut by junk barricades you vault, concrete houses get flat roof decks (many with a ladder), neighbours
## knock crawl-through holes into each other's houses, and stretches of the estero boardwalk are roofed over.
"""),
# place(): new spec fields
("""	var spec := {
		"xf": Transform3D(basis, Vector3(center.x, base_y, center.y)), "w": w, "d": d,
		"floors": int(opts.get("floors", 1)), "style": str(opts.get("style", "wood")), "kind": str(opts.get("kind", "house")),
		"stilts": stilts, "ground_y": hmin, "front": str(opts.get("front", "door")), "seed": rng.randi(),
		"district": str(opts.get("district", "")), "can_overhang": bool(opts.get("can_overhang", true)),
	}""", """	var fp: Vector2 = center + front2d.normalized() * (d * 0.5 + 0.45)
	var spec := {
		"xf": Transform3D(basis, Vector3(center.x, base_y, center.y)), "w": w, "d": d,
		"floors": int(opts.get("floors", 1)), "style": str(opts.get("style", "wood")), "kind": str(opts.get("kind", "house")),
		"stilts": stilts, "ground_y": hmin, "front": str(opts.get("front", "door")), "seed": rng.randi(),
		"district": str(opts.get("district", "")), "can_overhang": bool(opts.get("can_overhang", true)),
		"covered": bool(opts.get("covered", false)), "roof_deck": bool(opts.get("roof_deck", false)), "ladder": bool(opts.get("ladder", false)),
		"parapet": bool(opts.get("parapet", true)), "side_holes": opts.get("side_holes", []),
		"front_gy": float(opts.get("deck_y", -INF)) if stilts else L.ground_height(fp.x, fp.y),
	}"""),
# more three-storey houses
("""func _floors_dense(density: float) -> int:
	var r := rng.randf()
	if r < 0.36 / density:
		return 1
	if r < 0.9:
		return 2
	return 3
""", """func _floors_dense(density: float) -> int:
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
"""),
# dense: tunnels, loobans, barricades
("""	for i in us.size():
		var a: Vector2 = c + xa * float(us[i]) + za * (-half.y)
		var b: Vector2 = c + xa * float(us[i]) + za * half.y
		mb.alleys.append({"a": a, "b": b, "w": float(aw_u[i]), "kind": "alley"})
	for j in vs.size():
		var a2: Vector2 = c + xa * (-half.x) + za * float(vs[j])
		var b2: Vector2 = c + xa * half.x + za * float(vs[j])
		mb.alleys.append({"a": a2, "b": b2, "w": float(aw_v[j]), "kind": "alley"})
	for i in us.size() - 1:
		for j in vs.size() - 1:
			var u0: float = us[i] + aw_u[i] * 0.5
			var u1: float = us[i + 1] - aw_u[i + 1] * 0.5
			var v0: float = vs[j] + aw_v[j] * 0.5
			var v1: float = vs[j + 1] - aw_v[j + 1] * 0.5
			# Occasionally merge: a block with no alley through it forces long detours.
			_fill_block(c, xa, za, u0, u1, v0, v1, D)
""", """	for i in us.size():
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
			if u1 - u0 > 9.0 and v1 - v0 > 8.0 and not covered.has(Vector2i(i, j)) and not covered.has(Vector2i(i, j + 1)) \\
					and rng.randf() < 0.075:
				mb.loobans.append({"c": c + xa * ((u0 + u1) * 0.5) + za * ((v0 + v1) * 0.5), "half": Vector2((u1 - u0) * 0.5, (v1 - v0) * 0.5),
					"ang": ang, "district": D.name})
				continue
			_fill_block(c, xa, za, u0, u1, v0, v1, D, covered.has(Vector2i(i, j)), covered.has(Vector2i(i, j + 1)))
	# Junk barricades across some open lanes: vault them, or go round.
	for j in range(1, vs.size() - 1):
		for i in us.size() - 1:
			if covered.has(Vector2i(i, j)) or rng.randf() > 0.045:
				continue
			var ua2: float = us[i] + aw_u[i] * 0.5 + 1.5
			var ub2: float = us[i + 1] - aw_u[i + 1] * 0.5 - 1.5
			if ub2 <= ua2:
				continue
			var t := rng.randf_range(ua2, ub2)
			mb.barricades.append({"c": c + xa * t + za * float(vs[j]), "along": xa, "w": float(aw_v[j]), "district": D.name})
"""),
# fill_block: covered rows, decks, holes
("""func _fill_block(c: Vector2, xa: Vector2, za: Vector2, u0: float, u1: float, v0: float, v1: float, D: Dictionary) -> void:
""", """func _fill_block(c: Vector2, xa: Vector2, za: Vector2, u0: float, u1: float, v0: float, v1: float, D: Dictionary,
		cov0: bool = false, cov1: bool = false) -> void:
"""),
("""	for row in rows:
		var edge: float = row[0]
		var face: float = row[1]  # -1: faces the alley at v0 (front toward -za)
		var u := u0
		while u < u1 - 2.8:""", """	for row in rows:
		var edge: float = row[0]
		var face: float = row[1]  # -1: faces the alley at v0 (front toward -za)
		var row_cov: bool = cov0 if face < 0.0 else cov1
		var u := u0
		var hole_p := Vector2.INF   # a hole knocked through from the previous house, at this world point
		while u < u1 - 2.8:"""),
("""			if rng.randf() < 0.03:
				u += w + rng.randf_range(0.8, 1.6)  # a gap: someone's yard or a collapsed shack
				continue
			var front_kind := "door"
			if rng.randf() < 0.07:
				front_kind = "store"
			place(center, front, w - 0.1, d, {"floors": _floors_dense(float(D.density)), "style": _style_dense(), "front": front_kind,
				"kind": "store" if front_kind == "store" else "house", "district": D.name})
			u += w + rng.randf_range(0.0, 0.12)""", """			if rng.randf() < 0.03:
				u += w + rng.randf_range(0.8, 1.6)  # a gap: someone's yard or a collapsed shack
				hole_p = Vector2.INF
				continue
			var front_kind := "door"
			if rng.randf() < 0.07:
				front_kind = "store"
			var floors := _floors_dense(float(D.density))
			var style := _style_dense()
			var opts := {"floors": floors, "style": style, "front": front_kind,
				"kind": "store" if front_kind == "store" else "house", "district": D.name, "covered": row_cov}
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
			u += w + rng.randf_range(0.0, 0.12)"""),
# creek: covered boardwalk stretches
("""		var walk_pts := []
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
			x += w + rng.randf_range(0.0, 0.3)""", """		var walk_pts := []
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
			var wp: Vector2 = Vector2(x + w * 0.5, z) + nrm * (L.estero_w * 0.5 + 0.7)
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
				"w": 1.3, "kind": "walk", "y": deck, "house_side": Vector2(0, side), "district": D.name})"""),
# mixed: decks and low yard walls
("""				var style := "chb" if rng.randf() < 0.55 else ("concrete" if rng.randf() < 0.6 else "wood")
				place(center, za * face, w - 0.6, dd, {"floors": 1 if rng.randf() < 0.45 else 2, "style": style, "district": D.name,
					"front": "store" if rng.randf() < 0.08 else "door"})""", """				var style := "chb" if rng.randf() < 0.55 else ("concrete" if rng.randf() < 0.6 else "wood")
				var fl := 1 if rng.randf() < 0.4 else (2 if rng.randf() < 0.8 else 3)
				var mopts := {"floors": fl, "style": style, "district": D.name, "front": "store" if rng.randf() < 0.08 else "door"}
				_deck_opts(style, fl, false, mopts)
				if place(center, za * face, w - 0.6, dd, mopts) and rng.randf() < 0.45:
					# A hip-high front wall round the yard, with a gap for the gate: cover you can vault.
					mb.yard_walls.append({"c": center + za * face * (dd * 0.5 + 0.55), "along": xa, "len": w - 0.7, "district": D.name})"""),
])

P2 = 'A:/Python/aetherion-project/game/src/world/map_builder.gd'
patch(P2, [
("""var alleys: Array = []  # [{a: Vector2, b: Vector2, w: float, kind}] walkable lanes between houses
""", """var alleys: Array = []  # [{a: Vector2, b: Vector2, w: float, kind}] walkable lanes between houses
var tunnels: Array = []   # [{a, b, w, kind: lane|walk, y?, house_side?}] lanes and walks roofed over (lagusan.gd)
var loobans: Array = []   # [{c, half, ang}] open courtyards left in dense blocks (looban.gd)
var barricades: Array = []  # [{c, along, w}] junk walls across lanes
var yard_walls: Array = []  # [{c, along, len}] low front walls in the mixed district
var ladders: Array = []   # [{base, top_y, n, w}] climbable (Ladder in the movement code)
var cover = null          # Lagusan: which ground is roofed over
var _ladder_grid := {}    # Vector2i (4 m) -> [ladder index]
"""),
("""const ViewLod := preload("res://src/world/view_lod.gd")
""", """const ViewLod := preload("res://src/world/view_lod.gd")
const Lagusan := preload("res://src/world/lagusan.gd")
const Looban := preload("res://src/world/looban.gd")
const Vandal := preload("res://src/world/vandal.gd")
"""),
("""	var districts := Districts.new(self)
	if opts.get("districts", true):
		districts.build_all(opts.get("only", []))
	var ent := Entrances.new(self)
	ent.build()
	stats.entrances = ent.stats
	if opts.get("dress", true):
		StreetDress.new(self).build()
		practical.porch_lights()""", """	var districts := Districts.new(self)
	if opts.get("districts", true):
		districts.build_all(opts.get("only", []))
	cover = Lagusan.new(self)
	cover.build()
	stats.tunnels = cover.stats
	var lb := Looban.new(self)
	lb.build()
	stats.looban = lb.stats
	var ent := Entrances.new(self)
	ent.build()
	stats.entrances = ent.stats
	if opts.get("dress", true):
		StreetDress.new(self).build()
		practical.porch_lights()
		var vd := Vandal.new(self)
		vd.build()
		stats.decals = vd.stats
	_index_ladders()
	stats.ladders = ladders.size()"""),
("""	var out := s.build(spec)
	stairs.append_array(s.flights)
	buildings.append({"id": spec.id, "xf": spec.xf, "w": spec.w, "d": spec.d, "kind": spec.get("kind", "house"), "district": spec.get("district", "")})""",
"""	var out := s.build(spec)
	stairs.append_array(s.flights)
	ladders.append_array(s.ladders)
	buildings.append({"id": spec.id, "xf": spec.xf, "w": spec.w, "d": spec.d, "kind": spec.get("kind", "house"), "district": spec.get("district", ""),
		"style": spec.get("style", "wood"), "floors": spec.get("floors", 1), "covered": spec.get("covered", false), "deck": out.get("deck", false),
		"top": out.top, "front_open": out.get("front_open", [])})"""),
("""func new_building_id() -> int:""", """func _index_ladders() -> void:
	_ladder_grid.clear()
	for i in ladders.size():
		var b: Vector3 = ladders[i].base
		var k := Vector2i(floori(b.x / 4.0), floori(b.z / 4.0))
		if not _ladder_grid.has(k):
			_ladder_grid[k] = []
		_ladder_grid[k].append(i)


func ladders_near(p: Vector3) -> Array:
	## Ladders whose foot is within ~4 m (horizontally) of p.
	var out := []
	var k := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for i in _ladder_grid.get(k + Vector2i(dx, dz), []):
				out.append(ladders[i])
	return out


func new_building_id() -> int:"""),
])
