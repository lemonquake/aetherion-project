extends RefCounted
## Batches generated architecture into one mesh per (chunk, material, layer), one trimesh collider per
## (chunk, physical material) and one occluder per chunk. Thousands of boxes become a few hundred draw calls.
##
## Layers: "ext" (exteriors, long draw distance), "int" (interiors and small detail, short draw distance).

const CHUNK := 32.0

var mats = null
var root: Node3D
var _meshes: Dictionary = {}     # key "cx,cz|mat|layer" -> arrays dict
var _cols: Dictionary = {}       # key "cx,cz|phys" -> PackedVector3Array (triangles)
var _occ: Dictionary = {}        # key "cx,cz" -> {verts, idx}
var rng := RandomNumberGenerator.new()
var stats := {"boxes": 0, "tris": 0, "meshes": 0, "colliders": 0}
var draw_ext := 520.0
var draw_int := 85.0
var body_info: Dictionary = {}   # body RID -> {mat}
var bodies: Array = []


func _init(materials, parent: Node3D, seed_value: int = 1) -> void:
	mats = materials
	root = parent
	rng.seed = seed_value


static func chunk_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


func _arr(key: String) -> Dictionary:
	if not _meshes.has(key):
		_meshes[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(), "uv": PackedVector2Array(),
			"uv2": PackedVector2Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
	return _meshes[key]


func _mkey(ck: Vector2i, mat: String, layer: String) -> String:
	return "%d,%d|%s|%s" % [ck.x, ck.y, mat, layer]


# ------------------------------------------------------------------ primitives

func box(xf: Transform3D, size: Vector3, mat: String, opt: Dictionary = {}) -> void:
	## An oriented box centred at xf.origin. opt: tint (Color), paint (0..1), dirt (0..1), base_y (float),
	## collide (bool, default true), occlude (bool), layer ("ext"/"int"), faces (bitmask +x -x +y -y +z -z = 1..32),
	## phys (override physical material), uv_off (Vector2), tile (float override).
	stats.boxes += 1
	var h := size * 0.5
	var layer := str(opt.get("layer", "ext"))
	var faces := int(opt.get("faces", 63))
	var tint: Color = opt.get("tint", Color(1, 1, 1))
	tint.a = float(opt.get("paint", 0.0))
	var dirt := float(opt.get("dirt", 0.5))
	var base_y := float(opt.get("base_y", xf.origin.y - h.y * absf(xf.basis.y.y)))
	var tile := float(opt.get("tile", mats.tile(mat)))
	var uvo: Vector2 = opt.get("uv_off", Vector2(rng.randf() * 4.0, rng.randf() * 4.0))
	var a := _arr(_mkey(chunk_key(xf.origin), mat, layer))
	# Each face: normal axis, u axis, v axis (local), half extents along u and v.
	var defs := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP, h.z, h.y, h.x, 1],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.UP, h.z, h.y, h.x, 2],
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, h.x, h.z, h.y, 4],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, h.x, h.z, h.y, 8],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP, h.x, h.y, h.z, 16],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, h.x, h.y, h.z, 32],
	]
	for d in defs:
		if (faces & int(d[6])) == 0:
			continue
		var n: Vector3 = d[0]
		var u: Vector3 = d[1]
		var v: Vector3 = d[2]
		var hu: float = d[3]
		var hv: float = d[4]
		var hn: float = d[5]
		_quad(a, xf, n * hn, u, v, hu, hv, n, tile, uvo, tint, dirt, base_y)
	if opt.get("collide", true):
		_col_box(xf, size, str(opt.get("phys", mats.phys(mat))))
	if opt.get("occlude", false):
		_occ_box(xf, size)


func _quad(a: Dictionary, xf: Transform3D, center: Vector3, u: Vector3, v: Vector3, hu: float, hv: float, n: Vector3,
		tile: float, uvo: Vector2, tint: Color, dirt: float, base_y: float) -> void:
	var base = a.v.size()
	var wn := (xf.basis * n).normalized()
	var wu := (xf.basis * u).normalized()
	var wv := (xf.basis * v).normalized()
	# Tangent follows +u; the binormal must point to decreasing texture v (image up), which is +v here.
	var sign := 1.0 if wn.cross(wu).dot(wv) >= 0.0 else -1.0
	var corners := [[-1, -1], [1, -1], [1, 1], [-1, 1]]
	for c in corners:
		var lp: Vector3 = center + u * (hu * c[0]) + v * (hv * c[1])
		a.v.append(xf * lp)
		a.n.append(wn)
		a.t.append_array(PackedFloat32Array([wu.x, wu.y, wu.z, sign]))
		a.uv.append(Vector2((hu * c[0] + hu) / tile + uvo.x, -(hv * c[1] + hv) / tile + uvo.y))
		a.uv2.append(Vector2(dirt, base_y))
		a.c.append(tint)
	a.i.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
	stats.tris += 2


