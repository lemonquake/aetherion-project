extends RefCounted
## Landmark buildings and every water crossing. Sites are built before the districts and reserve their ground.

var mb = null
var L = null
var sink = null
var rng := RandomNumberGenerator.new()
const WATERFRONT := ["pump_station", "fish_port", "container_yard"]  # built at the water's edge on purpose

var _site := ""
var _site_type := ""
var _footprints := []  # [{site, type, p, half, ang}] every rectangle a site reserved, for _check_footprints


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	sink = mb.sink
	rng.seed = L.rng.seed + 211


func build_all() -> void:
	for s in L.sites:
		var p: Vector2 = s.pos
		var ang := float(s.ang)
		_site = str(s.name)
		_site_type = str(s.type)
		match str(s.type):
			"chapel":
				_chapel(p, ang)
			"court":
				_half_court(p, ang)
			"school":
				_school(p, ang)
			"barangay_hall":
				_hall(p, ang, "Barangay Hall")
			"clinic":
				_clinic(p, ang)
			"covered_court":
				_covered_court(p, ang)
			"water_tower":
				_water_tower(p)
			"outpost":
				_outpost(p, ang)
			"pump_station":
				_pump_station(p, ang)
			"junkshop", "scrapyard":
				_scrapyard(p, ang)
			"market":
				_market(p, ang)
			"church":
				_church(p, ang)
			"shophouses":
				_shophouses(p, ang, int(s.get("count", 5)))
			"gas_station":
				_gas_station(p, ang)
			"apartment":
				_apartment(p, ang)
			"warehouse":
				_warehouse(p, ang)
			"container_yard":
				_container_yard(p, ang)
			"fish_port":
				_fish_port(p, ang)
			"cell_tower":
				_cell_tower(p)
			"police":
				_police(p, ang)
	_site = ""
	_check_footprints()
	_highway()


# ------------------------------------------------------------------ helpers

func _gy(p: Vector2) -> float:
	return maxf(L.ground_height(p.x, p.y), L.WATER_Y + 1.0)


func _xf(p: Vector2, ang: float, y: float = INF) -> Transform3D:
	var yy := _gy(p) if y == INF else y
	return Transform3D(Basis(Vector3.UP, -ang), Vector3(p.x, yy, p.y))


func _reserve(p: Vector2, half: Vector2, ang: float, margin: float = 1.5) -> void:
	L.reserve_rect(p, half, ang, 2, margin)
	_footprints.append({"site": _site, "type": _site_type, "p": p, "half": half, "ang": ang})


func _check_footprints() -> void:
	## Sites are placed by hand and nothing stops one landing on a road, in the water or on another site (the layout
	## is scaled, so a move elsewhere can cause it). Warn so the layout gets fixed; the build carries on.
	var hits := {}
	for f in _footprints:
		var xa := Vector2(cos(f.ang), sin(f.ang))
		var za := Vector2(-sin(f.ang), cos(f.ang))
		var half: Vector2 = f.half
		for i in 9:
			for j in 9:
				var q: Vector2 = f.p + xa * half.x * (i / 4.0 - 1.0) + za * half.y * (j / 4.0 - 1.0)
				var what := ""
				for r in L.roads:
					if L.poly_dist(q, r.pts).x < float(r.w) * 0.5:
						what = str(r.name)
				if L.poly_dist(q, L.railway).x < 3.2:
					what = "the railway"
				if what == "" and not (f.type in WATERFRONT) and L.is_water(q.x, q.y):
					what = "water"
				for g in _footprints:
					if g.site != f.site and what == "":
						var lq: Vector2 = (q - g.p).rotated(-float(g.ang))
						if absf(lq.x) < (g.half as Vector2).x and absf(lq.y) < (g.half as Vector2).y:
							what = str(g.site)
				if what != "":
					var key := "%s|%s" % [f.site, what]
					hits[key] = int(hits.get(key, 0)) + 1
	for key in hits:
		var parts: PackedStringArray = str(key).split("|")
		push_warning("Sites: %s overlaps %s (%d of 81 sample points)" % [parts[0], parts[1], hits[key]])


func _boxes(xf: Transform3D, n: int, half: Vector2, y: float, choices: Array) -> void:
	## Loot boxes scattered on a site floor (xf local, within +-half), each [model, table].
	for k in n:
		var c: Array = _pick(choices)
		var lp := Vector3(rng.randf_range(-half.x, half.x), y, rng.randf_range(-half.y, half.y))
		mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), lp), str(c[1]), -1)


func _slab(xf: Transform3D, w: float, d: float, mat: String = "cement") -> void:
	sink.box(xf * Transform3D(Basis(), Vector3(0, -0.1, 0)), Vector3(w, 0.3, d), mat, {"dirt": 0.6})


