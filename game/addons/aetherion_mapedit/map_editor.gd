@tool
extends Node3D
## (r26) A map-editor map open in Godot (res://editor/maps/<id>.tscn, made by the Maps dock). The map's file,
## res://maps/<id>/map.json, is the source: this node shows every piece as the game builds it, one node per piece
## under its layer, and writes them back to the file with Save map (or Ctrl+S, which saves the map, not the pieces
## into the scene). When the file changes on disk (Claude editing it, a git pull) the map reloads by itself, unless
## there are unsaved edits here.
##   Notes      QA notes pinned on the map (res://maps/<id>/qa.json)
##   Waypoints  the bots' waypoint graph (load, edit, save, check: see the aetherion-waypoints skill)
##   Terrain3D  (r27) the uneven ground, when the map has one: sculpt, paint and plant it with Terrain3D's own tools
##              (select the node: its toolbar and the Terrain3D asset dock appear). Save map also writes its regions
##              and bakes the heights the game collides with (map_terrain.gd).
## The game never loads this scene.

const MapDoc := preload("res://src/world/maps/authored/map_doc.gd")
const MapPiece := preload("res://addons/aetherion_mapedit/map_piece.gd")
const QaNote := preload("res://addons/aetherion_mapedit/qa_note.gd")
const WaypointSet := preload("res://addons/aetherion_waypoints/waypoint_set.gd")
const MapTerrain := preload("res://src/world/maps/authored/map_terrain.gd")

@export var map_id := "":
	set(v):
		map_id = v
		if is_inside_tree() and Engine.is_editor_hint():
			load_map.call_deferred()
@export_group("Map")
@export var map_name := ""
## Two capital letters: the bots' waypoint ids start with them.
@export var code := ""
@export_range(1, 6) var levels := 1
## Metres from one level's floor to the next: the bots survey a walk grid at each.
@export var level_height := 3.2
## The play area (x, z, width, depth).
@export var bounds := Rect2(-40, -40, 80, 80)
@export var night_only := false
@export_group("View")
## Show the map up to this level (0: all of it); pieces above are hidden.
@export_range(0, 6) var show_level := 0:
	set(v):
		show_level = v
		_apply_level()
@export var show_labels := true:
	set(v):
		show_labels = v
		for p in pieces():
			p._update_label()
## Light the editor's view like the game's night (the lamps carry the scene) instead of daylight.
@export var night_preview := false:
	set(v):
		night_preview = v
		_preview_env()
@export_range(0, 23) var play_bots := 7
@export_group("")
@export_tool_button("Save map", "Save") var _b_save = save_map
@export_tool_button("Reload from file", "Reload") var _b_reload = load_map
@export_tool_button("Check map", "Search") var _b_check = check_map
@export_tool_button("Play it (host with bots)", "Play") var _b_play = play_map
@export_tool_button("Bake the bots' waypoints", "Node") var _b_bake = bake_bots
@export_tool_button("Draw the plan picture", "Image") var _b_plan = draw_plan

var doc := {}
var dirty := false
var notes_dirty := false
var _mtime := 0
var _qa_mtime := 0
var _t := 0.0
var _warned := false
var _loading := false
var _env: Node3D = null
var _outline: MeshInstance3D = null
var _saved_owners := []
var _night_set := false


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	set_process(true)
	if map_id != "":
		load_map.call_deferred()


func mark_dirty() -> void:
	if not _loading:
		dirty = true


func mark_notes_dirty() -> void:
	if not _loading:
		notes_dirty = true


func _scene_root() -> Node:
	if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
		return get_tree().edited_scene_root
	return self


func pieces() -> Array:
	var out := []
	var layers := get_node_or_null("Layers")
	if layers == null:
		return out
	for g in layers.get_children():
		for c in g.get_children():
			if c.get_script() == MapPiece:
				out.append(c)
	return out


func notes() -> Array:
	var out := []
	var nn := get_node_or_null("Notes")
	if nn != null:
		for c in nn.get_children():
			if c.get_script() == QaNote:
				out.append(c)
	return out


func layer_node(layer: String) -> Node3D:
	var layers := get_node_or_null("Layers") as Node3D
	if layers == null:
		layers = Node3D.new()
		layers.name = "Layers"
		add_child(layers)
		layers.owner = _scene_root()
	var nm := layer.validate_node_name()
	var g := layers.get_node_or_null(nm) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = nm
		g.set_meta("layer", layer)
		layers.add_child(g)
		g.owner = _scene_root()
	return g


