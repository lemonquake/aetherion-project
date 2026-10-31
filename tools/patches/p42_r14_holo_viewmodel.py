"""r14: the SmarTab becomes a hologram projected from a watch on the left wrist (game/src/player/viewmodel.gd)."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'src', 'player', 'viewmodel.gd')
raw = open(p, 'rb').read().decode('utf-8')
nl = '\r\n' if '\r\n' in raw else '\n'
s = raw.replace('\r\n', '\n')
if 'func _place_hologram' in s:
    raise SystemExit('already applied')


def R(a, b):
    global s
    assert s.count(a) == 1, (s.count(a), a[:80])
    s = s.replace(a, b)


R('''## Holding TAB lowers the weapon out of the firing position and brings the device up in the left hand; the large
## square screen is a live SubViewport (the SmarTab UI). Releasing TAB lowers it and raises the weapon again.''',
  '''## Holding TAB lowers the weapon and raises the left forearm: the watch on the wrist projects the SmarTab as a large
## hologram floating in front of the eyes (r14; a live SubViewport drawn with the hologram shader, a beam of light
## from the watch to it). Releasing TAB folds it back into the watch and raises the weapon again.''')

R('''var screen_size := Vector2(0.3, 0.3)    # doubled 2026-10-28: the text was too small to read''',
  '''var screen_size := Vector2(0.3, 0.3)    # the hologram's size (m), set each frame to fill most of the view
var panel_px_h := 600.0                  # its height on the window in pixels (the HUD sizes the picture to it)
var watch: Node3D                        # r14: on the left wrist
var _watch_face: MeshInstance3D
var _beam: MeshInstance3D
var _beam_im: ImmediateMesh
var _holo_mat: ShaderMaterial
var _watch_at := Vector3(-0.16, -0.22, -0.32)   # watch face centre (view model space), last frame
var _watch_n := Vector3(0, 0.2, 1)''')

start = s.index('func _build_smartab() -> void:')
end = s.index('# ------------------------------------------------------------------ the gun in hand')
NEW_BUILD = '''func _build_smartab() -> void:
	## r14: the hologram panel (a unit quad scaled to its size each frame), the beam from the watch, the watch itself.
	tab_root = Node3D.new()
	tab_root.name = "Hologram"
	add_child(tab_root)
	tab_screen = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	tab_screen.mesh = q
	tab_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holo_mat = ShaderMaterial.new()
	_holo_mat.shader = load("res://src/fx/hologram.gdshader")
	_holo_mat.render_priority = 100
	tab_screen.material_override = _holo_mat
	tab_root.add_child(tab_screen)
	# The projection lights the hand and nearby surfaces faintly, and can be seen by others.
	tab_light = OmniLight3D.new()
	tab_light.light_color = Color(0.5, 0.85, 1.0)
	tab_light.omni_range = 1.8
	tab_light.light_energy = 0.0
	tab_light.shadow_enabled = false
	tab_light.position = Vector3(0, 0, 0.12)
	tab_root.add_child(tab_light)
	tab_root.visible = false
	_beam_im = ImmediateMesh.new()
	_beam = MeshInstance3D.new()
	_beam.mesh = _beam_im
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bm := ShaderMaterial.new()
	bm.shader = load("res://src/fx/holo_beam.gdshader")
	bm.render_priority = 99
	_beam.material_override = bm
	_beam.extra_cull_margin = 4.0
	_beam.visible = false
	add_child(_beam)
	_build_watch()


func _build_watch() -> void:
	## A rugged smartwatch: dark case, glass face with a glowing ring, strap round the wrist. Placed on the wrist
	## every frame (hand_frame): face on the back of the wrist, strap along the forearm.
	watch = Node3D.new()
	watch.name = "Watch"
	add_child(watch)
	var case_m := _mat(Color(0.06, 0.065, 0.07), 0.45)
	case_m.metallic = 0.4
	var body := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.04, 0.012, 0.046)
	body.mesh = bx
	body.material_override = case_m
	watch.add_child(body)
	for sz in [-1.0, 1.0]:
		var lug := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.026, 0.006, 0.02)
		lug.mesh = lb
		lug.material_override = _mat(Color(0.08, 0.085, 0.08), 0.85)
		lug.position = Vector3(0, -0.002, sz * 0.031)
		watch.add_child(lug)
	var strap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.034
	cm.bottom_radius = 0.034
	cm.height = 0.024
	cm.radial_segments = 20
	cm.rings = 1
	strap.mesh = cm
	strap.material_override = _mat(Color(0.07, 0.075, 0.07), 0.9)
	# The strap's ring goes round the wrist: its axis along the forearm (+Z of the hand frame), its top under the case.
	strap.rotation = Vector3(PI * 0.5, 0, 0)
	strap.position = Vector3(0, -0.03, 0)
	watch.add_child(strap)
	_watch_face = MeshInstance3D.new()
	var face := QuadMesh.new()
	face.size = Vector2(0.034, 0.04)
	_watch_face.mesh = face
	_watch_face.rotation = Vector3(-PI * 0.5, 0, 0)
	_watch_face.position = Vector3(0, 0.0062, 0)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_texture = _watch_face_tex()
	fm.albedo_color = Color(1, 1, 1)
	_watch_face.material_override = fm
	watch.add_child(_watch_face)
	_set_layer(watch)


func _watch_face_tex() -> Texture2D:
	## The watch's own little screen: a cyan ring of ticks round a dark face.
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.01, 0.025, 0.035))
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5)
			var r := d.length() / (n * 0.5)
			var a := fposmod(atan2(d.y, d.x), TAU)
			var tick := absf(fposmod(a * 12.0 / TAU + 0.5, 1.0) - 0.5) < 0.09
			if (r > 0.78 and r < 0.86) or (tick and r > 0.66 and r < 0.76) or r < 0.07:
				img.set_pixel(x, y, Color(0.4, 0.9, 1.0))
			elif r < 0.5 and absf(d.y) < 2.0 and d.x > 0.0:
				img.set_pixel(x, y, Color(0.35, 0.8, 0.95))
	return ImageTexture.create_from_image(img)


func set_screen_texture(tex: Texture2D) -> void:
	_holo_mat.set_shader_parameter("ui_tex", tex)


func screen_uv(viewport_pos: Vector2) -> Vector2:
	## Where a mouse position on the window lands on the hologram (0..1), or (-1,-1).
	if not tab_root.visible:
		return Vector2(-1, -1)
	var from := cam.project_ray_origin(viewport_pos)
	var dir := cam.project_ray_normal(viewport_pos)
	var xf := tab_screen.global_transform
	var n := xf.basis.z.normalized()
	var denom := n.dot(dir)
	if absf(denom) < 1e-5:
		return Vector2(-1, -1)
	var t := n.dot(xf.origin - from) / denom
	if t < 0.0:
		return Vector2(-1, -1)
	var p := xf.affine_inverse() * (from + dir * t)
	return Vector2(p.x + 0.5, 0.5 - p.y)


func _place_hologram(dt: float) -> void:
	## The hologram fills most of the view (whatever the field of view and window shape), a little up and right of
	## centre, turned slightly toward the watch it comes from. It grows out of the watch as the arm comes up.
	var vs := get_viewport().get_visible_rect().size
	var aspect := vs.x / maxf(vs.y, 1.0)
	var d := 0.6
	var hh := d * tan(deg_to_rad(cam.fov) * 0.5)
	var hw := hh * aspect
	var pr := 1600.0 / 960.0
	var ph := minf(1.66 * hh, 1.84 * hw / pr)
	var pw := ph * pr
	screen_size = Vector2(pw, ph)
	panel_px_h = ph / (2.0 * hh) * vs.y
	var k := smoothstep(0.42, 1.0, _tab)
	var centre := Vector3(0.02 * hw, 0.06 * hh, -d)
	tab_root.visible = k > 0.001
	tab_root.position = _watch_at.lerp(centre, ease(k, 0.6))
	tab_root.rotation = Vector3(-0.03, 0.06, 0.0) * k
	tab_root.scale = Vector3.ONE * lerpf(0.03, 1.0, ease(k, 0.5))
	tab_screen.scale = Vector3(pw, ph, 1.0)
	var bright := float(Settings.get_value("accessibility", "smartab_brightness"))
	_holo_mat.set_shader_parameter("boot", k)
	_holo_mat.set_shader_parameter("bright", 0.75 + bright * 0.5)
	tab_light.light_energy = 0.4 * bright * k
	_beam.visible = _tab > 0.3
	if _beam.visible:
		_draw_beam(k)


func _draw_beam(k: float) -> void:
	## Faint planes from the watch face to the hologram's corners, with brighter edges; strongest while it opens.
	_beam_im.clear_surfaces()
	var apex := _watch_at + _watch_n * 0.004
	var xf := tab_root.transform * tab_screen.transform
	var corners := [xf * Vector3(-0.5, -0.5, 0), xf * Vector3(0.5, -0.5, 0), xf * Vector3(0.5, 0.5, 0), xf * Vector3(-0.5, 0.5, 0)]
	var s := lerpf(1.6, 0.35, k)
	(_beam.material_override as ShaderMaterial).set_shader_parameter("strength", s)
	_beam_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		_beam_im.surface_set_color(Color(1, 1, 1, 0.12))
		_beam_im.surface_add_vertex(apex)
		_beam_im.surface_set_color(Color(1, 1, 1, 0.0))
		_beam_im.surface_add_vertex(a)
		_beam_im.surface_add_vertex(b)
		# Edge: a thin sliver along apex -> corner.
		var side := (a - apex).cross(cam.global_transform.basis.z).normalized() * 0.0025
		_beam_im.surface_set_color(Color(1, 1, 1, 0.55))
		_beam_im.surface_add_vertex(apex)
		_beam_im.surface_set_color(Color(1, 1, 1, 0.05))
		_beam_im.surface_add_vertex(a + side * 3.0)
		_beam_im.surface_add_vertex(a - side * 3.0)
	_beam_im.surface_end()


func _place_watch() -> void:
	## On the back of the left wrist, a little up the forearm, wherever the arm is.
	if arms == null or not arms.ok or bool(arms.sides.L.get("hidden", false)):
		watch.visible = false
		return
	var hf: Transform3D = global_transform.affine_inverse() * arms.hand_frame("L")
	var b := hf.basis
	# Hand frame: -Z along the fingers, +Y out of the palm. The watch faces -Y (the back of the wrist).
	var up := -b.y
	var fwd := b.z
	var x := up.cross(fwd).normalized()
	watch.transform = Transform3D(Basis(x, up, x.cross(up)).orthonormalized(), hf.origin + b.z * 0.03 - b.y * 0.028)
	watch.visible = true
	_watch_at = watch.transform * Vector3(0, 0.007, 0)
	_watch_n = up


'''
s = s[:start] + NEW_BUILD + s[end:]

R('''	var e := ease(_tab, -2.0)
	tab_root.visible = _tab > 0.01
	tab_root.position = Vector3(lerpf(-0.12, -0.035, e), lerpf(-0.62, -0.035, e), lerpf(-0.2, -0.31, e))
	tab_root.rotation = Vector3(lerpf(-1.1, 0.12, e), lerpf(0.5, 0.05, e), lerpf(0.4, 0.0, e))
	var bright := float(Settings.get_value("accessibility", "smartab_brightness"))
	tab_light.light_energy = 0.35 * bright * e
	if tab_screen.material_override is StandardMaterial3D:
		(tab_screen.material_override as StandardMaterial3D).emission_energy_multiplier = 0.4 + bright * 1.2
''', '''	var e := ease(_tab, -2.0)
	_place_hologram(dt)
''')

R('''	# Left hand: the SmarTab while it is up, else the gun (handguard, pump, magazine, rounds...).
	if tab_root.visible and _tab > 0.25:
		var tb2 := tab_root.basis * FpArms.hand_basis(Vector3.UP, Vector3.BACK)
		# Flat against the back, low and a little left: the hand is hidden behind the device and its straight fingers
		# cannot curl round through the screen.
		arms.pose("L", tab_root.position + tab_root.basis * Vector3(-0.05, -0.13, -0.065), tb2, POLE_L, FpArms.grip("tablet"))''',
  '''	# Left hand: the forearm raised across the view, back of the wrist (the watch) toward the eyes while the SmarTab
	# is up; else the gun (handguard, pump, magazine, rounds...).
	if _tab > 0.02:
		var te := ease(_tab, -2.0)
		var palm := Vector3(lerpf(-0.24, -0.075, te), lerpf(-0.66, -0.19, te), lerpf(-0.18, -0.34, te))
		var hb := FpArms.hand_basis(Vector3(0.94, 0.34, -0.1), Vector3(0.05, -0.55, -1.0))
		arms.pose("L", palm, hb, Vector3(-0.5, -1.0, 0.3), FpArms.grip("relaxed"))''')

open(p, 'wb').write(s.replace('\n', nl).encode('utf-8'))
print('applied')
