extends RefCounted
## Static civil detail for Lawless Sub. Everything is submitted to GeoSink once at map construction;
## small service details use its short-range layer and share the existing material batches.

const GREEN := Color(0.2, 0.39, 0.34)
const CREAM := Color(0.83, 0.79, 0.65)
const YELLOW := Color(0.93, 0.7, 0.22)

var mb = null
var L = null
var sink = null
var stats := {"overpasses": 0, "stair_flights": 0, "drains": 0, "manholes": 0, "repairs": 0,
	"bridge_joints": 0, "bridge_bearings": 0, "utility_cabinets": 0, "bollards": 0}


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	sink = mb.sink


func build() -> void:
	_overpass()
	for i in L.roads.size():
		_road_services(L.roads[i], i)
	_bridge_structure()
	_street_utilities()
	_median_gardens()
	mb.stats.street_detail = stats


func _box(p: Vector3, size: Vector3, mat: String, opt: Dictionary = {}) -> void:
	sink.box(Transform3D(Basis(), p), size, mat, opt)


func _beam(a: Vector3, b: Vector3, w: float, mat: String, col: Color = GREEN, layer: String = "ext") -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var u := d.normalized()
	var ref := Vector3.UP if absf(u.y) < 0.95 else Vector3.RIGHT
	var r := ref.cross(u).normalized()
	var basis := Basis(r, u.cross(r), u)
	sink.box(Transform3D(basis, (a + b) * 0.5), Vector3(w, w, d.length()), mat,
		{"collide": false, "tint": col, "paint": 0.8, "dirt": 0.36, "layer": layer})


