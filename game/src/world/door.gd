extends RefCounted
## A hinged door or window shutter without a scene node: a kinematic physics body plus one instance in a shared
## MultiMesh (thousands of doors cost a handful of draw calls). The server decides where it swings; every client
## animates the same swing.
##
## - Tap Use: open toward where you are looking (the leaf swings away in front of you) / close. Furniture or a body
##   in the way stops the swing (a barricade).
## - An open door is a loose leaf on its hinge: walking or running into it shoves it out of the way and it keeps
##   swinging, slowed by the hinge, bouncing off its stop. Swung back to the frame it latches shut with a click and
##   blocks again. A shut door is not pushed open; it has to be used.
## - Locked doors are barred from one side: from the inside you lift the bar quietly; from outside you must force
##   it (hold Use ~2 s), which is loud and breaks the latch for the rest of the match.

const SPEED := 2.6
const MAX_ANGLE := 1.65
const OPEN_PASS := 0.08     # beyond this angle the leaf no longer blocks movement (it is pushed aside instead)
const HINGE_DAMP := 2.4     # free swing slows by this rate (1/s)
const LATCH := 0.03

var dyn = null
var spec: Dictionary = {}
var id := -1
var is_shutter := false
var angle := 0.0
var target := 0.0
var omega := 0.0            # free swing speed (rad/s)
var free := false           # swinging loose after a push (true) or driven toward target by Use (false)
var locked := false
var lock_inside := true
var moving := false
var w := 0.82
var h := 1.95
var t := 0.035
var base: Transform3D
var body: RID
var shape: RID
var mm_key := ""
var mm_index := -1
var _blocked_t := 0.0
var _solid := true
var _sync_t := 0.0


func setup(d, s: Dictionary) -> void:
	dyn = d
	spec = s
	id = int(s.id)
	w = float(s.w)
	h = float(s.h)
	t = float(s.get("t", 0.035))
	base = s.xf
	set_meta("door_id", id)
	set_meta("mat", dyn.mats.phys(str(s.get("mat", "plywood"))))
	_create(str(s.get("mat", "plywood")))


func setup_shutter(d, wspec: Dictionary) -> void:
	## Window shutter: hinged on the left edge of the window.
	dyn = d
	spec = wspec
	is_shutter = true
	id = 1000000 + int(wspec.id)
	w = float(wspec.w)
	h = float(wspec.h)
	t = 0.025
	base = (wspec.xf as Transform3D) * Transform3D(Basis(), Vector3(-w * 0.5, -h * 0.5, 0.0))
	set_meta("shutter_id", int(wspec.id))
	set_meta("mat", "wood")
	_create("planks_paint")


func _create(mat: String) -> void:
	shape = PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, Vector3(w, h, t) * 0.5)
	body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_KINEMATIC)
	PhysicsServer3D.body_set_space(body, dyn.space_rid)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), Vector3(w * 0.5, h * 0.5, 0)))
	PhysicsServer3D.body_set_collision_layer(body, Defs.PHYS_WORLD | Defs.PHYS_INTERACT)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_attach_object_instance_id(body, get_instance_id())
	var r = dyn.add_leaf_instance(self, mat)
	mm_key = r[0]
	mm_index = r[1]
	_apply()


func free_body() -> void:
	if body.is_valid():
		PhysicsServer3D.free_rid(body)
		PhysicsServer3D.free_rid(shape)
	body = RID()


func current_transform() -> Transform3D:
	return base * Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)


func center() -> Vector3:
	return current_transform() * Vector3(w * 0.5, h * 0.5, 0)


func reset_state(a: float, lk: bool) -> void:
	angle = a
	target = a
	omega = 0.0
	free = false
	locked = lk
	lock_inside = bool(spec.get("lock_inside", true))
	moving = false
	_apply()


