extends "res://src/world/building_kit.gd"
## House plan generator (r7): one building from an explicit plan instead of the shanty's dice. Footprint and yaw,
## one to four floors (or a tall hall with a mezzanine), rooms as rectangles per floor, interior walls with doors or
## open arches between neighbouring rooms (worked out from the plan: private rooms get one door to the best hall),
## outer doors that open outward, vault-sized ground-floor windows, plastered concrete walls thick enough to occlude,
## floors, ceilings and room finishes on the Interior layer, stairs that follow the shanty rules (the floor opening
## runs 0.6 m past the flight's foot, rails stop short of the top so it lets out), hip / gable tile roofs or a flat
## roof with a parapet and a ladder, a carport and balconies. Registered through MapBuilder.house(plan).
##
## Local frame as the shanty: origin at the footprint centre on the ground-floor level, x right, z back, -z front.
##
## Plan (every key but w, d, floors optional):
##   {seed, pos: Vector3 (footprint centre at ground-floor level) or xf: Transform3D, yaw: 0|90|180|270 (degrees,
##    turning the front from -z), w, d, kind ("house", "store", "factory", "office", ...), style ("suburban"),
##    district, ext_mat, ext_tint (Color), trim_tint, base_h (plinth below the floor, 0.3), wall_t (outer, 0.15),
##    int_t (inner, 0.1), door_mat, front_door_mat, auto_windows (true), win_mix: {glass, open, shutter} weights,
##    floors: [{h (floor to floor, 3.0), y (optional), mezzanine (slab only under its rooms, railings, columns),
##              rooms: [{type, rect: Rect2 | [x0, z0, x1, z1], floor, wall, tint, h (own ceiling), windows (0 = none),
##                       id}],
##              links: [[a, b, "door"|"open"|"none", at?]] (room indices or ids; at = metres along the shared wall),
##              ext: {front|back|left|right: [{type: door|window|opening, x (local x on front/back, z on left/right),
##                    w, h, y, win, vault, door_mat}]},
##              stair: {start: Vector2, dir: Vector2 or "+x"|"-x"|"+z"|"-z", w (1.0), side (let-out), to (floor),
##                      rail, mat},
##              balcony: {side, c0, c1, depth}}],
##    roof: {type: "hip"|"gable"|"flat"|"none", mat, pitch, over, ridge, parapet (0.9), ladder: {side, x}},
##    carport: {rect, h, mat}}
## Returns the shanty's out dictionary {id, rooms, doors, top, deck, front_open, h0, zone_front} plus spec (the record
## MapBuilder registers), far_body / far_roof, light_rooms, exits (outer doors) and report (counts, warnings).

const OPEN_TYPES := ["sala", "living", "dining", "foyer", "stair", "lobby", "corridor", "hall", "shop", "store_aisles", "factory_floor", "warehouse"]
const CIRC_TYPES := ["sala", "living", "dining", "foyer", "stair", "lobby", "corridor", "hall", "shop", "store_aisles", "factory_floor", "warehouse", "kitchen"]
const PRIVATE := ["bedroom", "bed", "toilet", "bath", "cr", "utility", "storage", "office", "stock_room", "garage", "kitchen", "chapel", "classroom"]
## Default finishes per room type: [floor, wall].
const FINISH := {
	"sala": ["tiles_interior", "wall_painted"], "living": ["tiles_interior", "wall_painted"], "dining": ["tiles_interior", "wall_painted"],
	"foyer": ["marble", "wall_painted"], "stair": ["tiles_interior", "wall_painted"], "corridor": ["tiles_interior", "wall_painted"],
	"hall": ["terrazzo", "wall_painted"], "lobby": ["marble", "wall_painted"], "kitchen": ["tiles_white", "tiles_white"],
	"bedroom": ["laminate", "wall_painted"], "bed": ["laminate", "wall_painted"], "toilet": ["tiles_blue", "tiles_wall"], "bath": ["tiles_blue", "tiles_wall"],
	"cr": ["tiles_blue", "tiles_wall"], "utility": ["concrete_floor2", "wall_grey"], "storage": ["concrete_floor2", "wall_grey"],
	"garage": ["garage", "wall_grey"], "office": ["laminate", "wall_painted"], "shop": ["tiles_floor", "wall_painted"],
	"store_aisles": ["terrazzo", "wall_painted"], "stock_room": ["concrete_floor2", "wall_grey"], "factory_floor": ["factory_floor", "factory_wall"],
	"warehouse": ["factory_floor", "factory_wall"], "mezzanine": ["metal_plate", "factory_wall"], "chapel": ["marble", "wall_painted"],
	"classroom": ["terrazzo", "wall_painted"],
}
## Soft interior paints (cream, mint, sky, blush, white, sand).
const ROOM_PAINTS := [Color(0.95, 0.92, 0.82), Color(0.82, 0.92, 0.84), Color(0.8, 0.88, 0.95), Color(0.96, 0.86, 0.84), Color(0.97, 0.97, 0.95),
	Color(0.92, 0.86, 0.74), Color(0.9, 0.93, 0.8)]
## Exterior paints of Philippine subdivision houses.
const EXT_PAINTS := [Color(0.93, 0.88, 0.76), Color(0.95, 0.93, 0.88), Color(0.84, 0.9, 0.8), Color(0.95, 0.83, 0.7), Color(0.82, 0.86, 0.9),
	Color(0.96, 0.9, 0.62), Color(0.9, 0.78, 0.74)]

var report := {"doors_outer": 0, "doors_inner": 0, "openings": 0, "windows": 0, "windows_ground": 0, "vault_windows": 0, "zones": 0, "warnings": []}


