extends RefCounted
## Steps up to raised front doors. Houses on a slope stand on a plinth up to the highest corner, and stilt houses
## stand on decks, so many outer doors open well above the lane. Each such door gets a short flight of steps down
## to the surface in front of it (the lane, or a boardwalk for houses over water): concrete block for plinths,
## planks for stilt houses. Rises stay under the character step height, so everyone can walk in.

const RISE := 0.19   # target step rise (character step height is 0.36)

var mb = null
var L = null
var stats := {"doors": 0, "flights": 0, "steps": 0, "unreachable": 0}
var _walks: Array = []


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	for a in mb.alleys:
		if a.has("y"):
			_walks.append(a)


func build() -> void:
	var seen := {}
	for d in mb.dyn.doors:
		if not d.get("outer", false) or not d.has("outward"):
			continue
		stats.doors += 1
		var out: Vector3 = d.outward
		out.y = 0.0
		if out.length() < 0.5:
			continue
		out = out.normalized()
		var xf: Transform3D = d.xf
		var w := float(d.w)
		var foot: Vector3 = xf * Vector3(w * 0.5, 0.0, 0.0)
		var probe := Vector2(foot.x + out.x * 1.0, foot.z + out.z * 1.0)
		var surf := _surface(probe)
		if surf == -INF:
			stats.unreachable += 1
			continue
		var rise := foot.y - surf
		d.steps_out = 0.0
		if rise < 0.24 or rise > 3.4:
			continue
		var n := int(ceil(rise / RISE))
		var sh := rise / n
		var sd := 0.3 if rise < 1.4 else 0.26
		var width := w + 0.3
		var timber = rise > 1.1 or L.is_water(probe.x, probe.y)
		var side := Vector3.UP.cross(out).normalized()
		var basis := Basis(side, Vector3.UP, out)
		for i in range(1, n):
			var top := foot.y - i * sh
			var z0 := 0.06 + (i - 1) * sd
			var bottom := surf - 0.2 if not timber else top - 0.08
			var h := top - bottom
			var c := foot + out * (z0 + sd * 0.5)
			c.y = bottom + h * 0.5
			mb.sink.box(Transform3D(basis, c), Vector3(width, h, sd), "floor_planks" if timber else "chb2",
				{"dirt": 0.9, "phys": "wood" if timber else "concrete", "layer": "ext"})
			stats.steps += 1
		if timber and n > 2:
			# Stringers under a plank flight so it does not float.
			var run := 0.06 + (n - 1) * sd
			for sx in [-width * 0.5 + 0.05, width * 0.5 - 0.05]:
				var a = foot + side * sx + out * 0.06 + Vector3.DOWN * 0.1
				var b = foot + side * sx + out * run + Vector3.DOWN * (rise - 0.05)
				var mid = (a + b) * 0.5
				var len = a.distance_to(b)
				var dir = (b - a) / len
				mb.sink.box(Transform3D(Basis(side, dir.cross(side).normalized(), dir), mid), Vector3(0.06, 0.12, len), "timber",
					{"dirt": 0.9, "collide": false, "layer": "ext"})
		var run2 := 0.06 + (n - 1) * sd
		d.steps_out = run2
		stats.flights += 1
		# Keep street clutter off the flight (walkable for bots: value 4).
		var mid2 := foot + out * run2 * 0.5
		L.reserve_rect(Vector2(mid2.x, mid2.z), Vector2(width * 0.5, run2 * 0.5 + 0.2), atan2(side.z, side.x), 4, 0.0, true)


func _surface(p: Vector2) -> float:
	## Height of the walkable surface at p: a boardwalk deck if one passes here, else the ground; -INF over open water.
	var best := -INF
	if L.is_water(p.x, p.y):
		for a in _walks:
			var pa: Vector2 = a.a
			var pb: Vector2 = a.b
			var ab := pb - pa
			var t := clampf((p - pa).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			if (pa + ab * t).distance_to(p) < float(a.w) * 0.5 + 0.9:
				best = maxf(best, float(a.y))
	if L.is_water(p.x, p.y):
		return best
	return maxf(best, L.ground_height(p.x, p.y))
