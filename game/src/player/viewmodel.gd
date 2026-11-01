extends Node3D
## First-person view: the weapon in hand (offset by the same recoil kick and sway the server uses, so the barrel,
## the reticle and the bullets agree), the arms holding it, the left hand raising the SmarTab, and the player's own
## flashlight.
##
## Holding TAB lowers the weapon and raises the left forearm: the watch on the wrist projects the SmarTab as a large
## hologram floating in front of the eyes (r14; a live SubViewport drawn with the hologram shader, a beam of light
## from the watch to it). Releasing TAB folds it back into the watch and raises the weapon again.
##
## The arms are a skinned human pair (fp_arms.gd) dressed like the player's outfit and posed by IK every frame: the
## right hand on the grip (or holding the flashlight when nothing is drawn), the left on the handguard, supporting a
## handgun, or holding the SmarTab. Guns are drawn from their moving parts (gun_model.gd) so reloads and the actions
## between and with shots move the real magazine, slide, bolt, pump, cylinder or barrels (weapon_anims.gd); every
## clip is timed by the weapon state machine, so it lasts exactly as long as the reload or cycle it shows.

const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")
const FpArms := preload("res://src/player/fp_arms.gd")
const Anims := preload("res://src/player/weapon_anims.gd")
const GunModel := preload("res://src/weapons/gun_model.gd")
const WS := preload("res://src/weapons/weapon_state.gd")
const Outfit := preload("res://src/player/outfit.gd")
const POLE_R := Vector3(0.7, -1.0, 0.35)
const POLE_L := Vector3(-0.8, -1.0, 0.25)

var world = null
var ch = null
var cam: Camera3D
var weapon_root: Node3D
var weapon_mesh: MeshInstance3D
var att_root: Node3D             # fitted attachments, in the weapon model's item_visual space (offset by the grip)
var laser_dot: MeshInstance3D
var _att_sig := ""
var _grip_vis := Vector3.ZERO    # the grip in item_visual space
var _aim_pos := Vector3.ZERO     # weapon root position when aiming (the sight's line on the eye)
var _light_pt := Vector3.ZERO    # where a weapon-mounted light sits (weapon root space)
var tab_root: Node3D
var tab_screen: MeshInstance3D
var tab_light: OmniLight3D
var torch_root: Node3D
var light: SpotLight3D
var muzzle: Node3D
var test_hide_arms := false     # tests: draw the view without the arms
var screen_size := Vector2(0.3, 0.3)    # the hologram's size (m), set each frame to fill most of the view
var panel_px_h := 600.0                  # its height on the window in pixels (the HUD sizes the picture to it)
var watch: Node3D                        # r14: on the left wrist
var _watch_face: MeshInstance3D
var _beam: MeshInstance3D
var _beam_im: ImmediateMesh
var _holo_mat: ShaderMaterial
var _watch_at := Vector3(-0.16, -0.22, -0.32)   # watch face centre (view model space), last frame
var _watch_n := Vector3(0, 0.2, 1)
var _nade: Node3D                # r14: a frag grenade in the right hand while cooking
var _pin: MeshInstance3D         # its pin ring, pulled by the left hand
var _nade_t := -1.0              # seconds into the throw, -1 none
var _cook := -1.0
var arms: Node3D                 # fp_arms.gd
var _grip := Vector3.ZERO        # in weapon_root space
var _support := Vector3.ZERO
var _long := false
var _cur := "-"
var _tab := 0.0
var _lower := 0.0
var _sprint := 0.0              # sprint carry: the gun stays in view, canted across the chest
var _kick_z := 0.0
var _bob := 0.0
var _hit := 0.0
var _draw := 0.0
# Moving parts of the gun in hand: role -> {node, base (rest transform, weapon space), pivot, aabb (weapon space)}.
var _parts: Dictionary = {}
var _anchors: Dictionary = {}    # anchor name -> Vector3 (weapon space)
var _mag_rel := Transform3D()     # the magazine relative to the left palm while the hand holds it
var _bore_y := 0.0
var _iron_rear := Vector3(0, 0.12, 0.0)    # rear and front iron sight tops (weapon space): the line the eye takes
var _iron_front := Vector3(0, 0.12, -0.4)  # when aiming without an optic
var _iron_pitch := 0.0           # gun tilt and turn (radians) that put both sights on that line while aiming with irons
var _iron_yaw := 0.0
var _iron_drop := 0.0            # extra lowering so nothing else on the gun reaches the crosshair
var _irons := true
var _kind := ""                  # reload kind for the gun in hand (weapon_anims.reload_kind)
var _props: Dictionary = {}      # carried props: name -> Node3D
# Animation playback
var _clip: Array = []
var _clip_name := ""
var _clip_t := 0.0
var _cues: Array = []            # [t, sound id] of the playing clip still to come
var _clip_total := 1.0
var _last_state := -1
var _last_phase := -1
var _last_timer := 0.0
var _empty := false
var _blend_out := 0.0            # 1 -> 0 after a clip is cut short: fades its last pose back to rest
var _held_pose: Dictionary = {}
var _drop_t := -1.0
var _drop_xf := Transform3D()
var _mag_mode := "gun"
var _fire_t := 9.0
var _cyl_turns := 0
var _slide_locked := false
var _jolt := Vector3.ZERO
var _look_key := ""
var _bandage_roll: MeshInstance3D
var _bandage_wrap: MeshInstance3D
var _heal_t := -1.0              # seconds into the treatment shown (own clock: the server sends its start, not its progress)
var _heal_item := ""
const HOOK := [0.3, 0.55, 0.6, 0.62, 0.65]   # fingers hooked over an edge


func setup(w, c, camera: Camera3D) -> void:
	world = w
	ch = c
	cam = camera
	weapon_root = Node3D.new()
	add_child(weapon_root)
	weapon_mesh = MeshInstance3D.new()
	weapon_root.add_child(weapon_mesh)
	att_root = Node3D.new()
	att_root.name = "Attachments"
	weapon_root.add_child(att_root)
	laser_dot = make_laser_dot()
	add_child(laser_dot)
	muzzle = Node3D.new()
	weapon_root.add_child(muzzle)
	_build_smartab()
	_build_torch()
	_build_nade()
	arms = FpArms.new()
	arms.name = "Arms"
	add_child(arms)
	arms.setup(Defs.RENDER_VIEWMODEL)
	# The source arms hang from shoulders just behind the eye; a little forward they reach a rifle's handguard.
	arms.position = Vector3(0.0, -0.01, -0.07)
	_dress_arms()
	light = SpotLight3D.new()
	light.shadow_enabled = true
	# The beam starts at your hand, inside your own body, which is drawn as shadows only (for the moon): left as a
	# caster it shadowed the whole beam and the flashlight lit nothing. Walls, furniture and other people still do.
	light.shadow_caster_mask = 0xFFFFF & ~Defs.RENDER_LOCAL_BODY
	light.shadow_bias = 0.04
	light.shadow_enabled = bool(Settings.get_value("graphics", "flashlight_shadows"))
	Settings.changed.connect(func(s, k): if s == "graphics" and k == "flashlight_shadows": light.shadow_enabled = bool(Settings.get_value("graphics", "flashlight_shadows")))
	light.spot_range = float(Defs.flashlight.get("spot_range", 34.0))
	light.spot_angle = float(Defs.flashlight.get("spot_angle_deg", 26.0))
	light.spot_attenuation = 1.2
	light.light_color = Color(1.0, 0.95, 0.85)
	light.light_volumetric_fog_energy = 0.35
	# The beam's hot centre comes from the angular falloff. A projector texture (the first version) went through
	# the renderer's decal atlas and came out dark or black depending on renderer and timing; phones could not trust it.
	light.spot_angle_attenuation = 3.0
	light.visible = false
	add_child(light)
	# Faint fill on the view-model layer only (moonlight on your own hands); never reaches the world.
	var fill := OmniLight3D.new()
	fill.light_cull_mask = Defs.RENDER_VIEWMODEL
	fill.light_color = Color(0.55, 0.65, 0.85)
	fill.light_energy = 0.35
	fill.omni_range = 2.0
	fill.shadow_enabled = false
	fill.position = Vector3(0.35, 0.45, 0.25)
	add_child(fill)
	_build_bandage()
	_set_layer(self)


