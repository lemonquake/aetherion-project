"""T grabs objects (E no longer does), V pings: new command bits, controller input, server handling, prompts, touch."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

m = Patch('game/src/player/motor.gd')
if 'B_GRAB' not in m.s:
  m.rep('''const B_PTT := 8192
''', '''const B_PTT := 8192
const B_GRAB := 16384
const B_PING := 32768
''')
  m.save()

c = Patch('game/src/player/player_controller.gd')
c.rep('''	"drop_held": Motor.B_DROP, "jump": Motor.B_JUMP, "fire": Motor.B_FIRE, "flashlight": Motor.B_LIGHT}''',
      '''	"drop_held": Motor.B_DROP, "jump": Motor.B_JUMP, "fire": Motor.B_FIRE, "flashlight": Motor.B_LIGHT,
	"grab": Motor.B_GRAB, "ping": Motor.B_PING}''')
c.rep('''			if Input.is_action_pressed("interact"):
				btn |= Motor.B_USE
''', '''			if Input.is_action_pressed("interact"):
				btn |= Motor.B_USE
			if Input.is_action_pressed("grab"):
				btn |= Motor.B_GRAB
''')
c.rep('''			# With the SmarTab up only the light and jump taps carry through (weapon actions are blocked).
			btn |= _latched & (Motor.B_LIGHT | Motor.B_JUMP)''', '''			# With the SmarTab up only the light, jump and ping taps carry through (weapon actions are blocked).
			btn |= _latched & (Motor.B_LIGHT | Motor.B_JUMP | Motor.B_PING)''')
c.save()

w = Patch('game/src/match/world.gd')
w.rep('''	if pressed & Motor.B_DROP:
		interaction.server_drop_held(ch, false)''', '''	if pressed & Motor.B_GRAB:
		interaction.server_grab(ch, cmd)
	if pressed & Motor.B_PING:
		server_ping(ch)
	if pressed & Motor.B_DROP:
		interaction.server_drop_held(ch, false)''')
w.save()

i = Patch('game/src/match/interaction.gd')
i.rep('''	if _held.has(ch.eid):
		server_drop_held(ch, false)
		return
	var t := target(ch, cmd)''', '''	var t := target(ch, cmd)''')
i.rep('''		"prop":
			_grab(ch, int(t.id))
		"revive":''', '''		"revive":''')
i.rep('''# ------------------------------------------------------------------ grabbing, dragging, throwing
''', '''# ------------------------------------------------------------------ grabbing, dragging, throwing

func server_grab(ch, cmd: Dictionary) -> void:
	## T: pick up, drag or carry the object pointed at; T again puts it down. Kept apart from Use (E), which only
	## takes weapons, ammunition and items, so grabbing a bottle never gets in the way of picking up a gun.
	if ch.mode != Motor.GROUND:
		return
	if _held.has(ch.eid):
		server_drop_held(ch, false)
		return
	var t := target(ch, cmd)
	if str(t.get("kind", "")) == "prop":
		_grab(ch, int(t.id))
''')
i.save()

h = Patch('game/src/ui/hud.gd')
h.rep('''			return "Fire: throw    Use: put down" if Settings.touch_active() else "Left mouse: throw    E: put down"''',
      '''			return "Fire: throw    Grab: put down" if Settings.touch_active() else "Left mouse: throw    %s: put down" % Settings.binding_label("grab")''')
h.rep('''			return "%s  %s" % [key, "Drag" if m > float(Defs.rule("interaction.carry_mass_limit", 22.0)) else "Pick up"]''',
      '''			var gk := "Grab" if Settings.touch_active() else Settings.binding_label("grab")
			return "%s  %s" % [gk, "Drag" if m > float(Defs.rule("interaction.carry_mass_limit", 22.0)) else "Pick up"]''')
h.save()

t = Patch('game/src/ui/touch_controls.gd')
t.rep('''	{"name": "interact", "action": "interact", "label": "Use", "pos": Vector2(-520, -420), "r": 66.0, "mode": "hold"},''',
      '''	{"name": "interact", "action": "interact", "label": "Use", "pos": Vector2(-520, -420), "r": 66.0, "mode": "hold"},
	{"name": "grab", "action": "grab", "label": "Grab", "pos": Vector2(-660, -300), "r": 52.0, "mode": "tap"},
	{"name": "ping", "action": "ping", "label": "Ping", "pos": Vector2(-820, 115), "r": 54.0, "mode": "tap", "tab": true},''')
t.save()
