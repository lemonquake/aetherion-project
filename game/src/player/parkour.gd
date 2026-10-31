class_name Parkour
## Parkour moves, part of the shared movement simulation (Motor) like vaulting: pure functions of the character's
## state, the command and the collision world, so the server, the owner's prediction and replays agree.
##
## Researched from real parkour (cat leap, climb-up, wall run, roll, slide) and the games built on it (r12 notes in
## work/lemondev/r12/PARKOUR.md):
## - Ledge grab (cat leap): in the air, moving forward at a wall whose top is within reach of the hands, the hands
##   catch the edge and the body hangs against the wall. Forward or Jump pulls up: on to the top, or over a thin wall
##   to the far side when there is ground to drop to. Back or Crouch lets go; left/right shimmy along the edge.
## - Wall run-up: jumping at a wall at a sprint (or reaching it early in a sprint jump) runs a step up it, about 1.5x
##   the height of a plain jump, which brings higher edges within reach.
## - Slide: Crouch at a sprint drops into a slide that keeps the speed for most of a second.
## - Landing roll: holding Crouch as you land from a drop rolls over the shoulder: less fall damage, momentum kept.
## - Haul-out: in water too deep to jump from, pushing into a wall (or Jump) catches its top when it is within reach
##   of the arms above the surface - a canal's coping from the bed - and the usual hang and climb-up follow.
## Bots only grab ledges while their brain sets the "climb_ok" meta (they would otherwise end up on walls by chance).

const PK_WALLRUN := 1      # the run-up was used on this jump
const PK_SPRINT_JUMP := 2  # this jump started at a sprint (a wall reached early still gives a run-up)
const PK_CLIMB := 4        # the vault in progress is a climb up from a ledge (hands on the edge)

const HAND_MIN := 0.95     # an edge this far above the feet (or higher) is caught by the hands, not cleared
const HAND_MAX := 1.65     # and no higher than this (arms up, at the moment the body meets the wall)
const GRAB_REACH := 0.45   # the wall within this of the capsule surface
const HANG_DROP := 1.95    # feet below the edge while hanging at full stretch
const HANG_OFF := 0.05     # body clear of the wall face
const OVER_MAX_DROP := 3.6 # climbing over a wall: the far side no lower than this below its top
const THIN := 0.7          # a top shallower than this can be climbed over
const WATER_REACH := 1.0   # in water: the arms reach this much higher than HAND_MAX (the surface carries the body, a kick off the bed)

static var water_grab_off := false   # tests: the 0.12 behaviour (no haul-out) for a baseline


static func _m(k: String) -> float:
	return Defs.move(k)


static func can_grab(ch) -> bool:
	if ch.held_prop_id >= 0 or ch.pk_cd > 0.0 or ch.mode != Motor.GROUND:
		return false
	if Net.is_bot(ch.pid) and not bool(ch.get_meta("climb_ok", false)):
		return false
	return true


# ------------------------------------------------------------------ ledges

