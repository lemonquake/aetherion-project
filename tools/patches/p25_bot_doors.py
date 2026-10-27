"""Patch: bots wait for a door to swing clear before walking through, retry a door that stopped half open, and
give a locked door a fresh press before holding Use to force it."""
p = 'A:/Python/aetherion-project/game/src/ai/bot_brain.gd'
s = open(p, encoding='utf-8').read()
old = '''	# A closed door on the way in: face it and press Use; hold Use to force a locked one.
	if step.has("door") and flat.length() < 2.2:
		var dn = world.map.dyn.doors[int(step.door)].get("node")
		if dn and absf(dn.target) < 0.05:
			var dc: Vector3 = dn.center()
			var tv: Vector3 = dc - ch.eye_position()
			cmd.yaw = atan2(-tv.x, -tv.z)
			cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
			_door_hold += dt
			if _door_hold < 3.5:
				cmd.btn |= Motor.B_USE
			if int(Time.get_ticks_msec() / 400) % 3 == 0 and not dn.locked:
				cmd.btn &= ~Motor.B_USE  # release now and then so a plain door gets a fresh press
			return
	_door_hold = 0.0'''
new = '''	# The door on the way in: open it from outside its swing, wait for it to swing clear, then walk through.
	if step.has("door") and flat.length() < 2.4:
		var dn = world.map.dyn.doors[int(step.door)].get("node")
		if dn:
			var ang := absf(dn.angle)
			var shut: bool = absf(dn.target) < 0.05
			var stuck_half: bool = not dn.moving and ang > 0.05 and ang < 1.0
			if shut or stuck_half:
				var dc: Vector3 = dn.center()
				var tv: Vector3 = dc - ch.eye_position()
				cmd.yaw = atan2(-tv.x, -tv.z)
				cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
				_door_hold += dt
				if dn.locked:
					# A fresh press, then hold to force it.
					if _door_hold > 0.15 and _door_hold < 4.0:
						cmd.btn |= Motor.B_USE
				elif fmod(_door_hold, 1.6) > 0.15 and fmod(_door_hold, 1.6) < 0.3:
					cmd.btn |= Motor.B_USE  # one press per attempt (a second press would close it again)
				if flat.length() < 1.6:
					cmd.my = -0.5  # stand back out of the swing
				if _door_hold > 9.0:
					_step_t = 999.0
				return
			if dn.moving and ang < 1.0:
				cmd.my = -0.3
				return
	_door_hold = 0.0'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
