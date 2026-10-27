"""Patch: corpse reach uses where the body lies; the server keeps every character's presentation flags current (a
host draws bots' and clients' flashlights from them); the SmarTab hand sits behind the device; the torch head faces
forward; the play-through finds the rifle's real slot."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/match/interaction.gd', [(
    '''	var corpse = world.map.dyn.corpses.get(id)
	return corpse.global_position if corpse else Vector3.INF''',
    '''	var corpse = world.map.dyn.corpses.get(id)
	return corpse.center() if corpse else Vector3.INF''')])

patch('src/match/world.gd', [(
    '''				_server_apply(ch, c, dt, tick, false)
				_acked[eid] = int(c.seq)
		_record(ch, tick)''',
    '''				_server_apply(ch, c, dt, tick, false)
				_acked[eid] = int(c.seq)
		# Presentation flags (light, aim, sprint...) for anything drawn on this machine; clients get them by snapshot.
		ch.flags = ch.compute_flags()
		_record(ch, tick)''')])

patch('src/player/viewmodel.gd', [
    ('''	hand_l.position = Vector3(0.0, -0.075, 0.03)
	hand_l.rotation = Vector3(-0.3, 0, 0)''', '''	# The left hand holds the device from behind and below; the screen faces the player.
	hand_l.position = Vector3(0.0, -0.085, -0.045)
	hand_l.rotation = Vector3(-0.35, 0, 0)'''),
    ('''	head.rotation = Vector3(PI * 0.5, 0, 0)
	head.position = Vector3(0, 0, -0.095)''', '''	head.rotation = Vector3(-PI * 0.5, 0, 0)  # wide end forward
	head.position = Vector3(0, 0, -0.095)'''),
    ('''	lens.position = Vector3(0, 0, -0.119)''', '''	lens.position = Vector3(0, 0, -0.118)'''),
])

patch('src/debug/autotest.gd', [(
    '''	var slot: int = ch.wpn.slot_for("rifle_556")
	await _tap("weapon_%d" % slot)''',
    '''	var slot := 1
	for s in [1, 2, 3]:
		if ch.wpn.slots[s] != null and str(ch.wpn.slots[s].id) == "rifle_556":
			slot = s
	await _tap("weapon_%d" % slot)''')])
