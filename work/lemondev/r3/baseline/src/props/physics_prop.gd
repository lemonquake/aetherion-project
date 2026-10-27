extends RigidBody3D
## A movable prop that has been woken up (pushed, grabbed, shot or hit). Server: a real rigid body with mass,
## friction, impact sounds and damage-dependent breaking. Clients: a kinematic copy following snapshots.

var dyn = null
var p: Dictionary = {}
var spec: Dictionary = {}
var server := false
var hp := 100.0
var _snaps: Array = []
var _last_impact := 0.0
var _scrape_t := 0.0
var _rest_sent := false
var _impact_cd := 0.0
var held_by := -1


func setup(d, prop: Dictionary, s: Dictionary, shape: Dictionary, model: Dictionary, is_server: bool) -> void:
	dyn = d
	p = prop
	spec = s
	server = is_server
	if not server:
		# Clients place it every frame from snapshots (interpolate()); engine interpolation on top would step.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	hp = float(prop.get("health", s.get("hp", 100)))
	mass = maxf(float(s.get("mass", 5.0)), 0.2)
	collision_layer = Defs.PHYS_PROP | Defs.PHYS_INTERACT
	collision_mask = Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS | Defs.PHYS_CHAR
	if s.get("no_block", false):
		# Trash: tumbles on the ground and can be carried, but people and bullets pass through it.
		collision_layer = Defs.PHYS_DEBRIS | Defs.PHYS_INTERACT
		collision_mask = Defs.PHYS_WORLD | Defs.PHYS_GLASS
	set_meta("prop_id", int(prop.id))
	set_meta("mat", str(s.get("mat", "wood")))
	var pm := PhysicsMaterial.new()
	match str(s.get("mat", "wood")):
		"plastic":
			pm.friction = 0.55
			pm.bounce = 0.25
		"steel", "sheet_metal":
			pm.friction = 0.45
			pm.bounce = 0.1
		"glass":
			pm.friction = 0.4
			pm.bounce = 0.15
		_:
			pm.friction = 0.7
			pm.bounce = 0.05
	physics_material_override = pm
	continuous_cd = mass < 3.0
	contact_monitor = server
	max_contacts_reported = 4 if server else 0
	can_sleep = true
	linear_damp = 0.1
	angular_damp = 0.4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = shape.size
	cs.shape = bs
	cs.position = shape.center
	add_child(cs)
	if DisplayServer.get_name() != "headless" and model.has("mesh"):
		var mi := MeshInstance3D.new()
		mi.mesh = model.mesh
		mi.position = model.get("offset", Vector3.ZERO)
		add_child(mi)
	if not server:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	else:
		body_entered.connect(_on_body_entered)
		sleeping_state_changed.connect(_on_sleep)


# ------------------------------------------------------------------ server

func on_pushed(by, dir: Vector3, vel: Vector3, dt: float) -> void:
	## A character walking into this prop: a bounded shove that light props feel and heavy ones barely do.
	var speed := Vector2(vel.x, vel.z).length()
	if speed < 0.2:
		return
	var push := minf(speed * 18.0 / maxf(mass, 1.0), 4.0)
	var f := Vector3(dir.x, 0.0, dir.z).normalized() * push * mass * 0.06
	if mass > float(Defs.rule("interaction.push_mass_limit", 120.0)):
		return
	apply_impulse(f, Vector3(0, 0.25, 0))
	sleeping = false


func _on_body_entered(other: Node) -> void:
	var speed := linear_velocity.length()
	if speed < 1.2 or _impact_cd > 0.0:
		return
	_impact_cd = 0.12
	var energy := 0.5 * mass * speed * speed
	var mat := str(spec.get("mat", "wood"))
	dyn.world.server_sound("impact_" + _impact_family(mat), global_position, clampf(linear_to_db(speed / 6.0), -18.0, 4.0), -1)
	take_damage(energy * 0.6, linear_velocity)


func _impact_family(mat: String) -> String:
	match mat:
		"plastic":
			return "plastic"
		"steel", "sheet_metal":
			return "metal"
		"glass":
			return "glass"
		"fabric", "sand":
			return "soft"
	return "wood"


func take_damage(amount: float, impulse: Vector3) -> void:
	hp -= amount
	p.health = hp
	if hp <= 0.0:
		dyn.server_break_prop(int(p.id), impulse)


func _on_sleep() -> void:
	if sleeping:
		dyn.server_prop_slept(int(p.id))


func _physics_process(dt: float) -> void:
	_impact_cd = maxf(_impact_cd - dt, 0.0)
	if not server or sleeping:
		return
	# Scraping: heavy furniture dragged across a floor is loud.
	var hv := Vector2(linear_velocity.x, linear_velocity.z).length()
	if mass > 8.0 and hv > 0.25 and get_contact_count() > 0:
		_scrape_t -= dt
		if _scrape_t <= 0.0:
			_scrape_t = 0.28
			dyn.world.server_sound("scrape_heavy" if mass > 25.0 else "scrape_light", global_position, clampf(linear_to_db(hv), -12.0, 3.0), -1)
	if global_position.y < -30.0:
		global_position = (p.home as Transform3D).origin + Vector3.UP
		linear_velocity = Vector3.ZERO


# ------------------------------------------------------------------ client

func push_snapshot(t: float, pos: Vector3, rot: Quaternion) -> void:
	_snaps.append([t, pos, rot])
	while _snaps.size() > 20:
		_snaps.pop_front()


func interpolate(render_tick: float) -> void:
	if server or _snaps.is_empty():
		return
	var a: Array = _snaps[0]
	var b: Array = _snaps[0]
	for i in range(_snaps.size() - 1, -1, -1):
		if float(_snaps[i][0]) <= render_tick:
			a = _snaps[i]
			b = _snaps[mini(i + 1, _snaps.size() - 1)]
			break
	var span := float(b[0]) - float(a[0])
	var f := 0.0 if span <= 0.0 else clampf((render_tick - float(a[0])) / span, 0.0, 1.0)
	global_transform = Transform3D(Basis((a[2] as Quaternion).slerp(b[2], f)), (a[1] as Vector3).lerp(b[1], f))


func client_rest(xf: Transform3D) -> void:
	_snaps.clear()
	global_transform = xf