static func find_ledge(ch, p: Vector3, fwd: Vector3, hand_max: float = HAND_MAX) -> Dictionary:
	## {edge (point on the face at the top), n (face normal toward us), top (y), hang (feet while hanging)} or {}.
	## hand_max: how high above the feet the hands reach (higher from the water).
	if not ch.is_inside_tree():
		return {}
	var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	var r := _m("radius")
	var ex := [ch.get_rid()]
	# 1. A wall face in front, from the waist to above the head.
	var face := INF
	var n := Vector3.ZERO
	for hh in [HAND_MIN - 0.2, 1.25, hand_max - 0.05, hand_max + 0.25]:
		var a: Vector3 = p + Vector3.UP * hh
		var hit := _ray(space, a, a + fwd * (r + GRAB_REACH), ex)
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.5:
			continue
		var hn := Vector3((hit.normal as Vector3).x, 0.0, (hit.normal as Vector3).z).normalized()
		var d := (Vector3(hit.position.x, p.y, hit.position.z) - p).dot(-hn)
		if d < face:
			face = d
			n = hn
	if face == INF or n.dot(fwd) > -0.55:
		return {}
	var into := -n
	# 2. The top, straight down just inside the face. A ray starting inside a taller wall finds nothing (no edge).
	var probe := p + into * (face + 0.1)
	var down := _ray(space, Vector3(probe.x, p.y + hand_max + 0.5, probe.z), Vector3(probe.x, p.y + HAND_MIN - 0.15, probe.z), ex)
	if down.is_empty() or (down.normal as Vector3).y < 0.7:
		return {}
	var top: float = (down.position as Vector3).y
	var rel := top - p.y
	if rel < HAND_MIN or rel > hand_max:
		return {}
	# 3. Nothing right above the edge (a real top, not a beam under a lintel or a shelf under a ceiling).
	for up in [0.12, 0.45]:
		var a2 := Vector3(p.x, top + up, p.z)
		if not _ray(space, a2, a2 + into * (face + 0.3), ex).is_empty():
			return {}
	var edge := Vector3(p.x, top, p.z) + into * face
	var hang := edge + n * (r + HANG_OFF)
	# Feet at full stretch, or on whatever is below (a low wall is held standing).
	var floor_hit := _ray(space, Vector3(hang.x, top - 0.3, hang.z), Vector3(hang.x, top - HANG_DROP - 0.05, hang.z), ex)
	hang.y = top - HANG_DROP
	if not floor_hit.is_empty():
		hang.y = (floor_hit.position as Vector3).y + 0.02
	if not _fits(ch, space, hang, minf(_m("stand_height") - 0.08, top - hang.y + 0.15)):
		return {}
	return {"edge": edge, "n": n, "top": top, "hang": hang}


enum { NOTHING, KICKED, GRABBED }


static func air_step(ch, cmd: Dictionary, dt: float, v: Vector3) -> int:
	## In the air: the wall run-up kick (KICKED: ch.velocity changed) and the ledge grab (GRABBED: now hanging).
	var btn := int(cmd.get("btn", 0))
	var my := float(cmd.get("my", 0.0))
	if my < 0.3 or (btn & Motor.B_CROUCH) != 0 or not can_grab(ch) or v.y < -7.5:
		return NOTHING
	var fwd: Vector3 = -Basis(Vector3.UP, ch.yaw).z
	var hv := Vector3(v.x, 0.0, v.z)
	if hv.dot(fwd) < -0.5:
		return NOTHING
	var p: Vector3 = ch.global_position
	# Reaching a wall early in a sprint jump: the feet take a step up it.
	if (ch.pk_bits & PK_SPRINT_JUMP) != 0 and (ch.pk_bits & PK_WALLRUN) == 0 and ch.air_t < 0.4 and v.y > -1.0 \
			and _wall_ahead(ch, p, fwd, 0.25):
		ch.pk_bits |= PK_WALLRUN
		ch.velocity = Vector3(v.x * 0.25, maxf(v.y, _m("wallrun_up_speed") - 0.6), v.z * 0.25)
		ch.emit_motion_event("wallrun", 0.0)
		return KICKED
	var L := find_ledge(ch, p, fwd)
	if L.is_empty():
		return NOTHING
	_grab(ch, L, p)
	return GRABBED


static func water_grab(ch, cmd: Dictionary, water: float) -> bool:
	## In water too deep to jump from, facing a wall: Jump, or pushing forward into it, catches its top when the arms
	## reach it from the water (HAND_MAX + up to WATER_REACH above the feet). True: now hanging.
	var btn := int(cmd.get("btn", 0))
	var pressed = btn & ~ch.prev_buttons
	if water_grab_off or float(cmd.get("my", 0.0)) < 0.3 or not can_grab(ch):
		return false
	if (pressed & Motor.B_JUMP) == 0 and not ch.is_on_wall():
		return false
	var p: Vector3 = ch.global_position
	var L := find_ledge(ch, p, -Basis(Vector3.UP, ch.yaw).z, HAND_MAX + minf(water, WATER_REACH))
	if L.is_empty():
		return false
	_grab(ch, L, p)
	return true


