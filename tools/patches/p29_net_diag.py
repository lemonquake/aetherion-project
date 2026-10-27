"""Patch: diagnostics for the network test (item sync counts, who a client sees, what Alpha's Use ray hits), and
the server stops sending owner state to players who have left."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/match/world.gd', [
    ('''	_items_bulk.rpc_id(pid, ids, entries, xfs)
''', '''	_items_bulk.rpc_id(pid, ids, entries, xfs)
	print("[net] sent %d floor items to %d" % [ids.size(), pid])
'''),
    ('''	if map == null:
		return
	for i in ids.size():''', '''	print("[net] received %d floor items" % ids.size())
	if map == null:
		return
	for i in ids.size():'''),
    ('''			if ch.pid == Net.local_pid:
				if hud:
					hud.on_owner_state()
				continue
			_owner_state.rpc_id(ch.pid, hd, idict)''', '''			if ch.pid == Net.local_pid:
				if hud:
					hud.on_owner_state()
				continue
			if not Net.players.get(ch.pid, {}).get("connected", false):
				continue
			_owner_state.rpc_id(ch.pid, hd, idict)'''),
])

patch('src/debug/autotest_net.gd', [
    ('''	_check("sees_teammate", alpha != null, "Alpha %s" % ("found" if alpha else "missing"))''',
     '''	if alpha == null:
		var seen := []
		for o in world.characters.values():
			seen.append("%s/%d/%s" % [o.pname, o.pid, str(Net.players.get(o.pid, {}).get("name", "?"))])
		print("[autotest-b] characters seen: %s; players: %s" % [", ".join(seen), str(Net.players.keys())])
	_check("sees_teammate", alpha != null, "Alpha %s" % ("found" if alpha else "missing"))'''),
    ('''	await _tap("interact")
	await _wait(1.2)
	_check("door_open_local"''', '''	var tgt: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
	print("[autotest-a] at door: me %s (wanted %s), door centre %s, use ray sees %s" % [str(ch.global_position.snapped(Vector3.ONE * 0.01)),
		str(stand.snapped(Vector3.ONE * 0.01)), str(c.snapped(Vector3.ONE * 0.01)), str(tgt.get("kind", "-"))])
	await _tap("interact")
	await _wait(1.2)
	_check("door_open_local"'''),
])
