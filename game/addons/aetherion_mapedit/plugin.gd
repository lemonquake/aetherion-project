@tool
extends EditorPlugin
## (r26) The Aetherion map editor.
##   Maps dock      every map-editor map: Open, New map, Play, Plan picture; the open map's QA notes (click one to
##                  select it, then F in the 3D view to go to it).
##   3D toolbar     (when a map is open) Add a piece where you are looking, Draw walls (click, click, click...;
##                  right click or Esc ends), Pin a note (click the spot), Save map.
##   Pieces         click a surface to select its piece; move / turn with the gizmo; orange handles resize.

const MapDoc := preload("res://src/world/maps/authored/map_doc.gd")
const MapEditor := preload("res://addons/aetherion_mapedit/map_editor.gd")
const MapPiece := preload("res://addons/aetherion_mapedit/map_piece.gd")
const QaNote := preload("res://addons/aetherion_mapedit/qa_note.gd")
const PieceGizmo := preload("res://addons/aetherion_mapedit/piece_gizmo.gd")
const SCENES := "res://editor/maps"

var _gizmo = null
var _bar: HBoxContainer = null
var _dock: VBoxContainer = null
var _list: ItemList = null
var _notes: ItemList = null
var _status: Label = null
var _mode := ""            # "" | "wall" | "note"
var _wall_from = null      # Vector3 while drawing walls
var _wall_btn: Button = null
var _note_btn: Button = null
var _new_dlg: ConfirmationDialog = null
var _new_id: LineEdit = null
var _new_name: LineEdit = null
var _new_levels: SpinBox = null


func _enter_tree() -> void:
	_gizmo = PieceGizmo.new()
	_gizmo.undo = get_undo_redo()
	add_node_3d_gizmo_plugin(_gizmo)
	_make_bar()
	_make_dock()
	set_input_event_forwarding_always_enabled()
	EditorInterface.get_selection().selection_changed.connect(_on_selection)
	scene_changed.connect(_on_scene_changed)
	_refresh.call_deferred()
	if OS.get_environment("AETHERION_MAPEDIT_TEST") != "":
		_selftest.call_deferred()


func _selftest() -> void:
	## The editor's own check (editor_selftest.gd), when the editor was started for it.
	var mid := OS.get_environment("AETHERION_MAPEDIT_MAP")
	await preload("res://addons/aetherion_mapedit/editor_selftest.gd").new().run(self, OS.get_environment("AETHERION_MAPEDIT_TEST"), mid if mid != "" else "covered_court")


func _exit_tree() -> void:
	if EditorInterface.get_selection().selection_changed.is_connected(_on_selection):
		EditorInterface.get_selection().selection_changed.disconnect(_on_selection)
	remove_node_3d_gizmo_plugin(_gizmo)
	if _bar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
		_bar.queue_free()
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
	if _new_dlg != null:
		_new_dlg.queue_free()


func _editor():
	var r := EditorInterface.get_edited_scene_root()
	return r if r != null and r.get_script() == MapEditor else null


# ------------------------------------------------------------------ the toolbar

func _make_bar() -> void:
	_bar = HBoxContainer.new()
	var add := MenuButton.new()
	add.text = "Add piece"
	add.flat = true
	add.tooltip_text = "A new piece where the middle of the view points (on the level you look at)"
	var pm := add.get_popup()
	for t in MapDoc.TYPES:
		pm.add_item(t.capitalize())
	pm.id_pressed.connect(func(i): _add_piece(MapDoc.TYPES[i]))
	_bar.add_child(add)
	_wall_btn = Button.new()
	_wall_btn.text = "Draw walls"
	_wall_btn.toggle_mode = true
	_wall_btn.flat = true
	_wall_btn.tooltip_text = "Click where a wall starts, then where it ends; each click adds the next wall. Right click or Esc ends. Shift: no 0.25 m snap"
	_wall_btn.toggled.connect(func(on): _set_mode("wall" if on else ""))
	_bar.add_child(_wall_btn)
	_note_btn = Button.new()
	_note_btn.text = "Pin a note"
	_note_btn.toggle_mode = true
	_note_btn.flat = true
	_note_btn.tooltip_text = "Click the spot: a QA note pinned there (write what is wrong in the Inspector)"
	_note_btn.toggled.connect(func(on): _set_mode("note" if on else ""))
	_bar.add_child(_note_btn)
	for b in [["Save map", func(): _call("save_map")], ["Play", func(): _call("play_map")]]:
		var btn := Button.new()
		btn.text = str(b[0])
		btn.flat = true
		btn.pressed.connect(b[1])
		_bar.add_child(btn)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	_bar.hide()


