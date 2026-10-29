extends RefCounted
## Lawless Sub's big lots. Enclosed kinds are real buildings from big_plans.gd (rooms, stairs, doors, loot); the
## open kinds keep their landmark shapes here: the pool's rim and floor, the court's posts and roof, tanks, the water
## tower, container stacks, the fuel canopy. Entry point: static func build(mb, lot) -> void (lot: layout.lots record).

const Houses := preload("res://src/world/maps/lawless_sub/houses.gd")
const BigPlans := preload("res://src/world/maps/lawless_sub/big_plans.gd")

const SHELLS := {
	# kind: [storey height, wall material, roof material, tint]
	"office_tower": [3.4, "facade_tile", "concrete", Color(0.75, 0.78, 0.8)],
	"apartment": [3.0, "wall_beige", "concrete", Color(0.92, 0.88, 0.78)],
	"guardhouse": [3.0, "wall_painted", "roof_tiles", Color(0.9, 0.86, 0.76)],
	"guard_booth": [2.6, "metal_paint", "metal_sheet", Color(0.8, 0.8, 0.76)],
	"clubhouse": [3.4, "wall_painted", "roof_tiles", Color(0.95, 0.9, 0.8)],
	"chapel": [6.0, "wall_painted", "roof_tiles_grey", Color(0.95, 0.94, 0.9)],
	"store": [4.5, "cladding", "metal_sheet", Color(0.95, 0.95, 0.95)],
	"strip_shops": [4.0, "wall_grey", "concrete", Color(0.88, 0.84, 0.72)],
	"factory": [9.0, "factory_wall", "metal_sheet", Color(0.8, 0.82, 0.84)],
	"warehouse": [8.0, "factory_wall", "metal_sheet", Color(0.7, 0.74, 0.7)],
}