func _posts_roof(xf: Transform3D, w: float, d: float, h: float, mat: String = "yero_rust", post_mat: String = "metal_paint", spacing: float = 5.0) -> void:
	## An open shed: steel posts, trusses and a low-pitched corrugated gable roof.
	var nx := maxi(int(w / spacing), 1)
	var nz := maxi(int(d / spacing), 1)
	for i in nx + 1:
		for j in [0, nz]:
			var x := -w * 0.5 + w * i / nx
			var z = -d * 0.5 + d * j / nz
			sink.box(xf * Transform3D(Basis(), Vector3(x, h * 0.5, z)), Vector3(0.2, h, 0.2), post_mat, {"dirt": 0.6, "tint": Color(0.35, 0.45, 0.4), "paint": 0.6})
	for i in nx + 1:
		var x := -w * 0.5 + w * i / nx
		sink.box(xf * Transform3D(Basis(), Vector3(x, h + 0.15, 0)), Vector3(0.12, 0.3, d), post_mat, {"dirt": 0.4, "collide": false})
	var rise := w * 0.12
	for side in [-1.0, 1.0]:
		var run := w * 0.5 + 0.6
		var ang := atan2(rise, run)
		var c := Vector3(side * run * 0.5, h + 0.35 + rise * 0.5, 0)
		var b := Basis(Vector3.FORWARD, ang * side)
		var length := d + 1.2
		var sheets := int(length / 0.75)
		for k in sheets:
			var zc := -length * 0.5 + (k + 0.5) * length / sheets
			sink.corrugated(xf * Transform3D(b * Basis(Vector3.UP, PI * 0.5), c + Vector3(0, 0, zc)), sqrt(run * run + rise * rise), 0.8, mat if rng.randf() > 0.2 else "yero",
				{"dirt": 0.5, "collide": false, "double": true})
		sink.col_box(xf * Transform3D(b, c), Vector3(sqrt(run * run + rise * rise), 0.06, length), "sheet_metal")


func _sign(xf: Transform3D, w: float, h: float, color: Color) -> void:
	sink.box(xf, Vector3(w, h, 0.04), "metal_paint", {"tint": color, "paint": 0.9, "dirt": 0.5, "collide": false})


func _house(p: Vector2, ang: float, w: float, d: float, floors: int, style: String, kind: String = "house", front: String = "door") -> Dictionary:
	var front2d := Vector2(sin(ang), -cos(ang))
	var basis := Basis(Vector3.UP, -ang)
	var y := _gy(p) + 0.1
	return mb.shanty({"xf": Transform3D(basis, Vector3(p.x, y, p.y)), "w": w, "d": d, "floors": floors, "style": style, "kind": kind,
		"front": front, "seed": rng.randi(), "stilts": false, "ground_y": y, "can_overhang": false, "district": "site"})


# ------------------------------------------------------------------ sites

func _chapel(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(6, 9), ang)
	_house(p, ang, 9.0, 13.0, 1, "concrete", "chapel", "open")
	# Bell frame: a steel tripod with a bell is the landmark of every kapilya.
	var xf := _xf(p + Vector2(sin(ang), -cos(ang)) * 8.5 + Vector2(cos(ang), sin(ang)) * 5.0, ang)
	for a in [0.0, 2.1, 4.2]:
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.12)
		sink.box(xf * Transform3D(b, Vector3(0, 3.0, 0)), Vector3(0.12, 6.0, 0.12), "metal_rust", {"dirt": 0.5})
	sink.cylinder(xf.origin + Vector3(0, 5.2, 0), Vector3.UP, 0.6, 0.32, "metal_rust", {"sides": 10})
	var cross := xf * Transform3D(Basis(), Vector3(0, 6.6, 0))
	sink.box(cross, Vector3(0.08, 1.0, 0.08), "metal_paint", {"collide": false, "tint": Color(0.9, 0.9, 0.85), "paint": 0.9})
	sink.box(cross * Transform3D(Basis(), Vector3(0, 0.2, 0)), Vector3(0.5, 0.08, 0.08), "metal_paint", {"collide": false, "tint": Color(0.9, 0.9, 0.85), "paint": 0.9})


func _half_court(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(7.5, 7.5), ang, 0.5)
	var xf := _xf(p, ang)
	sink.box(xf * Transform3D(Basis(), Vector3(0, 0.02, 0)), Vector3(14, 0.12, 14), "concrete_painted", {"dirt": 0.5})
	# Ring on a welded post with a plywood board.
	sink.box(xf * Transform3D(Basis(), Vector3(0, 1.7, -6.6)), Vector3(0.12, 3.4, 0.12), "metal_rust", {"dirt": 0.4})
	sink.box(xf * Transform3D(Basis(), Vector3(0, 3.4, -6.3)), Vector3(1.6, 1.1, 0.05), "plywood", {"dirt": 0.6, "tint": Color(0.9, 0.9, 0.9), "paint": 0.6})
	sink.cylinder(xf * Vector3(0, 3.05, -5.95), Vector3.UP, 0.02, 0.23, "metal_rust", {"sides": 12})


func _school(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(30, 18), ang)
	var xf := _xf(p, ang)
	_slab(xf, 62, 38, "concrete_dirty")
	# Two rows of classrooms around a yard with a flagpole.
	for row in [-1.0, 1.0]:
		for k in 4:
			var lp = p + Vector2(cos(ang), sin(ang)) * (-21.0 + k * 14.0) + Vector2(-sin(ang), cos(ang)) * (row * 13.0)
			_house(lp, ang + (PI if row > 0 else 0.0), 13.0, 8.0, 2 if k % 2 == 0 else 1, "concrete", "classroom")
	var fp := _xf(p, ang)
	sink.cylinder(fp.origin, Vector3.UP, 9.0, 0.05, "metal_paint", {"sides": 6, "collide": true})


func _hall(p: Vector2, ang: float, name: String) -> void:
	_reserve(p, Vector2(9, 7), ang)
	_house(p, ang, 15.0, 11.0, 2, "concrete", "hall")
	_sign(_xf(p, ang) * Transform3D(Basis(), Vector3(0, 6.4, -5.7)), 6.0, 1.0, Color(0.2, 0.35, 0.6))


