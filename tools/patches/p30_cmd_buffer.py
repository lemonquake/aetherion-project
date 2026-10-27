"""Patch: the server simulates a player only with that player's own commands. A short gap (late packets) waits
instead of inventing movement, and the backlog is caught up afterwards; only after 0.25 s of silence does the
character keep moving on its last stick input."""
p = 'A:/Python/aetherion-project/game/src/match/world.gd'
s = open(p, encoding='utf-8').read()
old = '''		var q: Array = _queues[eid]
		var n := 1 if q.size() <= 3 else 2
		if q.is_empty():
			# Packet loss: keep moving with the last known stick input, no new presses.
			var c: Dictionary = ch.last_cmd.duplicate() if not ch.last_cmd.is_empty() else {"seq": 0, "btn": 0, "mx": 0.0, "my": 0.0, "yaw": ch.yaw, "pitch": ch.pitch, "slot": ch.wpn.want, "view_tick": tick}
			c.btn = int(c.get("btn", 0)) & (Motor.B_SPRINT | Motor.B_CROUCH | Motor.B_WALK | Motor.B_AIM | Motor.B_FIRE | Motor.B_TAB | Motor.B_LIGHT | Motor.B_USE)
			_server_apply(ch, c, dt, tick, true)
		else:
			for i in mini(n, q.size()):
				var c: Dictionary = q.pop_front()
				_server_apply(ch, c, dt, tick, false)
				_acked[eid] = int(c.seq)'''
new = '''		var q: Array = _queues[eid]
		# Catch up a backlog a little faster than real time (never more than 3 steps a tick).
		var n := 1 if q.size() <= 2 else (2 if q.size() <= 6 else 3)
		if q.is_empty():
			_starved[eid] = float(_starved.get(eid, 0.0)) + dt
			if float(_starved[eid]) > 0.25:
				# A real outage: keep moving with the last known stick input, no new presses.
				var c: Dictionary = ch.last_cmd.duplicate() if not ch.last_cmd.is_empty() else {"seq": 0, "btn": 0, "mx": 0.0, "my": 0.0, "yaw": ch.yaw, "pitch": ch.pitch, "slot": ch.wpn.want, "view_tick": tick}
				c.btn = int(c.get("btn", 0)) & (Motor.B_SPRINT | Motor.B_CROUCH | Motor.B_WALK | Motor.B_AIM | Motor.B_FIRE | Motor.B_TAB | Motor.B_LIGHT | Motor.B_USE)
				_server_apply(ch, c, dt, tick, true)
			# else: a late packet; wait for it rather than invent a step the client never took.
		else:
			_starved[eid] = 0.0
			for i in mini(n, q.size()):
				var c: Dictionary = q.pop_front()
				_server_apply(ch, c, dt, tick, false)
				_acked[eid] = int(c.seq)'''
assert s.count(old) == 1
s = s.replace(old, new)
old = '''var _queues: Dictionary = {}     # eid -> Array of cmds
'''
new = '''var _queues: Dictionary = {}     # eid -> Array of cmds
var _starved: Dictionary = {}    # eid -> seconds without a command
'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
