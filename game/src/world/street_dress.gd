extends RefCounted
## The lived-in mess of a Philippine informal settlement, placed along every lane the districts recorded:
## wooden and concrete posts carrying sagging bundles of wire with service drops to each meter box, washing strung
## across the alleys, rubbish bags and heaps against walls, crates and pails and bottles people left out (loose,
## physical props: bottles can be thrown), puddles and open drains, graffiti and census numbers on walls,
## rubbish floating on the estero and river, banana, coconut and bamboo in the gaps, reeds at the water's edge,
## and tricycles, a jeepney and food carts where vehicles can go.

const TAGS := "res://assets/models/sleep/tags/"
const CLOTHES := [Color(0.75, 0.2, 0.18), Color(0.2, 0.35, 0.65), Color(0.85, 0.82, 0.7), Color(0.25, 0.5, 0.3), Color(0.9, 0.7, 0.2),
	Color(0.55, 0.3, 0.55), Color(0.15, 0.15, 0.17), Color(0.95, 0.95, 0.95), Color(0.85, 0.45, 0.55)]

var mb = null
var L = null
var sink = null
var dyn = null
var rng := RandomNumberGenerator.new()
var _anchors := {}  # Vector2i cell (8 m) -> [Vector3]
var _tags: Array = []
var stats := {"poles": 0, "wires": 0, "laundry": 0, "clutter": 0, "props": 0, "tags": 0, "puddles": 0, "plants": 0, "vehicles": 0, "floating": 0,
	"loot": 0, "boxes": 0}


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	sink = mb.sink
	dyn = mb.dyn
	rng.seed = L.rng.seed + 509
	for a in dyn.wire_anchors:
		var k := Vector2i(floori(a.x / 8.0), floori(a.z / 8.0))
		if not _anchors.has(k):
			_anchors[k] = []
		_anchors[k].append(a)
	var d := DirAccess.open(TAGS)
	if d:
		for f in d.get_files():
			if f.ends_with(".png"):
				_tags.append(TAGS + f)


func build() -> void:
	for a in mb.alleys:
		_lane(a)
	# Wall decals are placed by vandal.gd from one atlas (the per-texture decals here cost a draw call each).
	_water_rubbish()
	_vegetation()
	_vehicles()
	print("[dress] ", stats)


# ------------------------------------------------------------------ helpers

func _pick(a: Array):
	return a[rng.randi_range(0, a.size() - 1)]


func _gy(p: Vector2) -> float:
	return L.ground_height(p.x, p.y)


func _surface_y(p: Vector2, fallback: float) -> float:
	## Highest walkable surface under p (deck or ground), from the physics world once it exists; else terrain.
	return maxf(_gy(p), fallback)


func _lane_prop(name: String, xf: Transform3D, lane_w: float = 9.0) -> void:
	## Loose clutter against a wall: never in a doorway or a door's swing, and nothing heavy where it would leave
	## less than a person's width of the lane (a drum in a 1.3 m eskinita closed it).
	var heavy := float(mb.models.spec(name).get("mass", 99.0)) >= 6.0
	if heavy and lane_w < 2.4:
		return
	if not _spot_ok(xf.origin, 0.35):
		return
	dyn.add_prop_spec(name, dyn.seat(name, xf))
	stats.props += 1


func _spot_ok(p: Vector3, r: float) -> bool:
	return dyn.spot_clear(Vector2(p.x, p.z), Vector2(r, r), 0.0, p.y)


func _free_spot(p: Vector2, r: float) -> bool:
	return not L.is_water(p.x, p.y) and L.rect_free(p, Vector2(r, r), 0.0, false, 0.0)


# ------------------------------------------------------------------ lanes

