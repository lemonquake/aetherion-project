extends RefCounted
## Batches generated architecture into one mesh per (chunk, material, layer), one trimesh collider per
## (chunk, physical material), one occluder per chunk and one cheap far-distance mesh per chunk.
##
## Layers: "ext" (exteriors, near), "int" (interiors and small detail, short range), plus the automatic "far" layer
## (flat-coloured blocks standing in for whole buildings beyond ~230 m: what you see while parachuting).
##
## Accumulators are objects so their packed arrays grow in place (packed arrays stored in a Dictionary would be
## copied on every append).

const CHUNK := 48.0
## Exteriors and their far stand-ins use bigger chunks: they are drawn out to ~220 m, where 48 m chunks of ~20
## materials each meant well over a thousand draw calls per pass. Both layers share these chunks, so each one is
## drawn either near or far, crossfading at one distance.
const WIDE := 96.0
# Box faces: [normal, u, v, bit]. u x v must equal the normal: Acc.quad winds (c-u-v, c+u+v, c+u-v), which is
# Godot's front face seen from the normal's side. The four sides had u reversed, so every wall showed its far
# face, lit from the wrong side: rooms took moonlight through the walls and no lamp or flashlight lit them.
const FACES := [
	[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0), 1],
	[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0), 2],
	[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), 4],
	[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), 8],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0), 16],
	[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0), 32],
]
const NO_BOTTOM := 55
const OUTWARD := 32


class Acc:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, tan: Vector3, sgn: float,
			u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2, d2: Vector2, col: Color) -> void:
		var b := v.size()
		v.append(p0); v.append(p1); v.append(p2); v.append(p3)
		n.append(nrm); n.append(nrm); n.append(nrm); n.append(nrm)
		t.append(tan.x); t.append(tan.y); t.append(tan.z); t.append(sgn)
		t.append(tan.x); t.append(tan.y); t.append(tan.z); t.append(sgn)
		t.append(tan.x); t.append(tan.y); t.append(tan.z); t.append(sgn)
		t.append(tan.x); t.append(tan.y); t.append(tan.z); t.append(sgn)
		uv.append(u0); uv.append(u1); uv.append(u2); uv.append(u3)
		uv2.append(d2); uv2.append(d2); uv2.append(d2); uv2.append(d2)
		c.append(col); c.append(col); c.append(col); c.append(col)
		i.append(b); i.append(b + 2); i.append(b + 1); i.append(b); i.append(b + 3); i.append(b + 2)


class FarAcc:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, col: Color) -> void:
		var b := v.size()
		v.append(p0); v.append(p1); v.append(p2); v.append(p3)
		n.append(nrm); n.append(nrm); n.append(nrm); n.append(nrm)
		c.append(col); c.append(col); c.append(col); c.append(col)
		i.append(b); i.append(b + 2); i.append(b + 1); i.append(b); i.append(b + 3); i.append(b + 2)


class TriAcc:
	extends RefCounted
	var tris := PackedVector3Array()


var mats = null
var root: Node3D
var _meshes: Dictionary = {}
var _cols: Dictionary = {}
var _occ: Dictionary = {}
var _far: Dictionary = {}
var rng := RandomNumberGenerator.new()
var stats := {"boxes": 0, "tris": 0, "meshes": 0, "colliders": 0, "far_tris": 0}
var draw_ext := 220.0
var draw_int := 60.0
var far_begin := 220.0
## Exterior and far meshes, so ViewLod can move the near/far switch when the camera is in the air.
var ext_meshes: Array = []
var far_meshes: Array = []
var far_end := 1900.0
## Test runs only (--autotest=mapscan): every collision box is also kept as [xf, size, what], so a physics contact
## can be named (wall, partition, static prop, loot box, crate...). Off in play; it changes nothing that is built.
var record := false
## Face dump for the z-fighting check (tools/zfight_faces.py): every drawn box face and quad as
## [centre xyz, normal xyz, half-edge u xyz, half-edge v xyz] plus its material and "what". Off unless set.
var dump_faces := false
var _drawn := {}
var faces_dump := PackedFloat32Array()
var faces_names: PackedStringArray = []
var rec: Array = []
var _rec_grid := {}       # Vector2i (4 m cell) -> [index into rec]


