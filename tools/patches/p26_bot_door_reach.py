"""Patch: bots climb toward a raised door until it is within reach before operating it, and abandon the house when
its door cannot be passed (no searching through walls)."""
p = 'A:/Python/aetherion-project/game/src/ai/bot_brain.gd'
s = open(p, encoding='utf-8').read()


def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:80])
    s = s.replace(old, new)


sub('''			var stuck_half: bool = not dn.moving and ang > 0.05 and ang < 1.0
			if shut or stuck_half:''', '''			var stuck_half: bool = not dn.moving and ang > 0.05 and ang < 1.0
			var in_reach: bool = ch.eye_position().distance_to(dn.center()) < 2.0
			if (shut or stuck_half) and in_reach:''')
sub('''				if flat.length() < 1.6:
					cmd.my = -0.5  # stand back out of the swing''', '''				if flat.length() < 0.9:
					cmd.my = -0.5  # stand back out of the swing''')
sub('''	if arrived or _step_t > (40.0 if step.nav else 9.0):
		if arrived and step.has("search"):
			if not _search(cmd, int(step.search)):
				return
		plan_i += 1''', '''	if arrived or _step_t > (40.0 if step.nav else 9.0):
		if arrived and step.has("search"):
			if not _search(cmd, int(step.search)):
				return
		if not arrived and (step.has("door") or step.nav):
			# Could not get to or through the door: leave this house alone.
			plan_i = plan.size()
			return
		plan_i += 1''')
open(p, 'w', encoding='utf-8').write(s)
print('ok')
