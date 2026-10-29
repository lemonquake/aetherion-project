extends Node3D
## Laser pointers (hold V): a thin beam from the pointer in the player's hand to the first thing it hits, brightest at
## the pointer and fading along its tail, and a glowing dot with a little light of its own where it lands. Drawn on
## every peer for every character whose laser is on (F_LASER from the server); your own from your input at once.
## The beam is a camera-facing ribbon never thinner than about a pixel and a half, so it reads across a street.

const MAX_RANGE := 260.0
const SEGMENTS := 10

var world = null
var _mesh := ImmediateMesh.new()
var _mi: MeshInstance3D
var _beam_mat: ShaderMaterial
var _dots := {}          # eid -> {"q": MeshInstance3D, "l": OmniLight3D, "m": StandardMaterial3D}
var _dot_tex: Texture2D
var stats := {"beams": 0}

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
void fragment() {
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float core = smoothstep(0.0, 0.85, across);
	ALBEDO = COLOR.rgb * (0.6 + core * 2.2);
	ALPHA = COLOR.a * core;
}
"""


func setup(w) -> void:
	world = w
	name = "Lasers"
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = sh
	_mi = MeshInstance3D.new()
	_mi.mesh = _mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 16384.0   # vertices are rewritten every frame; never cull by the stale box
	add_child(_mi)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.18, Color(1, 1, 1, 0.95))
	g.add_point(0.42, Color(1, 1, 1, 0.25))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_dot_tex = gt


static func color_of(pid: int) -> Color:
	if pid == Net.local_pid:
		return Settings.laser_color(str(Settings.get_value("player", "laser_color")))
	return Settings.laser_color(str(Net.players.get(pid, {}).get("laser", "red")))


func _laser_on(ch) -> bool:
	if ch.mode != Motor.GROUND:
		return false
	var ctrl = world.controller
	if ctrl and ctrl.ch == ch:
		return ctrl.laser_held
	return (int(ch.flags) & Character.F_LASER) != 0


func beam(ch) -> Array:
	## [origin (the pointer in the hand), dot (where it lands, or the far end), hit something, surface normal].
	var ctrl = world.controller
	var eye: Vector3
	var b: Basis
	if ctrl and ctrl.ch == ch and ctrl.cam:
		b = Basis.from_euler(Vector3(ctrl.pitch, ctrl.yaw, 0.0))
		eye = ctrl.cam.global_position
	else:
		b = Basis.from_euler(Vector3(ch.pitch, ch.yaw, 0.0))
		eye = ch.get_global_transform_interpolated().origin + Vector3.UP * (ch.height() - Defs.move("eye_offset"))
	var dir := -b.z
	# Held low and to the right, like a pointer in the off hand; aimed where the eyes look (the dot is the crosshair).
	var origin := eye + b * (Vector3(0.12, -0.14, -0.34) if ctrl and ctrl.ch == ch else Vector3(0.2, -0.3, -0.42))
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * MAX_RANGE, Defs.SIGHT_MASK)
	q.exclude = [ch.get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return [origin, eye + dir * MAX_RANGE, false, Vector3.UP]
	return [origin, r.position, true, r.normal]


func _process(_dt: float) -> void:
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or world == null:
		return
	var cp := cam.global_position
	var used := {}
	stats.beams = 0
	for ch in world.characters.values():
		if not _laser_on(ch):
			continue
		var bm := beam(ch)
		var o: Vector3 = bm[0]
		var e: Vector3 = bm[1]
		var col := color_of(int(ch.pid))
		var axis := e - o
		if axis.length() < 0.05:
			continue
		stats.beams += 1
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _beam_mat)
		for i in SEGMENTS + 1:
			var t := float(i) / SEGMENTS
			# Segments crowd toward the pointer, where the beam is brightest and nearest the eye.
			var tt := t * t
			var p := o + axis * tt
			var to_cam := cp - p
			var side := to_cam.cross(axis).normalized()
			var w := maxf(0.0016, to_cam.length() * 0.0011)
			var a := lerpf(0.9, 0.1, pow(tt, 0.55))
			_mesh.surface_set_color(Color(col.r, col.g, col.b, a))
			_mesh.surface_set_uv(Vector2(tt, 0.0))
			_mesh.surface_add_vertex(p - side * w)
			_mesh.surface_set_color(Color(col.r, col.g, col.b, a))
			_mesh.surface_set_uv(Vector2(tt, 1.0))
			_mesh.surface_add_vertex(p + side * w)
		_mesh.surface_end()
		if bool(bm[2]):
			_dot(ch.eid, e, (cp - e).normalized(), col, cp.distance_to(e))
			used[ch.eid] = true
	for eid in _dots.keys():
		if not used.has(eid):
			var d: Dictionary = _dots[eid]
			d.q.visible = false
			d.l.visible = false


func _dot(eid: int, p: Vector3, to_cam: Vector3, col: Color, dist: float) -> void:
	if not _dots.has(eid):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = _dot_tex
		m.disable_fog = true
		m.no_depth_test = false
		var qm := QuadMesh.new()
		qm.size = Vector2.ONE
		var q := MeshInstance3D.new()
		q.mesh = qm
		q.material_override = m
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
		var l := OmniLight3D.new()
		l.omni_range = 0.8
		l.light_energy = 1.4
		l.shadow_enabled = false
		add_child(l)
		_dots[eid] = {"q": q, "l": l, "m": m}
	var d: Dictionary = _dots[eid]
	var size := maxf(0.035, dist * 0.0065)
	d.q.visible = true
	d.q.global_position = p + to_cam * 0.03
	d.q.scale = Vector3.ONE * size
	(d.m as StandardMaterial3D).albedo_color = Color(col.r * 2.0, col.g * 2.0, col.b * 2.0, 1.0)
	d.l.visible = dist < 45.0
	d.l.light_color = col
	d.l.global_position = p + to_cam * 0.12
