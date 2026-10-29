"""r4: UI fixes from the first tour - tabs, roughness (glTF flips V), team on join, stats as whole numbers, tiled
panel grain, a "none" icon, a thinner pedestal ring."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
patch('src/ui/main_menu.gd', '''	if _tabs.has(id):
		_tabs[id].set_pressed_no_signal(true)''', '''	if _tabs.has(id):
		_tabs[id].button_pressed = true   # (the group lets the other tabs go)''')
patch('src/ui/locker.gd', '''	if _slot_btns.has(sid):
		_slot_btns[sid].set_pressed_no_signal(true)''', '''	if _slot_btns.has(sid):
		_slot_btns[sid].button_pressed = true''')
patch('src/player/outfit.gd', '''	v_layer = floor(UV2.x);
	v_rough = UV2.y;''', '''	v_layer = floor(UV2.x);
	v_rough = 1.0 - UV2.y;   // glTF stores V flipped''')
patch('src/ui/main_menu.gd', '''	for kv in [["Matches", str(s.matches)], ["Wins", str(s.wins)], ["Top 5", str(s.top5)], ["Kills", str(s.kills)], ["Deaths", str(s.deaths)],''', '''	for kv in [["Matches", str(int(s.matches))], ["Wins", str(int(s.wins))], ["Top 5", str(int(s.top5))], ["Kills", str(int(s.kills))], ["Deaths", str(int(s.deaths))],''')
patch('src/ui/main_menu.gd', '''			var me := {"rank": "—", "name": Settings.player_name(), "level": Profile.level(), "wins": Profile.stats.wins, "kills": Profile.stats.kills,
				"kd": "%.2f" % (float(Profile.stats.kills) / maxf(float(Profile.stats.deaths), 1.0)), "matches": Profile.stats.matches}''', '''			var me := {"rank": "—", "name": Settings.player_name(), "level": Profile.level(), "wins": int(Profile.stats.wins), "kills": int(Profile.stats.kills),
				"kd": "%.2f" % (float(Profile.stats.kills) / maxf(float(Profile.stats.deaths), 1.0)), "matches": int(Profile.stats.matches)}''')
patch('src/ui/ui_theme.gd', '''	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


static func get_theme() -> Theme:''', '''	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	# Tile the middle: stretched, the grain turns into streaks across a big panel.
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return s


static func get_theme() -> Theme:''')
patch('src/ui/icons.gd', '''		"back":''', '''		"none":
			_ring(img, Vector2(12, 12), 8, 2.2, u, c)
			_poly(img, [Vector2(6.2, 7.6), Vector2(7.6, 6.2), Vector2(17.8, 16.4), Vector2(16.4, 17.8)], u, c)
		"back":''')
patch('src/ui/locker.gd', '''			pic.texture = Icons.texture("locker" if str(it.id) != "none" else "back", 64, UITheme.TEXT_DIM)''', '''			pic.texture = Icons.texture("locker" if str(it.id) != "none" else "none", 64, UITheme.TEXT_DIM)''')
patch('src/ui/locker.gd', '''	tm.inner_radius = 0.63
	tm.outer_radius = 0.655''', '''	tm.inner_radius = 0.645
	tm.outer_radius = 0.655''')
# Every human gets a team when they arrive (the first with room); they can move with a tap.
patch('src/net/net.gd', '''		players[1].level = Profile.level()
	_broadcast_lobby()
	return OK''', '''		players[1].level = Profile.level()
		players[1].team = _first_free_team(1)
	_broadcast_lobby()
	return OK''')
patch('src/net/net.gd', '''	players[id].level = level
	_welcome.rpc_id(id, id)''', '''	players[id].level = level
	players[id].team = _first_free_team(id)
	_welcome.rpc_id(id, id)''')
patch('src/net/net.gd', '''func slot_count() -> int:''', '''func _first_free_team(pid: int) -> int:
	for t in clampi(int(config.get("teams", 5)), 1, MAX_TEAMS):
		var n := 0
		for q in players:
			if q != pid and players[q].team == t:
				n += 1
		if n < team_size():
			return t
	return -1


func slot_count() -> int:''')
