"""Loot run (2026-10-26): attachments drawn on the first- and third-person weapon, fitted attachments replicated to
other players, aiming lines up the fitted sight with the eye, magnified scopes hide the gun for the scope view, the
support hand takes a fitted grip, a grip-hold per weapon, and a visible laser dot.

    python -I tools/patches/p49_attachment_visuals.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class Patch:
    def __init__(self, rel):
        self.p = os.path.join(ROOT, rel)
        raw = open(self.p, 'rb').read().decode()
        self.crlf = '\r\n' in raw
        self.s = raw.replace('\r\n', '\n')

    def rep(self, a, b, cnt=1):
        assert self.s.count(a) == cnt, (self.p, a[:90], self.s.count(a))
        self.s = self.s.replace(a, b)

    def save(self):
        open(self.p, 'wb').write((self.s.replace('\n', '\r\n') if self.crlf else self.s).encode())


# ------------------------------------------------------------------ replication of fitted attachments
c = Patch('game/src/player/character.gd')
c.rep('''var weapon_id := ""        # currently drawn weapon (for visuals of remote characters)''',
      '''var weapon_id := ""        # currently drawn weapon (for visuals of remote characters)
var weapon_att := 0        # its fitted attachments as a bit mask (Attachments.bitmask)''')
c.rep('''	weapon_id = str(b.weapon)''', '''	weapon_id = str(b.weapon)
	weapon_att = int(b.get("att", 0))''')
c.save()

sn = Patch('game/src/net/snapshot.gd')
sn.rep('''		var wi := weapon_ids.find(ch.weapon_id)
		b.put_u8(255 if wi < 0 else wi)''', '''		var wi := weapon_ids.find(ch.weapon_id)
		b.put_u8(255 if wi < 0 else wi)
		b.put_u32(ch.weapon_att)''')
sn.rep('''		o.weapon = "" if wi == 255 or wi >= weapon_ids.size() else weapon_ids[wi]''', '''		o.weapon = "" if wi == 255 or wi >= weapon_ids.size() else weapon_ids[wi]
		o.att = b.get_u32()''')
sn.save()

w = Patch('game/src/match/world.gd')
w.rep('''	ch.weapon_id = ch.wpn.current_id()''', '''	ch.weapon_id = ch.wpn.current_id()
	ch.weapon_att = Attach.bitmask(ch.wpn.weapon())''')
w.rep('''var _weapon_ids: Array = []''', '''const Attach := preload("res://src/weapons/attachments.gd")
var _weapon_ids: Array = []''')
w.save()

# ------------------------------------------------------------------ first person
v = Patch('game/src/player/viewmodel.gd')
v.rep('''const SLEEVE := Color(0.075, 0.075, 0.085)''', '''const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")
const SLEEVE := Color(0.075, 0.075, 0.085)''')
v.rep('''var weapon_mesh: MeshInstance3D''', '''var weapon_mesh: MeshInstance3D
var att_root: Node3D             # fitted attachments, in the weapon model's item_visual space (offset by the grip)
var laser_dot: MeshInstance3D
var _att_sig := ""
var _grip_vis := Vector3.ZERO    # the grip in item_visual space
var _aim_pos := Vector3.ZERO     # weapon root position when aiming (the sight's line on the eye)
var _light_pt := Vector3.ZERO    # where a weapon-mounted light sits (weapon root space)''')
v.rep('''	weapon_mesh = MeshInstance3D.new()
	weapon_root.add_child(weapon_mesh)''', '''	weapon_mesh = MeshInstance3D.new()
	weapon_root.add_child(weapon_mesh)
	att_root = Node3D.new()
	att_root.name = "Attachments"
	weapon_root.add_child(att_root)
	laser_dot = make_laser_dot()
	add_child(laser_dot)''')
v.rep('''func _equip(wid: String) -> void:
	## New weapon in hand: mesh, muzzle, and where the hands hold it.
	_cur = wid
	_draw = 1.0
	var md: Dictionary = world.map.item_visual(wid) if wid != "" else {}
	weapon_mesh.mesh = md.get("mesh")
	var sz: Vector3 = md.get("size", Vector3(0.05, 0.1, 0.4))
	_long = wid != "" and Defs.weapon(wid).get("slot", "long") == "long"
	# item_visual centres the model on x/z with its bottom at y = 0; the front is -z.
	var front := -sz.z * 0.5
	if _long:
		_grip = Vector3(0, sz.y * 0.32, front + sz.z * 0.6)
		_support = Vector3(0, sz.y * 0.5, front + sz.z * 0.27)
	else:
		_grip = Vector3(0, sz.y * 0.3, front + sz.z * 0.72)
		_support = _grip + Vector3(-0.03, -0.02, 0.015)
	# The grip sits at the weapon root, so the hand pose below is fixed whatever the model's size.
	weapon_mesh.transform = Transform3D(Basis(), -_grip) * (md.get("xf", Transform3D()) as Transform3D)
	muzzle.position = Vector3(0, sz.y * (0.7 if _long else 0.75), front - 0.01) - _grip
	_support -= _grip
	_grip = Vector3.ZERO
	_set_layer(weapon_root)''', '''func _equip(wid: String) -> void:
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
		dot.global_position = (r.position as Vector3) + (r.normal as Vector3) * 0.01''')
v.rep('''	var wid: String = ch.wpn.current_id()
	if wid != _cur:
		_equip(wid)''', '''	var wid: String = ch.wpn.current_id()
	if wid != _cur:
		_equip(wid)
	var atts: Array = ch.wpn.weapon().get("att", [])
	var sig := wid + ":" + ",".join(atts)
	if sig != _att_sig:
		_att_sig = sig
		_fit_attachments(wid, atts)''')
v.rep('''	var aim := Vector3(0.0, -0.12, -0.24) if _long else Vector3(0.0, -0.1, -0.36)''', '''	var aim := _aim_pos''')
v.rep('''	var armed = wid != "" and ch.mode == Motor.GROUND and _lower < 0.98
	weapon_root.visible = armed''', '''	var armed = wid != "" and ch.mode == Motor.GROUND and _lower < 0.98
	# Through a magnified scope the view is the scope picture (HUD overlay); the gun itself would fill the screen.
	weapon_root.visible = armed and not (ch.wpn.scoped() and ads > 0.88)
	if armed and Attach.flag(ch.wpn.weapon(), "laser") and _tab < 0.5:
		var b: Basis = cam.global_transform.basis * Basis(Vector3.UP, deg_to_rad(-off.x)) * Basis(Vector3.RIGHT, deg_to_rad(off.y))
		place_laser(laser_dot, get_world_3d().direct_space_state, muzzle_position(), -b.z, [ch.get_rid()])
	else:
		laser_dot.visible = false''')
v.rep('''	if ch.light.weapon_mounted:
		light.position = weapon_root.position + weapon_root.basis * (_support + Vector3(0.0, -0.03, -0.12))
		light.rotation = weapon_root.rotation''', '''	if ch.light.weapon_mounted:
		light.position = weapon_root.position + weapon_root.basis * _light_pt
		light.rotation = weapon_root.rotation''')
v.save()

# ------------------------------------------------------------------ third person
cv = Patch('game/src/player/character_visual.gd')
cv.rep('''const Footsteps := preload("res://src/audio/footsteps.gd")''', '''const Footsteps := preload("res://src/audio/footsteps.gd")
const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")
const ViewModel := preload("res://src/player/viewmodel.gd")''')
cv.rep('''var _cur_weapon := "-"''', '''var _cur_weapon := "-"
var _cur_att := -1
var att_root: Node3D
var laser_dot: MeshInstance3D''')
cv.rep('''	weapon_mesh = MeshInstance3D.new()
	weapon_node.add_child(weapon_mesh)
	if ch.is_local:
		weapon_mesh.layers = Defs.RENDER_LOCAL_BODY
		weapon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY''', '''	weapon_mesh = MeshInstance3D.new()
	weapon_node.add_child(weapon_mesh)
	att_root = Node3D.new()
	weapon_node.add_child(att_root)
	if ch.is_local:
		weapon_mesh.layers = Defs.RENDER_LOCAL_BODY
		weapon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	else:
		laser_dot = ViewModel.make_laser_dot()
		add_child(laser_dot)''')
cv.rep('''	if wid != _cur_weapon:
		_cur_weapon = wid
		var md: Dictionary = world.map.item_visual(wid) if wid != "" and world.map else {}
		weapon_mesh.mesh = md.get("mesh")
		weapon_mesh.transform = _weapon_xf(wid, md)
	var armed: bool = wid != "" and ch.mode == Motor.GROUND and (ch.flags & Character.F_TAB) == 0
	weapon_mesh.visible = armed''', '''	var att_mask: int = Attach.bitmask(ch.wpn.weapon()) if ch.is_local else ch.weapon_att
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
			laser_dot.visible = false''')
cv.save()
print('ok')
