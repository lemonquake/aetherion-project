"""Patch: bot CPU budget - one path search per tick with a smaller expansion cap, and a 40 m grid of buildings so
looking for the next house checks a few cells instead of every building on the map."""
p = 'A:/Python/aetherion-project/game/src/ai/bot_brain.gd'
s = open(p, encoding='utf-8').read()


def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:80])
    s = s.replace(old, new)


sub('''const SEARCHES_PER_TICK := 2''', '''const SEARCHES_PER_TICK := 1
const MAX_EXPAND := 3000
const BCELL := 40.0''')
sub('''static var conts_by_bid := {}
''', '''static var conts_by_bid := {}
static var bgrid := {}   # Vector2i(40 m cell) -> [building]
''')
sub('''	path = nav.find_path(ch.global_position, goal)
	path_i = 0''', '''	path = nav.find_path(ch.global_position, goal, MAX_EXPAND)
	path_i = 0''')
sub('''	doors_by_bid = {}
	conts_by_bid = {}''', '''	doors_by_bid = {}
	conts_by_bid = {}
	bgrid = {}
	for b in world.map.buildings:
		var o: Vector3 = (b.xf as Transform3D).origin
		var k := Vector2i(floori(o.x / BCELL), floori(o.z / BCELL))
		if not bgrid.has(k):
			bgrid[k] = []
		bgrid[k].append(b)''')
sub('''	var best = null
	var bd := INF
	for b in world.map.buildings:
		if _visited.has(b.id) or not doors_by_bid.has(b.id) or not conts_by_bid.has(b.id):
			continue''', '''	var best = null
	var bd := INF
	var here := Vector2i(floori(ch.global_position.x / BCELL), floori(ch.global_position.z / BCELL))
	var near := []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			near.append_array(bgrid.get(here + Vector2i(dx, dz), []))
	for b in near:
		if _visited.has(b.id) or not doors_by_bid.has(b.id) or not conts_by_bid.has(b.id):
			continue''')
open(p, 'w', encoding='utf-8').write(s)
print('ok')
