"""Patch: clients present at match start receive the floor loot in one bulk message; server-gated test commands
(teleport, give) for the multi-process network test; an autotest can run on clients too."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/core/game.gd', [
    ('''	_match_started.rpc()
	world.server_start_match()
	if arg("autotest") and not Net.dedicated:
		var at: Node = load("res://src/debug/autotest.gd").new()
		at.name = "AutoTest"
		world.add_child(at)''', '''	_match_started.rpc()
	world.server_start_match()
	# Everyone who loaded with us gets the floor loot rolled during the build (doors and windows are deterministic).
	for pid in _loaded_peers:
		if pid != 1:
			world.server_send_items(pid)
	if arg("autotest") and not Net.dedicated:
		_add_autotest()


func _add_autotest() -> void:
	var scenario := str(arg("autotest"))
	var path := "res://src/debug/autotest_net.gd" if scenario.begins_with("net") else "res://src/debug/autotest.gd"
	var at: Node = load(path).new()
	at.name = "AutoTest"
	world.add_child(at)'''),
    ('''func _match_started() -> void:
	_set_state("match")
	if world:
		world.client_match_started()''', '''func _match_started() -> void:
	_set_state("match")
	if world:
		world.client_match_started()
		if arg("autotest"):
			_add_autotest()'''),
])

patch('src/match/world.gd', [
    ('''func server_sync_late_peer(pid: int) -> void:''', '''func server_send_items(pid: int) -> void:
	## Floor loot rolled on the server during the build, in one message.
	var ids := PackedInt32Array()
	var entries := []
	var xfs := []
	for id in map.dyn.items:
		ids.append(id)
		entries.append(map.dyn.items[id].entry)
		xfs.append(map.dyn.items[id].xf)
	_items_bulk.rpc_id(pid, ids, entries, xfs)


@rpc("authority", "call_remote", "reliable")
func _items_bulk(ids: PackedInt32Array, entries: Array, xfs: Array) -> void:
	if map == null:
		return
	for i in ids.size():
		if not map.dyn.items.has(ids[i]):
			map.dyn.client_spawn_item(ids[i], entries[i], xfs[i])


# ------------------------------------------------------------------ test commands (server must run with --testcheats)

func test_cmd(cmd: Dictionary) -> void:
	if is_server:
		_test_apply(local_char, cmd)
	else:
		_test_req.rpc_id(1, cmd)


@rpc("any_peer", "reliable")
func _test_req(cmd: Dictionary) -> void:
	if is_server:
		_test_apply(char_by_pid(multiplayer.get_remote_sender_id()), cmd)


func _test_apply(ch: Character, cmd: Dictionary) -> void:
	if ch == null or Game.arg("testcheats") == null:
		return
	match str(cmd.get("op", "")):
		"teleport":
			ch.global_position = cmd.pos
			ch.velocity = Vector3.ZERO
			ch.yaw = float(cmd.get("yaw", ch.yaw))
		"give":
			interaction.give(ch, (cmd.entry as Dictionary).duplicate(true))
			ch.inv.mark_dirty()


func server_sync_late_peer(pid: int) -> void:'''),
])

patch('src/world/map_builder.gd', [(
    '''	for id in dyn.items:
		world.map_item_spawn.rpc_id(pid, id, dyn.items[id].entry, dyn.items[id].xf)''',
    '''	world.server_send_items(pid)''')])
