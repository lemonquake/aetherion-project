extends Node3D
## The running match: map, characters, props, items, corpses and every replicated event.
##
## Server: consumes player/bot commands at 60 Hz, simulates everything, sends per-client snapshots at 30 Hz with
## distance relevance (enemies beyond enemy_radius are not sent), and reliable events for discrete changes.
## Clients: predict their own character, interpolate everything else 100 ms in the past, and play effects.

const MapBuilder := preload("res://src/world/map_builder.gd")
const WeaponState := preload("res://src/weapons/weapon_state.gd")
const Health := preload("res://src/player/health.gd")
const Inventory := preload("res://src/items/inventory.gd")
const FlashlightState := preload("res://src/lighting/flashlight_state.gd")
const ProjectileServer := preload("res://src/weapons/projectile_server.gd")
const MatchServer := preload("res://src/match/match_server.gd")
const PlayerController := preload("res://src/player/player_controller.gd")
const CharacterVisual := preload("res://src/player/character_visual.gd")
const Effects := preload("res://src/fx/effects.gd")
const Hud := preload("res://src/ui/hud.gd")
const Snapshot := preload("res://src/net/snapshot.gd")
const Interaction := preload("res://src/match/interaction.gd")
const BotBrain := preload("res://src/ai/bot_brain.gd")

var is_server := false
var cfg: Dictionary = {}
var match_seed := 0
var map = null
var characters: Dictionary = {}  # eid -> Character
var by_pid: Dictionary = {}      # pid -> eid
var local_char: Character = null
var controller = null
var projectiles = null
var match_server = null
var effects = null
var hud = null
var ambience = null
var announcer = null
var interaction = null
var grenades = null
var bots: Dictionary = {}        # eid -> BotBrain
var spectate_eid := -1

var _next_eid := 1
var _queues: Dictionary = {}     # eid -> Array of cmds
var _starved: Dictionary = {}    # eid -> seconds without a command
var _budget: Dictionary = {}     # eid -> commands that may still be simulated (one per tick, banks up to 20)
var _acked: Dictionary = {}      # eid -> last processed seq
var _history: Dictionary = {}    # eid -> {ticks: Array, states: Array, i: next slot}, a ring per character
var _bot_dt: Dictionary = {}     # eid -> seconds a bot simulates this tick, 0 on a skipped tick (_bot_lod)
var _bot_last: Dictionary = {}   # eid -> tick of the bot's last step
var _snap_accum := 0
var _owner_sync_t := 0.0
const Attach := preload("res://src/weapons/attachments.gd")
var _weapon_ids: Array = []
var _match_info: Dictionary = {}
var _started := false
var chars_root: Node3D
var dyn_root: Node3D


func build(config: Dictionary, seed_value: int) -> void:
	is_server = Net.is_server
	cfg = config
	match_seed = seed_value
	_weapon_ids = Defs.weapons.keys()
	_weapon_ids.sort()
	chars_root = Node3D.new()
	chars_root.name = "Characters"
	add_child(chars_root)
	dyn_root = Node3D.new()
	dyn_root.name = "Dynamic"
	add_child(dyn_root)
	var t0 := Time.get_ticks_msec()
	map = MapBuilder.new()
	map.build(self, int(cfg.get("map_seed", 1729)), match_seed)
	print("[world] map built in %d ms" % (Time.get_ticks_msec() - t0))
	map.acoustics.space = get_world_3d().direct_space_state
	SoundSys.set_acoustics(map.acoustics)
	if DisplayServer.get_name() != "headless":
		SoundSys.warm()
		map.warm_up(self)
	interaction = Interaction.new(self)
	grenades = preload("res://src/weapons/grenades.gd").new()
	add_child(grenades)
	grenades.setup(self)
	if DisplayServer.get_name() != "headless":
		effects = Effects.new()
		effects.name = "Effects"
		add_child(effects)
		effects.setup(self)
		ambience = load("res://src/audio/ambience.gd").new()
		ambience.name = "Ambience"
		add_child(ambience)
		ambience.setup(self)
		hud = Hud.new()
		hud.name = "Hud"
		Game.ui.add_child(hud)
		hud.setup(self)
		announcer = preload("res://src/audio/announcer.gd").new()
		announcer.name = "Announcer"
		add_child(announcer)
		announcer.setup(self)
	if is_server:
		projectiles = ProjectileServer.new(self)
		match_server = MatchServer.new()
		match_server.name = "MatchServer"
		add_child(match_server)
		match_server.setup(self)


func teardown() -> void:
	if map and map.dyn:
		map.dyn.dispose()
	if hud and is_instance_valid(hud):
		hud.queue_free()
	if controller and is_instance_valid(controller):
		controller.queue_free()
	SoundSys.clear()


func server_start_match() -> void:
	_started = true
	match_server.start()


func client_match_started() -> void:
	_started = true


func show_results(summary: Dictionary) -> void:
	if hud:
		hud.show_results(summary)
	if controller:
		controller.set_results_mode(true)


# ------------------------------------------------------------------ queries used by many systems

func water_height(x: float, z: float) -> float:
	return map.water_height(x, z) if map else -INF


func history_state(eid: int, tick: int) -> Dictionary:
	## The newest recorded state at or before tick (the oldest kept if tick is older still).
	var h: Dictionary = _history.get(eid, {})
	if h.is_empty():
		return {}
	var ticks: Array = h.ticks
	var n := ticks.size()
	var oldest := {}
	for k in n:
		var j := (int(h.i) - 1 - k + n * 2) % n
		var t := int(ticks[j])
		if t < 0:
			break
		if t <= tick:
			return h.states[j]
		oldest = h.states[j]
	return oldest


func char_by_pid(pid: int) -> Character:
	var eid: int = by_pid.get(pid, -1)
	return characters.get(eid)


func alive_characters() -> Array:
	return characters.values().filter(func(c): return c.mode not in [Motor.DEAD, Motor.SPECTATE])


func team_of(eid: int) -> int:
	var c = characters.get(eid)
	return c.team if c else -1


# ------------------------------------------------------------------ characters

func server_spawn_character(pid: int, team: int, pname: String, pos: Vector3, mode: int) -> Character:
	var eid := _next_eid
	_next_eid += 1
	var ch := _make_character(eid, pid, team, pname, pos, mode)
	_spawn_char.rpc(eid, pid, team, pname, pos, mode)
	if Net.is_bot(pid):
		var brain = BotBrain.new(self, ch)
		bots[eid] = brain
	return ch


@rpc("authority", "call_remote", "reliable")
func _spawn_char(eid: int, pid: int, team: int, pname: String, pos: Vector3, mode: int) -> void:
	if characters.has(eid):
		return
	_make_character(eid, pid, team, pname, pos, mode)


