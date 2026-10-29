extends Node3D
## Independent map census and collision checks. Headless results do not certify rendered frame rate.
## Godot --headless --path game res://tests/deathmatch_design.tscn -- --out=<absolute.json> [--repeat]

const MapBuilder := preload("res://src/world/map_builder.gd")
const Layout := preload("res://src/world/maps/lawless_sub/sub_layout.gd")

class TestWorld:
	extends Node3D
	var is_server := false
	var match_info := {}
	var characters := {}
	var effects = null
	var map = null

var failures: Array = []
var checks := 0
var report := {}
var args := {}

func _source_hashes(path: String = "res://src/world") -> Dictionary:
	var hashes := {}
	for name in DirAccess.get_files_at(path):
		if name.ends_with(".gd") or name.ends_with(".gdshader"):
			hashes[path.path_join(name)] = FileAccess.get_sha256(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		hashes.merge(_source_hashes(path.path_join(name)))
	return hashes

func _ready() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool, detail = null) -> void:
	checks += 1
	if not ok:
		failures.append({"check": name, "detail": detail})
		print("[design] FAIL ", name, " ", detail)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true
	var seed_value := int(args.get("seed", 1729))
	var layout_a = Layout.new(seed_value)
	var layout_b = Layout.new(seed_value)
	_check("layout_deterministic", var_to_bytes(layout_a.lots) == var_to_bytes(layout_b.lots)
		and layout_a._reserved == layout_b._reserved and layout_a._water == layout_b._water)
	var categories := {}
	for lot in layout_a.lots:
		categories[str(lot.kind)] = int(categories.get(str(lot.kind), 0)) + 1
	report = {"engine": Engine.get_version_info(), "seed": seed_value, "backend": DisplayServer.get_name(),
		"lot_categories": categories, "roads": layout_a.roads.size(), "bridge_types": layout_a.bridges,
		"note": "No renderer frame-rate claim. Collision tests use built physics geometry, not layout masks."}
	var source_hashes := _source_hashes()
	report.source_sha256 = source_hashes
	var first_fingerprint := ""
	var listener_count := Settings.changed.get_connections().size()
	var baseline_objects := -1.0
	for cycle in int(args.get("cycles", 2 if args.has("repeat") else 1)):
		var world := TestWorld.new()
		add_child(world)
		var started := Time.get_ticks_msec()
		world.map = MapBuilder.new()
		world.map.build(world, seed_value, 1, {"map": "lawless_sub", "record": true})
		var map = world.map
		report["build_%d_ms" % cycle] = Time.get_ticks_msec() - started
		await get_tree().physics_frame
		await get_tree().physics_frame
		if cycle == 0:
			first_fingerprint = map.fingerprint
			report.fingerprint = first_fingerprint
			report.map_stats = map.stats.duplicate(true)
			_census(map)
			_check_physics(map, world.get_world_3d().direct_space_state)
		else:
			_check("scene_fingerprint_repeat", map.fingerprint == first_fingerprint, map.fingerprint)
		var map_ref := weakref(map)
		var dyn_ref := weakref(map.dyn)
		var lod_ref := weakref(map.view_lod)
		var lighting_ref := weakref(map.lighting)
		world.free()
		map = null
		await get_tree().process_frame
		_check("map_released_after_teardown", map_ref.get_ref() == null, cycle)
		_check("dynamics_released_after_teardown", dyn_ref.get_ref() == null, cycle)
		_check("lod_released_after_teardown", lod_ref.get_ref() == null, cycle)
		_check("lighting_released_after_teardown", lighting_ref.get_ref() == null, cycle)
		_check("settings_listeners_restored", Settings.changed.get_connections().size() == listener_count,
			{"cycle": cycle, "before": listener_count, "after": Settings.changed.get_connections().size()})
		report["orphan_nodes_after_cycle_%d" % cycle] = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		report["nodes_after_cycle_%d" % cycle] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
		report["objects_after_cycle_%d" % cycle] = objects
		report["static_memory_after_cycle_%d" % cycle] = Performance.get_monitor(Performance.MEMORY_STATIC)
		if cycle == 0:
			baseline_objects = objects
		else:
			_check("object_count_bounded_after_rebuild", objects <= baseline_objects + 32, {"first": baseline_objects, "now": objects})
	_check("source_unchanged_during_validation", source_hashes == _source_hashes())
	report.checks = checks
	report.failures = failures
	report.passed = failures.is_empty()
	var out := str(args.get("out", "user://deathmatch_design.json"))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
	print("[design] ", JSON.stringify({"passed": report.passed, "checks": checks, "failures": failures.size(),
		"fingerprint": first_fingerprint, "output": out, "stats": report.get("scene_census", {})}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _census(map) -> void:
	var found := {"nodes": 0, "meshes": 0, "multimeshes": 0, "model_instances": 0,
		"mesh_surfaces": 0, "lights": 0, "collision_shapes": 0, "occluders": 0, "triangles": 0}
	var queue: Array = [map.root]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		found.nodes += 1
		queue.append_array(node.get_children())
		if node is Node3D:
			_check("finite_transform", (node as Node3D).transform.is_finite(), node.name)
		if node is MeshInstance3D and node.mesh:
			found.meshes += 1
			_check("render_mesh_has_surface", node.mesh.get_surface_count() > 0, node.name)
			found.mesh_surfaces += node.mesh.get_surface_count()
			for i in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(i)
				var indices = arrays[Mesh.ARRAY_INDEX]
				var vertices = arrays[Mesh.ARRAY_VERTEX]
				found.triangles += indices.size() / 3 if indices != null and indices.size() > 0 else vertices.size() / 3
				var material: Material = node.mesh.surface_get_material(i)
				if material is ShaderMaterial and material.shader.resource_path.ends_with("urban_surface.gdshader"):
					var custom = arrays[Mesh.ARRAY_CUSTOM0]
					_check("urban_surface_attributes", custom != null and custom.size() == vertices.size() * 4,
						{"vertices": vertices.size(), "attributes": custom.size() if custom != null else -1})
					if custom is PackedFloat32Array:
						var valid := true
						var layer_count: int = map.mats._urban_layers.size()
						for c in range(0, custom.size(), 4):
							valid = valid and is_finite(custom[c]) and custom[c] >= 0 and custom[c] < layer_count and custom[c] == floorf(custom[c])
							for channel in range(1, 4):
								valid = valid and is_finite(custom[c + channel]) and custom[c + channel] >= 0 and custom[c + channel] <= 1
						_check("urban_surface_attribute_bounds", valid)
					for channel in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
						_check("urban_vertex_channel_count", arrays[channel] != null and arrays[channel].size() == vertices.size(), channel)
					_check("urban_tangent_channel_count", arrays[Mesh.ARRAY_TANGENT] != null and arrays[Mesh.ARRAY_TANGENT].size() == vertices.size() * 4)
		if node is MultiMeshInstance3D and node.multimesh:
			found.multimeshes += 1
			found.model_instances += node.multimesh.instance_count
			if node.multimesh.mesh:
				found.mesh_surfaces += node.multimesh.mesh.get_surface_count()
		if node is Light3D:
			found.lights += 1
		if node is CollisionShape3D:
			found.collision_shapes += 1
		if node is OccluderInstance3D:
			found.occluders += 1
	var texture_sizes := {}
	for path in map.mats._tex_cache:
		var tex = map.mats._tex_cache[path]
		if tex:
			texture_sizes[str(path)] = [tex.get_width(), tex.get_height()]
	var record_categories := {}
	for rec in map.sink.rec:
		var xf: Transform3D = rec[0]
		var size: Vector3 = rec[1]
		var what := str(rec[2])
		record_categories[what] = int(record_categories.get(what, 0)) + 1
		_check("finite_collision_box", xf.is_finite() and size.is_finite(), what)
		_check("positive_collision_box", size.x > 0 and size.y > 0 and size.z > 0, {"what": what, "size": str(size)})
	report.scene_census = found
	report.collision_categories = record_categories
	report.material_count = map.mats._cache.size()
	report.texture_count = texture_sizes.size()
	report.texture_dimensions = texture_sizes
	report.static_memory_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)

func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, Defs.MOVE_MASK)
	return space.intersect_ray(query)

