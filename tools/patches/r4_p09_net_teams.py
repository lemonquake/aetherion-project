"""r4: team slots (teams x squad size, bots fill), looks/profiles in the lobby, XP and stats in match results,
stats server modes, outfits on characters."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))

# ------------------------------------------------------------------ Net
f = 'src/net/net.gd'
patch(f, '''var config: Dictionary = {"mode": "squad", "bots": true, "bot_count": 20, "map_seed": 1729, "zone_speed": 1.0}''', '''## teams x team_size slots (5 x 4 by default, up to 7 teams of up to 4); humans pick any team and bots fill the slots
## left when "bots" is on (20 bots in a practice match: 5 squads of 4, one of them yours).
var config: Dictionary = {"name": "", "mode": "squad", "teams": 5, "team_size": 4, "bots": true, "bot_count": 20, "map_seed": 1729, "zone_speed": 1.0}
var port := DEFAULT_PORT
const MAX_TEAMS := 7
const MAX_TEAM_SIZE := 4''')
patch(f, '''	shutdown()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, int(Defs.rule("max_players", 40)) + 2, 4)''', '''	shutdown()
	self.port = port
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_TEAMS * MAX_TEAM_SIZE + 4, 4)''')
patch(f, '''	if not dedicated:
		players[1] = _new_player(Settings.player_name(), false)
		players[1].platform = platform()
	_broadcast_lobby()
	return OK''', '''	if not dedicated:
		players[1] = _new_player(Settings.player_name(), false)
		players[1].platform = platform()
		players[1].look = Profile.look
		players[1].profile = Profile.id
		players[1].level = Profile.level()
	_broadcast_lobby()
	return OK''')
patch(f, '''func _new_player(pname: String, bot: bool) -> Dictionary:
	return {"name": pname, "team": -1, "ready": bot, "bot": bot, "connected": true, "in_match": false}


func add_bot(pname: String) -> int:
	_next_bot -= 1
	players[_next_bot] = _new_player(pname, true)
	_broadcast_lobby()
	return _next_bot''', '''func _new_player(pname: String, bot: bool) -> Dictionary:
	return {"name": pname, "team": -1, "ready": bot, "bot": bot, "connected": true, "in_match": false, "look": {}, "profile": "", "level": 1}


func add_bot(pname: String, look: Dictionary = {}) -> int:
	_next_bot -= 1
	players[_next_bot] = _new_player(pname, true)
	players[_next_bot].look = look
	_broadcast_lobby()
	return _next_bot


func slot_count() -> int:
	return clampi(int(config.get("teams", 5)), 1, MAX_TEAMS) * team_size()


func humans() -> int:
	var n := 0
	for pid in players:
		if not players[pid].bot:
			n += 1
	return n''')
patch(f, '''func _on_connected() -> void:
	local_pid = multiplayer.get_unique_id()
	_hello.rpc_id(1, Settings.player_name(), VERSION, platform())''', '''func _on_connected() -> void:
	local_pid = multiplayer.get_unique_id()
	_hello.rpc_id(1, Settings.player_name(), VERSION, platform(), Profile.look, Profile.id, Profile.level())''')
patch(f, '''@rpc("any_peer", "reliable")
func _hello(pname: String, version: String, plat: String = "PC") -> void:''', '''@rpc("any_peer", "reliable")
func _hello(pname: String, version: String, plat: String = "PC", look: Dictionary = {}, profile: String = "", level: int = 1) -> void:''')
patch(f, '''	if players.size() >= int(Defs.rule("max_players", 40)):
		_kick.rpc_id(id, "The game is full.")''', '''	if humans() >= slot_count():
		_kick.rpc_id(id, "The game is full.")''')
patch(f, '''	players[id] = _new_player(pname, false)
	players[id].platform = plat
	_welcome.rpc_id(id, id)''', '''	players[id] = _new_player(pname, false)
	players[id].platform = plat
	players[id].look = look
	players[id].profile = profile.substr(0, 32)
	players[id].level = level
	_welcome.rpc_id(id, id)''')
patch(f, '''func request_team(team: int) -> void:''', '''func request_look(look: Dictionary) -> void:
	## The player changed their outfit in the Locker while in a lobby.
	if is_server:
		if players.has(local_pid):
			players[local_pid].look = look
			_broadcast_lobby()
	else:
		_req_look.rpc_id(1, look)


@rpc("any_peer", "reliable")
func _req_look(look: Dictionary) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if is_server and players.has(pid) and JSON.stringify(look).length() < 2048:
		players[pid].look = look
		_broadcast_lobby()


func request_team(team: int) -> void:''')
patch(f, '''	var size := team_size()
	var count := 0
	for q in players:
		if q != pid and players[q].team == team:
			count += 1
	if team >= 0 and count >= size:
		return''', '''	var size := team_size()
	var count := 0
	for q in players:
		if q != pid and players[q].team == team:
			count += 1
	if team >= 0 and (count >= size or team >= int(config.get("teams", 5))):
		return''')
patch(f, '''func set_config(key: String, value) -> void:
	if not is_server:
		return
	config[key] = value
	_broadcast_lobby()


func team_size() -> int:
	return int(Defs.rule("modes.%s.team_size" % config.get("mode", "squad"), 4))''', '''func set_config(key: String, value) -> void:
	if not is_server:
		return
	config[key] = value
	if key == "team_size":
		config.mode = {1: "solo", 2: "duo"}.get(int(value), "squad")
	if key == "mode":
		config.team_size = int(Defs.rule("modes.%s.team_size" % str(value), 4))
	if key in ["teams", "team_size"]:
		# Fewer or smaller teams: whoever no longer fits goes back to "no team yet".
		var counts := {}
		for pid in players:
			var t: int = players[pid].team
			if t >= int(config.teams) or (t >= 0 and int(counts.get(t, 0)) >= team_size()):
				players[pid].team = -1
			elif t >= 0:
				counts[t] = int(counts.get(t, 0)) + 1
	_broadcast_lobby()


func team_size() -> int:
	return clampi(int(config.get("team_size", Defs.rule("modes.%s.team_size" % config.get("mode", "squad"), 4))), 1, MAX_TEAM_SIZE)''')

# ------------------------------------------------------------------ Game: bots fill the slots; results feed profiles and the stats server
f = 'src/core/game.gd'
patch(f, '''const LobbyScript := preload("res://src/ui/lobby_ui.gd")''', '''const LobbyScript := preload("res://src/ui/lobby_ui.gd")
const Outfit := preload("res://src/player/outfit.gd")
const MasterServer := preload("res://src/online/master_server.gd")

var master: Node = null      # the stats server when this process runs one (--master, or --server --stats)
var last_xp: Dictionary = {} # {xp, level_before, level_after} from the last match, for the results screen''')
patch(f, '''	if arg("name"):
		Settings.set_value("player", "name", str(arg("name")))
	if arg("server"):''', '''	if arg("name"):
		Settings.set_value("player", "name", str(arg("name")))
	if arg("master") or arg("stats"):
		master = MasterServer.new()
		master.name = "Master"
		add_child(master)
		master.start(int(arg("master_port", MasterServer.PORT)), str(arg("data", "")))
		if arg("master") and not arg("server"):
			print("[master] running (no match server in this process)")
			return
	if arg("server"):''')
patch(f, '''	if arg("mode"):
		Net.set_config("mode", str(arg("mode")))
	if arg("bots") != null:
		Net.set_config("bot_count", int(arg("bots")))
		Net.set_config("bots", int(arg("bots")) > 0)''', '''	if arg("mode"):
		Net.set_config("mode", str(arg("mode")))
	if arg("teams") != null:
		Net.set_config("teams", clampi(int(arg("teams")), 1, Net.MAX_TEAMS))
	if arg("team_size") != null:
		Net.set_config("team_size", clampi(int(arg("team_size")), 1, Net.MAX_TEAM_SIZE))
	if arg("bots") != null:
		# --bots=N: room for N bots besides the humans expected (teams grow to fit, up to 7).
		var n := int(arg("bots"))
		Net.set_config("bot_count", n)
		Net.set_config("bots", n > 0)
		if arg("teams") == null:
			var want := n + maxi(int(arg("expect_players", 1)), 1)
			Net.set_config("teams", clampi(ceili(float(want) / Net.team_size()), 2, Net.MAX_TEAMS))''')
patch(f, '''	# Bots fill to the configured count.
	Net.remove_bots()
	if Net.config.get("bots", true):
		var names := BOT_NAMES.duplicate()
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in range(names.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = names[i]
			names[i] = names[j]
			names[j] = t
		var room := int(Defs.rule("max_players", 40)) - Net.players.size()
		for i in mini(int(Net.config.get("bot_count", 20)), room):
			Net.add_bot(names[i % names.size()])''', '''	# Bots fill the team slots the humans left open (5 teams of 4 by default: 20 slots).
	Net.remove_bots()
	if Net.config.get("bots", true):
		var names := BOT_NAMES.duplicate()
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in range(names.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = names[i]
			names[i] = names[j]
			names[j] = t
		var room := Net.slot_count() - Net.humans()
		if arg("bots") != null:
			room = mini(room, int(arg("bots")))
		for i in maxi(room, 0):
			Net.add_bot(names[i % names.size()], Outfit.random_look(rng.randi()))''')
patch(f, '''func end_match_to_results(summary: Dictionary) -> void:
	## Server: called by the world when a winner is decided.
	_show_results.rpc(summary)
	_show_results(summary)''', '''func end_match_to_results(summary: Dictionary) -> void:
	## Server: called by the world when a winner is decided. Every human's row carries the XP it earned; the host
	## reports the match to the stats server.
	for r in summary.get("rows", []):
		r.xp = 0 if r.get("bot", false) else Profile.match_xp(r)
		var p: Dictionary = Net.players.get(int(r.get("pid", 0)), {})
		r.profile = str(p.get("profile", ""))
		r.platform = str(p.get("platform", "PC"))
	if master:
		master._result({"players": summary.rows.filter(func(r): return not r.get("bot", false) and str(r.profile) != "").map(func(r): return {
			"id": r.profile, "name": r.name, "platform": r.platform, "kills": r.kills, "damage": r.damage, "place": r.place, "winner": r.winner,
			"time": r.time, "xp": r.xp})})
	elif not Net.dedicated:
		Online.post_result(summary.get("rows", []))
	_show_results.rpc(summary)
	_show_results(summary)''')
patch(f, '''@rpc("authority", "call_remote", "reliable")
func _show_results(summary: Dictionary) -> void:
	_set_state("results")
	if world:
		world.show_results(summary)''', '''@rpc("authority", "call_remote", "reliable")
func _show_results(summary: Dictionary) -> void:
	_set_state("results")
	last_xp = {}
	if not Net.dedicated:
		for r in summary.get("rows", []):
			if int(r.get("pid", 0)) == Net.local_pid and not r.get("bot", false):
				r.teams = int(summary.get("teams", 0))
				last_xp = Profile.add_match(r)
				summary.me = r
				summary.me_xp = last_xp
	if world:
		world.show_results(summary)''')

# ------------------------------------------------------------------ MatchServer: damage, place, pid in the summary
f = 'src/match/match_server.gd'
patch(f, '''		rows.append({"name": s.name, "team": s.team, "kills": s.kills, "downs": s.downs, "time": int(s.alive_t), "winner": int(s.team) == winner, "bot": s.bot})''', '''		var place := 1 if int(s.team) == winner else maxi(int(s.placed), 2)
		rows.append({"pid": int(s.pid), "name": s.name, "team": s.team, "kills": s.kills, "downs": s.downs, "time": int(s.alive_t), "winner": int(s.team) == winner,
			"bot": s.bot, "damage": int(float(s.damage)), "place": place})''')
patch(f, '''	return {"winner_team": winner, "winners": names, "rows": rows, "duration": int(_t)}''', '''	return {"winner_team": winner, "winners": names, "rows": rows, "duration": int(_t), "teams": initial_teams}''')

# ------------------------------------------------------------------ World: damage dealt counts for the attacker
f = 'src/match/world.gd'
patch(f, '''func server_after_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	_after_damage(ch, res, attacker)''', '''func server_after_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	_after_damage(ch, res, attacker)


func _count_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	## Damage dealt to the other teams, for XP and the stats.
	if match_server and match_server.stats.has(attacker) and attacker != ch.eid and team_of(attacker) != ch.team:
		match_server.stats[attacker].damage = float(match_server.stats[attacker].damage) + float(res.get("damage", 0.0))''')
patch(f, '''func _after_damage(ch: Character, res: Dictionary, attacker: int) -> void:''', '''func _after_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	_count_damage(ch, res, attacker)''')

# ------------------------------------------------------------------ Character visual: the outfit replaces the hooded body
f = 'src/player/character_visual.gd'
patch(f, '''const ViewModel := preload("res://src/player/viewmodel.gd")''', '''const ViewModel := preload("res://src/player/viewmodel.gd")
const Outfit := preload("res://src/player/outfit.gd")''')
patch(f, '''		skel = _find(model, "Skeleton3D")
		anim = _find(model, "AnimationPlayer")
		_tint_clothes()''', '''		skel = _find(model, "Skeleton3D")
		anim = _find(model, "AnimationPlayer")
		_dress()''')
patch(f, '''func _tint_clothes() -> void:''', '''func _dress() -> void:
	## The player's outfit (data/cosmetics.json) in place of the hooded body: head and hands, then one mesh for
	## everything worn (two draw calls instead of the body's eight).
	var look: Dictionary = Net.players.get(ch.pid, {}).get("look", {})
	if look.is_empty():
		look = Outfit.random_look(ch.eid * 7919 + 17)
	if not Outfit.ensure():
		_tint_clothes()
		return
	for mi in _all(model, "MeshInstance3D"):
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	Outfit.dress(skel, look, Defs.RENDER_CHARACTERS, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func _tint_clothes() -> void:''')
