extends RefCounted
## Civil-service and shopfront details for Lawless Sub. Geometry joins the existing chunk/material batches;
## there are no nodes, lights, colliders or per-frame work. Building openings and roof ladders stay clear.

const SIGNS := "decal:res://assets/urban/signs.png"
const CREAM := Color(0.86, 0.84, 0.74)
const CHARCOAL := Color(0.24, 0.29, 0.29)
const SHOP_COLORS := [Color(0.21, 0.43, 0.38), Color(0.58, 0.25, 0.17), Color(0.21, 0.34, 0.48), Color(0.65, 0.48, 0.22)]

var mb = null
var sink = null
var lots_by_bid := {}
var holes_by_bid := {}
var buildings_by_bid := {}
var stats := {"buildings": 0, "gutters": 0, "downpipes": 0, "meters": 0, "condensers": 0,
	"awnings": 0, "signs": 0, "pilasters": 0, "roof_vents": 0, "landmarks": 0, "skipped_openings": 0,
	"window_surrounds": 0, "entrance_surrounds": 0, "slab_bands": 0, "plinths": 0}


static func build_all(map_builder, layout) -> void:
	var detail = new(map_builder)
	detail.build(layout)


func _init(map_builder) -> void:
	mb = map_builder
	sink = mb.sink


func build(layout) -> void:
	for lot in layout.lots:
		if lot.has("bid"):
			lots_by_bid[int(lot.bid)] = lot
	for b in mb.buildings:
		buildings_by_bid[int(b.id)] = b
	_index_openings()
	_opening_relief()
	for b in mb.buildings:
		var lot: Dictionary = lots_by_bid.get(int(b.id), {})
		if lot.is_empty():
			continue
		if bool(b.get("open", false)):
			_landmark(b, lot)
			continue
		_facade(b, lot)
	mb.stats.facades = stats


func _index_openings() -> void:
	for o in mb.dyn.windows:
		_add_opening(int(o.get("bid", -1)), o.xf, float(o.w), float(o.h))
	for o in mb.dyn.doors:
		var xf: Transform3D = o.xf
		_add_opening(int(o.get("bid", -1)), xf * Transform3D(Basis(), Vector3(float(o.w) * 0.5, float(o.h) * 0.5, 0)), float(o.w), float(o.h))
	for o in mb.dyn.doorways:
		var xf := Transform3D(Basis(o.u, Vector3.UP, o.n), o.c + Vector3.UP * float(o.h) * 0.5)
		_add_opening(int(o.get("bid", -1)), xf, float(o.w), float(o.h))


func _add_opening(bid: int, xf: Transform3D, w: float, h: float) -> void:
	if not holes_by_bid.has(bid):
		holes_by_bid[bid] = []
	holes_by_bid[bid].append({"xf": xf, "w": w + 0.3, "h": h + 0.2})


func _clear(b: Dictionary, c: Vector3, size: Vector3, own_opening: Vector3 = Vector3.INF) -> bool:
	var inv: Transform3D = (b.xf as Transform3D).affine_inverse()
	var bounds := AABB(c - size * 0.5, size)
	for hole in holes_by_bid.get(int(b.id), []):
		if (hole.xf as Transform3D).origin.distance_squared_to(own_opening) < 0.0001:
			continue
		var hx: Transform3D = inv * (hole.xf as Transform3D)
		var half: Vector3 = hx.basis.x.abs() * float(hole.w) * 0.5 + Vector3.UP * float(hole.h) * 0.5 + hx.basis.z.abs() * 0.7
		if bounds.intersects(AABB(hx.origin - half, half * 2.0)):
			stats.skipped_openings += 1
			return false
	for ladder in mb.ladders:
		var foot: Vector3 = inv * (ladder.base as Vector3)
		var top: float = float(ladder.top_y) - (b.xf as Transform3D).origin.y
		var low := Vector3(foot.x - 0.8, foot.y - 0.2, foot.z - 0.8)
		var extent := Vector3(1.6, maxf(top - foot.y + 0.6, 0.5), 1.6)
		if bounds.intersects(AABB(low, extent)):
			stats.skipped_openings += 1
			return false
	return true


