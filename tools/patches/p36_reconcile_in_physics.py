"""Patch: reconcile inside the physics step. Snapshots arrive during the render frame, where move_and_slide() uses
the render delta instead of the physics delta, so replayed commands moved the character the wrong distance and every
correction seeded the next one. The newest snapshot is kept and applied at the start of the next physics tick."""
p = 'A:/Python/aetherion-project/game/src/player/player_controller.gd'
s = open(p, encoding='utf-8').read()


def sub(old, new):
    global s
    assert s.count(old) == 1, (s.count(old), old[:80])
    s = s.replace(old, new)


sub('''var stats := {"corrections": 0, "replayed": 0, "acks": 0, "max_error": 0.0}
''', '''var stats := {"corrections": 0, "replayed": 0, "acks": 0, "max_error": 0.0}
var _snap_ack := -1           # newest server state waiting to be reconciled in the next physics step
var _snap_own: Dictionary = {}
''')
sub('''func reconcile(ack: int, own: Dictionary) -> void:
	stats.acks += 1''', '''func reconcile(ack: int, own: Dictionary) -> void:
	## Called when a snapshot arrives (render frame). Kept until the next physics step: replaying commands calls
	## move_and_slide(), which only uses the physics delta inside a physics frame.
	if ack >= _snap_ack:
		_snap_ack = ack
		_snap_own = own


func _reconcile_now(ack: int, own: Dictionary) -> void:
	stats.acks += 1''')
sub('''	_look(dt)
	seq += 1
	var cmd := _build_cmd()''', '''	if _snap_ack >= 0 and not world.is_server:
		var a := _snap_ack
		_snap_ack = -1
		_reconcile_now(a, _snap_own)
	_look(dt)
	seq += 1
	var cmd := _build_cmd()''')
open(p, 'w', encoding='utf-8').write(s)
print('ok')
