extends Node
## Saveable preferences (user://settings.cfg): graphics, audio, controls, accessibility and key bindings.
## Values are applied immediately where the engine allows it; the world listens to `changed` for the rest.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"
## Bumped when defaults change in a way saved settings should pick up (see _migrate).
const VERSION := 3
## The master slider shows 0-100, but 100 plays at this fraction of full output unless debug.volume_unlock is on.
const MASTER_CAP := 0.75

const DEFAULTS := {
	"player": {"name": "", "laser_color": "red"},
	"gameplay": {"ally_names": true, "bot_learning": true},
	"online": {"server": ""},
	"graphics": {
		"window_mode": "windowed", "resolution": "1600x900", "vsync": true, "max_fps": 0,
		"preset": "high", "render_scale": 1.0, "upscaler": "off", "shadows": 2, "ssao": true, "ssil": false,
		"volumetric_fog": true, "antialiasing": "taa", "brightness": 0.0, "fov": 80.0, "view_distance": 1.0,
		"flashlight_shadows": true, "light_distance": 1.0,
	},
	"audio": {
		"master": 0.9, "effects": 1.0, "voice": 1.0, "ambience": 0.6, "ui": 0.8,
		"output": "headphones", "night_mode": false, "mic_device": "Default", "mic_gain": 1.0,
		"voice_mode": "push", "voice_threshold": 0.04,
	},
	"controls": {
		"mouse_sensitivity": 0.12, "ads_sensitivity": 0.75, "invert_y": false, "crouch_toggle": false,
		"sprint_toggle": false, "gamepad_sensitivity": 2.4, "gamepad_deadzone": 0.18,
		"touch_controls": false, "touch_sensitivity": 0.3, "touch_aim_toggle": true,
	},
	"accessibility": {"camera_motion": "normal", "smartab_text_scale": 1.0, "reduce_flashes": false, "smartab_brightness": 0.6},
	"debug": {"volume_unlock": false},
}

## What each graphics quality preset sets. Applied when a preset is picked; the individual options can still be
## changed afterwards.
const PRESETS := {
	# Phones and tablets (the default there): no shadow maps, AO or fog volumes, 3D drawn at 70 % and scaled up,
	# 2x MSAA (nearly free on tiled mobile GPUs), lamps culled sooner, a 60 fps cap to stay cool.
	"mobile": {"shadows": 0, "ssao": false, "volumetric_fog": false, "view_distance": 0.6, "render_scale": 0.7,
		"upscaler": "off", "antialiasing": "msaa", "flashlight_shadows": false, "light_distance": 0.6, "max_fps": 60},
	"low": {"shadows": 0, "ssao": false, "volumetric_fog": false, "view_distance": 0.8, "flashlight_shadows": false,
		"light_distance": 0.8},
	"medium": {"shadows": 1, "ssao": false, "volumetric_fog": true, "view_distance": 0.9},
	"high": {"shadows": 2, "ssao": true, "volumetric_fog": true, "view_distance": 1.0},
	"ultra": {"shadows": 3, "ssao": true, "volumetric_fog": true, "view_distance": 1.2},
}

