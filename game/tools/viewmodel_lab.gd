extends Node3D
## First-person bench: the real viewmodel (arms, gun parts, reload and action clips) on a stand-in player, without a
## map. For every gun it captures hip, aim, the firing action and frames through both reloads, and writes one strip
## per gun plus the frames:
##   godot --path game res://tools/viewmodel_lab.tscn -- --out=<dir> [--guns=a,b] [--frames=8] [--look=jacket|tee|bare]
##   [--size=960x540]
## Strips: <dir>/<gun>.png (hip, aim, fire, then reload and empty reload frames). Times are fractions of each clip.

const Viewmodel := preload("res://src/player/viewmodel.gd")
const WeaponState := preload("res://src/weapons/weapon_state.gd")
const GunModel := preload("res://src/weapons/gun_model.gd")
const GUNS := ["pistol_9", "pistol_45", "pistol_deagle", "revolver_357", "shotgun_pump", "shotgun_saiga", "shotgun_double",
	"sumpak", "smg_9", "machine_pistol", "smg_ump45", "smg_vector", "smg_tommy", "rifle_556", "rifle_762", "rifle_scar",
	"rifle_m416", "rifle_m762", "lmg_m249", "dmr_mini14", "dmr_sks", "marksman_308", "bolt_308", "bolt_kar98"]


class FakeLight:
	var on := false
	var weapon_mounted := false
	func swapping() -> bool:
		return false
	func flicker(_t: float, _eid: int) -> float:
		return 1.0


class FakeInv:
	var gear := {}


class FakeMap:
	var _cache := {}
	func item_visual(id: String) -> Dictionary:
		if _cache.has(id):
			return _cache[id]
		var res := {}
		for path in ["res://assets/models/items/%s.glb" % id, "res://assets/models/loot/%s.glb" % id]:
			if not ResourceLoader.exists(path):
				continue
			var parts := GunModel.parts(id) if path.contains("/items/") else {}
			var mesh: Mesh = null
			if parts.is_empty():
				var inst: Node = (load(path) as PackedScene).instantiate()
				var found := []
				_meshes(inst, Transform3D(), found)
				inst.free()
				for f in found:
					mesh = f if mesh == null else GunModel._joined(mesh, f)
			else:
				for r in parts:
					mesh = parts[r].mesh if mesh == null else GunModel._joined(mesh, parts[r].mesh)
			if mesh == null:
				continue
			var a := mesh.get_aabb()
			res = {"mesh": mesh, "size": a.size, "xf": Transform3D(Basis(), Vector3(-a.get_center().x, -a.position.y, -a.get_center().z)), "model": path}
			break
		_cache[id] = res
		return res

	func _meshes(n: Node, xf: Transform3D, out: Array) -> void:
		for c in n.get_children():
			var cx := xf * ((c as Node3D).transform if c is Node3D else Transform3D())
			if c is MeshInstance3D and (c as MeshInstance3D).mesh:
				out.append(GunModel._baked((c as MeshInstance3D).mesh, cx))
			_meshes(c, cx, out)


class FakeWorld:
	var map = FakeMap.new()


var ch: CharacterBody3D
var vm
var cam: Camera3D
var out_dir := "res://../work/lemondev/r5/vm"
var frames := 8
var bones := false
var size := Vector2i(960, 540)
var full := false


func _ready() -> void:
	var guns: Array = GUNS
	var look_name := "jacket"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--guns="):
			guns = Array(a.substr(7).split(","))
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif a.begins_with("--look="):
			look_name = a.substr(7)
		elif a == "--full":
			full = true
		elif a == "--bones":
			bones = true
		elif a.begins_with("--size="):
			var p := a.substr(7).split("x")
			size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir) if out_dir.begins_with("res://") else out_dir)
	get_window().size = size
	_scene()
	ch = CharacterBody3D.new()
	ch.set_script(load("res://tools/viewmodel_lab_ch.gd"))
	add_child(ch)
	ch.light = FakeLight.new()
	ch.inv = FakeInv.new()
	ch.wpn = WeaponState.new(ch)
	var looks := {
		"jacket": {"jacket": "bomber", "jacket_c": 1, "shirt": "tee", "gloves": "none", "skin": 0},
		"tee": {"jacket": "none", "shirt": "tee", "shirt_c": 1, "gloves": "none", "skin": 2},
		"long": {"jacket": "none", "shirt": "longsleeve", "shirt_c": 0, "gloves": "tactical", "skin": 1},
		"bare": {"jacket": "none", "shirt": "tank", "gloves": "fingerless", "skin": 3},
	}
	Net.players[ch.pid] = {"look": looks.get(look_name, looks.jacket)}
	cam = Camera3D.new()
	cam.fov = float(Settings.get_value("graphics", "fov"))
	cam.position = Vector3(0, 1.6, 0)
	add_child(cam)
	cam.current = true
	vm = Viewmodel.new()
	cam.add_child(vm)
	vm.setup(FakeWorld.new(), ch, cam)
	await _run(guns)
	get_tree().quit()


