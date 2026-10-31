@tool
extends EditorPlugin
## Registers the .map importer. With the plugin on, a .map saved from TrenchBroom is re-imported when Godot regains
## focus, and every scene that instances it (game/assets/maps/freight_delight.tscn) shows the new geometry.

var _importer: EditorImportPlugin


func _enter_tree() -> void:
	_importer = preload("res://addons/aetherion_map/map_importer.gd").new()
	add_import_plugin(_importer)


func _exit_tree() -> void:
	remove_import_plugin(_importer)
	_importer = null
