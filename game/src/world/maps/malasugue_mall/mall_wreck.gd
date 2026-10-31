extends RefCounted
## (r16) Malasugue Mall the morning after the outbreak reached it. Over every level's walks: litter (papers, bags,
## dropped shopping, cans, a shoe), dirt tracked about, blood (pools, bodies dragged to a door, bloody footprints
## walking away, spatter and handprints on walls and columns), ceilings come down (holes into the black void above,
## tiles hanging, cables and sparks, plaster dust, a leak), survivors' spray paint and notices taped up. Set pieces:
## the Grand Atrium's south LED screen fallen across the holiday stage, a triage post where the lounge was, barricades
## (the Level 3 restrooms, the Level 5 cinema), a shop on Level 4 burnt out and still smoking, and outside the main
## entrance a checkpoint that failed: wrecked and burnt cars, barriers, sandbags, police tape. In the shops: their
## stock on the floor, papers, blood.
##
## Anything that collides (and every dynamic prop, whose ids the server and the clients must agree on) is placed with
## rng, the same on every machine; things only drawn use vr. Decals never collide.

var B = null
var mb = null
var L = null
var S = null
var rng := RandomNumberGenerator.new()
var vr := RandomNumberGenerator.new()
var stats := {"decals": 0, "litter": 0, "blood": 0, "ceiling": 0, "writing": 0, "props": 0, "barricades": 0, "sparks": 0}

const SPRAY := ["spray_00", "spray_01", "spray_02", "spray_03", "spray_04", "spray_05", "spray_06", "spray_07", "spray_08", "spray_09", "spray_11",
	"spray_12", "spray_13", "v:eerie_02", "v:eerie_04", "v:hands_red", "v:x_red", "v:tally", "bloodtext_0", "bloodtext_3"]
const NOTICES := ["notice_evac", "notice_closed", "notice_relief", "notice_missing", "v:poster_02"]
const BAG_COLS := [Color(0.85, 0.15, 0.2), Color(0.95, 0.95, 0.92), Color(0.15, 0.3, 0.6), Color(0.92, 0.7, 0.2), Color(0.1, 0.1, 0.1), Color(0.6, 0.2, 0.5)]
const SPARK_TEX := "res://assets/fx/fx_spark.png"
const SMOKE_TEX := "res://assets/fx/fx_smoke.png"


func _init(builder) -> void:
	B = builder
	mb = builder.mb
	L = builder.L
	S = builder.S
	rng.seed = 161616
	vr.seed = 616161


func build() -> void:
	mb.dyn.interior_scope = true
	_fallen_screen()
	_triage()
	for lv in L.LEVELS:
		_litter(lv)
		_blood(lv)
		_ceilings(lv)
		_walls(lv)
	_barricades()
	_burnt_shop()
	_rooms()
	mb.dyn.interior_scope = false
	_outside()


# ------------------------------------------------------------------ helpers

func walk_point(lv: int, tries: int = 30) -> Vector2:
	## A random open spot on a level's walks (not in a shop, not in a wall or fitting), or INF.
	for i in tries:
		var p := Vector2(rng.randf_range(-L.MX + 2.0, L.MX - 2.0), rng.randf_range(-L.MZ + 2.0, L.MZ - 2.0))
		if not B.is_walk(lv, p):
			continue
		var c: Vector2i = L.nav_cell(p)
		if (L.nav_open[lv] as PackedByteArray)[c.y * L.nav_nx + c.x] == 0:
			continue
		return p
	return Vector2.INF


func clear_of_ways(lv: int, p: Vector2, r: float = 2.6) -> bool:
	## Away from the ways through: escalator ends, the fire doors, the entrances, the department store's stairs.
	for e in L.escalators:
		for q in [e.a, e.b]:
			var v: Vector3 = q
			if absf(v.y - L.level_y(lv)) < 0.5 and Vector2(v.x, v.z).distance_to(p) < r + 1.5:
				return false
	for c in L.CORES:
		var cr: Rect2 = c
		var inner_z := cr.end.y if cr.position.y < 0.0 else cr.position.y
		if Vector2(cr.position.x + 1.0, inner_z).distance_to(p) < r + 0.5:
			return false
	if lv == 0:
		for e2 in L.entrances:
			if (e2.hall as Rect2).grow(2.0).has_point(p):
				return false
	return true


func roomy(lv: int, p: Vector2, r: float = 2.4) -> bool:
	## Open walk all round p (eight directions r away): something solid here leaves the way past it.
	for k in 8:
		var q := p + Vector2(cos(TAU * k / 8.0), sin(TAU * k / 8.0)) * r
		if not B.is_walk(lv, q) or not open_cell(lv, q):
			return false
	return true


func open_cell(lv: int, p: Vector2) -> bool:
	var c: Vector2i = L.nav_cell(p)
	return (L.nav_open[lv] as PackedByteArray)[c.y * L.nav_nx + c.x] == 1


func decal(p: Vector3, size: Vector2, name: String, alpha: float = 1.0, yaw: float = NAN) -> void:
	B.floor_decal(p, size, vr.randf() * TAU if is_nan(yaw) else yaw, name, alpha)
	stats.decals += 1


func static_prop(name: String, xf: Transform3D, lv: int = -1, half: Vector2 = Vector2.ZERO) -> void:
	if mb.models.spec(name).is_empty():
		return
	mb.dyn.add_static_prop(name, xf)
	if lv >= 0 and half != Vector2.ZERO:
		L.block_rect(lv, Vector2(xf.origin.x, xf.origin.z), half, 0.0, 0.2)
	stats.props += 1


func loose(name: String, p: Vector3, yaw: float) -> void:
	## A dynamic prop (it can be kicked, shot, thrown): placed with rng only.
	if mb.models.spec(name).is_empty():
		return
	mb.dyn.add_prop_spec(name, mb.dyn.seat(name, Transform3D(Basis(Vector3.UP, yaw), p)))
	stats.props += 1


func tipped(name: String, p: Vector3, yaw: float, lift: float = 0.3, axis: Vector3 = Vector3(0, 0, 1)) -> void:
	## A static model lying on its side.
	if mb.models.spec(name).is_empty():
		return
	mb.dyn.add_static_prop(name, Transform3D(Basis(Vector3.UP, yaw) * Basis(axis, PI * 0.5), p + Vector3(0, lift, 0)))
	stats.props += 1


