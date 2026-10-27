"""Patch: commands are never silently dropped. A per-player budget (one command per server tick, banking up to 20)
lets inputs that arrived in a burst be caught up while a client still cannot move faster than real time; the queue
only overflows after half a second of backlog. Mode changes carry the server's velocity (a team jump's initial
throw), so the client predicts the fall from the same start."""
G = 'A:/Python/aetherion-project/game/'


def patch(path, pairs):
    s = open(G + path, encoding='utf-8').read()
    for old, new in pairs:
        assert s.count(old) == 1, (path, s.count(old), old[:90])
        s = s.replace(old, new)
    open(G + path, 'w', encoding='utf-8').write(s)
    print('patched', path)


patch('src/match/world.gd', [
    ('''var _starved: Dictionary = {}    # eid -> seconds without a command
''', '''var _starved: Dictionary = {}    # eid -> seconds without a command
var _budget: Dictionary = {}     # eid -> commands that may still be simulated (one per tick, banks up to 20)
'''),
    ('''	# A client cannot bank commands to move faster than real time.
	while q.size() > 12:
		q.pop_front()''', '''	# Half a second of backlog is the most we keep; beyond that the client is far behind (or cheating).
	while q.size() > 30:
		q.pop_front()'''),
    ('''		var q: Array = _queues[eid]
		# Catch up a backlog a little faster than real time (never more than 3 steps a tick).
		var n := 1 if q.size() <= 2 else (2 if q.size() <= 6 else 3)''', '''		var q: Array = _queues[eid]
		# Catch up a backlog a little faster than real time (never more than 3 steps a tick), paid from a budget that
		# grows by one command per tick: bursts are caught up, a client cannot run faster than real time.
		_budget[eid] = minf(float(_budget.get(eid, 0.0)) + 1.0, 20.0)
		var n := 1 if q.size() <= 2 else (2 if q.size() <= 6 else 3)'''),
    ('''			for i in mini(n, q.size()):
				var c: Dictionary = q.pop_front()
				_server_apply(ch, c, dt, tick, false)
				_acked[eid] = int(c.seq)''', '''			for i in mini(n, q.size()):
				if float(_budget[eid]) < 1.0:
					break
				_budget[eid] = float(_budget[eid]) - 1.0
				var c: Dictionary = q.pop_front()
				_server_apply(ch, c, dt, tick, false)
				_acked[eid] = int(c.seq)'''),
    ('''	ch.mode = mode
	_char_mode.rpc(ch.eid, mode, ch.global_position)''', '''	ch.mode = mode
	_char_mode.rpc(ch.eid, mode, ch.global_position, ch.velocity)'''),
    ('''func _char_mode(eid: int, mode: int, pos: Vector3) -> void:''', '''func _char_mode(eid: int, mode: int, pos: Vector3, vel: Vector3 = Vector3.ZERO) -> void:'''),
    ('''		ch.global_position = pos
		ch.velocity = Vector3.ZERO
		if controller:
			controller.on_mode_forced(mode)''', '''		ch.global_position = pos
		ch.velocity = vel
		if controller:
			controller.on_mode_forced(mode)'''),
])
