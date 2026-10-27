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
var floor_rng := RandomNumberGenerator.new()

var doors: Array = []
var windows: Array = []
var curtains: Array = []
var props: Array = []          # {id, name, xf, state, rid, ref, mm_key, mm_index, body, health}
var static_props: Array = []   # [name, xf, interior]
var wire_anchors: Array = []
var containers: Array = []     # {id, pos, table, bid, entries, opened_by}
var loot_spots: Array = []     # {pos, table, bid}
var items: Dictionary = {}     # id -> {entry, xf, body (physics RID), ref, inst (render RID)}
var loot_boxes: Array = []     # {cid, name, xf, open, interior, mm, inst_open (render RID once opened)}
var corpses: Dictionary = {}   # id -> Corpse node
var lights: Array = []         # {pos, kind, color, energy, range, flicker}

var _mm: Dictionary = {}       # "chunk|name" -> {node, xforms: Array}
var _leaf_meshes: Dictionary = {}
var _cgrid: Dictionary = {}
var _next_item := 1
var _igrid: Dictionary = {}    # Vector2i (8 m cell) -> [item id]
var floor_count := 0           # items 1..floor_count were rolled from the match seed on every machine
var _next_corpse := 1
var _rid_info: Dictionary = {} # RID -> {prop_id}
var _active: Dictionary = {}   # prop id -> PhysicsProp (awake bodies)
var _moving_doors: Array = []  # doors and shutters mid-swing; only these are ticked
## Set by the dresser while it furnishes a room: props placed meanwhile go on the Interior render layer (no moon
## shadow, hidden from the air) with short draw distances.
var interior_scope := false
var _policies := {}
var _dormant_shapes := {}      # prop name -> box shape RID shared by its dormant bodies
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
	floor_rng.seed = match_seed * 6271 + 5


# ------------------------------------------------------------------ registration during the build

func add_door(spec: Dictionary) -> void:
	spec.id = doors.size()
	doors.append(spec)


var _hinges := {}         # 4 m cell -> [Vector3(hinge x, hinge z, leaf width)], for door_swing_clear
var _hinges_indexed := 0


func door_swing_clear(c: Vector2, half: Vector2, ang: float) -> bool:
	## False when the rectangle (centre c, half extents, rotated ang in the x-z plane) reaches into a door's swing.
	## A door swings up to ~95 degrees toward whoever opens it, from inside or out, so anything heavy within a leaf's
	## width of the hinge jams it (and a static cabinet there would be swung through).
	while _hinges_indexed < doors.size():
		var o: Vector3 = (doors[_hinges_indexed].xf as Transform3D).origin
		var key := Vector2i(floori(o.x / 4.0), floori(o.z / 4.0))
		if not _hinges.has(key):
			_hinges[key] = []
		_hinges[key].append(Vector3(o.x, o.z, float(doors[_hinges_indexed].w)))
		_hinges_indexed += 1
	var cell := Vector2i(floori(c.x / 4.0), floori(c.y / 4.0))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for e in _hinges.get(cell + Vector2i(dx, dz), []):
				var lp := (Vector2(e.x, e.y) - c).rotated(-ang)
				var nearest := Vector2(clampf(lp.x, -half.x, half.x), clampf(lp.y, -half.y, half.y))
				if lp.distance_to(nearest) < e.z + 0.05:
					return false
	return true


func add_window(spec: Dictionary) -> void:
	spec.id = windows.size()
	windows.append(spec)
	_window_static(spec)


func add_curtain(spec: Dictionary) -> void:
	curtains.append(spec)


func add_static_prop(name: String, xf: Transform3D) -> void:
	var s: Dictionary = models.spec(name)
	if s.has("prim"):
		# A box that never moves (toilet, counter, mat, block): part of the chunk geometry, no draw call of its own.
		var size: Vector3 = s.size
		map.sink.box(xf * Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)), size, str(s.get("surface", "plywood")),
			{"collide": false, "layer": "int" if interior_scope else "ext", "dirt": 0.4})
	else:
		static_props.append([name, xf, interior_scope])
	if s.get("no_collide", false):
		return
	var sh := _prop_shape(name)
	if s.has("trunk"):
		var tr := float(s.trunk)
		var hgt := minf((sh.size as Vector3).y * 0.55, 4.5)
		map.sink.col_box(xf * Transform3D(Basis(), Vector3(0, hgt * 0.5, 0)), Vector3(tr, hgt, tr), "wood")
	else:
		var md: Dictionary = models.get_model(name)
		var off: Vector3 = md.get("offset", Vector3.ZERO)
		map.sink.col_box(xf * Transform3D(Basis(), sh.center), sh.size, str(s.get("mat", "default")))


func add_prop_spec(name: String, xf: Transform3D) -> int:
	var s: Dictionary = models.spec(name)
	if s.is_empty():
		return -1
	if s.get("static", false):
		static_props.append([name, xf, interior_scope])
		return -1
	var id := props.size()
	props.append({"id": id, "name": name, "xf": xf, "home": xf, "state": "dormant", "health": float(s.get("hp", 100)), "interior": interior_scope})
	return id