func build(plan: Dictionary) -> Dictionary:
	rng.seed = int(plan.get("seed", 1))
	var bid := int(plan.get("id", -1))
	var w := float(plan.w)
	var d := float(plan.d)
	var xf: Transform3D
	if plan.has("xf"):
		xf = plan.xf
	else:
		xf = Transform3D(Basis(Vector3.UP, deg_to_rad(-float(plan.get("yaw", 0.0)))), plan.get("pos", Vector3.ZERO))
	var kind := str(plan.get("kind", "house"))
	var te := float(plan.get("wall_t", 0.15))
	var ti := float(plan.get("int_t", 0.1))
	var ext_mat := str(plan.get("ext_mat", "wall_beige"))
	var ext_tint: Color = plan.get("ext_tint", EXT_PAINTS[rng.randi_range(0, EXT_PAINTS.size() - 1)])
	var trim_tint: Color = plan.get("trim_tint", Color(0.95, 0.94, 0.9))
	var dirt := rng.randf_range(0.25, 0.6)
	var fl: Array = plan.floors
	var out := {"id": bid, "rooms": [], "doors": [], "top": 0.0, "deck": false, "front_open": [], "h0": 3.0, "zone_front": 0, "light_rooms": []}
	# ---- normalise floors and rooms
	var y := 0.0
	var floors := []
	for f in fl.size():
		var F: Dictionary = (fl[f] as Dictionary).duplicate(true)
		F.h = float(F.get("h", 3.0))
		F.y = float(F.get("y", y))
		y = F.y + F.h
		var rs := []
		for r in F.get("rooms", []):
			var R: Dictionary = (r as Dictionary).duplicate()
			R.rect = _rect(R.rect)
			var fin: Array = FINISH.get(str(R.type), ["tiles_interior", "wall_painted"])
			R.floor_mat = str(R.get("floor", fin[0]))
			R.wall_mat = str(R.get("wall", fin[1]))
			R.tint = R.get("tint", ROOM_PAINTS[rng.randi_range(0, ROOM_PAINTS.size() - 1)])
			R.zone = 0
			R.idx = rs.size()
			rs.append(R)
		F.rooms = rs
		F.flights = []
		F.holes = []
		floors.append(F)
	var n_floors := floors.size()
	var top_y: float = floors[-1].y + floors[-1].h
	if bool(floors[-1].get("mezzanine", false)):
		top_y = floors[0].y + floors[0].h
	out.h0 = floors[0].h
	# ---- stairs first: their flights shape the floors above (openings) and the furniture keep-outs.
	for f in n_floors:
		var F: Dictionary = floors[f]
		if not F.has("stair"):
			continue
		var S: Dictionary = F.stair
		var to := int(S.get("to", f + 1))
		if to >= n_floors:
			# TODO: a stair house (bulkhead) on a flat roof; until then roofs are reached by ladder.
			report.warnings.append("floor %d: stair to missing floor %d (roof stairs not built yet)" % [f, to])
			continue
		var rise: float = (floors[to].y if to < n_floors else top_y + 0.15) - F.y
		var dir := _dir(S.get("dir", "+z"))
		var start := _v2(S.start)
		var sw := float(S.get("w", 1.0))
		var side := _v2(S.get("side", _default_side(start, dir, w, d)))
		var steps := int(ceil(rise / RISER))
		var run := float(S.get("tread", TREAD)) * steps
		var end := start + dir * run
		var across := Vector2(absf(dir.y), absf(dir.x)) * (sw * 0.5)
		var r0 := Vector2(minf(start.x, end.x), minf(start.y, end.y)) - across
		var r1 := Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + across
		var frect := Rect2(r0, r1 - r0)
		# The opening above runs 0.6 m back past the foot, so the head clears the floor's edge over the first treads.
		var back := start - dir * 0.6
		var h0 := Vector2(minf(back.x, end.x), minf(back.y, end.y)) - across
		var h1 := Vector2(maxf(back.x, end.x), maxf(back.y, end.y)) + across
		var hole := Rect2(h0, h1 - h0).grow_individual(0.0, 0.0, 0.0, 0.0)
		F.flights.append({"start": start, "dir": dir, "w": sw, "side": side, "rise": rise, "run": run, "end": end, "rect": frect, "to": to, "S": S, "hole": hole})
		if to < n_floors:
			floors[to].holes.append({"rect": hole, "flight": F.flights[-1], "from": f})
		else:
			F.roof_hole = hole
	# ---- zones (one per room) and the room records
	for f in n_floors:
		var F: Dictionary = floors[f]
		var mezz := bool(F.get("mezzanine", false))
		for R in F.rooms:
			var rect: Rect2 = R.rect
			var rh: float = float(R.get("h", F.h - (0.15 if f < n_floors - 1 or not mezz else 0.0)))
			if not R.has("h"):
				rh = _clear_h(floors, f, plan)
			R.clear_h = rh
			if mezz:
				rh = top_y - F.y
			var area := rect.size.x * rect.size.y
			var rev := "small" if area < 14.0 else ("medium" if area < 70.0 else "large")
			R.zone = ctx.acoustics.add_zone(aabb_rect(xf, _clear(rect, w, d, te, ti), xf.origin.y + F.y, rh), bid, f, rev, ctx.mats.phys(R.floor_mat))
			report.zones += 1
	# ---- ground plinth (the ground slab) and per-floor structure
	var base_h := float(plan.get("base_h", 0.3))
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, -base_h * 0.5, 0)), Vector3(w + 0.08, base_h, d + 0.08), "concrete",
		{"dirt": dirt + 0.2, "what": "floor_slab", "faces": 63 & ~8})
	for f in n_floors:
		var F: Dictionary = floors[f]
		var mezz := bool(F.get("mezzanine", false))
		var fy: float = F.y
		# Floor slab (the plinth is the ground floor's) with the stair openings cut out; its underside is the ceiling.
		if f > 0:
			var holes := []
			for hz in F.holes:
				holes.append(hz.rect)
			if mezz:
				for R in F.rooms:
					slab(xf, R.rect, fy, 0.12, "metal_plate", holes, {"under": "metal_plate", "dirt": 0.4, "what": "mezzanine"})
			else:
				slab(xf, Rect2(-w * 0.5 + 0.02, -d * 0.5 + 0.02, w - 0.04, d - 0.04), fy, 0.15, "concrete", holes,
					{"under": "ceiling", "under_tint": Color(0.96, 0.96, 0.94), "dirt": 0.2, "what": "floor"})
		# Room finishes, inside the walls (to the outer face, their edges z-fought with the facade at floor level).
		for R in F.rooms:
			var fr: Rect2 = _clear(R.rect, w, d, te, ti)
			var fopt := {"layer": "inner", "faces": 4 | 1 | 2 | 16 | 32, "dirt": dirt * 0.4, "what": "floor_finish"}
			if mezz:
				continue
			var holes2 := []
			for hz in F.holes:
				holes2.append(hz.rect)
			slab(xf, fr, fy + 0.02, 0.02, str(R.floor_mat), holes2, fopt)
		# Rooms with a ceiling of their own under a tall floor (offices in a factory hall).
		for R in F.rooms:
			if R.has("h") and float(R.h) < F.h - 0.3 and not mezz:
				var above := fy + float(R.h)
				var covered := false
				if f + 1 < n_floors and absf(float(floors[f + 1].y) - 0.12 - above) < 0.2:
					covered = true
				if not covered:
					slab(xf, _clear(R.rect, w, d, te, ti), above + 0.12, 0.12, "concrete", [], {"under": "ceiling", "dirt": 0.2, "what": "ceiling", "layer": "inner"})
		if not mezz:
			_outer_walls(xf, plan, floors, f, w, d, te, ext_mat, ext_tint, trim_tint, dirt, bid, out)
			_inner_walls(xf, plan, floors, f, w, d, te, ti, dirt, bid)
		else:
			_mezzanine(xf, floors, f, w, d, te, dirt)
		_hole_rails(xf, floors, f, w, d, te)
		if F.has("balcony"):
			_balcony(xf, F, w, d, te, ext_mat, ext_tint, dirt)
	# ---- stairs
	for f in n_floors:
		var F: Dictionary = floors[f]
		for fl2 in F.flights:
			var S: Dictionary = fl2.S
			var rail := bool(S.get("rail", _flight_open(fl2, w, d, te)))
			var o := {"mat": str(S.get("mat", "tiles_interior")), "soffit": "ceiling", "rail": false}
			stair_flight(xf, fl2.start, fl2.dir, fl2.w, fl2.rise, F.y + 0.02, fl2.side, o)
			if rail:
				_flight_rail(xf, fl2, F.y + 0.02)
			# Sound goes up the stairwell.
			var lo := _room_at(F, fl2.start - (fl2.dir as Vector2) * 0.3)
			var hi_f: Dictionary = floors[int(fl2.to)] if int(fl2.to) < n_floors else {}
			var hi := _room_at(hi_f, (fl2.end as Vector2) + (fl2.dir as Vector2) * 0.4) if not hi_f.is_empty() else {}
			if hi.is_empty() and not hi_f.is_empty():
				hi = _room_at(hi_f, (fl2.end as Vector2) - (fl2.dir as Vector2) * 0.5 + (fl2.side as Vector2) * float(fl2.w))
			if not lo.is_empty() and not hi.is_empty() and int(lo.zone) != int(hi.zone):
				ctx.acoustics.add_portal(int(lo.zone), int(hi.zone), xf * Vector3((fl2.start as Vector2).x, F.y + 1.5, (fl2.start as Vector2).y), "stair", 1.0)
	# ---- roof
	var roof: Dictionary = plan.get("roof", {"type": "hip"})
	var rtype := str(roof.get("type", "hip"))
	var rmat := str(roof.get("mat", "roof_tiles"))
	var ridge := top_y
	if rtype in ["hip", "gable"]:
		# A flat ceiling closes the top floor; the roof sits on the walls above it.
		if not bool(floors[-1].get("mezzanine", false)) and n_floors > 0 and float(floors[-1].h) < 6.0:
			slab(xf, Rect2(-w * 0.5 + 0.02, -d * 0.5 + 0.02, w - 0.04, d - 0.04), top_y, 0.1, "concrete", [],
				{"under": "ceiling", "under_tint": Color(0.97, 0.97, 0.95), "dirt": 0.2, "what": "ceiling"})
		var ro := {"mat": rmat, "pitch": float(roof.get("pitch", 0.45)), "over": float(roof.get("over", 0.55)), "gable_mat": ext_mat, "tint": ext_tint,
			"inner": float(floors[-1].h) >= 6.0, "ridge": str(roof.get("ridge", "x" if w >= d else "z")), "fascia_tint": trim_tint, "dirt": dirt}
		if rtype == "hip":
			ridge = hip_roof(xf, w, d, top_y, ro)
		else:
			ridge = gable_roof(xf, w, d, top_y, ro)
	elif rtype == "flat":
		out.deck = true
		var rh := 0.15
		var holes3 := []
		if floors[-1].has("roof_hole"):
			holes3.append(floors[-1].roof_hole)
		slab(xf, Rect2(-w * 0.5, -d * 0.5, w, d), top_y + rh, rh, "cement", holes3, {"layer": "ext", "inner_faces": 8, "under": "ceiling",
			"under_tint": Color(0.95, 0.95, 0.93), "dirt": dirt + 0.2, "what": "roof", "phys": "concrete"})
		var ph := float(roof.get("parapet", 0.9))
		var gaps := []
		var lad: Dictionary = roof.get("ladder", {})
		if not lad.is_empty():
			gaps.append(_ladder_gap(lad, w, d))
		parapet(xf, Rect2(-w * 0.5, -d * 0.5, w, d), top_y + rh, ph, 0.15, ext_mat, gaps, {"tint": ext_tint, "paint": 0.85, "dirt": dirt + 0.2})
		ridge = top_y + rh + ph
		if not lad.is_empty():
			_roof_ladder(xf, lad, w, d, top_y + rh, dirt)
		# A water tank on a stand, like every flat roof here.
		if bool(roof.get("tank", true)):
			var tx := (w * 0.5 - 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
			var tz := d * 0.5 - 1.2
			for lxz in [Vector2(-0.45, -0.45), Vector2(0.45, -0.45), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
				ctx.sink.box(xf * Transform3D(Basis(), Vector3(tx + lxz.x, top_y + rh + 0.6, tz + lxz.y)), Vector3(0.08, 1.2, 0.08), "metal_rust", {"dirt": 0.6, "what": "tank_stand"})
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(tx, top_y + rh + 1.23, tz)), Vector3(1.1, 0.06, 1.1), "metal_rust", {"dirt": 0.6, "what": "tank_stand"})
			ctx.sink.cylinder(xf * Vector3(tx, top_y + rh + 1.26, tz), xf.basis * Vector3.UP, 1.2, 0.5, "metal_paint", {"sides": 12, "collide": true,
				"tint": Color(0.2, 0.32, 0.6), "paint": 0.8})
	out.top = ridge
	# ---- carport
	if plan.has("carport"):
		_carport(xf, plan.carport, bid, dirt, out)
	# ---- room records for the dresser and the lights
	for f in n_floors:
		var F: Dictionary = floors[f]
		for R in F.rooms:
			var cr := _clear(R.rect, w, d, te, ti)
			var c := cr.get_center()
			var avoid := []
			for fl3 in F.flights:
				avoid.append((fl3.rect as Rect2).grow(0.15))
				# the foot of the flight and the way on to it
				var ft: Vector2 = (fl3.start as Vector2) - (fl3.dir as Vector2) * 0.6
				avoid.append(Rect2(ft - Vector2(0.6, 0.6), Vector2(1.2, 1.2)))
			for hz in F.holes:
				avoid.append((hz.rect as Rect2).grow(0.35))
				var top_end: Vector2 = (hz.flight.end as Vector2) + (hz.flight.side as Vector2) * (float(hz.flight.w) * 0.5 + 0.5)
				avoid.append(Rect2(top_end - Vector2(0.7, 0.7), Vector2(1.4, 1.4)))
				var fwd: Vector2 = (hz.flight.end as Vector2) + (hz.flight.dir as Vector2) * 0.6
				avoid.append(Rect2(fwd - Vector2(0.7, 0.7), Vector2(1.4, 1.4)))
			var local_av := []
			for a in avoid:
				var ar: Rect2 = a
				if ar.intersects(cr):
					local_av.append(Rect2(ar.position - c, ar.size))
			var rec := {"type": str(R.type), "xf": xf * Transform3D(Basis(), Vector3(c.x, F.y + 0.02, c.y)), "size": cr.size - Vector2(0.1, 0.1),
				"h": float(R.clear_h) - 0.02, "bid": bid, "zone": int(R.zone), "local_z": 0.0, "avoid_list": local_av, "plan": true, "floor": f,
				"kind": kind, "rect": R.rect}
			out.rooms.append(rec)
			if str(R.type) != "mezzanine":
				out.light_rooms.append(rec)
	# ---- far block colours and the registration record
	out.far_body = Color(ext_tint.r * 0.55, ext_tint.g * 0.55, ext_tint.b * 0.52)
	out.far_roof = Color(0.42, 0.2, 0.13) if rmat == "roof_tiles" else (Color(0.3, 0.3, 0.32) if rtype != "flat" else Color(0.45, 0.45, 0.43))
	out.spec = {"id": bid, "xf": xf, "w": w, "d": d, "kind": kind, "district": str(plan.get("district", "plan")), "style": str(plan.get("style", "suburban")),
		"floors": n_floors, "covered": false, "seed": int(plan.get("seed", 1))}
	out.exits = report.doors_outer
	if report.doors_outer < 2:
		report.warnings.append("only %d outer doors" % report.doors_outer)
	out.report = report
	return out