func _overpass() -> void:
	## Covered pedestrian crossing, 5.56 m clear below its deepest beam. The stairs are wholly inside
	## the 3 m public sidewalks; their 1.8 m width leaves a 1.2 m bypass beside the curb.
	var cx := -20.0
	var cz := -48.0
	var ground: float = L.LAND_Y + L.WALK_TOP
	var top := ground + 6.2
	var x0 := cx - 11.1
	var x1 := cx + 11.1
	var z0 := cz - 1.2
	var z1 := cz + 1.2
	_box(Vector3(cx, top - 0.17, cz), Vector3(x1 - x0, 0.34, 2.4), "concrete_floor2",
		{"what": "overpass_deck", "dirt": 0.45, "phys": "concrete"})
	# Deep longitudinal edge girders and transverse floor beams give the deck a constructed underside.
	for z in [z0 + 0.12, z1 - 0.12]:
		_box(Vector3(cx, top - 0.48, z), Vector3(x1 - x0 + 0.12, 0.56, 0.2), "metal_paint",
			{"collide": false, "tint": GREEN, "paint": 0.82, "dirt": 0.48})
		if z < cz:
			_rail(Vector3(x0 + 0.05, top, z), Vector3(x1 - 0.05, top, z), 1.12, true)
		else:
			# Leave the full stair width open at both landings.
			_rail(Vector3(x0 + 2.0, top, z), Vector3(x1 - 2.0, top, z), 1.12, true)
	for x in [cx - 9.7, cx + 9.7]:
		# Piers stay at the outside of the footway, away from the carriageway and its bypass.
		var pier_x := cx + signf(x - cx) * 10.55
		_box(Vector3(pier_x, ground + (top - ground) * 0.5 - 0.17, cz), Vector3(0.45, top - ground - 0.34, 1.55), "concrete",
			{"what": "overpass_pier", "dirt": 0.5})
		_box(Vector3(pier_x, top - 0.55, cz), Vector3(1.15, 0.3, 2.4), "concrete", {"collide": false, "dirt": 0.5})
		_box(Vector3(pier_x, ground + 0.12, cz), Vector3(0.7, 0.24, 1.85), "concrete_dirty", {"dirt": 0.65})
		mb.obstacles_add(Vector2(pier_x, cz), 0.8)
	for x in [x0 + 1.1, x1 - 1.1]:
		_stair(Vector3(x, ground, z1 + 12.0), Vector3(x, top, z1), 1.8)
		# The landing's back and outer end are protected, while the stair entry remains open.
		_rail(Vector3(x + (-0.9 if x < cx else 0.9), top, z0),
			Vector3(x + (-0.9 if x < cx else 0.9), top, z1), 1.12, true)
	# Roof posts, rafters and a shallow corrugated gable. No extra lights or transparent surfaces.
	for i in 7:
		var x := x0 + (x1 - x0) * i / 6.0
		for z in [cz - 1.12, cz + 1.12]:
			_box(Vector3(x, top + 1.3, z), Vector3(0.075, 2.6, 0.075), "metal_paint",
				{"collide": false, "tint": GREEN, "paint": 0.8})
		_beam(Vector3(x, top + 2.43, cz - 1.55), Vector3(x, top + 2.8, cz), 0.07, "metal_paint")
		_beam(Vector3(x, top + 2.8, cz), Vector3(x, top + 2.43, cz + 1.55), 0.07, "metal_paint")
		if i < 6:
			_box(Vector3(x + (x1 - x0) / 12.0, top - 0.28, cz), Vector3(0.1, 0.22, 2.2), "metal_paint",
				{"collide": false, "tint": GREEN, "paint": 0.8})
	for side in [-1.0, 1.0]:
		var bs := Basis(Vector3.RIGHT, side * 0.234)
		sink.box(Transform3D(bs, Vector3(cx, top + 2.61, cz + side * 0.81)), Vector3(23.0, 0.065, 1.69), "yero_paint",
			{"collide": false, "tint": GREEN, "paint": 0.85, "dirt": 0.35})
		# Gutter and pipe terminate in the public gutter rather than floating above the road.
		_box(Vector3(cx, top + 2.41, cz + side * 1.62), Vector3(23.1, 0.1, 0.12), "metal_paint",
			{"collide": false, "tint": CREAM, "paint": 0.65})
		_beam(Vector3(x0 + 0.25, ground + 0.25, cz + side * 1.45), Vector3(x0 + 0.25, top + 2.4, cz + side * 1.45), 0.065, "metal_paint", CREAM)
	# Side fascia: a real sign housing and inset face, to be lettered through the shared sign atlas.
	for z in [cz - 1.27, cz + 1.27]:
		_box(Vector3(cx, top + 0.66, z), Vector3(6.0, 1.2, 0.055), "metal_paint",
			{"collide": false, "tint": GREEN, "paint": 0.95, "dirt": 0.15})
		_box(Vector3(cx, top + 0.66, z + signf(z - cz) * 0.035), Vector3(5.8, 1.05, 0.018), "metal_paint",
			{"collide": false, "tint": CREAM, "paint": 1.0, "dirt": 0.12})
		sink.atlas_quad(Vector3(cx, top + 0.66, z + signf(z - cz) * 0.057), Vector3(signf(z - cz), 0, 0), Vector3.UP,
			5.8, 1.05, Rect2(0.75, 0.75, 0.25, 0.25), "decal:res://assets/urban/signs.png", {"layer": "ext"})
	stats.overpasses += 1
	stats.overpass = {"center": Vector3(cx, top, cz), "stair_feet": [Vector3(-30, ground, -34.8), Vector3(-10, ground, -34.8)],
		"deck_top": top, "road_clearance": top - 0.76 - (L.LAND_Y + L.ROAD_TOP), "width": 2.4}


func _rail(a: Vector3, b: Vector3, height: float, collision: bool) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	for h in [0.12, 0.56, height]:
		_beam(a + Vector3.UP * h, b + Vector3.UP * h, 0.05, "metal_paint", CREAM)
	var count := maxi(ceili(len / 1.25), 1)
	for i in count + 1:
		var p := a.lerp(b, float(i) / count)
		_box(p + Vector3.UP * height * 0.5, Vector3(0.055, height, 0.055), "metal_paint",
			{"collide": false, "tint": CREAM, "paint": 0.8})
	if collision:
		var horizontal := Vector3(d.x, 0, d.z)
		var basis := Basis(Vector3.UP, atan2(-horizontal.z, horizontal.x))
		sink.col_box(Transform3D(basis, (a + b) * 0.5 + Vector3.UP * height * 0.5),
			Vector3(horizontal.length(), height, 0.065), "steel", "overpass_rail")