func _make_character(eid: int, pid: int, team: int, pname: String, pos: Vector3, mode: int) -> Character:
	var ch := Character.new()
	ch.name = "C%d" % eid
	ch.eid = eid
	ch.pid = pid
	ch.team = team
	ch.pname = pname
	ch.world = self
	ch.mode = mode
	ch.wpn = WeaponState.new(ch)
	ch.light = FlashlightState.new(ch)
	ch.health = Health.new(ch)
	ch.inv = Inventory.new(ch)
	chars_root.add_child(ch)
	ch.global_position = pos
	characters[eid] = ch
	by_pid[pid] = eid
	_queues[eid] = []
	ch.is_local = pid == Net.local_pid and not is_server_dedicated()
	ch.is_remote = not is_server and not ch.is_local
	if ch.is_remote:
		ch.collision_layer = Defs.PHYS_CHAR
		ch.collision_mask = 0
		# Placed every frame from snapshots (interpolate()): engine interpolation on top would lag and step.
		ch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if DisplayServer.get_name() != "headless":
		var vis = CharacterVisual.new()
		vis.name = "Visual"
		ch.add_child(vis)
		vis.setup(self, ch)
		ch.visual = vis
	if ch.is_local:
		local_char = ch
		controller = PlayerController.new()
		controller.name = "PlayerController"
		add_child(controller)
		controller.setup(self, ch)
		if hud:
			hud.set_character(ch)
	return ch


func is_server_dedicated() -> bool:
	return is_server and Net.dedicated


func server_set_mode(ch: Character, mode: int) -> void:
	ch.mode = mode
	_char_mode.rpc(ch.eid, mode, ch.global_position, ch.velocity)


@rpc("authority", "call_remote", "reliable")
func _char_mode(eid: int, mode: int, pos: Vector3, vel: Vector3 = Vector3.ZERO) -> void:
	var ch: Character = characters.get(eid)
	if ch == null:
		return
	ch.mode = mode
	if ch.is_local:
		ch.global_position = pos
		ch.velocity = vel
		if controller:
			controller.on_mode_forced(mode)
	if ch.visual:
		ch.visual.on_mode(mode)


func server_remove_character(ch: Character) -> void:
	_remove_char.rpc(ch.eid)
	_remove_char(ch.eid)


@rpc("authority", "call_remote", "reliable")
func _remove_char(eid: int) -> void:
	var ch: Character = characters.get(eid)
	if ch == null:
		return
	characters.erase(eid)
	by_pid.erase(ch.pid)
	_queues.erase(eid)
	_history.erase(eid)
	_bot_dt.erase(eid)
	_bot_last.erase(eid)
	bots.erase(eid)
	if ch == local_char:
		local_char = null
		if controller:
			controller.on_local_died()
	ch.queue_free()


func server_rebind_player(old_pid: int, new_pid: int) -> void:
	var eid: int = by_pid.get(old_pid, -1)
	if eid < 0:
		return
	by_pid.erase(old_pid)
	by_pid[new_pid] = eid
	characters[eid].pid = new_pid
	_queues[eid] = []


func server_peer_left(pid: int) -> void:
	# The character stays in the world (vulnerable, idle) so the player can reconnect.
	var ch := char_by_pid(pid)
	if ch:
		_queues[ch.eid] = []


# ------------------------------------------------------------------ commands

func send_cmds(cmds: Array) -> void:
	## Called by the local PlayerController each tick with the newest commands (redundant copies included).
	if local_char == null:
		return
	if is_server:
		server_queue_cmds(local_char.eid, cmds)
	else:
		_cmds.rpc_id(1, Snapshot.encode_cmds(cmds))


@rpc("any_peer", "unreliable_ordered", "call_remote", 2)
func _cmds(bytes: PackedByteArray) -> void:
	if not is_server:
		return
	var pid := multiplayer.get_remote_sender_id()
	var ch := char_by_pid(pid)
	if ch == null or bytes.size() > 2048:
		return
	server_queue_cmds(ch.eid, Snapshot.decode_cmds(bytes))


func server_queue_cmds(eid: int, cmds: Array) -> void:
	var q: Array = _queues.get(eid, [])
	var last: int = _acked.get(eid, 0)
	if not q.is_empty():
		last = maxi(last, int(q[-1].seq))
	for c in cmds:
		if int(c.seq) > last and _cmd_valid(c):
			q.append(c)
			last = int(c.seq)
	# Half a second of backlog is the most we keep; beyond that the client is far behind (or cheating).
	while q.size() > 30:
		q.pop_front()
	_queues[eid] = q


func _cmd_valid(c: Dictionary) -> bool:
	for k in ["mx", "my", "yaw", "pitch"]:
		var v = c.get(k, 0.0)
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			return false
		if is_nan(float(v)) or is_inf(float(v)):
			return false
	return absf(float(c.mx)) <= 1.01 and absf(float(c.my)) <= 1.01


# ------------------------------------------------------------------ server tick

func _physics_process(dt: float) -> void:
	if map:
		map.physics_tick(dt)
	if not is_server:
		return
	var t_us := Time.get_ticks_usec()
	var tick := Net.tick
	_bot_lod(tick)
	for eid in bots.keys():
		if characters.has(eid) and float(_bot_dt.get(eid, dt)) > 0.0:
			server_queue_cmds(eid, [bots[eid].think(float(_bot_dt.get(eid, dt)), tick)])
	for eid in characters.keys():
		var ch: Character = characters[eid]
		if ch.mode in [Motor.DEAD, Motor.SPECTATE]:
			continue
		var q: Array = _queues[eid]
		var sdt := dt
		if _bot_dt.has(eid):
			# A bot on a skipped tick keeps still; its next step covers the time it missed.
			sdt = float(_bot_dt[eid])
			if sdt <= 0.0:
				ch.flags = ch.compute_flags()
				_record(ch, tick)
				continue
		# Catch up a backlog a little faster than real time (never more than 3 steps a tick), paid from a budget that
		# grows by one command per tick: bursts are caught up, a client cannot run faster than real time.
		_budget[eid] = minf(float(_budget.get(eid, 0.0)) + 1.0, 20.0)
		var n := 1 if q.size() <= 2 else (2 if q.size() <= 6 else 3)
		if q.is_empty():
			_starved[eid] = float(_starved.get(eid, 0.0)) + dt
			if float(_starved[eid]) > 0.25:
				# A real outage: keep moving with the last known stick input, no new presses.
				var c: Dictionary = ch.last_cmd.duplicate() if not ch.last_cmd.is_empty() else {"seq": 0, "btn": 0, "mx": 0.0, "my": 0.0, "yaw": ch.yaw, "pitch": ch.pitch, "slot": ch.wpn.want, "view_tick": tick}
				c.btn = int(c.get("btn", 0)) & (Motor.B_SPRINT | Motor.B_CROUCH | Motor.B_WALK | Motor.B_AIM | Motor.B_FIRE | Motor.B_TAB | Motor.B_LIGHT | Motor.B_USE)
				_server_apply(ch, c, dt, tick, true)
			# else: a late packet; wait for it rather than invent a step the client never took.
		else:
			_starved[eid] = 0.0
			if q.size() > 6 and Game.arg("netdebug") != null:
				print("[netdebug] server queue for %s is %d deep" % [ch.pname, q.size()])
			for i in mini(n, q.size()):
				if float(_budget[eid]) < 1.0:
					break
				_budget[eid] = float(_budget[eid]) - 1.0
				var c: Dictionary = q.pop_front()
				_server_apply(ch, c, sdt, tick, false)
				_acked[eid] = int(c.seq)
		# Presentation flags (light, aim, sprint...) for anything drawn on this machine; clients get them by snapshot.
		ch.flags = ch.compute_flags()
		if ch.mode != Motor.PLANE and _outside_world(ch):
			_rescue(ch)
		_record(ch, tick)
	projectiles.step(dt, tick)
	match_server.tick(dt)
	_server_health(dt)
	map.server_tick(dt)
	_snap_accum += 1
	if _snap_accum >= int(Defs.TICK_RATE / float(Defs.rule("net.snapshot_hz", 30))):
		_snap_accum = 0
		_send_snapshots(tick)
	_owner_sync_t -= dt
	if _owner_sync_t <= 0.0:
		_owner_sync_t = 0.1
		_send_owner_state()
	if match_server:
		match_server.note_tick_time(Time.get_ticks_usec() - t_us)


