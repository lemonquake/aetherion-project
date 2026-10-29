extends RefCounted
## Lagusan: lanes roofed over from house to house, as in the owner's Sleep warren. Patched corrugated sheets,
## plywood and tarp on timber purlins, a few gaps where the sky (or the sun) gets in, a floor of cement, planks or
## trodden mud, wires and rags hanging from the roof, a bare bulb every several metres (many dead or failing) and
## now and then a candle at a little shrine. It is dark in here at noon: the roof's underside, the floor and the
## house fronts along it are on the Interior render layer, which the sky fill never lights and the sun reaches only
## through the gaps (where shadows are drawn) or not at all (phones).
##
## Also the map's cover mask: covered(p) says whether a point on the ground is under one of these roofs (street
## dressing keeps poles and trees out, and puts its clutter on the interior layers there).

const CELL := 1.0

var mb = null
var L = null
var sink = null
var dyn = null
var rng := RandomNumberGenerator.new()
var _mask := PackedByteArray()
var _n := 0
var _half := 0.0
var stats := {"segments": 0, "metres": 0.0, "lights": 0, "dead": 0, "gaps": 0, "shrines": 0, "walks": 0}


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	sink = mb.sink
	dyn = mb.dyn
	rng.seed = L.rng.seed + 733
	_half = L.HALF
	_n = int(_half * 2.0 / CELL)
	_mask.resize(_n * _n)


func covered(p: Vector2) -> bool:
	var ix := int((p.x + _half) / CELL)
	var iz := int((p.y + _half) / CELL)
	if ix < 0 or iz < 0 or ix >= _n or iz >= _n:
		return false
	return _mask[iz * _n + ix] == 1


func build() -> void:
	for t in mb.tunnels:
		_segment(t)
	print("[lagusan] ", stats)


func _pick(a: Array):
	return a[rng.randi_range(0, a.size() - 1)]


func _mark(a: Vector2, b: Vector2, half_w: float) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * half_w
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * half_w
	for iz in range(maxi(int((lo.y + _half) / CELL), 0), mini(int((hi.y + _half) / CELL) + 1, _n)):
		for ix in range(maxi(int((lo.x + _half) / CELL), 0), mini(int((hi.x + _half) / CELL) + 1, _n)):
			var p := Vector2(-_half + (ix + 0.5) * CELL, -_half + (iz + 0.5) * CELL)
			if L.seg_dist(p, a, b) <= half_w:
				_mask[iz * _n + ix] = 1


