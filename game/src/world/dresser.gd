extends RefCounted
## Furnishes rooms according to what they are used for and hides loot where people keep things:
## batteries in drawers, medicine in the comfort room, tools in workshops, a gun under the bed now and then.
## Furniture is placed against walls with the doorway kept clear; tables sit in the open with chairs around them.

var mb = null
var rng := RandomNumberGenerator.new()
var _item_cache: Dictionary = {}


func _init(map_builder) -> void:
	mb = map_builder
	rng.seed = mb.layout.rng.seed + 307


# ------------------------------------------------------------------ rooms

func dress_room(r: Dictionary, house: Dictionary) -> void:
	var kind := str(house.get("kind", "house"))
	var t := str(r.type)
	var ctx := {"r": r, "occ": [], "w": float((r.size as Vector2).x), "d": float((r.size as Vector2).y), "xf": r.xf, "bid": int(r.bid)}
	# Keep the area inside the front door free.
	if r.has("door_x"):
		ctx.occ.append(Rect2(Vector2(float(r.door_x) - 0.6, -ctx.d * 0.5 - 0.2), Vector2(1.2, 1.4)))
	var av: Rect2 = r.get("avoid", Rect2())
	if av.size != Vector2.ZERO:
		ctx.occ.append(Rect2(av.position - Vector2(0, float(r.get("local_z", 0.0))), av.size).grow(0.1))
	match kind:
		"classroom":
			_classroom(ctx)
			return
		"clinic":
			_clinic(ctx)
			return
		"chapel", "church":
			_pews(ctx)
			return
		"hall", "police", "outpost", "pump":
			_office(ctx)
			return
	match t:
		"sala":
			_sala(ctx)
		"kitchen":
			_kitchen(ctx)
		"bed":
			_bedroom(ctx)
		"cr":
			_cr(ctx)
		"store":
			_store(ctx)
		"workshop":
			_workshop(ctx)


func _put(ctx: Dictionary, name: String, lp: Vector2, yaw: float, y: float = 0.0, pad: float = 0.05) -> bool:
	## Places a prop at room-local (x, z) facing yaw; rejects overlaps and anything outside the room.
	var s: Dictionary = mb.models.spec(name)
	var md: Dictionary = mb.models.get_model(name)
	if md.is_empty():
		return false
	var a: AABB = md.aabb
	var ext := Vector2(a.size.x, a.size.z)
	if absf(sin(yaw)) > 0.7:
		ext = Vector2(ext.y, ext.x)
	var rect := Rect2(lp - ext * 0.5, ext).grow(pad)
	var room := Rect2(Vector2(-ctx.w * 0.5, -ctx.d * 0.5), Vector2(ctx.w, ctx.d))
	if not room.encloses(rect.grow(-pad - 0.01)):
		return false
	for o in ctx.occ:
		if (o as Rect2).intersects(rect):
			return false
	ctx.occ.append(rect)
	# Model origin may not be centred: shift so its bounds are centred on lp and sit on the floor.
	var centre := Vector3(a.get_center().x, a.position.y, a.get_center().z)
	var rot := Basis(Vector3.UP, yaw)
	var xf: Transform3D = (ctx.xf as Transform3D) * Transform3D(rot, Vector3(lp.x, y, lp.y)) * Transform3D(Basis(), -centre)
	if s.get("static", false):
		mb.dyn.add_static_prop(name, xf)
	else:
		mb.dyn.add_prop_spec(name, xf)
	return true


