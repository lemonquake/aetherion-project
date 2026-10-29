extends RefCounted
## Lawless Sub's paved surfaces: carriageways (clipped at junctions so no two roads overlap), sidewalks with curbs,
## the avenue's median, painted markings (lane dashes, edge and centre lines, zebra crossings, stop lines, parking
## stalls, OUT / IN lettering) and the parking lots. Markings are one decal material (a worn white texture tinted
## per vertex), so every line, stripe and stall in a chunk is a single draw.

const PAINT := "decal:res://src/world/maps/lawless_sub/paint.png"
const WHITE := Color(0.93, 0.93, 0.9, 0.92)
const YELLOW := Color(0.96, 0.74, 0.18, 0.92)
const STEP := 6.0

var mb = null
var L = null
var sink = null
var stats := {"road_quads": 0, "walk_boxes": 0, "paint": 0, "stalls": 0, "lots": 0}


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	sink = mb.sink


func build() -> void:
	for i in L.roads.size():
		_carriageway(i)
		_sidewalks(i)
		_median(i)
		_markings(i)
	_intersection()
	for p in L.parking:
		_parking(p)


# ------------------------------------------------------------------ geometry of the road network

func _higher(i: int, j: int) -> bool:
	## True when road j wins the junction box over road i.
	var a: Dictionary = L.roads[i]
	var b: Dictionary = L.roads[j]
	return int(b.prio) < int(a.prio) or (int(b.prio) == int(a.prio) and j < i)


func _crosses(rd: Dictionary, ro: Dictionary, across: float) -> bool:
	## Road ro is perpendicular to rd and reaches the line `across` (a coordinate across rd).
	return int(ro.axis) != int(rd.axis) and across >= float(ro.lo) - 0.01 and across <= float(ro.hi) + 0.01 \
		and float(ro.c) >= float(rd.lo) - float(ro.w) and float(ro.c) <= float(rd.hi) + float(ro.w)


func _subtract(iv: Array, a: float, b: float) -> Array:
	var out := []
	for s in iv:
		var s0: float = s[0]
		var s1: float = s[1]
		if b <= s0 or a >= s1:
			out.append(s)
			continue
		if a > s0:
			out.append([s0, a])
		if b < s1:
			out.append([b, s1])
	return out


func _base_iv(rd: Dictionary) -> Array:
	return [[maxf(float(rd.lo), -L.HALF), minf(float(rd.hi), L.HALF)]]


func _bridge_cut(rd: Dictionary, iv: Array, across0: float, across1: float) -> Array:
	for r in L.bridge_rects:
		var rr: Rect2 = r
		var a0 := rr.position.y if int(rd.axis) == 0 else rr.position.x
		var a1 := rr.end.y if int(rd.axis) == 0 else rr.end.x
		if across1 <= a0 or across0 >= a1:
			continue
		var s0 := rr.position.x if int(rd.axis) == 0 else rr.position.y
		var s1 := rr.end.x if int(rd.axis) == 0 else rr.end.y
		iv = _subtract(iv, s0, s1)
	return iv


func _pt(rd: Dictionary, s: float, o: float) -> Vector2:
	## The point at distance s along road rd's axis and offset o across it (o > 0: +z for an E-W road, +x for N-S).
	return Vector2(s, float(rd.c) + o) if int(rd.axis) == 0 else Vector2(float(rd.c) + o, s)


func _y(p: Vector2) -> float:
	return L.ground_height(p.x, p.y)


# ------------------------------------------------------------------ carriageway