func _init(materials, parent: Node3D, seed_value: int = 1) -> void:
	mats = materials
	root = parent
	rng.seed = seed_value


static func chunk_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


func _acc(p: Vector3, mat: String, layer: String) -> Acc:
	var key: String
	if layer == "ext" or layer == "inner":
		key = "w%d,%d|%s|%s" % [floori(p.x / WIDE), floori(p.z / WIDE), mat, layer]
	else:
		var ck := chunk_key(p)
		key = "%d,%d|%s|%s" % [ck.x, ck.y, mat, layer]
	var a: Acc = _meshes.get(key)
	if a == null:
		a = Acc.new()
		_meshes[key] = a
	return a


func _tri(p: Vector3, phys: String) -> TriAcc:
	var ck := chunk_key(p)
	var key := "%d,%d|%s" % [ck.x, ck.y, phys]
	var a: TriAcc = _cols.get(key)
	if a == null:
		a = TriAcc.new()
		_cols[key] = a
	return a


func _faracc(p: Vector3) -> FarAcc:
	var key := "w%d,%d" % [floori(p.x / WIDE), floori(p.z / WIDE)]
	var a: FarAcc = _far.get(key)
	if a == null:
		a = FarAcc.new()
		_far[key] = a
	return a


# ------------------------------------------------------------------ primitives

func box(xf: Transform3D, size: Vector3, mat: String, opt: Dictionary = {}) -> void:
	## Oriented box centred at xf.origin. opt: tint, paint, dirt, base_y, collide (default true), occlude, layer,
	## faces (bitmask +x -x +y -y +z -z = 1,2,4,8,16,32), inner_faces (those of them that face the inside of a
	## building: drawn like exteriors but on the Interior render layer, which the moon skips when it casts no
	## shadows), phys, uv_off, tile.
	stats.boxes += 1
	var h := size * 0.5
	var layer: String = opt.get("layer", "ext")
	var faces: int = opt.get("faces", 63)
	var tint: Color = opt.get("tint", Color(1, 1, 1))
	tint.a = opt.get("paint", 0.0)
	var dirt: float = opt.get("dirt", 0.5)
	var base_y: float = opt.get("base_y", xf.origin.y - h.y)
	var tile: float = opt.get("tile", mats.tile(mat))
	var uvo: Vector2 = opt.get("uv_off", Vector2(rng.randf() * 4.0, rng.randf() * 4.0))
	# A box identical to one already drawn (two generators building the same fence or sheet) is not drawn again:
	# the copies z-fought face for face. The random draws above still happen, so nothing after it shifts.
	# The box as its three edge vectors without their signs (a copy turned 180 degrees is the same box).
	var edges := []
	for ai in 3:
		var ev: Vector3 = xf.basis[ai] * size[ai]
		if ev.x < -1e-4 or (absf(ev.x) <= 1e-4 and (ev.y < -1e-4 or (absf(ev.y) <= 1e-4 and ev.z < 0.0))):
			ev = -ev
		edges.append((ev * 1000.0).round())
	edges.sort()
	var dkey := hash([(xf.origin * 1000.0).round(), edges, mat])
	if _drawn.has(dkey):
		faces = 0
	else:
		_drawn[dkey] = true
	var outer := _acc(xf.origin, mat, layer)
	var inner_faces: int = opt.get("inner_faces", 0)
	var inner: Acc = _acc(xf.origin, mat, "inner") if inner_faces != 0 else null
	var d2 := Vector2(dirt, base_y)
	var bs := xf.basis
	var mirrored := bs.determinant() < 0.0  # a mirroring transform reverses the winding
	for f in FACES:
		if (faces & int(f[3])) == 0:
			continue
		var a: Acc = inner if (inner_faces & int(f[3])) != 0 else outer
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hn: float = absf(n.dot(h))
		var hu: float = absf(u.dot(h))
		var hv: float = absf(v.dot(h))
		var c := n * hn
		var wn := (bs * n).normalized()
		var wu := (bs * u).normalized()
		var wv := (bs * v).normalized()
		var sgn := 1.0 if wn.cross(wu).dot(wv) >= 0.0 else -1.0
		var su := hu * 2.0 / tile
		var sv := hv * 2.0 / tile
		if mirrored:
			a.quad(xf * (c - u * hu - v * hv), xf * (c - u * hu + v * hv), xf * (c + u * hu + v * hv), xf * (c + u * hu - v * hv),
				wn, wu, sgn, uvo, uvo + Vector2(0.0, -sv), uvo + Vector2(su, -sv), uvo + Vector2(su, 0.0), d2, tint)
		else:
			a.quad(xf * (c - u * hu - v * hv), xf * (c + u * hu - v * hv), xf * (c + u * hu + v * hv), xf * (c - u * hu + v * hv),
				wn, wu, sgn, uvo, uvo + Vector2(su, 0.0), uvo + Vector2(su, -sv), uvo + Vector2(0.0, -sv), d2, tint)
		stats.tris += 2
		if dump_faces:
			_dump_face(xf * c, wn, bs * u * hu, bs * v * hv, mat, str(opt.get("what", "")) + ("|in" if a == inner else ""))
	if opt.get("collide", true):
		_col_box(xf, size, opt.get("phys", mats.phys(mat)), str(opt.get("what", mat)))
	if opt.get("occlude", false):
		_occ_box(xf, size)