func _stair(foot: Vector3, landing: Vector3, width: float) -> void:
	var count := 34
	var d := landing - foot
	var run := absf(d.z)
	var tread := run / count
	var rise := d.y / count
	# Rendered treads have no individual physics faces: a single smooth slab is the walkable surface.
	# The slab follows the top envelope of the treads, so the capsule never catches a riser.
	var dir := Vector3(0, 0, signf(d.z))
	for i in count:
		var p := foot + dir * (tread * (i + 0.5)) + Vector3.UP * rise * (i + 1)
		_box(p - Vector3.UP * 0.06, Vector3(width, 0.12, tread + 0.012), "concrete_floor2",
			{"collide": false, "dirt": 0.45, "faces": 55, "what": "overpass_tread"})
		if i % 4 == 0:
			_box(p + dir * (tread * 0.34) + Vector3.UP * 0.007, Vector3(width - 0.06, 0.014, 0.055), "metal_paint",
				{"collide": false, "tint": YELLOW, "paint": 0.85, "layer": "mid"})
	var angle := atan2(d.y, run)
	var b := Basis(Vector3.RIGHT, angle * -signf(d.z))
	var length := d.length()
	var ramp_c := (foot + landing) * 0.5 - Vector3.UP * 0.13
	sink.col_box(Transform3D(b, ramp_c), Vector3(width, 0.26, length + 0.06), "concrete", "overpass_stair_ramp")
	for side in [-1.0, 1.0]:
		var off := Vector3(side * (width * 0.5 - 0.04), 0, 0)
		_beam(foot + off - Vector3.UP * 0.16, landing + off - Vector3.UP * 0.16, 0.18, "metal_paint")
		# Handrail is sloped with the flight; thin side faces close the stair edge at the same slope.
		for h in [0.5, 1.05]:
			_beam(foot + off + Vector3.UP * h, landing + off + Vector3.UP * h, 0.05, "metal_paint", CREAM)
		for i in 9:
			var p := foot.lerp(landing, i / 8.0) + off
			_box(p + Vector3.UP * 0.525, Vector3(0.055, 1.05, 0.055), "metal_paint",
				{"collide": false, "tint": CREAM, "paint": 0.8})
		# A narrow, sloped barrier prevents stepping through the handrail without blocking the bypass.
		sink.col_box(Transform3D(b, (foot + landing) * 0.5 + off + Vector3.UP * 0.6),
			Vector3(0.065, 1.15, length + 0.02), "steel", "overpass_stair_rail")
	mb.stairs.append({"foot": foot, "top": landing, "dir": dir, "start": foot, "run": run, "rise": d.y, "w": width, "side": 0})
	stats.stair_flights += 1


func _pt(rd: Dictionary, s: float, o: float) -> Vector2:
	return Vector2(s, float(rd.c) + o) if int(rd.axis) == 0 else Vector2(float(rd.c) + o, s)


func _junction(rd: Dictionary, s: float, margin: float) -> bool:
	for other in L.roads:
		if int(other.axis) == int(rd.axis):
			continue
		if float(rd.c) >= float(other.lo) and float(rd.c) <= float(other.hi) and absf(s - float(other.c)) < float(other.w) * 0.5 + float(other.sidewalk) + margin:
			return true
	return false


func _on_bridge(p: Vector2) -> bool:
	for rect in L.bridge_rects:
		if (rect as Rect2).grow(1.5).has_point(p):
			return true
	return false


