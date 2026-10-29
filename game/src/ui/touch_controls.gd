extends Control
## On-screen controls for phones and tablets: a floating move stick on the left, the view turned by dragging on the
## right, and buttons that send the same input actions as keys and mouse buttons. The rest of the game (and the
## server) cannot tell a phone from a PC, so both play by the same rules in a cross-play match.
##
## Buttons go in as real action events (Input.parse_input_event), so a quick tap is latched like a key press. While
## playing, Godot's mouse emulation from touch is switched off: an emulated left click would count as Fire. It is on
## again for menus and the SmarTab, whose screen takes taps as clicks.

const STICK_R := 125.0
const SPRINT_PULL := 1.25  # drag this far past the ring to lock sprint

var controller = null
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _sprint_lock := false
var _move := Vector2.ZERO
var _look_id := -1
var _held := {}     # touch index -> button
var _toggled := {}  # button name -> on
var _font: Font

## pos: offset from a corner (negative x from the right edge, negative y from the bottom). mode: hold (pressed while
## the finger is down), tap (one press), toggle (on until tapped again). look: dragging the button also turns the
## view. tab: still shown with the SmarTab up.
const BUTTONS := [
	{"name": "fire", "action": "fire", "label": "Fire", "pos": Vector2(-300, -290), "r": 105.0, "mode": "hold", "look": true},
	{"name": "fire_l", "action": "fire", "label": "Fire", "pos": Vector2(215, -560), "r": 66.0, "mode": "hold", "look": true},
	{"name": "aim", "action": "aim", "label": "Aim", "pos": Vector2(-118, -525), "r": 64.0, "mode": "toggle"},
	{"name": "jump", "action": "jump", "label": "Jump", "pos": Vector2(-112, -335), "r": 62.0, "mode": "hold"},
	{"name": "crouch", "action": "crouch", "label": "Crouch", "pos": Vector2(-112, -150), "r": 62.0, "mode": "toggle"},
	{"name": "reload", "action": "reload", "label": "Reload", "pos": Vector2(-480, -125), "r": 56.0, "mode": "tap"},
	{"name": "interact", "action": "interact", "label": "Use", "pos": Vector2(-520, -420), "r": 66.0, "mode": "hold"},
	{"name": "grab", "action": "grab", "label": "Grab", "pos": Vector2(-660, -300), "r": 52.0, "mode": "tap"},
	{"name": "frag", "action": "throw_grenade", "label": "Frag", "pos": Vector2(-640, -150), "r": 52.0, "mode": "tap"},
	{"name": "ping", "action": "ping", "label": "Ping", "pos": Vector2(-820, 115), "r": 54.0, "mode": "tap", "tab": true},
	{"name": "laser", "action": "laser", "label": "Laser", "pos": Vector2(-960, 115), "r": 54.0, "mode": "toggle"},
	{"name": "flashlight", "action": "flashlight", "label": "Light", "pos": Vector2(-120, 115), "r": 54.0, "mode": "hold", "tab": true},
	{"name": "smartab", "action": "smartab", "label": "Phone", "pos": Vector2(-260, 115), "r": 54.0, "mode": "toggle", "tab": true},
	{"name": "heal", "action": "heal", "label": "Heal", "pos": Vector2(-400, 115), "r": 54.0, "mode": "tap"},
	{"name": "weapon", "action": "next_weapon", "label": "Weapon", "pos": Vector2(-540, 115), "r": 54.0, "mode": "tap"},
	{"name": "radio", "action": "push_to_talk", "label": "Radio", "pos": Vector2(-680, 115), "r": 54.0, "mode": "hold"},
	{"name": "fire_mode", "action": "fire_mode", "label": "Auto", "pos": Vector2(-540, 245), "r": 58.0, "mode": "tap"},
	{"name": "menu", "action": "menu", "label": "Menu", "pos": Vector2(80, 80), "r": 48.0, "mode": "tap", "tab": true},
	{"name": "page_prev", "action": "smartab_prev", "label": "<", "pos": Vector2(-400, -300), "r": 60.0, "mode": "tap", "tab_only": true},
	{"name": "page_next", "action": "smartab_next", "label": ">", "pos": Vector2(-250, -300), "r": 60.0, "mode": "tap", "tab_only": true},
]


func setup(c) -> void:
	controller = c
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func _exit_tree() -> void:
	_release_all()
	Input.emulate_mouse_from_touch = true


func _playing() -> bool:
	return controller != null and not controller.paused and not controller.results and controller.spectating < 0


func _tab_up() -> bool:
	return bool(_toggled.get("smartab", false))


func _visible_button(b: Dictionary) -> bool:
	if b.name == "fire_mode" and not _selector_available():
		return false
	if b.get("tab_only", false):
		return _tab_up()
	return not _tab_up() or b.get("tab", false)


func _selector_available() -> bool:
	return controller != null and is_instance_valid(controller.ch) and controller.ch.wpn != null \
		and controller.ch.wpn.has_selector(controller.ch.wpn.current_id()) and controller.ch.mode == Motor.GROUND


func _k() -> float:
	## The layout above is in 1920x1080 units; phones scale the UI up (content_scale_factor), the controls keep size.
	return 1.0 / maxf(get_tree().root.content_scale_factor, 0.01)


func _centre(b: Dictionary) -> Vector2:
	var sz := get_viewport_rect().size
	var p: Vector2 = b.pos * _k()
	return Vector2(p.x if p.x >= 0.0 else sz.x + p.x, p.y if p.y >= 0.0 else sz.y + p.y)


