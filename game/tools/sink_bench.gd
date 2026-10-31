extends SceneTree
## r15: times GeoSink.box / quad (the hot path of every map build) on a fixed workload and checksums the output, so
## an optimisation can be checked to be both faster and identical.
##   godot --headless --path game -s res://tools/sink_bench.gd

const GeoSink := preload("res://src/world/geo_sink.gd")
const Materials := preload("res://src/world/materials.gd")


func _init() -> void:
	var mats := Materials.new()
	var root := Node3D.new()
	var sink := GeoSink.new(mats, root, 7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var names := ["plywood", "chb", "planks", "yero", "concrete", "mall_paint", "tiles"]
	var layers := ["ext", "int", "mid"]
	var t0 := Time.get_ticks_usec()
	for i in 60000:
		var p := Vector3(rng.randf_range(-300, 300), rng.randf_range(0, 12), rng.randf_range(-300, 300))
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		if i % 7 == 0:
			b = b * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5))
		if i % 11 == 0:
			b = b * Basis().scaled(Vector3(-1, 1, 1))
		var sz := Vector3(rng.randf_range(0.05, 4), rng.randf_range(0.05, 3), rng.randf_range(0.05, 4))
		var opt := {"layer": layers[i % 3], "collide": i % 2 == 0, "dirt": rng.randf()}
		if i % 5 == 0:
			opt.tint = Color(rng.randf(), rng.randf(), rng.randf())
			opt.paint = 1.0
		if i % 13 == 0:
			opt.faces = 63 & ~8
		sink.box(Transform3D(b, p), sz, names[i % names.size()], opt)
	var t1 := Time.get_ticks_usec()
	for i in 20000:
		var p2 := Vector3(rng.randf_range(-300, 300), rng.randf_range(0, 12), rng.randf_range(-300, 300))
		sink.quad(p2, p2 + Vector3(2, 0, 0), p2 + Vector3(2, 0, 2), p2 + Vector3(0, 0, 2), names[i % names.size()], {"collide": i % 2 == 0, "facing": Vector3.UP})
	var t2 := Time.get_ticks_usec()
	# checksum of everything accumulated
	var h := 0
	var keys: Array = sink._meshes.keys()
	keys.sort()
	for k in keys:
		var a = sink._meshes[k]
		h = hash([h, k, a.v.size(), hash(a.v), hash(a.n), hash(a.t), hash(a.uv), hash(a.uv2), hash(a.c), hash(a.i)])
	var ck: Array = sink._cols.keys()
	ck.sort()
	for k2 in ck:
		h = hash([h, k2, hash(sink._cols[k2].tris)])
	print("[bench] box x60000: %.0f ms (%.1f us each); quad x20000: %.0f ms; meshes %d, cols %d; checksum %08x" % [
		(t1 - t0) / 1000.0, float(t1 - t0) / 60000.0, (t2 - t1) / 1000.0, sink._meshes.size(), sink._cols.size(), h & 0xFFFFFFFF])
	root.free()
	quit()
