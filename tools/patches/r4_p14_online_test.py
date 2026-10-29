"""r4: test hooks for the online flow (--profile, --stats_server, --end_after, --quit_after_results) and the outfit draw
check split from the gun."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
patch('src/online/profile.gd', '''const PATH := "user://profile.json"''', '''const PATH := "user://profile.json"
## --profile=<name> keeps a separate profile (several game processes on one PC in the tests).
var path := PATH''')
patch('src/online/profile.gd', '''func _ready() -> void:
	load_profile()''', '''func _ready() -> void:
	if Game.arg("profile"):
		path = "user://profile_%s.json" % str(Game.arg("profile")).validate_filename()
	load_profile()''')
patch('src/online/profile.gd', '''	var f := FileAccess.open(PATH, FileAccess.READ)''', '''	var f := FileAccess.open(path, FileAccess.READ)''')
patch('src/online/profile.gd', '''	var f := FileAccess.open(PATH, FileAccess.WRITE)''', '''	var f := FileAccess.open(path, FileAccess.WRITE)''')
patch('src/online/online.gd', '''func server_address() -> String:
	var s := str(Settings.get_value("online", "server")).strip_edges()''', '''func server_address() -> String:
	var s := str(Game.arg("stats_server", Settings.get_value("online", "server"))).strip_edges()''')
patch('src/online/online.gd', '''	if DisplayServer.get_name() == "headless" and not Game.arg("autotest"):
		return''', '''	if DisplayServer.get_name() == "headless" and not Game.arg("autotest") and not Game.arg("stats_server"):
		return''')
patch('src/core/game.gd', '''func _begin_match() -> void:
	_load_timer = -1.0
	_set_state("match")
	_match_started.rpc()
	world.server_start_match()''', '''func _begin_match() -> void:
	_load_timer = -1.0
	_set_state("match")
	_match_started.rpc()
	world.server_start_match()
	if arg("end_after"):
		# Tests: end the match after this many seconds with whoever is standing.
		get_tree().create_timer(float(arg("end_after"))).timeout.connect(func():
			if world and world.match_server and state == "match":
				world.match_server.force_end())''')
patch('src/core/game.gd', '''	if world:
		world.show_results(summary)''', '''	if world:
		world.show_results(summary)
	if arg("quit_after_results"):
		print("[game] results: %s" % JSON.stringify(summary.get("me", {})))
		get_tree().create_timer(4.0).timeout.connect(func(): get_tree().quit())''')
patch('src/match/match_server.gd', '''func _summary(winner: int) -> Dictionary:''', '''func force_end() -> void:
	## Tests (--end_after): finish now; the team with most standing wins.
	if phase == "ended":
		return
	phase = "ended"
	var count := {}
	for c in world.characters.values():
		if c.mode in [Motor.GROUND, Motor.FREEFALL, Motor.CHUTE, Motor.PLANE]:
			count[c.team] = int(count.get(c.team, 0)) + 1
	var winner := -1
	for t in count:
		if winner < 0 or int(count[t]) > int(count[winner]):
			winner = t
	log_event("match ended early (test): winner team %d after %.0f s" % [winner, _t])
	Game.end_match_to_results(_summary(winner))


func _summary(winner: int) -> Dictionary:''')
patch('src/debug/autotest_r4.gd', '''		var surfaces := 0
		for mi in _meshes(o.visual):
			if mi.visible and mi.mesh:
				surfaces += mi.mesh.get_surface_count()
		surf_max = maxi(surf_max, surfaces)''', '''		var surfaces := 0
		for mi in _meshes(o.visual):
			# The body only: the gun and its attachments are drawn the same as before.
			if mi.visible and mi.mesh and not o.visual.weapon_node.is_ancestor_of(mi):
				surfaces += mi.mesh.get_surface_count()
		surf_max = maxi(surf_max, surfaces)''')
patch('src/debug/autotest_r4.gd', '''	t._check("outfits_draws", surf_max <= 3, "at most %d mesh surfaces per character (outfit, head, weapon); the hooded body alone had 8" % surf_max)''', '''	t._check("outfits_draws", surf_max <= 2, "at most %d mesh surfaces per character body (outfit and head; the gun as before); the hooded body had 8" % surf_max)''')