func _lane(a: Dictionary) -> void:
	var pa: Vector2 = a.a
	var pb: Vector2 = a.b
	var len := pa.distance_to(pb)
	if len < 4.0:
		return
	var dir := (pb - pa) / len
	var side := Vector2(-dir.y, dir.x)
	var w := float(a.w)
	var deck := float(a.get("y", -INF))
	var walk: bool = a.kind == "walk"
	# Posts and wire bundles
	var t := rng.randf_range(2.0, 8.0)
	var prev_top := Vector3.INF
	var pole_side := 1.0 if rng.randf() < 0.5 else -1.0
	while t < len:
		var p := pa + dir * t + side * pole_side * (w * 0.5 - 0.15)
		var gy := deck if walk else _gy(p)
		if mb.cover and mb.cover.covered(p):
			# No posts through a lane roof: the wiring runs along its underside instead.
			t += rng.randf_range(13.0, 20.0)
			prev_top = Vector3.INF
			continue
		if L.is_water(p.x, p.y) and not walk:
			t += rng.randf_range(14.0, 20.0)
			prev_top = Vector3.INF
			continue
		if not _spot_ok(Vector3(p.x, gy, p.y), 0.16):
			t += 1.1   # not in front of a door: a little further along
			continue
		var top := _pole(Vector3(p.x, gy, p.y), dir, walk)
		if prev_top != Vector3.INF and prev_top.distance_to(top) < 26.0:
			var n := rng.randi_range(3, 6)
			for k in n:
				var o := Vector3(0, -0.12 * k, 0) + Vector3(side.x, 0, side.y) * rng.randf_range(-0.25, 0.25)
				_wire(prev_top + o, top + o, rng.randf_range(0.35, 1.1))
		_service_drops(top)
		prev_top = top
		t += rng.randf_range(13.0, 20.0)
	# Washing across the alley
	if w < 3.2 and not walk:
		var n2 := int(len / 9.0)
		for k in n2:
			if rng.randf() < 0.32:
				var tc := rng.randf_range(0.0, len)
				var c := pa + dir * tc
				if mb.cover and mb.cover.covered(c):
					continue
				var y := _gy(c) + rng.randf_range(2.1, 2.6)
				var e0 := c - side * (w * 0.5 + 0.05) + dir * rng.randf_range(-0.6, 0.6)
				var e1 := c + side * (w * 0.5 + 0.05) + dir * rng.randf_range(-0.6, 0.6)
				_laundry(Vector3(e0.x, y, e0.y), Vector3(e1.x, y + rng.randf_range(-0.15, 0.15), e1.y))
	# Ground clutter along both walls
	var step := 0.0
	while step < len:
		step += rng.randf_range(1.6, 4.5)
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		var p2 := pa + dir * step + side * s * (w * 0.5 - rng.randf_range(0.18, 0.35))
		if L.is_water(p2.x, p2.y) and not walk:
			continue
		var y2 := deck if walk else _gy(p2)
		var r := rng.randf()
		var under: bool = mb.cover != null and mb.cover.covered(p2)
		if under:
			y2 += 0.025   # on the lane's floor slab
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p2.x, y2, p2.y))
		# Under a lane roof the clutter is lit like an inside room (interior layers).
		dyn.interior_scope = under
		if r < 0.22:
			if not _spot_ok(xf.origin, 0.4):
				continue
			var cn: String = _pick(["heap_small_a", "heap_small_b", "litter_a", "litter_b"])
			dyn.add_static_prop(cn, dyn.seat(cn, xf))
			stats.clutter += 1
		elif r < 0.5:
			_lane_prop(_pick(["trashbag", "trashbag", "box", "crate_plastic", "crate_plastic2", "crate_plastic3", "bucket", "gallon", "jerrycan", "container", "can", "old_tyre", "trash_can"]), xf, w)
		elif r < 0.62:
			_lane_prop("bottle", xf, w)
		elif r < 0.7 and not walk:
			_lane_prop(_pick(["monobloc", "stool", "bench_paint"]), xf, w)
		elif r < 0.78 and not walk:
			if _spot_ok(xf.origin, 0.3):
				var pn: String = _pick(["fern", "weeds", "grass_clump"])
				dyn.add_static_prop(pn, dyn.seat(pn, xf))
				stats.plants += 1
		elif r < 0.84 and not walk:
			_lane_prop(_pick(["drum_blue", "oil_drum", "drum"]), xf, w)
		elif r < 0.9 and not walk and w > 1.6 and not under:
			_puddle(Vector3(pa.x + dir.x * step, y2 + 0.02, pa.y + dir.y * step), rng.randf_range(0.8, 2.2))
		elif r < 0.935:
			# Something dropped or left out: loose loot by the wall.
			dyn.add_loot_spot(Vector3(p2.x, y2 + 0.02, p2.y), "floor_street", -1)
			stats.loot += 1
		elif r < 0.95 and not walk:
			var c: Array = _pick([["lootbox_bin", "box_bin"], ["lootbox_cooler", "box_cooler"], ["lootbox_balikbayan", "box_balikbayan"]])
			if w >= 1.9 and _spot_ok(xf.origin, 0.45) and dyn.add_loot_box(str(c[0]), xf, str(c[1]), -1) >= 0:
				stats.boxes += 1
	dyn.interior_scope = false
	# Open drain along one edge of wider lanes
	if not walk and w >= 1.8 and rng.randf() < 0.35:
		var ds := 1.0 if rng.randf() < 0.5 else -1.0
		var k := 0.0
		while k < len:
			var seg := minf(6.0, len - k)
			var mid := pa + dir * (k + seg * 0.5) + side * ds * (w * 0.5 - 0.22)
			if not L.is_water(mid.x, mid.y):
				var y3 := _gy(mid)
				var ang := atan2(-dir.y, dir.x)
				# Concrete sides, the silt on top (the silt 1 cm under the concrete's top z-fought with it).
				sink.box(Transform3D(Basis(Vector3.UP, ang), Vector3(mid.x, y3 + 0.03, mid.y)), Vector3(seg, 0.06, 0.34), "concrete_dirty", {"collide": false, "faces": 1 | 2 | 16 | 32, "dirt": 1.0, "layer": "mid"})
				sink.box(Transform3D(Basis(Vector3.UP, ang), Vector3(mid.x, y3 + 0.055, mid.y)), Vector3(seg, 0.01, 0.34), "mud", {"collide": false, "faces": 4, "dirt": 0.0, "layer": "mid"})
			k += seg


