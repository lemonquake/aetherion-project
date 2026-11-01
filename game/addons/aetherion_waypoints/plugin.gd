@tool
extends EditorPlugin
## (r23) The bot waypoint editor: with a Waypoints node (waypoint_set.gd) or one of its waypoints selected, the 3D
## view's toolbar gets Link / Unlink / Save / Check, and Shift + click on the shown level's floor adds a waypoint
## (joined to the one selected). Every action can be undone.

const WaypointNode := preload("res://addons/aetherion_waypoints/waypoint_node.gd")
const WaypointSet := preload("res://addons/aetherion_waypoints/waypoint_set.gd")

var _bar: HBoxContainer = null
var _set = null


func _enter_tree() -> void:
	_bar = HBoxContainer.new()
	var hint := Label.new()
	hint.text = "Waypoints: Shift+click adds"
	_bar.add_child(hint)
	for b in [["Link", _link], ["Unlink", _unlink], ["Save for the game", _save], ["Check in game", _check]]:
		var btn := Button.new()
		btn.text = str(b[0])
		btn.flat = true
		btn.pressed.connect(b[1])
		_bar.add_child(btn)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	_bar.hide()


func _exit_tree() -> void:
	if _bar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
		_bar.queue_free()
		_bar = null


func _handles(object: Object) -> bool:
	return _set_of(object) != null


func _edit(object: Object) -> void:
	_set = _set_of(object) if object != null else null


func _make_visible(visible: bool) -> void:
	if _bar != null:
		_bar.visible = visible


func _set_of(o):
	if not (o is Node):
		return null
	var n: Node = o
	while n != null:
		if n.get_script() == WaypointSet:
			return n
		n = n.get_parent()
	return null


func _selected() -> Array:
	var out := []
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n.get_script() == WaypointNode:
			out.append(n)
	return out


func _forward_3d_gui_input(cam: Camera3D, event: InputEvent) -> int:
	if _set == null or not (event is InputEventMouseButton):
		return AFTER_GUI_INPUT_PASS
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or not mb.shift_pressed:
		return AFTER_GUI_INPUT_PASS
	var sel := _selected()
	var lv: int = _set.show_level
	if lv <= 0:
		lv = _set.level_of((sel[0] as Node3D).global_position) if not sel.is_empty() else 1
	var y: float = (lv - 1) * float(_set.floor_height)
	var o := cam.project_ray_origin(mb.position)
	var d := cam.project_ray_normal(mb.position)
	if absf(d.y) < 0.0001:
		return AFTER_GUI_INPUT_PASS
	var t := (y - o.y) / d.y
	if t <= 0.0:
		return AFTER_GUI_INPUT_PASS
	_add_at(o + d * t, lv, sel[0] if sel.size() == 1 else null)
	return AFTER_GUI_INPUT_STOP


func _add_at(p: Vector3, lv: int, join_to) -> void:
	var g: Node3D = _set.level_group(lv)
	var n = WaypointNode.new()
	n.name = _set.new_name(lv)
	n.position = g.to_local(Vector3(snappedf(p.x, 0.25), p.y, snappedf(p.z, 0.25)))
	n.kind = "area"
	n.priority = 2
	var root := EditorInterface.get_edited_scene_root()
	var ur := get_undo_redo()
	ur.create_action("Add a waypoint")
	ur.add_do_method(g, "add_child", n, true)
	ur.add_do_method(n, "set_owner", root)
	ur.add_do_reference(n)
	ur.add_undo_method(g, "remove_child", n)
	if join_to != null:
		ur.add_do_method(self, "_join", join_to, n)
		ur.add_undo_method(self, "_part", join_to, n)
	ur.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(n)


func _join(a, b) -> void:
	a.link_to(b)
	b.link_to(a)


func _part(a, b) -> void:
	a.unlink(str(b.name))
	b.unlink(str(a.name))


func _link() -> void:
	var sel := _selected()
	if sel.size() < 2:
		push_warning("[waypoints] select two waypoints or more to link")
		return
	var pairs := []
	if sel.size() == 2:
		pairs.append([sel[0], sel[1]])
	else:
		for a in sel:
			var best = null
			var bd := INF
			for b in sel:
				if b == a:
					continue
				var dd := (a as Node3D).global_position.distance_to((b as Node3D).global_position)
				if dd < bd:
					bd = dd
					best = b
			if best != null:
				pairs.append([a, best])
	var ur := get_undo_redo()
	ur.create_action("Link waypoints")
	for pr in pairs:
		if str(pr[1].name) in pr[0].links:
			continue
		ur.add_do_method(self, "_join", pr[0], pr[1])
		ur.add_undo_method(self, "_part", pr[0], pr[1])
	ur.commit_action()


func _unlink() -> void:
	var sel := _selected()
	var ur := get_undo_redo()
	ur.create_action("Unlink waypoints")
	for a in sel:
		for b in sel:
			if a != b and str(b.name) in a.links and str(a.name) < str(b.name):
				ur.add_do_method(self, "_part", a, b)
				ur.add_undo_method(self, "_join", a, b)
	ur.commit_action()


func _save() -> void:
	if _set != null:
		_set.save_to_game()


func _check() -> void:
	if _set != null:
		_set.check_in_game()
