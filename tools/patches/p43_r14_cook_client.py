"""r14: client side of cooking a frag grenade: the controller's hold-to-cook input and fuse clock, the grenade in the
first-person hands (pin pulled, held up, thrown), the HUD fuse ring. Idempotent."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, 'rb').read().decode('utf-8')
    nl = '\r\n' if '\r\n' in raw else '\n'
    s = raw.replace('\r\n', '\n')
    for a, b in pairs:
        if b in s:
            continue
        assert s.count(a) == 1, (rel, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'wb').write(s.replace('\n', nl).encode('utf-8'))


patch('game/src/player/player_controller.gd', [
    ('var _latched := 0\n',
     'var _latched := 0\n'
     'var cook_t := -1.0             # r14: seconds since this player pulled a grenade pin (own prediction), -1 none\n'
     'var _throw_was := false\n'),
    ('''			if Input.is_action_pressed("laser") or laser_toggled:
				btn |= Motor.B_LASER
''', '''			if Input.is_action_pressed("laser") or laser_toggled:
				btn |= Motor.B_LASER
			# r14: the grenade key is held while cooking (the latch below still catches a quick tap).
			if Input.is_action_pressed("throw_grenade"):
				btn |= Motor.B_THROW
'''),
    ('''	_latched = 0
	laser_held =''', '''	_latched = 0
	_cook_input((btn & Motor.B_THROW) != 0)
	laser_held ='''),
    ('''func _weapon_intent(cmd: Dictionary) -> void:''', '''func _cook_input(down: bool) -> void:
	## r14: the fuse clock the HUD and the hands show: starts when the pin is pulled (the key goes down with a grenade
	## carried), stops when it is thrown (key up) or has gone off.
	if down and not _throw_was and cook_t < 0.0 and ch and ch.mode == Motor.GROUND and ch.held_prop_id < 0 \\
			and ch.inv and ch.inv.count("frag_grenade") > 0 and not tab_held:
		cook_t = 0.0
	elif cook_t >= 0.0 and not down:
		cook_t = -1.0
	_throw_was = down


func _weapon_intent(cmd: Dictionary) -> void:'''),
    ('''	_correction = _correction.lerp(Vector3.ZERO, clampf(dt * 12.0, 0.0, 1.0))
''', '''	_correction = _correction.lerp(Vector3.ZERO, clampf(dt * 12.0, 0.0, 1.0))
	if cook_t >= 0.0:
		cook_t += dt
		if cook_t > float(Defs.item("frag_grenade").get("fuse_s", 4.0)) + 0.25 or ch.mode != Motor.GROUND:
			cook_t = -1.0   # it went off in the hand (or was dropped)
'''),
])

patch('game/src/player/viewmodel.gd', [
    ('var _watch_n := Vector3(0, 0.2, 1)\n',
     'var _watch_n := Vector3(0, 0.2, 1)\n'
     'var _nade: Node3D                # r14: a frag grenade in the right hand while cooking\n'
     'var _pin: MeshInstance3D         # its pin ring, pulled by the left hand\n'
     'var _nade_t := -1.0              # seconds into the throw, -1 none\n'
     'var _cook := -1.0\n'),
    ('''	_build_smartab()
	_build_torch()''', '''	_build_smartab()
	_build_torch()
	_build_nade()'''),
    ('''func _build_watch() -> void:''', '''func _build_nade() -> void:
	_nade = Node3D.new()
	_nade.name = "Grenade"
	add_child(_nade)
	var md: Dictionary = world.map.item_visual("frag_grenade") if world and world.map else {}
	var mi := MeshInstance3D.new()
	if md.get("mesh"):
		mi.mesh = md.mesh
		var sz: Vector3 = md.get("size", Vector3(0.06, 0.1, 0.06))
		mi.transform = Transform3D(Basis(), Vector3(0, -sz.y * 0.5, 0)) * (md.get("xf", Transform3D()) as Transform3D)
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.032
		sm.height = 0.08
		mi.mesh = sm
		mi.material_override = _mat(Color(0.2, 0.25, 0.15), 0.7)
	_nade.add_child(mi)
	_pin = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.009
	tm.outer_radius = 0.0125
	_pin.mesh = tm
	_pin.material_override = _mat(Color(0.7, 0.7, 0.72), 0.3)
	_pin.position = Vector3(0.025, 0.05, 0)
	_nade.add_child(_pin)
	_nade.visible = false
	_set_layer(_nade)


func _nade_pose(dt: float) -> bool:
	## r14: cooking, the grenade is held up in the right hand, the left hand first pulls the pin (it stays on the
	## left hand's finger) then reaches forward to aim; on release, a quick overarm swing. True while it is shown.
	var cook: float = world.controller.cook_t if world and world.controller else -1.0
	if _cook >= 0.0 and cook < 0.0:
		_nade_t = 0.0
	_cook = cook
	if _nade_t >= 0.0:
		_nade_t += dt
		if _nade_t > 0.36:
			_nade_t = -1.0
	_nade.visible = cook >= 0.0 or (_nade_t >= 0.0 and _nade_t < 0.14)
	if cook < 0.0 and _nade_t < 0.0:
		return false
	var hold := Vector3(0.16, -0.13, -0.33) + Vector3(0, sin(Time.get_ticks_msec() * 0.004) * 0.004, 0)
	var p := hold
	if _nade_t >= 0.0:
		var u := clampf(_nade_t / 0.36, 0.0, 1.0)
		var wind := Vector3(0.24, -0.02, -0.17)
		var out := Vector3(0.06, -0.12, -0.66)
		var down := Vector3(0.0, -0.42, -0.45)
		p = hold.lerp(wind, smoothstep(0.0, 0.3, u)) if u < 0.3 else (wind.lerp(out, smoothstep(0.3, 0.55, u)) if u < 0.55 else out.lerp(down, smoothstep(0.55, 1.0, u)))
	_nade.position = p
	_nade.rotation = Vector3(0.3, -0.4, 0.2)
	var pin_out: bool = cook >= 0.0 and cook > 0.3 or _nade_t >= 0.0
	_pin.visible = not pin_out or cook < 0.3
	# Right hand round the grenade: palm under it, fingers over the top.
	var rb := FpArms.hand_basis(Vector3(-0.15, 0.55, -1.0), Vector3(-0.55, 0.65, 0.15))
	arms.pose("R", p - rb.y * 0.032, rb, POLE_R, FpArms.grip("cup"))
	# Left hand: at the pin for the first moment, then forward.
	if cook >= 0.0 and cook < 0.35:
		var lb := FpArms.hand_basis(Vector3(0.6, 0.2, -1.0), Vector3(0.7, -0.3, 0.0))
		arms.pose("L", p + Vector3(-0.07, 0.03, 0.02).lerp(Vector3(-0.16, 0.02, 0.05), cook / 0.35), lb, POLE_L, FpArms.grip("pinch"))
	else:
		var lb2 := FpArms.hand_basis(Vector3(0.1, 0.5, -1.0), Vector3(0.6, -0.2, -0.5))
		arms.pose("L", Vector3(-0.15, -0.13, -0.5), lb2, POLE_L, FpArms.grip("open"))
	return true


func _build_watch() -> void:'''),
    ('''	_lower = move_toward(_lower, 1.0 if (_tab > 0.0 or busy or ch.held_prop_id >= 0 or ch.sprinting or vaulting) else 0.0, dt / (0.1 if vaulting else 0.25))''',
     '''	var nade_busy: bool = _cook >= 0.0 or _nade_t >= 0.0
	_lower = move_toward(_lower, 1.0 if (_tab > 0.0 or busy or ch.held_prop_id >= 0 or ch.sprinting or vaulting or nade_busy) else 0.0, dt / (0.1 if vaulting else (0.12 if nade_busy else 0.25)))'''),
    ('''	if arms.visible and (_parkour_hands() or _treat_hands()):
		return''', '''	if arms.visible and (_parkour_hands() or _treat_hands()):
		_nade.visible = false
		return
	if arms.visible and _nade_pose(get_process_delta_time()):
		return'''),
])

patch('game/src/ui/hud.gd', [
    ('''		frags_label.text = ("Frag grenades: %d  (%s to throw)" % [nf, "Frag" if Settings.touch_active() else Settings.binding_label("throw_grenade")]) if nf > 0 and ch.mode == Motor.GROUND else ""''',
     '''		frags_label.text = ("Frag grenades: %d  (hold %s to cook, let go to throw)" % [nf, "Frag" if Settings.touch_active() else Settings.binding_label("throw_grenade")]) if nf > 0 and ch.mode == Motor.GROUND else ""'''),
])
print('applied')