func shopping_bag(p: Vector3, yaw: float, fallen: bool) -> void:
	## A paper shopping bag (drawn only): a box with a handle, standing or on its side spilling.
	var col: Color = BAG_COLS[vr.randi() % BAG_COLS.size()]
	var bas := Basis(Vector3.UP, yaw)
	if fallen:
		bas = bas * Basis(Vector3(1, 0, 0), PI * 0.5)
	var c := p + Vector3(0, 0.07 if fallen else 0.2, 0)
	S.box(Transform3D(bas, c), Vector3(0.34, 0.4, 0.13), "mall_satin", B.o({"tint": col, "paint": 1.0, "layer": "int"}))
	S.box(Transform3D(bas, c + bas * Vector3(0, 0.24, 0)), Vector3(0.16, 0.08, 0.01), "mall_black", B.o({"layer": "int"}))
	if fallen:
		for k in 2:
			S.box(Transform3D(Basis(Vector3.UP, vr.randf() * TAU), p + bas * Vector3(vr.randf_range(-0.2, 0.2), 0.4 + k * 0.15, 0) * Vector3(1, 0, 1) + Vector3(0, 0.03, 0)),
				Vector3(0.24, 0.05, 0.3), "mall_cloth", B.o({"tint": BAG_COLS[vr.randi() % BAG_COLS.size()], "paint": 1.0, "layer": "int"}))


func cart(lv: int, p: Vector3, yaw: float, on_side: bool) -> void:
	## A supermarket trolley (the mall's own, red handle): wire basket of rods, chassis, castors. Collides as a box.
	var bas := Basis(Vector3.UP, yaw)
	if on_side:
		bas = bas * Basis(Vector3(0, 0, 1), PI * 0.5)
	var at := func(o: Vector3) -> Vector3: return p + bas * o + Vector3(0, 0.29 if on_side else 0.0, 0)
	var steel = B.o({"layer": "int"})
	# basket: rails top and bottom, uprights, the floor of it
	for hy in [0.48, 0.98]:
		for s in [-1.0, 1.0]:
			S.box(Transform3D(bas, at.call(Vector3(s * 0.27, hy, 0))), Vector3(0.012, 0.012, 0.9), "mall_chrome", steel)
		for e in [-0.45, 0.45]:
			S.box(Transform3D(bas, at.call(Vector3(0, hy, e))), Vector3(0.55, 0.012, 0.012), "mall_chrome", steel)
	for k in 7:
		var zz := -0.45 + k * 0.15
		for s2 in [-1.0, 1.0]:
			S.box(Transform3D(bas, at.call(Vector3(s2 * 0.27, 0.73, zz))), Vector3(0.008, 0.5, 0.008), "mall_chrome", steel)
	for k2 in 5:
		S.box(Transform3D(bas, at.call(Vector3(-0.22 + k2 * 0.11, 0.73, 0.45))), Vector3(0.008, 0.5, 0.008), "mall_chrome", steel)
	S.box(Transform3D(bas, at.call(Vector3(0, 0.48, 0))), Vector3(0.54, 0.008, 0.9), "mall_steel", steel)
	# chassis, castors, the red handle
	for s3 in [-1.0, 1.0]:
		S.box(Transform3D(bas, at.call(Vector3(s3 * 0.22, 0.14, 0.0))), Vector3(0.025, 0.025, 0.95), "mall_steel", steel)
		for e2 in [-0.42, 0.42]:
			S.cylinder(at.call(Vector3(s3 * 0.22, 0.05, e2)) - bas * Vector3(0.02, 0, 0), bas * Vector3(1, 0, 0), 0.04, 0.05, "mall_black", B.o({"sides": 8, "layer": "int"}))
			S.box(Transform3D(bas, at.call(Vector3(s3 * 0.22, 0.31, e2))), Vector3(0.02, 0.34, 0.02), "mall_steel", steel)
	S.box(Transform3D(bas, at.call(Vector3(0, 1.02, -0.52))), Vector3(0.56, 0.04, 0.04), "mall_satin", B.o({"tint": Color(0.75, 0.08, 0.1), "paint": 1.0, "layer": "int"}))
	S.col_box(Transform3D(bas, at.call(Vector3(0, 0.5, 0))), Vector3(0.56, 1.0, 0.95), "steel", "cart")
	L.block_rect(lv, Vector2(p.x, p.z), Vector2(0.5, 0.6), -yaw, 0.2)
	# some still have someone's shopping in them
	if not on_side and vr.randf() < 0.6:
		for j in 3:
			shopping_bag(at.call(Vector3(vr.randf_range(-0.12, 0.12), 0.5, -0.25 + j * 0.25)), yaw + vr.randf_range(-0.4, 0.4), false)
	stats.carts = int(stats.get("carts", 0)) + 1


func backpack(p: Vector3, yaw: float) -> void:
	var col: Color = [Color(0.1, 0.12, 0.2), Color(0.5, 0.1, 0.12), Color(0.2, 0.3, 0.2), Color(0.12, 0.12, 0.12)][vr.randi() % 4]
	var bas := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), PI * 0.5)
	S.box(Transform3D(bas, p + Vector3(0, 0.1, 0)), Vector3(0.32, 0.44, 0.2), "mall_cloth", B.o({"tint": col, "paint": 1.0, "layer": "int"}))
	S.box(Transform3D(bas, p + Vector3(0, 0.1, 0) + bas * Vector3(0, -0.06, 0.12)), Vector3(0.26, 0.2, 0.06), "mall_cloth", B.o({"tint": col.darkened(0.25), "paint": 1.0, "layer": "int"}))


func tape(lv: int, a: Vector2, b: Vector2, h: float = 1.0, police: bool = true) -> void:
	## Hazard or police tape between two points (sagging a little), both faces.
	var y: float = L.level_y(lv) + h
	var m := (a + b) * 0.5
	var d := b - a
	var len := d.length()
	if len < 0.2:
		return
	var right := Vector3(d.x, -0.04, d.y).normalized()
	var nm := "tape_police" if police else "tape_caution"
	for s in [1.0, -1.0]:
		S.atlas_quad(Vector3(m.x, y - 0.05, m.y), right * s, Vector3.UP, len, 0.08, B.cell(nm), B.APOC, {"layer": "int"})


func post(lv: int, p: Vector2, h: float = 1.0) -> void:
	S.cylinder(Vector3(p.x, L.level_y(lv), p.y), Vector3.UP, h, 0.03, "mall_metal_vc", B.o({"sides": 8, "tint": Color(0.95, 0.75, 0.1), "paint": 1.0, "layer": "int"}))
	S.cylinder(Vector3(p.x, L.level_y(lv), p.y), Vector3.UP, 0.05, 0.16, "mall_black", B.o({"sides": 10, "layer": "int"}))