## action -> [keyboard/mouse default, gamepad default]. Mouse buttons are "mouse:N", joypad buttons "joy:N",
## joypad axes "axis:N:+/-".
const BINDINGS := {
	"move_forward": ["W", "axis:1:-"], "move_back": ["S", "axis:1:+"],
	"move_left": ["A", "axis:0:-"], "move_right": ["D", "axis:0:+"],
	"look_up": ["", "axis:3:-"], "look_down": ["", "axis:3:+"], "look_left": ["", "axis:2:-"], "look_right": ["", "axis:2:+"],
	"jump": ["Space", "joy:0"], "crouch": ["C", "joy:1"], "sprint": ["Shift", "joy:7"], "walk": ["Ctrl", ""],
	"fire": ["mouse:1", "axis:5:+"], "aim": ["mouse:2", "axis:4:+"], "reload": ["R", "joy:2"],
	"interact": ["E", "joy:10"], "grab": ["T", "joy:8"], "flashlight": ["F", "joy:9"], "smartab": ["Tab", "joy:4"],
	"heal": ["H", "joy:12"], "weapon_1": ["1", ""], "weapon_2": ["2", ""], "weapon_3": ["3", ""],
	"next_weapon": ["mouse:5", "joy:3"], "prev_weapon": ["mouse:4", ""], "holster": ["X", "joy:13"],
	"fire_mode": ["B", "joy:14"], "push_to_talk": ["CapsLock", "joy:11"], "ping": ["mouse:3", "joy:5"], "laser": ["V", ""], "text_chat": ["Y", ""],
	"drop_held": ["", ""], "throw_grenade": ["G", "joy:15"], "menu": ["Escape", "joy:6"], "map": ["M", ""],
	"smartab_prev": ["Q", "joy:11"], "smartab_next": ["E", "joy:10"],
}

var data: Dictionary = {}
var bindings: Dictionary = {}


## Overrides of DEFAULTS on phones and tablets (or on a PC started with --mobile, to try the mobile profile).
const MOBILE_DEFAULTS := {
	"graphics": {"preset": "mobile", "vsync": true},
	"controls": {"touch_controls": true},
}

static var _mobile := -1


static func is_mobile() -> bool:
	## A phone or tablet build, or a PC started with --mobile.
	if _mobile < 0:
		_mobile = 1 if OS.has_feature("mobile") or "--mobile" in OS.get_cmdline_user_args() else 0
	return _mobile == 1


func touch_active() -> bool:
	return bool(get_value("controls", "touch_controls"))


func play_mouse_mode() -> Input.MouseMode:
	## Mouse mode while playing: captured for mouse look, free when touch controls are on.
	return Input.MOUSE_MODE_VISIBLE if touch_active() else Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	load_settings()
	apply_bindings()
	apply_all()


func get_value(section: String, key: String):
	return data.get(section, {}).get(key, DEFAULTS.get(section, {}).get(key))


func set_value(section: String, key: String, value) -> void:
	if not data.has(section):
		data[section] = {}
	data[section][key] = value
	_apply(section, key)
	changed.emit(section, key)
	if section == "graphics" and key == "preset":
		var p: Dictionary = PRESETS.get(str(value), {})
		for k in p:
			set_value("graphics", k, p[k])


func load_settings() -> void:
	data = DEFAULTS.duplicate(true)
	if is_mobile():
		for section in MOBILE_DEFAULTS:
			for key in MOBILE_DEFAULTS[section]:
				data[section][key] = MOBILE_DEFAULTS[section][key]
		var mp: Dictionary = PRESETS.mobile
		for key in mp:
			data.graphics[key] = mp[key]
	bindings = {}
	for action in BINDINGS:
		bindings[action] = BINDINGS[action].duplicate()
	var cfg := ConfigFile.new()
	# A PC trying the mobile profile (--mobile) starts from it rather than from its own saved settings.
	if (is_mobile() and not OS.has_feature("mobile")) or cfg.load(PATH) != OK:
		return
	for section in cfg.get_sections():
		if section == "bindings":
			for action in cfg.get_section_keys(section):
				if bindings.has(action):
					bindings[action] = cfg.get_value(section, action)
			continue
		if not data.has(section):
			data[section] = {}
		for key in cfg.get_section_keys(section):
			data[section][key] = cfg.get_value(section, key)
	_migrate(int(cfg.get_value("meta", "version", 1)))