static func build(mb, lot: Dictionary) -> void:
	var kind := str(lot.kind)
	var c: Vector2 = lot.center
	var half: Vector2 = lot.half
	var basis := Basis(Vector3.UP, deg_to_rad(float(lot.yaw)))
	var y0 := float(lot.plinth_y)
	var xf := Transform3D(basis, Vector3(c.x, y0, c.y))
	var gy: float = mb.layout.ground_height(c.x, c.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lot.seed)
	if BigPlans.handles(kind):
		BigPlans.build(mb, lot)
		if kind == "chapel":
			# The bell tower over the front door.
			var d0 := half.y * 2.0
			mb.sink.box(xf * Transform3D(Basis(), Vector3(0, 4.5, -d0 * 0.5 - 1.3)), Vector3(2.6, 9.0, 2.6), "wall_painted",
				{"dirt": 0.5, "tint": Color(0.96, 0.95, 0.9), "paint": 0.7, "occlude": true, "what": "tower"})
			mb.sink.box(xf * Transform3D(Basis(), Vector3(0, 9.4, -d0 * 0.5 - 1.3)), Vector3(3.0, 0.8, 3.0), "roof_tiles_grey", {"dirt": 0.5, "what": "roof"})
		return
	if SHELLS.has(kind):
		var s: Array = SHELLS[kind]
		var floors := maxi(int(lot.floors), 1)
		var fh := float(s[0])
		var w := half.x * 2.0
		var d := half.y * 2.0
		var tint: Color = s[3]
		_shell(mb, xf, w, d, floors, fh, str(s[1]), tint, gy, minf(w * 0.35, 6.0))
		var top := floors * fh
		mb.sink.box(xf * Transform3D(Basis(), Vector3(0, top + 0.15, 0)), Vector3(w + 0.4, 0.3, d + 0.4), str(s[2]), {"dirt": 0.6, "inner_faces": 8, "what": "roof"})
		if kind == "office_tower":
			mb.sink.box(xf * Transform3D(Basis(), Vector3(0, top + 0.9, 0)), Vector3(w + 0.4, 1.2, d + 0.4), "concrete", {"faces": 51, "dirt": 0.6, "what": "parapet"})
			mb.sink.cylinder(xf * Vector3(w * 0.25, top + 0.3, d * 0.15), Vector3.UP, 2.6, 1.4, "metal_plate", {"sides": 10, "collide": true})
		if kind == "chapel":
			mb.sink.box(xf * Transform3D(Basis(), Vector3(0, top + 3.0, -d * 0.5 + 1.2)), Vector3(2.4, 6.0, 2.4), "wall_painted", {"dirt": 0.6, "tint": tint, "paint": 0.7})
		Houses.register(mb, lot, xf, w, d, floors, top + 0.3, "concrete", tint)
		return
	match kind:
		"gas_station":
			_gas_station(mb, lot, xf, gy)
		"pool":
			_pool(mb, lot, xf)
		"court":
			_court(mb, lot, xf)
		"playground":
			_slab(mb, xf, half * 2.0, "patio", Color(0.9, 0.7, 0.5))
			_record(mb, lot, xf, half, 0.3)
		"tank":
			mb.sink.cylinder(Vector3(c.x, gy, c.y), Vector3.UP, 8.5, minf(half.x, half.y) - 0.3, "metal_plate",
				{"sides": 16, "collide": true, "phys": "steel", "tint": Color(0.86, 0.88, 0.9), "paint": 0.6})
			mb.sink.box(Transform3D(Basis(), Vector3(c.x, gy + 8.55, c.y)), Vector3(half.x * 1.35, 0.1, half.y * 1.35), "metal_plate", {"dirt": 0.4})
			mb.sink.far_block(Transform3D(Basis(), Vector3(c.x, gy + 4.25, c.y)), Vector3(half.x * 1.8, 8.5, half.y * 1.8), Color(0.55, 0.56, 0.58), Color(0.6, 0.6, 0.6))
			_record(mb, lot, xf, half, 8.5)
		"water_tower":
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					mb.sink.box(Transform3D(Basis(), Vector3(c.x + sx * (half.x - 0.6), gy + 7.0, c.y + sz * (half.y - 0.6))), Vector3(0.4, 14.0, 0.4), "metal_rust", {"phys": "steel"})
			mb.sink.cylinder(Vector3(c.x, gy + 14.0, c.y), Vector3.UP, 5.0, minf(half.x, half.y) - 0.2, "metal_paint", {"sides": 16, "collide": true, "tint": Color(0.75, 0.8, 0.85), "paint": 0.7})
			mb.sink.box(Transform3D(Basis(), Vector3(c.x, gy + 19.05, c.y)), Vector3(half.x * 1.4, 0.1, half.y * 1.4), "metal_paint", {"tint": Color(0.75, 0.8, 0.85), "paint": 0.7})
			mb.sink.far_block(Transform3D(Basis(), Vector3(c.x, gy + 9.5, c.y)), Vector3(half.x * 2.0, 19.0, half.y * 2.0), Color(0.5, 0.52, 0.55), Color(0.45, 0.45, 0.45))
			_record(mb, lot, xf, half, 19.0)
		"container_yard":
			_containers(mb, lot, xf, rng)
		_:
			_slab(mb, xf, half * 2.0, "concrete_floor2", Color(1, 1, 1))
			_record(mb, lot, xf, half, 0.3)


