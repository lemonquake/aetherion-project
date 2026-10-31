extends RefCounted
## (r15) Malasugue Mall's centrepieces and the furniture of its walks: the Grand Atrium's pink event stage (a lit
## gift-box frame, mannequins, rope barriers on brass posts) and lounge, its ceiling of white discs and spotlights with
## LED screens hung from it; the East Court's three-storey Christmas tree, gifts, icicle lights and garlands round
## every level; the West Court's planted island and benches; and along the concourses on every level: kiosks,
## planters, benches, bins, directory totems, hanging sale banners, and on Level 5 the food hall's tables.

var B = null
var mb = null
var L = null
var S = null
var rng := RandomNumberGenerator.new()
var stats := {"props": 0, "lights": 0}

const PINK := Color(0.96, 0.62, 0.72)
const GOLD := Color(0.86, 0.68, 0.32)


func _init(builder) -> void:
	B = builder
	mb = builder.mb
	L = builder.L
	S = builder.S
	rng.seed = 2412


func build() -> void:
	mb.dyn.interior_scope = true
	_grand_stage()
	_grand_lounge()
	_disc_ceiling()
	_screens()
	_christmas_tree()
	_icicles()
	_west_island()
	for lv in L.LEVELS:
		_concourse(lv)
	_food_hall()
	mb.dyn.interior_scope = false


# ------------------------------------------------------------------ helpers

func prop(name: String, p: Vector3, yaw: float = 0.0, dynamic: bool = false, lv: int = -1) -> void:
	if mb.models.spec(name).is_empty():
		return
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	if dynamic:
		mb.dyn.add_prop_spec(name, mb.dyn.seat(name, xf))
	else:
		mb.dyn.add_static_prop(name, mb.dyn.seat(name, xf))
	if lv >= 0:
		L.block_rect(lv, Vector2(p.x, p.z), Vector2(0.35, 0.35), 0.0, 0.2)
	stats.props += 1


func planter(lv: int, p: Vector2, big: bool = true) -> void:
	if lv == 0 and p.y < -28.0 and p.x > 5.0 and p.x < 20.0:
		return   # keep the damaged elevator lobby visible and its approaches open
	var y: float = L.level_y(lv)
	B.solid(lv, Vector3(p.x, y + 0.45, p.y), Vector3(1.2, 0.9, 1.2), "mall_satin", {"tint": Color(0.92, 0.9, 0.86), "paint": 1.0, "layer": "ext"})
	var yaw := rng.randf() * TAU
	if B.h01(int(p.x), int(p.y), 700 + lv) < 0.35:
		# (r16) the plant pulled out (or knocked off) and lying in its own soil, dead leaves round it
		var dir := Vector3(cos(yaw), 0, sin(yaw))
		B.floor_decal(Vector3(p.x, y, p.y) + dir * 1.2, Vector2(1.6, 1.3), yaw, "v:mud_%d" % (int(absf(p.x)) % 2), 0.9)
		_lying(("money_tree" if big else "plant_anthurium"), Vector3(p.x, y, p.y) + dir * 1.4, yaw)
		B.bx(Vector3(p.x, y + 0.6, p.y), Vector3(1.05, 0.02, 1.05), "dirt", {"layer": "int"})
		return
	B.bx(Vector3(p.x, y + 0.91, p.y), Vector3(1.05, 0.02, 1.05), "dirt", {"layer": "int"})
	prop("money_tree" if big else "plant_anthurium", Vector3(p.x, y + 0.9, p.y), yaw)


func _lying(name: String, p: Vector3, yaw: float) -> void:
	## (r16) A static model knocked onto its side (its local up along the floor, toward yaw).
	if mb.models.spec(name).is_empty():
		return
	var bas := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), -PI * 0.5)
	mb.dyn.add_static_prop(name, Transform3D(bas, p + Vector3(0, 0.25, 0)))
	stats.props += 1


func bench(lv: int, p: Vector2, yaw: float) -> void:
	if B.h01(int(p.x * 2.0), int(p.y * 2.0), 710 + lv) < 0.3:
		# (r16) tipped over onto its back (used as cover, then left)
		var bas := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), PI * 0.5)
		if not mb.models.spec("street_bench").is_empty():
			mb.dyn.add_static_prop("street_bench", Transform3D(bas, Vector3(p.x, L.level_y(lv) + 0.42, p.y)))
			L.block_rect(lv, p, Vector2(1.0, 0.5), -yaw, 0.2)
			stats.props += 1
		return
	prop("street_bench", Vector3(p.x, L.level_y(lv), p.y), yaw, false, lv)