# ------------------------------------------------------------------ helpers

static func _rect(r) -> Rect2:
	if r is Rect2:
		return r
	var a: Array = r
	return Rect2(float(a[0]), float(a[1]), float(a[2]) - float(a[0]), float(a[3]) - float(a[1]))


static func _v2(v) -> Vector2:
	if v is Vector2:
		return v
	var a: Array = v
	return Vector2(float(a[0]), float(a[1]))


static func _dir(v) -> Vector2:
	if v is Vector2:
		return (v as Vector2).normalized()
	match str(v):
		"+x":
			return Vector2(1, 0)
		"-x":
			return Vector2(-1, 0)
		"-z":
			return Vector2(0, -1)
	return Vector2(0, 1)


static func _default_side(start: Vector2, dir: Vector2, w: float, d: float) -> Vector2:
	## The flight lets out away from the nearer outer wall.
	var across := Vector2(-dir.y, dir.x)
	var p := start
	var toward := Vector2(signf(p.x), 0) if absf(dir.y) > 0.5 else Vector2(0, signf(p.y))
	return -toward if toward != Vector2.ZERO else across


func _clear_h(floors: Array, f: int, plan: Dictionary) -> float:
	## Floor finish to ceiling: up to the next slab's underside, or the top ceiling.
	var F: Dictionary = floors[f]
	if f + 1 < floors.size() and not bool(floors[f + 1].get("mezzanine", false)):
		return float(floors[f + 1].y) - float(F.y) - 0.15 - 0.02
	var rt := str((plan.get("roof", {"type": "hip"}) as Dictionary).get("type", "hip"))
	if rt == "flat":
		return float(F.h) - 0.02
	return float(F.h) - (0.1 if float(F.h) < 6.0 else 0.0) - 0.02