func _clinic(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(8, 6), ang)
	_house(p, ang, 13.0, 9.0, 1, "concrete", "clinic")
	_sign(_xf(p, ang) * Transform3D(Basis(), Vector3(0, 3.4, -4.7)), 4.0, 0.8, Color(0.85, 0.85, 0.82))
	mb.dyn.add_light({"pos": _xf(p, ang) * Vector3(0, 3.0, -5.0), "kind": "emergency", "color": Color(1.0, 0.25, 0.2), "energy": 0.8, "range": 9.0, "flicker": 0.2})


func _covered_court(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(17, 11), ang)
	var xf := _xf(p, ang)
	sink.box(xf * Transform3D(Basis(), Vector3(0, 0.02, 0)), Vector3(32, 0.14, 20), "concrete_painted", {"dirt": 0.4})
	_posts_roof(xf, 32.0, 20.0, 8.0, "yero_paint", "metal_paint", 6.4)
	for side in [-1.0, 1.0]:
		var bx := xf * Transform3D(Basis(Vector3.UP, PI * 0.5 * side), Vector3(side * 14.5, 0, 0))
		sink.box(bx * Transform3D(Basis(), Vector3(0, 1.8, 0)), Vector3(0.15, 3.6, 0.15), "metal_paint", {})
		sink.box(bx * Transform3D(Basis(), Vector3(0, 3.6, 0.35)), Vector3(1.8, 1.1, 0.06), "plywood", {"tint": Color(0.92, 0.92, 0.92), "paint": 0.8, "collide": false})
	# Bleachers
	for k in 3:
		sink.box(xf * Transform3D(Basis(), Vector3(0, 0.25 + k * 0.4, 8.6 + k * 0.6)), Vector3(22, 0.12, 0.6), "concrete", {"dirt": 0.6})
	mb.dyn.add_light({"pos": xf * Vector3(0, 7.5, 0), "kind": "sodium", "color": Color(1.0, 0.75, 0.45), "energy": 1.6, "range": 22.0, "flicker": 0.35})


func _water_tower(p: Vector2) -> void:
	_reserve(p, Vector2(4, 4), 0.0)
	var base := Vector3(p.x, _gy(p), p.y)
	for a in 4:
		var o := Vector3(cos(a * PI * 0.5 + 0.78), 0, sin(a * PI * 0.5 + 0.78)) * 2.4
		sink.box(Transform3D(Basis(), base + o + Vector3(0, 9, 0)), Vector3(0.35, 18, 0.35), "concrete", {"dirt": 0.7})
	sink.cylinder(base + Vector3(0, 18, 0), Vector3.UP, 6.0, 3.6, "metal_paint", {"sides": 16, "tint": Color(0.55, 0.62, 0.7), "paint": 0.8, "collide": true})
	sink.box(Transform3D(Basis(), base + Vector3(0, 24.1, 0)), Vector3(7.2, 0.2, 7.2), "metal_rust", {})
	mb.dyn.add_light({"pos": base + Vector3(0, 24.6, 0), "kind": "beacon", "color": Color(1.0, 0.1, 0.05), "energy": 1.5, "range": 6.0, "blink": 1.4})


func _outpost(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(4, 3.5), ang)
	var h := _house(p, ang, 6.0, 5.0, 1, "chb", "outpost")
	mb.dyn.add_container(_xf(p, ang) * Vector3(1.8, 0.5, 1.6), "weapon_locker", int(h.id), Vector3(0.8, 1.6, 0.5))
	mb.dyn.add_light({"pos": _xf(p, ang) * Vector3(0, 2.6, -3.0), "kind": "tube", "color": Color(0.8, 0.95, 1.0), "energy": 0.9, "range": 8.0, "flicker": 0.5})


func _pump_station(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(10, 8), ang)
	var xf := _xf(p, ang, L.LAND_Y + 0.3)
	_house(p, ang, 16.0, 12.0, 2, "concrete", "pump")
	# Trash rack grates where the estero enters.
	for k in 6:
		sink.box(xf * Transform3D(Basis(), Vector3(-8.5, 0.5, -4.5 + k * 1.8)), Vector3(0.06, 3.0, 1.6), "grate", {"dirt": 0.9})
	mb.dyn.add_light({"pos": xf * Vector3(0, 7.0, -6.2), "kind": "sodium", "color": Color(1.0, 0.7, 0.4), "energy": 1.2, "range": 18.0, "flicker": 0.15})


func _scrapyard(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(14, 12), ang)
	var xf := _xf(p, ang)
	# Fence of patched sheets, heaps of scrap, a weighing shed.
	for side in 4:
		var a := side * PI * 0.5
		var b := Basis(Vector3.UP, a)
		for k in 7:
			var x := -12.0 + k * 4.0
			if side == 0 and k == 3:
				continue  # gate
			sink.box(xf * Transform3D(b, b.inverse() * Vector3(0, 0, 0) + Vector3(x, 1.2, 0) + Vector3(0, 0, 13.0 if side % 2 == 0 else 13.0)), Vector3(3.9, 2.4, 0.03), "yero_rust", {"dirt": 0.9})
	_house(p + Vector2(cos(ang), sin(ang)) * 6.0, ang, 7.0, 5.0, 1, "yero", "workshop", "open")
	for k in 6:
		var o := Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
		mb.dyn.add_static_prop(_pick(["wheel_rim", "old_tyre", "drum", "plank_pile", "hollow_block_pile"]), xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), o))
	for k in 3:
		var o2 := Vector3(rng.randf_range(-10, 0), 0.0, rng.randf_range(-10, 10))
		var c: Array = _pick([["lootbox_toolbox", "box_toolbox"], ["lootbox_ammocan", "box_ammocan"]])
		mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), o2), str(c[1]), -1)


