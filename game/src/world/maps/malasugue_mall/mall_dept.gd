extends RefCounted
## (r16) Alex Jackie, the department store: the whole east anchor on Levels 1-3 (91 m long, 14.5 m deep on each
## floor, Level 1 in two halves either side of the East Entrance), its floors joined inside by two escalators that
## stopped when the power went - stairs now, with the sign to say so. Departments under hanging signs: on Level 1
## cosmetics and fragrance counters, bags, shoes and customer service; on Level 2 kids, a clearance sale, ladies, the
## fitting rooms, men and the stock room behind a staff door; on Level 3 home and living, bedding, toys and
## appliances. Only parts of it still have power: the rest is dark between the racks, a fitting flickering here and
## there. And the mess the crowd left: racks pulled over, clothes and boxes everywhere, mannequins down, blood dragged
## into the stock room ("DEAD INSIDE - DO NOT OPEN" on its door).

var B = null
var mb = null
var L = null
var S = null
var rng := RandomNumberGenerator.new()
var stats := {"escalators": 0, "zones": 0, "lights": 0, "fixtures": 0}
var sh = null   # MallShops, while dressing a floor

const STEPS := 22
const FLAT := 1.25
const PAL_LADIES := [Color(0.85, 0.5, 0.58), Color(0.95, 0.94, 0.9), Color(0.55, 0.08, 0.1), Color(0.78, 0.68, 0.5), Color(0.55, 0.7, 0.86), Color(0.2, 0.2, 0.22)]
const PAL_MEN := [Color(0.1, 0.12, 0.2), Color(0.42, 0.42, 0.44), Color(0.08, 0.08, 0.09), Color(0.78, 0.74, 0.66), Color(0.3, 0.38, 0.26), Color(0.92, 0.92, 0.9)]
const PAL_KIDS := [Color(1, 0.5, 0.6), Color(0.4, 0.8, 0.95), Color(1, 0.85, 0.3), Color(0.6, 0.9, 0.5), Color(0.8, 0.6, 1.0)]


func _init(builder) -> void:
	B = builder
	mb = builder.mb
	L = builder.L
	S = builder.S
	rng.seed = 6161


# ------------------------------------------------------------------ power

func power_at(p: Vector3) -> int:
	## Which of the store's ceiling fittings still work, by floor and stretch (world z).
	var lv: int = L.level_of(p.y - 3.0)   # (a ceiling fitting is 4.2 m over its floor)
	var z := p.z
	match lv:
		0:
			if z > 30.0:
				return B.POWER_ON
			return B.POWER_FAULTY if absf(z - 21.0) < 2.5 or absf(z + 30.0) < 2.5 else B.POWER_DEAD
		1:
			if z > -9.5 and z < 15.5:
				return B.POWER_ON if absf(z - 3.0) > 2.0 else B.POWER_FAULTY
			return B.POWER_FAULTY if absf(z + 22.0) < 2.5 or absf(z - 33.0) < 2.0 else B.POWER_DEAD
		2:
			if z > 21.0:
				return B.POWER_ON
			return B.POWER_FAULTY if absf(z) < 2.5 or absf(z + 33.0) < 2.0 else B.POWER_DEAD
	return B.POWER_DEAD


# ------------------------------------------------------------------ the stopped escalators

func build_escalators() -> void:
	for e in L.DEPT_ESC:
		_escalator(int(e.t), float(e.x), float(e.z0), float(e.dir))
		stats.escalators += 1