func _wall_slot(ctx: Dictionary, name: String, wall: String, along: float = INF) -> Dictionary:
	## Position for a piece of furniture backed against a wall. Returns {pos, yaw} or {} if nothing fits.
	var md: Dictionary = mb.models.get_model(name)
	if md.is_empty():
		return {}
	var a: AABB = md.aabb
	var depth := a.size.z
	var width := a.size.x
	for attempt in 6:
		var pos := Vector2.ZERO
		var yaw := 0.0
		match wall:
			"back":
				var x := along if along != INF and attempt == 0 else rng.randf_range(-ctx.w * 0.5 + width * 0.5, ctx.w * 0.5 - width * 0.5)
				pos = Vector2(x, ctx.d * 0.5 - depth * 0.5 - 0.03)
				yaw = PI
			"front":
				var x2 := rng.randf_range(-ctx.w * 0.5 + width * 0.5, ctx.w * 0.5 - width * 0.5)
				pos = Vector2(x2, -ctx.d * 0.5 + depth * 0.5 + 0.03)
				yaw = 0.0
			"left":
				var z := rng.randf_range(-ctx.d * 0.5 + width * 0.5, ctx.d * 0.5 - width * 0.5)
				pos = Vector2(-ctx.w * 0.5 + depth * 0.5 + 0.03, z)
				yaw = PI * 0.5
			"right":
				var z2 := rng.randf_range(-ctx.d * 0.5 + width * 0.5, ctx.d * 0.5 - width * 0.5)
				pos = Vector2(ctx.w * 0.5 - depth * 0.5 - 0.03, z2)
				yaw = -PI * 0.5
		if _put(ctx, name, pos, yaw):
			return {"pos": pos, "yaw": yaw}
	return {}


func _world(ctx: Dictionary, lp: Vector2, y: float) -> Vector3:
	return (ctx.xf as Transform3D) * Vector3(lp.x, y, lp.y)


func _container_on(ctx: Dictionary, slot: Dictionary, table: String, y: float = 0.6, size := Vector3(0.6, 0.5, 0.45)) -> void:
	if slot.is_empty():
		return
	mb.dyn.add_container(_world(ctx, slot.pos, y), table, int(ctx.bid), size)


func _floor_loot(ctx: Dictionary, table: String, chance: float) -> void:
	if rng.randf() > chance:
		return
	for i in 6:
		var lp := Vector2(rng.randf_range(-ctx.w * 0.4, ctx.w * 0.4), rng.randf_range(-ctx.d * 0.4, ctx.d * 0.4))
		var free := true
		for o in ctx.occ:
			if (o as Rect2).has_point(lp):
				free = false
		if free:
			mb.dyn.add_loot_spot(_world(ctx, lp, 0.02), table, int(ctx.bid))
			return


func _clutter(ctx: Dictionary, n: int, names: Array) -> void:
	for i in n:
		var lp := Vector2(rng.randf_range(-ctx.w * 0.45, ctx.w * 0.45), rng.randf_range(-ctx.d * 0.45, ctx.d * 0.45))
		_put(ctx, names[rng.randi_range(0, names.size() - 1)], lp, rng.randf() * TAU, 0.0, 0.0)


# ------------------------------------------------------------------ room kinds

func _sala(ctx: Dictionary) -> void:
	if ctx.w * ctx.d < 4.0:
		return
	_wall_slot(ctx, _pick(["sofa_paint", "bench_paint", "sofa_paint"]), _pick(["left", "right", "back"]))
	var cab := _wall_slot(ctx, _pick(["cabinet_paint", "cabinet_paint2", "drawer_old", "shelves_paint"]), _pick(["back", "left", "right"]))
	_container_on(ctx, cab, "drawer", 0.5)
	if not cab.is_empty() and rng.randf() < 0.55:
		var tvp: Vector2 = cab.pos
		_put(ctx, _pick(["tv", "tv2"]), tvp, float(cab.yaw), 0.95, -0.4)
	var c := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.3))
	if _put(ctx, _pick(["table_small", "table_round", "table_paint"]), c, rng.randf_range(-0.1, 0.1)):
		for k in rng.randi_range(1, 3):
			var a := rng.randf() * TAU
			_put(ctx, _pick(["monobloc", "monobloc", "chair_wood", "stool"]), c + Vector2(cos(a), sin(a)) * 0.85, a + PI * 0.5 + rng.randf_range(-0.6, 0.6), 0.0, 0.0)
	_clutter(ctx, rng.randi_range(0, 3), ["box", "basket", "bottle", "gallon", "trashbag", "boots", "sungka", "crate_plastic"])
	_floor_loot(ctx, "floor_household", 0.25)