func bin(lv: int, p: Vector2) -> void:
	var y: float = L.level_y(lv)
	if B.h01(int(p.x * 3.0), int(p.y * 3.0), 715 + lv) < 0.4:
		# (r16) kicked over, the rubbish spread out of it
		var a = B.h01(int(p.x), lv, 716) * TAU
		var ax := Vector3(cos(a), 0, -sin(a))
		S.cylinder(Vector3(p.x, y + 0.24, p.y) - ax * 0.45, ax, 0.9, 0.24, "mall_steel", B.o({"sides": 14, "collide": true, "layer": "int"}))
		B.floor_decal(Vector3(p.x, y, p.y) + ax * 1.2, Vector2(2.0, 2.0), a, "floor_papers_%d" % (lv % 2), 0.95)
		B.floor_decal(Vector3(p.x, y, p.y) + ax * 0.9, Vector2(1.6, 1.6), a + 1.0, "v:oil_0", 0.8)
		L.block_rect(lv, p, Vector2(0.5, 0.5), 0.0, 0.2)
		return
	S.cylinder(Vector3(p.x, y, p.y), Vector3.UP, 0.9, 0.24, "mall_steel", B.o({"sides": 14, "collide": true, "layer": "int"}))
	B.bx(Vector3(p.x, y + 0.91, p.y), Vector3(0.36, 0.03, 0.36), "mall_black", {"layer": "int"})
	L.block_rect(lv, p, Vector2(0.25, 0.25), 0.0, 0.2)


func ropes(lv: int, pts: Array) -> void:
	## Brass stanchions and velvet ropes along a path (a queue or a display barrier).
	var y: float = L.level_y(lv)
	for i in pts.size():
		var p: Vector2 = pts[i]
		S.cylinder(Vector3(p.x, y, p.y), Vector3.UP, 0.95, 0.03, "mall_metal_vc", B.o({"sides": 8, "tint": GOLD, "paint": 1.0, "layer": "int"}))
		S.cylinder(Vector3(p.x, y, p.y), Vector3.UP, 0.04, 0.16, "mall_metal_vc", B.o({"sides": 12, "tint": GOLD, "paint": 1.0, "layer": "int"}))
		if i > 0:
			var q: Vector2 = pts[i - 1]
			var m := (p + q) * 0.5
			S.box(Transform3D(Basis(Vector3.UP, B.seg_yaw(q, p)), Vector3(m.x, y + 0.82, m.y)), Vector3(p.distance_to(q), 0.04, 0.04), "velvet", B.o({"tint": Color(0.7, 0.08, 0.15), "paint": 0.9, "layer": "int"}))
		L.block_rect(lv, p, Vector2(0.15, 0.15), 0.0, 0.15)


# ------------------------------------------------------------------ the Grand Atrium

