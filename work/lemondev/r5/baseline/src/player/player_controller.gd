extends Node
## Local player: samples input into commands, predicts the own character, reconciles with server snapshots,
## and drives the first-person camera and viewmodel.

const Viewmodel := preload("res://src/player/viewmodel.gd")
const PauseMenu := preload("res://src/ui/pause_menu.gd")
const Voice := preload("res://src/audio/voice.gd")
const TouchControls := preload("res://src/ui/touch_controls.gd")

var world = null
var ch: Character = null
var cam: Camera3D
var vm = null
var voice = null
var touch = null              # on-screen controls (phones, tablets, or touch_controls on)
var _touch_look := Vector2.ZERO

var yaw := 0.0
var pitch := 0.0
var seq := 0
var pending: Array = []      # [{cmd, state, wstate}]
var slot := 0
var crouch_toggled := false
var sprint_toggled := false
var tab_held := false
var map_held := false
var paused := false
var results := false
var spectating := -1
var _pause_ui: Control = null
var _climb_left := 0.0
var _yaw_left := 0.0
var _correction := Vector3.ZERO
var _bob_t := 0.0
var _land_jolt := 0.0
var _hit_shake := 0.0
var _cam_roll := 0.0
var _eye_smooth := 1.66
var _last_light_toggle := -10.0
var _mouse_delta := Vector2.ZERO
var stats := {"corrections": 0, "replayed": 0, "acks": 0, "max_error": 0.0}
## Taps seen as input events since the last command (bit per action); added to the next command so a press and
## release inside one render frame still reaches the server.
var _latched := 0
const LATCH := {"interact": Motor.B_USE, "reload": Motor.B_RELOAD, "heal": Motor.B_HEAL, "fire_mode": Motor.B_FIREMODE,
	"drop_held": Motor.B_DROP, "jump": Motor.B_JUMP, "fire": Motor.B_FIRE, "flashlight": Motor.B_LIGHT,
	"grab": Motor.B_GRAB, "ping": Motor.B_PING, "throw_grenade": Motor.B_THROW}
var _snap_ack := -1           # newest server state waiting to be reconciled in the next physics step
var _snap_own: Dictionary = {}


func setup(w, c: Character) -> void:
	world = w
	ch = c
	process_physics_priority = -10
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.near = 0.03
	cam.far = 1600.0
	cam.cull_mask = Defs.RENDER_WORLD | Defs.RENDER_VIEWMODEL | Defs.RENDER_CHARACTERS | Defs.RENDER_INTERIOR | Defs.RENDER_INTERIOR_PROPS
	cam.fov = float(Settings.get_value("graphics", "fov"))
	# Placed every frame from the character's interpolated transform: interpolating it again between physics
	# ticks would make it lag and step at the tick rate.
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(cam)
	cam.current = true
	SoundSys.listener_node = cam
	vm = Viewmodel.new()
	vm.name = "Viewmodel"
	cam.add_child(vm)
	vm.setup(world, ch, cam)
	voice = Voice.new()
	voice.name = "Voice"
	add_child(voice)
	voice.setup(world)
	if Settings.touch_active():
		var layer := CanvasLayer.new()
		layer.layer = 20
		add_child(layer)
		touch = TouchControls.new()
		layer.add_child(touch)
		touch.setup(self)
	yaw = ch.yaw
	pitch = 0.0
	Input.mouse_mode = Settings.play_mouse_mode()
	ch.motion_event.connect(_on_motion_event)
	Settings.changed.connect(func(s, k): if s == "graphics" and k == "fov": cam.fov = float(Settings.get_value("graphics", "fov")))


func _exit_tree() -> void:
	if cam and is_instance_valid(cam):
		cam.queue_free()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if paused or results:
		return
	for a in LATCH:
		if event.is_action_pressed(a):
			_latched |= int(LATCH[a])
	# Mouse look; touches also arrive as emulated mouse events (device -1), which must not turn the view.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse_delta += event.relative
	if event.is_action_pressed("weapon_1"):
		slot = 1
	elif event.is_action_pressed("weapon_2"):
		slot = 2
	elif event.is_action_pressed("weapon_3"):
		slot = 3
	elif event.is_action_pressed("holster"):
		slot = 0
	elif event.is_action_pressed("next_weapon") and not tab_held:
		slot = _cycle_slot(1)
	elif event.is_action_pressed("prev_weapon") and not tab_held:
		slot = _cycle_slot(-1)
	if event.is_action_pressed("crouch") and bool(Settings.get_value("controls", "crouch_toggle")):
		crouch_toggled = not crouch_toggled
	if event.is_action_pressed("sprint") and bool(Settings.get_value("controls", "sprint_toggle")):
		sprint_toggled = not sprint_toggled
	if event.is_action_pressed("text_chat") and world.hud:
		world.hud.open_text_chat()