func _build_bandage() -> void:
	## r12: the roll in the right hand and the dressing that grows round the left forearm while bandaging.
	var white := _mat(Color(0.93, 0.92, 0.88), 0.92)
	var roll := CylinderMesh.new()
	roll.top_radius = 0.024
	roll.bottom_radius = 0.024
	roll.height = 0.056
	roll.radial_segments = 14
	_bandage_roll = MeshInstance3D.new()
	_bandage_roll.mesh = roll
	_bandage_roll.material_override = white
	_bandage_roll.visible = false
	add_child(_bandage_roll)
	var wrap := CylinderMesh.new()
	wrap.top_radius = 0.043
	wrap.bottom_radius = 0.047
	wrap.height = 1.0
	wrap.radial_segments = 16
	wrap.cap_top = false
	wrap.cap_bottom = false
	_bandage_wrap = MeshInstance3D.new()
	_bandage_wrap.mesh = wrap
	_bandage_wrap.material_override = _mat(Color(0.9, 0.88, 0.83), 0.95)
	_bandage_wrap.visible = false
	add_child(_bandage_wrap)


func _dress_arms() -> void:
	var look: Dictionary = {}
	if ch and "pid" in ch:
		look = Net.players.get(ch.pid, {}).get("look", {})
	if look.is_empty() and ch and "eid" in ch:
		look = Outfit.random_look(int(ch.eid) * 7919 + 17)
	var key := str(look)
	if key == _look_key:
		return
	_look_key = key
	arms.dress(look)


func _set_layer(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			c.layers = Defs.RENDER_VIEWMODEL
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_set_layer(c)


func _mat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _build_torch() -> void:
	## The flashlight held in the right hand when no weapon is drawn: the player's own torch model if there is one.
	torch_root = Node3D.new()
	add_child(torch_root)
	var md: Dictionary = world.map.item_visual("flashlight") if world and world.map else {}
	var body := MeshInstance3D.new()
	if md.get("mesh"):
		body.mesh = md.mesh
		var sz: Vector3 = md.get("size", Vector3(0.04, 0.04, 0.16))
		# Lens forward: models are authored front -Z; centre them on the hand.
		body.transform = Transform3D(Basis(), Vector3(0, -sz.y * 0.5, sz.z * 0.15)) * (md.get("xf", Transform3D()) as Transform3D)
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.018
		cm.bottom_radius = 0.016
		cm.height = 0.16
		body.mesh = cm
		body.rotation = Vector3(-PI * 0.5, 0, 0)
		body.material_override = _mat(Color(0.1, 0.1, 0.11), 0.45)
	torch_root.add_child(body)
	var lens := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.012
	lm.height = 0.012
	lens.mesh = lm
	lens.position = Vector3(0, 0, -0.085)
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(1.0, 0.95, 0.85)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.95, 0.85)
	lmat.emission_energy_multiplier = 0.0
	lens.material_override = lmat
	lens.name = "Lens"
	torch_root.add_child(lens)
	torch_root.visible = false


func _build_smartab() -> void:
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


func _build_nade() -> void:
	_nade = Node3D.new()
	_nade.name = "Grenade"
	add_child(_nade)
	var md: Dictionary = world.map.item_visual("frag_grenade") if world and world.map else {}
	var mi := MeshInstance3D.new()
	if md.get("mesh"):
		mi.mesh = md.mesh
		var sz: Vector3 = md.get("size", Vector3(0.06, 0.1, 0.06))
		mi.transform = Transform3D(Basis(), Vector3(0, -sz.y * 0.5, 0)) * (md.get("xf", Transform3D()) as Transform3D)
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.032
		sm.height = 0.08
		mi.mesh = sm
		mi.material_override = _mat(Color(0.2, 0.25, 0.15), 0.7)
	_nade.add_child(mi)
	_pin = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.009
	tm.outer_radius = 0.0125
	_pin.mesh = tm
	_pin.material_override = _mat(Color(0.7, 0.7, 0.72), 0.3)
	_pin.position = Vector3(0.025, 0.05, 0)
	_nade.add_child(_pin)
	_nade.visible = false
	_set_layer(_nade)


func _nade_pose(dt: float) -> bool:
	## r14: cooking, the grenade is held up in the right hand, the left hand first pulls the pin (it stays on the
	## left hand's finger) then reaches forward to aim; on release, a quick overarm swing. True while it is shown.
	var cook: float = world.controller.cook_t if world and world.controller else -1.0
	if _cook >= 0.0 and cook < 0.0:
		_nade_t = 0.0
	_cook = cook
	if _nade_t >= 0.0:
		_nade_t += dt
		if _nade_t > 0.36:
			_nade_t = -1.0
	_nade.visible = cook >= 0.0 or (_nade_t >= 0.0 and _nade_t < 0.14)
	if cook < 0.0 and _nade_t < 0.0:
		return false
	var hold := Vector3(0.16, -0.13, -0.33) + Vector3(0, sin(Time.get_ticks_msec() * 0.004) * 0.004, 0)
	var p := hold
	if _nade_t >= 0.0:
		var u := clampf(_nade_t / 0.36, 0.0, 1.0)
		var wind := Vector3(0.24, -0.02, -0.17)
		var out := Vector3(0.06, -0.12, -0.66)
		var down := Vector3(0.0, -0.42, -0.45)
		p = hold.lerp(wind, smoothstep(0.0, 0.3, u)) if u < 0.3 else (wind.lerp(out, smoothstep(0.3, 0.55, u)) if u < 0.55 else out.lerp(down, smoothstep(0.55, 1.0, u)))
	_nade.position = p
	_nade.rotation = Vector3(0.3, -0.4, 0.2)
	# The pin ring comes away with the left hand's pull.
	_pin.visible = cook >= 0.0 and cook < 0.18
	# Right hand round the grenade: palm against its right side, fingers wrapped forward round the body and over the
	# lever (seen from behind: the back of the hand, the grenade showing past the fingers).
	var rb := FpArms.hand_basis(Vector3(-0.1, 0.4, -1.0), Vector3(-1.0, 0.25, 0.1))
	arms.pose("R", p - rb.y * 0.036 + Vector3(0, -0.01, 0.025), rb, POLE_R, FpArms.grip("fore"))
	# Left hand: at the pin for the first moment, then forward.
	if cook >= 0.0 and cook < 0.35:
		var lb := FpArms.hand_basis(Vector3(0.6, 0.2, -1.0), Vector3(0.7, -0.3, 0.0))
		arms.pose("L", p + Vector3(-0.07, 0.03, 0.02).lerp(Vector3(-0.16, 0.02, 0.05), cook / 0.35), lb, POLE_L, FpArms.grip("pinch"))
	else:
		var lb2 := FpArms.hand_basis(Vector3(0.1, 0.5, -1.0), Vector3(0.6, -0.2, -0.5))
		arms.pose("L", Vector3(-0.15, -0.13, -0.5), lb2, POLE_L, FpArms.grip("open"))
	return true


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
	_holo_mat.set_shader_parameter("opacity", float(Settings.get_value("accessibility", "smartab_opacity")))
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