# ------------------------------------------------------------------ load and save

func load_map() -> void:
	if map_id == "" or not Engine.is_editor_hint():
		return
	if not MapDoc.exists(map_id):
		push_warning("[map editor] no %s (make it from the Maps dock)" % MapDoc.path_of(map_id))
		return
	_loading = true
	var t0 := Time.get_ticks_msec()
	doc = MapDoc.load_doc(map_id)
	map_name = str(doc.get("name", map_id))
	code = str(doc.get("code", ""))
	levels = int(doc.get("levels", 1))
	level_height = float(doc.get("level_height", 3.2))
	var b: Array = doc.get("bounds", [-40, -40, 40, 40])
	bounds = Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	night_only = bool(doc.get("night_only", false))
	if night_only and not _night_set:
		night_preview = true   # (r27) a night-only map opens at night; untick Night Preview to edit it in daylight
		_night_set = true
	for nm in ["Layers", "Notes"]:
		var old := get_node_or_null(nm)
		if old != null:
			remove_child(old)
			old.free()
	var root := _scene_root()
	for p in doc.get("pieces", []):
		var n := MapPiece.new()
		n.data = p
		layer_node(str(p.get("layer", "Geometry"))).add_child(n)
		n.owner = root
	_load_notes()
	var wp := get_node_or_null("Waypoints")
	if wp == null:
		wp = WaypointSet.new()
		wp.name = "Waypoints"
		wp.auto_load = false
		add_child(wp)
		wp.owner = root
	wp.map_id = map_id
	wp.floor_height = level_height
	wp.levels = levels
	_preview_env()
	_ensure_terrain()
	_draw_outline()
	_apply_level()
	_mtime = FileAccess.get_modified_time(MapDoc.path_of(map_id))
	_qa_mtime = FileAccess.get_modified_time(MapDoc.qa_path_of(map_id)) if FileAccess.file_exists(MapDoc.qa_path_of(map_id)) else 0
	dirty = false
	notes_dirty = false
	_warned = false
	_loading = false
	print("[map editor] %s: %d pieces, %d notes (%d ms)" % [map_id, (doc.get("pieces", []) as Array).size(), notes().size(), Time.get_ticks_msec() - t0])


func _load_notes() -> void:
	var nn := Node3D.new()
	nn.name = "Notes"
	add_child(nn)
	nn.owner = _scene_root()
	var qp := MapDoc.qa_path_of(map_id)
	if not FileAccess.file_exists(qp):
		return
	var js = JSON.parse_string(FileAccess.get_file_as_string(qp))
	if not (js is Dictionary):
		return
	for d in js.get("notes", []):
		var q := QaNote.new()
		nn.add_child(q)
		q.owner = _scene_root()
		q.from_dict(d)


func collect() -> Dictionary:
	## The map as it stands in the editor.
	var out := doc.duplicate(true)
	out.id = map_id
	out.name = map_name
	if code != "":
		out.code = code
	out.levels = levels
	out.level_height = level_height
	out.bounds = [bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y]
	out.night_only = night_only
	var ps := []
	for p in pieces():
		ps.append(p.to_piece())
	out.pieces = ps
	return out


func save_map() -> void:
	if map_id == "":
		return
	doc = collect()
	var err := MapDoc.save_doc(doc, map_id)
	if err != OK:
		push_error("[map editor] could not write %s: %s" % [MapDoc.path_of(map_id), error_string(err)])
		return
	_mtime = FileAccess.get_modified_time(MapDoc.path_of(map_id))
	dirty = false
	_save_terrain()
	_save_notes()
	print("[map editor] saved %s: %d pieces, %d notes" % [MapDoc.path_of(map_id), (doc.pieces as Array).size(), notes().size()])
	for pr in MapDoc.check(doc):
		push_warning("[map editor] %s: %s" % [pr.id if pr.id != "" else map_id, pr.msg])


func _ensure_terrain() -> void:
	## (r27) The map's Terrain3D ground under the pieces, kept in this scene (its data lives in the map's folder).
	var s := MapTerrain.spec_of(doc)
	if s.is_empty() or OS.get_environment("AETHERION_MAPEDIT_NO_TERRAIN") == "1":
		return
	var t := get_node_or_null("Terrain3D")
	if t == null:
		t = MapTerrain.make_node(s, false, false)
		if t == null:
			push_warning("[map editor] %s has Terrain3D ground but the Terrain3D extension is not loaded" % map_id)
			return
		add_child(t)
		t.owner = _scene_root()