func add_container(pos: Vector3, table: String, bid: int, size: Vector3 = Vector3(0.5, 0.5, 0.5)) -> int:
	var id := containers.size()
	var snd := "search_drawer"
	if table in ["store_shelf", "trash", "crate", "military_crate", "box_balikbayan", "box_bin", "box_cooler"]:
		snd = "search_box"
	elif table in ["wardrobe", "weapon_locker", "clinic", "toolbox"] or table.begins_with("box_"):
		snd = "search_cabinet"
	elif table == "under_bed":
		snd = "search_soft"
	containers.append({"id": id, "pos": pos, "table": table, "bid": bid, "entries": [], "size": size, "searched": false, "sound": snd})
	var k := Vector2i(floori(pos.x / 8.0), floori(pos.z / 8.0))
	if not _cgrid.has(k):
		_cgrid[k] = []
	_cgrid[k].append(id)
	return id


func containers_near(p: Vector3, r: float) -> Array:
	var out := []
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for id in _cgrid.get(k + Vector2i(dx, dz), []):
				var c: Dictionary = containers[id]
				if (c.pos as Vector3).distance_to(p) <= r:
					out.append(c)
	return out


func add_loot_spot(pos: Vector3, table: String, bid: int) -> void:
	loot_spots.append({"pos": pos, "table": table, "bid": bid})


func add_loot_box(name: String, xf: Transform3D, table: String, bid: int) -> int:
	## A visible box that is also a loot container: it blocks movement and shots like furniture, Use searches it, and
	## its lid opens (for everyone) the first time someone does. Returns the container id, or -1.
	var md: Dictionary = models.get_model(name)
	if md.is_empty() or models.get_model(name + "_open").is_empty():
		return -1
	var sh := _prop_shape(name)
	map.sink.col_box(xf * Transform3D(Basis(), sh.center), sh.size, str(models.spec(name).get("mat", "wood")))
	# Containers are searched through a world-aligned box: the rotated footprint's bounds.
	var a: AABB = xf * (md.aabb as AABB)
	var cid := add_container(a.get_center(), table, bid, a.size)
	containers[cid].box = loot_boxes.size()
	loot_boxes.append({"cid": cid, "name": name, "xf": xf, "open": false, "interior": interior_scope})
	return cid


