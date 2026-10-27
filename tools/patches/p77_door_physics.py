"""Door physics wiring: Use opens toward where the player faces, characters shove open leaves every tick, the
server streams free swings to clients, and a leaf swung shut latches with the closing sound."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from patchlib import Patch

i = Patch('game/src/match/interaction.gd')
i.rep('''			var what: String = d.server_use(ch.global_position)''',
      '''			var what: String = d.server_use(ch.global_position, -Basis(Vector3.UP, float(cmd.get("yaw", ch.yaw))).z)''')
i.save()

w = Patch('game/src/match/world.gd')
w.rep('''		"close":
			pass
		"locked":''', '''		"close":
			pass
		"latched":
			server_sound("door_close", door.center(), 0.0, -1)
		"locked":''')
w.rep('''@rpc("authority", "call_remote", "reliable")
func map_door_ev(did: int, is_shutter: bool, angle: float, target: float, locked: bool, what: String) -> void:''',
      '''func map_door_swing(door) -> void:
	## Server: a door swinging loose after a push; clients follow its angle and swing speed (about 10 a second).
	_map_door_swing.rpc(int(door.spec.id), door.angle, door.omega)


@rpc("authority", "call_remote", "unreliable_ordered")
func _map_door_swing(did: int, angle: float, omega: float) -> void:
	if map and did >= 0 and did < map.dyn.doors.size():
		var d = map.dyn.doors[did].get("node")
		if d:
			d.set_swing(angle, omega)


@rpc("authority", "call_remote", "reliable")
func map_door_ev(did: int, is_shutter: bool, angle: float, target: float, locked: bool, what: String) -> void:''')
w.save()

d = Patch('game/src/world/dynamics.gd')
d.rep('''func tick(dt: float) -> void:
	for i in range(_moving_doors.size() - 1, -1, -1):''', '''var _door_cells := {}      # 4 m cell -> [door node], for characters pushing doors
var _door_cells_n := 0


func _push_doors() -> void:
	## Everyone walking into an open door shoves it aside (server and clients alike; the server's swing is what
	## every client converges to).
	if world == null or doors.is_empty():
		return
	if _door_cells_n != doors.size():
		_door_cells.clear()
		for dd in doors:
			var dn = dd.get("node")
			if dn == null:
				continue
			var o: Vector3 = (dd.xf as Transform3D).origin
			var key := Vector2i(floori(o.x / 4.0), floori(o.z / 4.0))
			if not _door_cells.has(key):
				_door_cells[key] = []
			_door_cells[key].append(dn)
		_door_cells_n = doors.size()
	var radius := Defs.move("radius")
	for ch in world.characters.values():
		if ch.mode != Motor.GROUND and ch.mode != Motor.DOWNED:
			continue
		var p: Vector3 = ch.global_position
		var v: Vector3 = ch.velocity
		var cell := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				for dn in _door_cells.get(cell + Vector2i(dx, dz), []):
					dn.push(p, v, radius)


func tick(dt: float) -> void:
	_push_doors()
	for i in range(_moving_doors.size() - 1, -1, -1):''')
d.save()