func _carriageway(i: int) -> void:
	var rd: Dictionary = L.roads[i]
	var hw := float(rd.w) * 0.5
	var iv := _base_iv(rd)
	for j in L.roads.size():
		if j == i or not _higher(i, j):
			continue
		var ro: Dictionary = L.roads[j]
		if _crosses(rd, ro, float(rd.c)):
			iv = _subtract(iv, float(ro.c) - float(ro.w) * 0.5, float(ro.c) + float(ro.w) * 0.5)
	iv = _bridge_cut(rd, iv, float(rd.c) - hw, float(rd.c) + hw)
	var mat := str(rd.mat)
	for s in iv:
		var s0: float = s[0]
		var s1: float = s[1]
		var n := maxi(int(ceil((s1 - s0) / STEP)), 1)
		for k in n:
			var a := s0 + (s1 - s0) * k / n
			var b := s0 + (s1 - s0) * (k + 1) / n
			var p0 := _pt(rd, a, -hw)
			var p1 := _pt(rd, b, -hw)
			var p2 := _pt(rd, b, hw)
			var p3 := _pt(rd, a, hw)
			var top: float = L.ROAD_TOP
			sink.quad(Vector3(p0.x, _y(p0) + top, p0.y), Vector3(p1.x, _y(p1) + top, p1.y), Vector3(p2.x, _y(p2) + top, p2.y), Vector3(p3.x, _y(p3) + top, p3.y),
				mat, {"collide": true, "phys": "concrete", "dirt": 0.25, "facing": Vector3.UP, "what": "road"})
			stats.road_quads += 1
			if float(rd.sidewalk) <= 0.0:
				# No curb: a slab edge so the road reads as poured over the ground.
				for side in [-1.0, 1.0]:
					var e0 := _pt(rd, a, hw * side)
					var e1 := _pt(rd, b, hw * side)
					var nrm := Vector3(0, 0, side) if int(rd.axis) == 0 else Vector3(side, 0, 0)
					sink.quad(Vector3(e0.x, _y(e0) - 0.1, e0.y), Vector3(e1.x, _y(e1) - 0.1, e1.y), Vector3(e1.x, _y(e1) + top, e1.y), Vector3(e0.x, _y(e0) + top, e0.y),
						"concrete_dirty", {"dirt": 0.7, "facing": nrm})


# ------------------------------------------------------------------ sidewalks

func _sidewalks(i: int) -> void:
	var rd: Dictionary = L.roads[i]
	var sw := float(rd.sidewalk)
	if sw <= 0.0:
		return
	var hw := float(rd.w) * 0.5
	for side in [-1.0, 1.0]:
		var o0 := hw if side > 0 else -hw - sw
		var o1 := hw + sw if side > 0 else -hw
		var mid := float(rd.c) + (o0 + o1) * 0.5
		var iv := _base_iv(rd)
		for j in L.roads.size():
			if j == i:
				continue
			var ro: Dictionary = L.roads[j]
			if not (_crosses(rd, ro, float(rd.c) + o0) or _crosses(rd, ro, float(rd.c) + o1) or _crosses(rd, ro, mid)):
				continue
			var cut := float(ro.w) * 0.5
			if _higher(i, j):
				cut += float(ro.sidewalk)
			iv = _subtract(iv, float(ro.c) - cut, float(ro.c) + cut)
		iv = _bridge_cut(rd, iv, float(rd.c) + o0, float(rd.c) + o1)
		for s in iv:
			var s0: float = s[0]
			var s1: float = s[1]
			if s1 - s0 < 0.3:
				continue
			# Drop the end of the footway to the crossing instead of ending every sidewalk at
			# a vertical kerb. The top and collision are the same inclined quad.
			var ramp_len := minf(1.6, (s1 - s0) * 0.22)
			if s0 > -L.edge + 2.0 and s0 < L.edge - 2.0:
				_curb_ramp(rd, s0, s0 + ramp_len, o0, o1, true)
				s0 += ramp_len
			if s1 > -L.edge + 2.0 and s1 < L.edge - 2.0:
				_curb_ramp(rd, s1 - ramp_len, s1, o0, o1, false)
				s1 -= ramp_len
			var n := maxi(int(ceil((s1 - s0) / STEP)), 1)
			for k in n:
				var a := s0 + (s1 - s0) * k / n
				var b := s0 + (s1 - s0) * (k + 1) / n
				var c2 := _pt(rd, (a + b) * 0.5, (o0 + o1) * 0.5)
				var g := minf(_y(_pt(rd, a, (o0 + o1) * 0.5)), _y(_pt(rd, b, (o0 + o1) * 0.5)))
				var gt := maxf(_y(_pt(rd, a, (o0 + o1) * 0.5)), _y(_pt(rd, b, (o0 + o1) * 0.5)))
				var top: float = gt + L.WALK_TOP
				var bot := g - 0.2
				var size := Vector3(b - a, top - bot, sw) if int(rd.axis) == 0 else Vector3(sw, top - bot, b - a)
				sink.box(Transform3D(Basis(), Vector3(c2.x, (top + bot) * 0.5, c2.y)), size, "sidewalk",
					{"faces": 55, "dirt": 0.35, "phys": "concrete", "what": "sidewalk", "uv_off": Vector2(c2.x * 0.13, c2.y * 0.13)})
				stats.walk_boxes += 1


