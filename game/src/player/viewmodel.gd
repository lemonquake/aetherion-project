extends Node3D
## First-person view: the weapon in hand (offset by the same recoil kick and sway the server uses, so the barrel,
## the reticle and the bullets agree), the arms holding it, the left hand raising the SmarTab, and the player's own
## flashlight.
##
## Holding TAB lowers the weapon out of the firing position and brings the device up in the left hand; the large
## square screen is a live SubViewport (the SmarTab UI). Releasing TAB lowers it and raises the weapon again.
##
## Arms are two-segment sleeves from shoulders just outside the view to gloved hands. The right hand sits on the
## weapon's grip (or holds the flashlight when nothing is drawn); the left hand takes the handguard of a long gun,
## supports a handgun, or holds the SmarTab. Grip and handguard points come from the weapon model's proportions.

const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")
const SLEEVE := Color(0.075, 0.075, 0.085)
const GLOVE := Color(0.09, 0.075, 0.065)
const SHOULDER_R := Vector3(0.24, -0.36, 0.16)
const SHOULDER_L := Vector3(-0.24, -0.36, 0.16)
const UPPER := 0.3
const FORE := 0.28

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
var screen_size := Vector2(0.15, 0.15)
var _arm_r: Dictionary   # {upper, fore, hand}
var _arm_l: Dictionary
var _grip := Vector3.ZERO      # in weapon_root space
var _support := Vector3.ZERO
var _long := false
var _cur := "-"
var _tab := 0.0
var _lower := 0.0
var _kick_z := 0.0
var _bob := 0.0
var _hit := 0.0
var _draw := 0.0


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
	_arm_r = _build_arm()
	_arm_l = _build_arm()
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
	_set_layer(self)


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


func _build_arm() -> Dictionary:
	## Upper arm and forearm are unit-length tapered cylinders scaled to their segment each frame; the hand is a
	## gloved, slightly flattened capsule with a thumb.
	var sleeve := _mat(SLEEVE, 0.95)
	var glove := _mat(GLOVE, 0.7)
	var parts := {}
	for k in ["upper", "fore"]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.height = 1.0
		cm.top_radius = 0.042 if k == "upper" else 0.036
		cm.bottom_radius = 0.048 if k == "upper" else 0.04
		cm.radial_segments = 10
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = sleeve
		add_child(mi)
		parts[k] = mi
	var hand := Node3D.new()
	add_child(hand)
	var palm := MeshInstance3D.new()
	var pm := CapsuleMesh.new()
	pm.radius = 0.03
	pm.height = 0.11
	palm.mesh = pm
	palm.scale = Vector3(1.0, 1.0, 0.72)
	palm.rotation = Vector3(PI * 0.5, 0, 0)
	palm.material_override = glove
	hand.add_child(palm)
	var thumb := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.011
	tm.height = 0.06
	thumb.mesh = tm
	thumb.rotation = Vector3(PI * 0.5, 0.5, 0)
	thumb.position = Vector3(-0.026, 0.012, -0.03)
	thumb.material_override = glove
	hand.add_child(thumb)
	var cuff := MeshInstance3D.new()
	var cu := CylinderMesh.new()
	cu.height = 0.04
	cu.top_radius = 0.037
	cu.bottom_radius = 0.037
	cuff.mesh = cu
	cuff.rotation = Vector3(PI * 0.5, 0, 0)
	cuff.position = Vector3(0, 0, 0.065)
	cuff.material_override = sleeve
	hand.add_child(cuff)
	parts.hand = hand
	return parts


func _segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 1e-4:
		mi.visible = false
		return
	mi.visible = true
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


