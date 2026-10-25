extends RefCounted
## Everything in the map that changes during a match: doors, shutters, windows, curtains, movable props, loose
## items, loot containers and corpses. Static geometry lives in GeoSink; this keeps per-object state, nodes and
## replication. The server owns all state; clients mirror it through the World RPCs (map_* methods).

const Door := preload("res://src/world/door.gd")
const PhysicsProp := preload("res://src/props/physics_prop.gd")
const Corpse := preload("res://src/props/corpse.gd")

class Ref:
	extends RefCounted
	## Lets raycasts against node-less physics bodies report what they hit.
	pass

var map = null
var world = null
var root: Node3D
var mats = null
var models = null
var rng := RandomNumberGenerator.new()
var match_rng := RandomNumberGenerator.new()
var loot_rng := RandomNumberGenerator.new()

var doors: Array = []
var windows: Array = []
var curtains: Array = []
var props: Array = []          # {id, name, xf, state, rid, ref, mm_key, mm_index, body, health}
var static_props: Array = []   # [name, xf]
var wire_anchors: Array = []
var containers: Array = []     # {id, pos, table, bid, entries, opened_by}
var loot_spots: Array = []     # {pos, table, bid}
var items: Dictionary = {}     # id -> {entry, xf, node}
var corpses: Dictionary = {}   # id -> Corpse node
var lights: Array = []         # {pos, kind, color, energy, range, flicker}

var _mm: Dictionary = {}       # "chunk|name" -> {node, xforms: Array}
var _next_item := 1
var _next_corpse := 1
var _rid_info: Dictionary = {} # RID -> {prop_id}
var _active: Dictionary = {}   # prop id -> PhysicsProp (awake bodies)
var _client_prop_snaps: Dictionary = {}
var space_rid: RID


func _init(m, w, parent: Node3D, materials, model_lib, seed_value: int, match_seed: int) -> void:
	map = m
	world = w
	root = parent
	mats = materials
	models = model_lib
	rng.seed = seed_value
	match_rng.seed = match_seed
	loot_rng.seed = match_seed * 7919 + 17


# ------------------------------------------------------------------ registration during the build

func add_door(spec: Dictionary) -> void:
	spec.id = doors.size()
	doors.append(spec)


func add_window(spec: Dictionary) -> void:
	spec.id = windows.size()
	windows.append(spec)


func add_curtain(spec: Dictionary) -> void:
	curtains.append(spec)


func add_static_prop(name: String, xf: Transform3D) -> void:
	static_props.append([name, xf])


func add_prop_spec(name: String, xf: Transform3D) -> int:
	var s: Dictionary = models.spec(name)
	if s.is_empty():
		return -1
	if s.get("static", false):
		static_props.append([name, xf])
		return -1
	var id := props.size()
	props.append({"id": id, "name": name, "xf": xf, "home": xf, "state": "dormant", "health": float(s.get("hp", 100))})
	return id


func add_container(pos: Vector3, table: String, bid: int, size: Vector3 = Vector3(0.5, 0.5, 0.5)) -> int:
	var id := containers.size()
	containers.append({"id": id, "pos": pos, "table": table, "bid": bid, "entries": [], "size": size, "searched": false})
	return id


func add_loot_spot(pos: Vector3, table: String, bid: int) -> void:
	loot_spots.append({"pos": pos, "table": table, "bid": bid})


func add_wire_anchor(p: Vector3) -> void:
	wire_anchors.append(p)


func add_light(spec: Dictionary) -> void:
	lights.append(spec)


# ------------------------------------------------------------------ instancing