func _escalator(t: int, x: float, z0: float, dir: float) -> void:
	var run: float = L.ESC_RUN
	var rise: float = L.FH
	var total := run + FLAT * 2.0
	var incl := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var X := Vector3(0, 0, dir)
	var Z := X.cross(Vector3.UP)
	var xf := Transform3D(Basis(X, Vector3.UP, Z), Vector3(x, t * L.FH, z0) - X * FLAT)
	var o := func(lx: float, ly: float, lz: float) -> Vector3: return xf * Vector3(lx, ly, lz)
	var inc_basis := xf.basis * Basis(Vector3(0, 0, 1), ang)
	var inc_mid := Vector3(FLAT + run * 0.5, rise * 0.5, 0.0)
	var hw := 0.5
	var bal := 0.62
	# the truss, clad down to the floor on both sides (a closed wedge under the incline)
	S.box(Transform3D(inc_basis, o.call(inc_mid.x, inc_mid.y - 0.82, 0.0)), Vector3(incl + 0.6, 1.0, 1.55), "mall_satin", B.o({"layer": "ext", "collide": true, "tint": Color(0.84, 0.85, 0.87), "paint": 1.0}))
	var segs := 9
	for k in segs:
		var u0 := FLAT + run * k / segs
		var u1 := FLAT + run * (k + 1) / segs
		var hgt := rise * ((u0 + u1) * 0.5 - FLAT) / run - 0.75
		if hgt < 0.15:
			continue
		S.box(Transform3D(xf.basis, o.call((u0 + u1) * 0.5, hgt * 0.5, 0.0)), Vector3(u1 - u0, hgt, 1.5), "mall_satin", B.o({"layer": "ext", "collide": true,
			"tint": Color(0.8, 0.81, 0.83), "paint": 1.0}))
	# the steps, standing still: grooved treads with their yellow edges, dark risers
	for i in STEPS:
		var u := FLAT + run * (i + 0.5) / STEPS
		var hy := rise * (i + 1) / STEPS
		S.box(Transform3D(xf.basis, o.call(u, hy - 0.015, 0.0)), Vector3(run / STEPS - 0.01, 0.03, 1.0), "mall_steel", B.o({"layer": "mid"}))
		S.box(Transform3D(xf.basis, o.call(u + run / STEPS * 0.5 - 0.025, hy + 0.001, 0.0)), Vector3(0.04, 0.004, 0.98), "mall_flat", B.o({"layer": "int", "tint": Color(0.98, 0.78, 0.08), "paint": 1.0}))
		S.box(Transform3D(xf.basis, o.call(FLAT + run * i / STEPS, hy - rise / STEPS * 0.5, 0.0)), Vector3(0.02, rise / STEPS, 1.0), "mall_black", B.o({"layer": "mid"}))
	for fl in [[FLAT * 0.5, 0.0], [FLAT + run + FLAT * 0.5, rise]]:
		S.box(Transform3D(xf.basis, o.call(fl[0], float(fl[1]) + 0.006, 0.0)), Vector3(FLAT, 0.012, 1.0), "mall_steel", B.o({"layer": "mid"}))
	# the walking surface: a smooth ramp at the step tops (the landings are the floors)
	S.col_box(Transform3D(inc_basis, o.call(inc_mid.x, inc_mid.y - 0.1, 0.0)), Vector3(incl, 0.2, 1.1), "escalator", "escalator")
	# skirts, glass balustrades, handrails, decking
	var parts := [[Vector3(FLAT * 0.5 - 0.3, 0.0, 0.0), Basis(), FLAT + 0.6], [inc_mid, Basis(Vector3(0, 0, 1), ang), incl], [Vector3(FLAT + run + FLAT * 0.5 + 0.3, rise, 0.0), Basis(), FLAT + 0.6]]
	for p in parts:
		var c: Vector3 = p[0]
		var bb: Basis = xf.basis * (p[1] as Basis)
		var len: float = p[2]
		for s in [-1.0, 1.0]:
			S.box(Transform3D(bb, xf * (c + Vector3(0, 0.14, s * (hw + 0.03)))), Vector3(len, 0.3, 0.03), "mall_steel", B.o({"layer": "mid"}))
			S.box(Transform3D(bb, xf * (c + Vector3(0, 0.22, s * (hw + 0.01)))), Vector3(len, 0.02, 0.012), "mall_light_dead", B.o({"layer": "mid"}))
			S.box(Transform3D(bb, xf * (c + Vector3(0, 0.66, s * bal))), Vector3(len, 0.82, 0.015), "mall_glass", B.o({"layer": "mid"}))
			S.box(Transform3D(bb, xf * (c + Vector3(0, 1.1, s * bal))), Vector3(len, 0.07, 0.085), "mall_black", B.o({"layer": "mid"}))
			S.box(Transform3D(bb, xf * (c + Vector3(0, 0.29, s * (hw + 0.12)))), Vector3(len, 0.03, 0.2), "mall_steel", B.o({"layer": "mid"}))
			S.col_box(Transform3D(bb, xf * (c + Vector3(0, 0.6, s * bal))), Vector3(len, 1.2, 0.08), "glass", "escalator_side")
	for s2 in [-1.0, 1.0]:
		for endx in [-0.3, total + 0.3]:
			S.box(Transform3D(xf.basis, o.call(endx, 0.7 + (rise if endx > total * 0.5 else 0.0), s2 * bal)), Vector3(0.05, 0.8, 0.09), "mall_black", B.o({"layer": "mid"}))
	# "Escalator not running" at the foot and the head, on folding stands
	for end in [[-0.9, 0.0, 0.0], [total + 0.9, rise, PI]]:
		var sp: Vector3 = o.call(end[0], end[1], -0.95)
		var sb := xf.basis * Basis(Vector3.UP, float(end[2]) + PI * 0.5)
		for k2 in 2:
			S.box(Transform3D(sb * Basis(Vector3(1, 0, 0), 0.18 * (1 - k2 * 2)), sp + Vector3(0, 0.45, 0) + sb * Vector3(0, 0, 0.08 * (1 - k2 * 2))), Vector3(0.62, 0.9, 0.02),
				"mall_gloss", B.o({"tint": Color(0.95, 0.8, 0.1), "paint": 1.0, "layer": "int"}))
		var nrm := sb * Vector3(0, 0, 1)
		B.wall_decal(sp + Vector3(0, 0.62, 0) + nrm * 0.1, nrm, Vector2(0.58, 0.15), "dept_escalator", 1.0, 0.0)
		L.block_rect(int(t + (1 if float(end[1]) > 0.0 else 0)), Vector2(sp.x, sp.z), Vector2(0.35, 0.2), 0.0, 0.1)
	# bots: the wedge under the stairs closed on the floor below. (They are not linked for bots: in testing a bot sent
	# up them stalled beside the wedge; bots go round by the mall's escalators and fire stairs.)
	var lo := xf * Vector3(FLAT, 0, 0)
	var hi := xf * Vector3(FLAT + run, 0, 0)
	var mid2 := (lo + hi) * 0.5
	L.block_rect(t, Vector2(mid2.x, mid2.z), Vector2(0.95, run * 0.5), 0.0, 0.25)
	for s3 in [-1.0, 1.0]:
		for lvl_end in [[t, 0.0], [t + 1, total]]:
			var ex: float = lvl_end[1]
			var p0 := xf * Vector3(ex - (1.55 if ex > 0.0 else -0.3), 0, s3 * bal)
			var p1 := xf * Vector3(ex + (0.3 if ex > 0.0 else 1.55), 0, s3 * bal)
			L.block_seg(int(lvl_end[0]), Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), 0.1, 0.25)
	mb.stairs.append({"foot": xf * Vector3(FLAT, 0, 0), "top": xf * Vector3(FLAT + run, rise, 0)})
	# the opening in the floor above: lined, and a glass balustrade round it but at the head of the stairs
	var w: Rect2 = L.dept_well(t + 1)
	var y1: float = L.level_y(t + 1)
	var y0: float = L.level_y(t) + L.CEIL
	for side in [[Vector2(w.position.x, w.position.y), Vector2(w.position.x, w.end.y), Vector2(1, 0)], [Vector2(w.end.x, w.position.y), Vector2(w.end.x, w.end.y), Vector2(-1, 0)],
			[Vector2(w.position.x, w.position.y), Vector2(w.end.x, w.position.y), Vector2(0, 1)], [Vector2(w.position.x, w.end.y), Vector2(w.end.x, w.end.y), Vector2(0, -1)]]:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var n: Vector2 = side[2]
		var m := (a + b) * 0.5 + n * 0.03
		S.box(Transform3D(Basis(Vector3.UP, B.seg_yaw(a, b)), Vector3(m.x, (y0 + y1) * 0.5 - 0.01, m.y)), Vector3(a.distance_to(b) + 0.06, y1 - y0 - 0.02, 0.06), "mall_paint",
			B.o({"tint": B.WHITE, "paint": 1.0, "layer": "ext"}))
	var head_z := float(z0) + dir * run
	var start_z := w.position.y if dir > 0.0 else w.end.y
	B._balustrade(t + 1, Vector2(w.position.x, start_z), Vector2(w.end.x, start_z), Vector2(0, dir))
	for sx in [w.position.x, w.end.x]:
		B._balustrade(t + 1, Vector2(sx, start_z), Vector2(sx, head_z - dir * 0.05), Vector2(signf(x - sx), 0))
	L.block_rect(t + 1, w.get_center(), w.size * 0.5, 0.0, 0.35)


