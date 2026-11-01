"""r23: a house plan's walk to a door: the graph's route, then the grid's way from its last waypoint to the door."""
B = "game/src/ai/bot_brain.gd"
s = open(B, encoding="utf-8", newline="").read()
CRLF = "\r\n" in s
s = s.replace("\r\n", "\n")


def rep(a, b):
    global s
    if s.count(a) != 1:
        raise SystemExit("anchor found %d times: %r" % (s.count(a), a[:80]))
    s = s.replace(a, b)


rep("var _wp_tail := {}                # the graph's part of a route waiting for the grid's way onto the graph\n",
    "var _wp_tail := {}                # the graph's part of a route waiting for the grid's way onto the graph\n"
    "var _wp_head := {}                # the graph's part of a route waiting for the grid's way from its end to a door\n")
rep("\tpath_wp = PackedInt32Array()\n\t_wp_tail = {}\n\t_wp_route = false\n",
    "\tpath_wp = PackedInt32Array()\n\t_wp_tail = {}\n\t_wp_head = {}\n\t_wp_route = false\n")
rep("""			if not _wp_tail.is_empty():
				# (r23) the grid's way onto the graph, then the graph's route
				path.append_array(_wp_tail.pts)
				path_wp.append_array(_wp_tail.wps)
				_wp_tail = {}
				_wp_route = true""", """			if not _wp_tail.is_empty():
				# (r23) the grid's way onto the graph, then the graph's route
				path.append_array(_wp_tail.pts)
				path_wp.append_array(_wp_tail.wps)
				_wp_tail = {}
				_wp_route = true
			elif not _wp_head.is_empty():
				# (r23) the graph's route, then the grid's way from its last waypoint to the house door
				var hp: Array = (_wp_head.pts as Array).duplicate()
				hp.append_array(path)
				var hw: PackedInt32Array = _wp_head.wps
				hw.append_array(path_wp)
				path = hp
				path_wp = hw
				_wp_head = {}
				_seg_from = ch.global_position""")
rep("""			path = rt.pts
			path_wp = rt.wps
			path_i = 0
			_wp_prev = -1
			_wp_route = true
			_seg_from = ch.global_position""", """			if plan_i < plan.size() and (rt.wps as PackedInt32Array)[(rt.wps as PackedInt32Array).size() - 1] >= 0 \\
					and (rt.pts[rt.pts.size() - 1] as Vector3).distance_to(goal) > 0.6:
				# a house plan's door is out of sight of every waypoint (doors in the lanes between houses): the graph's
				# route, then the grid's way from its last waypoint to the door, as house plans always walked it
				_wp_head = {"pts": rt.pts, "wps": rt.wps}
				_path_req = nav.request(rt.pts[rt.pts.size() - 1], goal, MAX_EXPAND)
				return
			path = rt.pts
			path_wp = rt.wps
			path_i = 0
			_wp_prev = -1
			_wp_route = true
			_seg_from = ch.global_position""")
if CRLF:
    s = s.replace("\n", "\r\n")
open(B, "w", encoding="utf-8", newline="").write(s)
print("patched")