func _call(m: String) -> void:
	var ed = _editor()
	if ed != null:
		ed.call(m)


func _set_mode(m: String) -> void:
	_mode = m
	_wall_from = null
	if _wall_btn != null:
		_wall_btn.set_pressed_no_signal(m == "wall")
	if _note_btn != null:
		_note_btn.set_pressed_no_signal(m == "note")


func _on_scene_changed(_root: Node) -> void:
	_refresh()


func _refresh() -> void:
	var ed = _editor()
	if _bar != null:
		_bar.visible = ed != null
	if ed == null:
		_set_mode("")
	_fill_list()
	_fill_notes()


func _on_selection() -> void:
	## A click on a piece's own meshes may select one of them: select the piece instead.
	var sel := EditorInterface.get_selection()
	var swap := []
	for n in sel.get_selected_nodes():
		if n.owner == null and n.get_script() != MapPiece:
			var p: Node = n.get_parent()
			while p != null and p.get_script() != MapPiece:
				p = p.get_parent()
			if p != null:
				swap.append([n, p])
	if not swap.is_empty():
		_swap_selection.call_deferred(swap)


func _swap_selection(swap: Array) -> void:
	var sel := EditorInterface.get_selection()
	for e in swap:
		sel.remove_node(e[0])
		sel.add_node(e[1])


# ------------------------------------------------------------------ clicks in the 3D view

func _forward_3d_gui_input(cam: Camera3D, event: InputEvent) -> int:
	var ed = _editor()
	if ed == null or _mode == "":
		return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		_set_mode("")
		return AFTER_GUI_INPUT_STOP
	if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return AFTER_GUI_INPUT_PASS
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and _mode == "wall":
		_set_mode("")
		return AFTER_GUI_INPUT_STOP
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return AFTER_GUI_INPUT_PASS
	var o := cam.project_ray_origin(mb.position)
	var d := cam.project_ray_normal(mb.position)
	if _mode == "note":
		var hit: Dictionary = ed.pick(o, d)
		var at = hit.get("point", _on_level(ed, o, d))
		if at == null:
			return AFTER_GUI_INPUT_STOP
		_add_note(ed, at, str(hit.node.name) if hit.has("node") else "")
		_set_mode("")
		return AFTER_GUI_INPUT_STOP
	if _mode == "wall":
		var p = _on_level(ed, o, d)
		if p == null:
			return AFTER_GUI_INPUT_STOP
		var snap := 0.01 if mb.shift_pressed else 0.25
		var q := Vector3(snappedf(p.x, snap), p.y, snappedf(p.z, snap))
		if _wall_from == null:
			_wall_from = q
		else:
			var a: Vector3 = _wall_from
			if Vector2(a.x, a.z).distance_to(Vector2(q.x, q.z)) > 0.05:
				_add({"type": "wall", "from": [a.x, a.z], "to": [q.x, q.z], "y": a.y, "h": ed.level_height if ed.level_height > 0.5 else 3.0, "t": 0.2, "openings": [], "layer": "Walls"})
			_wall_from = q
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _level_y(ed, cam_y: float) -> float:
	## The floor of the level being shown (Show Level), else the level the camera is on.
	var lv := int(ed.show_level) - 1 if int(ed.show_level) > 0 else clampi(int(floor(cam_y / maxf(float(ed.level_height), 0.5))), 0, int(ed.levels) - 1)
	return lv * float(ed.level_height)


func _on_level(ed, o: Vector3, d: Vector3):
	var hit: Dictionary = ed.pick(o, d, false)
	if not hit.is_empty() and str(hit.node.piece_type()) in ["floor", "box", "poly", "ramp"]:
		return hit.point   # on a floor, a box or a ramp: on its surface
	var y := _level_y(ed, o.y)
	if absf(d.y) < 1e-4:
		return null
	var k := (y - o.y) / d.y
	return o + d * k if k > 0.0 else null


