"""More evidence in [lootstats] (loot run 2026-10-26): bots standing in water, loose items bots picked up, detours
and fetches started / finished.

    python -I tools/patches/p60_lootstats_counters.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class Patch:
    def __init__(self, rel):
        self.p = os.path.join(ROOT, rel)
        raw = open(self.p, 'rb').read().decode()
        self.crlf = '\r\n' in raw
        self.s = raw.replace('\r\n', '\n')

    def rep(self, a, b, cnt=1):
        assert self.s.count(a) == cnt, (self.p, a[:90], self.s.count(a))
        self.s = self.s.replace(a, b)

    def save(self):
        open(self.p, 'wb').write((self.s.replace('\n', '\r\n') if self.crlf else self.s).encode())


b = Patch('game/src/ai/bot_brain.gd')
b.rep('''static var site_boxes := []   # containers outside houses (bid -1)''', '''static var site_boxes := []   # containers outside houses (bid -1)
## Match-wide looting counters for the [lootstats] log line.
static var counts := {"detours": 0, "detour_taken": 0, "fetches": 0, "fetch_done": 0, "items_taken": 0}''')
b.rep('''		if world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			_detour = best
			_detour_t = 0.0''', '''		if world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			_detour = best
			_detour_t = 0.0
			counts.detours += 1''')
b.rep('''	if flat.length() < 1.3:
		if not world.interaction.bot_take_item(ch, _detour):
			_skip["item:%d" % _detour] = true''', '''	if flat.length() < 1.3:
		if not world.interaction.bot_take_item(ch, _detour):
			_skip["item:%d" % _detour] = true
		else:
			counts.detour_taken += 1''')
b.rep('''	_fetch = best
	_fetch.t = 0.0''', '''	_fetch = best
	counts.fetches += 1
	_fetch.t = 0.0''')
b.rep('''	if flat.length() < 1.4:
		if _fetch.kind == "item":''', '''	if flat.length() < 1.4:
		counts.fetch_done += 1
		if _fetch.kind == "item":''')
b.rep('''	_build_index()
	_pick_landing()''', '''	_build_index()
	_pick_landing()''') if '_build_index()\n\t_pick_landing()' in b.s else None
b.rep('''	team_targets = {}
	for d in world.map.dyn.doors:''', '''	team_targets = {}
	counts = {"detours": 0, "detour_taken": 0, "fetches": 0, "fetch_done": 0, "items_taken": 0}
	for d in world.map.dyn.doors:''')
b.save()

i = Patch('game/src/match/interaction.gd')
i.rep('''	var left := bot_take_entry(ch, (it.entry as Dictionary).duplicate(true))
	world.server_sound("pickup", ch.global_position + Vector3.UP, 0.0, -1)''', '''	var left := bot_take_entry(ch, (it.entry as Dictionary).duplicate(true))
	world.server_sound("pickup", ch.global_position + Vector3.UP, 0.0, -1)
	BotBrain.counts.items_taken += 1''')
i.rep('''const LootSense := preload("res://src/ai/loot_sense.gd")''', '''const LootSense := preload("res://src/ai/loot_sense.gd")
const BotBrain := preload("res://src/ai/bot_brain.gd")''')
i.save()

m = Patch('game/src/match/match_server.gd')
m.rep('''	var junk := 0
	var long_guns := 0''', '''	var junk := 0
	var long_guns := 0
	var wet := 0''')
m.rep('''		if c.mode != Motor.GROUND:
			continue
		alive += 1''', '''		if c.mode != Motor.GROUND:
			continue
		alive += 1
		if c.water_depth() > 0.3:
			wet += 1''')
m.rep('''	log_event("[lootstats] bots on the ground %d; armed %d; armed with ammo for a gun %d; long guns %d; attachments fitted %d; rounds of unusable ammo carried %d; items on the ground %d"
		% [alive, armed, fed, long_guns, atts, junk, world.map.dyn.items.size()])''', '''	var BotBrain := preload("res://src/ai/bot_brain.gd")
	log_event("[lootstats] bots on the ground %d (in water %d); armed %d; armed with ammo for a gun %d; long guns %d; attachments fitted %d; rounds of unusable ammo carried %d; items on the ground %d; bot pickups %s"
		% [alive, wet, armed, fed, long_guns, atts, junk, world.map.dyn.items.size(), str(BotBrain.counts)])''')
m.save()
print('ok')