func _market(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(24, 17), ang)
	var xf := _xf(p, ang)
	_slab(xf, 46, 32, "concrete_floor")
	_posts_roof(xf, 44.0, 30.0, 6.0, "yero_rust", "metal_paint", 5.5)
	# Concrete stalls in rows; the meat and fish sections have tiled counters.
	for row in 4:
		for k in 7:
			var lx := -18.0 + k * 6.0
			var lz := -10.5 + row * 7.0
			mb.dyn.add_static_prop("market_stall", xf * Transform3D(Basis(), Vector3(lx, 0.0, lz)))
			if rng.randf() < 0.35:
				mb.dyn.add_container(xf * Vector3(lx, 0.9, lz), "store_shelf", -1, Vector3(1.8, 0.4, 0.8))
			if rng.randf() < 0.3:
				mb.dyn.add_loot_spot(xf * Vector3(lx + rng.randf_range(-0.6, 0.6), 0.88, lz), "floor_household", -1)
			if rng.randf() < 0.22:
				var c: Array = _pick([["lootbox_cooler", "box_cooler"], ["lootbox_bin", "box_bin"], ["lootbox_balikbayan", "box_balikbayan"]])
				mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(lx + 1.55, 0.05, lz + rng.randf_range(-0.3, 0.3))), str(c[1]), -1)
	mb.dyn.add_light({"pos": xf * Vector3(6, 5.6, 2), "kind": "tube", "color": Color(0.85, 0.95, 1.0), "energy": 1.0, "range": 12.0, "flicker": 0.6})


func _church(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(11, 18), ang)
	_house(p, ang, 18.0, 30.0, 1, "concrete", "church", "door")
	# Bell tower: the tallest masonry in town.
	var tp := p + Vector2(sin(ang), -cos(ang)) * 16.5 + Vector2(cos(ang), sin(ang)) * 6.0
	var xf := _xf(tp, ang)
	_reserve(tp, Vector2(3, 3), ang, 0.5)
	sink.box(xf * Transform3D(Basis(), Vector3(0, 10, 0)), Vector3(4.2, 20, 4.2), "plaster_white", {"dirt": 0.8, "occlude": true, "tint": Color(0.92, 0.9, 0.82), "paint": 0.6})
	sink.box(xf * Transform3D(Basis(), Vector3(0, 21.5, 0)), Vector3(3.6, 3.0, 3.6), "plaster_white", {"dirt": 0.5, "faces": 4 | 8})
	for c in [Vector3(1.6, 21.5, 1.6), Vector3(-1.6, 21.5, 1.6), Vector3(1.6, 21.5, -1.6), Vector3(-1.6, 21.5, -1.6)]:
		sink.box(xf * Transform3D(Basis(), c), Vector3(0.5, 3.0, 0.5), "plaster_white", {"dirt": 0.5})
	sink.box(xf * Transform3D(Basis(), Vector3(0, 23.2, 0)), Vector3(4.4, 0.4, 4.4), "plaster_white", {"dirt": 0.4})
	sink.box(xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 24.4, 0)), Vector3(2.6, 2.0, 2.6), "metal_rust", {"dirt": 0.3})
	sink.box(xf * Transform3D(Basis(), Vector3(0, 26.6, 0)), Vector3(0.12, 2.0, 0.12), "metal_rust", {"collide": false})
	sink.box(xf * Transform3D(Basis(), Vector3(0, 27.0, 0)), Vector3(0.9, 0.12, 0.12), "metal_rust", {"collide": false})


func _shophouses(p: Vector2, ang: float, count: int) -> void:
	var along := Vector2(cos(ang), sin(ang))
	for k in count:
		var w := rng.randf_range(5.5, 7.5)
		var lp := p + along * (k * 7.6 - count * 3.8)
		_reserve(lp, Vector2(w * 0.5, 5.0), ang, 0.2)
		var h := _house(lp, ang, w, 10.0, 2 if rng.randf() < 0.6 else 3, "concrete", "shop", "store")
		mb.dyn.add_container(_xf(lp, ang) * Vector3(0, 0.9, -1.5), "store_counter", int(h.id), Vector3(1.6, 0.4, 0.6))
		_sign(_xf(lp, ang) * Transform3D(Basis(), Vector3(0, 3.0, -5.25)), w * 0.9, 0.9, mb.mats.PAINTS[rng.randi_range(0, mb.mats.PAINTS.size() - 1)])


func _gas_station(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(13, 9), ang)
	var xf := _xf(p, ang)
	_slab(xf, 26, 18, "concrete_floor2")
	_posts_roof(xf * Transform3D(Basis(), Vector3(0, 0, -2)), 16.0, 8.0, 5.0, "metal_sheet", "metal_paint", 8.0)
	for k in 3:
		sink.box(xf * Transform3D(Basis(), Vector3(-5.0 + k * 5.0, 0.8, -2)), Vector3(0.7, 1.6, 0.5), "metal_paint", {"tint": Color(0.8, 0.2, 0.15), "paint": 0.8})
	_house(p + Vector2(-sin(ang), cos(ang)) * 6.0, ang, 8.0, 5.0, 1, "concrete", "store", "store")


func _apartment(p: Vector2, ang: float) -> void:
	## A three-storey "paupahan": a corridor of rooms per floor, external stair.
	_reserve(p, Vector2(13, 6), ang)
	var along := Vector2(cos(ang), sin(ang))
	for k in 4:
		var lp := p + along * (-9.0 + k * 6.0)
		_house(lp, ang, 5.8, 8.0, 3, "concrete", "apartment")


