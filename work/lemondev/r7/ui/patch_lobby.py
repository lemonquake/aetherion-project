import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()


def rep(a, c):
    global s
    assert s.count(a) == 1, a
    s = s.replace(a, c)


rep('''## outfit before the match, and who else is online.
''', '''## outfit before the match, and who else is online.
## r7 Deathmatch: two teams (West Team / East Team, rules.json deathmatch.team_names) of up to 10, the host sets the
## team size, everyone sees their loadout and opens Game Setup (src/ui/game_setup.gd) to change their guns.
''')
rep('''const Locker := preload("res://src/ui/locker.gd")
''', '''const Locker := preload("res://src/ui/locker.gd")
const GameSetup := preload("res://src/ui/game_setup.gd")
''')
rep('''var _cfg_key := ""
''', '''var _cfg_key := ""
var _setup_btn: Button
var _loadout_box: VBoxContainer
var _loadout_key := ""
var _tip: Label
var _compact := false
var _game_setup: Control
''')
rep('''	var compact := get_viewport_rect().size.x < 1500.0
''', '''	var compact := get_viewport_rect().size.x < 1500.0
	_compact = compact
''')
rep('''	head.add_child(UITheme.icon_button("locker", "Outfit", _open_locker))''', '''	_setup_btn = UITheme.icon_button("gun", "Game Setup", open_game_setup)
	head.add_child(_setup_btn)
	head.add_child(UITheme.icon_button("locker", "Outfit", _open_locker))''')
rep('''	_setup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ssc.add_child(_setup_box)
	row.add_child(_setup)''', '''	_setup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var side := UITheme.vbox(14)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ssc.add_child(side)
	side.add_child(_setup_box)
	_loadout_box = UITheme.vbox(8)
	side.add_child(_loadout_box)
	row.add_child(_setup)''')
rep('''	var tip := UITheme.label("Tap a team to join it. Bots take the seats nobody takes.", 17, UITheme.TEXT_DIM)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(tip)''', '''	var tip := UITheme.label("Tap a team to join it. Bots take the seats nobody takes.", 17, UITheme.TEXT_DIM)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip = tip
	bottom.add_child(tip)''')
rep('''	Net.lobby_changed.connect(_refresh)
	_refresh()
''', '''	Net.lobby_changed.connect(_refresh)
	if Net.is_server:
		Net.loadout_received.connect(func(pid: int):
			if Net.players.has(pid):
				print("[ui] loadout_received pid=%d %s %s" % [pid, str(Net.players[pid].get("name", "")), JSON.stringify(Net.players[pid].get("loadout", {}))]))
	# Your saved Deathmatch guns go to the server as soon as you are in the lobby (and again whenever they change).
	Profile.send_loadout()
	_refresh()
''')
# setup panel
rep('''	_setup_box.add_child(UITheme.section("Game Setup", "Only the host can change these." if not host else ""))
	var cfg := Net.config
	if host:
		_setup_box.add_child(_field("Teams", UITheme.stepper(int(cfg.get("teams", 5)), 2, Net.MAX_TEAMS, func(v): Net.set_config("teams", v))))
		_setup_box.add_child(_field("Squad size", UITheme.segmented([[1, "Solo"], [2, "Duo"], [3, "Trio"], [4, "Squad"]], Net.team_size(), func(v): Net.set_config("team_size", v))))
		_setup_box.add_child(UITheme.toggle("Fill empty slots with bots", bool(cfg.get("bots", true)), func(v): Net.set_config("bots", v)))
		_setup_box.add_child(_field("Safe zone", UITheme.segmented([[1.0, "Normal"], [1.6, "Fast"], [2.5, "Rapid"]], float(cfg.get("zone_speed", 1.0)), func(v): Net.set_config("zone_speed", v))))
	else:
		for kv in [["Teams", str(int(cfg.get("teams", 5)))], ["Squad size", str(Net.team_size())], ["Bots", "Fill empty slots" if cfg.get("bots", true) else "Off"],
				["Safe zone", {1.0: "Normal", 1.6: "Fast", 2.5: "Rapid"}.get(float(cfg.get("zone_speed", 1.0)), "Normal")]]:''', '''	_setup_box.add_child(UITheme.section("Match settings", "Only the host can change these." if not host else ""))
	var cfg := Net.config
	var dm := _dm()
	var mode_name := str(UITheme.MODE_NAMES.get(str(cfg.get("game_mode", "classic")), "Classic"))
	var map_name := str(UITheme.MAP_NAMES.get(str(cfg.get("map", "kalinaw")), str(cfg.get("map", ""))))
	if host:
		_setup_box.add_child(_field("Mode", UITheme.segmented([["classic", "Classic"], ["deathmatch", "Deathmatch"]], str(cfg.get("game_mode", "classic")), _set_mode)))
		_setup_box.add_child(_kv_row("Map", map_name))
		if dm:
			_setup_box.add_child(_field("Players per team", UITheme.stepper(Net.team_size(), 1, 10, func(v): Net.set_config("team_size", v))))
		else:
			_setup_box.add_child(_field("Teams", UITheme.stepper(int(cfg.get("teams", 5)), 2, Net.MAX_TEAMS, func(v): Net.set_config("teams", v))))
			_setup_box.add_child(_field("Squad size", UITheme.segmented([[1, "Solo"], [2, "Duo"], [3, "Trio"], [4, "Squad"]], Net.team_size(), func(v): Net.set_config("team_size", v))))
		_setup_box.add_child(UITheme.toggle("Fill empty slots with bots", bool(cfg.get("bots", true)), func(v): Net.set_config("bots", v)))
		_setup_box.add_child(_field("Safe zone", UITheme.segmented([[1.0, "Normal"], [1.6, "Fast"], [2.5, "Rapid"]], float(cfg.get("zone_speed", 1.0)), func(v): Net.set_config("zone_speed", v))))
	else:
		var rows := [["Mode", mode_name], ["Map", map_name]]
		if dm:
			rows.append(["Players per team", str(Net.team_size())])
		else:
			rows.append_array([["Teams", str(int(cfg.get("teams", 5)))], ["Squad size", str(Net.team_size())]])
		rows.append_array([["Bots", "Fill empty slots" if cfg.get("bots", true) else "Off"],
				["Safe zone", {1.0: "Normal", 1.6: "Fast", 2.5: "Rapid"}.get(float(cfg.get("zone_speed", 1.0)), "Normal")]])
		for kv in rows:''')
