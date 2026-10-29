extends RefCounted
## The settlement's public-address system: a pair of horn loudspeakers on a short mast above a street pole, one
## roughly every 85 m across the map. The announcer (audio/announcer.gd) speaks through the horns nearest the
## listener before every change of the artificial sun. Uses no random numbers, so the rest of the map is unchanged.

const SPACING := 85.0

var mb = null
var sink = null
var stats := {"speakers": 0}


func _init(map_builder) -> void:
	mb = map_builder
	sink = map_builder.sink


func build() -> void:
	var picked: Array = []
	var grid := {}   # 100 m cell -> [index into picked]
	for pt in mb.pole_tops:
		var top: Vector3 = pt[0]
		var c := Vector2i(floori(top.x / SPACING), floori(top.z / SPACING))
		var ok := true
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for i in grid.get(c + Vector2i(dx, dz), []):
					var q: Vector3 = picked[i].pos
					if Vector2(q.x - top.x, q.z - top.z).length() < SPACING:
						ok = false
		if not ok:
			continue
		var along: Vector2 = pt[1]
		var mouth := _horns(top, along)
		grid[c] = grid.get(c, []) + [picked.size()]
		picked.append({"pos": mouth, "along": along})
	mb.pa_speakers = picked
	stats.speakers = picked.size()


func _horns(top: Vector3, along: Vector2) -> Vector3:
	## A steel mast with two horns facing up and down the street, tilted down a little, and their driver cans.
	var mast_h := 0.75
	sink.cylinder(top, Vector3.UP, mast_h, 0.035, "metal_paint", {"sides": 6, "tint": Color(0.42, 0.44, 0.4), "paint": 0.7, "layer": "mid"})
	var hub := top + Vector3(0, mast_h - 0.08, 0)
	var a3 := Vector3(along.x, 0, along.y).normalized()
	sink.box(Transform3D(Basis(Vector3.UP, atan2(-a3.z, a3.x)), hub), Vector3(0.36, 0.06, 0.06), "metal_paint", {"collide": false, "tint": Color(0.4, 0.42, 0.38), "paint": 0.7, "layer": "mid"})
	for s in [-1.0, 1.0]:
		var dir = (a3 * s + Vector3.DOWN * 0.22).normalized()
		var base = hub + a3 * s * 0.16
		# Driver can at the back, then the horn flaring out in three steps.
		sink.cylinder(base - dir * 0.02, dir, 0.12, 0.055, "metal_paint", {"sides": 8, "tint": Color(0.2, 0.21, 0.2), "paint": 0.8, "layer": "mid"})
		var r := 0.06
		var p = base + dir * 0.1
		for k in 3:
			var l := 0.11 + k * 0.03
			r += 0.045 + k * 0.025
			sink.cylinder(p, dir, l, r, "metal_paint", {"sides": 10, "tint": Color(0.66, 0.68, 0.62), "paint": 0.75, "layer": "mid"})
			p += dir * l
	return hub