func _warehouse(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(17, 12), ang)
	var xf := _xf(p, ang)
	_slab(xf, 34, 24, "concrete_floor2")
	var w := 32.0
	var d := 22.0
	var h := 7.0
	# Corrugated walls with a big sliding door gap and a personnel door.
	for side in [[Vector3(0, h * 0.5, -d * 0.5), 0.0, w], [Vector3(0, h * 0.5, d * 0.5), PI, w], [Vector3(-w * 0.5, h * 0.5, 0), PI * 0.5, d], [Vector3(w * 0.5, h * 0.5, 0), -PI * 0.5, d]]:
		var b := Basis(Vector3.UP, float(side[1]))
		var len := float(side[2])
		var n := int(len / 0.8)
		for k in n:
			var x := -len * 0.5 + (k + 0.5) * len / n
			if absf(x) < 3.0 and float(side[1]) == 0.0:
				continue  # roller door opening
			sink.corrugated(xf * Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), side[0] + b * Vector3(x, 0, 0)), h, 0.82, "box_profile" if false else "yero_rust", {"dirt": 0.9, "collide": false})
		sink.col_box(xf * Transform3D(b, side[0]), Vector3(len, h, 0.06), "sheet_metal")
	_posts_roof(xf, w, d, h, "yero_rust", "metal_rust", 8.0)
	for k in 8:
		var o := Vector3(rng.randf_range(-13, 13), 0, rng.randf_range(-8, 8))
		mb.dyn.add_prop_spec(_pick(["crate_wood", "crate_wood2", "pallet", "cement_bag", "drum"]), xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), o))
	mb.dyn.add_container(xf * Vector3(10, 0.5, 6), "military_crate" if rng.randf() < 0.5 else "crate", -1, Vector3(1.2, 0.8, 0.8))
	mb.dyn.add_loot_spot(xf * Vector3(-6, 0.05, 2), "floor_contested", -1)
	mb.dyn.add_loot_spot(xf * Vector3(6, 0.05, -4), "floor_contested", -1)
	_boxes(xf, rng.randi_range(3, 5), Vector2(13, 8), 0.05, [["lootbox_ammocan", "box_ammocan"], ["lootbox_footlocker", "box_footlocker"],
		["lootbox_bin", "box_bin"], ["lootbox_riflecase", "box_riflecase"], ["lootbox_toolbox", "box_toolbox"]])
	mb.dyn.add_light({"pos": xf * Vector3(0, h - 0.5, 0), "kind": "sodium", "color": Color(1.0, 0.7, 0.4), "energy": 0.9, "range": 16.0, "flicker": 0.5})


func _container_yard(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(30, 14), ang)
	var xf := _xf(p, ang)
	_slab(xf, 62, 30, "concrete_floor")
	var colors := [Color(0.65, 0.18, 0.12), Color(0.15, 0.3, 0.5), Color(0.2, 0.45, 0.25), Color(0.75, 0.55, 0.2), Color(0.5, 0.5, 0.5)]
	for row in 3:
		for k in 6:
			var stack := rng.randi_range(1, 3)
			for s in stack:
				if rng.randf() < 0.12:
					continue
				var c := Vector3(-24.0 + k * 9.0 + rng.randf_range(-0.3, 0.3), 1.3 + s * 2.6, -8.0 + row * 8.0)
				sink.box(xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.02, 0.02)), c), Vector3(6.06, 2.59, 2.44), "container",
					{"tint": colors[rng.randi_range(0, colors.size() - 1)], "paint": 0.9, "dirt": 0.5, "occlude": true})
	# Gantry crane: the port's silhouette from anywhere on the map.
	var cxf := xf * Transform3D(Basis(), Vector3(0, 0, 14))
	for x in [-14.0, 14.0]:
		for z in [-3.0, 3.0]:
			sink.box(cxf * Transform3D(Basis(), Vector3(x, 14, z)), Vector3(0.9, 28, 0.9), "metal_paint", {"tint": Color(0.85, 0.65, 0.15), "paint": 0.9})
	sink.box(cxf * Transform3D(Basis(), Vector3(0, 28.5, 0)), Vector3(32, 1.6, 7.0), "metal_paint", {"tint": Color(0.85, 0.65, 0.15), "paint": 0.9})
	sink.box(cxf * Transform3D(Basis(), Vector3(0, 28.5, 18)), Vector3(3, 1.4, 30), "metal_paint", {"tint": Color(0.85, 0.65, 0.15), "paint": 0.9})
	mb.dyn.add_light({"pos": cxf * Vector3(0, 29.6, 0), "kind": "beacon", "color": Color(1.0, 0.15, 0.05), "energy": 2.0, "range": 8.0, "blink": 1.1})
	# Contested: rifle cases and ammunition left in the aisles between the stacks.
	for k in 5:
		var c: Array = _pick([["lootbox_riflecase", "box_riflecase"], ["lootbox_ammocan", "box_ammocan"], ["lootbox_footlocker", "box_footlocker"]])
		var lp := Vector3(-24.0 + rng.randi_range(0, 5) * 9.0 + 4.5, 0.05, -12.0 + rng.randi_range(0, 3) * 8.0)
		mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.2, 0.2)), lp), str(c[1]), -1)
		mb.dyn.add_loot_spot(xf * (lp + Vector3(0, 0, 1.2)), "floor_contested", -1)
	mb.dyn.add_light({"pos": cxf * Vector3(10, 27.0, 0), "kind": "flood", "color": Color(1.0, 0.72, 0.45), "energy": 3.0, "range": 40.0, "flicker": 0.0})


