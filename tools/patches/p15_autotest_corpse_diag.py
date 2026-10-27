"""Patch (test driver): report what the Use ray sees when a corpse will not open."""
p = 'A:/Python/aetherion-project/game/src/debug/autotest.gd'
s = open(p, encoding='utf-8').read()
old = '''	_check("corpse_opened", opened, "%d entries, %d batteries on body" % [(c.entries as Array).size(), their_batteries])'''
new = '''	if not opened:
		var tgt: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
		var eye: Vector3 = ch.eye_position()
		var q := PhysicsRayQueryParameters3D.create(eye, cc, 0xFFFFFFFF)
		q.exclude = [ch.get_rid()]
		var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
		print("[autotest] corpse diag: mode %d, eye %s, centre %s (%.2f m), target %s, ray hit %s layer %s meta %s" % [ch.mode, str(eye), str(cc),
			eye.distance_to(cc), str(tgt), str(hit.get("collider")), str(hit.get("collider").collision_layer if hit.get("collider") else -1),
			str(hit.get("collider").get_meta_list() if hit.get("collider") else [])])
	_check("corpse_opened", opened, "%d entries, %d batteries on body" % [(c.entries as Array).size(), their_batteries])'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
