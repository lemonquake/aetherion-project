extends RefCounted
## Static details for the playground, covered court and drained pool. These are decorative assemblies;
## all geometry joins existing batches and adds no colliders, nodes, materials, lights or frame callbacks.

const BLUE := Color(0.24, 0.38, 0.48)
const YELLOW := Color(0.83, 0.63, 0.22)
const RED := Color(0.66, 0.25, 0.17)
const WHITE := Color(0.9, 0.88, 0.79)
var sink = null
var stats := {"playgrounds": 0, "slides": 0, "swings": 0, "courts": 0, "hoops": 0, "trusses": 0,
	"pools": 0, "pool_ladders": 0, "benches": 0, "triangles": 0}


static func build_all(mb, layout) -> void:
	var detail = new()
	detail.sink = mb.sink
	var before := int(mb.sink.stats.tris)
	for lot in layout.lots:
		var kind := str(lot.kind)
		if kind not in ["playground", "court", "pool"]:
			continue
		var c: Vector2 = lot.center
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(lot.yaw))), Vector3(c.x, float(lot.plinth_y), c.y))
		match kind:
			"playground": detail._playground(xf)
			"court": detail._court(xf, lot.half)
			"pool": detail._pool(xf, lot.half)
	detail.stats.triangles = int(mb.sink.stats.tris) - before
	mb.stats.landmark_detail = detail.stats


func _box(xf: Transform3D, c: Vector3, size: Vector3, mat: String, color: Color) -> void:
	sink.box(xf * Transform3D(Basis(), c), size, mat,
		{"collide": false, "occlude": false, "tint": color, "paint": 0.9, "dirt": 0.35, "what": "landmark_detail"})


func _tube(xf: Transform3D, a: Vector3, b: Vector3, r: float, color: Color = BLUE) -> void:
	var axis := b - a
	if axis.length_squared() < 0.00001:
		return
	sink.cylinder(xf * a, xf.basis * axis.normalized(), axis.length(), r, "metal_paint",
		{"sides": 6, "collide": false, "tint": color, "paint": 0.9, "dirt": 0.3})


func _ring(xf: Transform3D, c: Vector3, radius: float, tube_r: float, color: Color, segments: int = 20) -> void:
	for i in segments:
		var a := TAU * i / segments
		var b := TAU * (i + 1) / segments
		_tube(xf, c + Vector3(cos(a), 0, sin(a)) * radius, c + Vector3(cos(b), 0, sin(b)) * radius, tube_r, color)


