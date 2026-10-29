extends Node3D
## Building kit preview and checks.
##   --fp            build Kalinaw and print its fingerprint plus a deep hash of every mesh, collider and registry
##                   (proves a refactor of shanty/map_builder left the map byte-identical).
##   (default)       build single buildings from house_plan.gd on a flat test ground and capture views.

const MapBuilder := preload("res://src/world/map_builder.gd")

var is_server := true
var match_info := {}
var characters := {}
var map = null
var args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true
	get_tree().create_timer(float(args.get("timeout", 600))).timeout.connect(func(): print("[bp] watchdog timeout"); get_tree().quit(2))
	if args.has("fp"):
		await _kalinaw_fp()
		get_tree().quit()
		return
	get_tree().quit()


# ------------------------------------------------------------------ Kalinaw fingerprint

func _kalinaw_fp() -> void:
	var t0 := Time.get_ticks_msec()
	map = MapBuilder.new()
	map.build(self, int(args.get("seed", 1729)), 1)
	print("[bp] kalinaw built in %d ms" % (Time.get_ticks_msec() - t0))
	print("[bp] fingerprint: ", map.fingerprint)
	var parts := {}
	var hm := 0
	var nm := 0
	var nv := 0
	var hc := 0
	var nc := 0
	for ch in map.root.get_children():
		for n in ch.get_children():
			if n is MeshInstance3D and (n as MeshInstance3D).mesh is ArrayMesh:
				var mesh: ArrayMesh = n.mesh
				for s in mesh.get_surface_count():
					var arr := mesh.surface_get_arrays(s)
					var mat = mesh.surface_get_material(s)
					hm = hash([hm, str(ch.name), hash(arr[Mesh.ARRAY_VERTEX]), hash(arr[Mesh.ARRAY_COLOR]), hash(arr[Mesh.ARRAY_TEX_UV]),
						hash(arr[Mesh.ARRAY_TEX_UV2]), hash(arr[Mesh.ARRAY_INDEX]), (mat.resource_name if mat else ""), n.layers, n.visibility_range_end])
					nm += 1
					nv += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			elif n is StaticBody3D:
				for cs in n.get_children():
					if cs is CollisionShape3D and cs.shape is ConcavePolygonShape3D:
						hc = hash([hc, str(ch.name), str(n.get_meta("mat", "")), n.collision_layer, hash((cs.shape as ConcavePolygonShape3D).get_faces())])
						nc += 1
			elif n is OccluderInstance3D:
				hc = hash([hc, hash((n.occluder as ArrayOccluder3D).vertices)])
	parts.meshes = "%d v%d #%08x" % [nm, nv, hm & 0xFFFFFFFF]
	parts.colliders = "%d #%08x" % [nc, hc & 0xFFFFFFFF]
	var d = map.dyn
	parts.doors = _hl(d.doors)
	parts.windows = _hl(d.windows)
	parts.curtains = _hl(d.curtains)
	parts.containers = _hl(d.containers)
	parts.loot_spots = _hl(d.loot_spots)
	parts.loot_boxes = _hl(d.loot_boxes)
	parts.props = _hl(d.props)
	parts.static_props = _hl(d.static_props)
	parts.doorways = _hl(d.doorways)
	parts.clearances = _hl(d.clearances)
	parts.lights = _hl(d.lights)
	parts.zones = _hl(map.acoustics.zones)
	parts.portals = _hl(map.acoustics.portals)
	parts.rooms = _hl(map.rooms)
	parts.stairs = _hl(map.stairs)
	parts.ladders = _hl(map.ladders)
	parts.buildings = _hl(map.buildings)
	parts.items = "%d" % d.items.size()
	parts.rng = "sink %d dresser %d dyn %d" % [map.sink.rng.state & 0xFFFFFF, map.dresser.rng.state & 0xFFFFFF, d.rng.state & 0xFFFFFF]
	parts.sink_stats = JSON.stringify(map.sink.stats)
	var total := hash(JSON.stringify(parts))
	for k in parts:
		print("[bp] fp %-12s %s" % [k, parts[k]])
	print("[bp] DEEP %s | %08x" % [map.fingerprint, total & 0xFFFFFFFF])


func _hl(a) -> String:
	var h := 0
	for e in a:
		h = hash([h, _hv(e)])
	return "%d #%08x" % [a.size(), h & 0xFFFFFFFF]


func _hv(v) -> int:
	match typeof(v):
		TYPE_OBJECT, TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL:
			return 0
		TYPE_DICTIONARY:
			var h := 0
			for k in v:
				h = hash([h, str(k), _hv(v[k])])
			return h
		TYPE_ARRAY:
			var h2 := 0
			for e in v:
				h2 = hash([h2, _hv(e)])
			return h2
		TYPE_FLOAT:
			return hash(snappedf(v, 0.0001))
	return hash(v)