func _grand_stage() -> void:
	## A pink stage south of the escalators: a raised platform, a gift box drawn in light (a hexagonal frame with its
	## lid tipped open), mannequins in holiday colours, a ring of ropes.
	var c := Vector3(0, 0, 9.4)
	B.solid(0, c + Vector3(0, 0.15, 0), Vector3(9.0, 0.3, 4.4), "mall_gloss", {"tint": PINK, "paint": 1.0, "layer": "ext"}, 0.0, 0.2)
	B.bx(c + Vector3(0, 0.302, 0), Vector3(8.6, 0.004, 4.0), "boucle", {"tint": Color(1.0, 0.8, 0.86), "paint": 0.8, "layer": "int"})
	# the gift box: a hexagonal ring of light, pink panels, the bow on top
	var gc := c + Vector3(-1.6, 0.3, 0.2)
	for k in 6:
		var a0 := TAU * k / 6.0
		var a1 := TAU * (k + 1) / 6.0
		var p0 := gc + Vector3(cos(a0) * 1.4, 1.6 + sin(a0) * 1.4, 0.0)
		var p1 := gc + Vector3(cos(a1) * 1.4, 1.6 + sin(a1) * 1.4, 0.0)
		var mid := (p0 + p1) * 0.5
		S.box(Transform3D(Basis(Vector3(0, 0, 1), atan2(p1.y - p0.y, p1.x - p0.x)), mid), Vector3(p0.distance_to(p1), 0.16, 0.5), "mall_gloss", B.o({"tint": Color(0.98, 0.78, 0.82), "paint": 1.0, "layer": "mid"}))
		S.box(Transform3D(Basis(Vector3(0, 0, 1), atan2(p1.y - p0.y, p1.x - p0.x)), mid + Vector3(0, 0, -0.26)), Vector3(p0.distance_to(p1), 0.06, 0.02), "mall_light_warm", B.o({"layer": "mid"}))
	B.bx(gc + Vector3(0, 0.1, 0.3), Vector3(2.4, 0.2, 1.0), "mall_gloss", {"tint": PINK.darkened(0.1), "paint": 1.0})
	for s in [-1.0, 1.0]:
		S.box(Transform3D(Basis(Vector3(0, 0, 1), s * 0.6), gc + Vector3(s * 0.45, 3.25, 0.0)), Vector3(0.9, 0.5, 0.12), "mall_gloss", B.o({"tint": GOLD, "paint": 1.0, "layer": "mid"}))
	# mannequins on the stage
	var tops := [Color(0.75, 0.08, 0.12), Color(0.95, 0.94, 0.9), Color(0.1, 0.25, 0.5), Color(0.86, 0.68, 0.32)]
	var spots := [Vector2(1.2, -0.8), Vector2(2.4, 0.6), Vector2(3.4, -0.6), Vector2(-3.4, 1.0)]
	for i in spots.size():
		var p: Vector2 = spots[i]
		var myaw := PI + rng.randf_range(-0.5, 0.5)
		if i < 3:
			# (r16) knocked flat when the screen came down
			_mannequin(Vector3(c.x + p.x, 0.42, c.z + p.y), myaw, tops[i], Color(0.12, 0.12, 0.14), true)
		else:
			_mannequin(Vector3(c.x + p.x, 0.3, c.z + p.y), myaw, tops[i], Color(0.12, 0.12, 0.14))
	# gifts at the front of the stage
	for k2 in 7:
		var gcol: Color = [Color(0.85, 0.1, 0.15), Color(0.1, 0.5, 0.25), Color(0.95, 0.85, 0.3), Color(0.95, 0.95, 0.95)][k2 % 4]
		var sz := rng.randf_range(0.3, 0.6)
		B.bx(c + Vector3(-4.0 + k2 * 0.7, 0.3 + sz * 0.5, 1.6 + rng.randf_range(-0.2, 0.2)), Vector3(sz, sz, sz), "mall_gloss", {"tint": gcol, "paint": 1.0})
	# ropes round it
	ropes(0, [Vector2(-5.2, 6.6), Vector2(-5.2, 12.2), Vector2(-2.0, 12.6), Vector2(2.0, 12.6), Vector2(5.2, 12.2), Vector2(5.2, 6.6)])
	mb.dyn.add_light({"pos": c + Vector3(0, 4.2, 0), "kind": "lamp", "color": Color(1.0, 0.82, 0.86), "energy": 1.4, "range": 12.0, "emitter": false})
	stats.lights += 1


func _mannequin(p: Vector3, yaw: float, top: Color, bottom: Color, fallen: bool = false) -> void:
	var bas := Basis(Vector3.UP, yaw)
	if fallen:
		bas = bas * Basis(Vector3(1, 0, 0), PI * 0.5)
	var parts := [[Vector3(0, 0.02, 0), Vector3(0.4, 0.04, 0.4), "mall_steel", Color.WHITE], [Vector3(0, 0.4, 0), Vector3(0.03, 0.8, 0.03), "mall_steel", Color.WHITE],
		[Vector3(-0.09, 0.5, 0), Vector3(0.13, 0.85, 0.15), "mall_cloth", bottom], [Vector3(0.09, 0.5, 0), Vector3(0.13, 0.85, 0.15), "mall_cloth", bottom],
		[Vector3(0, 1.22, 0), Vector3(0.38, 0.55, 0.22), "mall_cloth", top], [Vector3(-0.24, 1.15, 0), Vector3(0.09, 0.6, 0.1), "mall_cloth", top],
		[Vector3(0.24, 1.15, 0), Vector3(0.09, 0.6, 0.1), "mall_cloth", top], [Vector3(0, 1.55, 0), Vector3(0.08, 0.1, 0.08), "mall_gloss", Color(0.96, 0.96, 0.95)],
		[Vector3(0, 1.7, 0.01), Vector3(0.17, 0.22, 0.2), "mall_gloss", Color(0.96, 0.96, 0.95)]]
	for q in parts:
		S.box(Transform3D(bas, p + bas * (q[0] as Vector3)), q[1], q[2], B.o({"tint": q[3], "paint": 1.0, "layer": "int"}))


func _grand_lounge() -> void:
	## North of the escalators: sofas round a low table and planters, a jewellery kiosk, an information desk.
	## (r16) The sofas were dragged off to the triage post that took over this spot (MallWreck): the planters stay.
	var c := Vector2(0, -9.6)
	for s in [-1.0, 1.0]:
		planter(0, Vector2(c.x + s * 6.0, c.y - 1.5))
	_kiosk(0, Vector2(0, -12.6), "jewelry")