func _opening_relief() -> void:
	# Each surround follows a real opening, rather than painting another repeated motif across a blank facade.
	for opening in mb.dyn.windows:
		var b: Dictionary = buildings_by_bid.get(int(opening.get("bid", -1)), {})
		if b.is_empty() or not _on_shell(b, (opening.xf as Transform3D).origin):
			continue
		_surround(b, (opening.xf as Transform3D).origin, opening.outward, float(opening.w), float(opening.h), float(opening.get("t", 0.22)), true)
		stats.window_surrounds += 1
	for opening in mb.dyn.doors:
		if not bool(opening.get("outer", false)):
			continue
		var b: Dictionary = buildings_by_bid.get(int(opening.get("bid", -1)), {})
		if b.is_empty():
			continue
		var ox: Transform3D = opening.xf
		var center: Vector3 = ox * Vector3(float(opening.w) * 0.5, float(opening.h) * 0.5, 0)
		_surround(b, center, opening.outward, float(opening.w), float(opening.h), 0.22, false)
		stats.entrance_surrounds += 1
	for opening in mb.dyn.doorways:
		var b: Dictionary = buildings_by_bid.get(int(opening.get("bid", -1)), {})
		if b.is_empty() or not _on_shell(b, opening.c):
			continue
		var center: Vector3 = opening.c + Vector3.UP * float(opening.h) * 0.5
		_surround(b, center, opening.n, float(opening.w), float(opening.h), 0.22, false)
		stats.entrance_surrounds += 1


func _on_shell(b: Dictionary, p: Vector3) -> bool:
	var local: Vector3 = (b.xf as Transform3D).affine_inverse() * p
	return absf(absf(local.x) - float(b.w) * 0.5) < 0.4 or absf(absf(local.z) - float(b.d) * 0.5) < 0.4


func _surround(b: Dictionary, center: Vector3, outward: Vector3, w: float, h: float, wall_t: float, window: bool) -> void:
	var normal := outward.normalized()
	var fx := Transform3D(Basis(Vector3.UP.cross(normal).normalized(), Vector3.UP, normal), center)
	var z := wall_t * 0.5 + 0.085
	var tint := Color(0.76, 0.74, 0.65) if str(b.kind) in ["factory", "warehouse"] else CREAM
	for side in [-1.0, 1.0]:
		_relief_box(b, fx, Vector3(side * (w * 0.5 + 0.13), 0, z), Vector3(0.2, h + 0.3, 0.24), tint)
	if window:
		# Proud sill and broad weather hood cast separate shadows; their inner edges stay outside the aperture.
		_relief_box(b, fx, Vector3(0, -h * 0.5 - 0.09, wall_t * 0.5 + 0.13), Vector3(w + 0.44, 0.14, 0.42), tint)
		_relief_box(b, fx, Vector3(0, h * 0.5 + 0.13, wall_t * 0.5 + 0.22), Vector3(w + 0.48, 0.16, 0.64), tint)
	else:
		_relief_box(b, fx, Vector3(0, h * 0.5 + 0.13, z + 0.035), Vector3(w + 0.5, 0.2, 0.32), tint)


func _relief_box(b: Dictionary, fx: Transform3D, c: Vector3, size: Vector3, tint: Color) -> void:
	var inv: Transform3D = (b.xf as Transform3D).affine_inverse()
	var axes: Basis = inv.basis * fx.basis
	var half := axes.x.abs() * size.x * 0.5 + axes.y.abs() * size.y * 0.5 + axes.z.abs() * size.z * 0.5
	if _clear(b, inv * (fx * c), half * 2.0, fx.origin):
		_box(fx, c, size, "concrete", tint, 63)


func _box(xf: Transform3D, c: Vector3, size: Vector3, mat: String, tint: Color = CREAM, faces: int = 55) -> void:
	sink.box(xf * Transform3D(Basis(), c), size, mat,
		{"collide": false, "occlude": false, "tint": tint, "paint": 0.85, "dirt": 0.32, "faces": faces, "what": "facade_detail"})


func _pipe(xf: Transform3D, a: Vector3, b: Vector3, radius: float, tint: Color = CREAM) -> void:
	var direction := b - a
	if direction.length_squared() < 0.0001:
		return
	sink.cylinder(xf * a, xf.basis * direction.normalized(), direction.length(), radius, "metal_paint",
		{"sides": 6, "collide": false, "tint": tint, "paint": 0.8, "dirt": 0.35})


