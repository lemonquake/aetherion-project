extends RefCounted
## Lawless Sub's street furniture: lamp posts (geometry built here, before the sink is flushed; their lights go in
## through dyn.add_light so Lighting builds them), traffic lights and the wreck pile at the intersection, the bus
## stop and waiting shed, the stalled jeepney and bus on the avenue, parked and burnt-out cars, and the trees and
## shrubs of the canal walk and the estero bank. Every lamp pole top is offered to the PA system.

const LAMP_ALIVE := 0.6
## Downloaded r7 cars (front +Z, length along z) for the parking stalls, and wrecks for the streets.
const PARKED := ["car_compact", "car_coupe", "car_hatchback", "car_minivan", "car_offroad", "car_pickup", "car_sedan", "car_suv", "car_wagon",
	"car_saloon_old", "car_sedan_80s", "car_sedan_80s_b", "car_pickup_old", "van_delivery"]
const HULKS := ["car_burnt_a", "car_burnt_b", "car_police_burnt", "car_saloon_old", "car_sedan_80s", "car_pickup_old", "covered_car"]

var mb = null
var L = null
var sink = null
var rng := RandomNumberGenerator.new()
var stats := {"lamps": 0, "lights": 0, "trees": 0, "shrubs": 0, "cars": 0}


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	sink = mb.sink
	rng.seed = L.rng.seed + 1409


func build() -> void:
	_lamps()
	_traffic_lights()
	_wreck_pile()
	_bus_stop()
	_avenue_wrecks()
	_parked_cars()
	_canal_trees()
	_estero_trees()


# ------------------------------------------------------------------ lamps

func _spot_free(p: Vector2, r: float = 0.6) -> bool:
	if not L.in_play_area(p) or absf(p.x) > L.edge - 2.0 or absf(p.y) > L.edge - 2.0:
		return false
	if L.is_water(p.x, p.y) or L.in_spawn_zone(p, 1.0):
		return false
	for rd in L.roads:
		if L.road_rect(rd, float(rd.w) * 0.5 + 0.3).has_point(p):
			return false
	for l in L.lots:
		if (l.rect as Rect2).grow(r).has_point(p):
			return false
	for br in L.bridge_rects:
		if (br as Rect2).grow(2.0).has_point(p):
			return false
	for pk in L.parking:
		if (pk.rect as Rect2).grow(r).has_point(p):
			return false
	return true


func _near_junction(rd: Dictionary, s: float, margin: float) -> bool:
	for ro in L.roads:
		if int(ro.axis) == int(rd.axis):
			continue
		if float(rd.c) >= float(ro.lo) - float(rd.w) and float(rd.c) <= float(ro.hi) + float(rd.w) and absf(s - float(ro.c)) < float(ro.w) * 0.5 + float(ro.sidewalk) + margin:
			return true
	return false


func _lamps() -> void:
	for ri in L.roads.size():
		var rd: Dictionary = L.roads[ri]
		var kind := str(rd.lamps)
		var hw := float(rd.w) * 0.5
		var sw := float(rd.sidewalk)
		var spacing := 40.0 if kind == "median" else 44.0
		var s = ceilf((float(rd.lo) + 10.0) / spacing) * spacing + (ri % 3) * 7.0
		var k := 0
		while s < float(rd.hi) - 6.0:
			if not _near_junction(rd, s, 6.0):
				var along := Vector2(1, 0) if int(rd.axis) == 0 else Vector2(0, 1)
				if kind == "median":
					var p := _pt(rd, s, 0.0)
					if L.in_play_area(p) and absf(p.y) < L.edge - 4.0 and not L.in_spawn_zone(p, 1.0):
						_pole(p, L.ground_height(p.x, p.y) + L.ROAD_TOP + 0.16, [Vector2(-along.y, along.x), Vector2(along.y, -along.x)], along, 1.5)
				else:
					var side := 1.0 if (kind == "one" and ri % 2 == 0) or (kind == "both" and k % 2 == 0) else -1.0
					var off := hw + (sw - 0.45 if sw > 0.0 else 0.7)
					var p2 := _pt(rd, s, side * off)
					if _spot_free(p2, 0.3) or (sw > 0.0 and L.in_play_area(p2) and not L.in_spawn_zone(p2, 1.0) and absf(p2.x) < L.edge - 3.0 and absf(p2.y) < L.edge - 3.0):
						var toward := (Vector2(0, -side) if int(rd.axis) == 0 else Vector2(-side, 0))
						var gy: float = L.ground_height(p2.x, p2.y) + (L.WALK_TOP if sw > 0.0 else 0.0)
						_pole(p2, gy, [toward], along, 1.6 if hw > 4.0 else 1.1)
			s += spacing
			k += 1


