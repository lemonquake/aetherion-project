extends Node3D
## How a character looks and sounds to everyone else: the body model with its clip library, hands held on the
## weapon by IK, the flashlight beam as other players see it, the parachute canopy, and footsteps that depend on
## the surface and the gait. The local player's own body is hidden from their camera but still casts a shadow.

const BODY := "res://assets/models/sleep/characters/stranger.glb"
const Footsteps := preload("res://src/audio/footsteps.gd")
const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")
const ViewModel := preload("res://src/player/viewmodel.gd")
const Outfit := preload("res://src/player/outfit.gd")

var world = null
var ch = null
var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var weapon_node: Node3D
var weapon_mesh: MeshInstance3D
var light: SpotLight3D
var light_glow: MeshInstance3D
var canopy: Node3D
var ik: TwoBoneIK3D
var _hand_r: Node3D
var _hand_l: Node3D
var _pole_r: Node3D
var _pole_l: Node3D
var _cur_anim := ""
var _cur_weapon := "-"
var _cur_att := -1
var att_root: Node3D
var laser_dot: MeshInstance3D
var _steps = null
var _radio_t := 0.0
var _tint: Color
static var _body_scene: PackedScene
## Level of detail for other players (50 to a match, most of them far away): beyond 30 m the skeleton is posed every
## 2nd frame, beyond 70 m every 4th, beyond 140 m every 8th, and the hands' IK runs only within 30 m.
var _cam_d := 0.0
var _anim_acc := 0.0
var _anim_frame := 0
var _anim_manual := false


func setup(w, c) -> void:
	world = w
	ch = c
	if _body_scene == null and ResourceLoader.exists(BODY):
		_body_scene = load(BODY)
	if _body_scene:
		model = _body_scene.instantiate()
		add_child(model)
		model.rotation.y = PI  # the clip library faces -Y in Blender (+Z in Godot); characters face -Z
		skel = _find(model, "Skeleton3D")
		anim = _find(model, "AnimationPlayer")
		_dress()
		_setup_ik()
	if ch.is_local:
		# Own body: invisible to the first-person camera, shadows only.
		_set_layers(self, Defs.RENDER_LOCAL_BODY)
		for gi in _all(self, "GeometryInstance3D"):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		_set_layers(self, Defs.RENDER_CHARACTERS)
	weapon_node = Node3D.new()
	weapon_node.name = "WeaponPivot"
	add_child(weapon_node)
	weapon_mesh = MeshInstance3D.new()
	weapon_node.add_child(weapon_mesh)
	att_root = Node3D.new()
	weapon_node.add_child(att_root)
	if ch.is_local:
		weapon_mesh.layers = Defs.RENDER_LOCAL_BODY
		weapon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		laser_dot = ViewModel.make_laser_dot()
		add_child(laser_dot)
	if not ch.is_local:
		light = SpotLight3D.new()
		light.shadow_enabled = bool(Settings.get_value("graphics", "flashlight_shadows"))
		light.spot_range = float(Defs.flashlight.get("spot_range", 34.0))
		light.spot_angle = float(Defs.flashlight.get("spot_angle_deg", 26.0))
		light.spot_attenuation = 1.2
		light.light_energy = float(Defs.flashlight.get("spot_energy", 6.5))
		light.light_color = Color(1.0, 0.95, 0.85)
		light.light_volumetric_fog_energy = 0.35
		light.spot_angle_attenuation = 3.0
		light.visible = false
		add_child(light)
		# The lit lens is visible from the front even when the beam points away.
		light_glow = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.025
		sm.height = 0.05
		light_glow.mesh = sm
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = Color(1, 0.96, 0.88)
		gm.emission_enabled = true
		gm.emission = Color(1, 0.96, 0.88)
		gm.emission_energy_multiplier = 6.0
		light_glow.material_override = gm
		light_glow.visible = false
		add_child(light_glow)
	canopy = _make_canopy()
	canopy.visible = false
	add_child(canopy)
	_steps = Footsteps.new(world, ch)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _all(n: Node, cls: String) -> Array:
	var out := []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_all(c, cls))
	return out


func _set_layers(n: Node, layers: int) -> void:
	for gi in _all(n, "VisualInstance3D"):
		if not (gi is Light3D):
			gi.layers = layers


