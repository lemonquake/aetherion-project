extends RefCounted
## Material library for generated architecture and terrain. Each logical surface names a Poly Haven texture set,
## its real-world tile size (metres per texture repeat), the physical material used by bullets and footsteps,
## and shader tuning.

const SHADER := preload("res://src/world/surface.gdshader")
const TEX := "res://assets/thirdparty/polyhaven/textures/"
const NOISE := preload("res://assets/fx/noise_rgba.png")

const SURFACES := {
	"yero_rust": {"tex": "rusty_corrugated_iron", "tile": 1.6, "phys": "sheet_metal", "metal": 0.35, "grime": 0.4},
	"yero": {"tex": "corrugated_iron_02", "tile": 1.6, "phys": "sheet_metal", "metal": 0.55, "grime": 0.5},
	"yero_worn": {"tex": "worn_corrugated_iron", "tile": 1.6, "phys": "sheet_metal", "metal": 0.4, "grime": 0.5},
	"yero_paint": {"tex": "corrugated_iron_03", "tile": 1.6, "phys": "sheet_metal", "metal": 0.25, "grime": 0.5, "flake": 0.45},
	"metal_rust": {"tex": "rusty_metal_04", "tile": 1.2, "phys": "steel", "metal": 0.5, "grime": 0.3},
	"metal_sheet": {"tex": "rusty_metal_sheet", "tile": 1.4, "phys": "sheet_metal", "metal": 0.4, "grime": 0.4},
	"metal_paint": {"tex": "rusty_painted_metal", "tile": 1.2, "phys": "steel", "metal": 0.2, "grime": 0.4},
	"shutter": {"tex": "rusty_metal_shutter", "tile": 2.0, "phys": "sheet_metal", "metal": 0.4, "grime": 0.4},
	"grate": {"tex": "metal_grate_rusty", "tile": 1.0, "phys": "steel", "metal": 0.5, "grime": 0.2},
	"plywood": {"tex": "plywood", "tile": 1.2, "phys": "plywood", "grime": 0.7, "flake": 0.6},
	"osb": {"tex": "oriented_strand_board", "tile": 1.2, "phys": "plywood", "grime": 0.7},
	"planks": {"tex": "weathered_planks", "tile": 2.0, "phys": "wood", "grime": 0.6, "flake": 0.55},
	"planks_blue": {"tex": "blue_painted_planks", "tile": 2.0, "phys": "wood", "grime": 0.6},
	"planks_paint": {"tex": "distressed_painted_planks", "tile": 2.0, "phys": "wood", "grime": 0.6},
	"planks_peel": {"tex": "wood_peeling_paint_weathered", "tile": 1.8, "phys": "wood", "grime": 0.6},
	"planks_dark": {"tex": "dark_wooden_planks", "tile": 2.0, "phys": "wood", "grime": 0.5},
	"planks_green": {"tex": "green_rough_planks", "tile": 2.0, "phys": "wood", "grime": 0.6},
	"siding": {"tex": "weathered_plank_siding", "tile": 2.0, "phys": "wood", "grime": 0.6, "flake": 0.5},
	"timber": {"tex": "weathered_peeling_timber", "tile": 1.5, "phys": "wood", "grime": 0.5},
	"floor_wood": {"tex": "old_wood_floor", "tile": 2.0, "phys": "wood", "grime": 0.3},
	"floor_planks": {"tex": "worn_planks", "tile": 2.0, "phys": "wood", "grime": 0.4},
	"bamboo": {"tex": "bamboo_wall", "tile": 1.5, "phys": "wood", "grime": 0.5},
	"bamboo2": {"tex": "bamboo_wall_02", "tile": 1.5, "phys": "wood", "grime": 0.5},
	"chb": {"tex": "concrete_block_wall", "tile": 2.0, "phys": "hollow_block", "grime": 0.7},
	"chb2": {"tex": "concrete_block_wall_02", "tile": 2.0, "phys": "hollow_block", "grime": 0.7},
	"plaster": {"tex": "rough_plaster_broken", "tile": 2.5, "phys": "plaster", "grime": 0.8, "flake": 0.5},
	"plaster_damaged": {"tex": "damaged_plaster", "tile": 2.5, "phys": "plaster", "grime": 0.8, "flake": 0.5},
	"plaster_peel": {"tex": "peeling_painted_wall", "tile": 2.5, "phys": "plaster", "grime": 0.7},
	"plaster_cracked": {"tex": "worn_cracked_plaster", "tile": 2.5, "phys": "plaster", "grime": 0.7, "flake": 0.5},
	"plaster_white": {"tex": "white_plaster_02", "tile": 2.5, "phys": "plaster", "grime": 0.8, "flake": 0.45},
	"plaster_blue": {"tex": "blue_plaster_weathered", "tile": 2.5, "phys": "plaster", "grime": 0.7},
	"plaster_red": {"tex": "red_plaster_weathered", "tile": 2.5, "phys": "plaster", "grime": 0.7},
	"plaster_yellow": {"tex": "yellow_plaster", "tile": 2.5, "phys": "plaster", "grime": 0.8},
	"plaster_moss": {"tex": "worn_mossy_plasterwall", "tile": 2.5, "phys": "plaster", "grime": 0.6},
	"concrete": {"tex": "concrete_wall_008", "tile": 3.0, "phys": "concrete", "grime": 0.7},
	"concrete_dirty": {"tex": "dirty_concrete", "tile": 3.0, "phys": "concrete", "grime": 0.6},
	"concrete_cracked": {"tex": "cracked_concrete_wall", "tile": 3.0, "phys": "concrete", "grime": 0.6},
	"concrete_rebar": {"tex": "rebar_reinforced_concrete", "tile": 2.5, "phys": "concrete", "grime": 0.5},
	"concrete_floor": {"tex": "damaged_concrete_floor", "tile": 3.0, "phys": "concrete", "grime": 0.4},
	"concrete_floor2": {"tex": "concrete_floor_02", "tile": 3.0, "phys": "concrete", "grime": 0.4},
	"concrete_painted": {"tex": "concrete_floor_painted", "tile": 3.0, "phys": "concrete", "grime": 0.4},
	"garage": {"tex": "garage_floor", "tile": 3.0, "phys": "concrete", "grime": 0.4},
	"cement": {"tex": "scuffed_cement", "tile": 3.0, "phys": "concrete", "grime": 0.5},
	"tiles": {"tex": "dirty_tiles", "tile": 1.2, "phys": "concrete", "grime": 0.4},
	"tiles_floor": {"tex": "worn_tile_floor", "tile": 2.0, "phys": "concrete", "grime": 0.3},
	"tiles_blue": {"tex": "blue_floor_tiles_01", "tile": 1.5, "phys": "concrete", "grime": 0.3},
	"tiles_wall": {"tex": "square_tiled_wall", "tile": 1.2, "phys": "concrete", "grime": 0.3},
	"terrazzo": {"tex": "terrazzo_tiles", "tile": 2.0, "phys": "concrete", "grime": 0.3},
	"linoleum": {"tex": "old_linoleum_flooring_01", "tile": 2.0, "phys": "wood", "grime": 0.3},
	"linoleum_brown": {"tex": "linoleum_brown", "tile": 2.0, "phys": "wood", "grime": 0.3},
	"tarp": {"tex": "fabric_pattern_07", "tile": 1.5, "phys": "fabric", "grime": 0.5},
	"hessian": {"tex": "hessian_230", "tile": 1.0, "phys": "fabric", "grime": 0.4},
	"cloth": {"tex": "cotton_jersey", "tile": 1.0, "phys": "fabric", "grime": 0.2},
	"gingham": {"tex": "gingham_check", "tile": 0.8, "phys": "fabric", "grime": 0.2},
	"carpet": {"tex": "dirty_carpet", "tile": 2.0, "phys": "fabric", "grime": 0.3},
	"asbestos": {"tex": "asbestos_sheet", "tile": 2.0, "phys": "plaster", "grime": 0.6},
	"container": {"tex": "container_side", "tile": 2.5, "phys": "steel", "metal": 0.3, "grime": 0.4},
	"wallpaper": {"tex": "decrepit_wallpaper", "tile": 2.0, "phys": "plaster", "grime": 0.6},
	"ceiling": {"tex": "ceiling_interior", "tile": 2.0, "phys": "plaster", "grime": 0.2, "flake": 0.0},   # r11: whole paint coat (flaking left dark blotches)
	"asphalt": {"tex": "road_damaged", "tile": 6.0, "phys": "concrete", "grime": 0.3},
	"asphalt2": {"tex": "worn_asphalt", "tile": 5.0, "phys": "concrete", "grime": 0.3},
	"pavement": {"tex": "cracked_concrete", "tile": 4.0, "phys": "concrete", "grime": 0.3},
	"rubble": {"tex": "rubble", "tile": 3.0, "phys": "dirt", "grime": 0.2},
	"mud": {"tex": "brown_mud_02", "tile": 4.0, "phys": "dirt", "grime": 0.1},
	"dirt": {"tex": "dirt_floor", "tile": 4.0, "phys": "dirt", "grime": 0.1},
	"gravel": {"tex": "gravel_road", "tile": 4.0, "phys": "dirt", "grime": 0.1},
	"sand": {"tex": "coast_sand_01", "tile": 4.0, "phys": "sand", "grime": 0.0},
	"bark": {"tex": "palm_tree_bark", "tile": 1.5, "phys": "wood", "grime": 0.2},
	# Lawless Sub (r7): a suburb's roads, lots and canals, its houses' walls, roofs and floors, and the factory.
	"road_asphalt": {"tex": "asphalt_04", "tile": 6.0, "phys": "concrete", "grime": 0.25},
	"road_asphalt2": {"tex": "asphalt_06", "tile": 6.0, "phys": "concrete", "grime": 0.25},
	"lot_asphalt": {"tex": "clean_asphalt", "tile": 5.0, "phys": "concrete", "grime": 0.3},
	"sidewalk": {"tex": "concrete_pavers", "tile": 3.0, "phys": "concrete", "grime": 0.35},
	"pavers": {"tex": "interlocking_concrete_pavers", "tile": 2.5, "phys": "concrete", "grime": 0.35},
	"driveway": {"tex": "grooved_concrete_driveway", "tile": 3.0, "phys": "concrete", "grime": 0.35},
	"canal_wall": {"tex": "concrete_wall_007", "tile": 3.0, "phys": "concrete", "grime": 0.6},
	"concrete_panels": {"tex": "concrete_panels", "tile": 4.0, "phys": "concrete", "grime": 0.5},
	"facade_tile": {"tex": "concrete_tile_facade", "tile": 3.0, "phys": "concrete", "grime": 0.5, "flake": 0.22},
	"lawn": {"tex": "grass_path_2", "tile": 4.0, "phys": "dirt", "grime": 0.0},
	"lawn_leafy": {"tex": "grass_ground", "tile": 3.0, "phys": "dirt", "grime": 0.0},
	"roof_tiles": {"tex": "clay_roof_tiles_02", "tile": 2.5, "phys": "concrete", "grime": 0.45},
	"roof_tiles_grey": {"tex": "grey_roof_tiles", "tile": 2.5, "phys": "concrete", "grime": 0.45},
	"wall_beige": {"tex": "beige_wall_002", "tile": 2.5, "phys": "plaster", "grime": 0.6, "flake": 0.4},
	"wall_grey": {"tex": "grey_plaster", "tile": 2.5, "phys": "plaster", "grime": 0.6, "flake": 0.4},
	"wall_painted": {"tex": "painted_plaster_wall", "tile": 2.5, "phys": "plaster", "grime": 0.6, "flake": 0.45},
	"wall_plaster4": {"tex": "plastered_wall_04", "tile": 2.5, "phys": "plaster", "grime": 0.6},
	"brick_painted": {"tex": "painted_brick", "tile": 2.0, "phys": "hollow_block", "grime": 0.5},
	"brick": {"tex": "brick_wall_006", "tile": 2.0, "phys": "hollow_block", "grime": 0.5},
	"cladding": {"tex": "exterior_wall_cladding_03", "tile": 2.5, "phys": "plaster", "grime": 0.5},
	"laminate": {"tex": "laminate_floor_02", "tile": 2.0, "phys": "wood", "grime": 0.25},
	"parquet": {"tex": "herringbone_parquet", "tile": 1.5, "phys": "wood", "grime": 0.25},
	"tiles_interior": {"tex": "interior_tiles", "tile": 1.5, "phys": "concrete", "grime": 0.25},
	"tiles_white": {"tex": "long_white_tiles", "tile": 1.5, "phys": "concrete", "grime": 0.3},
	"marble": {"tex": "marble_tiles", "tile": 2.0, "phys": "concrete", "grime": 0.2},
	"patio": {"tex": "patio_tiles", "tile": 2.0, "phys": "concrete", "grime": 0.35},
	"factory_wall": {"tex": "factory_wall", "tile": 3.0, "phys": "sheet_metal", "metal": 0.4, "grime": 0.45},
	"factory_floor": {"tex": "hangar_concrete_floor", "tile": 4.0, "phys": "concrete", "grime": 0.35},
	"factory_brick": {"tex": "factory_brick", "tile": 2.5, "phys": "hollow_block", "grime": 0.5},
	"metal_plate": {"tex": "metal_plate", "tile": 1.5, "phys": "steel", "metal": 0.6, "grime": 0.3, "flake": 0.3},
	"metal_blue": {"tex": "blue_metal_plate", "tile": 1.5, "phys": "steel", "metal": 0.4, "grime": 0.35},
	# r15 Malasugue Mall: polished ("rough" lowers the texture's roughness, so the floors take the lights'
	# reflections), no rain streaks or damp line. r16: the mall after the outbreak: dirt tracked over the floors in
	# patches ("patch") and grime at the foot of the walls (the pieces' dirt comes from MallBuilder.o).
	"mall_floor": {"tex": "large_floor_tiles_02", "tile": 3.2, "phys": "concrete", "grime": 0.55, "patch": 1.0, "rough": -0.42, "clean": true},
	"mall_granite": {"tex": "granite_tile", "tile": 1.6, "phys": "concrete", "grime": 0.5, "patch": 1.0, "rough": -0.45, "clean": true},
	"mall_marble": {"tex": "marble_01", "tile": 4.0, "phys": "concrete", "grime": 0.5, "patch": 1.0, "rough": -0.5, "clean": true},
	"mall_mosaic": {"tex": "marble_mosaic_tiles", "tile": 1.2, "phys": "concrete", "grime": 0.55, "patch": 1.0, "rough": -0.3, "clean": true},
	"mall_tiles": {"tex": "floor_tiles_08", "tile": 1.6, "phys": "concrete", "grime": 0.55, "patch": 1.0, "rough": -0.35, "clean": true},
	"mall_grey": {"tex": "large_grey_tiles", "tile": 2.4, "phys": "concrete", "grime": 0.55, "patch": 1.0, "rough": -0.25, "clean": true},
	"mall_rubber": {"tex": "rubber_tiles", "tile": 1.0, "phys": "fabric", "grime": 0.4, "patch": 1.0, "clean": true},
	"stair_concrete": {"tex": "anti_slip_concrete", "tile": 2.0, "phys": "concrete", "grime": 0.5, "patch": 1.0, "clean": true},
	"mall_paint": {"tex": "plastered_wall_02", "tile": 3.0, "phys": "plaster", "grime": 0.45, "flake": 0.0, "clean": true},
	"oak": {"tex": "oak_veneer_01", "tile": 1.6, "phys": "wood", "grime": 0.4, "patch": 1.0, "rough": -0.25, "clean": true},
	"walnut": {"tex": "walnut_veneer", "tile": 1.6, "phys": "wood", "grime": 0.4, "patch": 1.0, "rough": -0.2, "clean": true},
	"white_oak": {"tex": "white_oak_veneer", "tile": 1.6, "phys": "wood", "grime": 0.4, "patch": 1.0, "rough": -0.2, "clean": true},
	"velvet": {"tex": "velour_velvet", "tile": 0.8, "phys": "fabric", "grime": 0.0, "clean": true},
	"leather": {"tex": "brown_leather", "tile": 1.0, "phys": "fabric", "grime": 0.0, "rough": -0.15, "clean": true},
	"boucle": {"tex": "wool_boucle", "tile": 0.8, "phys": "fabric", "grime": 0.0, "clean": true},
	"plaza_hex": {"tex": "hexagonal_concrete_paving", "tile": 2.5, "phys": "concrete", "grime": 0.15},
	# made for the mall (tools/make_mall_textures.py): polished cream porcelain, a grey accent band, the atrium's
	# larger slabs; the Christmas tree's and the garlands' foliage.
	"mall_cream": {"dir": "res://assets/mall/tex/floor_cream", "tile": 2.4, "phys": "concrete", "grime": 0.85, "patch": 1.0, "clean": true},
	"mall_band": {"dir": "res://assets/mall/tex/floor_band", "tile": 2.4, "phys": "concrete", "grime": 0.85, "patch": 1.0, "clean": true},
	"mall_atrium": {"dir": "res://assets/mall/tex/floor_atrium", "tile": 2.4, "phys": "concrete", "grime": 0.85, "patch": 1.0, "clean": true},
	"mall_foliage": {"tex": "leafy_grass", "tile": 0.9, "phys": "fabric", "grime": 0.0, "flake": 0.0, "clean": true},
}

