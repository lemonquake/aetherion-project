"""r24: a Deathmatch round restart brings the players back two per tick (humans first) instead of all 21 in one tick
(79 ms in one frame, then two slow frames while they were first drawn: the hitch when a round was won)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p24_util import patch

G = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'src')

patch(os.path.join(G, 'match', 'match_server.gd'), [
    ('''var _hurt_by := {}            # (r24) victim eid -> {attacker pid: true}: who earns an assist when it dies
''', '''var _hurt_by := {}            # (r24) victim eid -> {attacker pid: true}: who earns an assist when it dies
var _spawn_queue: Array = []  # (r24) pids still to bring back at a round start, a couple per tick
var _spawn_us := []           # (r24) microseconds each of this round's respawns took (the match log's [roundtime])
const SPAWNS_PER_TICK := 2
'''),
    ('''	var us2 := Time.get_ticks_usec()
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
''', '''	# Humans first (their camera comes back at once), then the bots, a couple per tick (the start hold covers it).
	_spawn_queue.clear()
	_spawn_us.clear()
	for human in [true, false]:
		for pid in Net.players:
			var p: Dictionary = Net.players[pid]
			if bool(p.bot) == human or (not p.bot and not p.connected):
				continue
			if _pid_stats.has(pid):
				_pid_stats[pid].placed = 0
			_spawn_queue.append(pid)
	phase = "playing"
	_spawn_some()
	_broadcast()
	log_event("round %d started; scores %s" % [round_number, str(team_score)])
	log_event("[roundtime] remove %.1f ms, field %.1f ms" % [(us1 - us0) / 1000.0, (Time.get_ticks_usec() - us1) / 1000.0])


func _spawn_some() -> void:
	for i in SPAWNS_PER_TICK:
		if _spawn_queue.is_empty():
			break
		var pid: int = _spawn_queue.pop_front()
		if not Net.players.has(pid):
			continue
		var a := Time.get_ticks_usec()
		_respawn(pid)
		_spawn_us.append(Time.get_ticks_usec() - a)
	if _spawn_queue.is_empty() and not _spawn_us.is_empty():
		_spawn_us.sort()
		log_event("[roundtime] %d respawns, slowest %.1f ms, median %.1f ms" % [_spawn_us.size(), _spawn_us[-1] / 1000.0, _spawn_us[_spawn_us.size() / 2] / 1000.0])
		_spawn_us.clear()
'''),
    ('''		"playing":
			_zone_tick(dt)
			_check_end()
''', '''		"playing":
			_zone_tick(dt)
			if not _spawn_queue.is_empty():
				_spawn_some()   # a round is still bringing its players back: nobody can have won it yet
			else:
				_check_end()
'''),
])