func _apply() -> void:
	var xf := current_transform()
	if body.is_valid():
		PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
		# Shut, the leaf is a wall. Open, people push it aside rather than walk into it; bullets still hit it.
		var solid := absf(angle) <= OPEN_PASS or is_shutter
		if solid != _solid:
			_solid = solid
			PhysicsServer3D.body_set_collision_layer(body, (Defs.PHYS_WORLD if solid else Defs.PHYS_PROJ_ONLY) | Defs.PHYS_INTERACT)
	dyn.set_leaf_transform(mm_key, mm_index, xf * Transform3D(Basis().scaled(Vector3(w, h, t)), Vector3(w * 0.5, h * 0.5, 0)))
	if spec.has("portal") and dyn.map:
		dyn.map.acoustics.set_portal_open(int(spec.portal), clampf(absf(angle) / 1.1, 0.0, 1.0))


func hinge_side_sign(from: Vector3) -> float:
	var local := base.affine_inverse() * from
	return 1.0 if local.z > 0.0 else -1.0


func is_inside(from: Vector3) -> bool:
	if not spec.has("outward"):
		return true
	var outward: Vector3 = spec.outward
	return (from - base.origin).dot(outward) < 0.0


func _away_sign(facing: Vector3, user_pos: Vector3) -> float:
	## Angle sign that swings the leaf forward along `facing` (a positive angle moves it toward the frame's -z side).
	## Without a usable facing, away from where the user stands.
	var n0 := base.basis.z.normalized()
	var f := Vector3(facing.x, 0.0, facing.z)
	if f.length() > 0.1 and absf(f.normalized().dot(n0)) > 0.15:
		return 1.0 if f.dot(n0) < 0.0 else -1.0
	return hinge_side_sign(user_pos)


func server_use(user_pos: Vector3, facing: Vector3 = Vector3.ZERO) -> String:
	if locked:
		if lock_inside == is_inside(user_pos):
			locked = false
			return "unlock"
		return "locked"
	free = false
	omega = 0.0
	if absf(angle) > 0.05 or absf(target) > 0.05:
		target = 0.0
	else:
		target = MAX_ANGLE * _away_sign(facing, user_pos)
	_start()
	return "open" if absf(target) > 0.05 else "close"


func server_force(user_pos: Vector3) -> void:
	locked = false
	free = false
	target = MAX_ANGLE * hinge_side_sign(user_pos)
	_start()


func set_target(a: float, current: float, lk: bool) -> void:
	free = false
	omega = 0.0
	target = a
	if absf(current - angle) > 0.4:
		angle = current
		_apply()
	locked = lk
	_start()


func set_swing(a: float, w_rad: float) -> void:
	## Client: the server's free swing (angle now, swing speed). The leaf eases to it and keeps swinging locally.
	free = true
	if absf(a - angle) > 0.25:
		angle = a
	else:
		angle = lerpf(angle, a, 0.5)
	omega = w_rad
	_apply()
	_start()


func _start() -> void:
	## Swinging doors are the only ones ticked (the map has thousands).
	moving = true
	dyn.door_started(self)


func _is_server() -> bool:
	return dyn.world != null and dyn.world.get("is_server") == true


func push(p: Vector3, v: Vector3, radius: float) -> bool:
	## A character at p (feet), moving at v, against this leaf: shove the leaf out of the way and set it swinging.
	## Shut and locked doors are not pushed. Returns true when it pushed.
	if locked or is_shutter or (not free and absf(angle) <= OPEN_PASS and absf(target) < 0.05):
		return false
	# Cheap reject first (called for every character against every open door nearby, every tick).
	var dx := p.x - base.origin.x
	var dz := p.z - base.origin.z
	var reach_sq := (w + radius + 0.15) * (w + radius + 0.15)
	if dx * dx + dz * dz > reach_sq or p.y > base.origin.y + h or p.y + 1.6 < base.origin.y:
		return false
	var b := current_transform().basis
	var u := b.x
	u.y = 0.0
	u = u.normalized()
	var n := Vector3(-u.z, 0.0, u.x)  # leaf normal in the x-z plane (= b.z for an upright leaf)
	if n.dot(b.z) < 0.0:
		n = -n
	var rel := p - base.origin
	rel.y = 0.0
	var s := rel.dot(u)
	var q := rel.dot(n)
	if s < -0.05 or s > w + radius * 0.5:
		return false
	var reach := radius + t * 0.5 + 0.06
	var pen := reach - absf(q)
	if pen <= 0.0:
		return false
	var side := signf(q) if q != 0.0 else 1.0
	# A positive angle moves the leaf toward -n: from the +n side the leaf must turn positive to get away.
	var sgn := side
	var lever := clampf(s, 0.3, w)
	var into := maxf(-v.dot(n) * side, 0.0)
	var want := sgn * (into / lever * 1.2 + 0.4)
	angle = clampf(angle + sgn * pen / lever, -MAX_ANGLE, MAX_ANGLE)
	if omega * sgn < absf(want):
		omega = want
	free = true
	_start()
	_apply()
	return true