# ------------------------------------------------------------------ the gun in hand

func on_fire() -> void:
	_kick_z = 0.06
	_fire_t = 0.0
	_jolt = Vector3(3.5 if _long else 6.0, randf_range(-1.0, 1.0), randf_range(-2.0, 2.0))
	if _parts.has("cylinder"):
		_cyl_turns += 1


func on_hit(damage: float) -> void:
	_hit = minf(_hit + 0.4 + damage * 0.01, 1.0)


func _equip(wid: String) -> void:
	## New weapon in hand: mesh and moving parts, muzzle, and where the hands hold it.
	if wid != "" and wid != _cur and ch and ch.mode == Motor.GROUND:
		SoundSys.play_local("weapon_draw", -6.0)
	_cur = wid
	_draw = 1.0
	for p in _parts.values():
		(p.node as Node3D).queue_free()
	_parts.clear()
	for p in _props.values():
		(p as Node3D).queue_free()
	_props.clear()
	_clip = []
	_clip_name = ""
	_blend_out = 0.0
	_mag_mode = "gun"
	_drop_t = -1.0
	_slide_locked = false
	var md: Dictionary = world.map.item_visual(wid) if wid != "" else {}
	var sz: Vector3 = md.get("size", Vector3(0.05, 0.1, 0.4))
	_long = wid != "" and Defs.weapon(wid).get("slot", "long") == "long"
	# item_visual centres the model on x/z with its bottom at y = 0; the front is -z. "hold" = [grip, fore-end] as
	# fractions of the length from the muzzle, optionally followed by their heights as fractions of the model height.
	var front := -sz.z * 0.5
	var hold: Array = Defs.weapon(wid).get("hold", [0.6, 0.27] if _long else [0.72, 0.3]) if wid != "" else [0.6, 0.27]
	var gv := float(hold[2]) if hold.size() > 2 else (0.32 if _long else 0.3)
	var fv := float(hold[3]) if hold.size() > 3 else 0.5
	if _long:
		_grip = Vector3(0, sz.y * gv, front + sz.z * float(hold[0]))
		_support = Vector3(0, sz.y * fv, front + sz.z * float(hold[1]))
	else:
		_grip = Vector3(0, sz.y * gv, front + sz.z * float(hold[0]))
		_support = _grip + Vector3(-0.03, -0.02, 0.015)
	_grip_vis = _grip
	var base: Transform3D = Transform3D(Basis(), -_grip) * (md.get("xf", Transform3D()) as Transform3D)
	# The grip sits at the weapon root, so the hand pose below is fixed whatever the model's size.
	var parts: Dictionary = GunModel.parts(wid) if wid != "" else {}
	weapon_mesh.mesh = parts.body.mesh if parts.has("body") else md.get("mesh")
	weapon_mesh.transform = base
	att_root.transform = Transform3D(Basis(), -_grip)
	muzzle.position = Vector3(0, sz.y * (0.7 if _long else 0.75), front - 0.01) - _grip
	_bore_y = muzzle.position.y
	_support -= _grip
	_grip = Vector3.ZERO
	for role in parts:
		if role == "body":
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = parts[role].mesh
		weapon_root.add_child(mi)
		mi.transform = base
		var bb: AABB = base * (parts[role].aabb as AABB)
		_parts[role] = {"node": mi, "base": base, "aabb": bb, "pivot": _pivot(role, bb)}
	if wid != "" and not _long and (not _parts.has("mag") or (_parts.mag.aabb as AABB).size.y < 0.04):
		_pistol_mag(sz)
	_kind = Anims.reload_kind(wid, _parts) if wid != "" else ""
	var sight_meshes := [weapon_mesh.mesh]
	for role in _parts:
		if role in ["slide", "bolt", "barrel"] and _parts[role].node is MeshInstance3D:
			sight_meshes.append((_parts[role].node as MeshInstance3D).mesh)
	_iron_line(sight_meshes, base)
	_anchors_for(sz)
	_build_props()
	_att_sig = "-"
	_last_state = -1
	_set_layer(weapon_root)


func _iron_line(meshes: Array, base: Transform3D) -> void:
	## Finds the gun's own sights on its centre line: the rear sight is the highest point over the receiver (pistols:
	## the back of the slide), the front sight the highest point ahead of it. Aiming without an optic lines the eye up
	## with both, so nothing of the gun rises above the sight line and the crosshair stays clear.
	var rear := Vector3(0, -INF, 0)
	var pts: Array[Vector3] = []
	var every: Array[Vector3] = []
	var r0 := -0.3 if _long else -0.06
	for mesh in meshes:
		if mesh == null:
			continue
		for si in (mesh as Mesh).get_surface_count():
			var vs: PackedVector3Array = (mesh as Mesh).surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in vs:
				var p := base * v
				every.append(p)
				if absf(p.x) > 0.012:
					continue
				pts.append(p)
				if p.z > r0 and p.z < 0.06 and p.y > rear.y:
					rear = p
	if rear.y == -INF:
		_iron_rear = Vector3(0, _bore_y + 0.03, 0.0)
		_iron_front = _iron_rear + Vector3(0, 0, -0.3)
		return
	var front := Vector3(0, -INF, 0)
	var gap := 0.12 if _long else 0.07
	for p in pts:
		if p.z < rear.z - gap and p.y > front.y:
			front = p
	if front.y == -INF:
		front = rear + Vector3(0, 0, -0.3)
	_iron_rear = rear
	_iron_front = front
	# Tilt that levels the line from the rear sight to the front sight (front higher: the nose goes down).
	_iron_pitch = -atan2(front.y - rear.y, rear.z - front.z)
	# Sights a little off the model's centre line: turn the gun so the front post sits over the rear notch.
	_iron_yaw = atan2(front.x - rear.x, rear.z - front.z)
	# Anything else close to the line of sight (a carry handle, a mount, a cocking knob) must stay under the
	# crosshair too: lower the gun until the highest of them is below it.
	var b := _iron_basis()
	var eye := b * rear + Vector3(0.0, 0.0018, _iron_relief())
	_iron_drop = 0.0
	for p in every:
		var q := b * p - eye
		if q.z > -0.03 or absf(q.x) > -q.z * 0.06:
			continue
		_iron_drop = maxf(_iron_drop, q.y + 0.003 * -q.z)


func _iron_relief() -> float:
	## How far in front of the eye the rear sight sits while aiming.
	return 0.13 if _long else 0.36


func _iron_basis() -> Basis:
	return Basis.from_euler(Vector3(_iron_pitch, _iron_yaw, 0.0))


func _pivot(role: String, bb: AABB) -> Vector3:
	var c := bb.get_center()
	match role:
		"bolt":
			return Vector3(0.0, _bore_y if _bore_y != 0.0 else c.y, c.z)
		"barrel":
			return Vector3(0.0, bb.position.y, bb.end.z)
	return c