func set_box_open(cid: int, open: bool) -> void:
	## Swaps a loot box's closed model (a MultiMesh instance, scaled to nothing where it stands so its cell keeps tight
	## bounds) for its open one: a render instance of its own, made the first time the box is opened (thousands of
	## boxes, few open; registering the open models in every cell would cost a draw call per cell even when hidden).
	if cid < 0 or cid >= containers.size() or not containers[cid].has("box"):
		return
	var b: Dictionary = loot_boxes[int(containers[cid].box)]
	if bool(b.open) == open:
		return
	b.open = open
	_mm_set(b.get("mm", ["", -1]), b.xf, not open, str(b.name))
	if DisplayServer.get_name() == "headless":
		return
	if open and not b.get("inst_open", RID()).is_valid():
		var md: Dictionary = models.get_model(str(b.name) + "_open")
		if md.is_empty():
			return
		var inst := RenderingServer.instance_create2((md.mesh as Mesh).get_rid(), root.get_world_3d().scenario)
		RenderingServer.instance_set_transform(inst, (b.xf as Transform3D) * Transform3D(Basis(), md.get("offset", Vector3.ZERO)))
		RenderingServer.instance_set_layer_mask(inst, Defs.RENDER_INTERIOR_PROPS if b.interior else Defs.RENDER_WORLD)
		RenderingServer.instance_geometry_set_cast_shadows_setting(inst, RenderingServer.SHADOW_CASTING_SETTING_OFF)
		var pol := _policy(str(b.name), models.get_model(str(b.name)), bool(b.interior))
		RenderingServer.instance_geometry_set_visibility_range(inst, 0.0, float(pol.range) - float(pol.cell) * 0.7, 0.0, 4.0,
			RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
		b.inst_open = inst
	elif not open and b.get("inst_open", RID()).is_valid():
		RenderingServer.free_rid(b.inst_open)
		b.inst_open = RID()


func _mm_set(r: Array, xf: Transform3D, visible: bool, name: String) -> void:
	var e: Dictionary = _mm.get(r[0], {})
	if e.is_empty() or int(r[1]) < 0:
		return
	var md: Dictionary = models.get_model(name)
	var t: Transform3D = xf * Transform3D(Basis(), md.get("offset", Vector3.ZERO))
	if not visible:
		t = Transform3D(Basis().scaled(Vector3.ZERO), t.origin)
	if e.node == null:
		e.xforms[int(r[1])] = t
	else:
		(e.node as MultiMeshInstance3D).multimesh.set_instance_transform(int(r[1]), t)


func set_loot_visible(v: bool) -> void:
	## Shows or hides every ground item and loot box (performance attribution only).
	for it in items.values():
		if it.get("inst", RID()).is_valid():
			RenderingServer.instance_set_visible(it.inst, v)
	for key in _mm:
		if "|lootbox_" in str(key) and _mm[key].node:
			(_mm[key].node as Node3D).visible = v
	for b in loot_boxes:
		if b.get("inst_open", RID()).is_valid():
			RenderingServer.instance_set_visible(b.inst_open, v)


func opened_boxes() -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in loot_boxes:
		if b.open:
			out.append(int(b.cid))
	return out


func add_wire_anchor(p: Vector3) -> void:
	wire_anchors.append(p)


func add_light(spec: Dictionary) -> void:
	lights.append(spec)


# ------------------------------------------------------------------ instancing

func instantiate() -> void:
	space_rid = root.get_world_3d().space
	for d in doors:
		var door := Door.new()
		door.setup(self, d)
		d.node = door
	for w in windows:
		_window_dynamic(w)
	for c in curtains:
		_curtain_instance(c)
	for sp in static_props:
		_instance(str(sp[0]), sp[1], bool(sp[2]))
	for p in props:
		_make_dormant(p)
	for b in loot_boxes:
		b.mm = _instance(str(b.name), b.xf, bool(b.interior))
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
		mmi.visibility_range_end = float(e.range)
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if e.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if e.interior:
			mmi.layers = Defs.RENDER_INTERIOR_PROPS
		if not str(key).contains("|leaf_"):
			# Props never animate here (they are hidden or shown in one step), so no interpolation buffers either.
			mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		mmi.name = "MM_%d" % e.xforms.size() + "_" + str(randi())
		root.add_child(mmi)
		e.node = mmi


# ------------------------------------------------------------------ shared instanced leaves (doors, shutters, glass, curtains)

func _leaf_mesh(kind: String, mat: String) -> Mesh:
	var key := kind + "|" + mat
	if _leaf_meshes.has(key):
		return _leaf_meshes[key]
	var m: Mesh
	match kind:
		"box":
			var sb := SurfaceTool.new()
			sb.begin(Mesh.PRIMITIVE_TRIANGLES)
			sb.set_color(Color(1, 1, 1, 0))
			_add_box_st(sb, Transform3D(), Vector3.ONE)
			sb.generate_tangents()
			m = sb.commit()
			m.surface_set_material(0, mats.get_material(mat))
		"jalousie":
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var n := 8
			for i in n:
				var y := -0.5 + (i + 0.5) / n
				_add_box_st(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)), Vector3(0, y, 0)), Vector3(0.96, 1.0 / n + 0.015, 0.01))
			m = st.commit()
			m.surface_set_material(0, mats.get_material("glass"))
		"curtain":
			var st2 := SurfaceTool.new()
			st2.begin(Mesh.PRIMITIVE_TRIANGLES)
			var cols := 10
			for i in cols:
				var x0 := -0.5 + float(i) / cols
				var x1 := -0.5 + float(i + 1) / cols
				var z0 := sin(i * 1.9) * 0.04
				var z1 := sin((i + 1) * 1.9) * 0.04
				var pts := [Vector3(x0, 0.5, z0), Vector3(x1, 0.5, z1), Vector3(x1, -0.5, z1 + 0.02), Vector3(x0, -0.5, z0 + 0.02)]
				for tri in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:
					for k in tri:
						var pp: Vector3 = pts[k]
						st2.set_uv(Vector2(pp.x + 0.5, 0.5 - pp.y) * 1.5)
						st2.add_vertex(pp)
			st2.generate_normals()
			m = st2.commit()
			m.surface_set_material(0, mats.get_material(mat))
	_leaf_meshes[key] = m
	return m


func add_leaf_instance(owner, mat: String, kind: String = "box") -> Array:
	return add_leaf(kind, mat, owner.base, 90.0)


func add_leaf(kind: String, mat: String, xf: Transform3D, range: float) -> Array:
	## Doors, shutters, louvres and curtains: tiny meshes in their thousands, one MultiMesh per 96 m cell (a few
	## more triangles drawn costs nothing next to a draw call per cell and pass). The range is measured to the cell
	## centre, hence + 0.7 cell.
	var ck := Vector2i(floori(xf.origin.x / 96.0), floori(xf.origin.z / 96.0))
	var key := "%d,%d|leaf_%s_%s" % [ck.x, ck.y, kind, mat]
	if not _mm.has(key):
		_mm[key] = {"mesh": _leaf_mesh(kind, mat), "xforms": [], "node": null, "range": range + 67.0,
			"shadow": kind != "jalousie", "interior": kind == "curtain"}
	_mm[key].xforms.append(xf)
	return [key, _mm[key].xforms.size() - 1]


func set_leaf_transform(key: String, index: int, xf: Transform3D) -> void:
	var e: Dictionary = _mm.get(key, {})
	if e.is_empty() or index < 0:
		return
	if e.node == null:
		e.xforms[index] = xf
	else:
		(e.node as MultiMeshInstance3D).multimesh.set_instance_transform(index, xf)


