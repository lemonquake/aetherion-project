"""Patch: master volume 100 plays at 75% of full output; a Debug settings option lifts the cap (100 = full)."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/core/settings.gd', [
    ('''const PATH := "user://settings.cfg"
''', '''const PATH := "user://settings.cfg"
## The master slider shows 0-100, but 100 plays at this fraction of full output unless debug.volume_unlock is on.
const MASTER_CAP := 0.75
'''),
    ('''	"accessibility": {"camera_motion": "normal", "smartab_text_scale": 1.0, "reduce_flashes": false, "smartab_brightness": 0.6},
}''', '''	"accessibility": {"camera_motion": "normal", "smartab_text_scale": 1.0, "reduce_flashes": false, "smartab_brightness": 0.6},
	"debug": {"volume_unlock": false},
}'''),
    ('''		"audio.master", "audio.effects", "audio.voice", "audio.ambience", "audio.ui":''', '''		"audio.master", "debug.volume_unlock":
			var mi0 := AudioServer.get_bus_index("Master")
			if mi0 >= 0:
				AudioServer.set_bus_volume_db(mi0, linear_to_db(maxf(master_output(), 0.0001)))
		"audio.effects", "audio.voice", "audio.ambience", "audio.ui":'''),
    ('''# ------------------------------------------------------------------ apply
''', '''# ------------------------------------------------------------------ apply

func master_output() -> float:
	## What the Master bus actually gets: the slider value scaled by the cap (lifted by the debug option).
	var cap := 1.0 if bool(get_value("debug", "volume_unlock")) else MASTER_CAP
	return float(get_value("audio", "master")) * cap

'''),
])

patch('src/ui/settings_ui.gd', [
    ('''func _slider(section: String, key: String, lo: float, hi: float, step: float, fmt: String = "%.2f") -> Control:''',
     '''func _slider(section: String, key: String, lo: float, hi: float, step: float, fmt: String = "%.2f", shown: float = 1.0) -> Control:
	## `shown` scales the number in the label (e.g. 100 to show a 0-1 value as 0-100).'''),
    ('''	var l := UITheme.label(fmt % s.value, 18, UITheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(val): Settings.set_value(section, key, val); l.text = fmt % val)''',
     '''	var l := UITheme.label(fmt % (s.value * shown), 18, UITheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(val): Settings.set_value(section, key, val); l.text = fmt % (val * shown))'''),
    ('''	_row(p, "Master volume", _slider("audio", "master", 0.0, 1.0, 0.01, "%.2f"))''',
     '''	_row(p, "Master volume", _slider("audio", "master", 0.0, 1.0, 0.01, "%.0f", 100.0))'''),
    ('''	_tabs.add_child(_access())''', '''	_tabs.add_child(_access())
	_tabs.add_child(_debug())'''),
    ('''func _controls() -> Control:''', '''func _debug() -> Control:
	var p := _page("Debug")
	_row(p, "Unlock master volume", _check("debug", "volume_unlock"),
		"Normally a master volume of 100 plays at 75% of full output, to keep gunshots from being painful. "
		+ "With this on, 100 means full output.")
	return p


func _controls() -> Control:'''),
])
