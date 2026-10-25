class_name Motor
## Character movement simulation. Pure function of (character state, command, dt) so the server, the owning
## client's prediction/replay and bots all run identical code.

enum { PLANE, FREEFALL, CHUTE, GROUND, DOWNED, DEAD, SPECTATE }

const B_JUMP := 1
const B_CROUCH := 2
const B_SPRINT := 4
const B_WALK := 8
const B_FIRE := 16
const B_AIM := 32
const B_RELOAD := 64
const B_USE := 128
const B_LIGHT := 256
const B_TAB := 512
const B_HEAL := 1024
const B_FIREMODE := 2048
const B_DROP := 4096
const B_PTT := 8192


static func step(ch, cmd: Dictionary, dt: float) -> void:
	ch.yaw = float(cmd.get("yaw", ch.yaw))
	ch.pitch = clampf(float(cmd.get("pitch", ch.pitch)), -1.45, 1.45)
	match ch.mode:
		PLANE:
			pass
		FREEFALL:
			_freefall(ch, cmd, dt)
		CHUTE:
			_chute(ch, cmd, dt)
		GROUND:
			_ground(ch, cmd, dt, false)
		DOWNED:
			_ground(ch, cmd, dt, true)
	ch.prev_buttons = int(cmd.get("btn", 0))


static func wish_dir(ch, cmd: Dictionary) -> Vector3:
	var mv := Vector2(float(cmd.get("mx", 0.0)), float(cmd.get("my", 0.0))).limit_length(1.0)
	var basis := Basis(Vector3.UP, ch.yaw)
	return basis * Vector3(mv.x, 0.0, -mv.y)


static func _ground(ch, cmd: Dictionary, dt: float, downed: bool) -> void:
	var btn := int(cmd.get("btn", 0))
	var water = ch.water_depth()
	# Stance
	var want_crouch := (btn & B_CROUCH) != 0 and not downed
	if want_crouch != ch.crouching:
		if want_crouch or ch.can_stand():
			ch.crouching = want_crouch
	var target_c := 1.0 if ch.crouching else 0.0
	if downed:
		target_c = 2.0
	ch.crouch = move_toward(ch.crouch, target_c, dt * 5.0)
	ch.apply_height()
	# Speed
	var speed := Defs.move("run_speed")
	var sprinting = (btn & B_SPRINT) != 0 and not ch.crouching and float(cmd.get("my", 0.0)) > 0.3 \
		and (btn & B_AIM) == 0 and ch.can_sprint()
	if downed:
		speed = Defs.move("crawl_speed")
	elif ch.crouching:
		speed = Defs.move("crouch_speed")
	elif (btn & B_WALK) != 0:
		speed = Defs.move("walk_speed")
	elif sprinting:
		speed = Defs.move("sprint_speed")
	if (btn & B_AIM) != 0 and not downed:
		speed *= Defs.move("aim_speed_mult")
	speed *= ch.speed_mult()
	if water > 1.15:
		speed = minf(speed, Defs.move("swim_speed"))
	elif water > 0.45:
		speed = minf(speed, Defs.move("wade_speed"))
	ch.sprinting = sprinting
	ch.walking = (btn & B_WALK) != 0
	var wish := wish_dir(ch, cmd) * speed
	var v: Vector3 = ch.velocity
	var on_floor: bool = ch.is_on_floor()
	var swimming = water > 1.15
	if swimming:
		# Treading water: slow, buoyant, no jumping.
		var target_y = (ch.water_surface() - 1.35) - ch.global_position.y
		v.y = move_toward(v.y, clampf(target_y * 2.0, -1.5, 1.5), dt * 6.0)
		v.x = move_toward(v.x, wish.x, dt * 3.0)
		v.z = move_toward(v.z, wish.z, dt * 3.0)
	elif on_floor:
		var accel := Defs.move("accel_ground")
		var hv := Vector3(v.x, 0.0, v.z)
		if wish.length() > 0.01:
			hv = hv.move_toward(wish, accel * dt)
		else:
			hv = hv.move_toward(Vector3.ZERO, Defs.move("friction_ground") * dt)
		v.x = hv.x
		v.z = hv.z
		if (btn & B_JUMP) != 0 and (ch.prev_buttons & B_JUMP) == 0 and not ch.crouching and not downed \
				and ch.jump_cooldown <= 0.0 and water < 0.6:
			v.y = Defs.move("jump_velocity")
			ch.jump_cooldown = 0.45
			ch.emit_motion_event("jump", 0.0)
		else:
			v.y = -0.5
	else:
		var hv := Vector3(v.x, 0.0, v.z)
		hv = hv.move_toward(wish if wish.length() > 0.01 else hv, Defs.move("accel_air") * dt)
		v.x = hv.x
		v.z = hv.z
		v.y -= Defs.move("gravity") * dt
		v.y = maxf(v.y, -55.0)
	ch.jump_cooldown = maxf(ch.jump_cooldown - dt, 0.0)
	var fall_speed := -v.y
	var was_air := not on_floor
	ch.velocity = v
	ch.move_body(dt)
	if was_air and ch.is_on_floor() and fall_speed > 2.0:
		ch.emit_motion_event("land", fall_speed)
	ch.land_timer = maxf(ch.land_timer - dt, 0.0)