func _pose_arm(arm: Dictionary, shoulder: Vector3, hand_xf: Transform3D, side: float, show: bool) -> void:
	## Two-bone arm by the law of cosines; the elbow drops down and slightly outward.
	for k in ["upper", "fore"]:
		(arm[k] as Node3D).visible = show
	(arm.hand as Node3D).visible = show
	if not show:
		return
	var wrist := hand_xf * Vector3(0, 0, 0.085)
	var to := wrist - shoulder
	var dist := clampf(to.length(), 0.05, UPPER + FORE - 0.005)
	var dir := to.normalized()
	var a := clampf((UPPER * UPPER + dist * dist - FORE * FORE) / (2.0 * UPPER * dist), -1.0, 1.0)
	var pole := (Vector3(side * 0.35, -1.0, 0.1)).normalized()
	var bend := (pole - dir * pole.dot(dir)).normalized()
	var elbow := shoulder + dir * (UPPER * a) + bend * (UPPER * sqrt(1.0 - a * a))
	_segment(arm.upper, shoulder, elbow)
	_segment(arm.fore, elbow, wrist)
	(arm.hand as Node3D).transform = hand_xf


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
	tab_root = Node3D.new()
	add_child(tab_root)
	# Rugged body
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.19, 0.2, 0.022)
	body.mesh = bm
	body.material_override = _mat(Color(0.09, 0.1, 0.1), 0.65)
	tab_root.add_child(body)
	# Wrist strap across the back
	var strap := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.05, 0.16, 0.012)
	strap.mesh = sm
	strap.material_override = _mat(Color(0.12, 0.13, 0.1), 0.9)
	strap.position = Vector3(0, -0.02, -0.016)
	tab_root.add_child(strap)
	tab_screen = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = screen_size
	tab_screen.mesh = q
	tab_screen.position = Vector3(0, 0.005, 0.0115)
	tab_root.add_child(tab_screen)
	# The screen lights the hand and nearby surfaces faintly, and can be seen by others.
	tab_light = OmniLight3D.new()
	tab_light.light_color = Color(0.75, 0.9, 1.0)
	tab_light.omni_range = 1.6
	tab_light.light_energy = 0.0
	tab_light.shadow_enabled = false
	tab_light.position = Vector3(0, 0, 0.12)
	tab_root.add_child(tab_light)
	tab_root.visible = false


func set_screen_texture(tex: Texture2D) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.emission_enabled = true
	m.emission_texture = tex
	m.emission_energy_multiplier = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tab_screen.material_override = m


func screen_uv(viewport_pos: Vector2) -> Vector2:
	## Where a mouse position on the window lands on the SmarTab screen (0..1), or (-1,-1).
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
	return Vector2(p.x / screen_size.x + 0.5, 0.5 - p.y / screen_size.y)


# ------------------------------------------------------------------ per frame

func on_fire() -> void:
	_kick_z = 0.06


func on_hit(damage: float) -> void:
	_hit = minf(_hit + 0.4 + damage * 0.01, 1.0)


func _equip(wid: String) -> void:
	## New weapon in hand: mesh, muzzle, and where the hands hold it.
	_cur = wid
	_draw = 1.0
	var md: Dictionary = world.map.item_visual(wid) if wid != "" else {}
	weapon_mesh.mesh = md.get("mesh")
	var sz: Vector3 = md.get("size", Vector3(0.05, 0.1, 0.4))
	_long = wid != "" and Defs.weapon(wid).get("slot", "long") == "long"
	# item_visual centres the model on x/z with its bottom at y = 0; the front is -z. "hold" = [grip, fore-end] as
	# fractions of the length from the muzzle.
	var front := -sz.z * 0.5
	var hold: Array = Defs.weapon(wid).get("hold", [0.6, 0.27] if _long else [0.72, 0.3]) if wid != "" else [0.6, 0.27]
	if _long:
		_grip = Vector3(0, sz.y * 0.32, front + sz.z * float(hold[0]))
		_support = Vector3(0, sz.y * 0.5, front + sz.z * float(hold[1]))
	else:
		_grip = Vector3(0, sz.y * 0.3, front + sz.z * float(hold[0]))
		_support = _grip + Vector3(-0.03, -0.02, 0.015)
	_grip_vis = _grip
	# The grip sits at the weapon root, so the hand pose below is fixed whatever the model's size.
	weapon_mesh.transform = Transform3D(Basis(), -_grip) * (md.get("xf", Transform3D()) as Transform3D)
	att_root.transform = Transform3D(Basis(), -_grip)
	muzzle.position = Vector3(0, sz.y * (0.7 if _long else 0.75), front - 0.01) - _grip
	_support -= _grip
	_grip = Vector3.ZERO
	_att_sig = "-"
	_set_layer(weapon_root)


