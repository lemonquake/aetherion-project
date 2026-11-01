extends Node
## Local player: samples input into commands, predicts the own character, reconciles with server snapshots,
## and drives the first-person camera and viewmodel.

const Viewmodel := preload("res://src/player/viewmodel.gd")
const PauseMenu := preload("res://src/ui/pause_menu.gd")
const Workbench := preload("res://src/ui/workbench_ui.gd")
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
var laser_held := false      # the laser pointer is up (drawn at once by fx/lasers.gd; the server hears B_LASER)
var laser_toggled := false   # touch: the Laser button toggles it
var paused := false
var results := false
var spectating := -1
## r24 spectator options. Views: behind the player, close over the shoulder, from high above, or a free camera (a
## solo host only). Watching everyone (enemies too) is allowed when no other human is in the match (alone vs bots).
enum SpectView { BEHIND, SHOULDER, OVERHEAD, FREE }
const SPECT_VIEW_NAMES := ["Behind", "Over the shoulder", "Overhead", "Free camera"]
var spect_view := SpectView.BEHIND
var spect_all := false
var _free_pos := Vector3.ZERO
var _pause_ui: Control = null
var workbench: Control = null    # (r24) the attachment workbench while it is open (K)
var _climb_left := 0.0
var _yaw_left := 0.0
var _correction := Vector3.ZERO
const GAIT_BOB := 0.5  # head bob, sway and limp roll while walking/running, relative to the old amount
var _bob_t := 0.0
var _land_jolt := 0.0
var _hit_shake := 0.0
## A hit punches the view (pitch, yaw, roll in radians): it snaps away in 50 ms and settles by about 0.4 s, the same at
## any frame rate. The view only: where the gun points is unchanged.
var _kicks: Array = []       # [seconds, Vector3 peak]
const KICK_RISE := 0.05
var _cam_roll := 0.0
var _eye_smooth := 1.66
## r12 body feel: the head leans with the body's acceleration (forward when setting off, back when braking, into a
## hard turn), tips sideways in a slide, and goes over in a landing roll.
var _prev_vel := Vector3.ZERO
var _acc_smooth := Vector3.ZERO
var _lean := Vector2.ZERO        # pitch, roll (radians)
var _slide_k := 0.0
var _roll_view_t := -1.0
var _climb_k := 0.0
var _last_light_toggle := -10.0
var _mouse_delta := Vector2.ZERO
var stats := {"corrections": 0, "replayed": 0, "acks": 0, "max_error": 0.0, "err_sum": 0.0, "err_n": 0}
## Taps seen as input events since the last command (bit per action); added to the next command so a press and
## release inside one render frame still reaches the server.
var _latched := 0
var cook_t := -1.0             # r14: seconds since this player pulled a grenade pin (own prediction), -1 none
var _throw_was := false
var _fire_release_required := false
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


func setup_spectator(w) -> void:
	## r7: no character of our own in this match (joined late, or came back after dying): only the spectator
	## camera, following the living (teammates first), cycled like a dead player's.
	world = w
	ch = null
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.near = 0.03
	cam.far = 1600.0
	cam.cull_mask = Defs.RENDER_WORLD | Defs.RENDER_CHARACTERS | Defs.RENDER_INTERIOR | Defs.RENDER_INTERIOR_PROPS
	cam.fov = float(Settings.get_value("graphics", "fov"))
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(cam)
	cam.current = true
	SoundSys.listener_node = cam
	voice = Voice.new()
	voice.name = "Voice"
	add_child(voice)
	voice.setup(world)
	Input.mouse_mode = Settings.play_mouse_mode()
	if world.hud:
		world.hud.on_local_died()
	_pick_spectate()


