"""r13: network checks for the radio static. The sound trace carries world positions; a test-only server op makes the
nearest enemy bot call out next to the requester; the net test's Bravo checks it hears enemies' static and voice and
no static from its own team's radios.

    python -I tools/patches/r13_static_net.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, 'rb').read().decode('utf-8')
    crlf = '\r\n' in raw
    s = raw.replace('\r\n', '\n')
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:80])
        s = s.replace(a, b)
    if crlf:
        s = s.replace('\n', '\r\n')
    open(p, 'wb').write(s.encode('utf-8'))
    print('patched', rel)


patch('game/src/audio/sound_system.gd', [
    ('var trace: Array = []     # tests: [msec, id, "local"/"world"] of every sound started, while trace_on',
     'var trace: Array = []     # tests: [msec, id, "local"/"radio"/"world" (, position)] of every sound started, while trace_on'),
    ('\t\ttrace.append([Time.get_ticks_msec(), id, "world"])',
     '\t\ttrace.append([Time.get_ticks_msec(), id, "world", pos])'),
])

patch('game/src/match/world.gd', [
    ('''		"zone_restore":
			if match_server == null or not match_server.has_meta("zone_saved"):''',
     '''		"bot_say":
			# r13 net test: the nearest enemy bot stands 7 m from this player, holds still for 5 s and calls out; its
			# radio's static and its voice should reach this player.
			var best = null
			var bd := INF
			for b in bots.values():
				if is_instance_valid(b.ch) and b.ch.team != ch.team and b.ch.mode == Motor.GROUND:
					var d: float = b.ch.global_position.distance_to(ch.global_position)
					if d < bd:
						bd = d
						best = b
			if best == null:
				return
			best.test_idle = true
			best.ch.global_position = ch.global_position + Vector3(7.0, 0.0, 0.0)
			best.ch.velocity = Vector3.ZERO
			_static_t.erase(best.ch.eid)
			server_bot_radio(best.ch, str(cmd.get("line", "contact")), best.voice, 0)
			get_tree().create_timer(5.0).timeout.connect(func():
				if is_instance_valid(best.ch):
					best.test_idle = false)
		"zone_restore":
			if match_server == null or not match_server.has_meta("zone_saved"):'''),
])

patch('game/src/debug/autotest_net.gd', [
    ('''		# Watch for the radio flag while Alpha transmits.
		var t := 0.0
		while t < 6.0 and not _state_get().has("radio"):
			if is_instance_valid(alpha) and (alpha.flags & Character.F_RADIO) != 0:
				_radio_seen = true
			await get_tree().physics_frame
			t += 1.0 / 60.0
		_check("radio_cue_seen_by_teammate", _radio_seen or _voice_in > 0, "radio flag seen %s, %d voice packets" % [str(_radio_seen), _voice_in])''',
     '''		# Watch for the radio flag while Alpha transmits. r13: no radio static from Alpha's or Bravo's own radio (static
		# is for enemies near a transmitting radio).
		SoundSys.trace_on = true
		var tr0: int = SoundSys.trace.size()
		var mate_static := 0
		var t := 0.0
		var t_radio := -1.0
		while t < 7.5 and (t_radio < 0.0 or t < t_radio + 1.0):
			if t_radio < 0.0 and _state_get().has("radio"):
				t_radio = t
			if is_instance_valid(alpha) and (alpha.flags & Character.F_RADIO) != 0:
				_radio_seen = true
			for i in range(tr0, SoundSys.trace.size()):
				var e: Array = SoundSys.trace[i]
				if str(e[1]) == "radio_static" and e.size() > 3:
					for o in [alpha, ch]:
						if is_instance_valid(o) and (e[3] as Vector3).distance_to(o.global_position + Vector3.UP * 1.35) < 3.0:
							mate_static += 1
			tr0 = SoundSys.trace.size()
			await get_tree().physics_frame
			t += 1.0 / 60.0
		_check("radio_cue_seen_by_teammate", _radio_seen or _voice_in > 0, "radio flag seen %s, %d voice packets" % [str(_radio_seen), _voice_in])
		_check("radio_static_not_for_teammates", mate_static == 0, "radio static from Alpha's or Bravo's radio heard by Bravo: %d" % mate_static)'''),
    ('''	await _until(func(): return _state_get().has("a_done"), 40.0)
	_state_put({"b_done": true})''',
     '''	await _until(func(): return _state_get().has("a_done"), 40.0)
	await _static_from_enemy()
	_state_put({"b_done": true})


func _static_from_enemy() -> void:
	## r13: an enemy bot 7 m off calls out on its radio; Bravo hears its radio's static and its voice (server events
	## sent to this client only because it is close).
	SoundSys.trace_on = true
	var tr0: int = SoundSys.trace.size()
	world.test_cmd({"op": "bot_say", "line": "contact"})
	var got := {}
	await _until(func():
		for i in range(tr0, SoundSys.trace.size()):
			var e: Array = SoundSys.trace[i]
			if e.size() > 3 and (e[3] as Vector3).distance_to(ch.global_position) > 3.0:
				if str(e[1]) == "radio_static":
					got.static = true
				elif str(e[1]).begins_with("vox_enemy_spotted_") or str(e[1]).begins_with("botr_contact_"):
					got.voice = true
		return got.has("static") and got.has("voice"), 4.0)
	_check("radio_static_from_enemy", got.has("static") and got.has("voice"),
		"an enemy bot's callout 7 m away: its radio static heard %s, its voice heard %s" % [str(got.has("static")), str(got.has("voice"))])'''),
])
