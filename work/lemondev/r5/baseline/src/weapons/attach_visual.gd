extends RefCounted
## Where attachments sit on a weapon model, and the meshes that draw them (first person and third person).
##
## Mount points come from the weapon model's own shape: its height profile along the barrel (top, bottom and right
## side per slice), the bore height at the muzzle, and the grip / fore-end positions in weapons.json "hold". A weapon
## can override any of them in "mounts" ({"sight": fraction from the muzzle, "sight_dy": metres, ...}).
## Everything is in the weapon's item_visual space: centred on x/z, bottom at y = 0, muzzle toward -z.

const Attach := preload("res://src/weapons/attachments.gd")
const BINS := 64
const MAG_EXT := 0.05     # how far an extended magazine reaches below the gun's own
const MAG_QUICK := 0.022

static var _profiles := {}


static func profile(map, wid: String) -> Dictionary:
	## {front, len, top, bot, right (per slice), bore, size}. Cached per weapon.
	if _profiles.has(wid):
		return _profiles[wid]
	var md: Dictionary = map.item_visual(wid)
	var sz: Vector3 = md.get("size", Vector3(0.05, 0.1, 0.5))
	var xf: Transform3D = md.get("xf", Transform3D())
	var front := -sz.z * 0.5
	var top := PackedFloat32Array()
	var bot := PackedFloat32Array()
	var right := PackedFloat32Array()
	top.resize(BINS)
	bot.resize(BINS)
	right.resize(BINS)
	for i in BINS:
		top[i] = -1.0
		bot[i] = 99.0
		right[i] = 0.0
	var bore_sum := 0.0
	var bore_n := 0
	var mesh: Mesh = md.get("mesh")
	if mesh is ArrayMesh:
		for si in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v0 in verts:
				var v: Vector3 = xf * v0
				var i := clampi(int((v.z - front) / maxf(sz.z, 0.01) * BINS), 0, BINS - 1)
				top[i] = maxf(top[i], v.y)
				bot[i] = minf(bot[i], v.y)
				right[i] = maxf(right[i], v.x)
				if v.z < front + sz.z * 0.02:
					bore_sum += v.y
					bore_n += 1
	# Fill empty slices from their neighbours.
	for i in BINS:
		if top[i] < 0.0:
			var j := i - 1 if i > 0 else i + 1
			while j >= 0 and j < BINS and top[j] < 0.0:
				j += 1
			if j >= 0 and j < BINS:
				top[i] = top[j]
				bot[i] = bot[j]
				right[i] = right[j]
			else:
				top[i] = sz.y * 0.6
				bot[i] = sz.y * 0.3
				right[i] = sz.x * 0.5
	var res := {"front": front, "len": sz.z, "top": top, "bot": bot, "right": right, "size": sz,
		"bore": bore_sum / bore_n if bore_n > 0 else sz.y * 0.7}
	_profiles[wid] = res
	return res


static func _slice(p: Dictionary, f: float) -> int:
	return clampi(int(f * BINS), 0, BINS - 1)


static func _max_top(p: Dictionary, f0: float, f1: float) -> float:
	var m := -1.0
	for i in range(_slice(p, f0), _slice(p, f1) + 1):
		m = maxf(m, p.top[i])
	return m


static func _mount_f(wid: String, k: String) -> float:
	var d := Defs.weapon(wid)
	var m: Dictionary = d.get("mounts", {})
	if m.has(k):
		return float(m[k])
	var hand := str(d.get("slot", "long")) == "handgun"
	var hold: Array = d.get("hold", [0.72 if hand else 0.6, 0.3 if hand else 0.27])
	match k:
		"sight":
			return 0.55 if hand else float(hold[0]) - 0.05
		"grip":
			return float(hold[1]) + 0.03
		"light":
			return 0.25 if hand else 0.12
		"mag":
			return float(hold[0]) if hand else float(hold[0]) - 0.13
		"stock":
			return 1.0
		"cheek":
			return 0.86
		"loops":
			return 0.8
	return 0.5