rep('''func _field(title: String, c: Control) -> Control:''', '''func _kv_row(k: String, v: String) -> Control:
	var h := UITheme.hbox(8)
	var kl := UITheme.label(k, 19, UITheme.TEXT_DIM)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(kl)
	h.add_child(UITheme.label(v, 21, UITheme.TEXT, UITheme.font_semibold))
	return h


func _dm() -> bool:
	return str(Net.config.get("game_mode", "classic")) == "deathmatch"


func _set_mode(m: String) -> void:
	## Host: switch the lobby between Classic (5 squads of 4 on Sitio Kalinaw) and Deathmatch (2 teams of 10 on
	## Lawless Sub). The choice is also remembered for the menu.
	if not Net.is_server or m == str(Net.config.get("game_mode", "classic")):
		return
	Profile.set_game_mode(m)
	Net.set_config("game_mode", m)
	Net.set_config("map", str(Defs.rule("game_modes.%s.map" % m, "lawless_sub" if m == "deathmatch" else "kalinaw")))
	if m == "deathmatch":
		Net.set_config("teams", 2)
		Net.set_config("team_size", int(Defs.rule("deathmatch.team_size", 10)))
	else:
		Net.set_config("teams", 5)
		Net.set_config("team_size", 4)


func _loadout_panel() -> void:
	## Deathmatch: your two guns (as the server has them once it answered, else as saved here) and the kit.
	var lo: Dictionary = Net.players.get(Net.local_pid, {}).get("loadout", {})
	var confirmed := not lo.is_empty()
	if not confirmed:
		lo = Profile.get_loadout()
	var key := "%s|%s|%s" % [_dm(), JSON.stringify(lo), confirmed]
	if key == _loadout_key:
		return
	_loadout_key = key
	for c in _loadout_box.get_children():
		c.queue_free()
	_loadout_box.visible = _dm()
	if not _dm():
		return
	_loadout_box.add_child(UITheme.section("Your loadout"))
	var guns := UITheme.hbox(8)
	for kind in ["primary", "secondary"]:
		guns.add_child(GameSetup.gun_tile(str(lo.get(kind, "")), "Primary" if kind == "primary" else "Secondary", Vector2(150, 66)))
	_loadout_box.add_child(guns)
	var kit := []
	for g in Defs.rules.get("deathmatch", {}).get("gear", []):
		kit.append(Defs.item_name(str(g)))
	var kl := UITheme.label("Everyone also starts with: %s." % ", ".join(kit), 16, UITheme.TEXT_DIM)
	kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loadout_box.add_child(kl)
	var b := UITheme.icon_button("gun", "Change guns", open_game_setup)
	_loadout_box.add_child(b)


func open_game_setup() -> Control:
	if _game_setup and is_instance_valid(_game_setup):
		return _game_setup
	_game_setup = GameSetup.new()
	_game_setup.closed.connect(func(): _loadout_key = ""; _refresh())
	add_child(_game_setup)
	return _game_setup


func _field(title: String, c: Control) -> Control:''')
# refresh
rep('''	_title.text = str(Net.config.get("name", "")) if str(Net.config.get("name", "")) != "" else "Custom game"
	_setup_panel()''', '''	_title.text = str(Net.config.get("name", "")) if str(Net.config.get("name", "")) != "" else "Custom game"
	_setup_panel()
	_loadout_panel()
	var dm := _dm()
	_setup_btn.visible = dm
	_tip.text = ("Tap a team to switch to it. Bots take the seats nobody takes. No respawns: the last team standing wins." if dm
		else "Tap a team to join it. Bots take the seats nobody takes.")
	var mine: Dictionary = Net.players.get(Net.local_pid, {}).get("loadout", {})
	if not mine.is_empty() and JSON.stringify(mine) != str(get_meta("lo_seen", "")):
		set_meta("lo_seen", JSON.stringify(mine))
		print("[ui] lobby shows my loadout (pid %d): %s" % [Net.local_pid, JSON.stringify(mine)])''')