# ------------------------------------------------------------------ dressing a floor

func dress(shops, u: Dictionary) -> void:
	sh = shops
	var lv: int = int(u.level)
	var w: float = sh._w
	var d: float = sh._d
	var north: bool = lv == 0 and (u.rect as Rect2).get_center().y < 0.0
	if lv == 0 and not north:
		_zone_cosmetics(0.0, 13.0)
		_zone_fragrance(13.0, 19.0)
		_zone_bags(19.0, 34.5, 7.4)
		_zone_service(34.5, w)
	elif lv == 0:
		_zone_shoes(0.0, 15.0)
		_zone_bags(15.0, 28.0, d - 1.0)
		_zone_cosmetics(28.0, w)
	elif lv == 1:
		_zone_kids(0.0, 18.0)
		_zone_clearance(18.0, 30.0)
		_zone_fashion(30.0, 55.0, "dept_ladies", PAL_LADIES, Color(0.85, 0.5, 0.58))
		_zone_fitting(55.0, 70.0)
		_zone_fashion(70.0, 85.5, "dept_men", PAL_MEN, Color(0.1, 0.12, 0.2))
		_stock_room(85.5, w)
	else:
		_zone_home(0.0, 25.0)
		_zone_bedding(25.0, 45.0)
		_zone_toys(45.0, 62.0)
		_zone_appliances(75.0, w)
		_sign(68.5, "dept_clearance_sale")
	_lights(lv, w, d)
	_mess(lv, w, d)
	# guns and loot lying about, as in every shop
	for k in int(w / 14.0):
		sh.loot(rng.randf_range(1.0, w - 1.0), rng.randf_range(2.0, d - 2.0), 0.02, "floor_weapon" if k % 2 == 0 else "floor_contested")


func _keep_out(x: float, z: float, r: float = 0.9) -> bool:
	## Inside the escalators' footprints (world rects round the wedges and the openings) or too near the front glass.
	var p: Vector3 = sh.P(x, z)
	for e in L.DEPT_ESC:
		var ex := float(e.x)
		var za := float(e.z0) - float(e.dir) * (FLAT + 1.6)
		var zb = float(e.z0) + float(e.dir) * (L.ESC_RUN + FLAT + 1.6)
		if absf(p.x - ex) < 1.1 + r and p.z > minf(za, zb) - r and p.z < maxf(za, zb) + r:
			if absf(p.y - L.level_y(int(e.t))) < 0.5 or absf(p.y - L.level_y(int(e.t) + 1)) < 0.5:
				return true
	return z < 1.6


