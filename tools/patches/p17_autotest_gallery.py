"""Patch (test driver): draw every weapon class in the lit lane and photograph the first-person view."""
p = 'A:/Python/aetherion-project/game/src/debug/autotest.gd'
s = open(p, encoding='utf-8').read()


def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:80])
    s = s.replace(old, new)


sub('''	await _house_lights()
	await _dark_house()''', '''	await _house_lights()
	await _gallery()
	await _dark_house()''')
sub('''func _smartab() -> void:''', '''func _gallery() -> void:
	## Each weapon class in hand under the lane bulb, hip and aimed.
	if _lane_spot == Vector3.INF:
		return
	if not ch.light.on:
		await _tap("flashlight")
	for id in ["pistol_9", "revolver_357", "shotgun_pump", "smg_9", "rifle_762", "rifle_556"]:
		var slot := 3 if Defs.weapon(id).get("slot", "long") == "handgun" else 1
		ch.wpn.slots[slot] = WeaponState.new_instance(id)
		await _tap("holster")
		await _wait(0.3)
		await _tap("weapon_%d" % slot)
		await _wait(1.3)
		await _shot("gun_%s" % id)
		if id in ["pistol_9", "rifle_762"]:
			await _hold("aim", 0.8, "gun_%s_aim" % id)
	ch.wpn.slots[1] = null
	ch.wpn.slots[3] = null
	await _tap("holster")


func _smartab() -> void:''')
sub('''var world = null
var ctl = null''', '''const WeaponState := preload("res://src/weapons/weapon_state.gd")

var world = null
var ctl = null''')
open(p, 'w', encoding='utf-8').write(s)
print('ok')
