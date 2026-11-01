"""r23: bots walk the waypoint graph (game/src/ai/waypoints.gd): routes, edge steering, door edges, stuck edges."""
import sys

P = sys.argv[1] if len(sys.argv) > 1 else "game/src/ai/bot_brain.gd"
s = open(P, encoding="utf-8", newline="").read()
CRLF = "\r\n" in s
s = s.replace("\r\n", "\n")


def rep(a, b):
    global s
    if s.count(a) != 1:
        raise SystemExit("patch anchor found %d times: %r" % (s.count(a), a[:80]))
    s = s.replace(a, b)


rep('''var _path_pending := false
var _path_req := 0
''', '''var _path_pending := false
var _path_req := 0
# r23: the waypoint graph (waypoints.gd). A path from it is a list of nodes; the bot walks edge to edge.
var path_wp := PackedInt32Array() # the node of each path point (-1: a grid point or the goal)
var _wp_prev := -1                # the node last reached: the edge walked now starts there (-1: from where the bot set off)
var _seg_from := Vector3.INF      # where the stretch walked now starts
var _wp_tail := {}                # the graph's part of a route waiting for the grid's way onto the graph
var _wp_route := false            # the path in hand came from the graph
var _wp_check_t := 0.0
var _wp_ok_next := false
var _off_line_t := 0.0
var _wpdoor_t := 0.0
static var wp_stats := {"routes": 0, "leads": 0, "grid": 0, "off_line": 0, "stuck_edges": 0, "door_waits": 0, "locked": 0}
''')

rep('''	goal = g
	_no_prog = 0.0
	_best_wp = INF
	path = []
	path_i = 0
''', '''	goal = g
	_no_prog = 0.0
	_best_wp = INF
	path = []
	path_i = 0
	path_wp = PackedInt32Array()
	_wp_tail = {}
	_wp_route = false
	_wp_prev = -1
''')

rep('''func _ensure_path() -> void:
	if _path_req != 0:
		var r = nav.take(_path_req)
		if r != null:
			_path_req = 0
			path = r
			path_i = 0
''', '''func _ensure_path() -> void:
	if _path_req != 0:
		var r = nav.take(_path_req)
		if r != null:
			_path_req = 0
			path = r
			path_i = 0
			path_wp = PackedInt32Array()
			path_wp.resize(path.size())
			path_wp.fill(-1)
			_wp_prev = -1
			_seg_from = ch.global_position
			if not _wp_tail.is_empty():
				# (r23) the grid's way onto the graph, then the graph's route
				path.append_array(_wp_tail.pts)
				path_wp.append_array(_wp_tail.wps)
				_wp_tail = {}
				_wp_route = true
''')

rep('''	if not _path_pending or goal == Vector3.INF:
		return
	_path_pending = false
	_path_req = nav.request(ch.global_position, goal, MAX_EXPAND)
''', '''	if not _path_pending or goal == Vector3.INF:
		return
	_path_pending = false
	if Waypoints.ready():
		# r23: the waypoint graph: from the node the bot can walk straight to, along proven edges, to the node the goal
		# is in plain sight of (and the goal), or to the node nearest it when it is not.
		var rt := Waypoints.route(ch.global_position, goal)
		if rt.has("pts"):
			if rt.has("lead"):
				# nowhere near a node it can walk straight to (pushed into a corner, fallen somewhere): the grid's way to
				# the nearest node first
				_wp_tail = {"pts": rt.pts, "wps": rt.wps}
				_path_req = nav.request(ch.global_position, rt.lead, MAX_EXPAND)
				wp_stats.leads += 1
				return
			path = rt.pts
			path_wp = rt.wps
			path_i = 0
			_wp_prev = -1
			_wp_route = true
			_seg_from = ch.global_position
			# already past the first node (a new route every few seconds): on to the next when the way there is clear
			if path.size() > 1 and path_wp[0] >= 0 and (path[0] as Vector3).distance_to(ch.global_position) < 4.0 \\
					and Waypoints.clear(ch.global_position, path[1]):
				path_i = 1
			wp_stats.routes += 1
			return
	wp_stats.grid += 1
	_path_req = nav.request(ch.global_position, goal, MAX_EXPAND)
''')

