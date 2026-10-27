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
	"ceiling": {"tex": "ceiling_interior", "tile": 2.0, "phys": "plaster", "grime": 0.2},
	"asphalt": {"tex": "road_damaged", "tile": 6.0, "phys": "concrete", "grime": 0.3},
	"asphalt2": {"tex": "worn_asphalt", "tile": 5.0, "phys": "concrete", "grime": 0.3},
	"pavement": {"tex": "cracked_concrete", "tile": 4.0, "phys": "concrete", "grime": 0.3},
	"rubble": {"tex": "rubble", "tile": 3.0, "phys": "dirt", "grime": 0.2},
	"mud": {"tex": "brown_mud_02", "tile": 4.0, "phys": "dirt", "grime": 0.1},
	"dirt": {"tex": "dirt_floor", "tile": 4.0, "phys": "dirt", "grime": 0.1},
	"gravel": {"tex": "gravel_road", "tile": 4.0, "phys": "dirt", "grime": 0.1},
	"sand": {"tex": "coast_sand_01", "tile": 4.0, "phys": "sand", "grime": 0.0},
	"bark": {"tex": "palm_tree_bark", "tile": 1.5, "phys": "wood", "grime": 0.2},
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


func get_material(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m: Material
	match name:
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
			if name.begins_with("decal:"):
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
	var dir: String = TEX + str(s.tex) + "/"
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
	return mat


func tile(name: String) -> float:
	return float(SURFACES.get(name, {}).get("tile", 2.0))


func phys(name: String) -> String:
	if name.begins_with("glass"):
		return "glass"
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