func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, mat: String, opt: Dictionary = {}) -> void:
	## Free quad. Points go round the edge in either direction; opt.facing (Vector3) says which side is the front
	## (default: the side from which p0..p3 appear clockwise, Godot's front-face winding).
	if opt.has("facing"):
		var nn := (p3 - p0).cross(p1 - p0)
		if nn.dot(opt.facing) < 0.0:
			var tmp := p1
			p1 = p3
			p3 = tmp
	var layer: String = opt.get("layer", "ext")
	var a := _acc((p0 + p2) * 0.5, mat, layer)
	var n := (p3 - p0).cross(p1 - p0).normalized()
	var u := (p1 - p0).normalized()
	var v := u.cross(n).normalized()
	var tile: float = opt.get("tile", mats.tile(mat))
	var uvo: Vector2 = opt.get("uv_off", Vector2.ZERO)
	var tint: Color = opt.get("tint", Color(1, 1, 1))
	tint.a = opt.get("paint", 0.0)
	var d2 := Vector2(opt.get("dirt", 0.4), opt.get("base_y", minf(minf(p0.y, p1.y), minf(p2.y, p3.y))))
	var uvs := []
	for p in [p0, p1, p2, p3]:
		var rel: Vector3 = p - p0
		uvs.append(Vector2(rel.dot(u) / tile + uvo.x, -rel.dot(v) / tile + uvo.y))
	var sgn := 1.0 if n.cross(u).dot(v) >= 0.0 else -1.0
	a.quad(p0, p3, p2, p1, n, u, sgn, uvs[0], uvs[3], uvs[2], uvs[1], d2, tint)
	stats.tris += 2
	if dump_faces:
		_dump_face((p0 + p2) * 0.5, n, (p1 - p0) * 0.5, (p3 - p0) * 0.5, mat, str(opt.get("what", "quad")))
	if opt.get("double", false):
		a.quad(p0, p1, p2, p3, -n, u, -sgn, uvs[0], uvs[1], uvs[2], uvs[3], d2, tint)
		stats.tris += 2
	if opt.get("collide", false):
		if record:
			var qu := p1 - p0
			var qv := p3 - p0
			var qn := qu.cross(qv)
			if qu.length() > 0.001 and qv.length() > 0.001 and qn.length() > 0.0001:
				var bu := qu.normalized()
				var bn := qn.normalized()
				_record(Transform3D(Basis(bu, bn, bu.cross(bn)).orthonormalized(), (p0 + p2) * 0.5), Vector3(qu.length(), 0.04, qv.length()), str(opt.get("what", mat)))
		var ta := _tri(p0, opt.get("phys", mats.phys(mat)))
		ta.tris.append(p0); ta.tris.append(p1); ta.tris.append(p2)
		ta.tris.append(p0); ta.tris.append(p2); ta.tris.append(p3)