rep('''	if path_i < path.size():
		target = path[path_i]
		# (r21) on to the next waypoint only when right at this one, or when the next is in plain sight from here: a
		# waypoint just through a doorway counted as reached from inside the room sent bots along the inside of the
		# wall toward the one after it. (Stair and escalator points, off the floor's walk grid, keep the loose reach.)
		var dw := Vector2(target.x - ch.global_position.x, target.z - ch.global_position.z).length()
		if dw < 0.45 or (dw < 1.2 and (path_i + 1 >= path.size() or absf((path[path_i + 1] as Vector3).y - target.y) > 0.5
				or not nav.walkable_at(target) or nav.line_clear(ch.global_position, path[path_i + 1]))):
			path_i += 1
			_best_wp = INF
	var to = target - ch.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 0.6 and path_i >= path.size():
		goal = Vector3.INF
		return
	# r21: the path is walked and the goal is still off, behind something: that path ended as near as the walk gets
	# (the goal is in a pocket or on another floor with no way there). Done, rather than pushing at the wall. (On a
	# storeyed map only: on the flat maps a long search stops early on purpose and the next one carries on from its end.)
	if path_i >= path.size() and not _path_pending and _path_req == 0 and flat.length() > 1.5 and nav.get("levels") != null \\
			and not nav.line_clear(ch.global_position, goal):
		goal = Vector3.INF
		return
	var want_yaw := atan2(-flat.x, -flat.y)
''', '''	var node := -1
	if path_i < path.size():
		target = path[path_i]
		node = path_wp[path_i] if path_i < path_wp.size() else -1
		var dw := Vector2(target.x - ch.global_position.x, target.z - ch.global_position.z).length()
		if node >= 0 and not (str(Waypoints.nodes[node].kind) in ["stair", "escalator"]):
			# (r23) a waypoint node: reached at 0.45 m, or at 1.2 m when a body can walk straight on to the next point
			# from here (swept, checked five times a second). Never on round a corner it cannot see past.
			var adv := dw < 0.45
			if not adv and dw < 1.2 and path_i + 1 < path.size():
				_wp_check_t -= dt
				if _wp_check_t <= 0.0:
					_wp_check_t = 0.2
					var nx_p: Vector3 = path[path_i + 1]
					_wp_ok_next = absf(nx_p.y - target.y) < 0.5 and Waypoints.clear(ch.global_position, nx_p)
				adv = _wp_ok_next
			if adv:
				_wp_prev = node
				_seg_from = target
				_wp_ok_next = false
				_wp_check_t = 0.0
				path_i += 1
				_best_wp = INF
		# (r21) on to the next waypoint only when right at this one, or when the next is in plain sight from here: a
		# waypoint just through a doorway counted as reached from inside the room sent bots along the inside of the
		# wall toward the one after it. (Stair and escalator points, off the floor's walk grid, keep the loose reach.)
		elif dw < 0.45 or (dw < 1.2 and (path_i + 1 >= path.size() or absf((path[path_i + 1] as Vector3).y - target.y) > 0.5
				or not nav.walkable_at(target) or nav.line_clear(ch.global_position, path[path_i + 1]))):
			if node >= 0:
				_wp_prev = node
			_seg_from = target
			path_i += 1
			_best_wp = INF
		if path_i < path.size():
			target = path[path_i]
			node = path_wp[path_i] if path_i < path_wp.size() else -1
		else:
			target = goal
			node = -1
	var to = target - ch.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 0.6 and path_i >= path.size():
		goal = Vector3.INF
		return
	# r21: the path is walked and the goal is still off, behind something: that path ended as near as the walk gets
	# (the goal is in a pocket or on another floor with no way there). Done, rather than pushing at the wall. (On a
	# storeyed map only: on the flat maps a long search stops early on purpose and the next one carries on from its end.
	# (r23) A route of the waypoint graph ends at the goal only when the goal is in plain sight of its last node: on
	# every map its end is as near as the roads get.)
	if path_i >= path.size() and not _path_pending and _path_req == 0 and flat.length() > 1.5 and (_wp_route or nav.get("levels") != null) \\
			and not nav.line_clear(ch.global_position, goal):
		goal = Vector3.INF
		return
	# r23: on an edge of the graph the bot steers for a point a metre ahead of itself on the edge, not for its end, so
	# it keeps to the line that was swept clear; pushed well off it (a crowd, a fight), it plans again from where it is.
	var steer := target
	if node >= 0 and _seg_from != Vector3.INF:
		var ab := Vector2(target.x - _seg_from.x, target.z - _seg_from.z)
		var seg_len := ab.length()
		if seg_len > 0.6:
			var u := ab / seg_len
			var rel := Vector2(ch.global_position.x - _seg_from.x, ch.global_position.z - _seg_from.z)
			var along := clampf(rel.dot(u) + 1.0, 0.0, seg_len)
			steer = Vector3(_seg_from.x + u.x * along, target.y, _seg_from.z + u.y * along)
			if absf(rel.cross(u)) > 1.8 and not _off_floor():
				_off_line_t += dt
				if _off_line_t > 1.0:
					_off_line_t = 0.0
					wp_stats.off_line += 1
					_set_goal(goal)
					return
			else:
				_off_line_t = 0.0
		# a door on this edge: open it first
		if _wp_prev >= 0:
			var e := Waypoints.edge(Waypoints.edge_between(_wp_prev, node))
			if not e.is_empty() and str(e.kind) == "door" and int(e.door) >= 0 and _wp_door(cmd, dt, int(e.door), _wp_prev, node):
				return
	var sv := Vector2(steer.x - ch.global_position.x, steer.z - ch.global_position.z)
	if sv.length() < 0.05:
		sv = flat
	var want_yaw := atan2(-sv.x, -sv.y)
''')