func _fish_port(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(14, 10), ang)
	var xf := _xf(p, ang, L.WATER_Y + 1.8)
	# Concrete pier into the bay with a landing shed and moored bangkas.
	sink.box(xf * Transform3D(Basis(), Vector3(0, -0.3, 30)), Vector3(10, 0.6, 70), "concrete_dirty", {"dirt": 0.8})
	for k in 8:
		for side in [-1.0, 1.0]:
			sink.box(xf * Transform3D(Basis(), Vector3(side * 4.6, -2.5, -2.0 + k * 9.0)), Vector3(0.6, 4.4, 0.6), "concrete", {"dirt": 1.0})
	_posts_roof(xf * Transform3D(Basis(), Vector3(0, 0, 6)), 9.0, 14.0, 4.0, "yero_rust", "metal_rust", 4.5)
	for k in 5:
		mb.dyn.add_static_prop("boat", xf * Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.2, 0.2)), Vector3(-9.0 if k % 2 == 0 else 9.0, -1.9, 10.0 + k * 9.0)))
	# Fishermen's iceboxes and gear on the pier.
	for k in 6:
		var c: Array = _pick([["lootbox_cooler", "box_cooler"], ["lootbox_cooler", "box_cooler"], ["lootbox_bin", "box_bin"], ["lootbox_toolbox", "box_toolbox"]])
		mb.dyn.add_loot_box(str(c[0]), xf * Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(rng.randf_range(-3.5, 3.5), 0.0, 2.0 + k * 8.0)), str(c[1]), -1)
	mb.dyn.add_loot_spot(xf * Vector3(0, 0.02, 20), "floor_street", -1)


func _cell_tower(p: Vector2) -> void:
	_reserve(p, Vector2(4, 4), 0.0)
	var base := Vector3(p.x, _gy(p), p.y)
	var h := 42.0
	for k in 3:
		var a := k * TAU / 3.0
		var o := Vector3(cos(a), 0, sin(a)) * 2.0
		var top := Vector3(cos(a), 0, sin(a)) * 0.5 + Vector3(0, h, 0)
		var dir := (top - o)
		sink.box(Transform3D(Basis.looking_at(dir.normalized(), Vector3.FORWARD if absf(dir.normalized().y) > 0.99 else Vector3.UP), base + o + dir * 0.5) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO),
			Vector3(0.2, dir.length(), 0.2), "metal_paint", {"tint": Color(0.75, 0.75, 0.75), "paint": 0.8})
	for y in range(4, int(h), 6):
		var r := lerpf(2.0, 0.5, float(y) / h)
		sink.box(Transform3D(Basis(), base + Vector3(0, y, 0)), Vector3(r * 1.7, 0.08, r * 1.7), "grate", {"collide": false})
	mb.dyn.add_light({"pos": base + Vector3(0, h + 0.5, 0), "kind": "beacon", "color": Color(1.0, 0.05, 0.02), "energy": 3.0, "range": 10.0, "blink": 1.6})


func _police(p: Vector2, ang: float) -> void:
	_reserve(p, Vector2(8, 6), ang)
	var h := _house(p, ang, 12.0, 9.0, 2, "concrete", "police")
	var xf := _xf(p, ang)
	mb.dyn.add_container(xf * Vector3(4.5, 0.5, 3.0), "weapon_locker", int(h.id), Vector3(1.0, 1.8, 0.5))
	mb.dyn.add_container(xf * Vector3(-4.5, 0.5, 3.0), "weapon_locker", int(h.id), Vector3(1.0, 1.8, 0.5))
	mb.dyn.add_loot_spot(xf * Vector3(0, 0.8, 2.0), "floor_contested", int(h.id))
	_sign(xf * Transform3D(Basis(), Vector3(0, 5.5, -4.7)), 5.0, 0.8, Color(0.15, 0.25, 0.55))
	mb.dyn.add_light({"pos": xf * Vector3(0, 2.8, -5.0), "kind": "tube", "color": Color(0.85, 0.95, 1.0), "energy": 1.0, "range": 10.0, "flicker": 0.2})


func _highway() -> void:
	## The elevated expressway along the east edge: pillars, a deck at 9 m, barriers. People live underneath.
	var x = L.highway_x
	var deck_y := 9.5
	var z: float = -L.HALF
	while z < L.HALF:
		var gy := maxf(L.ground_height(x, z), L.WATER_Y - 3.0)
		if not (z > L.coast_z(x) + 20.0):
			sink.box(Transform3D(Basis(), Vector3(x, (gy + deck_y) * 0.5 - 0.6, z)), Vector3(2.2, deck_y - gy - 1.2, 2.2), "concrete_dirty", {"dirt": 0.9, "occlude": true})
			sink.box(Transform3D(Basis(), Vector3(x, deck_y - 1.0, z)), Vector3(14.0, 1.0, 2.0), "concrete", {"dirt": 0.5})
		z += 30.0
	z = -L.HALF
	while z < L.HALF:
		sink.box(Transform3D(Basis(), Vector3(x, deck_y, z + 15.0)), Vector3(14.0, 0.7, 30.0), "concrete", {"dirt": 0.4, "occlude": true})
		for side in [-1.0, 1.0]:
			sink.box(Transform3D(Basis(), Vector3(x + side * 6.8, deck_y + 0.8, z + 15.0)), Vector3(0.4, 0.9, 30.0), "concrete", {"dirt": 0.5})
		z += 30.0


# ------------------------------------------------------------------ crossings