func _kiosk(lv: int, p: Vector2, kind: String) -> void:
	## A free-standing kiosk: a ring of counters round a staff space, a canopy with the sign of a shop.
	var y: float = L.level_y(lv)
	var col := {"jewelry": Color(0.08, 0.08, 0.1), "phone": Color(0.1, 0.35, 0.7), "coffee": Color(0.3, 0.2, 0.14), "perfume": Color(0.95, 0.93, 0.95)}.get(kind, Color(0.2, 0.2, 0.2))
	var looted: bool = B.h01(int(p.x), int(p.y), 720 + lv) < 0.6
	if looted:
		B.floor_decal(Vector3(p.x, y, p.y), Vector2(4.2, 4.2), rng.randf() * TAU, "floor_glass", 0.9)
		B.floor_decal(Vector3(p.x + 1.6, y, p.y - 0.8), Vector2(2.4, 2.4), rng.randf() * TAU, "floor_papers_%d" % (lv % 2), 0.9)
	for k in 4:
		var a := PI * 0.5 * k
		var off := Vector2(cos(a), sin(a)) * 1.1
		var yaw := -a
		B.solid(lv, Vector3(p.x + off.x, y + 0.5, p.y + off.y), Vector3(0.6, 1.0, 1.6), "mall_gloss", {"tint": col, "paint": 1.0, "layer": "ext"}, yaw, 0.25)
		if looted and k % 2 == 0:
			for j2 in 3:
				var sp := Vector3(p.x + off.x * (1.9 + rng.randf()), y + 0.03, p.y + off.y * (1.9 + rng.randf())) + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
				B.bx(sp, Vector3(0.12, 0.05, 0.08), "mall_metal_vc", {"tint": GOLD if kind == "jewelry" else Color(0.15, 0.15, 0.18), "paint": 1.0, "layer": "int"})
			continue
		S.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x + off.x, y + 1.15, p.y + off.y)), Vector3(0.6, 0.3, 1.6), "mall_glass", B.o({"layer": "mid"}))
		S.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x + off.x, y + 1.02, p.y + off.y)), Vector3(0.5, 0.02, 1.5), "velvet" if kind == "jewelry" else "mall_satin", B.o({"tint": Color(0.3, 0.05, 0.1) if kind == "jewelry" else Color(0.9, 0.9, 0.9), "paint": 1.0, "layer": "int"}))
		for j in 6:
			var it := Vector3(p.x + off.x, y + 1.05, p.y + off.y) + Basis(Vector3.UP, yaw) * Vector3(0, 0, -0.6 + j * 0.24)
			B.bx(it, Vector3(0.08, 0.04, 0.08), "mall_metal_vc", {"tint": GOLD if kind == "jewelry" else Color(0.15, 0.15, 0.18), "paint": 1.0, "layer": "int"})
	# canopy on four slim posts
	for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		S.cylinder(Vector3(p.x + s.x * 1.35, y + 1.0, p.y + s.y * 1.35), Vector3.UP, 1.6, 0.03, "mall_steel", B.o({"sides": 8, "layer": "mid"}))
	B.bx(Vector3(p.x, y + 2.65, p.y), Vector3(3.1, 0.18, 3.1), "mall_gloss", {"tint": col, "paint": 1.0, "layer": "ext"})
	B.bx(Vector3(p.x, y + 2.55, p.y), Vector3(2.9, 0.02, 2.9), "mall_light_warm" if not looted else "mall_light_dead", {"layer": "mid"})
	mb.dyn.add_container(Vector3(p.x, y + 0.8, p.y), "store_counter", 0, Vector3(0.8, 0.6, 0.8))


