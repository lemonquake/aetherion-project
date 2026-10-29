"""r4: holes test stands 2 m out from a door on a side with floor and a clear view; chunks have a floor on their
strength and falling props only chip chunks on real impacts; the suppression round starts 9 m away."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
f = 'src/debug/autotest_r4.gd'
s = open(f, encoding='utf-8').read()
a = s.index('	# A house front: stand in front of the nearest outer door and aim at the wall beside it.')
b = s.index('	if wall.is_empty():', a)
new = '''	# A house front: stand 2 m in front of a nearby door (on a side with floor under it) and aim at the wall beside it.
	var ch = t.ch
	var wall := {}
	var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	var doors: Array = world.map.dyn.doors.filter(func(d): return d.get("node") != null and not d.node.destroyed)
	doors.sort_custom(func(a, b): return (a.xf as Transform3D).origin.distance_to(ch.global_position) < (b.xf as Transform3D).origin.distance_to(ch.global_position))
	for d in doors.slice(0, 40):
		var dn = d.node
		var xf: Transform3D = dn.current_transform()
		var side: Vector3 = xf.basis.x.normalized()
		for sgn in [1.0, -1.0]:
			var fr: Vector3 = xf.basis.z.normalized() * sgn
			var stand: Vector3 = dn.center() + fr * 2.0
			var fl := space.intersect_ray(PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.4, stand + Vector3.DOWN * 1.2, Defs.PHYS_WORLD))
			if fl.is_empty() or absf((fl.position as Vector3).y - xf.origin.y) > 0.3:
				continue
			var eye := Vector3(stand.x, xf.origin.y + 1.6, stand.z)
			for ss in [-1.0, 1.0]:
				var target: Vector3 = dn.center() + side * ss * (float(dn.w) * 0.5 + 0.55) + fr * 0.01
				var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + (target - eye) * 1.25, Defs.SHOT_MASK))
				if not h.is_empty() and h.collider and h.collider.has_meta("mat") and not h.collider.has_meta("door_id") \\
						and str(h.collider.get_meta("mat")) != "glass" and absf((h.normal as Vector3).y) < 0.3 and (h.position as Vector3).distance_to(target) < 0.5:
					t._teleport(Vector3(stand.x, xf.origin.y + 0.1, stand.z), 0.0)
					await t._wait(0.3)
					t._look_at(h.position)
					wall = h
					break
			if not wall.is_empty():
				break
		if not wall.is_empty():
			break
'''
s = s[:a] + new + s[b:]
open(f, 'w', encoding='utf-8', newline='\n').write(s)
print('wall search replaced')
patch(f, '''	var origin := head + fwd * 30.0 + side * 0.8''', '''	var origin := head + fwd * 9.0 + side * 0.8''')
patch(f, '''	t._check("outfits_draws", surf_max <= 2,''', '''	t._check("outfits_draws", surf_max <= 2 or worst_list.size() > 0 and false,''')
patch(f, '''		var surfaces := 0
		for mi in _meshes(o.visual):''', '''		var surfaces := 0
		var parts := []
		for mi in _meshes(o.visual):''')
patch(f, '''			if mi.is_visible_in_tree() and mi.mesh and not o.visual.weapon_node.is_ancestor_of(mi):
				surfaces += mi.mesh.get_surface_count()
		surf_max = maxi(surf_max, surfaces)''', '''			if mi.is_visible_in_tree() and mi.mesh and not o.visual.weapon_node.is_ancestor_of(mi):
				surfaces += mi.mesh.get_surface_count()
				parts.append("%s:%d" % [mi.name, mi.mesh.get_surface_count()])
		if surfaces > surf_max:
			worst_list = parts
		surf_max = maxi(surf_max, surfaces)''')
patch(f, '''	var keys := {}
	var surf_max := 0''', '''	var keys := {}
	var surf_max := 0
	var worst_list := []''')
patch(f, '''"at most %d mesh surfaces per character body (outfit and head; the gun as before); the hooded body had 8" % surf_max)''', '''"at most %d mesh surfaces per character body (outfit and head; the gun as before; the hooded body had 8): %s" % [surf_max, ", ".join(worst_list)])''')

f = 'src/props/physics_prop.gd'
patch(f, '''			var per := float(spec.get("hp", 100)) * 1.2 / maxf((chunk_info.keys as Array).size(), 1.0)''', '''			# Each chunk takes at least a pistol round's worth: a plastic chair loses pieces, it does not burst.
			var per := maxf(float(spec.get("hp", 100)) * 1.2 / maxf((chunk_info.keys as Array).size(), 1.0), 28.0)''')
patch(f, '''	take_damage(energy * 0.6, linear_velocity, global_position + linear_velocity.normalized() * 0.2)''', '''	# Only a real crash knocks pieces off where it lands; a tip-over just wears the whole prop.
	take_damage(energy * 0.6, linear_velocity, global_position + linear_velocity.normalized() * 0.2 if energy > 60.0 else Vector3.INF)''')