func _pole(base: Vector3, along: Vector2, light: bool) -> Vector3:
	stats.poles += 1
	var concrete := rng.randf() < 0.45
	var h := rng.randf_range(5.6, 7.2) if not light else rng.randf_range(3.6, 4.4)
	var lean := Basis(Vector3(along.x, 0, along.y).normalized(), rng.randf_range(-0.05, 0.05))
	var mat := "concrete_dirty" if concrete else "timber"
	var r := 0.11 if concrete else 0.08
	sink.box(Transform3D(lean, base + lean * Vector3(0, h * 0.5, 0)), Vector3(r * 2.0, h, r * 2.0), mat, {"dirt": 0.9, "phys": "concrete" if concrete else "wood", "layer": "ext"})
	var top := base + lean * Vector3(0, h - 0.25, 0)
	var ang := atan2(-along.y, along.x)
	sink.box(Transform3D(Basis(Vector3.UP, ang + PI * 0.5), top), Vector3(1.1, 0.09, 0.09), "timber", {"collide": false, "layer": "mid"})
	if rng.randf() < 0.3:
		# A pole-mounted transformer or a junction box with a tangle under it.
		sink.box(Transform3D(Basis(), top + Vector3(0, -0.9, 0.18)), Vector3(0.4, 0.55, 0.32), "metal_paint", {"collide": false, "tint": Color(0.55, 0.58, 0.55), "paint": 0.8, "layer": "mid"})
	if not light:
		mb.pole_tops.append([top, along])
	if not light and mb.practical.rng.randf() < 0.5:
		# About half the posts carry a bare bulb for the lane (some dead, many faulty).
		mb.practical.pole_bulb(top + Vector3(0, -0.12, 0), along)
	return top


func _wire(a: Vector3, b: Vector3, sag: float) -> void:
	## A catenary-ish cable from a to b, as thin black segments.
	stats.wires += 1
	var n := 7
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		_segment(prev, p, 0.014)
		prev = p


