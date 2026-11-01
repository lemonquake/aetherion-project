extends "res://src/world/maps/authored/authored_layout.gd"
## (r26) A map made in the map editor (res://maps/<id>/map.json, see map_doc.gd). Its pieces compile into brushes and
## entities, MapScene builds the scene from them (meshes, collision, lights, spawns, landmarks, stair flights), and
## AuthoredLayout surveys it for the bots like Freight Delight. Doors, props and designated bot spots come straight
## from the file (MapBuilder places the doors and props).

const MapDoc := preload("res://src/world/maps/authored/map_doc.gd")
const MapScene := preload("res://addons/aetherion_map/map_scene.gd")

var doc := {}
var doc_hash := 0


func _init(seed_value: int, map_id: String) -> void:
	rng.seed = seed_value
	MAP_ID = map_id
	var t0 := Time.get_ticks_msec()
	doc = MapDoc.load_doc(map_id)
	if doc.is_empty():
		push_error("[map] %s: no %s" % [map_id, MapDoc.path_of(map_id)])
		return
	doc_hash = hash(FileAccess.get_file_as_string(MapDoc.path_of(map_id)))
	FH = float(doc.get("level_height", 3.2))
	LEVELS = maxi(1, int(doc.get("levels", 1)))
	var b: Array = doc.get("bounds", [-40, -40, 40, 40])
	bounds = Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	edge = maxf(absf(bounds.position.x), maxf(absf(bounds.end.x), maxf(absf(bounds.position.y), absf(bounds.end.y))))
	PLAY_HALF = edge
	HALF = edge + 8.0
	night_only = bool(doc.get("night_only", false))
	var ng = doc.get("night_grade", null)
	if ng is Dictionary:
		for k in ng:
			var v = ng[k]
			night_grade[k] = Color.from_string(v, Color.BLACK) if v is String and str(v).begins_with("#") else v
	var dc = doc.get("dm_centre", null)
	dm_centre = MapDoc.v2(dc, bounds.get_center())
	designated = MapDoc.spots(doc)
	var ms := MapScene.new()
	ms.configure({})
	var sc: Node3D = ms.build_entities(MapDoc.entities(doc), map_id)
	stats.build = ms.stats
	stats.compile_ms = Time.get_ticks_msec() - t0
	if not (ms.stats.missing as Array).is_empty():
		push_warning("[map] %s: missing textures %s" % [map_id, str(ms.stats.missing)])
	load_scene(sc)