## r15: plain (untextured) mall materials, by name: [albedo, roughness, metallic, physical material]. "vc" ones take
## their colour from the vertex tint (sink opt tint), so one material serves every painted part.
const PLAIN := {
	"mall_steel": [Color(0.74, 0.75, 0.77), 0.3, 0.92, "steel"],
	"mall_chrome": [Color(0.86, 0.87, 0.9), 0.08, 1.0, "steel"],
	"mall_black": [Color(0.03, 0.03, 0.035), 0.22, 0.0, "plaster"],
	"mall_light_dead": [Color(0.3, 0.3, 0.29), 0.35, 0.0, "plaster"],   # r16: a fitting with no power
	"mall_mirror": [Color(0.9, 0.92, 0.94), 0.02, 1.0, "glass"],
	"mall_flat": [Color(1, 1, 1), 0.7, 0.0, "plaster", "vc"],
	"mall_satin": [Color(1, 1, 1), 0.38, 0.0, "plaster", "vc"],
	"mall_gloss": [Color(1, 1, 1), 0.12, 0.0, "plaster", "vc"],
	"mall_cloth": [Color(1, 1, 1), 0.9, 0.0, "fabric", "vc"],
	"mall_metal_vc": [Color(1, 1, 1), 0.35, 0.75, "steel", "vc"],
}