func _migrate(from: int) -> void:
	## Saved settings from an older build: move what changed meaning, keep everything the player chose.
	if from < 2:
		# V became the team ping and push to talk moved to Caps Lock; ambience defaults to 60 % (was 80 %).
		if str((bindings.get("push_to_talk", [""]) as Array)[0]) == "V":
			bindings.push_to_talk[0] = "CapsLock"
		bindings.ping = BINDINGS.ping.duplicate()
		bindings.grab = BINDINGS.grab.duplicate()
		bindings.throw_grenade = BINDINGS.throw_grenade.duplicate()
		if str((bindings.get("drop_held", [""]) as Array)[0]) == "G":
			bindings.drop_held = BINDINGS.drop_held.duplicate()
		if is_equal_approx(float(data.get("audio", {}).get("ambience", 0.6)), 0.8):
			data.audio.ambience = 0.6
	if from < 3:
		# V became the laser pointer; pinging a spot moved to the middle mouse button.
		if str((bindings.get("ping", [""]) as Array)[0]) == "V":
			bindings.ping = BINDINGS.ping.duplicate()
		bindings.laser = BINDINGS.laser.duplicate()


func save_settings() -> void:
	if is_mobile() and not OS.has_feature("mobile"):
		return  # --mobile on a PC must not overwrite the PC's own settings
	var cfg := ConfigFile.new()
	for section in data:
		for key in data[section]:
			cfg.set_value(section, key, data[section][key])
	for action in bindings:
		cfg.set_value("bindings", action, bindings[action])
	cfg.set_value("meta", "version", VERSION)
	cfg.save(PATH)


# ------------------------------------------------------------------ bindings

func apply_bindings() -> void:
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		InputMap.action_erase_events(action)
		for spec in bindings[action]:
			var ev := event_from_spec(str(spec))
			if ev:
				InputMap.action_add_event(action, ev)


func rebind(action: String, index: int, ev: InputEvent) -> void:
	var spec := spec_from_event(ev)
	if spec == "":
		return
	var list: Array = bindings.get(action, ["", ""])
	while list.size() <= index:
		list.append("")
	list[index] = spec
	bindings[action] = list
	apply_bindings()
	save_settings()


func reset_bindings() -> void:
	for action in BINDINGS:
		bindings[action] = BINDINGS[action].duplicate()
	apply_bindings()
	save_settings()


func event_from_spec(spec: String) -> InputEvent:
	if spec == "":
		return null
	if spec.begins_with("mouse:"):
		var mb := InputEventMouseButton.new()
		mb.button_index = int(spec.substr(6)) as MouseButton
		return mb
	if spec.begins_with("joy:"):
		var jb := InputEventJoypadButton.new()
		jb.button_index = int(spec.substr(4)) as JoyButton
		return jb
	if spec.begins_with("axis:"):
		var parts := spec.split(":")
		var jm := InputEventJoypadMotion.new()
		jm.axis = int(parts[1]) as JoyAxis
		jm.axis_value = -1.0 if parts[2] == "-" else 1.0
		return jm
	var key := InputEventKey.new()
	var code := OS.find_keycode_from_string(spec)
	if code == KEY_NONE:
		return null
	key.physical_keycode = code
	return key


