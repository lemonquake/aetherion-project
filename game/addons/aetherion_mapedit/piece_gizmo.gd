@tool
extends EditorNode3DGizmoPlugin
## (r26) Map pieces in the 3D view: clicking a piece's surface selects it (its brushes are its collision), a thin
## outline shows its brushes (bright when selected), and orange handles resize it: a wall's two ends (snapped to 5 cm,
## Shift: 1 cm) and its height; a box's width, height and depth; a floor's width and depth; the rise of stairs and
## ramps and a ramp's length. Each drag is one undo step.

const MapDoc := preload("res://src/world/maps/authored/map_doc.gd")
const MapPiece := preload("res://addons/aetherion_mapedit/map_piece.gd")

var undo: EditorUndoRedoManager = null


func _init() -> void:
	create_material("outline", Color(1.0, 1.0, 1.0, 0.18))
	create_material("selected", Color(1.0, 0.75, 0.15, 0.95))
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "AetherionMapPiece"


func _has_gizmo(node: Node3D) -> bool:
	return node.get_script() == MapPiece


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var n = gizmo.get_node_3d()
	var sel := EditorInterface.get_selection().get_selected_nodes().has(n)
	var lines := PackedVector3Array()
	var tris := PackedVector3Array()
	var brs: Array = n.local_brushes()
	if brs.is_empty():
		var ab: AABB = MapDoc.bounds_local(n.data)
		for i in 12:
			var e := _box_edge(ab, i)
			lines.append(e[0])
			lines.append(e[1])
		var bm := BoxMesh.new()
		bm.size = ab.size
		for v in bm.get_faces():
			tris.append(v + ab.get_center())
	else:
		for br in brs:
			for poly in MapDoc.face_polys(br):
				for k in poly.size():
					lines.append(poly[k])
					lines.append(poly[(k + 1) % poly.size()])
				for k in range(1, poly.size() - 1):
					tris.append(poly[0])
					tris.append(poly[k])
					tris.append(poly[k + 1])
	gizmo.add_lines(lines, get_material("selected" if sel else "outline", gizmo))
	if tris.size() >= 3:
		var tm := TriangleMesh.new()
		tm.create_from_faces(tris)
		gizmo.add_collision_triangles(tm)
	if sel:
		var hs := _handles(n)
		if not hs.is_empty():
			gizmo.add_handles(PackedVector3Array(hs), get_material("handles", gizmo), [])


static func _box_edge(ab: AABB, i: int) -> Array:
	var a := ab.position
	var b := ab.end
	var c := [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z)]
	var e := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	return [c[e[i][0]], c[e[i][1]]]


func _handles(n) -> Array:
	## Handle positions in the piece's frame.
	var d: Dictionary = n.data
	match str(d.get("type", "")):
		"wall":
			var ln := MapDoc.wall_len(d)
			var h := float(d.get("h", 3.0))
			return [Vector3(-ln * 0.5, 0.05, 0), Vector3(ln * 0.5, 0.05, 0), Vector3(0, h, 0)]
		"box":
			var s := MapDoc.v3(d.get("size"), Vector3(2, 2, 2))
			return [Vector3(s.x * 0.5, s.y * 0.5, 0), Vector3(0, s.y, 0), Vector3(0, s.y * 0.5, s.z * 0.5)]
		"floor":
			var s2 := MapDoc.v2(d.get("size"), Vector2(4, 4))
			return [Vector3(s2.x * 0.5, 0, 0), Vector3(0, 0, s2.y * 0.5)]
		"stairs":
			var st := MapDoc.stair_steps(d)
			return [Vector3(0, st.rise, -(st.n - 1) * st.run)]
		"ramp":
			return [Vector3(0, float(d.get("rise", 1.0)), -float(d.get("len", 4.0))), Vector3(0, 0, -float(d.get("len", 4.0)))]
	return []


