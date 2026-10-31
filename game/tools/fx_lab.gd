extends Node3D
## Explosion look lab (r14): a grenade's visual effects (Effects.explosion) on a plain lit ground in front of a wall,
## captured at fixed times after the blast. Prints the flipbook frame the fireball cards are on.
##   godot --path game res://tools/fx_lab.tscn -- --out=<dir> [--dist=8]

const Particles := preload("res://src/fx/particles.gd")

var out := "user://fx_lab"
var _parts = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var dist := 8.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			dist = float(a.trim_prefix("--dist="))
	get_window().size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.38, 0.32)
	ground.material_override = gm
	add_child(ground)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(20, 7, 0.3)
	wall.mesh = bm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.62, 0.6, 0.56)
	wall.material_override = wm
	wall.position = Vector3(0, 3.5, -2.0)
	add_child(wall)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.6, dist), Vector3(0, 1.2, 0))
	_parts = Particles.new()
	add_child(_parts)
	_parts.setup()
	if "--animcheck" in OS.get_cmdline_user_args():
		# Two fireball emitters beside the blast: left pinned at the flipbook's middle frame (offset 0.5, speed 0),
		# right at its first frame. If the left one looks like the middle of the sheet, the material reads the frame.
		for i in 2:
			var src: GPUParticles3D = _parts.pools["fireball"][0]
			var p := src.duplicate() as GPUParticles3D
			var pm2 := (src.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
			pm2.anim_speed_min = 0.0
			pm2.anim_speed_max = 0.0
			pm2.anim_offset_min = 0.5 if i == 0 else 0.0
			pm2.anim_offset_max = pm2.anim_offset_min
			pm2.initial_velocity_min = 0.0
			pm2.initial_velocity_max = 0.0
			pm2.gravity = Vector3.ZERO
			p.process_material = pm2
			p.lifetime = 20.0
			p.amount = 2
			add_child(p)
			p.global_position = Vector3((-1.0 if i == 0 else 1.0) * dist * 0.35, 1.5, dist * 0.3)
			p.restart()
	if "--outline" in OS.get_cmdline_user_args():
		# The suitable-loot highlight (fx/loot_highlight.gd) on bare render instances, as ground items are drawn: a box
		# of rounds-sized cube and a sphere, with and without the overlay.
		cam.look_at_from_position(Vector3(0, 0.9, 1.3), Vector3(0, 0.04, 0))
		var cel := ShaderMaterial.new()
		cel.shader = load("res://src/fx/loot_cel.gdshader")
		var om := ShaderMaterial.new()
		om.shader = load("res://src/fx/loot_outline.gdshader")
		om.next_pass = cel
		var meshes := [BoxMesh.new(), SphereMesh.new(), BoxMesh.new(), SphereMesh.new()]
		for i in 4:
			(meshes[i] as PrimitiveMesh).material = gm
			if meshes[i] is BoxMesh:
				(meshes[i] as BoxMesh).size = Vector3(0.12, 0.06, 0.08)
			else:
				(meshes[i] as SphereMesh).radius = 0.04
				(meshes[i] as SphereMesh).height = 0.08
			var inst := RenderingServer.instance_create2((meshes[i] as Mesh).get_rid(), get_world_3d().scenario)
			RenderingServer.instance_set_transform(inst, Transform3D(Basis(Vector3.UP, 0.4), Vector3(-0.45 + i * 0.3, 0.04, 0)))
			if i < 2:
				RenderingServer.instance_geometry_set_material_overlay(inst, om.get_rid())
		await get_tree().create_timer(0.6).timeout
		await _shot("outline")
		get_tree().quit()
		return
	await get_tree().create_timer(0.6).timeout
	await _shot("00_before")
	var t0 := Time.get_ticks_msec()
	_explode(Vector3(0, 0.15, 0))
	for at in [0.06, 0.2, 0.45, 0.8, 1.3, 2.2, 4.0, 7.0]:
		while Time.get_ticks_msec() - t0 < int(at * 1000.0):
			await get_tree().process_frame
		await _shot("t%05.2f" % at)
	get_tree().quit()


func _explode(pos: Vector3) -> void:
	# The particle part of Effects.explosion (lights and decals need a world; a flash light is added here).
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.8, 0.55)
	l.omni_range = 22.0
	l.light_energy = 16.0
	add_child(l)
	l.global_position = pos + Vector3.UP * 0.8
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	var up := Vector3.UP
	for k in ["fireball", "blast_smoke", "dust_ring", "embers", "sparks", "blast_debris", "chunk_dust"]:
		_parts.emit(k, pos + up * (0.5 if k == "fireball" else 0.3), up)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("[fx_lab] shot %s" % name)