func atlas_quad(c: Vector3, right: Vector3, up: Vector3, w: float, h: float, uv: Rect2, mat: String, opt: Dictionary = {}) -> void:
	## A decal quad showing one cell (uv, 0..1) of an atlas texture, upright: `right` is the viewer's right as seen
	## from the front (the side right x up points to). opt: layer (default mid), tint (alpha = opacity).
	var a := _acc(c, mat, opt.get("layer", "mid"))
	var r := right.normalized() * w * 0.5
	var u := up.normalized() * h * 0.5
	var n := right.cross(up).normalized()
	var col: Color = opt.get("tint", Color(1, 1, 1, 1))
	var d2 := Vector2(0.0, c.y - h * 0.5)
	a.quad(c - r - u, c + r - u, c + r + u, c - r + u, n, right.normalized(), 1.0,
		Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position, d2, col)
	stats.tris += 2


func corrugated(xf: Transform3D, length: float, width: float, mat: String, opt: Dictionary = {}) -> void:
	## A corrugated sheet in the local XZ plane (ridges along local Z). Drawn as a thin slab: the photographed
	## corrugation normal map carries the profile, which keeps thousands of roofs cheap.
	var o := opt.duplicate()
	if not o.has("faces"):
		o.faces = 4 | 8 | 16 | 32  # top, bottom, both eaves
	if not o.has("collide"):
		o.collide = true
	o.phys = o.get("phys", "sheet_metal")
	box(xf, Vector3(width, 0.012, length), mat, o)


func cylinder(base_pos: Vector3, axis: Vector3, length: float, radius: float, mat: String, opt: Dictionary = {}) -> void:
	var layer: String = opt.get("layer", "ext")
	var a := _acc(base_pos, mat, layer)
	var sides: int = opt.get("sides", 8)
	var ax := axis.normalized()
	var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
	var side := ax.cross(ref).normalized()
	var up := side.cross(ax).normalized()
	var tint: Color = opt.get("tint", Color(1, 1, 1))
	tint.a = opt.get("paint", 0.0)
	var tile: float = mats.tile(mat)
	var d2 := Vector2(opt.get("dirt", 0.4), base_pos.y)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		var dm := (d0 + d1).normalized()
		var u0 := float(i) * TAU * radius / sides / tile
		var u1 := float(i + 1) * TAU * radius / sides / tile
		var tg := ax.cross(dm).normalized()
		a.quad(base_pos + d0 * radius, base_pos + d0 * radius + ax * length, base_pos + d1 * radius + ax * length, base_pos + d1 * radius,
			dm, tg, 1.0, Vector2(u0, 0), Vector2(u0, -length / tile), Vector2(u1, -length / tile), Vector2(u1, 0), d2, tint)
		stats.tris += 2
	if opt.get("collide", false):
		var mid := base_pos + ax * length * 0.5
		_col_box(Transform3D(Basis(side, ax, side.cross(ax)).orthonormalized(), mid), Vector3(radius * 1.7, length, radius * 1.7), opt.get("phys", mats.phys(mat)), str(opt.get("what", mat)))


