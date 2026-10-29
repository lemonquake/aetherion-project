extends Node3D
## How a character looks and sounds to everyone else: the body model with its clip library, hands held on the
## weapon by analytical two-bone IK and upper-body aim/sprint posture, the flashlight beam as other players see it,
## the parachute canopy, and footsteps that depend on the surface and the gait. The local player's own body is
## hidden from their camera but still casts a shadow.

const BODY := "res://assets/models/sleep/characters/stranger.glb"
const Footsteps := preload("res://src/audio/footsteps.gd")
const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")
const ViewModel := preload("res://src/player/viewmodel.gd")
const Outfit := preload("res://src/player/outfit.gd")

const LOOP_ANIMS := [
	"idle", "idle_adjust", "idle_hurt", "idle_look",
	"walk", "hero_walk", "walk_hurt", "walk_back",
	"strafe_l", "strafe_r",
	"run", "hero_run", "run_hurt",
	"crouch_walk", "carry_box",
]

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
var ik: SkeletonModifier3D
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

# Cached bone indices and rest lengths for upper-body posture & analytical two-bone arm IK
var _b_hips := -1
var _b_spine := -1
var _b_chest := -1
var _b_neck := -1
var _b_head := -1
var _b_sh_l := -1
var _b_ua_l := -1
var _b_fa_l := -1
var _b_ha_l := -1
var _b_sh_r := -1
var _b_ua_r := -1
var _b_fa_r := -1
var _b_ha_r := -1
var _l1_r := 0.28
var _l2_r := 0.26
var _l1_l := 0.28
var _l2_l := 0.26
var _grip_local := Vector3.ZERO
var _support_local := Vector3(0.0, 0.01, -0.28)
var _is_long := true
var _sprint_blend := 0.0
var _stride_phase := 0.0


class TacticalPoseModifier extends SkeletonModifier3D:
	var vis = null

	func _process_modification() -> void:
		if vis != null and is_instance_valid(vis):
			vis._apply_tactical_pose()


func setup(w, c) -> void:
	world = w
	ch = c
	if _body_scene == null and ResourceLoader.exists(BODY):
		_body_scene = load(BODY)
	weapon_node = Node3D.new()
	weapon_node.name = "WeaponPivot"
	add_child(weapon_node)
	weapon_mesh = MeshInstance3D.new()
	weapon_node.add_child(weapon_mesh)
	att_root = Node3D.new()
	weapon_node.add_child(att_root)
	if _body_scene:
		model = _body_scene.instantiate()
		add_child(model)
		model.rotation.y = PI  # the clip library faces -Y in Blender (+Z in Godot); characters face -Z
		skel = _find(model, "Skeleton3D")
		anim = _find(model, "AnimationPlayer")
		_setup_anims()
		_dress()
		_setup_ik()
	if ch.is_local:
		# Own body: invisible to the first-person camera, shadows only.
		_set_layers(self, Defs.RENDER_LOCAL_BODY)
		for gi in _all(self, "GeometryInstance3D"):
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		_set_layers(self, Defs.RENDER_CHARACTERS)
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