static func _grab(ch, L: Dictionary, p: Vector3) -> void:
	ch.jump_buf = -1.0
	ch.ledge_t = 0.0
	ch.ledge_p = L.edge
	ch.ledge_n = L.n
	ch.ledge_y = (L.hang as Vector3).y
	ch.velocity = Vector3.ZERO
	ch.crouching = false
	ch.slide_t = -1.0
	ch.emit_motion_event("ledge_grab", float(L.top) - p.y)


static func hang_spot(ch) -> Vector3:
	var s: Vector3 = ch.ledge_p + ch.ledge_n * (_m("radius") + HANG_OFF)
	return Vector3(s.x, ch.ledge_y, s.z)


static func hang_step(ch, cmd: Dictionary, dt: float) -> bool:
	## Hanging: pull up, let go or shimmy. False when the hands let go this step (normal falling takes over).
	var btn := int(cmd.get("btn", 0))
	var pressed = btn & ~ch.prev_buttons
	var my := float(cmd.get("my", 0.0))
	var mx := float(cmd.get("mx", 0.0))
	ch.ledge_t += dt
	ch.velocity = Vector3.ZERO
	ch.crouch = move_toward(ch.crouch, 0.0, dt * 5.0)
	ch.apply_height()
	# Settle on to the hang spot (the first instant the hands catch, the body swings in against the wall).
	var spot := hang_spot(ch)
	var prev: Vector3 = ch.global_position
	ch.global_position = prev.move_toward(spot, 7.0 * dt)
	ch.velocity = (ch.global_position - prev) / maxf(dt, 0.001)
	if (pressed & Motor.B_CROUCH) != 0 or my < -0.5:
		let_go(ch, 0.6)
		return false
	if ch.ledge_t > _m("hang_max_s"):
		let_go(ch, 0.3)
		return false
	if ((my > 0.3 and ch.ledge_t > 0.22) or (pressed & Motor.B_JUMP) != 0) and ch.ledge_t > 0.1:
		if climb(ch):
			return true
	if absf(mx) > 0.3:
		_shimmy(ch, signf(mx) * _m("shimmy_speed") * dt)
	return true


static func let_go(ch, push: float) -> void:
	ch.ledge_t = -1.0
	ch.pk_cd = 0.4
	ch.velocity = ch.ledge_n * push + Vector3.DOWN * 0.5
	ch.emit_motion_event("ledge_drop", 0.0)


static func _shimmy(ch, d: float) -> void:
	var t: Vector3 = ch.ledge_n.cross(Vector3.UP).normalized()
	var spot := hang_spot(ch) + t * d
	var probe := Vector3(spot.x, ch.ledge_p.y - 1.3, spot.z)
	var L := find_ledge(ch, probe, -ch.ledge_n)
	if L.is_empty() or absf(float(L.top) - ch.ledge_p.y) > 0.25:
		return
	ch.ledge_p = L.edge
	ch.ledge_n = (ch.ledge_n * 0.7 + (L.n as Vector3) * 0.3).normalized()
	ch.ledge_y = (L.hang as Vector3).y


