extends SceneTree
## (r27) Writes a drafted ground into a map's Terrain3D data, once, at the start: the heights and the texture control
## map (Terrain3D's bit layout) a draft script made, the texture sets (packed albedo+height, normal+roughness), the
## ground cover's meshes and every planted instance. After this the Terrain3D data in the map's folder is the source:
## sculpt, paint and plant it in the Godot editor (editor/maps/<id>.tscn), and Save map bakes the heights again.
##
##   godot --headless --path game -s res://tools/terrain_import.gd -- --map=hidden_forest --draft=<abs dir>
##
## The draft directory holds heights.f32 (n x n little-endian floats), control.u32 (n x n uint32), meta.json
## ({area, spacing, n}) and cover.json ({mesh name: [[x, y, z, yaw, scale], ...]}). Texture sets come from
## res://maps/<id>/terrain/tex/sets.json (tools/make_jungle_textures.py), meshes from res://assets/models/hf/.

const MapDoc := preload("res://src/world/maps/authored/map_doc.gd")
const MapTerrain := preload("res://src/world/maps/authored/map_terrain.gd")

## Ground cover: how far each kind is drawn (metres; Terrain3D's lod0 range is also its last), and whether it shadows.
## No ground cover casts shadows: a fern in a torch's or the moon's shadow map costs as much again as drawing it.
const COVER := {
	"fern_a": [22.0, false], "fern_b": [20.0, false], "weed_leaves": [16.0, false], "periwinkle": [15.0, false],
	"taro": [32.0, false], "banana": [42.0, false], "banana_tree": [70.0, false],
	"mossrock_s1": [34.0, false], "mossrock_s3": [30.0, false], "root_flat": [24.0, false],
}
## Metres one texture repeat covers on the ground, per set (Terrain3D's uv_scale is repeats a metre).
const TEX_REPEAT := {"litter": 3.2, "sprouts": 3.0, "soil": 3.0, "roots": 3.5, "trail": 3.2, "lichen_rock": 4.0,
	"cliff": 5.0, "flagstones": 3.6, "leaf_grass": 3.2}


func _init() -> void:
	_run.call_deferred()


func _arg(k: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k):
			return a.split("=", true, 1)[1]
	return def


