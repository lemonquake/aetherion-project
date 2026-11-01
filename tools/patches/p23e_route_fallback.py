"""r23: a route tries the main-graph waypoints nearest the goal before giving up."""
W = "game/src/ai/waypoints.gd"
s = open(W, encoding="utf-8", newline="").read()
a = """	if best.is_empty():
		_fail("no_path", to)
		return {}"""
b = """	if best.is_empty():
		# the waypoints the goal is in sight of are cut off for now: the nearest ones that can be reached instead
		for i in _near(to, _lv(to), 40.0 if levels else 60.0, true):
			if int(nodes[i].comp) != main_comp or astar.is_point_disabled(i):
				continue
			var ids2 := astar.get_id_path(s, i) if s != i else PackedInt64Array([s])
			if not ids2.is_empty():
				best = ids2
				goal_clear = false
				break
	if best.is_empty():
		_fail("no_path", to)
		return {}"""
assert s.count(a) == 1
s = s.replace(a, b)
open(W, "w", encoding="utf-8", newline="").write(s)
print("patched")