func _road_services(rd: Dictionary, index: int) -> void:
	var lo := maxf(float(rd.lo), -L.edge + 7.0)
	var hi := minf(float(rd.hi), L.edge - 7.0)
	var along := Vector3.RIGHT if int(rd.axis) == 0 else Vector3.BACK
	var across := Vector3.BACK if int(rd.axis) == 0 else Vector3.RIGHT
	var basis := Basis(Vector3.UP, 0.0 if int(rd.axis) == 0 else PI * 0.5)
	var s := ceilf(lo / 29.0) * 29.0 + (index % 3) * 3.0
	while s < hi:
		if not _junction(rd, s, 3.0):
			for side in [-1.0, 1.0]:
				var p := _pt(rd, s, side * (float(rd.w) * 0.5 - 0.35))
				if L.is_water(p.x, p.y) or _on_bridge(p):
					continue
				var y: float = L.ground_height(p.x, p.y) + L.ROAD_TOP + 0.007
				var c := Vector3(p.x, y, p.y)
				# Recessed dark throat, cast frame, then individual crossbars. All are flush and non-blocking.
				sink.box(Transform3D(basis, c), Vector3(0.84, 0.012, 0.46), "black", {"collide": false, "layer": "mid", "faces": 4})
				for off in [-0.42, 0.42]:
					_beam(c + along * off - across * 0.23, c + along * off + across * 0.23, 0.045, "metal_rust", CREAM, "mid")
				for k in 7:
					var a := c + along * (-0.35 + k * 0.116) + Vector3.UP * 0.007
					_beam(a - across * 0.22, a + across * 0.22, 0.028, "metal_rust", CREAM, "mid")
				stats.drains += 1
			var mid := _pt(rd, s + 3.0, 1.1 if float(rd.w) > 8.0 else 0.65)
			if not L.is_water(mid.x, mid.y) and not _on_bridge(mid):
				_manhole(Vector3(mid.x, L.ground_height(mid.x, mid.y) + L.ROAD_TOP + 0.008, mid.y))
			# Repair trench follows one road edge with a construction seam, below lane markings.
			var rp := _pt(rd, s - 3.0, -float(rd.w) * 0.25)
			if not L.is_water(rp.x, rp.y) and not _on_bridge(rp):
				var y: float = L.ground_height(rp.x, rp.y) + L.ROAD_TOP + 0.003
				var rc := Vector3(rp.x, y, rp.y)
				var length := 2.2 + (index % 4) * 0.45
				sink.quad(rc - along * length * 0.5 - across * 0.43, rc + along * length * 0.5 - across * 0.36,
					rc + along * (length * 0.5 - 0.1) + across * 0.47, rc - along * length * 0.5 + across * 0.39,
					"road_asphalt2", {"facing": Vector3.UP, "collide": false, "layer": "mid", "dirt": 0.68, "tint": Color(0.5, 0.5, 0.5), "paint": 0.5})
				stats.repairs += 1
		s += 29.0


func _manhole(c: Vector3) -> void:
	# Eight-sided cast cover with a contrasting rim and shallow radial ribs.
	for i in 4:
		var a0 := i * PI * 0.5
		var a1 := a0 + PI * 0.25
		var a2 := a0 + PI * 0.5
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * 0.34
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * 0.34
		var p2 := c + Vector3(cos(a2), 0, sin(a2)) * 0.34
		sink.quad(c, p0, p1, p2, "metal_plate", {"facing": Vector3.UP, "layer": "mid", "dirt": 0.65})
		_beam(p0 + Vector3.UP * 0.008, p1 + Vector3.UP * 0.008, 0.025, "metal_rust", CREAM, "mid")
		_beam(p1 + Vector3.UP * 0.008, p2 + Vector3.UP * 0.008, 0.025, "metal_rust", CREAM, "mid")
	for off in [-0.13, 0.0, 0.13]:
		_beam(c + Vector3(-0.21, 0.015, off), c + Vector3(0.21, 0.015, off), 0.018, "metal_rust", CREAM, "mid")
	stats.manholes += 1