func _pistol_mag(sz: Vector3) -> void:
	## Handguns keep their magazine inside the grip (the models have none, or only its base plate): a plain one is
	## made to fit, hidden in the grip until a reload pulls it out.
	var h := clampf(sz.y * 0.55, 0.06, 0.12)
	var root := Node3D.new()
	weapon_root.add_child(root)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.022, h, 0.034)
	body.mesh = bm
	body.material_override = _mat(Color(0.07, 0.07, 0.075), 0.45)
	# Grips slope back toward the bottom.
	body.transform = Transform3D(Basis(Vector3.RIGHT, 0.26), Vector3(0.0, -h * 0.5 + 0.01, 0.012))
	root.add_child(body)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.026, 0.008, 0.04)
	plate.mesh = pm
	plate.material_override = body.material_override
	plate.transform = Transform3D(Basis(Vector3.RIGHT, 0.26), body.transform * Vector3(0, -h * 0.5, 0))
	root.add_child(plate)
	var gb := Transform3D(Basis(), Vector3(0, -sz.y * 0.3 + 0.03, 0.0))
	if _parts.has("mag"):
		# The model's base plate rides along with the made-up magazine.
		(_parts.mag.node as Node3D).reparent(root, true)
	var bb := AABB(Vector3(-0.011, -h, -0.017), Vector3(0.022, h, 0.034))
	_parts["mag"] = {"node": root, "base": gb, "aabb": gb * bb, "pivot": (gb * bb).get_center()}
	root.transform = gb


func _anchors_for(sz: Vector3) -> void:
	## Where the hands go on this gun (weapon space), from its parts and proportions.
	var a := {}
	a.grip = Vector3(0.017, -0.004, 0.012) if _long else Vector3(0.016, -0.012, 0.01)
	a.sup = _support + Vector3(-0.008, -0.03, 0.0)
	var mw := Vector3(-0.02, -0.12, -0.12)
	if _parts.has("mag"):
		var mb: AABB = _parts.mag.aabb
		if _long:
			mw = Vector3(mb.position.x - 0.004, mb.position.y + mb.size.y * 0.55, mb.get_center().z)
		else:
			mw = Vector3(0.0, mb.position.y - 0.012, mb.get_center().z + 0.004)
	a.mw = mw
	var top := _bore_y + 0.035
	a.chg_t = Vector3(0.0, top, 0.04)
	a.chg_r = Vector3(0.045, _bore_y + 0.005, -0.13)
	a.chg_f = Vector3(-0.035, _bore_y + 0.015, _support.z - 0.06)
	a.top = Vector3(0.0, top + 0.01, mw.z if _parts.has("mag") else -0.1)
	a.port = Vector3(0.0, _bore_y - 0.05, -0.1)
	a.sl = Vector3(0.0, _bore_y + 0.02, 0.025)
	if _parts.has("slide"):
		var sb: AABB = _parts.slide.aabb
		a.sl = Vector3(sb.get_center().x, sb.end.y, sb.end.z - 0.025)
	a.bolt = Vector3(0.06, _bore_y - 0.01, 0.0)
	if _parts.has("bolt"):
		var bb: AABB = _parts.bolt.aabb
		a.bolt = Vector3(bb.end.x + 0.008, bb.get_center().y, bb.get_center().z)
		a.chg_t = Vector3(bb.get_center().x, bb.end.y + 0.008, bb.get_center().z)
	a.pmp = _support + Vector3(0.0, -0.03, 0.0)
	if _parts.has("pump"):
		var pb: AABB = _parts.pump.aabb
		a.pmp = Vector3(pb.get_center().x - 0.004, pb.position.y - 0.004, pb.get_center().z)
	a.gate = Vector3(0.03, _bore_y - 0.01, -0.02)
	if _parts.has("cylinder"):
		var cb: AABB = _parts.cylinder.aabb
		a.gate = Vector3(cb.end.x, cb.get_center().y, cb.end.z)
	a.brch = Vector3(0.0, _bore_y, -0.12)
	a.bar = _support + Vector3(0.0, -0.025, 0.0)
	a.bar_rear = Vector3(0.0, _bore_y, -0.1)
	if _parts.has("barrel"):
		var rb: AABB = _parts.barrel.aabb
		a.brch = Vector3(0.0, rb.end.y, rb.end.z)
		a.bar = Vector3(0.0, rb.position.y - 0.006, rb.end.z - 0.06)
		a.bar_rear = Vector3(0.0, rb.get_center().y, rb.end.z)
	_anchors = a
	# The magazine in the left hand keeps the pose it had in the gun relative to the grabbing palm.
	if _parts.has("mag"):
		var h := "magL" if _long else "magP"
		var hand := Transform3D(Anims.hand_basis(h), a.mw)
		_mag_rel = hand.affine_inverse() * (_parts.mag.base as Transform3D)


func _build_props() -> void:
	## Rounds, shells and clips the left hand carries during reloads (small, plain, only near the hand).
	var brass := _mat(Color(0.78, 0.6, 0.3), 0.35)
	brass.metallic = 0.8
	var red := _mat(Color(0.55, 0.08, 0.06), 0.6)
	var shell := func(n: int) -> Node3D:
		var r := Node3D.new()
		for i in n:
			var hull := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0105
			cm.bottom_radius = 0.0105
			cm.height = 0.062
			hull.mesh = cm
			hull.material_override = red
			hull.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.012 + 0.024 * i if n > 1 else 0.0, 0, -0.006))
			r.add_child(hull)
			var head := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.0112
			hm.bottom_radius = 0.0112
			hm.height = 0.014
			head.mesh = hm
			head.material_override = brass
			head.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), hull.position + Vector3(0, 0, 0.034))
			r.add_child(head)
		return r
	_props.shell = shell.call(1)
	_props.shells2 = shell.call(2)
	var round := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0035
	rm.bottom_radius = 0.0047
	rm.height = 0.038
	round.mesh = rm
	round.material_override = brass
	round.rotation = Vector3(PI * 0.5, 0, 0)
	var rr := Node3D.new()
	rr.add_child(round)
	_props.round = rr
	var clip := Node3D.new()
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.012, 0.004, 0.06)
	plate.mesh = pm
	plate.material_override = brass
	clip.add_child(plate)
	for i in 5:
		var rd := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.0035
		cm2.bottom_radius = 0.0055
		cm2.height = 0.07
		rd.mesh = cm2
		rd.material_override = brass
		rd.position = Vector3(0, 0.037, -0.024 + i * 0.012)
		clip.add_child(rd)
	_props.clip = clip
	# Two shells sitting in an opened breech (break actions), riding the barrels.
	if _parts.has("barrel"):
		var loaded: Node3D = shell.call(2)
		(_parts.barrel.node as Node3D).add_child(loaded)
		loaded.transform = (_parts.barrel.base as Transform3D).affine_inverse() * Transform3D(Basis(), (_anchors.brch as Vector3) + Vector3(0, -0.012, -0.03))
		_props.loaded2 = loaded
	for k in _props:
		var p: Node3D = _props[k]
		if p.get_parent() == null:
			weapon_root.add_child(p)
		p.visible = false