func sparks(p: Vector3, every: float = 2.6) -> void:
	## A shorted cable spitting sparks now and then, with the flash of light that goes with each burst.
	stats.sparks += 1
	mb.dyn.add_light({"pos": p + Vector3(0, -0.1, 0), "kind": "bulb", "color": Color(0.75, 0.85, 1.0), "energy": 1.6, "range": 6.0, "fault": "starter",
		"fade": 30.0, "emitter": false})
	if not S.visual:
		return
	var gp := GPUParticles3D.new()
	gp.amount = 22
	gp.lifetime = every
	gp.explosiveness = 0.96
	gp.randomness = 0.4
	gp.fixed_fps = 30
	gp.position = p
	gp.visibility_aabb = AABB(Vector3(-3, -5, -3), Vector3(6, 6, 6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.8
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.6, 1.0))
	ramp.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	# each spark lives a fraction of the cycle: most of the cycle nothing shows
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.12, 0.6))
	curve.add_point(Vector2(0.18, 0.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	gp.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = load(SPARK_TEX)
	m.albedo_color = Color(1.0, 0.85, 0.6) * 2.0
	q.material = m
	gp.draw_pass_1 = q
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_range_end = 45.0
	gp.name = "MallSparks"
	mb.root.add_child(gp)


func smoke(_p: Vector3, _size: Vector3) -> void:
	# The fire is out. No ambient smoke or fog volumes in Malasugue Mall.
	pass


# ------------------------------------------------------------------ the Grand Atrium

func _fallen_screen() -> void:
	## The south LED screen's cables gave: it came down across the holiday stage, propped on the gift-box frame,
	## face down. Its cables still hang from the ceiling, one end sparking; broken modules and glass all round.
	var c := Vector3(0.2, 1.62, 11.7)
	var bas := Basis(Vector3.UP, 0.12) * Basis(Vector3(1, 0, 0), -1.0) * Basis(Vector3(0, 0, 1), 0.07)
	S.box(Transform3D(bas, c), Vector3(9.2, 5.2, 0.3), "mall_black", B.o({"layer": "ext", "collide": true}))
	# the steel frame on its back, now facing up, and a corner torn open
	for k in 5:
		S.box(Transform3D(bas, c + bas * Vector3(-3.6 + k * 1.8, 0, 0.17)), Vector3(0.08, 5.0, 0.05), "mall_steel", B.o({"layer": "mid"}))
	S.box(Transform3D(bas, c + bas * Vector3(0, 1.4, 0.17)), Vector3(9.0, 0.08, 0.05), "mall_steel", B.o({"layer": "mid"}))
	S.box(Transform3D(bas, c + bas * Vector3(0, -1.4, 0.17)), Vector3(9.0, 0.08, 0.05), "mall_steel", B.o({"layer": "mid"}))
	L.block_rect(0, Vector2(c.x, c.z), Vector2(4.8, 2.7), -0.1, 0.3)
	# its hangers' cables, down from the roof, one end sparking
	var gy: float = L.level_y(L.LEVELS - 1) + L.FH + 1.6
	for k2 in [-3.5, 3.5]:
		var top := Vector3(k2, gy, 12.4)
		var lowp := Vector3(k2 + 0.6, 6.5 + absf(k2) * 0.3, 12.0)
		S.box(Transform3D(Basis.looking_at((lowp - top).normalized(), Vector3.RIGHT), (top + lowp) * 0.5), Vector3(0.03, 0.03, top.distance_to(lowp)), "mall_steel", B.o({"layer": "mid"}))
	sparks(Vector3(-3.9, 0.9, 13.4), 3.1)
	for i in 26:
		var p := Vector3(vr.randf_range(-6.0, 6.5), 0.0, vr.randf_range(7.0, 16.5))
		if p.z < 11.6 and absf(p.x) < 4.5:
			p.y = 0.3   # on the stage
		S.box(Transform3D(Basis(Vector3.UP, vr.randf() * TAU), p + Vector3(0, 0.025, 0)), Vector3(0.32, 0.05, 0.16), "mall_black", B.o({"layer": "int"}))
	decal(Vector3(1.0, 0.0, 14.6), Vector2(5.5, 4.0), "floor_glass", 1.0)
	decal(Vector3(-4.6, 0.0, 13.8), Vector2(3.0, 3.0), "floor_dust", 0.9)
	decal(Vector3(5.2, 0.0, 13.2), Vector2(3.0, 3.0), "floor_glass", 0.9)
	# someone under it: a pool spreading out from the edge
	decal(Vector3(-1.6, 0.0, 14.2), Vector2(2.6, 2.6), "b:12", 0.95)
	decal(Vector3(-1.2, 0.0, 15.6), Vector2(1.2, 1.2), "b:9", 0.9)
	tape(0, Vector2(-6.5, 7.0), Vector2(-6.5, 17.0))
	tape(0, Vector2(-6.5, 17.0), Vector2(6.8, 17.0))
	for q in [Vector2(-6.5, 7.0), Vector2(-6.5, 17.0), Vector2(6.8, 17.0)]:
		post(0, q)
		L.block_rect(0, q, Vector2(0.15, 0.15), 0.0, 0.15)


func _triage() -> void:
	## Where the atrium lounge was: a triage post set up in the first hours, then abandoned. Cots in two rows behind
	## sheet screens, drip stands, a table of supplies, body bags, blood under the beds, police tape round it all.
	var lv := 0
	var cots := []
	for xc in [-2.3, 2.3]:
		for zc in [-6.1, -7.9, -9.7]:
			cots.append(Vector2(xc, zc))
	for i in cots.size():
		var p: Vector2 = cots[i]
		var yaw := rng.randf_range(-0.08, 0.08)
		var bas := Basis(Vector3.UP, yaw)
		# a folding frame and a thin mattress, a sheet thrown back
		S.box(Transform3D(bas, Vector3(p.x, 0.44, p.y)), Vector3(1.95, 0.08, 0.78), "mall_cloth", B.o({"tint": Color(0.3, 0.42, 0.32), "paint": 1.0, "layer": "int", "collide": true}))
		for sx in [-0.9, 0.9]:
			for sz in [-0.34, 0.34]:
				S.box(Transform3D(bas, Vector3(p.x, 0.2, p.y) + bas * Vector3(sx, 0, sz)), Vector3(0.03, 0.4, 0.03), "mall_steel", B.o({"layer": "int"}))
		S.box(Transform3D(bas * Basis(Vector3(0, 0, 1), rng.randf_range(-0.1, 0.1)), Vector3(p.x + 0.4, 0.5, p.y)), Vector3(1.0, 0.03, 0.8),
			"mall_cloth", B.o({"tint": Color(0.92, 0.92, 0.9), "paint": 1.0, "layer": "int"}))
		L.block_rect(lv, p, Vector2(1.0, 0.4), -yaw, 0.2)
		if i % 2 == 0:
			decal(Vector3(p.x, 0.0, p.y), Vector2(1.6, 1.6), "b:13", 0.9)
			decal(Vector3(p.x + 0.5, 0.48, p.y), Vector2(0.6, 0.6), "b:%d" % (8 + i % 2), 0.9)
		# a drip stand by the head of the bed, its bag still hanging
		var ds := Vector3(p.x - 1.1 * signf(p.x + 0.01), 0.0, p.y + 0.5)
		S.cylinder(ds, Vector3.UP, 1.9, 0.012, "mall_chrome", B.o({"sides": 6, "layer": "int"}))
		S.cylinder(ds, Vector3.UP, 0.03, 0.22, "mall_chrome", B.o({"sides": 6, "layer": "int"}))
		S.box(Transform3D(Basis(), ds + Vector3(0.06, 1.75, 0)), Vector3(0.1, 0.18, 0.04), "mall_glass", B.o({"layer": "int"}))
	# sheet screens between the rows, one pulled half down
	for zc2 in [-5.0, -7.0, -8.8, -10.6]:
		S.box(Transform3D(Basis(), Vector3(0.0, 1.0, zc2)), Vector3(0.02, 1.7, 1.6), "mall_cloth", B.o({"tint": Color(0.86, 0.88, 0.86), "paint": 1.0, "layer": "int"}))
	B.wall_decal(Vector3(0.012, 1.1, -7.0), Vector3(1, 0, 0), Vector2(1.2, 0.8), "blood_hands_0", 0.9)
	B.wall_decal(Vector3(-0.012, 1.2, -8.8), Vector3(-1, 0, 0), Vector2(1.4, 0.7), "blood_spatter", 0.95)
	L.block_seg(lv, Vector2(0, -4.2), Vector2(0, -11.4), 0.1, 0.25)
	# a supplies table, boxes of gloves and gauze, a medical case open on the floor
	S.box(Transform3D(Basis(), Vector3(-4.5, 0.74, -11.2)), Vector3(1.8, 0.05, 0.75), "mall_satin", B.o({"tint": Color(0.85, 0.85, 0.83), "paint": 1.0, "layer": "int", "collide": true}))
	for sx2 in [-0.8, 0.8]:
		S.box(Transform3D(Basis(), Vector3(-4.5 + sx2, 0.37, -11.2)), Vector3(0.04, 0.72, 0.65), "mall_steel", B.o({"layer": "int"}))
	for k in 6:
		S.box(Transform3D(Basis(Vector3.UP, vr.randf()), Vector3(-5.2 + k * 0.28, 0.82, -11.2 + vr.randf_range(-0.2, 0.2))), Vector3(0.22, 0.12, 0.14),
			"mall_satin", B.o({"tint": [Color(0.3, 0.55, 0.9), Color(0.95, 0.95, 0.95), Color(0.9, 0.3, 0.3)][k % 3], "paint": 1.0, "layer": "int"}))
	L.block_rect(lv, Vector2(-4.5, -11.2), Vector2(0.95, 0.4), 0.0, 0.2)
	loose("medical_box", Vector3(-3.6, 0.0, -10.4), 0.6)
	loose("medical_box", Vector3(4.6, 0.0, -6.0), 2.1)
	loose("wheelchair", Vector3(4.4, 0.0, -10.6), 2.6)
	loose("extinguisher", Vector3(-4.2, 0.0, -5.4), 0.0)
	# two body bags laid out by the screens
	for bp in [Vector2(-4.4, -8.4), Vector2(4.5, -8.6)]:
		var bb := Basis(Vector3.UP, 0.08 * signf(bp.x))
		S.box(Transform3D(bb, Vector3(bp.x, 0.14, bp.y)), Vector3(0.62, 0.26, 1.9), "mall_cloth", B.o({"tint": Color(0.08, 0.09, 0.1), "paint": 1.0, "layer": "int", "collide": true}))
		S.box(Transform3D(bb, Vector3(bp.x, 0.2, bp.y - 0.62)), Vector3(0.42, 0.18, 0.5), "mall_cloth", B.o({"tint": Color(0.07, 0.08, 0.09), "paint": 1.0, "layer": "int"}))
		S.box(Transform3D(bb, Vector3(bp.x + 0.12, 0.28, bp.y)), Vector3(0.02, 0.01, 1.7), "mall_steel", B.o({"layer": "int"}))
		L.block_rect(lv, bp, Vector2(0.35, 1.0), 0.0, 0.2)
	decal(Vector3(4.2, 0.0, -9.6), Vector2(3.8, 1.0), "blood_drag_1", 0.9, PI * 0.5)
	# the stencilled board and the tape round it
	S.box(Transform3D(Basis(Vector3.UP, 0.3), Vector3(-5.6, 0.9, -4.6)), Vector3(1.2, 1.0, 0.03), "plywood", B.o({"layer": "int", "tint": Color(0.75, 0.72, 0.65), "paint": 0.3}))
	B.wall_decal(Vector3(-5.6, 0.9, -4.6) + Vector3(sin(0.3), 0, cos(0.3)) * 0.02, Vector3(sin(0.3), 0, cos(0.3)), Vector2(1.1, 0.55), "quarantine", 1.0)
	for k2 in 2:
		S.box(Transform3D(Basis(Vector3.UP, 0.3) * Basis(Vector3(1, 0, 0), 0.25 * (1 - k2 * 2)), Vector3(-5.6, 0.45, -4.6) + Basis(Vector3.UP, 0.3) * Vector3(0, 0, 0.18 * (1 - k2 * 2))),
			Vector3(1.1, 0.9, 0.02), "plywood", B.o({"layer": "int", "tint": Color(0.7, 0.66, 0.58), "paint": 0.3}))
	var ring := [Vector2(-6.2, -4.3), Vector2(6.2, -4.3), Vector2(6.2, -11.6)]
	for k3 in ring.size():
		post(lv, ring[k3])
		L.block_rect(lv, ring[k3], Vector2(0.15, 0.15), 0.0, 0.15)
		if k3 > 0:
			tape(lv, ring[k3 - 1], ring[k3], 1.0, false)
	# what they left on the floor
	for k4 in 6:
		decal(Vector3(vr.randf_range(-5.5, 5.5), 0.0, vr.randf_range(-11.0, -4.8)), Vector2(1.6, 1.6), ["floor_papers_0", "floor_grime_1", "b:%d" % (vr.randi() % 4)][k4 % 3], 0.85)


# ------------------------------------------------------------------ the walks of every level

func _litter(lv: int) -> void:
	## Papers and dirt over the floor, dropped shopping, bags of rubbish, cans, a shoe or a suitcase.
	var y: float = L.level_y(lv)
	for i in 72:
		var p := walk_point(lv)
		if p == Vector2.INF:
			continue
		var k := i % 7
		var nm = ["floor_papers_0", "floor_papers_1", "floor_grime_0", "floor_grime_1", "floor_papers_0", "v:oil_%d" % (i % 3), "floor_dust"][k]
		var s := vr.randf_range(2.2, 4.0) if k < 4 else vr.randf_range(1.6, 2.8)
		decal(Vector3(p.x, y, p.y), Vector2(s, s), nm, vr.randf_range(0.8, 1.0))
	# shopping carts, pushed about or on their sides
	for c in 7:
		var cp := walk_point(lv)
		if cp == Vector2.INF or not clear_of_ways(lv, cp) or not roomy(lv, cp):
			continue
		cart(lv, Vector3(cp.x, y, cp.y), rng.randf() * TAU, rng.randf() < 0.35)
	# what people dropped when they ran: a suitcase, a backpack, shoes, a phone
	for b in 5:
		var bp := walk_point(lv)
		if bp == Vector2.INF or not clear_of_ways(lv, bp) or not roomy(lv, bp, 1.8):
			continue
		loose("suitcase", Vector3(bp.x, y, bp.y), rng.randf() * TAU)
		backpack(Vector3(bp.x + vr.randf_range(-0.8, 0.8), y, bp.y + vr.randf_range(-0.8, 0.8)), vr.randf() * TAU)
		for s2 in 2:
			S.box(Transform3D(Basis(Vector3.UP, vr.randf() * TAU), Vector3(bp.x + vr.randf_range(-1.5, 1.5), y + 0.05, bp.y + vr.randf_range(-1.5, 1.5))),
				Vector3(0.11, 0.1, 0.28), "leather", B.o({"tint": BAG_COLS[vr.randi() % BAG_COLS.size()], "paint": 0.6, "layer": "int"}))
		S.box(Transform3D(Basis(Vector3.UP, vr.randf() * TAU), Vector3(bp.x + vr.randf_range(-1.0, 1.0), y + 0.006, bp.y + vr.randf_range(-1.0, 1.0))),
			Vector3(0.075, 0.01, 0.15), "mall_black", B.o({"layer": "int"}))
	for i2 in 40:
		var p2 := walk_point(lv)
		if p2 == Vector2.INF:
			continue
		var pos := Vector3(p2.x, y, p2.y)
		match i2 % 6:
			0, 3:
				static_prop("litter_a" if i2 % 2 == 0 else "litter_b", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), pos))
			1:
				if clear_of_ways(lv, p2):
					loose("trashbag", pos, rng.randf() * TAU)
			2:
				shopping_bag(pos, vr.randf() * TAU, vr.randf() < 0.6)
				shopping_bag(pos + Vector3(vr.randf_range(-0.5, 0.5), 0, vr.randf_range(-0.5, 0.5)), vr.randf() * TAU, true)
			4:
				loose("can", pos, rng.randf() * TAU)
				loose("bottle", pos + Vector3(0.4, 0, 0.2), rng.randf() * TAU)
			5:
				if clear_of_ways(lv, p2):
					loose(["box", "suitcase", "boots", "crate_plastic", "box", "wet_floor_sign"][(i2 / 6 + lv) % 6], pos, rng.randf() * TAU)
		stats.litter += 1