func _exit_tree() -> void:
	if cam and is_instance_valid(cam):
		cam.queue_free()
	# The pause menu lives under Game.UI, not under this controller: leaving the match must take it down too.
	for ui in [_pause_ui, workbench]:
		if ui and is_instance_valid(ui):
			if ui.get_parent():
				ui.get_parent().remove_child(ui)
			ui.queue_free()
	_pause_ui = null
	workbench = null
	paused = false


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if paused or results:
		return
	if ch == null:
		# Spectating: fire / jump / next weapon watch the next teammate, aim / previous weapon the one before.
		# r24: E changes the camera view, R switches between teammates and everyone (alone vs bots).
		if event.is_action_pressed("fire") or (event.is_action_pressed("jump") and spect_view != SpectView.FREE) or event.is_action_pressed("next_weapon"):
			spectate_cycle(1)
		elif event.is_action_pressed("aim") or event.is_action_pressed("prev_weapon"):
			spectate_cycle(-1)
		elif event.is_action_pressed("interact"):
			spectate_next_view()
		elif event.is_action_pressed("reload"):
			spectate_toggle_all()
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
		if not (ch and ch.wpn.ads > 0.5 and ch.wpn.step_zoom(-1)):
			slot = _cycle_slot(1)
	elif event.is_action_pressed("prev_weapon") and not tab_held:
		if not (ch and ch.wpn.ads > 0.5 and ch.wpn.step_zoom(1)):
			slot = _cycle_slot(-1)
	if event.is_action_pressed("crouch") and bool(Settings.get_value("controls", "crouch_toggle")):
		crouch_toggled = not crouch_toggled
	if event.is_action_pressed("sprint") and bool(Settings.get_value("controls", "sprint_toggle")):
		sprint_toggled = not sprint_toggled
	if event.is_action_pressed("text_chat") and world.hud:
		world.hud.open_text_chat()
	if event.is_action_pressed("workbench") and ch != null and not tab_held:
		open_workbench()


func open_workbench() -> void:
	## (r24) The attachment workbench over the match (which goes on): the player stands still while it is open.
	if workbench and is_instance_valid(workbench):
		return
	var start = slot if slot in [1, 2, 3] and ch.wpn.slots[slot] != null else null
	workbench = Workbench.new(Workbench.MatchSource.new(world), start)
	Game.ui.add_child(workbench)
	paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	workbench.closed.connect(func():
		workbench = null
		paused = false
		if not results:
			Input.mouse_mode = Settings.play_mouse_mode())


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
	var can_act := not paused and not results and (world == null or str(world.match_info.get("phase", "")) not in ["round_end", "ended"])
	var mv := Vector2.ZERO
	if can_act:
		mv = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		var touch_sprint := false
		if touch and touch.stick_held():
			# (r15) The on-screen stick as it is: get_vector's dead zone remap made a phone run at walking pace.
			mv = touch.move_vector()
			touch_sprint = touch.sprint_wanted()
		tab_held = Input.is_action_pressed("smartab") or Input.is_action_pressed("map")
		map_held = Input.is_action_pressed("map")
		if Input.is_action_pressed("jump"):
			btn |= Motor.B_JUMP
		var crouch_on := crouch_toggled if bool(Settings.get_value("controls", "crouch_toggle")) else Input.is_action_pressed("crouch")
		if crouch_on:
			btn |= Motor.B_CROUCH
		var sprint_on := sprint_toggled if bool(Settings.get_value("controls", "sprint_toggle")) else Input.is_action_pressed("sprint")
		if sprint_on or touch_sprint:
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
			if Input.is_action_pressed("laser") or laser_toggled:
				btn |= Motor.B_LASER
			# r14: the grenade key is held while cooking (the latch below still catches a quick tap).
			if Input.is_action_pressed("throw_grenade"):
				btn |= Motor.B_THROW
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
		btn |= Motor.B_ACTION_BLOCKED
		if Input.is_action_pressed("fire"):
			_fire_release_required = true
	if _fire_release_required:
		btn &= ~Motor.B_FIRE
		if not Input.is_action_pressed("fire"):
			_fire_release_required = false
	_latched = 0
	_cook_input((btn & Motor.B_THROW) != 0)
	laser_held = (btn & Motor.B_LASER) != 0 and ch != null and ch.mode == Motor.GROUND
	return {"seq": seq, "mx": mv.x, "my": mv.y, "yaw": yaw, "pitch": pitch, "btn": btn, "slot": slot,
		"view_tick": int(Net.interp_tick()), "tick": Net.tick}


