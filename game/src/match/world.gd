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
var interaction = null
var bots: Dictionary = {}        # eid -> BotBrain
var spectate_eid := -1

var _next_eid := 1
var _queues: Dictionary = {}     # eid -> Array of cmds
var _acked: Dictionary = {}      # eid -> last processed seq
var _history: Dictionary = {}    # eid -> {ticks: PackedInt32Array, states: Array}
var _snap_accum := 0
var _owner_sync_t := 0.0
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
	interaction = Interaction.new(self)
	if DisplayServer.get_name() != "headless":
		effects = Effects.new()
		effects.name = "Effects"
		add_child(effects)
		effects.setup(self)
		hud = Hud.new()
		hud.name = "Hud"
		Game.ui.add_child(hud)
		hud.setup(self)
	if is_server:
		projectiles = ProjectileServer.new(self)
		match_server = MatchServer.new()
		match_server.name = "MatchServer"
		add_child(match_server)
		match_server.setup(self)


func teardown() -> void:
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
	var h: Dictionary = _history.get(eid, {})
	if h.is_empty():
		return {}
	var ticks: PackedInt32Array = h.ticks
	var states: Array = h.states
	var n := ticks.size()
	for i in range(n - 1, -1, -1):
		if ticks[i] <= tick:
			return states[i]
	return states[0] if n > 0 else {}


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
	_char_mode.rpc(ch.eid, mode, ch.global_position)


@rpc("authority", "call_remote", "reliable")
func _char_mode(eid: int, mode: int, pos: Vector3) -> void:
	var ch: Character = characters.get(eid)
	if ch == null:
		return
	ch.mode = mode
	if ch.is_local:
		ch.global_position = pos
		ch.velocity = Vector3.ZERO
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
	# A client cannot bank commands to move faster than real time.
	while q.size() > 12:
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
	var tick := Net.tick
	for eid in bots.keys():
		if characters.has(eid):
			server_queue_cmds(eid, [bots[eid].think(dt, tick)])
	for eid in characters.keys():
		var ch: Character = characters[eid]
		if ch.mode in [Motor.DEAD, Motor.SPECTATE]:
			continue
		var q: Array = _queues[eid]
		var n := 1 if q.size() <= 3 else 2
		if q.is_empty():
			# Packet loss: keep moving with the last known stick input, no new presses.
			var c: Dictionary = ch.last_cmd.duplicate() if not ch.last_cmd.is_empty() else {"seq": 0, "btn": 0, "mx": 0.0, "my": 0.0, "yaw": ch.yaw, "pitch": ch.pitch, "slot": ch.wpn.want, "view_tick": tick}
			c.btn = int(c.get("btn", 0)) & (Motor.B_SPRINT | Motor.B_CROUCH | Motor.B_WALK | Motor.B_AIM | Motor.B_FIRE | Motor.B_TAB | Motor.B_LIGHT | Motor.B_USE)
			_server_apply(ch, c, dt, tick, true)
		else:
			for i in mini(n, q.size()):
				var c: Dictionary = q.pop_front()
				_server_apply(ch, c, dt, tick, false)
				_acked[eid] = int(c.seq)
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
		or ch.light.swapping() or not ch.health.treatment.is_empty()
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
		var shots: Array = ch.wpn.step(cmd, dt, tick)
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
	if synthetic:
		return
	var pressed := btn & ~prev
	if pressed & Motor.B_USE:
		interaction.server_use(ch, cmd)
	elif btn & Motor.B_USE:
		interaction.server_use_held(ch, cmd, dt)
	else:
		interaction.server_use_released(ch)
	if pressed & Motor.B_HEAL:
		interaction.server_quick_heal(ch)
	if pressed & Motor.B_DROP:
		interaction.server_drop_held(ch, false)
	if (btn & Motor.B_FIRE) and ch.held_prop_id >= 0:
		interaction.server_throw_charge(ch, dt)
	elif ch.held_prop_id >= 0 and (prev & Motor.B_FIRE):
		interaction.server_drop_held(ch, true)
	interaction.server_hold_update(ch, cmd, dt)