func spec_from_event(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		return OS.get_keycode_string(code)
	if ev is InputEventMouseButton:
		return "mouse:%d" % ev.button_index
	if ev is InputEventJoypadButton:
		return "joy:%d" % ev.button_index
	if ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.5:
		return "axis:%d:%s" % [ev.axis, "-" if ev.axis_value < 0.0 else "+"]
	return ""


func binding_label(action: String, index: int = 0) -> String:
	var list: Array = bindings.get(action, [])
	if index >= list.size() or str(list[index]) == "":
		return "—"
	var spec := str(list[index])
	if spec.begins_with("mouse:"):
		return {"mouse:1": "Left mouse", "mouse:2": "Right mouse", "mouse:3": "Middle mouse",
			"mouse:4": "Wheel up", "mouse:5": "Wheel down"}.get(spec, spec)
	return spec


# ------------------------------------------------------------------ apply

func master_output() -> float:
	## What the Master bus actually gets: the slider value scaled by the cap (lifted by the debug option).
	var cap := 1.0 if bool(get_value("debug", "volume_unlock")) else MASTER_CAP
	return float(get_value("audio", "master")) * cap


func apply_all() -> void:
	for section in data:
		for key in data[section]:
			_apply(section, key)


func _apply(section: String, key: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var v = get_value(section, key)
	match section + "." + key:
		"graphics.window_mode":
			if OS.has_feature("mobile"):
				# Phones: always fullscreen (Android's immersive mode hides the status and navigation bars).
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				return
			match str(v):
				"fullscreen":
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
				"borderless":
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				_:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					_apply("graphics", "resolution")
		"graphics.resolution":
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
				var p := str(v).split("x")
				if p.size() == 2:
					var size := Vector2i(int(p[0]), int(p[1]))
					var screen := DisplayServer.screen_get_size()
					size = size.min(screen)
					DisplayServer.window_set_size(size)
					DisplayServer.window_set_position((screen - size) / 2)
		"graphics.vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		"graphics.max_fps":
			Engine.max_fps = int(v)
		"graphics.render_scale", "graphics.upscaler", "graphics.antialiasing":
			_apply_viewport()
		"audio.master", "debug.volume_unlock":
			var mi0 := AudioServer.get_bus_index("Master")
			if mi0 >= 0:
				AudioServer.set_bus_volume_db(mi0, linear_to_db(maxf(master_output(), 0.0001)))
		"audio.effects", "audio.voice", "audio.ambience", "audio.ui":
			var bus: String = {"master": "Master", "effects": "Effects", "voice": "Voice", "ambience": "Ambience", "ui": "UI"}[key]
			var idx := AudioServer.get_bus_index(bus)
			if idx >= 0:
				AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(float(v), 0.0001)))
		"audio.night_mode":
			var mi := AudioServer.get_bus_index("Master")
			for i in AudioServer.get_bus_effect_count(mi):
				if AudioServer.get_bus_effect(mi, i) is AudioEffectCompressor:
					AudioServer.set_bus_effect_enabled(mi, i, bool(v))
		"audio.mic_device":
			if str(v) in AudioServer.get_input_device_list():
				AudioServer.input_device = str(v)
	return


func _apply_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var scale := clampf(float(get_value("graphics", "render_scale")), 0.5, 1.0)
	var up := str(get_value("graphics", "upscaler"))
	# FSR and TAA exist only in the Forward+ renderer; phones (Mobile) and old GPUs (Compatibility) scale bilinearly.
	var fwd := RenderingServer.get_current_rendering_method() == "forward_plus"
	if fwd and up == "fsr2" and scale < 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	elif fwd and scale < 1.0:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	var aa := str(get_value("graphics", "antialiasing"))
	vp.use_taa = fwd and aa == "taa" and up != "fsr2"
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = Viewport.MSAA_2X if aa == "msaa" else Viewport.MSAA_DISABLED


## The laser pointer colours a player can pick (Settings, Profile): id -> [name, beam colour].
const LASER_COLORS := {
	"red": ["Red", Color(1.0, 0.12, 0.1)], "purple": ["Purple", Color(0.62, 0.22, 1.0)], "green": ["Green", Color(0.2, 1.0, 0.25)],
	"blue": ["Blue", Color(0.2, 0.45, 1.0)], "pink": ["Pink", Color(1.0, 0.3, 0.72)], "yellow": ["Yellow", Color(1.0, 0.88, 0.15)],
}


static func laser_color(id: String) -> Color:
	return (LASER_COLORS.get(id, LASER_COLORS.red) as Array)[1]


func player_name() -> String:
	var n := str(get_value("player", "name")).strip_edges()
	if n == "":
		n = "Player%d" % (randi() % 900 + 100)
		set_value("player", "name", n)
		save_settings()
	return n
