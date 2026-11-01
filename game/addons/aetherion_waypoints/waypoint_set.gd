@tool
extends Node3D
## (r23) A map's bot waypoint graph in the editor: one child per level (Level1 ...), a waypoint node per waypoint,
## and the joins drawn as lines (walk white, tight orange, door cyan, stair / escalator magenta, wade blue; red: joins
## the game's last check dropped). The game reads res://data/waypoints/<map>.json, which "Save for the game" writes.
##
## Editing (with this node or any waypoint selected, in the 3D view):
##   Shift + click      a new waypoint on the shown level's floor, joined to the waypoint selected (if one is)
##   toolbar Link       join the selected waypoints (two: to each other; more: each to the nearest selected one)
##   toolbar Unlink     remove the joins between the selected waypoints
##   Ctrl+D / Delete    copy (keeps the joins) / remove waypoints, as with any node
## Then "Check in game": the game proves every join with its physics (a body-sized sweep) and says what failed.

const WaypointNode := preload("res://addons/aetherion_waypoints/waypoint_node.gd")
const CODES := {"w": "walk", "t": "tight", "d": "door", "s": "stair", "e": "escalator", "v": "wade"}
const LINE_COLORS := {"w": Color(0.9, 0.9, 0.9), "t": Color(1.0, 0.55, 0.1), "d": Color(0.2, 0.9, 1.0), "s": Color(1.0, 0.3, 1.0),
	"e": Color(1.0, 0.3, 1.0), "v": Color(0.3, 0.5, 1.0), "bad": Color(1.0, 0.1, 0.1)}

@export var map_id := "malasugue_mall"
## The game mode the check runs the map in (Sitio Kalinaw: classic).
@export var game_mode := "deathmatch"
## Show one level's waypoints and joins (0: every level).
@export_range(0, 5) var show_level := 0:
	set(v):
		show_level = v
		_apply_level()
## Metres from one level's floor to the next (the mall: 5).
@export var floor_height := 5.0
@export var levels := 5
## Opened with no waypoints: load the game's at once.
@export var auto_load := true
@export_tool_button("Load the game's waypoints", "Load") var _b_load = load_from_game
@export_tool_button("Save for the game", "Save") var _b_save = save_to_game
@export_tool_button("Check in game (physics)", "Search") var _b_check = check_in_game
@export_tool_button("Generate again (replaces all edits)", "Reload") var _b_gen = generate_again

var _lines: MeshInstance3D = null
var _im: ImmediateMesh = null
var _sig := 0
var _t := 0.0
var _bad: Array = []          # [[name, name]] joins the last check dropped
var _next := {}               # level -> next number for new names


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_im = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.mesh = _im
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = false
	_lines.material_override = m
	add_child(_lines, false, Node.INTERNAL_MODE_FRONT)
	set_process(true)
	if auto_load and all_nodes().is_empty() and FileAccess.file_exists(_path()):
		load_from_game.call_deferred()   # opened empty: the game's graph, ready to edit


func _process(dt: float) -> void:
	if not Engine.is_editor_hint():
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.4
	var s := 0
	for n in all_nodes(true):
		var p: Vector3 = n.global_position
		s = hash([s, int(p.x * 20.0), int(p.y * 20.0), int(p.z * 20.0), n.links.size(), str(n.name)])
	if s != _sig:
		_sig = s
		redraw()


func level_group(lv: int) -> Node3D:
	## Level lv (1-based)'s node; made when missing.
	var nm := "Level%d" % lv
	var g := get_node_or_null(nm) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = nm
		add_child(g)
		g.owner = _root()
	return g


func _root() -> Node:
	return get_tree().edited_scene_root if Engine.is_editor_hint() and get_tree().edited_scene_root != null else owner


func level_of(p: Vector3) -> int:
	return clampi(int(floor((p.y + 1.2) / floor_height)), 0, levels - 1) + 1


func all_nodes(shown_only: bool = false) -> Array:
	var out := []
	for g in get_children():
		if not (g is Node3D):
			continue
		if shown_only and show_level > 0 and str(g.name) != "Level%d" % show_level:
			continue
		for c in g.get_children():
			if c.get_script() == WaypointNode:
				out.append(c)
	return out


func new_name(lv: int) -> String:
	var code := {"malasugue_mall": "MM", "freight_delight": "FD", "lawless_sub": "LS", "kalinaw": "SK"}.get(map_id, preload("res://src/world/maps/authored/map_doc.gd").code_of(map_id)) as String
	var g := level_group(lv)
	var k := int(_next.get(lv, 0))
	if k == 0:
		k = 9000   # hand-made waypoints are numbered from 9001
	while true:
		k += 1
		var nm := "%s%d-%04d" % [code, lv, k]
		if g.get_node_or_null(nm) == null:
			_next[lv] = k
			return nm
	return ""


