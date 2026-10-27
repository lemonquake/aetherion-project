"""Patch (diagnostics): trace a Use press from the client's outgoing commands to the server's command processing."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/match/world.gd', [(
    '''	var pressed := btn & ~prev
	if pressed & Motor.B_USE:''', '''	var pressed := btn & ~prev
	if (pressed & Motor.B_USE) and Game.arg("netdebug") != null and not Net.is_bot(ch.pid):
		print("[netdebug] server: %s Use edge in cmd %d (mode %d)" % [ch.pname, int(cmd.get("seq", -1)), ch.mode])
	if pressed & Motor.B_USE:''')])

patch('src/debug/autotest_net.gd', [(
    '''	await _until(func(): return Time.get_unix_time_from_system() >= go, 10.0)
	await _tap("interact")
	await _wait(1.5)''', '''	await _until(func(): return Time.get_unix_time_from_system() >= go, 10.0)
	await _tap("interact")
	var used := []
	for pnd in ctl.pending:
		if int(pnd.cmd.btn) & Motor.B_USE:
			used.append(int(pnd.cmd.seq))
	print("[autotest-%s] race: commands carrying Use: %s (tab %s, paused %s, mode %d)" % [role, str(used), str(ctl.tab_held), str(ctl.paused), ch.mode])
	await _wait(1.5)'''),
])
