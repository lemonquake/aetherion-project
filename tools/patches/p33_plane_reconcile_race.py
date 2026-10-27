"""Patch: while aboard the aircraft the client just follows the server (no prediction corrections); the item race
uses an outdoor item, stands on the item's own surface and reports what the Use ray sees."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/player/player_controller.gd', [(
    '''	var predicted: Dictionary = pending[idx].state
	var err := (predicted.pos as Vector3).distance_to(own.pos)''', '''	var predicted: Dictionary = pending[idx].state
	if int(own.mode) == Motor.PLANE and int(predicted.mode) == Motor.PLANE:
		# Aboard the aircraft the server places everyone on its path; there is nothing to predict.
		pending = pending.slice(idx + 1)
		_hard_set(own)
		return
	var err := (predicted.pos as Vector3).distance_to(own.pos)''')])

patch('src/debug/autotest_net.gd', [
    ('''	var best := -1
	var bd := INF
	for id in world.map.dyn.items:
		var it: Dictionary = world.map.dyn.items[id]
		var p: Vector3 = (it.xf as Transform3D).origin
		var d := p.distance_to(ch.global_position)
		if d < bd and str(it.entry.id) == "battery":
			bd = d
			best = id
	if best < 0:
		for id in world.map.dyn.items:
			best = id
			break''', '''	# An item lying outdoors with open ground on both sides, so both players can stand next to it.
	var best := -1
	var bd := INF
	var space := world.get_world_3d().direct_space_state
	for id in world.map.dyn.items:
		var it: Dictionary = world.map.dyn.items[id]
		var p: Vector3 = (it.xf as Transform3D).origin
		var d := p.distance_to(ch.global_position)
		if d >= bd or world.map.acoustics.zone_at(p + Vector3.UP * 0.5) != 0:
			continue
		var clear := true
		for side in [1.0, -1.0]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.UP * 1.0 + Vector3(side, 0, 0.3).normalized() * 1.2, Defs.PHYS_WORLD | Defs.PHYS_PROP)
			if not space.intersect_ray(q).is_empty():
				clear = false
		if clear:
			bd = d
			best = id'''),
    ('''	var dir := Vector3(side, 0, 0.3).normalized()
	var stand := p + dir * 0.9
	stand.y = world.map.ground_height(stand.x, stand.z) + 0.1
	await _teleport(stand, p + Vector3.UP * 0.03)''', '''	var dir := Vector3(side, 0, 0.3).normalized()
	var stand := p + dir * 0.9 + Vector3.UP * 0.1
	await _teleport(stand, p + Vector3.UP * 0.03)
	var tgt: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
	print("[autotest-%s] race: item %d at %s, me %s, use ray sees %s %s" % [role, id, str(p.snapped(Vector3.ONE * 0.01)),
		str(ch.global_position.snapped(Vector3.ONE * 0.01)), str(tgt.get("kind", "-")), str(tgt.get("id", ""))])'''),
])
