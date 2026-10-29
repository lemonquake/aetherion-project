extends RefCounted
## Lawless Sub's houses and shophouses (r7 wave 2): real buildings from house_plan.gd through MapBuilder.house().
## Three plans, sized to the lot's envelope and mirrored at random:
##   two-storey house: sala, stair hall, kitchen, dining, utility and toilet downstairs; master bedroom, two more
##     bedrooms, bathroom and an L-shaped hall upstairs; hip or gable tile roof; front door and a kitchen door.
##   bungalow (shallow lots, one floor): sala, kitchen, two bedrooms, toilet and a short hall.
##   shophouse (Canal Row): a store across the ground floor with a wide front opening, stock room and toilet behind,
##     two bedrooms, a bathroom and a hall upstairs; flat roof with a parapet and a ladder.
## Every ground-floor window is vault-sized (house_plan's rule). Entry point kept: static func build(mb, lot).
## Local frame as house_plan: x right, z back, -z is the front (towards the lot's street).

const HOUSE_ROOFS := ["roof_tiles", "roof_tiles", "roof_tiles_grey"]
const EXT_MATS := ["wall_painted", "wall_painted", "wall_beige", "plaster_white"]


static func build(mb, lot: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lot.seed)
	var shop := str(lot.kind) == "shophouse"
	var env: Dictionary = lot.envelope
	var ehalf: Vector2 = env.half
	var plan: Dictionary
	var w: float
	var d: float
	if shop:
		w = ehalf.x * 2.0 - 0.1
		d = minf(ehalf.y * 2.0, rng.randf_range(9.6, 11.0))
		plan = _shophouse(w, d, rng)
	elif ehalf.y * 2.0 < 9.2 or int(lot.floors) < 2:
		w = minf(ehalf.x * 2.0, rng.randf_range(8.0, 9.6))
		d = clampf(ehalf.y * 2.0, 7.0, 9.0)
		plan = _bungalow(w, d, rng) if int(lot.floors) < 2 or d < 8.6 else _two_storey(w, maxf(d, 8.6), rng)
	else:
		w = minf(ehalf.x * 2.0, rng.randf_range(8.4, 9.8))
		d = minf(ehalf.y * 2.0, rng.randf_range(9.4, 11.0))
		plan = _two_storey(w, d, rng)
	if rng.randf() < 0.5:
		_mirror(plan)
	var front: Vector2 = lot.front
	var c: Vector2 = env.center + front * (ehalf.y - d * 0.5)
	var y0 := float(lot.plinth_y)
	var gy: float = mb.layout.ground_height(c.x, c.y)
	plan.seed = int(lot.seed)
	plan.w = w
	plan.d = d
	plan.xf = Transform3D(Basis(Vector3.UP, deg_to_rad(float(lot.yaw))), Vector3(c.x, y0, c.y))
	plan.kind = "store" if shop else "house"
	plan.style = "suburban"
	plan.district = str(lot.get("district", ""))
	plan.base_h = maxf(y0 - gy + 0.3, 0.3)
	plan.ext_mat = "wall_grey" if shop else EXT_MATS[rng.randi_range(0, EXT_MATS.size() - 1)]
	var out: Dictionary = mb.house(plan)
	lot.bid = int(out.id)
	if not shop:
		_yard_wall(mb, lot, rng)