func _disc_ceiling() -> void:
	## The Grand Atrium's ceiling (navy, 1.6 m above the roof line): white discs on a hex grid, small spotlights in the
	## gaps - the reference mall's ceiling.
	var gy: float = L.level_y(L.LEVELS - 1) + L.FH + 1.6
	var rr: Vector2 = L.GRAND_R + Vector2(0.4, 0.4)
	var discs: Array = []
	var spots: Array = []
	var row := 0
	var z := -rr.y
	while z <= rr.y:
		var x := -rr.x + (0.75 if row % 2 else 0.0)
		while x <= rr.x:
			if B.L.in_ellipse(Vector2(x, z), L.GRAND_C, rr):
				discs.append(Transform3D(Basis(), Vector3(x, gy - 0.06, z)))
				if rng.randf() < 0.45 and B.h01(int(x * 2.0), int(z * 2.0), 730) > 0.4:
					spots.append(Transform3D(Basis(), Vector3(x + 0.75, gy - 0.02, z + 0.65)))
			x += 1.5
		z += 1.3
		row += 1
	var dm := CylinderMesh.new()
	dm.top_radius = 0.56
	dm.bottom_radius = 0.56
	dm.height = 0.04
	dm.radial_segments = 20
	dm.rings = 1
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.92, 0.92, 0.9)
	wm.roughness = 0.85
	dm.material = wm
	var sm := CylinderMesh.new()
	sm.top_radius = 0.07
	sm.bottom_radius = 0.07
	sm.height = 0.02
	sm.radial_segments = 10
	sm.rings = 1
	sm.material = mb.mats.get_material("mall_light")
	for pair in [[dm, discs], [sm, spots]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = (pair[1] as Array).size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, pair[1][i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mi.name = "GrandCeiling"
		mb.root.add_child(mi)
	stats.discs = discs.size()


func _screens() -> void:
	## Two LED screens hung in the Grand Atrium (back to back over the escalators' ends), one in the West Court.
	var gy: float = L.level_y(L.LEVELS - 1) + L.FH + 1.6
	for s in [-1.0]:
		# (r16) the south screen came down on the stage (MallWreck); this one hangs on, glitching (tint g)
		var c := Vector3(0, 15.8, s * 12.4)
		B.bx(c, Vector3(9.2, 5.2, 0.3), "mall_black", {"layer": "ext"})
		S.atlas_quad(c + Vector3(0, 0, -s * 0.16), Vector3(-s, 0, 0), Vector3.UP, 9.0, 5.0, Rect2(0, 0, 0.5, 0.25), "mall_ads", {"layer": "ext", "tint": Color(0.3 + s * 0.2, 0.85, 0, 1)})
		S.atlas_quad(c + Vector3(0, 0, s * 0.16), Vector3(s, 0, 0), Vector3.UP, 9.0, 5.0, Rect2(0, 0, 0.5, 0.25), "mall_ads", {"layer": "ext", "tint": Color(0.55 + s * 0.2, 0.6, 0, 1)})
		for k in [-3.5, 3.5]:
			B.bx(Vector3(k, (15.8 + 2.6 + gy) * 0.5, s * 12.4), Vector3(0.03, gy - 18.4, 0.03), "mall_steel", {"layer": "mid"})
	var wc: Vector2 = L.WEST_COURT.get_center()
	var c2 := Vector3(wc.x, 13.0, L.WEST_COURT.end.y - 1.2)
	B.bx(c2, Vector3(7.2, 4.1, 0.3), "mall_black", {"layer": "ext"})
	S.atlas_quad(c2 + Vector3(0, 0, -0.16), Vector3(-1, 0, 0), Vector3.UP, 7.0, 3.9, Rect2(0, 0, 0.5, 0.25), "mall_ads", {"layer": "ext", "tint": Color(0.77, 0.35, 0, 1)})


# ------------------------------------------------------------------ the East Court

func _christmas_tree() -> void:
	## Three storeys of tree: tiers of green narrowing to a lit star, baubles and fairy lights, a red skirt and
	## presents, a rope ring.
	var c: Vector2 = L.EAST_C
	var h := 13.5
	var tiers := 9
	for k in tiers:
		var y0 := 0.6 + k * (h - 1.2) / tiers
		var r0 := lerpf(3.4, 0.35, float(k) / tiers)
		var r1 := lerpf(3.4, 0.35, float(k + 1) / tiers) * 0.55
		_cone(Vector3(c.x, y0, c.y), (h - 1.2) / tiers * 1.25, r0, r1, Color(0.06, 0.26, 0.12))
	S.cylinder(Vector3(c.x, 0, c.y), Vector3.UP, 0.7, 0.35, "walnut", B.o({"sides": 12, "collide": true}))
	S.cylinder(Vector3(c.x, 0, c.y), Vector3.UP, 0.25, 3.8, "mall_cloth", B.o({"sides": 28, "tint": Color(0.6, 0.06, 0.08), "paint": 1.0, "collide": true}))
	for lv in L.LEVELS:
		pass
	L.block_rect(0, c, Vector2(3.9, 3.9), 0.0, 0.3)
	S.col_box(Transform3D(Basis(), Vector3(c.x, h * 0.5, c.y)), Vector3(3.0, h, 3.0), "fabric", "tree")
	# baubles and fairy lights
	var baubles: Array = []
	var bcol: Array = []
	var fairy: Array = []
	var fairy_dead: Array = []
	for i in 420:
		var t := rng.randf()
		var y := 0.8 + t * (h - 1.6)
		var r := lerpf(3.3, 0.3, t) * rng.randf_range(0.82, 1.0)
		var a := rng.randf() * TAU
		var p := Vector3(c.x + cos(a) * r, y, c.y + sin(a) * r)
		if i % 3 == 0:
			baubles.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)), p))
			bcol.append([Color(0.85, 0.08, 0.12), Color(0.9, 0.72, 0.25), Color(0.85, 0.85, 0.9), Color(0.15, 0.3, 0.8)][i % 4])
		elif y < h * 0.55:
			fairy.append(Transform3D(Basis(), p))
		else:
			fairy_dead.append(Transform3D(Basis(), p))   # (r16) the top strings are out
	var bm := SphereMesh.new()
	bm.radius = 0.12
	bm.height = 0.24
	bm.radial_segments = 10
	bm.rings = 5
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.metallic = 0.7
	bmat.roughness = 0.2
	bm.material = bmat
	_mm(bm, baubles, bcol, "TreeBaubles")
	var fm := SphereMesh.new()
	fm.radius = 0.035
	fm.height = 0.07
	fm.radial_segments = 6
	fm.rings = 3
	fm.material = mb.mats.get_material("mall_light_warm")
	_mm(fm, fairy, [], "TreeLights")
	var fd: SphereMesh = fm.duplicate()
	fd.material = mb.mats.get_material("mall_light_dead")
	_mm(fd, fairy_dead, [], "TreeLightsDead")
	# the star
	for k2 in 5:
		var a2 := TAU * k2 / 5.0
		S.box(Transform3D(Basis(Vector3(0, 0, 1), a2), Vector3(c.x, h + 0.35, c.y)), Vector3(0.12, 0.9, 0.12), "mall_light_warm", B.o({"layer": "ext"}))
	mb.dyn.add_light({"pos": Vector3(c.x, h + 0.4, c.y), "kind": "lamp", "color": Color(1.0, 0.85, 0.5), "energy": 1.6, "range": 14.0, "emitter": false,
		"fault": "sag"})
	mb.dyn.add_light({"pos": Vector3(c.x + 3.0, 3.5, c.y), "kind": "lamp", "color": Color(1.0, 0.8, 0.55), "energy": 1.0, "range": 9.0, "emitter": false})
	# presents and the rope ring
	for k3 in 16:
		var a3 := TAU * k3 / 16.0 + rng.randf_range(-0.1, 0.1)
		var sz := rng.randf_range(0.35, 0.8)
		var gp := Vector3(c.x + cos(a3) * 3.95, sz * 0.5, c.y + sin(a3) * 3.95)
		var gcol: Color = [Color(0.85, 0.1, 0.15), Color(0.1, 0.5, 0.25), Color(0.95, 0.85, 0.3), Color(0.95, 0.95, 0.95), Color(0.2, 0.35, 0.8)][k3 % 5]
		S.box(Transform3D(Basis(Vector3.UP, a3), gp), Vector3(sz, sz, sz), "mall_gloss", B.o({"tint": gcol, "paint": 1.0, "layer": "int"}))
		S.box(Transform3D(Basis(Vector3.UP, a3), gp), Vector3(sz + 0.01, sz + 0.01, 0.06), "mall_gloss", B.o({"tint": GOLD, "paint": 1.0, "layer": "int"}))
	var ring := []
	for k4 in 13:
		var a4 := TAU * k4 / 12.0
		ring.append(c + Vector2(cos(a4), sin(a4)) * 5.4)
	ropes(0, ring)


