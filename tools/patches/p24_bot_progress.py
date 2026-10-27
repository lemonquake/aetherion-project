"""Patch: bots leave by the foot of the steps; a plan step with no progress for 2.5 s (jittering against a door leaf
or a wall counts as no progress) gets a sidestep, then is skipped."""
p = 'A:/Python/aetherion-project/game/src/ai/bot_brain.gd'
s = open(p, encoding='utf-8').read()


def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:80])
    s = s.replace(old, new)


sub('''	plan.append({"p": centre + out_dir * 1.6, "nav": false})''',
    '''	plan.append({"p": centre + out_dir * (1.4 + foot_of_steps), "nav": false})''')
sub('''var _searched := {}
''', '''var _searched := {}
var _best_d := INF
var _no_progress := 0.0
''')
sub('''		plan_i += 1
		_step_t = 0.0
		_stuck_t = 0.0''', '''		plan_i += 1
		_step_t = 0.0
		_stuck_t = 0.0
		_best_d = INF
		_no_progress = 0.0''')
sub('''	var moved = ch.global_position.distance_to(_last_pos)
	_last_pos = ch.global_position
	_stuck_t = _stuck_t + dt if moved < 0.4 * dt else maxf(_stuck_t - dt, 0.0)
	if _stuck_t > 0.8:
		cmd.mx = 1.0 if int(_stuck_t * 2.0) % 2 == 0 else -1.0
		if rng.randf() < 0.1:
			cmd.btn |= Motor.B_JUMP
	if _stuck_t > 3.5:
		_stuck_t = 0.0
		_step_t = 999.0''', '''	# Progress, not motion: sliding back and forth against a door leaf is still stuck.
	if flat.length() < _best_d - 0.2:
		_best_d = flat.length()
		_no_progress = 0.0
	else:
		_no_progress += dt
	_stuck_t = _no_progress
	if _no_progress > 1.0:
		cmd.mx = 1.0 if int(_no_progress * 1.5) % 2 == 0 else -1.0
		if rng.randf() < 0.08:
			cmd.btn |= Motor.B_JUMP
	if _no_progress > 4.0:
		_step_t = 999.0''')
open(p, 'w', encoding='utf-8').write(s)
print('ok')