## Paint colours seen on Filipino informal housing: sun-faded pastels, institutional greens and blues, primer reds.
const PAINTS := [
	Color(0.55, 0.72, 0.78), Color(0.62, 0.8, 0.66), Color(0.86, 0.72, 0.78), Color(0.9, 0.84, 0.62),
	Color(0.78, 0.84, 0.88), Color(0.52, 0.62, 0.45), Color(0.72, 0.46, 0.38), Color(0.92, 0.9, 0.84),
	Color(0.48, 0.58, 0.74), Color(0.8, 0.62, 0.45), Color(0.66, 0.52, 0.66), Color(0.85, 0.55, 0.42),
	Color(0.35, 0.55, 0.62), Color(0.95, 0.78, 0.5),
]

var _cache: Dictionary = {}
var _tex_cache: Dictionary = {}
var urban_arrays := false
var _urban_layers: Dictionary = {}
var mall_horror := false

# Atlas cell, roughness bias, metalness, albedo gain. This profile is enabled
# only for Malasugue Mall, including its props, concrete structure and furniture.
const MALL_CELLS := {
	"mall_cream": [20, -.10, 0, 1], "mall_floor": [0, -.08, 0, 1],
	"mall_band": [1, -.08, 0, .8], "mall_granite": [1, -.06, 0, 1],
	"mall_atrium": [2, -.12, 0, 1], "mall_marble": [2, -.1, 0, 1],
	"mall_mosaic": [3, -.08, 0, 1], "mall_tiles": [13, -.12, 0, 1],
	"mall_grey": [20, .02, 0, .85], "mall_paint": [24, 0, 0, 1],
	"mall_wall_cream": [16,0,0,1], "mall_wall_sage": [17,0,0,1], "mall_wall_buff": [18,0,0,1], "mall_wall_brick": [19,0,0,1],
	"mall_terrazzo": [20,-.08,0,1], "mall_green_stone": [21,-.1,0,1], "mall_geometric": [22,-.08,0,1], "mall_repair": [23,0,0,1],
	"mall_ceiling": [5, 0, 0, .87], "mall_rubber": [9, 0, 0, 1],
	"mall_foliage": [15, 0, 0, .7], "mall_steel": [6, -.08, .77, .85],
	"mall_chrome": [6, -.16, .88, 1], "mall_black": [9, -.15, 0, .25],
	"mall_mirror": [6, -.24, .94, 1], "mall_light_dead": [5, 0, 0, .45],
	"mall_flat": [16, 0, 0, .92], "mall_satin": [16, -.1, 0, .95],
	"mall_gloss": [13, -.2, 0, .9], "mall_cloth": [10, 0, 0, 1],
	"mall_metal_vc": [14, -.08, .6, .9], "mall_tread": [7, 0, .65, 1],
	"oak": [8, 0, 0, .8], "walnut": [8, 0, 0, .55], "white_oak": [8, .08, 0, 1],
	"velvet": [10, 0, 0, .7], "leather": [11, 0, 0, 1], "boucle": [10, 0, 0, .8],
}


