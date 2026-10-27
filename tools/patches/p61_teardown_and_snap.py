"""Loot run (2026-10-26): free the map's server-side physics and render RIDs when a match is torn down (props, glass,
doors, ground items: they leaked on every return to the menu or lobby), snap each floor item (not only its spot) to
the surface under it, and hide broken windows in place (moving them 1 km down stretched their cell's bounds).

    python -I tools/patches/p61_teardown_and_snap.py
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


d = Patch('game/src/world/dynamics.gd')
d.rep('''		s.pos = Vector3(sp.x, (hit.position as Vector3).y + 0.01, sp.z)
		var entries := roll_table(str(s.table), floor_rng)
		for e in entries:
			spawn.append([e, Transform3D(Basis(Vector3.UP, floor_rng.randf() * TAU), (s.pos as Vector3) + Vector3(floor_rng.randf_range(-0.15, 0.15), 0.02, floor_rng.randf_range(-0.15, 0.15)))])''',
      '''		s.pos = Vector3(sp.x, (hit.position as Vector3).y + 0.01, sp.z)
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
			spawn.append([e, Transform3D(Basis(Vector3.UP, yaw), p)])''')
d.rep('''	if w.has("leaf"):
		set_leaf_transform(w.leaf[0], w.leaf[1], Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))''',
      '''	if w.has("leaf"):
		set_leaf_transform(w.leaf[0], w.leaf[1], Transform3D(Basis().scaled(Vector3.ZERO), (w.xf as Transform3D).origin))''')
d.rep('''func reset_props() -> void:''', '''func dispose() -> void:
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
	for dd in doors:
		var dn = dd.get("node")
		if dn and dn.has_method("free_body"):
			dn.free_body()
	for sh in _dormant_shapes.values():
		PhysicsServer3D.free_rid(sh)
	_dormant_shapes.clear()
	for sh in _item_shapes.values():
		PhysicsServer3D.free_rid(sh)
	_item_shapes.clear()


func reset_props() -> void:''')
d.save()

w = Patch('game/src/match/world.gd')
w.rep('''func teardown() -> void:
	if hud and is_instance_valid(hud):
		hud.queue_free()''', '''func teardown() -> void:
	if map and map.dyn:
		map.dyn.dispose()
	if hud and is_instance_valid(hud):
		hud.queue_free()''')
w.save()
print('ok')