func _drum_in_well(wid: String, atts: Array) -> void:
	## (r25) A drum takes the place of the gun's own magazine: the magazine part draws nothing and carries the drum,
	## so a reload pulls the drum out and puts it back.
	if not _parts.has("mag") or not (_parts.mag.node is MeshInstance3D):
		return
	var mag: MeshInstance3D = _parts.mag.node
	if not _parts.mag.has("mesh0"):
		_parts.mag["mesh0"] = mag.mesh
	var old := mag.get_node_or_null("WellDrum")
	if old:
		mag.remove_child(old)
		old.queue_free()
	mag.mesh = _parts.mag.mesh0
	var did := AttachVisual.drum_in_well(wid, atts)
	var drum := att_root.get_node_or_null(did) as MeshInstance3D if did != "" else null
	if drum == null:
		return
	mag.mesh = null
	var xf := (_parts.mag.base as Transform3D).affine_inverse() * att_root.transform * drum.transform
	att_root.remove_child(drum)
	drum.name = "WellDrum"
	mag.add_child(drum)
	drum.transform = xf


func _fit_attachments(wid: String, atts: Array) -> void:
	## Draws the fitted attachments and moves what they change: the aim line (sight), the muzzle (device), the
	## support hand (grip) and the weapon light.
	AttachVisual.build(world.map, att_root, wid, atts, Defs.RENDER_VIEWMODEL, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_drum_in_well(wid, atts)
	var md: Dictionary = world.map.item_visual(wid)
	var sz: Vector3 = md.get("size", Vector3(0.05, 0.1, 0.4))
	var front := -sz.z * 0.5
	# Without an optic the eye looks along the gun's own sights: tilted so rear and front sight line up, with their
	# tops just under the crosshair and the rear sight a short way in front of the eye.
	var tilted := _iron_basis() * _iron_rear
	var hip_aim := Vector3(-tilted.x, -tilted.y - 0.0018 - _iron_drop, -_iron_relief() - tilted.z)
	_irons = true
	_aim_pos = hip_aim
	muzzle.position = Vector3(0, sz.y * (0.7 if _long else 0.75), front - 0.01) - _grip_vis
	var hold: Array = Defs.weapon(wid).get("hold", [0.6, 0.27] if _long else [0.72, 0.3])
	if _long:
		var fv := float(hold[3]) if hold.size() > 3 else 0.5
		_support = Vector3(0, sz.y * fv, front + sz.z * float(hold[1])) - _grip_vis
	_light_pt = _support + Vector3(0.0, -0.03, -0.12)
	for a in atts:
		var aid := str(a)
		match Attach.kind(aid):
			"sight":
				var ax := AttachVisual.sight_axis(world.map, wid, aid) - _grip_vis
				var rear := AttachVisual.sight_rear_z(world.map, wid, aid) - _grip_vis.z
				_aim_pos = Vector3(-ax.x, -ax.y, minf(hip_aim.z, -0.075 - rear))
				_irons = false
			"muzzle":
				var amd: Dictionary = world.map.item_visual(aid)
				var mx: Transform3D = AttachVisual.mount_xf(world.map, wid, aid) * (amd.get("xf", Transform3D()) as Transform3D).affine_inverse()
				muzzle.position = mx * Vector3(0, (amd.size as Vector3).y * 0.5, -(amd.size as Vector3).z * 0.5) - _grip_vis
			"grip":
				var gmd: Dictionary = world.map.item_visual(aid)
				var gx: Transform3D = AttachVisual.mount_xf(world.map, wid, aid) * (gmd.get("xf", Transform3D()) as Transform3D).affine_inverse()
				if _long:
					_support = gx * Vector3(0, (gmd.size as Vector3).y * 0.35, 0) - _grip_vis
	_anchors.sup = _support + Vector3(-0.008, -0.03, 0.0)
	for a in atts:
		if Attach.kind(str(a)) == "grip" and _long:
			# A vertical / angled grip is held around its body, not under the handguard.
			_anchors.sup = _support + Vector3(-0.02, -0.02, 0.012)


static func make_laser_dot() -> MeshInstance3D:
	## The small red spot a laser sight puts on whatever it points at (visible to everyone).
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.08, 0.05, 0.9)
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 2.0))
	m.albedo_texture = ImageTexture.create_from_image(img)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	mi.visible = false
	return mi


static func place_laser(dot: MeshInstance3D, space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, exclude: Array) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 60.0, Defs.SHOT_MASK)
	q.exclude = exclude
	var r := space.intersect_ray(q)
	dot.visible = not r.is_empty()
	if dot.visible:
		dot.global_position = (r.position as Vector3) + (r.normal as Vector3) * 0.01


# ------------------------------------------------------------------ animation timing

func _track_clip(dt: float) -> void:
	## Picks the clip for the weapon state and how far into it we are. Reload and cycle times come straight from the
	## weapon state machine's timer, so the hands finish exactly when the rounds go in.
	var wpn = ch.wpn
	var st: int = wpn.state
	var w: Dictionary = wpn.weapon()
	var started := st != _last_state
	if st == WS.RELOAD and _kind != "":
		var phase: int = wpn.reload_phase
		var stepped: bool = started or phase != _last_phase or float(wpn.timer) > _last_timer + 1e-4
		if started:
			_empty = not bool(w.get("chamber", true)) or str(Defs.weapon(_cur).get("feed", "")) == "break"
		if stepped:
			_play(Anims.clip_name(_cur, phase, _parts), maxf(float(wpn.timer), 0.05))
		_last_phase = phase
	elif st == WS.CYCLE:
		if started:
			var fm: String = wpn.fire_mode()
			_play("cycle_pump" if fm == "pump" else "cycle_bolt", maxf(float(wpn.timer), 0.05))
	elif _clip_name != "" and started:
		# The reload or cycle ended (or was cut short by a switch, a fall, the device): fade what is left.
		if _clip_t < 0.97:
			_held_pose = _sample_pose()
			_blend_out = 1.0
		_clip = []
		_clip_name = ""
		_cues = []
		_mag_mode = "gun"
		_drop_t = -1.0
	_last_state = st
	_last_timer = float(wpn.timer)
	if _clip_name != "":
		_clip_t = clampf(1.0 - float(wpn.timer) / _clip_total, 0.0, 1.0)
		while not _cues.is_empty() and float(_cues[0][0]) <= _clip_t:
			SoundSys.play_local(str(_cues[0][1]), -2.0)
			_cues.pop_front()
	_blend_out = move_toward(_blend_out, 0.0, dt / 0.18)
	# Slide lock: a handgun fired empty stays open until the reload.
	_slide_locked = _parts.has("slide") and not _long and int(w.get("mag", 0)) <= 0 and not bool(w.get("chamber", true)) and st != WS.RELOAD


func _play(name: String, total: float) -> void:
	_clip_name = name
	_clip = Anims.filled(Anims.clip(name, _empty, _cur))
	_clip_total = total
	_clip_t = 0.0
	_cues = Anims.cues(name, _empty, _cur)


func _rest_hands() -> Dictionary:
	var l := {"a": "sup", "o": Vector3.ZERO, "h": "sup", "c": "fore"}
	if not _long:
		l = {"a": "grip", "o": Vector3(-0.025, -0.02, 0.0), "h": "psup", "c": "cup"}
	elif _kind == "tube":
		l = {"a": "pmp", "o": Vector3.ZERO, "h": "pump", "c": "fore"}
	return {"L": l, "R": {"a": "grip", "o": Vector3.ZERO, "h": "grip", "c": "pistol"}}


