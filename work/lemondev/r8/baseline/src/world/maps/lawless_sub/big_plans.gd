extends RefCounted
## Lawless Sub's enclosed big buildings as real buildings (house_plan.gd through MapBuilder.house()): rooms on every
## floor, switchback stair cores, doors on at least two sides, vault-sized ground-floor windows, roofs.
##   office_tower  Lawless Tower: lobby, offices round an east-west corridor, stair core, 4 floors, flat roof + ladder
##   apartment     Canal Flats: units off a corridor, stair core, 3 floors, flat roof + ladder
##   clubhouse     function hall, kitchen, office, stair; function room and storage upstairs; tile roof
##   chapel        nave (6 m), sacristy and store; gable roof; the bell tower in front
##   store         Lawless Mart: aisles, stock room, office, toilet; flat roof + ladder
##   strip_shops   four shops (pharmacy, eatery, laundromat, hardware), each with a back room
##   factory       Lawless Plastics: 9 m hall with machine lines, offices under a mezzanine reached by a stair
##   warehouse     tall hall, office and stock room
##   guardhouse / guard_booth  one room, two doors
## Local frame: x right, z back, -z the lot's front.

const KINDS := ["office_tower", "apartment", "clubhouse", "chapel", "store", "strip_shops", "factory", "warehouse", "guardhouse", "guard_booth"]
const RISER := 0.21
const TREAD := 0.27


static func handles(kind: String) -> bool:
	return kind in KINDS


static func build(mb, lot: Dictionary) -> Dictionary:
	var kind := str(lot.kind)
	var half: Vector2 = lot.half
	var w := half.x * 2.0
	var d := half.y * 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lot.seed)
	var n := int(lot.floors)
	var plan: Dictionary
	match kind:
		"office_tower":
			plan = _office_tower(w, d, n, rng)
		"apartment":
			plan = _apartment(w, d, n, rng)
		"clubhouse":
			plan = _clubhouse(w, d, n, rng)
		"chapel":
			plan = _chapel(w, d, n, rng)
		"store":
			plan = _store(w, d, n, rng)
		"strip_shops":
			plan = _strip_shops(w, d, n, rng)
		"factory":
			plan = _factory(w, d, n, rng)
		"warehouse":
			plan = _warehouse(w, d, n, rng)
		"guardhouse":
			plan = _guardhouse(w, d, n, rng)
		_:
			plan = _guard_booth(w, d, n, rng)
	var c: Vector2 = lot.center
	var y0 := float(lot.plinth_y)
	var gy: float = mb.layout.ground_height(c.x, c.y)
	plan.seed = int(lot.seed)
	plan.w = w
	plan.d = d
	plan.xf = Transform3D(Basis(Vector3.UP, deg_to_rad(float(lot.yaw))), Vector3(c.x, y0, c.y))
	if not plan.has("kind"):
		plan.kind = kind
	plan.district = str(lot.get("district", "site"))
	plan.style = "concrete"
	plan.base_h = maxf(y0 - gy + 0.3, 0.3)
	var out: Dictionary = mb.house(plan)
	lot.bid = int(out.id)
	return out


static func _run(h: float) -> float:
	return ceilf(h / RISER) * TREAD


static func _core_stairs(floors: Array, cx: float, z0: float, h: float) -> void:
	## Switchback stairs in a core whose front edge is z0: even floors climb +z on the west lane, odd floors climb -z
	## on the east lane, so no flight sits under the opening of the one below. Needs a core 2.4 m wide and
	## 1.0 + run + 1.4 m deep.
	var run := _run(h)
	for f in floors.size() - 1:
		if f % 2 == 0:
			floors[f].stair = {"start": Vector2(cx - 0.6, z0 + 1.0), "dir": "+z", "w": 1.0, "to": f + 1, "side": Vector2(1, 0)}
		else:
			floors[f].stair = {"start": Vector2(cx + 0.6, z0 + 1.0 + run), "dir": "-z", "w": 1.0, "to": f + 1, "side": Vector2(-1, 0)}