func _facade(b: Dictionary, lot: Dictionary) -> void:
	var xf: Transform3D = b.xf
	var kind := str(lot.kind)
	var X := float(b.w) * 0.5
	var Z := float(b.d) * 0.5
	var industrial := kind in ["factory", "warehouse"]
	var height := float(b.h0) * int(b.floors)
	if industrial:
		height = float(b.h0)
	height = minf(height, float(b.top) - 0.15)
	var seed_value := absi(int(lot.seed))
	stats.buildings += 1
	_edge_relief(b, xf, X, Z)
	_drainage(b, xf, X, Z, height)
	_meter(b, xf, X, Z, height)
	# Service units stay on the two rear corners, above the ground-floor vault band.
	if X > 2.6 and Z > 2.4 and kind not in ["chapel", "guardhouse", "guard_booth"]:
		for side in [-1.0, 1.0]:
			var c := Vector3(side * (X - 0.66), minf(height - 0.5, 2.9 if height < 5.5 else height - 1.25), Z + 0.24)
			if _clear(b, c, Vector3(1.0, 0.8, 0.6)):
				_condenser(xf, c)
				if kind == "house":
					break
	if kind in ["office_tower", "apartment", "clubhouse"]:
		for side in [-1.0, 1.0]:
			var c := Vector3(side * (X - 0.12), height * 0.5, -Z - 0.08)
			if _clear(b, c, Vector3(0.24, height, 0.16)):
				_box(xf, c, Vector3(0.24, height, 0.16), "concrete", CREAM)
				stats.pilasters += 1
	if kind == "shophouse":
		var sign_id := seed_value % 8
		var width := minf(float(b.w) - 1.0, 4.0)
		_awning(b, xf, 0.0, width, Z, 2.88, SHOP_COLORS[seed_value % SHOP_COLORS.size()])
		_sign(b, xf, Vector3(0, 3.16, -Z - 0.115), minf(width, 3.6), 1.0, sign_id)
	elif kind == "strip_shops":
		for i in 4:
			var cx := -X + float(b.w) * (i + 0.5) / 4.0
			var width := minf(float(b.w) / 4.0 - 0.7, 6.0)
			_awning(b, xf, cx, width, Z, 2.8, SHOP_COLORS[i])
			_sign(b, xf, Vector3(cx, 3.26, -Z - 0.115), minf(width - 0.2, 4.0), 1.0, [14, 4, 1, 2][i])
	elif kind == "store":
		for cx in [-X + 4.5, X - 4.5]:
			_awning(b, xf, cx, 4.2, Z, 2.95, SHOP_COLORS[0])
		_sign(b, xf, Vector3(0, 3.45, -Z - 0.12), 5.2, 1.35, 8)
	elif kind == "apartment":
		_sign(b, xf, Vector3(0, 2.96, -Z - 0.12), 4.1, 0.9, 9)
	elif kind == "clubhouse":
		_sign(b, xf, Vector3(0, 3.12, -Z - 0.12), 4.0, 1.0, 10)
	elif kind == "chapel":
		_sign(b, xf, Vector3(-X * 0.55, 3.6, -Z - 0.12), 3.0, 1.0, 12)
	elif industrial:
		_sign(b, xf, Vector3(0, 5.1, -Z - 0.12), 5.0, 1.5, 11)
		_roof_vent(xf, Vector3(0, float(b.top) - 0.2, 0), 0.46)
		var pitch := maxf((float(b.top) - height - 0.06) / minf(X, Z), 0.0)
		_roof_vent(xf, Vector3(0, float(b.top) - 0.2 - Z * 0.45 * pitch, Z * 0.45), 0.35)


func _edge_relief(b: Dictionary, xf: Transform3D, X: float, Z: float) -> void:
	if str(b.kind) in ["apartment", "office_tower"]:
		for floor_index in range(1, int(b.floors)):
			var y := float(b.h0) * floor_index - 0.03
			for side in [-1.0, 1.0]:
				var c := Vector3(0, y, side * (Z + 0.1))
				var size := Vector3(X * 2.0 + 0.48, 0.24, 0.28)
				if _clear(b, c, size):
					_box(xf, c, size, "concrete", CREAM, 63)
					stats.slab_bands += 1
				c = Vector3(side * (X + 0.1), y, 0)
				size = Vector3(0.28, 0.24, Z * 2.0 - 0.08)
				if _clear(b, c, size):
					_box(xf, c, size, "concrete", CREAM, 63)
					stats.slab_bands += 1
	for side in [-1.0, 1.0]:
		for back in [-1.0, 1.0]:
			var c := Vector3(side * (X - 0.55), 0, back * (Z + 0.085))
			var world_c: Vector3 = xf * c
			var base: float = mb.layout.ground_height(world_c.x, world_c.z) - xf.origin.y
			var height := clampf(0.38 - base, 0.3, 1.0)
			c.y = 0.38 - height * 0.5
			var size := Vector3(1.1, height, 0.25)
			if _clear(b, c, size):
				_box(xf, c, size, "concrete", Color(0.62, 0.62, 0.56), 63)
				stats.plinths += 1


