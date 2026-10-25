class_name Character
extends CharacterBody3D
## A player or bot body. The same node runs on the server (authoritative), on the owning client (predicted)
## and on other clients (interpolated from snapshots, never simulated).

signal motion_event(kind: String, value: float)

const HitZones := preload("res://src/player/hitzones.gd")

var eid := 0
var pid := 0
var team := 0
var pname := ""
var world = null  # World node
var is_local := false
var is_remote := false  # interpolated proxy on a client

# --- movement state (part of prediction snapshot)
var mode := Motor.GROUND
var yaw := 0.0
var pitch := 0.0
var crouch := 0.0
var crouching := false
var sprinting := false
var walking := false
var prev_buttons := 0
var jump_cooldown := 0.0
var land_timer := 0.0
var freefall_t := 0.0
var chute_t := 0.0
var chute_yaw := 0.0
var flare_t := 0.0
var chute_snag_t := 0.0
var chute_separation := Vector3.ZERO

# --- gameplay state
var flags := 0
var weapon_id := ""        # currently drawn weapon (for visuals of remote characters)
var injury_speed := 1.0    # from leg injuries (server authoritative, mirrored to owner)
var carry_speed := 1.0     # from carried weight/held object
var stamina := 1.0
var replaying := false     # true while the owning client re-simulates unacknowledged commands
var events: Array = []     # motion events produced during the last step (server consumes)
var last_cmd: Dictionary = {}
var held_prop_id := -1

# Components (assigned by World)
var wpn = null      # WeaponState
var light = null    # FlashlightState
var health = null   # Health (server) or HealthView (clients)
var inv = null      # Inventory (server and owner)

# --- remote interpolation
var _snaps: Array = []  # [{t, pos, yaw, pitch, crouch, mode, flags, vel, weapon}]
var visual: Node3D = null

var _shape: CollisionShape3D
var _capsule: CapsuleShape3D

const F_LIGHT := 1
const F_AIM := 2
const F_SPRINT := 4
const F_TAB := 8
const F_RELOAD := 16
const F_HEAL := 32
const F_CROUCH := 64
const F_WALK := 128
const F_FIRED := 256
const F_LOWBAT := 512
const F_DOWNED := 1024
const F_FLARE := 2048
const F_HOLD := 4096
const F_RADIO := 8192
const F_WATER := 16384
const F_LIMP := 32768
const F_WLIGHT := 65536  # active light is weapon-mounted
const F_BUSY := 131072   # swapping battery / treating / reviving


func _init() -> void:
	collision_layer = Defs.PHYS_CHAR
	collision_mask = Defs.MOVE_MASK | Defs.PHYS_CHAR
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	wall_min_slide_angle = deg_to_rad(10.0)
	safe_margin = 0.02
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_capsule = CapsuleShape3D.new()
	_capsule.radius = Defs.move("radius") if Defs.rules.size() > 0 else 0.3
	_capsule.height = 1.78
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = 0.89
	add_child(_shape)


# ------------------------------------------------------------------ geometry helpers

func height() -> float:
	if mode == Motor.DOWNED:
		return Defs.move("downed_height")
	return lerpf(Defs.move("stand_height"), Defs.move("crouch_height"), clampf(crouch, 0.0, 1.0))


func apply_height() -> void:
	var h := height()
	h = maxf(h, _capsule.radius * 2.0 + 0.01)
	if absf(_capsule.height - h) > 0.001:
		_capsule.height = h
		_shape.position.y = h * 0.5


func eye_position() -> Vector3:
	return global_position + Vector3.UP * (height() - Defs.move("eye_offset"))


func aim_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func aim_dir() -> Vector3:
	return -aim_basis().z


func can_stand() -> bool:
	if not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = _capsule.radius - 0.02
	cap.height = Defs.move("stand_height") - 0.1
	q.shape = cap
	q.transform = Transform3D(Basis(), global_position + Vector3.UP * (cap.height * 0.5 + 0.08))
	q.collision_mask = Defs.MOVE_MASK
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()


func can_sprint() -> bool:
	return injury_speed > 0.55 and stamina > 0.05 and not (flags & F_TAB)


func speed_mult() -> float:
	return injury_speed * carry_speed


func water_surface() -> float:
	if world:
		return world.water_height(global_position.x, global_position.z)
	return -INF


func water_depth() -> float:
	var s := water_surface()
	if s == -INF:
		return 0.0
	return maxf(s - global_position.y, 0.0)


func height_above_ground() -> float:
	if not is_inside_tree():
		return 999.0
	var space := get_world_3d().direct_space_state
	var from := global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 600.0, Defs.PHYS_WORLD | Defs.PHYS_PROP)
	var r := space.intersect_ray(q)
	var agl := 600.0
	if not r.is_empty():
		agl = from.y - r.position.y
	var ws := water_surface()
	if ws != -INF:
		agl = minf(agl, from.y - ws)
	return agl


# ------------------------------------------------------------------ movement

func move_body(dt: float, airborne: bool = false) -> void:
	var pre := global_position
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	if not airborne and is_on_floor() and horizontal.length() > 0.2:
		_try_step(pre, horizontal, dt)
	_push_props(dt)