func instantiate() -> void:
	space_rid = root.get_world_3d().space
	var dr := Node3D.new()
	dr.name = "Doors"
	root.add_child(dr)
	for d in doors:
		var door := Door.new()
		door.setup(self, d)
		dr.add_child(door)
		d.node = door
	var wr := Node3D.new()
	wr.name = "Windows"
	root.add_child(wr)
	for w in windows:
		_build_window(wr, w)
	for c in curtains:
		_build_curtain(wr, c)
	for sp in static_props:
		_instance(str(sp[0]), sp[1])
	for p in props:
		_make_dormant(p)
	for key in _mm:
		var e: Dictionary = _mm[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e.mesh
		mm.instance_count = e.xforms.size()
		for i in e.xforms.size():
			mm.set_instance_transform(i, e.xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = 110.0 if e.small else 260.0
		mmi.name = "MM_" + key.replace("|", "_").replace(",", "_")
		root.add_child(mmi)
		e.node = mmi


func _instance(name: String, xf: Transform3D) -> int:
	## Adds a visual instance (MultiMesh) of a prop model. Returns the instance index.
	var md: Dictionary = models.get_model(name)
	if md.is_empty():
		return -1
	var ck := Vector2i(floori(xf.origin.x / 48.0), floori(xf.origin.z / 48.0))
	var key := "%d,%d|%s" % [ck.x, ck.y, name]
	if not _mm.has(key):
		var aabb: AABB = md.aabb
		_mm[key] = {"mesh": md.mesh, "xforms": [], "node": null, "small": aabb.get_longest_axis_size() < 0.8}
	var off: Vector3 = md.get("offset", Vector3.ZERO)
	_mm[key].xforms.append(xf * Transform3D(Basis(), off))
	return _mm[key].xforms.size() - 1


func _prop_shape(name: String) -> Dictionary:
	## Collision box (centre offset + size) from the model bounds.
	var md: Dictionary = models.get_model(name)
	if md.is_empty():
		return {"size": Vector3(0.4, 0.4, 0.4), "center": Vector3(0, 0.2, 0)}
	var a: AABB = md.aabb
	var off: Vector3 = md.get("offset", Vector3.ZERO)
	return {"size": a.size.max(Vector3(0.04, 0.04, 0.04)), "center": a.get_center() + off}


func _make_dormant(p: Dictionary, create_instance: bool = true) -> void:
	if create_instance:
		var idx := _instance(str(p.name), p.xf)
		var ck := Vector2i(floori((p.xf as Transform3D).origin.x / 48.0), floori((p.xf as Transform3D).origin.z / 48.0))
		p.mm_key = "%d,%d|%s" % [ck.x, ck.y, p.name]
		p.mm_index = idx
	var sh := _prop_shape(str(p.name))
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, (sh.size as Vector3) * 0.5)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space_rid)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), sh.center))
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, p.xf)
	PhysicsServer3D.body_set_collision_layer(body, Defs.PHYS_PROP | Defs.PHYS_INTERACT)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	var ref := Ref.new()
	ref.set_meta("prop_id", p.id)
	ref.set_meta("mat", str(models.spec(str(p.name)).get("mat", "wood")))
	PhysicsServer3D.body_attach_object_instance_id(body, ref.get_instance_id())
	p.rid = body
	p.shape_rid = shape
	p.ref = ref
	p.state = "dormant"


func _hide_instance(p: Dictionary) -> void:
	var e: Dictionary = _mm.get(p.get("mm_key", ""), {})
	if e.is_empty() or e.node == null or int(p.get("mm_index", -1)) < 0:
		return
	(e.node as MultiMeshInstance3D).multimesh.set_instance_transform(int(p.mm_index), Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))


func _show_instance(p: Dictionary, xf: Transform3D) -> void:
	var e: Dictionary = _mm.get(p.get("mm_key", ""), {})
	if e.is_empty() or e.node == null or int(p.get("mm_index", -1)) < 0:
		return
	var md: Dictionary = models.get_model(str(p.name))
	(e.node as MultiMeshInstance3D).multimesh.set_instance_transform(int(p.mm_index), xf * Transform3D(Basis(), md.get("offset", Vector3.ZERO)))


# ------------------------------------------------------------------ windows and curtains

func _build_window(parent: Node3D, w: Dictionary) -> void:
	var t: String = w.type
	var xf: Transform3D = w.xf
	var node := Node3D.new()
	node.transform = xf
	parent.add_child(node)
	w.node = node
	w.broken = false
	match t:
		"glass", "store":
			if t == "store":
				_bars(node, w, 0.06)
				return
			# Jalousie: overlapping glass louvres in an aluminium frame; breaks as a unit.
			var n := maxi(int(float(w.h) / 0.11), 3)
			var gm := MeshInstance3D.new()
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in n:
				var y := -float(w.h) * 0.5 + (i + 0.5) * float(w.h) / n
				var b := Basis(Vector3.RIGHT, deg_to_rad(-12.0))
				_add_box_st(st, Transform3D(b, Vector3(0, y, 0)), Vector3(float(w.w) - 0.04, float(w.h) / n + 0.012, 0.005))
			gm.mesh = st.commit()
			gm.material_override = mats.get_material("glass")
			gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			node.add_child(gm)
			w.glass_mesh = gm
			var body := StaticBody3D.new()
			body.collision_layer = Defs.PHYS_GLASS
			body.collision_mask = 0
			body.set_meta("mat", "glass")
			body.set_meta("window_id", w.id)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(float(w.w), float(w.h), 0.03)
			cs.shape = bs
			body.add_child(cs)
			node.add_child(body)
			w.body = body
			# Aluminium frame
			var fr := MeshInstance3D.new()
			var fst := SurfaceTool.new()
			fst.begin(Mesh.PRIMITIVE_TRIANGLES)
			_add_box_st(fst, Transform3D(Basis(), Vector3(-float(w.w) * 0.5 + 0.015, 0, 0)), Vector3(0.03, float(w.h), 0.05))
			_add_box_st(fst, Transform3D(Basis(), Vector3(float(w.w) * 0.5 - 0.015, 0, 0)), Vector3(0.03, float(w.h), 0.05))
			fr.mesh = fst.commit()
			fr.material_override = mats.get_material("metal_sheet")
			node.add_child(fr)
		"shutter":
			var door := Door.new()
			door.setup_shutter(self, w)
			node.add_child(door)
			w.door = door
		"bars":
			_bars(node, w, 0.12)
		"plastic":
			var pm := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(float(w.w), float(w.h))
			pm.mesh = q
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.55, 0.6, 0.62, 0.55)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.roughness = 0.6
			pm.material_override = mat
			node.add_child(pm)
		"open":
			pass


