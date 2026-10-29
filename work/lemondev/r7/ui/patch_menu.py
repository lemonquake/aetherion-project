import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()


def rep(a, c):
    global s
    assert s.count(a) == 1, a
    s = s.replace(a, c)


rep('''const Locker := preload("res://src/ui/locker.gd")
''', '''const Locker := preload("res://src/ui/locker.gd")
const GameSetup := preload("res://src/ui/game_setup.gd")
''')
rep('''var _create := {"name": "", "teams": 5, "team_size": 4, "bots": true, "zone_speed": 1.0}''',
    '''var _create := {"name": "", "teams": 5, "team_size": 4, "bots": true, "zone_speed": 1.0, "game_mode": "classic", "dm_team_size": 10}''')
rep('''	_create.name = "%s's game" % Settings.player_name()
	_show("home")''', '''	_create.name = "%s's game" % Settings.player_name()
	_create.game_mode = Profile.game_mode
	_create.dm_team_size = int(Defs.rule("deathmatch.team_size", 10))
	_show("home")''')
rep('''	_refresh_chip()
	_refresh_online()
''', '''	_refresh_chip()
	_refresh_online()
	if Game.arg("ui_tour_r7") and not Game.has_node("UiTourR7"):
		var tour: Node = GameSetup.Tour.new()
		tour.name = "UiTourR7"
		Game.add_child(tour)
''')
i = s.index('func _page_home() -> Control:')
j = s.index('func _last_match_card() -> Control:')
s = s[:i] + open(sys.argv[2], encoding='utf-8').read() + s[j:]
rep('''	cv.add_child(_field("Game name", name))
	cv.add_child(_field("Teams", UITheme.stepper(int(_create.teams), 2, Net.MAX_TEAMS, func(v): _create.teams = v; _update_summary())))
	cv.add_child(_field("Squad size", UITheme.segmented([[1, "Solo"], [2, "Duo"], [3, "Trio"], [4, "Squad"]], int(_create.team_size), func(v): _create.team_size = v; _update_summary())))''',
    '''	cv.add_child(_field("Game name", name))
	cv.add_child(_field("Mode", UITheme.segmented([["classic", "Classic"], ["deathmatch", "Deathmatch"]], str(_create.game_mode), _set_mode)))
	if str(_create.game_mode) == "deathmatch":
		cv.add_child(_field("Players per team (%s and %s)" % [UITheme.dm_team_name(0), UITheme.dm_team_name(1)],
			UITheme.stepper(int(_create.dm_team_size), 1, 10, func(v): _create.dm_team_size = v; _update_summary())))
	else:
		cv.add_child(_field("Teams", UITheme.stepper(int(_create.teams), 2, Net.MAX_TEAMS, func(v): _create.teams = v; _update_summary())))
		cv.add_child(_field("Squad size", UITheme.segmented([[1, "Solo"], [2, "Duo"], [3, "Trio"], [4, "Squad"]], int(_create.team_size), func(v): _create.team_size = v; _update_summary())))''')
rep('''	var hb := UITheme.primary("HOST GAME", _host_custom, 0, 72)
	cv.add_child(hb)''', '''	if str(_create.game_mode) == "deathmatch":
		cv.add_child(_loadout_button())
	var hb := UITheme.primary("HOST GAME", _host_custom, 0, 72)
	cv.add_child(hb)''')
rep('''	var slots := int(_create.teams) * int(_create.team_size)
	_summary.text = "%d teams of %d: %d players. %s" % [int(_create.teams), int(_create.team_size), slots,''',
    '''	if str(_create.game_mode) == "deathmatch":
		var n := int(_create.dm_team_size)
		_summary.text = "Deathmatch on %s: %s against %s, %d a side. %s" % [UITheme.MAP_NAMES.get(_map_for("deathmatch"), ""), UITheme.dm_team_name(0), UITheme.dm_team_name(1), n,
			("Bots fill whatever the humans leave open (%d with just you)." % (2 * n - 1)) if _create.bots else "No bots: only humans play."]
		return
	var slots := int(_create.teams) * int(_create.team_size)
	_summary.text = "Classic on %s: %d teams of %d, %d players. %s" % [UITheme.MAP_NAMES.get(_map_for("classic"), ""), int(_create.teams), int(_create.team_size), slots,''')
rep('''		sub.add_child(UITheme.pill("LAN" if g.get("lan", false) else "Online", UITheme.ACCENT2, 13))''',
    '''		var gm := str(g.get("game_mode", "classic"))
		sub.add_child(UITheme.pill(str(UITheme.MODE_NAMES.get(gm, gm.capitalize())), UITheme.ACCENT if gm == "deathmatch" else UITheme.TEXT_DIM, 13))
		if g.has("map"):
			sub.add_child(UITheme.pill(str(UITheme.MAP_NAMES.get(str(g.map), str(g.map))), UITheme.TEXT_DIM, 13))
		sub.add_child(UITheme.pill("LAN" if g.get("lan", false) else "Online", UITheme.ACCENT2, 13))''')
rep('''func _quick_match() -> void:
	var err := Net.host()
	if err != OK:
		show_status("Could not start a local game (error %d)." % err)
		return
	Net.set_config("name", "%s's practice" % Settings.player_name())
	Net.set_config("teams", 5)
	Net.set_config("team_size", 4)
	Net.set_config("bots", true)
	Game.show_lobby()''', '''func _quick_match() -> void:
	var err := Net.host(int(Game.arg("port", Net.DEFAULT_PORT)))
	if err != OK:
		show_status("Could not start a local game (error %d)." % err)
		return
	var mode := Profile.game_mode
	Net.set_config("name", "%s's practice" % Settings.player_name())
	_apply_mode_config(mode, int(Defs.rule("deathmatch.team_size", 10)))
	if mode != "deathmatch":
		Net.set_config("teams", 5)
		Net.set_config("team_size", 4)
	Net.set_config("bots", true)
	Profile.send_loadout()
	Game.show_lobby()''')
rep('''	var err := Net.host()
	if err != OK:
		show_status("Could not open port %d (error %d). Another game may be running." % [Net.DEFAULT_PORT, err])
		return
	Net.set_config("name", str(_create.name).strip_edges() if str(_create.name).strip_edges() != "" else "%s's game" % Settings.player_name())
	Net.set_config("teams", int(_create.teams))
	Net.set_config("team_size", int(_create.team_size))''', '''	var port := int(Game.arg("port", Net.DEFAULT_PORT))
	var err := Net.host(port)
	if err != OK:
		show_status("Could not open port %d (error %d). Another game may be running." % [port, err])
		return
	Net.set_config("name", str(_create.name).strip_edges() if str(_create.name).strip_edges() != "" else "%s's game" % Settings.player_name())
	var mode := str(_create.game_mode)
	_apply_mode_config(mode, int(_create.dm_team_size))
	if mode != "deathmatch":
		Net.set_config("teams", int(_create.teams))
		Net.set_config("team_size", int(_create.team_size))''')
rep('''	Net.set_config("zone_speed", float(_create.zone_speed))
	Game.show_lobby()''', '''	Net.set_config("zone_speed", float(_create.zone_speed))
	Profile.send_loadout()
	Game.show_lobby()''')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('patched')