func _try_step(pre: Vector3, horizontal: Vector3, dt: float) -> void:
	## CharacterBody3D does not climb kerbs: if we were blocked by something shorter than step_height, lift over it.
	var moved := Vector3(global_position.x - pre.x, 0.0, global_position.z - pre.z).length()
	var wanted := horizontal.length() * dt
	if moved > wanted * 0.6:
		return
	var step_h := Defs.move("step_height")
	var motion := horizontal * dt
	var t := global_transform
	if test_move(t, Vector3.UP * step_h):
		return
	t.origin += Vector3.UP * step_h
	if test_move(t, motion):
		return
	t.origin += motion
	var col := KinematicCollision3D.new()
	if test_move(t, Vector3.DOWN * (step_h + 0.05), col):
		t.origin += col.get_travel()
		if col.get_normal().y > 0.7:
			global_position = t.origin


func _push_props(dt: float) -> void:
	## Walking into a loose prop shoves it with a bounded impulse; heavy furniture barely moves.
	if not (world and world.is_server):
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var body := c.get_collider()
		if body is RigidBody3D and body.has_method("on_pushed"):
			body.on_pushed(self, -c.get_normal(), velocity, dt)
		elif body and body.has_meta("prop_id") and world:
			world.server_wake_prop(int(body.get_meta("prop_id")), self, -c.get_normal(), velocity)


func emit_motion_event(kind: String, value: float) -> void:
	events.append([kind, value])
	if not replaying:
		motion_event.emit(kind, value)


# ------------------------------------------------------------------ prediction state

func get_state() -> Dictionary:
	return {"pos": global_position, "vel": velocity, "mode": mode, "crouch": crouch, "crouching": crouching,
		"jcd": jump_cooldown, "ff": freefall_t, "ct": chute_t, "cy": chute_yaw, "fl": flare_t, "pb": prev_buttons}


func set_state(s: Dictionary) -> void:
	global_position = s.pos
	velocity = s.vel
	mode = s.mode
	crouch = s.crouch
	crouching = s.crouching
	jump_cooldown = s.get("jcd", 0.0)
	freefall_t = s.get("ff", 0.0)
	chute_t = s.get("ct", 0.0)
	chute_yaw = s.get("cy", chute_yaw)
	flare_t = s.get("fl", 0.0)
	prev_buttons = s.get("pb", prev_buttons)
	apply_height()


# ------------------------------------------------------------------ flags

func compute_flags() -> int:
	var f := 0
	if light and light.on:
		f |= F_LIGHT
		if light.low():
			f |= F_LOWBAT
		if light.weapon_mounted:
			f |= F_WLIGHT
	if wpn:
		if wpn.aiming:
			f |= F_AIM
		if wpn.reloading():
			f |= F_RELOAD
		if wpn.fired_recently():
			f |= F_FIRED
	if sprinting:
		f |= F_SPRINT
	if crouching:
		f |= F_CROUCH
	if walking:
		f |= F_WALK
	if mode == Motor.DOWNED:
		f |= F_DOWNED
	if flare_t > 0.0:
		f |= F_FLARE
	if held_prop_id >= 0:
		f |= F_HOLD
	if water_depth() > 0.45:
		f |= F_WATER
	if injury_speed < 0.95:
		f |= F_LIMP
	f |= flags & (F_TAB | F_HEAL | F_RADIO | F_BUSY)
	return f


# ------------------------------------------------------------------ remote interpolation

func push_snapshot(t: float, s: Dictionary) -> void:
	if not _snaps.is_empty() and t <= float(_snaps[-1].t):
		return
	s.t = t
	_snaps.append(s)
	while _snaps.size() > 30:
		_snaps.pop_front()


func interpolate(render_tick: float) -> void:
	if _snaps.is_empty():
		return
	var a: Dictionary = _snaps[0]
	var b: Dictionary = _snaps[0]
	for i in range(_snaps.size() - 1, -1, -1):
		if float(_snaps[i].t) <= render_tick:
			a = _snaps[i]
			b = _snaps[mini(i + 1, _snaps.size() - 1)]
			break
	var span := float(b.t) - float(a.t)
	var f := 0.0 if span <= 0.0 else clampf((render_tick - float(a.t)) / span, 0.0, 1.0)
	if span <= 0.0 and render_tick > float(a.t):
		# Extrapolate a little when snapshots are late (at most 150 ms).
		var ex := minf((render_tick - float(a.t)) / Defs.TICK_RATE, 0.15)
		global_position = (a.pos as Vector3) + (a.vel as Vector3) * ex
	else:
		global_position = (a.pos as Vector3).lerp(b.pos, f)
	yaw = lerp_angle(float(a.yaw), float(b.yaw), f)
	pitch = lerpf(float(a.pitch), float(b.pitch), f)
	crouch = lerpf(float(a.crouch), float(b.crouch), f)
	mode = int(b.mode) if f > 0.5 else int(a.mode)
	flags = int(b.flags) if f > 0.5 else int(a.flags)
	velocity = (a.vel as Vector3).lerp(b.vel, f)
	weapon_id = str(b.weapon)
	chute_yaw = lerp_angle(float(a.get("cy", yaw)), float(b.get("cy", yaw)), f)
	apply_height()


func last_snapshot_age(render_tick: float) -> float:
	if _snaps.is_empty():
		return INF
	return (render_tick - float(_snaps[-1].t)) / Defs.TICK_RATE