static func _freefall(ch, cmd: Dictionary, dt: float) -> void:
	var d: Dictionary = Defs.rules.get("deploy", {})
	var wish := wish_dir(ch, cmd) * float(d.get("freefall_horizontal", 16.0))
	var v: Vector3 = ch.velocity
	var hv := Vector3(v.x, 0, v.z).move_toward(wish, 9.0 * dt)
	v.x = hv.x
	v.z = hv.z
	var term := float(d.get("freefall_speed", 52.0))
	if float(cmd.get("my", 0.0)) > 0.5:
		term *= 1.12  # diving
	v.y = move_toward(v.y, -term, 14.0 * dt)
	ch.velocity = v
	ch.freefall_t += dt
	var agl = ch.height_above_ground()
	var btn := int(cmd.get("btn", 0))
	var pressed_open = (btn & B_JUMP) != 0 and (ch.prev_buttons & B_JUMP) == 0
	if ch.freefall_t > float(d.get("min_freefall_s", 2.5)) and (pressed_open or agl < float(d.get("auto_open_agl", 110.0))):
		ch.mode = CHUTE
		ch.chute_yaw = ch.yaw
		ch.chute_t = 0.0
		ch.emit_motion_event("chute_open", 0.0)
	ch.move_body(dt, true)
	if ch.is_on_floor() or ch.water_depth() > 0.3:
		# Hit the ground without a canopy (only possible if something went badly wrong).
		ch.emit_motion_event("land", -v.y)
		ch.mode = GROUND


static func _chute(ch, cmd: Dictionary, dt: float) -> void:
	var d: Dictionary = Defs.rules.get("deploy", {})
	var btn := int(cmd.get("btn", 0))
	var my := float(cmd.get("my", 0.0))
	var mx := float(cmd.get("mx", 0.0))
	ch.chute_t += dt
	# Steering: A/D turn the canopy; the camera looks freely.
	ch.chute_yaw -= mx * deg_to_rad(float(d.get("chute_turn_deg_s", 55.0))) * dt
	var fwd := float(d.get("chute_forward", 8.5))
	var desc := float(d.get("chute_descent", 5.2))
	if my > 0.3:
		fwd = float(d.get("chute_forward_fast", 12.0))
		desc = float(d.get("chute_descent_fast", 7.6))
	elif my < -0.3:
		fwd = float(d.get("chute_forward_brake", 3.2))
		desc = float(d.get("chute_descent_brake", 3.6))
	var agl = ch.height_above_ground()
	# Flare: pulling both toggles (jump) near the ground converts speed into lift for a soft landing.
	if (btn & B_JUMP) != 0 and (ch.prev_buttons & B_JUMP) == 0 and ch.flare_t <= 0.0 and agl < float(d.get("flare_window_agl", 4.0)) * 2.5:
		ch.flare_t = float(d.get("flare_duration_s", 1.4))
		ch.emit_motion_event("flare", 0.0)
	if ch.flare_t > 0.0:
		ch.flare_t -= dt
		desc = float(d.get("flare_descent", 1.6))
		fwd *= 0.45
	# Opening shock: the first second bleeds the freefall speed.
	var v: Vector3 = ch.velocity
	var target := Basis(Vector3.UP, ch.chute_yaw) * Vector3(0, 0, -fwd)
	target.y = -desc
	var rate := 30.0 if ch.chute_t < 1.2 else 6.0
	v = v.move_toward(target, rate * dt)
	v += ch.chute_separation * dt
	ch.velocity = v
	ch.move_body(dt, true)
	var landed: bool = ch.is_on_floor()
	if ch.water_depth() > 0.5:
		landed = true
	if not landed and ch.get_slide_collision_count() > 0:
		ch.chute_snag_t += dt
		var limit := float(d.get("stuck_timeout_s", 2.0))
		if ch.chute_snag_t > limit:
			# Caught on a roof edge or a tree: cut away the canopy and drop the last metres.
			ch.mode = GROUND
			ch.emit_motion_event("chute_cut", 0.0)
			ch.chute_snag_t = 0.0
			return
	else:
		ch.chute_snag_t = 0.0
	if landed:
		ch.mode = GROUND
		ch.emit_motion_event("land", -v.y if ch.flare_t <= 0.0 else -v.y * 0.6)
		ch.emit_motion_event("chute_land", Vector3(v.x, 0, v.z).length())
