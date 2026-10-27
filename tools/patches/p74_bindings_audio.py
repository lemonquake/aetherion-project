"""Controls and audio defaults asked for on 2026-10-27:
- T grabs / drags / carries objects; E only uses things and picks up weapons, ammunition and items.
- V pings your position to the team (so push to talk moves to Caps Lock).
- Environment sounds at 60 % by default.
Settings saved before this get a one-time migration (settings version 2) so the new keys and defaults take effect.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

s = Patch('game/src/core/settings.gd')
s.rep('''		"master": 0.9, "effects": 1.0, "voice": 1.0, "ambience": 0.8, "ui": 0.8,''',
      '''		"master": 0.9, "effects": 1.0, "voice": 1.0, "ambience": 0.6, "ui": 0.8,''')
s.rep('''	"interact": ["E", "joy:10"], "flashlight": ["F", "joy:9"], "smartab": ["Tab", "joy:4"],''',
      '''	"interact": ["E", "joy:10"], "grab": ["T", "joy:8"], "flashlight": ["F", "joy:9"], "smartab": ["Tab", "joy:4"],''')
s.rep('''	"fire_mode": ["B", "joy:14"], "push_to_talk": ["V", "joy:11"], "text_chat": ["Y", ""],''',
      '''	"fire_mode": ["B", "joy:14"], "push_to_talk": ["CapsLock", "joy:11"], "ping": ["V", "joy:5"], "text_chat": ["Y", ""],''')
s.rep('''const PATH := "user://settings.cfg"''', '''const PATH := "user://settings.cfg"
## Bumped when defaults change in a way saved settings should pick up (see _migrate).
const VERSION := 2''')
s.rep('''		for key in cfg.get_section_keys(section):
			data[section][key] = cfg.get_value(section, key)
''', '''		for key in cfg.get_section_keys(section):
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
		if is_equal_approx(float(data.get("audio", {}).get("ambience", 0.6)), 0.8):
			data.audio.ambience = 0.6
''')
s.rep('''	for action in bindings:
		cfg.set_value("bindings", action, bindings[action])
	cfg.save(PATH)''', '''	for action in bindings:
		cfg.set_value("bindings", action, bindings[action])
	cfg.set_value("meta", "version", VERSION)
	cfg.save(PATH)''')
s.save()

u = Patch('game/src/ui/settings_ui.gd')
u.rep('''"interact": "Use / pick up / hold to drag",''', '''"interact": "Use / pick up items", "grab": "Grab, drag or carry objects",''')
u.rep('''		"push_to_talk": "Push to talk",''', '''		"push_to_talk": "Push to talk", "ping": "Ping your position to the team",''')
u.save()
