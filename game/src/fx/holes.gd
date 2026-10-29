extends Node3D
## Bullet holes, exit spall and blast marks: small cards laid on the surface that was hit, drawn from one atlas
## (tools/make_impact_textures.py) through MultiMeshes, so hundreds of holes cost a few draw calls and work on every
## renderer (Decal nodes do not exist on the OpenGL fallback). Marks on things that move (doors, props) go into a
## small MultiMesh parented to that object: they swing and tumble with it, and go with the chunk they were on.
## The oldest mark is removed once the budget (by quality) is used up.

const CELL := 48.0
const WORLD_CAP := 192     # marks per world cell set
const OBJ_CAP := 40        # marks per moving object
const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_disable;
varying float v_alpha;
varying vec3 v_tint;
void vertex() {
	float c = INSTANCE_CUSTOM.x;
	vec2 cell = vec2(mod(c, 4.0), floor(c / 4.0));
	UV = (cell + UV) * 0.25;
	v_alpha = INSTANCE_CUSTOM.y;
	// Collision surfaces can sit a few centimetres behind the drawn ones (plank tops, wall cladding): pull the card
	// toward the eye along its own view ray, which keeps its place on screen but lets it win the depth test.
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= max(1.0 - 0.06 / max(length(vp.xyz), 0.1), 0.2);
	POSITION = PROJECTION_MATRIX * vp;
	v_tint = vec3(INSTANCE_CUSTOM.z);
}
void fragment() {
	vec4 a = texture(albedo_tex, UV);
	vec4 n = texture(normal_tex, UV);
	ALBEDO = a.rgb * v_tint;
	ALPHA = a.a * v_alpha;
	NORMAL_MAP = n.rgb;
	ROUGHNESS = n.a;
	SPECULAR = 0.35;
}
"""
## Atlas cells (see the tool): which mark each material leaves, entry and exit.
const CELLS := {
	"concrete": [[0, 1], [2]], "default": [[0, 1], [2]], "hollow_block": [[15], [2]], "plaster": [[3], [3]],
	"wood": [[4, 5], [6]], "plywood": [[4, 5], [6]], "sheet_metal": [[7, 8], [9]], "steel": [[7, 8], [9]],
	"glass": [[10], [10]], "fabric": [[11], [11]], "plastic": [[11], [11]], "dirt": [[12], [12]], "sand": [[12], [12]],
	"tile": [[13], [13]],
}
## Card size in metres: the crater, dust ring and cracks around a hole about a centimetre across.
const SIZE := {"concrete": 0.14, "default": 0.14, "hollow_block": 0.14, "plaster": 0.13, "wood": 0.11, "plywood": 0.11,
	"sheet_metal": 0.08, "steel": 0.07, "glass": 0.26, "fabric": 0.07, "plastic": 0.08, "dirt": 0.15, "sand": 0.15, "tile": 0.13}

var mat: ShaderMaterial
var quad: QuadMesh
var budget := 400
var count := 0
var _sets := {}      # key -> {node: MultiMeshInstance3D, mm: MultiMesh, cap, free: Array, top}
var _order: Array = []   # [set key, index] oldest first
var _rng := RandomNumberGenerator.new()
var _obj_keys := {}  # instance id of the object node -> set key
var world_cap := WORLD_CAP
var obj_cap := OBJ_CAP
var world_range := 90.0
var _serial := 0
var _serials := {}   # "key:index" -> serial of the mark there now (so a handle can tell it was recycled)


func setup() -> void:
	_rng.randomize()
	budget = 160 if Settings.is_mobile() else 450
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("albedo_tex", load("res://assets/fx/holes_albedo.png"))
	mat.set_shader_parameter("normal_tex", load("res://assets/fx/holes_normal.png"))
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat


func _new_set(key: String, parent: Node3D, cap: int, range_end: float, box: AABB = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	# Marks are placed from _process: with physics interpolation on, the MultiMesh would draw stale (empty) buffers.
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = Defs.RENDER_WORLD | Defs.RENDER_INTERIOR
	# Unused instances sit at the origin until a mark takes them: a fixed box keeps culling and the draw distance
	# about this cell (or this object), not the whole map.
	mi.custom_aabb = box
	if range_end > 0.0:
		mi.visibility_range_end = range_end
	(parent if parent else self).add_child(mi)
	if parent == null:
		mi.global_transform = Transform3D()
	var s := {"node": mi, "mm": mm, "cap": cap, "free": [], "top": 0, "key": key}
	_sets[key] = s
	return s


func add(pos: Vector3, normal: Vector3, mat_id: String, exit: bool = false, on: Node3D = null, size_mult: float = 1.0) -> void:
	## A hole where a round went in (or came out, exit = true) of a surface of material mat_id. on: the moving object
	## it belongs to (door anchor or prop body), else the static world.
	var cells: Array = CELLS.get(mat_id, CELLS["default"])[1 if exit else 0]
	var c: int = cells[_rng.randi() % cells.size()]
	var sz := float(SIZE.get(mat_id, 0.07)) * (1.7 if exit and mat_id not in ["glass", "fabric", "plastic"] else 1.0) * size_mult
	sz *= _rng.randf_range(0.85, 1.2)
	_place(pos, normal, c, sz, 1.0, on)


func add_mark(pos: Vector3, normal: Vector3, cell: int, size: float, alpha: float = 1.0, on: Node3D = null) -> void:
	_place(pos, normal, cell, size, alpha, on)


func _place(pos: Vector3, normal: Vector3, c: int, sz: float, alpha: float, on: Node3D) -> void:
	var n := normal.normalized()
	var ref := Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD
	var x := ref.cross(n).normalized()
	var y := n.cross(x).normalized()
	var b := Basis(x, y, n) * Basis(Vector3(0, 0, 1), _rng.randf() * TAU)
	place_xf(Transform3D(b.scaled(Vector3(sz, sz, sz)), pos + n * 0.004), Color(float(c), alpha, _rng.randf_range(0.85, 1.05), 0.0), on)


func place_xf(xf: Transform3D, custom: Color, on: Node3D = null) -> Array:
	## One card with world transform xf (the quad lies in its XY plane and faces +Z; image right = +X, image down =
	## -Y) and per-mark data custom (x atlas cell, y alpha, z tint). Returns a handle for set_mark_xf, or [].
	var pos := xf.origin
	var s: Dictionary
	if on != null and is_instance_valid(on):
		var oid := on.get_instance_id()
		var ok: String = _obj_keys.get(oid, "")
		if ok == "" or not _sets.has(ok) or not is_instance_valid(_sets[ok].node):
			ok = "o%d" % oid
			_obj_keys[oid] = ok
			s = _new_set(ok, on, obj_cap, 0.0)
		else:
			s = _sets[ok]
	else:
		var ck := Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))
		var key := "w%d,%d" % [ck.x, ck.y]
		s = _sets[key] if _sets.has(key) else _new_set(key, null, world_cap, world_range, AABB(Vector3(ck.x * CELL, -40.0, ck.y * CELL), Vector3(CELL, 160.0, CELL)))
	var idx := -1
	if not s.free.is_empty():
		idx = s.free.pop_back()
	elif int(s.top) < int(s.cap):
		idx = s.top
		s.top = int(s.top) + 1
		(s.mm as MultiMesh).visible_instance_count = s.top
	else:
		_remove_oldest_in(s)
		if s.free.is_empty():
			return []
		idx = s.free.pop_back()
	if on != null and is_instance_valid(on):
		xf = on.global_transform.affine_inverse() * xf
	var mm: MultiMesh = s.mm
	mm.set_instance_transform(idx, xf)
	mm.set_instance_custom_data(idx, custom)
	_order.append([s.key, idx])
	_serial += 1
	_serials["%s:%d" % [s.key, idx]] = _serial
	count += 1
	while count > budget and not _order.is_empty():
		_remove(_order.pop_front())
	return [s.key, idx, _serial]


func set_mark_xf(handle: Array, xf: Transform3D) -> bool:
	## Moves a mark placed in the static world (handle from place_xf); false once it has been recycled.
	if handle.is_empty() or int(_serials.get("%s:%d" % [handle[0], handle[1]], -1)) != int(handle[2]):
		return false
	var s: Dictionary = _sets.get(handle[0], {})
	if s.is_empty() or not is_instance_valid(s.node):
		return false
	(s.mm as MultiMesh).set_instance_transform(int(handle[1]), xf)
	return true


func _remove_oldest_in(s: Dictionary) -> void:
	for i in _order.size():
		if _order[i][0] == s.key:
			_remove(_order[i])
			_order.remove_at(i)
			return


func _remove(e: Array) -> void:
	var s: Dictionary = _sets.get(e[0], {})
	count -= 1
	_serials.erase("%s:%d" % [e[0], e[1]])
	if s.is_empty() or not is_instance_valid(s.node):
		return
	(s.mm as MultiMesh).set_instance_transform(int(e[1]), Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	s.free.append(int(e[1]))


func clear_box(on: Node3D, box: AABB) -> void:
	## Marks on `on` inside box (its own space) go: the chunk or panel they were on has been knocked off.
	if on == null:
		return
	var ok: String = _obj_keys.get(on.get_instance_id(), "")
	if ok == "" or not _sets.has(ok):
		return
	var s: Dictionary = _sets[ok]
	var mm: MultiMesh = s.mm
	var keep: Array = []
	for e in _order:
		if e[0] == ok and box.has_point(mm.get_instance_transform(int(e[1])).origin):
			_remove(e)
		else:
			keep.append(e)
	_order = keep


func forget(on: Node3D) -> void:
	## The object is gone (destroyed door, broken prop): its marks go with it.
	if on == null:
		return
	var ok: String = _obj_keys.get(on.get_instance_id(), "")
	if ok == "" or not _sets.has(ok):
		return
	if is_instance_valid(_sets[ok].node):
		_sets[ok].node.queue_free()
	var keep: Array = []
	for e in _order:
		if e[0] == ok:
			count -= 1
		else:
			keep.append(e)
	_order = keep
	_sets.erase(ok)
	_obj_keys.erase(on.get_instance_id())
