extends RefCounted
## Loads third-party models once, merges each into a single multi-surface Mesh with its own materials, and records
## its bounds. Instancing (MultiMesh) and physics props use the merged mesh.
##
## Model ids are Poly Haven asset ids (res://assets/thirdparty/polyhaven/models/<id>/<id>.gltf) or entries in
## ALIASES (processed Sketchfab / Blender assets, or fallbacks built from primitives).

const PH := "res://assets/thirdparty/polyhaven/models/"
const PROCESSED := "res://assets/models/"

## Logical prop name -> {path or primitive, scale, mass, phys material, breakable, health}
const PROPS := {
	"monobloc": {"model": "plastic_monobloc_chair_01", "mass": 2.2, "mat": "plastic", "hp": 60, "kind": "chair"},
	"chair_wood": {"model": "painted_wooden_chair_01", "mass": 4.5, "mat": "wood", "hp": 90, "kind": "chair"},
	"chair_wood2": {"model": "painted_wooden_chair_02", "mass": 4.5, "mat": "wood", "hp": 90, "kind": "chair"},
	"chair_plain": {"model": "WoodenChair_01", "mass": 4.0, "mat": "wood", "hp": 80, "kind": "chair"},
	"school_chair": {"model": "SchoolChair_01", "mass": 5.0, "mat": "wood", "hp": 100, "kind": "chair"},
	"stool": {"model": "wooden_stool_01", "mass": 2.5, "mat": "wood", "hp": 60, "kind": "chair"},
	"stool_fold": {"model": "folding_wooden_stool", "mass": 2.0, "mat": "wood", "hp": 50, "kind": "chair"},
	"stool_paint": {"model": "painted_wooden_stool", "mass": 2.5, "mat": "wood", "hp": 60, "kind": "chair"},
	"metal_stool": {"model": "metal_stool_01", "mass": 4.0, "mat": "steel", "hp": 300, "kind": "chair"},
	"table_paint": {"model": "painted_wooden_table", "mass": 22.0, "mat": "wood", "hp": 220, "kind": "table"},
	"table_wood": {"model": "WoodenTable_01", "mass": 26.0, "mat": "wood", "hp": 240, "kind": "table"},
	"table_small": {"model": "small_wooden_table_01", "mass": 9.0, "mat": "wood", "hp": 120, "kind": "table"},
	"table_round": {"model": "round_wooden_table_01", "mass": 14.0, "mat": "wood", "hp": 160, "kind": "table"},
	"picnic_table": {"model": "wooden_picnic_table", "mass": 45.0, "mat": "wood", "hp": 400, "kind": "table"},
	"desk_metal": {"model": "metal_office_desk", "mass": 48.0, "mat": "steel", "hp": 900, "kind": "table"},
	"school_desk": {"model": "SchoolDesk_01", "mass": 14.0, "mat": "wood", "hp": 150, "kind": "table"},
	"cabinet_paint": {"model": "painted_wooden_cabinet", "mass": 40.0, "mat": "wood", "hp": 260, "kind": "cabinet"},
	"cabinet_paint2": {"model": "painted_wooden_cabinet_02", "mass": 38.0, "mat": "wood", "hp": 260, "kind": "cabinet"},
	"shelves_paint": {"model": "painted_wooden_shelves", "mass": 18.0, "mat": "wood", "hp": 160, "kind": "cabinet"},
	"nightstand": {"model": "painted_wooden_nightstand", "mass": 12.0, "mat": "wood", "hp": 120, "kind": "cabinet"},
	"drawer_cabinet": {"model": "drawer_cabinet", "mass": 30.0, "mat": "wood", "hp": 220, "kind": "cabinet"},
	"drawer_old": {"model": "vintage_wooden_drawer_01", "mass": 28.0, "mat": "wood", "hp": 200, "kind": "cabinet"},
	"bookshelf": {"model": "wooden_bookshelf_worn", "mass": 35.0, "mat": "wood", "hp": 240, "kind": "cabinet"},
	"steel_shelves": {"model": "steel_frame_shelves_01", "mass": 25.0, "mat": "steel", "hp": 600, "kind": "cabinet"},
	"steel_shelves2": {"model": "steel_frame_shelves_02", "mass": 25.0, "mat": "steel", "hp": 600, "kind": "cabinet"},
	"shelf": {"model": "Shelf_01", "mass": 12.0, "mat": "wood", "hp": 120, "kind": "cabinet"},
	"sofa_paint": {"model": "painted_wooden_sofa", "mass": 40.0, "mat": "wood", "hp": 300, "kind": "sofa"},
	"bench_paint": {"model": "painted_wooden_bench", "mass": 18.0, "mat": "wood", "hp": 180, "kind": "chair"},
	"bed_old": {"model": "old_bed_frame", "mass": 55.0, "mat": "steel", "hp": 900, "kind": "bed", "static": true},
	"daybed": {"model": "vintage_day_bed", "mass": 45.0, "mat": "wood", "hp": 400, "kind": "bed", "static": true},
	"tv": {"model": "Television_01", "mass": 14.0, "mat": "plastic", "hp": 40, "kind": "electronics", "glass": true},
	"tv2": {"model": "television_02", "mass": 12.0, "mat": "plastic", "hp": 40, "kind": "electronics", "glass": true},
	"laptop": {"model": "classic_laptop", "mass": 2.5, "mat": "plastic", "hp": 25, "kind": "electronics"},
	"microwave": {"model": "vintage_microwave", "mass": 12.0, "mat": "steel", "hp": 80, "kind": "electronics"},
	"stove": {"model": "electric_stove", "mass": 30.0, "mat": "steel", "hp": 400, "kind": "appliance"},
	"cash_register": {"model": "CashRegister_01", "mass": 10.0, "mat": "steel", "hp": 120, "kind": "electronics"},
	"fan_ceiling": {"model": "ceiling_fan", "mass": 5.0, "mat": "steel", "hp": 60, "kind": "fixture", "static": true},
	"clock": {"model": "wall_clock", "mass": 1.0, "mat": "plastic", "hp": 10, "kind": "decor", "static": true},
	"lpg_small": {"model": "small_lpg_tank", "mass": 14.0, "mat": "steel", "hp": 500, "kind": "tank"},
	"propane": {"model": "propane_tank", "mass": 18.0, "mat": "steel", "hp": 600, "kind": "tank"},
	"pot": {"model": "pot_enamel_01", "mass": 1.2, "mat": "steel", "hp": 200, "kind": "small"},
	"pot_brass": {"model": "brass_pot_01", "mass": 1.5, "mat": "steel", "hp": 200, "kind": "small"},
	"jug": {"model": "jug_01", "mass": 1.0, "mat": "glass", "hp": 6, "kind": "breakable_glass"},
	"bottle": {"model": "wine_bottles_01", "mass": 0.6, "mat": "glass", "hp": 4, "kind": "breakable_glass", "throwable": true},
	"gallon": {"model": "plastic_bottle_gallon", "mass": 1.5, "mat": "plastic", "hp": 40, "kind": "small"},
	"jerrycan": {"model": "plastic_jerrycan", "mass": 3.0, "mat": "plastic", "hp": 60, "kind": "small"},
	"jerrycan_metal": {"model": "metal_jerrycan", "mass": 4.0, "mat": "steel", "hp": 300, "kind": "small"},
	"bucket": {"model": "wooden_bucket_01", "mass": 2.0, "mat": "wood", "hp": 40, "kind": "small"},
	"container": {"model": "plastic_container", "mass": 1.5, "mat": "plastic", "hp": 30, "kind": "small"},
	"bowl": {"model": "wooden_bowl_01", "mass": 0.4, "mat": "wood", "hp": 20, "kind": "small"},
	"board": {"model": "wooden_cutting_board", "mass": 0.8, "mat": "wood", "hp": 30, "kind": "small"},
	"box": {"model": "cardboard_box_01", "mass": 2.5, "mat": "fabric", "hp": 25, "kind": "small"},
	"crate_plastic": {"model": "plastic_crate_01", "mass": 1.8, "mat": "plastic", "hp": 50, "kind": "small"},
	"crate_plastic2": {"model": "plastic_crate_02", "mass": 1.8, "mat": "plastic", "hp": 50, "kind": "small"},
	"crate_plastic3": {"model": "plastic_crate_03", "mass": 1.8, "mat": "plastic", "hp": 50, "kind": "small"},
	"crate_wood": {"model": "wooden_crate_01", "mass": 12.0, "mat": "wood", "hp": 120, "kind": "crate"},
	"crate_wood2": {"model": "wooden_crate_02", "mass": 12.0, "mat": "wood", "hp": 120, "kind": "crate"},
	"crate_military": {"model": "wooden_military_crate", "mass": 30.0, "mat": "wood", "hp": 300, "kind": "crate"},
	"crate_military2": {"model": "old_military_crate", "mass": 30.0, "mat": "wood", "hp": 300, "kind": "crate"},
	"trashbag": {"model": "trashbag", "mass": 4.0, "mat": "fabric", "hp": 30, "kind": "small"},
	"old_tyre": {"model": "old_tyre", "mass": 9.0, "mat": "plastic", "hp": 400, "kind": "small"},
	"cement_bag": {"model": "cement_bag", "mass": 25.0, "mat": "sand", "hp": 200, "kind": "heavy"},
	"can": {"model": "can_rusted", "mass": 0.3, "mat": "sheet_metal", "hp": 20, "kind": "small", "throwable": true},
	"trash_can": {"model": "metal_trash_can", "mass": 6.0, "mat": "sheet_metal", "hp": 200, "kind": "small"},
	"drum": {"model": "Barrel_01", "mass": 20.0, "mat": "sheet_metal", "hp": 500, "kind": "heavy"},
	"Barrel_01": {"model": "Barrel_01", "mass": 20.0, "mat": "sheet_metal", "hp": 500, "kind": "heavy"},
	"drum_blue": {"model": "barrel_03", "mass": 16.0, "mat": "plastic", "hp": 400, "kind": "heavy"},
	"barrels": {"model": "wooden_barrels_01", "mass": 60.0, "mat": "wood", "hp": 600, "kind": "heavy", "static": true},
	"compost": {"model": "compost_bags", "mass": 40.0, "mat": "sand", "hp": 300, "kind": "heavy"},
	"broom": {"model": "plastic_broom", "mass": 0.6, "mat": "plastic", "hp": 20, "kind": "small"},
	"dustpan": {"model": "dustpan", "mass": 0.3, "mat": "plastic", "hp": 15, "kind": "small"},
	"boots": {"model": "rubber_boots", "mass": 1.2, "mat": "plastic", "hp": 40, "kind": "small"},
	"basket": {"model": "wicker_basket_01", "mass": 0.8, "mat": "wood", "hp": 25, "kind": "small"},
	"sungka": {"model": "sungka_board", "mass": 3.0, "mat": "wood", "hp": 80, "kind": "small"},
	"suitcase": {"model": "vintage_suitcase", "mass": 4.0, "mat": "fabric", "hp": 60, "kind": "small"},
	"ladder": {"model": "wooden_ladder", "mass": 9.0, "mat": "wood", "hp": 120, "kind": "long"},
	"ladder_alu": {"model": "ladder_sectioned_01", "mass": 9.0, "mat": "steel", "hp": 300, "kind": "long"},
	"tool_chest": {"model": "metal_tool_chest", "mass": 40.0, "mat": "steel", "hp": 900, "kind": "cabinet"},
	"toolbox": {"model": "metal_toolbox", "mass": 6.0, "mat": "steel", "hp": 300, "kind": "small"},
	"drill_press": {"model": "drill_press_01", "mass": 80.0, "mat": "steel", "hp": 2000, "kind": "heavy", "static": true},
	"welding_cart": {"model": "portable_welding_cart", "mass": 50.0, "mat": "steel", "hp": 900, "kind": "heavy"},
	"generator": {"model": "portable_generator", "mass": 45.0, "mat": "steel", "hp": 900, "kind": "heavy"},
	"hand_truck": {"model": "hand_truck", "mass": 14.0, "mat": "steel", "hp": 500, "kind": "long"},
	"tire_pump": {"model": "tire_pump", "mass": 2.0, "mat": "steel", "hp": 100, "kind": "small"},
	"wheel_rim": {"model": "rusted_wheel_rim_01", "mass": 9.0, "mat": "steel", "hp": 900, "kind": "small"},
	"sledgehammer": {"model": "sledgehammer_01", "mass": 4.0, "mat": "steel", "hp": 900, "kind": "small"},
	"crowbar": {"model": "crowbar_01", "mass": 1.5, "mat": "steel", "hp": 900, "kind": "small"},
	"wrench": {"model": "pipe_wrench", "mass": 1.5, "mat": "steel", "hp": 900, "kind": "small"},
	"medical_box": {"model": "medical_box", "mass": 3.0, "mat": "steel", "hp": 120, "kind": "small"},
	"wheelchair": {"model": "wheelchair_01", "mass": 16.0, "mat": "steel", "hp": 500, "kind": "heavy"},
	"crutches": {"model": "vintage_crutches_01", "mass": 1.5, "mat": "wood", "hp": 60, "kind": "small"},
	"extinguisher": {"model": "korean_fire_extinguisher_01", "mass": 6.0, "mat": "steel", "hp": 600, "kind": "small"},
	"chalkboard": {"model": "standing_chalkboard_01", "mass": 15.0, "mat": "wood", "hp": 150, "kind": "long"},
	"utility_box": {"model": "utility_box_01", "mass": 30.0, "mat": "steel", "hp": 900, "kind": "fixture", "static": true},
	"utility_box2": {"model": "utility_box_02", "mass": 30.0, "mat": "steel", "hp": 900, "kind": "fixture", "static": true},
	"power_box": {"model": "power_box_01", "mass": 25.0, "mat": "steel", "hp": 900, "kind": "fixture", "static": true},
	"aircon": {"model": "exterior_aircon_unit", "mass": 35.0, "mat": "steel", "hp": 600, "kind": "fixture", "static": true},
	"hydrant": {"model": "fire_hydrant", "mass": 80.0, "mat": "steel", "hp": 5000, "kind": "fixture", "static": true},
	"barrier": {"model": "concrete_road_barrier", "mass": 900.0, "mat": "concrete", "hp": 99999, "kind": "fixture", "static": true},
	"manhole": {"model": "water_manhole_cover", "mass": 40.0, "mat": "steel", "hp": 99999, "kind": "fixture", "static": true},
	"street_lamp": {"model": "street_lamp_01", "mass": 200.0, "mat": "steel", "hp": 99999, "kind": "fixture", "static": true},
	"street_lamp2": {"model": "street_lamp_02", "mass": 200.0, "mat": "steel", "hp": 99999, "kind": "fixture", "static": true},
	"security_light": {"model": "security_light", "mass": 3.0, "mat": "steel", "hp": 99999, "kind": "fixture", "static": true},
	"boat": {"model": "ship_pinnace", "mass": 400.0, "mat": "wood", "hp": 99999, "kind": "fixture", "static": true},
	"lifebuoy": {"model": "lifebuoy", "mass": 2.0, "mat": "plastic", "hp": 99, "kind": "small"},
	"buoy": {"model": "ocean_buoy", "mass": 60.0, "mat": "plastic", "hp": 99999, "kind": "fixture", "static": true},
	"covered_car": {"model": "covered_car", "mass": 1200.0, "mat": "steel", "hp": 99999, "kind": "fixture", "static": true},
	"pipes": {"model": "modular_industrial_pipes_01", "mass": 500.0, "mat": "steel", "hp": 99999, "kind": "fixture", "static": true},
	"lamp_industrial": {"model": "hanging_industrial_lamp", "mass": 3.0, "mat": "steel", "hp": 99999, "kind": "fixture", "static": true},
	"fluorescent": {"model": "mounted_fluorescent_lights", "mass": 3.0, "mat": "steel", "hp": 30, "kind": "fixture", "static": true},
	"bulb_socket": {"model": "pull_chain_light_socket", "mass": 0.3, "mat": "plastic", "hp": 10, "kind": "fixture", "static": true},
	"crate_ammo": {"model": "ammo_box", "mass": 6.0, "mat": "steel", "hp": 300, "kind": "small"},
	"hollow_block": {"prim": "box", "size": Vector3(0.4, 0.2, 0.15), "mass": 12.0, "mat": "hollow_block", "hp": 300, "kind": "heavy", "surface": "chb", "static": true},
	"stone": {"prim": "box", "size": Vector3(0.3, 0.18, 0.25), "mass": 8.0, "mat": "concrete", "hp": 99999, "kind": "heavy", "surface": "concrete_dirty", "static": true},
	"plank_pile": {"prim": "box", "size": Vector3(2.2, 0.25, 0.6), "mass": 50.0, "mat": "wood", "hp": 400, "kind": "heavy", "surface": "planks", "static": true},
	"hollow_block_pile": {"prim": "box", "size": Vector3(1.2, 0.6, 0.8), "mass": 300.0, "mat": "hollow_block", "hp": 99999, "kind": "heavy", "surface": "chb", "static": true},
	"sandbag": {"prim": "box", "size": Vector3(0.7, 0.18, 0.4), "mass": 25.0, "mat": "sand", "hp": 99999, "kind": "heavy", "surface": "hessian", "static": true},
	"plywood_sheet": {"prim": "box", "size": Vector3(1.2, 2.2, 0.02), "mass": 10.0, "mat": "plywood", "hp": 80, "kind": "long", "surface": "plywood"},
	"yero_sheet": {"prim": "box", "size": Vector3(0.82, 2.4, 0.01), "mass": 6.0, "mat": "sheet_metal", "hp": 500, "kind": "long", "surface": "yero_rust"},
	"banig": {"prim": "box", "size": Vector3(1.6, 0.01, 1.9), "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "surface": "bamboo2", "static": true},
	"mattress": {"prim": "box", "size": Vector3(1.0, 0.12, 1.9), "mass": 8.0, "mat": "fabric", "hp": 99999, "kind": "heavy", "surface": "gingham"},
	"toilet": {"prim": "box", "size": Vector3(0.38, 0.4, 0.55), "mass": 25.0, "mat": "concrete", "hp": 300, "kind": "fixture", "surface": "tiles", "static": true},
	"counter": {"prim": "box", "size": Vector3(1.6, 0.95, 0.55), "mass": 80.0, "mat": "wood", "hp": 600, "kind": "heavy", "surface": "planks_paint", "static": true},
	"sink_counter": {"prim": "box", "size": Vector3(1.2, 0.85, 0.5), "mass": 60.0, "mat": "concrete", "hp": 600, "kind": "heavy", "surface": "tiles", "static": true},
	"altar_shelf": {"prim": "box", "size": Vector3(0.7, 0.05, 0.25), "mass": 2.0, "mat": "wood", "hp": 30, "kind": "decor", "surface": "planks_dark", "static": true},
	"workbench": {"prim": "box", "size": Vector3(2.0, 0.9, 0.7), "mass": 90.0, "mat": "wood", "hp": 800, "kind": "heavy", "surface": "planks_dark", "static": true},
	"market_stall": {"prim": "box", "size": Vector3(2.0, 0.85, 1.0), "mass": 120.0, "mat": "concrete", "hp": 99999, "kind": "heavy", "surface": "tiles", "static": true},
	"pallet": {"prim": "box", "size": Vector3(1.2, 0.14, 1.0), "mass": 18.0, "mat": "wood", "hp": 200, "kind": "heavy", "surface": "planks"},
}

var mats = null
var _cache: Dictionary = {}


func _init(materials) -> void:
	mats = materials


func spec(name: String) -> Dictionary:
	return PROPS.get(name, {})


func get_model(name: String) -> Dictionary:
	## Returns {mesh: Mesh, aabb: AABB} for a logical prop or Poly Haven id. Cached.
	if _cache.has(name):
		return _cache[name]
	var s: Dictionary = PROPS.get(name, {})
	var res := {}
	if s.has("prim"):
		var bm := BoxMesh.new()
		bm.size = s.size
		bm.material = mats.get_material(str(s.get("surface", "plywood")))
		res = {"mesh": bm, "aabb": AABB(-s.size * 0.5 + Vector3(0, s.size.y * 0.5, 0), s.size), "offset": Vector3(0, s.size.y * 0.5, 0)}
	else:
		var id := str(s.get("model", name))
		res = _load_scene_mesh(PH + id + "/" + id + ".gltf")
		if res.is_empty():
			res = _load_scene_mesh(PROCESSED + id + ".glb")
	_cache[name] = res
	return res


func _load_scene_mesh(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var ps: PackedScene = load(path)
	if ps == null:
		return {}
	var inst := ps.instantiate()
	var st := SurfaceTool.new()
	var mesh := ArrayMesh.new()
	var aabb := AABB()
	var first := true
	var meshes := _collect(inst, Transform3D())
	for item in meshes:
		var mi: MeshInstance3D = item[0]
		var xf: Transform3D = item[1]
		var m := mi.mesh
		if m == null:
			continue
		for si in m.get_surface_count():
			var arrays := m.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms = arrays[Mesh.ARRAY_NORMAL]
			var tans = arrays[Mesh.ARRAY_TANGENT]
			for i in verts.size():
				verts[i] = xf * verts[i]
				if first:
					aabb = AABB(verts[i], Vector3.ZERO)
					first = false
				else:
					aabb = aabb.expand(verts[i])
			arrays[Mesh.ARRAY_VERTEX] = verts
			if norms is PackedVector3Array:
				for i in norms.size():
					norms[i] = (xf.basis * norms[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = norms
			if tans is PackedFloat32Array and tans.size() >= 4:
				for i in range(0, tans.size(), 4):
					var t := (xf.basis * Vector3(tans[i], tans[i + 1], tans[i + 2])).normalized()
					tans[i] = t.x
					tans[i + 1] = t.y
					tans[i + 2] = t.z
				arrays[Mesh.ARRAY_TANGENT] = tans
			# Drop blend shapes / bones; props are rigid.
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat := mi.get_active_material(si)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	inst.free()
	if mesh.get_surface_count() == 0:
		return {}
	return {"mesh": mesh, "aabb": aabb, "offset": Vector3.ZERO}


func _collect(n: Node, xf: Transform3D) -> Array:
	var out := []
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		out.append([n, here])
	for c in n.get_children():
		out.append_array(_collect(c, here))
	return out