func _add_piece(t: String) -> void:
	var ed = _editor()
	if ed == null:
		return
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var cam := vp.get_camera_3d()
	var at := Vector3.ZERO
	if cam != null:
		var c := vp.get_visible_rect().size * 0.5
		var p = _on_level(ed, cam.project_ray_origin(c), cam.project_ray_normal(c))
		if p != null:
			at = Vector3(snappedf(p.x, 0.25), snappedf(p.y, 0.05), snappedf(p.z, 0.25))
	var piece: Dictionary = (MapDoc.DEFAULTS.get(t, {}) as Dictionary).duplicate(true)
	piece.type = t
	if t == "wall":
		piece.from = [at.x - 2.0, at.z]
		piece.to = [at.x + 2.0, at.z]
		piece.y = at.y
		piece.layer = "Walls"
	else:
		piece.at = [at.x, at.y + (2.6 if t == "light" else 0.0), at.z]
		piece.layer = "Things" if t in MapDoc.THINGS else "Geometry"
	if t in MapDoc.DEFAULT_MAT:
		piece.mat = MapDoc.DEFAULT_MAT[t]
	_add(piece)


func _add(piece: Dictionary) -> void:
	var ed = _editor()
	var t := str(piece.type)
	piece.id = ed.new_piece_id(t)
	var n = MapPiece.new()
	n.data = piece
	var g: Node3D = ed.layer_node(str(piece.get("layer", "Geometry")))
	var ur := get_undo_redo()
	ur.create_action("Add %s %s" % [t, piece.id])
	ur.add_do_method(g, "add_child", n, true)
	ur.add_do_method(n, "set_owner", EditorInterface.get_edited_scene_root())
	ur.add_do_method(ed, "mark_dirty")
	ur.add_do_reference(n)
	ur.add_undo_method(g, "remove_child", n)
	ur.add_undo_method(ed, "mark_dirty")
	ur.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)


func _add_note(ed, at: Vector3, piece_id: String) -> void:
	var nn: Node3D = ed.get_node_or_null("Notes")
	if nn == null:
		return
	var q = QaNote.new()
	q.name = ed.new_note_id()
	q.position = at
	q.piece = piece_id
	q.created = Time.get_datetime_string_from_system(false, true)
	var ur := get_undo_redo()
	ur.create_action("Pin note %s" % q.name)
	ur.add_do_method(nn, "add_child", q, true)
	ur.add_do_method(q, "set_owner", EditorInterface.get_edited_scene_root())
	ur.add_do_method(ed, "mark_notes_dirty")
	ur.add_do_reference(q)
	ur.add_undo_method(nn, "remove_child", q)
	ur.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(q)
	EditorInterface.inspect_object(q)
	_fill_notes.call_deferred()


# ------------------------------------------------------------------ the Maps dock

func _make_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Maps"
	var lbl := Label.new()
	lbl.text = "Map editor maps"
	_dock.add_child(lbl)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 140)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(i): _open(str(_list.get_item_metadata(i))))
	_dock.add_child(_list)
	var row := HFlowContainer.new()
	for b in [["Open", func(): _open(_picked())], ["New map", _new_map], ["Play", func(): _play(_picked())], ["Refresh", _refresh]]:
		var btn := Button.new()
		btn.text = str(b[0])
		btn.pressed.connect(b[1])
		row.add_child(btn)
	_dock.add_child(row)
	var nl := Label.new()
	nl.text = "QA notes on the open map"
	_dock.add_child(nl)
	_notes = ItemList.new()
	_notes.custom_minimum_size = Vector2(0, 160)
	_notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes.item_selected.connect(_go_note)
	_dock.add_child(_notes)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "Pieces: click to select, drag handles to resize. Notes: Pin a note in the 3D toolbar."
	_dock.add_child(_status)
	add_control_to_dock(DOCK_SLOT_LEFT_UR, _dock)
	_new_dlg = ConfirmationDialog.new()
	_new_dlg.title = "New map"
	var box := VBoxContainer.new()
	_new_id = LineEdit.new()
	_new_id.placeholder_text = "id: lowercase_with_underscores"
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "Name players see"
	_new_levels = SpinBox.new()
	_new_levels.min_value = 1
	_new_levels.max_value = 6
	_new_levels.value = 2
	_new_levels.prefix = "Levels"
	for c in [_new_id, _new_name, _new_levels]:
		box.add_child(c)
	_new_dlg.add_child(box)
	_new_dlg.confirmed.connect(_create_map)
	EditorInterface.get_base_control().add_child(_new_dlg)