func _get_handle_name(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	var t := str(gizmo.get_node_3d().data.get("type", ""))
	var names := {"wall": ["from", "to", "height"], "box": ["width", "height", "depth"], "floor": ["width", "depth"],
		"stairs": ["rise"], "ramp": ["rise", "length"]}
	var arr: Array = names.get(t, [])
	return str(arr[id]) if id < arr.size() else ""


func _get_handle_value(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool) -> Variant:
	return gizmo.get_node_3d().data.duplicate(true)


func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var n = gizmo.get_node_3d()
	var d: Dictionary = n.data.duplicate(true)
	var gx: Transform3D = n.global_transform
	var inv := gx.affine_inverse()
	var ro: Vector3 = inv * camera.project_ray_origin(screen_pos)
	var rd: Vector3 = inv.basis * camera.project_ray_normal(screen_pos)
	var fine := Input.is_key_pressed(KEY_SHIFT)
	var snap := 0.01 if fine else 0.05
	var t := str(d.get("type", ""))
	match t:
		"wall":
			if id <= 1:
				# the end follows the mouse on the wall's base plane (world), the other end stays
				var wo: Vector3 = camera.project_ray_origin(screen_pos)
				var wd: Vector3 = camera.project_ray_normal(screen_pos)
				var y := float(d.get("y", 0.0))
				if absf(wd.y) < 1e-4:
					return
				var k := (y - wo.y) / wd.y
				if k <= 0.0:
					return
				var p := wo + wd * k
				d["from" if id == 0 else "to"] = [snappedf(p.x, snap), snappedf(p.z, snap)]
			else:
				d.h = maxf(0.05, snappedf(_along(Vector3.ZERO, Vector3.UP, ro, rd), snap))
		"box":
			var s := MapDoc.v3(d.get("size"), Vector3(2, 2, 2))
			if id == 0:
				s.x = maxf(0.02, snappedf(_along(Vector3(0, s.y * 0.5, 0), Vector3.RIGHT, ro, rd) * 2.0, snap))
			elif id == 1:
				s.y = maxf(0.02, snappedf(_along(Vector3.ZERO, Vector3.UP, ro, rd), snap))
			else:
				s.z = maxf(0.02, snappedf(_along(Vector3(0, s.y * 0.5, 0), Vector3.BACK, ro, rd) * 2.0, snap))
			d.size = [s.x, s.y, s.z]
		"floor":
			var s2 := MapDoc.v2(d.get("size"), Vector2(4, 4))
			if id == 0:
				s2.x = maxf(0.05, snappedf(_along(Vector3.ZERO, Vector3.RIGHT, ro, rd) * 2.0, snap))
			else:
				s2.y = maxf(0.05, snappedf(_along(Vector3.ZERO, Vector3.BACK, ro, rd) * 2.0, snap))
			d.size = [s2.x, s2.y]
		"stairs":
			var st := MapDoc.stair_steps(d)
			d.rise = maxf(0.2, snappedf(_along(Vector3(0, 0, -(st.n - 1) * st.run), Vector3.UP, ro, rd), snap))
		"ramp":
			if id == 0:
				d.rise = maxf(0.05, snappedf(_along(Vector3(0, 0, -float(d.get("len", 4.0))), Vector3.UP, ro, rd), snap))
			else:
				d.len = maxf(0.2, snappedf(_along(Vector3.ZERO, Vector3.FORWARD, ro, rd), snap))
	n.data = d
	n._dirty()


static func _along(p0: Vector3, axis: Vector3, ro: Vector3, rd: Vector3) -> float:
	## How far along the line p0 + s * axis lies the point nearest the ray (ro, rd).
	var w0 := p0 - ro
	var a := axis.dot(axis)
	var b := axis.dot(rd)
	var c := rd.dot(rd)
	var dd := axis.dot(w0)
	var e := rd.dot(w0)
	var den := a * c - b * b
	if absf(den) < 1e-9:
		return 0.0
	return (b * e - c * dd) / den


func _commit_handle(gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var n = gizmo.get_node_3d()
	if cancel:
		n.data = restore
		return
	if undo == null:
		return
	undo.create_action("Resize %s" % str(n.name))
	undo.add_do_property(n, "data", n.data.duplicate(true))
	undo.add_undo_property(n, "data", restore)
	undo.add_do_method(n, "_dirty")
	undo.add_undo_method(n, "_dirty")
	undo.commit_action(false)