func _segment(a: Vector3, b: Vector3, thick: float) -> void:
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
	sink.box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(thick, thick, l), "wire", {"collide": false, "faces": 1 | 2 | 4 | 8, "layer": "mid"})


func _service_drops(top: Vector3) -> void:
	var k := Vector2i(floori(top.x / 8.0), floori(top.z / 8.0))
	var drops := 0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for an in _anchors.get(k + Vector2i(dx, dz), []):
				var p: Vector3 = an
				if p.distance_to(top) < 13.0 and drops < 5 and rng.randf() < 0.6:
					_wire(top + Vector3(0, -0.1, 0), p, rng.randf_range(0.2, 0.6))
					drops += 1


func _laundry(a: Vector3, b: Vector3) -> void:
	stats.laundry += 1
	_wire(a, b, 0.18)
	var len := a.distance_to(b)
	var n := int(len / 0.45)
	for i in n:
		if rng.randf() < 0.35:
			continue
		var t := (i + 0.5) / n
		var p := a.lerp(b, t) + Vector3.DOWN * 0.18 * 4.0 * t * (1.0 - t)
		var cw := rng.randf_range(0.28, 0.55)
		var ch := rng.randf_range(0.3, 0.75)
		var d := (b - a).normalized()
		var basis := Basis(d, Vector3.UP, d.cross(Vector3.UP)).orthonormalized()
		var col: Color = _pick(CLOTHES)
		sink.box(Transform3D(basis * Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), p + Vector3.DOWN * ch * 0.5), Vector3(cw, ch, 0.01),
			_pick(["cloth", "gingham", "denim"]) if false else _pick(["cloth", "gingham"]), {"collide": false, "faces": 16 | 32, "tint": col, "paint": 1.0, "dirt": 0.1, "layer": "mid"})


func _puddle(c: Vector3, r: float) -> void:
	stats.puddles += 1
	var a := rng.randf() * TAU
	var x := Vector3(cos(a), 0, sin(a)) * r
	var z := Vector3(-sin(a), 0, cos(a)) * r * rng.randf_range(0.5, 0.9)
	sink.quad(c - x - z, c + x - z, c + x + z, c - x + z, "puddle", {"facing": Vector3.UP, "layer": "mid"})


# ------------------------------------------------------------------ walls: graffiti, census numbers, posters

func _walls() -> void:
	if _tags.is_empty():
		return
	for bd in mb.buildings:
		if rng.randf() > 0.42:
			continue
		var xf: Transform3D = bd.xf
		var w := float(bd.w)
		var d := float(bd.d)
		var tex: String = _pick(_tags)
		var big := tex.find("graffiti") >= 0
		var sw := rng.randf_range(0.9, 1.8) if big else rng.randf_range(0.35, 0.8)
		var sh := sw * (0.5 if big else rng.randf_range(0.55, 0.9))
		var lx := rng.randf_range(-w * 0.5 + sw * 0.5, w * 0.5 - sw * 0.5)
		var ly := rng.randf_range(0.6, 1.9)
		var c := xf * Vector3(lx, ly, -d * 0.5 - 0.035)
		var right := xf.basis.x.normalized()
		var up := Vector3.UP
		var p0 := c - right * sw * 0.5 - up * sh * 0.5
		var p1 := c + right * sw * 0.5 - up * sh * 0.5
		var p2 := c + right * sw * 0.5 + up * sh * 0.5
		var p3 := c - right * sw * 0.5 + up * sh * 0.5
		var col := Color(1, 1, 1, rng.randf_range(0.55, 0.95))
		# UV: quad() maps from p0 along p1 (u) and up (v); feed corners so the texture is upright.
		sink.quad(p3, p2, p1, p0, "decal:" + tex, {"facing": -xf.basis.z, "layer": "mid", "tile": sw, "tint": col, "paint": col.a})
		stats.tags += 1


# ------------------------------------------------------------------ water