static func mount_xf(map, wid: String, att: String) -> Transform3D:
	## Places the attachment's item_visual model (centred, bottom at 0) on the weapon, in weapon item_visual space.
	var p := profile(map, wid)
	var amd: Dictionary = map.item_visual(att)
	var asz: Vector3 = amd.get("size", Vector3(0.03, 0.03, 0.06))
	var axf: Transform3D = amd.get("xf", Transform3D())
	var L: float = p.len
	var front: float = p.front
	var mounts: Dictionary = Defs.weapon(wid).get("mounts", {})
	var at := Vector3.ZERO
	var anchor := Vector3.ZERO
	var basis := Basis()
	match Attach.kind(att):
		"sight":
			var f := _mount_f(wid, "sight")
			var half := asz.z * 0.5 / maxf(L, 0.01)
			var y := _max_top(p, f - half, f + half) + float(mounts.get("sight_dy", 0.0))
			at = Vector3(0, y, front + f * L)
			anchor = Vector3(0, 0, 0)
		"muzzle":
			at = Vector3(0, float(p.bore) + float(mounts.get("muzzle_dy", 0.0)), front + 0.004)
			anchor = Vector3(0, asz.y * 0.5, asz.z * 0.5)
		"grip", "light":
			var f2 := _mount_f(wid, "grip" if Attach.kind(att) == "grip" else "light")
			var i := _slice(p, f2)
			at = Vector3(0, p.bot[i] + 0.004 + float(mounts.get(Attach.kind(att) + "_dy", 0.0)), front + f2 * L)
			anchor = Vector3(0, asz.y, 0)
		"mag":
			var f3 := _mount_f(wid, "mag")
			var i3 := _slice(p, f3)
			var lo := 99.0
			for j in range(maxi(i3 - 3, 0), mini(i3 + 4, BINS)):
				lo = minf(lo, p.bot[j])
			var reach := MAG_EXT if Attach.flag({"att": [att]}, "ext") else MAG_QUICK
			basis = Basis().scaled(Vector3(1.0, reach / maxf(asz.y, 0.01), 1.0))
			at = Vector3(0, lo + 0.003, front + f3 * L)
			anchor = Vector3(0, asz.y, 0)
		"stock":
			match att:
				"cheek_pad":
					var f4 := _mount_f(wid, "cheek")
					at = Vector3(0, p.top[_slice(p, f4)] - 0.004, front + f4 * L)
					anchor = Vector3.ZERO
				"bullet_loops":
					var f5 := _mount_f(wid, "loops")
					var i5 := _slice(p, f5)
					at = Vector3(p.right[i5] - 0.002, (p.top[i5] + p.bot[i5]) * 0.5, front + f5 * L)
					anchor = Vector3(-asz.x * 0.5, asz.y * 0.5, 0)
				_:
					var i6 := BINS - 2
					at = Vector3(0, p.top[i6] - 0.02, front + L - 0.01)
					anchor = Vector3(0, asz.y - 0.035, -asz.z * 0.5)
	return Transform3D(basis, at) * Transform3D(Basis(), -anchor) * axf


static func sight_axis(map, wid: String, att: String) -> Vector3:
	## The optical axis point of a fitted sight (its middle), in weapon item_visual space.
	var a: Dictionary = Defs.attachments.get(att, {})
	var amd: Dictionary = map.item_visual(att)
	var asz: Vector3 = amd.get("size", Vector3(0.03, 0.04, 0.06))
	var h := float(a.get("axis", float(a.get("axis_f", 0.6)) * asz.y))
	var xf := mount_xf(map, wid, att) * (amd.get("xf", Transform3D()) as Transform3D).affine_inverse()
	return xf * Vector3(0, h, 0)


static func sight_rear_z(map, wid: String, att: String) -> float:
	var amd: Dictionary = map.item_visual(att)
	var asz: Vector3 = amd.get("size", Vector3(0.03, 0.04, 0.06))
	return sight_axis(map, wid, att).z + asz.z * 0.5


static func build(map, parent: Node3D, wid: String, atts: Array, layers: int, shadows: int) -> void:
	## Replaces parent's children with one MeshInstance3D per fitted attachment.
	for c in parent.get_children():
		c.queue_free()
	if wid == "":
		return
	for a in atts:
		var amd: Dictionary = map.item_visual(str(a))
		if amd.get("mesh") == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = amd.mesh
		mi.transform = mount_xf(map, wid, str(a))
		mi.layers = layers
		mi.cast_shadow = shadows
		mi.name = str(a)
		parent.add_child(mi)