# ------------------------------------------------------------------ prediction

func _physics_process(dt: float) -> void:
	if results or ch == null or not is_instance_valid(ch):
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
	_weapon_intent(cmd)
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


func _cook_input(down: bool) -> void:
	## r14: the fuse clock the HUD and the hands show: starts when the pin is pulled (the key goes down with a grenade
	## carried), stops when it is thrown (key up) or has gone off.
	if down and not _throw_was and cook_t < 0.0 and ch and ch.mode == Motor.GROUND and ch.held_prop_id < 0 \
			and ch.inv and ch.inv.count("frag_grenade") > 0 and not tab_held:
		cook_t = 0.0
	elif cook_t >= 0.0 and not down:
		cook_t = -1.0
	_throw_was = down


func _weapon_intent(cmd: Dictionary) -> void:
	# Reapply the same weapon blockers during prediction and authoritative replay.
	ch.wpn.blocked = (cmd.btn & (Motor.B_TAB | Motor.B_ACTION_BLOCKED)) != 0 or ch.mode != Motor.GROUND or ch.water_depth() > 1.15 \
		or ch.held_prop_id >= 0 or ch.light.swapping() or (ch.flags & Character.F_BUSY) != 0 or ch.vault_t >= 0.0 or ch.ledge_t >= 0.0 or ch.roll_t >= 0.0 or cook_t >= 0.0 or (ch.flags & Character.F_COOK) != 0
	if cmd.btn & Motor.B_TAB:
		ch.flags |= Character.F_TAB
		ch.wpn.cancel_reload()
	else:
		ch.flags &= ~Character.F_TAB


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
	stats.err_sum += err
	stats.err_n += 1
	var mode_diff := int(predicted.mode) != int(own.mode)
	var w_pred: Dictionary = pending[idx].w
	var w_diff := int(w_pred.mag) != int(own.wpn.mag) or int(w_pred.cur) != int(own.wpn.cur) or int(w_pred.state) != int(own.wpn.state) \
		or bool(w_pred.chamber) != bool(own.wpn.chamber) or int(w_pred.mode) != int(own.wpn.mode) \
		or int(w_pred.get("bl", 0)) != int(own.wpn.get("bl", 0)) or bool(w_pred.pf) != bool(own.wpn.pf) \
		or bool(w_pred.pm) != bool(own.wpn.pm) or bool(w_pred.pr) != bool(own.wpn.pr) \
		or bool(w_pred.get("rq", false)) != bool(own.wpn.get("rq", false)) or int(w_pred.shots) != int(own.wpn.shots)
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
		_weapon_intent(c)
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
		"vb": own.get("vb", Vector3.ZERO), "vh": float(own.get("vh", 1.78)), "vs": float(own.get("vs", 0.0)),
		"at": float(own.get("at", 0.0)), "jb": float(own.get("jb", -1.0)), "st": float(own.get("st", -1.0)), "rt": float(own.get("rt", -1.0)),
		"lt": float(own.get("lt", -1.0)), "lp": own.get("lp", Vector3.ZERO), "ln": own.get("ln", Vector3.ZERO), "ly": float(own.get("ly", 0.0)),
		"pk": int(own.get("pk", 0)), "pc": float(own.get("pc", 0.0))})
	ch.wpn.set_state(own.wpn)


func on_mode_forced(mode: int) -> void:
	pending.clear()
	_correction = Vector3.ZERO
	if ch and mode != Motor.GROUND:
		ch.wpn.cancel_burst()
	if mode == Motor.DOWNED:
		slot = 0


# r13: after dying, the camera stays on your body for a few seconds (third person) before spectating a teammate.
const DEATH_CAM_S := 6.0
var _death: Dictionary = {}   # {t (s), pos, yaw, killer_pos}


