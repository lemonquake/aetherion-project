extends AnimatableBody3D
## A hinged door or window shutter. The server decides where it swings; every client animates the same swing.
##
## - Tap Use: open away from you / close. Furniture or a body in the way stops the swing (a barricade).
## - Locked doors are barred from one side: from the inside you lift the bar quietly; from outside you must
##   force it (hold Use ~2 s), which is loud and breaks the latch for the rest of the match.

const SPEED := 2.6         # rad/s
const MAX_ANGLE := 1.65

var dyn = null
var spec: Dictionary = {}
var id := -1
var is_shutter := false
var angle := 0.0
var target := 0.0
var locked := false
var lock_inside := true
var moving := false
var w := 0.82
var h := 1.95
var t := 0.035
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _base: Transform3D
var _blocked_t := 0.0


func setup(d, s: Dictionary) -> void:
	dyn = d
	spec = s
	id = int(s.id)
	w = float(s.w)
	h = float(s.h)
	t = float(s.get("t", 0.035))
	_base = s.xf
	_build(str(s.get("mat", "plywood")))
	set_meta("door_id", id)
	set_meta("mat", dyn.mats.phys(str(s.get("mat", "plywood"))))


func setup_shutter(d, wspec: Dictionary) -> void:
	## Window shutter: hinged on the left edge of the window, opening outward.
	dyn = d
	spec = wspec
	is_shutter = true
	id = 100000 + int(wspec.id)
	w = float(wspec.w)
	h = float(wspec.h)
	t = 0.025
	_base = Transform3D(Basis(), Vector3(-w * 0.5, -h * 0.5, 0.0))
	_build("planks_paint")
	set_meta("shutter_id", int(wspec.id))
	set_meta("mat", "wood")


func _build(mat: String) -> void:
	sync_to_physics = false
	collision_layer = Defs.PHYS_WORLD | Defs.PHYS_INTERACT
	collision_mask = 0
	transform = _base
	_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, t)
	_shape.shape = bs
	_shape.position = Vector3(w * 0.5, h * 0.5, 0)
	add_child(_shape)
	if DisplayServer.get_name() == "headless":
		return
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, h, t)
	_mesh.mesh = bm
	_mesh.position = _shape.position
	_mesh.material_override = dyn.mats.get_material(mat)
	add_child(_mesh)
	# Handle / hasp
	var hm := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.1, 0.03, 0.06)
	hm.mesh = hb
	hm.position = Vector3(w - 0.08, h * 0.5 if not is_shutter else h * 0.5, t * 0.5 + 0.03)
	hm.material_override = dyn.mats.get_material("metal_rust")
	add_child(hm)


func reset_state(a: float, lk: bool) -> void:
	angle = a
	target = a
	locked = lk
	lock_inside = bool(spec.get("lock_inside", true))
	moving = false
	_apply()


func _apply() -> void:
	transform = _base * Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	if spec.has("portal") and dyn and dyn.map:
		dyn.map.acoustics.set_portal_open(int(spec.portal), clampf(absf(angle) / 1.1, 0.0, 1.0))


func hinge_side_sign(from: Vector3) -> float:
	## +1 if `from` is on the door's local +Z side.
	var local := _base.affine_inverse() * from
	return 1.0 if local.z > 0.0 else -1.0


func is_inside(from: Vector3) -> bool:
	## The inside of an outer door is opposite its outward normal.
	if not spec.has("outward"):
		return true
	var outward: Vector3 = spec.outward
	return (from - global_position).dot(outward) < 0.0


func server_use(user_pos: Vector3) -> String:
	## Returns what happened: "open", "close", "locked", "unlock".
	if locked:
		if lock_inside == is_inside(user_pos):
			locked = false
			return "unlock"
		return "locked"
	if absf(target) > 0.05:
		target = 0.0
	else:
		target = MAX_ANGLE * -hinge_side_sign(user_pos)
	moving = true
	return "open" if absf(target) > 0.05 else "close"


func server_force() -> void:
	locked = false
	target = MAX_ANGLE * (1.0 if randf() < 0.5 else -1.0)
	if spec.has("outward"):
		target = MAX_ANGLE * -hinge_side_sign(global_position + (spec.outward as Vector3) * 2.0)
	moving = true


func set_target(a: float, current: float, lk: bool) -> void:
	## Client: replicated state.
	target = a
	if absf(current - angle) > 0.4:
		angle = current
	locked = lk
	moving = true


func tick(dt: float) -> void:
	if not moving:
		return
	var next := move_toward(angle, target, SPEED * dt)
	if dyn and dyn.world and dyn.world.is_server and _would_hit(next):
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
		if dyn and dyn.world and dyn.world.is_server and absf(angle) < 0.01:
			dyn.world.server_sound("door_close", global_position + Vector3.UP, 0.0, -1)


func _would_hit(next: float) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w - 0.08, h - 0.1, t + 0.02)
	q.shape = bs
	q.transform = _base * Transform3D(Basis(Vector3.UP, next), Vector3.ZERO) * Transform3D(Basis(), Vector3(w * 0.5 + 0.03, h * 0.5, 0))
	q.collision_mask = Defs.PHYS_PROP | Defs.PHYS_CHAR | Defs.PHYS_CORPSE
	q.exclude = [get_rid()]
	for r in space.intersect_shape(q, 4):
		var c = r.collider
		if c is RigidBody3D and c.has_method("on_pushed") and c.mass < 6.0:
			# Light props get shoved aside by the door.
			c.apply_central_impulse((c.global_position - global_position).normalized() * 1.5)
			continue
		return true
	return false