static func _shell(mb, xf: Transform3D, w: float, d: float, floors: int, fh: float, mat: String, tint: Color, gy: float, door_w: float) -> void:
	## A walk-in ground floor (door gap in the front, local -z) and a closed block above, with this kind's storey height.
	var sink = mb.sink
	var plinth := maxf(xf.origin.y - gy + 0.25, 0.3)
	sink.box(xf * Transform3D(Basis(), Vector3(0, -plinth * 0.5 + 0.02, 0)), Vector3(w, plinth + 0.04, d), "concrete_floor2", {"dirt": 0.5, "what": "floor"})
	var o := {"dirt": 0.6, "tint": tint, "paint": 0.6, "occlude": true, "what": "wall"}
	var t := 0.3
	sink.box(xf * Transform3D(Basis(), Vector3(0, fh * 0.5, d * 0.5 - t * 0.5)), Vector3(w, fh, t), mat, o)
	for s in [-1.0, 1.0]:
		sink.box(xf * Transform3D(Basis(), Vector3(s * (w * 0.5 - t * 0.5), fh * 0.5, 0)), Vector3(t, fh, d - t * 2.0), mat, o)
	var dl := -door_w * 0.5
	var dr := door_w * 0.5
	var zf := -d * 0.5 + t * 0.5
	sink.box(xf * Transform3D(Basis(), Vector3((-w * 0.5 + dl) * 0.5, fh * 0.5, zf)), Vector3(dl + w * 0.5, fh, t), mat, o)
	sink.box(xf * Transform3D(Basis(), Vector3((dr + w * 0.5) * 0.5, fh * 0.5, zf)), Vector3(w * 0.5 - dr, fh, t), mat, o)
	var dh := minf(2.6, fh - 0.4)
	sink.box(xf * Transform3D(Basis(), Vector3(0, (dh + fh) * 0.5, zf)), Vector3(door_w, fh - dh, t), mat, o)
	if floors > 1:
		var uh := (floors - 1) * fh
		sink.box(xf * Transform3D(Basis(), Vector3(0, fh + uh * 0.5, 0)), Vector3(w, uh, d), mat,
			{"dirt": 0.6, "tint": tint, "paint": 0.6, "occlude": true, "inner_faces": 8, "what": "wall"})
	else:
		sink.box(xf * Transform3D(Basis(), Vector3(0, fh - 0.08, 0)), Vector3(w, 0.16, d), "concrete", {"dirt": 0.5, "inner_faces": 8, "what": "ceiling"})


static func _slab(mb, xf: Transform3D, size: Vector2, mat: String, tint: Color) -> void:
	var painted := tint != Color(1, 1, 1)
	mb.sink.box(xf * Transform3D(Basis(), Vector3(0, -0.1, 0)), Vector3(size.x, 0.3, size.y), mat,
		{"faces": 55, "dirt": 0.5, "tint": tint, "paint": 0.3 if painted else 0.0, "what": "slab"})


static func _record(mb, lot: Dictionary, xf: Transform3D, half: Vector2, top: float) -> void:
	var id: int = mb.new_building_id()
	mb.buildings.append({"id": id, "xf": xf, "w": half.x * 2.0, "d": half.y * 2.0, "kind": str(lot.kind), "district": "site", "style": "concrete",
		"floors": 1, "covered": false, "deck": false, "top": top, "front_open": [], "h0": top, "lot": int(lot.id), "open": true})
	lot.bid = id


static func _gas_station(mb, lot: Dictionary, xf: Transform3D, gy: float) -> void:
	var half: Vector2 = lot.half
	_slab(mb, xf, half * 2.0, "concrete_floor2", Color(1, 1, 1))
	# Canopy on four columns over the pump islands, a kiosk at the back.
	var cw := half.x * 1.3
	var cd := half.y * 0.8
	var cz := -half.y * 0.15
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mb.sink.box(xf * Transform3D(Basis(), Vector3(sx * cw * 0.35, 2.6, cz + sz * cd * 0.3)), Vector3(0.45, 5.2, 0.45), "metal_paint", {"tint": Color(0.9, 0.9, 0.88), "paint": 0.8})
		mb.sink.box(xf * Transform3D(Basis(), Vector3(sx * cw * 0.35, 0.6, cz)), Vector3(1.2, 1.2, cd * 0.55), "metal_paint", {"tint": Color(0.75, 0.2, 0.15), "paint": 0.8, "what": "pump_island"})
	mb.sink.box(xf * Transform3D(Basis(), Vector3(0, 5.5, cz)), Vector3(cw, 0.6, cd), "metal_paint", {"tint": Color(0.92, 0.92, 0.9), "paint": 0.85, "inner_faces": 8, "what": "canopy"})
	# The kiosk floor sits 4 cm over the forecourt slab (at 1 cm the two z-fought).
	var kx := Transform3D(xf.basis, xf * Vector3(0, 0.04, half.y - 4.5))
	_shell(mb, kx, half.x * 0.7, 7.0, 1, 3.6, "cladding", Color(0.95, 0.95, 0.95), gy, 2.0)
	mb.sink.box(kx * Transform3D(Basis(), Vector3(0, 3.75, 0)), Vector3(half.x * 0.7 + 0.4, 0.3, 7.4), "concrete", {"dirt": 0.5})
	_record(mb, lot, xf, half, 6.0)