func on_death_report(info: Dictionary) -> void:
	_death = {"t": Time.get_ticks_msec() / 1000.0, "pos": info.get("pos", Vector3.ZERO), "yaw": float(info.get("yaw", yaw)),
		"killer_pos": info.get("killer_pos", Vector3.INF)}


func on_local_died() -> void:
	if ch:
		ch.wpn.cancel_burst()
		var now := Time.get_ticks_msec() / 1000.0
		if _death.is_empty() or now - float(_death.t) > 2.0:
			_death = {"t": now, "pos": ch.global_position, "yaw": ch.yaw, "killer_pos": Vector3.INF}
	ch = null
	pending.clear()
	if vm:
		vm.visible = false
	if world.hud:
		world.hud.on_local_died()
	_pick_spectate()


func _pick_spectate() -> void:
	spectating = -1
	var list := spectate_candidates()
	if not list.is_empty():
		_set_spectate(int(list[0]))


func spectate_candidates() -> Array:
	## Who a dead player can watch: living teammates (bots included); when none is left, any living player.
	var my_team := int(Net.players.get(Net.local_pid, {}).get("team", -1))
	var mates := []
	var others := []
	for c in world.characters.values():
		if c.mode in [Motor.DEAD, Motor.SPECTATE]:
			continue
		if c.team == my_team:
			mates.append(c.eid)
		else:
			others.append(c.eid)
	mates.sort()
	others.sort()
	if spect_all and can_watch_enemies():
		return mates + others
	return mates if not mates.is_empty() else others


func can_watch_enemies() -> bool:
	## Watching the other teams is fair only when no other human is playing (it would show where they are).
	return Net.humans() <= 1


func can_free_camera() -> bool:
	## The free camera can fly anywhere: only on a solo host, which simulates the whole map (a client is sent only
	## what is around the player it watches).
	return can_watch_enemies() and world != null and world.is_server


func spectate_next_view() -> void:
	var n := SPECT_VIEW_NAMES.size() if can_free_camera() else SPECT_VIEW_NAMES.size() - 1
	spect_view = (spect_view + 1) % n
	if spect_view == SpectView.FREE and cam:
		_free_pos = cam.global_position
		var e := cam.global_transform.basis.get_euler()
		pitch = clampf(e.x, -1.4, 1.4)
		yaw = e.y
	if world.hud:
		world.hud.spect_changed()


func spectate_toggle_all() -> void:
	if not can_watch_enemies():
		return
	spect_all = not spect_all
	if not spect_all:
		_pick_spectate()   # back to a teammate when one is standing
	if world.hud:
		world.hud.spect_changed()


func spectate_cycle(d: int) -> void:
	if not _death.is_empty():
		_death = {}   # skip the camera on your body
		if world.hud and world.hud.death_card:
			world.hud.death_card.hide_report()
		return
	var list := spectate_candidates()
	if list.is_empty():
		spectating = -1
		return
	var i := list.find(spectating)
	i = 0 if i < 0 else (i + d + list.size()) % list.size()
	_set_spectate(int(list[i]))


func _set_spectate(eid: int) -> void:
	if eid != spectating:
		var t = world.characters.get(eid)
		if t:
			yaw = t.yaw  # start behind the new target, looking where it looks
	spectating = eid
	world.request_spectate(eid)


func set_results_mode(on: bool) -> void:
	results = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Settings.play_mouse_mode()


func on_suppressed(dist: float) -> void:
	## A near miss: a small flinch of the view (much less than being hit).
	_hit_shake = minf(_hit_shake + 0.18 * clampf(1.0 - dist / 2.2, 0.2, 1.0), 0.6)


