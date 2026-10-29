extends RefCounted
## Climbing the ladders up house fronts to the roof decks. Part of the shared movement simulation (Motor), like
## vaulting: a pure function of the character's state, the command and the map's ladder list (built from the map
## seed, the same on every machine), so prediction and replays agree with the server.
##
## Walk into a ladder facing the wall and you take hold of it. Forward climbs (or descends while looking down, or
## while facing away from the wall), back descends, Jump lets go and kicks you off the wall. At the top you step forward on to the roof; at the foot,
## backing off the bottom rung puts you on the ground. Walking off a roof edge into a ladder catches you on it.
## Bots do not use ladders, except to climb out of a canal (the bot brain sets the "ladder_ok" meta while it does).

const REACH_SIDE := 0.36   # metres either side of the ladder's centre line
const REACH_OUT := 0.5     # how far from the climbing line (out from the wall) you can be and still grab it


static func find(ch) -> Dictionary:
	var w = ch.world
	if w == null or w.map == null or not w.map.has_method("ladders_near"):
		return {}
	if Net.is_bot(ch.pid) and not bool(ch.get_meta("ladder_ok", false)):
		return {}
	var p: Vector3 = ch.global_position
	for ld in w.map.ladders_near(p):
		var b: Vector3 = ld.base
		var n: Vector3 = ld.n
		var rel := p - b
		var off := rel.dot(n)
		var lat := rel - n * off
		lat.y = 0.0
		if lat.length() > REACH_SIDE or off < -0.3 or off > REACH_OUT:
			continue
		if p.y < b.y - 0.35 or p.y > float(ld.top_y) + 0.35:
			continue
		return ld
	return {}


static func wants(ch, cmd: Dictionary, ld: Dictionary) -> bool:
	if ld.is_empty():
		return false
	var n: Vector3 = ld.n
	var fwd := -Basis(Vector3.UP, ch.yaw).z
	var into := fwd.dot(-n)
	var my := float(cmd.get("my", 0.0))
	var p: Vector3 = ch.global_position
	var top := float(ld.top_y)
	# Standing on the roof at the top of the ladder: only take hold when stepping back over the edge.
	if p.y > top - 0.15 and ch.is_on_floor():
		return false
	if not ch.is_on_floor():
		return p.y > (ld.base as Vector3).y + 0.15
	return into > 0.45 and my > 0.3


static func step(ch, cmd: Dictionary, dt: float, ld: Dictionary) -> void:
	var btn := int(cmd.get("btn", 0))
	var n: Vector3 = ld.n
	var p: Vector3 = ch.global_position
	var top := float(ld.top_y)
	ch.sprinting = false
	if (btn & Motor.B_JUMP) != 0 and (ch.prev_buttons & Motor.B_JUMP) == 0:
		# Let go and push off the wall.
		ch.velocity = n * 2.6 + Vector3.UP * 1.2
		ch.jump_cooldown = 0.45
		ch.move_body(dt, true)
		return
	if ch.crouching and ch.can_stand():
		ch.crouching = false
	ch.crouch = move_toward(ch.crouch, 0.0, dt * 5.0)
	ch.apply_height()
	var my := float(cmd.get("my", 0.0))
	var look_down: bool = ch.pitch < -0.55
	var facing_out := (-Basis(Vector3.UP, ch.yaw).z).dot(-n) < -0.2
	var climb := my * (-1.0 if look_down or facing_out else 1.0) * Defs.move("ladder_speed")
	if p.y >= top + 0.04 and climb > 0.0:
		# Over the top: step forward on to the roof.
		ch.velocity = -n * 2.4 + Vector3.UP * 0.6
		ch.move_body(dt, true)
		return
	var rel := p - (ld.base as Vector3)
	var off := rel.dot(n)
	var lat := rel - n * off
	lat.y = 0.0
	var v := Vector3.UP * climb - lat * 8.0 - n * off * 6.0
	if p.y > top + 0.3:
		v.y = minf(v.y, 0.0)
	ch.velocity = v
	var y0 := p.y
	ch.move_body(dt, true)
	# A rung every 30 cm: a knock you can hear.
	if floori(y0 / 0.3) != floori(ch.global_position.y / 0.3):
		ch.emit_motion_event("ladder", absf(climb))