func _drainage(b: Dictionary, xf: Transform3D, X: float, Z: float, height: float) -> void:
	var over := 0.12 if bool(b.get("deck", false)) else (0.43 if str(b.kind) in ["factory", "warehouse"] else 0.55)
	var pitch := 0.0 if bool(b.get("deck", false)) else maxf((float(b.top) - height - 0.06) / minf(X, Z), 0.0)
	var gutter_y := height - over * pitch - 0.05
	var along_z := Z > X and not bool(b.get("deck", false))
	for side in [-1.0, 1.0]:
		if along_z:
			_box(xf, Vector3(side * (X + over), gutter_y, 0), Vector3(0.15, 0.13, Z * 2.0 + over * 2.0), "metal_paint", CHARCOAL)
		else:
			_box(xf, Vector3(0, gutter_y, side * (Z + over)), Vector3(X * 2.0 + over * 2.0, 0.13, 0.15), "metal_paint", CHARCOAL)
		stats.gutters += 1
		var c := Vector3(side * (X + 0.14), height * 0.5, Z - 0.06) if along_z else Vector3(side * (X - 0.06), height * 0.5, Z + 0.14)
		if not _clear(b, c, Vector3(0.15, height, 0.25)):
			continue
		_pipe(xf, Vector3(c.x, 0.22, c.z), Vector3(c.x, gutter_y - 0.25, c.z), 0.055)
		var tip := Vector3(side * (X + over), gutter_y, c.z) if along_z else Vector3(c.x, gutter_y, Z + over)
		_pipe(xf, Vector3(c.x, gutter_y - 0.25, c.z), tip, 0.055)
		_pipe(xf, Vector3(c.x, 0.22, c.z), Vector3(c.x, 0.12, c.z + 0.2), 0.055)
		for y in [0.55, height - 0.75]:
			if along_z:
				_box(xf, Vector3(side * (X + 0.08), y, c.z), Vector3(0.15, 0.04, 0.17), "metal_paint", CHARCOAL)
			else:
				_box(xf, Vector3(c.x, y, Z + 0.1), Vector3(0.17, 0.04, 0.15), "metal_paint", CHARCOAL)
		stats.downpipes += 1


func _meter(b: Dictionary, xf: Transform3D, X: float, Z: float, height: float) -> void:
	for side in [-1.0, 1.0]:
		var c := Vector3(side * (X - 0.4), 1.6, -Z - 0.13)
		if not _clear(b, c, Vector3(0.42, 0.65, 0.35)):
			continue
		_box(xf, c, Vector3(0.3, 0.43, 0.13), "metal_paint", CHARCOAL)
		_box(xf, c + Vector3(0, 0.06, -0.075), Vector3(0.18, 0.13, 0.025), "metal_paint", CREAM, 32)
		_pipe(xf, c + Vector3(0, 0.23, 0), Vector3(c.x, minf(height - 0.22, 2.9), c.z), 0.018, CHARCOAL)
		stats.meters += 1
		break


func _condenser(xf: Transform3D, c: Vector3) -> void:
	_box(xf, c, Vector3(0.95, 0.58, 0.38), "metal_paint", Color(0.77, 0.79, 0.72))
	# A circular fan housing and a separate louver bank distinguish this from a featureless wall box.
	_pipe(xf, c + Vector3(-0.18, 0, 0.205), c + Vector3(-0.18, 0, 0.225), 0.21, CHARCOAL)
	_box(xf, c + Vector3(-0.18, 0, 0.235), Vector3(0.32, 0.035, 0.025), "metal_paint", CHARCOAL)
	_box(xf, c + Vector3(-0.18, 0, 0.235), Vector3(0.035, 0.32, 0.025), "metal_paint", CHARCOAL)
	for i in 5:
		_box(xf, c + Vector3(0.29, -0.18 + i * 0.09, 0.205), Vector3(0.21, 0.025, 0.025), "metal_paint", CHARCOAL)
	for side in [-1.0, 1.0]:
		_box(xf, c + Vector3(side * 0.32, -0.33, -0.03), Vector3(0.055, 0.09, 0.52), "metal_paint", CHARCOAL)
	_pipe(xf, c + Vector3(0.42, -0.05, -0.12), c + Vector3(0.52, -0.37, -0.12), 0.025)
	stats.condensers += 1