func _record(ch: Character, tick: int) -> void:
	if not _history.has(ch.eid):
		_history[ch.eid] = {"ticks": PackedInt32Array(), "states": []}
	var h: Dictionary = _history[ch.eid]
	h.ticks.append(tick)
	h.states.append({"pos": ch.global_position, "yaw": ch.yaw, "pitch": ch.pitch, "crouch": ch.crouch, "mode": ch.mode,
		"armed": ch.wpn.cur != WeaponState.HOLSTER})
	var keep := int(float(Defs.rule("net.max_rewind_s", 0.3)) * Defs.TICK_RATE) + 40
	if h.ticks.size() > keep:
		h.ticks = h.ticks.slice(h.ticks.size() - keep)
		h.states = h.states.slice(h.states.size() - keep)


func _server_motion_event(ch: Character, kind: String, value: float) -> void:
	match kind:
		"land":
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
			server_sound("chute_collapse", ch.global_position + Vector3.UP, 0.0, -1)
			if value > float(Defs.rule("deploy.injury_landing_speed", 9.5)):
				var res2: Dictionary = ch.health.apply_simple((value - 9.5) * 6.0, "landing", "leg_l" if randf() < 0.5 else "leg_r")
				_after_damage(ch, res2, -1)
		"chute_cut":
			server_sound("chute_collapse", ch.global_position + Vector3.UP * 2.0, 0.0, -1)
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
	_ev_hit.rpc(ch.eid, part, pos, dir, absorbed, bool(res.get("armor_broken", false)), float(res.damage))
	if not is_server_dedicated():
		_ev_hit(ch.eid, part, pos, dir, absorbed, bool(res.get("armor_broken", false)), float(res.damage))
	_after_damage(ch, res, int(p.shooter))
	return res


func _after_damage(ch: Character, res: Dictionary, attacker: int) -> void:
	if res.get("downed", false):
		server_set_mode(ch, Motor.DOWNED)
		ch.wpn.cur = WeaponState.HOLSTER
		ch.light.on = false
		interaction.server_drop_held(ch, false)
		server_sound("downed", ch.global_position + Vector3.UP * 0.4, 0.0, -1)
		if match_server:
			match_server.on_downed(ch, attacker)
	if res.get("killed", false) and ch.mode != Motor.DEAD:
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


func server_radio_event(pid: int, kind: String) -> void:
	var ch := char_by_pid(pid)
	if ch == null or ch.mode in [Motor.DEAD, Motor.PLANE]:
		return
	if kind == "on":
		ch.flags |= Character.F_RADIO
		server_sound("radio_on", ch.global_position + Vector3.UP * 1.35, 0.0, -1)
	else:
		ch.flags &= ~Character.F_RADIO
		server_sound("radio_off", ch.global_position + Vector3.UP * 1.35, 0.0, -1)


# ------------------------------------------------------------------ events: combat

@rpc("authority", "call_remote", "reliable")
func _ev_shot(eid: int, origin: Vector3, dir: Vector3, velocity: float, ammo: String, weapon: String, seed: int) -> void:
	if local_char and local_char.eid == eid:
		return  # already predicted locally
	if effects:
		effects.shot(characters.get(eid), origin, dir, velocity, ammo, weapon, seed)


func server_impact(pos: Vector3, normal: Vector3, kind: String, what: String, shooter: int, shot_id: int) -> void:
	_ev_impact.rpc(pos, normal, kind, what, shooter)
	if not is_server_dedicated():
		_ev_impact(pos, normal, kind, what, shooter)


@rpc("authority", "call_remote", "unreliable")
func _ev_impact(pos: Vector3, normal: Vector3, kind: String, what: String, shooter: int) -> void:
	if effects:
		effects.impact(pos, normal, kind, what)


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
	_ev_impact.rpc(pos, normal, "flesh", "hole", -1)
	if not is_server_dedicated():
		_ev_impact(pos, normal, "flesh", "hole", -1)


func server_wake_prop(prop_id: int, by: Character, dir: Vector3, vel: Vector3) -> void:
	map.server_push_prop(prop_id, by, dir, vel)


# ------------------------------------------------------------------ late join

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