func _bridge_structure() -> void:
	for bridge in L.bridges:
		if str(bridge.type) == "footbridge":
			_footbridge_truss(bridge)
			continue
		if str(bridge.type) != "road_bridge":
			continue
		var rect: Rect2 = bridge.rect
		var rd: Dictionary = {}
		for r in L.roads:
			if str(r.name) == str(bridge.get("road", "")):
				rd = r
		if rd.is_empty():
			continue
		var axis := int(rd.axis)
		var a := rect.position.x if axis == 0 else rect.position.y
		var b := rect.end.x if axis == 0 else rect.end.y
		var along := Vector3.RIGHT if axis == 0 else Vector3.BACK
		var across := Vector3.BACK if axis == 0 else Vector3.RIGHT
		var deck_y: float = L.LAND_Y + L.ROAD_TOP
		var width := float(rd.w) + float(rd.sidewalk) * 2.0
		for end in [a + 0.45, b - 0.45]:
			var p := _pt(rd, end, 0)
			var c := Vector3(p.x, deck_y + 0.006, p.y)
			_beam(c - across * float(rd.w) * 0.5, c + across * float(rd.w) * 0.5, 0.055, "metal_plate", Color(0.25, 0.26, 0.25), "mid")
			stats.bridge_joints += 1
			for off in [-width * 0.28, width * 0.28]:
				var bp: Vector3 = c + across * off - Vector3.UP * 0.86
				_box(bp, Vector3(0.9, 0.18, 0.9), "black", {"collide": false, "layer": "mid"})
				_box(bp - Vector3.UP * 0.28, Vector3(1.15, 0.38, 1.15), "concrete_dirty", {"collide": false, "dirt": 0.8})
				stats.bridge_bearings += 1
		# Downstand longitudinal girders, drainage scuppers and underside service conduit.
		for side in [-1.0, 1.0]:
			var p0 := _pt(rd, a + 0.6, side * (width * 0.5 - 0.3))
			var p1 := _pt(rd, b - 0.6, side * (width * 0.5 - 0.3))
			_beam(Vector3(p0.x, L.LAND_Y - 0.9, p0.y), Vector3(p1.x, L.LAND_Y - 0.9, p1.y), 0.36, "concrete", CREAM)
			var s := a + 2.0
			while s < b - 1.0:
				var p := _pt(rd, s, side * (width * 0.5 + 0.18))
				_beam(Vector3(p.x, L.LAND_Y - 0.2, p.y), Vector3(p.x, L.WATER_Y + 0.35, p.y), 0.09, "metal_rust", CREAM, "mid")
				s += 5.0


func _footbridge_truss(bridge: Dictionary) -> void:
	var a: Vector2 = bridge.a
	var b: Vector2 = bridge.b
	var d := (b - a).normalized()
	var side := Vector2(-d.y, d.x)
	var len := a.distance_to(b)
	var top: float = L.LAND_Y + 0.22
	var width := float(bridge.get("w", 2.2))
	for s in [-1.0, 1.0]:
		var off: Vector2 = side * (width * 0.5 - 0.04) * s
		var pa := Vector3(a.x + off.x, top - 0.27, a.y + off.y)
		var pb := Vector3(b.x + off.x, top - 0.27, b.y + off.y)
		_beam(pa, pb, 0.18, "metal_paint")
		var count := maxi(ceili(len / 3.2), 1)
		for i in count:
			var p0 := a.lerp(b, float(i) / count) + off
			var p1 := a.lerp(b, float(i + 1) / count) + off
			_beam(Vector3(p0.x, top + (0.12 if i % 2 == 0 else 0.94), p0.y),
				Vector3(p1.x, top + (0.94 if i % 2 == 0 else 0.12), p1.y), 0.05, "metal_paint", GREEN)
		for end in [pa, pb]:
			_box(end - Vector3.UP * 0.12, Vector3(0.48, 0.2, 0.48), "concrete_dirty", {"dirt": 0.8, "collide": false})
			stats.bridge_bearings += 1
	for i in 9:
		var p := a.lerp(b, i / 8.0)
		_beam(Vector3(p.x - side.x * width * 0.5, top - 0.18, p.y - side.y * width * 0.5),
			Vector3(p.x + side.x * width * 0.5, top - 0.18, p.y + side.y * width * 0.5), 0.08, "metal_paint")


