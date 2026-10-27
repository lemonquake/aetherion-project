"""Loot run fixes after loot2 (2026-10-26):
- Poly Haven guns (9 mm pistol, bolt rifle) are modelled along X: turn them so the muzzle points -Z (they were held
  sideways in first person, and the bolt rifle stood on its end on the ground).
- Floor loot snaps to the surface under it when the match is set up (every machine, same physics world); a spot with
  nothing solid under it, or inside something (a stair step), gets no loot.
- The loot-box test tries several boxes and stands where the Use ray actually picks the box.

    python -I tools/patches/p57_loot_fixes_2.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class Patch:
    def __init__(self, rel):
        self.p = os.path.join(ROOT, rel)
        raw = open(self.p, 'rb').read().decode()
        self.crlf = '\r\n' in raw
        self.s = raw.replace('\r\n', '\n')

    def rep(self, a, b, cnt=1):
        assert self.s.count(a) == cnt, (self.p, a[:90], self.s.count(a))
        self.s = self.s.replace(a, b)

    def save(self):
        open(self.p, 'wb').write((self.s.replace('\n', '\r\n') if self.crlf else self.s).encode())


d = Patch('game/src/world/dresser.gd')
d.rep('''	if model != "":
		var md: Dictionary = mb.models.get_model(model)
		if not md.is_empty():
			var a: AABB = md.aabb
			var c := a.get_center()
			res = {"mesh": md.mesh, "size": a.size, "xf": Transform3D(Basis(), Vector3(-c.x, -a.position.y, -c.z))}''', '''	if model != "":
		var md: Dictionary = mb.models.get_model(model)
		if not md.is_empty():
			var a: AABB = md.aabb
			# Guns are used with the muzzle toward -z; Poly Haven models lie along x.
			var rot := Basis()
			if Defs.is_weapon(id) and a.size.x > a.size.z * 1.5:
				rot = Basis(Vector3.UP, PI * 0.5 if _muzzle_at_plus_x(md.mesh, a) else -PI * 0.5)
			var ra: AABB = Transform3D(rot, Vector3.ZERO) * a
			var c := ra.get_center()
			res = {"mesh": md.mesh, "size": ra.size, "xf": Transform3D(rot, Vector3(-c.x, -ra.position.y, -c.z))}''')
d.rep('''func _pick(a: Array):''', '''static func _muzzle_at_plus_x(mesh: Mesh, a: AABB) -> bool:
	## The muzzle is the end with the smaller cross-section (barrel against grip or stock).
	var slab := a.size.x * 0.12
	var lo := [INF, -INF, INF, -INF]   # y min/max, z min/max at the -x end
	var hi := [INF, -INF, INF, -INF]
	for si in mesh.get_surface_count():
		for v in (mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var e = lo if v.x < a.position.x + slab else (hi if v.x > a.end.x - slab else null)
			if e == null:
				continue
			e[0] = minf(e[0], v.y)
			e[1] = maxf(e[1], v.y)
			e[2] = minf(e[2], v.z)
			e[3] = maxf(e[3], v.z)
	return (hi[1] - hi[0]) * (hi[3] - hi[2]) < (lo[1] - lo[0]) * (lo[3] - lo[2])


func _pick(a: Array):''')
d.save()

y = Patch('game/src/world/dynamics.gd')
y.rep('''	# Floor loot is in plain sight: every machine rolls it from the match seed, in the same order, with the same ids.
	var spawn := []
	for s in loot_spots:
		var entries := roll_table(str(s.table), floor_rng)''', '''	# Floor loot is in plain sight: every machine rolls it from the match seed, in the same order, with the same ids.
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
		var entries := roll_table(str(s.table), floor_rng)''')
y.save()

a = Patch('game/src/debug/autotest.gd')
a.rep('''func _loot_box_use() -> void:
	## Walk up to a loot box in a house, Use it: its contents open on the SmarTab and the lid opens.
	var b := _nearest_box(true)
	if b.is_empty():
		_check("loot_box_opens", false, "no closed loot box")
		return
	var c: Dictionary = world.map.dyn.containers[int(b.cid)]
	var base_y: float = (b.xf as Transform3D).origin.y
	if not _stand_by(c.pos, base_y, 1.0) and not _stand_by(c.pos, base_y, 1.4):
		_check("loot_box_opens", false, "no place to stand by %s at %s" % [str(b.name), str((c.pos as Vector3).snapped(Vector3.ONE * 0.1))])
		return
	if not ch.light.on:
		await _tap("flashlight")
	await _wait(0.6)
	_look_at(c.pos)
	await _wait(0.5)''', '''func _loot_box_use() -> void:
	## Walk up to a loot box in a house, Use it: its contents open on the SmarTab and the lid opens.
	var b := {}
	var c := {}
	var tried := {}
	for attempt in 8:
		var cand := _nearest_box_excluding(tried)
		if cand.is_empty():
			break
		tried[int(cand.cid)] = true
		var cc: Dictionary = world.map.dyn.containers[int(cand.cid)]
		var base_y: float = (cand.xf as Transform3D).origin.y
		if not _stand_by(cc.pos, base_y, 1.0) and not _stand_by(cc.pos, base_y, 1.4):
			continue
		await _wait(0.3)
		_look_at(cc.pos)
		var t0: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
		if str(t0.get("kind", "")) == "container" and int(t0.get("id", -1)) == int(cand.cid):
			b = cand
			c = cc
			break
	if b.is_empty():
		_check("loot_box_opens", false, "no loot box with a clear Use line among %d tried" % tried.size())
		return
	if not ch.light.on:
		await _tap("flashlight")
	await _wait(0.6)
	_look_at(c.pos)
	await _wait(0.5)''')
a.rep('''func _stand_by(target: Vector3''', '''func _nearest_box_excluding(skip: Dictionary) -> Dictionary:
	var dyn = world.map.dyn
	var best := {}
	var bd := INF
	for b in dyn.loot_boxes:
		var c: Dictionary = dyn.containers[int(b.cid)]
		if b.open or int(c.bid) < 0 or skip.has(int(b.cid)):
			continue
		var d := (c.pos as Vector3).distance_to(ch.global_position)
		if d < bd:
			bd = d
			best = b
	return best


func _stand_by(target: Vector3''')
a.save()
print('ok')