func _sign(x: float, name: String, z: float = 6.6) -> void:
	## A department's sign hanging from the ceiling on two rods, both faces.
	var h: float = L.CEIL - 0.75
	sh.box(x, z, h, Vector3(2.04, 0.52, 0.05), "mall_satin", {"tint": Color(0.08, 0.12, 0.22), "paint": 1.0, "layer": "mid"})
	for s in [0.0, PI]:
		sh.quad_wall(x, z - 0.03 * (1.0 if s == 0.0 else -1.0), h, 2.0, 0.5, B.cell(name), B.APOC, s, "mid")
	for rx in [-0.8, 0.8]:
		sh.box(x + rx, z, h + 0.26 + (L.CEIL - h - 0.26) * 0.5, Vector3(0.015, L.CEIL - h - 0.26, 0.015), "mall_steel", {"layer": "mid"})
	stats.zones += 1


func _rack_or_fallen(x: float, z: float, len: float, yaw: float, pal: Array) -> void:
	if _keep_out(x, z, len * 0.5):
		return
	if rng.randf() < 0.28:
		_fallen_rack(x, z, len, yaw, pal)
	else:
		sh.rack(x, z, len, yaw, pal)
	stats.fixtures += 1


func _fallen_rack(x: float, z: float, len: float, yaw: float, pal: Array) -> void:
	## Pulled over: the rail on the floor, the clothes in a heap round it.
	sh.box(x, z, 0.05, Vector3(len, 0.03, 0.03), "mall_chrome", {}, yaw + 0.2)
	sh.box(x + 0.4, z + 0.2, 0.3, Vector3(0.04, 0.04, 1.42), "mall_chrome", {}, yaw)
	for i in int(len / 0.18):
		var o := Vector3(rng.randf_range(-len * 0.6, len * 0.6), 0, rng.randf_range(-0.7, 0.7)).rotated(Vector3.UP, yaw)
		sh.box(x + o.x, z + o.z, 0.03 + rng.randf() * 0.05, Vector3(0.45, 0.04, 0.6), "mall_cloth", {"tint": pal[rng.randi() % pal.size()], "paint": 1.0}, rng.randf() * TAU)


func _fallen_mannequin(x: float, z: float, yaw: float, top: Color, bottom: Color) -> void:
	## A display figure face down on the floor, an arm come off.
	var bas: Basis = sh._xf.basis * Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), PI * 0.5)
	var p: Vector3 = sh.P(x, z, 0.12)
	var skin := Color(0.96, 0.96, 0.95)
	for q in [[Vector3(-0.09, 0.5, 0), Vector3(0.13, 0.85, 0.15), "mall_cloth", bottom], [Vector3(0.09, 0.5, 0), Vector3(0.13, 0.85, 0.15), "mall_cloth", bottom],
			[Vector3(0, 1.22, 0), Vector3(0.38, 0.55, 0.22), "mall_cloth", top], [Vector3(0.24, 1.15, 0), Vector3(0.09, 0.6, 0.1), "mall_cloth", top],
			[Vector3(0, 1.55, 0), Vector3(0.08, 0.1, 0.08), "mall_gloss", skin], [Vector3(0, 1.7, 0.01), Vector3(0.17, 0.22, 0.2), "mall_gloss", skin]]:
		S.box(Transform3D(bas, p + bas * (q[0] as Vector3) + Vector3(0, -0.02, 0)), q[1], q[2], B.o({"tint": q[3], "paint": 1.0, "layer": "int"}))
	sh.box(x + 0.6, z - 0.5, 0.05, Vector3(0.09, 0.09, 0.6), "mall_cloth", {"tint": top, "paint": 1.0}, yaw + 1.1)


func _zone_fashion(x0: float, x1: float, sign_name: String, pal: Array, accent: Color) -> void:
	var d: float = sh._d
	_sign((x0 + x1) * 0.5, sign_name)
	var cols := int((x1 - x0) / 3.4)
	for i in cols:
		var x := x0 + (i + 0.5) * (x1 - x0) / cols
		for z in [3.6, 6.2, 8.8, 11.4]:
			if (i + int(z)) % 4 == 0:
				if not _keep_out(x, z):
					sh.round_rack(x, z)
			else:
				_rack_or_fallen(x, z, 2.0, 0.0, pal)
	# mannequins on a plinth by the walk, some knocked down
	for k in 4:
		var mx := x0 + 1.5 + k * (x1 - x0 - 3.0) / 3.0
		if _keep_out(mx, 2.2):
			continue
		var c1: Color = pal[rng.randi() % pal.size()]
		var c2: Color = pal[rng.randi() % pal.size()]
		if rng.randf() < 0.45:
			_fallen_mannequin(mx, 2.6, rng.randf() * TAU, c1, c2)
		else:
			sh.mannequin(mx, 2.2, PI + rng.randf_range(-0.4, 0.4), c1, c2, false, 0.0)
	if not _keep_out((x0 + x1) * 0.5, d - 0.6):
		sh.wall_shelf(x0 + 0.3, x1 - 0.3, d - 0.15, 4 if sign_name == "dept_ladies" else 5, 4)
	sh.box((x0 + x1) * 0.5, d - 0.16, 3.2, Vector3(x1 - x0 - 0.6, 0.5, 0.02), "mall_satin", {"tint": accent, "paint": 1.0})