func _playground(xf: Transform3D) -> void:
	# Slide at the left/rear; swing footprint at the right/front. A 1.6 m clear strip separates the assemblies.
	var x := -2.3
	_box(xf, Vector3(x, 1.65, 1.8), Vector3(0.9, 0.1, 0.9), "metal_paint", YELLOW)
	for side in [-1.0, 1.0]:
		for z in [1.45, 2.15]:
			_tube(xf, Vector3(x + side * 0.35, 0.08, z), Vector3(x + side * 0.35, 1.62, z), 0.045)
		_tube(xf, Vector3(x + side * 0.44, 1.68, 1.4), Vector3(x + side * 0.44, 2.3, 1.4), 0.025, YELLOW)
		_tube(xf, Vector3(x + side * 0.44, 1.68, 2.2), Vector3(x + side * 0.44, 2.3, 2.2), 0.025, YELLOW)
		_tube(xf, Vector3(x + side * 0.44, 2.3, 1.4), Vector3(x + side * 0.44, 2.3, 2.2), 0.03, YELLOW)
		_tube(xf, Vector3(x + side * 0.32, 0.12, 3.15), Vector3(x + side * 0.32, 1.68, 2.17), 0.035, YELLOW)
		_tube(xf, Vector3(x + side * 0.39, 1.87, 1.37), Vector3(x + side * 0.39, 0.43, -1.55), 0.045, YELLOW)
	for i in 6:
		var at := Vector3(x, 0.12, 3.15).lerp(Vector3(x, 1.68, 2.17), float(i + 1) / 7.0)
		_tube(xf, at + Vector3(-0.32, 0, 0), at + Vector3(0.32, 0, 0), 0.025, YELLOW)
	sink.quad(xf * Vector3(x - 0.35, 1.69, 1.37), xf * Vector3(x + 0.35, 1.69, 1.37),
		xf * Vector3(x + 0.35, 0.25, -1.55), xf * Vector3(x - 0.35, 0.25, -1.55), "metal_paint",
		{"collide": false, "double": true, "facing": Vector3.UP, "tint": RED, "paint": 0.95, "dirt": 0.25})
	_tube(xf, Vector3(x - 0.37, 0.23, -1.56), Vector3(x + 0.37, 0.23, -1.56), 0.045, YELLOW)
	# Twin A-frames, top beam, four hanging links and two small seats.
	for sx in [-0.2, 3.2]:
		for z in [-2.3, 0.1]:
			_tube(xf, Vector3(sx, 0.08, z), Vector3(sx, 2.55, -1.1), 0.055)
		_tube(xf, Vector3(sx, 0.75, -1.97), Vector3(sx, 0.75, -0.23), 0.035)
	_tube(xf, Vector3(-0.25, 2.55, -1.1), Vector3(3.25, 2.55, -1.1), 0.07, YELLOW)
	for sx in [0.6, 2.2]:
		_box(xf, Vector3(sx, 0.55, -1.1), Vector3(0.62, 0.07, 0.28), "metal_paint", RED)
		for side in [-1.0, 1.0]:
			_tube(xf, Vector3(sx + side * 0.25, 0.59, -1.1), Vector3(sx + side * 0.25, 2.5, -1.1), 0.012, WHITE)
	stats.playgrounds += 1
	stats.slides += 1
	stats.swings += 2


func _line(xf: Transform3D, a: Vector2, b: Vector2, width: float = 0.09) -> void:
	var d := (b - a).normalized()
	var side := Vector2(-d.y, d.x) * width * 0.5
	var points := [a - side, b - side, b + side, a + side]
	sink.quad(xf * Vector3(points[0].x, 0.075, points[0].y), xf * Vector3(points[1].x, 0.075, points[1].y),
		xf * Vector3(points[2].x, 0.075, points[2].y), xf * Vector3(points[3].x, 0.075, points[3].y), "concrete_painted",
		{"collide": false, "facing": Vector3.UP, "tint": WHITE, "paint": 1.0, "dirt": 0.12})


func _arc(xf: Transform3D, c: Vector2, radius: float, start: float, end: float, steps: int = 32) -> void:
	for i in steps:
		var a := lerpf(start, end, float(i) / steps)
		var b := lerpf(start, end, float(i + 1) / steps)
		_line(xf, c + Vector2(cos(a), sin(a)) * radius, c + Vector2(cos(b), sin(b)) * radius)


func _court(xf: Transform3D, half: Vector2) -> void:
	# Practice-court markings follow the existing opposed backboards across the covered slab's short axis.
	var hx := minf(7.3, half.x - 1.0)
	var hz := half.y - 1.35
	for side in [-1.0, 1.0]:
		_line(xf, Vector2(-hx, side * hz), Vector2(hx, side * hz))
		_line(xf, Vector2(side * hx, -hz), Vector2(side * hx, hz))
		var free_z: float = side * (hz - 4.6)
		_line(xf, Vector2(-2.45, side * hz), Vector2(-2.45, free_z))
		_line(xf, Vector2(2.45, side * hz), Vector2(2.45, free_z))
		_line(xf, Vector2(-2.45, free_z), Vector2(2.45, free_z))
		_arc(xf, Vector2(0, free_z), 1.8, PI if side > 0 else 0.0, TAU if side > 0 else PI, 20)
		var hoop_z: float = side * (half.y - 1.73)
		_arc(xf, Vector2(0, hoop_z), 6.2, PI if side > 0 else 0.0, TAU if side > 0 else PI, 32)
		_hoop(xf, Vector3(0, 3.05, hoop_z), side)
	_line(xf, Vector2(-hx, 0), Vector2(hx, 0))
	_arc(xf, Vector2.ZERO, 1.8, 0.0, TAU, 40)
	# Four deep parallel steel trusses sit directly under the existing roof and terminate at its columns.
	for i in 4:
		var z := -half.y + 1.0 + (half.y * 2.0 - 2.0) * i / 3.0
		var x0 := -half.x + 0.5
		var x1 := half.x - 0.5
		_tube(xf, Vector3(x0, 7.42, z), Vector3(x1, 7.42, z), 0.055)
		_tube(xf, Vector3(x0, 6.48, z), Vector3(x1, 6.48, z), 0.055)
		for k in 8:
			var a := lerpf(x0, x1, float(k) / 8.0)
			var b := lerpf(x0, x1, float(k + 1) / 8.0)
			_tube(xf, Vector3(a, 6.48 if k % 2 == 0 else 7.42, z), Vector3(b, 7.42 if k % 2 == 0 else 6.48, z), 0.035)
		for side in [-1.0, 1.0]:
			_tube(xf, Vector3(side * (half.x - 0.5), 5.7, z), Vector3(side * (half.x - 2.9), 6.48, z), 0.045)
		stats.trusses += 1
	stats.courts += 1


