@tool
extends RefCounted
## (r26) The map editor checked inside the real Godot editor, with pictures. Runs when the editor starts with
## AETHERION_MAPEDIT_TEST=<folder> (and AETHERION_MAPEDIT_MAP=<map id>, default hidden_forest):
##   godot --path game -e   (with those two set in the environment)
## Opens the map's editor scene, waits for every piece, then checks: one node per piece; the editor writes the file
## back unchanged; moving, turning and resizing a piece write its position, bearing and size; a wall's length; a click
## ray picks the piece under it; a QA note is saved to qa.json and read back. It frames the map, saves the 3D view and
## the whole editor window as pictures, writes report.json in the folder, and quits. The map file is left as it was.
## (r27) The pictures follow the map: the overview is framed on its bounds; AETHERION_MAPEDIT_LOOK=x,y,z,dist picks
## the closer look (x,y,z,dist[,yaw,pitch] in degrees), AETHERION_MAPEDIT_SELECT the piece shown selected, AETHERION_MAPEDIT_NIGHT=0|1 the preview light.

const MapDoc := preload("res://src/world/maps/authored/map_doc.gd")

var plugin
var out := ""
var checks := []


func _check(name: String, ok: bool, detail: String) -> void:
	checks.append({"name": name, "ok": ok, "detail": detail})
	print("[mapedit test] %s %s: %s" % ["PASS" if ok else "FAIL", name, detail])


