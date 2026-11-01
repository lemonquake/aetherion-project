extends SceneTree
## (r23) The mall editor's waypoint scripts outside the editor: load the game's graph into nodes, move one, add one
## joined to another, delete one, save under a test name, read the file back and load it the way the game does.
##   godot --headless --path game -s res://tools/waypoint_editor_test.gd

const WaypointNode := preload("res://addons/aetherion_waypoints/waypoint_node.gd")

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var scene: Node = (load("res://editor/malasugue_mall_editor.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var ws = scene.get_node("Waypoints")
	_check(ws != null and ws.has_method("load_from_game"), "the editor scene has a Waypoints set")
	ws.load_from_game()
	await process_frame
	var nodes: Array = ws.all_nodes()
	var src = JSON.parse_string(FileAccess.get_file_as_string("res://data/waypoints/malasugue_mall.json"))
	_check(nodes.size() == (src.nodes as Array).size(), "loaded every waypoint (%d of %d)" % [nodes.size(), (src.nodes as Array).size()])
	var links := 0
	for n in nodes:
		links += n.links.size()
	_check(links > (src.edges as Array).size(), "joins on both ends (%d link entries for %d edges)" % [links, (src.edges as Array).size()])
	# edit: move the first, delete the second, add one joined to the third
	var a = nodes[0]
	var gone = nodes[1]
	var c = nodes[2]
	var gone_name := str(gone.name)
	a.position += Vector3(0.5, 0.0, 0.0)
	gone.get_parent().remove_child(gone)
	gone.free()
	var lv: int = ws.level_of(c.global_position)
	var n = WaypointNode.new()
	n.name = ws.new_name(lv)
	n.position = c.position + Vector3(1.0, 0.0, 0.0)
	n.kind = "hide"
	n.priority = 1
	n.faces = true
	ws.level_group(lv).add_child(n)
	n.link_to(c)
	c.link_to(n)
	ws.map_id = "rt_test"
	ws.save_to_game()
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/waypoints/rt_test.json"))
	_check(typeof(d) == TYPE_DICTIONARY and str(d.source) == "edited", "saved as an edited graph")
	_check((d.nodes as Array).size() == (src.nodes as Array).size(), "one deleted, one added: same count (%d)" % (d.nodes as Array).size())
	var ids := {}
	for r in d.nodes:
		ids[str(r.id)] = r
	_check(not ids.has(gone_name), "the deleted waypoint is gone")
	_check(ids.has(str(n.name)) and str(ids[str(n.name)].k) == "hide" and int(ids[str(n.name)].pri) == 1 and ids[str(n.name)].has("d"),
		"the new waypoint kept its kind, priority and facing (%s)" % str(n.name))
	var moved: Array = ids[str(a.name)].p
	var orig: Array = (src.nodes as Array)[0].p
	_check(absf(float(moved[0]) - (float(orig[0]) + 0.5)) < 0.02 and absf(float(moved[2]) - float(orig[2])) < 0.02,
		"the moved waypoint's position (%.2f, was %.2f)" % [float(moved[0]), float(orig[0])])
	var joined := false
	var dangling := 0
	for e in d.edges:
		if (str(e[0]) == str(n.name) and str(e[1]) == str(c.name)) or (str(e[1]) == str(n.name) and str(e[0]) == str(c.name)):
			joined = true
		if str(e[0]) == gone_name or str(e[1]) == gone_name:
			dangling += 1
	_check(joined, "the new join is saved")
	_check(dangling == 0, "no join to the deleted waypoint")
	# the game's loader reads it
	var W = load("res://src/ai/waypoints.gd")
	W.map_id = "rt_test"
	_check(W._load(d) and W.nodes.size() == (d.nodes as Array).size(), "the game's loader reads the edited file (%d nodes, %d edges)" % [W.nodes.size(), W.edges.size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data/waypoints/rt_test.json"))
	print("waypoint editor test: %d failed" % fails)
	quit(1 if fails > 0 else 0)