func _clear(r: Rect2, w: float, d: float, te: float, ti: float) -> Rect2:
	## The room's floor inside its walls: outer walls take te, inner walls half of ti.
	var x0 := r.position.x + (te if r.position.x <= -w * 0.5 + 0.02 else ti * 0.5)
	var x1 := r.end.x - (te if r.end.x >= w * 0.5 - 0.02 else ti * 0.5)
	var z0 := r.position.y + (te if r.position.y <= -d * 0.5 + 0.02 else ti * 0.5)
	var z1 := r.end.y - (te if r.end.y >= d * 0.5 - 0.02 else ti * 0.5)
	return Rect2(x0, z0, maxf(x1 - x0, 0.1), maxf(z1 - z0, 0.1))


func _room_at(F: Dictionary, p: Vector2) -> Dictionary:
	if F.is_empty():
		return {}
	for R in F.rooms:
		if (R.rect as Rect2).grow(0.05).has_point(p):
			return R
	return {}


func _find_room(F: Dictionary, key) -> Dictionary:
	if key is int or key is float:
		return F.rooms[int(key)] if int(key) < F.rooms.size() else {}
	for R in F.rooms:
		if str(R.get("id", "")) == str(key) or str(R.type) == str(key):
			return R
	return {}


func _side_geom(side: String, w: float, d: float, te: float) -> Array:
	## [a, b, local coordinate at a, sign]: an outer wall's centre line walked with the inside on its +z; c = (u - u0) * sign
	## where u is local x (front/back) or z (left/right).
	match side:
		"front":
			return [Vector2(-w * 0.5, -d * 0.5 + te * 0.5), Vector2(w * 0.5, -d * 0.5 + te * 0.5), -w * 0.5, 1.0]
		"right":
			return [Vector2(w * 0.5 - te * 0.5, -d * 0.5 + te), Vector2(w * 0.5 - te * 0.5, d * 0.5 - te), -d * 0.5 + te, 1.0]
		"back":
			return [Vector2(w * 0.5, d * 0.5 - te * 0.5), Vector2(-w * 0.5, d * 0.5 - te * 0.5), w * 0.5, -1.0]
	return [Vector2(-w * 0.5 + te * 0.5, d * 0.5 - te), Vector2(-w * 0.5 + te * 0.5, -d * 0.5 + te), d * 0.5 - te, -1.0]


func _edge_interval(r: Rect2, side: String, w: float, d: float) -> Array:
	## The part of rect r's edge that lies on the outer wall `side`, as [u0, u1] in local x or z; [] if none.
	match side:
		"front":
			return [r.position.x, r.end.x] if r.position.y <= -d * 0.5 + 0.02 else []
		"back":
			return [r.position.x, r.end.x] if r.end.y >= d * 0.5 - 0.02 else []
		"left":
			return [r.position.y, r.end.y] if r.position.x <= -w * 0.5 + 0.02 else []
	return [r.position.y, r.end.y] if r.end.x >= w * 0.5 - 0.02 else []


# ------------------------------------------------------------------ outer walls

func _outer_walls(xf: Transform3D, plan: Dictionary, floors: Array, f: int, w: float, d: float, te: float, ext_mat: String, ext_tint: Color,
		trim_tint: Color, dirt: float, bid: int, out: Dictionary) -> void:
	var F: Dictionary = floors[f]
	var fy: float = F.y
	var h: float = F.h
	if f == floors.size() - 1 or bool(floors[f + 1].get("mezzanine", false)):
		h = F.h if f == 0 or not bool(floors[f].get("mezzanine", false)) else F.h
	var ext: Dictionary = F.get("ext", {})
	var auto := bool(F.get("auto_windows", plan.get("auto_windows", true)))
	var kind := str(plan.get("kind", "house"))
	for side in ["front", "right", "back", "left"]:
		var g := _side_geom(side, w, d, te)
		var a: Vector2 = g[0]
		var b: Vector2 = g[1]
		var u0: float = g[2]
		var sg: float = g[3]
		var length := a.distance_to(b)
		var ops := []
		for e in ext.get(side, []):
			var E: Dictionary = (e as Dictionary).duplicate()
			var u := float(E.get("x", 0.0))
			E.c = (u - u0) * sg
			_fill_opening(E, f, kind, plan)
			ops.append(E)
		# Windows wherever a room meets this wall and nothing else was asked for.
		if auto:
			for R in F.rooms:
				var iv := _edge_interval(R.rect, side, w, d)
				if iv.is_empty() or int(R.get("windows", 1)) == 0:
					continue
				var c0 := (float(iv[0]) - u0) * sg
				var c1 := (float(iv[1]) - u0) * sg
				if c0 > c1:
					var tmp := c0
					c0 = c1
					c1 = tmp
				c0 = maxf(c0, 0.0)
				c1 = minf(c1, length)
				var span := c1 - c0
				if span < 1.6:
					continue
				var n := clampi(int((span + 0.6) / 3.2), 1, 6)
				for k in n:
					var cc := c0 + span * (k + 0.5) / n
					var win := {"type": "window", "c": cc}
					_fill_opening(win, f, kind, plan, str(R.type))
					if _clashes(win, ops, 0.4) or _over_flight(xf, floors, f, side, cc, float(win.w), w, d, te, u0, sg):
						continue
					ops.append(win)
		# Zones: the room just inside each opening.
		for o in ops:
			var u := u0 + float(o.c) * sg
			var inside := Vector2(u, -d * 0.5 + 0.4) if side == "front" else (Vector2(u, d * 0.5 - 0.4) if side == "back" else (Vector2(w * 0.5 - 0.4, u) if side == "right" else Vector2(-w * 0.5 + 0.4, u)))
			var R2 := _room_at(F, inside)
			o.zone_p = int(R2.zone) if not R2.is_empty() else 0
			o.zone_n = 0
			match str(o.type):
				"door":
					report.doors_outer += 1
				"window":
					report.windows += 1
					if f == 0:
						report.windows_ground += 1
					if bool(o.get("vault", false)):
						report.vault_windows += 1
				"opening":
					report.openings += 1
					if f == 0:
						report.doors_outer += 1
			if f == 0 and side == "front":
				out.front_open.append(Vector4(u, float(o.w), float(o.get("y", 0.0)), float(o.h)))
				if str(o.type) == "door" and int(out.zone_front) == 0:
					out.zone_front = int(o.zone_p)
		# Linings: each room's own wall finish on the inside face.
		var lin := []
		for R in F.rooms:
			var iv2 := _edge_interval(R.rect, side, w, d)
			if iv2.is_empty():
				continue
			var l0 := clampf((float(iv2[0]) - u0) * sg, 0.0, length)
			var l1 := clampf((float(iv2[1]) - u0) * sg, 0.0, length)
			lin.append([minf(l0, l1), maxf(l0, l1), str(R.wall_mat), R.tint if str(R.wall_mat).begins_with("wall_") else null])
		var hh := h if not (f == floors.size() - 1) else h
		wall_seg(xf, a, b, fy, hh, te, ext_mat, ops, {"outer": true, "bid": bid, "dirt": dirt, "tint": ext_tint, "paint": 0.85, "inner_p": true,
			"lin_p": lin, "frame": "planks_paint", "frame_tint": trim_tint, "sill_mat": "concrete"})
		# A band at each floor line outside (the slab edge, painted in the trim colour).
		if f > 0:
			var mid := (a + b) * 0.5
			var nrm := Vector3(-(b - a).normalized().y, 0, (b - a).normalized().x) * -1.0
			var bsize := Vector3(length + 0.04, 0.18, 0.04) if absf((b - a).x) > absf((b - a).y) else Vector3(0.04, 0.18, length + 0.04)
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(mid.x, fy - 0.06, mid.y) + nrm * (te * 0.5 + 0.02)), bsize, "cement",
				{"collide": false, "dirt": dirt, "tint": trim_tint, "paint": 0.8})