func _setup_anims() -> void:
	if anim == null:
		return
	for a_name in LOOP_ANIMS:
		if anim.has_animation(a_name):
			var a: Animation = anim.get_animation(a_name)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR


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
	if skel == null:
		return
	_b_hips = skel.find_bone("hips")
	_b_spine = skel.find_bone("spine")
	_b_chest = skel.find_bone("chest")
	_b_neck = skel.find_bone("neck")
	_b_head = skel.find_bone("head")
	_b_sh_l = skel.find_bone("shoulder.L")
	_b_ua_l = skel.find_bone("upper_arm.L")
	_b_fa_l = skel.find_bone("forearm.L")
	_b_ha_l = skel.find_bone("hand.L")
	_b_sh_r = skel.find_bone("shoulder.R")
	_b_ua_r = skel.find_bone("upper_arm.R")
	_b_fa_r = skel.find_bone("forearm.R")
	_b_ha_r = skel.find_bone("hand.R")
	if _b_ua_r >= 0 and _b_fa_r >= 0 and _b_ha_r >= 0:
		_l1_r = skel.get_bone_global_rest(_b_ua_r).origin.distance_to(skel.get_bone_global_rest(_b_fa_r).origin)
		_l2_r = skel.get_bone_global_rest(_b_fa_r).origin.distance_to(skel.get_bone_global_rest(_b_ha_r).origin)
	if _b_ua_l >= 0 and _b_fa_l >= 0 and _b_ha_l >= 0:
		_l1_l = skel.get_bone_global_rest(_b_ua_l).origin.distance_to(skel.get_bone_global_rest(_b_fa_l).origin)
		_l2_l = skel.get_bone_global_rest(_b_fa_l).origin.distance_to(skel.get_bone_global_rest(_b_ha_l).origin)
	_hand_r = Node3D.new()
	_hand_l = Node3D.new()
	_pole_r = Node3D.new()
	_pole_l = Node3D.new()
	for n in [_hand_r, _hand_l, _pole_r, _pole_l]:
		add_child(n)
	var mod := TacticalPoseModifier.new()
	mod.name = "TacticalPoseModifier"
	mod.vis = self
	skel.add_child(mod)
	mod.active = true
	ik = mod


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
	var is_sprinting: bool = ((flags & Character.F_SPRINT) != 0 or bool(ch.sprinting)) and speed > 2.2 and (flags & Character.F_CROUCH) == 0 and ch.crouch < 0.4
	_sprint_blend = move_toward(_sprint_blend, 1.0 if is_sprinting else 0.0, dt * 6.5)
	_stride_phase = fposmod(_stride_phase + dt * maxf(speed * 1.85, 1.5), TAU)
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
			var airborne: bool = (not ch.is_remote and not ch.is_on_floor() and absf(v.y) > 2.4) or (ch.is_remote and absf(v.y) > 3.5 and absf(v.y) > speed * 0.75)
			if airborne and v.y < -6.0:
				want = "knockback"
			elif (flags & Character.F_CROUCH) != 0 or ch.crouch > 0.5:
				want = "crouch_walk"
				spd = clampf(speed / 1.35, 0.0, 1.45)
				if speed < 0.18:
					spd = 0.0
			elif is_sprinting or speed > 4.6:
				if (flags & Character.F_LIMP) != 0 and anim.has_animation("run_hurt"):
					want = "run_hurt"
				elif anim.has_animation("hero_run"):
					want = "hero_run"
				else:
					want = "run"
				spd = clampf(speed / 5.1, 0.92, 1.35)
			elif speed > 0.35:
				if local.z > 0.35 and absf(local.z) >= absf(local.x) * 0.85:
					want = "walk_back"
					spd = clampf(speed / 2.2, 0.75, 1.45)
				elif absf(local.x) > absf(local.z) * 1.15:
					want = "strafe_l" if local.x < 0.0 else "strafe_r"
					spd = clampf(speed / 2.5, 0.75, 1.55)
				elif speed > 3.15 and (flags & Character.F_WALK) == 0:
					want = "run_hurt" if ((flags & Character.F_LIMP) != 0 and anim.has_animation("run_hurt")) else "run"
					spd = clampf(speed / 4.2, 0.82, 1.22)
				else:
					want = "walk_hurt" if (flags & Character.F_LIMP) != 0 else "walk"
					spd = clampf(speed / 2.1, 0.75, 1.45)
			else:
				want = "idle_hurt" if (flags & Character.F_LIMP) != 0 else "idle"
	if not anim.has_animation(want):
		want = "idle"
	if want != _cur_anim:
		anim.play(want, 0.18)
		_cur_anim = want
	elif not anim.is_playing() and spd > 0.0:
		anim.play(want)
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
		weapon_mesh.transform = _weapon_xf(wid, md, att_mask)
		att_root.transform = Transform3D(Basis(), -_grip_local)
		if world.map:
			AttachVisual.build(world.map, att_root, wid, Attach.from_bitmask(att_mask),
				Defs.RENDER_LOCAL_BODY if ch.is_local else Defs.RENDER_CHARACTERS,
				GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if ch.is_local else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var armed: bool = wid != "" and ch.mode == Motor.GROUND and (ch.flags & Character.F_TAB) == 0
	weapon_mesh.visible = armed
	att_root.visible = armed
	if ik:
		ik.active = ch.mode == Motor.GROUND and (ch.is_local or _cam_d < 35.0)
	if not armed or ik == null or not ik.active:
		var h: float = ch.height()
		var aim: bool = (ch.flags & Character.F_AIM) != 0
		weapon_node.position = Vector3(0.11 if not aim else 0.06, h - 0.38, -0.22)
		weapon_node.rotation = Vector3(ch.pitch if armed else -0.6, 0.08 if armed else 0.0, 0.0)
	if laser_dot:
		if armed and Attach.flag({"att": Attach.from_bitmask(att_mask)}, "laser") and is_inside_tree():
			var cam := get_viewport().get_camera_3d()
			if cam and cam.global_position.distance_to(global_position) < 70.0:
				var b: Basis = Basis.from_euler(Vector3(ch.pitch, ch.yaw, 0))
				ViewModel.place_laser(laser_dot, get_world_3d().direct_space_state, weapon_node.global_transform * Vector3(0, 0, -0.45), -b.z, [ch.get_rid()])
			else:
				laser_dot.visible = false
		else:
			laser_dot.visible = false


func _weapon_xf(wid: String, md: Dictionary, att_mask: int = 0) -> Transform3D:
	var xf: Transform3D = md.get("xf", Transform3D())
	_is_long = wid == "" or Defs.weapon(wid).get("slot", "long") == "long"
	var sz: Vector3 = md.get("size", Vector3(0.08, 0.14, 0.78) if _is_long else Vector3(0.05, 0.13, 0.20))
	var front := -sz.z * 0.5
	var hold: Array = Defs.weapon(wid).get("hold", [0.6, 0.27] if _is_long else [0.72, 0.3]) if wid != "" else [0.6, 0.27]
	var gv := float(hold[2]) if hold.size() > 2 else (0.32 if _is_long else 0.3)
	var fv := float(hold[3]) if hold.size() > 3 else 0.5
	_grip_local = Vector3(0.0, sz.y * gv, front + sz.z * float(hold[0]))
	if _is_long:
		var sup := Vector3(0.0, sz.y * fv, front + sz.z * float(hold[1]))
		if world and world.map and att_mask != 0:
			for a in Attach.from_bitmask(att_mask):
				var aid := str(a)
				if Attach.kind(aid) == "grip":
					var gmd: Dictionary = world.map.item_visual(aid)
					if not gmd.is_empty():
						var gx: Transform3D = AttachVisual.mount_xf(world.map, wid, aid) * (gmd.get("xf", Transform3D()) as Transform3D).affine_inverse()
						sup = gx * Vector3(0.0, (gmd.size as Vector3).y * 0.35, 0.0)
		_support_local = sup - _grip_local
		_support_local.z = clampf(_support_local.z, -0.34, -0.16)
	else:
		_support_local = Vector3(-0.026, -0.018, 0.018)
	return Transform3D(Basis(), -_grip_local) * xf


func _apply_tactical_pose() -> void:
	if skel == null or ch == null or not is_instance_valid(ch) or ch.mode != Motor.GROUND:
		return
	var wid: String = ch.weapon_id
	var armed: bool = wid != "" and (ch.flags & Character.F_TAB) == 0
	var aim: bool = (ch.flags & Character.F_AIM) != 0
	var fired: bool = (ch.flags & Character.F_FIRED) != 0
	var sp: float = _sprint_blend if (not aim and not fired) else 0.0
	var pitch: float = clampf(ch.pitch, -1.25, 1.25)

	# 1. Upper-body posture (spine, chest, neck, head) in Skeleton3D space (+Z is forward, -X is right, +X is left)
	# Pitching UP (+ch.pitch) is negative rotation around +X_skel; leaning forward into a sprint is positive around +X_skel.
	var torso_pitch_skel: float = -pitch * (1.0 - 0.55 * sp) + sp * 0.22
	var bladed_yaw_skel: float = (-0.16 if _is_long else -0.06) * (1.0 - 0.5 * sp) if armed else 0.0

	if _b_spine >= 0:
		var sr := skel.get_bone_pose_rotation(_b_spine)
		var q_sp := Quaternion.from_euler(Vector3(torso_pitch_skel * 0.25, bladed_yaw_skel * 0.35, 0.0))
		skel.set_bone_pose_rotation(_b_spine, sr * q_sp)
	if _b_chest >= 0:
		var cr := skel.get_bone_pose_rotation(_b_chest)
		var q_ch := Quaternion.from_euler(Vector3(torso_pitch_skel * 0.38, bladed_yaw_skel * 0.65, 0.0))
		skel.set_bone_pose_rotation(_b_chest, cr * q_ch)
	if _b_neck >= 0:
		var nr := skel.get_bone_pose_rotation(_b_neck)
		var q_nk := Quaternion.from_euler(Vector3(-pitch * 0.18 - sp * 0.08, -bladed_yaw_skel * 0.45, 0.0))
		skel.set_bone_pose_rotation(_b_neck, nr * q_nk)
	if _b_head >= 0:
		var hr := skel.get_bone_pose_rotation(_b_head)
		var q_hd := Quaternion.from_euler(Vector3(-pitch * 0.24 - sp * 0.12, -bladed_yaw_skel * 0.55, 0.0))
		skel.set_bone_pose_rotation(_b_head, hr * q_hd)

	if not armed:
		if _b_sh_l >= 0:
			skel.set_bone_pose_rotation(_b_sh_l, skel.get_bone_rest(_b_sh_l).basis.get_rotation_quaternion())
		if _b_sh_r >= 0:
			skel.set_bone_pose_rotation(_b_sh_r, skel.get_bone_rest(_b_sh_r).basis.get_rotation_quaternion())
		# Unarmed sprint / run: enhance athletic arm drive if sprinting
		if sp > 0.05 and _b_ua_l >= 0 and _b_ua_r >= 0 and _b_fa_l >= 0 and _b_fa_r >= 0:
			var bend_q := Quaternion(Vector3.BACK, 0.45 * sp)
			skel.set_bone_pose_rotation(_b_fa_l, skel.get_bone_pose_rotation(_b_fa_l) * bend_q)
			skel.set_bone_pose_rotation(_b_fa_r, skel.get_bone_pose_rotation(_b_fa_r) * Quaternion(Vector3.FORWARD, 0.45 * sp))
		return

	# 2. Protract clavicles so the left support arm easily reaches the rifle handguard and right shoulder pockets the stock
	if _b_sh_l >= 0:
		var sh_l_rest := skel.get_bone_rest(_b_sh_l).basis.get_rotation_quaternion()
		# Rotate shoulder.L around its local Z (+Y_skel) forward (+Z_skel) by ~22 deg
		var protract_l := Quaternion(Vector3(0, 0, 1), -0.36 if _is_long else -0.22)
		skel.set_bone_pose_rotation(_b_sh_l, sh_l_rest * protract_l)
	if _b_sh_r >= 0:
		var sh_r_rest := skel.get_bone_rest(_b_sh_r).basis.get_rotation_quaternion()
		var protract_r := Quaternion(Vector3(0, 0, 1), 0.10 if _is_long else 0.18)
		skel.set_bone_pose_rotation(_b_sh_r, sh_r_rest * protract_r)

	# 3. Position weapon_node (whose origin is the pistol grip) from the posed chest bone
	var chest_g := skel.get_bone_global_pose(_b_chest) if _b_chest >= 0 else Transform3D(Basis(), Vector3(0, 1.26, 0))
	# Convert chest shoulder-line anchor from Skeleton3D space (model rotated PI around Y) to CharacterVisual space
	var chest_anchor_skel := chest_g.origin + chest_g.basis * Vector3(0.0, 0.155, 0.0)
	var chest_self := Vector3(-chest_anchor_skel.x, chest_anchor_skel.y, -chest_anchor_skel.z)
	var aim_b := Basis.from_euler(Vector3(pitch, 0.0, 0.0))

	var fire_pos: Vector3
	var fire_rot: Vector3
	var stock_local := Vector3(0.0, 0.015, 0.205)
	if _is_long:
		fire_rot = Vector3(pitch, 0.08 if not aim else 0.04, 0.0)
		var fire_basis := Basis.from_euler(fire_rot)
		var pocket_self := chest_self + (Vector3(0.095, -0.025, -0.015) if not aim else Vector3(0.072, -0.008, -0.012))
		fire_pos = pocket_self - fire_basis * stock_local
	else:
		var grip_off_p := Vector3(0.045, -0.045, -0.255) if not aim else Vector3(0.015, -0.005, -0.245)
		fire_pos = chest_self + aim_b * grip_off_p
		fire_rot = Vector3(pitch, 0.03, 0.0)

	if sp > 0.001:
		var bob_y := sin(_stride_phase * 2.0) * 0.016 * sp
		var bob_x := cos(_stride_phase) * 0.020 * sp
		var sprint_pos: Vector3
		var sprint_rot: Vector3
		if _is_long:
			# Tactical across-chest low-ready sprint carry with stock clear of shoulder/pack straps
			sprint_rot = Vector3(-0.14 + bob_y * 1.5, 0.48 + bob_x * 1.4, 0.14)
			var spr_basis := Basis.from_euler(sprint_rot)
			var sprint_pocket := chest_self + Vector3(0.125 + bob_x, -0.085 + bob_y, -0.065)
			sprint_pos = sprint_pocket - spr_basis * stock_local
		else:
			sprint_pos = chest_self + Vector3(0.065 + bob_x, -0.085 + bob_y, -0.25)
			sprint_rot = Vector3(-0.32 + bob_y * 2.0, 0.22 + bob_x * 1.2, 0.08)
		weapon_node.position = fire_pos.lerp(sprint_pos, sp)
		var q_fire := Quaternion.from_euler(fire_rot)
		var q_spr := Quaternion.from_euler(sprint_rot)
		weapon_node.basis = Basis(q_fire.slerp(q_spr, sp))
	else:
		weapon_node.position = fire_pos
		weapon_node.rotation = fire_rot

	# 4. Compute right-hand (pistol grip) and left-hand (handguard/support) targets in Skeleton3D space
	# Since model.rotation.y == PI, transforming from self space to Skeleton3D space is Basis(Vector3.UP, PI)
	var flip_pi := Basis(Vector3.UP, PI)
	var wpn_skel_origin := flip_pi * weapon_node.position
	var wpn_skel_basis := (flip_pi * weapon_node.basis).orthonormalized()
	var g_fwd: Vector3 = -wpn_skel_basis.z     # Toward muzzle in Skeleton3D space
	var g_up: Vector3 = wpn_skel_basis.y       # Toward top sight rail in Skeleton3D space
	var g_right: Vector3 = wpn_skel_basis.x    # Toward right side of weapon in Skeleton3D space

	var grip_skel: Vector3 = wpn_skel_origin + wpn_skel_basis * Vector3(0.0, -0.012, 0.010)
	var sup_skel: Vector3 = wpn_skel_origin + wpn_skel_basis * _support_local

	_hand_r.position = weapon_node.position
	_hand_l.position = weapon_node.position + weapon_node.basis * _support_local

	# Right hand basis in Skeleton3D space:
	# +Y along fingers (forward & slightly down), +Z out of back of hand (+g_right), +X down pistol grip (-g_up)
	var hr_y := (g_fwd * 0.96 - g_up * 0.28).normalized()
	var hr_z := (g_right - hr_y * g_right.dot(hr_y)).normalized()
	var hr_x := hr_y.cross(hr_z).normalized()
	hr_z = hr_x.cross(hr_y).normalized()
	var hand_r_basis := Basis(hr_x, hr_y, hr_z)
	var wrist_r_target := grip_skel - hr_y * 0.076 + hr_z * 0.018

	# Left hand basis in Skeleton3D space:
	var hl_y: Vector3
	var hl_z: Vector3
	if _is_long:
		# Cradling underside/left of handguard: palm (-Z) faces up-and-right (+g_up, +g_right), so +Z faces down-and-left
		hl_y = (g_fwd * 0.94 + g_right * 0.34).normalized()
		var palm_l := (g_up * 0.62 + g_right * 0.78).normalized()
		hl_z = (-palm_l - hl_y * (-palm_l).dot(hl_y)).normalized()
	else:
		# Two-handed pistol support grip: palm (-Z) faces right (+g_right), back of hand (+Z) faces left (-g_right)
		hl_y = (g_fwd * 0.96 - g_up * 0.28).normalized()
		hl_z = (-g_right - hl_y * (-g_right).dot(hl_y)).normalized()
	var hl_x := hl_y.cross(hl_z).normalized()
	hl_z = hl_x.cross(hl_y).normalized()
	var hand_l_basis := Basis(hl_x, hl_y, hl_z)
	var wrist_l_target := sup_skel - hl_y * (0.074 if _is_long else 0.086) + hl_z * (0.020 if _is_long else 0.026)

	# Elbow pole vectors in Skeleton3D space (down and outward from chest)
	var pole_r_skel := chest_g.origin + chest_g.basis * Vector3(-0.34, -0.26, -0.06)
	var pole_l_skel := chest_g.origin + chest_g.basis * Vector3(0.32, -0.30, 0.06)

	_solve_arm_ik(false, _b_sh_r, _b_ua_r, _b_fa_r, _b_ha_r, _l1_r, _l2_r, wrist_r_target, hand_r_basis, pole_r_skel)
	_solve_arm_ik(true, _b_sh_l, _b_ua_l, _b_fa_l, _b_ha_l, _l1_l, _l2_l, wrist_l_target, hand_l_basis, pole_l_skel)


func _solve_arm_ik(is_left: bool, b_sh: int, b_ua: int, b_fa: int, b_ha: int, l1: float, l2: float, wrist_target: Vector3, hand_basis: Basis, pole_target: Vector3) -> void:
	if b_sh < 0 or b_ua < 0 or b_fa < 0 or b_ha < 0:
		return
	var pg := skel.get_bone_global_pose(b_sh)
	var S: Vector3 = pg * skel.get_bone_rest(b_ua).origin
	var to := wrist_target - S
	var dist := clampf(to.length(), 0.08, l1 + l2 - 0.003)
	var dir := to.normalized()
	var W := S + dir * dist
	var ca := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var sa := sqrt(maxf(0.0, 1.0 - ca * ca))

	var pole_v := pole_target - S
	var bend := pole_v - dir * pole_v.dot(dir)
	if bend.length_squared() < 1e-6:
		bend = Vector3(0.0, -1.0, 0.0) - dir * (-dir.y)
	bend = bend.normalized()

	var E := S + (dir * ca + bend * sa) * l1
	var u_y := (E - S).normalized()
	var f_y := (W - E).normalized()
	var n_plane := dir.cross(bend).normalized()
	if n_plane.length_squared() < 1e-6:
		n_plane = Vector3.UP

	# In stranger.glb rest pose:
	# Right arm (+X_bone) points toward outer elbow (+bend); Left arm (+X_bone) points toward inner elbow (-bend).
	var sign_x := -1.0 if is_left else 1.0
	var u_x := (n_plane.cross(u_y) * sign_x).normalized()
	var u_z := u_x.cross(u_y).normalized()
	var Ru := Basis(u_x, u_y, u_z).orthonormalized()

	var f_x := (n_plane.cross(f_y) * sign_x).normalized()
	var f_z := f_x.cross(f_y).normalized()
	var Rf := Basis(f_x, f_y, f_z).orthonormalized()

	# Share 45% of wrist pronation/supination twist with the forearm so the wrist never pinches
	var tw := _twist_angle(Rf, hand_basis, f_y)
	Rf = (Basis(f_y, tw * 0.45) * Rf).orthonormalized()

	skel.set_bone_pose_rotation(b_ua, (pg.basis.orthonormalized().inverse() * Ru).get_rotation_quaternion())
	skel.set_bone_pose_rotation(b_fa, (Ru.inverse() * Rf).get_rotation_quaternion())
	skel.set_bone_pose_rotation(b_ha, (Rf.inverse() * hand_basis).get_rotation_quaternion())


static func _twist_angle(from_b: Basis, to_b: Basis, axis: Vector3) -> float:
	var dq := (to_b * from_b.inverse()).get_rotation_quaternion()
	var v := Vector3(dq.x, dq.y, dq.z)
	var p := axis * v.dot(axis)
	var tq := Quaternion(p.x, p.y, p.z, dq.w).normalized()
	var ang := 2.0 * acos(clampf(tq.w, -1.0, 1.0))
	if Vector3(tq.x, tq.y, tq.z).dot(axis) < 0.0:
		ang = -ang
	return clampf(wrapf(ang, -PI, PI), -1.35, 1.35)


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
		pos = weapon_node.position + weapon_node.basis * (_support_local + Vector3(0.0, -0.02, -0.10))
		basis = weapon_node.basis
	elif long:
		# Clipped to the shoulder strap: follows the body, half the pitch.
		pos = Vector3(-0.12, h - 0.45, -0.18)
		basis = Basis.from_euler(Vector3(ch.pitch * 0.5, 0, 0))
	elif ch.weapon_id != "":
		pos = weapon_node.position + weapon_node.basis * Vector3(-0.04, -0.02, -0.12)
		basis = weapon_node.basis
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
