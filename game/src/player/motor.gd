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
const B_GRAB := 16384
const B_PING := 32768
const B_THROW := 65536
const B_ACTION_BLOCKED := 131072  # menus/results suppress weapon actions on every peer
const B_LASER := 262144           # laser pointer held
const LadderMove := preload("res://src/player/ladder.gd")


static var legacy = null   # tests only (r12 before/after captures): the r11 motor script runs instead


static func step(ch, cmd: Dictionary, dt: float) -> void:
	if legacy != null:
		legacy.step(ch, cmd, dt)
		return
	ch.yaw = float(cmd.get("yaw", ch.yaw))
	ch.pitch = clampf(float(cmd.get("pitch", ch.pitch)), -1.45, 1.45)
	match ch.mode:
		PLANE:
			if ch.world and ch.world.has_method("plane_pos") and not ch.world.match_info.is_empty():
				ch.global_position = ch.world.plane_pos(float(cmd.get("tick", 0)))
				ch.velocity = Vector3.ZERO
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
	var pressed = btn & ~ch.prev_buttons
	ch.pk_cd = maxf(ch.pk_cd - dt, 0.0)
	var fi := Field.for_cmd(ch, cmd)
	var in_field := bool(fi.on)
	if ch.vault_t >= 0.0:
		Vault.step(ch, dt)
		return
	if ch.ledge_t >= 0.0:
		if in_field or downed:
			Parkour.let_go(ch, 0.0)   # the field tears the hands off the edge
		elif Parkour.hang_step(ch, cmd, dt):
			return
	if not downed and not in_field:
		var ld := LadderMove.find(ch)
		if LadderMove.wants(ch, cmd, ld):
			LadderMove.step(ch, cmd, dt, ld)
			return
	var water = ch.water_depth()
	# Too deep to jump: push into a wall whose top is within reach and the hands catch it (a canal's coping).
	if water >= 0.6 and not downed and not in_field and Parkour.water_grab(ch, cmd, water):
		return
	var v: Vector3 = ch.velocity
	var on_floor: bool = ch.is_on_floor()
	var hv := Vector3(v.x, 0.0, v.z)
	# Slide: Crouch at a sprint.
	if on_floor and not downed and water < 0.45 and ch.held_prop_id < 0:
		Parkour.try_slide(ch, cmd, hv)
	# Stance (a slide or a roll holds the body low)
	var want_crouch := (btn & B_CROUCH) != 0 and not downed
	if ch.slide_t >= 0.0:
		want_crouch = true
	if want_crouch != ch.crouching and ch.roll_t < 0.0:
		if want_crouch or ch.can_stand():
			ch.crouching = want_crouch
	var target_c := 1.0 if ch.crouching else 0.0
	if downed:
		target_c = 2.0
	ch.crouch = move_toward(ch.crouch, target_c, dt * (9.0 if ch.slide_t >= 0.0 else 5.0))
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
	if (ch.flags & Character.F_HEAL) != 0 and not sprinting:
		speed = minf(speed, Defs.move("walk_speed"))   # treating a wound: a slow walk at most
	speed *= ch.speed_mult()
	if ch.land_timer > 0.0:
		speed *= lerpf(1.0, 0.45, clampf(ch.land_timer / 0.5, 0.0, 1.0))   # a hard landing: a stumble
	if water > 1.15:
		speed = minf(speed, Defs.move("swim_speed"))
	elif water > 0.45:
		speed = minf(speed, Defs.move("wade_speed"))
	ch.sprinting = sprinting and ch.slide_t < 0.0
	ch.walking = (btn & B_WALK) != 0
	var stick := Vector2(float(cmd.get("mx", 0.0)), float(cmd.get("my", 0.0))).limit_length(1.0)
	var wd := wish_dir(ch, cmd)
	var wish := wd * speed
	var swimming = water > 1.15
	if swimming:
		# Treading water: slow, buoyant, no jumping.
		var target_y = (ch.water_surface() - 1.35) - ch.global_position.y
		v.y = move_toward(v.y, clampf(target_y * 2.0, -1.5, 1.5), dt * 6.0)
		v.x = move_toward(v.x, wish.x, dt * 3.0)
		v.z = move_toward(v.z, wish.z, dt * 3.0)
		ch.slide_t = -1.0
		ch.air_t = 0.0
	elif on_floor:
		ch.air_t = 0.0
		if ch.slide_t >= 0.0:
			hv = Parkour.slide_step(ch, cmd, hv, dt)
		elif ch.roll_t >= 0.0:
			hv = Parkour.roll_step(ch, hv, dt)
		else:
			hv = run(hv, wd, speed * stick.length(), dt)
		v.x = hv.x
		v.z = hv.z
		var jump_press: bool = ((pressed & B_JUMP) != 0 or ch.jump_buf >= 0.0) and not downed \
				and ch.jump_cooldown <= 0.0 and water < 0.6 and ch.roll_t < 0.0
		ch.jump_buf = -1.0
		var vault := Vault.find(ch) if jump_press and ch.held_prop_id < 0 else {}
		if not vault.is_empty() and float(vault.get("drop", 0.0)) > 3.0 and Net.is_bot(ch.pid):
			vault = {}   # (r17) a bot does not vault off a balcony into a long drop
		if not vault.is_empty():
			# Close to something low enough to get over or through: vault instead of jumping.
			Vault.start(ch, vault)
			ch.jump_cooldown = 0.3
			return
		if jump_press and (not ch.crouching or ch.slide_t >= 0.0) and ch.can_stand():
			ch.crouching = false
			v = Parkour.ground_jump(ch, cmd, hv, wd, v)
			ch.jump_cooldown = 0.45
		else:
			v.y = -0.5
	else:
		ch.air_t += dt
		ch.slide_t = -1.0
		# Running off an edge, Jump still works for a moment (coyote time); pressed just before landing, it waits.
		if (pressed & B_JUMP) != 0 and not downed:
			if ch.air_t < Defs.move("coyote_s") and ch.jump_cooldown <= 0.0 and v.y <= 0.5 and water < 0.6:
				v = Parkour.ground_jump(ch, cmd, hv, wd, v)
				ch.jump_cooldown = 0.45
			else:
				ch.jump_buf = 0.0
		elif ch.jump_buf >= 0.0:
			ch.jump_buf += dt
			if ch.jump_buf > Defs.move("jump_buffer_s"):
				ch.jump_buf = -1.0
		if not downed:
			var pk := Parkour.air_step(ch, cmd, dt, v)
			if pk == Parkour.GRABBED:
				return
			if pk == Parkour.KICKED:
				v = ch.velocity
		hv = Vector3(v.x, 0.0, v.z)
		# Little control in the air: a body cannot push off nothing.
		hv = hv.move_toward(wish if wish.length() > 0.01 else hv, Defs.move("accel_air") * dt)
		v.x = hv.x
		v.z = hv.z
		v.y -= Defs.move("gravity") * dt
		v.y = maxf(v.y, -55.0)
	# The forcefield: nothing moves out into it, and it carries the body in.
	if in_field:
		v = Field.apply(fi, v)
		ch.slide_t = -1.0
	ch.jump_cooldown = maxf(ch.jump_cooldown - dt, 0.0)
	var fall_speed := -v.y
	var was_air := not on_floor
	# (r15) Escalators: the steps carry whoever stands on them. The body makes its own move, then rides the belt's
	# travel as a plain translation along the lane (the controller's step-up and slope logic fought a belt fed in as
	# velocity at the top of a down escalator). The map answers from geometry alone (MallLayout.belt_at), so the
	# server, the shooter's own prediction and the bots agree.
	var belt := Vector3.ZERO
	if on_floor and ch.world and ch.world.get("map") != null:
		belt = ch.world.map.belt_at(ch.global_position)
	ch.velocity = v
	ch.wish_h = Vector3(wish.x, 0.0, wish.z)
	var before: Vector3 = ch.global_position
	ch.move_body(dt)
	if belt != Vector3.ZERO:
		ch.global_position += belt * dt
	Field.note_progress(ch, fi, before, dt)
	if was_air and ch.is_on_floor() and fall_speed > 2.0:
		_landed(ch, cmd, fall_speed, downed)
	ch.land_timer = maxf(ch.land_timer - dt, 0.0)