func _save_terrain() -> void:
	## (r27) Writes the Terrain3D regions and bakes the heights the game collides with and the bots survey.
	var s := MapTerrain.spec_of(doc)
	var t := get_node_or_null("Terrain3D")
	if s.is_empty() or t == null or t.get("data") == null:
		return
	t.get("data").save_directory(str(s.dir))
	var img := MapTerrain.bake(t, s)
	var err := MapTerrain.save_baked(img, s, map_id)
	print("[map editor] baked the ground of %s: %d x %d heights (%s)" % [map_id, img.get_width(), img.get_height(), error_string(err)])


func _save_notes() -> void:
	var arr := []
	for q in notes():
		arr.append(q.to_dict())
	var qp := MapDoc.qa_path_of(map_id)
	if arr.is_empty() and not FileAccess.file_exists(qp):
		return
	var f := FileAccess.open(qp, FileAccess.WRITE)
	if f == null:
		push_error("[map editor] could not write %s" % qp)
		return
	var lines := ["{", " \"map\": %s," % JSON.stringify(map_id), " \"notes\": ["]
	for i in arr.size():
		lines.append("  %s%s" % [JSON.stringify(arr[i]), "," if i < arr.size() - 1 else ""])
	lines.append(" ]")
	lines.append("}")
	f.store_string("\n".join(lines) + "\n")
	f.close()
	_qa_mtime = FileAccess.get_modified_time(qp)
	notes_dirty = false


func _process(dt: float) -> void:
	if not Engine.is_editor_hint() or map_id == "" or _loading:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.5
	var p := MapDoc.path_of(map_id)
	if not FileAccess.file_exists(p):
		return
	var mt := FileAccess.get_modified_time(p)
	var qp := MapDoc.qa_path_of(map_id)
	var qt := FileAccess.get_modified_time(qp) if FileAccess.file_exists(qp) else 0
	if mt != _mtime or qt != _qa_mtime:
		if dirty or notes_dirty:
			if not _warned:
				push_warning("[map editor] %s changed on disk while you have unsaved edits here: Save map keeps yours, Reload from file takes the file's" % p)
				_warned = true
			return
		print("[map editor] %s changed on disk: reloading" % (p if mt != _mtime else qp))
		load_map()


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE and map_id != "" and not _loading:
		if dirty or notes_dirty:
			save_map()
		# the pieces and notes live in the map's files, not in this scene: keep them out of the .tscn
		_saved_owners.clear()
		for nm in ["Layers", "Notes"]:
			var n := get_node_or_null(nm)
			if n != null:
				_strip(n)
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		for e in _saved_owners:
			if is_instance_valid(e[0]):
				(e[0] as Node).owner = e[1]
		_saved_owners.clear()


func _strip(n: Node) -> void:
	if n.owner != null:
		_saved_owners.append([n, n.owner])
		n.owner = null
	for c in n.get_children():
		_strip(c)


# ------------------------------------------------------------------ the view

func _apply_level() -> void:
	if not is_inside_tree():
		return
	var top := INF if show_level <= 0 else show_level * level_height - 0.3
	for p in pieces():
		var y: float = (p as Node3D).position.y
		p.visible = y < top
	var wp := get_node_or_null("Waypoints")
	if wp != null and wp.get("show_level") != show_level:
		wp.set("show_level", show_level)


func _preview_env() -> void:
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	if _env != null:
		_env.free()
	_env = Node3D.new()
	add_child(_env, false, Node.INTERNAL_MODE_FRONT)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	if night_preview:
		sm.sky_top_color = Color(0.02, 0.025, 0.045)
		sm.sky_horizon_color = Color(0.09, 0.06, 0.05)
		sm.ground_horizon_color = Color(0.05, 0.04, 0.04)
		sm.ground_bottom_color = Color(0.01, 0.01, 0.01)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.11, 0.12, 0.17)
		env.ambient_light_energy = 0.25
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 0.8
	sky.sky_material = sm
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_env.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.08 if night_preview else 1.1
	sun.light_color = Color(0.6, 0.7, 1.0) if night_preview else Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	_env.add_child(sun)