func _pt(rd: Dictionary, s: float, o: float) -> Vector2:
	return Vector2(s, float(rd.c) + o) if int(rd.axis) == 0 else Vector2(float(rd.c) + o, s)


func _pole(p: Vector2, gy: float, arms: Array, along: Vector2, reach: float) -> void:
	var base := Vector3(p.x, gy, p.y)
	var grey := Color(0.55, 0.58, 0.56)
	sink.cylinder(base, Vector3.UP, 8.2, 0.1, "metal_paint", {"sides": 8, "collide": true, "tint": grey, "paint": 0.6, "phys": "steel"})
	for a in arms:
		var toward: Vector2 = a
		var arm := Vector3(toward.x, 0.12, toward.y).normalized()
		sink.cylinder(base + Vector3(0, 8.0, 0), arm, reach + 0.2, 0.05, "metal_paint", {"sides": 6, "tint": grey, "paint": 0.6})
		var head := base + Vector3(0, 8.0, 0) + arm * reach
		sink.box(Transform3D(Basis.looking_at(Vector3(toward.x, 0, toward.y), Vector3.UP), head + Vector3(0, -0.04, 0)), Vector3(0.3, 0.12, 0.6), "metal_paint",
			{"collide": false, "tint": Color(0.4, 0.42, 0.4), "paint": 0.6})
		if rng.randf() < LAMP_ALIVE:
			mb.dyn.add_light({"pos": head + Vector3(0, -0.16, 0), "kind": "street", "color": Color(1.0, 0.72, 0.42) if rng.randf() < 0.6 else Color(0.85, 0.92, 1.0),
				"energy": 1.7, "range": 18.0, "flicker": 0.4 if rng.randf() < 0.2 else 0.0})
			stats.lights += 1
	mb.pole_tops.append([base + Vector3(0, 8.25, 0), along])
	mb.obstacles_add(p, 0.4)
	L.lamp_spots.append(base)
	stats.lamps += 1


# ------------------------------------------------------------------ the intersection

func _traffic_lights() -> void:
	var c: Vector2 = L.dm_centre
	var av := 8.0 + 1.2
	var bv := 7.0 + 1.2
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := c + Vector2(corner.x * av, corner.y * bv)
		var gy: float = L.ground_height(p.x, p.y) + L.WALK_TOP
		var base := Vector3(p.x, gy, p.y)
		sink.cylinder(base, Vector3.UP, 5.6, 0.09, "metal_paint", {"sides": 8, "collide": true, "tint": Color(0.3, 0.32, 0.3), "paint": 0.7, "phys": "steel"})
		# Arm over the lanes coming in, with a three-lamp head (dark: the power is out).
		var arm := Vector3(0, 0, -corner.y) if absf(corner.x) > 0.0 else Vector3(-corner.x, 0, 0)
		arm = Vector3(-corner.x, 0, 0) if corner.x * corner.y > 0.0 else Vector3(0, 0, -corner.y)
		sink.cylinder(base + Vector3(0, 5.4, 0), arm, 4.2, 0.06, "metal_paint", {"sides": 6, "tint": Color(0.3, 0.32, 0.3), "paint": 0.7})
		var head := base + Vector3(0, 5.0, 0) + arm * 4.0
		sink.box(Transform3D(Basis.looking_at(-arm.cross(Vector3.UP), Vector3.UP), head), Vector3(0.36, 1.0, 0.3), "metal_paint", {"collide": false, "tint": Color(0.12, 0.12, 0.1), "paint": 0.9})
		mb.obstacles_add(p, 0.4)


func _wreck_pile() -> void:
	## The pile-up in the middle of the junction: central cover that breaks both long lanes.
	var c: Vector2 = L.dm_centre
	var spec := [["jeepney_painted", Vector2(-3.6, -2.4), 0.45], ["car_police_flipped", Vector2(3.4, 1.6), 1.25], ["car_burnt_a", Vector2(-0.6, 3.6), -0.25],
		["car_police_burnt", Vector2(2.6, -3.4), 2.1], ["hollow_block_pile", Vector2(0.4, -0.2), 0.3], ["sandbag", Vector2(-1.8, 1.0), 0.0]]
	for e in spec:
		var p: Vector2 = c + (e[1] as Vector2)
		var gy: float = L.ground_height(p.x, p.y) + L.ROAD_TOP
		mb.dyn.add_static_prop(str(e[0]), mb.dyn.seat(str(e[0]), Transform3D(Basis(Vector3.UP, float(e[2])), Vector3(p.x, gy, p.y))))
		mb.obstacles_add(p, 3.0 if str(e[0]) != "sandbag" else 1.0)
	stats.cars += 4