func _cone(base: Vector3, h: float, r0: float, r1: float, col: Color) -> void:
	var sides := 18
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := base + Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p1 := base + Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var q1 := base + Vector3(cos(a1) * r1, h, sin(a1) * r1)
		var q0 := base + Vector3(cos(a0) * r1, h, sin(a0) * r1)
		var outn := Vector3(cos((a0 + a1) * 0.5), 0.6, sin((a0 + a1) * 0.5))
		S.quad(p0, p1, q1, q0, "mall_foliage", B.o({"tint": col.lightened(rng.randf() * 0.15), "paint": 1.0, "facing": outn, "layer": "ext", "tile": 0.9}))
	S.quad(base + Vector3(r0, 0, 0), base + Vector3(0, 0, r0), base + Vector3(-r0, 0, 0), base + Vector3(0, 0, -r0), "mall_foliage",
		B.o({"tint": col.darkened(0.3), "paint": 1.0, "facing": Vector3.DOWN, "layer": "ext"}))


func _mm(mesh: Mesh, xforms: Array, colors: Array, name: String) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.visibility_range_end = 160.0
	mi.name = name
	mb.root.add_child(mi)


func _icicles() -> void:
	## Strings of white icicle lights hanging under the East Court's slab edges on every level, and a garland of green
	## with red bows along its balustrade rails (the reference court's holiday dress).
	var dots: Array = []
	var dots_dead: Array = []
	var ec: Vector2 = L.EAST_C
	for lv in range(1, L.LEVELS):
		var y: float = L.level_y(lv) - 0.86
		var r: float = L.EAST_R + 0.06
		var n := int(TAU * r / 0.22)
		for i in n:
			var a := TAU * i / n
			var p := Vector2(ec.x + cos(a) * r, ec.y + sin(a) * r)
			var strand := 2 + (i * 7) % 6
			var lit_strand: bool = B.h01(i / 9, lv, 740) > 0.45
			for k in strand:
				(dots if lit_strand else dots_dead).append(Transform3D(Basis(), Vector3(p.x, y - 0.03 - k * 0.09, p.y)))
		# garland along the handrail
		var segs := 48
		for j in segs:
			var a0 := TAU * j / segs
			var a1 := TAU * (j + 1) / segs
			var gr: float = L.EAST_R - 0.2
			var p0 := Vector2(ec.x + cos(a0) * gr, ec.y + sin(a0) * gr)
			var p1 := Vector2(ec.x + cos(a1) * gr, ec.y + sin(a1) * gr)
			var m := (p0 + p1) * 0.5
			var gy: float = L.level_y(lv) + 1.0
			for tw in 3:
				var rot := Basis(Vector3.UP, B.seg_yaw(p0, p1)) * Basis(Vector3.RIGHT, tw * PI / 3.0 + rng.randf() * 0.3)
				S.box(Transform3D(rot, Vector3(m.x, gy, m.y)), Vector3(p0.distance_to(p1) + 0.12, 0.26, 0.05), "mall_foliage",
					B.o({"tint": Color(0.1, 0.32, 0.14).lightened(rng.randf() * 0.12), "paint": 1.0, "layer": "mid", "tile": 0.6}))
			if j % 4 == 0:
				B.bx(Vector3(m.x, L.level_y(lv) + 0.95, m.y), Vector3(0.22, 0.2, 0.26), "mall_gloss", {"tint": Color(0.8, 0.06, 0.1), "paint": 1.0, "layer": "mid"})
	var dm := SphereMesh.new()
	dm.radius = 0.022
	dm.height = 0.044
	dm.radial_segments = 6
	dm.rings = 3
	dm.material = mb.mats.get_material("mall_light")
	_mm(dm, dots, [], "Icicles")
	var dd: SphereMesh = dm.duplicate()
	dd.material = mb.mats.get_material("mall_light_dead")
	_mm(dd, dots_dead, [], "IciclesDead")
	stats.icicle_lights = dots.size()