static func climb(ch) -> bool:
	## Pull up from the hang: over a thin wall when there is ground beyond, else on to the top. False when there is no
	## room either way (the hands stay on the edge).
	if not ch.is_inside_tree():
		return false
	var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	var ex := [ch.get_rid()]
	var r := _m("radius")
	var into: Vector3 = -ch.ledge_n
	var top: float = ch.ledge_p.y
	var e: Vector3 = ch.ledge_p
	# How deep the top is.
	var depth := 1.6
	var k := 1
	while k <= 15:
		var q := e + into * (k * 0.1)
		if _ray(space, Vector3(q.x, top + 0.25, q.z), Vector3(q.x, top - 0.15, q.z), ex).is_empty():
			depth = k * 0.1 - 0.05
			break
		k += 1
	var a: Vector3 = ch.global_position
	var land := Vector3.INF
	var mid := Vector3.INF
	var over := false
	if depth <= THIN:
		for extra in [0.1, 0.25, 0.45]:
			var b = e + into * (depth + r + extra)
			var h := _ray(space, Vector3(b.x, top + 0.3, b.z), Vector3(b.x, top - OVER_MAX_DROP, b.z), ex)
			if h.is_empty():
				continue
			var cand := Vector3(b.x, (h.position as Vector3).y + 0.02, b.z)
			if _fits(ch, space, cand, _m("crouch_height")):
				land = cand
				mid = e + into * (depth * 0.5) + Vector3.UP * 0.12
				over = true
				break
	if land == Vector3.INF:
		var on := e + into * (r + 0.14)
		var h2 := _ray(space, Vector3(on.x, top + 0.3, on.z), Vector3(on.x, top - 0.2, on.z), ex)
		if h2.is_empty():
			return false
		var cand2 := Vector3(on.x, (h2.position as Vector3).y + 0.02, on.z)
		if not _fits(ch, space, cand2, _m("crouch_height")):
			return false
		land = cand2
		mid = e + into * 0.08 + Vector3.UP * 0.06
	# Room above the top to get the folded body through (a window: its opening), and nothing in the way across it.
	var gap := 1.8
	var up_hit := _ray(space, mid + Vector3.UP * 0.02, mid + Vector3.UP * 1.8, ex)
	if not up_hit.is_empty():
		gap = (up_hit.position as Vector3).y - mid.y
	if gap < 0.62:
		return false
	var across_a := e - into * 0.05 + Vector3.UP * 0.2
	var across_b := Vector3(land.x, top + 0.2, land.z)
	if over and not _ray(space, across_a, across_b, ex).is_empty():
		return false
	var rise := maxf(mid.y - a.y, 0.0)
	ch.ledge_t = -1.0
	ch.vault_t = 0.0
	ch.vault_d = 0.42 + 0.27 * rise + (0.12 if over else 0.0)
	ch.vault_a = a
	ch.vault_m = Vector3(mid.x, mid.y, mid.z)
	ch.vault_b = land
	ch.vault_h = clampf(gap + 0.05, _m("crouch_height") * 0.6, _m("crouch_height") * 0.9)
	ch.vault_s = 0.0
	ch.pk_bits |= PK_CLIMB
	if not _fits(ch, space, land, _m("stand_height") - 0.05):
		ch.crouching = true
	ch.velocity = Vector3.ZERO
	ch.emit_motion_event("climb", rise)
	return true


# ------------------------------------------------------------------ jumps

static func _wall_ahead(ch, p: Vector3, fwd: Vector3, reach: float) -> bool:
	if not ch.is_inside_tree():
		return false
	var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	var r := _m("radius")
	var ex := [ch.get_rid()]
	var n_hits := 0
	for hh in [0.5, 1.2]:
		var a: Vector3 = p + Vector3.UP * hh
		var hit := _ray(space, a, a + fwd * (r + reach), ex)
		if not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.4 and (hit.normal as Vector3).dot(fwd) < -0.75:
			n_hits += 1
	return n_hits == 2


static func ground_jump(ch, cmd: Dictionary, hv: Vector3, wd: Vector3, v: Vector3) -> Vector3:
	## The take-off: a plain jump, or a run-up when sprinting into a wall. A standing jump with the stick held
	## carries the body that way (forward more than backward). Returns the new velocity.
	var fwd: Vector3 = -Basis(Vector3.UP, ch.yaw).z
	var speed := hv.length()
	ch.pk_bits = 0
	if speed > _m("sprint_speed") * 0.72:
		ch.pk_bits |= PK_SPRINT_JUMP
	if speed > _m("sprint_speed") * 0.72 and hv.dot(fwd) > speed * 0.7 and can_grab(ch) and _wall_ahead(ch, ch.global_position, fwd, 0.7):
		ch.pk_bits |= PK_WALLRUN
		v.y = _m("wallrun_up_speed")
		hv *= 0.25
		ch.emit_motion_event("wallrun", 0.0)
	else:
		v.y = _m("jump_velocity")
		if wd.length_squared() > 0.01:
			var dir := wd.normalized()
			var back := dir.dot(fwd) < -0.5
			var carry := _m("jump_carry_back") if back else _m("jump_carry")
			var along := hv.dot(dir)
			if along < carry:
				hv += dir * (carry - along)
	v.x = hv.x
	v.z = hv.z
	ch.slide_t = -1.0
	ch.emit_motion_event("jump", speed)
	return v