func _cycle_slot(d: int) -> int:
	var s := slot
	for i in 4:
		s = (s + d + 4) % 4
		if s == 0 or (ch and ch.wpn.slots[s] != null):
			return s
	return slot


func _toggle_pause() -> void:
	if tab_held:
		return
	paused = not paused
	if paused:
		_pause_ui = PauseMenu.new()
		Game.ui.add_child(_pause_ui)
		_pause_ui.closed.connect(func(): paused = false; _pause_ui = null; Input.mouse_mode = Settings.play_mouse_mode())
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _pause_ui:
			_pause_ui.queue_free()
			_pause_ui = null
		Input.mouse_mode = Settings.play_mouse_mode()


func add_touch_look(rel: Vector2) -> void:
	## A finger dragging the view (screen units of the 1920x1080 layout).
	_touch_look += rel


func _look(dt: float) -> void:
	var sens := float(Settings.get_value("controls", "mouse_sensitivity")) * 0.01
	var tsens := float(Settings.get_value("controls", "touch_sensitivity")) * 0.01
	if ch and ch.wpn.ads > 0.5:
		var ads := float(Settings.get_value("controls", "ads_sensitivity")) / maxf(ch.wpn.zoom() * 0.75, 1.0)
		sens *= ads
		tsens *= ads
	var inv_y := -1.0 if bool(Settings.get_value("controls", "invert_y")) else 1.0
	if not tab_held:
		yaw -= _mouse_delta.x * sens + _touch_look.x * tsens
		pitch -= (_mouse_delta.y * sens + _touch_look.y * tsens) * inv_y
		var dz := float(Settings.get_value("controls", "gamepad_deadzone"))
		var stick := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_up", "look_down"))
		if stick.length() > dz:
			var gs := float(Settings.get_value("controls", "gamepad_sensitivity"))
			stick = stick * ((stick.length() - dz) / (1.0 - dz)) / stick.length()
			yaw -= stick.x * gs * dt
			pitch -= stick.y * gs * dt * inv_y
	_mouse_delta = Vector2.ZERO
	_touch_look = Vector2.ZERO
	# Recoil climb arrives over ~70 ms so the view kicks rather than teleports.
	if _climb_left > 0.0:
		var take := minf(_climb_left, maxf(_climb_left * dt * 18.0, dt * 8.0))
		pitch += deg_to_rad(take)
		_climb_left -= take
	if absf(_yaw_left) > 0.0:
		var ty := clampf(_yaw_left * dt * 18.0, -absf(_yaw_left), absf(_yaw_left))
		yaw -= deg_to_rad(ty)
		_yaw_left -= ty
	pitch = clampf(pitch, -1.45, 1.45)
	yaw = wrapf(yaw, -PI, PI)


func _build_cmd() -> Dictionary:
	var btn := 0
	var can_act := not paused and not results
	var mv := Vector2.ZERO
	if can_act:
		mv = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		tab_held = Input.is_action_pressed("smartab") or Input.is_action_pressed("map")
		map_held = Input.is_action_pressed("map")
		if Input.is_action_pressed("jump"):
			btn |= Motor.B_JUMP
		var crouch_on := crouch_toggled if bool(Settings.get_value("controls", "crouch_toggle")) else Input.is_action_pressed("crouch")
		if crouch_on:
			btn |= Motor.B_CROUCH
		var sprint_on := sprint_toggled if bool(Settings.get_value("controls", "sprint_toggle")) else Input.is_action_pressed("sprint")
		if sprint_on:
			btn |= Motor.B_SPRINT
		if mv.y <= 0.1:
			sprint_toggled = false
		if Input.is_action_pressed("walk"):
			btn |= Motor.B_WALK
		if not tab_held:
			if Input.is_action_pressed("fire"):
				btn |= Motor.B_FIRE
			if Input.is_action_pressed("aim"):
				btn |= Motor.B_AIM
			if Input.is_action_pressed("reload"):
				btn |= Motor.B_RELOAD
			if Input.is_action_pressed("interact"):
				btn |= Motor.B_USE
			if Input.is_action_pressed("grab"):
				btn |= Motor.B_GRAB
			if Input.is_action_pressed("heal"):
				btn |= Motor.B_HEAL
			if Input.is_action_pressed("fire_mode"):
				btn |= Motor.B_FIREMODE
			if Input.is_action_pressed("drop_held"):
				btn |= Motor.B_DROP
		if Input.is_action_pressed("flashlight"):
			btn |= Motor.B_LIGHT
		if tab_held:
			btn |= Motor.B_TAB
			# With the SmarTab up only the light, jump and ping taps carry through (weapon actions are blocked).
			btn |= _latched & (Motor.B_LIGHT | Motor.B_JUMP | Motor.B_PING)
		else:
			btn |= _latched
	else:
		tab_held = false
	_latched = 0
	return {"seq": seq, "mx": mv.x, "my": mv.y, "yaw": yaw, "pitch": pitch, "btn": btn, "slot": slot,
		"view_tick": int(Net.interp_tick()), "tick": Net.tick}


