"""Patch (test driver): stand next to the corpse before using it; stage the observer view in an open lane."""
p = 'A:/Python/aetherion-project/game/src/debug/autotest.gd'
s = open(p, encoding='utf-8').read()


def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:80])
    s = s.replace(old, new)


sub('''	_look_at(c.center())
	await _shot("corpse")''', '''	# Kneel-distance from the body, looking at its chest.
	var cc: Vector3 = c.center()
	var away: Vector3 = (ch.global_position - cc) * Vector3(1, 0, 1)
	away = away.normalized() if away.length() > 0.1 else Vector3(1, 0, 0)
	ch.global_position = Vector3(cc.x, ch.global_position.y, cc.z) + away * 1.1
	ch.velocity = Vector3.ZERO
	await _wait(0.2)
	_look_at(cc)
	await _shot("corpse")''')
sub('''		ctl.pitch -= 0.12
	_check("corpse_opened"''', '''		_look_at(cc + Vector3(randf_range(-0.2, 0.2), -0.05 * i, randf_range(-0.2, 0.2)))
	_check("corpse_opened"''')
sub('''var _shot_n := 0
''', '''var _shot_n := 0
var _lane_spot := Vector3.INF
''')
sub('''		_teleport(stand + Vector3.UP * 0.2, 0.0)
		_look_at(p - Vector3.UP * 3.0)''', '''		_teleport(stand + Vector3.UP * 0.2, 0.0)
		_lane_spot = stand
		_look_at(p - Vector3.UP * 3.0)''')
sub('''	# Stand them in the street just outside our room, armed, light on, facing a camera 4 m away.
	var spot: Vector3 = ch.global_position
	var r := _pick_room()''', '''	# Out in the lane by the bulb: find a clear 5 m line, put them at the far end, armed, light on, facing us.
	var spot: Vector3 = _lane_spot if _lane_spot != Vector3.INF else ch.global_position
	ch.global_position = spot + Vector3.UP * 0.2
	var space := world.get_world_3d().direct_space_state
	for k in 16:
		var a := TAU * k / 16.0
		var dir := Vector3(sin(a), 0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.4, spot + Vector3.UP * 1.4 + dir * 6.0, Defs.PHYS_WORLD)
		if space.intersect_ray(q).is_empty():
			ctl.yaw = atan2(-dir.x, -dir.z)
			break''')
sub('''	target.global_position = spot + fwd * 4.0''', '''	target.global_position = spot + fwd * 4.5 + Vector3.UP * 0.3''')
sub('''	ch.global_position = spot - fwd * 1.5''', '''	ch.global_position = spot - fwd * 0.5''')
open(p, 'w', encoding='utf-8').write(s)
print('patched autotest')