func tick(dt: float) -> void:
	if not moving:
		return
	if free:
		_tick_free(dt)
		return
	var next := move_toward(angle, target, SPEED * dt)
	if _is_server() and _would_hit(next):
		_blocked_t += dt
		if _blocked_t > 0.15:
			# Something heavy (or someone) is in the way: stop here. The barricade holds.
			target = angle
			moving = false
			_blocked_t = 0.0
			dyn.world.map_door_state(self, "blocked")
		return
	_blocked_t = 0.0
	angle = next
	_apply()
	if is_equal_approx(angle, target):
		moving = false
		if _is_server() and absf(angle) < 0.01:
			dyn.world.server_sound("door_close", center(), 0.0, -1)


func _tick_free(dt: float) -> void:
	var prev := angle
	angle += omega * dt
	omega *= exp(-HINGE_DAMP * dt)
	if absf(angle) > MAX_ANGLE:
		# The stop (a wall or the frame's limit): bounce back a little.
		angle = signf(angle) * MAX_ANGLE
		omega = -omega * 0.25
	var crossed := prev != 0.0 and signf(prev) != signf(angle)
	if crossed or absf(angle) < LATCH:
		if _is_server():
			# Swung back into the frame: it latches shut.
			angle = 0.0
			omega = 0.0
			target = 0.0
			free = false
			moving = false
			_apply()
			dyn.world.map_door_state(self, "latched")
			return
		# A client waits for the server to say it latched; until then the leaf rests just off the frame.
		angle = signf(prev) * (OPEN_PASS + 0.02)
		omega = 0.0
	_apply()
	if _is_server():
		_sync_t -= dt
		if _sync_t <= 0.0:
			_sync_t = 0.1
			dyn.world.map_door_swing(self)
	if absf(omega) < 0.03:
		omega = 0.0
		free = false
		target = angle
		moving = false
		if _is_server():
			dyn.world.map_door_swing(self)


func _would_hit(next: float) -> bool:
	var space := PhysicsServer3D.space_get_direct_state(dyn.space_rid)
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w - 0.08, h - 0.1, t + 0.02)
	q.shape = bs
	q.transform = base * Transform3D(Basis(Vector3.UP, next), Vector3.ZERO) * Transform3D(Basis(), Vector3(w * 0.5 + 0.03, h * 0.5, 0))
	q.collision_mask = Defs.PHYS_PROP | Defs.PHYS_CHAR | Defs.PHYS_CORPSE
	q.exclude = [body]
	for r in space.intersect_shape(q, 4):
		var c = r.collider
		if c is RigidBody3D and c.has_method("on_pushed") and c.mass < 6.0:
			c.apply_central_impulse((c.global_position - center()).normalized() * 1.5)
			continue
		if c != null and c.has_meta("prop_id") and light_resting_prop(int(c.get_meta("prop_id"))):
			# A bottle or bucket resting in the swing is a static body until something wakes it: the server wakes it
			# and shoves it like the loose props above; a client leaves it to the server's update.
			if _is_server():
				var pb = dyn.server_activate(int(c.get_meta("prop_id")))
				if pb is RigidBody3D:
					pb.apply_central_impulse((pb.global_position - center()).normalized() * 1.5)
			continue
		if c is Character and absf(next) > OPEN_PASS and absf(next) > absf(angle):
			# Opening into someone: the open leaf does not block people, it pushes past them (they shove it back).
			continue
		return true
	return false


func light_resting_prop(prop_id: int) -> bool:
	## A resting prop light enough for a door to shove aside (heavy ones stop it: barricades).
	if prop_id < 0 or prop_id >= dyn.props.size():
		return false
	return float(dyn.models.spec(str(dyn.props[prop_id].name)).get("mass", 99.0)) < 6.0
