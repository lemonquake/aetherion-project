"""Patch: jumping is only possible while the aircraft is over the play area and the last team is pushed out before
it leaves; free fall opens the canopy by altitude when there is no ground below; anyone below the world is put
back on land."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/match/match_server.gd', [
    ('''	plane.dur = (plane.a as Vector3).distance_to(plane.b) / float(plane.speed)
''', '''	plane.dur = (plane.a as Vector3).distance_to(plane.b) / float(plane.speed)
	# The part of the path over the play area: jumping opens when the aircraft enters it, and whoever is still
	# aboard leaves just before it crosses out again.
	var first := -1.0
	var last := -1.0
	for i in 401:
		var f := i / 400.0
		var q: Vector3 = (plane.a as Vector3).lerp(plane.b, f)
		if L.in_play_area(Vector2(q.x, q.z)) and not L.is_water(q.x, q.z):
			if first < 0.0:
				first = f
			last = f
	if first < 0.0:
		first = 0.4
		last = 0.6
	plane.open_s = maxf(first * float(plane.dur), float(plane.get("jump_after", 0.0)))
	plane.close_s = maxf(last * float(plane.dur) - 1.5, float(plane.open_s) + 5.0)
'''),
    ('''		var wants := (btn & Motor.B_JUMP) != 0 and t > float(plane.get("jump_after", 0.0))
		if world.bots.has(ch.eid):
			wants = wants or (world.bots[ch.eid].wants_jump(p) and t > float(plane.get("jump_after", 0.0)))
		if wants:
			team_jump(ch.team)
	if t >= float(plane.dur) - 0.5:''', '''		var over := t > float(plane.open_s) and t < float(plane.close_s)
		var wants := (btn & Motor.B_JUMP) != 0 and over
		if world.bots.has(ch.eid):
			wants = wants or (world.bots[ch.eid].wants_jump(p) and over)
		if wants:
			team_jump(ch.team)
	if t >= float(plane.close_s):'''),
])

patch('src/player/motor.gd', [(
    '''	if ch.freefall_t > float(d.get("min_freefall_s", 2.5)) and (pressed_open or agl < float(d.get("auto_open_agl", 110.0))):''',
    '''	# With nothing below (off the edge of the map) the altitude itself decides.
	var low: bool = agl < float(d.get("auto_open_agl", 110.0)) or (agl > 590.0 and ch.global_position.y < 120.0)
	if ch.freefall_t > float(d.get("min_freefall_s", 2.5)) and (pressed_open or low):''')])

patch('src/match/world.gd', [(
    '''		# Presentation flags (light, aim, sprint...) for anything drawn on this machine; clients get them by snapshot.
		ch.flags = ch.compute_flags()''',
    '''		# Presentation flags (light, aim, sprint...) for anything drawn on this machine; clients get them by snapshot.
		ch.flags = ch.compute_flags()
		if ch.global_position.y < -40.0 or absf(ch.global_position.x) > 640.0 or absf(ch.global_position.z) > 640.0:
			_rescue(ch)'''),
    ('''func _reload_sounds(ch: Character, st0: int, rounds0: int) -> void:''', '''func _rescue(ch: Character) -> void:
	## Failsafe: someone left the world (fell through, flew off the edge). Put them on the nearest dry land.
	var L = map.layout
	var p := Vector2(clampf(ch.global_position.x, -L.PLAY_HALF + 20.0, L.PLAY_HALF - 20.0), clampf(ch.global_position.z, -L.PLAY_HALF + 20.0, L.PLAY_HALF - 20.0))
	for r in [0.0, 10.0, 25.0, 50.0, 80.0, 120.0]:
		var found := false
		for k in 12:
			var q := p + Vector2(cos(k * TAU / 12.0), sin(k * TAU / 12.0)) * r
			if not L.is_water(q.x, q.y) and L.in_play_area(q):
				p = q
				found = true
				break
		if found:
			break
	ch.global_position = Vector3(p.x, L.ground_height(p.x, p.y) + 1.0, p.y)
	ch.velocity = Vector3.ZERO
	print("[world] rescued %s back onto land at %s" % [ch.pname, str(ch.global_position.round())])
	if ch.mode in [Motor.FREEFALL, Motor.CHUTE]:
		server_set_mode(ch, Motor.GROUND)
	else:
		server_set_mode(ch, ch.mode)


func _reload_sounds(ch: Character, st0: int, rounds0: int) -> void:'''),
])

patch('src/debug/autotest.gd', [(
    '''	await _until(func(): return (Net.tick - int(world.match_server.plane.t0)) > int((float(world.match_server.plane.jump_after) + 1.0) * Defs.TICK_RATE), 20.0)''',
    '''	await _until(func(): return (Net.tick - int(world.match_server.plane.t0)) > int((float(world.match_server.plane.open_s) + 1.0) * Defs.TICK_RATE), 60.0)''')])
patch('src/debug/autotest_net.gd', [(
    '''	await _until(func(): return Net.interp_tick() - float(pl.t0) > (float(pl.get("jump_after", 6.0)) + 1.5) * Defs.TICK_RATE, 30.0)''',
    '''	await _until(func(): return Net.interp_tick() - float(pl.t0) > (float(pl.get("open_s", 6.0)) + 1.5) * Defs.TICK_RATE, 60.0)''')])