# ------------------------------------------------------------------ prediction

func _physics_process(dt: float) -> void:
	if ch == null or not is_instance_valid(ch):
		return
	if _snap_ack >= 0 and not world.is_server:
		var a := _snap_ack
		_snap_ack = -1
		_reconcile_now(a, _snap_own)
	_look(dt)
	seq += 1
	var cmd := _build_cmd()
	if world.is_server:
		# Host: the server simulates this character directly from the queue in the same tick.
		world.send_cmds([cmd])
		_after_step_effects(cmd, [])
		return
	# Predict
	ch.events.clear()
	ch.wpn.blocked = (cmd.btn & Motor.B_TAB) != 0 or ch.mode != Motor.GROUND or ch.water_depth() > 1.15 \
		or ch.held_prop_id >= 0 or ch.light.swapping() or (ch.flags & Character.F_BUSY) != 0 or ch.vault_t >= 0.0
	if cmd.btn & Motor.B_TAB:
		ch.flags |= Character.F_TAB
		ch.wpn.cancel_reload()
	else:
		ch.flags &= ~Character.F_TAB
	Motor.step(ch, cmd, dt)
	var shots := []
	if ch.mode == Motor.GROUND:
		shots = ch.wpn.step(cmd, dt, Net.tick)
		var lev: Array = ch.light.step(cmd, dt, false)
		if "on" in lev or "off" in lev:
			_last_light_toggle = Time.get_ticks_msec() / 1000.0
		for e in lev:
			if e in ["on", "off", "click_dead"]:
				SoundSys.play_local("flashlight_click")
	pending.append({"cmd": cmd, "state": ch.get_state(), "w": ch.wpn.get_state()})
	if pending.size() > 120:
		pending.pop_front()
	var redundancy := int(Defs.rule("net.input_redundancy", 4))
	var send := []
	for i in range(maxi(pending.size() - redundancy, 0), pending.size()):
		send.append(pending[i].cmd)
	world.send_cmds(send)
	_after_step_effects(cmd, shots)


func _after_step_effects(cmd: Dictionary, shots: Array) -> void:
	for s in shots:
		if s.get("dry", false):
			SoundSys.play_local("dry_fire")
			continue
		if world.effects:
			world.effects.shot(ch, s.origin, s.dir, float(s.velocity), str(s.ammo), str(s.weapon), int(s.seed), true)
		if vm:
			vm.on_fire()
	if world.is_server:
		# On the host the server already applied recoil into these pending values.
		pass
	_climb_left += ch.wpn.climb_pending
	_yaw_left += ch.wpn.yaw_pending
	ch.wpn.climb_pending = 0.0
	ch.wpn.yaw_pending = 0.0


func host_shot(s: Dictionary) -> void:
	## Host only: the server fired this character's weapon; show the same effects a predicting client would.
	if world.effects:
		world.effects.shot(ch, s.origin, s.dir, float(s.velocity), str(s.ammo), str(s.weapon), int(s.seed), true)
	if vm:
		vm.on_fire()


func reconcile(ack: int, own: Dictionary) -> void:
	## Called when a snapshot arrives (render frame). Kept until the next physics step: replaying commands calls
	## move_and_slide(), which only uses the physics delta inside a physics frame.
	if ack >= _snap_ack:
		_snap_ack = ack
		_snap_own = own