func _bars(node: Node3D, w: Dictionary, spacing: float) -> void:
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(int(float(w.w) / spacing), 2)
	for i in n + 1:
		var x := -float(w.w) * 0.5 + i * float(w.w) / n
		_add_box_st(st, Transform3D(Basis(), Vector3(x, 0, 0.03)), Vector3(0.014, float(w.h), 0.014))
	for y in [-0.45, 0.0, 0.45]:
		_add_box_st(st, Transform3D(Basis(), Vector3(0, y * float(w.h), 0.03)), Vector3(float(w.w), 0.02, 0.012))
	mi.mesh = st.commit()
	mi.material_override = mats.get_material("metal_rust")
	node.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Defs.PHYS_BLOCKER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(float(w.w), float(w.h), 0.05)
	cs.shape = bs
	body.add_child(cs)
	node.add_child(body)


func _build_curtain(parent: Node3D, c: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(c.seed)
	var mi := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := float(c.w)
	var h := float(c.h)
	var cols := 12
	var verts := []
	for j in 2:
		for i in cols + 1:
			var x := -w * 0.5 + w * i / cols
			var z := sin(i * 1.7 + r.randf()) * 0.035
			verts.append(Vector3(x, h * 0.5 - h * j, z + (0.04 * j * sin(i))))
	for i in cols:
		var a: Vector3 = verts[i]
		var b: Vector3 = verts[i + 1]
		var cc: Vector3 = verts[cols + 1 + i + 1]
		var d: Vector3 = verts[cols + 1 + i]
		for tri in [[a, b, cc], [a, cc, d]]:
			for k in 3:
				st.set_uv(Vector2(tri[k].x / 0.8, -tri[k].y / 0.8))
				st.add_vertex(tri[k])
	st.generate_normals()
	mi.mesh = st.commit()
	var m: Material = mats.get_material(r.randi() % 2 == 0 and "gingham" or "cloth")
	mi.material_override = m
	mi.transform = c.xf
	parent.add_child(mi)


static func _add_box_st(st: SurfaceTool, xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * Vector3(h.x, h.y, h.z)
		var hu := absf(u.dot(h))
		var hv := absf(v.dot(h))
		var p := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal((xf.basis * n).normalized())
			st.set_uv(uvs[idx] * Vector2(hu * 2.0, hv * 2.0))
			st.add_vertex(xf * p[idx])


# ------------------------------------------------------------------ match randomisation

func randomize_for_match(is_server: bool) -> void:
	## Door states and prop jitter come from the match seed on every machine (they are visible anyway).
	## Loot is rolled on the server only and stays hidden until a container is opened or an item is seen.
	for d in doors:
		var r := match_rng.randf()
		if d.get("outer", false):
			d.locked = r < 0.22
			d.lock_inside = match_rng.randf() < 0.5
			d.start_angle = 0.0 if r < 0.72 else match_rng.randf_range(0.25, 1.4)
		else:
			d.locked = false
			d.start_angle = 0.0 if r < 0.5 else match_rng.randf_range(0.4, 1.5)
		if d.has("node"):
			(d.node as Node).call("reset_state", float(d.start_angle), bool(d.locked))
	if not is_server:
		return
	for c in containers:
		c.entries = roll_table(str(c.table))
		c.searched = false
	var spawn := []
	for s in loot_spots:
		var entries := roll_table(str(s.table))
		for e in entries:
			spawn.append([e, Transform3D(Basis(Vector3.UP, loot_rng.randf() * TAU), (s.pos as Vector3) + Vector3(loot_rng.randf_range(-0.15, 0.15), 0.02, loot_rng.randf_range(-0.15, 0.15)))])
	for sp in spawn:
		server_spawn_item(sp[0], sp[1], false)


func roll_table(table: String) -> Array:
	var t: Dictionary = Defs.loot.get("tables", {}).get(table, {})
	if t.is_empty():
		return []
	var rolls: Array = t.get("rolls", [1, 1])
	var n := loot_rng.randi_range(int(rolls[0]), int(rolls[1]))
	var entries: Array = t.get("entries", [])
	var total := 0.0
	for e in entries:
		total += float(e[1])
	var out := []
	for i in n:
		var pick := loot_rng.randf() * total
		for e in entries:
			pick -= float(e[1])
			if pick <= 0.0:
				if str(e[0]) != "nothing":
					out.append_array(make_entries(str(e[0]), e))
				break
	return out


func make_entries(id: String, e: Array) -> Array:
	var cnt := 1
	if e.size() > 2:
		cnt = loot_rng.randi_range(int(e[2][0]), int(e[2][1]))
	if Defs.is_weapon(id):
		var w := preload("res://src/weapons/weapon_state.gd").new_instance(id, loot_rng)
		if loot_rng.randf() < 0.18:
			var allowed: Array = Defs.weapon(id).get("attachments", [])
			if not allowed.is_empty():
				w.att.append(allowed[loot_rng.randi_range(0, allowed.size() - 1)])
		return [{"id": id, "n": 1, "w": w}]
	var d := Defs.item(id)
	match str(d.get("kind", "")):
		"battery":
			var out := []
			var cr: Array = e[3] if e.size() > 3 else [0.3, 1.0]
			for i in cnt:
				out.append({"id": "battery", "n": 1, "c": snappedf(loot_rng.randf_range(float(cr[0]), float(cr[1])), 0.01)})
			return out
		"flashlight":
			return [{"id": id, "n": 1, "c": snappedf(loot_rng.randf_range(0.0, 0.8), 0.01)}]
		"armor":
			return [{"id": id, "n": 1, "d": float(d.get("durability", 100)) * loot_rng.randf_range(0.55, 1.0)}]
	return [{"id": id, "n": cnt}]


# ------------------------------------------------------------------ items on the ground

func server_spawn_item(entry: Dictionary, xf: Transform3D, broadcast: bool = true) -> int:
	var id := _next_item
	_next_item += 1
	items[id] = {"entry": entry, "xf": xf}
	if broadcast:
		world.map_item_spawn.rpc(id, entry, xf)
	_spawn_item_node(id)
	return id


func client_spawn_item(id: int, entry: Dictionary, xf: Transform3D) -> void:
	items[id] = {"entry": entry, "xf": xf}
	_spawn_item_node(id)
	_next_item = maxi(_next_item, id + 1)


func _spawn_item_node(id: int) -> void:
	var it: Dictionary = items[id]
	var body := StaticBody3D.new()
	body.name = "Item%d" % id
	body.collision_layer = Defs.PHYS_INTERACT
	body.collision_mask = 0
	body.set_meta("item_id", id)
	body.transform = it.xf
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var md: Dictionary = map.item_visual(str(it.entry.id))
	bs.size = (md.size as Vector3).max(Vector3(0.18, 0.08, 0.18))
	cs.shape = bs
	cs.position = Vector3(0, bs.size.y * 0.5, 0)
	body.add_child(cs)
	if DisplayServer.get_name() != "headless" and md.has("mesh"):
		var mi := MeshInstance3D.new()
		mi.mesh = md.mesh
		mi.transform = md.get("xf", Transform3D())
		body.add_child(mi)
	root.add_child(body)
	it.node = body


func remove_item(id: int) -> void:
	var it: Dictionary = items.get(id, {})
	if it.is_empty():
		return
	if it.get("node") and is_instance_valid(it.node):
		it.node.queue_free()
	items.erase(id)


# ------------------------------------------------------------------ props: activation, simulation, replication

func prop_by_rid(rid: RID) -> Dictionary:
	for p in props:
		if p.get("rid", RID()) == rid:
			return p
	return {}


func server_activate(id: int) -> Node:
	if id < 0 or id >= props.size():
		return null
	var p: Dictionary = props[id]
	if p.state == "active" and _active.has(id):
		return _active[id]
	if p.state == "broken":
		return null
	if p.get("rid", RID()).is_valid():
		PhysicsServer3D.free_rid(p.rid)
		PhysicsServer3D.free_rid(p.shape_rid)
		p.rid = RID()
	_hide_instance(p)
	var body := _make_physics_prop(p, true)
	world.map_prop_activate.rpc(id, p.xf)
	return body


func client_activate(id: int, xf: Transform3D) -> void:
	if id < 0 or id >= props.size():
		return
	var p: Dictionary = props[id]
	if p.state == "active":
		return
	if p.get("rid", RID()).is_valid():
		PhysicsServer3D.free_rid(p.rid)
		PhysicsServer3D.free_rid(p.shape_rid)
		p.rid = RID()
	p.xf = xf
	_hide_instance(p)
	_make_physics_prop(p, false)


func _make_physics_prop(p: Dictionary, server: bool) -> Node:
	var s: Dictionary = models.spec(str(p.name))
	var body := PhysicsProp.new()
	body.setup(self, p, s, _prop_shape(str(p.name)), models.get_model(str(p.name)), server)
	body.name = "Prop%d" % p.id
	root.add_child(body)
	body.global_transform = p.xf
	p.state = "active"
	p.body = body
	_active[p.id] = body
	return body


func server_prop_slept(id: int) -> void:
	var p: Dictionary = props[id]
	p.xf = (p.body as Node3D).global_transform
	world.map_prop_rest.rpc(id, p.xf)


func client_prop_rest(id: int, xf: Transform3D) -> void:
	var p: Dictionary = props[id]
	p.xf = xf
	if p.get("body") and is_instance_valid(p.body):
		p.body.client_rest(xf)


func awake_props_near(pos: Vector3, radius: float) -> Array:
	var out := []
	for id in _active:
		var b = _active[id]
		if not is_instance_valid(b) or b.sleeping:
			continue
		var gp: Vector3 = b.global_position
		if gp.distance_to(pos) <= radius:
			out.append({"id": id, "pos": gp, "rot": b.global_transform.basis.get_rotation_quaternion()})
			if out.size() >= 48:
				break
	return out


func client_prop_snapshot(id: int, pos: Vector3, rot: Quaternion, t: float) -> void:
	if id < 0 or id >= props.size():
		return
	var p: Dictionary = props[id]
	if p.state != "active":
		client_activate(id, Transform3D(Basis(rot), pos))
	if p.get("body") and is_instance_valid(p.body):
		p.body.push_snapshot(t, pos, rot)


func client_interpolate(render_tick: float) -> void:
	for id in _active:
		var b = _active[id]
		if is_instance_valid(b):
			b.interpolate(render_tick)


func server_break_prop(id: int, impulse: Vector3) -> void:
	var p: Dictionary = props[id]
	if p.state == "broken":
		return
	var pos: Vector3 = (p.body as Node3D).global_position if p.get("body") and is_instance_valid(p.body) else (p.xf as Transform3D).origin
	_break_local(id)
	world.map_prop_break.rpc(id, pos, impulse)


func client_break_prop(id: int, pos: Vector3, impulse: Vector3) -> void:
	_break_local(id)
	if world.effects:
		world.effects.prop_broken(str(props[id].name), pos, impulse, models.spec(str(props[id].name)))


func _break_local(id: int) -> void:
	var p: Dictionary = props[id]
	p.state = "broken"
	if p.get("rid", RID()).is_valid():
		PhysicsServer3D.free_rid(p.rid)
		PhysicsServer3D.free_rid(p.shape_rid)
		p.rid = RID()
	_hide_instance(p)
	if p.get("body") and is_instance_valid(p.body):
		p.body.queue_free()
	_active.erase(id)


func reset_props() -> void:
	## Puts every prop back to its home transform and dormant state (between matches).
	for id in _active.keys():
		var b = _active[id]
		if is_instance_valid(b):
			b.queue_free()
	_active.clear()
	for p in props:
		if p.get("rid", RID()).is_valid():
			PhysicsServer3D.free_rid(p.rid)
			PhysicsServer3D.free_rid(p.shape_rid)
		p.xf = p.home
		p.health = float(models.spec(str(p.name)).get("hp", 100))
		_make_dormant(p, false)
		_show_instance(p, p.xf)


func tick(dt: float) -> void:
	for d in doors:
		if d.has("node") and d.node.moving:
			d.node.tick(dt)
	for w in windows:
		if w.has("door") and w.door.moving:
			w.door.tick(dt)
