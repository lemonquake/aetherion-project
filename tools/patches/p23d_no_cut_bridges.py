"""r23: closing an edge never cuts the graph (bridges, single doorways); a crowd is not a stuck edge."""
W = "game/src/ai/waypoints.gd"
B = "game/src/ai/bot_brain.gd"


def patch(path, pairs):
    s = open(path, encoding="utf-8", newline="").read()
    crlf = "\r\n" in s
    s = s.replace("\r\n", "\n")
    for a, b in pairs:
        if s.count(a) != 1:
            raise SystemExit("%s: anchor found %d times: %r" % (path, s.count(a), a[:80]))
        s = s.replace(a, b)
    if crlf:
        s = s.replace("\n", "\r\n")
    open(path, "w", encoding="utf-8", newline="").write(s)


patch(W, [(
    """	var e: Dictionary = edges[ei]
	if astar.are_points_connected(int(e.a), int(e.b), false):
		astar.disconnect_points(int(e.a), int(e.b), true)
	_blocked[ei] = Time.get_ticks_msec() + int(secs * 1000.0)""",
    """	var e: Dictionary = edges[ei]
	if not astar.are_points_connected(int(e.a), int(e.b), false):
		return
	astar.disconnect_points(int(e.a), int(e.b), true)
	# never the only way between its ends (a bridge, the one doorway of a room): closing it would cut the graph in two,
	# and every bot on the far side would be left without a route. It stays open; the bots queue there.
	var alt := astar.get_id_path(int(e.a), int(e.b))
	var direct := (nodes[int(e.a)].p as Vector3).distance_to(nodes[int(e.b)].p)
	var alt_len := 0.0
	for k in range(1, alt.size()):
		alt_len += (nodes[alt[k - 1]].p as Vector3).distance_to(nodes[alt[k]].p)
	if alt.is_empty() or alt_len > direct * 6.0 + 40.0:
		astar.connect_points(int(e.a), int(e.b), not bool(e.one))
		stats.kept_open = int(stats.get("kept_open", 0)) + 1
		return
	_blocked[ei] = Time.get_ticks_msec() + int(secs * 1000.0)""")])

patch(B, [(
    """		var wn: int = path_wp[path_i] if path_i < path_wp.size() else -1
		if wn >= 0 and _wp_prev >= 0:
			Waypoints.report_stuck(_wp_prev, wn, ch.eid)
			wp_stats.stuck_edges += 1""",
    """		var wn: int = path_wp[path_i] if path_i < path_wp.size() else -1
		if wn >= 0 and _wp_prev >= 0 and _ahead() != "char":
			Waypoints.report_stuck(_wp_prev, wn, ch.eid)   # (someone in the way is a queue, not a blocked edge)
			wp_stats.stuck_edges += 1""")])
print("patched")