rep('''	_info.text = "%d human%s (%d ready) and %d bot%s · %d teams of %d · %s" % [humans, "" if humans == 1 else "s", ready, bots, "" if bots == 1 else "s",
		n_teams, size, "You are hosting." if host else "Waiting for the host to start."]''', '''	if dm:
		_info.text = "Deathmatch on %s · %s against %s, %d a side · %d human%s (%d ready) and %d bot%s · %s" % [
			UITheme.MAP_NAMES.get(str(Net.config.get("map", "lawless_sub")), ""), UITheme.dm_team_name(0), UITheme.dm_team_name(1), size,
			humans, "" if humans == 1 else "s", ready, bots, "" if bots == 1 else "s", "You are hosting." if host else "Waiting for the host to start."]
	else:
		_info.text = "%d human%s (%d ready) and %d bot%s · %d teams of %d · %s" % [humans, "" if humans == 1 else "s", ready, bots, "" if bots == 1 else "s",
			n_teams, size, "You are hosting." if host else "Waiting for the host to start."]
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART''')
# team card
rep('''	var card := Button.new()
	card.theme_type_variation = "CardButton"
	card.toggle_mode = true
	card.button_pressed = mine
	card.custom_minimum_size = Vector2(300, 74 + size * 52)''', '''	var dm := _dm()
	var row_h := 40 if dm else 44
	var card := Button.new()
	card.theme_type_variation = "CardButton"
	card.toggle_mode = true
	card.button_pressed = mine
	card.custom_minimum_size = Vector2(430 if dm and not _compact else (380 if dm else 300), 74 + size * (row_h + 6) if dm else 74 + size * 52)''')
rep('''	var tl := UITheme.label("Team %d" % (t + 1), 26, col.lightened(0.1), UITheme.font_condensed)''', '''	var tl := UITheme.label(UITheme.team_name(t), 26, col.lightened(0.1), UITheme.font_condensed)''')
rep('''	for pid in members:
		v.add_child(_slot_row(pid))
	var bots_on: bool = Net.config.get("bots", true)
	for i in size - members.size():
		var r := UITheme.hbox(8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.custom_minimum_size = Vector2(0, 44)''', '''	for pid in members:
		var sr := _slot_row(pid)
		sr.custom_minimum_size.y = row_h
		v.add_child(sr)
	var bots_on: bool = Net.config.get("bots", true)
	for i in size - members.size():
		var r := UITheme.hbox(8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.custom_minimum_size = Vector2(0, row_h)''')
rep('''		r.add_child(UITheme.label("Bot" if bots_on else "Open seat", 19, UITheme.TEXT_DIM * Color(1, 1, 1, 0.75)))''', '''		r.add_child(UITheme.label(("Bot (fills at the start)" if dm else "Bot") if bots_on else "Open seat", 19, UITheme.TEXT_DIM * Color(1, 1, 1, 0.75)))''')
rep('''			r.add_child(UITheme.label("Tap to join", 16, UITheme.ACCENT))''', '''			r.add_child(UITheme.label("Tap to switch" if dm and Net.players.get(Net.local_pid, {}).get("team", -1) >= 0 else "Tap to join", 16, UITheme.ACCENT))''')
rep('''	if not p.bot:
		r.add_child(UITheme.pill("Lv %d" % int(p.get("level", 1)), UITheme.ACCENT, 13))''', '''	if not p.bot:
		var lo: Dictionary = p.get("loadout", {})
		if _dm() and not lo.is_empty():
			var ll := UITheme.label("%s + %s" % [Defs.item_name(str(lo.get("primary", ""))), Defs.item_name(str(lo.get("secondary", "")))], 15, UITheme.TEXT_DIM)
			ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.add_child(ll)
		r.add_child(UITheme.pill("Lv %d" % int(p.get("level", 1)), UITheme.ACCENT, 13))''')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('patched')