func _blood(lv: int) -> void:
	## Stories in blood: bodies dragged off toward a door, pools where someone fell (and the prints of whoever walked
	## through it), spatter on the nearest wall.
	var y: float = L.level_y(lv)
	for i in 5:
		var p := walk_point(lv)
		if p == Vector2.INF:
			continue
		var dir := vr.randf() * TAU
		var fwd := Vector2(cos(dir), -sin(dir))
		decal(Vector3(p.x, y, p.y), Vector2(2.8, 2.8), "blood_pool_drag", 1.0, dir)
		var q := p + fwd * 2.2
		for k in 1 + vr.randi() % 3:
			if not B.is_walk(lv, q + fwd * 1.8):
				break
			decal(Vector3(q.x, y, q.y) + Vector3(fwd.x, 0, fwd.y) * 1.8, Vector2(3.6, 1.15), "blood_drag_%d" % (k % 2), 1.0, dir)
			q += fwd * 3.6
			dir += vr.randf_range(-0.25, 0.25)
			fwd = Vector2(cos(dir), -sin(dir))
		stats.blood += 1
	for i2 in 8:
		var p2 := walk_point(lv)
		if p2 == Vector2.INF:
			continue
		decal(Vector3(p2.x, y, p2.y), Vector2(2.3, 2.3), "b:%d" % (12 + i2 % 2), 1.0)
		for k2 in 3:
			decal(Vector3(p2.x + vr.randf_range(-1.3, 1.3), y, p2.y + vr.randf_range(-1.3, 1.3)), Vector2(0.7, 0.7), "b:%d" % [0, 1, 2, 3, 8, 10][vr.randi() % 6], 0.9)
		var sd := vr.randf() * TAU
		decal(Vector3(p2.x, y, p2.y) + Vector3(cos(sd), 0, -sin(sd)) * 2.8, Vector2(3.6, 0.9), "blood_steps", 0.85, sd)
		stats.blood += 1