func _apply_level() -> void:
	if not is_inside_tree():
		return
	for g in get_children():
		if g is Node3D and str(g.name).begins_with("Level"):
			(g as Node3D).visible = show_level == 0 or str(g.name) == "Level%d" % show_level
	var p := get_parent()
	if p != null and p.has_method("set_cut"):
		p.set_cut(show_level)
	_sig = 0


# ------------------------------------------------------------------ lines

func redraw() -> void:
	if _im == null:
		return
	_im.clear_surfaces()
	var by := {}
	for n in all_nodes():
		by[str(n.name)] = n
	var shown := {}
	for n2 in all_nodes(true):
		shown[str(n2.name)] = true
	var done := {}
	var any := false
	for nm in shown:
		var a = by[nm]
		for i in a.links.size():
			var o := str(a.links[i])
			if not by.has(o):
				continue
			var k2: String = (nm + "|" + o) if nm < o else (o + "|" + nm)
			if done.has(k2):
				continue
			done[k2] = true
			if not any:
				_im.surface_begin(Mesh.PRIMITIVE_LINES)
				any = true
			var code := str(a.link_kinds[i]) if i < a.link_kinds.size() else "w"
			var c: Color = LINE_COLORS.get(code.substr(0, 1), Color.WHITE)
			_im.surface_set_color(c)
			_im.surface_add_vertex(to_local((a as Node3D).global_position) + Vector3.UP * 0.2)
			_im.surface_set_color(c if code != "e" else Color(0.4, 0.1, 0.4))
			_im.surface_add_vertex(to_local((by[o] as Node3D).global_position) + Vector3.UP * 0.2)
	for b in _bad:
		if by.has(str(b[0])) and by.has(str(b[1])) and (shown.has(str(b[0])) or shown.has(str(b[1]))):
			if not any:
				_im.surface_begin(Mesh.PRIMITIVE_LINES)
				any = true
			_im.surface_set_color(LINE_COLORS.bad)
			_im.surface_add_vertex(to_local((by[str(b[0])] as Node3D).global_position) + Vector3.UP * 0.3)
			_im.surface_add_vertex(to_local((by[str(b[1])] as Node3D).global_position) + Vector3.UP * 0.3)
	if any:
		_im.surface_end()


# ------------------------------------------------------------------ the game's file

func _path() -> String:
	return "res://data/waypoints/%s.json" % map_id


func load_from_game() -> void:
	var t0 := Time.get_ticks_msec()
	if not FileAccess.file_exists(_path()):
		push_warning("[waypoints] no %s yet: bake it first (tools/bake_botnav.sh %s)" % [_path(), map_id])
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	if typeof(d) != TYPE_DICTIONARY:
		push_error("[waypoints] %s is not a waypoint file" % _path())
		return
	for g in get_children():
		if g is Node3D and str(g.name).begins_with("Level"):
			remove_child(g)
			g.free()
	var root := _root()
	var made := []
	for r in d.get("nodes", []):
		var n = WaypointNode.new()
		n.name = str(r.id)
		var p: Array = r.p
		n.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		n.kind = str(r.get("k", "area"))
		n.priority = int(r.get("pri", 2))
		n.place_name = str(r.get("n", ""))
		n.via = bool(r.get("via", false))
		var dv: Array = r.get("d", [])
		if dv.size() == 2 and (absf(float(dv[0])) + absf(float(dv[1]))) > 0.01:
			n.faces = true
			n.rotation.y = atan2(-float(dv[0]), -float(dv[1]))
		var g2 := level_group(int(r.get("lv", 0)) + 1)
		g2.add_child(n)
		n.owner = root
		made.append(n)
	for e in d.get("edges", []):
		var a = made[int(e[0])] if not (e[0] is String) else _find(str(e[0]))
		var b = made[int(e[1])] if not (e[1] is String) else _find(str(e[1]))
		if a == null or b == null:
			continue
		var code := str(e[2]) if e.size() > 2 else "w"
		a.link_to(b, code)
		if code.substr(0, 1) != "e" and not (e.size() > 3 and bool(e[3])):
			b.link_to(a, code)
	_apply_level()
	_sig = 0
	print("[waypoints] loaded %d waypoints and %d joins from %s (%s, %d ms)" % [made.size(), (d.get("edges", []) as Array).size(), _path(),
		str(d.get("source", "")), Time.get_ticks_msec() - t0])


func _find(nm: String):
	for g in get_children():
		var n = g.get_node_or_null(nm) if g is Node3D else null
		if n != null:
			return n
	return null