func _mall_data(name: String) -> PackedFloat32Array:
	if MALL_CELLS.has(name):
		return PackedFloat32Array(MALL_CELLS[name])
	if not SURFACES.has(name):
		return PackedFloat32Array()
	var ph := str(SURFACES[name].get("phys", "concrete"))
	var cell := 12
	if ph in ["wood", "plywood"]:
		cell = 8
	elif ph in ["steel", "sheet_metal"]:
		cell = 14
	elif ph == "fabric":
		cell = 10
	elif ph == "plaster":
		cell = 4
	if name.begins_with("tiles") or name in ["terrazzo", "marble"]:
		cell = 13
	if name == "ceiling":
		cell = 5
	if name in ["concrete","concrete_panels","cement","concrete_floor2"]:
		cell = 23
	return PackedFloat32Array([float(cell), 0.0, 0.5 if cell == 14 else 0.0, 0.9])


func enable_urban_arrays() -> void:
	## Opaque architecture shares three imported, compressed arrays. Models and
	## transparent surfaces retain their existing materials and physical metadata.
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/urban/surfaces.json"))
	if data is Dictionary:
		_urban_layers = data
		urban_arrays = true


## (r15) The mall's vertex-tinted materials drawn as one batch (mall_vc.gdshader): name -> [roughness, metallic].
const VC_BATCH := {"mall_flat": [0.7, 0.0], "mall_satin": [0.38, 0.0], "mall_gloss": [0.12, 0.0], "mall_cloth": [0.9, 0.0],
	"mall_metal_vc": [0.35, 0.75]}
