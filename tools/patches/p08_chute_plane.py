"""Patch: a snagged canopy slides off whatever it caught and is only cut away close to the ground; the aircraft moves
from the moment the match starts (jumping opens after the pre-jump delay), so the plane camera, the characters
aboard and the aircraft model all agree."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/player/motor.gd', [(
    '''	if not landed and ch.get_slide_collision_count() > 0:
		ch.chute_snag_t += dt
		var limit := float(d.get("stuck_timeout_s", 2.0))
		if ch.chute_snag_t > limit:
			# Caught on a roof edge or a tree: cut away the canopy and drop the last metres.
			ch.mode = GROUND
			ch.emit_motion_event("chute_cut", 0.0)
			ch.chute_snag_t = 0.0
			return''',
    '''	if not landed and ch.get_slide_collision_count() > 0:
		ch.chute_snag_t += dt
		# Brushing a wall, a roof edge or a tree: the canopy drags the jumper off it and the descent continues.
		var away := Vector3.ZERO
		for i in ch.get_slide_collision_count():
			away += ch.get_slide_collision(i).get_normal()
		away.y = 0.0
		if away.length_squared() > 1e-4:
			away = away.normalized()
			ch.velocity += away * 3.0 * dt * 10.0
		var limit := float(d.get("stuck_timeout_s", 2.0))
		if ch.chute_snag_t > limit and agl < 3.2:
			# Hung up just above the ground: cut away the canopy and drop the last metre or two.
			ch.mode = GROUND
			ch.emit_motion_event("chute_cut", 0.0)
			ch.chute_snag_t = 0.0
			return
		if ch.chute_snag_t > limit * 2.0 and away != Vector3.ZERO:
			# Still caught high up: the wind pulls the canopy free.
			ch.global_position += away * 0.5
			ch.chute_snag_t = 0.0''')])

patch('src/match/match_server.gd', [
    ('''		"speed": float(Defs.rule("plane.speed", 70.0)) * 0.65, "t0": Net.tick + int(float(Defs.rule("plane.pre_jump_delay_s", 6.0)) * Defs.TICK_RATE)}''',
     '''		"speed": float(Defs.rule("plane.speed", 70.0)) * 0.65, "t0": Net.tick, "jump_after": float(Defs.rule("plane.pre_jump_delay_s", 6.0))}'''),
    ('''		var wants := (btn & Motor.B_JUMP) != 0 and t > 0.0''',
     '''		var wants := (btn & Motor.B_JUMP) != 0 and t > float(plane.get("jump_after", 0.0))'''),
    ('''			wants = wants or world.bots[ch.eid].wants_jump(p)''',
     '''			wants = wants or (world.bots[ch.eid].wants_jump(p) and t > float(plane.get("jump_after", 0.0)))'''),
])

patch('src/fx/effects.gd', [
    ('''	var k2 := (t - float(pl.t0)) / Defs.TICK_RATE / float(pl.dur)
	var pos := a.lerp(b, k2)''', '''	var k2 := maxf((t - float(pl.t0)) / Defs.TICK_RATE / float(pl.dur), 0.0)
	var pos := a.lerp(b, k2)'''),
    ('''		show = k > -0.2 and k < 1.05''', '''		show = k < 1.05'''),
])

patch('src/debug/autotest.gd', [(
    '''	await _until(func(): return (Net.tick - int(world.match_server.plane.t0)) > 120, 15.0)''',
    '''	await _until(func(): return (Net.tick - int(world.match_server.plane.t0)) > int((float(world.match_server.plane.jump_after) + 1.0) * Defs.TICK_RATE), 20.0)''')])