func save_to_game() -> void:
	## Writes res://data/waypoints/<map>.json as "edited" (the game checks it against its physics when it loads it, or
	## at once with "Check in game"). Joins to waypoints that were deleted are dropped.
	var nodes := all_nodes()
	var index := {}
	for n in nodes:
		index[str(n.name)] = n
	var out_n := []
	for n2 in nodes:
		var p: Vector3 = (n2 as Node3D).global_position
		var r := {"id": str(n2.name), "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "lv": level_of(p) - 1,
			"k": str(n2.kind), "pri": int(n2.priority)}
		if str(n2.place_name) != "":
			r["n"] = str(n2.place_name)
		if n2.faces:
			var f: Vector3 = -(n2 as Node3D).global_basis.z
			r["d"] = [snappedf(f.x, 0.001), snappedf(f.z, 0.001)]
		if n2.via:
			r["via"] = true
		out_n.append(r)
	var edges := {}
	for a in nodes:
		for i in a.links.size():
			var o := str(a.links[i])
			if not index.has(o) or o == str(a.name):
				continue
			var code := str(a.link_kinds[i]) if i < a.link_kinds.size() else "w"
			var one := code.substr(0, 1) == "e"
			var nm := str(a.name)
			var k := (nm + ">" + o) if one else ((nm + "|" + o) if nm < o else (o + "|" + nm))
			if not edges.has(k) or str(edges[k][2]) == "w":
				edges[k] = [nm, o, code] if one or nm < o else [o, nm, code]
	var old := {}
	if FileAccess.file_exists(_path()):
		var d0 = JSON.parse_string(FileAccess.get_file_as_string(_path()))
		if typeof(d0) == TYPE_DICTIONARY:
			old = d0
	var d := {"format": 1, "map": map_id, "key": str(old.get("key", "")), "source": "edited", "verified": "", "nodes": out_n,
		"edges": edges.values(), "saved": Time.get_datetime_string_from_system()}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_path().get_base_dir()))
	var f2 := FileAccess.open(_path(), FileAccess.WRITE)
	if f2 == null:
		push_error("[waypoints] cannot write %s" % _path())
		return
	f2.store_string(JSON.stringify(d))
	f2 = null
	_bad = []
	var p2 := get_parent()
	if p2 != null and p2.has_method("save_extras"):
		p2.save_extras()
	print("[waypoints] saved %d waypoints and %d joins to %s" % [out_n.size(), edges.size(), _path()])


func _godot() -> String:
	## The console build of this editor (its output can be read), when it sits beside it.
	var exe := OS.get_executable_path()
	if exe.ends_with(".exe") and not exe.ends_with("_console.exe"):
		var con := exe.trim_suffix(".exe") + "_console.exe"
		if FileAccess.file_exists(con):
			return con
	return exe


func _run_game(extra: Array) -> int:
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--game_mode=" + game_mode,
		"--map=" + map_id, "--bots=2", "--autostart=1", "--expect_players=0", "--port=27799"]
	args.append_array(extra)
	var out := []
	print("[waypoints] running the game headless: %s" % " ".join(args))
	var code := OS.execute(_godot(), args, out, true)
	for line in str("".join(out)).split("\n"):
		if line.contains("[waypoints]") or line.contains("[wpcheck]") or line.contains("SCRIPT ERROR"):
			print(line)
	return code


func check_in_game() -> void:
	## Saves, then the game builds the map, proves every join (walk / tight / door, or dropped), stamps the file and
	## reports here. Dropped joins show red until the next save.
	save_to_game()
	var t0 := Time.get_ticks_msec()
	_run_game(["--wpcheck"])
	var rep_path := "user://waypoints/%s_check.json" % map_id
	if not FileAccess.file_exists(rep_path):
		push_error("[waypoints] the check wrote no report (%s)" % rep_path)
		return
	var r = JSON.parse_string(FileAccess.get_file_as_string(rep_path))
	if typeof(r) != TYPE_DICTIONARY:
		return
	load_from_game()
	_bad = []
	for e in r.get("dropped", []):
		_bad.append([str(e[0]), str(e[1])])
		print("[waypoints] dropped %s - %s: %s" % [str(e[0]), str(e[1]), str(e[2])])
	for nm in r.get("blocked", []):
		print("[waypoints] %s: a body does not fit there (move it off the wall or the counter)" % str(nm))
	var orph: Array = r.get("orphans", [])
	if not orph.is_empty():
		print("[waypoints] %d waypoints are not joined to the rest (bots never use them): %s" % [orph.size(), ", ".join(PackedStringArray(orph.slice(0, 30)))])
	print("[waypoints] check done in %.1f s: %d joins dropped, %d waypoints blocked, %d not joined" % [(Time.get_ticks_msec() - t0) / 1000.0,
		(r.get("dropped", []) as Array).size(), (r.get("blocked", []) as Array).size(), orph.size()])
	_sig = 0


func generate_again() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Make %s's waypoints again from the map?\nEvery waypoint and join you placed or changed is replaced." % map_id
	dlg.title = "Generate the waypoints again"
	dlg.confirmed.connect(_generate_now)
	EditorInterface.popup_dialog_centered(dlg)


func _generate_now() -> void:
	_run_game(["--botnav_bake", "--waypoints_regen"])
	load_from_game()
