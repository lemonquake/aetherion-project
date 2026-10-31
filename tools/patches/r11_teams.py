"""r11: Deathmatch takes two or three teams (three by default) of up to seven players each.

Spawns: the plan's spawn_centres (two teams, NW plaza vs SE yard) and spawn_centres_3 (three teams round the middle:
the flats parking NW, the East Yard, the South Yard). Team names come from rules.json deathmatch.team_names
(three teams) or team_names_2 (two teams).
    python -I tools/patches/r11_teams.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch, ROOT

# ---------------------------------------------------------------- rules.json (edited as JSON text, key order kept)
p = Patch('game/data/rules.json')
p.rep('"_doc": "Team vs team on Lawless Sub: 2 teams, no respawn, no downed state, chosen guns plus armour and a heavy-plate helmet.",\n'
      '    "teams": 2, "team_size": 10, "max_team_size": 10,\n'
      '    "team_names": ["West Team", "East Team"],',
      '"_doc": "Team vs team on Lawless Sub: 2 or 3 teams (3 by default) of up to 7, no respawn, no downed state, chosen guns plus armour and a heavy-plate helmet.",\n'
      '    "teams": 3, "team_size": 7, "max_team_size": 7, "max_teams": 3,\n'
      '    "team_names": ["North Team", "East Team", "South Team"],\n'
      '    "team_names_2": ["West Team", "East Team"],')
p.save()

# ---------------------------------------------------------------- net.gd: seating
p = Patch('game/src/net/net.gd')
p.rep('const DM_MAX_TEAM_SIZE := 10  # Deathmatch: two teams of up to 10',
      'const DM_MAX_TEAM_SIZE := 7   # Deathmatch: two or three teams of up to 7 (r11)\n'
      'const DM_MAX_TEAMS := 3')
p.rep('peer.create_server(port, maxi(MAX_TEAMS * MAX_TEAM_SIZE, 2 * DM_MAX_TEAM_SIZE) + 4, 4)',
      'peer.create_server(port, maxi(MAX_TEAMS * MAX_TEAM_SIZE, DM_MAX_TEAMS * DM_MAX_TEAM_SIZE) + 4, 4)')
p.rep('''		# Deathmatch: join the smaller of the two teams.
		var c := [0, 0]
		for q in players:
			var tq := int(players[q].team)
			if q != pid and tq >= 0 and tq < 2:
				c[tq] += 1
		var tm := 0 if int(c[0]) <= int(c[1]) else 1
		return tm if int(c[tm]) < team_size() else -1''',
      '''		# Deathmatch: join the smallest team.
		var nt := dm_teams()
		var c := []
		c.resize(nt)
		c.fill(0)
		for q in players:
			var tq := int(players[q].team)
			if q != pid and tq >= 0 and tq < nt:
				c[tq] += 1
		var tm := 0
		for t in nt:
			if int(c[t]) < int(c[tm]):
				tm = t
		return tm if int(c[tm]) < team_size() else -1''')
p.rep('''func max_team_size() -> int:
	return DM_MAX_TEAM_SIZE if is_dm() else MAX_TEAM_SIZE''',
      '''func max_team_size() -> int:
	return DM_MAX_TEAM_SIZE if is_dm() else MAX_TEAM_SIZE


func dm_teams() -> int:
	## Deathmatch team count: 2 or 3.
	return clampi(int(config.get("teams", 3)), 2, DM_MAX_TEAMS)''')
p.rep('''				config.teams = int(Defs.rule("deathmatch.teams", 2))''',
      '''				config.teams = clampi(int(Defs.rule("deathmatch.teams", 3)), 2, DM_MAX_TEAMS)''')
p.rep('''	elif is_dm() and key == "teams":
		config.teams = 2''',
      '''	elif is_dm() and key == "teams":
		config.teams = clampi(int(value), 2, DM_MAX_TEAMS)''')
p.rep('''	## Fill empty team slots: keep chosen teams, then pack the rest in join order (Deathmatch: into the smaller of
	## the two teams, so bots even them out).''',
      '''	## Fill empty team slots: keep chosen teams, then pack the rest in join order (Deathmatch: into the smallest
	## team, so bots even them out).''')
p.rep('''		if dm and t >= 2:''', '''		if dm and t >= dm_teams():''')
p.rep('''		if dm:
			t = 0 if int(counts.get(0, 0)) <= int(counts.get(1, 0)) else 1''',
      '''		if dm:
			for k in dm_teams():
				if int(counts.get(k, 0)) < int(counts.get(t, 0)):
					t = k''')
p.save()

# ---------------------------------------------------------------- lobby
p = Patch('game/src/ui/lobby_ui.gd')
p.rep('''			_setup_box.add_child(_field("Players per team", UITheme.stepper(Net.team_size(), 1, 10, func(v): Net.set_config("team_size", v))))''',
      '''			_setup_box.add_child(_field("Teams", UITheme.stepper(Net.dm_teams(), 2, Net.DM_MAX_TEAMS, func(v): Net.set_config("teams", v))))
			_setup_box.add_child(_field("Players per team", UITheme.stepper(Net.team_size(), 1, Net.DM_MAX_TEAM_SIZE, func(v): Net.set_config("team_size", v))))''')
p.rep('''		if dm:
			rows.append(["Players per team", str(Net.team_size())])''',
      '''		if dm:
			rows.append_array([["Teams", str(Net.dm_teams())], ["Players per team", str(Net.team_size())]])''')
p.rep('''	## Host: switch the lobby between Classic (5 squads of 4 on Sitio Kalinaw) and Deathmatch (2 teams of 10 on
	## Lawless Sub). The choice is also remembered for the menu.''',
      '''	## Host: switch the lobby between Classic (5 squads of 4 on Sitio Kalinaw) and Deathmatch (3 teams of 7 on
	## Lawless Sub). The choice is also remembered for the menu.''')
p.rep('''		Net.set_config("teams", 2)
		Net.set_config("team_size", int(Defs.rule("deathmatch.team_size", 10)))''',
      '''		Net.set_config("teams", int(Defs.rule("deathmatch.teams", 3)))
		Net.set_config("team_size", int(Defs.rule("deathmatch.team_size", 7)))''')
p.rep('''		_info.text = "Deathmatch on %s · %s against %s, %d a side · %d human%s (%d ready) and %d bot%s · %s" % [
			UITheme.MAP_NAMES.get(str(Net.config.get("map", "lawless_sub")), ""), UITheme.dm_team_name(0), UITheme.dm_team_name(1), size,''',
      '''		var tn := []
		for t in Net.dm_teams():
			tn.append(UITheme.dm_team_name(t))
		_info.text = "Deathmatch on %s · %s, %d a side · %d human%s (%d ready) and %d bot%s · %s" % [
			UITheme.MAP_NAMES.get(str(Net.config.get("map", "lawless_sub")), ""), " against ".join(tn), size,''')
p.rep('''## r7 Deathmatch: two teams (West Team / East Team, rules.json deathmatch.team_names) of up to 10, the host sets the''',
      '''## r7 Deathmatch (r11: two or three teams, North / East / South Team, rules.json deathmatch.team_names) of up to 7, the host sets the''')
p.save()

# ---------------------------------------------------------------- team names
p = Patch('game/src/ui/ui_theme.gd')
p.rep('''static func dm_team_name(t: int) -> String:
	var names: Array = Defs.rules.get("deathmatch", {}).get("team_names", ["West Team", "East Team"])
	return str(names[t]) if t >= 0 and t < names.size() else "Team %d" % (t + 1)''',
      '''static func dm_team_names(n: int) -> Array:
	## Deathmatch team names for n teams (rules.json deathmatch.team_names for three, team_names_2 for two).
	var dm: Dictionary = Defs.rules.get("deathmatch", {})
	var names: Array = dm.get("team_names_2", ["West Team", "East Team"]) if n <= 2 else dm.get("team_names", ["North Team", "East Team", "South Team"])
	return names.slice(0, n)


static func dm_team_name(t: int) -> String:
	var names := dm_team_names(clampi(int(Net.config.get("teams", 3)), 2, 3))
	return str(names[t]) if t >= 0 and t < names.size() else "Team %d" % (t + 1)''')
p.rep('''	## "Team 3" in Classic, "West Team" / "East Team" in Deathmatch.''',
      '''	## "Team 3" in Classic, "North Team" / "East Team" / "South Team" in Deathmatch.''')
p.save()

# ---------------------------------------------------------------- HUD team bar and intro
p = Patch('game/src/ui/hud.gd')
p.rep('''		if mine >= 0 and names.size() >= 2:
			toast("You are on the %s. Eliminate the %s and stay inside the haze line." % [str(names[mine]), str(names[1 - mine])])''',
      '''		if mine >= 0 and mine < names.size() and names.size() >= 2:
			var others := []
			for t in names.size():
				if t != mine:
					others.append(str(names[t]))
			toast("You are on the %s. Eliminate the %s and stay inside the haze line." % [str(names[mine]), " and the ".join(others)])''')
p.rep('''	var names: Array = info.get("team_names", ["West Team", "East Team"])
	var panel := PanelContainer.new()''',
      '''	var names: Array = info.get("team_names", ["North Team", "East Team", "South Team"])
	var panel := PanelContainer.new()''')
p.rep('''	_team_labels = []
	for t in 2:
		var col: Color''',
      '''	_team_labels = []
	for t in maxi(names.size(), 2):
		var col: Color''')
p.rep('''		if t == 0:
			row.add_child(nm)
			row.add_child(cnt)
			var vs := UITheme.label("vs", 20, UITheme.TEXT_DIM)
			row.add_child(vs)
		else:
			row.add_child(cnt)
			row.add_child(nm)''',
      '''		if t > 0:
			row.add_child(UITheme.label("vs", 20, UITheme.TEXT_DIM))
		if t == 0:
			row.add_child(nm)
			row.add_child(cnt)
		else:
			row.add_child(cnt)
			row.add_child(nm)''')
p.rep('''	var mine := _my_team()
	for t in 2:
		var n := int(alive.get(t, alive.get(str(t), 0)))''',
      '''	var mine := _my_team()
	for t in _team_labels.size():
		var n := int(alive.get(t, alive.get(str(t), 0)))''')
p.save()

# ---------------------------------------------------------------- match server
p = Patch('game/src/match/match_server.gd')
p.rep('''## r7 Deathmatch: two teams start on the ground at their spawns, armed; no plane, no downed state.''',
      '''## r7 Deathmatch: two or three teams (r11) start on the ground at their spawns, armed; no plane, no downed state.''')
p.rep('''	team_names = (_dm_rule("team_names", ["West Team", "East Team"]) as Array).duplicate()''',
      '''	var n_teams := Net.dm_teams()
	team_names = UITheme.dm_team_names(n_teams).duplicate()''')
p.rep('''	spawn_info = dm_spawns(Game.match_seed)''', '''	spawn_info = dm_spawns(Game.match_seed, n_teams)''')
p.rep('''		var team := clampi(int(p.team), 0, 1)''', '''		var team := clampi(int(p.team), 0, n_teams - 1)''')
p.rep('''	var c := _dm_centre(rng)
	var r0: float = L.PLAY_HALF * 1.45 + c.length()''',
      '''	var c := _dm_centre(rng, n_teams)
	var r0: float = L.PLAY_HALF * 1.45 + c.length()''')
p.rep('''	var a0: Vector3 = spawn_info[0].anchor
	var a1: Vector3 = spawn_info[1].anchor
	log_event("deathmatch start on %s: %d players, %d teams; spawns %s and %s (%.0f m apart, %s); day offset %.0f s; zone centre %s r=%.0f"
		% [str(Net.config.get("map", "kalinaw")), stats.size(), initial_teams, str(a0.round()), str(a1.round()), a0.distance_to(a1),
		str(spawn_info.get("source", "?")), day_offset, str(c.round()), r0])''',
      '''	var anchors := []
	var gaps := []
	for t in n_teams:
		if spawn_info.has(t):
			anchors.append(str((spawn_info[t].anchor as Vector3).round()))
			var a: Vector3 = spawn_info[t].anchor
			var b: Vector3 = spawn_info.get((t + 1) % n_teams, spawn_info[t]).anchor
			gaps.append("%.0f" % Vector2(a.x - b.x, a.z - b.z).length())
	log_event("deathmatch start on %s: %d players, %d teams; spawns %s (%s m apart, %s); day offset %.0f s; zone centre %s r=%.0f"
		% [str(Net.config.get("map", "kalinaw")), stats.size(), initial_teams, ", ".join(anchors), "/".join(gaps),
		str(spawn_info.get("source", "?")), day_offset, str(c.round()), r0])''')
p.rep('''func _dm_centre(rng: RandomNumberGenerator) -> Vector2:
	## The centre of the first circle: within centre_jitter of the map centre (or the layout's dm_centre), on dry
	## land inside the play area.
	var L = world.map.layout
	var base := Vector2.ZERO
	var dc = L.get("dm_centre") if L is Object else null''',
      '''func _dm_centre(rng: RandomNumberGenerator, n_teams: int = 2) -> Vector2:
	## The centre of the first circle: within centre_jitter of the map centre (or the layout's dm_centre; with three
	## teams the middle of their spawns), on dry land inside the play area.
	var L = world.map.layout
	var base := Vector2.ZERO
	var dc = L.get("dm_centre") if L is Object else null
	if n_teams == 3 and L is Object and L.has_method("dm_centre_for"):
		dc = L.dm_centre_for(3)''')
p.rep('''func dm_spawns(seed_value: int) -> Dictionary:
	## Team spawn areas: the layout's own (Lawless Sub: layout.spawns[team], layout.spawn_yaw[team]), or two dry,
	## open, in-play areas about 300+ m apart picked from the match seed. Each team faces the other.
	## Returns {0: {pts, yaw, anchor}, 1: {...}, "source": "layout" | "computed"}.
	var L = world.map.layout
	var out := {}
	var ls = L.get("spawns") if L is Object else null
	if ls != null and (ls is Array or ls is Dictionary) and ls.size() >= 2:
		var ly = L.get("spawn_yaw")
		for t in 2:''',
      '''func dm_spawns(seed_value: int, n_teams: int = 2) -> Dictionary:
	## Team spawn areas: the layout's own (Lawless Sub: layout.spawns[team], layout.spawn_yaw[team]; three teams use
	## layout.spawns3 / spawn_yaw3), or two dry, open, in-play areas about 300+ m apart picked from the match seed.
	## Each team faces the middle. Returns {0: {pts, yaw, anchor}, 1: {...}[, 2: ...], "source": "layout" | "computed"}.
	var L = world.map.layout
	var out := {}
	var ls = L.get("spawns") if L is Object else null
	var ly = L.get("spawn_yaw") if L is Object else null
	if n_teams == 3 and L is Object and L.get("spawns3") != null and (L.get("spawns3") as Array).size() >= 3:
		ls = L.get("spawns3")
		ly = L.get("spawn_yaw3")
	if ls != null and (ls is Array or ls is Dictionary) and ls.size() >= n_teams:
		for t in n_teams:''')
p.rep('''		if out.has(0) and out.has(1):
			if ly == null:''',
      '''		if out.size() == n_teams:
			if ly == null and n_teams == 2:''')
p.save()

# ---------------------------------------------------------------- bots: head for an enemy spawn, any enemy team
p = Patch('game/src/ai/bot_brain.gd')
p.rep('''			var other: Dictionary = world.match_server.spawn_info.get(1 - ch.team, {})''',
      '''			var foes := []
			for t in world.match_server.spawn_info:
				if t is int and t != ch.team:
					foes.append(t)
			var other: Dictionary = world.match_server.spawn_info.get(foes[rng.randi() % foes.size()], {}) if not foes.is_empty() else {}''')
p.save()
print('r11 teams patch done')