func _instance(name: String, xf: Transform3D, interior: bool = false) -> Array:
	## Adds a visual instance (MultiMesh) of a prop model. Returns [cell key, instance index] (["", -1] if none).
	var md: Dictionary = models.get_model(name)
	if md.is_empty():
		return ["", -1]
	var pol := _policy(name, md, interior)
	var cell: float = pol.cell
	var ck := Vector2i(floori(xf.origin.x / cell), floori(xf.origin.z / cell))
	var key := "%d,%d|%s|%s" % [ck.x, ck.y, name, "i" if interior else "e"]
	if not _mm.has(key):
		_mm[key] = {"mesh": md.mesh, "xforms": [], "node": null, "range": pol.range, "shadow": pol.shadow, "interior": interior}
	var off: Vector3 = md.get("offset", Vector3.ZERO)
	_mm[key].xforms.append(xf * Transform3D(Basis(), off))
	return [key, _mm[key].xforms.size() - 1]


func _policy(name: String, md: Dictionary, interior: bool) -> Dictionary:
	## How a model is instanced. Each MultiMesh is culled, LOD-selected and range-checked as one box (the range is
	## measured to its centre, hence + 0.7 cell), and each of its surfaces is a draw call in every pass. So: heavy
	## meshes in small cells with short ranges, cheap ones in big cells, and shadows only from things big enough
	## to matter (each shadow pass redraws whole cells).
	var pk := name + ("|i" if interior else "|e")
	if _policies.has(pk):
		return _policies[pk]
	var s: Dictionary = models.spec(name)
	var kind := str(s.get("kind", ""))
	var size: float = (md.aabb as AABB).get_longest_axis_size()
	var no_shadow := kind == "lootbox"
	var mesh: Mesh = md.mesh
	var surf := mesh.get_surface_count()
	var tris := 12
	if mesh is ArrayMesh:
		tris = 0
		for i in surf:
			tris += (mesh as ArrayMesh).surface_get_array_index_len(i) / 3
	var cheap := tris * surf <= 300
	var cell := 64.0 if cheap else 32.0
	var want := 80.0
	var shadow := size > 1.2 and surf <= 4
	if kind == "tree" or (kind == "plant" and size > 2.5):
		cell = 96.0
		want = 200.0
		shadow = true
	elif kind == "plant":
		want = 45.0
		shadow = false
	elif kind == "vehicle" or size > 3.0:
		cell = 64.0
		want = 140.0
		shadow = true
	elif interior:
		# Rooms are dark and walled in: furniture is seen through a doorway or a lit window close by, not across the
		# block, and furnished rooms put dozens of models in every cell (each a draw call per pass).
		want = 15.0 if size < 0.7 else 25.0
		shadow = size >= 0.7 and surf <= 4
	elif size < 0.8:
		want = 45.0
		shadow = false
	if surf >= 6 and kind not in ["tree", "vehicle"]:
		# Litter and heaps made of a dozen materials: a dozen draw calls per cell and pass, for ground clutter.
		want = minf(want, 35.0)
		shadow = false
	# The draw-distance setting scales prop ranges too (phones draw street props and trees closer). Read at build.
	want *= clampf(float(Settings.get_value("graphics", "view_distance")), 0.6, 1.3)
	var pol := {"cell": cell, "range": want + cell * 0.7, "shadow": shadow and not no_shadow}
	_policies[pk] = pol
	return pol


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
		var r := _instance(str(p.name), p.xf, bool(p.get("interior", false)))
		p.mm_key = r[0]
		p.mm_index = r[1]
	var sh := _prop_shape(str(p.name))
	# One box shape per model, shared by all its dormant bodies (tens of thousands once rooms are furnished).
	var shape: RID = _dormant_shapes.get(p.name, RID())
	if not shape.is_valid():
		shape = PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, (sh.size as Vector3) * 0.5)
		_dormant_shapes[p.name] = shape
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space_rid)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), sh.center))
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, p.xf)
	# Trash (no_block) can be grabbed but blocks no one and stops no bullet.
	var no_block: bool = models.spec(str(p.name)).get("no_block", false)
	PhysicsServer3D.body_set_collision_layer(body, Defs.PHYS_INTERACT if no_block else Defs.PHYS_PROP | Defs.PHYS_INTERACT)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	var ref := Ref.new()
	ref.set_meta("prop_id", p.id)
	ref.set_meta("mat", str(models.spec(str(p.name)).get("mat", "wood")))
	PhysicsServer3D.body_attach_object_instance_id(body, ref.get_instance_id())
	p.rid = body
	p.ref = ref
	p.state = "dormant"


func _hide_instance(p: Dictionary) -> void:
	var e: Dictionary = _mm.get(p.get("mm_key", ""), {})
	if e.is_empty() or e.node == null or int(p.get("mm_index", -1)) < 0:
		return
	# Scaled to nothing where it stands: moving it far away would stretch the cell's bounds (culling and the
	# visibility range use them) across the map.
	(e.node as MultiMeshInstance3D).multimesh.set_instance_transform(int(p.mm_index), Transform3D(Basis().scaled(Vector3.ZERO), (p.xf as Transform3D).origin))


func _show_instance(p: Dictionary, xf: Transform3D) -> void:
	var e: Dictionary = _mm.get(p.get("mm_key", ""), {})
	if e.is_empty() or e.node == null or int(p.get("mm_index", -1)) < 0:
		return
	var md: Dictionary = models.get_model(str(p.name))
	(e.node as MultiMeshInstance3D).multimesh.set_instance_transform(int(p.mm_index), xf * Transform3D(Basis(), md.get("offset", Vector3.ZERO)))