func _button_at(pos: Vector2) -> Dictionary:
	for b in BUTTONS:
		if _visible_button(b) and pos.distance_to(_centre(b)) <= float(b.r) * _k() * 1.15:
			return b
	return {}


func _send(action: String, pressed: bool, strength: float = 1.0) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = strength if pressed else 0.0
	Input.parse_input_event(ev)


func _process(_dt: float) -> void:
	# Menus, the pause screen, results and the SmarTab screen take taps as mouse clicks; play does not.
	var menus = not _playing() or _tab_up() or (controller and controller.world and controller.world.hud and controller.world.hud.chat_edit != null)
	Input.emulate_mouse_from_touch = menus
	if not _playing() and (_stick_id >= 0 or not _held.is_empty()):
		_release_all()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_id:
			_stick_pos = d.position
			_update_stick()
		elif d.index == _look_id and controller and not _tab_up():
			controller.add_touch_look(d.relative)


func _touch_down(index: int, pos: Vector2) -> void:
	var b := _button_at(pos)
	if not _playing():
		if not b.is_empty() and b.name == "menu":
			_send("menu", true)
			_send("menu", false)
		return
	if not b.is_empty():
		var mode := str(b.mode)
		if b.name == "aim" and not bool(Settings.get_value("controls", "touch_aim_toggle")):
			mode = "hold"
		match mode:
			"hold":
				_held[index] = b
				_send(str(b.action), true)
				if b.get("look", false) and _look_id < 0:
					_look_id = index
			"tap":
				_send(str(b.action), true)
				_send(str(b.action), false)
			"toggle":
				var on := not bool(_toggled.get(b.name, false))
				_toggled[b.name] = on
				_send(str(b.action), on)
		return
	var sz := get_viewport_rect().size
	if pos.x < sz.x * 0.42 and _stick_id < 0:
		_stick_id = index
		_stick_origin = pos
		_stick_pos = pos
		_update_stick()
	elif _look_id < 0 and not _tab_up():
		_look_id = index


func _touch_up(index: int) -> void:
	if index == _stick_id:
		_stick_id = -1
		_sprint_lock = false
		_set_move(Vector2.ZERO)
		_send("sprint", false)
	if index == _look_id:
		_look_id = -1
	if _held.has(index):
		_send(str(_held[index].action), false)
		_held.erase(index)


func _update_stick() -> void:
	var off := _stick_pos - _stick_origin
	var v := off / (STICK_R * _k())
	# Pulling well past the ring locks sprint until the stick is let go or brought back down.
	if v.length() > SPRINT_PULL and -v.y > 0.7 * v.length():
		_sprint_lock = true
	elif -v.y < 0.4:
		_sprint_lock = false
	_send("sprint", _sprint_lock)
	_set_move(v.limit_length(1.0))


func _set_move(v: Vector2) -> void:
	# Screen y points down; forward is up.
	var axes := {"move_right": maxf(v.x, 0.0), "move_left": maxf(-v.x, 0.0), "move_forward": maxf(-v.y, 0.0), "move_back": maxf(v.y, 0.0)}
	for a in axes:
		var s: float = axes[a]
		_send(a, s > 0.08, s)
	_move = v


func _release_all() -> void:
	for i in _held:
		_send(str(_held[i].action), false)
	_held.clear()
	for name in _toggled:
		if _toggled[name]:
			for b in BUTTONS:
				if b.name == name:
					_send(str(b.action), false)
	_toggled.clear()
	_stick_id = -1
	_look_id = -1
	_sprint_lock = false
	_set_move(Vector2.ZERO)
	_send("sprint", false)


func reset_toggle(name: String) -> void:
	## The game turned something off by itself (aim dropped on a weapon change, the SmarTab closed by a menu...).
	if _toggled.get(name, false):
		_toggled[name] = false
		for b in BUTTONS:
			if b.name == name:
				_send(str(b.action), false)


func _draw() -> void:
	if not _playing():
		for b in BUTTONS:
			if b.name == "menu":
				_button(b, false)
		return
	for b in BUTTONS:
		if not _visible_button(b):
			continue
		var on := bool(_toggled.get(b.name, false))
		for i in _held:
			if _held[i].name == b.name:
				on = true
		_button(b, on)
	if _stick_id >= 0:
		var sr := STICK_R * _k()
		draw_circle(_stick_origin, sr, Color(1, 1, 1, 0.08))
		draw_arc(_stick_origin, sr, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(sr)
		draw_circle(knob, 48.0 * _k(), Color(1, 1, 1, 0.3 if not _sprint_lock else 0.55))
		if _sprint_lock:
			_label(_stick_origin + Vector2(0, -sr - 30.0 * _k()), "Sprint", 26)


func _button(b: Dictionary, on: bool) -> void:
	var c := _centre(b)
	var r := float(b.r) * _k()
	draw_circle(c, r, Color(1, 1, 1, 0.22 if on else 0.09))
	draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.6 if on else 0.32), 3.0)
	if b.name == "fire_mode" and _selector_available():
		_label(c + Vector2(0, -16.0 * _k()), "Mode", 20)
		_label(c + Vector2(0, 13.0 * _k()), controller.ch.wpn.fire_mode_label(), 26)
	else:
		_label(c, str(b.label), 24 if float(b.r) < 80.0 else 30)


func _label(c: Vector2, text: String, size: int) -> void:
	size = int(size * _k())
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string_outline(_font, c + Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.6))
	draw_string(_font, c + Vector2(-w * 0.5, size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.9))