# ------------------------------------------------------------------ the West Court and the concourses

func _west_island() -> void:
	## On the West Court's floor, round the escalators' foot: two planted beds with benches facing them.
	var wc: Vector2 = L.WEST_COURT.get_center()
	for s in [-1.0, 1.0]:
		var c := Vector2(wc.x, s * 8.5)
		B.solid(0, Vector3(c.x, 0.3, c.y), Vector3(8.0, 0.6, 3.0), "mall_granite", {"layer": "ext"})
		B.bx(Vector3(c.x, 0.61, c.y), Vector3(7.6, 0.02, 2.6), "lawn_leafy", {"layer": "int"})
		for k in 3:
			prop("money_tree", Vector3(c.x - 2.6 + k * 2.6, 0.6, c.y), rng.randf() * TAU)
		for k2 in 2:
			bench(0, Vector2(c.x - 2.0 + k2 * 4.0, c.y - s * 2.3), PI if s > 0.0 else 0.0)


func _concourse(lv: int) -> void:
	## The walks of one level: planters and benches along the court edges, bins, kiosks in the wide spots north and
	## south of the islands, a directory totem by each escalator landing, sale banners under the ceiling (Levels 1-3).
	var y: float = L.level_y(lv)
	for zs in [-1.0, 1.0]:
		for x in [-26.5, 26.5]:
			if lv < L.LEVELS - 1:
				_kiosk(lv, Vector2(x, zs * 27.5), ["phone", "coffee", "perfume", "jewelry"][int(absf(x) / 26.5 + (zs + 1.0)) % 4])
		for x2 in [-44.0, -12.0, 12.0, 40.0]:
			planter(lv, Vector2(x2, zs * 31.0), lv % 2 == 0)
			bench(lv, Vector2(x2 + 2.2, zs * 31.0), 0.0 if zs < 0.0 else PI)
			bin(lv, Vector2(x2 - 1.4, zs * 31.0))
	# directory totems by the escalator landings
	for bk in L.BANKS:
		for s in [-1.0, 1.0]:
			var x3 = float(bk.cx) + s * (L.ESC_RUN * 0.5 + 3.4)
			if lv == 0 and absf(float(bk.cx)) < 1.0:
				continue
			var p := Vector3(x3, y, s * -5.2)
			B.solid(lv, p + Vector3(0, 1.0, 0), Vector3(0.9, 2.0, 0.22), "mall_gloss", {"tint": Color(0.12, 0.14, 0.18), "paint": 1.0, "layer": "mid"})
			for f in [-1.0, 1.0]:
				S.atlas_quad(p + Vector3(0, 1.65, f * 0.115), Vector3(-f, 0, 0), Vector3.UP, 0.8, 0.4, Rect2(((8 + lv) % 4) * 0.25, ((8 + lv) / 4) * 0.25, 0.25, 0.25), "mall_wayfind", {"layer": "mid"})
				S.atlas_quad(p + Vector3(0, 1.1, f * 0.115), Vector3(-f, 0, 0), Vector3.UP, 0.8, 0.4, Rect2(0.75, 0.0, 0.25, 0.25) if lv < 4 else Rect2(0.0, 0.25, 0.25, 0.25), "mall_wayfind", {"layer": "mid"})
	# hanging banners
	if lv <= 2:
		var cy = y + L.CEIL - 1.3
		var k := lv
		for zs2 in [-1.0, 1.0]:
			for xb in [-40.0, -20.0, 20.0, 40.0]:
				var tile := (k + int(xb / 20.0) + 8) % 8
				if tile in [2, 5, 6]:
					tile = 0
				var p2 := Vector3(xb, cy, zs2 * 29.0)
				if B.h01(int(xb), lv * 2 + int(zs2 + 1.0), 760) < 0.35:
					# (r16) torn down, lying where it fell, trodden on
					var fy = B.h01(int(xb), lv, 761) * TAU
					S.atlas_quad(Vector3(xb, y + 0.012, zs2 * 29.0 + 0.6), Vector3(cos(fy), 0, -sin(fy)), Vector3(-sin(fy), 0, -cos(fy)), 0.75, 2.1,
						Rect2(tile * 0.125, 0, 0.125, 1.0), "mall_banners", {"layer": "int"})
					k += 1
					continue
				S.atlas_quad(p2, Vector3(1, 0, 0), Vector3.UP, 0.75, 2.1, Rect2(tile * 0.125, 0, 0.125, 1.0), "mall_banners", {"layer": "mid"})
				S.atlas_quad(p2 + Vector3(0, 0, -0.01), Vector3(-1, 0, 0), Vector3.UP, 0.75, 2.1, Rect2(tile * 0.125, 0, 0.125, 1.0), "mall_banners", {"layer": "mid"})
				B.bx(p2 + Vector3(0, 1.07, 0), Vector3(0.8, 0.03, 0.03), "mall_steel", {"layer": "mid"})
				B.bx(p2 + Vector3(0, 1.1 + (L.CEIL - 1.3 - 1.05) * 0.0 + 0.11, 0), Vector3(0.01, 0.2, 0.01), "mall_steel", {"layer": "mid"})
				k += 1


