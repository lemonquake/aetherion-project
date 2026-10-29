"""r4: doors and shutters lose panels where they are shot, then fall off their hinges."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
f = 'src/world/door.gd'
patch(f, '''const SPEED := 2.6''', '''const Destruct := preload("res://src/world/destruct.gd")

const SPEED := 2.6''')
patch(f, '''var _blocked_t := 0.0
var _solid := true
var _sync_t := 0.0
''', '''var _blocked_t := 0.0
var _solid := true
var _sync_t := 0.0
## Damage: panels shot out of the leaf (index -> true), the leaf gone altogether, the node that follows the leaf once
## something hangs on it (holes, the damaged leaf), each panel's remaining strength (server).
var lost := {}
var destroyed := false
var anchor: Node3D = null
var _panels: Array = []
var _panel_hp := {}
var _panel_shapes: Array = []
var _damaged_mi: MeshInstance3D = null
''')
patch(f, '''func free_body() -> void:
	if body.is_valid():
		PhysicsServer3D.free_rid(body)
		PhysicsServer3D.free_rid(shape)
	body = RID()
''', '''func free_body() -> void:
	if body.is_valid():
		PhysicsServer3D.free_rid(body)
		PhysicsServer3D.free_rid(shape)
	for s in _panel_shapes:
		PhysicsServer3D.free_rid(s)
	_panel_shapes.clear()
	body = RID()
''')
patch(f, '''func _apply() -> void:
	var xf := current_transform()
	if body.is_valid():''', '''func _apply() -> void:
	if destroyed:
		return
	var xf := current_transform()
	if anchor:
		anchor.global_transform = xf
	if body.is_valid():''')
patch(f, '''	dyn.set_leaf_transform(mm_key, mm_index, xf * Transform3D(Basis().scaled(Vector3(w, h, t)), Vector3(w * 0.5, h * 0.5, 0)))
	if spec.has("portal") and dyn.map:''', '''	if lost.is_empty():
		dyn.set_leaf_transform(mm_key, mm_index, xf * Transform3D(Basis().scaled(Vector3(w, h, t)), Vector3(w * 0.5, h * 0.5, 0)))
	if spec.has("portal") and dyn.map:''')
patch(f, '''	if locked or is_shutter or (not free and absf(angle) <= OPEN_PASS and absf(target) < 0.05):
		return false''', '''	if destroyed or locked or is_shutter or (not free and absf(angle) <= OPEN_PASS and absf(target) < 0.05):
		return false''')
patch(f, '''func tick(dt: float) -> void:
	if not moving:
		return''', '''func tick(dt: float) -> void:
	if not moving or destroyed:
		moving = false
		return''')

ADD = '''

# ------------------------------------------------------------------ damage (panels shot out, then the whole leaf)

func panels() -> Array:
	if _panels.is_empty():
		_panels = Destruct.door_panels(id, w, h)
	return _panels


func anchor_node() -> Node3D:
	## A node that follows the leaf: bullet holes and the damaged leaf hang on it. Made on first use.
	if anchor == null or not is_instance_valid(anchor):
		anchor = Node3D.new()
		anchor.name = "Leaf%d" % id
		anchor.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		dyn.root.add_child(anchor)
		anchor.global_transform = current_transform()
	return anchor


func panel_strength() -> float:
	## Damage a panel takes before it is shot out (a 9 mm round does about 40, a rifle round 150 or more).
	var m := "planks_paint" if is_shutter else str(spec.get("mat", "plywood"))
	if m.contains("metal") or m.contains("steel") or m.contains("iron"):
		return 170.0
	if m.contains("plywood"):
		return 45.0
	return 70.0


func server_damage(at: Vector3, amount: float) -> int:
	## A hit on the leaf at a world point. Returns the panel shot out by it, or -1 if the panel held.
	if destroyed:
		return -1
	var local := current_transform().affine_inverse() * at
	var i := Destruct.door_panel_at(panels(), lost, Vector2(local.x, local.y))
	if i < 0:
		return -1
	var hp := float(_panel_hp.get(i, panel_strength())) - amount
	_panel_hp[i] = hp
	return i if hp <= 0.0 else -1


func lose_panel(i: int) -> bool:
	## Panel i is gone (server and clients alike). Returns true when that brought the whole leaf down.
	if destroyed or lost.has(i):
		return false
	lost[i] = true
	if Destruct.door_collapses(panels(), lost):
		destroy()
		return true
	_rebuild()
	return false


func panel_box(i: int) -> AABB:
	var r: Rect2 = panels()[i]
	return AABB(Vector3(r.position.x, r.position.y, -t * 0.5), Vector3(r.size.x, r.size.y, t))


func _rebuild() -> void:
	## The shared instance goes; the panels still standing are drawn on the anchor, and the leaf's collision becomes
	## one box per standing panel (rounds and eyes pass through the holes).
	dyn.set_leaf_transform(mm_key, mm_index, Transform3D(Basis().scaled(Vector3.ZERO), base.origin))
	if body.is_valid():
		PhysicsServer3D.body_clear_shapes(body)
		for s in _panel_shapes:
			PhysicsServer3D.free_rid(s)
		_panel_shapes.clear()
		for i in panels().size():
			if lost.has(i):
				continue
			var bx := panel_box(i)
			var sh := PhysicsServer3D.box_shape_create()
			PhysicsServer3D.shape_set_data(sh, bx.size * 0.5)
			PhysicsServer3D.body_add_shape(body, sh, Transform3D(Basis(), bx.get_center()))
			_panel_shapes.append(sh)
	if DisplayServer.get_name() == "headless":
		return
	var an := anchor_node()
	if _damaged_mi == null:
		_damaged_mi = MeshInstance3D.new()
		an.add_child(_damaged_mi)
	_damaged_mi.mesh = _panel_mesh()
	_apply()


func _panel_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	var cols := Destruct.DOOR_COLS
	var rows := Destruct.DOOR_ROWS
	for i in panels().size():
		if lost.has(i):
			continue
		var bx := panel_box(i)
		_leaf_box(st, bx)
		# Splinters along every edge that borders a shot-out panel.
		var c := i / rows
		var r := i % rows
		rng.seed = hash(id * 131 + i)
		for nb in [[c - 1, r, Vector3.LEFT], [c + 1, r, Vector3.RIGHT], [c, r - 1, Vector3.DOWN], [c, r + 1, Vector3.UP]]:
			if int(nb[0]) < 0 or int(nb[0]) >= cols or int(nb[1]) < 0 or int(nb[1]) >= rows or not lost.has(int(nb[0]) * rows + int(nb[1])):
				continue
			var dir: Vector3 = nb[2]
			var along := Vector3(absf(dir.y), absf(dir.x), 0)
			var edge_c := bx.get_center() + dir * Vector3(bx.size.x * 0.5, bx.size.y * 0.5, 0)
			var span := absf(along.dot(bx.size))
			for k in rng.randi_range(3, 6):
				var off := along * rng.randf_range(-0.45, 0.45) * span
				var ln := rng.randf_range(0.02, 0.07)
				var wd := rng.randf_range(0.008, 0.025)
				var sz := along * wd + dir.abs() * ln + Vector3(0, 0, t * rng.randf_range(0.3, 0.9))
				_leaf_box(st, AABB(edge_c + off + dir * ln * 0.5 - sz * 0.5, sz))
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, dyn.mats.get_material("planks_paint" if is_shutter else str(spec.get("mat", "plywood"))))
	return m


func _leaf_box(st: SurfaceTool, bx: AABB) -> void:
	## A box in the leaf's own space, textured as the intact leaf is (the face texture spans the whole leaf).
	var lo := bx.position
	var hi := bx.end
	var faces := [[Vector3(0, 0, 1), 2, 0, 1], [Vector3(0, 0, -1), 2, 0, 1], [Vector3(1, 0, 0), 0, 2, 1],
		[Vector3(-1, 0, 0), 0, 2, 1], [Vector3(0, 1, 0), 1, 0, 2], [Vector3(0, -1, 0), 1, 0, 2]]
	for f in faces:
		var n: Vector3 = f[0]
		var ax: int = f[1]
		var ua: int = f[2]
		var va: int = f[3]
		var fixed := hi[ax] if n[ax] > 0.0 else lo[ax]
		var pts: Array = []
		for q in [[0, 0], [1, 0], [1, 1], [0, 1]]:
			var p := Vector3()
			p[ax] = fixed
			p[ua] = lo[ua] if q[0] == 0 else hi[ua]
			p[va] = lo[va] if q[1] == 0 else hi[va]
			pts.append(p)
		# Godot draws clockwise triangles as front faces: wind each face so it faces outward.
		var order := [0, 1, 2, 0, 2, 3]
		var e1: Vector3 = pts[1] - pts[0]
		var e2: Vector3 = pts[2] - pts[0]
		if e1.cross(e2).dot(n) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for k in order:
			var p2: Vector3 = pts[k]
			st.set_normal(n)
			var uv := Vector2(p2.x / w, 1.0 - p2.y / h)
			if n.z < 0.0:
				uv.x = 1.0 - uv.x
			st.set_uv(uv)
			st.add_vertex(p2)


func destroy() -> void:
	## The leaf falls off its hinges: the doorway is open for good.
	destroyed = true
	moving = false
	free = false
	locked = false
	dyn.set_leaf_transform(mm_key, mm_index, Transform3D(Basis().scaled(Vector3.ZERO), base.origin))
	free_body()
	if _damaged_mi and is_instance_valid(_damaged_mi):
		_damaged_mi.queue_free()
		_damaged_mi = null
	if spec.has("portal") and dyn.map:
		dyn.map.acoustics.set_portal_open(int(spec.portal), 1.0)
'''
b = open(f, 'rb').read()
crlf = b'\r\n' in b
s = b.decode('utf-8').rstrip('\r\n')
s += ADD.replace('\n', '\r\n') if crlf else ADD
open(f, 'wb').write(s.encode('utf-8'))
print('appended damage section')