func _server_apply(ch: Character, cmd: Dictionary, dt: float, tick: int, synthetic: bool) -> void:
	var btn := int(cmd.get("btn", 0))
	var prev := ch.prev_buttons
	# Things that occupy the hands block firing.
	var tab := (btn & Motor.B_TAB) != 0 and ch.mode == Motor.GROUND
	if tab:
		ch.flags |= Character.F_TAB
		ch.wpn.cancel_reload()
	else:
		ch.flags &= ~Character.F_TAB
	ch.wpn.blocked = tab or ch.mode != Motor.GROUND or ch.water_depth() > 1.15 or ch.held_prop_id >= 0 \
		or ch.light.swapping() or not ch.health.treatment.is_empty() or ch.vault_t >= 0.0
	if ch.light.swapping():
		ch.flags |= Character.F_BUSY
	else:
		ch.flags &= ~Character.F_BUSY
	ch.injury_speed = ch.health.leg_speed()
	ch.carry_speed = ch.inv.speed_mult() * (Defs.move("carry_heavy_speed") / Defs.move("run_speed") if interaction.holding_heavy(ch) else 1.0)
	ch.events.clear()
	Motor.step(ch, cmd, dt)
	ch.last_cmd = cmd
	for e in ch.events:
		_server_motion_event(ch, e[0], float(e[1]))
	if ch.mode not in [Motor.GROUND, Motor.DOWNED]:
		return
	if ch.mode == Motor.GROUND:
		var st0: int = ch.wpn.state
		var rounds0: int = int(ch.wpn.weapon().get("mag", 0))
		var shots: Array = ch.wpn.step(cmd, dt, tick)
		_reload_sounds(ch, st0, rounds0)
		for s in shots:
			if s.get("dry", false):
				server_sound("dry_fire", ch.global_position + Vector3.UP * 1.3, 0.0, ch.eid)
				continue
			projectiles.spawn(ch, s, int(cmd.get("view_tick", tick)), tick)
			_ev_shot.rpc(ch.eid, s.origin, s.dir, float(s.velocity), str(s.ammo), str(s.weapon), int(s.seed))
			if not is_server_dedicated():
				if ch == local_char and controller:
					controller.host_shot(s)
				else:
					_ev_shot(ch.eid, s.origin, s.dir, float(s.velocity), str(s.ammo), str(s.weapon), int(s.seed))
			if match_server:
				match_server.on_shot(ch)
		for ev in ch.light.step(cmd, dt, true):
			_server_light_event(ch, ev)
	ch.weapon_id = ch.wpn.current_id()
	ch.weapon_att = Attach.bitmask(ch.wpn.weapon())
	if synthetic:
		return
	var pressed := btn & ~prev
	if (pressed & Motor.B_USE) and Game.arg("netdebug") != null and not Net.is_bot(ch.pid):
		print("[netdebug] server: %s Use edge in cmd %d (mode %d)" % [ch.pname, int(cmd.get("seq", -1)), ch.mode])
	if pressed & Motor.B_USE:
		interaction.server_use(ch, cmd)
	elif btn & Motor.B_USE:
		interaction.server_use_held(ch, cmd, dt)
	else:
		interaction.server_use_released(ch)
	if (pressed & Motor.B_TAB) and ch.mode == Motor.GROUND:
		interaction.server_tab_open(ch, cmd)
	if pressed & Motor.B_HEAL:
		interaction.server_quick_heal(ch)
	if pressed & Motor.B_GRAB:
		interaction.server_grab(ch, cmd)
	if pressed & Motor.B_PING:
		server_ping(ch)
	if pressed & Motor.B_THROW:
		grenades.server_throw(ch)
	if pressed & Motor.B_DROP:
		interaction.server_drop_held(ch, false)
	if (btn & Motor.B_FIRE) and ch.held_prop_id >= 0:
		interaction.server_throw_charge(ch, dt)
	elif ch.held_prop_id >= 0 and (prev & Motor.B_FIRE):
		interaction.server_drop_held(ch, true)
	interaction.server_hold_update(ch, cmd, dt)


func _record(ch: Character, tick: int) -> void:
	## Lag-compensation history: a ring of the last ~1 s of states. Plain Arrays are shared by reference, so writing a
	## slot copies nothing (appending to a packed array held in a Dictionary copied it, and trimming re-sliced it).
	var h: Dictionary = _history.get(ch.eid, {})
	if h.is_empty():
		var keep := int(float(Defs.rule("net.max_rewind_s", 0.3)) * Defs.TICK_RATE) + 40
		var ticks := []
		ticks.resize(keep)
		ticks.fill(-1)
		var states := []
		states.resize(keep)
		h = {"ticks": ticks, "states": states, "i": 0}
		_history[ch.eid] = h
	var i := int(h.i)
	h.ticks[i] = tick
	h.states[i] = {"pos": ch.global_position, "yaw": ch.yaw, "pitch": ch.pitch, "crouch": ch.crouch, "mode": ch.mode,
		"armed": ch.wpn.cur != WeaponState.HOLSTER}
	h.i = (i + 1) % (h.ticks as Array).size()