func _curb_ramp(rd: Dictionary, a: float, b: float, o0: float, o1: float, low_start: bool) -> void:
	var p0 := _pt(rd, a, o0)
	var p1 := _pt(rd, b, o0)
	var p2 := _pt(rd, b, o1)
	var p3 := _pt(rd, a, o1)
	var ha: float = L.ROAD_TOP if low_start else L.WALK_TOP
	var hb: float = L.WALK_TOP if low_start else L.ROAD_TOP
	var v0 := Vector3(p0.x, _y(p0) + ha, p0.y)
	var v1 := Vector3(p1.x, _y(p1) + hb, p1.y)
	var v2 := Vector3(p2.x, _y(p2) + hb, p2.y)
	var v3 := Vector3(p3.x, _y(p3) + ha, p3.y)
	sink.quad(v0, v1, v2, v3, "sidewalk", {"facing": Vector3.UP, "collide": true,
		"phys": "concrete", "dirt": 0.4, "what": "curb_ramp"})
	for edge in [[v0, v1], [v2, v3]]:
		var va: Vector3 = edge[0]
		var vb: Vector3 = edge[1]
		sink.quad(va, vb, vb - Vector3.UP * 0.25, va - Vector3.UP * 0.25, "concrete",
			{"dirt": 0.55, "double": true})
	# A yellow tactile strip on the high end reads at gameplay distance and follows the ramp.
	var s := b - (b - a) * 0.25 if low_start else a + (b - a) * 0.25
	var c := _pt(rd, s, (o0 + o1) * 0.5)
	var height := lerpf(ha, hb, (s - a) / (b - a))
	var across := Vector3(0, 0, 1) if int(rd.axis) == 0 else Vector3(1, 0, 0)
	var slope := Vector3(1, (hb - ha) / (b - a), 0) if int(rd.axis) == 0 else Vector3(0, (hb - ha) / (b - a), 1)
	if across.cross(slope).y < 0.0:
		across = -across
	sink.atlas_quad(Vector3(c.x, _y(c) + height + 0.007, c.y), across, slope,
		absf(o1 - o0) - 0.12, 0.32, Rect2(0, 0, 1, 1), PAINT, {"layer": "mid", "tint": Color(0.92, 0.72, 0.28, 0.9)})
	stats.curb_ramps = int(stats.get("curb_ramps", 0)) + 1


# ------------------------------------------------------------------ median

func _median(i: int) -> void:
	var rd: Dictionary = L.roads[i]
	var mw := float(rd.median)
	if mw <= 0.0:
		return
	var iv := _base_iv(rd)
	for j in L.roads.size():
		if j == i:
			continue
		var ro: Dictionary = L.roads[j]
		if _crosses(rd, ro, float(rd.c)):
			var cut := float(ro.w) * 0.5 + float(ro.sidewalk) + 2.5
			iv = _subtract(iv, float(ro.c) - cut, float(ro.c) + cut)
	for s in iv:
		var s0: float = s[0]
		var s1: float = s[1]
		var n := maxi(int(ceil((s1 - s0) / STEP)), 1)
		for k in n:
			var a := s0 + (s1 - s0) * k / n
			var b := s0 + (s1 - s0) * (k + 1) / n
			var c2 := _pt(rd, (a + b) * 0.5, 0.0)
			var g := _y(c2)
			var top: float = g + L.ROAD_TOP + 0.16
			var bot := g
			var size := Vector3(b - a, top - bot, mw) if int(rd.axis) == 0 else Vector3(mw, top - bot, b - a)
			sink.box(Transform3D(Basis(), Vector3(c2.x, (top + bot) * 0.5, c2.y)), size, "concrete",
				{"faces": 55, "dirt": 0.5, "tint": Color(0.95, 0.85, 0.35), "paint": 0.35, "phys": "concrete", "what": "median"})
		# Rounded-off noses: a yellow stripe painted on each end.
		for e in [s0, s1]:
			if absf(e) < L.HALF - 1.0:
				_paint_line(rd, e - 0.2, e + 0.2, 0.0, mw, YELLOW, 0.17)