func _bus_stop() -> void:
	## A waiting shed behind the avenue's west sidewalk by the junction, and a bus stop sign on each side.
	var c := Vector2(-33.0, -23.0)
	var gy: float = L.ground_height(c.x, c.y)
	sink.box(Transform3D(Basis(), Vector3(c.x, gy + 0.05, c.y)), Vector3(3.6, 0.2, 6.4), "concrete", {"dirt": 0.6, "what": "shed_floor"})
	for dx in [-1.6, 1.6]:
		for dz in [-3.0, 3.0]:
			sink.box(Transform3D(Basis(), Vector3(c.x + dx, gy + 1.4, c.y + dz)), Vector3(0.1, 2.7, 0.1), "metal_paint", {"tint": Color(0.2, 0.4, 0.6), "paint": 0.8})
	sink.box(Transform3D(Basis(Vector3.FORWARD, 0.08), Vector3(c.x, gy + 2.85, c.y)), Vector3(4.0, 0.06, 7.0), "yero_paint",
		{"dirt": 0.5, "tint": Color(0.25, 0.45, 0.65), "paint": 0.8, "inner_faces": 8})
	sink.box(Transform3D(Basis(), Vector3(c.x - 1.4, gy + 0.45, c.y)), Vector3(0.45, 0.08, 5.6), "planks_paint", {"dirt": 0.5})
	sink.box(Transform3D(Basis(), Vector3(c.x - 1.65, gy + 1.0, c.y)), Vector3(0.05, 1.6, 6.0), "metal_paint", {"tint": Color(0.2, 0.4, 0.6), "paint": 0.8})
	mb.obstacles_add(c, 3.5)
	for s in [Vector2(-29.3, -31.0), Vector2(-10.3, 24.0)]:
		var g2: float = L.ground_height(s.x, s.y) + L.WALK_TOP
		sink.cylinder(Vector3(s.x, g2, s.y), Vector3.UP, 2.6, 0.04, "metal_paint", {"sides": 6, "collide": true, "tint": Color(0.6, 0.6, 0.6), "paint": 0.6})
		sink.box(Transform3D(Basis(), Vector3(s.x, g2 + 2.4, s.y)), Vector3(0.04, 0.5, 0.6), "metal_paint", {"collide": false, "tint": Color(0.15, 0.35, 0.7), "paint": 0.95})
		mb.obstacles_add(s, 0.3)


func _avenue_wrecks() -> void:
	## A jeepney stalled in the southbound lanes and a bus dead in the northbound ones: the avenue is seen in stretches.
	var j := Vector2(-24.0, -84.0)
	mb.dyn.add_static_prop("jeepney_painted", mb.dyn.seat("jeepney_painted", Transform3D(Basis(Vector3.UP, 0.12), Vector3(j.x, L.ground_height(j.x, j.y) + L.ROAD_TOP, j.y))))
	mb.obstacles_add(j, 3.0)
	var j2 := Vector2(-15.5, -150.0)
	mb.dyn.add_static_prop("jeepney", mb.dyn.seat("jeepney", Transform3D(Basis(Vector3.UP, PI - 0.2), Vector3(j2.x, L.ground_height(j2.x, j2.y) + L.ROAD_TOP, j2.y))))
	mb.obstacles_add(j2, 3.0)
	_bus(Vector2(-15.8, 92.0), 0.06)
	_bus(Vector2(40.0, 3.5), PI * 0.5 + 0.08)


func _bus(c: Vector2, yaw: float) -> void:
	## A city bus as massing: body, a dark window band, wheels; solid, so it is real cover.
	var gy: float = L.ground_height(c.x, c.y) + L.ROAD_TOP
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, Vector3(c.x, gy, c.y))
	sink.box(xf * Transform3D(Basis(), Vector3(0, 1.85, 0)), Vector3(2.5, 2.7, 11.5), "metal_paint", {"dirt": 0.6, "tint": Color(0.82, 0.8, 0.72), "paint": 0.85, "occlude": true, "what": "bus"})
	sink.box(xf * Transform3D(Basis(), Vector3(0, 2.25, 0)), Vector3(2.56, 0.95, 11.1), "metal_plate", {"collide": false, "faces": 51, "tint": Color(0.08, 0.1, 0.12), "paint": 0.95})
	sink.box(xf * Transform3D(Basis(), Vector3(0, 1.1, 0)), Vector3(2.56, 0.25, 11.56), "metal_paint", {"collide": false, "faces": 51, "tint": Color(0.7, 0.15, 0.12), "paint": 0.9})
	for wz in [-3.8, 3.6]:
		for wx in [-1.1, 1.1]:
			sink.cylinder(xf * Vector3(wx - 0.15 * signf(wx), 0.5, wz), b * Vector3(1, 0, 0), 0.3, 0.5, "black", {"sides": 10})
	mb.obstacles_add(c, 6.0)
	stats.cars += 1