func _ceilings(lv: int) -> void:
	## Where the ceiling came down: a hole into the dark void, tiles hanging by a corner, cables, a fitting dangling,
	## the tiles in pieces on the floor in a spread of plaster dust; one of them sparks. One leak per level.
	var y: float = L.level_y(lv)
	var cy: float = y + L.CEIL
	var n := 0
	for i in 12:
		if n >= 4:
			break
		var p := walk_point(lv)
		if p == Vector2.INF or not clear_of_ways(lv, p, 3.5):
			continue
		n += 1
		stats.ceiling += 1
		var yaw := vr.randf() * TAU
		var sz := vr.randf_range(1.8, 3.0)
		B.ceil_decal(Vector3(p.x, cy, p.y), Vector2(sz, sz), yaw, "ceiling_hole")
		# tiles hanging from the edge
		for k in 2 + vr.randi() % 2:
			var a := yaw + k * 2.1
			var e := Vector3(p.x + cos(a) * sz * 0.38, cy - 0.02, p.y - sin(a) * sz * 0.38)
			var tilt := vr.randf_range(0.7, 1.25)
			var bas := Basis(Vector3.UP, a) * Basis(Vector3(0, 0, 1), -tilt)
			S.box(Transform3D(bas, e + bas * Vector3(0.3, 0, 0)), Vector3(0.6, 0.012, 0.6), "mall_satin", B.o({"tint": Color(0.86, 0.85, 0.82), "paint": 1.0, "layer": "int"}))
		# cables
		for k2 in 2 + vr.randi() % 2:
			var t0 := Vector3(p.x + vr.randf_range(-0.6, 0.6), cy + 0.1, p.y + vr.randf_range(-0.6, 0.6))
			var t1 := t0 + Vector3(vr.randf_range(-0.4, 0.4), -vr.randf_range(1.0, 2.3), vr.randf_range(-0.4, 0.4))
			S.box(Transform3D(Basis.looking_at((t1 - t0).normalized(), Vector3.RIGHT), (t0 + t1) * 0.5), Vector3(0.018, 0.018, t0.distance_to(t1)), "mall_black", B.o({"layer": "int"}))
			if k2 == 0 and n == 2:
				sparks(t1, vr.randf_range(2.2, 3.6))
		if n == 1:
			# a downlight hanging by its wire
			var dl := Vector3(p.x + 0.4, cy - 1.3, p.y)
			S.cylinder(dl, Vector3.UP, 0.08, 0.11, "mall_chrome", B.o({"sides": 10, "layer": "int"}))
			S.box(Transform3D(Basis(), (dl + Vector3(p.x + 0.3, cy, p.y)) * 0.5), Vector3(0.012, 1.3, 0.012), "mall_black", B.o({"layer": "int"}))
		# on the floor: broken tiles, plaster dust, a chunk of duct
		decal(Vector3(p.x, y, p.y), Vector2(sz * 1.6, sz * 1.6), "floor_dust", 1.0)
		for k3 in 7:
			var fp := Vector3(p.x + vr.randf_range(-1.4, 1.4), y, p.y + vr.randf_range(-1.4, 1.4))
			var fb := Basis(Vector3.UP, vr.randf() * TAU) * Basis(Vector3(1, 0, 0), vr.randf_range(-0.25, 0.25))
			S.box(Transform3D(fb, fp + Vector3(0, 0.03, 0)), Vector3(vr.randf_range(0.2, 0.6), 0.015, vr.randf_range(0.2, 0.6)), "mall_satin",
				B.o({"tint": Color(0.84, 0.83, 0.8), "paint": 1.0, "layer": "int"}))
		if n == 3:
			static_prop("rubble_a", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.6, 0.6, 0.6)), Vector3(p.x, y, p.y)))
	# the leak: a stain on the ceiling, a puddle under it
	var lp := walk_point(lv)
	if lp != Vector2.INF:
		B.ceil_decal(Vector3(lp.x, cy, lp.y), Vector2(2.2, 2.2), vr.randf() * TAU, "ceiling_stain")
		S.atlas_quad(Vector3(lp.x, y + 0.004, lp.y), Vector3(1, 0, 0), Vector3(0, 0, -1), 2.6, 2.0, Rect2(0, 0, 1, 1), "puddle", {"layer": "int"})