func _awning(b: Dictionary, xf: Transform3D, cx: float, width: float, Z: float, y: float, tint: Color) -> void:
	if not _clear(b, Vector3(cx, y + 0.08, -Z - 0.65), Vector3(width, 0.25, 1.1)):
		return
	var front_z := -Z - 1.25
	var back_z := -Z - 0.06
	var n := maxi(int(ceilf(width / 0.5)), 4)
	for i in n:
		var x0 := cx - width * 0.5 + width * i / n
		var x1 := cx - width * 0.5 + width * (i + 1) / n
		var col: Color = tint if i % 2 == 0 else CREAM
		sink.quad(xf * Vector3(x0, y + 0.23, back_z), xf * Vector3(x1, y + 0.23, back_z),
			xf * Vector3(x1, y - 0.04, front_z), xf * Vector3(x0, y - 0.04, front_z), "cloth",
			{"collide": false, "double": true, "facing": Vector3.UP, "tint": col, "paint": 0.9, "dirt": 0.3})
		_box(xf, Vector3((x0 + x1) * 0.5, y - 0.13, front_z), Vector3(x1 - x0, 0.18, 0.025), "cloth", col, 16 | 32)
	_box(xf, Vector3(cx, y - 0.01, front_z + 0.025), Vector3(width + 0.08, 0.045, 0.045), "metal_paint", CHARCOAL)
	for side in [-1.0, 1.0]:
		_pipe(xf, Vector3(cx + side * width * 0.45, y - 0.22, -Z - 0.08), Vector3(cx + side * width * 0.45, y - 0.02, front_z), 0.023, CHARCOAL)
	stats.awnings += 1


func _sign(b: Dictionary, xf: Transform3D, c: Vector3, w: float, h: float, idx: int) -> void:
	if c.y - h * 0.5 < 2.5 or not _clear(b, c, Vector3(w, h, 0.2)):
		return
	_box(xf, c, Vector3(w + 0.12, h + 0.12, 0.09), "metal_paint", CHARCOAL)
	var uv := Rect2((idx % 4) * 0.25, floorf(float(idx) / 4.0) * 0.25, 0.25, 0.25)
	sink.atlas_quad(xf * (c + Vector3(0, 0, -0.055)), -xf.basis.x, xf.basis.y, w, h, uv, SIGNS,
		{"layer": "ext", "tint": Color(1, 1, 1, 1)})
	stats.signs += 1


func _roof_vent(xf: Transform3D, c: Vector3, radius: float) -> void:
	_pipe(xf, c, c + Vector3.UP * 1.05, radius, CHARCOAL)
	_pipe(xf, c + Vector3.UP * 1.08, c + Vector3.UP * 1.18, radius * 1.4, CREAM)
	stats.roof_vents += 1


func _landmark(b: Dictionary, lot: Dictionary) -> void:
	var xf: Transform3D = b.xf
	var X := float(b.w) * 0.5
	var Z := float(b.d) * 0.5
	match str(lot.kind):
		"gas_station":
			# The sign faces the forecourt on the existing pump canopy, rather than the edge of the lot.
			_sign(b, xf, Vector3(0, 5.55, -Z * 0.15 - Z * 0.4 - 0.1), 5.2, 1.1, 13)
			stats.landmarks += 1
		"tank":
			var radius := minf(X, Z) - 0.26
			for y in [2.0, 6.4]:
				_pipe(xf, Vector3(0, y, 0), Vector3(0, y + 0.09, 0), radius, CHARCOAL)
			stats.landmarks += 1
		"water_tower":
			# Tension ties stiffen the four existing legs and break up the empty support silhouette.
			for side in [-1.0, 1.0]:
				for y in [2.0, 7.0]:
					_pipe(xf, Vector3(-X + 0.6, y, side * (Z - 0.6)), Vector3(X - 0.6, y + 5.0, side * (Z - 0.6)), 0.045, CHARCOAL)
					_pipe(xf, Vector3(X - 0.6, y, side * (Z - 0.6)), Vector3(-X + 0.6, y + 5.0, side * (Z - 0.6)), 0.045, CHARCOAL)
			stats.landmarks += 1