func _scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.38, 0.41)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.5
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.28, 0.25)
	floor_mi.material_override = gm
	add_child(floor_mi)
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 4, 0.2)
	wall.mesh = bm
	wall.position = Vector3(0, 2, -6)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.55, 0.52, 0.48)
	wall.material_override = wm
	add_child(wall)


func _tick(dt: float, cmd: Dictionary = {}) -> void:
	ch.wpn.step(cmd, dt, Net.tick)
	vm.update_view(dt, false, false)


func _frame() -> void:
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frame()
	return get_viewport().get_texture().get_image()


func _settle(seconds: float, cmd: Dictionary = {}) -> void:
	var t := 0.0
	while t < seconds:
		_tick(1.0 / 60.0, cmd)
		t += 1.0 / 60.0
		await _frame()


func _hand_test() -> void:
	## Calibration: both hands in known orientations (no gun). Frames: palms down fingers forward; palms facing
	## each other; palms up; fists.
	for s in 4:
		ch.wpn.slots[s] = null
	await _settle(0.3, {"slot": 0})
	var FA = vm.arms
	var poses := [
		[Vector3(0, 0, -1), Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(0, -1, 0), "open"],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), "open"],
		[Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0, 1, 0), "open"],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0), "fist"],
	]
	var shots: Array[Image] = []
	var labels: Array[String] = []
	for p in poses:
		for i in 3:
			vm.update_view(1.0 / 60.0, false, false)
			FA.pose("R", Vector3(0.14, -0.2, -0.38), FA.hand_basis(p[0], p[1]), vm.POLE_R, FA.grip(p[4]))
			FA.pose("L", Vector3(-0.14, -0.2, -0.38), FA.hand_basis(p[2], p[3]), vm.POLE_L, FA.grip(p[4]))
			await _frame()
		shots.append(await _grab())
		labels.append("pose")
	_save_strip("handtest", shots, labels)


func _run(guns: Array) -> void:
	if "handtest" in guns:
		await _hand_test()
		return
	for gid in guns:
		var d := Defs.weapon(gid)
		var slot := WeaponState.HANDGUN if str(d.get("slot", "")) == "handgun" else WeaponState.PRIMARY
		for s in 4:
			ch.wpn.slots[s] = null
		var w := WeaponState.new_instance(gid, null, 1.0)
		ch.wpn.slots[slot] = w
		ch.wpn.reserve_cache[str(d.get("ammo", ""))] = 400
		var cmd := {"slot": slot}
		ch.wpn.want = slot
		await _settle(1.0, cmd)
		var shots: Array[Image] = []
		var labels: Array[String] = []
		shots.append(await _grab())
		labels.append("hip")
		print("[vmlab] %s pose error R %s  L %s (m, deg)" % [gid, str(vm.arms.pose_error("R")), str(vm.arms.pose_error("L"))])
		if full:
			# Each hand alone (the other folded away), to tell them apart.
			for side in ["L", "R"]:
				vm.update_view(0.0, false, false)
				vm.arms.show_side(side, false)
				shots.append(await _grab())
				labels.append("only_" + ("R" if side == "L" else "L"))
		# Sprinting lowers the gun: half-way down and all the way (where the arm's ends can come into view).
		ch.set("sprinting", true)
		await _settle(0.12, cmd)
		shots.append(await _grab())
		labels.append("sprint_mid")
		await _settle(0.6, cmd)
		shots.append(await _grab())
		labels.append("sprint")
		ch.set("sprinting", false)
		await _settle(0.8, cmd)
		ch.wpn.ads = 1.0
		vm.update_view(0.0, false, false)
		shots.append(await _grab())
		labels.append("aim")
		_iron_report(gid)
		ch.wpn.ads = 0.0
		# Fire once and catch the action mid-way (slide back, pump / bolt cycling).
		var fired := {"slot": slot, "btn": Motor.B_FIRE}
		_tick(1.0 / 60.0, fired)
		vm.on_fire()
		_tick(0.015, cmd)
		shots.append(await _grab())
		labels.append("fire")
		if ch.wpn.state == WeaponState.CYCLE:
			var tot: float = ch.wpn.timer
			while ch.wpn.state == WeaponState.CYCLE and ch.wpn.timer > tot * 0.55:
				_tick(1.0 / 60.0, cmd)
			shots.append(await _grab())
			labels.append("cycle")
		await _settle(1.2, cmd)
		var before := shots.size()
		for empty in [false, true]:
			w.mag = 1 if not empty else 0
			w.chamber = not empty
			if str(d.get("feed", "")) == "break":
				w.mag = 0
				w.chamber = false
			ch.wpn.start_reload()
			if ch.wpn.state != WeaponState.RELOAD:
				push_warning("lab: %s did not start a reload" % gid)
				continue
			# Walk the reload in small steps and grab evenly spaced frames over its whole length.
			var total := _reload_length(gid, w)
			var step := total / float(frames + 1)
			var t := 0.0
			var next := step
			while ch.wpn.state == WeaponState.RELOAD and t < total + 2.0:
				_tick(1.0 / 120.0, cmd)
				t += 1.0 / 120.0
				if t >= next and shots.size() < before + frames * 2:
					shots.append(await _grab())
					labels.append(("E" if empty else "R") + "%.0f%%" % (100.0 * t / total))
					if bones:
						_print_bones(labels[-1])
					next += step
			await _settle(0.6, cmd)
		_save_strip(gid, shots, labels)
		print("[vmlab] %s: %d frames (%s)" % [gid, shots.size(), vm._kind])