static func run(hv: Vector3, wd: Vector3, target: float, dt: float) -> Vector3:
	## One step of running on the ground, like a body rather than a cursor: speed builds up (quickly at first, slowly
	## near the top), the part of the motion that is not along the stick is shed by the feet's grip (a hard turn
	## costs the built-up speed and the run starts again), going the other way first brakes to a stop, and with no
	## input the body brakes over a step or two instead of stopping dead.
	var sprint := Defs.move("sprint_speed")
	if target > 0.01 and wd.length_squared() > 1e-4:
		var dir := wd.normalized()
		var along := hv.dot(dir)
		var perp := hv - dir * along
		perp = perp.move_toward(Vector3.ZERO, Defs.move("turn_grip") * dt)
		if along < 0.0:
			along = minf(along + Defs.move("brake_slow") * dt, 0.0)
		elif along < target:
			var a := lerpf(Defs.move("accel_start"), Defs.move("accel_top"), clampf(along / sprint, 0.0, 1.0))
			along = minf(along + a * dt, target)
		else:
			along = move_toward(along, target, Defs.move("brake_fast") * dt)
		return dir * along + perp
	var s := hv.length()
	var decel := lerpf(Defs.move("brake_slow"), Defs.move("brake_fast"), clampf(s / sprint, 0.0, 1.0))
	return hv.move_toward(Vector3.ZERO, decel * dt)