func _fill_opening(E: Dictionary, f: int, kind: String, plan: Dictionary, room_type: String = "") -> void:
	## Sizes and kinds for an outer opening that the plan left open.
	var t := str(E.get("type", "window"))
	E.type = t
	if t == "door":
		E.w = float(E.get("w", 1.0))
		E.h = float(E.get("h", 2.15))
		E.y = 0.0
		E.door_mat = str(E.get("door_mat", plan.get("front_door_mat", "planks_dark")))
		E.role = str(E.get("role", "front"))
	elif t == "opening":
		E.w = float(E.get("w", 2.6))
		E.h = float(E.get("h", 2.4))
		E.y = 0.0
	else:
		var mix: Dictionary = plan.get("win_mix", {"glass": 0.55, "open": 0.35, "shutter": 0.1})
		if f == 0:
			# Every ground-floor window is sized to vault through; the glass ones break first.
			E.y = float(E.get("y", VAULT_SILL))
			E.h = float(E.get("h", VAULT_H))
			E.w = float(E.get("w", rng.randf_range(VAULT_W, 1.25)))
			if not E.has("win"):
				if room_type in ["toilet", "bath", "cr"]:
					E.win = "plastic"
				else:
					var roll := rng.randf()
					E.win = "glass" if roll < float(mix.get("glass", 0.55)) else "open"
			E.vault = bool(E.get("vault", float(E.y) <= 1.0 and float(E.h) >= 1.1 and float(E.w) >= 0.95))
		else:
			E.y = float(E.get("y", 0.9))
			E.h = float(E.get("h", 1.2))
			E.w = float(E.get("w", rng.randf_range(1.0, 1.3)))
			if not E.has("win"):
				var r2 := rng.randf()
				if room_type in ["toilet", "bath", "cr"]:
					E.win = "plastic"
				elif r2 < float(mix.get("glass", 0.55)):
					E.win = "glass"
				elif r2 < float(mix.get("glass", 0.55)) + float(mix.get("shutter", 0.1)):
					E.win = "shutter"
				else:
					E.win = "open"
			E.vault = bool(E.get("vault", false))


func _clashes(o: Dictionary, ops: Array, margin: float) -> bool:
	for p in ops:
		if absf(float(o.c) - float(p.c)) < (float(o.w) + float(p.w)) * 0.5 + margin:
			return true
	return false


func _over_flight(xf: Transform3D, floors: Array, f: int, side: String, c: float, ww: float, w: float, d: float, te: float, u0: float, sg: float) -> bool:
	## A window would open on to a flight that runs along this wall (on this floor, or the one below whose flight
	## climbs through the opening into this one).
	var u := u0 + c * sg
	var lst := []
	for fl2 in floors[f].flights:
		lst.append(fl2.rect)
	for hz in floors[f].holes:
		lst.append(hz.rect)
	for r in lst:
		var rr: Rect2 = (r as Rect2).grow(0.3)
		var near := false
		match side:
			"front":
				near = rr.position.y <= -d * 0.5 + te + 0.4 and u + ww * 0.5 > rr.position.x and u - ww * 0.5 < rr.end.x
			"back":
				near = rr.end.y >= d * 0.5 - te - 0.4 and u + ww * 0.5 > rr.position.x and u - ww * 0.5 < rr.end.x
			"left":
				near = rr.position.x <= -w * 0.5 + te + 0.4 and u + ww * 0.5 > rr.position.y and u - ww * 0.5 < rr.end.y
			"right":
				near = rr.end.x >= w * 0.5 - te - 0.4 and u + ww * 0.5 > rr.position.y and u - ww * 0.5 < rr.end.y
		if near:
			return true
	return false


# ------------------------------------------------------------------ inner walls

