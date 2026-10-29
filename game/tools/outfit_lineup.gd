extends Node3D
## Seven characters in a row under the same light, for checking outfits:
##   godot --path game res://tools/outfit_lineup.tscn -- --mode=new|old --out=<png>
## --mode=old (the 0.5.0 hooded body, hoodie tinted per player as
## 0.5.0 did) or --mode=new (random outfits). --out=<png>. For the blind review of character appearance.

const BODY := "res://assets/models/sleep/characters/stranger.glb"
const Outfit := preload("res://src/player/outfit.gd")
const PALETTE := [Color(0.08, 0.08, 0.09), Color(0.16, 0.2, 0.14), Color(0.22, 0.12, 0.1), Color(0.12, 0.14, 0.22),
	Color(0.3, 0.28, 0.24), Color(0.1, 0.18, 0.2), Color(0.26, 0.1, 0.14), Color(0.18, 0.18, 0.18)]


func _ready() -> void:
	var mode := "new"
	var out := "res://../work/lineup.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
		if a.begins_with("--out="):
			out = a.substr(6)
	get_window().size = Vector2i(1920, 1080)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.25, 6.2)
	cam.fov = 40.0
	add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 0.95, 0))
	cam.current = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.34, 0.37)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(25), 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 10)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.33, 0.3)
	ground.material_override = gm
	add_child(ground)
	if mode == "tactical":
		await _run_tactical(out, cam)
		return
	var scene: PackedScene = load(BODY)
	for i in 7:
		var m: Node3D = scene.instantiate()
		add_child(m)
		m.position = Vector3(-3.3 + i * 1.1, 0, 0)
		m.rotation.y = 0.25 * (i - 3) * 0.3
		var skel: Skeleton3D = _find(m, "Skeleton3D")
		var anim: AnimationPlayer = _find(m, "AnimationPlayer")
		if anim and anim.has_animation("idle"):
			anim.play("idle")
			anim.seek(0.4 * i, true)
		if mode == "new":
			for mi in _meshes(m):
				mi.get_parent().remove_child(mi)
				mi.queue_free()
			Outfit.dress(skel, Outfit.random_look(1000 + i * 7919), 1, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		else:
			for mi in _meshes(m):
				for s in mi.get_surface_override_material_count():
					var mat: Material = mi.get_active_material(s)
					if mat is StandardMaterial3D and str(mat.resource_name).to_lower().find("hood") >= 0:
						var nm: StandardMaterial3D = mat.duplicate()
						nm.albedo_color = PALETTE[i % PALETTE.size()]
						mi.set_surface_override_material(s, nm)
	for f in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("[lineup] ", out)
	get_tree().quit()


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _meshes(n: Node) -> Array:
	var o := []
	if n is MeshInstance3D:
		o.append(n)
	for c in n.get_children():
		o.append_array(_meshes(c))
	return o


class _MockWpn:
	var wid := "rifle_m416"
	func weapon() -> Dictionary:
		return {"id": wid, "att": {}}


class _MockMap:
	func item_visual(wid: String) -> Dictionary:
		for pat in ["res://assets/models/items/%s.glb" % wid, "res://assets/models/loot/%s.glb" % wid]:
			if ResourceLoader.exists(pat):
				var scn: Node3D = (load(pat) as PackedScene).instantiate()
				var list := scn.find_children("*", "MeshInstance3D", true, false)
				if not list.is_empty():
					var out := ArrayMesh.new()
					for n in list:
						var mi := n as MeshInstance3D
						if mi.mesh == null:
							continue
						var rel := Transform3D()
						var cur: Node = mi
						while cur != null and cur != scn:
							if cur is Node3D:
								rel = (cur as Node3D).transform * rel
							cur = cur.get_parent()
						for s in mi.mesh.get_surface_count():
							var st := SurfaceTool.new()
							st.append_from(mi.mesh, s, rel)
							st.commit(out)
					var a := out.get_aabb()
					var xf := Transform3D(Basis(), Vector3(-a.get_center().x, -a.position.y, -a.get_center().z))
					scn.free()
					return {"mesh": out, "size": a.size, "xf": xf}
				scn.free()
		var sz := Vector3(0.06, 0.20, 0.82) if wid.begins_with("rifle") else Vector3(0.04, 0.14, 0.20)
		var bm := BoxMesh.new()
		bm.size = sz
		return {"mesh": bm, "size": sz, "xf": Transform3D(Basis(), Vector3(0, sz.y * 0.5, 0))}


class _MockWorld:
	var map = _MockMap.new()


func _attach_dm_vest(vis: Node3D) -> void:
	var skel: Skeleton3D = vis.get("skel")
	if skel == null or not ResourceLoader.exists("res://assets/models/items/vest_heavy.glb"):
		return
	var bone := skel.find_bone("chest")
	if bone < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = "DmVest"
	skel.add_child(att)
	att.bone_idx = bone
	var vest: Node3D = (load("res://assets/models/items/vest_heavy.glb") as PackedScene).instantiate()
	var holder := Node3D.new()
	holder.name = "VestHolder"
	att.add_child(holder)
	holder.add_child(vest)
	for mi in vest.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = Defs.RENDER_CHARACTERS
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var upright := Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0)).scaled(Vector3.ONE * 0.76)
	var bone_g: Transform3D = skel.global_transform * skel.get_bone_global_pose(bone)
	var vb: Basis = vis.global_transform.basis.orthonormalized()
	var want := Transform3D(vb * upright, bone_g.origin + vb * Vector3(0, 0.04, -0.02))
	holder.transform = bone_g.affine_inverse() * want