static func _office_tower(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var h := 3.4
	var cz0 := 1.0
	var floors := []
	for f in maxi(n, 2):
		var rooms := []
		if f == 0:
			rooms.append({"type": "lobby", "rect": [-X * 0.45, -Z, X * 0.45, -1.0]})
			rooms.append({"type": "office", "rect": [-X, -Z, -X * 0.45, -1.0]})
			rooms.append({"type": "office", "rect": [X * 0.45, -Z, X, -1.0]})
		else:
			for k in 4:
				rooms.append({"type": "office", "rect": [-X + w * k / 4.0, -Z, -X + w * (k + 1) / 4.0, -1.0]})
		rooms.append({"type": "corridor", "rect": [-X, -1.0, X, cz0], "windows": 0 if f > 0 else 1})
		rooms.append({"type": "office", "rect": [-X, cz0, -X * 0.5, Z]})
		rooms.append({"type": "storage" if f == 0 else "office", "rect": [-X * 0.5, cz0, -1.6, Z]})
		rooms.append({"type": "stair", "rect": [-1.6, cz0, 1.6, Z], "windows": 0})
		rooms.append({"type": "toilet", "rect": [1.6, cz0, X * 0.45, Z]})
		rooms.append({"type": "office", "rect": [X * 0.45, cz0, X, Z]})
		var F := {"h": h, "rooms": rooms}
		if f == 0:
			F.ext = {"front": [{"type": "opening", "x": 0.0, "w": 2.6, "h": 2.6}],
				"left": [{"type": "door", "x": 0.0, "w": 1.0, "door_mat": "metal_paint"}],
				"right": [{"type": "door", "x": 0.0, "w": 1.0, "door_mat": "metal_paint"}],
				"back": [{"type": "door", "x": 0.0, "w": 1.0, "role": "back", "door_mat": "metal_paint"}]}
		floors.append(F)
	_core_stairs(floors, 0.0, cz0, h)
	return {"kind": "office", "floors": floors, "ext_mat": "facade_tile", "ext_tint": Color(0.78, 0.8, 0.82), "win_mix": {"glass": 0.8, "open": 0.15, "shutter": 0.05},
		"roof": {"type": "flat", "parapet": 1.1, "ladder": {"side": "back", "x": X - 3.0}, "tank": true}}


static func _apartment(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var h := 3.0
	var cz0 := 1.0
	var types := ["sala", "bedroom", "kitchen"]
	var floors := []
	for f in maxi(n, 2):
		var rooms := []
		for k in 3:
			rooms.append({"type": types[(k + f) % 3], "rect": [-X + w * k / 3.0, -Z, -X + w * (k + 1) / 3.0, -1.0]})
		rooms.append({"type": "corridor", "rect": [-X, -1.0, X, cz0], "windows": 0})
		rooms.append({"type": types[(f + 1) % 3], "rect": [-X, cz0, -1.6, Z]})
		rooms.append({"type": "stair", "rect": [-1.6, cz0, 1.6, Z], "windows": 0})
		rooms.append({"type": "bedroom" if f % 2 == 0 else "bath", "rect": [1.6, cz0, X, Z]})
		var F := {"h": h, "rooms": rooms}
		if f == 0:
			F.ext = {"left": [{"type": "door", "x": 0.0, "w": 1.0, "door_mat": "planks_paint"}],
				"right": [{"type": "door", "x": 0.0, "w": 1.0, "door_mat": "planks_paint"}],
				"back": [{"type": "door", "x": 0.0, "w": 1.0, "role": "back", "door_mat": "metal_paint"}]}
		else:
			F.balcony = {"side": "front", "c0": -X + 1.0, "c1": X - 1.0, "depth": 1.1}
		floors.append(F)
	_core_stairs(floors, 0.0, cz0, h)
	return {"kind": "house", "floors": floors, "ext_mat": "wall_beige", "ext_tint": Color(0.9, 0.86, 0.76).lerp(Color(0.8, 0.86, 0.9), rng.randf()),
		"roof": {"type": "flat", "parapet": 1.0, "ladder": {"side": "back", "x": -X + 2.0}, "tank": true}}


static func _clubhouse(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var sx0 := X - 8.5
	var sx1 := sx0 + 3.5
	var g := {"h": 3.4, "rooms": [
		{"type": "hall", "rect": [-X, -Z, sx0, Z]},
		{"type": "kitchen", "rect": [sx0, -Z, X, -1.0]},
		{"type": "stair", "rect": [sx0, -1.0, sx1, Z], "windows": 0},
		{"type": "office", "rect": [sx1, -1.0, X, 4.0]},
		{"type": "toilet", "rect": [sx1, 4.0, X, Z]},
	], "ext": {
		"front": [{"type": "door", "x": -X * 0.5, "w": 1.6, "h": 2.4, "door_mat": "planks_dark"}],
		"back": [{"type": "door", "x": -X * 0.6, "w": 1.0, "role": "back"}],
		"right": [{"type": "door", "x": -Z * 0.5, "w": 1.0, "role": "back"}],
	}, "stair": {"start": Vector2((sx0 + sx1) * 0.5, 0.0), "dir": "+z", "w": 1.1, "to": 1}}
	var u := {"h": 3.2, "rooms": [
		{"type": "hall", "rect": [-X, -Z, sx0, Z]},
		{"type": "storage", "rect": [sx0, -Z, X, -1.0]},
		{"type": "corridor", "rect": [sx0, -1.0, sx1, Z], "windows": 0},
		{"type": "office", "rect": [sx1, -1.0, X, Z]},
	], "balcony": {"side": "front", "c0": -X + 1.0, "c1": sx0 - 1.0, "depth": 1.6}}
	return {"kind": "hall", "floors": [g, u], "ext_mat": "wall_painted", "ext_tint": Color(0.95, 0.9, 0.8), "roof": {"type": "hip", "mat": "roof_tiles", "pitch": 0.4}}


static func _chapel(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var g := {"h": 6.0, "rooms": [
		{"type": "chapel", "rect": [-X, -Z, X, Z - 4.0]},
		{"type": "office", "rect": [-X, Z - 4.0, 0.0, Z], "h": 3.0},
		{"type": "storage", "rect": [0.0, Z - 4.0, X, Z], "h": 3.0},
	], "ext": {
		"front": [{"type": "door", "x": 0.0, "w": 1.8, "h": 2.8, "door_mat": "planks_dark"}],
		"left": [{"type": "door", "x": -2.0, "w": 1.0}],
		"right": [{"type": "door", "x": -2.0, "w": 1.0}],
	}}
	return {"kind": "chapel", "floors": [g], "ext_mat": "wall_painted", "ext_tint": Color(0.96, 0.95, 0.9),
		"roof": {"type": "gable", "mat": "roof_tiles_grey", "pitch": 0.6, "ridge": "z"}}


static func _store(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var zb := Z - 5.0
	var g := {"h": 4.2, "rooms": [
		{"type": "store_aisles", "rect": [-X, -Z, X, zb]},
		{"type": "stock_room", "rect": [-X, zb, X - 7.0, Z]},
		{"type": "office", "rect": [X - 7.0, zb, X - 3.0, Z]},
		{"type": "toilet", "rect": [X - 3.0, zb, X, Z]},
	], "ext": {
		"front": [{"type": "opening", "x": -X + 4.5, "w": 2.2, "h": 2.5}, {"type": "opening", "x": X - 4.5, "w": 2.2, "h": 2.5}],
		"back": [{"type": "door", "x": -X + 3.0, "w": 1.2, "role": "back", "door_mat": "metal_paint"}],
		"left": [{"type": "door", "x": -Z * 0.3, "w": 1.0, "door_mat": "metal_paint"}],
	}}
	return {"kind": "store", "floors": [g], "ext_mat": "cladding", "ext_tint": Color(0.95, 0.95, 0.95), "win_mix": {"glass": 0.9, "open": 0.1, "shutter": 0.0},
		"roof": {"type": "flat", "parapet": 0.8, "ladder": {"side": "back", "x": X - 1.5}, "tank": false}}


static func _strip_shops(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var zb := Z - 3.0
	var types := ["shop", "dining", "utility", "shop"]
	var rooms := []
	var front := []
	var back := []
	var links := []
	for k in 4:
		var x0 := -X + w * k / 4.0
		var x1 := -X + w * (k + 1) / 4.0
		rooms.append({"type": types[k], "rect": [x0, -Z, x1, zb], "id": "s%d" % k})
		rooms.append({"type": "storage", "rect": [x0, zb, x1, Z], "id": "b%d" % k})
		front.append({"type": "opening", "x": (x0 + x1) * 0.5, "w": minf(x1 - x0 - 2.0, 3.6), "h": 2.5})
		back.append({"type": "door", "x": (x0 + x1) * 0.5, "w": 0.95, "role": "back", "door_mat": "metal_paint"})
		links.append(["s%d" % k, "b%d" % k, "door"])
		if k > 0:
			links.append(["s%d" % (k - 1), "s%d" % k, "none"])
			links.append(["b%d" % (k - 1), "b%d" % k, "none"])
			links.append(["s%d" % (k - 1), "b%d" % k, "none"])
			links.append(["b%d" % (k - 1), "s%d" % k, "none"])
	var g := {"h": 3.8, "rooms": rooms, "links": links, "ext": {"front": front, "back": back}}
	return {"kind": "store", "floors": [g], "ext_mat": "wall_grey", "ext_tint": Color(0.9, 0.86, 0.74),
		"roof": {"type": "flat", "parapet": 0.7, "ladder": {"side": "back", "x": X - 1.0}, "tank": true}}


static func _factory(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var ox := X - 10.0                # offices east of this, under the mezzanine
	var g := {"h": 9.0, "rooms": [
		{"type": "factory_floor", "rect": [-X, -Z, ox, Z]},
		{"type": "office", "rect": [ox, -Z, X, -3.0], "h": 3.2},
		{"type": "toilet", "rect": [ox, -3.0, ox + 4.0, 3.0], "h": 3.2},
		{"type": "storage", "rect": [ox + 4.0, -3.0, X, 3.0], "h": 3.2},
		{"type": "office", "rect": [ox, 3.0, X, Z], "h": 3.2},
	], "ext": {
		"front": [{"type": "opening", "x": -X * 0.55, "w": 4.2, "h": 4.0}, {"type": "opening", "x": -X * 0.05, "w": 4.2, "h": 4.0},
			{"type": "door", "x": ox + 3.0, "w": 1.0, "door_mat": "metal_paint"}],
		"back": [{"type": "door", "x": -X * 0.4, "w": 1.2, "role": "back", "door_mat": "metal_paint"}, {"type": "door", "x": ox + 5.0, "w": 1.0, "role": "back", "door_mat": "metal_paint"}],
		"left": [{"type": "opening", "x": 0.0, "w": 3.6, "h": 3.6}],
	}, "stair": {"start": Vector2(ox - 0.9, -Z + 3.0), "dir": "+z", "w": 1.0, "to": 1, "side": Vector2(1, 0), "mat": "metal_plate"}}
	var m := {"y": 3.4, "h": 5.6, "mezzanine": true, "rooms": [{"type": "mezzanine", "rect": [ox - 1.6, -Z + 0.3, X - 0.3, Z - 0.3]}]}
	return {"kind": "factory", "floors": [g, m], "ext_mat": "factory_wall", "ext_tint": Color(0.82, 0.84, 0.86), "win_mix": {"glass": 0.5, "open": 0.4, "shutter": 0.1},
		"roof": {"type": "gable", "mat": "metal_sheet", "pitch": 0.22, "over": 0.4}}


static func _warehouse(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var g := {"h": 8.0, "rooms": [
		{"type": "warehouse", "rect": [-X, -Z, X, Z - 5.0]},
		{"type": "office", "rect": [-X, Z - 5.0, -X + 9.0, Z], "h": 3.0},
		{"type": "stock_room", "rect": [-X + 9.0, Z - 5.0, X, Z], "h": 3.0},
	], "ext": {
		"front": [{"type": "opening", "x": -X * 0.4, "w": 4.5, "h": 4.2}, {"type": "opening", "x": X * 0.4, "w": 4.5, "h": 4.2}],
		"back": [{"type": "door", "x": -X + 4.5, "w": 1.0, "role": "back", "door_mat": "metal_paint"}],
		"right": [{"type": "door", "x": -2.0, "w": 1.0, "door_mat": "metal_paint"}],
	}}
	return {"kind": "warehouse", "floors": [g], "ext_mat": "factory_wall", "ext_tint": Color(0.72, 0.76, 0.72),
		"roof": {"type": "gable", "mat": "metal_sheet", "pitch": 0.2, "over": 0.4}}


static func _guardhouse(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var X := w * 0.5
	var Z := d * 0.5
	var g := {"h": 3.0, "rooms": [{"type": "office", "rect": [-X, -Z, X, Z]}], "ext": {
		"front": [{"type": "door", "x": -X * 0.4, "w": 0.95}], "back": [{"type": "door", "x": X * 0.4, "w": 0.95, "role": "back"}]}}
	return {"kind": "outpost", "floors": [g], "ext_mat": "wall_painted", "ext_tint": Color(0.9, 0.86, 0.76), "roof": {"type": "hip", "mat": "roof_tiles", "pitch": 0.4}}


static func _guard_booth(w: float, d: float, n: int, rng: RandomNumberGenerator) -> Dictionary:
	var p := _guardhouse(w, d, n, rng)
	p.floors[0].h = 2.6
	p.roof = {"type": "flat", "parapet": 0.2, "tank": false}
	return p