func _bot_lod(tick: int) -> void:
	## AI level of detail. A bot within 60 m of a living human, fighting or chasing someone, or whose squad has a
	## dead human watching, runs every tick; within 150 m every 2nd tick; farther every 4th, its step covering the
	## ticks it missed. Spread over ticks by entity id. Bots cost the server what a player's movement costs plus
	## their thinking, and nobody sees a bot 150 m away in the dark move at 15 steps a second.
	var humans := []
	var watching := {}
	for eid in characters:
		var c: Character = characters[eid]
		if Net.is_bot(c.pid):
			continue
		if c.mode in [Motor.DEAD, Motor.SPECTATE]:
			watching[c.team] = true
		else:
			humans.append(c.global_position)
	var dt := 1.0 / Defs.TICK_RATE
	var lod_off := Game.arg("bot_lod_off") != null  # every bot every tick, for comparisons
	for eid in bots:
		if not characters.has(eid):
			continue
		var ch: Character = characters[eid]
		var b = bots[eid]
		var every := 1
		if not lod_off and b.state != "fight" and int(b.target_eid) < 0 and ch.mode != Motor.PLANE and not watching.has(ch.team):
			var d2 := INF
			for hp in humans:
				d2 = minf(d2, (hp as Vector3).distance_squared_to(ch.global_position))
			every = 1 if d2 < 3600.0 else (2 if d2 < 22500.0 else 4)
		var last := int(_bot_last.get(eid, tick - 1))
		if (tick + int(eid)) % every != 0 and tick - last < every:
			_bot_dt[eid] = 0.0
			continue
		_bot_dt[eid] = dt * clampi(tick - last, 1, 4)
		_bot_last[eid] = tick


func _outside_world(ch: Character) -> bool:
	## Below the world, or past the edge of the terrain on foot / close to the ground (a canopy may still be steered
	## back from high up).
	var p := ch.global_position
	if p.y < -40.0:
		return true
	var edge: float = map.layout.HALF + 40.0
	var off_edge := absf(p.x) > edge or absf(p.z) > edge
	if not off_edge:
		return false
	return ch.mode in [Motor.GROUND, Motor.DOWNED] or p.y < 30.0


func _rescue(ch: Character) -> void:
	## Failsafe: someone left the world (fell through, flew off the edge). Put them on the nearest dry land.
	var L = map.layout
	var p := Vector2(clampf(ch.global_position.x, -L.PLAY_HALF + 20.0, L.PLAY_HALF - 20.0), clampf(ch.global_position.z, -L.PLAY_HALF + 20.0, L.PLAY_HALF - 20.0))
	for r in [0.0, 10.0, 25.0, 50.0, 80.0, 120.0]:
		var found := false
		for k in 12:
			var q = p + Vector2(cos(k * TAU / 12.0), sin(k * TAU / 12.0)) * r
			if not L.is_water(q.x, q.y) and L.in_play_area(q):
				p = q
				found = true
				break
		if found:
			break
	ch.global_position = Vector3(p.x, L.ground_height(p.x, p.y) + 1.0, p.y)
	ch.velocity = Vector3.ZERO
	print("[world] rescued %s back onto land at %s" % [ch.pname, str(ch.global_position.round())])
	if ch.mode in [Motor.FREEFALL, Motor.CHUTE]:
		server_set_mode(ch, Motor.GROUND)
	else:
		server_set_mode(ch, ch.mode)


func _reload_sounds(ch: Character, st0: int, rounds0: int) -> void:
	var feed := str(ch.wpn.def().get("feed", "mag"))
	var rounds := int(ch.wpn.weapon().get("mag", 0))
	var at: Vector3 = ch.global_position + Vector3.UP * 1.1
	if st0 != WeaponState.RELOAD and ch.wpn.state == WeaponState.RELOAD:
		# Magazine guns: the reload sequence of their class; tubes, cylinders and break actions: open up.
		var cls := str(ch.wpn.def().get("class", "rifle"))
		var seq := {"handgun": "reload_pistol", "smg": "reload_smg", "precision": "reload_sniper", "marksman": "reload_sniper"}.get(cls, "reload_rifle")
		server_sound(seq if feed == "mag" else "switch_click", at, 0.0, -1)
	elif ch.wpn.state == WeaponState.RELOAD and rounds > rounds0 and feed != "mag":
		server_sound("mag_in", at, -6.0, -1)
	elif st0 == WeaponState.RELOAD and ch.wpn.state != WeaponState.RELOAD and feed == "mag" and rounds > rounds0:
		server_sound("reload_finish", at, 0.0, -1)


func _server_motion_event(ch: Character, kind: String, value: float) -> void:
	match kind:
		"land":
			if match_server:
				match_server.on_landed(ch, value)
			var cfg_h: Dictionary = Defs.health
			var hard := float(Defs.rule("deploy.hard_landing_speed", 6.0))
			if value > float(cfg_h.get("fall_damage_speed", 7.5)):
				var lethal := float(cfg_h.get("fall_lethal_speed", 18.0))
				var dmg := pow((value - 7.5) / (lethal - 7.5), 1.6) * 100.0
				var leg := "leg_l" if randf() < 0.5 else "leg_r"
				var res: Dictionary = ch.health.apply_simple(dmg, "fall", leg)
				_after_damage(ch, res, -1)
			if value > hard:
				server_sound("land_hard", ch.global_position, 0.0, -1)
			elif value > 3.0:
				server_sound("land_soft", ch.global_position, 0.0, -1)
		"chute_open":
			server_sound("chute_open", ch.global_position + Vector3.UP * 4.0, 0.0, -1)
		"chute_land":
			if match_server:
				match_server.on_landed(ch, value)
			server_sound("chute_collapse", ch.global_position + Vector3.UP, 0.0, -1)
			if value > float(Defs.rule("deploy.injury_landing_speed", 9.5)):
				var res2: Dictionary = ch.health.apply_simple((value - 9.5) * 6.0, "landing", "leg_l" if randf() < 0.5 else "leg_r")
				_after_damage(ch, res2, -1)
		"chute_cut":
			server_sound("chute_collapse", ch.global_position + Vector3.UP * 2.0, 0.0, -1)
		"ladder":
			server_sound("ladder_step", ch.global_position + Vector3.UP * 0.9, 0.0, ch.eid)
		"jump":
			pass


func _server_light_event(ch: Character, ev: String) -> void:
	match ev:
		"on", "off", "click_dead":
			server_sound("flashlight_click", ch.eye_position(), 0.0, ch.eid)
		"swap_start":
			server_sound("battery_out", ch.eye_position() - Vector3.UP * 0.3, 0.0, ch.eid)
		"swap_done":
			server_sound("battery_in", ch.eye_position() - Vector3.UP * 0.3, 0.0, ch.eid)
		"dead":
			server_sound("flashlight_die", ch.eye_position(), 0.0, ch.eid)
	ch.inv.dirty = true