func _clear(space: PhysicsDirectSpaceState3D, feet: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis(), feet + Vector3.UP * 0.91)
	query.collision_mask = Defs.MOVE_MASK
	query.margin = 0.01
	return space.intersect_shape(query, 1).is_empty()

func _check_physics(map, space: PhysicsDirectSpaceState3D) -> void:
	var spawn_details := []
	for team in map.layout.spawns.size():
		_check("team_has_ten_spawns", map.layout.spawns[team].size() >= 10, team)
		for p: Vector3 in map.layout.spawns[team]:
			var ground := _ray(space, p + Vector3.UP * 0.45, p - Vector3.UP * 0.5)
			_check("spawn_floor", not ground.is_empty(), str(p))
			var clear := _clear(space, p)
			_check("spawn_standing_clearance", clear, str(p))
			spawn_details.append({"team": team, "position": str(p), "clear": clear,
				"surface_error_m": absf(ground.position.y - p.y) if not ground.is_empty() else -1})
	report.spawn_checks = spawn_details
	var bridge_checks := []
	for bridge in map.layout.bridges:
		if str(bridge.type) == "pipe":
			continue # Pipe crossing is a balance route; no standing capsule invariant.
		var a: Vector2
		var b: Vector2
		var top: float = map.layout.LAND_Y + map.layout.ROAD_TOP
		if str(bridge.type) == "footbridge":
			a = bridge.a
			b = bridge.b
			top = map.layout.LAND_Y + 0.22
		else:
			var rect: Rect2 = bridge.rect
			if rect.size.x > rect.size.y:
				a = Vector2(rect.position.x + 0.3, rect.get_center().y)
				b = Vector2(rect.end.x - 0.3, rect.get_center().y)
			else:
				a = Vector2(rect.get_center().x, rect.position.y + 0.3)
				b = Vector2(rect.get_center().x, rect.end.y - 0.3)
		var supported := true
		for k in 21:
			var p2 := a.lerp(b, k / 20.0)
			var feet := Vector3(p2.x, top, p2.y)
			var hit := _ray(space, feet + Vector3.UP * 0.2, feet - Vector3.UP * 0.3)
			supported = supported and not hit.is_empty()
		_check("bridge_continuous_deck", supported, bridge.name)
		bridge_checks.append({"name": bridge.name, "samples": 21, "supported": supported})
	report.bridge_checks = bridge_checks
	var stair_support := 0
	var stair_samples := 0
	for stair in map.stairs:
		var a: Vector3 = stair.get("start", stair.foot)
		# foot/top include approach and side-exit positions; their diagonal is not the flight's centre line.
		var b: Vector3 = a + (stair.dir as Vector3) * float(stair.run) + Vector3.UP * float(stair.rise)
		for k in [0.15, 0.5, 0.85]:
			var p := a.lerp(b, k)
			var hit := _ray(space, p + Vector3.UP * 0.65, p - Vector3.UP * 0.85)
			stair_samples += 1
			if not hit.is_empty():
				stair_support += 1
			_check("stair_surface_support", not hit.is_empty(), {"position": str(p), "foot": str(a), "top": str(b)})
	report.stair_checks = {"flights": map.stairs.size(), "samples": stair_samples, "supported": stair_support}
	var detail: Dictionary = map.stats.get("street_detail", {})
	if detail.has("overpass"):
		var pass_detail: Dictionary = detail.overpass
		var center: Vector3 = pass_detail.center
		var top: float = pass_detail.deck_top
		_check("overpass_vehicle_clearance", float(pass_detail.road_clearance) >= 5.3, pass_detail.road_clearance)
		for foot: Vector3 in pass_detail.stair_feet:
			var landing := Vector3(foot.x, top, center.z + 1.2)
			_check("overpass_landing_open", _clear(space, landing + Vector3.UP * 0.04), str(landing))
			var rail_hit := _ray(space, landing + Vector3(0, 0.8, 0.6), landing - Vector3(0, -0.8, 0.6))
			_check("overpass_stair_opening", rail_hit.is_empty(), str(landing))
		for x in [center.x - 4.0, center.x + 4.0]:
			var from := Vector3(x, map.layout.LAND_Y + map.layout.ROAD_TOP + 0.3, center.z)
			var hit := _ray(space, from, from + Vector3.UP * 5.1)
			_check("overpass_road_clear", hit.is_empty(), str(from))
		report.overpass_checked = true