func _dress() -> void:
	## The player's outfit (data/cosmetics.json) in place of the hooded body: head and hands, then one mesh for
	## everything worn (two draw calls instead of the body's eight).
	var look: Dictionary = Net.players.get(ch.pid, {}).get("look", {})
	if look.is_empty():
		look = Outfit.random_look(ch.eid * 7919 + 17)
	if not Outfit.ensure():
		_tint_clothes()
		return
	for mi in _all(model, "MeshInstance3D"):
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	Outfit.dress(skel, look, Defs.RENDER_CHARACTERS, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func _tint_clothes() -> void:
	## Each player gets a different hoodie colour, so a team can tell its members apart in the dark.
	var palette := [Color(0.08, 0.08, 0.09), Color(0.16, 0.2, 0.14), Color(0.22, 0.12, 0.1), Color(0.12, 0.14, 0.22),
		Color(0.3, 0.28, 0.24), Color(0.1, 0.18, 0.2), Color(0.26, 0.1, 0.14), Color(0.18, 0.18, 0.18)]
	_tint = palette[ch.eid % palette.size()]
	for mi in _all(model, "MeshInstance3D"):
		var m: MeshInstance3D = mi
		for i in m.get_surface_override_material_count():
			var mat := m.get_active_material(i)
			if mat is StandardMaterial3D and str(mat.resource_name).to_lower().find("hood") >= 0:
				var nm: StandardMaterial3D = mat.duplicate()
				nm.albedo_color = _tint
				m.set_surface_override_material(i, nm)


func _setup_ik() -> void:
	if skel == null or not ClassDB.class_exists("TwoBoneIK3D"):
		return
	_hand_r = Node3D.new()
	_hand_l = Node3D.new()
	_pole_r = Node3D.new()
	_pole_l = Node3D.new()
	for n in [_hand_r, _hand_l, _pole_r, _pole_l]:
		add_child(n)
	ik = TwoBoneIK3D.new()
	skel.add_child(ik)
	ik.set_setting_count(2)
	var defs := [["upper_arm.R", "forearm.R", "hand.R", _hand_r, _pole_r], ["upper_arm.L", "forearm.L", "hand.L", _hand_l, _pole_l]]
	for i in 2:
		ik.set_root_bone_name(i, defs[i][0])
		ik.set_middle_bone_name(i, defs[i][1])
		ik.set_end_bone_name(i, defs[i][2])
		ik.set_target_node(i, ik.get_path_to(defs[i][3]))
		ik.set_pole_node(i, ik.get_path_to(defs[i][4]))
	ik.active = false


# ------------------------------------------------------------------ per frame

func _process(dt: float) -> void:
	if ch == null or not is_instance_valid(ch):
		return
	var mode: int = ch.mode
	visible = mode not in [Motor.PLANE, Motor.DEAD, Motor.SPECTATE]
	if not visible:
		return
	rotation = Vector3(0, ch.yaw if mode != Motor.CHUTE else ch.chute_yaw, 0)
	var cam := get_viewport().get_camera_3d() if not ch.is_local else null
	_cam_d = cam.global_position.distance_to(global_position) if cam else 0.0
	canopy.visible = mode == Motor.CHUTE
	if canopy.visible:
		canopy.position = Vector3(0, 5.2, 0.6)
		canopy.rotation = Vector3(0.12 if (ch.flags & Character.F_FLARE) == 0 else -0.25, 0, sin(Time.get_ticks_msec() * 0.0011) * 0.04)
	_animate(dt)
	_weapon(dt)
	_flashlight(dt)
	if mode in [Motor.GROUND, Motor.DOWNED]:
		_steps.update(dt)
	_radio(dt)


func _animate(dt: float) -> void:
	if anim == null:
		return
	var v: Vector3 = ch.velocity
	var local := Basis(Vector3.UP, -ch.yaw) * v
	var speed := Vector2(v.x, v.z).length()
	var flags: int = ch.flags
	var want := "idle"
	var spd := 1.0
	match ch.mode:
		Motor.FREEFALL:
			want = "knockback"
		Motor.CHUTE:
			want = "idle"
		Motor.DOWNED:
			want = "knockdown"
		_:
			if not ch.is_on_floor() and absf(v.y) > 3.0:
				want = "knockback" if v.y < -6.0 else "idle"
			elif (flags & Character.F_CROUCH) != 0 or ch.crouch > 0.5:
				want = "crouch_walk"
				spd = clampf(speed / 1.2, 0.0, 1.4)
				if speed < 0.2:
					spd = 0.0
			elif speed > 5.0:
				want = "run"
				spd = speed / 5.8
			elif speed > 0.4:
				if local.z > 0.3 and absf(local.z) > absf(local.x):
					want = "walk_back"
				elif absf(local.x) > absf(local.z):
					want = "strafe_l" if local.x < 0.0 else "strafe_r"
				else:
					want = "walk_hurt" if (flags & Character.F_LIMP) else "walk"
				spd = speed / 1.6
			else:
				want = "idle_hurt" if (flags & Character.F_LIMP) else "idle"
	if not anim.has_animation(want):
		want = "idle"
	if want != _cur_anim:
		anim.play(want, 0.2)
		_cur_anim = want
	anim.speed_scale = spd
	var every := 1 if _cam_d < 30.0 else (2 if _cam_d < 70.0 else (4 if _cam_d < 140.0 else 8))
	if (every > 1) != _anim_manual:
		_anim_manual = every > 1
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if _anim_manual else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	if _anim_manual:
		_anim_acc += dt
		_anim_frame += 1
		if (_anim_frame + ch.eid) % every == 0:
			anim.advance(_anim_acc)
			_anim_acc = 0.0


func _weapon(dt: float) -> void:
	var wid: String = ch.weapon_id
	var att_mask: int = Attach.bitmask(ch.wpn.weapon()) if ch.is_local else ch.weapon_att
	if wid != _cur_weapon or att_mask != _cur_att:
		_cur_weapon = wid
		_cur_att = att_mask
		var md: Dictionary = world.map.item_visual(wid) if wid != "" and world.map else {}
		weapon_mesh.mesh = md.get("mesh")
		weapon_mesh.transform = _weapon_xf(wid, md)
		att_root.transform = weapon_mesh.transform * (md.get("xf", Transform3D()) as Transform3D).affine_inverse()
		if world.map:
			AttachVisual.build(world.map, att_root, wid, Attach.from_bitmask(att_mask),
				Defs.RENDER_LOCAL_BODY if ch.is_local else Defs.RENDER_CHARACTERS,
				GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if ch.is_local else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var armed: bool = wid != "" and ch.mode == Motor.GROUND and (ch.flags & Character.F_TAB) == 0
	weapon_mesh.visible = armed
	att_root.visible = armed
	if laser_dot:
		if armed and Attach.flag({"att": Attach.from_bitmask(att_mask)}, "laser") and is_inside_tree():
			var cam := get_viewport().get_camera_3d()
			if cam and cam.global_position.distance_to(global_position) < 70.0:
				var b: Basis = Basis.from_euler(Vector3(ch.pitch, ch.yaw, 0))
				ViewModel.place_laser(laser_dot, get_world_3d().direct_space_state, weapon_node.global_transform * Vector3(0, 0, -0.6), -b.z, [ch.get_rid()])
			else:
				laser_dot.visible = false
		else:
			laser_dot.visible = false
	# The weapon pivots at the shoulder line and follows the aim pitch.
	var h: float = ch.height()
	var aim = (ch.flags & Character.F_AIM) != 0
	weapon_node.position = Vector3(0.12 if not aim else 0.06, h - 0.38, -0.15)
	weapon_node.rotation = Vector3(ch.pitch if armed else -0.6, 0, 0)
	if ik:
		var near_ik: bool = armed and (ch.is_local or _cam_d < 30.0)
		ik.active = near_ik
		if near_ik:
			var long: bool = Defs.weapon(wid).get("slot", "long") == "long"
			_hand_r.global_transform = weapon_node.global_transform * Transform3D(Basis(), Vector3(0, -0.05, -0.12 if long else -0.3))
			_hand_l.global_transform = weapon_node.global_transform * Transform3D(Basis(), Vector3(-0.02, -0.05, -0.45 if long else -0.28))
			_pole_r.global_position = global_transform * Vector3(0.6, h - 0.8, 0.2)
			_pole_l.global_position = global_transform * Vector3(-0.6, h - 0.8, 0.0)


func _weapon_xf(wid: String, md: Dictionary) -> Transform3D:
	var xf: Transform3D = md.get("xf", Transform3D())
	if md.has("size"):
		# Item visuals sit on the ground; lift them to be held: barrel along -Z, grip near the pivot.
		var sz: Vector3 = md.size
		var long: bool = Defs.weapon(wid).get("slot", "long") == "long"
		return Transform3D(Basis(), Vector3(0, -0.06, -sz.z * (0.35 if long else 0.2))) * xf
	return xf


func _flashlight(dt: float) -> void:
	if light == null:
		return
	var on: bool = (ch.flags & Character.F_LIGHT) != 0 and ch.mode in [Motor.GROUND]
	light.visible = on
	light_glow.visible = on
	if not on:
		return
	var weapon_mounted = (ch.flags & Character.F_WLIGHT) != 0
	var h: float = ch.height()
	var aim_b := Basis.from_euler(Vector3(ch.pitch, 0, 0))
	var long: bool = ch.weapon_id != "" and Defs.weapon(ch.weapon_id).get("slot", "long") == "long"
	var pos: Vector3
	var basis := aim_b
	if weapon_mounted:
		pos = weapon_node.position + aim_b * Vector3(0.0, -0.03, -0.55)
	elif long:
		# Clipped to the shoulder strap: follows the body, half the pitch.
		pos = Vector3(-0.12, h - 0.45, -0.18)
		basis = Basis.from_euler(Vector3(ch.pitch * 0.5, 0, 0))
	elif ch.weapon_id != "":
		pos = weapon_node.position + aim_b * Vector3(-0.06, -0.02, -0.32)
	else:
		pos = Vector3(0.22, h - 0.55, -0.35)
	light.position = pos
	light.basis = basis
	light_glow.position = pos + basis * Vector3(0, 0, -0.04)
	var low = (ch.flags & Character.F_LOWBAT) != 0
	var k := 1.0
	if low:
		var t := Time.get_ticks_msec() / 1000.0 * float(Defs.flashlight.get("low_flicker_rate", 0.9)) + float(ch.eid) * 3.17
		var n := sin(t * 7.1) * 0.5 + sin(t * 13.3 + 1.7) * 0.3 + sin(t * 2.3) * 0.2
		k = 0.55 * (1.0 - (0.8 if n > 0.82 else 0.0))
	var base_e := float(Defs.flashlight.get("weapon_light_energy" if weapon_mounted else "spot_energy", 6.5))
	light.light_energy = base_e * k
	light.spot_angle = float(Defs.flashlight.get("weapon_light_angle" if weapon_mounted else "spot_angle_deg", 26.0))


func _radio(dt: float) -> void:
	## The faint static of a keyed radio while a player transmits to their team.
	if (ch.flags & Character.F_RADIO) == 0:
		SoundSys.stop_loop("radio_%d" % ch.eid)
		return
	SoundSys.start_loop("radio_%d" % ch.eid, "radio_static", ch.global_position + Vector3.UP * 1.35)
	SoundSys.update_loop("radio_%d" % ch.eid, ch.global_position + Vector3.UP * 1.35)


func on_mode(mode: int) -> void:
	pass


func _make_canopy() -> Node3D:
	## A ram-air canopy: a curved, ribbed wing with lines down to the harness.
	var n := Node3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 9
	var span := 7.5
	var chord := 2.6
	for i in cells:
		var a0 := -0.55 + 1.1 * float(i) / cells
		var a1 := -0.55 + 1.1 * float(i + 1) / cells
		var x0 := sin(a0) * span * 0.5
		var x1 := sin(a1) * span * 0.5
		var y0 := cos(a0) * 1.6 - 1.6
		var y1 := cos(a1) * 1.6 - 1.6
		var q := [Vector3(x0, y0, -chord * 0.5), Vector3(x1, y1, -chord * 0.5), Vector3(x1, y1, chord * 0.5), Vector3(x0, y0, chord * 0.5)]
		for tri in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:
			for k in tri:
				st.add_vertex(q[k])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.24, 0.17)
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	n.add_child(mi)
	var lines := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in 6:
		var x := -span * 0.42 + span * 0.84 * i / 5.0
		im.surface_add_vertex(Vector3(x, cos(asin(clampf(x / (span * 0.5), -1, 1))) * 1.6 - 1.6, 0))
		im.surface_add_vertex(Vector3(0, -4.0, -0.5))
	im.surface_end()
	lines.mesh = im
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.05, 0.05, 0.05)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines.material_override = lm
	n.add_child(lines)
	return n
