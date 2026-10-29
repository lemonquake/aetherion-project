extends Node
## Headless integration checks for the shared server/client firearm simulation and packet codec.
## godot --headless --path game res://tests/fire_modes.tscn

const WeaponState := preload("res://src/weapons/weapon_state.gd")
const Snapshot := preload("res://src/net/snapshot.gd")
const Interaction := preload("res://src/match/interaction.gd")
const Inventory := preload("res://src/items/inventory.gd")
const Flashlight := preload("res://src/lighting/flashlight_state.gd")
const TouchControls := preload("res://src/ui/touch_controls.gd")
const PlayerController := preload("res://src/player/player_controller.gd")
var failures := 0
var checks := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)


func _gun(id: String, mode: int = 0):
	var w = WeaponState.new()
	w.slots[1] = WeaponState.new_instance(id, null, 1.0)
	w.cur = 1
	w.want = 1
	w.weapon().mode = mode
	return w


func _step(w, btn: int, tick: int = 0, slot: int = 1) -> Array:
	return w.step({"btn": btn, "slot": slot}, 1.0 / 60.0, tick)


func _run() -> void:
	var selectors := 0
	for id in Defs.weapons:
		var d: Dictionary = Defs.weapon(id)
		var w = _gun(id)
		if str(d.get("class", "")) in ["rifle", "smg"]:
			selectors += 1
			_check(w.fire_mode() == "auto", id + " starts Auto")
			for mode in ["semi", "burst", "auto"]:
				_step(w, Motor.B_FIREMODE)
				_check(w.fire_mode() == mode, id + " cycle to " + mode)
				for i in 5:
					_step(w, Motor.B_FIREMODE)
				_check(w.fire_mode() == mode, id + " held selector cycles once")
				_step(w, 0)
			_check(_held_count(id, 0, 60) > 3, id + " Auto holds continuously")
			_check(_held_count(id, 1, 120) == 1, id + " Single only once per press")
			_check(_held_count(id, 2, 180) == 3, id + " held Burst stops at three")
			_tap_burst(id)
		else:
			_check(w.available_modes() == d.get("fire_modes", ["semi"]), id + " original modes preserved")
	_check(selectors == 10, "all ten rifle/SMG definitions exercised")
	_interruptions()
	_packet_and_acquisition()
	_touch_input()
	_menu_interruption()
	_long_run()
	_check(str(Settings.BINDINGS.fire_mode[0]) == "B", "default selector key is B")
	_check(TouchControls.BUTTONS.filter(func(b): return b.name == "fire_mode" and b.action == "fire_mode").size() == 1,
		"one mobile selector uses the same input action")
	print("[fire_modes] %d checks, %d failed; 10000 fixed steps at 60 Hz per simulation replica" % [checks, failures])
	get_tree().quit(1 if failures else 0)


func _held_count(id: String, mode: int, steps: int) -> int:
	var w = _gun(id, mode)
	for tick in steps:
		_step(w, Motor.B_FIRE, tick)
	return w.shots


func _tap_burst(id: String) -> void:
	var w = _gun(id, 2)
	var ticks := []
	for tick in 80:
		if not _step(w, Motor.B_FIRE if tick == 0 else 0, tick).is_empty():
			ticks.append(tick)
	_check(ticks.size() == 3 and w.burst_left == 0, id + " tap completes three rounds after release")
	if ticks.size() == 3:
		var seconds := 60.0 / float(Defs.weapon(id).rpm)
		_check((ticks[1] - ticks[0]) / 60.0 >= seconds - 0.0001 and (ticks[2] - ticks[1]) / 60.0 >= seconds - 0.0001,
			id + " burst respects weapon RPM")
	_step(w, Motor.B_FIRE, 81)
	for tick in range(82, 160):
		_step(w, 0, tick)
	_check(w.shots == 6, id + " second press starts exactly one more burst")
	for rounds in [1, 2]:
		w = _gun(id, 2)
		w.weapon().mag = rounds - 1
		for tick in 80:
			_step(w, Motor.B_FIRE if tick == 0 else 0, tick)
		_check(w.shots == rounds and w.loaded() == 0 and w.burst_left == 0, id + " partial magazine truncates burst")


