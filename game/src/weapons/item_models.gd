extends RefCounted
## r24: gun and attachment models where there is no map (the workbench opened from Game Setup in the menus). Answers
## item_visual(id) like Dresser.item_visual does for guns and attachments, so AttachVisual and ItemIcons work with
## it: {mesh, size, xf}, the model centred on x/z with its bottom at y = 0 and the muzzle toward -z.

const GunModel := preload("res://src/weapons/gun_model.gd")

static var _cache := {}


func item_visual(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var mid := str(Defs.weapon(id).get("model", id)) if Defs.is_weapon(id) else id
	var res := {}
	for path in ["res://assets/models/items/%s.glb" % mid, "res://assets/models/loot/%s.glb" % mid]:
		if not ResourceLoader.exists(path):
			continue
		var m := _merged(path)
		if m == null:
			continue
		var a := m.get_aabb()
		res = {"mesh": m, "size": a.size, "xf": Transform3D(Basis(), Vector3(-a.get_center().x, -a.position.y, -a.get_center().z)), "model": path}
		break
	if res.is_empty():
		var size := Vector3(0.05, 0.05, 0.12) if Defs.is_attachment(id) else Vector3(0.08, 0.1, 0.8)
		var bm := BoxMesh.new()
		bm.size = size
		res = {"mesh": bm, "size": size, "xf": Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)), "placeholder": true}
	_cache[id] = res
	return res


static func _merged(path: String) -> ArrayMesh:
	## Every mesh of the scene in one ArrayMesh, node transforms baked in.
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst := ps.instantiate()
	var out: ArrayMesh = null
	var stack := [[inst, Transform3D()]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		for c in n.get_children():
			var cx := xf
			if c is Node3D:
				cx = xf * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh:
				var baked: ArrayMesh = GunModel._baked((c as MeshInstance3D).mesh, cx)
				out = baked if out == null else GunModel._joined(out, baked)
			stack.append([c, cx])
	inst.free()
	return out
