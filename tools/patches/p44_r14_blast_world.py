"""r14: grenade blasts in world.gd (a door blown apart for everyone, what the local player feels) and the camera
shake in player_controller.gd. Idempotent."""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, 'rb').read().decode('utf-8')
    nl = '\r\n' if '\r\n' in raw else '\n'
    s = raw.replace('\r\n', '\n')
    for a, b in pairs:
        if b in s:
            continue
        assert s.count(a) == 1, (rel, s.count(a), a[:80])
        s = s.replace(a, b)
    open(p, 'wb').write(s.replace('\n', nl).encode('utf-8'))


patch('game/src/match/world.gd', [
    ('''func _door_by(did: int, is_shutter: bool):''', '''func server_door_blast(door, pos: Vector3, strength: float) -> void:
	## r14: a grenade right by a door: every panel blown out at once and the leaf gone, for everyone.
	map_door_blast.rpc(int(door.spec.id), door.is_shutter, pos, strength)
	_door_blast_local(door, pos, strength)


@rpc("authority", "call_remote", "reliable")
func map_door_blast(did: int, is_shutter: bool, pos: Vector3, strength: float) -> void:
	var d = _door_by(did, is_shutter)
	if d:
		_door_blast_local(d, pos, strength)


func _door_blast_local(d, pos: Vector3, strength: float) -> void:
	if d.destroyed:
		return
	var xf: Transform3D = d.current_transform()
	var boxes := []
	for j in d.panels().size():
		if not d.lost.has(j):
			boxes.append(d.panel_box(j))
	for j in d.panels().size():
		if not d.destroyed and not d.lost.has(j):
			d.lose_panel(j)
	if not d.destroyed:
		d.destroy()
	if effects:
		effects.door_blown(d, xf, boxes, pos, strength)


func local_blast(pos: Vector3) -> void:
	## r14: what a grenade going off does to whoever watches through this camera: hearing muffled and ringing
	## (closer and in the open is worse, a wall between halves it; it starts when the bang arrives), the view
	## shaken, and up close in the open whited out for a moment.
	if controller == null or controller.cam == null:
		return
	var ear: Vector3 = controller.cam.global_position
	var d := ear.distance_to(pos)
	if d > 45.0:
		return
	var s := clampf(1.0 - (d - 2.5) / 19.0, 0.0, 1.0)
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, ear, Defs.PHYS_WORLD)
	var open := get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if not open:
		s *= 0.45
	SoundSys.deafen(s, 2.0 + 6.5 * s, d / 343.0)
	if controller.has_method("blast_shake"):
		controller.blast_shake(clampf(1.0 - d / 40.0, 0.0, 1.0) * (1.0 if open else 0.6))
	if hud and open and s > 0.3 and local_char and local_char.mode not in [Motor.DEAD, Motor.SPECTATE]:
		hud.blast(s)


func _door_by(did: int, is_shutter: bool):'''),
])

patch('game/src/player/player_controller.gd', [
    ('''func _on_motion_event(kind: String, value: float) -> void:''', '''func blast_shake(strength: float) -> void:
	## r14: a grenade going off nearby shakes the view (stronger closer); a sharp jolt, then the shake dies away.
	if strength <= 0.0:
		return
	_hit_shake = minf(_hit_shake + strength * 2.6, 3.0)
	_kicks.append([Time.get_ticks_msec() / 1000.0, Vector3(-0.06 * strength, randf_range(-0.04, 0.04) * strength, randf_range(-0.05, 0.05) * strength)])
	if _kicks.size() > 6:
		_kicks.pop_front()


func _on_motion_event(kind: String, value: float) -> void:'''),
])
print('applied')
