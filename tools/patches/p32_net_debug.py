"""Patch: --netdebug prints large prediction corrections and server queue depth; the item race compares the item's
own count instead of the whole inventory (battery charge changes it anyway)."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/player/player_controller.gd', [(
    '''	if err < 0.04 and not mode_diff and not w_diff:
		return
	stats.corrections += 1''', '''	if err < 0.04 and not mode_diff and not w_diff:
		return
	stats.corrections += 1
	if err > 0.25 and Game.arg("netdebug") != null:
		print("[netdebug] correction %.2f m at ack %d (pending %d): predicted %s vel %s mode %d / server %s vel %s mode %d" % [err, ack,
			pending.size(), str((predicted.pos as Vector3).snapped(Vector3.ONE * 0.01)), str((predicted.vel as Vector3).snapped(Vector3.ONE * 0.01)),
			int(predicted.mode), str((own.pos as Vector3).snapped(Vector3.ONE * 0.01)), str((own.vel as Vector3).snapped(Vector3.ONE * 0.01)), int(own.mode)])''')])

patch('src/match/world.gd', [(
    '''		else:
			_starved[eid] = 0.0
			for i in mini(n, q.size()):''', '''		else:
			_starved[eid] = 0.0
			if q.size() > 6 and Game.arg("netdebug") != null:
				print("[netdebug] server queue for %s is %d deep" % [ch.pname, q.size()])
			for i in mini(n, q.size()):''')])

patch('src/debug/autotest_net.gd', [
    ('''	var before := _bag_signature()
	await _until(func(): return Time.get_unix_time_from_system() >= go, 10.0)
	await _tap("interact")
	await _wait(1.5)
	return _bag_signature() != before


func _bag_signature() -> String:
	return JSON.stringify(ch.inv.to_dict()) + JSON.stringify(ch.wpn.slots)''', '''	var item_id := str(it.entry.id)
	var before := _holding(item_id)
	await _until(func(): return Time.get_unix_time_from_system() >= go, 10.0)
	await _tap("interact")
	await _wait(1.5)
	return _holding(item_id) > before


func _holding(item_id: String) -> int:
	## How many of this item the character has: in the bag, as gear, or as a weapon in a slot.
	var n: int = ch.inv.count(item_id)
	for g in ch.inv.gear.values():
		if g != null and str(g.get("id", "")) == item_id:
			n += 1
	for sl in ch.wpn.slots:
		if sl != null and str(sl.get("id", "")) == item_id:
			n += 1
	return n'''),
])