func _zone_kids(x0: float, x1: float) -> void:
	_sign((x0 + x1) * 0.5, "dept_kids")
	for i in int((x1 - x0) / 3.0):
		var x := x0 + 1.5 + i * 3.0
		for z in [4.0, 7.0, 10.0]:
			_rack_or_fallen(x, z, 1.4, 0.0, PAL_KIDS)
	for k in 3:
		var mx := x0 + 2.0 + k * 5.0
		if not _keep_out(mx, 2.2):
			sh.mannequin(mx, 2.2, PI, PAL_KIDS[k], PAL_KIDS[k + 1], false, -0.45)
	sh.wall_shelf(x0 + 0.3, x1 - 0.3, sh._d - 0.15, 5, 4)


func _zone_clearance(x0: float, x1: float) -> void:
	## Tables heaped with sale clothes (dug through and flung about), "Clearance Sale" over them.
	_sign((x0 + x1) * 0.5 - 2.0, "dept_clearance_sale", 4.0)
	for i in 3:
		for z in [3.6, 6.6]:
			var x := x0 + 2.0 + i * 3.4
			if _keep_out(x, z, 1.1):
				continue
			sh.box(x, z, 0.4, Vector3(1.8, 0.8, 1.0), "white_oak", {"solid": true})
			for k in 9:
				sh.box(x + rng.randf_range(-0.8, 0.8), z + rng.randf_range(-0.45, 0.45), 0.82 + k * 0.025, Vector3(0.4, 0.05, 0.5), "mall_cloth",
					{"tint": PAL_LADIES[rng.randi() % PAL_LADIES.size()], "paint": 1.0}, rng.randf() * TAU)
			for k2 in 5:
				sh.box(x + rng.randf_range(-1.6, 1.6), z + rng.randf_range(-1.2, 1.2), 0.025, Vector3(0.45, 0.04, 0.6), "mall_cloth",
					{"tint": PAL_MEN[rng.randi() % PAL_MEN.size()], "paint": 1.0}, rng.randf() * TAU)


func _zone_fitting(x0: float, x1: float) -> void:
	## Fitting rooms along the back: a row of booths with curtains (some torn down), a mirror at the end.
	_sign((x0 + x1) * 0.5, "dept_fitting_rooms", 9.0)
	var d: float = sh._d
	var n := int((x1 - x0 - 1.0) / 1.4)
	for i in n + 1:
		var bx := x0 + 0.5 + i * 1.4
		sh.box(bx, d - 1.0, 1.1, Vector3(0.05, 2.2, 1.8), "mall_satin", {"tint": Color(0.9, 0.88, 0.84), "paint": 1.0, "solid": true})
	for i2 in n:
		var cx := x0 + 0.5 + (i2 + 0.5) * 1.4
		sh.box(cx, d - 0.2, 1.2, Vector3(1.3, 1.6, 0.02), "mall_mirror", {})
		if rng.randf() < 0.6:
			sh.box(cx, d - 1.92, 1.15, Vector3(1.3, 2.0, 0.03), "velvet", {"tint": Color(0.5, 0.08, 0.12), "paint": 0.8})
		else:
			sh.box(cx + 0.3, d - 2.4, 0.04, Vector3(1.0, 0.06, 1.4), "velvet", {"tint": Color(0.5, 0.08, 0.12), "paint": 0.8}, 0.4)
	sh.box((x0 + x1) * 0.5, d - 1.92, 2.22, Vector3(x1 - x0 - 0.8, 0.04, 0.06), "mall_chrome", {})


func _zone_home(x0: float, x1: float) -> void:
	## Room sets: a sofa and coffee table on a rug, armchairs, lamps, a dining table; some overturned.
	_sign((x0 + x1) * 0.5, "dept_home_living")
	var sets := int((x1 - x0) / 6.0)
	for i in sets:
		var cx := x0 + 3.0 + i * 6.0
		for zc in [4.6, 10.0]:
			if _keep_out(cx, zc, 2.5):
				continue
			sh.box(cx, zc, 0.006, Vector3(3.6, 0.012, 2.6), "mall_cloth", {"tint": [Color(0.6, 0.45, 0.35), Color(0.3, 0.35, 0.45), Color(0.5, 0.52, 0.4)][i % 3], "paint": 1.0})
			if (i + int(zc)) % 3 == 0:
				sh.prop("dining_table", cx, zc, 0.0, false)
				for k in 4:
					sh.prop("dining_chair", cx + (-0.6 + (k % 2) * 1.2), zc + (-0.7 if k < 2 else 0.7), 0.0 if k < 2 else PI, true)
			else:
				sh.prop(["sofa_modern", "sofa_leather", "sofa_classic"][i % 3], cx, zc + 0.9, PI, false)
				sh.prop("coffee_table_modern" if i % 2 == 0 else "coffee_table", cx, zc - 0.3, 0.0, true)
				sh.prop("armchair_modern", cx + 1.6, zc - 0.4, -PI * 0.6, true)
				sh.prop("side_table_tall", cx - 1.6, zc + 0.8, 0.0, true)
			stats.fixtures += 1