func _inner_walls(xf: Transform3D, plan: Dictionary, floors: Array, f: int, w: float, d: float, te: float, ti: float, dirt: float, bid: int) -> void:
	var F: Dictionary = floors[f]
	var rooms: Array = F.rooms
	var fy: float = F.y
	# Explicit links first, then the rules.
	var links := {}
	for L in F.get("links", []):
		var A := _find_room(F, L[0])
		var B := _find_room(F, L[1])
		if A.is_empty() or B.is_empty():
			report.warnings.append("floor %d: link %s" % [f, str(L)])
			continue
		links[_pair(int(A.idx), int(B.idx))] = [str(L[2]), float(L[3]) if L.size() > 3 else NAN]
	var shared := []   # [i, j, a, b] (a -> b with room i on the wall's +z side)
	for i in rooms.size():
		for j in rooms.size():
			if i == j:
				continue
			var ri: Rect2 = rooms[i].rect
			var rj: Rect2 = rooms[j].rect
			# vertical line: i to the west (-x) of j. Walked +z, the wall's +z side is -x: room i is on p.
			if absf(ri.end.x - rj.position.x) < 0.03:
				var z0 := maxf(ri.position.y, rj.position.y)
				var z1 := minf(ri.end.y, rj.end.y)
				if z1 - z0 > 0.05:
					shared.append([i, j, Vector2(ri.end.x, z0), Vector2(ri.end.x, z1)])
			# horizontal line: i to the south (+z) of j. Walked +x, the wall's +z side is +z: room i is on p.
			if absf(ri.position.y - rj.end.y) < 0.03:
				var x0 := maxf(ri.position.x, rj.position.x)
				var x1 := minf(ri.end.x, rj.end.x)
				if x1 - x0 > 0.05:
					shared.append([i, j, Vector2(x0, ri.position.y), Vector2(x1, ri.position.y)])
	# Private rooms: one door to their best circulation neighbour.
	var best := {}
	for s in shared:
		for k in 2:
			var me: int = s[k]
			var other: int = s[1 - k]
			var mt := str(rooms[me].type)
			var ot := str(rooms[other].type)
			if not mt in PRIVATE:
				continue
			if not ot in CIRC_TYPES or (ot == "kitchen" and not mt in ["toilet", "bath", "cr", "utility", "storage"]):
				continue
			if mt == "kitchen" and ot == "kitchen":
				continue
			var ln := (s[2] as Vector2).distance_to(s[3])
			if ln < 0.95:
				continue
			var score := ln + (2.0 if ot in ["corridor", "hall", "stair", "foyer"] else 0.0)
			if not best.has(me) or float(best[me][0]) < score:
				best[me] = [score, other]
	for me in best:
		var key := _pair(int(me), int(best[me][1]))
		if not links.has(key):
			links[key] = ["door", NAN]
	for s in shared:
		var i: int = s[0]
		var j: int = s[1]
		var key2 := _pair(i, j)
		if links.has(key2):
			continue
		var ti_t := str(rooms[i].type)
		var tj_t := str(rooms[j].type)
		var both_open := ti_t in OPEN_TYPES and tj_t in OPEN_TYPES
		var kd := (ti_t == "kitchen" and tj_t in ["dining", "sala", "living"]) or (tj_t == "kitchen" and ti_t in ["dining", "sala", "living"])
		if (both_open or kd) and (s[2] as Vector2).distance_to(s[3]) >= 1.1:
			links[key2] = ["open", NAN]
	# Every wall line once, for the joints below: [vertical, line coordinate, lo, hi].
	var segs := []
	for s in shared:
		var sa: Vector2 = s[2]
		var sb: Vector2 = s[3]
		var sv := absf(sa.x - sb.x) < 0.01
		var rec := [sv, sa.x if sv else sa.y, sa.y if sv else sa.x, sb.y if sv else sb.x]
		var dup := false
		for q in segs:
			if q[0] == rec[0] and absf(float(q[1]) - float(rec[1])) < 0.03 and absf(float(q[2]) - float(rec[2])) < 0.03 and absf(float(q[3]) - float(rec[3])) < 0.03:
				dup = true
		if not dup:
			segs.append(rec)
	# Build each shared wall once.
	var done := {}
	for s in shared:
		var i: int = s[0]
		var j: int = s[1]
		var key3 := _pair(i, j)
		var a: Vector2 = s[2]
		var b: Vector2 = s[3]
		# Clip to the outer walls' inner faces; at the joints with other walls, meet them without overlapping
		# (overlapping coplanar faces z-fight): see _joint.
		var vert := absf(a.x - b.x) < 0.01
		if vert:
			a.y = maxf(a.y - _joint(segs, true, a.x, a.y, a.y, b.y, ti), -d * 0.5 + te) if a.y > -d * 0.5 + 0.03 else -d * 0.5 + te
			b.y = minf(b.y + _joint(segs, true, a.x, b.y, a.y, b.y, ti), d * 0.5 - te) if b.y < d * 0.5 - 0.03 else d * 0.5 - te
		else:
			a.x = maxf(a.x - _joint(segs, false, a.y, a.x, a.x, b.x, ti), -w * 0.5 + te) if a.x > -w * 0.5 + 0.03 else -w * 0.5 + te
			b.x = minf(b.x + _joint(segs, false, a.y, b.x, a.x, b.x, ti), w * 0.5 - te) if b.x < w * 0.5 - 0.03 else w * 0.5 - te
		var segkey := "%s|%s" % [str(a.snapped(Vector2.ONE * 0.01)), str(b.snapped(Vector2.ONE * 0.01))]
		if done.has(segkey):
			continue
		done[segkey] = true
		var Ri: Dictionary = rooms[i]
		var Rj: Dictionary = rooms[j]
		var hgt := minf(float(Ri.clear_h), float(Rj.clear_h)) + 0.02
		var length := a.distance_to(b)
		var ops := []
		if links.has(key3) and str(links[key3][0]) != "none":
			var lk: Array = links[key3]
			var typ := str(lk[0])
			var priv := str(Ri.type) in ["toilet", "bath", "cr"] or str(Rj.type) in ["toilet", "bath", "cr"]
			var dw := 0.75 if priv else 0.85
			var dh := 2.05
			if typ == "open":
				dw = clampf(length - 0.6, 0.9, 2.4 if (str(Ri.type) in ["sala", "living", "dining"] and str(Rj.type) in ["sala", "living", "dining", "kitchen"]) else 1.4)
				dh = minf(2.2, hgt - 0.2)
			var c: float = lk[1]
			if is_nan(c):
				c = _door_spot(xf, floors, f, a, b, dw, typ == "door")
			if length >= dw + 0.3:
				var op := {"type": "door" if typ == "door" else "opening", "c": c, "w": dw, "h": dh, "y": 0.0, "door_mat": str(plan.get("door_mat", "planks_paint")),
					"role": "partition", "frame": "planks_paint" if typ == "door" else ""}
				ops.append(op)
				if typ == "door":
					report.doors_inner += 1
				else:
					report.openings += 1
		var pm := str(Ri.wall_mat)
		var lin_n := []
		if str(Rj.wall_mat) != pm or not (Rj.tint as Color).is_equal_approx(Ri.tint):
			lin_n.append([0.0, length, str(Rj.wall_mat), Rj.tint if str(Rj.wall_mat).begins_with("wall_") else null])
		var o := {"zone_p": int(Ri.zone), "zone_n": int(Rj.zone), "bid": bid, "dirt": dirt * 0.4, "layer": "int", "lin_n": lin_n, "outer": false,
			"frame": "planks_paint", "frame_tint": Color(0.95, 0.94, 0.9), "what": "partition"}
		if pm.begins_with("wall_"):
			o.tint = Ri.tint
			o.paint = 0.8
		wall_seg(xf, a, b, fy, hgt, ti, pm, ops, o)


static func _joint(segs: Array, vert: bool, line: float, p: float, lo: float, hi: float, ti: float) -> float:
	## How far a partition reaches past its end p (negative: stops short), so walls meet without overlapping faces:
	## the same wall continuing in line -> meet at the joint (0); the end on the middle of a crossing wall -> stop at
	## its face (-ti/2); an L corner -> the vertical wall runs through the corner (+ti/2), the horizontal one butts
	## against it (-ti/2); nothing there -> +ti/2 as before.
	var left := false
	var right := false
	for q in segs:
		if bool(q[0]) == vert:
			if absf(float(q[1]) - line) < 0.03 and (absf(float(q[2]) - p) < 0.03 or absf(float(q[3]) - p) < 0.03) 					and not (absf(float(q[2]) - lo) < 0.03 and absf(float(q[3]) - hi) < 0.03):
				return 0.0
		elif absf(float(q[1]) - p) < 0.03:
			if float(q[2]) < line - 0.03 and float(q[3]) >= line - 0.03:
				left = true
			if float(q[3]) > line + 0.03 and float(q[2]) <= line + 0.03:
				right = true
	if left and right:
		return -ti * 0.5
	if left or right:
		return ti * 0.5 if vert else -ti * 0.5
	return ti * 0.5