func _walls(lv: int) -> void:
	## Spray paint and blood on the walls of the walks: the stair cores' fronts (by the doors people ran for), the
	## columns, the restroom fronts; notices taped up; bullet holes where someone made a stand.
	var y: float = L.level_y(lv)
	var faces := []   # [centre, normal, width]
	for c in L.CORES:
		var r: Rect2 = c
		var inner_z := r.end.y if r.position.y < 0.0 else r.position.y
		var inward := signf(inner_z - (r.position.y if r.position.y < 0.0 else r.end.y))
		faces.append([Vector3(r.position.x + 1.65 + (r.size.x - 1.65) * 0.5, y, inner_z + inward * 0.13), Vector3(0, 0, inward), r.size.x - 1.9])
	for rr in L.RESTROOMS:
		var r2: Rect2 = rr
		var iz := r2.end.y if r2.position.y < 0.0 else r2.position.y
		var inw := signf(iz - (r2.position.y if r2.position.y < 0.0 else r2.end.y))
		faces.append([Vector3(r2.position.x + 1.2, y, iz + inw * 0.11), Vector3(0, 0, inw), 1.9])
		faces.append([Vector3(r2.end.x - 1.2, y, iz + inw * 0.11), Vector3(0, 0, inw), 1.9])
	for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var p2 := Vector2(s.x * (L.GRAND_R.x * 0.78 + 1.6), s.y * (L.GRAND_R.y * 0.78 + 1.6))
		faces.append([Vector3(p2.x, y, p2.y + s.y * 0.46), Vector3(0, 0, s.y), 0.85])
		faces.append([Vector3(p2.x + s.x * 0.46, y, p2.y), Vector3(s.x, 0, 0), 0.85])
	var used := 0
	for i in faces.size():
		var f: Array = faces[i]
		var c3: Vector3 = f[0]
		var n: Vector3 = f[1]
		var w: float = f[2]
		var h = B.h01(i, lv, 900)
		if h < 0.62:
			var nm: String = SPRAY[int(B.h01(i, lv, 901) * SPRAY.size()) % SPRAY.size()]
			var dw := minf(w, 2.6)
			B.wall_decal(c3 + Vector3(0, 1.5 + vr.randf_range(-0.2, 0.3), 0), n, Vector2(dw, dw * 0.5), nm, 0.95, vr.randf_range(-0.08, 0.08))
			used += 1
		elif h < 0.82:
			B.wall_decal(c3 + Vector3(vr.randf_range(-0.2, 0.2), 1.2, 0), n, Vector2(minf(w, 1.6), minf(w, 1.6) * 0.5), "blood_spatter", 0.95)
			B.wall_decal(c3 + Vector3(0, 0.9, 0), n, Vector2(0.8, 0.8), "blood_hands_%d" % (i % 2), 0.9)
		else:
			B.wall_decal(c3 + Vector3(0, 1.45, 0), n, Vector2(0.5, 0.68), NOTICES[(i + lv) % NOTICES.size()], 1.0, vr.randf_range(-0.06, 0.06))
		if B.h01(i, lv, 902) < 0.3:
			B.wall_decal(c3 + Vector3(vr.randf_range(-0.3, 0.3), 1.1, 0), n, Vector2(0.7, 0.7), "wall_bullets", 1.0)
		stats.writing += 1
	stats["writing_L%d" % (lv + 1)] = used


# ------------------------------------------------------------------ barricades

