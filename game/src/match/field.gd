class_name Field
## The forcefield at the edge of the safe area (it replaced the damaging haze in r12). It does no damage to anyone it
## can move: they are pushed toward the centre, a little faster than its edge moves, so a closing field herds people
## in. Someone it presses against a wall, or who is caught on something while it passes over them, is squeezed:
## (r17) heavy damage that grows the longer they stay pinned and kills in about two seconds (crush_dps; it was an
## instant kill, and testers in Malasugue Mall saw players stuck on walls survive it). The push is part of the shared
## movement simulation (Motor), so the owner's prediction, replays and bots agree with the server; the squeeze is
## decided by the server from what the push achieved (Motor sets field_pin).
##
## The field is live once the first circle starts closing and from the second circle on (when the haze used to hurt).

const MatchServer := preload("res://src/match/match_server.gd")

const SPRING := 4.0       # extra inward speed per metre inside the field (m/s per m)
const MARGIN := 0.6       # inward speed above the edge's own speed (m/s)
const MAX_PUSH := 9.0     # cap on the push (m/s)
const CRUSH_DEPTH := 0.55 # metres the field must have passed over the body before it can crush
const CRUSH_PIN_S := 0.2  # seconds pinned that deep before the squeeze starts to hurt
const CRUSH_DPS := 30.0   # damage per second when the squeeze starts...
const CRUSH_RAMP := 30.0  # ...and how much it grows per second pinned (100 health lasts about 2 s)
const STUCK_DEPTH := 2.6  # this deep, being held back by other people counts as pinned too (a crowd against a wall)
const TOUCH := 0.05       # the push starts this far outside the edge (no flicker on the line)

static var legacy_haze := false   # tests: draw the old haze wall instead (blind A/B captures)
static var test_only: Array = []  # tests: when not empty, only these characters (eids) feel the field


static func live(z: Dictionary) -> bool:
	return not z.is_empty() and (int(z.get("i", -1)) > 0 or str(z.get("state", "")) == "shrink"
		or (int(z.get("i", -1)) >= 0 and str(z.get("state", "")) == "hold"))


static func at(world, pos: Vector3, tick: float) -> Dictionary:
	## {on, pen, n, v, c, r}: inside the field (on), how deep (pen, metres past the edge; negative inside the safe
	## area), the way in (n, horizontal unit vector), how fast the edge is closing on this spot (v, m/s), the centre
	## and radius. {} with on = false when there is no live field.
	var out := {"on": false, "pen": -INF, "n": Vector3.ZERO, "v": 0.0, "c": Vector2.ZERO, "r": INF}
	if world == null or not ("match_info" in world):
		return out
	var z: Dictionary = world.match_info.get("zone", {})
	if not live(z):
		return out
	var circ = MatchServer.circle_at(z, tick)
	var c: Vector2 = circ[0]
	var r := float(circ[1])
	var p2 := Vector2(pos.x, pos.z)
	var d := p2.distance_to(c)
	out.c = c
	out.r = r
	out.pen = d - r
	var dirv := c - p2
	out.n = Vector3(dirv.x, 0.0, dirv.y) / d if d > 0.01 else Vector3.ZERO
	if str(z.get("state", "")) == "shrink":
		# How fast the edge comes at this spot: the change of depth over the next quarter second.
		var later = MatchServer.circle_at(z, tick + Defs.TICK_RATE * 0.25)
		var pen2: float = p2.distance_to(later[0]) - float(later[1])
		out.v = maxf((pen2 - float(out.pen)) / 0.25, 0.0)
	out.on = float(out.pen) > -TOUCH
	return out


static func for_cmd(ch, cmd: Dictionary) -> Dictionary:
	## The field for one movement step. The server holds a client's claimed tick near its own, so an old tick
	## cannot be used to dodge the field.
	if not test_only.is_empty() and not (ch.eid in test_only):
		return {"on": false, "pen": -INF, "n": Vector3.ZERO, "v": 0.0, "c": Vector2.ZERO, "r": INF}
	var tick := float(cmd.get("tick", Net.tick))
	if ch.world and ch.world.is_server:
		tick = clampf(tick, float(Net.tick - 20), float(Net.tick + 20))
	return at(ch.world, ch.global_position, tick)


static func crush_dps(pin_s: float) -> float:
	return CRUSH_DPS + CRUSH_RAMP * maxf(pin_s - CRUSH_PIN_S, 0.0)


static func push_speed(fi: Dictionary) -> float:
	return minf(float(fi.v) + MARGIN + SPRING * maxf(float(fi.pen), 0.0), MAX_PUSH)


static func apply(fi: Dictionary, v: Vector3) -> Vector3:
	## The velocity inside the field: nothing outward survives, and the inward part is at least the push.
	if not bool(fi.get("on", false)):
		return v
	var n: Vector3 = fi.n
	if n == Vector3.ZERO:
		return v
	var hv := Vector3(v.x, 0.0, v.z)
	var outward := hv.dot(-n)
	if outward > 0.0:
		hv += n * outward
	var want := push_speed(fi)
	var inward := hv.dot(n)
	if inward < want:
		hv += n * (want - inward)
	return Vector3(hv.x, v.y, hv.z)


static func note_progress(ch, fi: Dictionary, before: Vector3, dt: float) -> void:
	## After the step: did the push carry the body in? Deep in the field and held in place (a wall, a fence, a
	## corner; another person only once the field has squeezed everyone into the last few metres, or the body is
	## deep in it) builds up the pin the server squeezes on.
	if not bool(fi.get("on", false)) or float(fi.pen) < CRUSH_DEPTH:
		ch.field_pin = maxf(ch.field_pin - dt * 3.0, 0.0)
		return
	var n: Vector3 = fi.n
	var moved = (ch.global_position - before).dot(n)
	var want := push_speed(fi) * dt
	if moved >= want * 0.35:
		ch.field_pin = maxf(ch.field_pin - dt * 3.0, 0.0)
		return
	if float(fi.r) > 4.0 and float(fi.pen) < STUCK_DEPTH and ch.get_slide_collision_count() > 0:
		# Held back only by other people: they are not a wall (they get out of the way or are pushed too). (r17) Touching
		# a wall as well is pinned: before, any person in the pile spared everyone in it, so a crowd pressed against a
		# wall was never squeezed.
		var only_people := true
		for i in ch.get_slide_collision_count():
			if not (ch.get_slide_collision(i).get_collider() is CharacterBody3D):
				only_people = false
				break
		if only_people:
			return
	ch.field_pin += dt