func _zone_bedding(x0: float, x1: float) -> void:
	## Beds made up for display (one used: someone slept here), nightstands, shelves of towels and pillows.
	_sign((x0 + x1) * 0.5, "dept_bedding_bath")
	var n := int((x1 - x0) / 3.6)
	for i in n:
		var cx := x0 + 1.8 + i * 3.6
		var zc := 9.6
		if _keep_out(cx, zc, 1.5):
			continue
		var cover: Color = [Color(0.9, 0.88, 0.84), Color(0.55, 0.65, 0.78), Color(0.75, 0.55, 0.5), Color(0.35, 0.4, 0.35)][i % 4]
		sh.box(cx, zc, 0.22, Vector3(1.6, 0.44, 2.1), "walnut", {"solid": true})
		sh.box(cx, zc, 0.52, Vector3(1.55, 0.18, 2.0), "mall_cloth", {"tint": Color(0.95, 0.95, 0.93), "paint": 1.0})
		sh.box(cx + (0.2 if i % 3 == 0 else 0.0), zc - 0.2, 0.63, Vector3(1.6, 0.06, 1.5), "mall_cloth", {"tint": cover, "paint": 1.0}, 0.12 if i % 3 == 0 else 0.0)
		sh.box(cx, zc + 1.0, 0.7, Vector3(1.6, 1.0, 0.08), "walnut", {"solid": true})
		for s in [-0.4, 0.4]:
			sh.box(cx + s, zc + 0.75, 0.7, Vector3(0.6, 0.14, 0.4), "mall_cloth", {"tint": Color(0.96, 0.96, 0.95), "paint": 1.0})
		sh.prop("nightstand", cx + 1.15, zc + 0.75, PI, false)
		stats.fixtures += 1
	sh.wall_shelf(x0 + 0.3, x1 - 0.3, sh._d - 0.15, 5, 4)
	for i2 in int((x1 - x0) / 4.0):
		var x := x0 + 2.0 + i2 * 4.0
		if not _keep_out(x, 5.0):
			sh.gondola(x, 5.0, 2.4, 0.0, 2, 1.4)


func _zone_toys(x0: float, x1: float) -> void:
	_sign((x0 + x1) * 0.5, "dept_toys")
	for i in int((x1 - x0) / 3.6):
		var x := x0 + 1.8 + i * 3.6
		for z in [4.5, 8.0]:
			if not _keep_out(x, z, 1.4):
				sh.gondola(x, z, 2.6, PI * 0.5, 1 + (i % 3), 1.5)
	sh.wall_shelf(x0 + 0.3, x1 - 0.3, sh._d - 0.15, 1, 4)


func _zone_appliances(x0: float, x1: float) -> void:
	## Fridges and washing machines in rows, televisions on the wall (one still showing the adverts), an aircon.
	_sign((x0 + x1) * 0.5, "dept_appliances")
	var d: float = sh._d
	for i in int((x1 - x0 - 1.0) / 1.1):
		var x := x0 + 1.0 + i * 1.1
		var fridge := i % 3 != 2
		sh.box(x, d - 0.7, (1.75 if fridge else 0.85) * 0.5, Vector3(0.8, 1.75 if fridge else 0.85, 0.7), "mall_gloss",
			{"tint": [Color(0.9, 0.9, 0.9), Color(0.75, 0.76, 0.78), Color(0.15, 0.15, 0.16)][i % 3], "paint": 1.0, "solid": true})
		sh.box(x - 0.3, d - 1.06, 1.0 if fridge else 0.6, Vector3(0.03, 0.4, 0.03), "mall_chrome", {})
	for k in 3:
		var tx := x0 + 2.0 + k * 3.2
		if k == 1:
			sh.screen(tx, 0.4, 2.0, 1.6, 0.9, PI, 0.3)
		else:
			sh.box(tx, 0.4, 2.0, Vector3(1.7, 1.0, 0.06), "mall_black", {})
	for j in int((x1 - x0 - 2.0) / 2.4):
		var gx := x0 + 2.0 + j * 2.4
		if not _keep_out(gx, 6.0):
			sh.box(gx, 6.0, 0.45, Vector3(0.65, 0.9, 0.65), "mall_gloss", {"tint": Color(0.94, 0.94, 0.94), "paint": 1.0, "solid": true})
			sh.box(gx, 5.67, 0.55, Vector3(0.4, 0.4, 0.02), "mall_black", {})


func _zone_cosmetics(x0: float, x1: float) -> void:
	## Islands of lit glass counters round a mirrored column, testers spilled, a brand's light box behind.
	_sign((x0 + x1) * 0.5, "dept_cosmetics")
	var n := int((x1 - x0) / 6.5)
	for i in n:
		var cx := x0 + 3.25 + i * 6.5
		for zc in [5.0, 9.8]:
			if _keep_out(cx, zc, 2.2):
				continue
			sh.box(cx, zc, 1.4, Vector3(0.6, 2.8, 0.6), "mall_mirror", {"solid": true})
			for k in 4:
				var a := PI * 0.5 * k
				var o := Vector3(cos(a), 0, sin(a)) * 1.25
				if B.h01(int(cx), k, int(zc)) < 0.3:
					# smashed: the glass gone, the testers on the floor
					sh.box(cx + o.x, zc + o.z, 0.3, Vector3(1.6 if k % 2 == 0 else 0.5, 0.6, 0.5 if k % 2 == 0 else 1.6), "mall_black", {"solid": true})
					B.floor_decal(sh.P(cx + o.x * 1.6, zc + o.z * 1.6), Vector2(1.6, 1.6), rng.randf() * TAU, "floor_glass", 0.9)
					for j in 5:
						sh.box(cx + o.x * 1.5 + rng.randf_range(-0.5, 0.5), zc + o.z * 1.5 + rng.randf_range(-0.5, 0.5), 0.03, Vector3(0.05, 0.05, 0.12), "mall_metal_vc",
							{"tint": Color(0.85, 0.7, 0.25), "paint": 1.0}, rng.randf() * TAU)
				else:
					sh.glass_case(cx + o.x, zc + o.z, 1.6 if k % 2 == 0 else 0.5, 0.5 if k % 2 == 0 else 1.6, 0.0, [Color(0.85, 0.2, 0.3), Color(0.9, 0.85, 0.8), Color(0.2, 0.2, 0.25)][k % 3])
			stats.fixtures += 1


