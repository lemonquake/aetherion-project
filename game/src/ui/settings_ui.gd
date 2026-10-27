extends Control
## Settings overlay used by the main menu, lobby and pause menu. Changes apply immediately and save on close.

signal closed

var _rebinding := ""
var _rebind_index := 0
var _rebind_button: Button
var _tabs: TabContainer


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var outer := UITheme.vbox(10)
	outer.custom_minimum_size = Vector2(980, 720)
	center.add_child(outer)
	var head := UITheme.hbox(10)
	var title := UITheme.label("Settings", 40, UITheme.TEXT, UITheme.font_condensed)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UITheme.button("Close", _close, 140))
	outer.add_child(head)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_tabs)
	_tabs.add_child(_graphics())
	_tabs.add_child(_audio())
	_tabs.add_child(_controls())
	_tabs.add_child(_access())
	_tabs.add_child(_debug())


func _close() -> void:
	Settings.save_settings()
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if _rebinding != "":
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			_rebinding = ""
			_refresh_bind_button()
		elif (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.6):
			Settings.rebind(_rebinding, _rebind_index, event)
			_rebinding = ""
			_refresh_bind_button()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ pages

func _page(title: String) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = title
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := UITheme.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(v)
	return s


func _row(parent: Control, text: String, control: Control, note: String = "") -> void:
	var h := UITheme.hbox(16)
	var l := UITheme.label(text, 20)
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	parent.get_child(0).add_child(h)
	if note != "":
		var n := UITheme.label(note, 16, UITheme.TEXT_DIM)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.get_child(0).add_child(n)


func _option(section: String, key: String, items: Array) -> OptionButton:
	## items: [[value, label], ...]
	var o := OptionButton.new()
	var cur = Settings.get_value(section, key)
	for i in items.size():
		o.add_item(str(items[i][1]))
		o.set_item_metadata(i, items[i][0])
		if str(items[i][0]) == str(cur):
			o.select(i)
	o.item_selected.connect(func(i): Settings.set_value(section, key, o.get_item_metadata(i)))
	# Follow changes made elsewhere (a quality preset sets several options).
	Settings.changed.connect(func(s, k):
		if s == section and k == key:
			for i in o.item_count:
				if str(o.get_item_metadata(i)) == str(Settings.get_value(section, key)):
					o.set_block_signals(true)
					o.select(i)
					o.set_block_signals(false))
	return o


func _check(section: String, key: String) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(section, key))
	c.toggled.connect(func(on): Settings.set_value(section, key, on))
	Settings.changed.connect(func(s, k):
		if s == section and k == key:
			c.set_block_signals(true)
			c.button_pressed = bool(Settings.get_value(section, key))
			c.set_block_signals(false))
	return c


