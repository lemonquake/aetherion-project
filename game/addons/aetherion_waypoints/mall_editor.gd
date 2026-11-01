@tool
extends Node3D
## (r23) Malasugue Mall's map editor (editor/malasugue_mall_editor.tscn). Shows the mall as the game builds it
## (editor/malasugue_mall/mall_preview.scn, made by tools/mall_preview_export.tscn) with the floors above the one
## being edited hidden, and holds:
##   Waypoints  the bots' waypoint graph (select it: Load / Save / Check in game in the inspector, the toolbar in 3D);
##   Extras     anything placed under it (walls, crates, cover, lights: any node or scene, with collision where bots
##              and players should bump into it) is added to the mall in the game. Saved with "Save for the game".
## The game never loads this scene: it reads the waypoint file and the extras scene the buttons write.

const PREVIEW := "res://editor/malasugue_mall/mall_preview.scn"
const EXTRAS := "res://assets/maps/malasugue_mall_extras.scn"

## Show the mall up to this level (0: every floor); the waypoints show the same level.
@export_range(0, 5) var level := 0:
	set(v):
		level = v
		set_cut(v)
		var w := get_node_or_null("Waypoints")
		if w != null and w.get("show_level") != v:
			w.set("show_level", v)
## The suspended ceilings (they hide the floor from above).
@export var ceilings := false:
	set(v):
		ceilings = v
		set_cut(level)
@export_tool_button("Save extras for the game", "Save") var _b_extras = save_extras

var _preview: Node3D = null


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	if ResourceLoader.exists(PREVIEW):
		_preview = (load(PREVIEW) as PackedScene).instantiate()
		add_child(_preview, false, Node.INTERNAL_MODE_FRONT)
	else:
		push_warning("[mall editor] no %s: run tools/mall_preview_export.tscn once" % PREVIEW)
	set_cut(level)


func set_cut(v: int) -> void:
	if _preview == null:
		return
	for c in _preview.get_children():
		var nm := str(c.name)
		if nm == "Ceilings":
			(c as Node3D).visible = ceilings
		elif nm.begins_with("Level"):
			(c as Node3D).visible = v == 0 or int(nm.substr(5)) <= v


func save_extras() -> void:
	## The Extras node's children as their own scene, which the game adds to the mall (map_builder.gd _mall_extras).
	var ex := get_node_or_null("Extras")
	if ex == null or ex.get_child_count() == 0:
		if FileAccess.file_exists(EXTRAS):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(EXTRAS))
			print("[mall editor] no extras: %s removed" % EXTRAS)
		return
	var dup: Node = ex.duplicate()
	_own(dup, dup)
	var ps := PackedScene.new()
	var err := ps.pack(dup)
	if err == OK:
		err = ResourceSaver.save(ps, EXTRAS)
	dup.free()
	print("[mall editor] saved %d extras to %s (%s)" % [ex.get_child_count(), EXTRAS, error_string(err)])


func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		if c.scene_file_path == "":
			_own(c, root)
