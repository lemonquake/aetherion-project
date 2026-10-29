extends RefCounted
## Chunk-by-chunk destruction data. A breakable prop's model is cut into a grid of chunks (up to 3 per axis, about
## 30 cm each) by triangle centre, once per model and cached. Every machine (a headless server too) cuts the same
## mesh the same way, so chunk indices agree between the server and clients. A door leaf is cut into panels: 3
## columns x 5 rows with seams jittered from the door's id, the same everywhere.

const TARGET := 0.3
const MAX_PER_AXIS := 3
const KEEP := [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]

static var _cache := {}


static func chunks_for(models, name: String) -> Dictionary:
	## {dims, origin, cell (size), offset, keys: [cell index], chunks: {index: {surf: [arrays|null], aabb, center}},
	##  mats: [Material], volume: {index: fraction of the model's triangles}}. Empty dict if the model has no mesh.
	if _cache.has(name):
		return _cache[name]
	var md: Dictionary = models.get_model(name)
	if md.is_empty() or not (md.get("mesh") is Mesh):
		_cache[name] = {}
		return {}
	var mesh: Mesh = md.mesh
	var aabb: AABB = md.aabb
	var off: Vector3 = md.get("offset", Vector3.ZERO)
	var dims := Vector3i(_axis(aabb.size.x), _axis(aabb.size.y), _axis(aabb.size.z))
	var cell := Vector3(aabb.size.x / dims.x, aabb.size.y / dims.y, aabb.size.z / dims.z).max(Vector3(0.001, 0.001, 0.001))
	var groups := {}   # cell index -> [per surface PackedInt32Array of triangle corner indices]
	var nsurf := mesh.get_surface_count()
	var src: Array = []
	var total_tris := 0
	var tri_count := {}
	for s in nsurf:
		var arr: Array = mesh.surface_get_arrays(s)
		src.append(arr)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		for t in range(0, idx.size() - 2, 3):
			var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
			var g := ((c - aabb.position) / cell).floor()
			var gi := Vector3i(clampi(int(g.x), 0, dims.x - 1), clampi(int(g.y), 0, dims.y - 1), clampi(int(g.z), 0, dims.z - 1))
			var key := gi.x + gi.y * dims.x + gi.z * dims.x * dims.y
			if not groups.has(key):
				var e := []
				e.resize(nsurf)
				for k in nsurf:
					e[k] = PackedInt32Array()
				groups[key] = e
			# Packed arrays are values: take it out, append, put it back.
			var g_arr: PackedInt32Array = groups[key][s]
			g_arr.append(idx[t])
			g_arr.append(idx[t + 1])
			g_arr.append(idx[t + 2])
			groups[key][s] = g_arr
			tri_count[key] = int(tri_count.get(key, 0)) + 1
			total_tris += 1
	var chunks := {}
	var keys := groups.keys()
	keys.sort()
	var volume := {}
	for key in keys:
		var surf: Array = []
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for s in nsurf:
			var corners: PackedInt32Array = groups[key][s]
			if corners.is_empty():
				surf.append(null)
				continue
			var packed := _compact(src[s], corners)
			surf.append(packed)
			for p in (packed[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				lo = lo.min(p)
				hi = hi.max(p)
		var box := AABB(lo + off, (hi - lo).max(Vector3(0.03, 0.03, 0.03)))
		chunks[key] = {"surf": surf, "aabb": box, "center": box.get_center()}
		volume[key] = float(tri_count[key]) / maxf(total_tris, 1)
	var mats: Array = []
	for s in nsurf:
		mats.append(mesh.surface_get_material(s))
	var info := {"dims": dims, "origin": aabb.position + off, "cell": cell, "offset": off, "keys": keys, "chunks": chunks,
		"mats": mats, "volume": volume, "debris_mesh": {}}
	_cache[name] = info
	return info


static func _axis(size: float) -> int:
	return clampi(int(round(size / TARGET)), 1, MAX_PER_AXIS)


static func _compact(arr: Array, corners: PackedInt32Array) -> Array:
	## The vertices those triangle corners use, renumbered from 0.
	var remap := {}
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	new_idx.resize(corners.size())
	for i in corners.size():
		var o := corners[i]
		var n: int = remap.get(o, -1)
		if n < 0:
			n = order.size()
			remap[o] = n
			order.append(o)
		new_idx[i] = n
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in KEEP:
		var a = arr[k]
		if a == null:
			continue
		match k:
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
				var r := PackedVector3Array()
				r.resize(order.size())
				for i in order.size():
					r[i] = a[order[i]]
				out[k] = r
			Mesh.ARRAY_TANGENT:
				var r2 := PackedFloat32Array()
				r2.resize(order.size() * 4)
				for i in order.size():
					for j in 4:
						r2[i * 4 + j] = a[order[i] * 4 + j]
				out[k] = r2
			Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
				var r3 := PackedVector2Array()
				r3.resize(order.size())
				for i in order.size():
					r3[i] = a[order[i]]
				out[k] = r3
			Mesh.ARRAY_COLOR:
				var r4 := PackedColorArray()
				r4.resize(order.size())
				for i in order.size():
					r4[i] = a[order[i]]
				out[k] = r4
	out[Mesh.ARRAY_INDEX] = new_idx
	return out


static func build_mesh(info: Dictionary, alive: Array) -> ArrayMesh:
	## The model with only the chunks in alive (cell indices), one surface per source surface, same materials.
	var mesh := ArrayMesh.new()
	var nsurf: int = (info.mats as Array).size()
	for s in nsurf:
		var parts: Array = []
		for key in alive:
			var c: Dictionary = info.chunks.get(key, {})
			if c.is_empty() or c.surf[s] == null:
				continue
			parts.append(c.surf[s])
		if parts.is_empty():
			continue
		var merged := _merge(parts)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged)
		mesh.surface_set_material(mesh.get_surface_count() - 1, info.mats[s])
	return mesh


static func chunk_mesh(info: Dictionary, key: int) -> ArrayMesh:
	## One chunk on its own (a piece of debris). Cached per model.
	if info.debris_mesh.has(key):
		return info.debris_mesh[key]
	var m := build_mesh(info, [key])
	info.debris_mesh[key] = m
	return m


static func _merge(parts: Array) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var first: Array = parts[0]
	for k in KEEP:
		if first[k] != null:
			out[k] = (first[k] as Variant).duplicate()
	out[Mesh.ARRAY_INDEX] = (first[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
	for pi in range(1, parts.size()):
		var p: Array = parts[pi]
		var base := (out[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for k in KEEP:
			if out[k] != null and p[k] != null:
				var acc = out[k]
				acc.append_array(p[k])
				out[k] = acc
		var idx: PackedInt32Array = (p[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
		for i in idx.size():
			idx[i] += base
		var all_idx: PackedInt32Array = out[Mesh.ARRAY_INDEX]
		all_idx.append_array(idx)
		out[Mesh.ARRAY_INDEX] = all_idx
	return out


static func nearest_chunk(info: Dictionary, alive: Array, local: Vector3) -> int:
	## The living chunk whose box is nearest a point in the prop's own space (the collision box spans empty cells).
	var best := -1
	var best_d := INF
	for key in alive:
		var c: Dictionary = info.chunks.get(key, {})
		if c.is_empty():
			continue
		var b: AABB = c.aabb
		var q := local.clamp(b.position, b.end)
		var d := q.distance_squared_to(local)
		if d < best_d:
			best_d = d
			best = key
	return best


# ------------------------------------------------------------------ door panels

const DOOR_COLS := 3
const DOOR_ROWS := 5


static func door_panels(door_id: int, w: float, h: float) -> Array:
	## [Rect2 in the leaf's own plane: x from the hinge (0..w), y from the bottom (0..h)], column-major from the
	## hinge, bottom up. Seams jittered from the id so neighbouring doors break differently.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(door_id * 7919 + 17)
	var xs := [0.0]
	for i in range(1, DOOR_COLS):
		xs.append(w * float(i) / DOOR_COLS + rng.randf_range(-0.08, 0.08) * w / DOOR_COLS)
	xs.append(w)
	var out := []
	for c in DOOR_COLS:
		var ys := [0.0]
		for j in range(1, DOOR_ROWS):
			ys.append(h * float(j) / DOOR_ROWS + rng.randf_range(-0.25, 0.25) * h / DOOR_ROWS)
		ys.append(h)
		for r in DOOR_ROWS:
			out.append(Rect2(xs[c], ys[r], xs[c + 1] - xs[c], ys[r + 1] - ys[r]))
	return out


static func door_panel_at(panels: Array, lost: Dictionary, local: Vector2) -> int:
	## The panel under a point on the leaf, or the nearest one still standing.
	var best := -1
	var best_d := INF
	for i in panels.size():
		if lost.has(i):
			continue
		var r: Rect2 = panels[i]
		var q := Vector2(clampf(local.x, r.position.x, r.end.x), clampf(local.y, r.position.y, r.end.y))
		var d := q.distance_squared_to(local)
		if d < best_d:
			best_d = d
			best = i
	return best


static func door_collapses(panels: Array, lost: Dictionary) -> bool:
	## The leaf falls off its hinges once the hinge column is shot through or most of it is gone.
	if float(lost.size()) >= panels.size() * 0.6:
		return true
	for r in DOOR_ROWS:
		if not lost.has(r):
			return false
	return true