func far_block(xf: Transform3D, size: Vector3, col: Color, top_col: Color) -> void:
	## Coarse stand-in for a whole building (or floor) seen from far away. No bottom face.
	var a := _faracc(xf.origin)
	var h := size * 0.5
	var bs := xf.basis
	for f in FACES:
		if int(f[3]) == 8:
			continue
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var hn: float = absf(n.dot(h))
		var hu: float = absf(u.dot(h))
		var hv: float = absf(v.dot(h))
		var c := n * hn
		var shade := 0.75 + 0.25 * (bs * n).normalized().dot(Vector3(0.3, 0.8, 0.5).normalized())
		var cc := top_col if int(f[3]) == 4 else col * Color(shade, shade, shade)
		if bs.determinant() < 0.0:
			a.quad(xf * (c - u * hu - v * hv), xf * (c - u * hu + v * hv), xf * (c + u * hu + v * hv), xf * (c + u * hu - v * hv), (bs * n).normalized(), cc)
		else:
			a.quad(xf * (c - u * hu - v * hv), xf * (c + u * hu - v * hv), xf * (c + u * hu + v * hv), xf * (c - u * hu + v * hv), (bs * n).normalized(), cc)
		stats.far_tris += 2


func _col_box(xf: Transform3D, size: Vector3, phys: String, what: String = "") -> void:
	if record:
		_record(xf, size, what if what != "" else phys)
	var ta := _tri(xf.origin, phys)
	var h := size * 0.5
	var c := []
	for i in 8:
		c.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		ta.tris.append(c[q[0]]); ta.tris.append(c[q[1]]); ta.tris.append(c[q[2]])
		ta.tris.append(c[q[0]]); ta.tris.append(c[q[2]]); ta.tris.append(c[q[3]])


func col_box(xf: Transform3D, size: Vector3, phys: String, what: String = "") -> void:
	## Invisible collision (ramps under steps, clipping blockers).
	_col_box(xf, size, phys, what)


func _dump_face(c: Vector3, n: Vector3, eu: Vector3, ev: Vector3, mat: String, what: String) -> void:
	faces_dump.append_array(PackedFloat32Array([c.x, c.y, c.z, n.x, n.y, n.z, eu.x, eu.y, eu.z, ev.x, ev.y, ev.z]))
	faces_names.append(mat + "|" + what)