# ------------------------------------------------------------------ markings

func _paint(c: Vector2, y: float, along: Vector2, length: float, width: float, col: Color) -> void:
	## A painted strip lying on the surface at height y: `length` along `along`, `width` across.
	var up := Vector3(along.x, 0, along.y).normalized()
	var right := up.cross(Vector3.UP)
	sink.atlas_quad(Vector3(c.x, y, c.y), right, up, width, length, Rect2(0, 0, 1, 1), PAINT, {"layer": "mid", "tint": col})
	stats.paint += 1


func _paint_line(rd: Dictionary, a: float, b: float, o: float, width: float, col: Color, lift: float = 0.012) -> void:
	## A strip along road rd from a to b at offset o (pieces of at most STEP so it follows the ground).
	var n := maxi(int(ceil((b - a) / STEP)), 1)
	var along := Vector2(1, 0) if int(rd.axis) == 0 else Vector2(0, 1)
	for k in n:
		var s0 := a + (b - a) * k / n
		var s1 := a + (b - a) * (k + 1) / n
		var c := _pt(rd, (s0 + s1) * 0.5, o)
		_paint(c, _y(c) + L.ROAD_TOP + lift, along, s1 - s0, width, col)


func _paint_across(rd: Dictionary, s: float, o0: float, o1: float, depth: float, col: Color) -> void:
	## A strip across road rd at distance s (a stop line), from offset o0 to o1, `depth` thick along the road.
	var c := _pt(rd, s, (o0 + o1) * 0.5)
	var across := Vector2(0, 1) if int(rd.axis) == 0 else Vector2(1, 0)
	_paint(c, _y(c) + L.ROAD_TOP + 0.013, across, absf(o1 - o0), depth, col)


func _marking_iv(i: int) -> Array:
	## Where road i's lines run: everywhere but junctions, stopping short of crossings and stop lines.
	var rd: Dictionary = L.roads[i]
	var iv := _base_iv(rd)
	for j in L.roads.size():
		if j == i:
			continue
		var ro: Dictionary = L.roads[j]
		if _crosses(rd, ro, float(rd.c) - float(rd.w) * 0.5) or _crosses(rd, ro, float(rd.c) + float(rd.w) * 0.5) or _crosses(rd, ro, float(rd.c)):
			var cut := float(ro.w) * 0.5 + (float(ro.sidewalk) + 3.0 if int(ro.prio) <= 1 and int(rd.prio) <= 1 else 0.6)
			iv = _subtract(iv, float(ro.c) - cut, float(ro.c) + cut)
	return iv


func _markings(i: int) -> void:
	var rd: Dictionary = L.roads[i]
	var lanes := int(rd.lanes)
	if lanes <= 0:
		return
	var hw := float(rd.w) * 0.5
	var mw := float(rd.median) * 0.5
	var iv := _marking_iv(i)
	var lane_w := (hw - mw - 0.6) / lanes
	for s in iv:
		var s0: float = s[0]
		var s1: float = s[1]
		for side in [-1.0, 1.0]:
			# Edge line by the curb.
			_paint_line(rd, s0, s1, side * (hw - 0.45), 0.15, WHITE)
			if mw > 0.0:
				_paint_line(rd, s0, s1, side * (mw + 0.2), 0.12, YELLOW)
			# Lane dashes: 3 m paint, 6 m gap, phased from the map edge so both ends of a junction line up.
			for k in range(1, lanes):
				var o = side * (mw + 0.15 + lane_w * k)
				var t := ceilf(s0 / 9.0) * 9.0
				while t + 3.0 <= s1:
					_paint_line(rd, t, t + 3.0, o, 0.13, WHITE)
					t += 9.0
		if mw <= 0.0:
			if lanes >= 2:
				# Double yellow centre line.
				_paint_line(rd, s0, s1, -0.16, 0.11, YELLOW)
				_paint_line(rd, s0, s1, 0.16, 0.11, YELLOW)
			else:
				var t2 := ceilf(s0 / 8.0) * 8.0
				while t2 + 3.0 <= s1:
					_paint_line(rd, t2, t2 + 3.0, 0.0, 0.12, YELLOW)
					t2 += 8.0