func on_hit(part: String, dir: Vector3, damage: float, absorbed: String) -> void:
	_hit_shake = minf(_hit_shake + 0.3 + damage * 0.02, 1.2)
	# The punch: the head snaps away from the shot. A hit from the front tips the view up, from behind down, from a
	# side turns and rolls it away; stronger for heavier hits and for the head, softened by armour that stopped it.
	var amt := deg_to_rad(clampf(1.2 + damage * 0.06, 1.2, 4.5))
	if part == "head":
		amt *= 1.4
	if absorbed != "":
		amt *= 0.6
	var d := dir
	d.y = 0.0
	var fwd := -Basis(Vector3.UP, yaw).z
	var right := Basis(Vector3.UP, yaw).x
	var front := 1.0 if d.length() < 0.01 else -fwd.dot(d.normalized())   # 1: shot came from in front
	var side := 0.0 if d.length() < 0.01 else right.dot(d.normalized())   # >0: pushed to the right
	var jitter := randf_range(-0.25, 0.25)
	_kicks.append([Time.get_ticks_msec() / 1000.0, Vector3(amt * (0.65 * front + 0.35 + jitter * 0.3), -amt * side * 0.9 + amt * jitter * 0.4, -amt * side * 0.7)])
	if _kicks.size() > 6:
		_kicks.pop_front()
	if vm:
		vm.on_hit(damage)


func blast_shake(strength: float) -> void:
	## r14: a grenade going off nearby shakes the view (stronger closer); a sharp jolt, then the shake dies away.
	if strength <= 0.0:
		return
	_hit_shake = minf(_hit_shake + strength * 2.6, 3.0)
	_kicks.append([Time.get_ticks_msec() / 1000.0, Vector3(-0.06 * strength, randf_range(-0.04, 0.04) * strength, randf_range(-0.05, 0.05) * strength)])
	if _kicks.size() > 6:
		_kicks.pop_front()


func _on_motion_event(kind: String, value: float) -> void:
	match kind:
		"land":
			_land_jolt = clampf(value / 9.0, 0.0, 1.0)
		"land_roll":
			_land_jolt = 0.35
			_roll_view_t = 0.0
		"ledge_grab":
			_land_jolt = 0.3
			_kicks.append([Time.get_ticks_msec() / 1000.0, Vector3(-0.035, 0.0, 0.0)])
		"wallrun":
			_kicks.append([Time.get_ticks_msec() / 1000.0, Vector3(0.03, 0.0, 0.0)])
		"ladder":
			if not world.is_server:
				SoundSys.play_at("ladder_step", ch.global_position + Vector3.UP * 0.9)
		"jump":
			pass


# ------------------------------------------------------------------ camera

