@tool
extends EditorImportPlugin
## .map (TrenchBroom, Valve 220) -> PackedScene. The scene is built by map_scene.gd; see there for what each entity
## becomes. Re-import after changing surfaces.json or a material override (FileSystem dock > right-click > Reimport).

const MapScene := preload("res://addons/aetherion_map/map_scene.gd")


func _get_importer_name() -> String:
	return "aetherion.brush_map"


func _get_visible_name() -> String:
	return "Brush map (TrenchBroom / Valve 220)"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["map"])


func _get_save_extension() -> String:
	return "scn"


func _get_resource_type() -> String:
	return "PackedScene"


func _get_preset_count() -> int:
	return 1


func _get_preset_name(_preset_index: int) -> String:
	return "Default"


func _get_import_order() -> int:
	return 100   # after textures (the materials point at them)


func _get_priority() -> float:
	return 1.0


func _can_import_threaded() -> bool:
	return false   # loads textures and materials while it builds


func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return [
		{"name": "units_per_metre", "default_value": 32.0},
		{"name": "textures_root", "default_value": "res://assets/maps/textures", "property_hint": PROPERTY_HINT_DIR},
		{"name": "surfaces", "default_value": "res://assets/maps/surfaces.json", "property_hint": PROPERTY_HINT_FILE, "hint_string": "*.json"},
		{"name": "material_overrides", "default_value": "res://assets/maps/materials", "property_hint": PROPERTY_HINT_DIR},
		{"name": "chunk_size", "default_value": 24.0},
	]


func _get_option_visibility(_path: String, _option_name: StringName, _options: Dictionary) -> bool:
	return true


func _import(source_file: String, save_path: String, options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var text := FileAccess.get_file_as_string(source_file)
	if text.is_empty():
		push_error("[map import] cannot read %s" % source_file)
		return ERR_CANT_OPEN
	var builder = MapScene.new()
	var root: Node3D = builder.build(text, options, source_file.get_file().get_basename())
	if root == null:
		return ERR_PARSE_ERROR
	var ps := PackedScene.new()
	var err := ps.pack(root)
	root.free()
	if err != OK:
		push_error("[map import] could not pack %s: %s" % [source_file, error_string(err)])
		return err
	print("[map import] %s: %s" % [source_file, JSON.stringify(builder.stats)])
	return ResourceSaver.save(ps, "%s.%s" % [save_path, _get_save_extension()], ResourceSaver.FLAG_COMPRESS)
