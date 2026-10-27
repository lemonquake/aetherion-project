extends RefCounted
## Loads third-party models once, merges each into a single multi-surface Mesh with its own materials, and records
## its bounds. Instancing (MultiMesh) and physics props use the merged mesh.
##
## Model ids are Poly Haven asset ids, or entries with a path (processed Sketchfab / Blender assets) or a primitive.
## A Poly Haven id loads its game-ready copy (res://assets/models/polyhaven/<id>.gltf, made by
## tools/blender/process_props.py: one variant, decimated, one material); the download itself
## (res://assets/thirdparty/polyhaven/models/<id>/<id>_1k.gltf, some of it millions of triangles) is only a fallback.

const PH := "res://assets/thirdparty/polyhaven/models/"
const PH_PROCESSED := "res://assets/models/polyhaven/"
const PROCESSED := "res://assets/models/"

## Logical prop name -> {path or primitive, scale, mass, phys material, breakable, health}
## Cabinets are static: the dresser puts loot containers inside them as fixed volumes, and a movable body there would
## take the use ray ("grab" instead of "search") and could be pushed away from its contents.
const PROPS := {
	"monobloc": {"model": "plastic_monobloc_chair_01", "mass": 2.2, "mat": "plastic", "hp": 60, "kind": "chair"},
	"chair_wood": {"model": "painted_wooden_chair_01", "mass": 4.5, "mat": "wood", "hp": 90, "kind": "chair"},
	"chair_wood2": {"model": "painted_wooden_chair_02", "mass": 4.5, "mat": "wood", "hp": 90, "kind": "chair"},
	"chair_plain": {"model": "painted_wooden_chair_02", "mass": 4.0, "mat": "wood", "hp": 80, "kind": "chair"},
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
	"cabinet_paint": {"model": "painted_wooden_cabinet", "mass": 40.0, "mat": "wood", "hp": 260, "kind": "cabinet", "static": true},
	"cabinet_paint2": {"model": "painted_wooden_cabinet_02", "mass": 38.0, "mat": "wood", "hp": 260, "kind": "cabinet", "static": true},
	"shelves_paint": {"model": "painted_wooden_shelves", "mass": 18.0, "mat": "wood", "hp": 160, "kind": "cabinet", "static": true},
	"nightstand": {"model": "painted_wooden_nightstand", "mass": 12.0, "mat": "wood", "hp": 120, "kind": "cabinet", "static": true},
	"drawer_cabinet": {"model": "drawer_cabinet", "mass": 30.0, "mat": "wood", "hp": 220, "kind": "cabinet", "static": true},
	"drawer_old": {"model": "vintage_wooden_drawer_01", "mass": 28.0, "mat": "wood", "hp": 200, "kind": "cabinet", "static": true},
	"bookshelf": {"model": "wooden_bookshelf_worn", "mass": 35.0, "mat": "wood", "hp": 240, "kind": "cabinet", "static": true},
	"steel_shelves": {"model": "steel_frame_shelves_01", "mass": 25.0, "mat": "steel", "hp": 600, "kind": "cabinet", "static": true},
	"steel_shelves2": {"model": "steel_frame_shelves_02", "mass": 25.0, "mat": "steel", "hp": 600, "kind": "cabinet", "static": true},
	"shelf": {"model": "Shelf_01", "mass": 12.0, "mat": "wood", "hp": 120, "kind": "cabinet", "static": true},
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
	"trashbag": {"model": "trashbag", "mass": 4.0, "mat": "fabric", "hp": 30, "kind": "small", "no_block": true},
	"old_tyre": {"model": "old_tyre", "mass": 9.0, "mat": "plastic", "hp": 400, "kind": "small"},
	"cement_bag": {"model": "cement_bag", "mass": 25.0, "mat": "sand", "hp": 200, "kind": "heavy"},
	"can": {"model": "can_rusted", "mass": 0.3, "mat": "sheet_metal", "hp": 20, "kind": "small", "throwable": true, "no_block": true},
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
	"tool_chest": {"model": "metal_tool_chest", "mass": 40.0, "mat": "steel", "hp": 900, "kind": "cabinet", "static": true},
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
	# Loot boxes (tools/blender/make_loot_models.py): containers you can see; the _open model replaces the closed one
	# once somebody has searched it.
	"lootbox_balikbayan": {"path": "res://assets/models/loot/lootbox_balikbayan.glb", "mass": 8.0, "mat": "fabric", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_balikbayan_open": {"path": "res://assets/models/loot/lootbox_balikbayan_open.glb", "mass": 8.0, "mat": "fabric", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_bin": {"path": "res://assets/models/loot/lootbox_bin.glb", "mass": 4.0, "mat": "plastic", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_bin_open": {"path": "res://assets/models/loot/lootbox_bin_open.glb", "mass": 4.0, "mat": "plastic", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_ammocan": {"path": "res://assets/models/loot/lootbox_ammocan.glb", "mass": 6.0, "mat": "sheet_metal", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_ammocan_open": {"path": "res://assets/models/loot/lootbox_ammocan_open.glb", "mass": 6.0, "mat": "sheet_metal", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_footlocker": {"path": "res://assets/models/loot/lootbox_footlocker.glb", "mass": 20.0, "mat": "wood", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_footlocker_open": {"path": "res://assets/models/loot/lootbox_footlocker_open.glb", "mass": 20.0, "mat": "wood", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_toolbox": {"path": "res://assets/models/loot/lootbox_toolbox.glb", "mass": 7.0, "mat": "sheet_metal", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_toolbox_open": {"path": "res://assets/models/loot/lootbox_toolbox_open.glb", "mass": 7.0, "mat": "sheet_metal", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_medcase": {"path": "res://assets/models/loot/lootbox_medcase.glb", "mass": 3.0, "mat": "plastic", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_medcase_open": {"path": "res://assets/models/loot/lootbox_medcase_open.glb", "mass": 3.0, "mat": "plastic", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_riflecase": {"path": "res://assets/models/loot/lootbox_riflecase.glb", "mass": 9.0, "mat": "plastic", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_riflecase_open": {"path": "res://assets/models/loot/lootbox_riflecase_open.glb", "mass": 9.0, "mat": "plastic", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_cooler": {"path": "res://assets/models/loot/lootbox_cooler.glb", "mass": 6.0, "mat": "plastic", "hp": 99999, "kind": "lootbox", "static": true},
	"lootbox_cooler_open": {"path": "res://assets/models/loot/lootbox_cooler_open.glb", "mass": 6.0, "mat": "plastic", "hp": 99999, "kind": "lootbox", "static": true},
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
	"heap_large_a": {"path": "res://assets/models/sleep/kit/heap_large_a.glb", "mass": 400.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true, "no_collide": true},
	"heap_large_b": {"path": "res://assets/models/sleep/kit/heap_large_b.glb", "mass": 400.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true, "no_collide": true},
	"heap_medium_a": {"path": "res://assets/models/sleep/kit/heap_medium_a.glb", "mass": 200.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true, "no_collide": true},
	"heap_medium_b": {"path": "res://assets/models/sleep/kit/heap_medium_b.glb", "mass": 200.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true, "no_collide": true},
	"heap_small_a": {"path": "res://assets/models/sleep/kit/heap_small_a.glb", "mass": 60.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true, "no_collide": true},
	"heap_small_b": {"path": "res://assets/models/sleep/kit/heap_small_b.glb", "mass": 60.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true, "no_collide": true},
	"litter_a": {"path": "res://assets/models/sleep/kit/litter_a.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"litter_b": {"path": "res://assets/models/sleep/kit/litter_b.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"rubble_a": {"path": "res://assets/models/sleep/kit/rubble_a.glb", "mass": 300.0, "mat": "concrete", "hp": 99999, "kind": "fixture", "static": true},
	"rubble_b": {"path": "res://assets/models/sleep/kit/rubble_b.glb", "mass": 300.0, "mat": "concrete", "hp": 99999, "kind": "fixture", "static": true},
	"floating_a": {"path": "res://assets/models/sleep/kit/floating_a.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"floating_b": {"path": "res://assets/models/sleep/kit/floating_b.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"floating_c": {"path": "res://assets/models/sleep/kit/floating_c.glb", "mass": 1.0, "mat": "fabric", "hp": 99999, "kind": "decor", "static": true, "no_collide": true},
	"old_mattress": {"path": "res://assets/models/sleep/kit/mattress.glb", "mass": 10.0, "mat": "fabric", "hp": 99999, "kind": "fixture", "static": true},
	"tricycle_a": {"path": "res://assets/models/sleep/street/tricycle_a.glb", "mass": 300.0, "mat": "sheet_metal", "hp": 99999, "kind": "vehicle", "static": true},
	"tricycle_b": {"path": "res://assets/models/sleep/street/tricycle_b.glb", "mass": 300.0, "mat": "sheet_metal", "hp": 99999, "kind": "vehicle", "static": true},
	"jeepney": {"path": "res://assets/models/sleep/street/jeepney.glb", "mass": 2500.0, "mat": "steel", "hp": 99999, "kind": "vehicle", "static": true},
	"food_cart_a": {"path": "res://assets/models/sleep/street/food_cart_a.glb", "mass": 80.0, "mat": "wood", "hp": 99999, "kind": "vehicle", "static": true},
	"food_cart_b": {"path": "res://assets/models/sleep/street/food_cart_b.glb", "mass": 80.0, "mat": "wood", "hp": 99999, "kind": "vehicle", "static": true},
	"food_stall": {"path": "res://assets/models/sleep/street/food_stall_c.glb", "mass": 120.0, "mat": "wood", "hp": 99999, "kind": "vehicle", "static": true},
	"oil_drum": {"path": "res://assets/models/sleep/street/oil_drum.glb", "mass": 20.0, "mat": "sheet_metal", "hp": 500, "kind": "heavy"},
	"palm_a": {"path": "res://assets/models/sleep/nature/palm_coconut_a.glb", "mass": 500.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.25},
	"palm_b": {"path": "res://assets/models/sleep/nature/palm_coconut_b.glb", "mass": 500.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.25},
	"banana_a": {"path": "res://assets/models/sleep/nature/banana_plant.glb", "mass": 50.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"banana_b": {"path": "res://assets/models/sleep/nature/banana_small.glb", "mass": 50.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"bamboo": {"path": "res://assets/models/sleep/nature/bamboo_clump.glb", "mass": 200.0, "mat": "wood", "hp": 99999, "kind": "plant", "static": true, "trunk": 0.6},
	"reeds": {"path": "res://assets/models/sleep/nature/reeds.glb", "mass": 5.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"cattails": {"path": "res://assets/models/sleep/nature/cattails.glb", "mass": 5.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"fern": {"path": "res://assets/models/sleep/nature/fern.glb", "mass": 2.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"tree_island": {"model": "island_tree_01", "mass": 900.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.35},
	"tree_island2": {"model": "island_tree_02", "mass": 900.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.35},
	"tree_small": {"model": "tree_small_02", "mass": 300.0, "mat": "wood", "hp": 99999, "kind": "tree", "static": true, "trunk": 0.2},
	"shrub": {"model": "shrub_02", "mass": 20.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"grass_clump": {"model": "grass_medium_01", "mass": 1.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
	"weeds": {"model": "weed_plant_02", "mass": 1.0, "mat": "foliage", "hp": 99999, "kind": "plant", "static": true, "no_collide": true},
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
	elif s.has("path"):
		res = _load_scene_mesh(str(s.path))
	else:
		var id := str(s.get("model", name))
		res = _load_scene_mesh(PH_PROCESSED + id + ".gltf")
		if res.is_empty():
			res = _load_scene_mesh(_ph_path(id))
			if not res.is_empty():
				push_warning("ModelLib: no processed copy of %s, loading the Poly Haven original (run tools/blender/process_props.py)" % id)
		if res.is_empty():
			res = _load_scene_mesh(PROCESSED + id + ".glb")
	_cache[name] = res
	return res


func _ph_path(id: String) -> String:
	## Poly Haven downloads keep the published file name (<id>_1k.gltf).
	for suffix in ["_1k.gltf", ".gltf", "_2k.gltf"]:
		var p = PH + id + "/" + id + suffix
		if ResourceLoader.exists(p):
			return p
	return ""


func _load_scene_mesh(path: String) -> Dictionary:
	## Merges every mesh in the scene into one Mesh: node transforms baked in, surfaces that share a material joined
	## (each surface is a draw call per pass, for every MultiMesh cell), then LODs generated: merging drops the
	## imported ones, and instanced props are drawn far away and in every shadow pass.
	if path == "" or not ResourceLoader.exists(path):
		return {}
	var ps: PackedScene = load(path)
	if ps == null:
		return {}
	var inst := ps.instantiate()
	var groups := {}   # material/format key -> {mat, arrays}
	var order := []
	var aabb := AABB()
	var first := true
	for item in _collect(inst, Transform3D()):
		var mi: MeshInstance3D = item[0]
		var xf: Transform3D = item[1]
		var m := mi.mesh
		if m == null:
			continue
		for si in m.get_surface_count():
			if m.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := m.surface_get_arrays(si)
			var verts: PackedVector3Array = xf * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			if verts.is_empty():
				continue
			arrays[Mesh.ARRAY_VERTEX] = verts
			var sub := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				sub = sub.expand(v)
			aabb = sub if first else aabb.merge(sub)
			first = false
			var norms = arrays[Mesh.ARRAY_NORMAL]
			if norms is PackedVector3Array and not xf.basis.is_equal_approx(Basis()):
				var nb := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
				var nn: PackedVector3Array = nb * (norms as PackedVector3Array)
				for i in nn.size():
					nn[i] = nn[i].normalized()
				arrays[Mesh.ARRAY_NORMAL] = nn
			var tans = arrays[Mesh.ARRAY_TANGENT]
			if tans is PackedFloat32Array and tans.size() >= 4 and not xf.basis.is_equal_approx(Basis()):
				for i in range(0, tans.size(), 4):
					var t := (xf.basis * Vector3(tans[i], tans[i + 1], tans[i + 2])).normalized()
					tans[i] = t.x
					tans[i + 1] = t.y
					tans[i + 2] = t.z
				arrays[Mesh.ARRAY_TANGENT] = tans
			# Props are rigid: no skin, no blend shapes, no custom channels.
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			for ci in 4:
				arrays[Mesh.ARRAY_CUSTOM0 + ci] = null
			if arrays[Mesh.ARRAY_INDEX] == null:
				var seq := PackedInt32Array()
				seq.resize(verts.size())
				for i in verts.size():
					seq[i] = i
				arrays[Mesh.ARRAY_INDEX] = seq
			var mat := mi.get_active_material(si)
			var fmt := ""
			for k in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
				fmt += "1" if arrays[k] != null else "0"
			var key := "%d|%s" % [mat.get_instance_id() if mat else 0, fmt]
			if not groups.has(key):
				groups[key] = {"mat": mat, "arrays": arrays}
				order.append(key)
			else:
				_append_arrays(groups[key].arrays, arrays)
	inst.free()
	if order.is_empty():
		return {}
	var im := ImporterMesh.new()
	for key in order:
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, groups[key].arrays, [], {}, groups[key].mat)
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	return {"mesh": mesh, "aabb": aabb, "offset": Vector3.ZERO}


static func _append_arrays(dst: Array, src: Array) -> void:
	var base := (dst[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if dst[k] != null:
			var a = dst[k]
			a.append_array(src[k])
			dst[k] = a
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	for i in idx.size():
		idx[i] += base
	var di: PackedInt32Array = dst[Mesh.ARRAY_INDEX]
	di.append_array(idx)
	dst[Mesh.ARRAY_INDEX] = di


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