func _zone_fragrance(x0: float, x1: float) -> void:
	_sign((x0 + x1) * 0.5, "dept_fragrance")
	for z in [4.5, 8.5]:
		if not _keep_out((x0 + x1) * 0.5, z, 2.0):
			sh.glass_case((x0 + x1) * 0.5, z, x1 - x0 - 1.6, 0.6, 0.0, Color(0.95, 0.85, 0.55), 1.1)
	sh.wall_shelf(x0 + 0.3, x1 - 0.3, sh._d - 0.15, 0, 5)


func _zone_bags(x0: float, x1: float, zmax: float) -> void:
	_sign((x0 + x1) * 0.5, "dept_bags_accessories", minf(5.0, zmax - 1.0))
	for i in int((x1 - x0) / 3.0):
		var x := x0 + 1.5 + i * 3.0
		for z in [3.6, 6.0]:
			if z > zmax or _keep_out(x, z, 1.0):
				continue
			sh.box(x, z, 0.38, Vector3(1.4, 0.76, 0.9), "white_oak", {"solid": true})
			for k in 4:
				sh.box(x - 0.5 + k * 0.33, z + rng.randf_range(-0.2, 0.2), 0.88, Vector3(0.28, 0.24, 0.12), "leather", {"tint": PAL_LADIES[(i + k) % PAL_LADIES.size()], "paint": 0.7}, rng.randf_range(-0.3, 0.3))


func _zone_shoes(x0: float, x1: float) -> void:
	_sign((x0 + x1) * 0.5, "dept_shoes")
	sh.wall_shelf(x0 + 0.3, x1 - 0.3, sh._d - 0.15, 6, 5)
	for i in int((x1 - x0) / 4.0):
		var x := x0 + 2.0 + i * 4.0
		if not _keep_out(x, 6.5):
			sh.box(x, 6.5, 0.22, Vector3(2.4, 0.44, 0.6), "leather", {"solid": true, "tint": Color(0.3, 0.2, 0.15), "paint": 0.6})
		for k in 6:
			sh.box(x + rng.randf_range(-1.5, 1.5), 6.5 + rng.randf_range(-1.6, 1.6), 0.05, Vector3(0.11, 0.1, 0.28), "leather",
				{"tint": PAL_MEN[rng.randi() % PAL_MEN.size()], "paint": 0.7}, rng.randf() * TAU)


func _zone_service(x0: float, x1: float) -> void:
	_sign((x0 + x1) * 0.5, "dept_customer_service", 5.0)
	sh.counter((x0 + x1) * 0.5, sh._d - 2.0, minf(4.0, x1 - x0 - 1.0))