func _interruptions() -> void:
	for reason in ["reload", "switch", "selector", "blocked", "holster"]:
		var w = _gun("rifle_556", 2)
		w.slots[2] = WeaponState.new_instance("smg_9", null, 1.0)
		w.reserve_cache["556"] = 60
		_step(w, Motor.B_FIRE, 0)
		_check(w.burst_left == 2, reason + " starts with two rounds pending")
		match reason:
			"reload": _step(w, Motor.B_RELOAD, 1)
			"switch": _step(w, 0, 1, 2)
			"selector": _step(w, Motor.B_FIREMODE, 1)
			"blocked":
				w.blocked = true
				_step(w, 0, 1)
				w.blocked = false
			"holster": _step(w, 0, 1, 0)
		var slot: int = w.cur
		for tick in range(2, 240):
			_step(w, 0, tick, slot)
		_check(w.shots == 1 and w.burst_left == 0, reason + " cancels pending burst permanently")
	var empty = _gun("smg_9", 2)
	empty.weapon().mag = 0
	empty.weapon().chamber = false
	var dry: Array = _step(empty, Motor.B_FIRE)
	_check(dry.size() == 1 and dry[0].get("dry", false) and empty.burst_left == 0, "empty burst emits one dry click")
	_check(_step(empty, Motor.B_FIRE).is_empty(), "holding empty burst never repeats dry click")
	var rapid = _gun("rifle_556", 2)
	for tick in 80:
		_step(rapid, Motor.B_FIRE if tick in [0, 6] else 0, tick)
	_check(rapid.shots == 3, "repressing during an active burst does not extend it")
	var unchanged: Dictionary = empty.get_state().duplicate(true)
	_step(empty, 0)
	var invalid = empty.step({"btn": Motor.B_FIRE}, NAN, 1)
	_check(invalid.is_empty() and is_finite(empty.cooldown), "non-finite delta cannot poison state")


func _packet_and_acquisition() -> void:
	var ch := Character.new()
	add_child(ch)
	ch.eid = 42
	ch.wpn = _gun("rifle_556", 2)
	ch.light = Flashlight.new(ch)
	ch.inv = Inventory.new(ch)
	var it = Interaction.new(null)
	var acquired := WeaponState.new_instance("smg_9", null, 1.0)
	acquired.mode = 2
	it.give(ch, {"id": "smg_9", "n": 1, "w": acquired})
	_check(ch.wpn.slots[2].mode == 0, "acquiring a dropped SMG resets it to Auto")
	_step(ch.wpn, Motor.B_FIRE, 10)
	ch.wpn._reload_queued = true
	var bytes := Snapshot.encode(10, 9, ch, [], [], [])
	var decoded: Dictionary = Snapshot.decode(bytes, [])
	var encoded: Dictionary = ch.wpn.get_state()
	for key in ["mode", "bl", "pf", "pm", "rq", "mag", "chamber", "shots"]:
		_check(decoded.own.wpn[key] == encoded[key], "packet preserves " + key)
	var clone = _gun("rifle_556")
	clone.set_state(decoded.own.wpn)
	ch.wpn._reload_queued = false
	clone._reload_queued = false
	for tick in range(11, 70):
		_step(ch.wpn, 0, tick)
		_step(clone, 0, tick)
	_check(clone.shots == 3 and clone.shots == ch.wpn.shots, "packet correction resumes remaining burst without duplication")
	var cmd := {"seq": 7, "mx": 0.0, "my": 0.0, "yaw": 0.0, "pitch": 0.0, "btn": Motor.B_FIREMODE, "slot": 1, "tick": 100}
	_check(Snapshot.decode_cmds(Snapshot.encode_cmds([cmd]))[0].btn == Motor.B_FIREMODE, "B/touch intent survives command packet")
	var before: Dictionary = ch.inv.to_dict().duplicate(true)
	before.w[1].mode = 0
	ch.wpn.weapon().mode = 2
	ch.inv.from_dict(before)
	_check(ch.wpn.weapon().mode == 2, "inventory sync preserves the predicted selector until snapshot correction")
	for restart in 20:
		var fresh = _gun("rifle_556")
		_check(fresh.fire_mode() == "auto" and fresh.burst_left == 0, "new character/restart has Auto and no pending rounds")
	ch.free()


func _touch_input() -> void:
	var ch := Character.new()
	add_child(ch)
	ch.wpn = _gun("rifle_556")
	var ctl = PlayerController.new()
	ctl.ch = ch
	add_child(ctl)
	ctl.set_process(false)
	ctl.set_physics_process(false)
	var touch = TouchControls.new()
	add_child(touch)
	touch.setup(ctl)
	touch.set_process(false)
	var b: Dictionary = TouchControls.BUTTONS.filter(func(entry): return entry.name == "fire_mode")[0]
	_check(touch._visible_button(b), "mobile selector visible with a rifle")
	touch._touch_down(0, touch._centre(b))
	Input.flush_buffered_events()
	var cmd: Dictionary = ctl._build_cmd()
	_check((int(cmd.btn) & Motor.B_FIREMODE) != 0, "quick mobile tap is latched into next command")
	_step(ch.wpn, int(cmd.btn))
	_check(ch.wpn.fire_mode_label() == "Single", "mobile button label reads current state after tap")
	_check((int(ctl._build_cmd().btn) & Motor.B_FIREMODE) == 0, "mobile mode tap is not held or repeated")
	ch.wpn.slots[1] = WeaponState.new_instance("pistol_9")
	_check(not touch._visible_button(b), "mobile selector hides for fixed-mode handgun")
	touch.free()
	ctl.free()
	ch.free()