static func _pair(i: int, j: int) -> String:
	return "%d-%d" % [mini(i, j), maxi(i, j)]


func _door_spot(xf: Transform3D, floors: Array, f: int, a: Vector2, b: Vector2, dw: float, is_door: bool) -> float:
	## Where along a shared wall a door goes: near one end (as real houses have them), clear of stair flights and their
	## openings; the middle when the wall is short.
	var length := a.distance_to(b)
	var cands := [length * 0.5]
	if length > dw + 1.2:
		cands = [0.35 + dw * 0.5, length - 0.35 - dw * 0.5, length * 0.5]
		if rng.randf() < 0.5:
			cands = [cands[1], cands[0], cands[2]]
	var dirv := (b - a) / maxf(length, 0.001)
	for c in cands:
		var p := a + dirv * float(c)
		var ok := true
		var lst := []
		for fl2 in floors[f].flights:
			lst.append((fl2.rect as Rect2).grow(0.5))
			var ft: Vector2 = (fl2.start as Vector2) - (fl2.dir as Vector2) * 0.6
			lst.append(Rect2(ft - Vector2(0.7, 0.7), Vector2(1.4, 1.4)))
		for hz in floors[f].holes:
			lst.append((hz.rect as Rect2).grow(0.4))
		for r in lst:
			if (r as Rect2).has_point(p):
				ok = false
		if ok:
			return float(c)
	return float(cands[0])


# ------------------------------------------------------------------ stairs, openings, mezzanines

func _flight_open(fl2: Dictionary, w: float, d: float, te: float) -> bool:
	## A handrail goes on a flight's open side (one not against a wall).
	return true


func _flight_rail(xf: Transform3D, fl2: Dictionary, y: float) -> void:
	## A handrail on the side opposite the let-out, rising with the flight and stopping a metre short of the top.
	var dir: Vector2 = fl2.dir
	var side: Vector2 = fl2.side
	var sw := float(fl2.w)
	var rise := float(fl2.rise)
	var run := float(fl2.run)
	var start: Vector2 = fl2.start
	# The rail goes on the let-out side when the other side is a wall; the flight is built along walls, so the rail is
	# on the side the flight lets out to, and stops short of the top so it still lets out sideways.
	var off := side * (sw * 0.5 + 0.03)
	var len_run := maxf(run - 1.0, 0.5)
	var lo := start + off
	var hi := start + dir * len_run + off
	var hi_y := rise * len_run / run
	var p0 := Vector3(lo.x, y + 0.9, lo.y)
	var p1 := Vector3(hi.x, y + hi_y + 0.9, hi.y)
	var len := p0.distance_to(p1)
	var dz := (p1 - p0) / len
	var bx := Vector3.UP.cross(dz).normalized()
	var basis := Basis(bx, dz.cross(bx), dz)
	var mopt := {"collide": false, "layer": "int", "tint": Color(0.14, 0.1, 0.07), "paint": 0.9}
	ctx.sink.box(xf * Transform3D(basis, (p0 + p1) * 0.5), Vector3(0.06, 0.05, len), "timber", mopt)
	var n := maxi(int(len / 0.9), 2)
	for k in n + 1:
		var q := p0.lerp(p1, float(k) / n)
		ctx.sink.box(xf * Transform3D(Basis(), q - Vector3.UP * 0.45), Vector3(0.035, 0.9, 0.035), "metal_paint", {"collide": false, "layer": "int", "tint": Color(0.1, 0.1, 0.1), "paint": 0.9})
	ctx.sink.col_box(xf * Transform3D(basis, (p0 + p1) * 0.5 - basis.y * 0.4), Vector3(0.05, 1.0, len), "blocker", "stair_rail")


func _hole_rails(xf: Transform3D, floors: Array, f: int, w: float, d: float, te: float) -> void:
	## Round a stair opening in this floor: across its low end and down its open side, stopping a metre short of the
	## flight's top so it lets out sideways; nothing where an outer wall closes it.
	var fy := float(floors[f].y)
	var mezz := bool(floors[f].get("mezzanine", false))
	for hz in floors[f].holes:
		var r: Rect2 = hz.rect
		if mezz:
			var any := false
			for R in floors[f].rooms:
				if (R.rect as Rect2).intersects(r):
					any = true
			if not any:
				continue
		var fl2: Dictionary = hz.flight
		var dir: Vector2 = fl2.dir
		var side: Vector2 = fl2.side
		var start: Vector2 = fl2.start
		var low := start - dir * 0.6
		var acr := Vector2(absf(dir.y), absf(dir.x))
		var half := float(fl2.w) * 0.5
		# Low end, across.
		var e0 := low - acr * half
		var e1 := low + acr * half
		railing(xf, e0, e1, fy, {"h": 1.0})
		# The two long sides: a wall closes one when it runs along the outer wall.
		for sgn in [-1.0, 1.0]:
			var off: Vector2 = acr * half * sgn
			var edge_mid := (r.get_center() + off)
			var against := absf(edge_mid.x) > w * 0.5 - te - 0.15 if acr.x > 0.5 else absf(edge_mid.y) > d * 0.5 - te - 0.15
			if against:
				continue
			var lets_out := off.dot(side) > 0.0
			var stop := float(fl2.run) - (1.0 if lets_out else 0.0)
			railing(xf, low + off, start + dir * stop + off, fy, {"h": 1.0})


func _mezzanine(xf: Transform3D, floors: Array, f: int, w: float, d: float, te: float, dirt: float) -> void:
	## Columns under a mezzanine and a rail along its open edges (a gap where a stair arrives).
	var F: Dictionary = floors[f]
	var fy: float = F.y
	var y0 := float(floors[0].y)
	var lets := []
	for g in floors:
		for fl2 in g.flights:
			if int(fl2.to) == f:
				var tp: Vector2 = (fl2.end as Vector2) - (fl2.dir as Vector2) * 0.5 + (fl2.side as Vector2) * float(fl2.w)
				lets.append(Rect2(tp - Vector2(0.9, 0.9), Vector2(1.8, 1.8)))
				var fw: Vector2 = (fl2.end as Vector2) + (fl2.dir as Vector2) * 0.4
				lets.append(Rect2(fw - Vector2(0.8, 0.8), Vector2(1.6, 1.6)))
	for R in F.rooms:
		var r: Rect2 = R.rect
		var edges := [[Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y)],
			[Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.position.y)]]
		for e in edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var mid := (a + b) * 0.5
			var on_wall := absf(mid.x) > w * 0.5 - 0.05 if absf(a.x - b.x) < 0.01 else absf(mid.y) > d * 0.5 - 0.05
			if on_wall:
				continue
			# Rail in pieces, skipping where a stair lets out.
			var length := a.distance_to(b)
			var dv := (b - a) / length
			var s := 0.0
			var k := 0.0
			var inside := false
			while k <= length:
				var p := a + dv * k
				var blocked := false
				for lr in lets:
					if (lr as Rect2).has_point(p):
						blocked = true
				if blocked and not inside:
					if k - s > 0.2:
						railing(xf, a + dv * s, p, fy, {"h": 1.05})
					inside = true
				elif not blocked and inside:
					s = k
					inside = false
				k += 0.1
			if not inside and length - s > 0.2:
				railing(xf, a + dv * s, b, fy, {"h": 1.05})
			# Columns along the open edge.
			var n := maxi(int(length / 4.5), 1)
			for i in n + 1:
				var p2 := a + dv * (length * i / n) - Vector2(dv.y, -dv.x) * 0.0
				column(xf, p2.clamp(Vector2(-w * 0.5 + te + 0.15, -d * 0.5 + te + 0.15), Vector2(w * 0.5 - te - 0.15, d * 0.5 - te - 0.15)), y0, fy - 0.12, 0.22,
					"metal_paint", {"tint": Color(0.75, 0.55, 0.15), "layer": "int"})


