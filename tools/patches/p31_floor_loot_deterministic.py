"""Patch: floor loot (visible to everyone anyway) is rolled from the match seed on every machine in the same order,
so every client has it from the first frame without a transfer; container contents stay server-only. The bulk item
message becomes an authoritative replace used for late joiners. Test fix: Bravo's teammate lookup."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/world/dynamics.gd', [
    ('''var loot_rng := RandomNumberGenerator.new()
''', '''var loot_rng := RandomNumberGenerator.new()
var floor_rng := RandomNumberGenerator.new()
'''),
    ('''	loot_rng.seed = match_seed * 7919 + 17
''', '''	loot_rng.seed = match_seed * 7919 + 17
	floor_rng.seed = match_seed * 6271 + 5
'''),
    ('''	if not is_server:
		return
	for c in containers:
		c.entries = roll_table(str(c.table))
		c.searched = false
	var spawn := []
	for s in loot_spots:
		var entries := roll_table(str(s.table))
		for e in entries:
			spawn.append([e, Transform3D(Basis(Vector3.UP, loot_rng.randf() * TAU), (s.pos as Vector3) + Vector3(loot_rng.randf_range(-0.15, 0.15), 0.02, loot_rng.randf_range(-0.15, 0.15)))])
	for sp in spawn:
		server_spawn_item(sp[0], sp[1], false)''', '''	# Floor loot is in plain sight: every machine rolls it from the match seed, in the same order, with the same ids.
	var spawn := []
	for s in loot_spots:
		var entries := roll_table(str(s.table), floor_rng)
		for e in entries:
			spawn.append([e, Transform3D(Basis(Vector3.UP, floor_rng.randf() * TAU), (s.pos as Vector3) + Vector3(floor_rng.randf_range(-0.15, 0.15), 0.02, floor_rng.randf_range(-0.15, 0.15)))])
	for sp in spawn:
		server_spawn_item(sp[0], sp[1], false)
	if not is_server:
		return
	# Container contents stay hidden: rolled on the server only.
	for c in containers:
		c.entries = roll_table(str(c.table))
		c.searched = false'''),
    ('''func roll_table(table: String) -> Array:''', '''func roll_table(table: String, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = loot_rng'''),
    ('''	var n := loot_rng.randi_range(int(rolls[0]), int(rolls[1]))''', '''	var n := rng.randi_range(int(rolls[0]), int(rolls[1]))'''),
    ('''		var pick := loot_rng.randf() * total''', '''		var pick := rng.randf() * total'''),
    ('''					out.append_array(make_entries(str(e[0]), e))''', '''					out.append_array(make_entries(str(e[0]), e, rng))'''),
    ('''func make_entries(id: String, e: Array) -> Array:''', '''func make_entries(id: String, e: Array, rng: RandomNumberGenerator = null) -> Array:
	if rng == null:
		rng = loot_rng'''),
    ('''		cnt = loot_rng.randi_range(int(e[2][0]), int(e[2][1]))''', '''		cnt = rng.randi_range(int(e[2][0]), int(e[2][1]))'''),
    ('''		var w := preload("res://src/weapons/weapon_state.gd").new_instance(id, loot_rng)
		if loot_rng.randf() < 0.18:''', '''		var w := preload("res://src/weapons/weapon_state.gd").new_instance(id, rng)
		if rng.randf() < 0.18:'''),
    ('''				w.att.append(allowed[loot_rng.randi_range(0, allowed.size() - 1)])''', '''				w.att.append(allowed[rng.randi_range(0, allowed.size() - 1)])'''),
    ('''				out.append({"id": "battery", "n": 1, "c": snappedf(loot_rng.randf_range(float(cr[0]), float(cr[1])), 0.01)})''',
     '''				out.append({"id": "battery", "n": 1, "c": snappedf(rng.randf_range(float(cr[0]), float(cr[1])), 0.01)})'''),
    ('''			return [{"id": id, "n": 1, "c": snappedf(loot_rng.randf_range(0.0, 0.8), 0.01)}]''',
     '''			return [{"id": id, "n": 1, "c": snappedf(rng.randf_range(0.0, 0.8), 0.01)}]'''),
])

patch('src/core/game.gd', [(
    '''	# Everyone who loaded with us gets the floor loot rolled during the build (doors and windows are deterministic).
	for pid in _loaded_peers:
		if pid != 1:
			world.server_send_items(pid)
''', '')])

patch('src/match/world.gd', [(
    '''	print("[net] received %d floor items" % ids.size())
	if map == null:
		return
	for i in ids.size():''', '''	## Authoritative list of the items on the ground (late joiners): drop what is gone, add what is new.
	if map == null:
		return
	var keep := {}
	for i in ids.size():
		keep[ids[i]] = true
	for id in map.dyn.items.keys():
		if not keep.has(id):
			map.dyn.remove_item(id)
	for i in ids.size():''')])

patch('src/debug/autotest_net.gd', [(
    '''	var alpha = null
	await _until(func():
		for o in world.characters.values():
			if o != ch and str(Net.players.get(o.pid, {}).get("name", "")) == "Alpha":
				alpha = o
				return true
		return false, 60.0)''', '''	var found := {}   # lambdas cannot assign outer locals; they can fill a dictionary
	await _until(func():
		for o in world.characters.values():
			if o != ch and str(Net.players.get(o.pid, {}).get("name", "")) == "Alpha":
				found.alpha = o
				return true
		return false, 60.0)
	var alpha = found.get("alpha")''')])
