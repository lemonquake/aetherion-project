"""Patch: the match status line reports what bots are doing (states, containers searched, weapons carried)."""
p = 'A:/Python/aetherion-project/game/src/match/match_server.gd'
s = open(p, encoding='utf-8').read()
old = '''	var circ := zone_circle(Net.tick)
	log_event("status: %s; armed %d; shots %d; zone %d %s r=%.0f; corpses %d%s" % [str(modes), armed, shots_fired, int(zone.get("i", -1)),
		str(zone.get("state", "")), float(circ[1]), world.map.dyn.corpses.size(), perf])'''
new = '''	var circ := zone_circle(Net.tick)
	log_event("status: %s; armed %d; shots %d; zone %d %s r=%.0f; corpses %d%s" % [str(modes), armed, shots_fired, int(zone.get("i", -1)),
		str(zone.get("state", "")), float(circ[1]), world.map.dyn.corpses.size(), perf])
	if not world.bots.is_empty():
		var states := {}
		var searched := 0
		var guns := 0
		var steps := 0
		for b in world.bots.values():
			states[b.state] = states.get(b.state, 0) + 1
			searched += b._searched.size()
			steps += b.plan_i
			for sl in [1, 2, 3]:
				if b.ch.wpn.slots[sl] != null:
					guns += 1
		var opened := 0
		for c in world.map.dyn.containers:
			if c.searched:
				opened += 1
		log_event("bots: %s; containers searched by bots %d (all players %d); plan steps done %d; guns carried %d" % [str(states), searched, opened, steps, guns])'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