func _fit_attachments(wid: String, atts: Array) -> void:
	## Draws the fitted attachments and moves what they change: the aim line (sight), the muzzle (device), the
	## support hand (grip) and the weapon light.
	AttachVisual.build(world.map, att_root, wid, atts, Defs.RENDER_VIEWMODEL, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var md: Dictionary = world.map.item_visual(wid)
	var sz: Vector3 = md.get("size", Vector3(0.05, 0.1, 0.4))
	var front := -sz.z * 0.5
	var hip_aim := Vector3(0.0, -0.12, -0.24) if _long else Vector3(0.0, -0.1, -0.36)
	_aim_pos = hip_aim
	muzzle.position = Vector3(0, sz.y * (0.7 if _long else 0.75), front - 0.01) - _grip_vis
	var hold: Array = Defs.weapon(wid).get("hold", [0.6, 0.27] if _long else [0.72, 0.3])
	if _long:
		_support = Vector3(0, sz.y * 0.5, front + sz.z * float(hold[1])) - _grip_vis
	_light_pt = _support + Vector3(0.0, -0.03, -0.12)
	for a in atts:
		var aid := str(a)
		match Attach.kind(aid):
			"sight":
				var ax := AttachVisual.sight_axis(world.map, wid, aid) - _grip_vis
				var rear := AttachVisual.sight_rear_z(world.map, wid, aid) - _grip_vis.z
				_aim_pos = Vector3(-ax.x, -ax.y, minf(hip_aim.z, -0.075 - rear))
			"muzzle":
				var amd: Dictionary = world.map.item_visual(aid)
				var mx: Transform3D = AttachVisual.mount_xf(world.map, wid, aid) * (amd.get("xf", Transform3D()) as Transform3D).affine_inverse()
				muzzle.position = mx * Vector3(0, (amd.size as Vector3).y * 0.5, -(amd.size as Vector3).z * 0.5) - _grip_vis
			"grip":
				var gmd: Dictionary = world.map.item_visual(aid)
				var gx: Transform3D = AttachVisual.mount_xf(world.map, wid, aid) * (gmd.get("xf", Transform3D()) as Transform3D).affine_inverse()
				if _long:
					_support = gx * Vector3(0, (gmd.size as Vector3).y * 0.35, 0) - _grip_vis
			"light":
				var lmd: Dictionary = world.map.item_visual(aid)
				var lx: Transform3D = AttachVisual.mount_xf(world.map, wid, aid) * (lmd.get("xf", Transform3D()) as Transform3D).affine_inverse()
				_light_pt = lx * Vector3(0, (lmd.size as Vector3).y * 0.4, -(lmd.size as Vector3).z * 0.5) - _grip_vis


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
	_draw = move_toward(_draw, 0.0, dt * 2.5)
	# TAB: the weapon goes down and out of the way, the device comes up.
	_tab = move_toward(_tab, 1.0 if tab_held and ch.mode == Motor.GROUND else 0.0, dt / 0.32)
	var busy: bool = ch.light.swapping() or (ch.flags & Character.F_HEAL) != 0
	# Vaulting: the gun drops out of sight fast and comes back up after (only if it was out: the drawn weapon is
	# unchanged, this is just the hands being busy).
	var vaulting: bool = ch.vault_t >= 0.0
	_lower = move_toward(_lower, 1.0 if (_tab > 0.0 or busy or ch.held_prop_id >= 0 or ch.sprinting or vaulting) else 0.0, dt / (0.1 if vaulting else 0.25))
	var e := ease(_tab, -2.0)
	tab_root.visible = _tab > 0.01
	tab_root.position = Vector3(-0.07, lerpf(-0.42, -0.045, e), lerpf(-0.2, -0.3, e))
	tab_root.rotation = Vector3(lerpf(-1.1, 0.12, e), lerpf(0.5, 0.05, e), lerpf(0.4, 0.0, e))
	var bright := float(Settings.get_value("accessibility", "smartab_brightness"))
	tab_light.light_energy = 0.35 * bright * e
	if tab_screen.material_override is StandardMaterial3D:
		(tab_screen.material_override as StandardMaterial3D).emission_energy_multiplier = 0.4 + bright * 1.2
	# Weapon pose: hip or aim, offset by the same kick and sway that steer the bullets. Positions are the grip.
	var ads: float = ch.wpn.ads
	var off: Vector2 = ch.wpn.aim_offset_deg(Net.tick)
	var hip := Vector3(0.15, -0.21, -0.3) if _long else Vector3(0.13, -0.19, -0.38)
	var aim := _aim_pos
	var hv := Vector2(ch.velocity.x, ch.velocity.z).length()
	_bob += dt * hv * 1.6
	var motion := str(Settings.get_value("accessibility", "camera_motion"))
	var bob_k := 1.0 if motion == "normal" else (0.4 if motion == "reduced" else 0.15)
	var bob := Vector3(sin(_bob) * 0.008, absf(cos(_bob)) * 0.01, 0) * clampf(hv / 4.0, 0.0, 1.5) * (1.0 - ads * 0.8) * bob_k
	_kick_z = move_toward(_kick_z, 0.0, dt * 0.6)
	var pos := hip.lerp(aim, ads) + bob + Vector3(0, -0.4 * ease(_lower, -2.0) - 0.25 * _draw, _kick_z)
	weapon_root.position = pos
	weapon_root.rotation = Vector3(deg_to_rad(off.y) - 0.9 * _lower, deg_to_rad(-off.x), 0.15 * _lower)
	var armed = wid != "" and ch.mode == Motor.GROUND and _lower < 0.98
	# Through a magnified scope the view is the scope picture (HUD overlay); the gun itself would fill the screen.
	weapon_root.visible = armed and not (ch.wpn.scoped() and ads > 0.88)
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
	_arms(armed)
	_flashlight(dt)


func _arms(armed: bool) -> void:
	var on_ground: bool = ch.mode in [Motor.GROUND, Motor.DOWNED]
	# Right hand: weapon grip, else the torch, else hidden below the view.
	var r_show := on_ground and (armed or torch_root.visible)
	var r_xf := Transform3D()
	if armed:
		r_xf = weapon_root.transform * Transform3D(Basis(Vector3.RIGHT, -0.25), _grip + Vector3(0.0, -0.025, 0.02))
	elif torch_root.visible:
		r_xf = torch_root.transform * Transform3D(Basis(), Vector3(0.0, -0.005, 0.03))
	_pose_arm(_arm_r, SHOULDER_R, r_xf, 1.0, r_show)
	# Left hand: the SmarTab while it is up, else the handguard or the handgun.
	var l_show := on_ground and (tab_root.visible or armed)
	var l_xf := Transform3D()
	if tab_root.visible and _tab > 0.25:
		l_xf = tab_root.transform * Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0.0, -0.105, -0.035))
	elif armed:
		l_xf = weapon_root.transform * Transform3D(Basis(Vector3.FORWARD, -0.6 if _long else -0.2), _support + Vector3(-0.012, -0.02, 0.0))
	else:
		l_show = false
	_pose_arm(_arm_l, SHOULDER_L, l_xf, -1.0, l_show)


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