func _kitchen(ctx: Dictionary) -> void:
	var cab := _wall_slot(ctx, _pick(["cabinet_paint", "cabinet_paint2", "shelves_paint", "shelf"]), _pick(["back", "left", "right"]))
	_container_on(ctx, cab, "kitchen", 0.7)
	var st := _wall_slot(ctx, _pick(["sink_counter", "counter"]), _pick(["back", "left", "right"]))
	if not st.is_empty():
		if rng.randf() < 0.6:
			_put(ctx, "pot", st.pos, 0.0, 0.88, -0.5)
	_wall_slot(ctx, _pick(["lpg_small", "propane", "drum_blue"]), _pick(["back", "left", "right"]))
	var c := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.2))
	if _put(ctx, _pick(["table_paint", "table_small", "table_wood"]), c, 0.0):
		for k in rng.randi_range(1, 3):
			var a := rng.randf() * TAU
			_put(ctx, _pick(["stool", "monobloc", "stool_fold", "chair_plain"]), c + Vector2(cos(a), sin(a)) * 0.8, rng.randf() * TAU, 0.0, 0.0)
	_clutter(ctx, rng.randi_range(1, 4), ["bottle", "bottle", "jug", "gallon", "bucket", "container", "bowl", "jerrycan", "can"])
	_floor_loot(ctx, "floor_household", 0.15)


func _bedroom(ctx: Dictionary) -> void:
	var bed := {}
	if ctx.w >= 2.2 and ctx.d >= 2.2 and rng.randf() < 0.65:
		bed = _wall_slot(ctx, _pick(["bed_old", "daybed"]), _pick(["back", "left", "right"]))
	if bed.is_empty():
		var lp := Vector2(rng.randf_range(-ctx.w * 0.2, ctx.w * 0.2), rng.randf_range(-ctx.d * 0.2, ctx.d * 0.2))
		if _put(ctx, "banig", lp, rng.randf_range(-0.2, 0.2) + (PI * 0.5 if ctx.w > ctx.d else 0.0)):
			_put(ctx, "mattress", lp, PI * 0.5 if ctx.w > ctx.d else 0.0, 0.01, -0.2)
			bed = {"pos": lp}
	if not bed.is_empty():
		mb.dyn.add_container(_world(ctx, bed.pos, 0.15), "under_bed", int(ctx.bid), Vector3(1.2, 0.3, 1.6))
	var w := _wall_slot(ctx, _pick(["cabinet_paint", "drawer_cabinet", "drawer_old", "cabinet_paint2"]), _pick(["back", "left", "right", "front"]))
	_container_on(ctx, w, "wardrobe", 0.9)
	var n := _wall_slot(ctx, _pick(["nightstand", "drawer_old"]), _pick(["left", "right", "back"]))
	_container_on(ctx, n, "drawer", 0.4)
	_clutter(ctx, rng.randi_range(0, 3), ["suitcase", "box", "basket", "crate_plastic2", "boots"])
	_floor_loot(ctx, "floor_household", 0.2)


func _cr(ctx: Dictionary) -> void:
	_put(ctx, "toilet", Vector2(0, ctx.d * 0.5 - 0.35), PI)
	_put(ctx, _pick(["bucket", "container", "gallon"]), Vector2(ctx.w * 0.3, -ctx.d * 0.2), rng.randf() * TAU, 0.0, 0.0)
	mb.dyn.add_container(_world(ctx, Vector2(-ctx.w * 0.3, 0), 1.2), "bathroom", int(ctx.bid), Vector3(0.4, 0.4, 0.25))