func _sample_pose() -> Dictionary:
	## The clip's pose now: {g, L, R, p, mag, prop}, hands still in anchor form (resolved after the gun is placed).
	var rest := _rest_hands()
	if _clip.is_empty():
		return {"g": [Vector3.ZERO, Vector3.ZERO], "L": [rest.L, rest.L, 0.0], "R": [rest.R, rest.R, 0.0], "p": {}, "mag": "gun", "prop": ""}
	var s := Anims.sample(_clip, _clip_t)
	var a: Dictionary = s.a
	var b: Dictionary = s.b
	var f: float = s.f
	var parts := {}
	for r in a.p:
		var pa: Array = a.p[r]
		var pb: Array = b.p.get(r, pa)
		parts[r] = [(pa[0] as Vector3).lerp(pb[0], f), (pa[1] as Vector3).lerp(pb[1], f)]
	var la: Dictionary = a.L if not (a.L as Dictionary).is_empty() else rest.L
	var lb: Dictionary = b.L if not (b.L as Dictionary).is_empty() else rest.L
	var ra: Dictionary = a.R if not (a.R as Dictionary).is_empty() else rest.R
	var rb: Dictionary = b.R if not (b.R as Dictionary).is_empty() else rest.R
	return {"g": Anims.lerp_g(a.g, b.g, f), "L": [la, lb, f], "R": [ra, rb, f], "p": parts, "mag": a.mag, "prop": a.prop}


func _hand_xf(h: Dictionary) -> Transform3D:
	## A hand key (anchor, offset, pose) as a palm transform in this node's space, through the gun's current place.
	var anchor := str(h.get("a", "grip"))
	var off: Vector3 = h.get("o", Vector3.ZERO)
	var hb := Anims.hand_basis(str(h.get("h", "grip")))
	if anchor == "pouch":
		return Transform3D(hb, Anims.POUCH + off)
	var p: Vector3 = _anchors.get(anchor, Vector3.ZERO) + off
	return weapon_root.transform * Transform3D(hb, p)


func _blend_hand(pair: Array) -> Array:
	## [palm transform, curl] between two hand keys.
	var xa := _hand_xf(pair[0])
	var xb := _hand_xf(pair[1])
	var f: float = pair[2]
	var xf := xa.interpolate_with(xb, f)
	var curl := FpArms.mix_curl(FpArms.grip(str(pair[0].get("c", "relaxed"))), FpArms.grip(str(pair[1].get("c", "relaxed"))), f)
	return [xf, curl]


# ------------------------------------------------------------------ per frame

func update_view(dt: float, tab_held: bool, map_held: bool) -> void:
	if ch == null or not is_instance_valid(ch):
		return
	var wid: String = ch.wpn.current_id()
	if wid != _cur:
		_equip(wid)
	var atts: Array = ch.wpn.weapon().get("att", [])
	var sig := wid + ":" + ",".join(atts)
	if sig != _att_sig:
		_att_sig = sig
		_fit_attachments(wid, atts)
	_dress_arms()
	_draw = move_toward(_draw, 0.0, dt * 2.5)
	_fire_t += dt
	_track_clip(dt)
	# TAB: the weapon goes down and out of the way, the device comes up.
	_tab = move_toward(_tab, 1.0 if tab_held and ch.mode == Motor.GROUND else 0.0, dt / 0.32)
	var busy: bool = ch.light.swapping() or (ch.flags & Character.F_HEAL) != 0
	# Vaulting: the gun drops out of sight fast and comes back up after (only if it was out: the drawn weapon is
	# unchanged, this is just the hands being busy).
	var vaulting: bool = ch.vault_t >= 0.0 or ch.ledge_t >= 0.0 or ch.roll_t >= 0.0
	var nade_busy: bool = _cook >= 0.0 or _nade_t >= 0.0
	_lower = move_toward(_lower, 1.0 if (_tab > 0.0 or busy or ch.held_prop_id >= 0 or vaulting or nade_busy) else 0.0, dt / (0.1 if vaulting else (0.12 if nade_busy else 0.25)))
	# Sprinting carries the gun low and canted (still in view); pulling the trigger ends the sprint and it snaps up.
	_sprint = move_toward(_sprint, 1.0 if ch.sprinting else 0.0, dt / (0.22 if ch.sprinting else 0.1))
	var sp := ease(_sprint, -2.0)
	var e := ease(_tab, -2.0)
	_place_hologram(dt)
	# Weapon pose: hip or aim, offset by the same kick and sway that steer the bullets. Positions are the grip.
	var ads: float = ch.wpn.ads
	var off: Vector2 = ch.wpn.aim_offset_deg(Net.tick)
	var hip := Vector3(0.14, -0.2, -0.3) if _long else Vector3(0.13, -0.19, -0.38)
	var aim := _aim_pos
	var hv := Vector2(ch.velocity.x, ch.velocity.z).length()
	_bob += dt * hv * 1.6
	var motion := str(Settings.get_value("accessibility", "camera_motion"))
	var bob_k := 1.0 if motion == "normal" else (0.4 if motion == "reduced" else 0.15)
	var bob := Vector3(sin(_bob) * 0.004, absf(cos(_bob)) * 0.005, 0) * clampf(hv / 4.0, 0.0, 1.5) * (1.0 - ads * 0.8) * bob_k
	_kick_z = move_toward(_kick_z, 0.0, dt * 0.6)
	_jolt = _jolt.move_toward(Vector3.ZERO, dt * 60.0)
	var pose := _sample_pose()
	var held := _held_pose if _blend_out > 0.0 else {}
	var g: Array = pose.g
	if not held.is_empty():
		g = Anims.lerp_g(g, held.g, ease(_blend_out, 2.0))
	var draw_rot := Vector3(-0.6 * _draw, 0.25 * _draw, 0.35 * _draw)
	var sprint_pos := Vector3(-0.05, -0.06 + absf(sin(_bob)) * 0.012, 0.05) * sp
	var pos := hip.lerp(aim, ads) + bob + sprint_pos + Vector3(0, -0.4 * ease(_lower, -2.0) - 0.25 * _draw, _kick_z) + (g[0] as Vector3)
	weapon_root.position = pos
	var grot: Vector3 = g[1]
	var iron_k := ads if _irons else 0.0
	weapon_root.rotation = Vector3(deg_to_rad(off.y + grot.x + _jolt.x * (1.0 - ads * 0.6)) - 0.9 * _lower - 0.32 * sp + draw_rot.x + _iron_pitch * iron_k,
		deg_to_rad(-off.x + grot.y + _jolt.y) + draw_rot.y + 0.55 * sp + _iron_yaw * iron_k, 0.15 * _lower + 0.35 * sp + deg_to_rad(grot.z + _jolt.z) + draw_rot.z)
	var armed = wid != "" and ch.mode == Motor.GROUND and _lower < 0.98
	# Through a magnified scope the view is the scope picture (HUD overlay); the gun itself would fill the screen.
	weapon_root.visible = armed and not (ch.wpn.scoped() and ads > 0.88)
	_pose_parts(pose, held)
	if armed and Attach.flag(ch.wpn.weapon(), "laser") and _tab < 0.5:
		var b: Basis = cam.global_transform.basis * Basis(Vector3.UP, deg_to_rad(-off.x)) * Basis(Vector3.RIGHT, deg_to_rad(off.y))
		place_laser(laser_dot, get_world_3d().direct_space_state, muzzle_position(), -b.z, [ch.get_rid()])
	else:
		laser_dot.visible = false
	# Unarmed with a flashlight: it is held out in the right hand, lowered while the SmarTab is up.
	var has_torch: bool = ch.inv != null and ch.inv.gear.get("flashlight") != null
	torch_root.visible = wid == "" and has_torch and ch.mode == Motor.GROUND and _tab < 0.6
	if torch_root.visible:
		torch_root.position = Vector3(0.17, -0.2, -0.32) + bob + Vector3(0, -0.3 * e, 0)
		torch_root.rotation = Vector3(0.04, 0.05, 0)
		var lens_m := (torch_root.get_node("Lens") as MeshInstance3D).material_override as StandardMaterial3D
		lens_m.emission_energy_multiplier = 3.0 * ch.light.flicker(Time.get_ticks_msec() / 1000.0, ch.eid) if ch.light.on else 0.0
	_arms(armed, pose, held)
	_place_watch()
	_flashlight(dt)