func _long_run() -> void:
	var server = _gun("rifle_556")
	var predicted = _gun("rifle_556")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1729
	var time0 := Time.get_ticks_usec()
	for tick in 10000:
		if tick % 180 == 0:
			for w in [server, predicted]:
				w.weapon().mag = 29
				w.weapon().chamber = true
		var btn := Motor.B_FIRE if tick % 45 < 24 else 0
		if tick % 101 == 0:
			btn |= Motor.B_FIREMODE
		if tick % 241 == 0:
			btn |= Motor.B_RELOAD
		var block := rng.randf() < 0.015
		server.blocked = block
		predicted.blocked = block
		var a := _step(server, btn, tick)
		var b := _step(predicted, btn, tick)
		_check(server.get_state() == predicted.get_state() and a == b, "deterministic replica at tick %d" % tick)
		_check(server.loaded() >= 0 and server.weapon().mag <= 30 and server.burst_left >= 0 and server.burst_left <= 3 \
			and is_finite(server.cooldown) and server.kick.is_finite(), "bounded state at tick %d" % tick)
		if tick % 37 == 0:
			predicted.set_state(server.get_state())
	print("[fire_modes] deterministic workload %.2f ms, seed 1729, shots %d" % [(Time.get_ticks_usec() - time0) / 1000.0, server.shots])


func _menu_interruption() -> void:
	# Exercise the real controller command builder and prediction blocker, including the held physical fire
	# action across menu closure. Merely setting WeaponState.blocked would miss a missing command bit/release gate.
	for screen in ["paused", "results"]:
		for mode in [0, 1, 2]:
			Input.action_release("fire")
			var ch := Character.new()
			add_child(ch)
			ch.wpn = _gun("rifle_556", mode)
			ch.wpn.ch = ch
			ch.light = Flashlight.new(ch)
			var ctl = PlayerController.new()
			ctl.ch = ch
			ctl.slot = 1
			add_child(ctl)
			ctl.set_process(false)
			ctl.set_physics_process(false)
			Input.action_press("fire")
			var cmd: Dictionary = ctl._build_cmd()
			ctl._weapon_intent(cmd)
			ch.wpn.step(cmd, Defs.TICK_DT, 0)
			_check(ch.wpn.shots == 1, "%s mode%d starts with one shot" % [screen, mode])
			ctl.set(screen, true)
			cmd = ctl._build_cmd()
			_check((int(cmd.btn) & Motor.B_ACTION_BLOCKED) != 0 and (int(cmd.btn) & Motor.B_FIRE) == 0,
				"%s mode%d sends explicit weapon blocker without Fire" % [screen, mode])
			var received: Dictionary = Snapshot.decode_cmds(Snapshot.encode_cmds([cmd]))[0]
			_check((int(received.btn) & Motor.B_ACTION_BLOCKED) != 0,
				"%s mode%d blocker survives command codec" % [screen, mode])
			ctl._weapon_intent(received)
			_check(ch.wpn.blocked, "%s mode%d prediction consumes decoded blocker" % [screen, mode])
			ch.wpn.step(received, Defs.TICK_DT, 1)
			for tick in range(2, 62):
				cmd = ctl._build_cmd()
				ctl._weapon_intent(cmd)
				ch.wpn.step(cmd, Defs.TICK_DT, tick)
			_check(ch.wpn.shots == 1 and ch.wpn.burst_left == 0,
				"%s mode%d stops all pending rounds while menu remains open" % [screen, mode])
			ctl.set(screen, false)
			for tick in range(62, 122):
				cmd = ctl._build_cmd()
				_check((int(cmd.btn) & Motor.B_FIRE) == 0,
					"%s mode%d held Fire stays suppressed after resume tick%d" % [screen, mode, tick])
				ctl._weapon_intent(cmd)
				ch.wpn.step(cmd, Defs.TICK_DT, tick)
			_check(ch.wpn.shots == 1, "%s mode%d menu closure cannot resume held Fire" % [screen, mode])
			Input.action_release("fire")
			cmd = ctl._build_cmd()
			ctl._weapon_intent(cmd)
			ch.wpn.step(cmd, Defs.TICK_DT, 122)
			Input.action_press("fire")
			for tick in range(123, 183):
				cmd = ctl._build_cmd()
				ctl._weapon_intent(cmd)
				ch.wpn.step(cmd, Defs.TICK_DT, tick)
			_check((ch.wpn.shots > 4 if mode == 0 else ch.wpn.shots == (2 if mode == 1 else 4)),
				"%s mode%d fresh Fire press restores correct firing behavior" % [screen, mode])
			Input.action_release("fire")
			ctl.free()
			ch.free()