func _parked_cars() -> void:
	## Some stalls hold cars under covers (most of the lots' cars were driven off); a few burnt hulks in the streets.
	var md: Dictionary = mb.models.get_model("covered_car")
	var long_x := false
	if not md.is_empty():
		var bb: AABB = md.aabb
		long_x = bb.size.x > bb.size.z
	for st in mb.stall_spots:
		var r: Rect2 = st.rect
		var n := int(st.n)
		for k in n:
			if rng.randf() > 0.32:
				continue
			var p := Vector2(r.position.x + (k + 0.5) * float(st.w), r.position.y + r.size.y * 0.5)
			if L.in_spawn_zone(p, 3.0) or float(st.w) > 3.0:
				continue
			var nm: String = PARKED[rng.randi_range(0, PARKED.size() - 1)] if rng.randf() < 0.8 else "covered_car"
			var lx := long_x if nm == "covered_car" else false
			var yaw := (PI * 0.5 if lx else 0.0) + rng.randf_range(-0.05, 0.05) + (PI if float(st.facing) < 0.0 else 0.0)
			var gy: float = L.ground_height(p.x, p.y) + L.ROAD_TOP + 0.01
			mb.dyn.add_static_prop(nm, mb.dyn.seat(nm, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, gy, p.y))))
			mb.obstacles_add(p, 2.5)
			stats.cars += 1
	# Hulks parked half on the kerb along the subdivision streets.
	var streets: Array = L.roads.filter(func(rd): return int(rd.prio) == 3)
	for i in 22:
		var rd: Dictionary = streets[rng.randi_range(0, streets.size() - 1)]
		var s := rng.randf_range(float(rd.lo) + 15.0, float(rd.hi) - 15.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p2 := _pt(rd, s, side * (float(rd.w) * 0.5 - 1.1))
		if _near_junction(rd, s, 6.0) or L.in_spawn_zone(p2, 3.0):
			continue
		var nm2: String = HULKS[rng.randi_range(0, HULKS.size() - 1)]
		var lx2 := long_x if nm2 == "covered_car" else false
		var yaw2 := (0.0 if int(rd.axis) == 1 else PI * 0.5) + (PI * 0.5 if lx2 else 0.0) + (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.12, 0.12)
		var gy2: float = L.ground_height(p2.x, p2.y) + L.ROAD_TOP
		mb.dyn.add_static_prop(nm2, mb.dyn.seat(nm2, Transform3D(Basis(Vector3.UP, yaw2), Vector3(p2.x, gy2, p2.y))))
		mb.obstacles_add(p2, 2.5)
		stats.cars += 1


# ------------------------------------------------------------------ greenery

func _tree(p: Vector2, y: float) -> void:
	var name = ["tree_island", "tree_small", "tree_island2", "tree_small"][rng.randi_range(0, 3)]
	mb.dyn.add_static_prop(name, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y, p.y)))
	mb.obstacles_add(p, 0.8)
	stats.trees += 1


func _canal_trees() -> void:
	## Trees every ~9 m down the planter strip on both banks, shrubs between them.
	for e in mb.canal_edges:
		var a: Vector2 = e.a
		var d: Vector2 = e.d
		var nrm: Vector2 = e.n
		var len := float(e.len)
		var t := 4.5
		while t < len - 2.0:
			var p = a + d * t + nrm * (L.WALL_T + 2.6 + (L.APRON - L.WALL_T - 2.6) * 0.5)
			if _green_ok(p):
				var y: float = L.LAND_Y + L.APRON_TOP + 0.06
				if int(t / 4.5) % 2 == 1:
					_tree(p, y)
				else:
					mb.dyn.add_static_prop("shrub", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y, p.y)))
					stats.shrubs += 1
			t += 4.5


func _green_ok(p: Vector2) -> bool:
	if not L.in_play_area(p) or absf(p.x) > L.edge - 3.0 or absf(p.y) > L.edge - 3.0 or L.in_spawn_zone(p, 1.0):
		return false
	for rd in L.roads:
		if L.road_rect(rd, float(rd.w) * 0.5 + float(rd.sidewalk) + 1.5).has_point(p):
			return false
	for br in L.bridge_rects:
		if (br as Rect2).grow(3.0).has_point(p):
			return false
	for l in L.lots:
		if (l.rect as Rect2).grow(1.5).has_point(p):
			return false
	return true


func _estero_trees() -> void:
	for e in L.esteros:
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var off := float(e.hw) + float(e.bank) + 1.6
		var x := a.x + 6.0
		while x < minf(b.x, L.edge - 4.0):
			var p := Vector2(x + rng.randf_range(-2.0, 2.0), a.y + off)
			if _green_ok(p) and L.reserved_at(p.x, p.y) == 0:
				_tree(p, L.ground_height(p.x, p.y))
			x += rng.randf_range(11.0, 19.0)
