"""Patch: quick taps are never lost. Commands sample held state once per physics tick; at a low frame rate a tap can
be pressed and released between two samples. Presses of edge-triggered actions are latched from the input events
and included in the next command."""
p = 'A:/Python/aetherion-project/game/src/player/player_controller.gd'
s = open(p, encoding='utf-8').read()


def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:80])
    s = s.replace(old, new)


sub('''var stats := {"corrections": 0, "replayed": 0, "acks": 0, "max_error": 0.0}
''', '''var stats := {"corrections": 0, "replayed": 0, "acks": 0, "max_error": 0.0}
## Taps seen as input events since the last command (bit per action); added to the next command so a press and
## release inside one render frame still reaches the server.
var _latched := 0
const LATCH := {"interact": Motor.B_USE, "reload": Motor.B_RELOAD, "heal": Motor.B_HEAL, "fire_mode": Motor.B_FIREMODE,
	"drop_held": Motor.B_DROP, "jump": Motor.B_JUMP, "fire": Motor.B_FIRE, "flashlight": Motor.B_LIGHT}
''')
sub('''	if paused or results:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:''', '''	if paused or results:
		return
	for a in LATCH:
		if event.is_action_pressed(a):
			_latched |= int(LATCH[a])
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:''')
sub('''		if tab_held:
			btn |= Motor.B_TAB
	else:
		tab_held = false''', '''		if tab_held:
			btn |= Motor.B_TAB
			# With the SmarTab up only the light and jump taps carry through (weapon actions are blocked).
			btn |= _latched & (Motor.B_LIGHT | Motor.B_JUMP)
		else:
			btn |= _latched
	else:
		tab_held = false
	_latched = 0''')
open(p, 'w', encoding='utf-8').write(s)
print('ok')