func _draw_outline() -> void:
	## The play area's edge and a line at each level's height, so it is plain where the map ends.
	if _outline == null:
		_outline = MeshInstance3D.new()
		_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		_outline.material_override = m
		add_child(_outline, false, Node.INTERNAL_MODE_FRONT)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for lv in levels:
		var y := lv * level_height + 0.02
		var c := Color(1.0, 0.85, 0.2) if lv == 0 else Color(0.4, 0.8, 1.0, 0.6)
		var r := bounds
		var pts := [Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y)]
		for i in 4:
			im.surface_set_color(c)
			im.surface_add_vertex(pts[i])
			im.surface_set_color(c)
			im.surface_add_vertex(pts[(i + 1) % 4])
	im.surface_end()
	_outline.mesh = im


func pick(o: Vector3, d: Vector3, things := true) -> Dictionary:
	## The visible piece a world ray meets first: {node, t, point}, or {}.
	var best := {}
	for p in pieces():
		if not p.visible:
			continue
		if not things and not (p.piece_type() in MapDoc.GEOMETRY):
			continue
		var t: float = p.ray_hit(o, d)
		if t >= 0.0 and (best.is_empty() or t < float(best.t)):
			best = {"node": p, "t": t, "point": o + d * t}
	return best


func new_piece_id(t: String) -> String:
	var base := {"box": "B", "floor": "F", "wall": "W", "poly": "P", "column": "C", "stairs": "S", "ramp": "R",
		"light": "L", "spawn": "T", "landmark": "M", "spot": "H", "prop": "O"}.get(t, "X") as String
	var used := {}
	for p in pieces():
		used[str(p.name)] = true
	var k := 1
	while used.has("%s%d" % [base, k]):
		k += 1
	return "%s%d" % [base, k]


func new_note_id() -> String:
	var used := {}
	for q in notes():
		used[str(q.name)] = true
	var k := 1
	while used.has("N%d" % k):
		k += 1
	return "N%d" % k


# ------------------------------------------------------------------ the buttons

func check_map() -> void:
	var d := collect()
	var probs := MapDoc.check(d)
	for pr in probs:
		push_warning("[map editor] %s: %s" % [pr.id if pr.id != "" else map_id, pr.msg])
	print("[map editor] %s: %d pieces, %d problems" % [map_id, (d.pieces as Array).size(), probs.size()])


func _godot(console: bool) -> String:
	var exe := OS.get_executable_path()
	if console and exe.ends_with(".exe") and not exe.ends_with("_console.exe"):
		var con := exe.trim_suffix(".exe") + "_console.exe"
		if FileAccess.file_exists(con):
			return con
	if not console and exe.ends_with("_console.exe"):
		var gui := exe.trim_suffix("_console.exe") + ".exe"
		if FileAccess.file_exists(gui):
			return gui
	return exe


func play_map() -> void:
	## Saves, then starts the game on this map as a host with bots, in its own window.
	if dirty or notes_dirty:
		save_map()
	var args := ["--path", ProjectSettings.globalize_path("res://"), "--", "--host", "--game_mode=deathmatch",
		"--map=" + map_id, "--bots=%d" % play_bots, "--autostart=1"]
	var pid := OS.create_process(_godot(false), args)
	print("[map editor] playing %s (process %d): %s" % [map_id, pid, " ".join(args)])


func bake_bots() -> void:
	## Saves, then has the game make the bots' walk check and waypoint graph for this map (a headless run, about a
	## minute; the editor waits). Then run the waypoints' "Check in game" or the strict check (aetherion-waypoints).
	if dirty or notes_dirty:
		save_map()
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--game_mode=deathmatch",
		"--map=" + map_id, "--bots=2", "--autostart=1", "--expect_players=0", "--botnav_bake", "--port=27788"]
	print("[map editor] baking the bots' navigation for %s (the editor waits)..." % map_id)
	var out := []
	var code_r := OS.execute(_godot(true), args, out, true)
	for line in str("".join(out)).split("\n"):
		if line.contains("[botnav]") or line.contains("[waypoints]") or line.contains("SCRIPT ERROR") or line.contains("[map]"):
			print(line)
	print("[map editor] bake finished (exit %d): res://data/waypoints/%s.json" % [code_r, map_id])


func draw_plan() -> void:
	## Saves, then draws the plan (tools/map_plan.py): work/maps/<id>/plan.png, every piece with its id, and the notes.
	if dirty or notes_dirty:
		save_map()
	var script := ProjectSettings.globalize_path("res://").path_join("../tools/map_plan.py").simplify_path()
	var out := []
	var code_r := OS.execute("python", ["-I", script, map_id], out, true)
	print("[map editor] %s (exit %d)" % ["".join(out).strip_edges(), code_r])