func save_faces(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_32(faces_names.size())
	f.store_buffer(faces_dump.to_byte_array())
	f.close()
	var g := FileAccess.open(path + ".names", FileAccess.WRITE)
	g.store_string("
".join(faces_names))
	g.close()


func _record(xf: Transform3D, size: Vector3, what: String) -> void:
	var i := rec.size()
	rec.append([xf, size, what])
	var r := (size * 0.5).length()
	for cx in range(floori((xf.origin.x - r) / 4.0), floori((xf.origin.x + r) / 4.0) + 1):
		for cz in range(floori((xf.origin.z - r) / 4.0), floori((xf.origin.z + r) / 4.0) + 1):
			var k := Vector2i(cx, cz)
			if not _rec_grid.has(k):
				_rec_grid[k] = []
			_rec_grid[k].append(i)


func recorded_at(p: Vector3, margin: float = 0.04) -> Array:
	## Recorded collision boxes containing p (grown by margin), smallest first: [[xf, size, what], ...].
	var out := []
	for i in _rec_grid.get(Vector2i(floori(p.x / 4.0), floori(p.z / 4.0)), []):
		var e: Array = rec[i]
		var lp: Vector3 = (e[0] as Transform3D).affine_inverse() * p
		var h: Vector3 = (e[1] as Vector3) * 0.5 + Vector3.ONE * margin
		if absf(lp.x) <= h.x and absf(lp.y) <= h.y and absf(lp.z) <= h.z:
			out.append(e)
	out.sort_custom(func(a, b): return (a[1] as Vector3).x * (a[1] as Vector3).y * (a[1] as Vector3).z < (b[1] as Vector3).x * (b[1] as Vector3).y * (b[1] as Vector3).z)
	return out


func recorded_near(p: Vector3) -> Array:
	## Recorded boxes listed in p's 4 m cell: [[xf, size, what], ...].
	var out := []
	for i in _rec_grid.get(Vector2i(floori(p.x / 4.0), floori(p.z / 4.0)), []):
		out.append(rec[i])
	return out


func _occ_box(xf: Transform3D, size: Vector3) -> void:
	var ck := chunk_key(xf.origin)
	var key := "%d,%d" % [ck.x, ck.y]
	var o: FarAcc = _occ.get(key)
	if o == null:
		o = FarAcc.new()
		_occ[key] = o
	var h := size * 0.5 * 0.97
	var base := o.v.size()
	for i in 8:
		o.v.append(xf * Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		o.i.append(base + q[0]); o.i.append(base + q[1]); o.i.append(base + q[2])
		o.i.append(base + q[0]); o.i.append(base + q[2]); o.i.append(base + q[3])


# ------------------------------------------------------------------ output

func finish() -> void:
	var chunks := {}
	for key in _meshes:
		var parts: PackedStringArray = key.split("|")
		var a: Acc = _meshes[key]
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
		var layer := parts[2]
		if layer == "mid":
			mi.visibility_range_end = 140.0
			mi.visibility_range_end_margin = 15.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if parts[1].begins_with("decal:") or parts[1] == "puddle":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif layer == "inner":
			# Inside faces of outer walls, floors and ceilings: drawn as far as exteriors (seen through windows and
			# doors), on the Interior layer.
			mi.layers = Defs.RENDER_INTERIOR
			mi.visibility_range_end = draw_ext
			mi.visibility_range_end_margin = 30.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			ext_meshes.append(mi)
		elif layer == "int":
			mi.layers = Defs.RENDER_INTERIOR
			mi.visibility_range_end = draw_int
			mi.visibility_range_end_margin = 8.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		else:
			mi.visibility_range_end = draw_ext
			mi.visibility_range_end_margin = 30.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			ext_meshes.append(mi)
		_chunk_node(chunks, parts[0]).add_child(mi)
		stats.meshes += 1
	var far_mat := StandardMaterial3D.new()
	far_mat.vertex_color_use_as_albedo = true
	far_mat.roughness = 0.95
	for key in _far:
		var f: FarAcc = _far[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = f.v
		arrays[Mesh.ARRAY_NORMAL] = f.n
		arrays[Mesh.ARRAY_COLOR] = f.c
		arrays[Mesh.ARRAY_INDEX] = f.i
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, far_mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visibility_range_begin = far_begin
		mi.visibility_range_begin_margin = 30.0
		mi.visibility_range_end = far_end
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		far_meshes.append(mi)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_chunk_node(chunks, key).add_child(mi)
	for key in _cols:
		var parts: PackedStringArray = key.split("|")
		var ta: TriAcc = _cols[key]
		if ta.tris.is_empty():
			continue
		var body := StaticBody3D.new()
		body.collision_layer = Defs.PHYS_BLOCKER if parts[1] == "blocker" else Defs.PHYS_WORLD
		body.collision_mask = 0
		body.set_meta("mat", parts[1])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(ta.tris)
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		_chunk_node(chunks, parts[0]).add_child(body)
		stats.colliders += 1
	for key in _occ:
		var o: FarAcc = _occ[key]
		var occ := ArrayOccluder3D.new()
		occ.set_arrays(o.v, o.i)
		var oi := OccluderInstance3D.new()
		oi.occluder = occ
		_chunk_node(chunks, key).add_child(oi)
	_meshes.clear()
	_cols.clear()
	_occ.clear()
	_far.clear()


func _chunk_node(chunks: Dictionary, key: String) -> Node3D:
	if chunks.has(key):
		return chunks[key]
	var n := Node3D.new()
	n.name = "Chunk_" + key.replace(",", "_")
	root.add_child(n)
	chunks[key] = n
	return n