func _process(dt: float) -> void:
	if ch == null or not is_instance_valid(ch):
		# r24: dying while aimed through a scope left the scope's zoom on the death and spectator cameras.
		if cam:
			cam.fov = float(Settings.get_value("graphics", "fov"))
		if not _death_camera():
			_spectate_camera(dt)
		return
	if world.hud:
		world.hud.tab_held = tab_held
		world.hud.map_held = map_held
	_correction = _correction.lerp(Vector3.ZERO, clampf(dt * 12.0, 0.0, 1.0))
	if cook_t >= 0.0:
		cook_t += dt
		if cook_t > float(Defs.item("frag_grenade").get("fuse_s", 4.0)) + 0.25 or ch.mode != Motor.GROUND:
			cook_t = -1.0   # it went off in the hand (or was dropped)
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
		# Halved 2026-10-28 (walking and running bob read as dizzying); GAIT_BOB scales the limp too.
		bob.y = sin(_bob_t * 2.0) * 0.025 * GAIT_BOB * clampf(hv / 4.0, 0.3, 1.3)
		bob.x = sin(_bob_t) * 0.018 * GAIT_BOB
		var limp: float = ch.health.limp_side() if ch.health and ch.health.has_method("limp_side") else 0.0
		if limp != 0.0:
			# Uneven gait: the injured leg's step dips harder and rolls the head toward it.
			var phase := sin(_bob_t + (0.0 if limp > 0.0 else PI))
			bob.y -= maxf(phase, 0.0) * 0.045 * GAIT_BOB * (2.0 - ch.injury_speed)
			roll += maxf(phase, 0.0) * 0.022 * GAIT_BOB * limp
	_land_jolt = move_toward(_land_jolt, 0.0, dt * 3.0)
	bob.y -= sin(_land_jolt * PI) * 0.08
	_hit_shake = move_toward(_hit_shake, 0.0, dt * 2.5)
	var shake := Vector3(sin(Time.get_ticks_msec() * 0.031), sin(Time.get_ticks_msec() * 0.027), 0) * _hit_shake * 0.01
	# Hit punch: each hit follows (t/r) e^(1 - t/r), peak 1 at t = r, nearly gone by 0.4 s.
	var now_s := Time.get_ticks_msec() / 1000.0
	var _kick := Vector3.ZERO
	for i in range(_kicks.size() - 1, -1, -1):
		var age := now_s - float(_kicks[i][0])
		if age > 0.6:
			_kicks.remove_at(i)
			continue
		_kick += (_kicks[i][1] as Vector3) * (age / KICK_RISE) * exp(1.0 - age / KICK_RISE)
	_kick = _kick.clamp(Vector3(-0.14, -0.14, -0.12), Vector3(0.14, 0.14, 0.12))
	pos += Basis(Vector3.UP, yaw) * (bob * motion_k)
	# r12 body feel: lean with the acceleration, tip into a slide, nod over the top of a climb, go over in a roll.
	var vel: Vector3 = ch.velocity
	if dt > 0.0:
		var acc := (vel - _prev_vel) / dt
		acc.y = 0.0
		_prev_vel = vel
		_acc_smooth = _acc_smooth.lerp(acc.limit_length(40.0), clampf(dt * 6.0, 0.0, 1.0))
	var fwd_v := -Basis(Vector3.UP, yaw).z
	var right_v := Basis(Vector3.UP, yaw).x
	var lean_to := Vector2.ZERO
	if on_floor and ch.vault_t < 0.0 and ch.ledge_t < 0.0 and ch.roll_t < 0.0:
		lean_to = Vector2(-_acc_smooth.dot(fwd_v) * 0.0045, -_acc_smooth.dot(right_v) * 0.004).clamp(Vector2(-0.07, -0.06), Vector2(0.07, 0.06))
	_lean = _lean.lerp(lean_to, clampf(dt * 7.0, 0.0, 1.0))
	_slide_k = move_toward(_slide_k, 1.0 if ch.slide_t >= 0.0 else 0.0, dt * 5.0)
	var climb_to := 0.0
	if ch.vault_t >= 0.0 and (ch.pk_bits & Parkour.PK_CLIMB) != 0:
		climb_to = sin(clampf(ch.vault_t / maxf(ch.vault_d, 0.05), 0.0, 1.0) * PI)
	_climb_k = move_toward(_climb_k, climb_to, dt * 6.0)
	var roll_pitch := 0.0
	if _roll_view_t >= 0.0:
		_roll_view_t += dt
		var u := clampf(_roll_view_t / Defs.move("roll_s"), 0.0, 1.0)
		roll_pitch = -TAU * (u * u * (3.0 - 2.0 * u)) if motion == "normal" else -sin(u * PI) * 0.9 * motion_k
		if u >= 1.0:
			_roll_view_t = -1.0
	roll += _lean.y + 0.07 * _slide_k
	_cam_roll = lerpf(_cam_roll, roll * motion_k, clampf(dt * 8.0, 0.0, 1.0))
	var p_view := pitch + (_lean.x - 0.22 * _climb_k) * motion_k + roll_pitch
	var y_view := yaw
	if ch.mode == Motor.PLANE:
		_plane_camera(dt)
		return
	if vm and not vm.visible:
		vm.visible = true
	var kick := _kick * maxf(motion_k, 0.25)   # even "off" keeps a small punch: it says you were hit
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(p_view + shake.y * motion_k + kick.x, y_view + shake.x * motion_k + kick.y, _cam_roll + kick.z)), pos)
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