# ------------------------------------------------------------------ slide and roll

static func try_slide(ch, cmd: Dictionary, hv: Vector3) -> bool:
	var btn := int(cmd.get("btn", 0))
	var pressed = btn & ~ch.prev_buttons
	if (pressed & Motor.B_CROUCH) == 0 or ch.slide_t >= 0.0 or ch.roll_t >= 0.0:
		return false
	var fwd: Vector3 = -Basis(Vector3.UP, ch.yaw).z
	if hv.length() < _m("slide_speed_min") or hv.dot(fwd) < hv.length() * 0.6:
		return false
	ch.slide_t = 0.0
	ch.crouching = true
	ch.emit_motion_event("slide", hv.length())
	return true


static func slide_step(ch, cmd: Dictionary, hv: Vector3, dt: float) -> Vector3:
	ch.slide_t += dt
	var s := hv.length()
	var dir := hv / s if s > 0.01 else -Basis(Vector3.UP, ch.yaw).z
	# Downhill keeps it going, uphill stops it sooner.
	var slope := 0.0
	if ch.is_on_floor():
		var fn: Vector3 = ch.get_floor_normal()
		slope = Vector3(fn.x, 0.0, fn.z).dot(dir) * 9.81
	s = maxf(s - (_m("slide_decel") - slope) * dt, 0.0)
	# A little steering with the stick.
	var wish := Motor.wish_dir(ch, cmd)
	if wish.length_squared() > 0.01:
		var ang := dir.signed_angle_to(wish.normalized(), Vector3.UP)
		dir = dir.rotated(Vector3.UP, clampf(ang, -0.9 * dt, 0.9 * dt))
	var btn := int(cmd.get("btn", 0))
	if s < 2.4 or ch.slide_t > _m("slide_s") or ((btn & Motor.B_CROUCH) == 0 and ch.slide_t > 0.3):
		ch.slide_t = -1.0
		if (btn & Motor.B_CROUCH) == 0 and ch.can_stand():
			ch.crouching = false
	return dir * s


static func start_roll(ch, hv: Vector3) -> Vector3:
	ch.roll_t = 0.0
	var fwd: Vector3 = -Basis(Vector3.UP, ch.yaw).z
	var s := hv.length()
	var dir := hv / s if s > 0.5 else fwd
	ch.emit_motion_event("roll", s)
	return dir * clampf(maxf(s, 3.0), 3.0, _m("sprint_speed"))


static func roll_step(ch, hv: Vector3, dt: float) -> Vector3:
	ch.roll_t += dt
	var s := hv.length()
	var dir := hv / s if s > 0.01 else -Basis(Vector3.UP, ch.yaw).z
	s = maxf(s - 2.2 * dt, 2.4)
	if ch.roll_t >= _m("roll_s"):
		ch.roll_t = -1.0
		ch.crouching = not ch.can_stand()
	return dir * s


# ------------------------------------------------------------------ helpers

static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, ex: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Defs.MOVE_MASK)
	q.exclude = ex
	return space.intersect_ray(q)


static func _fits(ch, space: PhysicsDirectSpaceState3D, feet: Vector3, height: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = _m("radius") - 0.03
	cap.height = maxf(height, cap.radius * 2.0 + 0.02)
	q.shape = cap
	q.transform = Transform3D(Basis(), feet + Vector3.UP * (cap.height * 0.5 + 0.05))
	q.collision_mask = Defs.MOVE_MASK
	q.exclude = [ch.get_rid()]
	return space.intersect_shape(q, 1).is_empty()