func _server_health(dt: float) -> void:
	for ch in characters.values():
		if ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
			continue
		var res: Dictionary = ch.health.tick(dt)
		interaction.server_treatment_tick(ch, dt)
		if res.killed:
			_after_damage(ch, res, ch.health.last_attacker)
		if ch.health.downed and ch.mode == Motor.GROUND:
			server_set_mode(ch, Motor.DOWNED)
			ch.wpn.cur = WeaponState.HOLSTER


func server_can_be_downed(ch: Character) -> bool:
	if Net.team_size() <= 1:
		return false
	for o in characters.values():
		if o != ch and o.team == ch.team and o.mode in [Motor.GROUND, Motor.FREEFALL, Motor.CHUTE] and not o.health.downed:
			return true
	return false


func server_projectile_hit_character(ch: Character, part: String, p: Dictionary, dir: Vector3, pos: Vector3, normal: Vector3) -> Dictionary:
	var speed := (p.vel as Vector3).length()
	var e := Ballistics.energy(p.mass, speed)
	var res: Dictionary = ch.health.apply_hit(part, e, Defs.ammo(str(p.ammo)), float(p.e0), dir, int(p.seed), int(p.shooter))
	var absorbed: String = res.get("absorbed_by", "")
	if float(res.damage) > 0.5 and not res.get("killed", false):
		server_sound("headshot" if part == "head" else "player_hit", ch.global_position + Vector3.UP * (1.6 if part == "head" else 1.1), 0.0, -1)
	_ev_hit.rpc(ch.eid, part, pos, dir, absorbed, bool(res.get("armor_broken", false)), float(res.damage))
	if not is_server_dedicated():
		_ev_hit(ch.eid, part, pos, dir, absorbed, bool(res.get("armor_broken", false)), float(res.damage))
	_after_damage(ch, res, int(p.shooter))
	return res


@rpc("authority", "call_remote", "reliable")
func ev_grenade(id: int, p: Vector3, v: Vector3, fuse: float) -> void:
	if grenades:
		grenades.spawn(id, p, v, fuse)


@rpc("authority", "call_remote", "reliable")
func ev_explode(id: int, pos: Vector3) -> void:
	if grenades:
		grenades.explode_visual(id, pos)


func server_after_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	_after_damage(ch, res, attacker)


func _count_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	## Damage dealt to the other teams, for XP and the stats.
	if match_server and match_server.stats.has(attacker) and attacker != ch.eid and team_of(attacker) != ch.team:
		match_server.stats[attacker].damage = float(match_server.stats[attacker].damage) + float(res.get("damage", 0.0))


func _after_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	_count_damage(ch, res, attacker)
	if res.get("downed", false):
		server_set_mode(ch, Motor.DOWNED)
		ch.wpn.cur = WeaponState.HOLSTER
		ch.light.on = false
		interaction.server_drop_held(ch, false)
		server_sound("downed", ch.global_position + Vector3.UP * 0.4, 0.0, -1)
		if match_server:
			match_server.on_downed(ch, attacker)
	if res.get("killed", false) and ch.mode != Motor.DEAD:
		server_sound("death", ch.global_position + Vector3.UP * 1.2, 0.0, -1)
		interaction.server_drop_held(ch, false)
		var impulse := Vector3.ZERO
		if attacker >= 0 and characters.has(attacker):
			impulse = (ch.global_position - characters[attacker].global_position).normalized() * 3.0
		map.server_spawn_corpse(ch, impulse)
		server_set_mode(ch, Motor.DEAD)
		if match_server:
			match_server.on_killed(ch, attacker)
		server_remove_character(ch)


# ------------------------------------------------------------------ snapshots

func _send_snapshots(tick: int) -> void:
	var enemy_r := float(Defs.rule("relevance.enemy_radius", 180.0))
	var prop_r := float(Defs.rule("relevance.prop_radius", 70.0))
	for pid in Net.human_peers():
		var me := char_by_pid(pid)
		var viewer_pos := Vector3.ZERO
		var viewer_team := int(Net.players.get(pid, {}).get("team", -1))
		if me:
			viewer_pos = me.global_position
		elif characters.has(spectate_target(pid)):
			viewer_pos = characters[spectate_target(pid)].global_position
		var others := []
		for ch in characters.values():
			if ch == me:
				continue
			if ch.team != viewer_team and ch.global_position.distance_to(viewer_pos) > enemy_r and ch.mode != Motor.PLANE:
				continue
			others.append(ch)
		var props: Array = map.awake_props_near(viewer_pos, prop_r)
		var bytes := Snapshot.encode(tick, _acked.get(me.eid, 0) if me else 0, me, others, props, _weapon_ids)
		Net.send_snapshot(pid, bytes)


func spectate_target(pid: int) -> int:
	var team := int(Net.players.get(pid, {}).get("team", -1))
	for ch in characters.values():
		if ch.team == team:
			return ch.eid
	return characters.keys()[0] if not characters.is_empty() else -1


func _ready() -> void:
	Net.snapshot_received.connect(_on_snapshot)


func _on_snapshot(bytes: PackedByteArray) -> void:
	if is_server:
		return
	var s: Dictionary = Snapshot.decode(bytes, _weapon_ids)
	if s.is_empty():
		return
	Net.on_snapshot_tick(int(s.tick))
	if local_char and s.has("own") and controller:
		controller.reconcile(int(s.ack), s.own)
	for o in s.others:
		var ch: Character = characters.get(int(o.eid))
		if ch and ch.is_remote:
			ch.push_snapshot(float(s.tick), o)
	for pr in s.props:
		map.client_prop_snapshot(int(pr.id), pr.pos, pr.rot, float(s.tick))


func _send_owner_state() -> void:
	for ch in characters.values():
		if ch.mode == Motor.DEAD or Net.is_bot(ch.pid):
			continue
		if ch.health.dirty or ch.inv.dirty:
			var hd: Dictionary = ch.health.to_dict()
			var idict: Dictionary = ch.inv.to_dict()
			ch.health.dirty = false
			ch.inv.dirty = false
			if ch.pid == Net.local_pid:
				if hud:
					hud.on_owner_state()
				continue
			if not Net.players.get(ch.pid, {}).get("connected", false):
				continue
			_owner_state.rpc_id(ch.pid, hd, idict)


@rpc("authority", "call_remote", "reliable")
func _owner_state(hd: Dictionary, idict: Dictionary) -> void:
	if local_char == null:
		return
	local_char.health.from_dict(hd)
	local_char.inv.from_dict(idict)
	local_char.injury_speed = local_char.health.leg_speed()
	if hud:
		hud.on_owner_state()


# ------------------------------------------------------------------ events: sound