func _picked() -> String:
	var s := _list.get_selected_items()
	if s.is_empty():
		var ed = _editor()
		return str(ed.map_id) if ed != null else ""
	return str(_list.get_item_metadata(s[0]))


func _fill_list() -> void:
	if _list == null:
		return
	_list.clear()
	for id in MapDoc.ids():
		var i := _list.add_item("%s  (%s)" % [MapDoc.title(id), id])
		_list.set_item_metadata(i, id)


func _fill_notes() -> void:
	if _notes == null:
		return
	_notes.clear()
	var ed = _editor()
	if ed == null:
		return
	for q in ed.notes():
		var i := _notes.add_item("%s [%s] %s" % [str(q.name), str(q.status), str(q.text).replace("\n", " ").left(60)])
		_notes.set_item_metadata(i, q.get_path())
		_notes.set_item_custom_fg_color(i, QaNote.STATUS_COLORS.get(str(q.status), Color.WHITE))


func _go_note(i: int) -> void:
	var ed = _editor()
	if ed == null:
		return
	var q = ed.get_node_or_null(_notes.get_item_metadata(i))
	if q != null:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(q)


func scene_path(id: String) -> String:
	return "%s/%s.tscn" % [SCENES, id]


func _open(id: String) -> void:
	if id == "":
		return
	var sp := scene_path(id)
	if not ResourceLoader.exists(sp):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENES))
		var root = MapEditor.new()
		root.name = id.to_pascal_case()
		root.map_id = id
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, sp)
		root.free()
		EditorInterface.get_resource_filesystem().update_file(sp)
	EditorInterface.open_scene_from_path(sp)
	_refresh.call_deferred()


func _play(id: String) -> void:
	var ed = _editor()
	if ed != null and str(ed.map_id) == id:
		ed.play_map()
		return
	var exe := OS.get_executable_path()
	OS.create_process(exe, ["--path", ProjectSettings.globalize_path("res://"), "--", "--host", "--game_mode=deathmatch", "--map=" + id, "--bots=7", "--autostart=1"])


func _new_map() -> void:
	_new_id.text = ""
	_new_name.text = ""
	_new_dlg.popup_centered(Vector2i(360, 160))


func _create_map() -> void:
	var id := _new_id.text.strip_edges().to_lower().replace(" ", "_").replace("-", "_")
	if id == "" or not id.is_valid_identifier():
		push_error("[map editor] the id must be lowercase letters, digits and _ (got %s)" % id)
		return
	if MapDoc.exists(id):
		push_error("[map editor] %s exists already" % id)
		return
	var nm := _new_name.text.strip_edges()
	MapDoc.save_doc(MapDoc.normalise(starter(id, nm if nm != "" else id.capitalize(), int(_new_levels.value)), id), id)
	EditorInterface.get_resource_filesystem().scan()
	_fill_list()
	_open(id)


static func starter(id: String, nm: String, levels: int) -> Dictionary:
	## A new map: a 60 x 60 m ground, a lamp, and a spawn for each of two teams, ready to build on.
	return {"id": id, "name": nm, "code": id.substr(0, 2).to_upper(), "modes": ["deathmatch"], "bounds": [-30, -30, 30, 30],
		"levels": levels, "level_height": 3.2, "night_only": false, "field_optional": true,
		"teams": {"max_teams": 2, "max_team_size": 8, "team_size": 6},
		"pieces": [
			{"id": "ground", "type": "floor", "layer": "Ground", "at": [0, 0, 0], "size": [60, 60], "t": 0.3, "mat": "freight/concrete_rough"},
			{"id": "lamp1", "type": "light", "layer": "Lights", "at": [0, 4, 0], "kind": "street", "color": "#ffb46b", "energy": 2.0, "range": 18},
			{"id": "t1_1", "type": "spawn", "layer": "Spawns", "at": [-24, 0, 0], "team": 1, "yaw": 90},
			{"id": "t2_1", "type": "spawn", "layer": "Spawns", "at": [24, 0, 0], "team": 2, "yaw": 270},
		]}