func build_crossings() -> void:
	for c in L.crossings:
		match str(c.type):
			"road_bridge":
				_road_bridge(c)
			"rail_bridge":
				_rail_bridge(c)
			"steel_footbridge":
				_footbridge(c, "metal_rust", 1.9, true)
			"plank_bridge":
				_footbridge(c, "planks", 1.2, false)
			"pipe_bridge":
				_pipe_bridge(c)
			"culvert":
				_culvert(c)


func _span(c: Dictionary) -> Array:
	var a: Vector2 = c.a
	var b: Vector2 = c.b
	# Extend the span until both ends are on dry ground.
	var dir := (b - a).normalized()
	for i in 30:
		if L.is_water(a.x, a.y):
			a -= dir * 1.5
		if L.is_water(b.x, b.y):
			b += dir * 1.5
	return [a - dir * 2.0, b + dir * 2.0]


func _road_bridge(c: Dictionary) -> void:
	var ab := _span(c)
	var a: Vector2 = ab[0]
	var b: Vector2 = ab[1]
	var len := a.distance_to(b)
	var mid := (a + b) * 0.5
	var ang := atan2(-(b - a).y, (b - a).x)
	var w := float(c.w) + 2.0
	var y = L.LAND_Y + 1.4
	var xf := Transform3D(Basis(Vector3.UP, ang), Vector3(mid.x, y, mid.y))
	sink.box(xf * Transform3D(Basis(), Vector3(0, -0.35, 0)), Vector3(len, 0.7, w), "concrete", {"dirt": 0.5, "occlude": true})
	sink.box(xf * Transform3D(Basis(), Vector3(0, 0.01, 0)), Vector3(len, 0.04, w - 1.6), "asphalt2", {"dirt": 0.2})
	for side in [-1.0, 1.0]:
		sink.box(xf * Transform3D(Basis(), Vector3(0, 0.12, side * (w * 0.5 - 0.4))), Vector3(len, 0.25, 0.8), "concrete_dirty", {"dirt": 0.6})
		sink.box(xf * Transform3D(Basis(), Vector3(0, 0.7, side * (w * 0.5 - 0.1))), Vector3(len, 0.9, 0.2), "concrete", {"dirt": 0.7})
	var piers := int(len / 14.0)
	for k in range(1, piers):
		var lx := -len * 0.5 + len * k / piers
		var wp: Vector3 = xf * Vector3(lx, 0, 0)
		var gy: float = L.ground_height(wp.x, wp.z)
		sink.box(Transform3D(xf.basis, Vector3(wp.x, (gy + y) * 0.5 - 0.4, wp.z)), Vector3(1.2, y - gy, w - 1.0), "concrete_dirty", {"dirt": 1.0})
	# Ramps up from the banks.
	for end in [-1.0, 1.0]:
		var e: Vector3 = xf * Vector3(end * len * 0.5, 0, 0)
		var out = Vector3(cos(ang), 0, -sin(ang)) * end
		var gy2: float = L.ground_height(e.x + out.x * 8.0, e.z + out.z * 8.0)
		var rise = y - gy2
		var rl := 8.0
		var ra := atan2(rise, rl)
		var rc = e + out * rl * 0.5 + Vector3(0, -rise * 0.5, 0)
		var rb := Basis(Vector3.UP, ang) * Basis(Vector3.BACK, ra * end)
		sink.box(Transform3D(rb, rc + Vector3(0, -0.3, 0)), Vector3(rl + 0.4, 0.6, w), "concrete", {"dirt": 0.6})
	mb.dyn.add_light({"pos": xf * Vector3(0, 4.0, w * 0.5), "kind": "street", "color": Color(1.0, 0.72, 0.42), "energy": 1.4, "range": 16.0, "flicker": 0.25})


func _rail_bridge(c: Dictionary) -> void:
	var ab := _span(c)
	var a: Vector2 = ab[0]
	var b: Vector2 = ab[1]
	var len := a.distance_to(b)
	var mid := (a + b) * 0.5
	var ang := atan2(-(b - a).y, (b - a).x)
	var y = L.LAND_Y + 1.1
	var xf := Transform3D(Basis(Vector3.UP, ang), Vector3(mid.x, y, mid.y))
	# Steel girders, sleepers you can see the water between, two rails, truss sides.
	for side in [-1.0, 1.0]:
		sink.box(xf * Transform3D(Basis(), Vector3(0, -0.5, side * 1.1)), Vector3(len, 0.9, 0.25), "metal_rust", {"dirt": 0.3})
		sink.box(xf * Transform3D(Basis(), Vector3(0, 3.6, side * 2.3)), Vector3(len, 0.3, 0.3), "metal_rust", {"dirt": 0.3})
		var n := int(len / 4.0)
		for k in n + 1:
			var x := -len * 0.5 + len * k / n
			sink.box(xf * Transform3D(Basis(), Vector3(x, 1.6, side * 2.3)), Vector3(0.25, 3.8, 0.25), "metal_rust", {"dirt": 0.3})
			if k < n:
				var diag := Basis(Vector3.BACK, atan2(3.6, len / n) * (1.0 if k % 2 == 0 else -1.0))
				sink.box(xf * Transform3D(diag, Vector3(x + len / n * 0.5, 1.6, side * 2.3)), Vector3(sqrt(pow(len / n, 2) + 12.96), 0.15, 0.15), "metal_rust", {"dirt": 0.3, "collide": false})
	var sn := int(len / 0.65)
	for k in sn:
		if sink.rng.randf() < 0.06:
			continue
		sink.box(xf * Transform3D(Basis(), Vector3(-len * 0.5 + (k + 0.5) * len / sn, 0.0, 0)), Vector3(0.22, 0.14, 2.8), "timber", {"dirt": 0.9, "collide": false})
	sink.col_box(xf * Transform3D(Basis(), Vector3(0, 0.0, 0)), Vector3(len, 0.14, 2.8), "wood")
	for side in [-0.72, 0.72]:
		sink.box(xf * Transform3D(Basis(), Vector3(0, 0.14, side)), Vector3(len, 0.13, 0.07), "metal_rust", {"dirt": 0.3})