func _segment(t: Dictionary) -> void:
	var a: Vector2 = t.a
	var b: Vector2 = t.b
	var len := a.distance_to(b)
	if len < 2.0:
		return
	var walk: bool = t.kind == "walk"
	var w := float(t.w)
	var dir := (b - a) / len
	var side := Vector2(-dir.y, dir.x)
	var d3 := Vector3(dir.x, 0, dir.y)
	var s3 := Vector3(side.x, 0, side.y)
	var basis := Basis(d3, Vector3.UP, s3)   # x along the lane, z across it
	# A walk along the estero has houses on one side only: the roof runs from their fronts out over the walk.
	var c_off := 0.0
	var span := w + 0.12
	if walk:
		var hs: Vector2 = t.get("house_side", side)
		var sgn := 1.0 if hs.dot(side) > 0.0 else -1.0
		c_off = 0.1 * sgn
		span = w + 0.35
	var floor_y := float(t.get("y", NAN))
	var gy_mid: float = floor_y if walk else L.ground_height((a.x + b.x) * 0.5, (a.y + b.y) * 0.5)
	var roof_h := rng.randf_range(2.6, 2.82) if not walk else rng.randf_range(2.35, 2.5)
	var roof_y := gy_mid + roof_h
	if not walk:
		# Follow the lane's rise so the roof never drops low on a slope.
		roof_y = maxf(L.ground_height(a.x, a.y), L.ground_height(b.x, b.y)) + roof_h
	stats.segments += 1
	stats.metres += len
	if walk:
		stats.walks += 1
	_mark(a + side * c_off, b + side * c_off, span * 0.5 + 0.2)
	L.reserve_rect((a + b) * 0.5, Vector2(len * 0.5, w * 0.5), atan2(dir.y, dir.x), 4, 0.0, true)
	var roof_mat: String = _pick(["yero_rust", "yero_rust", "yero_worn", "yero"])
	var floor_mat: String = "planks" if walk else _pick(["cement", "cement", "mud"])
	# ---- roof: sheets laid across the lane, ridges across, each a little off; now and then a missing one
	var x := 0.0
	var last_gap := -10.0
	while x < len:
		var sw := 0.82
		var p := a + dir * (x + sw * 0.5) + side * c_off
		var gap := rng.randf() < 0.07 and x - last_gap > 4.0 and x > 1.5 and x < len - 1.5
		if gap:
			last_gap = x
			stats.gaps += 1
		else:
			var m := roof_mat
			var r := rng.randf()
			if r < 0.12:
				m = "plywood"
			elif r < 0.2:
				m = "tarp"
			elif r < 0.3:
				m = _pick(["yero_rust", "yero_worn", "yero_paint"])
			var sag := rng.randf_range(-0.04, 0.06)
			var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.03, 0.03)) * Basis(Vector3.FORWARD, rng.randf_range(-0.02, 0.02))
			var xf := Transform3D(basis * tilt, Vector3(p.x, roof_y + sag, p.y))
			if m in ["plywood", "tarp"]:
				sink.box(xf, Vector3(sw, 0.02, span + rng.randf_range(-0.1, 0.1)), m, {"dirt": 0.9, "collide": false, "faces": 4 | 8, "inner_faces": 8,
					"tint": mb.mats.PAINTS[rng.randi_range(0, mb.mats.PAINTS.size() - 1)], "paint": 0.5 if m == "tarp" else 0.0})
			else:
				sink.corrugated(xf, span + rng.randf_range(-0.05, 0.12), sw, m, {"dirt": 0.85, "collide": false, "inner_faces": 8,
					"tint": mb.mats.PAINTS[rng.randi_range(0, mb.mats.PAINTS.size() - 1)], "paint": 0.6 if m == "yero_paint" else 0.0})
			# Weights against the wind: a tyre, a block, a stone.
			if rng.randf() < 0.08:
				var wn: String = _pick(["old_tyre", "hollow_block", "stone"])
				dyn.add_static_prop(wn, dyn.seat(wn, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, roof_y + 0.02, p.y) + s3 * rng.randf_range(-span * 0.3, span * 0.3))))
		x += sw - 0.06
	# Walkable from above (roof runners): one thin collider over the lane, with a hole where a sheet is missing is
	# not worth it - the gaps are smaller than a person.
	sink.col_box(Transform3D(basis, Vector3((a.x + b.x) * 0.5, roof_y - 0.01, (a.y + b.y) * 0.5) + s3 * c_off), Vector3(len, 0.04, span), "sheet_metal")
	# Purlins along both edges and joists across, seen from below.
	for e in [-1.0, 1.0]:
		var ep = (a + b) * 0.5 + side * (c_off + e * (span * 0.5 - 0.08))
		sink.box(Transform3D(basis, Vector3(ep.x, roof_y - 0.07, ep.y)), Vector3(len, 0.08, 0.07), "timber", {"dirt": 1.0, "collide": false, "layer": "int"})
	var j := 0.8
	while j < len - 0.4:
		var jp := a + dir * j + side * c_off
		sink.box(Transform3D(basis, Vector3(jp.x, roof_y - 0.14, jp.y)), Vector3(0.06, 0.07, span - 0.1), "timber", {"dirt": 1.0, "collide": false, "layer": "int"})
		j += rng.randf_range(1.4, 2.1)
	# ---- floor: slabs or planks over the dirt, on the interior layer (the terrain under it would take the sky fill)
	if not walk:
		var k := 0.0
		while k < len:
			var seg := minf(1.8, len - k)
			var fp := a + dir * (k + seg * 0.5)
			if not L.is_water(fp.x, fp.y):
				var fy: float = L.ground_height(fp.x, fp.y)
				sink.box(Transform3D(basis * Basis(Vector3.UP, rng.randf_range(-0.01, 0.01)), Vector3(fp.x, fy - 0.005, fp.y)), Vector3(seg + 0.04, 0.06, w + 0.3), floor_mat,
					{"dirt": 1.0, "layer": "int", "faces": 4 | 1 | 2, "phys": "concrete" if floor_mat != "mud" else "dirt"})
			k += seg
	else:
		# Under the arcade the boardwalk itself is the floor; a dark underside to the roof is enough.
		pass
	# ---- hanging life: wires along the roof, rags and bags, a bulb every several metres
	var fy0 = gy_mid if walk else L.ground_height(a.x, a.y)
	for wi in rng.randi_range(2, 4):
		var off := rng.randf_range(-span * 0.4, span * 0.4)
		var sag := rng.randf_range(0.08, 0.3)
		var prev := Vector3(a.x, roof_y - 0.2, a.y) + s3 * (off + c_off)
		var n := maxi(int(len / 2.5), 1)
		for i in range(1, n + 1):
			var q := a + dir * (len * i / n)
			var cur := Vector3(q.x, roof_y - 0.2 - sag * (0.5 + 0.5 * sin(i * 2.1)), q.y) + s3 * (off + c_off)
			_segment_box(prev, cur, 0.012)
			prev = cur
	var h := rng.randf_range(1.0, 3.0)
	while h < len - 0.5:
		var q2 := a + dir * h + side * (c_off + rng.randf_range(-span * 0.35, span * 0.35))
		var ln := rng.randf_range(0.25, 0.6)
		var col: Color = mb.mats.PAINTS[rng.randi_range(0, mb.mats.PAINTS.size() - 1)] * Color(0.7, 0.7, 0.7)
		sink.box(Transform3D(basis * Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)), Vector3(q2.x, roof_y - 0.16 - ln * 0.5, q2.y)), Vector3(rng.randf_range(0.15, 0.4), ln, 0.012),
			"cloth", {"collide": false, "faces": 16 | 32, "tint": col, "paint": 0.8, "dirt": 0.6, "layer": "int"})
		h += rng.randf_range(1.2, 3.5)
	var lpos := rng.randf_range(1.5, 4.0)
	var lit_any := false
	while lpos < len - 1.0:
		var q3 := a + dir * lpos + side * (c_off + rng.randf_range(-0.2, 0.2))
		var drop := rng.randf_range(0.3, 0.55)
		var by := roof_y - 0.12 - drop
		_segment_box(Vector3(q3.x, roof_y - 0.1, q3.y), Vector3(q3.x, by + 0.05, q3.y), 0.01)
		# A few are dead; the first of every lane always burns, so there is always a little light to go by.
		var dead := rng.randf() < 0.22 and lit_any
		lit_any = lit_any or not dead
		var r2 := rng.randf()
		var fault := "" if r2 < 0.45 else ("flicker" if r2 < 0.7 else ("dying" if r2 < 0.88 else "sag"))
		var col2: Color = [Color(1.0, 0.7, 0.4), Color(1.0, 0.64, 0.34), Color(0.86, 0.93, 1.0)][rng.randi_range(0, 2)]
		dyn.add_light({"pos": Vector3(q3.x, by, q3.y), "kind": "bulb", "color": col2, "energy": rng.randf_range(0.45, 0.85),
			"range": rng.randf_range(4.0, 6.0), "fault": fault, "dead": dead, "no_shadow": true})
		stats.lights += 1
		if dead:
			stats.dead += 1
		lpos += rng.randf_range(6.5, 11.0)
	# ---- a little shrine on a wall: a shelf, a red cloth, a statue, candles
	if not walk and rng.randf() < 0.22:
		var sp := a + dir * rng.randf_range(len * 0.25, len * 0.75)
		var e := 1.0 if rng.randf() < 0.5 else -1.0
		var wp := sp + side * e * (w * 0.5 - 0.16)
		var sy: float = L.ground_height(sp.x, sp.y) + 1.35
		var sb := Basis(d3, Vector3.UP, s3 * e)
		sink.box(Transform3D(sb, Vector3(wp.x, sy, wp.y)), Vector3(0.5, 0.03, 0.24), "planks_dark", {"collide": false, "layer": "int"})
		sink.box(Transform3D(sb, Vector3(wp.x, sy + 0.02, wp.y)), Vector3(0.52, 0.01, 0.26), "cloth", {"collide": false, "layer": "int", "tint": Color(0.55, 0.06, 0.05), "paint": 1.0})
		sink.box(Transform3D(sb, Vector3(wp.x, sy + 0.14, wp.y) - s3 * e * 0.02), Vector3(0.08, 0.22, 0.07), "plaster_white", {"collide": false, "layer": "int"})
		for ci in 2:
			var cp := Vector3(wp.x, sy + 0.07, wp.y) + d3 * (0.15 if ci == 0 else -0.16) - s3 * e * 0.04
			sink.box(Transform3D(sb, cp), Vector3(0.025, 0.08, 0.025), "plaster_white", {"collide": false, "layer": "int"})
			if ci == 0 or rng.randf() < 0.5:
				dyn.add_light({"pos": cp + Vector3.UP * 0.06, "kind": "candle", "color": Color(1.0, 0.58, 0.26), "energy": 0.35, "range": 3.2, "fault": "candle", "no_shadow": true})
				stats.lights += 1
		stats.shrines += 1
	# ---- tarp and sack strips hanging at both mouths: you see into it only once you are close
	for end in [a, b]:
		for i in rng.randi_range(1, 3):
			var mp: Vector2 = end + side * (c_off + rng.randf_range(-span * 0.4, span * 0.4))
			var ln2 := rng.randf_range(0.35, 0.8)
			sink.box(Transform3D(basis, Vector3(mp.x, roof_y - 0.05 - ln2 * 0.5, mp.y)), Vector3(0.012, ln2, rng.randf_range(0.2, 0.5)),
				"cloth", {"collide": false, "faces": 1 | 2, "dirt": 0.8, "layer": "mid",
				"tint": mb.mats.PAINTS[rng.randi_range(0, mb.mats.PAINTS.size() - 1)], "paint": 0.6})


func _segment_box(a: Vector3, b: Vector3, thick: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var z := d / l
	var x := z.cross(Vector3.UP)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := x.cross(z).normalized()
	sink.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(thick, thick, l), "wire", {"collide": false, "faces": 1 | 2 | 4 | 8, "layer": "int"})
