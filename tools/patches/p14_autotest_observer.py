"""Patch (test driver): the observed bot stands still with its light on while the observer shot is taken."""
p = 'A:/Python/aetherion-project/game/src/debug/autotest.gd'
s = open(p, encoding='utf-8').read()
old = '''	target.light.on = true
	var cam := Camera3D.new()'''
new = '''	target.light.on = true
	var brain = world.bots.get(target.eid)
	world.bots.erase(target.eid)
	world._queues[target.eid] = []
	target.last_cmd = {}
	var cam := Camera3D.new()'''
assert s.count(old) == 1
s = s.replace(old, new)
old = '''	cam.current = false
	ctl.cam.current = true
	cam.queue_free()'''
new = '''	cam.current = false
	ctl.cam.current = true
	cam.queue_free()
	if brain:
		world.bots[target.eid] = brain'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