func _water_rubbish() -> void:
	## Floating rubbish rafts and loose junk on the estero and along the river banks.
	for i in int(900 * L.MAP_SCALE * L.MAP_SCALE):  # samples per area, not per map
		var p := Vector2(rng.randf_range(-L.PLAY_HALF, L.PLAY_HALF), rng.randf_range(-L.PLAY_HALF, L.PLAY_HALF))
		if not L.is_water(p.x, p.y) or p.y > L.coast_z(p.x) - 10.0:
			continue
		# Prefer the edges: rubbish collects against the banks and stilts.
		var near_bank = not L.is_water(p.x + 4.0, p.y) or not L.is_water(p.x - 4.0, p.y) or not L.is_water(p.x, p.y + 4.0) or not L.is_water(p.x, p.y - 4.0)
		if not near_bank and rng.randf() < 0.75:
			continue
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, L.WATER_Y + 0.01, p.y))
		dyn.add_static_prop(_pick(["floating_a", "floating_b", "floating_c"]), xf)
		stats.floating += 1


# ------------------------------------------------------------------ plants

func _vegetation() -> void:
	for i in int(5000 * L.MAP_SCALE * L.MAP_SCALE):  # samples per area, not per map
		var p := Vector2(rng.randf_range(-L.PLAY_HALF - 40.0, L.PLAY_HALF + 40.0), rng.randf_range(-L.PLAY_HALF - 40.0, L.coast_z(0.0)))
		var water = L.is_water(p.x, p.y)
		var gy := _gy(p)
		if water:
			continue
		var bank = L.is_water(p.x + 3.0, p.y) or L.is_water(p.x - 3.0, p.y) or L.is_water(p.x, p.y + 3.0) or L.is_water(p.x, p.y - 3.0)
		if not L.rect_free(p, Vector2(0.6, 0.6), 0.0, false, 0.0) or not _spot_ok(Vector3(p.x, gy, p.y), 0.6):
			continue
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, gy, p.y))
		var q: Vector2 = p / L.MAP_SCALE  # in the unscaled layout's coordinates
		var outskirts := absf(q.x) > 430.0 or q.y < -470.0 or (q.x > 230.0 and q.y < -260.0)
		if bank:
			dyn.add_static_prop(_pick(["reeds", "cattails", "reeds", "banana_b", "fern"]), xf)
		elif outskirts:
			dyn.add_static_prop(_pick(["palm_a", "palm_b", "banana_a", "tree_island", "tree_small", "bamboo", "shrub", "grass_clump", "grass_clump"]), xf)
		elif rng.randf() < 0.35:
			dyn.add_static_prop(_pick(["banana_a", "banana_b", "palm_a", "palm_b", "tree_small", "bamboo", "shrub", "weeds"]), xf)
		else:
			continue
		L.reserve_rect(p, Vector2(0.5, 0.5), 0.0, 4)
		stats.plants += 1


# ------------------------------------------------------------------ vehicles

func _vehicles() -> void:
	for r in L.roads:
		var pts: PackedVector2Array = r.pts
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var len := a.distance_to(b)
			var dir := (b - a) / len
			var t := rng.randf_range(10.0, 40.0)
			while t < len:
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var p := a + dir * t + Vector2(-dir.y, dir.x) * side * (float(r.w) * 0.5 - 1.0)
				if not L.is_water(p.x, p.y) and L.in_play_area(p) and _spot_ok(Vector3(p.x, _gy(p), p.y), 1.6):
					var yaw := atan2(dir.x, dir.y) + (PI if rng.randf() < 0.5 else 0.0) + rng.randf_range(-0.15, 0.15)
					var kind: String = _pick(["tricycle_a", "tricycle_b", "tricycle_a", "food_cart_a", "food_cart_b", "food_stall"])
					if float(r.w) >= 8.0 and rng.randf() < 0.18:
						kind = "jeepney"
					dyn.add_static_prop(kind, dyn.seat(kind, Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, _gy(p), p.y))))
					stats.vehicles += 1
				t += rng.randf_range(25.0, 70.0)
