"""r24: how long each part of a Deathmatch round restart takes, in the match log (to find the restart hitch)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p24_util import patch

G = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'src')

patch(os.path.join(G, 'match', 'match_server.gd'), [
    ('''func _start_next_round() -> void:
	# Keep match totals while replacing every life, including the winning survivors.
	for ch in world.characters.values():
''', '''func _start_next_round() -> void:
	# Keep match totals while replacing every life, including the winning survivors.
	var us0 := Time.get_ticks_usec()
	for ch in world.characters.values():
'''),
    ('''	var rng := RandomNumberGenerator.new()
	rng.seed = Game.match_seed + round_number * 31
	_reset_dm_field(rng)
	for pid in Net.players:
		var p: Dictionary = Net.players[pid]
		if not p.bot and not p.connected:
			continue
		if _pid_stats.has(pid):
			_pid_stats[pid].placed = 0
		_respawn(pid)
	phase = "playing"
	_broadcast()
	log_event("round %d started; scores %s" % [round_number, str(team_score)])
''', '''	var us1 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.match_seed + round_number * 31
	_reset_dm_field(rng)
	var us2 := Time.get_ticks_usec()
	var spawn_us := []
	for pid in Net.players:
		var p: Dictionary = Net.players[pid]
		if not p.bot and not p.connected:
			continue
		if _pid_stats.has(pid):
			_pid_stats[pid].placed = 0
		var a := Time.get_ticks_usec()
		_respawn(pid)
		spawn_us.append(Time.get_ticks_usec() - a)
	phase = "playing"
	_broadcast()
	log_event("round %d started; scores %s" % [round_number, str(team_score)])
	spawn_us.sort()
	log_event("[roundtime] remove %.1f ms, field %.1f ms, %d respawns %.1f ms (slowest %.1f ms, median %.1f ms)" % [(us1 - us0) / 1000.0,
		(us2 - us1) / 1000.0, spawn_us.size(), (Time.get_ticks_usec() - us2) / 1000.0, spawn_us[-1] / 1000.0 if not spawn_us.is_empty() else 0.0,
		spawn_us[spawn_us.size() / 2] / 1000.0 if not spawn_us.is_empty() else 0.0])
'''),
])
