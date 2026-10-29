"""r4: tests pick targets they can actually hit (clear line to a door, a visible chunk, a solid wall), count only
visible body meshes, and fire single shots one tap at a time."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
f = 'src/debug/autotest_r4.gd'
patch(f, '''			if mi.visible and mi.mesh and not o.visual.weapon_node.is_ancestor_of(mi):''', '''			if mi.is_visible_in_tree() and mi.mesh and not o.visual.weapon_node.is_ancestor_of(mi):''')
patch(f, '''			if not h.is_empty() and h.collider and h.collider.has_meta("mat") and not h.collider.has_meta("door_id") \\''', '''			if not h.is_empty() and h.collider and h.collider.has_meta("mat") and not h.collider.has_meta("door_id") and str(h.collider.get_meta("mat")) != "glass" \\''')
# chunks: aim at the lowest chunk the eye can actually see
patch(f, '''		if body and is_instance_valid(body) and not body.alive.is_empty():
			# The lowest chunk still there: legs first, so the rest has something to fall from.
			var lowest: int = body.alive[0]
			for k in body.alive:
				if (info.chunks[k].center as Vector3).y < (info.chunks[lowest].center as Vector3).y:
					lowest = k
			aim = (body as Node3D).global_transform * (info.chunks[lowest].center as Vector3)''', '''		if body and is_instance_valid(body) and not body.alive.is_empty():
			# The lowest chunk the eye can see (a ray reaches the prop there): legs first, so the rest falls.
			var order: Array = body.alive.duplicate()
			order.sort_custom(func(a, b): return (info.chunks[a].center as Vector3).y < (info.chunks[b].center as Vector3).y)
			var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
			for k in order:
				var p: Vector3 = (body as Node3D).global_transform * (info.chunks[k].center as Vector3)
				var hh := space.intersect_ray(PhysicsRayQueryParameters3D.create(ch.eye_position(), p + (p - ch.eye_position()).normalized() * 0.3, Defs.SHOT_MASK))
				if not hh.is_empty() and hh.collider == body:
					aim = hh.position
					break''')
# doors: a closed door with a clear line from one of its sides
s = open(f, encoding='utf-8').read()
old_start = s.index('	var best = null\n	var bd := INF\n	for d in dyn.doors:')
old_end = s.index('	t._shot("door_0")')
new = '''	var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	var cands: Array = []
	for d in dyn.doors:
		var dn = d.get("node")
		if dn == null or dn.destroyed or absf(dn.angle) > 0.01 or dn.locked:
			continue
		var dist: float = dn.center().distance_to(ch.global_position)
		if dist < 150.0:
			cands.append([dist, dn])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var door = null
	var stand := Vector3.ZERO
	var front := Vector3.ZERO
	var xf := Transform3D()
	for c in cands.slice(0, 40):
		var dn = c[1]
		var dxf: Transform3D = dn.current_transform()
		for sgn in [1.0, -1.0]:
			var fr: Vector3 = dxf.basis.z.normalized() * sgn
			var st: Vector3 = dn.center() + fr * 2.4
			var floor_y: float = dxf.origin.y + 0.1
			var eye := Vector3(st.x, floor_y + 1.6, st.z)
			# Every panel row in plain view from here, nothing in between.
			var clear := true
			for r in Destruct.DOOR_ROWS:
				var p: Vector3 = dxf * dn.panel_box(r).get_center()
				var hh := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, p + (p - eye).normalized() * 0.05, Defs.SHOT_MASK))
				if hh.is_empty() or hh.collider != dn:
					clear = false
					break
			var dn_ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(st + Vector3.UP * 0.5, st + Vector3.DOWN * 0.8, Defs.PHYS_WORLD))
			if clear and not dn_ray.is_empty() and absf((dn_ray.position as Vector3).y - dxf.origin.y) < 0.4:
				door = dn
				stand = Vector3(st.x, floor_y, st.z)
				front = fr
				xf = dxf
				break
		if door:
			break
	if door == null:
		t._check("door_panels", false, "no closed door with a clear line of fire in the 40 nearest")
		return
	t._teleport(stand, 0.0)
	await t._wait(0.4)
	t._look_at(door.center())
	await t._wait(0.3)
'''
s = s[:old_start] + new + s[old_end:]
open(f, 'w', encoding='utf-8', newline='\n').write(s)
print('door picking replaced')
patch(f, '''	var c0 := int(fx.particles.emitted.get("casing", 0))
	var m0 := int(fx.particles.emitted.get("muzzle", 0))
	t.ctl.pitch = -0.1
	t._act_press("fire")
	await t._wait(0.35)
	t._shot("realism_firing")
	t._act_release("fire")
	await t._wait(0.3)''', '''	var c0 := int(fx.particles.emitted.get("casing", 0))
	var m0 := int(fx.particles.emitted.get("muzzle", 0))
	t.ctl.pitch = -0.1
	for i in 4:
		t._act_press("fire")
		await t._wait(0.08)
		if i == 1:
			t._shot("realism_firing")
		t._act_release("fire")
		await t._wait(0.18)
	await t._wait(0.3)''')
