"""Patch: the out-of-world failsafe ignores players aboard the aircraft and only catches falling/canopied players
near the ground; the play-through picks a spot with a clear view of the corpse."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/match/world.gd', [(
    '''		if ch.global_position.y < -40.0 or absf(ch.global_position.x) > 640.0 or absf(ch.global_position.z) > 640.0:
			_rescue(ch)''', '''		if ch.mode != Motor.PLANE and _outside_world(ch):
			_rescue(ch)''')])
patch('src/match/world.gd', [(
    '''func _rescue(ch: Character) -> void:''', '''func _outside_world(ch: Character) -> bool:
	## Below the world, or past the edge of the terrain on foot / close to the ground (a canopy may still be steered
	## back from high up).
	var p := ch.global_position
	if p.y < -40.0:
		return true
	var off_edge := absf(p.x) > 600.0 or absf(p.z) > 600.0
	if not off_edge:
		return false
	return ch.mode in [Motor.GROUND, Motor.DOWNED] or p.y < 30.0


func _rescue(ch: Character) -> void:''')])

patch('src/debug/autotest.gd', [(
    '''	# Kneel-distance from the body, looking at its chest.
	var cc: Vector3 = c.center()
	var away: Vector3 = (ch.global_position - cc) * Vector3(1, 0, 1)
	away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
	ch.global_position = Vector3(cc.x, ch.global_position.y, cc.z) + away * 1.1
	ch.velocity = Vector3.ZERO''', '''	# Kneel-distance from the body with a clear view of it (the body may have fallen against furniture).
	var cc: Vector3 = c.center()
	var space := world.get_world_3d().direct_space_state
	var spot := Vector3(cc.x, ch.global_position.y, cc.z) + Vector3(1.1, 0, 0)
	for k in 12:
		var a := TAU * k / 12.0
		var cand := Vector3(cc.x, ch.global_position.y, cc.z) + Vector3(cos(a), 0, sin(a)) * 1.1
		var eye := cand + Vector3.UP * 1.6
		var q := PhysicsRayQueryParameters3D.create(eye, cc, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var q2 := PhysicsRayQueryParameters3D.create(cand + Vector3.UP * 1.0, Vector3(cc.x, cand.y + 1.0, cc.z), Defs.PHYS_WORLD)
		if space.intersect_ray(q).is_empty() and space.intersect_ray(q2).is_empty():
			spot = cand
			break
	ch.global_position = spot
	ch.velocity = Vector3.ZERO''')])