var _vc_data := {}


func batch_name(name: String) -> String:
	if mall_horror and not _mall_data(name).is_empty():
		return "mall_horror"
	if VC_BATCH.has(name):
		return "mall_vc"
	return "urban_array" if urban_arrays and _urban_layers.has(name) else name


func surface_data(name: String) -> PackedFloat32Array:
	if mall_horror:
		var md := _mall_data(name)
		if not md.is_empty():
			return md
	if VC_BATCH.has(name):
		if not _vc_data.has(name):
			_vc_data[name] = PackedFloat32Array([float(VC_BATCH[name][0]), float(VC_BATCH[name][1]), 0.0, 0.0])
		return _vc_data[name]
	if not urban_arrays or not _urban_layers.has(name):
		return PackedFloat32Array()
	var s: Dictionary = SURFACES[name]
	return PackedFloat32Array([float(_urban_layers[name]), float(s.get("metal", 0.0)), float(s.get("grime", 0.5)), float(s.get("flake", 0.55))])


func get_material(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	if mall_horror and not _mall_data(name).is_empty():
		var direct := get_material("mall_horror").duplicate() as ShaderMaterial
		direct.set_shader_parameter("batched", false)
		var data := _mall_data(name)
		direct.set_shader_parameter("profile", Vector4(data[0],data[1],data[2],data[3]))
		_cache[name] = direct
		return direct
	if mall_horror and name in ["mall_signs", "mall_signs_dead", "mall_wayfind", "mall_banners", "mall_posters", "mall_goods", "mall_rails"]:
		var print_mat := ShaderMaterial.new()
		print_mat.shader = preload("res://src/world/maps/malasugue_mall/horror_print.gdshader")
		var image_name := "signs" if name == "mall_signs_dead" else name.substr(5)
		print_mat.set_shader_parameter("print_tex",_tex("res://assets/mall/"+image_name+".png"))
		print_mat.set_shader_parameter("noise_tex",NOISE)
		print_mat.set_shader_parameter("glow",.3 if name == "mall_wayfind" else (.12 if name == "mall_signs" else 0.0))
		_cache[name] = print_mat
		return print_mat
	var m: Material
	match name:
		"mall_horror":
			var hm := ShaderMaterial.new()
			hm.shader = preload("res://src/world/maps/malasugue_mall/horror_surface.gdshader")
			for channel in ["albedo", "normal", "orm"]:
				hm.set_shader_parameter(channel + "_atlas", _tex("res://assets/mall/horror/" + channel + ".png"))
				hm.set_shader_parameter(channel + "_variants", _tex("res://assets/mall/horror/" + channel + "_variants.png"))
			hm.set_shader_parameter("noise_tex", NOISE)
			m = hm
		"urban_array":
			var ua := ShaderMaterial.new()
			ua.shader = preload("res://src/world/urban_surface.gdshader")
			ua.set_shader_parameter("albedo_array", load("res://assets/urban/surfaces_albedo.png"))
			ua.set_shader_parameter("normal_array", load("res://assets/urban/surfaces_normal.png"))
			ua.set_shader_parameter("orm_array", load("res://assets/urban/surfaces_orm.png"))
			ua.set_shader_parameter("noise_tex", NOISE)
			m = ua
		"glass":
			var g := StandardMaterial3D.new()
			g.albedo_color = Color(0.55, 0.62, 0.6, 0.32)
			g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g.roughness = 0.12
			g.metallic = 0.2
			g.metallic_specular = 0.8
			g.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = g
		"glass_frosted":
			var g2 := StandardMaterial3D.new()
			g2.albedo_color = Color(0.7, 0.75, 0.72, 0.55)
			g2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			g2.roughness = 0.5
			g2.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = g2
		"mall_glass":
			# Shopfront and balustrade glass: clearer than a house window, with a hint of green edge tint.
			var mg := StandardMaterial3D.new()
			mg.albedo_color = Color(0.72, 0.8, 0.78, 0.16)
			mg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mg.roughness = 0.04
			mg.metallic = 0.1
			mg.metallic_specular = 0.9
			mg.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = mg
		"mall_glow", "mall_light", "mall_light_warm":
			# Emitters: downlights, light coves, neon. mall_glow takes its colour from the vertex tint.
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var gc := Color(1.0, 0.97, 0.9) if name == "mall_light" else Color(1.0, 0.82, 0.58)
			if name == "mall_glow":
				gm.vertex_color_use_as_albedo = true
				gc = Color(1, 1, 1)
			gm.albedo_color = gc
			m = gm
		"mall_signs_dead":
			# r16: a shop sign whose power is off: the same print, unlit and dusty.
			var sd := StandardMaterial3D.new()
			sd.albedo_texture = _tex("res://assets/mall/signs.png")
			sd.albedo_color = Color(0.62, 0.6, 0.58)
			sd.roughness = 0.6
			sd.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m = sd
		"mall_signs", "mall_wayfind", "mall_banners", "mall_posters", "mall_goods", "mall_rails":
			# Printed and back-lit graphics (tools/make_mall_assets.py): signs and wayfinding glow.
			var sm2 := StandardMaterial3D.new()
			var tex := _tex("res://assets/mall/%s.png" % name.substr(5))
			sm2.albedo_texture = tex
			sm2.roughness = 0.45 if name != "mall_goods" else 0.6
			sm2.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if name in ["mall_signs", "mall_wayfind"]:
				# Back-lit: the print itself glows a little (multiply: the colours stay; add would whiten them).
				sm2.emission_enabled = true
				sm2.emission_texture = tex
				sm2.emission = Color(1, 1, 1)
				sm2.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				sm2.emission_energy_multiplier = 0.35
			if name == "mall_banners":
				sm2.cull_mode = BaseMaterial3D.CULL_DISABLED
			m = sm2
		"city_windows":
			# The city round the mall: a grid of windows, some lit (their own emission map), by day and night.
			var cw := StandardMaterial3D.new()
			cw.albedo_texture = _tex("res://assets/mall/tex/city_windows/albedo.png")
			cw.emission_enabled = true
			cw.emission_texture = _tex("res://assets/mall/tex/city_windows/emission.png")
			cw.emission_energy_multiplier = 0.9
			cw.roughness = 0.6
			cw.vertex_color_use_as_albedo = true
			m = cw
		"mall_vc":
			var vc := ShaderMaterial.new()
			vc.shader = preload("res://src/world/maps/malasugue_mall/mall_vc.gdshader")
			vc.set_shader_parameter("noise_tex", NOISE)
			m = vc
		"mall_ads":
			var am2 := ShaderMaterial.new()
			am2.shader = preload("res://src/world/maps/malasugue_mall/led_screen.gdshader")
			am2.set_shader_parameter("frames", _tex("res://assets/mall/ads.png"))
			m = am2
		"black":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.02, 0.02, 0.02)
			b.roughness = 1.0
			m = b
		"wire":
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.015, 0.015, 0.016)
			wm.roughness = 0.55
			m = wm
		"puddle":
			var pm := ShaderMaterial.new()
			pm.shader = preload("res://src/world/puddle.gdshader")
			m = pm
		"decal_atlas":
			# Every wall and ground decal in one texture (tools/make_vandal_atlas.py): one draw call per chunk.
			var am := ShaderMaterial.new()
			am.shader = preload("res://src/world/decal.gdshader")
			am.set_shader_parameter("tex", _tex("res://assets/fx/vandal_atlas.png"))
			m = am
		_:
			if PLAIN.has(name):
				var pl: Array = PLAIN[name]
				var pm2 := StandardMaterial3D.new()
				pm2.albedo_color = pl[0]
				pm2.roughness = float(pl[1])
				pm2.metallic = float(pl[2])
				pm2.vertex_color_use_as_albedo = pl.size() > 4
				m = pm2
			elif name.begins_with("decal:"):
				var dm := ShaderMaterial.new()
				dm.shader = preload("res://src/world/decal.gdshader")
				dm.set_shader_parameter("tex", _tex(name.substr(6)))
				m = dm
			else:
				m = _surface(name)
	_cache[name] = m
	return m