var _ping_t: Dictionary = {}     # eid -> time of the last ping (s)


func server_ping(ch: Character) -> void:
	## V: a click on the team radio and this player's position blinking on every teammate's minimap for 5 s. The
	## click comes out of the radio itself, so anyone close enough hears it, enemies included (bots turn to look).
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_ping_t.get(ch.eid, -10.0)) < 1.0 or ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
		return
	_ping_t[ch.eid] = now
	var pos := ch.global_position
	server_sound("radio_click", pos + Vector3.UP * 1.3, 0.0, -1)
	for pid in Net.human_peers():
		if int(Net.players[pid].get("team", -1)) == ch.team:
			_ev_ping.rpc_id(pid, ch.eid, pos)
	if not is_server_dedicated() and int(Net.players.get(Net.local_pid, {}).get("team", -1)) == ch.team:
		_ev_ping(ch.eid, pos)
	var heard := float(SoundSys.defs.get("radio_click", {}).get("dist", 18.0))
	for eid in bots:
		var b = bots[eid]
		if b.ch.team != ch.team and b.ch.global_position.distance_to(pos) < heard:
			b.hear(pos, heard)


@rpc("authority", "call_remote", "reliable")
func _ev_ping(eid: int, pos: Vector3) -> void:
	if hud:
		hud.add_ping(eid, pos)


func server_sound(id: String, pos: Vector3, db: float = 0.0, except_eid: int = -1) -> void:
	## Plays a sound for every client close enough to hear it (the source's own client may already have played it).
	var d: Dictionary = SoundSys.defs.get(id, {})
	var radius := float(d.get("dist", 40.0)) * 1.1
	for pid in Net.human_peers():
		var ch := char_by_pid(pid)
		if except_eid >= 0 and ch and ch.eid == except_eid:
			continue
		if ch and ch.global_position.distance_to(pos) > radius:
			continue
		_ev_sound.rpc_id(pid, id, pos, db)
	if not is_server_dedicated():
		# The host's own character is not predicted, so its sounds are always played here.
		_ev_sound(id, pos, db)


@rpc("authority", "call_remote", "reliable")
func _ev_sound(id: String, pos: Vector3, db: float) -> void:
	SoundSys.play_at(id, pos, db)


func voice_targets(from_pid: int) -> Array:
	## Who receives a transmission, and how: [pid, src_eid, kind]. Teammates hear it on their own radios (kind 0).
	## Everyone else hears it only by being close: to the speaker (kind 2, their voice) or to one of the radios it
	## comes out of (kind 1, a teammate's, tinny and quiet) - eavesdropping, as in life.
	var out := []
	var team := int(Net.players.get(from_pid, {}).get("team", -1))
	var sources := radio_sources(from_pid)
	for pid in Net.players:
		var p: Dictionary = Net.players[pid]
		if pid == from_pid or p.bot or not p.connected:
			continue
		if int(p.team) == team:
			out.append([pid, -1, 0])
			continue
		if sources.is_empty():
			continue
		var lc := char_by_pid(pid)
		if lc == null or lc.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
			continue
		var best: Array = []
		var best_d := INF
		for s in sources:
			var d: float = (s[1] as Vector3).distance_to(lc.global_position + Vector3.UP * 1.5)
			if d < float(s[3]) and d < best_d:
				best_d = d
				best = s
		if not best.is_empty():
			out.append([pid, int(best[0]), int(best[2])])
	return out


func radio_sources(from_pid: int) -> Array:
	## Where a transmission can be overheard: [eid, position, kind, radius]. Kind 2 is the speaker's own voice, kind 1
	## each living teammate's radio playing it. Nothing in the aircraft (everyone is aboard together).
	if not bool(Defs.rule("radio.eavesdrop", true)):
		return []
	var sp := char_by_pid(from_pid)
	var team := int(Net.players.get(from_pid, {}).get("team", -1))
	var out := []
	var rr := float(Defs.rule("radio.eavesdrop_radius", 12.0))
	if sp and sp.mode not in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
		out.append([sp.eid, sp.global_position + Vector3.UP * 1.5, 2, float(Defs.rule("radio.voice_radius", 9.0))])
	for c in characters.values():
		if c.team == team and c != sp and c.mode not in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
			out.append([c.eid, c.global_position + Vector3.UP * 1.35, 1, rr])
	return out


func server_radio_event(pid: int, kind: String) -> void:
	## Key down: the push-to-talk click on the speaker and the squelch opening on every teammate's radio; key up: the
	## release click and each radio's squelch tail. All of them are heard by whoever is near (enemies included), and
	## bots of other teams near any of those radios turn toward it.
	var ch := char_by_pid(pid)
	if ch == null:
		return
	var team := ch.team
	var alive := ch.mode not in [Motor.DEAD, Motor.PLANE, Motor.SPECTATE]
	if kind == "on":
		ch.flags |= Character.F_RADIO
		if alive:
			server_sound("radio_key", ch.global_position + Vector3.UP * 1.35, 0.0, ch.eid)
	else:
		ch.flags &= ~Character.F_RADIO
		if alive:
			server_sound("radio_off", ch.global_position + Vector3.UP * 1.35, 0.0, ch.eid)
	var heard := float(Defs.rule("radio.eavesdrop_radius", 12.0))
	for c in characters.values():
		if c.team != team or c == ch or c.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
			continue
		var rp: Vector3 = c.global_position + Vector3.UP * 1.35
		server_sound("radio_on" if kind == "on" else "radio_squelch", rp, 0.0, -1)
		if kind == "on":
			for eid in bots:
				var b = bots[eid]
				if b.ch.team != team and b.ch.global_position.distance_to(rp) < heard:
					b.hear(rp, heard)


# ------------------------------------------------------------------ events: combat

@rpc("authority", "call_remote", "reliable")
func _ev_shot(eid: int, origin: Vector3, dir: Vector3, velocity: float, ammo: String, weapon: String, seed: int) -> void:
	if local_char and local_char.eid == eid:
		return  # already predicted locally
	if effects:
		effects.shot(characters.get(eid), origin, dir, velocity, ammo, weapon, seed)


func server_impact(pos: Vector3, normal: Vector3, kind: String, what: String, shooter: int, shot_id: int, mat: String = "", att: int = 0) -> void:
	## att: what the mark hangs on (1 << 24 | door, 2 << 24 | shutter, 3 << 24 | prop), 0 for the static world.
	_ev_impact.rpc(pos, normal, kind, what, shooter, mat, att)
	if not is_server_dedicated():
		_ev_impact(pos, normal, kind, what, shooter, mat, att)


@rpc("authority", "call_remote", "unreliable")
func _ev_impact(pos: Vector3, normal: Vector3, kind: String, what: String, shooter: int, mat: String = "", att: int = 0) -> void:
	if effects:
		effects.impact(pos, normal, kind, what, mat, att)


