"""Trace why a bot's loose-item scan finds nothing (loot run 2026-10-26): counts per filter in the bot trace.

    python -I tools/patches/p58_bot_scan_trace.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'src', 'ai', 'bot_brain.gd')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''	var best := -1
	var bv := 0.6
	for id in world.map.dyn.items_near(ch.global_position, 7.0):
		if _skip.has("item:%d" % id):
			continue
		var it: Dictionary = world.map.dyn.items[id]
		var p: Vector3 = (it.xf as Transform3D).origin
		if absf(p.y - ch.global_position.y) > 1.5 or world.map.acoustics.zone_at(p + Vector3.UP * 0.3) != zone:
			continue
		var v = LootSense.value(ch, it.entry) - ch.global_position.distance_to(p) * 0.05
		if v > bv:
			bv = v
			best = id''', '''	var best := -1
	var bv := 0.6
	var near: Array = world.map.dyn.items_near(ch.global_position, 7.0)
	var why := {"near": near.size(), "skip": 0, "height": 0, "zone": 0, "value": 0}
	for id in near:
		if _skip.has("item:%d" % id):
			why.skip += 1
			continue
		var it: Dictionary = world.map.dyn.items[id]
		var p: Vector3 = (it.xf as Transform3D).origin
		if absf(p.y - ch.global_position.y) > 1.5:
			why.height += 1
			continue
		if world.map.acoustics.zone_at(p + Vector3.UP * 0.3) != zone:
			why.zone += 1
			continue
		var v = LootSense.value(ch, it.entry) - ch.global_position.distance_to(p) * 0.05
		if v <= bv:
			why.value += 1
		if v > bv:
			bv = v
			best = id
	_scan_why = why''')
rep('''var _scan_t := 0.0''', '''var _scan_t := 0.0
var _scan_why := {}''')
rep('''	extra += " guns " + ",".join(guns)''', '''	extra += " guns " + ",".join(guns)
	if not _scan_why.is_empty():
		extra += " scan " + str(_scan_why)''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())
print('ok')