static func _two_storey(w: float, d: float, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var sx := X - 2.9                 # west edge of the stair hall
	var zm := -Z + 5.4                # back of the front rooms
	var kx := -X + minf(4.0, w * 0.45)  # kitchen | dining
	var run := 15 * 0.27              # 3.0 m rise at 0.21 m risers
	var s0 := -Z + 0.55
	var zc := s0 + run + 0.1          # just past the top of the flight
	var hx := X - 2.1                 # upstairs hall
	var g := {"h": 3.0, "rooms": [
		{"type": "sala", "rect": [-X, -Z, sx, zm]},
		{"type": "stair", "rect": [sx, -Z, X, zm]},
		{"type": "kitchen", "rect": [-X, zm, kx, Z]},
		{"type": "dining", "rect": [kx, zm, X - 1.9, Z]},
		{"type": "utility", "rect": [X - 1.9, zm, X, zm + 1.8], "windows": 0},
		{"type": "cr", "rect": [X - 1.9, zm + 1.8, X, Z]},
	], "ext": {
		"front": [{"type": "door", "x": (-X + sx) * 0.5 + rng.randf_range(-0.6, 0.6), "w": 1.0, "door_mat": "planks_dark"}],
		"back": [{"type": "door", "x": (-X + kx) * 0.5, "w": 0.9, "role": "back", "door_mat": "planks_paint"}],
	}, "stair": {"start": Vector2(X - 0.65, s0), "dir": "+z", "w": 1.0, "to": 1}}
	var u := {"h": 3.0, "rooms": [
		{"type": "bedroom", "rect": [-X, -Z, hx, zc]},
		{"type": "corridor", "rect": [hx, -Z, X, zc + 1.7], "windows": 0},
		{"type": "corridor", "rect": [kx, zc, hx, zc + 2.4], "windows": 0},
		{"type": "bedroom", "rect": [-X, zc, kx, Z]},
		{"type": "bath", "rect": [kx, zc + 2.4, hx, Z]},
		{"type": "bedroom", "rect": [hx, zc + 1.7, X, Z]},
	]}
	if rng.randf() < 0.45:
		u.balcony = {"side": "front", "c0": -X + 0.8, "c1": hx - 0.8, "depth": 1.2}
	var roof := {"type": "hip" if rng.randf() < 0.6 else "gable", "mat": HOUSE_ROOFS[rng.randi_range(0, HOUSE_ROOFS.size() - 1)], "pitch": rng.randf_range(0.38, 0.55)}
	return {"floors": [g, u], "roof": roof}


static func _bungalow(w: float, d: float, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var bx := X - minf(3.6, w * 0.42)   # bedrooms east of this
	var zs := -Z + d * 0.52              # back of the sala
	var g := {"h": 3.0, "rooms": [
		{"type": "sala", "rect": [-X, -Z, bx, zs]},
		{"type": "kitchen", "rect": [-X, zs, bx - 1.3, Z]},
		{"type": "corridor", "rect": [bx - 1.3, zs, bx, Z - 1.8], "windows": 0},
		{"type": "cr", "rect": [bx - 1.3, Z - 1.8, bx, Z]},
		{"type": "bedroom", "rect": [bx, -Z, X, -Z + d * 0.5]},
		{"type": "bedroom", "rect": [bx, -Z + d * 0.5, X, Z]},
	], "ext": {
		"front": [{"type": "door", "x": (-X + bx) * 0.5 + rng.randf_range(-0.5, 0.5), "w": 1.0, "door_mat": "planks_dark"}],
		"left": [{"type": "door", "x": (zs + Z) * 0.5, "w": 0.9, "role": "back", "door_mat": "planks_paint"}],
	}}
	return {"floors": [g], "roof": {"type": "hip" if rng.randf() < 0.5 else "gable", "mat": HOUSE_ROOFS[rng.randi_range(0, HOUSE_ROOFS.size() - 1)], "pitch": rng.randf_range(0.35, 0.5)}}


static func _shophouse(w: float, d: float, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var hx := X - 2.2                 # stair hall west edge
	var zb := Z - 3.0                 # back rooms
	var run := 15 * 0.27
	var s0 := -Z + 0.6
	var zc := s0 + run + 0.1
	var g := {"h": 3.0, "rooms": [
		{"type": "shop", "rect": [-X, -Z, hx, zb]},
		{"type": "stair", "rect": [hx, -Z, X, zb]},
		{"type": "stock_room", "rect": [-X, zb, X - 1.8, Z]},
		{"type": "cr", "rect": [X - 1.8, zb, X, Z]},
	], "ext": {
		"front": [{"type": "opening", "x": (-X + hx) * 0.5, "w": minf(hx + X - 1.2, 3.4), "h": 2.5},
			{"type": "door", "x": (hx + X) * 0.5, "w": 0.95, "door_mat": "metal_paint"}],
		"back": [{"type": "door", "x": -X + 1.4, "w": 0.95, "role": "back", "door_mat": "metal_paint"}],
	}, "stair": {"start": Vector2(X - 0.65, s0), "dir": "+z", "w": 1.0, "to": 1}}
	var u := {"h": 3.0, "rooms": [
		{"type": "bedroom", "rect": [-X, -Z, hx, zc]},
		{"type": "corridor", "rect": [hx, -Z, X, zc + 1.6], "windows": 0},
		{"type": "bedroom", "rect": [-X, zc, hx, Z]},
		{"type": "bath", "rect": [hx, zc + 1.6, X, Z]},
	]}
	var tint := Color(0.86, 0.84, 0.78).lerp(Color(0.95, 0.9, 0.75), rng.randf())
	return {"floors": [g, u], "ext_tint": tint, "win_mix": {"glass": 0.6, "open": 0.2, "shutter": 0.2},
		"roof": {"type": "flat", "parapet": 0.9, "ladder": {"side": "back", "x": X - 1.0}, "tank": rng.randf() < 0.6}}


static func _mirror(plan: Dictionary) -> void:
	## Flips the plan left for right (x -> -x): rooms, stairs, outer openings, balconies, the roof ladder.
	for F in plan.floors:
		for R in F.rooms:
			var r: Array = R.rect
			R.rect = [-float(r[2]), r[1], -float(r[0]), r[3]]
		if F.has("stair"):
			var st: Vector2 = F.stair.start
			F.stair.start = Vector2(-st.x, st.y)
		if F.has("ext"):
			var e: Dictionary = F.ext
			var ne := {}
			for side in e:
				var to: String = {"left": "right", "right": "left"}.get(side, side)
				var arr := []
				for o in e[side]:
					var o2: Dictionary = (o as Dictionary).duplicate()
					if side in ["front", "back"]:
						o2.x = -float(o.x)
					arr.append(o2)
				ne[to] = arr
			F.ext = ne
		if F.has("balcony") and str(F.balcony.side) in ["front", "back"]:
			var b: Dictionary = F.balcony
			var c0 := float(b.c0)
			b.c0 = -float(b.c1)
			b.c1 = -c0
	var roof: Dictionary = plan.get("roof", {})
	if roof.has("ladder") and str(roof.ladder.side) in ["front", "back"]:
		roof.ladder.x = -float(roof.ladder.x)


static func _yard_wall(mb, lot: Dictionary, rng: RandomNumberGenerator) -> void:
	## A low front wall along the lot's street edge with a gate gap.
	var c: Vector2 = lot.center
	var half: Vector2 = lot.half
	var basis := Basis(Vector3.UP, deg_to_rad(float(lot.yaw)))
	var y := float(lot.plinth_y) - 0.15
	var xf := Transform3D(basis, Vector3(c.x, y, c.y))
	var gate := rng.randf_range(-half.x * 0.4, half.x * 0.4)
	var gw := 3.0
	var z := -half.y + 0.15
	var l0 := gate - gw * 0.5 + half.x
	var r0 := half.x - (gate + gw * 0.5)
	var col := Color(0.85, 0.82, 0.74)
	if l0 > 0.2:
		mb.sink.box(xf * Transform3D(Basis(), Vector3(-half.x + l0 * 0.5, 0.55, z)), Vector3(l0, 1.1, 0.15), "wall_grey", {"dirt": 0.7, "tint": col, "paint": 0.5, "what": "yard_wall"})
	if r0 > 0.2:
		mb.sink.box(xf * Transform3D(Basis(), Vector3(half.x - r0 * 0.5, 0.55, z)), Vector3(r0, 1.1, 0.15), "wall_grey", {"dirt": 0.7, "tint": col, "paint": 0.5, "what": "yard_wall"})


static func register(mb, lot: Dictionary, xf: Transform3D, w: float, d: float, floors: int, top: float, style: String, col: Color) -> void:
	## For the big-building massing that is still a plain shell: a buildings record and a far block.
	var id: int = mb.new_building_id()
	mb.buildings.append({"id": id, "xf": xf, "w": w, "d": d, "kind": str(lot.kind), "district": str(lot.get("district", "")), "style": style,
		"floors": floors, "covered": false, "deck": false, "top": top, "front_open": [], "h0": 3.0, "lot": int(lot.id)})
	lot.bid = id
	mb.sink.far_block(xf * Transform3D(Basis(), Vector3(0, top * 0.5, 0)), Vector3(w + 0.6, top, d + 0.6), col * Color(0.6, 0.6, 0.6), Color(0.35, 0.22, 0.17))