@rpc("authority", "call_remote", "reliable")
func _ev_hit(eid: int, part: String, pos: Vector3, dir: Vector3, absorbed: String, armor_broken: bool, damage: float) -> void:
	if effects:
		effects.body_hit(characters.get(eid), part, pos, dir, absorbed, armor_broken, damage)
	if local_char and local_char.eid == eid and controller:
		controller.on_hit(part, dir, damage, absorbed)


func server_flyby(ch: Character, pos: Vector3, speed: float, dist: float) -> void:
	if ch.pid == Net.local_pid and not is_server_dedicated():
		_ev_flyby(pos, speed, dist)
	elif not Net.is_bot(ch.pid):
		_ev_flyby.rpc_id(ch.pid, pos, speed, dist)
	if bots.has(ch.eid):
		bots[ch.eid].on_flyby(pos)


@rpc("authority", "call_remote", "unreliable")
func _ev_flyby(pos: Vector3, speed: float, dist: float) -> void:
	if effects:
		effects.flyby(pos, speed, dist)


func server_glass_hit(collider, pos: Vector3, dir: Vector3, energy: float) -> void:
	map.server_break_glass(collider, pos, dir)


func server_prop_hit(prop_id: int, pos: Vector3, dir: Vector3, energy: float, momentum: float) -> void:
	map.server_prop_hit(prop_id, pos, dir, energy, momentum)


func server_corpse_hit(corpse_id: int, pos: Vector3, dir: Vector3, normal: Vector3) -> void:
	map.server_corpse_hit(corpse_id, pos, dir)
	_ev_impact.rpc(pos, normal, "flesh", "hole", -1, "flesh", 0)
	if not is_server_dedicated():
		_ev_impact(pos, normal, "flesh", "hole", -1, "flesh", 0)


func server_wake_prop(prop_id: int, by: Character, dir: Vector3, vel: Vector3) -> void:
	map.server_push_prop(prop_id, by, dir, vel)


# ------------------------------------------------------------------ late join

func server_send_items(pid: int) -> void:
	## Late joiners built the same floor loot from the match seed (ids 1..floor_count): send only what changed since,
	## the items taken and the items dropped.
	var gone := PackedInt32Array()
	var ids := PackedInt32Array()
	var entries := []
	var xfs := []
	for id in range(1, map.dyn.floor_count + 1):
		if not map.dyn.items.has(id):
			gone.append(id)
	for id in map.dyn.items:
		if id > map.dyn.floor_count:
			ids.append(id)
			entries.append(map.dyn.items[id].entry)
			xfs.append(map.dyn.items[id].xf)
	_items_delta.rpc_id(pid, map.dyn.floor_count, gone, ids, entries, xfs)
	print("[net] floor items to %d: %d taken, %d dropped" % [pid, gone.size(), ids.size()])


@rpc("authority", "call_remote", "reliable")
func _items_delta(floor_count: int, gone: PackedInt32Array, ids: PackedInt32Array, entries: Array, xfs: Array) -> void:
	## Items on the ground for a late joiner: remove the taken ones, add the dropped ones.
	if map == null:
		return
	if floor_count != map.dyn.floor_count:
		push_warning("[net] floor loot differs from the server's (%d vs %d items)" % [map.dyn.floor_count, floor_count])
	for id in gone:
		map.dyn.remove_item(id)
	for i in ids.size():
		if not map.dyn.items.has(ids[i]):
			map.dyn.client_spawn_item(ids[i], entries[i], xfs[i])


func map_box_opened_server(cid: int) -> void:
	map.dyn.set_box_open(cid, true)
	_box_opened.rpc(PackedInt32Array([cid]))


@rpc("authority", "call_remote", "reliable")
func _box_opened(cids: PackedInt32Array) -> void:
	if map == null:
		return
	for cid in cids:
		map.dyn.set_box_open(cid, true)


# ------------------------------------------------------------------ test commands (server must run with --testcheats)

func test_cmd(cmd: Dictionary) -> void:
	if is_server:
		_test_apply(local_char, cmd)
	else:
		_test_req.rpc_id(1, cmd)


@rpc("any_peer", "reliable")
func _test_req(cmd: Dictionary) -> void:
	if is_server:
		_test_apply(char_by_pid(multiplayer.get_remote_sender_id()), cmd)


func _test_apply(ch: Character, cmd: Dictionary) -> void:
	if ch == null or Game.arg("testcheats") == null:
		return
	match str(cmd.get("op", "")):
		"teleport":
			ch.global_position = cmd.pos
			ch.velocity = Vector3.ZERO
			ch.yaw = float(cmd.get("yaw", ch.yaw))
		"give":
			interaction.give(ch, (cmd.entry as Dictionary).duplicate(true))
			ch.inv.mark_dirty()


func server_sync_late_peer(pid: int) -> void:
	for ch in characters.values():
		_spawn_char.rpc_id(pid, ch.eid, ch.pid, ch.team, ch.pname, ch.global_position, ch.mode)
	map.server_sync_peer(pid)
	if match_server:
		match_server.sync_peer(pid)
	_match_started.rpc_id(pid)


@rpc("authority", "call_remote", "reliable")
func _match_started() -> void:
	client_match_started()


# ------------------------------------------------------------------ interpolation (clients)

func _process(dt: float) -> void:
	if is_server:
		return
	var rt := Net.interp_tick()
	for ch in characters.values():
		if ch.is_remote:
			ch.interpolate(rt)
	if map:
		map.client_interpolate(rt)


# ------------------------------------------------------------------ map events

func map_door_state(door, what: String) -> void:
	## Server: a door or shutter changed. Everyone animates the same swing; sounds come from the door.
	var is_shutter: bool = door.is_shutter
	var did: int = int(door.spec.id)
	map_door_ev.rpc(did, is_shutter, door.angle, door.target, door.locked, what)
	match what:
		"open":
			server_sound("door_open" if not is_shutter else "shutter_open", door.center(), 0.0, -1)
		"close":
			pass
		"latched":
			server_sound("door_close", door.center(), 0.0, -1)
		"locked":
			server_sound("door_locked", door.center(), 0.0, -1)
		"unlock":
			server_sound("door_unlock", door.center(), 0.0, -1)
		"forced":
			server_sound("door_burst", door.center(), 0.0, -1)
		"blocked":
			server_sound("door_bump", door.center(), 0.0, -1)


func map_door_swing(door) -> void:
	## Server: a door swinging loose after a push; clients follow its angle and swing speed (about 10 a second).
	_map_door_swing.rpc(int(door.spec.id), door.angle, door.omega)