func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, mat: String, opt: Dictionary = {}) -> void:
	## A free quad (p0..p3 counter-clockwise seen from the front). Used for roofs, ramps and terrain patches.
	var layer := str(opt.get("layer", "ext"))
	var a := _arr(_mkey(chunk_key((p0 + p2) * 0.5), mat, layer))
	var n := (p1 - p0).cross(p3 - p0).normalized()
	var u := (p1 - p0).normalized()
	var v := n.cross(u).normalized()
	var tile := float(opt.get("tile", mats.tile(mat)))
	var uvo: Vector2 = opt.get("uv_off", Vector2.ZERO)
	var tint: Color = opt.get("tint", Color(1, 1, 1))
	tint.a = float(opt.get("paint", 0.0))
	var dirt := float(opt.get("dirt", 0.4))
	var base_y := float(opt.get("base_y", minf(minf(p0.y, p1.y), minf(p2.y, p3.y))))
	var base = a.v.size()
	for p in [p0, p1, p2, p3]:
		a.v.append(p)
		a.n.append(n)
		a.t.append_array(PackedFloat32Array([u.x, u.y, u.z, 1.0]))
		var rel: Vector3 = p - p0
		a.uv.append(Vector2(rel.dot(u) / tile + uvo.x, -rel.dot(v) / tile + uvo.y))
		a.uv2.append(Vector2(dirt, base_y))
		a.c.append(tint)
	a.i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	stats.tris += 2
	if opt.get("double", false):
		var b2 = a.v.size()
		for p in [p0, p1, p2, p3]:
			a.v.append(p)
			a.n.append(-n)
			a.t.append_array(PackedFloat32Array([u.x, u.y, u.z, -1.0]))
			var rel2: Vector3 = p - p0
			a.uv.append(Vector2(rel2.dot(u) / tile + uvo.x, -rel2.dot(v) / tile + uvo.y))
			a.uv2.append(Vector2(dirt, base_y))
			a.c.append(tint)
		a.i.append_array(PackedInt32Array([b2, b2 + 2, b2 + 1, b2, b2 + 3, b2 + 2]))
	if opt.get("collide", false):
		var key := "%d,%d|%s" % [chunk_key(p0).x, chunk_key(p0).y, str(opt.get("phys", mats.phys(mat)))]
		if not _cols.has(key):
			_cols[key] = PackedVector3Array()
		_cols[key].append_array(PackedVector3Array([p0, p1, p2, p0, p2, p3]))


func corrugated(xf: Transform3D, length: float, width: float, mat: String, opt: Dictionary = {}) -> void:
	## A corrugated sheet lying in the local XZ plane: ridges run along local Z (the slope), `width` along X.
	## Real geometry (sine profile) so silhouettes and grazing light read as corrugated iron.
	var layer := str(opt.get("layer", "ext"))
	var a := _arr(_mkey(chunk_key(xf.origin), mat, layer))
	var pitch := 0.076
	var amp := 0.009
	var waves := maxi(int(width / pitch), 1)
	var segs := waves * 2
	var tint: Color = opt.get("tint", Color(1, 1, 1))
	tint.a = float(opt.get("paint", 0.0))
	var dirt := float(opt.get("dirt", 0.5))
	var tile = mats.tile(mat)
	var uvo: Vector2 = opt.get("uv_off", Vector2(rng.randf() * 3.0, rng.randf() * 3.0))
	var double := bool(opt.get("double", true))
	for side in ([1, -1] if double else [1]):
		for s in segs:
			var x0 := -width * 0.5 + width * float(s) / segs
			var x1 := -width * 0.5 + width * float(s + 1) / segs
			var y0 := sin(float(s) / segs * waves * TAU) * amp
			var y1 := sin(float(s + 1) / segs * waves * TAU) * amp
			var p0 := Vector3(x0, y0, -length * 0.5)
			var p1 := Vector3(x1, y1, -length * 0.5)
			var p2 := Vector3(x1, y1, length * 0.5)
			var p3 := Vector3(x0, y0, length * 0.5)
			var nl = Vector3(-(y1 - y0), x1 - x0, 0).normalized() * side
			var base = a.v.size()
			var wn = (xf.basis * nl).normalized()
			var wu := (xf.basis * Vector3.RIGHT).normalized()
			for p in [p0, p1, p2, p3]:
				a.v.append(xf * (p + Vector3(0, 0.0015 * side, 0)))
				a.n.append(wn)
				a.t.append_array(PackedFloat32Array([wu.x, wu.y, wu.z, float(side)]))
				a.uv.append(Vector2((p.x + width * 0.5) / tile + uvo.x, (p.z + length * 0.5) / tile + uvo.y))
				a.uv2.append(Vector2(dirt, xf.origin.y - 3.0))
				a.c.append(tint)
			if side == 1:
				a.i.append_array(PackedInt32Array([base, base + 3, base + 2, base, base + 2, base + 1]))
			else:
				a.i.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
			stats.tris += 2
	if opt.get("collide", true):
		_col_box(xf, Vector3(width, 0.03, length), str(opt.get("phys", "sheet_metal")))