func _store(ctx: Dictionary) -> void:
	var counter := _put(ctx, "counter", Vector2(0, -ctx.d * 0.5 + 1.0), 0.0)
	if counter:
		mb.dyn.add_container(_world(ctx, Vector2(0, -ctx.d * 0.5 + 1.0), 0.6), "store_counter", int(ctx.bid), Vector3(1.4, 0.6, 0.5))
		if rng.randf() < 0.5:
			_put(ctx, "cash_register", Vector2(0.3, -ctx.d * 0.5 + 1.0), PI, 0.95, -0.3)
	for wall in ["left", "right", "back"]:
		var s := _wall_slot(ctx, _pick(["steel_shelves", "shelves_paint", "steel_shelves2", "shelf"]), wall)
		_container_on(ctx, s, "store_shelf", 1.0, Vector3(0.9, 1.2, 0.4))
	_clutter(ctx, rng.randi_range(2, 5), ["crate_plastic", "crate_plastic2", "box", "gallon", "bottle", "jerrycan"])


func _workshop(ctx: Dictionary) -> void:
	_wall_slot(ctx, "workbench", "back")
	var tc := _wall_slot(ctx, _pick(["tool_chest", "steel_shelves"]), _pick(["left", "right"]))
	_container_on(ctx, tc, "toolbox", 0.7)
	_wall_slot(ctx, _pick(["welding_cart", "generator", "drill_press"]), _pick(["left", "right", "back"]))
	_clutter(ctx, rng.randi_range(3, 7), ["old_tyre", "wheel_rim", "drum", "toolbox", "jerrycan_metal", "tire_pump", "crate_wood", "sledgehammer", "crowbar", "wrench", "hand_truck"])
	_floor_loot(ctx, "toolbox", 0.3)


func _classroom(ctx: Dictionary) -> void:
	_wall_slot(ctx, "chalkboard", "front")
	var cols := maxi(int(ctx.w / 1.6), 1)
	var rows := maxi(int((ctx.d - 2.0) / 1.4), 1)
	for i in cols:
		for j in rows:
			var lp := Vector2(-ctx.w * 0.5 + 0.9 + i * 1.6, -ctx.d * 0.5 + 2.2 + j * 1.4)
			if rng.randf() < 0.85:
				_put(ctx, "school_desk", lp, PI + rng.randf_range(-0.15, 0.15), 0.0, 0.0)
				_put(ctx, "school_chair", lp + Vector2(0, 0.55), PI + rng.randf_range(-0.3, 0.3), 0.0, 0.0)
	var cab := _wall_slot(ctx, "steel_shelves", "back")
	_container_on(ctx, cab, "drawer", 1.0)


func _clinic(ctx: Dictionary) -> void:
	for wall in ["left", "right", "back"]:
		var s := _wall_slot(ctx, _pick(["steel_shelves", "cabinet_paint", "drawer_cabinet"]), wall)
		_container_on(ctx, s, "clinic", 1.0, Vector3(0.9, 1.0, 0.4))
	_wall_slot(ctx, _pick(["bed_old", "daybed"]), _pick(["left", "right"]))
	_put(ctx, "desk_metal", Vector2(0, -ctx.d * 0.25), 0.0)
	_clutter(ctx, 3, ["medical_box", "wheelchair", "crutches", "extinguisher", "monobloc"])
	_floor_loot(ctx, "clinic", 0.6)


func _pews(ctx: Dictionary) -> void:
	var rows := int((ctx.d - 3.0) / 1.2)
	for j in rows:
		for side in [-1.0, 1.0]:
			_put(ctx, "bench_paint", Vector2(side * ctx.w * 0.25, -ctx.d * 0.5 + 2.0 + j * 1.2), PI, 0.0, 0.0)
	_put(ctx, "table_wood", Vector2(0, ctx.d * 0.5 - 1.2), 0.0)


