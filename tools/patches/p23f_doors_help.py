"""r23: door edges force a locked door (as house plans do) and never loop; help orders follow a teammate who moves on."""
B = "game/src/ai/bot_brain.gd"
s = open(B, encoding="utf-8", newline="").read()
CRLF = "\r\n" in s
s = s.replace("\r\n", "\n")


def rep(a, b):
    global s
    if s.count(a) != 1:
        raise SystemExit("anchor found %d times: %r" % (s.count(a), a[:80]))
    s = s.replace(a, b)


rep("""	if dn.locked or _wpdoor_t > 8.0:
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
		cmd.btn |= Motor.B_USE""", """	if _wpdoor_t > 8.0:
		# it will not open (locked fast, jammed): that edge closes for a while and the bot goes round; when it is the only
		# way (Waypoints.block keeps such an edge open), this walk ends here instead of coming back to the door for ever
		wp_stats.locked += 1
		var ei := Waypoints.edge_between(a, b)
		Waypoints.block(ei, 120.0)
		_wpdoor_t = 0.0
		if Waypoints._blocked.has(ei):
			_set_goal(goal)
		else:
			goal = Vector3.INF
			_ended_short = true
		return true
	if _wpdoor_t == 0.0:
		wp_stats.door_waits += 1
	_wpdoor_t += dt
	var tv: Vector3 = dc - eye
	cmd.yaw = atan2(-tv.x, -tv.z)
	cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
	if dn.locked:
		# locked: a fresh press, then held to force it (as on the way into a house)
		if _wpdoor_t > 0.15 and _wpdoor_t < 4.0:
			cmd.btn |= Motor.B_USE
	elif fmod(_wpdoor_t, 1.6) > 0.15 and fmod(_wpdoor_t, 1.6) < 0.3:
		cmd.btn |= Motor.B_USE""")

rep("""	if str(order.kind) == "help":
		var src = world.characters.get(int(order.from))
		if src != null and (src.global_position as Vector3).distance_to(p) > 4.0:
			p = src.global_position
			order.p = p
			_set_goal(p)""", """	if str(order.kind) == "help":
		var src = world.characters.get(int(order.from))
		if src != null and (src.global_position as Vector3).distance_to(p) > 4.0:
			p = src.global_position
			order.p = p
			_set_goal(p)
			# (r23) the teammate moved on: after it again (a helper that had got there stood where it was)
			if bool(order.arrived):
				order.arrived = false
				order.said = true""")
rep("""		goal = Vector3.INF
		say("clear" if str(order.kind) == "check" else "in_position", true)""", """		goal = Vector3.INF
		if not bool(order.get("said", false)):
			say("clear" if str(order.kind) == "check" else "in_position", true)""")
if CRLF:
    s = s.replace("\n", "\r\n")
open(B, "w", encoding="utf-8", newline="").write(s)
print("patched")