func cylinder(base_pos: Vector3, axis: Vector3, length: float, radius: float, mat: String, opt: Dictionary = {}) -> void:
	var layer := str(opt.get("layer", "ext"))
	var a := _arr(_mkey(chunk_key(base_pos), mat, layer))
	var sides := int(opt.get("sides", 8))
	var ax := axis.normalized()
	var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
	var side := ax.cross(ref).normalized()
	var up := side.cross(ax).normalized()
	var tint: Color = opt.get("tint", Color(1, 1, 1))
	tint.a = float(opt.get("paint", 0.0))
	var tile = mats.tile(mat)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		var base = a.v.size()
		var pts := [base_pos + d0 * radius, base_pos + d1 * radius, base_pos + d1 * radius + ax * length, base_pos + d0 * radius + ax * length]
		var ns := [d0, d1, d1, d0]
		var us := [0.0, 1.0, 1.0, 0.0]
		for k in 4:
			a.v.append(pts[k])
			a.n.append(ns[k])
			var tg: Vector3 = ax.cross(ns[k]).normalized()
			a.t.append_array(PackedFloat32Array([tg.x, tg.y, tg.z, 1.0]))
			a.uv.append(Vector2((float(i) + us[k]) * TAU * radius / sides / tile, (0.0 if k < 2 else -length / tile)))
			a.uv2.append(Vector2(float(opt.get("dirt", 0.4)), base_pos.y))
			a.c.append(tint)
		a.i.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))
		stats.tris += 2
	if opt.get("collide", false):
		var mid := base_pos + ax * length * 0.5
		var b := Basis(side, ax, -up) if true else Basis()
		_col_box(Transform3D(Basis(side, ax, side.cross(ax)).orthonormalized(), mid), Vector3(radius * 1.7, length, radius * 1.7), str(opt.get("phys", mats.phys(mat))))


func _col_box(xf: Transform3D, size: Vector3, phys: String) -> void:
	var key := "%d,%d|%s" % [chunk_key(xf.origin).x, chunk_key(xf.origin).y, phys]
	if not _cols.has(key):
		_cols[key] = PackedVector3Array()
	var h := size * 0.5
	var c := []
	for i in 8:
		c.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	var f := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	var arr: PackedVector3Array = _cols[key]
	for q in f:
		arr.append_array(PackedVector3Array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]]))
	_cols[key] = arr


func col_box(xf: Transform3D, size: Vector3, phys: String) -> void:
	## Invisible collision (ramps under steps, clipping blockers).
	_col_box(xf, size, phys)


func _occ_box(xf: Transform3D, size: Vector3) -> void:
	var ck := chunk_key(xf.origin)
	var key := "%d,%d" % [ck.x, ck.y]
	if not _occ.has(key):
		_occ[key] = {"v": PackedVector3Array(), "i": PackedInt32Array()}
	var o: Dictionary = _occ[key]
	var h := size * 0.5 * 0.97
	var base = o.v.size()
	for i in 8:
		o.v.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	var f := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	for q in f:
		o.i.append_array(PackedInt32Array([base + q[0], base + q[1], base + q[2], base + q[0], base + q[2], base + q[3]]))


# ------------------------------------------------------------------ output

func finish() -> void:
	var chunks := {}
	for key in _meshes:
		var parts: PackedStringArray = key.split("|")
		var a: Dictionary = _meshes[key]
		if a.i.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = a.v
		arrays[Mesh.ARRAY_NORMAL] = a.n
		arrays[Mesh.ARRAY_TANGENT] = a.t
		arrays[Mesh.ARRAY_TEX_UV] = a.uv
		arrays[Mesh.ARRAY_TEX_UV2] = a.uv2
		arrays[Mesh.ARRAY_COLOR] = a.c
		arrays[Mesh.ARRAY_INDEX] = a.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mats.get_material(parts[1]))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.name = "M_" + key.replace("|", "_").replace(",", "_")
		var layer := parts[2]
		if layer == "int":
			mi.visibility_range_end = draw_int
			mi.visibility_range_end_margin = 10.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			mi.visibility_range_end = draw_ext
		_chunk_node(chunks, parts[0]).add_child(mi)
		stats.meshes += 1
	var space := root.get_world_3d().space
	for key in _cols:
		var parts: PackedStringArray = key.split("|")
		var tris: PackedVector3Array = _cols[key]
		if tris.is_empty():
			continue
		var body := StaticBody3D.new()
		body.name = "B_" + key.replace("|", "_").replace(",", "_")
		body.collision_layer = Defs.PHYS_WORLD
		body.collision_mask = 0
		body.set_meta("mat", parts[1])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(tris)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		_chunk_node(chunks, parts[0]).add_child(body)
		stats.colliders += 1
	for key in _occ:
		var o: Dictionary = _occ[key]
		var occ := ArrayOccluder3D.new()
		occ.set_arrays(o.v, o.i)
		var oi := OccluderInstance3D.new()
		oi.occluder = occ
		_chunk_node(chunks, key).add_child(oi)
	_meshes.clear()
	_cols.clear()
	_occ.clear()


func _chunk_node(chunks: Dictionary, key: String) -> Node3D:
	if chunks.has(key):
		return chunks[key]
	var n := Node3D.new()
	n.name = "Chunk_" + key.replace(",", "_")
	root.add_child(n)
	chunks[key] = n
	return n
