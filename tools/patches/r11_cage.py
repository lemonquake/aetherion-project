"""r11: Lawless Sub's edge becomes a steel cage: 7.5 m steel wall on posts with an inward-leaning mesh overhang and
wire, a hazard band, sealed gates where roads meet it, bar grilles over the water outlets, and big loudspeaker
stacks (a cabinet and two horns) every ~64 m plus a horn tower in each corner. The speakers are the map's PA
(mb.pa_speakers), so the announcer speaks from the cage. The old street-pole horns are not built on this map.
    python -I tools/patches/r11_cage.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

p = Patch('game/src/world/maps/lawless_sub/sub_works.gd')
p.rep('''## the map's edge: a perimeter wall with the city beyond it.''',
      '''## the map's edge: a steel cage wall (r11) with big loudspeakers on it, and the city beyond.''')
start = p.s.index('func _perimeter() -> void:')
end = p.s.index('func _backdrop() -> void:')
p.s = p.s[:start] + '''const CAGE_H := 7.5            # steel wall height above the ground
const CAGE_BAY := 4.0
const CAGE_LEAN := 3.2          # mesh overhang length, leaning in over the arena
const SPEAKER_STEP := 64.0
const STEEL := Color(0.3, 0.34, 0.35)
const STEEL_DARK := Color(0.16, 0.17, 0.17)
const HAZARD := Color(0.86, 0.68, 0.12)


func _perimeter() -> void:
	## (r11) The cage: steel wall panels between I-section posts, a mesh overhang leaning in at the top with wire
	## along its edge, a hazard band, sealed double gates where a road meets the wall, bar grilles where water leaves.
	## Big speaker stacks on the posts every SPEAKER_STEP and a horn tower in each corner (mb.pa_speakers).
	var e: float = L.edge
	var corners := [Vector2(-e, -e), Vector2(e, -e), Vector2(e, e), Vector2(-e, e)]
	var speakers: Array = []
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var len := a.distance_to(b)
		var d := (b - a) / len
		var inward := Vector2(-d.y, d.x)   # corners run clockwise in x/z: the left normal points inside
		if inward.dot(-a - b) < 0.0:
			inward = -inward
		var basis := Basis(Vector3.UP, atan2(-d.y, d.x))
		var n := int(round(len / CAGE_BAY))
		var bay := len / n
		var road_run := 0
		for k in n:
			var m := a + d * (bay * (k + 0.5))
			var water: bool = L.is_water(m.x, m.y) or L.is_water(m.x + inward.x * 3.0, m.y + inward.y * 3.0)
			var g: float = L.ground_height(m.x, m.y)
			if water:
				g = minf(L.terrain_height(m.x, m.y), g)
			var road: bool = L.reserved_at(m.x, m.y) == 1
			var base := g - 0.4
			var top := L.ground_height(m.x, m.y) + CAGE_H
			if water:
				# Bars from the bed to the top: the water goes, nobody does.
				for bk in 6:
					var bp := m + d * (bay * ((bk + 0.5) / 6.0 - 0.5))
					sink.box(Transform3D(basis, Vector3(bp.x, (base + top) * 0.5, bp.y)), Vector3(0.09, top - base, 0.09), "metal_rust",
						{"dirt": 0.6, "phys": "steel", "what": "cage_bars"})
				sink.box(Transform3D(basis, Vector3(m.x, top - 0.6, m.y)), Vector3(bay, 0.3, 0.16), "metal_paint",
					{"tint": STEEL_DARK, "paint": 0.8, "dirt": 0.6, "phys": "steel"})
				sink.box(Transform3D(basis, Vector3(m.x, L.LAND_Y + 0.4, m.y)), Vector3(bay, 0.3, 0.16), "metal_paint",
					{"tint": STEEL_DARK, "paint": 0.8, "dirt": 0.6, "phys": "steel"})
			else:
				sink.box(Transform3D(basis, Vector3(m.x, (base + top) * 0.5, m.y)), Vector3(bay + 0.02, top - base, 0.14), "metal_sheet",
					{"dirt": 0.75, "occlude": true, "what": "cage_wall", "tint": STEEL if not road else Color(0.36, 0.33, 0.3), "paint": 0.55, "phys": "steel"})
				var ip := m + inward * 0.09
				# Hazard band and two horizontal rails on the inside face.
				sink.box(Transform3D(basis, Vector3(ip.x, g + 0.75, ip.y)), Vector3(bay, 0.5, 0.03), "metal_paint",
					{"collide": false, "tint": HAZARD, "paint": 0.85, "dirt": 0.7})
				for ry in [2.9, 5.6]:
					sink.box(Transform3D(basis, Vector3(ip.x + inward.x * 0.05, g + ry, ip.y + inward.y * 0.05)), Vector3(bay, 0.18, 0.12), "metal_paint",
						{"collide": false, "tint": STEEL_DARK, "paint": 0.8, "dirt": 0.6})
				if road:
					road_run += 1
				elif road_run > 0:
					_sealed_gate(a + d * (bay * (k - road_run * 0.5)), d, inward, basis, bay * road_run, g)
					road_run = 0
			# Post at the bay's start (and the last one's end): an I-section on the inside.
			var pp := a + d * (bay * k) + inward * 0.22
			sink.box(Transform3D(basis, Vector3(pp.x, (base + top + 0.5) * 0.5, pp.y)), Vector3(0.32, top + 0.5 - base, 0.3), "metal_paint",
				{"tint": STEEL_DARK, "paint": 0.8, "dirt": 0.65, "phys": "steel", "what": "cage_post"})
			# The overhang: mesh leaning in from the top, a strut on every second post, wire along the edge.
			var lean := 0.62   # radians from vertical
			var up_in := Vector3(inward.x * sin(lean), cos(lean), inward.y * sin(lean))
			var c0 := Vector3(m.x, top, m.y) + up_in * (CAGE_LEAN * 0.5)
			var pb := Basis(Vector3(d.x, 0, d.y), up_in, Vector3(d.x, 0, d.y).cross(up_in).normalized())
			sink.box(Transform3D(pb, c0), Vector3(bay, CAGE_LEAN, 0.05), "grate", {"dirt": 0.5, "phys": "steel", "what": "cage_mesh"})
			if k % 2 == 0:
				var sp := Vector3(pp.x, top, pp.y) + up_in * (CAGE_LEAN * 0.5)
				sink.box(Transform3D(pb, sp + Vector3(inward.x, 0, inward.y) * -0.04), Vector3(0.12, CAGE_LEAN + 0.3, 0.14), "metal_paint",
					{"tint": STEEL_DARK, "paint": 0.8, "dirt": 0.6, "collide": false})
			var tip := Vector3(m.x, top, m.y) + up_in * CAGE_LEAN
			sink.cylinder(tip - Vector3(d.x, 0, d.y) * (bay * 0.5), Vector3(d.x, 0, d.y), bay, 0.22, "grate",
				{"sides": 6, "collide": false, "dirt": 0.4, "what": "cage_wire"})
		if road_run > 0:
			_sealed_gate(a + d * (bay * (n - road_run * 0.5)), d, inward, basis, bay * road_run, L.ground_height(b.x, b.y))
		# Speaker stacks along this side, clear of the corners.
		var nsp := int(floor((len - 40.0) / SPEAKER_STEP)) + 1
		var off := (len - (nsp - 1) * SPEAKER_STEP) * 0.5
		for s in nsp:
			var q := a + d * (off + s * SPEAKER_STEP)
			for step in 10:
				if not (L.is_water(q.x, q.y) or L.reserved_at(q.x, q.y) == 1 or L.is_water(q.x + inward.x * 4.0, q.y + inward.y * 4.0)):
					break
				q += d * 4.0
			speakers.append(_cage_speaker(q, d, inward))
		stats.panels += n
	for i in 4:
		speakers.append(_corner_tower(corners[i]))
	mb.pa_speakers = speakers
	stats.speakers = speakers.size()


func _sealed_gate(c: Vector2, d: Vector2, inward: Vector2, basis: Basis, width: float, g: float) -> void:
	## Where a road meets the cage: two welded gate leaves (frame, diagonal braces) and a chained bar across them.
	var h := CAGE_H - 0.6
	var ip := c + inward * 0.2
	for s in [-1.0, 1.0]:
		var lc := ip + d * (s * width * 0.25)
		var lw := width * 0.5 - 0.2
		var fr := [[Vector3(0, h - 0.1, 0), Vector3(lw, 0.18, 0.12)], [Vector3(0, 0.3, 0), Vector3(lw, 0.18, 0.12)],
			[Vector3(-lw * 0.5, h * 0.5 + 0.1, 0), Vector3(0.18, h - 0.2, 0.12)], [Vector3(lw * 0.5, h * 0.5 + 0.1, 0), Vector3(0.18, h - 0.2, 0.12)]]
		for f in fr:
			var off: Vector3 = f[0]
			var p3 := Vector3(lc.x, g, lc.y) + Vector3(d.x, 0, d.y) * off.x + Vector3.UP * off.y
			sink.box(Transform3D(basis, p3), f[1], "metal_paint", {"collide": false, "tint": Color(0.5, 0.18, 0.12), "paint": 0.85, "dirt": 0.7})
		var diag := atan2(h - 0.6, lw)
		var db := basis * Basis(Vector3(0, 0, 1), diag * s)
		sink.box(Transform3D(db, Vector3(lc.x, g + h * 0.5, lc.y)), Vector3(sqrt(lw * lw + h * h) - 0.4, 0.16, 0.1), "metal_paint",
			{"collide": false, "tint": Color(0.5, 0.18, 0.12), "paint": 0.85, "dirt": 0.7})
	# The bar and chain across the middle.
	sink.box(Transform3D(basis, Vector3(ip.x, g + 1.4, ip.y) + Vector3(inward.x, 0, inward.y) * 0.12), Vector3(1.6, 0.14, 0.14), "metal_rust",
		{"collide": false, "dirt": 0.5})
	sink.cylinder(Vector3(ip.x, g + 1.4, ip.y) + Vector3(inward.x, 0, inward.y) * 0.22 - Vector3(d.x, 0, d.y) * 0.5, Vector3(d.x, 0, d.y), 1.0, 0.06,
		"metal_rust", {"sides": 6, "collide": false})


func _cage_speaker(q: Vector2, d: Vector2, inward: Vector2) -> Dictionary:
	## A loudspeaker stack on the cage: a black cabinet with a grille on a steel bracket at the top of the wall, two
	## big horns over it, all aimed in and down at the arena. Returns the PA record (the sound comes from the horns).
	var g: float = L.ground_height(q.x, q.y)
	var in3 := Vector3(inward.x, 0, inward.y)
	var along := Vector3(d.x, 0, d.y)
	var aim := (in3 - Vector3.UP * 0.22).normalized()
	var yaw_b := Basis(Vector3.UP, atan2(-d.y, d.x))
	var sgn := 1.0 if inward.dot(Vector2(-d.y, d.x)) > 0.0 else -1.0   # +1: the basis' local z is the inward side
	var tilt := yaw_b * Basis(Vector3(1, 0, 0), 0.22 * sgn)            # face aimed down at the arena
	var top := g + CAGE_H
	# Bracket arms off the wall.
	for s in [-0.5, 0.5]:
		var bp := Vector3(q.x, top - 1.6, q.y) + along * s + in3 * 0.55
		sink.box(Transform3D(yaw_b, bp), Vector3(0.12, 0.12, 1.1), "metal_paint",
			{"tint": STEEL_DARK, "paint": 0.8, "dirt": 0.5, "collide": false})
	# Cabinet and its grille.
	var cab := Vector3(q.x, top - 1.0, q.y) + in3 * 1.05
	sink.box(Transform3D(tilt, cab), Vector3(1.5, 2.3, 0.95), "metal_paint",
		{"tint": Color(0.06, 0.06, 0.065), "paint": 0.9, "dirt": 0.35, "phys": "steel", "what": "speaker"})
	sink.box(Transform3D(tilt, cab + tilt * Vector3(0, 0, 0.49 * sgn)), Vector3(1.32, 2.1, 0.04), "grate",
		{"tint": Color(0.12, 0.12, 0.12), "paint": 0.6, "dirt": 0.3, "collide": false})
	# Two horns on top: driver can, then the flare in three steps.
	var mouth := Vector3.ZERO
	for s in [-0.42, 0.42]:
		var base := cab + Vector3.UP * 1.55 + along * s - in3 * 0.2
		sink.cylinder(base - aim * 0.1, aim, 0.35, 0.16, "metal_paint", {"sides": 10, "tint": Color(0.1, 0.1, 0.1), "paint": 0.9, "collide": false})
		var r := 0.17
		var pcur := base + aim * 0.25
		for k in 3:
			var l := 0.3 + k * 0.08
			r += 0.1 + k * 0.06
			sink.cylinder(pcur, aim, l, r, "metal_paint", {"sides": 12, "tint": Color(0.7, 0.72, 0.68), "paint": 0.8, "dirt": 0.4, "collide": false})
			pcur += aim * l
		mouth += pcur * 0.5
	return {"pos": mouth, "along": d, "kind": "cage"}


func _corner_tower(c: Vector2) -> Dictionary:
	## A lattice mast inside each corner with a ring of four big horns, the tallest thing on the cage.
	var inside := -c.normalized() * 6.0
	var p := c + inside
	var g: float = L.ground_height(p.x, p.y)
	var mast_h := CAGE_H + 6.5
	for dx in [-0.6, 0.6]:
		for dz in [-0.6, 0.6]:
			sink.box(Transform3D(Basis(), Vector3(p.x + dx, g + mast_h * 0.5, p.y + dz)), Vector3(0.16, mast_h, 0.16), "metal_paint",
				{"tint": STEEL_DARK, "paint": 0.8, "dirt": 0.6, "phys": "steel", "what": "speaker_mast"})
	var y := g + 1.5
	while y < mast_h:
		sink.box(Transform3D(Basis(), Vector3(p.x, y, p.y)), Vector3(1.36, 0.08, 1.36), "metal_paint", {"tint": STEEL_DARK, "paint": 0.8, "collide": false, "faces": 12})
		y += 2.4
	var hub := Vector3(p.x, g + mast_h, p.y)
	sink.box(Transform3D(Basis(), hub - Vector3.UP * 0.4), Vector3(1.8, 0.8, 1.8), "metal_paint", {"tint": Color(0.06, 0.06, 0.065), "paint": 0.9, "phys": "steel"})
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var dir := (Vector3(cos(a), 0, sin(a)) - Vector3.UP * 0.25).normalized()
		var r := 0.2
		var pc := hub + dir * 0.5
		for s in 3:
			var l := 0.36 + s * 0.1
			r += 0.12 + s * 0.07
			sink.cylinder(pc, dir, l, r, "metal_paint", {"sides": 12, "tint": Color(0.7, 0.72, 0.68), "paint": 0.8, "dirt": 0.4, "collide": false})
			pc += dir * l
	return {"pos": hub, "along": Vector2(1, 0), "kind": "tower"}


''' + p.s[end:]
p.save()

# The cage's speakers are this map's PA: no street-pole horns on Lawless Sub.
p = Patch('game/src/world/map_builder.gd')
p.rep('''		stats.dress = dr.stats
		PaSystem.new(self).build()
		practical.porch_lights()''', '''		stats.dress = dr.stats
		practical.porch_lights()   # r11: the PA is the cage's speakers (sub_works._perimeter), not pole horns''')
p.save()
print('r11 cage patch done')