# ------------------------------------------------------------------ windows and curtains

func _window_static(w: Dictionary) -> void:
	## Frames, bars, grilles and plastic sheets never change: they go straight into the batched geometry.
	var xf: Transform3D = w.xf
	var ww := float(w.w)
	var hh := float(w.h)
	var sink = map.sink
	match str(w.type):
		"glass":
			sink.box(xf * Transform3D(Basis(), Vector3(-ww * 0.5 + 0.015, 0, 0)), Vector3(0.03, hh, 0.05), "metal_sheet", {"collide": false, "layer": "int"})
			sink.box(xf * Transform3D(Basis(), Vector3(ww * 0.5 - 0.015, 0, 0)), Vector3(0.03, hh, 0.05), "metal_sheet", {"collide": false, "layer": "int"})
		"store", "bars":
			var spacing := 0.06 if str(w.type) == "store" else 0.12
			var n := maxi(int(ww / spacing), 2)
			for i in n + 1:
				var x := -ww * 0.5 + i * ww / n
				sink.box(xf * Transform3D(Basis(), Vector3(x, 0, 0.03)), Vector3(0.014, hh, 0.014), "metal_rust", {"collide": false, "faces": 1 | 2 | 16 | 32})
			for y in [-0.45, 0.0, 0.45]:
				sink.box(xf * Transform3D(Basis(), Vector3(0, y * hh, 0.03)), Vector3(ww, 0.02, 0.012), "metal_rust", {"collide": false, "faces": 4 | 8 | 16 | 32})
			sink.col_box(xf * Transform3D(Basis(), Vector3(0, 0, 0.03)), Vector3(ww, hh, 0.05), "blocker")
		"plastic":
			var c0: Vector3 = xf * Vector3(-ww * 0.5, -hh * 0.5, 0)
			var c1: Vector3 = xf * Vector3(ww * 0.5, -hh * 0.5, 0)
			var c2: Vector3 = xf * Vector3(ww * 0.5, hh * 0.5, 0)
			var c3: Vector3 = xf * Vector3(-ww * 0.5, hh * 0.5, 0)
			sink.quad(c0, c1, c2, c3, "glass_frosted", {"double": true, "layer": "int"})


func _window_dynamic(w: Dictionary) -> void:
	w.broken = false
	match str(w.type):
		"glass":
			var xf: Transform3D = w.xf
			var r := add_leaf("jalousie", "glass", xf * Transform3D(Basis().scaled(Vector3(float(w.w), float(w.h), 1.0)), Vector3.ZERO), 90.0)
			w.leaf = r
			var shape := PhysicsServer3D.box_shape_create()
			PhysicsServer3D.shape_set_data(shape, Vector3(float(w.w), float(w.h), 0.03) * 0.5)
			var body := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
			PhysicsServer3D.body_set_space(body, space_rid)
			PhysicsServer3D.body_add_shape(body, shape)
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
			PhysicsServer3D.body_set_collision_layer(body, Defs.PHYS_GLASS)
			PhysicsServer3D.body_set_collision_mask(body, 0)
			var ref := Ref.new()
			ref.set_meta("mat", "glass")
			ref.set_meta("window_id", int(w.id))
			PhysicsServer3D.body_attach_object_instance_id(body, ref.get_instance_id())
			w.body = body
			w.shape = shape
			w.ref = ref
		"shutter":
			var door := Door.new()
			door.setup_shutter(self, w)
			w.door = door


func _curtain_instance(c: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(c.seed)
	var mat := "gingham" if r.randf() < 0.5 else "cloth"
	add_leaf("curtain", mat, (c.xf as Transform3D) * Transform3D(Basis().scaled(Vector3(float(c.w), float(c.h), 1.0)), Vector3.ZERO), 70.0)


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
			d.node.reset_state(float(d.start_angle), bool(d.locked))
	# Floor loot is in plain sight: every machine rolls it from the match seed, in the same order, with the same ids.
	# Each spot first settles on the surface under it (the same static world on every machine); one with nothing
	# under it, or inside something, stays empty.
	var spawn := []
	var space := PhysicsServer3D.space_get_direct_state(space_rid if space_rid.is_valid() else root.get_world_3d().space)
	for s in loot_spots:
		var sp: Vector3 = s.pos
		var down := PhysicsRayQueryParameters3D.create(sp + Vector3.UP * 0.35, sp + Vector3.DOWN * 0.45, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var hit := space.intersect_ray(down)
		if hit.is_empty() or (hit.position as Vector3).y > sp.y + 0.06:
			s.dropped = true
			floor_rng.randf()  # keep the sequence in step whatever the outcome
			continue
		s.pos = Vector3(sp.x, (hit.position as Vector3).y + 0.01, sp.z)
		var entries := roll_table(str(s.table), floor_rng)
		for e in entries:
			# Items of one spot lie a little apart, each on the surface under it (or at the spot itself when the
			# nudge would put it on a step or under something).
			var yaw := floor_rng.randf() * TAU
			var p: Vector3 = (s.pos as Vector3) + Vector3(floor_rng.randf_range(-0.15, 0.15), 0.0, floor_rng.randf_range(-0.15, 0.15))
			var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.35, p + Vector3.DOWN * 0.3, Defs.PHYS_WORLD | Defs.PHYS_PROP))
			if h2.is_empty() or absf((h2.position as Vector3).y - (s.pos as Vector3).y) > 0.04:
				p = s.pos
			else:
				p.y = (h2.position as Vector3).y + 0.01
			spawn.append([e, Transform3D(Basis(Vector3.UP, yaw), p)])
	for sp in spawn:
		server_spawn_item(sp[0], sp[1], false)
	floor_count = _next_item - 1
	if not is_server:
		return
	# Container contents stay hidden: rolled on the server only.
	for c in containers:
		c.entries = roll_table(str(c.table))
		c.searched = false