func _office(ctx: Dictionary) -> void:
	for k in rng.randi_range(1, 3):
		var lp := Vector2(rng.randf_range(-ctx.w * 0.3, ctx.w * 0.3), rng.randf_range(-ctx.d * 0.3, ctx.d * 0.3))
		if _put(ctx, "desk_metal", lp, _pick([0.0, PI])):
			_put(ctx, _pick(["monobloc", "chair_plain"]), lp + Vector2(0, 0.8), PI, 0.0, 0.0)
	var c := _wall_slot(ctx, _pick(["steel_shelves", "drawer_cabinet", "cabinet_paint"]), _pick(["back", "left", "right"]))
	_container_on(ctx, c, "drawer", 0.8)
	_floor_loot(ctx, "floor_household", 0.3)


# ------------------------------------------------------------------ ground item visuals

const ITEM_MODELS := {
	"battery": "", "flashlight": "small_plastic_torch", "bandage": "medical_tape", "first_aid": "medical_box",
	"splint": "", "painkillers": "", "vest_light": "", "vest_heavy": "", "helmet_light": "", "helmet_heavy": "",
	"backpack_small": "", "backpack_large": "", "weapon_light": "", "sight_reddot": "", "sight_holo": "", "scope_4x": "", "scope_6x": "",
	"pistol_9": "service_pistol", "bolt_308": "bolt_action_rifle_7_62",
}


func item_visual(id: String) -> Dictionary:
	if _item_cache.has(id):
		return _item_cache[id]
	var res := {}
	var model := str(ITEM_MODELS.get(id, ""))
	if id.begins_with("ammo_"):
		model = "ammo_box"
	if model != "":
		var md: Dictionary = mb.models.get_model(model)
		if not md.is_empty():
			var a: AABB = md.aabb
			var c := a.get_center()
			res = {"mesh": md.mesh, "size": a.size, "xf": Transform3D(Basis(), Vector3(-c.x, -a.position.y, -c.z))}
	if res.is_empty():
		var processed := "res://assets/models/items/%s.glb" % id
		if ResourceLoader.exists(processed):
			var md2: Dictionary = mb.models._load_scene_mesh(processed)
			if not md2.is_empty():
				var a2: AABB = md2.aabb
				res = {"mesh": md2.mesh, "size": a2.size, "xf": Transform3D(Basis(), Vector3(-a2.get_center().x, -a2.position.y, -a2.get_center().z))}
	if res.is_empty():
		var size := Vector3(0.25, 0.08, 0.15)
		var col := Color(0.3, 0.3, 0.3)
		var kind := str(Defs.item(id).get("kind", ""))
		match kind:
			"weapon":
				size = Vector3(0.08, 0.1, 0.8) if Defs.weapon(id).get("slot", "") == "long" else Vector3(0.05, 0.13, 0.2)
				col = Color(0.08, 0.08, 0.08)
			"battery":
				size = Vector3(0.034, 0.06, 0.034)
				col = Color(0.75, 0.55, 0.15)
			"medical":
				size = Vector3(0.12, 0.05, 0.08)
				col = Color(0.85, 0.85, 0.82)
			"armor":
				size = Vector3(0.45, 0.12, 0.5) if id.begins_with("vest") else Vector3(0.24, 0.17, 0.26)
				col = Color(0.18, 0.22, 0.16)
			"backpack":
				size = Vector3(0.35, 0.18, 0.45)
				col = Color(0.15, 0.2, 0.3)
			"attachment":
				size = Vector3(0.05, 0.05, 0.12)
				col = Color(0.1, 0.1, 0.1)
		var bm := BoxMesh.new()
		bm.size = size
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.7
		bm.material = m
		res = {"mesh": bm, "size": size, "xf": Transform3D(Basis(), Vector3(0, size.y * 0.5, 0))}
	_item_cache[id] = res
	return res


func _pick(a: Array):
	return a[rng.randi_range(0, a.size() - 1)]
