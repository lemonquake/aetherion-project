"""Patch: with --netdebug the server logs every human Use press: what its ray hit and which item was taken."""
p = 'A:/Python/aetherion-project/game/src/match/interaction.gd'
s = open(p, encoding='utf-8').read()
old = '''	var t := target(ch, cmd)
	if t.is_empty():
		return
	match str(t.kind):'''
new = '''	var t := target(ch, cmd)
	if Game.arg("netdebug") != null and not Net.is_bot(ch.pid):
		print("[netdebug] %s pressed Use at %s yaw %.3f pitch %.3f: %s %s" % [ch.pname, str(ch.global_position.snapped(Vector3.ONE * 0.01)),
			float(cmd.get("yaw", 0.0)), float(cmd.get("pitch", 0.0)), str(t.get("kind", "nothing")), str(t.get("id", ""))])
	if t.is_empty():
		return
	match str(t.kind):'''
assert s.count(old) == 1
s = s.replace(old, new)
old = '''	var e: Dictionary = (it.entry as Dictionary).duplicate(true)
	var left := give(ch, e)'''
new = '''	var e: Dictionary = (it.entry as Dictionary).duplicate(true)
	var left := give(ch, e)
	if Game.arg("netdebug") != null:
		print("[netdebug] %s took item %d (%s), left over: %s" % [ch.pname, id, str(e.id), str(left)])'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
