"""Frag grenades on G: world wiring, command bit, binding (drop_held loses G: T puts objects down now), touch
button, explosion effect, grenade count on the HUD."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

m = Patch('game/src/player/motor.gd')
m.rep('''const B_PING := 32768
''', '''const B_PING := 32768
const B_THROW := 65536
''')
m.save()

c = Patch('game/src/player/player_controller.gd')
c.rep('''	"grab": Motor.B_GRAB, "ping": Motor.B_PING}''', '''	"grab": Motor.B_GRAB, "ping": Motor.B_PING, "throw_grenade": Motor.B_THROW}''')
c.save()

w = Patch('game/src/match/world.gd')
w.rep('''	interaction = Interaction.new(self)
''', '''	interaction = Interaction.new(self)
	grenades = preload("res://src/weapons/grenades.gd").new()
	add_child(grenades)
	grenades.setup(self)
''')
w.rep('''var interaction = null
''', '''var interaction = null
var grenades = null
''')
w.rep('''	if pressed & Motor.B_PING:
		server_ping(ch)''', '''	if pressed & Motor.B_PING:
		server_ping(ch)
	if pressed & Motor.B_THROW:
		grenades.server_throw(ch)''')
w.rep('''func _after_damage(ch: Character, res: Dictionary, attacker: int) -> void:''', '''@rpc("authority", "call_remote", "reliable")
func ev_grenade(id: int, p: Vector3, v: Vector3, fuse: float) -> void:
	if grenades:
		grenades.spawn(id, p, v, fuse)


@rpc("authority", "call_remote", "reliable")
func ev_explode(id: int, pos: Vector3) -> void:
	if grenades:
		grenades.explode_visual(id, pos)


func server_after_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	_after_damage(ch, res, attacker)


func _after_damage(ch: Character, res: Dictionary, attacker: int) -> void:''')
w.save()

s = Patch('game/src/core/settings.gd')
s.rep('''	"drop_held": ["G", ""],''', '''	"drop_held": ["", ""], "throw_grenade": ["G", "joy:15"],''')
s.rep('''		bindings.grab = BINDINGS.grab.duplicate()''', '''		bindings.grab = BINDINGS.grab.duplicate()
		bindings.throw_grenade = BINDINGS.throw_grenade.duplicate()
		if str((bindings.get("drop_held", [""]) as Array)[0]) == "G":
			bindings.drop_held = BINDINGS.drop_held.duplicate()''')
s.save()

u = Patch('game/src/ui/settings_ui.gd')
u.rep('''"drop_held": "Drop held object",''', '''"drop_held": "Drop held object", "throw_grenade": "Throw a frag grenade",''')
u.save()

t = Patch('game/src/ui/touch_controls.gd')
t.rep('''	{"name": "grab", "action": "grab", "label": "Grab", "pos": Vector2(-660, -300), "r": 52.0, "mode": "tap"},''',
      '''	{"name": "grab", "action": "grab", "label": "Grab", "pos": Vector2(-660, -300), "r": 52.0, "mode": "tap"},
	{"name": "frag", "action": "throw_grenade", "label": "Frag", "pos": Vector2(-640, -150), "r": 52.0, "mode": "tap"},''')
t.save()

e = Patch('game/src/fx/effects.gd')
e.rep('''func glass_break(pos: Vector3, dir: Vector3, w: Dictionary) -> void:''', '''func explosion(pos: Vector3) -> void:
	## Frag grenade: a hard white-orange flash that lights the street or the room, sparks and a dust cloud.
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.4)
	l.omni_range = 16.0
	l.light_energy = 6.0 if bool(Settings.get_value("accessibility", "reduce_flashes")) else 14.0
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos + Vector3.UP * 0.6
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)
	_burst(pos, Vector3.UP, Color(1.0, 0.7, 0.3), 26, 14.0, 0.45, true)
	_burst(pos, Vector3.UP, Color(0.32, 0.3, 0.28), 18, 3.0, 1.6)
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.amount = 14
	smoke.lifetime = 2.4
	smoke.explosiveness = 0.9
	smoke.direction = Vector3.UP
	smoke.spread = 80.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 2.2
	smoke.gravity = Vector3(0, 0.25, 0)
	smoke.scale_amount_min = 0.9
	smoke.scale_amount_max = 1.8
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.28, 0.27, 0.25, 0.55)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = sm
	smoke.mesh = q
	add_child(smoke)
	smoke.global_position = pos + Vector3.UP * 0.3
	smoke.emitting = true
	get_tree().create_timer(3.0).timeout.connect(smoke.queue_free)


func glass_break(pos: Vector3, dir: Vector3, w: Dictionary) -> void:''')
e.save()

h = Patch('game/src/ui/hud.gd')
h.rep('''var minimap: Control
''', '''var minimap: Control
var frags_label: Label
''')
h.rep('''	minimap.setup(world)
''', '''	minimap.setup(world)
	frags_label = UITheme.label("", 18, Color(0.82, 0.86, 0.8, 0.9))
	frags_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	frags_label.position = Vector2(-260, -60)
	frags_label.size = Vector2(240, 26)
	frags_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(frags_label)
''')
h.rep('''	# Context prompt
	_prompt_t -= dt''', '''	# Frag grenades carried, with the key that throws them.
	var nf := 0
	if ch.inv:
		for e in ch.inv.bag:
			if str(e.id) == "frag_grenade":
				nf += int(e.n)
	frags_label.text = ("Frag grenades %d   %s: throw" % [nf, "Frag" if Settings.touch_active() else Settings.binding_label("throw_grenade")]) if nf > 0 and ch.mode == Motor.GROUND else ""
	# Context prompt
	_prompt_t -= dt''')
h.save()
