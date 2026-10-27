"""Patch (test driver): when the Use ray misses the race item, say what a full-mask ray from the eye hits first."""
p = 'A:/Python/aetherion-project/game/src/debug/autotest_net.gd'
s = open(p, encoding='utf-8').read()
old = '''	print("[autotest-%s] race: item %d at %s, me %s, use ray sees %s %s" % [role, id, str(p.snapped(Vector3.ONE * 0.01)),
		str(ch.global_position.snapped(Vector3.ONE * 0.01)), str(tgt.get("kind", "-")), str(tgt.get("id", ""))])'''
new = '''	var node = it.get("node")
	var q := PhysicsRayQueryParameters3D.create(ch.eye_position(), p + Vector3.UP * 0.03, 0xFFFFFFFF)
	q.exclude = [ch.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	var hc = hit.get("collider")
	print("[autotest-%s] race: item %d at %s (node %s), me %s, eye-to-item %.2f m, use ray sees %s %s; full ray hits %s layer %s at %s" % [role, id,
		str(p.snapped(Vector3.ONE * 0.01)), str(node.global_position.snapped(Vector3.ONE * 0.01)) if node and is_instance_valid(node) else "none",
		str(ch.global_position.snapped(Vector3.ONE * 0.01)), ch.eye_position().distance_to(p), str(tgt.get("kind", "-")), str(tgt.get("id", "")),
		str(hc.name) if hc else "nothing", str(hc.collision_layer) if hc and "collision_layer" in hc else "-",
		str((hit.get("position", Vector3.ZERO) as Vector3).snapped(Vector3.ONE * 0.01))])'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