func _slider(section: String, key: String, lo: float, hi: float, step: float, fmt: String = "%.2f", shown: float = 1.0) -> Control:
	## `shown` scales the number in the label (e.g. 100 to show a 0-1 value as 0-100).
	var h := UITheme.hbox(10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(section, key))
	s.custom_minimum_size = Vector2(320, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := UITheme.label(fmt % (s.value * shown), 18, UITheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(val): Settings.set_value(section, key, val); l.text = fmt % (val * shown))
	Settings.changed.connect(func(sec, k):
		if sec == section and k == key and not is_equal_approx(s.value, float(Settings.get_value(section, key))):
			s.set_block_signals(true)
			s.value = float(Settings.get_value(section, key))
			l.text = fmt % (s.value * shown)
			s.set_block_signals(false))
	h.add_child(s)
	h.add_child(l)
	return h


func _graphics() -> Control:
	var p := _page("Graphics")
	_row(p, "Window", _option("graphics", "window_mode", [["windowed", "Windowed"], ["borderless", "Borderless fullscreen"], ["fullscreen", "Fullscreen"]]))
	_row(p, "Window size", _option("graphics", "resolution", [["1280x720", "1280 × 720"], ["1600x900", "1600 × 900"], ["1920x1080", "1920 × 1080"], ["2560x1440", "2560 × 1440"], ["3840x2160", "3840 × 2160"]]))
	_row(p, "Vertical sync", _check("graphics", "vsync"))
	_row(p, "Frame rate limit", _option("graphics", "max_fps", [[0, "Unlimited"], [30, "30"], [60, "60"], [90, "90"], [120, "120"], [144, "144"]]))
	_row(p, "Quality preset", _option("graphics", "preset", [["mobile", "Mobile"], ["low", "Low"], ["medium", "Medium"], ["high", "High"], ["ultra", "Ultra"]]),
		"Sets shadow resolution, flashlight shadow detail, ambient occlusion, fog volume and draw distance.")
	_row(p, "Render scale", _slider("graphics", "render_scale", 0.5, 1.0, 0.05, "%.2f"))
	_row(p, "Upscaler", _option("graphics", "upscaler", [["off", "Off"], ["fsr", "AMD FSR 1"], ["fsr2", "AMD FSR 2"]]))
	_row(p, "Anti-aliasing", _option("graphics", "antialiasing", [["taa", "TAA"], ["fxaa", "FXAA"], ["msaa", "MSAA 2×"], ["off", "Off"]]))
	_row(p, "Shadows", _option("graphics", "shadows", [[0, "Low"], [1, "Medium"], [2, "High"], [3, "Ultra"]]))
	_row(p, "Ambient occlusion", _check("graphics", "ssao"))
	_row(p, "Volumetric fog", _check("graphics", "volumetric_fog"), "Fog shapes flashlight beams and distant lights. Disabling it is faster but flattens the night.")
	_row(p, "Flashlight shadows", _check("graphics", "flashlight_shadows"), "Beams cast shadows of door frames, furniture and people. Costs the most on phones.")
	_row(p, "Lamp distance", _slider("graphics", "light_distance", 0.5, 1.0, 0.05, "%.2f"), "How far away lamps still light the scene. Applies from the next match.")
	_row(p, "Draw distance", _slider("graphics", "view_distance", 0.6, 1.3, 0.05, "%.2f"),
		"How far buildings keep their full detail on the ground before simpler blocks take over.")
	_row(p, "Brightness", _slider("graphics", "brightness", -0.5, 0.5, 0.05, "%+.2f"),
		"Adjust until the left bar of the calibration strip in game is barely visible. Darkness is part of the game; raising this does not reveal hidden players any more than a brighter monitor would.")
	_row(p, "Field of view", _slider("graphics", "fov", 65.0, 100.0, 1.0, "%.0f°"))
	return p


func _audio() -> Control:
	var p := _page("Audio")
	_row(p, "Master volume", _slider("audio", "master", 0.0, 1.0, 0.01, "%.0f", 100.0))
	_row(p, "Effects", _slider("audio", "effects", 0.0, 1.0, 0.01, "%.2f"))
	_row(p, "Team voice", _slider("audio", "voice", 0.0, 1.5, 0.01, "%.2f"))
	_row(p, "Ambience", _slider("audio", "ambience", 0.0, 1.0, 0.01, "%.2f"))
	_row(p, "Interface", _slider("audio", "ui", 0.0, 1.0, 0.01, "%.2f"))
	_row(p, "Output", _option("audio", "output", [["headphones", "Headphones"], ["speakers", "Speakers"]]),
		"Headphones use full left/right separation. Speakers narrow the stereo image so cues stay audible from both sides.")
	_row(p, "Night mode", _check("audio", "night_mode"), "Compresses loud sounds so quiet footsteps stay audible at low volume.")
	var mic := OptionButton.new()
	var devices := AudioServer.get_input_device_list()
	var cur := str(Settings.get_value("audio", "mic_device"))
	for i in devices.size():
		mic.add_item(devices[i])
		if devices[i] == cur:
			mic.select(i)
	mic.item_selected.connect(func(i): Settings.set_value("audio", "mic_device", mic.get_item_text(i)))
	_row(p, "Microphone", mic)
	_row(p, "Microphone gain", _slider("audio", "mic_gain", 0.2, 3.0, 0.05, "%.2f"))
	_row(p, "Voice mode", _option("audio", "voice_mode", [["push", "Push to talk"], ["open", "Voice activation"], ["off", "Microphone off"]]),
		"Your team hears you on their radios, with a click when you key up. Radios can be overheard: anyone within about 12 m of a teammate's radio, or 9 m of you, hears what you say.")
	_row(p, "Voice activation level", _slider("audio", "voice_threshold", 0.005, 0.2, 0.005, "%.3f"))
	return p


func _debug() -> Control:
	var p := _page("Debug")
	_row(p, "Unlock master volume", _check("debug", "volume_unlock"),
		"Normally a master volume of 100 plays at 75% of full output, to keep gunshots from being painful. "
		+ "With this on, 100 means full output.")
	return p


func _controls() -> Control:
	var p := _page("Controls")
	if Settings.is_mobile() or Settings.touch_active():
		_row(p, "Touch look speed", _slider("controls", "touch_sensitivity", 0.1, 1.0, 0.02, "%.2f"))
		_row(p, "Aiming sensitivity", _slider("controls", "ads_sensitivity", 0.2, 1.5, 0.05, "%.2f"))
		_row(p, "Invert vertical look", _check("controls", "invert_y"))
		_row(p, "Aim button toggles", _check("controls", "touch_aim_toggle"), "On: tap Aim to aim, then tap again to stop. Off: hold Aim to aim.")
		_row(p, "On-screen touch controls", _check("controls", "touch_controls"), "Applies from the next match.")
		_touch_guide(p)
		return p
	_row(p, "Mouse sensitivity", _slider("controls", "mouse_sensitivity", 0.02, 0.5, 0.005, "%.3f"))
	_row(p, "Aiming sensitivity", _slider("controls", "ads_sensitivity", 0.2, 1.5, 0.05, "%.2f"))
	_row(p, "Invert vertical look", _check("controls", "invert_y"))
	_row(p, "Crouch toggles", _check("controls", "crouch_toggle"))
	_row(p, "Sprint toggles", _check("controls", "sprint_toggle"))
	_row(p, "Controller look speed", _slider("controls", "gamepad_sensitivity", 0.5, 6.0, 0.1, "%.1f"))
	_row(p, "Controller dead zone", _slider("controls", "gamepad_deadzone", 0.05, 0.4, 0.01, "%.2f"))
	_row(p, "On-screen touch controls", _check("controls", "touch_controls"), "On by default on phones and tablets. Applies from the next match.")
	_row(p, "Touch look speed", _slider("controls", "touch_sensitivity", 0.1, 1.0, 0.02, "%.2f"))
	_row(p, "Aim button toggles", _check("controls", "touch_aim_toggle"))
	var labels := {
		"move_forward": "Move forward", "move_back": "Move back", "move_left": "Move left", "move_right": "Move right",
		"jump": "Jump / vault", "crouch": "Crouch", "sprint": "Sprint", "walk": "Walk quietly", "fire": "Fire / throw",
		"aim": "Aim", "reload": "Reload", "interact": "Use / pick up items", "grab": "Grab, drag or carry objects", "flashlight": "Light (hold: change battery)",
		"smartab": "SmarTab (hold)", "map": "SmarTab map (hold)", "heal": "Treat injuries", "weapon_1": "Primary weapon",
		"weapon_2": "Secondary weapon", "weapon_3": "Handgun", "holster": "Holster", "fire_mode": "Fire mode",
		"push_to_talk": "Push to talk", "ping": "Ping your position to the team", "text_chat": "Team text", "drop_held": "Drop held object", "throw_grenade": "Throw a frag grenade", "next_weapon": "Next weapon",
		"prev_weapon": "Previous weapon", "smartab_prev": "SmarTab: previous page", "smartab_next": "SmarTab: next page",
	}
	var head := UITheme.hbox(16)
	var hl := UITheme.label("Action", 18, UITheme.TEXT_DIM)
	hl.custom_minimum_size = Vector2(300, 0)
	head.add_child(hl)
	head.add_child(UITheme.label("Keyboard / mouse        Controller", 18, UITheme.TEXT_DIM))
	p.get_child(0).add_child(head)
	for action in labels:
		var h := UITheme.hbox(16)
		var l := UITheme.label(labels[action], 19)
		l.custom_minimum_size = Vector2(300, 0)
		h.add_child(l)
		for idx in [0, 1]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(200, 36)
			b.text = Settings.binding_label(action, idx)
			b.set_meta("action", action)
			b.set_meta("index", idx)
			b.pressed.connect(func(): _start_rebind(b))
			h.add_child(b)
		p.get_child(0).add_child(h)
	p.get_child(0).add_child(UITheme.button("Reset all bindings", func(): Settings.reset_bindings(); _rebuild_tab(2), 0))
	return p


func _touch_guide(p: Control) -> void:
	var guide := [
		["Move / sprint", "Drag the move stick on the left. Push up past the ring to sprint."],
		["Look / fire", "Drag on the right to look. Hold either Fire button to shoot; drag it to aim while firing."],
		["Jump / parachute", "Tap Jump to jump, vault, leave the plane, open the canopy or flare before landing."],
		["Steer parachute", "Use the move stick: up speeds up, down brakes, left/right turns."],
		["Crouch", "Tap Crouch to crouch; tap again to stand."],
		["Reload / weapon", "Tap Reload to reload. Tap Weapon to switch weapons."],
		["Use / revive", "Tap Use to open doors, search containers or take items. Hold Use to revive a teammate."],
		["Grab / throw", "Tap Grab to carry or drag an object. Tap again to put it down, or tap Fire to throw it."],
		["Frag grenade", "Tap Frag to throw a frag grenade."],
		["Light / battery", "Tap Light to switch the flashlight on or off. Hold Light to change batteries."],
		["Phone / map", "Tap Phone to open the SmarTab; tap again to close. Tap Map for the map and flight path."],
		["SmarTab pages", "Tap a page title or the < and > buttons. Tap items and buttons to select or use them."],
		["Heal", "Close Phone, then tap Heal to treat an injury. You can also select medicine on the Items page and tap Use."],
		["Team / menu", "Tap Ping to share your position. Hold Radio to talk to your team. Tap Menu for Resume, Settings or Leave match."],
	]
	p.get_child(0).add_child(UITheme.label("Touch controls", 24, UITheme.TEXT, UITheme.font_semibold))
	for entry in guide:
		var title := UITheme.label(entry[0], 20)
		p.get_child(0).add_child(title)
		var note := UITheme.label(entry[1], 18, UITheme.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		p.get_child(0).add_child(note)


func _access() -> Control:
	var p := _page("Accessibility")
	_row(p, "Camera motion", _option("accessibility", "camera_motion", [["normal", "Normal"], ["reduced", "Reduced"], ["off", "Off"]]),
		"Reduces head bob, the limp sway of injured legs and landing jolts. Injuries still slow you and still disturb your aim.")
	_row(p, "SmarTab text size", _slider("accessibility", "smartab_text_scale", 0.8, 1.5, 0.05, "%.2f"))
	_row(p, "SmarTab screen brightness", _slider("accessibility", "smartab_brightness", 0.15, 1.0, 0.05, "%.2f"),
		"A brighter screen is easier to read and easier for others to spot in the dark.")
	_row(p, "Reduce flashes", _check("accessibility", "reduce_flashes"), "Dims muzzle flashes and flickering bulbs.")
	return p


func _start_rebind(b: Button) -> void:
	_rebinding = b.get_meta("action")
	_rebind_index = b.get_meta("index")
	_rebind_button = b
	b.text = "Press a key… (Esc cancels)"


func _refresh_bind_button() -> void:
	if _rebind_button and is_instance_valid(_rebind_button):
		_rebind_button.text = Settings.binding_label(_rebind_button.get_meta("action"), _rebind_button.get_meta("index"))


func _rebuild_tab(i: int) -> void:
	var old := _tabs.get_child(i)
	var fresh := _controls()
	_tabs.add_child(fresh)
	_tabs.move_child(fresh, i)
	old.queue_free()
	_tabs.current_tab = i