rep('''	if _no_prog > 3.2:
		var fwd := -Basis(Vector3.UP, yaw).z
		if _ahead() in ["wall", "low"]:
			BotTeam.note_stuck(nav, ch.global_position + fwd * 1.2, ch.eid)
''', '''	if _no_prog > 3.2:
		var fwd := -Basis(Vector3.UP, yaw).z
		# (r23) stuck on an edge of the waypoint graph: it closes for every bot for a while (and for the rest of the
		# match after three reports), so the next route goes another way
		var wn: int = path_wp[path_i] if path_i < path_wp.size() else -1
		if wn >= 0 and _wp_prev >= 0:
			Waypoints.report_stuck(_wp_prev, wn, ch.eid)
			wp_stats.stuck_edges += 1
		if _ahead() in ["wall", "low"]:
			BotTeam.note_stuck(nav, ch.global_position + fwd * 1.2, ch.eid)
''')

rep('''		_feel_mx = clampf(push * 1.5, -0.9, 0.9)
	if absf(_feel_mx) > 0.05:
		cmd.mx = clampf(float(cmd.mx) + _feel_mx, -1.0, 1.0)
''', '''		_feel_mx = clampf(push * 1.5, -0.9, 0.9)
		if path_i < path_wp.size() and path_wp[path_i] >= 0:
			_feel_mx *= 0.5   # (r23) on a swept edge: the line itself keeps off the walls; whiskers only nudge
	if absf(_feel_mx) > 0.05:
		cmd.mx = clampf(float(cmd.mx) + _feel_mx, -1.0, 1.0)
''')

rep('''func _gait(cmd: Dictionary, dist: float, slow: bool) -> void:''', '''func _wp_door(cmd: Dictionary, dt: float, di: int, a: int, b: int) -> bool:
	## r23: the edge walked goes through door di. Shut and within reach: face it and open it (one press per try), out
	## of its swing, and wait while it swings open. Locked, or still shut after 8 s: that edge closes for a while and
	## the bot routes round it. True while the door holds the bot up.
	var dn = world.map.dyn.doors[di].get("node") if di < world.map.dyn.doors.size() else null
	if dn == null or bool(dn.get("destroyed")):
		return false
	var ang := absf(float(dn.angle))
	var shut: bool = ang <= dn.OPEN_PASS and absf(float(dn.target)) < 0.05 and not dn.free
	if not shut:
		if dn.moving and ang <= dn.OPEN_PASS:
			cmd.my = 0.0
			return true
		_wpdoor_t = 0.0
		return false
	var dc: Vector3 = dn.center()
	var eye: Vector3 = ch.eye_position()
	if eye.distance_to(dc) > 2.0:
		return false
	if dn.locked or _wpdoor_t > 8.0:
		if dn.locked:
			wp_stats.locked += 1
		Waypoints.block(Waypoints.edge_between(a, b), 120.0 if dn.locked else 40.0)
		_wpdoor_t = 0.0
		_set_goal(goal)
		return true
	if _wpdoor_t == 0.0:
		wp_stats.door_waits += 1
	_wpdoor_t += dt
	var tv: Vector3 = dc - eye
	cmd.yaw = atan2(-tv.x, -tv.z)
	cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
	if fmod(_wpdoor_t, 1.6) > 0.15 and fmod(_wpdoor_t, 1.6) < 0.3:
		cmd.btn |= Motor.B_USE
	cmd.my = -0.5 if Vector2(dc.x - ch.global_position.x, dc.z - ch.global_position.z).length() < 0.9 else 0.0
	return true


func _gait(cmd: Dictionary, dist: float, slow: bool) -> void:''')

rep('''		BotNav.prepare(world, nav)   # r21: the walk checked against the real collision; waypoints and hiding spots
''', '''		BotNav.prepare(world, nav)   # r21: the walk checked against the real collision; waypoints and hiding spots
		Waypoints.prepare(world, nav)   # r23: the waypoint graph bots walk (waypoints.gd)
''')
rep('''const BotNav := preload("res://src/ai/bot_nav.gd")
''', '''const BotNav := preload("res://src/ai/bot_nav.gd")
const Waypoints := preload("res://src/ai/waypoints.gd")
''')
if CRLF:
    s = s.replace("\n", "\r\n")
open(P, "w", encoding="utf-8", newline="").write(s)
print("patched", P)
