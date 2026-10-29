extends Node3D
## Loads every r7 prop (names from res://data/r7_props.json) through ModelLib, the way the map does, and prints its
## triangles, surfaces, textures and bounds next to the catalogue's numbers. Without --headless it also lines the
## models up beside a 1.8 m figure and saves captures.
##   godot --headless --path game res://tools/check_r7_props.tscn
##   godot --path game res://tools/check_r7_props.tscn -- --shots=<dir>

const Materials := preload("res://src/world/materials.gd")
const ModelLib := preload("res://src/world/model_lib.gd")

var lib = null
var rows: Array = []


func _ready() -> void:
	var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/r7_props.json"))
	var props: Dictionary = cat.props
	lib = ModelLib.new(Materials.new())
	var bad := 0
	print("%-22s %7s %4s %4s  %-20s %-20s %s" % ["name", "tris", "surf", "tex", "size x,y,z (m)", "catalogue x,h,z", "result"])
	for name in props.keys():
		var c: Dictionary = props[name]
		var spec: Dictionary = lib.spec(name)
		var md: Dictionary = lib.get_model(name)
		if spec.is_empty() or md.is_empty():
			print("%-22s FAIL: %s" % [name, "no PROPS entry" if spec.is_empty() else "model did not load"])
			bad += 1
			continue
		var mesh: Mesh = md.mesh
		var tris := 0
		var tex := 0
		for i in mesh.get_surface_count():
			tris += (mesh as ArrayMesh).surface_get_array_index_len(i) / 3
			var m := mesh.surface_get_material(i)
			if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture != null:
				tex += 1
		var a: AABB = md.aabb
		var fp: Array = c.footprint
		var why := []
		if absf(a.size.x - float(fp[0])) > 0.03 or absf(a.size.z - float(fp[1])) > 0.03 or absf(a.size.y - float(c.height)) > 0.03:
			why.append("size differs from the catalogue")
		var bmin: Array = c.bounds_min
		if a.position.distance_to(Vector3(float(bmin[0]), float(bmin[1]), float(bmin[2]))) > 0.01:
			why.append("bounds differ from the catalogue")
		# Sketchfab (r7) models must stand on their floor centre; Poly Haven copies keep the author's origin.
		if spec.has("path") and (absf(a.position.y) > 0.01 or absf(a.get_center().x) > 0.01 or absf(a.get_center().z) > 0.01):
			why.append("origin not at the floor centre")
		if tex < mesh.get_surface_count():
			why.append("untextured surface")
		if tris > 15000:
			why.append("over 15k triangles")
		var ok := why.is_empty()
		if not ok:
			bad += 1
		rows.append([name, md, a])
		print("%-22s %7d %4d %4d  %-20s %-20s %s" % [name, tris, mesh.get_surface_count(), tex,
			"%.2f,%.2f,%.2f" % [a.size.x, a.size.y, a.size.z], "%.2f,%.2f,%.2f" % [float(fp[0]), float(c.height), float(fp[1])],
			"PASS" if ok else "FAIL: " + ", ".join(why)])
	print("r7 props: %d checked, %d PASS, %d FAIL" % [props.size(), props.size() - bad, bad])
	var shots := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.substr(8)
	if DisplayServer.get_name() == "headless" or shots == "":
		get_tree().quit(1 if bad > 0 else 0)
		return
	await _captures(shots)
	get_tree().quit(1 if bad > 0 else 0)


func _figure(at: Vector3, parent: Node) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.22
	cm.height = 1.8
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.15, 0.4, 0.95)
	cm.material = sm
	mi.mesh = cm
	mi.position = at + Vector3(0, 0.9, 0)
	parent.add_child(mi)


func _place(names: Array, origin: Vector3, gap: float, parent: Node) -> float:
	## A row along +X, every model at yaw 0 (front toward +Z, toward the camera), a figure after each.
	var x := origin.x
	for r in rows:
		if not names.has(r[0]):
			continue
		var a: AABB = r[2]
		var mi := MeshInstance3D.new()
		mi.mesh = (r[1] as Dictionary).mesh
		mi.position = Vector3(x - a.position.x, origin.y, origin.z)
		parent.add_child(mi)
		x += a.size.x + 0.15
		_figure(Vector3(x + 0.25, origin.y, origin.z), parent)
		x += 0.5 + gap
	return x


func _captures(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.47, 0.53)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.6)
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.3, 0.31)
	pm.material = gm
	ground.mesh = pm
	add_child(ground)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	get_window().size = Vector2i(1920, 1080)
	var sets := {
		"cars": ["car_compact", "car_coupe", "car_hatchback", "car_minivan", "car_offroad", "car_pickup", "car_sedan", "car_sport", "car_suv", "car_wagon"],
		"cars2": ["car_saloon_old", "car_sedan_80s", "car_sedan_80s_b", "car_pickup_old", "van_delivery", "car_burnt_a", "car_burnt_b", "car_police_burnt", "car_police_flipped", "jeepney_painted"],
		"street_factory": ["forklift_a", "forklift_b", "chem_tanks", "conveyor", "control_pedestal", "traffic_light", "ped_signal", "basketball_hoop", "playground_slide", "playground_set", "gas_pump_old", "gas_pump_round"],
		"store_house": ["store_display_case", "store_chiller", "store_shelf_wall", "steel_shelves3", "metal_rack", "display_shelves", "payphone", "aircon_condenser", "china_cabinet", "tv_cabinet", "sofa_classic", "sofa_leather", "armchair", "armchair_modern", "coffee_table", "dining_table", "dining_chair", "potted_plant", "potted_plant2", "street_bench", "barrier2", "iron_gate"],
	}
	var z := 0.0
	for key in sets:
		var row := Node3D.new()
		add_child(row)
		var end := _place(sets[key], Vector3(0, 0, z), 0.4, row)
		var mid := end * 0.5
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		# Orthographic size is the view height: fit the row's width into 16:9.
		cam.size = maxf(end / (16.0 / 9.0) * 1.05, 4.0)
		cam.position = Vector3(mid, cam.size * 0.45, z + 40.0)
		cam.look_at(Vector3(mid, cam.size * 0.3, z), Vector3.UP)
		for i in 8:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := dir.path_join("godot_%s.png" % key)
		img.save_png(p)
		print("capture ", p)
		row.free()