func _balcony(xf: Transform3D, F: Dictionary, w: float, d: float, te: float, ext_mat: String, ext_tint: Color, dirt: float) -> void:
	var B: Dictionary = F.balcony
	var side := str(B.get("side", "front"))
	var dep := float(B.get("depth", 1.1))
	var c0 := float(B.get("c0", -1.5))
	var c1 := float(B.get("c1", 1.5))
	var fy := float(F.y)
	var r := Rect2()
	match side:
		"front":
			r = Rect2(c0, -d * 0.5 - dep, c1 - c0, dep)
		"back":
			r = Rect2(c0, d * 0.5, c1 - c0, dep)
		"left":
			r = Rect2(-w * 0.5 - dep, c0, dep, c1 - c0)
		_:
			r = Rect2(w * 0.5, c0, dep, c1 - c0)
	slab(xf, r, fy + 0.02, 0.16, "cement", [], {"layer": "ext", "dirt": dirt, "what": "balcony", "tint": ext_tint, "paint": 0.5})
	# Tiles 3 cm over the slab: at 1.5 cm the two tops z-fought from across the street.
	slab(xf, r.grow(-0.02), fy + 0.05, 0.03, "tiles_interior", [], {"layer": "ext", "faces": 4, "dirt": dirt, "what": "balcony"})
	# Low wall with a rail on its three open sides.
	var pts := []
	match side:
		"front":
			pts = [[Vector2(r.position.x + 0.06, r.end.y), Vector2(r.position.x + 0.06, r.position.y + 0.06)], [Vector2(r.position.x, r.position.y + 0.06), Vector2(r.end.x, r.position.y + 0.06)],
				[Vector2(r.end.x - 0.06, r.position.y + 0.06), Vector2(r.end.x - 0.06, r.end.y)]]
		"back":
			pts = [[Vector2(r.end.x - 0.06, r.position.y), Vector2(r.end.x - 0.06, r.end.y - 0.06)], [Vector2(r.end.x, r.end.y - 0.06), Vector2(r.position.x, r.end.y - 0.06)],
				[Vector2(r.position.x + 0.06, r.end.y - 0.06), Vector2(r.position.x + 0.06, r.position.y)]]
		"left":
			pts = [[Vector2(r.end.x, r.position.y + 0.06), Vector2(r.position.x + 0.06, r.position.y + 0.06)], [Vector2(r.position.x + 0.06, r.position.y), Vector2(r.position.x + 0.06, r.end.y)],
				[Vector2(r.position.x + 0.06, r.end.y - 0.06), Vector2(r.end.x, r.end.y - 0.06)]]
		_:
			pts = [[Vector2(r.position.x, r.end.y - 0.06), Vector2(r.end.x - 0.06, r.end.y - 0.06)], [Vector2(r.end.x - 0.06, r.end.y), Vector2(r.end.x - 0.06, r.position.y)],
				[Vector2(r.end.x - 0.06, r.position.y + 0.06), Vector2(r.position.x, r.position.y + 0.06)]]
	for pp in pts:
		_wall_holes_only(xf, pp[0], pp[1], fy + 0.02, 0.5, 0.12, ext_mat, [], {"tint": ext_tint, "paint": 0.85, "dirt": dirt, "what": "balcony_wall"})
		railing(xf, pp[0], pp[1], fy + 0.52, {"h": 0.5, "layer": "ext", "tint": Color(0.1, 0.1, 0.1)})


# ------------------------------------------------------------------ roof access, carport

func _ladder_gap(lad: Dictionary, w: float, d: float) -> Array:
	## The parapet gap where a ladder arrives: [side, c0, c1] along the edge as parapet() measures it.
	var side := str(lad.get("side", "back"))
	var x := float(lad.get("x", 0.0))
	var c := 0.0
	match side:
		"front":
			c = x + w * 0.5
		"back":
			c = w * 0.5 - x
		"right":
			c = x + d * 0.5 - 0.15
		_:
			c = d * 0.5 - 0.15 - x
	return [side, c - 0.45, c + 0.45]


func _roof_ladder(xf: Transform3D, lad: Dictionary, w: float, d: float, roof_y: float, dirt: float) -> void:
	## A steel ladder up an outer wall to the roof (the kit's shanty ladder, turned to that wall).
	var side := str(lad.get("side", "back"))
	var x := float(lad.get("x", 0.0))
	var yaw := 0.0
	var depth := d
	match side:
		"back":
			yaw = PI
		"right":
			yaw = -PI * 0.5
			depth = w
		"left":
			yaw = PI * 0.5
			depth = w
	var lx := x
	if side in ["back", "left"]:
		lx = -x
	var lxf := xf * Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)
	var gy := xf.origin.y - float(lad.get("ground_drop", 0.3))
	_ladder(lxf, lx, depth, roof_y + 0.0, gy, dirt)


func _carport(xf: Transform3D, C: Dictionary, bid: int, dirt: float, out: Dictionary) -> void:
	## A carport beside the house: a driveway slab, four steel posts and a flat roof; dressed like a room (outdoors).
	var r := _rect(C.rect)
	var h := float(C.get("h", 2.6))
	slab(xf, r, -0.12, 0.2, "driveway", [], {"layer": "ext", "dirt": dirt + 0.2, "what": "driveway"})
	for p in [r.position + Vector2(0.15, 0.15), Vector2(r.end.x - 0.15, r.position.y + 0.15), r.end - Vector2(0.15, 0.15), Vector2(r.position.x + 0.15, r.end.y - 0.15)]:
		ctx.sink.cylinder(xf * Vector3(p.x, -0.12, p.y), xf.basis * Vector3.UP, h + 0.12, 0.05, "metal_paint", {"sides": 8, "collide": true, "tint": Color(0.15, 0.15, 0.15), "paint": 0.9})
	slab(xf, r.grow(0.15), h + 0.08, 0.08, str(C.get("mat", "metal_blue")), [], {"layer": "ext", "dirt": dirt, "what": "carport_roof"})
	var c := r.get_center()
	out.rooms.append({"type": "carport", "xf": xf * Transform3D(Basis(), Vector3(c.x, -0.02, c.y)), "size": r.size - Vector2(0.4, 0.4), "h": h, "bid": bid,
		"zone": 0, "local_z": 0.0, "avoid_list": [], "plan": true, "floor": 0, "kind": "carport", "rect": r})
