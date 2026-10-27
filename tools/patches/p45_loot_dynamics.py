"""Loot run (2026-10-26): loot boxes with open/closed lids, node-less ground items with a resting pose, guaranteed
rolls and weapon ammunition in loot tables, hidden MultiMesh instances that keep their cell bounds.

    python -I tools/patches/p45_loot_dynamics.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'src', 'world', 'dynamics.gd')
raw = open(p, 'rb').read().decode()
CRLF = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b, cnt=1):
    global s
    assert s.count(a) == cnt, (a[:90], s.count(a))
    s = s.replace(a, b)


rep('''var items: Dictionary = {}     # id -> {entry, xf, node}''', '''var items: Dictionary = {}     # id -> {entry, xf, body (physics RID), ref, inst (render RID)}
var loot_boxes: Array = []     # {cid, name, xf, open, interior, mm, mm_open}''')
rep('''	var snd := "search_drawer"
	if table in ["store_shelf", "trash", "crate", "military_crate"]:
		snd = "search_box"
	elif table in ["wardrobe", "weapon_locker", "clinic", "toolbox"]:
		snd = "search_cabinet"''', '''	var snd := "search_drawer"
	if table in ["store_shelf", "trash", "crate", "military_crate", "box_balikbayan", "box_bin", "box_cooler"]:
		snd = "search_box"
	elif table in ["wardrobe", "weapon_locker", "clinic", "toolbox"] or table.begins_with("box_"):
		snd = "search_cabinet"''')
rep('''func add_loot_spot(pos: Vector3, table: String, bid: int) -> void:
	loot_spots.append({"pos": pos, "table": table, "bid": bid})''', '''func add_loot_spot(pos: Vector3, table: String, bid: int) -> void:
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
	## Swaps the closed and open models of a loot box (both are MultiMesh instances; the hidden one is scaled to
	## nothing where it stands, so its cell keeps tight bounds).
	if cid < 0 or cid >= containers.size() or not containers[cid].has("box"):
		return
	var b: Dictionary = loot_boxes[int(containers[cid].box)]
	if bool(b.open) == open:
		return
	b.open = open
	_mm_set(b.get("mm", ["", -1]), b.xf, not open, str(b.name))
	_mm_set(b.get("mm_open", ["", -1]), b.xf, open, str(b.name) + "_open")


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


func opened_boxes() -> PackedInt32Array:
	var out := PackedInt32Array()
	for b in loot_boxes:
		if b.open:
			out.append(int(b.cid))
	return out''')
rep('''	for p in props:
		_make_dormant(p)
	for key in _mm:''', '''	for p in props:
		_make_dormant(p)
	for b in loot_boxes:
		b.mm = _instance(str(b.name), b.xf, bool(b.interior))
		b.mm_open = _instance(str(b.name) + "_open", b.xf, bool(b.interior))
		_mm_set(b.mm_open, b.xf, false, str(b.name) + "_open")
	for key in _mm:''')
rep('''	(e.node as MultiMeshInstance3D).multimesh.set_instance_transform(int(p.mm_index), Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))''',
    '''	# Scaled to nothing where it stands: moving it far away would stretch the cell's bounds (culling and the
	# visibility range use them) across the map.
	(e.node as MultiMeshInstance3D).multimesh.set_instance_transform(int(p.mm_index), Transform3D(Basis().scaled(Vector3.ZERO), (p.xf as Transform3D).origin))''')
rep('''	var out := []
	for i in n:
		var pick := rng.randf() * total
		for e in entries:
			pick -= float(e[1])
			if pick <= 0.0:
				if str(e[0]) != "nothing":
					out.append_array(make_entries(str(e[0]), e, rng))
				break
	return out''', '''	var out := []
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
	return []''')
rep('''	var entries: Array = t.get("entries", [])
	var total := 0.0
	for e in entries:
		total += float(e[1])
''', '''	var entries: Array = t.get("entries", [])
''')
rep('''		if rng.randf() < 0.18:
			var allowed: Array = Defs.weapon(id).get("attachments", [])''', '''		if rng.randf() < float(Defs.loot.get("weapon_attachment_chance", 0.18)):
			var allowed: Array = Defs.weapon(id).get("attachments", [])''')
rep('''			return [{"id": id, "n": 1, "d": float(d.get("durability", 100)) * loot_rng.randf_range(0.55, 1.0)}]''',
    '''			return [{"id": id, "n": 1, "d": float(d.get("durability", 100)) * rng.randf_range(0.55, 1.0)}]''')

a = s.index('func _spawn_item_node(id: int) -> void:')
b = s.index('# ------------------------------------------------------------------ props: activation')
s = s[:a] + '''func _spawn_item_node(id: int) -> void:
	## Items on the ground have no scene nodes (thousands lie around the map): a static physics body the Use ray can
	## hit, and a render instance with a short draw distance.
	var it: Dictionary = items[id]
	var iid := str(it.entry.id)
	var md: Dictionary = map.item_visual(iid)
	var rest := item_rest(iid)
	var xf: Transform3D = it.xf
	var shape: RID = _item_shapes.get(iid, RID())
	if not shape.is_valid():
		shape = PhysicsServer3D.box_shape_create()
		PhysicsServer3D.shape_set_data(shape, ((rest.size as Vector3).max(Vector3(0.16, 0.06, 0.16))) * 0.5)
		_item_shapes[iid] = shape
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space_rid if space_rid.is_valid() else root.get_world_3d().space)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), Vector3(0, maxf((rest.size as Vector3).y, 0.06) * 0.5, 0)))
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_collision_layer(body, Defs.PHYS_INTERACT)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	var ref := Ref.new()
	ref.set_meta("item_id", id)
	PhysicsServer3D.body_attach_object_instance_id(body, ref.get_instance_id())
	it.body = body
	it.ref = ref
	if DisplayServer.get_name() != "headless" and md.get("mesh") != null:
		var inst := RenderingServer.instance_create2((md.mesh as Mesh).get_rid(), root.get_world_3d().scenario)
		RenderingServer.instance_set_transform(inst, xf * (rest.xf as Transform3D))
		RenderingServer.instance_geometry_set_cast_shadows_setting(inst, RenderingServer.SHADOW_CASTING_SETTING_OFF)
		var indoor: bool = map.acoustics != null and map.acoustics.zone_at(xf.origin + Vector3.UP * 0.3) != 0
		RenderingServer.instance_set_layer_mask(inst, Defs.RENDER_INTERIOR_PROPS if indoor else Defs.RENDER_WORLD)
		var big := (rest.size as Vector3).length() > 0.5
		var reach := (36.0 if big else 24.0) * clampf(float(Settings.get_value("graphics", "view_distance")), 0.6, 1.3)
		RenderingServer.instance_geometry_set_visibility_range(inst, 0.0, reach, 0.0, 4.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
		it.inst = inst


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
	items.erase(id)


''' + s[b:]
open(p, 'wb').write((s.replace('\n', '\r\n') if CRLF else s).encode())
print('ok')