func _surface(name: String) -> Material:
	var s: Dictionary = SURFACES.get(name, SURFACES.plywood)
	var dir: String = (str(s.dir) if s.has("dir") else TEX + str(s.tex)) + "/"
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var alb := _tex(dir + "albedo.jpg")
	if alb == null:
		alb = _tex(dir + "albedo.png")
	mat.set_shader_parameter("albedo_tex", alb if alb else _fallback())
	var nrm := _tex(dir + "normal.jpg")
	if nrm == null:
		nrm = _tex(dir + "normal.png")
	if nrm:
		mat.set_shader_parameter("normal_tex", nrm)
	var rgh := _tex(dir + "roughness.jpg")
	if rgh == null:
		rgh = _tex(dir + "roughness.png")
	if rgh:
		mat.set_shader_parameter("rough_tex", rgh)
	var ao := _tex(dir + "ao.jpg")
	if ao == null:
		ao = _tex(dir + "ao.png")
	if ao:
		mat.set_shader_parameter("ao_tex", ao)
		mat.set_shader_parameter("use_ao", true)
	mat.set_shader_parameter("metallic", float(s.get("metal", 0.0)))
	mat.set_shader_parameter("grime", float(s.get("grime", 0.5)))
	mat.set_shader_parameter("paint_flake", float(s.get("flake", 0.55)))
	mat.set_shader_parameter("noise_tex", NOISE)
	if s.get("clean", false):
		mat.set_shader_parameter("streaks", 0.0)
		mat.set_shader_parameter("water_line", -1000.0)
	mat.set_shader_parameter("rough_offset", float(s.get("rough", 0.0)))
	mat.set_shader_parameter("floor_patch", float(s.get("patch", 0.0)))
	return mat


