extends RefCounted
## (r15) Malasugue Mall's escalators: two criss-cross banks of eight (up and down between every pair of levels). Each
## is drawn as a real one: the truss clad in brushed steel under the incline, skirt panels with a light line, glass
## balustrades with black rubber handrails and their rounded ends, steel decking between lanes, comb plates with the
## yellow comb edge at both landings, and a chain of steps that actually moves (escalator_steps.gdshader). Walking on
## one, the movement code rides its belt (MallLayout.belt_at); bots get a one-way link along each (up or down).

const STEPS_SHADER := preload("res://src/world/maps/malasugue_mall/escalator_steps.gdshader")
const STEP_PITCH := 0.4619   # along the chain: 0.4 m of tread on a 30-degree incline

var B = null
var mb = null
var L = null
var S = null
var stats := {"escalators": 0, "steps": 0}
var _step_mesh: ArrayMesh
var _step_mat: ShaderMaterial


func _init(builder) -> void:
	B = builder
	mb = builder.mb
	L = builder.L
	S = builder.S


func build() -> void:
	_step_mesh = _make_step_mesh()
	_step_mat = ShaderMaterial.new()
	_step_mat.shader = STEPS_SHADER
	_step_mat.set_shader_parameter("flat_len", L.ESC_FLAT)
	_step_mat.set_shader_parameter("run", L.ESC_RUN)
	_step_mat.set_shader_parameter("rise", L.FH)
	for e in L.escalators:
		_escalator(e)
		stats.escalators += 1


func _frame(e: Dictionary) -> Transform3D:
	## Escalator space: x along the run from the start of the lower landing, y up, z across (lane centre 0).
	var a: Vector3 = e.a
	var b: Vector3 = e.b
	var sx := signf(b.x - a.x)
	var X := Vector3(sx, 0, 0)
	var Z := X.cross(Vector3.UP)
	return Transform3D(Basis(X, Vector3.UP, Z), Vector3(a.x - sx * L.ESC_FLAT, a.y, a.z))