func roll_table(table: String, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = loot_rng
	var t: Dictionary = Defs.loot.get("tables", {}).get(table, {})
	if t.is_empty():
		return []
	var rolls: Array = t.get("rolls", [1, 1])
	var n := rng.randi_range(int(rolls[0]), int(rolls[1]))
	var entries: Array = t.get("entries", [])
	var out := []
	var g: Array = t.get("guaranteed", [])
	if not g.is_empty():
		out.append_array(_pick_entry(g, rng))
	for i in n:
		out.append_array(_pick_entry(entries, rng))
	return out


func _pick_entry(entries: Array, rng: RandomNumberGenerator) -> Array:
	var total := 0.0
	for e in entries:
		total += float(e[1])
	var pick := rng.randf() * total
	for e in entries:
		pick -= float(e[1])
		if pick <= 0.0:
			if str(e[0]) == "nothing":
				return []
			var out := make_entries(str(e[0]), e, rng)
			# A gun usually comes with some of its own ammunition.
			if Defs.is_weapon(str(e[0])):
				var wa: Dictionary = Defs.loot.get("weapon_ammo", {})
				if rng.randf() < float(wa.get("chance", 0.0)):
					var cal := str(Defs.weapon(str(e[0])).get("ammo", ""))
					var cr: Array = (wa.get("counts", {}) as Dictionary).get(cal, [5, 15])
					out.append({"id": "ammo_" + cal, "n": rng.randi_range(int(cr[0]), int(cr[1]))})
			return out
	return []


func make_entries(id: String, e: Array, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = loot_rng
	var cnt := 1
	if e.size() > 2:
		cnt = rng.randi_range(int(e[2][0]), int(e[2][1]))
	if Defs.is_weapon(id):
		var w := preload("res://src/weapons/weapon_state.gd").new_instance(id, rng)
		if rng.randf() < float(Defs.loot.get("weapon_attachment_chance", 0.18)):
			var allowed: Array = Defs.weapon(id).get("attachments", [])
			if not allowed.is_empty():
				w.att.append(allowed[rng.randi_range(0, allowed.size() - 1)])
		return [{"id": id, "n": 1, "w": w}]
	var d := Defs.item(id)
	match str(d.get("kind", "")):
		"battery":
			var out := []
			var cr: Array = e[3] if e.size() > 3 else [0.3, 1.0]
			for i in cnt:
				out.append({"id": "battery", "n": 1, "c": snappedf(rng.randf_range(float(cr[0]), float(cr[1])), 0.01)})
			return out
		"flashlight":
			return [{"id": id, "n": 1, "c": snappedf(rng.randf_range(0.0, 0.8), 0.01)}]
		"armor":
			return [{"id": id, "n": 1, "d": float(d.get("durability", 100)) * rng.randf_range(0.55, 1.0)}]
	return [{"id": id, "n": cnt}]


# ------------------------------------------------------------------ items on the ground

func server_spawn_item(entry: Dictionary, xf: Transform3D, broadcast: bool = true) -> int:
	var id := _next_item
	_next_item += 1
	items[id] = {"entry": entry, "xf": xf}
	_igrid_add(id, xf.origin)
	if broadcast:
		world.map_item_spawn.rpc(id, entry, xf)
	_spawn_item_node(id)
	return id


func client_spawn_item(id: int, entry: Dictionary, xf: Transform3D) -> void:
	items[id] = {"entry": entry, "xf": xf}
	_igrid_add(id, xf.origin)
	_spawn_item_node(id)
	_next_item = maxi(_next_item, id + 1)


func _spawn_item_node(id: int) -> void:
	## Items on the ground have no scene nodes and no physics bodies (thousands lie around the map): a pick box in
	## the item's own frame for the Use ray (item_hit) and a render instance with a short draw distance.
	var it: Dictionary = items[id]
	var iid := str(it.entry.id)
	var md: Dictionary = map.item_visual(iid)
	var rest := item_rest(iid)
	var xf: Transform3D = it.xf
	var sz: Vector3 = (rest.size as Vector3).max(Vector3(0.16, 0.06, 0.16))
	it.box = AABB(Vector3(-sz.x * 0.5, 0.0, -sz.z * 0.5), sz)
	if DisplayServer.get_name() != "headless" and md.get("mesh") != null:
		var inst := RenderingServer.instance_create2((md.mesh as Mesh).get_rid(), root.get_world_3d().scenario)
		RenderingServer.instance_set_transform(inst, xf * (rest.xf as Transform3D))
		RenderingServer.instance_geometry_set_cast_shadows_setting(inst, RenderingServer.SHADOW_CASTING_SETTING_OFF)
		var indoor: bool = map.acoustics != null and map.acoustics.zone_at(xf.origin + Vector3.UP * 0.3) != 0
		RenderingServer.instance_set_layer_mask(inst, Defs.RENDER_INTERIOR_PROPS if indoor else Defs.RENDER_WORLD)
		# Guns are seen from further than rounds and small items; indoors (small slum rooms, walls between them) a
		# shorter reach saves hundreds of draw calls in a dense block.
		var gun := Defs.is_weapon(iid) or (rest.size as Vector3).length() > 0.5
		var reach := ((14.0 if gun else 9.0) if indoor else (24.0 if gun else 15.0)) * clampf(float(Settings.get_value("graphics", "view_distance")), 0.6, 1.3)
		RenderingServer.instance_geometry_set_visibility_range(inst, 0.0, reach, 0.0, 4.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
		_set_item_glow(inst, md.mesh as Mesh, true)
		it.inst = inst
		it.reach = reach


var _glow_mats := {}   # source material -> copy that glows faintly in its own colours


func _set_item_glow(inst: RID, mesh: Mesh, on: bool) -> void:
	## Loot reads on a dark floor (other battle royales are played in daylight): each surface gets a copy of its
	## material that emits a little of its own colour, so a gun or a box of rounds shows its shape without a light.
	## Same draw calls as the plain model (no overlay pass).
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s)
		var m: Material = null
		if on and src is BaseMaterial3D:
			if not _glow_mats.has(src):
				var g := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				g.emission_enabled = true
				g.emission = (src as BaseMaterial3D).albedo_color
				g.emission_texture = (src as BaseMaterial3D).albedo_texture
				g.emission_energy_multiplier = 0.09
				g.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
				_glow_mats[src] = g
			m = _glow_mats[src]
		RenderingServer.instance_set_surface_override_material(inst, s, m.get_rid() if m else RID())


func set_item_glint(on: bool) -> void:
	## Ground item glow on or off (performance attribution).
	for id in items:
		var it: Dictionary = items[id]
		if it.get("inst", RID()).is_valid():
			_set_item_glow(it.inst, map.item_visual(str(it.entry.id)).mesh, on)


var _item_shapes := {}
var _rest_cache := {}


func item_rest(id: String) -> Dictionary:
	## How an item lies on the floor: {xf: model transform relative to the item's floor point, size: its bounds}.
	## Guns lie on their side; anything tall and thin tips over; bottles, kits and packs stand.
	if _rest_cache.has(id):
		return _rest_cache[id]
	var md: Dictionary = map.item_visual(id)
	var sz: Vector3 = md.get("size", Vector3(0.2, 0.1, 0.2))
	var base: Transform3D = md.get("xf", Transform3D())
	var rot := Basis()
	var kind := str(Defs.item(id).get("kind", ""))
	if kind == "weapon":
		rot = Basis(Vector3.FORWARD, PI * 0.5)
	elif sz.y > maxf(sz.x, sz.z) * 1.25 and id not in ["painkillers", "first_aid", "backpack_small", "backpack_large", "radio"]:
		rot = Basis(Vector3.RIGHT, PI * 0.5)
	# Model space after item_visual: centred on x/z, bottom at y = 0.
	var box := AABB(Vector3(-sz.x * 0.5, 0.0, -sz.z * 0.5), sz)
	var turned: AABB = Transform3D(rot, Vector3.ZERO) * box
	var shift := Vector3(-turned.get_center().x, -turned.position.y, -turned.get_center().z)
	var res := {"xf": Transform3D(rot, shift) * base, "size": turned.size}
	_rest_cache[id] = res
	return res


func remove_item(id: int) -> void:
	var it: Dictionary = items.get(id, {})
	if it.is_empty():
		return
	if it.get("body", RID()).is_valid():
		PhysicsServer3D.free_rid(it.body)
	if it.get("inst", RID()).is_valid():
		RenderingServer.free_rid(it.inst)
	var k := Vector2i(floori((it.xf as Transform3D).origin.x / 8.0), floori((it.xf as Transform3D).origin.z / 8.0))
	if _igrid.has(k):
		(_igrid[k] as Array).erase(id)
	items.erase(id)


func _igrid_add(id: int, p: Vector3) -> void:
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	if not _igrid.has(k):
		_igrid[k] = []
	_igrid[k].append(id)


func item_hit(from: Vector3, dir: Vector3, reach: float) -> Array:
	## The nearest item the ray from `from` along `dir` (normalised) passes through within reach: [id, distance],
	## or [-1, INF].
	var best := -1
	var bt := reach
	for id in items_near(from, reach + 0.6):
		var it: Dictionary = items[id]
		if not it.has("box"):
			continue
		var inv: Transform3D = (it.xf as Transform3D).affine_inverse()
		var hit = (it.box as AABB).grow(0.03).intersects_ray(inv * from, inv.basis * dir)
		if hit != null:
			var t := (inv * from).distance_to(hit)
			if t < bt:
				bt = t
				best = int(id)
	return [best, bt if best >= 0 else INF]


func items_near(p: Vector3, r: float) -> Array:
	## Ids of items on the ground within r (r up to 8 m checks the 3x3 cells around p; more scans wider).
	var out := []
	var span := int(ceil(r / 8.0))
	var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			for id in _igrid.get(k + Vector2i(dx, dz), []):
				if ((items[id].xf as Transform3D).origin).distance_to(p) <= r:
					out.append(id)
	return out


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
		p.rid = RID()
	_hide_instance(p)
	if p.get("body") and is_instance_valid(p.body):
		p.body.queue_free()
	_active.erase(id)


func dispose() -> void:
	## Frees what the servers hold outside the scene tree (bodies, shapes, render instances). Nodes go with the tree.
	for id in items.keys():
		remove_item(id)
	for p in props:
		if p.get("rid", RID()).is_valid():
			PhysicsServer3D.free_rid(p.rid)
			p.rid = RID()
	for w in windows:
		if w.has("body") and (w.body as RID).is_valid():
			PhysicsServer3D.free_rid(w.body)
			PhysicsServer3D.free_rid(w.shape)
			w.body = RID()
		if w.get("door") != null and w.door.has_method("free_body"):
			w.door.free_body()
	for dd in doors:
		var dn = dd.get("node")
		if dn and dn.has_method("free_body"):
			dn.free_body()
	for b in loot_boxes:
		if b.get("inst_open", RID()).is_valid():
			RenderingServer.free_rid(b.inst_open)
			b.inst_open = RID()
	for sh in _dormant_shapes.values():
		PhysicsServer3D.free_rid(sh)
	_dormant_shapes.clear()
	for sh in _item_shapes.values():
		PhysicsServer3D.free_rid(sh)
	_item_shapes.clear()


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
		p.xf = p.home
		p.health = float(models.spec(str(p.name)).get("hp", 100))
		_make_dormant(p, false)
		_show_instance(p, p.xf)


func door_started(d) -> void:
	if not _moving_doors.has(d):
		_moving_doors.append(d)


var _door_cells := {}      # 4 m cell -> [door node], for characters pushing doors
var _door_cells_n := 0


func _push_doors() -> void:
	## Everyone walking into an open door shoves it aside (server and clients alike; the server's swing is what
	## every client converges to).
	if world == null or doors.is_empty():
		return
	if _door_cells_n != doors.size():
		_door_cells.clear()
		for dd in doors:
			var dn = dd.get("node")
			if dn == null:
				continue
			var o: Vector3 = (dd.xf as Transform3D).origin
			var key := Vector2i(floori(o.x / 4.0), floori(o.z / 4.0))
			if not _door_cells.has(key):
				_door_cells[key] = []
			_door_cells[key].append(dn)
		_door_cells_n = doors.size()
	var radius := Defs.move("radius")
	for ch in world.characters.values():
		if ch.mode != Motor.GROUND and ch.mode != Motor.DOWNED:
			continue
		var p: Vector3 = ch.global_position
		var v: Vector3 = ch.velocity
		var cell := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for dn in _door_cells.get(cell + Vector2i(dx, dz), []):
					dn.push(p, v, radius)


func tick(dt: float) -> void:
	_push_doors()
	for i in range(_moving_doors.size() - 1, -1, -1):
		var d = _moving_doors[i]
		d.tick(dt)
		if not d.moving:
			_moving_doors.remove_at(i)


# ------------------------------------------------------------------ corpses

func server_spawn_corpse(ch, impulse: Vector3) -> int:
	var id := _next_corpse
	_next_corpse += 1
	var c := Corpse.new()
	root.add_child(c)
	c.setup_server(world, id, ch, impulse)
	c.entries = ch.inv.all_entries()
	# Whatever was in the hands and on the body stays with the body.
	corpses[id] = c
	world.map_corpse_spawn.rpc(id, ch.pname, ch.team, c.pose())
	return id


func client_spawn_corpse(id: int, who: String, team: int, xforms: Array) -> void:
	if corpses.has(id):
		return
	var c := Corpse.new()
	root.add_child(c)
	c.setup_client(world, id, who, team, xforms)
	corpses[id] = c
	_next_corpse = maxi(_next_corpse, id + 1)


# ------------------------------------------------------------------ glass

func break_window(wid: int, pos: Vector3, dir: Vector3) -> bool:
	if wid < 0 or wid >= windows.size():
		return false
	var w: Dictionary = windows[wid]
	if w.get("broken", false):
		return false
	w.broken = true
	if w.has("leaf"):
		set_leaf_transform(w.leaf[0], w.leaf[1], Transform3D(Basis().scaled(Vector3.ZERO), (w.xf as Transform3D).origin))
	if w.has("body") and (w.body as RID).is_valid():
		PhysicsServer3D.free_rid(w.body)
		PhysicsServer3D.free_rid(w.shape)
		w.body = RID()
	if w.has("portal"):
		map.acoustics.set_portal_kind(int(w.portal), "opening")
		map.acoustics.set_portal_open(int(w.portal), 1.0)
	return true
