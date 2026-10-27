"""Patch (test driver): the race item must be in plain view from both standing spots (eye-height rays reach it)."""
p = 'A:/Python/aetherion-project/game/src/debug/autotest_net.gd'
s = open(p, encoding='utf-8').read()
old = '''		var clear := true
		for side in [1.0, -1.0]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.UP * 1.0 + Vector3(side, 0, 0.3).normalized() * 1.2, Defs.PHYS_WORLD | Defs.PHYS_PROP)
			if not space.intersect_ray(q).is_empty():
				clear = false'''
new = '''		var clear := true
		for side in [1.0, -1.0]:
			var stand := p + Vector3(side, 0, 0.3).normalized() * 0.9
			var eye := stand + Vector3.UP * 1.75
			# Room to stand, and an unobstructed view of the item from eye height.
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, stand + Vector3.UP * 1.0, Defs.PHYS_WORLD | Defs.PHYS_PROP)
			var q2 := PhysicsRayQueryParameters3D.create(eye, p + Vector3.UP * 0.03, Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS)
			var q3 := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.5, stand + Vector3.DOWN * 0.6, Defs.PHYS_WORLD)
			var floor_hit := space.intersect_ray(q3)
			if not space.intersect_ray(q).is_empty() or not space.intersect_ray(q2).is_empty() or floor_hit.is_empty() \
					or absf((floor_hit.position as Vector3).y - p.y) > 0.3:
				clear = false'''
assert s.count(old) == 1, s.count(old)
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