func tile(name: String) -> float:
	if name in ["mall_terrazzo","mall_green_stone"]:
		return 3.6
	if name == "mall_geometric":
		return 2.4
	if name.begins_with("mall_wall_"):
		return 4.0
	if name == "mall_ceiling":
		return 2.4
	return float(SURFACES.get(name, {}).get("tile", 2.0))


func phys(name: String) -> String:
	if mall_horror:
		if name == "mall_repair":
			return "concrete"
		if name in ["mall_terrazzo","mall_green_stone","mall_geometric"]:
			return "tile"
		if name in ["mall_tread"]:
			return "steel"
		if name in ["mall_cream", "mall_floor", "mall_band", "mall_granite", "mall_atrium", "mall_marble", "mall_mosaic", "mall_tiles", "mall_grey", "tiles", "tiles_wall", "tiles_white", "terrazzo", "marble"]:
			return "tile"
		if name == "mall_rubber":
			return "rubber"
	if name.begins_with("glass") or name == "mall_glass":
		return "glass"
	if PLAIN.has(name):
		return str(PLAIN[name][3])
	if name.begins_with("mall_") and not SURFACES.has(name):
		return "plaster"
	if name.begins_with("decal:") or name == "puddle" or name == "wire" or name == "decal_atlas":
		return "fabric"
	return str(SURFACES.get(name, {}).get("phys", "default"))


func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t


func _fallback() -> Texture2D:
	if _tex_cache.has("_fallback"):
		return _tex_cache["_fallback"]
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.48, 0.45))
	var t := ImageTexture.create_from_image(img)
	_tex_cache["_fallback"] = t
	return t