static func _landed(ch, cmd: Dictionary, fall_speed: float, downed: bool) -> void:
	## Touch-down. Holding Crouch from a real drop rolls (the server takes less fall damage for "land_roll");
	## a hard landing without it stumbles for a moment.
	var btn := int(cmd.get("btn", 0))
	var h := fall_speed * fall_speed / (2.0 * Defs.move("gravity"))
	ch.pk_bits &= ~(Parkour.PK_WALLRUN | Parkour.PK_SPRINT_JUMP)
	if not downed and (btn & B_CROUCH) != 0 and h > 1.6 and ch.water_depth() < 0.45:
		var v: Vector3 = ch.velocity
		var hv := Parkour.start_roll(ch, Vector3(v.x, 0.0, v.z))
		ch.velocity = Vector3(hv.x, v.y, hv.z)
		ch.emit_motion_event("land_roll", fall_speed)
		return
	if h > 3.2:
		ch.land_timer = clampf((h - 3.2) / 5.0, 0.15, 0.6)
	ch.emit_motion_event("land", fall_speed)


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
	# With nothing below (off the edge of the map) the altitude itself decides.
	var low: bool = agl < float(d.get("auto_open_agl", 110.0)) or (agl > 590.0 and ch.global_position.y < 120.0)
	if ch.freefall_t > float(d.get("min_freefall_s", 2.5)) and (pressed_open or low):
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
		# Brushing a wall, a roof edge or a tree: the canopy drags the jumper off it and the descent continues.
		var away := Vector3.ZERO
		for i in ch.get_slide_collision_count():
			away += ch.get_slide_collision(i).get_normal()
		away.y = 0.0
		if away.length_squared() > 1e-4:
			away = away.normalized()
			ch.velocity += away * 3.0 * dt * 10.0
		var limit := float(d.get("stuck_timeout_s", 2.0))
		if ch.chute_snag_t > limit and agl < 3.2:
			# Hung up just above the ground: cut away the canopy and drop the last metre or two.
			ch.mode = GROUND
			ch.emit_motion_event("chute_cut", 0.0)
			ch.chute_snag_t = 0.0
			return
		if ch.chute_snag_t > limit * 2.0 and away != Vector3.ZERO:
			# Still caught high up: the wind pulls the canopy free.
			ch.global_position += away * 0.5
			ch.chute_snag_t = 0.0
	else:
		ch.chute_snag_t = 0.0
	if landed:
		ch.mode = GROUND
		ch.emit_motion_event("land", -v.y if ch.flare_t <= 0.0 else -v.y * 0.6)
		ch.emit_motion_event("chute_land", Vector3(v.x, 0, v.z).length())
