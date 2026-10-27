"""Patch (test driver): verify the master volume cap and its debug unlock on the real audio bus."""
p = 'A:/Python/aetherion-project/game/src/debug/autotest.gd'
s = open(p, encoding='utf-8').read()
old = '''	await _deploy()
	if not is_instance_valid(ch):
		return'''
new = '''	_volume_cap()
	await _deploy()
	if not is_instance_valid(ch):
		return'''
assert s.count(old) == 1
s = s.replace(old, new)
old = '''func _deploy() -> void:'''
new = '''func _volume_cap() -> void:
	## Slider 100 plays at 75% of full output; the debug unlock makes 100 full. Restores the player's settings.
	var keep_master = Settings.get_value("audio", "master")
	var keep_unlock = Settings.get_value("debug", "volume_unlock")
	Settings.set_value("debug", "volume_unlock", false)
	Settings.set_value("audio", "master", 1.0)
	var capped := db_to_linear(AudioServer.get_bus_volume_db(0))
	Settings.set_value("debug", "volume_unlock", true)
	var full := db_to_linear(AudioServer.get_bus_volume_db(0))
	Settings.set_value("debug", "volume_unlock", keep_unlock)
	Settings.set_value("audio", "master", keep_master)
	_check("master_volume_cap", absf(capped - 0.75) < 0.005 and absf(full - 1.0) < 0.005,
		"slider 100 -> %.3f of full output; with debug unlock -> %.3f" % [capped, full])


func _deploy() -> void:'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
