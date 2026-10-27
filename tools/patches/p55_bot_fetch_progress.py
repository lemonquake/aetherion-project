"""Bot fetch fixes (loot run 2026-10-26, traced match): fetch only loot the bot can see and reach (no more than a
step up or down), and give up after 4 s without getting closer instead of 40 s.

    python -I tools/patches/p55_bot_fetch_progress.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, 'game', 'src', 'ai', 'bot_brain.gd')
raw = open(p, 'rb').read().decode()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')


def rep(a, b):
    global s
    assert s.count(a) == 1, a[:80]
    s = s.replace(a, b)


rep('''		var v := LootSense.value(ch, it.entry)
		if v < min_v:
			continue
		var dd := p.distance_to(here) / v
		if dd < bd:
			bd = dd
			best = {"kind": "item", "id": id, "p": p}''', '''		var v := LootSense.value(ch, it.entry)
		if v < min_v or absf(p.y - here.y) > 1.2:
			continue
		var dd := p.distance_to(here) / v
		if dd < bd and _in_sight(p + Vector3.UP * 0.1):
			bd = dd
			best = {"kind": "item", "id": id, "p": p}''')
rep('''		var p2: Vector3 = c.pos
		var dist := p2.distance_to(here)
		if dist > reach:
			continue
		var dd2 := dist / 1.5
		if dd2 < bd:''', '''		var p2: Vector3 = c.pos
		var dist := p2.distance_to(here)
		if dist > reach or absf(p2.y - here.y) > 1.8:
			continue
		var dd2 := dist / 1.5
		if dd2 < bd and _in_sight(p2):''')
rep('''	_fetch = best
	_fetch.t = 0.0''', '''	_fetch = best
	_fetch.t = 0.0
	_fetch.best = INF
	_fetch.still = 0.0''')
rep('''	if gone or float(_fetch.t) > 40.0:''', '''	var d_now := Vector2(p.x - ch.global_position.x, p.z - ch.global_position.z).length()
	if d_now < float(_fetch.best) - 0.4:
		_fetch.best = d_now
		_fetch.still = 0.0
	else:
		_fetch.still = float(_fetch.still) + dt
	if gone or float(_fetch.t) > 25.0 or float(_fetch.still) > 4.0:''')
rep('''func _fetch_step(cmd: Dictionary, dt: float) -> void:''', '''func _in_sight(p: Vector3) -> bool:
	## A clear line from the bot's eyes (walls, props and glass block it; the loot itself does not).
	var q := PhysicsRayQueryParameters3D.create(ch.eye_position(), p, Defs.SIGHT_MASK)
	q.exclude = [ch.get_rid()]
	var r := world.get_world_3d().direct_space_state.intersect_ray(q)
	return r.is_empty() or (r.position as Vector3).distance_to(p) < 0.6


func _fetch_step(cmd: Dictionary, dt: float) -> void:''')
open(p, 'wb').write((s.replace('\n', '\r\n') if crlf else s).encode())
print('ok')