func _print_bones(label: String) -> void:
	## Shoulder, elbow and wrist of each arm in camera space (x right, y up, -z ahead), for posing bugs.
	var inv := cam.global_transform.affine_inverse()
	var sk: Skeleton3D = vm.arms.skel
	for s in ["L", "R"]:
		var d: Dictionary = vm.arms.sides[s]
		var pts := []
		for b in [d.upper, d.fore, d.hand]:
			pts.append((inv * (sk.global_transform * sk.get_bone_global_pose(int(b))).origin).snapped(Vector3.ONE * 0.01))
		print("[bones] %s %s shoulder %s elbow %s wrist %s" % [label, s, pts[0], pts[1], pts[2]])


func _iron_report(gid: String) -> void:
	## Aiming without an optic: how far the highest point of the gun is from the crosshair (pixels; negative = below
	## it, so the crosshair is clear) and whether the front sight sits under it.
	var vs := get_viewport().get_visible_rect().size
	var cy := vs.y * 0.5
	var top := INF
	var nodes: Array = [vm.weapon_mesh]
	for r in vm._parts:
		if vm._parts[r].node is MeshInstance3D and (vm._parts[r].node as Node3D).visible:
			nodes.append(vm._parts[r].node)
	for mi in nodes:
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var xf: Transform3D = (mi as Node3D).global_transform
		for si in m.get_surface_count():
			for v in (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var p: Vector3 = xf * v
				if cam.is_position_behind(p) or cam.global_transform.affine_inverse() * p == Vector3.ZERO:
					continue
				var local := cam.global_transform.affine_inverse() * p
				if local.z > -cam.near:
					continue
				var sp := cam.unproject_position(p)
				if absf(sp.x - vs.x * 0.5) < vs.x * 0.25:
					top = minf(top, sp.y)
	var front_sp := cam.unproject_position(vm.weapon_root.global_transform * vm._iron_front)
	var rear_sp := cam.unproject_position(vm.weapon_root.global_transform * vm._iron_rear)
	print("[vmlab] %s irons: gun top %.1f px from crosshair (negative = below), front sight %s rear sight %s (centre %.0f,%.0f)" % [gid, cy - top, str(front_sp.round()), str(rear_sp.round()), vs.x * 0.5, cy])


func _reload_length(gid: String, w: Dictionary) -> float:
	var d := Defs.weapon(gid)
	var feed := str(d.get("feed", "mag"))
	if feed in ["tube", "cylinder"]:
		var n = ch.wpn.mag_cap() - int(w.mag)
		return float(d.get("reload_start", 0.5)) + n * float(d.get("reload_time", 0.5)) + float(d.get("reload_end", 0.4))
	return float(d.get("reload_empty_time" if not w.chamber else "reload_time", 2.5))


func _save_strip(gid: String, shots: Array[Image], labels: Array[String]) -> void:
	var cols := 4
	var tw := size.x / 2
	var th := size.y / 2
	var rows := int(ceil(shots.size() / float(cols)))
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in shots.size():
		var im: Image = shots[i]
		im.convert(Image.FORMAT_RGB8)
		if full:
			im.save_png(out_dir.path_join("%s_%02d_%s.png" % [gid, i, labels[i].replace("%", "")]))
		im.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(im, Rect2i(0, 0, tw, th), Vector2i((i % cols) * tw, (i / cols) * th))
	var base := out_dir.path_join(gid)
	sheet.save_png(base + ".png")
	var f := FileAccess.open(base + ".txt", FileAccess.WRITE)
	f.store_string(" | ".join(labels))
