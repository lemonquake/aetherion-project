"""work/sounds in the game: class reloads, magazine seat, attachment click, player hit / headshot / death, menu
clicks; calibre colour chip on each gun in the SmarTab and the calibre in pickup prompts."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

d = Patch('game/src/core/defs.gd')
d.rep('''func is_weapon(id: String) -> bool:''', '''func ammo_color(id: String) -> Color:
	## The calibre's colour (items.json "color") for an ammunition item or a gun; grey when it has none.
	var aid := ammo_item(id) if is_weapon(id) else id
	var c: Array = items.get(aid, {}).get("color", [150, 150, 150])
	return Color8(int(c[0]), int(c[1]), int(c[2]))


func calibre_name(id: String) -> String:
	## Short calibre label for a gun or its ammunition ("5.56", "12 ga").
	var aid := ammo_item(id) if is_weapon(id) else id
	return {"ammo_9x19": "9mm", "ammo_45acp": ".45", "ammo_357": ".357", "ammo_12buck": "12 ga", "ammo_12slug": "12 ga slug",
		"ammo_556": "5.56", "ammo_762x39": "7.62", "ammo_308": ".308", "ammo_50ae": ".50 AE"}.get(aid, "")


func is_weapon(id: String) -> bool:''')
d.save()

w = Patch('game/src/match/world.gd')
w.rep('''	if st0 != WeaponState.RELOAD and ch.wpn.state == WeaponState.RELOAD:
		server_sound("mag_out" if feed == "mag" else "switch_click", at, 0.0, -1)
	elif ch.wpn.state == WeaponState.RELOAD and rounds > rounds0 and feed != "mag":
		server_sound("mag_in", at, -6.0, -1)
	elif st0 == WeaponState.RELOAD and ch.wpn.state != WeaponState.RELOAD and feed == "mag" and rounds > rounds0:
		server_sound("mag_in", at, 0.0, -1)''', '''	if st0 != WeaponState.RELOAD and ch.wpn.state == WeaponState.RELOAD:
		# Magazine guns: the reload sequence of their class; tubes, cylinders and break actions: open up.
		var cls := str(ch.wpn.def().get("class", "rifle"))
		var seq := {"handgun": "reload_pistol", "smg": "reload_smg", "precision": "reload_sniper", "marksman": "reload_sniper"}.get(cls, "reload_rifle")
		server_sound(seq if feed == "mag" else "switch_click", at, 0.0, -1)
	elif ch.wpn.state == WeaponState.RELOAD and rounds > rounds0 and feed != "mag":
		server_sound("mag_in", at, -6.0, -1)
	elif st0 == WeaponState.RELOAD and ch.wpn.state != WeaponState.RELOAD and feed == "mag" and rounds > rounds0:
		server_sound("reload_finish", at, 0.0, -1)''')
w.rep('''	var absorbed: String = res.get("absorbed_by", "")
	_ev_hit.rpc(ch.eid, part, pos, dir, absorbed, bool(res.get("armor_broken", false)), float(res.damage))''', '''	var absorbed: String = res.get("absorbed_by", "")
	if float(res.damage) > 0.5 and not res.get("killed", false):
		server_sound("headshot" if part == "head" else "player_hit", ch.global_position + Vector3.UP * (1.6 if part == "head" else 1.1), 0.0, -1)
	_ev_hit.rpc(ch.eid, part, pos, dir, absorbed, bool(res.get("armor_broken", false)), float(res.damage))''')
w.rep('''	if res.get("killed", false) and ch.mode != Motor.DEAD:
		interaction.server_drop_held(ch, false)''', '''	if res.get("killed", false) and ch.mode != Motor.DEAD:
		server_sound("death", ch.global_position + Vector3.UP * 1.2, 0.0, -1)
		interaction.server_drop_held(ch, false)''')
w.save()

i = Patch('game/src/match/interaction.gd')
i.rep('''func fit(ch, slot: int, att: String) -> void:''', '''func _attach_click(ch) -> void:
	world.server_sound("attach", ch.global_position + Vector3.UP * 1.2, 0.0, -1)


func fit(ch, slot: int, att: String) -> void:''')
i.save()

u = Patch('game/src/ui/ui_theme.gd')
u.rep('''	b.custom_minimum_size = Vector2(min_w, 44)
	b.pressed.connect(cb)
	return b''', '''	b.custom_minimum_size = Vector2(min_w, 44)
	# Menu clicks (work/sounds/buttons): back / cancel / close sound different from everything else.
	var back := text.to_lower().begins_with("back") or text.to_lower() in ["cancel", "close", "leave", "quit"]
	b.pressed.connect(func(): SoundSys.play_ui("ui_back" if back else "ui_select"))
	b.pressed.connect(cb)
	return b''')
u.save()

s = Patch('game/src/ui/smartab_ui.gd')
s.rep('''		_t("%s  %s" % [names[s - 1], str(d.get("name", w.id))], Vector2(18, y + 26), 26, INK if ch.wpn.cur == s else DIM)''',
      '''		var title := "%s  %s" % [names[s - 1], str(d.get("name", w.id))]
		_t(title, Vector2(18, y + 26), 26, INK if ch.wpn.cur == s else DIM)
		# Calibre chip in the ammunition's colour: guns sharing a chip share ammunition.
		var cx := 30.0 + _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, int(26 * _scale)).x
		var chip := Rect2(cx, y + 6, 78, 26)
		draw_rect(chip, Defs.ammo_color(str(w.id)))
		_t(Defs.calibre_name(str(w.id)), chip.position + Vector2(8, 20), 18, Color(1, 1, 1))''')
s.save()

h = Patch('game/src/ui/hud.gd')
h.rep('''			if Defs.is_attachment(iid):''', '''			if Defs.is_weapon(iid) or iid.begins_with("ammo_"):
				label += "  [%s]" % Defs.calibre_name(iid)
			if Defs.is_attachment(iid):''')
h.save()
