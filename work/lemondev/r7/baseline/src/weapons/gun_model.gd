extends RefCounted
## A gun's model split into its moving parts, for the first-person view: "body" plus any of mag, slide, bolt, pump,
## cylinder, barrel (tools/blender/process_items.py keeps them as separate nodes of assets/models/items/<id>.glb).
## Every part is in the same space as the merged mesh item_visual returns, so item_visual's "xf" places them all.

static var _cache: Dictionary = {}


static func parts(id: String) -> Dictionary:
	## {role: {"mesh": Mesh, "aabb": AABB}} (model space); empty when the gun has no processed model.
	if _cache.has(id):
		return _cache[id]
	var out := {}
	var path := "res://assets/models/items/%s.glb" % id
	if ResourceLoader.exists(path):
		var ps: PackedScene = load(path)
		var inst := ps.instantiate()
		_collect(inst, Transform3D(), out)
		inst.free()
	_cache[id] = out
	return out


static func _collect(n: Node, xf: Transform3D, out: Dictionary) -> void:
	for c in n.get_children():
		var cx := xf
		if c is Node3D:
			cx = xf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var role := str(c.name).get_slice(".", 0).get_slice("_", 0).to_lower()
			var m: Mesh = (c as MeshInstance3D).mesh
			if not cx.is_equal_approx(Transform3D()):
				m = _baked(m, cx)
			if out.has(role):
				# Two nodes for one role (an exporter split): keep them both as one mesh.
				m = _joined(out[role].mesh, m)
			out[role] = {"mesh": m, "aabb": m.get_aabb()}
		_collect(c, cx, out)


static func _plain(arr: Array) -> Array:
	## Only the arrays a static gun mesh needs (imported surfaces may carry bone or custom channels that cannot be
	## re-added as they are).
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]:
		out[k] = arr[k]
	return out


static func _baked(m: Mesh, xf: Transform3D) -> ArrayMesh:
	var am := ArrayMesh.new()
	for si in m.get_surface_count():
		var arr := _plain(m.surface_get_arrays(si))
		arr[Mesh.ARRAY_VERTEX] = xf * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		if arr[Mesh.ARRAY_NORMAL] is PackedVector3Array:
			var nb := xf.basis.inverse().transposed()
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in nn.size():
				nn[i] = (nb * nn[i]).normalized()
			arr[Mesh.ARRAY_NORMAL] = nn
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(am.get_surface_count() - 1, m.surface_get_material(si))
	return am


static func _joined(a: Mesh, b: Mesh) -> ArrayMesh:
	var am := ArrayMesh.new()
	for m in [a, b]:
		for si in (m as Mesh).get_surface_count():
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _plain((m as Mesh).surface_get_arrays(si)))
			am.surface_set_material(am.get_surface_count() - 1, (m as Mesh).surface_get_material(si))
	return am