func _stock_room(x0: float, x1: float) -> void:
	## Behind a wall with a staff door: steel shelving with boxes, a pallet, dark. Someone was dragged in here; the
	## door's been written on.
	var d: float = sh._d
	sh.box(x0, (d + 2.2) * 0.5, L.CEIL * 0.5, Vector3(0.2, L.CEIL, d - 2.2), "mall_paint", {"tint": Color(0.82, 0.82, 0.8), "paint": 1.0, "solid": true, "layer": "ext"})
	sh.box(x0, 0.6, L.CEIL * 0.5, Vector3(0.2, L.CEIL, 1.2), "mall_paint", {"tint": Color(0.82, 0.82, 0.8), "paint": 1.0, "solid": true, "layer": "ext"})
	sh.box(x0, 1.7, 2.3 + (L.CEIL - 2.3) * 0.5, Vector3(0.2, L.CEIL - 2.3, 1.0), "mall_paint", {"tint": Color(0.82, 0.82, 0.8), "paint": 1.0, "collide": true, "layer": "ext"})
	var hinge: Vector3 = sh.P(x0, 1.2)
	mb.dyn.add_door({"xf": Transform3D(sh._xf.basis * Basis(Vector3.UP, -PI * 0.5), hinge), "w": 0.98, "h": 2.25, "t": 0.05, "mat": "metal_paint",
		"outer": false, "bid": sh._bid, "role": "fire_door", "clr": Vector2(1.0, 1.0)})
	sh.quad_wall(x0 - 0.12, 1.7, 2.45, 0.9, 0.23, B.cell("dept_staff"), B.APOC, PI * 0.5, "mid")
	B.wall_decal(sh.P(x0 - 0.11, 3.2, 1.3), -(sh._xf.basis.x.normalized()), Vector2(2.4, 1.2), "bloodtext_1", 0.95, 0.04)
	# inside: shelving down both sides with boxes
	for zz in [3.2, d - 0.6]:
		for k in 3:
			var hy := 0.3 + k * 0.75
			sh.box((x0 + x1) * 0.5 + 0.1, zz, hy, Vector3(x1 - x0 - 0.6, 0.03, 0.6), "mall_steel", {"solid": k == 0})
			for j in int((x1 - x0 - 0.8) / 0.55):
				if rng.randf() < 0.7:
					sh.box(x0 + 0.6 + j * 0.55, zz, hy + 0.2, Vector3(0.45, 0.38, 0.5), "plywood", {"tint": Color(0.72, 0.58, 0.4), "paint": 0.8}, rng.randf_range(-0.15, 0.15))
	for k2 in 6:
		sh.box(rng.randf_range(x0 + 0.8, x1 - 0.8), rng.randf_range(5.0, d - 2.0), 0.2, Vector3(0.5, 0.4, 0.45), "plywood", {"tint": Color(0.72, 0.58, 0.4), "paint": 0.8}, rng.randf() * TAU)
	# what happened: dragged in, left
	B.floor_decal(sh.P((x0 + x1) * 0.5, 7.5), Vector2(2.6, 2.6), sh.YAW(0.3), "blood_pool_drag", 1.0)
	B.floor_decal(sh.P(x0 - 2.2, 1.7), Vector2(4.0, 0.9), sh.YAW(0.0), "blood_drag_0", 0.95)
	B.floor_decal(sh.P(x0 - 6.0, 1.9), Vector2(4.0, 0.9), sh.YAW(0.1), "blood_drag_1", 0.9)
	var bb: Basis = sh._xf.basis * Basis(Vector3.UP, 0.3)
	S.box(Transform3D(bb, sh.P((x0 + x1) * 0.5, 9.5, 0.14)), Vector3(0.62, 0.26, 1.9), "mall_cloth", B.o({"tint": Color(0.08, 0.09, 0.1), "paint": 1.0, "layer": "int", "collide": true}))
	sh.loot((x0 + x1) * 0.5, 11.5, 0.02, "floor_contested")


# ------------------------------------------------------------------ light and mess

func _lights(lv: int, w: float, d: float) -> void:
	## A spot every 6.5 m down two lines where the store still has power; one flickering fitting in each faulty
	## stretch (its lens the downlight it replaces).
	var done_fault := {}
	for row in [4.4, 10.2]:
		var n := int(w / 6.5)
		for i in n:
			var x := (i + 0.5) * w / n
			var p: Vector3 = sh.P(x, row, L.CEIL - 0.03)
			var st := power_at(p)
			if st == B.POWER_DEAD:
				continue
			if st == B.POWER_FAULTY:
				var key := int(p.z / 6.0)
				if done_fault.has(key):
					continue
				done_fault[key] = true
				var best := -1
				var bd := 4.0
				for j in (B.downlights[lv] as Array).size():
					var q: Vector3 = (B.downlights[lv][j][0] as Transform3D).origin
					var dd := q.distance_squared_to(p)
					if dd < bd:
						bd = dd
						best = j
				if best >= 0:
					p = (B.downlights[lv][best][0] as Transform3D).origin
					B.downlights[lv][best][1] = B.POWER_LAMP
			mb.dyn.add_light({"pos": p, "kind": "down", "angle": 70.0, "color": Color(1.0, 0.94, 0.86), "energy": 2.6 if st == B.POWER_ON else 3.0, "range": 7.2,
				"fade": 32.0, "emitter": st == B.POWER_FAULTY, "fault": B.FAULTS[(i + lv) % 6] if st == B.POWER_FAULTY else "", "attenuation": 0.8})
			stats.lights += 1


func _mess(lv: int, w: float, d: float) -> void:
	## Clothes and boxes trodden over the floors, papers, dirt, blood; shopping bags dropped by the doors.
	for i in int(w * d / 22.0):
		var x := rng.randf_range(0.6, w - 0.6)
		var z := rng.randf_range(1.0, d - 0.6)
		var p: Vector3 = sh.P(x, z)
		var k := i % 7
		if k < 3:
			B.floor_decal(p, Vector2(2.4, 2.4), rng.randf() * TAU, ["floor_papers_0", "floor_grime_0", "floor_grime_1"][k], 0.85)
		elif k < 6:
			sh.box(x, z, 0.03, Vector3(0.45, 0.04, 0.55), "mall_cloth", {"tint": (PAL_LADIES + PAL_MEN)[rng.randi() % 12], "paint": 1.0}, rng.randf() * TAU)
		else:
			sh.box(x, z, 0.12, Vector3(0.4, 0.24, 0.3), "plywood", {"tint": Color(0.72, 0.58, 0.4), "paint": 0.8}, rng.randf() * TAU)
	for j in 4:
		var bp: Vector3 = sh.P(rng.randf_range(2.0, w - 2.0), rng.randf_range(3.0, d - 3.0))
		B.floor_decal(bp, Vector2(1.8, 1.8), rng.randf() * TAU, "b:%d" % (12 + j % 2), 0.95)
		var sd := rng.randf() * TAU
		B.floor_decal(bp + Vector3(cos(sd), 0, -sin(sd)) * 2.6, Vector2(3.6, 0.9), sd, "blood_steps", 0.85)