func _reconcile_now(ack: int, own: Dictionary) -> void:
	stats.acks += 1
	ch.injury_speed = float(own.injury_speed)
	ch.carry_speed = float(own.carry_speed)
	var server_flags := int(own.flags)
	ch.flags = (ch.flags & Character.F_TAB) | (server_flags & ~Character.F_TAB)
	if Time.get_ticks_msec() / 1000.0 - _last_light_toggle > 0.4:
		ch.light.on = bool(own.light_on)
	ch.light.swap_t = float(own.light_swap)
	var idx := -1
	for i in pending.size():
		if int(pending[i].cmd.seq) == ack:
			idx = i
			break
	if idx < 0:
		if pending.is_empty() or ack > int(pending[-1].cmd.seq):
			_hard_set(own)
			pending.clear()
		return
	var predicted: Dictionary = pending[idx].state
	if int(own.mode) == Motor.PLANE and int(predicted.mode) == Motor.PLANE:
		# Aboard the aircraft the server places everyone on its path; there is nothing to predict.
		pending = pending.slice(idx + 1)
		_hard_set(own)
		return
	var err := (predicted.pos as Vector3).distance_to(own.pos)
	stats.max_error = maxf(stats.max_error, err)
	var mode_diff := int(predicted.mode) != int(own.mode)
	var w_pred: Dictionary = pending[idx].w
	var w_diff := int(w_pred.mag) != int(own.wpn.mag) or int(w_pred.cur) != int(own.wpn.cur) or int(w_pred.state) != int(own.wpn.state) \
		or bool(w_pred.chamber) != bool(own.wpn.chamber)
	pending = pending.slice(idx + 1)
	if err < 0.04 and not mode_diff and not w_diff:
		return
	stats.corrections += 1
	if err > 0.25 and Game.arg("netdebug") != null:
		print("[netdebug] correction %.2f m at ack %d (pending %d): predicted %s vel %s mode %d / server %s vel %s mode %d" % [err, ack,
			pending.size(), str((predicted.pos as Vector3).snapped(Vector3.ONE * 0.01)), str((predicted.vel as Vector3).snapped(Vector3.ONE * 0.01)),
			int(predicted.mode), str((own.pos as Vector3).snapped(Vector3.ONE * 0.01)), str((own.vel as Vector3).snapped(Vector3.ONE * 0.01)), int(own.mode)])
	var before := ch.global_position
	_hard_set(own)
	ch.replaying = true
	for p in pending:
		var c: Dictionary = p.cmd
		ch.events.clear()
		Motor.step(ch, c, Defs.TICK_DT)
		if ch.mode == Motor.GROUND:
			ch.wpn.step(c, Defs.TICK_DT, int(c.tick))
		p.state = ch.get_state()
		p.w = ch.wpn.get_state()
		stats.replayed += 1
	ch.replaying = false
	ch.wpn.climb_pending = 0.0
	ch.wpn.yaw_pending = 0.0
	if not mode_diff:
		_correction += before - ch.global_position


func _hard_set(own: Dictionary) -> void:
	ch.set_state({"pos": own.pos, "vel": own.vel, "mode": int(own.mode), "crouch": float(own.crouch), "crouching": bool(own.crouching),
		"jcd": float(own.jcd), "ff": float(own.ff), "ct": float(own.ct), "cy": float(own.cy), "fl": float(own.fl), "pb": int(own.pb),
		"vt": float(own.get("vt", -1.0)), "vd": float(own.get("vd", 0.5)), "va": own.get("va", Vector3.ZERO), "vm": own.get("vm", Vector3.ZERO),
		"vb": own.get("vb", Vector3.ZERO), "vh": float(own.get("vh", 1.78))})
	ch.wpn.set_state(own.wpn)


func on_mode_forced(mode: int) -> void:
	pending.clear()
	_correction = Vector3.ZERO
	if mode == Motor.DOWNED:
		slot = 0


func on_local_died() -> void:
	ch = null
	pending.clear()
	if vm:
		vm.visible = false
	if world.hud:
		world.hud.on_local_died()
	_pick_spectate()


func _pick_spectate() -> void:
	spectating = -1
	var my_team := int(Net.players.get(Net.local_pid, {}).get("team", -1))
	for c in world.characters.values():
		if c.team == my_team and c.mode not in [Motor.DEAD, Motor.SPECTATE]:
			spectating = c.eid
			return
	for c in world.characters.values():
		if c.mode not in [Motor.DEAD, Motor.SPECTATE]:
			spectating = c.eid
			return


func set_results_mode(on: bool) -> void:
	results = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Settings.play_mouse_mode()


func on_suppressed(dist: float) -> void:
	## A near miss: a small flinch of the view (much less than being hit).
	_hit_shake = minf(_hit_shake + 0.18 * clampf(1.0 - dist / 2.2, 0.2, 1.0), 0.6)


func on_hit(part: String, dir: Vector3, damage: float, absorbed: String) -> void:
	_hit_shake = minf(_hit_shake + 0.3 + damage * 0.02, 1.2)
	if vm:
		vm.on_hit(damage)