func _street_utilities() -> void:
	# Cabinets sit by existing retaining walls, clear of lot entries, spawn zones and traffic lanes.
	for p in [Vector2(-8.1, -59), Vector2(-8.1, 24), Vector2(208.5, 8.9), Vector2(209, -8.9)]:
		var y: float = L.ground_height(p.x, p.y)
		_box(Vector3(p.x, y + 0.16, p.y), Vector3(0.85, 0.32, 0.55), "concrete_dirty", {"what": "utility_plinth", "dirt": 0.65})
		_box(Vector3(p.x, y + 0.83, p.y), Vector3(0.72, 1.03, 0.42), "metal_paint",
			{"what": "utility_cabinet", "tint": GREEN, "paint": 0.8, "dirt": 0.55})
		_box(Vector3(p.x, y + 1.37, p.y), Vector3(0.8, 0.07, 0.48), "metal_paint",
			{"collide": false, "tint": GREEN, "paint": 0.8, "dirt": 0.4})
		for h in [0.65, 0.73, 0.81, 0.89]:
			_box(Vector3(p.x, y + h, p.y - 0.215), Vector3(0.4, 0.022, 0.015), "black",
				{"collide": false, "layer": "mid", "faces": 32})
		mb.obstacles_add(p, 0.65)
		stats.utility_cabinets += 1
	# Short bollards protect the bus-stop pad without fencing the public sidewalk.
	for z in [-26.6, -23.0, -19.4]:
		var p := Vector2(-31.45, z)
		var y: float = L.ground_height(p.x, p.y)
		sink.cylinder(Vector3(p.x, y, p.y), Vector3.UP, 0.72, 0.065, "metal_paint",
			{"sides": 6, "collide": true, "phys": "steel", "what": "bollard", "tint": YELLOW, "paint": 0.9})
		_box(Vector3(p.x, y + 0.56, p.y), Vector3(0.135, 0.09, 0.135), "metal_paint",
			{"collide": false, "tint": CREAM, "paint": 1.0, "layer": "mid"})
		mb.obstacles_add(p, 0.2)
		stats.bollards += 1


func _median_gardens() -> void:
	## Five separated public planting groups in the avenue median. Residential entrances stay untouched;
	## the nearest planting is over 60 m from the overpass, and none occupies a junction or lamp base.
	var positions := []
	var tree: Dictionary = mb.models.get_model("tree_small")
	var scale := 0.8
	if not tree.is_empty():
		var bounds: AABB = tree.aabb
		scale = minf(0.8, 7.0 / maxf(bounds.size.y, 0.1))
	for z in [-190.0, -110.0, 70.0, 145.0, 185.0]:
		var p := Vector2(-20.0, z)
		if L.in_spawn_zone(p, 8.0) or L.is_water(p.x, p.y):
			continue
		var median_y: float = L.ground_height(p.x, p.y) + L.ROAD_TOP + 0.16
		# Border, soil and open planting cavity are distinct, with all edges inside the 1.2 m median.
		for dx in [-0.44, 0.44]:
			_box(Vector3(p.x + dx, median_y + 0.12, z), Vector3(0.14, 0.24, 4.0), "concrete",
				{"what": "median_planter", "dirt": 0.65, "tint": CREAM, "paint": 0.25})
		for dz in [-1.93, 1.93]:
			_box(Vector3(p.x, median_y + 0.12, z + dz), Vector3(0.74, 0.24, 0.14), "concrete",
				{"what": "median_planter", "dirt": 0.65, "tint": CREAM, "paint": 0.25})
		_box(Vector3(p.x, median_y + 0.11, z), Vector3(0.74, 0.08, 3.72), "dirt",
			{"faces": 4, "collide": false, "dirt": 0.4})
		var soil_y := median_y + 0.15
		var tree_xf := Transform3D(Basis(Vector3.UP, z * 0.09).scaled(Vector3.ONE * scale), Vector3(p.x, soil_y, z))
		mb.dyn.add_static_prop("tree_small", mb.dyn.seat("tree_small", tree_xf))
		for dz in [-1.35, 1.35]:
			var shrub_xf := Transform3D(Basis(Vector3.UP, z * 0.17 + dz).scaled(Vector3.ONE * 0.55), Vector3(p.x, soil_y, z + dz))
			mb.dyn.add_static_prop("shrub", mb.dyn.seat("shrub", shrub_xf))
		mb.obstacles_add(p, 0.65)
		positions.append(Vector3(p.x, soil_y, z))
	stats.median_gardens = positions
	stats.added_trees = positions.size()
	stats.added_shrubs = positions.size() * 2
