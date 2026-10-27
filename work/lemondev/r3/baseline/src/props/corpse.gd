extends Node3D
## A dead player: an 11-part ragdoll and the inventory they carried.
##
## The server simulates the ragdoll (jointed rigid bodies) with the momentum of the fall and the killing shot,
## streams the part transforms to clients until every part sleeps, then sends the final pose. Clients pose the
## same parts kinematically, so every machine sees the body lying in the same place and the loot is always where
## the body is. Corpses stay until the match resets.

const PARTS := {
	# name: [parent, size (x,y,z), standing offset from feet (local, facing -Z), mass]
	"pelvis": ["", Vector3(0.32, 0.2, 0.2), Vector3(0, 0.95, 0), 12.0],
	"chest": ["pelvis", Vector3(0.36, 0.42, 0.22), Vector3(0, 1.28, 0), 18.0],
	"head": ["chest", Vector3(0.2, 0.24, 0.22), Vector3(0, 1.64, 0), 5.0],
	"uarm_l": ["chest", Vector3(0.1, 0.3, 0.1), Vector3(-0.24, 1.33, 0), 2.2],
	"larm_l": ["uarm_l", Vector3(0.09, 0.3, 0.09), Vector3(-0.27, 1.04, 0), 1.6],
	"uarm_r": ["chest", Vector3(0.1, 0.3, 0.1), Vector3(0.24, 1.33, 0), 2.2],
	"larm_r": ["uarm_r", Vector3(0.09, 0.3, 0.09), Vector3(0.27, 1.04, 0), 1.6],
	"uleg_l": ["pelvis", Vector3(0.14, 0.44, 0.14), Vector3(-0.1, 0.64, 0), 7.0],
	"lleg_l": ["uleg_l", Vector3(0.12, 0.44, 0.12), Vector3(-0.1, 0.22, 0), 4.0],
	"uleg_r": ["pelvis", Vector3(0.14, 0.44, 0.14), Vector3(0.1, 0.64, 0), 7.0],
	"lleg_r": ["uleg_r", Vector3(0.12, 0.44, 0.12), Vector3(0.1, 0.22, 0), 4.0],
}
const ORDER := ["pelvis", "chest", "head", "uarm_l", "larm_l", "uarm_r", "larm_r", "uleg_l", "lleg_l", "uleg_r", "lleg_r"]

var id := -1
var server := false
var entries: Array = []
var pname := ""
var team := 0
var outfit := 0
var bodies: Dictionary = {}     # server: name -> RigidBody3D
var visuals: Dictionary = {}    # client: name -> Node3D
var settled := false
var _sync_t := 0.0
var _rest_t := 0.0
var _snaps: Array = []
var world = null


func setup_server(w, cid: int, ch, impulse: Vector3) -> void:
	world = w
	id = cid
	server = true
	pname = ch.pname
	team = ch.team
	name = "Corpse%d" % id
	var basis := Basis(Vector3.UP, ch.yaw)
	var origin: Vector3 = ch.global_position
	var crouch: float = clampf(ch.crouch, 0.0, 1.0)
	var lying: bool = ch.mode == Motor.DOWNED
	for part in ORDER:
		var spec: Array = PARTS[part]
		var rb := RigidBody3D.new()
		rb.name = part
		rb.mass = float(spec[3])
		rb.collision_layer = Defs.PHYS_CORPSE
		rb.collision_mask = Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS | Defs.PHYS_CORPSE
		rb.set_meta("corpse_id", id)
		rb.set_meta("mat", "flesh")
		rb.linear_damp = 0.4
		rb.angular_damp = 2.5
		rb.continuous_cd = true
		var pm := PhysicsMaterial.new()
		pm.friction = 0.9
		pm.bounce = 0.0
		rb.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var sz: Vector3 = spec[1]
		cap.radius = minf(sz.x, sz.z) * 0.5
		cap.height = maxf(sz.y, cap.radius * 2.0 + 0.01)
		cs.shape = cap
		rb.add_child(cs)
		if DisplayServer.get_name() != "headless":
			rb.add_child(_part_mesh(part, cap))
		var off: Vector3 = spec[2]
		off.y *= lerpf(1.0, 0.68, crouch)
		if lying:
			off = Vector3(off.x, 0.18, -off.y + 0.9)
		var rot := Basis() if not lying else Basis(Vector3.RIGHT, -PI * 0.5)
		add_child(rb)
		rb.global_transform = Transform3D(basis * rot, origin + basis * off)
		rb.linear_velocity = ch.velocity * 0.9
		bodies[part] = rb
	# The killing blow: most of the impulse goes into the chest and head.
	(bodies.chest as RigidBody3D).apply_central_impulse(impulse * 9.0)
	(bodies.head as RigidBody3D).apply_central_impulse(impulse * 2.0 + Vector3.UP * 0.2)
	(bodies.pelvis as RigidBody3D).apply_central_impulse(impulse * 3.0)
	for part in ORDER:
		var parent := str(PARTS[part][0])
		if parent == "":
			continue
		_joint(bodies[parent], bodies[part], part)