@rpc("authority", "call_remote", "unreliable_ordered")
func _map_door_swing(did: int, angle: float, omega: float) -> void:
	if map and did >= 0 and did < map.dyn.doors.size():
		var d = map.dyn.doors[did].get("node")
		if d:
			d.set_swing(angle, omega)


@rpc("authority", "call_remote", "reliable")
func map_door_ev(did: int, is_shutter: bool, angle: float, target: float, locked: bool, what: String) -> void:
	if map == null:
		return
	var d = null
	if is_shutter:
		if did >= 0 and did < map.dyn.windows.size():
			d = map.dyn.windows[did].get("door")
	elif did >= 0 and did < map.dyn.doors.size():
		d = map.dyn.doors[did].get("node")
	if d:
		d.set_target(target, angle, locked)


@rpc("authority", "call_remote", "reliable")
func map_window_broken(wid: int, pos: Vector3, dir: Vector3) -> void:
	if map and map.dyn.break_window(wid, pos, dir) and effects:
		effects.glass_break(pos, dir, map.dyn.windows[wid])


func map_item_spawn_server(e: Dictionary, xf: Transform3D) -> void:
	map.dyn.server_spawn_item(e, xf, true)


@rpc("authority", "call_remote", "reliable")
func map_item_spawn(id: int, e: Dictionary, xf: Transform3D) -> void:
	if map:
		map.dyn.client_spawn_item(id, e, xf)


func map_item_remove(id: int) -> void:
	map.dyn.remove_item(id)
	map_item_removed.rpc(id)


@rpc("authority", "call_remote", "reliable")
func map_item_removed(id: int) -> void:
	if map:
		map.dyn.remove_item(id)


@rpc("authority", "call_remote", "reliable")
func map_prop_activate(id: int, xf: Transform3D) -> void:
	if map:
		map.dyn.client_activate(id, xf)


@rpc("authority", "call_remote", "reliable")
func map_prop_rest(id: int, xf: Transform3D) -> void:
	if map:
		map.dyn.client_prop_rest(id, xf)


@rpc("authority", "call_remote", "reliable")
func map_prop_break(id: int, pos: Vector3, impulse: Vector3) -> void:
	if map:
		map.dyn.client_break_prop(id, pos, impulse)


@rpc("authority", "call_remote", "reliable")
func map_prop_chunk(id: int, key: int, impulse: Vector3) -> void:
	if map:
		map.dyn.client_prop_chunk(id, key, impulse)


@rpc("authority", "call_remote", "reliable")
func map_prop_chunks(id: int, keys: PackedInt32Array) -> void:
	if map:
		map.dyn.client_prop_chunks(id, keys)


func _door_by(did: int, is_shutter: bool):
	if map == null:
		return null
	if is_shutter:
		if did >= 0 and did < map.dyn.windows.size():
			return map.dyn.windows[did].get("door")
		return null
	if did >= 0 and did < map.dyn.doors.size():
		return map.dyn.doors[did].get("node")
	return null


func server_door_hit(door, pos: Vector3, dir: Vector3, energy: float) -> void:
	var i: int = door.server_damage(pos, energy * 0.08)
	if i >= 0:
		server_door_panel(door, i, dir)


func server_door_panel(door, i: int, dir: Vector3) -> void:
	map_door_panel.rpc(int(door.spec.id), door.is_shutter, i, dir)
	_door_panel_local(door, i, dir)


@rpc("authority", "call_remote", "reliable")
func map_door_panel(did: int, is_shutter: bool, i: int, dir: Vector3) -> void:
	var d = _door_by(did, is_shutter)
	if d:
		_door_panel_local(d, i, dir)


@rpc("authority", "call_remote", "reliable")
func map_door_panels(did: int, is_shutter: bool, panels: PackedInt32Array) -> void:
	## Late join: panels already shot out, without effects.
	var d = _door_by(did, is_shutter)
	if d:
		for i in panels:
			d.lose_panel(i)


func _door_panel_local(d, i: int, dir: Vector3) -> void:
	var xf: Transform3D = d.current_transform()
	var box: AABB = d.panel_box(i)
	var standing: Array = []
	var fell: bool = d.lose_panel(i)
	if fell:
		for j in d.panels().size():
			if not d.lost.has(j) or j == i:
				standing.append(d.panel_box(j))
	if effects:
		if d.anchor:
			effects.holes.clear_box(d.anchor, box.grow(0.03))
			if fell:
				effects.holes.forget(d.anchor)
		effects.door_panel_lost(d, xf, box, dir, standing)


@rpc("authority", "call_remote", "reliable")
func map_corpse_spawn(id: int, who: String, team: int, xforms: Array) -> void:
	if map:
		map.dyn.client_spawn_corpse(id, who, team, xforms)


func corpse_pose(id: int, xforms: Array, final: bool) -> void:
	map_corpse_pose.rpc(id, xforms, final)


@rpc("authority", "call_remote", "unreliable_ordered")
func map_corpse_pose(id: int, xforms: Array, final: bool) -> void:
	if map and map.dyn.corpses.has(id):
		map.dyn.corpses[id].client_pose(xforms, final)


# ------------------------------------------------------------------ containers and inventory requests

func send_container(ch, kind: String, id: int, entries: Array) -> void:
	if ch.pid == Net.local_pid and not is_server_dedicated():
		_container_view(kind, id, entries)
	elif not Net.is_bot(ch.pid):
		_container_view.rpc_id(ch.pid, kind, id, entries)


@rpc("authority", "call_remote", "reliable")
func _container_view(kind: String, id: int, entries: Array) -> void:
	if hud:
		hud.show_container(kind, id, entries)


func request_inventory(req: Dictionary) -> void:
	## Client (or host) asks the server to change its inventory.
	if is_server:
		if local_char:
			interaction.server_inventory_request(local_char, req)
	else:
		_inv_req.rpc_id(1, req)


@rpc("any_peer", "reliable")
func _inv_req(req: Dictionary) -> void:
	if not is_server:
		return
	var ch := char_by_pid(multiplayer.get_remote_sender_id())
	if ch and ch.mode in [Motor.GROUND, Motor.DOWNED]:
		interaction.server_inventory_request(ch, req)


# ------------------------------------------------------------------ match state

var match_info: Dictionary = {}


@rpc("authority", "call_remote", "reliable")
func match_state(info: Dictionary) -> void:
	match_info = info
	if hud:
		hud.on_match_state(info)
	if effects:
		effects.on_match_state(info)


@rpc("authority", "call_remote", "reliable")
func match_toast(text: String, sound: String) -> void:
	if hud:
		hud.toast(text)
	if sound != "":
		SoundSys.play_local(sound)


func plane_pos(tick: float) -> Vector3:
	return MatchServer.plane_at(match_info.get("plane", {}), tick)


func zone_circle(tick: float) -> Array:
	return MatchServer.circle_at(match_info.get("zone", {}), tick)