func run(p, out_dir: String, id: String) -> void:
	plugin = p
	out = out_dir
	DirAccess.make_dir_recursive_absolute(out)
	var tree: SceneTree = EditorInterface.get_base_control().get_tree()
	await tree.create_timer(2.0).timeout
	var file_before := FileAccess.get_file_as_string(MapDoc.path_of(id))
	var qa_existed := FileAccess.file_exists(MapDoc.qa_path_of(id))
	var qa_before := FileAccess.get_file_as_string(MapDoc.qa_path_of(id)) if qa_existed else ""
	plugin._open(id)
	var ed = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await tree.process_frame
		ed = plugin._editor()
		if ed != null and ed.pieces().size() > 0:
			break
	if ed == null:
		_check("open", false, "the map's editor scene did not open")
		_finish(tree)
		return
	for i in 30:
		await tree.process_frame
	var doc := MapDoc.load_doc(id)
	var n_doc: int = (doc.pieces as Array).size()
	_check("open", ed.pieces().size() == n_doc, "%d piece nodes for %d pieces in %s (%d ms)" % [ed.pieces().size(), n_doc, MapDoc.path_of(id), Time.get_ticks_msec() - t0])
	var shown := 0
	var hidden := 0   # pieces all in tool textures (clip): invisible on purpose
	for pc in ed.pieces():
		if str(pc.data.get("mat", "")).ends_with("/clip"):
			hidden += 1
		elif pc._preview != null and pc._preview.get_child_count() > 0:
			shown += 1
	_check("previews", shown == n_doc - hidden, "%d of %d pieces drawn (%d invisible clip pieces)" % [shown, n_doc, hidden])
	var mine: Array = MapDoc.normalise(ed.collect(), id).pieces
	# the editor writes pieces grouped by layer, so compare them by id
	var by_id := {}
	for q in doc.pieces:
		by_id[str(q.id)] = MapDoc.to_json({"pieces": [q]})
	var diffs := []
	for q in mine:
		var a := MapDoc.to_json({"pieces": [q]})
		var b := str(by_id.get(str(q.id), ""))
		if a != b and diffs.size() < 3:
			diffs.append("%s
   file:   %s
   editor: %s" % [str(q.id), b.split("
")[2] if b != "" else "(none)", a.split("
")[2]])
	_check("unchanged_on_save", diffs.is_empty() and mine.size() == n_doc, "every piece the editor writes is the piece it read (%d)%s" % [mine.size(), "" if diffs.is_empty() else ": " + "
".join(diffs)])
	# move, turn, resize
	var box = _first(ed, "box")
	if box != null:
		var at0: Array = box.data.at.duplicate()
		box.position += Vector3(1.0, 0.0, -0.5)
		box.rotation.y = deg_to_rad(-30.0)
		var pd: Dictionary = box.to_piece()
		_check("move_turn", absf(float(pd.at[0]) - float(at0[0]) - 1.0) < 0.001 and absf(float(pd.at[2]) - float(at0[2]) + 0.5) < 0.001 and absf(float(pd.yaw) - 30.0) < 0.2,
			"%s moved to %s, bearing %s" % [box.name, str(pd.at), str(pd.yaw)])
		var s0 := MapDoc.v3(box.data.size)
		box.scale = Vector3(2.0, 1.0, 1.0)
		await tree.process_frame
		var s1 := MapDoc.v3(box.data.size)
		_check("scale_resizes", absf(s1.x - s0.x * 2.0) < 0.02 and box.scale.is_equal_approx(Vector3.ONE), "%s size %s -> %s, scale back to %s" % [box.name, str(s0), str(s1), str(box.scale)])
		box.data = box.data.duplicate(true)
		var back: Dictionary = MapDoc.normalise({"pieces": [_find_piece(doc, str(box.name))]}).pieces[0]
		box.data = back
	var w = _first(ed, "wall")
	if w != null:
		var mid0: Vector3 = w.position
		var len0 := MapDoc.wall_len(w.data)
		w.set("p_len", len0 + 2.0)
		var a := MapDoc.v2(w.data.from)
		var b := MapDoc.v2(w.data.to)
		_check("wall_length", absf(a.distance_to(b) - len0 - 2.0) < 0.01 and Vector2(mid0.x, mid0.z).distance_to((a + b) * 0.5) < 0.01,
			"%s %.2f m -> %.2f m about the same middle" % [w.name, len0, a.distance_to(b)])
		w.set("p_len", len0)
	# picking: straight down onto the road
	# (r27) onto the map's first floor piece
	var target := "road"
	var at := Vector3(0, 30, -28)
	for fp in doc.pieces:
		if str(fp.get("type", "")) == "floor" and not str(fp.get("mat", "")).ends_with("/clip"):
			target = str(fp.id)
			var fa := MapDoc.v3(fp.get("at"))
			at = Vector3(fa.x, fa.y + 30.0, fa.z)
			break
	var hit: Dictionary = ed.pick(at, Vector3.DOWN, false)
	_check("pick", not hit.is_empty() and str(hit.node.name) == target, "a ray down at (%.1f, %.1f) hits %s (%s expected)" % [at.x, at.z, str(hit.node.name) if not hit.is_empty() else "nothing", target])
	# a QA note, saved and read back
	var n0: int = ed.notes().size()
	plugin._add_note(ed, Vector3(0, 0.1, 2), "court")
	var note = ed.notes().back() if ed.notes().size() > n0 else null
	if note != null:
		note.text = "Self-test note: the line paint should be brighter."
		ed.save_map()
		var js = JSON.parse_string(FileAccess.get_file_as_string(MapDoc.qa_path_of(id)))
		var found := false
		for d in (js.get("notes", []) if js is Dictionary else []):
			if str(d.get("text", "")).begins_with("Self-test note"):
				found = true
		_check("qa_note", found, "%s pinned on %s, saved to %s" % [note.name, note.piece, MapDoc.qa_path_of(id)])
	else:
		_check("qa_note", false, "no note was added")
	# the pictures: the whole map framed, then a closer look
	var night := OS.get_environment("AETHERION_MAPEDIT_NIGHT")
	if night != "":
		ed.night_preview = night == "1"
	var bb: Array = doc.get("bounds", [-40, -40, 40, 40])
	var half := maxf(absf(float(bb[2]) - float(bb[0])), absf(float(bb[3]) - float(bb[1]))) * 0.5
	var mid := Vector3((float(bb[0]) + float(bb[2])) * 0.5, 0, (float(bb[1]) + float(bb[3])) * 0.5)
	var ov := OS.get_environment("AETHERION_MAPEDIT_OVERVIEW").split(",")   # dist,yaw,pitch
	if ov.size() == 3:
		await _frame(tree, float(ov[0]), deg_to_rad(float(ov[2])), deg_to_rad(float(ov[1])), mid)
	else:
		await _frame(tree, maxf(70.0, half * 1.75), deg_to_rad(-40.0), deg_to_rad(-30.0), mid)
	_shot("editor_view_map.png", true)
	_shot("editor_window_map.png", false)
	var look := OS.get_environment("AETHERION_MAPEDIT_LOOK").split(",")
	if look.size() >= 4:
		var lyaw := float(look[4]) if look.size() > 4 else 160.0
		var lpitch := float(look[5]) if look.size() > 5 else -22.0
		await _frame(tree, float(look[3]), deg_to_rad(lpitch), deg_to_rad(lyaw), Vector3(float(look[0]), float(look[1]), float(look[2])))
	else:
		await _frame(tree, 22.0, deg_to_rad(-18.0), deg_to_rad(160.0), Vector3(-3, 2, -12))
	_shot("editor_view_hall.png", true)
	EditorInterface.get_selection().clear()
	var sel := OS.get_environment("AETHERION_MAPEDIT_SELECT")
	var sel_node = _named(ed, sel if sel != "" else "hall_s")
	if sel_node != null:
		EditorInterface.get_selection().add_node(sel_node)
	await tree.process_frame
	await tree.process_frame
	_shot("editor_window_selected.png", false)
	# leave the map as it was
	var f := FileAccess.open(MapDoc.path_of(id), FileAccess.WRITE)
	f.store_string(file_before)
	f.close()
	if qa_existed:
		var q := FileAccess.open(MapDoc.qa_path_of(id), FileAccess.WRITE)
		q.store_string(qa_before)
		q.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MapDoc.qa_path_of(id)))
	_finish(tree)


func _first(ed, t: String):
	for pc in ed.pieces():
		if pc.piece_type() == t and pc.visible:
			return pc
	return null


func _named(ed, nm: String):
	for pc in ed.pieces():
		if str(pc.name) == nm:
			return pc
	return ed


func _find_piece(doc: Dictionary, pid: String) -> Dictionary:
	for p in doc.pieces:
		if str(p.id) == pid:
			return p
	return {}


func _frame(_tree: SceneTree, dist: float, pitch: float, yaw: float, target: Vector3) -> void:
	## Puts the editor's 3D view where the picture needs it. The view's camera is driven by its own cursor, so this
	## sets the camera after the editor each frame for a moment, then leaves it.
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var xf := Transform3D(b, target + b.z * dist)
	for i in 30:
		await RenderingServer.frame_pre_draw
		cam.global_transform = xf
		RenderingServer.camera_set_transform(cam.get_camera_rid(), xf)
	await RenderingServer.frame_post_draw


func _shot(name: String, view_only: bool) -> void:
	var img: Image = EditorInterface.get_editor_viewport_3d(0).get_texture().get_image() if view_only else EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	if img == null:
		_check("shot_" + name, false, "no picture")
		return
	img.save_png(out.path_join(name))
	print("[mapedit test] picture %s (%dx%d)" % [out.path_join(name), img.get_width(), img.get_height()])


func _finish(tree: SceneTree) -> void:
	var ok := true
	for c in checks:
		ok = ok and bool(c.ok)
	var f := FileAccess.open(out.path_join("report.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"ok": ok, "checks": checks}, "  "))
		f.close()
	print("[mapedit test] %s (%d checks)" % ["PASS" if ok else "FAIL", checks.size()])
	tree.quit(0 if ok else 1)
