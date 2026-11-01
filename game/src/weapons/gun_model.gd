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


static var _wells: Dictionary = {}
static var _no_mag: Dictionary = {}


static func well(id: String) -> Dictionary:
	## (r25) Where the gun's own magazine goes into the gun (model space): {"lip": the middle of the well's lower
	## edge}. Empty when the magazine is not a part of its own or is too short to see (handguns keep theirs in the grip).
	if _wells.has(id):
		return _wells[id]
	var out := {}
	var p := parts(id)
	if p.has("mag") and p.has("body") and (p.mag.aabb as AABB).size.y >= 0.04:
		var top: float = (p.mag.aabb as AABB).end.y
		# The magazine's top: the part inside the gun, and its footprint there.
		var lo := Vector3(INF, 0, INF)
		var hi := Vector3(-INF, 0, -INF)
		for si in (p.mag.mesh as Mesh).get_surface_count():
			for v in (p.mag.mesh as Mesh).surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				if v.y > top - 0.02:
					lo = Vector3(minf(lo.x, v.x), 0, minf(lo.z, v.z))
					hi = Vector3(maxf(hi.x, v.x), 0, maxf(hi.z, v.z))
		var c := (lo + hi) * 0.5
		var half := (hi - lo) * 0.5 + Vector3(0.004, 0, 0.004)
		# The lowest point of the body around that footprint is the well's lip.
		var lip := INF
		for si in (p.body.mesh as Mesh).get_surface_count():
			for v in (p.body.mesh as Mesh).surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				if absf(v.x - c.x) < half.x and absf(v.z - c.z) < half.z and v.y < top + 0.01:
					lip = minf(lip, v.y)
		if lip == INF:
			lip = top - 0.03
		out = {"lip": Vector3(c.x, lip, c.z)}
	_wells[id] = out
	return out


static func without_mag(id: String) -> Mesh:
	## (r25) The whole gun as one mesh, but without its own magazine (a drum is in the well instead).
	if _no_mag.has(id):
		return _no_mag[id]
	var am := ArrayMesh.new()
	var p := parts(id)
	for role in p:
		if role == "mag":
			continue
		var m: Mesh = p[role].mesh
		for si in m.get_surface_count():
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _plain(m.surface_get_arrays(si)))
			am.surface_set_material(am.get_surface_count() - 1, m.surface_get_material(si))
	_no_mag[id] = am
	return am


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