static func _pool(mb, lot: Dictionary, xf: Transform3D) -> void:
	## Placeholder: the deck and a rim round a drained basin (the floor painted pool blue). Not sunk yet.
	var half: Vector2 = lot.half
	_slab(mb, xf, half * 2.0, "patio", Color(1, 1, 1))
	var pw := half.x * 2.0 - 3.0
	var pd := half.y * 2.0 - 3.0
	mb.sink.box(xf * Transform3D(Basis(), Vector3(0, 0.08, 0)), Vector3(pw, 0.06, pd), "tiles_blue", {"faces": 4, "dirt": 0.7, "what": "pool_floor"})
	for s in [-1.0, 1.0]:
		mb.sink.box(xf * Transform3D(Basis(), Vector3(s * pw * 0.5, 0.35, 0)), Vector3(0.3, 0.5, pd), "tiles_white", {"dirt": 0.6})
		mb.sink.box(xf * Transform3D(Basis(), Vector3(0, 0.35, s * pd * 0.5)), Vector3(pw, 0.5, 0.3), "tiles_white", {"dirt": 0.6})
	_record(mb, lot, xf, half, 0.6)


static func _court(mb, lot: Dictionary, xf: Transform3D) -> void:
	var half: Vector2 = lot.half
	_slab(mb, xf, half * 2.0, "concrete_painted", Color(0.45, 0.6, 0.5))
	var h := 7.5
	var n := 4
	for s in [-1.0, 1.0]:
		for i in n:
			var z := -half.y + 1.0 + (half.y * 2.0 - 2.0) * i / (n - 1)
			mb.sink.box(xf * Transform3D(Basis(), Vector3(s * (half.x - 0.5), h * 0.5, z)), Vector3(0.35, h, 0.35), "metal_paint", {"tint": Color(0.3, 0.45, 0.6), "paint": 0.7})
	mb.sink.box(xf * Transform3D(Basis(), Vector3(0, h + 0.1, 0)), Vector3(half.x * 2.0 + 1.0, 0.12, half.y * 2.0 + 1.0), "yero_paint",
		{"tint": Color(0.3, 0.45, 0.6), "paint": 0.8, "inner_faces": 8, "what": "court_roof"})
	for s2 in [-1.0, 1.0]:
		mb.sink.box(xf * Transform3D(Basis(), Vector3(0, 3.0, s2 * (half.y - 1.2))), Vector3(1.8, 1.1, 0.1), "plywood", {"dirt": 0.6})
	mb.sink.far_block(xf * Transform3D(Basis(), Vector3(0, h * 0.5, 0)), Vector3(half.x * 2.0, h, half.y * 2.0), Color(0.3, 0.4, 0.5), Color(0.3, 0.42, 0.55))
	_record(mb, lot, xf, half, h)


static func _containers(mb, lot: Dictionary, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	## Rows of 12 m containers, stacked one to three high, with aisles between the rows.
	var half: Vector2 = lot.half
	_slab(mb, xf, half * 2.0, "concrete_floor2", Color(1, 1, 1))
	var cols := [Color(0.62, 0.2, 0.15), Color(0.18, 0.34, 0.55), Color(0.3, 0.46, 0.3), Color(0.7, 0.55, 0.2), Color(0.5, 0.5, 0.52)]
	var x := -half.x + 2.0
	while x + 2.44 <= half.x - 1.0:
		var z := -half.y + 1.0
		while z + 12.2 <= half.y - 0.5:
			var stack := rng.randi_range(0, 3)
			for k in stack:
				mb.sink.box(xf * Transform3D(Basis(), Vector3(x + 1.22, 1.3 + k * 2.6, z + 6.1)), Vector3(2.44, 2.59, 12.2), "container",
					{"dirt": 0.5, "tint": cols[rng.randi_range(0, cols.size() - 1)], "paint": 0.75, "occlude": true, "what": "container"})
			z += 12.2 + 1.2
		x += 2.44 + (5.5 if rng.randf() < 0.5 else 0.6)
	mb.sink.far_block(xf * Transform3D(Basis(), Vector3(0, 2.6, 0)), Vector3(half.x * 2.0, 5.2, half.y * 2.0), Color(0.4, 0.3, 0.25), Color(0.4, 0.35, 0.3))
	_record(mb, lot, xf, half, 7.8)