func _food_hall() -> void:
	## Level 5's food hall: tables north and south of the Grand Atrium and round the West Court, between the stalls.
	var lv: int = L.LEVELS - 1
	var y: float = L.level_y(lv)
	for zs in [-1.0, 1.0]:
		for i in 7:
			for k in 3:
				var x := -13.5 + i * 4.5
				var z = zs * (20.0 + k * 3.6)
				if B.L.in_ellipse(Vector2(x, z), L.GRAND_C, L.GRAND_R + Vector2(1.6, 1.6)):
					continue
				_table4(lv, Vector3(x, y, z))
	# the food hall sign over the north and south walks
	for zs2 in [-1.0, 1.0]:
		var p := Vector3(0, y + L.CEIL - 0.9, zs2 * 32.5)
		S.atlas_quad(p, Vector3(-zs2, 0, 0), Vector3.UP, 1.8, 3.4, Rect2(5 * 0.125, 0, 0.125, 1.0), "mall_banners", {"layer": "mid"})


func _table4(lv: int, p: Vector3) -> void:
	var mess: float = B.h01(int(p.x), int(p.z), 750)
	prop("round_table2", p + (Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5)) if mess < 0.6 else Vector3.ZERO), rng.randf() * 0.5 if mess < 0.6 else 0.0, true)
	for k in 4:
		var a := PI * 0.5 * k + PI * 0.25
		# chairs face +z unturned: turned to face the table; (r16) most shoved back or knocked over in the rush
		var cp := p + Vector3(cos(a) * 0.72, 0, sin(a) * 0.72)
		var cy := atan2(-cos(a), -sin(a))
		if mess < 0.6:
			cp += Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 1.4)
			cy += rng.randf_range(-1.2, 1.2)
			if rng.randf() < 0.45 and not mb.models.spec("dining_chair").is_empty():
				var bas := Basis(Vector3.UP, cy) * Basis(Vector3(1, 0, 0), PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0))
				mb.dyn.add_static_prop("dining_chair", Transform3D(bas, cp + Vector3(0, 0.22, 0)))
				stats.props += 1
				continue
		prop("dining_chair", cp, cy, true)
	L.block_rect(lv, Vector2(p.x, p.z), Vector2(0.9, 0.9), 0.0, 0.15)