func _pose_parts(pose: Dictionary, held: Dictionary) -> void:
	var k := ease(_blend_out, 2.0) if not held.is_empty() else 0.0
	for role in _parts:
		var p: Dictionary = _parts[role]
		var node: Node3D = p.node
		var v: Array = pose.p.get(role, [Vector3.ZERO, Vector3.ZERO])
		if k > 0.0:
			var hv: Array = held.p.get(role, [Vector3.ZERO, Vector3.ZERO])
			v = [(v[0] as Vector3).lerp(hv[0], k), (v[1] as Vector3).lerp(hv[1], k)]
		var dpos: Vector3 = v[0]
		var drot: Vector3 = v[1]
		match role:
			"slide":
				# Recoil: back in 30 ms, home in 60 ms; held open when the gun ran dry.
				var t := _fire_t
				var back := (t / 0.03) if t < 0.03 else maxf(0.0, 1.0 - (t - 0.03) / 0.06)
				dpos.z = maxf(dpos.z, 0.028 * back)
				if _slide_locked:
					dpos.z = maxf(dpos.z, 0.028)
			"cylinder":
				drot.z += 360.0 / 7.0 * (float(_cyl_turns) - clampf(1.0 - _fire_t / 0.12, 0.0, 1.0))
		var pv: Vector3 = p.pivot
		var r := Basis.from_euler(Vector3(deg_to_rad(drot.x), deg_to_rad(drot.y), deg_to_rad(drot.z)))
		node.transform = Transform3D(Basis(), dpos) * Transform3D(Basis(), pv) * Transform3D(r, Vector3.ZERO) * Transform3D(Basis(), -pv) * (p.base as Transform3D)
	# The magazine: in the gun, in the left hand, or falling away.
	if _parts.has("mag"):
		var mag: Node3D = _parts.mag.node
		var mode := str(pose.mag)
		if mode != _mag_mode:
			if mode == "drop":
				_drop_t = 0.0
				_drop_xf = weapon_root.transform * mag.transform
			_mag_mode = mode
		mag.visible = true
		match mode:
			"hand":
				var lh: Array = _blend_hand(pose.L)
				mag.transform = weapon_root.transform.affine_inverse() * (lh[0] as Transform3D) * _mag_rel
			"drop":
				_drop_t += get_process_delta_time()
				var t := _drop_t
				var fall := Transform3D(Basis(Vector3.RIGHT, -1.6 * t * t), Vector3(-0.05 * t, -4.9 * t * t, 0.08 * t))
				mag.transform = weapon_root.transform.affine_inverse() * Transform3D(Basis(), _drop_xf.origin) * fall * Transform3D(_drop_xf.basis, Vector3.ZERO)
				mag.visible = t < 0.45
			"none":
				mag.visible = false
	# Carried props ride the left palm.
	var prop := str(pose.prop)
	for name in _props:
		var pn: Node3D = _props[name]
		var on = name == prop
		if name == "loaded2":
			on = prop == "loaded2" or (_clip_name == "break" and _clip_t > 0.7 and _clip_t < 0.86)
			pn.visible = on
			continue
		pn.visible = on
		if on:
			var lh: Array = _blend_hand(pose.L)
			var palm: Transform3D = lh[0]
			pn.transform = weapon_root.transform.affine_inverse() * palm * Transform3D(Basis(), Vector3(0.0, 0.025, -0.04))


func _arms(armed: bool, pose: Dictionary, held: Dictionary) -> void:
	if arms == null or not arms.ok:
		return
	var on_ground: bool = ch.mode in [Motor.GROUND, Motor.DOWNED]
	var scope_hidden: bool = armed and not weapon_root.visible
	arms.visible = on_ground and not scope_hidden and not test_hide_arms
	if arms.visible and (_parkour_hands() or _treat_hands()):
		_nade.visible = false
		return
	if arms.visible and _nade_pose(get_process_delta_time()):
		return
	var k := ease(_blend_out, 2.0) if not held.is_empty() else 0.0
	# Stance: a long gun brings the left shoulder forward and in (the torso turns into the stock); a handgun is held
	# out with both shoulders forward. Both also drop the shoulders a little, so the top of the sleeve (where the
	# arms end: there is no torso) stays below the bottom of the view.
	var stance: float = 1.0 - _lower
	if armed and _long:
		arms.shoulder = {"R": Vector3(-0.01, -0.02, -0.02) * stance, "L": Vector3(0.07, -0.09, -0.09) * stance}
	elif armed:
		arms.shoulder = {"R": Vector3(-0.03, -0.06, -0.05) * stance, "L": Vector3(0.05, -0.09, -0.07) * stance}
	else:
		arms.shoulder = {"R": Vector3.ZERO, "L": Vector3.ZERO}
	# Right hand: weapon grip, else the torch, else folded away below the view.
	if armed:
		var r := _blend_hand(pose.R)
		if k > 0.0:
			var hr := _blend_hand(held.R)
			r = [(r[0] as Transform3D).interpolate_with(hr[0], k), FpArms.mix_curl(r[1], hr[1], k)]
		var rx: Transform3D = r[0]
		arms.pose("R", rx.origin, rx.basis, POLE_R, r[1])
	elif torch_root.visible:
		var tb := torch_root.basis * FpArms.hand_basis(Vector3(-0.3, -0.2, -1.0).rotated(Vector3.FORWARD, 0.0), Vector3.LEFT)
		arms.pose("R", torch_root.position + torch_root.basis * Vector3(0.018, -0.004, 0.03), tb, POLE_R, FpArms.grip("torch"))
	else:
		arms.show_side("R", false)
	# Left hand: the forearm raised across the view, back of the wrist (the watch) toward the eyes while the SmarTab
	# is up; else the gun (handguard, pump, magazine, rounds...).
	if _tab > 0.02:
		var te := ease(_tab, -2.0)
		var palm := Vector3(lerpf(-0.24, -0.075, te), lerpf(-0.66, -0.19, te), lerpf(-0.18, -0.34, te))
		var hb := FpArms.hand_basis(Vector3(0.94, 0.34, -0.1), Vector3(0.05, -0.55, -1.0))
		arms.pose("L", palm, hb, Vector3(-0.5, -1.0, 0.3), FpArms.grip("relaxed"))
	elif armed:
		var l := _blend_hand(pose.L)
		if k > 0.0:
			var hl := _blend_hand(held.L)
			l = [(l[0] as Transform3D).interpolate_with(hl[0], k), FpArms.mix_curl(l[1], hl[1], k)]
		var lx: Transform3D = l[0]
		arms.pose("L", lx.origin, lx.basis, POLE_L, l[1])
	else:
		arms.show_side("L", false)