func _run_tactical(out: String, cam: Camera3D) -> void:
	const CharacterVisual := preload("res://src/player/character_visual.gd")
	cam.cull_mask = 0xFFFFF
	var w := _MockWorld.new()
	var poses := [
		{"wid": "rifle_556", "pitch": 0.0, "flags": Character.F_AIM, "vel": Vector3.ZERO, "crouch": 0.0, "cam": Vector3(0.95, 1.38, -1.15), "look": Vector3(0.0, 1.28, -0.15), "dm_op": true},
		{"wid": "rifle_m416", "pitch": 0.0, "flags": Character.F_AIM, "vel": Vector3.ZERO, "crouch": 0.0, "cam": Vector3(-0.95, 1.38, -1.15), "look": Vector3(0.0, 1.30, -0.15)},
		{"wid": "rifle_m416", "pitch": 0.45, "flags": Character.F_AIM, "vel": Vector3.ZERO, "crouch": 0.0, "cam": Vector3(1.15, 1.38, -0.95), "look": Vector3(0.0, 1.32, -0.15)},
		{"wid": "rifle_m416", "pitch": -0.45, "flags": Character.F_AIM, "vel": Vector3.ZERO, "crouch": 0.0, "cam": Vector3(1.15, 1.38, -0.95), "look": Vector3(0.0, 1.20, -0.15)},
		{"wid": "rifle_m416", "pitch": 0.0, "flags": Character.F_SPRINT, "vel": Vector3(0, 0, -6.0), "crouch": 0.0, "cam": Vector3(1.35, 1.12, -1.35), "look": Vector3(0.0, 0.98, 0.0)},
		{"wid": "pistol_9", "pitch": 0.0, "flags": Character.F_CROUCH | Character.F_AIM, "vel": Vector3(0, 0, -1.2), "crouch": 1.0, "cam": Vector3(-1.05, 1.05, -1.15), "look": Vector3(0.0, 0.92, -0.15)},
	]
	var entries := []
	for i in poses.size():
		var p: Dictionary = poses[i]
		var ch := Character.new()
		ch.eid = i + 2
		ch.pid = i + 2
		ch.is_local = false
		ch.is_remote = true
		ch.mode = Motor.GROUND
		ch.weapon_id = str(p.wid)
		ch.pitch = float(p.pitch)
		ch.flags = int(p.flags)
		ch.velocity = p.vel
		ch.crouch = float(p.crouch)
		ch.sprinting = (ch.flags & Character.F_SPRINT) != 0
		var mw := _MockWpn.new()
		mw.wid = str(p.wid)
		ch.wpn = mw
		ch.position = Vector3(-12.0 + i * 5.0, 0.0, 0.0)
		add_child(ch)
		if p.get("dm_op", false):
			Net.players[ch.pid] = {"look": {"helmet": "combat", "shirt": "tank", "shirt_c": 4, "elbow": "hard", "pants": "camo", "boots": "combat", "gloves": "tactical", "skin": 0}}
		var vis := CharacterVisual.new()
		ch.add_child(vis)
		vis.setup(w, ch)
		if p.get("dm_op", false):
			_attach_dm_vest(vis)
			Net.players.erase(ch.pid)
		entries.append([ch, vis, p])
	# Advance 80 frames (1.33 seconds, well past 0.633s sprint clip duration!)
	for f in 80:
		for e in entries:
			(e[1] as Node3D)._process(1.0 / 60.0)
		await get_tree().process_frame
	var sp_vis = entries[4][1]
	print("[tactical] sprint anim at t=1.33s: cur=", sp_vis._cur_anim, " playing=", sp_vis.anim.is_playing(), " pos=", sp_vis.anim.current_animation_position)
	get_window().size = Vector2i(640, 640)
	var sheet := Image.create(3 * 640, 2 * 640, false, Image.FORMAT_RGBA8)
	for i in entries.size():
		var ch: Node3D = entries[i][0]
		var vis: Node3D = entries[i][1]
		var p: Dictionary = entries[i][2]
		cam.look_at_from_position(ch.global_position + (p.cam as Vector3), ch.global_position + (p.look as Vector3), Vector3.UP)
		vis._process(1.0 / 60.0)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, 640, 640), Vector2i((i % 3) * 640, (i / 3) * 640))
	sheet.save_png(out)
	print("[tactical] saved ", out)
	get_tree().quit()