func _death_camera() -> bool:
	## The camera on your own body for DEATH_CAM_S: close above it at first, pulling back and circling slowly, on the
	## side away from whoever killed you so they are in the background. False when it is over (spectating follows).
	if _death.is_empty() or cam == null:
		return false
	var age := Time.get_ticks_msec() / 1000.0 - float(_death.t)
	if age > DEATH_CAM_S:
		_death = {}
		return false
	var body: Vector3 = _death.pos
	var focus := body + Vector3.UP * 0.35
	var kp: Vector3 = _death.killer_pos
	var away := Vector3(sin(float(_death.yaw)), 0.0, cos(float(_death.yaw)))   # behind where you were facing
	if kp != Vector3.INF and Vector2(kp.x - body.x, kp.z - body.z).length() > 1.0:
		away = Vector3(body.x - kp.x, 0.0, body.z - kp.z).normalized()
	var u := clampf(age / DEATH_CAM_S, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - clampf(age / 2.2, 0.0, 1.0), 3.0)
	var dir := away.rotated(Vector3.UP, 0.35 + u * 0.7)
	var desired := focus + dir * lerpf(1.2, 4.4, e) + Vector3.UP * lerpf(2.6, 2.4, e)
	var space = world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, desired, Defs.SIGHT_MASK)
	var r = space.intersect_ray(q)
	if not r.is_empty():
		desired = (r.position as Vector3).lerp(focus, 0.12)
	var look := focus
	if kp != Vector3.INF:
		look = focus.lerp(kp + Vector3.UP * 1.2, 0.18 * smoothstep(0.45, 0.9, u))
	cam.global_transform = Transform3D(Basis.looking_at(look - desired, Vector3.UP), desired)
	if world.hud:
		world.hud.set_spectating(null)
	return true


func _spectate_camera(dt: float) -> void:
	if cam == null:
		return
	var cur = world.characters.get(spectating)
	if cur == null or cur.mode in [Motor.DEAD, Motor.SPECTATE]:
		_pick_spectate()
	elif not spect_all and cur.team != int(Net.players.get(Net.local_pid, {}).get("team", -1)) and Engine.get_process_frames() % 30 == 0:
		# Watching an enemy because no teammate was left: back to a teammate as soon as one is (late spawn, rebind).
		var list := spectate_candidates()
		if not list.is_empty() and world.characters[list[0]].team != cur.team:
			_pick_spectate()
	var t = world.characters.get(spectating)
	if spect_view == SpectView.FREE and can_free_camera():
		_free_camera(dt, t)
		return
	if t == null:
		return
	_look(dt)
	var b := Basis.from_euler(Vector3(clampf(pitch, -1.0, 0.6), yaw, 0))
	var focus: Vector3 = t.get_global_transform_interpolated().origin + Vector3.UP * 1.6
	var desired := focus + b * Vector3(0.4, 0.3, 3.2)
	if spect_view == SpectView.SHOULDER:
		desired = focus + b * Vector3(0.55, 0.05, 1.35)
	elif spect_view == SpectView.OVERHEAD:
		# High above and a little behind, looking down at the player and what is around them.
		var back := Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 6.0)
		desired = focus + Vector3.UP * 13.0 + back
		b = Basis.looking_at(focus - desired, Vector3.UP)
	var space = world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, desired, Defs.SIGHT_MASK)
	var r = space.intersect_ray(q)
	if not r.is_empty():
		desired = (r.position as Vector3).lerp(focus, 0.1)
	cam.global_transform = Transform3D(b, desired)
	if world.hud:
		world.hud.set_spectating(t)


func _free_camera(dt: float, t) -> void:
	## Fly anywhere: move keys, Space up, Crouch down, Sprint faster. The HUD still names who Next/Previous selected.
	_look(dt)
	pitch = clampf(pitch, -1.5, 1.5)
	var b := Basis.from_euler(Vector3(pitch, yaw, 0))
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var up := (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	var speed := 26.0 if Input.is_action_pressed("sprint") else 9.0
	_free_pos += (b * Vector3(mv.x, 0.0, mv.y) + Vector3.UP * up) * speed * dt
	cam.global_transform = Transform3D(b, _free_pos)
	if world.hud:
		world.hud.set_spectating(t)