func _footbridge(c: Dictionary, mat: String, y_above: float, steel: bool) -> void:
	var ab := _span(c)
	var a: Vector2 = ab[0]
	var b: Vector2 = ab[1]
	var len := a.distance_to(b)
	var ang := atan2(-(b - a).y, (b - a).x)
	var w := float(c.w)
	var y = L.LAND_Y + (0.9 if steel else 0.5)
	var basis := Basis(Vector3.UP, ang)
	var n := int(len / (0.5 if steel else 0.26))
	for k in n:
		var t := (k + 0.5) / n
		var p := a.lerp(b, t)
		var sag := 0.0 if steel else -sin(t * PI) * 0.35
		var tilt := Basis(Vector3.RIGHT, sink.rng.randf_range(-0.04, 0.04)) if not steel else Basis()
		if not steel and sink.rng.randf() < 0.04:
			continue  # a missing plank
		sink.box(Transform3D(basis * tilt, Vector3(p.x, y + sag, p.y)), Vector3(len / n * (0.96 if steel else 0.85), 0.05, w), mat if steel else _pick(["planks", "planks_dark", "plywood"]),
			{"dirt": 0.8, "collide": false, "layer": "ext"})
	# Walkable surface (piecewise for the sag).
	var segs := 8
	for k in segs:
		var t0 := float(k) / segs
		var t1 := float(k + 1) / segs
		var p0 := a.lerp(b, t0)
		var p1 := a.lerp(b, t1)
		var y0 = y + (0.0 if steel else -sin(t0 * PI) * 0.35)
		var y1 = y + (0.0 if steel else -sin(t1 * PI) * 0.35)
		var mid := (p0 + p1) * 0.5
		var pitch := atan2(y1 - y0, p0.distance_to(p1))
		sink.col_box(Transform3D(basis * Basis(Vector3.BACK, pitch), Vector3(mid.x, (y0 + y1) * 0.5 - 0.02, mid.y)), Vector3(p0.distance_to(p1) + 0.05, 0.06, w), "wood" if not steel else "steel")
	# Railings: steel pipe rails, or rope and bamboo on the plank bridges.
	for side in [-1.0, 1.0]:
		var off = Vector2(sin(ang), cos(ang)) * (w * 0.5 + 0.03) * side
		var posts := int(len / 2.0)
		for k in posts + 1:
			var t := float(k) / posts
			var p = a.lerp(b, t) + off
			var sag2 := 0.0 if steel else -sin(t * PI) * 0.35
			sink.box(Transform3D(basis, Vector3(p.x, y + sag2 + 0.5, p.y)), Vector3(0.05, 1.0, 0.05), "metal_rust" if steel else "bark", {"collide": false})
		var mid2 = (a + b) * 0.5 + off
		sink.box(Transform3D(basis, Vector3(mid2.x, y + 1.0 - (0.0 if steel else 0.2), mid2.y)), Vector3(len, 0.04, 0.04), "metal_rust" if steel else "bark", {"collide": true})
	# Supports in the water.
	var sup := int(len / 6.0)
	for k in range(1, sup):
		var p := a.lerp(b, float(k) / sup)
		var gy: float = L.ground_height(p.x, p.y)
		sink.box(Transform3D(basis, Vector3(p.x, (gy + y) * 0.5, p.y)), Vector3(0.12, y - gy, w + 0.2), "metal_rust" if steel else "timber", {"collide": false})


func _pipe_bridge(c: Dictionary) -> void:
	var ab := _span(c)
	var a: Vector2 = ab[0]
	var b: Vector2 = ab[1]
	var y = L.LAND_Y + 1.6
	var dir3 := Vector3(b.x - a.x, 0, b.y - a.y)
	sink.cylinder(Vector3(a.x, y, a.y), dir3.normalized(), dir3.length(), 0.6, "metal_rust", {"sides": 14, "collide": true, "phys": "steel"})
	_footbridge({"a": c.a + Vector2(0, 1.3), "b": c.b + Vector2(0, 1.3), "w": 0.8}, "grate", 0.0, true)


func _culvert(c: Dictionary) -> void:
	var a: Vector2 = c.a
	var b: Vector2 = c.b
	var mid := (a + b) * 0.5
	var ang := atan2(-(b - a).y, (b - a).x)
	var len := a.distance_to(b) + 4.0
	var xf := Transform3D(Basis(Vector3.UP, ang), Vector3(mid.x, L.LAND_Y + 0.1, mid.y))
	sink.box(xf * Transform3D(Basis(), Vector3(0, -0.3, 0)), Vector3(len, 0.6, float(c.w)), "concrete", {"dirt": 0.7})
	for side in [-1.0, 1.0]:
		sink.box(xf * Transform3D(Basis(), Vector3(0, 0.45, side * float(c.w) * 0.5)), Vector3(len, 0.9, 0.2), "concrete_dirty", {"dirt": 0.7})


func _pick(a: Array):
	return a[rng.randi_range(0, a.size() - 1)]