func _escalator(e: Dictionary) -> void:
	var xf := _frame(e)
	var run: float = L.ESC_RUN
	var rise: float = L.FH
	var fl: float = L.ESC_FLAT
	var total := run + fl * 2.0
	var incl := sqrt(run * run + rise * rise)
	var ang := atan2(rise, run)
	var t := int(e.t)
	var hw := 0.5     # half the step width
	var bal := 0.62   # balustrade from the lane centre
	var o := func(lx: float, ly: float, lz: float) -> Vector3:
		return xf * Vector3(lx, ly, lz)
	var inc_basis := xf.basis * Basis(Vector3(0, 0, 1), ang)   # x along the incline
	var inc_mid := Vector3(fl + run * 0.5, rise * 0.5, 0.0)
	# --- the truss under the incline, clad
	S.box(Transform3D(inc_basis, o.call(inc_mid.x, inc_mid.y - 0.82, 0.0)), Vector3(incl + 0.6, 1.0, 1.55), "mall_satin", B.o({"layer": "ext", "collide": true, "tint": Color(0.84, 0.85, 0.87), "paint": 1.0}))
	S.box(Transform3D(inc_basis, o.call(inc_mid.x, inc_mid.y - 1.33, 0.0)), Vector3(incl + 0.6, 0.02, 1.4), "mall_paint", B.o({"layer": "ext", "tint": B.WHITE, "paint": 1.0}))
	# --- the surface the feet use: a smooth ramp at the step tops (the landings are the floor)
	S.col_box(Transform3D(inc_basis, o.call(inc_mid.x, inc_mid.y - 0.1, 0.0)), Vector3(incl, 0.2, 1.1), "escalator", "escalator")
	# --- skirts, balustrades and handrails along the three parts (lower landing, incline, upper landing)
	var parts := [[Vector3(fl * 0.5 - 0.3, 0.0, 0.0), Basis(), fl + 0.6], [inc_mid, Basis(Vector3(0, 0, 1), ang), incl], [Vector3(fl + run + fl * 0.5 + 0.3, rise, 0.0), Basis(), fl + 0.6]]
	for p in parts:
		var c: Vector3 = p[0]
		var bb: Basis = xf.basis * (p[1] as Basis)
		var len: float = p[2]
		for s in [-1.0, 1.0]:
			var side := Vector3(0, 0, s)
			# skirt (steel, 25 cm) with a light line on it
			S.box(Transform3D(bb, xf * (c + Vector3(0, 0.14, s * (hw + 0.03)))), Vector3(len, 0.3, 0.03), "mall_steel", B.o({"layer": "mid"}))
			S.box(Transform3D(bb, xf * (c + Vector3(0, 0.22, s * (hw + 0.01)))), Vector3(len, 0.02, 0.012), "mall_light", B.o({"layer": "mid"}))
			# glass balustrade and its black handrail
			S.box(Transform3D(bb, xf * (c + Vector3(0, 0.66, s * bal))), Vector3(len, 0.82, 0.015), "mall_glass", B.o({"layer": "mid"}))
			S.box(Transform3D(bb, xf * (c + Vector3(0, 1.1, s * bal))), Vector3(len, 0.07, 0.085), "mall_black", B.o({"layer": "mid"}))
			# outer decking (stainless) from the skirt out to the balustrade line
			S.box(Transform3D(bb, xf * (c + Vector3(0, 0.29, s * (hw + 0.12)))), Vector3(len, 0.03, 0.2), "mall_steel", B.o({"layer": "mid"}))
			S.col_box(Transform3D(bb, xf * (c + Vector3(0, 0.6, s * bal))), Vector3(len, 1.2, 0.08), "glass", "escalator_side")
	# rounded handrail ends (newels) at both landings
	for s2 in [-1.0, 1.0]:
		for endx in [-0.3, total + 0.3]:
			S.box(Transform3D(xf.basis, o.call(endx, 0.7 + (rise if endx > total * 0.5 else 0.0), s2 * bal)), Vector3(0.05, 0.8, 0.09), "mall_black", B.o({"layer": "mid"}))
	# comb plates with their yellow comb edge
	for cp in [[0.25, 0.0, 1.0], [total - 0.25, rise, -1.0]]:
		S.box(Transform3D(xf.basis, o.call(cp[0], cp[1] + 0.008, 0.0)), Vector3(0.5, 0.016, 1.05), "mall_steel", B.o({"layer": "mid"}))
		S.box(Transform3D(xf.basis, o.call(float(cp[0]) + float(cp[2]) * 0.24, float(cp[1]) + 0.018, 0.0)), Vector3(0.04, 0.008, 1.0), "mall_flat", B.o({"layer": "int", "tint": Color(0.98, 0.8, 0.1), "paint": 1.0}))
	# under a ground-floor escalator's low end nobody stands upright: bots keep out
	if t == 0:
		var lo := xf * Vector3(fl, 0, 0)
		var hi := xf * Vector3(fl + run * 0.45, 0, 0)
		var mid2 := (lo + hi) * 0.5
		L.block_rect(0, Vector2(mid2.x, mid2.z), Vector2(run * 0.25, 0.8), 0.0, 0.25)
	# the flats' balustrades stand on the landing floors: bots keep out of them
	for lvl_end in [[t, 0.0], [t + 1, total]]:
		var lv: int = lvl_end[0]
		var ex: float = lvl_end[1]
		for s3 in [-1.0, 1.0]:
			var p0 := xf * Vector3(ex - (1.55 if ex > 0.0 else -0.3), 0, s3 * bal)
			var p1 := xf * Vector3(ex + (0.3 if ex > 0.0 else 1.55), 0, s3 * bal)
			L.block_seg(lv, Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), 0.1, 0.25)
	# --- the moving steps
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _step_mesh
	var n := int(floor((total + incl - run) / STEP_PITCH))
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, Transform3D())
		mm.set_instance_custom_data(i, Color(float(i) / n, 0, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _step_mat
	mi.transform = xf * Transform3D(Basis(), Vector3(0, 0.004, 0))
	mi.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(total + 2, rise + 2, 2))
	mi.set_instance_shader_parameter("speed", L.ESC_SPEED if bool(e.up) else -L.ESC_SPEED)
	mi.visibility_range_end = 90.0
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.name = "Escalator_%s_%d_%s" % [str(e.bank).replace(" ", ""), t, "up" if bool(e.up) else "down"]
	mb.root.add_child(mi)
	stats.steps += n
	# --- an arrow sign at the boarding end, and the bot link (one way, the way it moves)
	var board := (xf * Vector3(-0.6, 0, 0)) if bool(e.up) else (xf * Vector3(total + 0.6, rise, 0))
	var leave := (xf * Vector3(total + 0.6, rise, 0)) if bool(e.up) else (xf * Vector3(-0.6, 0, 0))
	L.add_link(board, leave, [], 1.0)


func _make_step_mesh() -> ArrayMesh:
	## One step: a grooved aluminium tread 1 m wide and 0.4 m deep (its leading edge at the origin, trailing toward
	## -x), yellow demarcation along the leading edge and both sides, and the riser hanging from the trailing edge
	## (its lower vertices fold flat on the landings: see the shader).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var metal := Color(0.62, 0.63, 0.65, 0.85)
	var yellow := Color(0.98, 0.78, 0.08, 0.0)
	var dark := Color(0.12, 0.12, 0.13, 0.6)
	_quad(st, Vector3(-0.4, 0, -0.46), Vector3(-0.04, 0, -0.46), Vector3(-0.04, 0, 0.46), Vector3(-0.4, 0, 0.46), Vector3.UP, metal)
	_quad(st, Vector3(-0.04, 0.001, -0.5), Vector3(0, 0.001, -0.5), Vector3(0, 0.001, 0.5), Vector3(-0.04, 0.001, 0.5), Vector3.UP, yellow)
	for s in [-1.0, 1.0]:
		var z0 := 0.46 if s > 0.0 else -0.5
		var z1 := 0.5 if s > 0.0 else -0.46
		_quad(st, Vector3(-0.4, 0.001, z0), Vector3(-0.04, 0.001, z0), Vector3(-0.04, 0.001, z1), Vector3(-0.4, 0.001, z1), Vector3.UP, yellow)
	# riser at the trailing edge, facing -x (toward the step below)
	_quad(st, Vector3(-0.4, 0, 0.5), Vector3(-0.4, 0, -0.5), Vector3(-0.4, -0.231, -0.5), Vector3(-0.4, -0.231, 0.5), Vector3(-1, 0, 0), dark)
	# the tread's front face
	_quad(st, Vector3(0, 0, -0.5), Vector3(0, 0, 0.5), Vector3(0, -0.04, 0.5), Vector3(0, -0.04, -0.5), Vector3(1, 0, 0), metal)
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	# wound so that n is the front face (Godot: clockwise seen from the front)
	var nn := (b - a).cross(d - a)
	var pts := [a, b, c, d] if nn.dot(n) < 0.0 else [a, d, c, b]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(pts[idx])