func _intersection() -> void:
	## The main junction (avenue x boulevard): zebra crossings on all four arms, stop lines on the lanes coming in.
	var av: Dictionary = {}
	var bv: Dictionary = {}
	for rd in L.roads:
		if int(rd.prio) == 0:
			av = rd
		elif int(rd.prio) == 1:
			bv = rd
	if av.is_empty() or bv.is_empty():
		return
	var ahw := float(av.w) * 0.5
	var bhw := float(bv.w) * 0.5
	var cx := float(av.c)
	var cz := float(bv.c)
	# Arms of the avenue (N and S): stripes run along the avenue, across its whole width (gap at the median).
	for sgn in [-1.0, 1.0]:
		var z0: float = cz + sgn * (bhw + 0.6)
		var z1: float = cz + sgn * (bhw + 4.0)
		var x := cx - ahw + 0.5
		while x < cx + ahw - 0.3:
			if absf(x - cx) > float(av.median) * 0.5 + 0.3:
				var c := Vector2(x, (z0 + z1) * 0.5)
				_paint(c, _y(c) + L.ROAD_TOP + 0.014, Vector2(0, 1), absf(z1 - z0), 0.5, WHITE)
				stats.zebra = int(stats.get("zebra", 0)) + 1
			x += 1.0
		# Stop line on the lanes coming in (drive on the right: southbound use the west half).
		var zs: float = cz + sgn * (bhw + 5.0)
		if sgn < 0.0:
			_paint_across(av, zs, -ahw + 0.3, -float(av.median) * 0.5 - 0.2, 0.45, WHITE)
		else:
			_paint_across(av, zs, float(av.median) * 0.5 + 0.2, ahw - 0.3, 0.45, WHITE)
	# Arms of the boulevard (W and E).
	for sgn in [-1.0, 1.0]:
		var x0: float = cx + sgn * (ahw + 0.6)
		var x1: float = cx + sgn * (ahw + 4.0)
		var z := cz - bhw + 0.5
		while z < cz + bhw - 0.3:
			var c2 := Vector2((x0 + x1) * 0.5, z)
			_paint(c2, _y(c2) + L.ROAD_TOP + 0.014, Vector2(1, 0), absf(x1 - x0), 0.5, WHITE)
			stats.zebra = int(stats.get("zebra", 0)) + 1
			z += 1.0
		var xs: float = cx + sgn * (ahw + 5.0)
		if sgn > 0.0:
			_paint_across(bv, xs, -bhw + 0.3, -0.3, 0.45, WHITE)   # westbound, north half
		else:
			_paint_across(bv, xs, 0.3, bhw - 0.3, 0.45, WHITE)     # eastbound, south half


# ------------------------------------------------------------------ parking lots