func _barricade(lv: int, a: Vector2, b: Vector2, gap: float = -1.0, gap_w: float = 1.3) -> void:
	## Whatever came to hand, piled across a way: tables on their sides, a sofa, mattresses and plywood leant up,
	## sandbags from the security office, boxes. One collision wall along it (but the gap) and the bots' grid closed.
	var y: float = L.level_y(lv)
	var d := b - a
	var len := d.length()
	var u := d / len
	var nrm := Vector2(-u.y, u.x)
	var yaw: float = B.seg_yaw(a, b)
	var spans := [[0.0, len]]
	if gap >= 0.0:
		spans = [[0.0, gap - gap_w * 0.5], [gap + gap_w * 0.5, len]]
	for sp in spans:
		var s0: float = sp[0]
		var s1: float = sp[1]
		if s1 - s0 < 0.3:
			continue
		var m := a + u * (s0 + s1) * 0.5
		S.col_box(Transform3D(Basis(Vector3.UP, yaw), Vector3(m.x, y + 0.7, m.y)), Vector3(s1 - s0, 1.4, 0.7), "wood", "barricade")
		L.block_seg(lv, a + u * s0, a + u * s1, 0.8, 0.3)
		var t := s0 + 0.3
		var k := 0
		while t < s1 - 0.3:
			var c := a + u * t + nrm * rng.randf_range(-0.15, 0.15)
			var pos := Vector3(c.x, y, c.y)
			match (k + int(rng.randf() * 3.0)) % 6:
				0:
					# a table on its side, top facing out
					S.box(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.2, 0.2)), pos + Vector3(0, 0.45, 0)), Vector3(1.2, 0.9, 0.05), "walnut", B.o({"layer": "int"}))
					for lx in [-0.5, 0.5]:
						S.box(Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, 0.6, 0) + Basis(Vector3.UP, yaw) * Vector3(lx, 0, -0.35)), Vector3(0.05, 0.05, 0.7), "walnut", B.o({"layer": "int"}))
					t += 1.25
				1:
					# a mattress leant up
					S.box(Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), 0.32), pos + Vector3(0, 0.9, 0)), Vector3(1.0, 1.85, 0.14), "mall_cloth",
						B.o({"tint": Color(0.82, 0.8, 0.72), "paint": 1.0, "layer": "int"}))
					t += 1.05
				2:
					# sandbags, three courses
					for row in 3:
						for j in 2:
							S.box(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.1, 0.1)), pos + Basis(Vector3.UP, yaw) * Vector3(-0.36 + j * 0.72, 0.09 + row * 0.17, 0)),
								Vector3(0.7, 0.18, 0.4), "mall_cloth", B.o({"tint": Color(0.55, 0.5, 0.38), "paint": 1.0, "layer": "int"}))
					t += 1.5
				3:
					# plywood sheets
					for j2 in 2:
						S.box(Transform3D(Basis(Vector3.UP, yaw + j2 * 0.15) * Basis(Vector3(1, 0, 0), 0.2 + j2 * 0.1), pos + Vector3(0, 1.05, 0)), Vector3(1.2, 2.1, 0.02), "plywood",
							B.o({"layer": "int"}))
					t += 1.3
				4:
					# a sofa on its end
					tipped("sofa_modern", pos, yaw, 0.9, Vector3(1, 0, 0))
					t += 1.9
				_:
					# boxes and a chair on top
					for j3 in 3:
						S.box(Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.3, 0.3)), pos + Vector3(rng.randf_range(-0.2, 0.2), 0.25 + j3 * 0.45, 0)), Vector3(0.6, 0.45, 0.5),
							"plywood", B.o({"tint": Color(0.72, 0.58, 0.4), "paint": 0.8, "layer": "int"}))
					t += 0.8
			k += 1
		stats.barricades += 1


func _barricades() -> void:
	## Level 3: across the front of the big restrooms (people held out in there), a way left in at one end.
	var br: Dictionary = L.BIG_RESTROOM
	var z = -L.BAND_Z + 2.2
	_barricade(int(br.level), Vector2(-40.0, z), Vector2(float(br.x1) - 0.6, z), 7.2, 1.5)
	B.wall_decal(Vector3((float(br.x0) + float(br.x1)) * 0.5 + 2.0, L.level_y(int(br.level)) + 2.4, -L.BAND_Z + 0.22), Vector3(0, 0, 1), Vector2(2.4, 1.2), "spray_08", 0.95)
	# Level 5: inside the cinema's lobby, the last ones holed up ("4 ALIVE CINEMA L5"), a way through by the doors
	var lv = L.LEVELS - 1
	var x: float = L.ANCHOR_X + 2.0
	_barricade(lv, Vector2(x, -7.0), Vector2(x, 7.0), 7.0, 1.4)
	B.wall_decal(Vector3(L.ANCHOR_X - 0.21, L.level_y(lv) + 3.75, 6.5), Vector3(-1, 0, 0), Vector2(2.2, 1.1), "spray_06", 0.95)
	B.wall_decal(Vector3(L.ANCHOR_X - 0.21, L.level_y(lv) + 3.75, -6.5), Vector3(-1, 0, 0), Vector2(2.2, 1.1), "bloodtext_0", 0.95)


# ------------------------------------------------------------------ the burnt shop

func _burnt_shop() -> void:
	## A unit on Level 4 that caught fire: everything inside blackened, the floor scorched, soot climbing the front and
	## out along the ceiling, embers still glowing, smoke coming out.
	var room := {}
	for r in B.rooms:
		var c: Vector3 = (r.xf as Transform3D) * Vector3(float(r.w) * 0.5, 0, float(r.d) * 0.5)
		if int(r.lv) == int(B.BURNT.lv) and Vector2(c.x, c.z).distance_to(B.BURNT.p) < 4.0:
			room = r
	if room.is_empty():
		return
	var xf: Transform3D = room.xf
	var w: float = room.w
	var d: float = room.d
	var y: float = L.level_y(int(room.lv))
	var P := func(x: float, z: float, h: float) -> Vector3: return xf * Vector3(x, y + h, z)
	var n_out := -xf.basis.z.normalized()
	# char over the floor and walls inside
	for i in 9:
		decal(P.call(vr.randf_range(1.0, w - 1.0), vr.randf_range(1.0, d - 1.0), 0.0), Vector2(4.0, 4.0), "floor_scorch", 1.0)
	for side in [[Vector3(0.12, 0, 0), xf.basis.x.normalized()], [Vector3(w - 0.12, 0, 0), -xf.basis.x.normalized()]]:
		for k in 3:
			var o: Vector3 = side[0]
			B.wall_decal(P.call(o.x, d * (k + 0.5) / 3.0, 1.9), side[1], Vector2(3.6, 3.6), "wall_soot", 1.0)
	for k2 in 3:
		B.wall_decal(P.call(w * (k2 + 0.5) / 3.0, d - 0.14, 1.9), n_out, Vector2(4.2, 3.8), "wall_soot", 1.0)
	# up the front and out along the walk's ceiling
	B.wall_decal(P.call(w * 0.5, -0.22, 3.6), n_out, Vector2(w * 0.8, 2.6), "wall_soot", 1.0)
	for k3 in 3:
		B.ceil_decal(P.call(w * (k3 + 0.5) / 3.0, -1.6, L.CEIL), Vector2(4.0, 4.0), vr.randf() * TAU, "floor_scorch", 0.9)
		decal(P.call(w * (k3 + 0.5) / 3.0, -1.8, 0.0), Vector2(3.2, 3.2), "floor_scorch", 0.7)
	# fallen, burnt shelving and rubble
	for k4 in 5:
		var bp: Vector3 = P.call(rng.randf_range(1.0, w - 1.0), rng.randf_range(1.5, d - 1.0), 0.0)
		S.box(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(1, 0, 0), rng.randf_range(-1.3, 1.3)), bp + Vector3(0, 0.3, 0)), Vector3(1.6, 0.06, 0.5),
			"mall_satin", B.o({"tint": Color(0.06, 0.055, 0.05), "paint": 1.0, "layer": "int"}))
	static_prop("rubble_b", Transform3D(Basis(), P.call(w * 0.4, d * 0.6, 0.0)))
	static_prop("heap_medium_a", Transform3D(Basis(Vector3.UP, 1.0), P.call(w * 0.7, d * 0.4, 0.0)))
	# embers and smoke
	mb.dyn.add_light({"pos": P.call(w * 0.55, d * 0.55, 0.4), "kind": "bulb", "color": Color(1.0, 0.42, 0.12), "energy": 1.2, "range": 6.0, "fault": "candle",
		"fade": 34.0, "emitter": false})
	smoke(P.call(w * 0.5, d * 0.5, 0.5), Vector3(w * 0.7, 1.0, d * 0.6))
	stats.burnt = str(room.name)