func _run() -> void:
	var map_id := _arg("map")
	var draft := _arg("draft")
	if not ClassDB.class_exists("Terrain3D"):
		push_error("[terrain import] the Terrain3D extension is not loaded")
		quit(2)
		return
	var doc := MapDoc.load_doc(map_id)
	var s := MapTerrain.spec_of(doc)
	if s.is_empty():
		push_error("[terrain import] %s has no terrain block" % map_id)
		quit(2)
		return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(draft.path_join("meta.json")))
	var n := int(meta.n)
	var area: Array = meta.area
	var dir := str(s.dir)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	# ------------------------------------------------ assets: the texture sets and the ground cover's meshes
	var assets = ClassDB.instantiate("Terrain3DAssets")
	var sets = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("tex/sets.json")))
	for i in (sets as Array).size():
		var nm := str(sets[i].name)
		var ta = ClassDB.instantiate("Terrain3DTextureAsset")
		ta.set("name", nm)
		ta.set("albedo_texture", load(dir.path_join("tex/%s_ah.png" % nm)))
		ta.set("normal_texture", load(dir.path_join("tex/%s_nr.png" % nm)))
		ta.set("uv_scale", 1.0 / float(TEX_REPEAT.get(nm, 3.0)))
		ta.set("detiling_rotation", 0.35)
		ta.set("detiling_shift", 0.25)
		ta.set("ao_strength", 0.7)
		ta.set("normal_depth", 1.1)
		assets.set_texture_asset(i, ta)
	var cover = JSON.parse_string(FileAccess.get_file_as_string(draft.path_join("cover.json")))
	var mesh_ids := {}
	var mi := 0
	for nm in COVER:
		if not (cover as Dictionary).has(nm):
			continue
		var path := "res://assets/models/hf/%s.gltf" % nm
		if not ResourceLoader.exists(path):
			push_warning("[terrain import] no %s" % path)
			continue
		var ma = ClassDB.instantiate("Terrain3DMeshAsset")
		ma.set("name", nm)
		ma.set("scene_file", load(path))
		ma.set("lod0_range", float(COVER[nm][0]))
		ma.set("fade_margin", 6.0)
		ma.set("cast_shadows", 1 if bool(COVER[nm][1]) else 0)
		assets.set_mesh_asset(mi, ma)
		mesh_ids[nm] = mi
		mi += 1
	var err := ResourceSaver.save(assets, str(s.assets))
	print("[terrain import] assets: %d texture sets, %d meshes -> %s (%s)" % [(sets as Array).size(), mi, s.assets, error_string(err)])

	# ------------------------------------------------ materials: the full shader, and Terrain3D's lightweight one for phones
	var mat = ClassDB.instantiate("Terrain3DMaterial")
	mat.set("world_background", 0)
	mat.set("auto_shader_enabled", false)
	mat.set("macro_variation_enabled", true)
	mat.set("max_regions", 16)
	err = ResourceSaver.save(mat, str(s.material))
	var mob = ClassDB.instantiate("Terrain3DMaterial")
	mob.set("world_background", 0)
	mob.set("max_regions", 16)
	var lw := "res://addons/terrain_3d/extras/shaders/lightweight.gdshader"
	if ResourceLoader.exists(lw):
		mob.set("shader_override", load(lw))
		mob.set("shader_override_enabled", true)
	ResourceSaver.save(mob, str(s.mobile_material))
	print("[terrain import] materials -> %s, %s (%s)" % [s.material, s.mobile_material, error_string(err)])

	# ------------------------------------------------ the terrain itself
	var t: Node3D = ClassDB.instantiate("Terrain3D")
	# (the default region size is 256, the size this draft is cut for; setting it resizes data, an editor action)
	t.set("vertex_spacing", float(s.spacing))
	t.set("collision_mode", 0)
	t.set("assets", assets)
	t.set("material", mat)
	root.add_child(t)
	await process_frame
	await process_frame
	var full := n - 1   # the last row and column (+area edge) belong to the next region: drop them
	var hb := FileAccess.get_file_as_bytes(draft.path_join("heights.f32"))
	var him := Image.create_from_data(n, n, false, Image.FORMAT_RF, hb).get_region(Rect2i(0, 0, full, full))
	var cb := FileAccess.get_file_as_bytes(draft.path_join("control.u32"))
	var cim := Image.create_from_data(n, n, false, Image.FORMAT_RF, cb).get_region(Rect2i(0, 0, full, full))
	var data = t.get("data")
	data.import_images([him, cim, null], Vector3(float(area[0]), 0.0, float(area[1])), 0.0, 1.0)
	print("[terrain import] regions: %d" % int(data.get_region_count()))
	# check: a few heights against the draft
	for q in [Vector2(-60, 36), Vector2(0, 0), Vector2(44, -46), Vector2(70, -70)]:
		var ix := int((q.x - float(area[0])) / float(meta.spacing))
		var iz := int((q.y - float(area[1])) / float(meta.spacing))
		var want := hb.decode_float((iz * n + ix) * 4)
		print("[terrain import]   height at (%d, %d): %.3f (draft %.3f)" % [q.x, q.y, data.get_height(Vector3(q.x, 0, q.y)), want])

	# ------------------------------------------------ the ground cover
	var inst = t.get("instancer")
	var total := 0
	for nm in mesh_ids:
		var xfs: Array[Transform3D] = []
		for e in cover[nm]:
			var b := Basis(Vector3.UP, deg_to_rad(float(e[3]))).scaled(Vector3.ONE * float(e[4]))
			xfs.append(Transform3D(b, Vector3(float(e[0]), float(e[1]), float(e[2]))))
		inst.add_transforms(int(mesh_ids[nm]), xfs, PackedColorArray(), false)
		total += xfs.size()
	inst.update_mmis(-1, Vector2i(2147483647, 2147483647), true)
	print("[terrain import] ground cover: %d instances of %d meshes" % [total, mesh_ids.size()])

	data.save_directory(dir)
	var img := MapTerrain.bake(t, s)
	err = MapTerrain.save_baked(img, s, map_id)
	print("[terrain import] saved %s, baked %d x %d heights (%s)" % [dir, img.get_width(), img.get_height(), error_string(err)])
	quit(0)
