"""r4: the holes test aims at the wall beside the nearest outer door (the landing spot may be open ground)."""
import os
import re

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
f = 'src/debug/autotest_r4.gd'
s = open(f, encoding='utf-8').read()
new = '''	# A house front: stand in front of the nearest outer door and aim at the wall beside it.
	var ch = t.ch
	var wall := {}
	var doors: Array = world.map.dyn.doors.filter(func(d): return d.get("node") != null and not d.node.destroyed and d.has("outward"))
	doors.sort_custom(func(a, b): return (a.xf as Transform3D).origin.distance_to(ch.global_position) < (b.xf as Transform3D).origin.distance_to(ch.global_position))
	for d in doors.slice(0, 25):
		var dn = d.node
		var xf: Transform3D = dn.current_transform()
		var out: Vector3 = d.outward
		var stand: Vector3 = dn.center() + out * 3.5
		var gy: float = world.map.ground_height(stand.x, stand.z)
		if absf(gy - xf.origin.y) > 0.6:
			continue
		t._teleport(Vector3(stand.x, xf.origin.y + 0.1, stand.z), 0.0)
		await t._wait(0.2)
		var side: Vector3 = xf.basis.x.normalized()
		for sgn in [-1.0, 1.0]:
			var target: Vector3 = dn.center() + side * sgn * (float(dn.w) * 0.5 + 0.7) + out * 0.02
			var eye: Vector3 = ch.eye_position()
			var q := PhysicsRayQueryParameters3D.create(eye, eye + (target - eye) * 1.3, Defs.SHOT_MASK)
			var h: Dictionary = ch.get_world_3d().direct_space_state.intersect_ray(q)
			if not h.is_empty() and h.collider and h.collider.has_meta("mat") and not h.collider.has_meta("door_id") \\
					and absf((h.normal as Vector3).y) < 0.3 and (h.position as Vector3).distance_to(target) < 0.6:
				wall = h
				t._look_at(h.position)
				break
		if not wall.is_empty():
			break
	if wall.is_empty():
'''
pat = re.compile(r'\t# A plain wall:.*?\n\tif wall\.is_empty\(\):\n', re.S)
s2, n = pat.subn(lambda m: new, s)
print('replaced', n)
open(f, 'w', encoding='utf-8', newline='\n').write(s2)