# ------------------------------------------------------------------ inside the shops

func _rooms() -> void:
	## Each shop's floor: its stock knocked off the shelves, papers, dirt; blood in a third of them (and a body
	## dragged out of some).
	for r in B.rooms:
		var kind := str(r.kind)
		if kind in ["closed", "restroom", "department"]:
			continue
		var xf: Transform3D = r.xf
		var w: float = r.w
		var d: float = r.d
		var y: float = L.level_y(int(r.lv))
		var area := w * d
		var n := clampi(int(area / 30.0), 2, 14)
		for i in n:
			var p := xf * Vector3(vr.randf_range(0.8, w - 0.8), y, vr.randf_range(1.0, d - 0.8))
			decal(p, Vector2(2.2, 2.2), ["floor_papers_0", "floor_grime_0", "floor_papers_1", "floor_grime_1"][i % 4], 0.85)
		# stock on the floor
		for j in clampi(int(area / 12.0), 3, 18):
			var sp := xf * Vector3(vr.randf_range(0.6, w - 0.6), y, vr.randf_range(0.8, d - 0.6))
			var col: Color = BAG_COLS[vr.randi() % BAG_COLS.size()].lerp(Color(0.8, 0.78, 0.74), vr.randf() * 0.5)
			S.box(Transform3D(Basis(Vector3.UP, vr.randf() * TAU) * Basis(Vector3(1, 0, 0), vr.randf_range(-0.2, 0.2)), sp + Vector3(0, 0.05, 0)),
				Vector3(vr.randf_range(0.12, 0.35), vr.randf_range(0.05, 0.12), vr.randf_range(0.12, 0.3)), "mall_satin" if j % 3 else "mall_cloth",
				B.o({"tint": col, "paint": 1.0, "layer": "int"}))
		if B.h01(int(xf.origin.x * 3.0), int(xf.origin.z * 3.0), 950 + int(r.lv)) < 0.36:
			var bp := xf * Vector3(w * vr.randf_range(0.3, 0.7), y, d * vr.randf_range(0.4, 0.8))
			decal(bp, Vector2(2.0, 2.0), "b:%d" % (12 + vr.randi() % 2), 0.95)
			if vr.randf() < 0.5:
				# dragged out toward the door
				var to := xf * Vector3(w * 0.5, y, 0.6)
				var dv := Vector2(to.x - bp.x, to.z - bp.z)
				var dl := dv.length()
				if dl > 2.0:
					var mid := (bp + to) * 0.5
					decal(mid, Vector2(dl, 0.9), "blood_drag_0", 0.95, atan2(-dv.y, dv.x))
			var wall_p := xf * Vector3(w * 0.5, y + 1.3, d - 0.14)
			B.wall_decal(wall_p, -xf.basis.z.normalized(), Vector2(2.0, 1.0), "blood_spatter", 0.95)
			stats.blood += 1
		if vr.randf() < 0.5:
			static_prop("litter_b", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), xf * Vector3(w * 0.3, y, d * 0.5)))


# ------------------------------------------------------------------ outside

func _outside() -> void:
	## The drop-off lanes the morning after: a checkpoint at the main (south) entrance that did not hold - concrete
	## barriers, sandbags, police tape, a flipped and a burnt police car; abandoned and burnt cars in both lanes, a van
	## that hit the bollards; bags of rubbish and blood on the paving.
	var mz: float = L.MZ
	var cars := [["car_police_flipped", Vector3(13.0, 0.0, mz + 6.6), 0.35], ["car_burnt_a", Vector3(-24.0, 0.0, mz + 7.4), 2.9],
		["van_delivery", Vector3(29.0, 0.0, mz + 5.0), -0.55], ["covered_car", Vector3(-35.0, 0.0, mz + 7.0), 0.05],
		["car_burnt_b", Vector3(20.0, 0.0, -mz - 7.0), 3.3], ["car_pickup_old", Vector3(-9.0, 0.0, -mz - 7.4), 0.12],
		["car_burnt_a", Vector3(-31.0, 0.0, -mz - 6.4), 2.5]]
	for c in cars:
		static_prop(str(c[0]), Transform3D(Basis(Vector3.UP, float(c[2])), c[1]), 0, Vector2(2.4, 1.2))
		decal(c[1] + Vector3(0, 0.0, 0), Vector2(5.0, 5.0), "floor_scorch" if str(c[0]).contains("burnt") else "v:oil_1", 0.85, float(c[2]))
	# the checkpoint
	for bx in [-10.5, -8.3, 8.3, 10.5]:
		static_prop("barrier2", Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.15, 0.15)), Vector3(bx, 0.0, mz + 3.8)), 0, Vector2(1.1, 0.4))
	for sx in [-4.6, 4.6]:
		for row in 3:
			for j in 3:
				var sp := Vector3(sx + (j - 1) * 0.72, 0.09 + row * 0.18, mz + 4.6)
				S.box(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.08, 0.08)), sp), Vector3(0.7, 0.18, 0.4), "mall_cloth", B.o({"tint": Color(0.5, 0.46, 0.34), "paint": 1.0,
					"collide": true}))
		L.block_rect(0, Vector2(sx, mz + 4.6), Vector2(1.1, 0.25), 0.0, 0.3)
	for k in 3:
		var a := Vector2(-6.6 + k * 4.4, mz + 6.0)
		tape(0, a, a + Vector2(4.4, 0.0), 1.0, true)
	B.wall_decal(Vector3(-4.0, 1.6, mz + 0.27), Vector3(0, 0, 1), Vector2(2.6, 1.3), "spray_02", 0.95)
	B.wall_decal(Vector3(7.6, 1.5, mz + 0.27), Vector3(0, 0, 1), Vector2(2.6, 1.3), "quarantine", 1.0)
	for i in 30:
		var p := Vector2(rng.randf_range(-70.0, 70.0), (mz + rng.randf_range(2.0, 14.0)) * (1.0 if i % 2 == 0 else -1.0))
		if i % 5 == 0:
			loose("trashbag", Vector3(p.x, 0.0, p.y), rng.randf() * TAU)
		else:
			decal(Vector3(p.x, 0.0, p.y), Vector2(3.0, 3.0), ["floor_papers_0", "v:mud_0", "floor_grime_1", "b:13", "v:oil_2"][i % 5], 0.9)
	decal(Vector3(1.0, 0.0, mz + 8.0), Vector2(3.0, 3.0), "blood_pool_drag", 1.0, PI * 0.5)
	decal(Vector3(1.0, 0.0, mz + 4.8), Vector2(3.6, 0.9), "blood_drag_0", 0.95, PI * 0.5)