func _hoop(xf: Transform3D, c: Vector3, side: float) -> void:
	_ring(xf, c, 0.23, 0.022, RED)
	_box(xf, c + Vector3(0, 0, side * 0.34), Vector3(0.11, 0.055, 0.36), "metal_paint", RED)
	for i in 8:
		var a := TAU * i / 8.0
		_tube(xf, c + Vector3(cos(a) * 0.21, -0.025, sin(a) * 0.21),
			c + Vector3(cos(a + 0.35) * 0.13, -0.36, sin(a + 0.35) * 0.13), 0.007, WHITE)
	_ring(xf, c + Vector3(0, -0.36, 0), 0.13, 0.007, WHITE, 12)
	# Two braces carry each existing plywood board up to the roof structure.
	for sx in [-0.65, 0.65]:
		_tube(xf, Vector3(sx, 3.45, c.z + side * 0.53), Vector3(sx, 6.47, c.z + side * 0.53), 0.035)
	stats.hoops += 1


func _pool(xf: Transform3D, half: Vector2) -> void:
	var edge := half.y - 1.5
	var cx := minf(2.8, half.x - 2.2)
	var profile := [Vector2(0.08, edge + 0.65), Vector2(1.05, edge + 0.65), Vector2(1.28, edge + 0.5),
		Vector2(1.35, edge + 0.25), Vector2(1.28, edge), Vector2(1.05, edge - 0.25), Vector2(0.2, edge - 0.25)]
	for side in [-1.0, 1.0]:
		for i in profile.size() - 1:
			_tube(xf, Vector3(cx + side * 0.35, profile[i].x, profile[i].y), Vector3(cx + side * 0.35, profile[i + 1].x, profile[i + 1].y), 0.028, WHITE)
	for y in [0.3, 0.5, 0.7, 0.9]:
		_tube(xf, Vector3(cx - 0.35, y, edge - 0.25), Vector3(cx + 0.35, y, edge - 0.25), 0.025, WHITE)
	var bench := Vector3(-3.5, 0, -half.y + 0.85)
	for side in [-1.0, 1.0]:
		for z in [-0.16, 0.16]:
			_box(xf, bench + Vector3(side * 0.82, 0.27, z), Vector3(0.065, 0.43, 0.065), "metal_paint", BLUE)
		_box(xf, bench + Vector3(side * 0.82, 0.73, -0.25), Vector3(0.06, 0.9, 0.06), "metal_paint", BLUE)
	for z in [-0.16, 0, 0.16]:
		_box(xf, bench + Vector3(0, 0.51, z), Vector3(2.2, 0.065, 0.13), "planks", YELLOW)
	for y in [0.8, 1.0]:
		_box(xf, bench + Vector3(0, y, -0.26), Vector3(2.2, 0.13, 0.065), "planks", YELLOW)
	stats.pools += 1
	stats.pool_ladders += 1
	stats.benches += 1