func _joint(a: RigidBody3D, b: RigidBody3D, part: String) -> void:
	var j := ConeTwistJoint3D.new()
	add_child(j)
	# Joint at the top of the child part.
	var sz: Vector3 = PARTS[part][1]
	j.global_transform = Transform3D(b.global_transform.basis, b.global_transform * Vector3(0, sz.y * 0.5, 0))
	j.node_a = j.get_path_to(a)
	j.node_b = j.get_path_to(b)
	var swing := 0.6
	var twist := 0.4
	if part == "head":
		swing = 0.5
		twist = 0.6
	elif part.begins_with("larm") or part.begins_with("lleg"):
		swing = 1.2
		twist = 0.15
	elif part.begins_with("uarm"):
		swing = 1.4
		twist = 0.8
	elif part.begins_with("uleg"):
		swing = 0.9
		twist = 0.3
	j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, swing)
	j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, twist)
	# No softness: Jolt ignores it and logged a warning with a backtrace per joint (a hitch on every death).
	j.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)


func pose() -> Array:
	var out := []
	for part in ORDER:
		var rb: RigidBody3D = bodies[part]
		out.append(rb.global_transform)
	return out


func _physics_process(dt: float) -> void:
	if not server or settled:
		return
	_sync_t -= dt
	var moving := false
	for part in ORDER:
		var rb: RigidBody3D = bodies[part]
		if rb.linear_velocity.length() > 0.08 or rb.angular_velocity.length() > 0.2:
			moving = true
		if rb.global_position.y < -40.0:
			rb.global_position = (bodies.pelvis as RigidBody3D).global_position + Vector3.UP
	if moving:
		_rest_t = 0.0
	else:
		_rest_t += dt
	if _sync_t <= 0.0:
		_sync_t = 1.0 / float(Defs.rule("corpse_ragdoll_sync_hz", 12))
		world.corpse_pose(id, pose(), false)
	if _rest_t > 1.2 or get_tree() == null:
		settled = true
		# Settled bodies stop simulating but keep their collision so bullets and loot rays still find them.
		for part in ORDER:
			var rb: RigidBody3D = bodies[part]
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rb.freeze = true
		world.corpse_pose(id, pose(), true)


# ------------------------------------------------------------------ clients

func setup_client(w, cid: int, who: String, t: int, xforms: Array) -> void:
	# The pose stream is interpolated here every frame; engine interpolation on top would step.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world = w
	id = cid
	pname = who
	team = t
	name = "Corpse%d" % id
	for i in ORDER.size():
		var part: String = ORDER[i]
		var sb := StaticBody3D.new()
		sb.collision_layer = Defs.PHYS_CORPSE
		sb.collision_mask = 0
		sb.set_meta("corpse_id", id)
		sb.set_meta("mat", "flesh")
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var sz: Vector3 = PARTS[part][1]
		cap.radius = minf(sz.x, sz.z) * 0.5
		cap.height = maxf(sz.y, cap.radius * 2.0 + 0.01)
		cs.shape = cap
		sb.add_child(cs)
		if DisplayServer.get_name() != "headless":
			sb.add_child(_part_mesh(part, cap))
		add_child(sb)
		visuals[part] = sb
		if i < xforms.size():
			sb.global_transform = xforms[i]


func client_pose(xforms: Array, final: bool) -> void:
	_snaps.append([Time.get_ticks_msec() / 1000.0, xforms])
	if final:
		settled = true
		_apply(xforms)
		_snaps.clear()


func _process(dt: float) -> void:
	if server or _snaps.is_empty():
		return
	# Play the stream back ~120 ms late, interpolating between received poses.
	var now := Time.get_ticks_msec() / 1000.0 - 0.12
	var a: Array = _snaps[0]
	var b: Array = _snaps[0]
	for i in range(_snaps.size() - 1, -1, -1):
		if float(_snaps[i][0]) <= now:
			a = _snaps[i]
			b = _snaps[mini(i + 1, _snaps.size() - 1)]
			break
	var span := float(b[0]) - float(a[0])
	var f := 0.0 if span <= 0.0 else clampf((now - float(a[0])) / span, 0.0, 1.0)
	var out := []
	for i in ORDER.size():
		var ta: Transform3D = a[1][i]
		var tb: Transform3D = b[1][i]
		out.append(ta.interpolate_with(tb, f))
	_apply(out)
	while _snaps.size() > 2 and float(_snaps[1][0]) < now:
		_snaps.pop_front()


func _apply(xforms: Array) -> void:
	for i in mini(xforms.size(), ORDER.size()):
		(visuals[ORDER[i]] as Node3D).global_transform = xforms[i]


func _part_mesh(part: String, cap: CapsuleShape3D) -> MeshInstance3D:
	## Simple clothed segments (dark hoodie, jeans, skin at head and hands) until the skinned body replaces them.
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = cap.radius
	cm.height = cap.height
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	if part in ["chest", "uarm_l", "uarm_r", "pelvis"]:
		m.albedo_color = Color(0.07, 0.07, 0.08)
	elif part.begins_with("uleg") or part.begins_with("lleg"):
		m.albedo_color = Color(0.12, 0.14, 0.2)
	else:
		m.albedo_color = Color(0.4, 0.28, 0.22)
	m.roughness = 0.9
	mi.material_override = m
	return mi


func center() -> Vector3:
	if server:
		return (bodies.pelvis as Node3D).global_position
	return (visuals.pelvis as Node3D).global_position