func _parking(p: Dictionary) -> void:
	var r: Rect2 = p.rect
	var mat := str(p.get("mat", "lot_asphalt"))
	var top: float = L.ROAD_TOP + 0.01
	var nx := maxi(int(ceil(r.size.x / 8.0)), 1)
	var nz := maxi(int(ceil(r.size.y / 8.0)), 1)
	for i in nx:
		for j in nz:
			var a := Vector2(r.position.x + r.size.x * i / nx, r.position.y + r.size.y * j / nz)
			var b := Vector2(r.position.x + r.size.x * (i + 1) / nx, r.position.y + r.size.y * (j + 1) / nz)
			var q0 := Vector3(a.x, _y(a) + top, a.y)
			var q1 := Vector3(b.x, _y(Vector2(b.x, a.y)) + top, a.y)
			var q2 := Vector3(b.x, _y(b) + top, b.y)
			var q3 := Vector3(a.x, _y(Vector2(a.x, b.y)) + top, b.y)
			sink.quad(q0, q1, q2, q3, mat, {"collide": true, "phys": "concrete", "dirt": 0.3, "facing": Vector3.UP, "what": "parking"})
	# A low curb round the lot.
	for e in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end], [r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		var a2: Vector2 = e[0]
		var b2: Vector2 = e[1]
		var len := a2.distance_to(b2)
		var dir := (b2 - a2) / len
		var n2 := maxi(int(ceil(len / STEP)), 1)
		for k in n2:
			var m := a2 + dir * (len * (k + 0.5) / n2)
			var g := _y(m)
			var size := Vector3(len / n2, 0.3, 0.2) if absf(dir.x) > 0.5 else Vector3(0.2, 0.3, len / n2)
			sink.box(Transform3D(Basis(), Vector3(m.x, g + 0.03, m.y)), size, "concrete", {"faces": 55, "dirt": 0.5, "what": "curb"})
	stats.lots += 1
	var kind := str(p.get("stalls", "rows"))
	if kind == "rows":
		_stall_rows(r, 2.6, 5.2, 6.6)
	elif kind == "trucks":
		_stall_rows(r, 4.0, 14.0, 9.0)
	if p.has("out"):
		var o: Array = p.out
		_lettering("OUT", Vector2(float(o[0]), float(o[1])), str(o[2]))
	if p.has("in"):
		var o2: Array = p["in"]
		_lettering("IN", Vector2(float(o2[0]), float(o2[1])), str(o2[2]))


func _stall_rows(r: Rect2, sw: float, sd: float, aisle: float) -> void:
	## Double-loaded rows of stalls running east-west: a row facing the aisle, the aisle, two rows back to back...
	var z := r.position.y + 1.2
	var facing := 1.0
	var y_of := func(c: Vector2) -> float: return _y(c) + L.ROAD_TOP + 0.022
	while z + sd <= r.end.y - 0.8:
		var x0 := r.position.x + 1.5
		var x1 := r.end.x - 1.5
		var n := int((x1 - x0) / sw)
		var off := x0 + ((x1 - x0) - n * sw) * 0.5
		for k in n + 1:
			var x := off + k * sw
			var c := Vector2(x, z + sd * 0.5)
			_paint(c, y_of.call(c), Vector2(0, 1), sd, 0.12, WHITE)
		# The line at the head of the stalls (the aisle side stays open).
		var back := z if facing > 0.0 else z + sd
		var cb := Vector2((off + off + n * sw) * 0.5, back)
		_paint(cb, y_of.call(cb), Vector2(1, 0), n * sw, 0.12, WHITE)
		stats.stalls += n
		mb.stall_spots.append({"rect": Rect2(Vector2(off, z), Vector2(n * sw, sd)), "w": sw, "n": n, "facing": facing})
		z += sd
		if facing > 0.0:
			z += aisle
			facing = -1.0
		else:
			facing = 1.0


const GLYPHS := {
	"O": ["111", "101", "101", "101", "111"],
	"U": ["101", "101", "101", "101", "111"],
	"T": ["111", "010", "010", "010", "010"],
	"I": ["1", "1", "1", "1", "1"],
	"N": ["1001", "1101", "1011", "1001", "1001"],
}


func _lettering(text: String, c: Vector2, toward: String) -> void:
	## Block letters on the asphalt, read by a driver heading `toward` (their tops point that way), plus an arrow.
	var up2: Vector2 = L.FRONTS.get(toward, Vector2(1, 0))
	var right2 := Vector2(-up2.y, up2.x)   # the driver's right
	var cell := 0.45
	var width := 0.0
	for ch in text:
		width += (GLYPHS[ch][0] as String).length() + 1
	width -= 1
	var x := -width * 0.5
	for ch in text:
		var g: Array = GLYPHS[ch]
		for row in 5:
			var line: String = g[row]
			for col in line.length():
				if line[col] == "1":
					var p := c + right2 * ((x + col + 0.5) * cell) + up2 * ((2.0 - row) * cell)
					_paint(p, _y(p) + L.ROAD_TOP + 0.024, up2, cell * 1.02, cell * 1.02, WHITE)
		x += line_len(g) + 1
	# Arrow ahead of the word.
	var tip := c + up2 * 6.0
	_paint(c + up2 * 4.0, _y(c) + L.ROAD_TOP + 0.024, up2, 3.0, 0.3, WHITE)
	for s in [-1.0, 1.0]:
		var d = (up2 * -0.7 + right2 * s * 0.7).normalized()
		_paint(tip + d * 0.6, _y(tip) + L.ROAD_TOP + 0.024, d, 1.3, 0.28, WHITE)


static func line_len(g: Array) -> int:
	return (g[0] as String).length()