func _on_motion_event(kind: String, value: float) -> void:
	match kind:
		"land":
			_land_jolt = clampf(value / 9.0, 0.0, 1.0)
		"ladder":
			if not world.is_server:
				SoundSys.play_at("ladder_step", ch.global_position + Vector3.UP * 0.9)
		"jump":
			pass


# ------------------------------------------------------------------ camera

func _process(dt: float) -> void:
	if ch == null or not is_instance_valid(ch):
		_spectate_camera(dt)
		return
	if world.hud:
		world.hud.tab_held = tab_held
		world.hud.map_held = map_held
	_correction = _correction.lerp(Vector3.ZERO, clampf(dt * 12.0, 0.0, 1.0))
	var motion := str(Settings.get_value("accessibility", "camera_motion"))
	var motion_k := 1.0 if motion == "normal" else (0.35 if motion == "reduced" else 0.0)
	var base: Vector3 = ch.get_global_transform_interpolated().origin + _correction
	var eye_h := ch.height() - Defs.move("eye_offset")
	_eye_smooth = lerpf(_eye_smooth, eye_h, clampf(dt * 14.0, 0.0, 1.0))
	var pos := base + Vector3.UP * _eye_smooth
	# Head bob and injured gait
	var hv := Vector2(ch.velocity.x, ch.velocity.z).length()
	var on_floor := ch.is_on_floor() and ch.mode in [Motor.GROUND, Motor.DOWNED]
	var bob := Vector3.ZERO
	var roll := 0.0
	if on_floor and hv > 0.3:
		var stride := 0.9 + hv * 0.12
		_bob_t += dt * hv / stride * PI
		bob.y = sin(_bob_t * 2.0) * 0.025 * clampf(hv / 4.0, 0.3, 1.3)
		bob.x = sin(_bob_t) * 0.018
		var limp: float = ch.health.limp_side() if ch.health and ch.health.has_method("limp_side") else 0.0
		if limp != 0.0:
			# Uneven gait: the injured leg's step dips harder and rolls the head toward it.
			var phase := sin(_bob_t + (0.0 if limp > 0.0 else PI))
			bob.y -= maxf(phase, 0.0) * 0.045 * (2.0 - ch.injury_speed)
			roll += maxf(phase, 0.0) * 0.022 * limp
	_land_jolt = move_toward(_land_jolt, 0.0, dt * 3.0)
	bob.y -= sin(_land_jolt * PI) * 0.08
	_hit_shake = move_toward(_hit_shake, 0.0, dt * 2.5)
	var shake := Vector3(sin(Time.get_ticks_msec() * 0.031), sin(Time.get_ticks_msec() * 0.027), 0) * _hit_shake * 0.01
	pos += Basis(Vector3.UP, yaw) * (bob * motion_k)
	_cam_roll = lerpf(_cam_roll, roll * motion_k, clampf(dt * 8.0, 0.0, 1.0))
	var p_view := pitch
	var y_view := yaw
	if ch.mode == Motor.PLANE:
		_plane_camera(dt)
		return
	if vm and not vm.visible:
		vm.visible = true
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(p_view + shake.y * motion_k, y_view + shake.x * motion_k, _cam_roll)), pos)
	var zoom: float = lerpf(1.0, ch.wpn.zoom(), ch.wpn.ads) if ch.wpn else 1.0
	cam.fov = float(Settings.get_value("graphics", "fov")) / zoom
	if vm:
		vm.update_view(dt, tab_held, map_held)


func _plane_camera(dt: float) -> void:
	var target: Vector3 = world.plane_pos(Net.interp_tick() if not world.is_server else float(Net.tick))
	var b := Basis.from_euler(Vector3(pitch, yaw, 0))
	cam.global_transform = Transform3D(b, target - b.z * -1.0 * 0.0 + b * Vector3(0, 6, 22))
	cam.fov = float(Settings.get_value("graphics", "fov"))
	if vm:
		vm.visible = false


func _spectate_camera(dt: float) -> void:
	if cam == null:
		return
	if not world.characters.has(spectating):
		_pick_spectate()
	var t = world.characters.get(spectating)
	if t == null:
		return
	_look(dt)
	var b := Basis.from_euler(Vector3(clampf(pitch, -1.0, 0.6), yaw, 0))
	var focus: Vector3 = t.get_global_transform_interpolated().origin + Vector3.UP * 1.6
	var desired := focus + b * Vector3(0.4, 0.3, 3.2)
	var space = world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, desired, Defs.SIGHT_MASK)
	var r = space.intersect_ray(q)
	if not r.is_empty():
		desired = (r.position as Vector3).lerp(focus, 0.1)
	cam.global_transform = Transform3D(b, desired)
	if world.hud:
		world.hud.set_spectating(t)