func _parkour_hands() -> bool:
	## r12: hanging, both hands are on the edge, fingers hooked over it; climbing up they stay planted there (so they
	## sink down the view as the body rises) until the body is over; vaulting, the left hand pushes off the top.
	var climbing: bool = ch.vault_t >= 0.0 and (ch.pk_bits & Parkour.PK_CLIMB) != 0
	var vaulting: bool = ch.vault_t >= 0.0 and not climbing
	if ch.ledge_t < 0.0 and not climbing and not vaulting:
		return false
	arms.shoulder = {"R": Vector3.ZERO, "L": Vector3.ZERO}
	var inv := global_transform.affine_inverse()
	if ch.ledge_t >= 0.0 or climbing:
		var u := 0.0 if ch.ledge_t >= 0.0 else clampf(ch.vault_t / maxf(ch.vault_d, 0.05), 0.0, 1.0)
		if u > 0.72:
			arms.show_side("R", false)
			arms.show_side("L", false)
			return true
		var n: Vector3 = ch.ledge_n
		var into := -Vector3(n.x, 0.0, n.z).normalized()
		var right := into.cross(Vector3.UP).normalized()
		# The first instant the hands slap down on to the edge from above.
		var slap := clampf(1.0 - ch.ledge_t / 0.12, 0.0, 1.0) if ch.ledge_t >= 0.0 else 0.0
		for s in ["R", "L"]:
			var side := 1.0 if s == "R" else -1.0
			var wp: Vector3 = ch.ledge_p + into * 0.07 + right * side * 0.21 + Vector3.UP * (0.025 + 0.12 * slap)
			var fingers := inv.basis * (into * 0.8 + Vector3.DOWN * 0.25 + right * side * 0.15).normalized()
			var palm := inv.basis * Vector3.DOWN
			arms.pose(s, inv * wp, FpArms.hand_basis(fingers, palm), POLE_R if s == "R" else POLE_L, HOOK)
		return true
	var u2 := clampf(ch.vault_t / maxf(ch.vault_d, 0.05), 0.0, 1.0)
	arms.show_side("R", false)
	if u2 > 0.6:
		arms.show_side("L", false)
		return true
	var fwd := Vector3(ch.vault_b.x - ch.vault_a.x, 0.0, ch.vault_b.z - ch.vault_a.z).normalized()
	var left := Vector3.UP.cross(fwd).normalized()
	var wp2: Vector3 = ch.vault_m + Vector3.DOWN * 0.05 + left * 0.17 - fwd * 0.05
	arms.pose("L", inv * wp2, FpArms.hand_basis(inv.basis * (fwd + left * 0.3).normalized(), inv.basis * Vector3.DOWN), POLE_L, FpArms.grip("open"))
	return true


func _treat_hands() -> bool:
	## r12: treating a wound. Bandage: the left forearm comes up across the view and the right hand winds the roll
	## round it, the dressing growing along the arm; other treatments use the same hands without the roll.
	if (ch.flags & Character.F_HEAL) == 0 or ch.ledge_t >= 0.0:
		_heal_t = -1.0
		_bandage_roll.visible = false
		_bandage_wrap.visible = false
		return false
	if _heal_t < 0.0:
		_heal_t = 0.0
		var tr: Dictionary = ch.health.treatment if ch.health else {}
		_heal_item = str(tr.get("item", "bandage"))
	_heal_t += get_process_delta_time()
	var total := float(Defs.item(_heal_item).get("use_time", 2.0))
	var u := clampf(_heal_t / maxf(total, 0.1), 0.0, 1.0)
	var bring := smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.9, 1.0, u))
	arms.shoulder = {"R": Vector3(-0.03, -0.04, -0.04), "L": Vector3(0.05, -0.06, -0.06)}
	# Left forearm across the bottom of the view, palm down, fingers to the right.
	var lp := Vector3(0.0, -0.58, -0.3).lerp(Vector3(0.02, -0.19, -0.37), bring)   # well inside an 80 degree view
	var lfing := Vector3(1.0, 0.06, -0.38).normalized()
	arms.pose("L", lp, FpArms.hand_basis(lfing, Vector3(0.0, -1.0, 0.25)), POLE_L, FpArms.grip("relaxed"))
	var ax := -lfing                                  # from the wrist toward the elbow
	var wrist := lp - lfing * 0.085
	var wrap_len := lerpf(0.02, 0.15, smoothstep(0.08, 0.88, u))
	var e1 := (Vector3.UP - ax * ax.dot(Vector3.UP)).normalized()
	var e2 := ax.cross(e1)
	var bx := e1.cross(ax).normalized()
	_bandage_wrap.visible = _heal_item == "bandage"
	_bandage_wrap.transform = Transform3D(Basis(bx, ax * wrap_len, bx.cross(ax)), wrist + ax * (0.02 + wrap_len * 0.5))
	# Right hand: round and round the forearm at the front of the dressing.
	var c := wrist + ax * (0.03 + wrap_len)
	var ang := _heal_t * TAU * 2.2
	var rp := c + (e1 * cos(ang) + e2 * sin(ang)) * 0.078
	var to_arm := (c - rp).normalized()
	var tangent := ax.cross(to_arm).normalized()
	if bring < 0.5:
		rp = rp.lerp(Vector3(0.12, -0.55, -0.3), 1.0 - bring * 2.0)
	arms.pose("R", rp, FpArms.hand_basis(tangent * 0.6 + to_arm * 0.4, to_arm), POLE_R, FpArms.grip("cup"))
	_bandage_roll.visible = _heal_item == "bandage" and bring > 0.3
	_bandage_roll.transform = Transform3D(Basis(tangent, ax, tangent.cross(ax)), rp + to_arm * 0.035)
	return true


func muzzle_position() -> Vector3:
	return muzzle.global_position if weapon_root.visible else cam.global_position


func _flashlight(dt: float) -> void:
	var on: bool = ch.light.on and ch.mode == Motor.GROUND
	light.visible = on
	if not on:
		return
	var wid: String = ch.wpn.current_id()
	var off: Vector2 = ch.wpn.aim_offset_deg(Net.tick)
	if ch.light.weapon_mounted:
		light.position = weapon_root.position + weapon_root.basis * _light_pt
		light.rotation = weapon_root.rotation
	elif _long and wid != "":
		# Shoulder clip: lower, follows the body and only half of the view pitch.
		light.position = Vector3(-0.14, -0.32, -0.1)
		light.rotation = Vector3(-cam.rotation.x * 0.5, 0, 0)
	elif wid != "":
		# Held under the handgun in the support hand.
		light.position = weapon_root.position + weapon_root.basis * (_support + Vector3(0.0, -0.04, -0.06))
		light.rotation = Vector3(deg_to_rad(off.y), deg_to_rad(-off.x), 0)
	else:
		light.position = torch_root.position + Vector3(0, 0, -0.1)
		light.rotation = torch_root.rotation
	var e := float(Defs.flashlight.get("weapon_light_energy" if ch.light.weapon_mounted else "spot_energy", 6.5))
	light.light_energy = e * ch.light.flicker(Time.get_ticks_msec() / 1000.0, ch.eid)
	light.spot_angle = float(Defs.flashlight.get("weapon_light_angle" if ch.light.weapon_mounted else "spot_angle_deg", 26.0))
