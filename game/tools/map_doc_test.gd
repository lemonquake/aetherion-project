extends SceneTree
## (r26) The map editor's file format end to end, headless:
##   godot --headless --path game -s res://tools/map_doc_test.gd [-- --map=<id>]
## Without --map: a small two-storey map written to res://maps/zz_selftest (deleted after), compiled, built by
## MapScene and surveyed by JsonLayout: brushes, spawns, the stair flight and its link, walk grids on both floors,
## doors, the text round trip. With --map: the same checks on that map file, and its problems (MapDoc.check).

const MapDoc := preload("res://src/world/maps/authored/map_doc.gd")
const JsonLayout := preload("res://src/world/maps/authored/json_layout.gd")

var _fails := 0


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s %s: %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		_fails += 1


func _initialize() -> void:
	var id := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			id = a.substr(6)
	var made := id == ""
	if made:
		id = "zz_selftest"
		_write_selftest(id)
	var doc := MapDoc.load_doc(id)
	_check("load", not doc.is_empty(), "%d pieces" % (doc.get("pieces", []) as Array).size())
	var probs := MapDoc.check(doc)
	for pr in probs:
		print("  problem %s: %s" % [pr.id, pr.msg])
	_check("problems", probs.is_empty(), "%d" % probs.size())
	var again := MapDoc.normalise(JSON.parse_string(MapDoc.to_json(doc)), id)
	_check("text_round_trip", MapDoc.to_json(again) == MapDoc.to_json(doc), "%d chars (written, read back, written again: the same text)" % MapDoc.to_json(doc).length())
	var t0 := Time.get_ticks_msec()
	var L = JsonLayout.new(7, id)
	var ms := Time.get_ticks_msec() - t0
	var b: Dictionary = L.stats.get("build", {})
	_check("built", L.scene != null and int(b.get("brushes", 0)) > 0, "%d brushes, %d meshes, %d bodies, %d lights in %d ms, missing %s" % [
		int(b.get("brushes", 0)), int(b.get("meshes", 0)), int(b.get("bodies", 0)), int(b.get("lights", 0)), ms, str(b.get("missing", []))])
	_check("spawns", L.spawns[0].size() > 0 and L.spawns[1].size() > 0, "team 1: %d, team 2: %d" % [L.spawns[0].size(), L.spawns[1].size()])
	var open := []
	for g in L.nav_open:
		var n := 0
		for v in (g as PackedByteArray):
			n += v
		open.append(n)
	_check("walk_grids", open.size() == L.LEVELS and not open.has(0), "open cells per level %s" % str(open))
	var stairs := 0
	for p in doc.pieces:
		if str(p.type) == "stairs" and float(p.get("rise", 0)) >= float(doc.get("level_height", 3.2)) * 0.8:
			stairs += 1
	_check("stair_links", L.nav_links.size() == stairs, "%d flights, %d links (%d full-storey stairs)" % [L.flights.size(), L.nav_links.size(), stairs])
	_check("doors", true, "%d doors, %d props, %d bot spots" % [MapDoc.doors(doc).size(), MapDoc.props(doc).size(), L.designated.size()])
	if made:
		_check("selftest_doors", MapDoc.doors(doc).size() == 1, "%d" % MapDoc.doors(doc).size())
		var feet: Vector3 = L.flights[0].foot if not L.flights.is_empty() else Vector3.INF
		var top: Vector3 = L.flights[0].top if not L.flights.is_empty() else Vector3.INF
		_check("selftest_flight", feet.distance_to(Vector3(4, 0, 2.7)) < 1.2 and absf(top.y - 3.2) < 0.05, "foot %s top %s" % [str(feet), str(top)])
		var fl: float = L.floor_below(4.0, -6.0, 4.0)
		_check("selftest_upper_floor", absf(fl - 3.2) < 0.01, "floor under (4, -6) from 4 m: %.2f" % fl)
		var wall: Array = L.spans_at(0.0, 5.0)
		var blocked := false
		for sp in wall:
			if (sp as Vector2).y > 0.05 and (sp as Vector2).x < 2.0:
				blocked = true
		_check("selftest_doorway", not blocked and wall.size() == 2, "solid spans in the doorway %s (the ground slab and the lintel)" % str(wall))
		var stack: Array = L.spans_at(0.0, -10.0)
		var want := [Vector2(2.1, 4.0), Vector2(5.2, 6.5)]
		var found := 0
		for sp in stack:
			for wv in want:
				if (sp as Vector2).distance_to(wv) < 0.01:
					found += 1
		var ok_stack := found == 2 and stack.size() == 4   # the ground slab, the upper floor's edge, the two wall spans
		_check("selftest_stacked_openings", ok_stack, "spans through a door with a window above it %s" % str(stack))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MapDoc.path_of(id)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MapDoc.path_of(id).get_base_dir()))
	if L.scene != null:
		L.scene.free()
	print("map_doc_test: %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(0 if _fails == 0 else 1)


func _write_selftest(id: String) -> void:
	var doc := {"id": id, "name": "Self Test", "code": "ZZ", "levels": 2, "level_height": 3.2, "bounds": [-12, -12, 12, 12],
		"pieces": [
			{"id": "ground", "type": "floor", "at": [0, 0, 0], "size": [24, 24], "mat": "freight/concrete_rough"},
			{"id": "upper", "type": "floor", "at": [4, 3.2, -6], "size": [8, 8], "mat": "freight/planks"},
			{"id": "w_south", "type": "wall", "from": [-10, 5], "to": [10, 5], "y": 0, "h": 3, "t": 0.2,
				"openings": [{"at": 10, "w": 1, "h": 2.1, "sill": 0, "door": "plywood"}, {"at": 4, "w": 1.2, "h": 1.0, "sill": 1.0}]},
			{"id": "w_north", "type": "wall", "from": [-10, -10], "to": [10, -10], "y": 0, "h": 6.5,
				"openings": [{"at": 10, "w": 1, "h": 2.1, "sill": 0}, {"at": 10, "w": 1.6, "h": 1.2, "sill": 4.0}]},
			{"id": "stair", "type": "stairs", "at": [4, 0, 2.7], "yaw": 0, "w": 1.4, "rise": 3.2, "rail": true},
			{"id": "crate", "type": "box", "at": [-5, 0, -2], "size": [1.2, 1.2, 1.2], "yaw": 30, "mat": "freight/pallet"},
			{"id": "pillar", "type": "column", "at": [-2, 0, -6], "r": 0.3, "h": 3.2},
			{"id": "lamp", "type": "light", "at": [0, 2.8, 0], "kind": "bulb", "fault": "flicker"},
			{"id": "s1", "type": "spawn", "at": [-8, 0, 0], "team": 1, "yaw": 90},
			{"id": "s2", "type": "spawn", "at": [8, 0, 0], "team": 2, "yaw": 270},
			{"id": "lm", "type": "landmark", "at": [0, 0, 0], "name": "Middle"},
			{"id": "sp", "type": "spot", "at": [4, 3.2, -8], "kind": "snipe", "yaw": 180, "name": "Upper deck"},
		]}
	MapDoc.save_doc(MapDoc.normalise(doc, id), id)
