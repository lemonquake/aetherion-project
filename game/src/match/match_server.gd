extends Node
## Server-side match flow: aircraft pass and team jumps, the encroaching haze (shrinking safe zone), eliminations,
## the winner, and the results summary. Clients receive compact state through World.match_state RPCs and compute
## the plane position and the zone circle from shared start ticks.

const WeaponState := preload("res://src/weapons/weapon_state.gd")

var world = null
var phase := "idle"          # idle, plane, playing, ended
var plane := {}              # {a: Vector3, b: Vector3, speed, t0 (tick), dur (s)}
var zone := {}               # {i, state, t0, t1, c0: Vector2, r0, c1: Vector2, r1, dps}
var stats: Dictionary = {}   # eid -> {kills, damage, downs, alive_t, placed}
var team_alive: Dictionary = {}
var initial_teams := 0
var eliminated_order: Array = []
var _zone_rng := RandomNumberGenerator.new()
var _t := 0.0
var _warned := {}
var _forced_jump := false
var _status_t := 0.0
var _tick_us := PackedInt32Array()  # server tick durations since the last status line
var shots_fired := 0
var landed := {}
## Match log on stdout: always on a dedicated server, or with --matchlog.
var _log_on := false


func setup(w) -> void:
	world = w
	_zone_rng.seed = Game.match_seed + 31
	_log_on = Net.dedicated or Game.arg("matchlog") != null


func log_event(msg: String) -> void:
	if _log_on:
		print("[match %6.1f] %s" % [_t, msg])


# ------------------------------------------------------------------ start

func start() -> void:
	var L = world.map.layout
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.match_seed
	# Flight path: a random line through the middle third of the map.
	var ang := rng.randf() * TAU
	var k: float = L.MAP_SCALE
	var mid := Vector2(rng.randf_range(-150, 150), rng.randf_range(-150, 120)) * k
	var dir := Vector2(cos(ang), sin(ang))
	var reach := 760.0 * k
	var alt := float(Defs.rule("plane.altitude", 320.0))
	plane = {"a": Vector3(mid.x - dir.x * reach, alt, mid.y - dir.y * reach), "b": Vector3(mid.x + dir.x * reach, alt, mid.y + dir.y * reach),
		"speed": float(Defs.rule("plane.speed", 70.0)) * 0.65, "t0": Net.tick, "jump_after": float(Defs.rule("plane.pre_jump_delay_s", 6.0))}
	plane.dur = (plane.a as Vector3).distance_to(plane.b) / float(plane.speed)
	# The part of the path over the play area: jumping opens when the aircraft enters it, and whoever is still
	# aboard leaves just before it crosses out again.
	var first := -1.0
	var last := -1.0
	for i in 401:
		var f := i / 400.0
		var q: Vector3 = (plane.a as Vector3).lerp(plane.b, f)
		if L.in_play_area(Vector2(q.x, q.z)) and not L.is_water(q.x, q.z):
			if first < 0.0:
				first = f
			last = f
	if first < 0.0:
		first = 0.4
		last = 0.6
	plane.open_s = maxf(first * float(plane.dur), float(plane.get("jump_after", 0.0)))
	plane.close_s = maxf(last * float(plane.dur) - 1.5, float(plane.open_s) + 5.0)
	# Characters board the plane.
	var teams := {}
	for pid in Net.players:
		var p: Dictionary = Net.players[pid]
		var ch: Character = world.server_spawn_character(pid, int(p.team), str(p.name), plane.a, Motor.PLANE)
		_loadout(ch)
		stats[ch.eid] = {"pid": pid, "name": p.name, "team": p.team, "kills": 0, "damage": 0.0, "downs": 0, "alive_t": 0.0, "placed": 0, "bot": p.bot}
		teams[int(p.team)] = true
	initial_teams = teams.size()
	phase = "plane"
	log_event("start: %d players, %d teams, plane %s -> %s" % [stats.size(), initial_teams, str(plane.a), str(plane.b)])
	# First zone: covers nearly the whole playable map; the next circle is announced right away.
	var r0: float = L.PLAY_HALF * 1.25
	zone = {"i": -1, "state": "wait", "t0": Net.tick, "t1": Net.tick, "c0": Vector2.ZERO, "r0": r0, "c1": Vector2.ZERO, "r1": r0, "dps": 0.0}
	_broadcast()


func _loadout(ch: Character) -> void:
	# Everyone starts with a flashlight on a part-used battery and nothing else.
	for e in Defs.loot.get("starting_loadout", []):
		var cr: Array = e[2]
		var entry := {"id": str(e[0]), "n": int(e[1]), "c": snappedf(randf_range(float(cr[0]), float(cr[1])), 0.01)}
		if Defs.item(entry.id).get("kind", "") == "flashlight":
			ch.inv.equip_gear(entry)
		else:
			ch.inv.add(entry, true)


# ------------------------------------------------------------------ per tick

func tick(dt: float) -> void:
	_t += dt
	_status_t -= dt
	if _status_t <= 0.0 and phase in ["plane", "playing"]:
		_status_t = 15.0
		_log_status()
	match phase:
		"plane":
			_plane_tick()
			_zone_tick(dt)
		"playing":
			_zone_tick(dt)
			_check_end()
	for eid in stats:
		if world.characters.has(eid):
			stats[eid].alive_t += dt


func plane_pos(tick: float) -> Vector3:
	if plane.is_empty():
		return Vector3.ZERO
	var t := clampf((tick - float(plane.t0)) / Defs.TICK_RATE / float(plane.dur), 0.0, 1.0)
	return (plane.a as Vector3).lerp(plane.b, t)


func _plane_tick() -> void:
	var p := plane_pos(Net.tick)
	var t := float(Net.tick - int(plane.t0)) / Defs.TICK_RATE
	var any_aboard := false
	for ch in world.characters.values():
		if ch.mode != Motor.PLANE:
			continue
		any_aboard = true
		ch.global_position = p
		ch.velocity = ((plane.b as Vector3) - (plane.a as Vector3)).normalized() * float(plane.speed)
		var btn := int(ch.last_cmd.get("btn", 0))
		var over := t > float(plane.open_s) and t < float(plane.close_s)
		var wants := (btn & Motor.B_JUMP) != 0 and over
		if world.bots.has(ch.eid):
			wants = wants or (world.bots[ch.eid].wants_jump(p) and over)
		if wants:
			team_jump(ch.team)
	if t >= float(plane.close_s):
		for ch in world.characters.values():
			if ch.mode == Motor.PLANE:
				team_jump(ch.team)
	if not any_aboard and t > 0.0:
		phase = "playing"
		_next_zone()
		_broadcast()
		log_event("everyone has jumped; zone phase 0 announced")


func team_jump(team: int) -> void:
	## The whole team leaves together in a staggered stick so canopies open close but never on top of each other.
	var p := plane_pos(Net.tick)
	var fwd := ((plane.b as Vector3) - (plane.a as Vector3)).normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var spacing := float(Defs.rule("deploy.cluster_spacing", 7.0))
	var stagger := float(Defs.rule("deploy.cluster_vertical_stagger", 4.0))
	var k := 0
	log_event("team %d jumps at %s" % [team, str(p.round())])
	for ch in world.characters.values():
		if ch.team != team or ch.mode != Motor.PLANE:
			continue
		var off := -fwd * spacing * k + side * (spacing * 0.6 * (1 if k % 2 == 0 else -1)) * (1 if k > 0 else 0) + Vector3.DOWN * (stagger * k + 6.0)
		ch.global_position = p + off
		ch.velocity = fwd * float(plane.speed) * 0.35 + Vector3.DOWN * 8.0
		ch.freefall_t = 0.0
		ch.yaw = atan2(-fwd.x, -fwd.z)
		world.server_set_mode(ch, Motor.FREEFALL)
		world.server_sound("jump_wind", ch.global_position, 0.0, -1)
		k += 1


# ------------------------------------------------------------------ zone

func zone_circle(tick: float) -> Array:
	## [centre (Vector2), radius] at the given tick.
	if zone.is_empty():
		return [Vector2.ZERO, 99999.0]
	if zone.state != "shrink":
		return [zone.c0, zone.r0]
	var t := clampf((tick - float(zone.t0)) / maxf(float(zone.t1) - float(zone.t0), 1.0), 0.0, 1.0)
	return [(zone.c0 as Vector2).lerp(zone.c1, t), lerpf(float(zone.r0), float(zone.r1), t)]


func _next_zone() -> void:
	var phases: Array = Defs.rule("zone.phases", [])
	var i := int(zone.i) + 1
	if i >= phases.size():
		return
	var ph: Dictionary = phases[i]
	var L = world.map.layout
	var cur := zone_circle(Net.tick)
	var r1: float = float(ph.radius) * L.PLAY_HALF * 1.6
	var r0: float = cur[1]
	r1 = minf(r1, r0 * 0.9)
	# The next centre lies inside the current circle, biased toward dry land.
	var c1: Vector2 = cur[0]
	for attempt in 40:
		var a := _zone_rng.randf() * TAU
		var d := sqrt(_zone_rng.randf()) * maxf(r0 - r1, 0.0)
		var cand: Vector2 = (cur[0] as Vector2) + Vector2(cos(a), sin(a)) * d
		if not L.is_water(cand.x, cand.y) and L.in_play_area(cand):
			c1 = cand
			break
	var wait := float(ph.wait) / float(Net.config.get("zone_speed", 1.0))
	var shrink := float(ph.shrink) / float(Net.config.get("zone_speed", 1.0))
	zone = {"i": i, "state": "wait", "t0": Net.tick, "t1": Net.tick + int(wait * Defs.TICK_RATE), "c0": cur[0], "r0": r0, "c1": c1, "r1": r1,
		"dps": float(ph.dps), "shrink_s": shrink}
	_warned.clear()


func _zone_tick(dt: float) -> void:
	if zone.is_empty() or int(zone.i) < 0:
		return
	var now := Net.tick
	if zone.state == "wait":
		var left := float(int(zone.t1) - now) / Defs.TICK_RATE
		for w in Defs.rule("zone.warning_s", [60, 30, 10]):
			if left <= float(w) and not _warned.has(w) and left > 0.0:
				_warned[w] = true
				world.match_toast.rpc("The haze moves in %d seconds. Check the map." % int(w), "zone_warning")
				if not world.is_server_dedicated():
					world.match_toast("The haze moves in %d seconds. Check the map." % int(w), "zone_warning")
		if now >= int(zone.t1):
			zone.state = "shrink"
			zone.t0 = now
			zone.t1 = now + int(float(zone.shrink_s) * Defs.TICK_RATE)
			_broadcast()
			log_event("zone %d shrinking to r=%.0f at %s" % [int(zone.i), float(zone.r1), str((zone.c1 as Vector2).round())])
			world.match_toast.rpc("The haze is closing in.", "zone_move")
			if not world.is_server_dedicated():
				world.match_toast("The haze is closing in.", "zone_move")
	elif zone.state == "shrink" and now >= int(zone.t1):
		zone.c0 = zone.c1
		zone.r0 = zone.r1
		zone.state = "hold"
		_next_zone()
		_broadcast()
	# Damage outside the safe area.
	var circ := zone_circle(now)
	var dps := float(zone.get("dps", 0.0))
	if int(zone.i) > 0 or zone.state == "shrink":
		for ch in world.characters.values():
			if ch.mode not in [Motor.GROUND, Motor.DOWNED]:
				continue
			var p := Vector2(ch.global_position.x, ch.global_position.z)
			if p.distance_to(circ[0]) > float(circ[1]):
				var res: Dictionary = ch.health.apply_simple(dps * dt, "haze")
				world._after_damage(ch, res, -1)


# ------------------------------------------------------------------ eliminations

func on_shot(ch: Character) -> void:
	shots_fired += 1


func on_landed(ch: Character, speed: float) -> void:
	if landed.has(ch.eid):
		return
	landed[ch.eid] = true
	var mates := []
	for o in world.characters.values():
		if o != ch and o.team == ch.team and landed.has(o.eid):
			mates.append("%.0f m" % o.global_position.distance_to(ch.global_position))
	log_event("%s (team %d) landed at %s, %.1f m/s, health %.0f; teammates %s" % [ch.pname, ch.team, str(ch.global_position.round()),
		speed, ch.health.health, ", ".join(mates) if not mates.is_empty() else "-"])


func on_downed(ch: Character, attacker: int) -> void:
	if stats.has(attacker) and world.team_of(attacker) != ch.team:
		stats[attacker].downs += 1
	log_event("%s downed by %s" % [ch.pname, _name(attacker)])


func _name(eid: int) -> String:
	if stats.has(eid):
		return str(stats[eid].name)
	return "the world" if eid < 0 else "#%d" % eid


func note_tick_time(us: int) -> void:
	_tick_us.append(us)


func _log_status() -> void:
	if not _log_on:
		return
	var ticks := _tick_us.duplicate()
	_tick_us.clear()
	var perf := ""
	if not ticks.is_empty():
		ticks.sort()
		var sum := 0
		for v in ticks:
			sum += v
		perf = "; server tick avg %.2f ms, p99 %.2f ms, max %.2f ms over %d ticks" % [sum / 1000.0 / ticks.size(),
			ticks[int(ticks.size() * 0.99)] / 1000.0, ticks[-1] / 1000.0, ticks.size()]
	var modes := {}
	var armed := 0
	for c in world.characters.values():
		var m: String = ["plane", "freefall", "chute", "ground", "downed", "dead", "spectate"][c.mode] if c.mode < 7 else str(c.mode)
		modes[m] = modes.get(m, 0) + 1
		if c.wpn.current_id() != "":
			armed += 1
	var circ := zone_circle(Net.tick)
	log_event("status: %s; armed %d; shots %d; zone %d %s r=%.0f; corpses %d%s" % [str(modes), armed, shots_fired, int(zone.get("i", -1)),
		str(zone.get("state", "")), float(circ[1]), world.map.dyn.corpses.size(), perf])
	if not world.bots.is_empty():
		var states := {}
		var searched := 0
		var guns := 0
		var steps := 0
		for b in world.bots.values():
			states[b.state] = states.get(b.state, 0) + 1
			searched += b._searched.size()
			steps += b.plan_i
			for sl in [1, 2, 3]:
				if b.ch.wpn.slots[sl] != null:
					guns += 1
		var opened := 0
		for c in world.map.dyn.containers:
			if c.searched:
				opened += 1
		log_event("bots: %s; containers searched by bots %d (all players %d); plan steps done %d; guns carried %d" % [str(states), searched, opened, steps, guns])
		_log_loot()


func _log_loot() -> void:
	## Evidence for bot looting: of the bots on the ground, how many carry a gun, how many of those carry ammunition
	## for it, how many attachments are fitted, and how much ammunition for no carried gun they hold.
	var LootSense := preload("res://src/ai/loot_sense.gd")
	var alive := 0
	var armed := 0
	var fed := 0
	var atts := 0
	var junk := 0
	var long_guns := 0
	var wet := 0
	for b in world.bots.values():
		var c = b.ch
		if c.mode != Motor.GROUND:
			continue
		alive += 1
		if c.water_depth() > 0.3:
			wet += 1
		var has_gun := false
		var has_ammo := false
		for s in [1, 2, 3]:
			var w = c.wpn.slots[s]
			if w == null:
				continue
			has_gun = true
			if s < 3:
				long_guns += 1
			atts += (w.get("att", []) as Array).size()
			if int(w.mag) + (1 if w.chamber else 0) + c.inv.count(Defs.ammo_item(str(w.id))) > 0:
				has_ammo = true
		if has_gun:
			armed += 1
			if has_ammo:
				fed += 1
		for e in LootSense.junk(c):
			if str(Defs.item(str(e.id)).get("kind", "")) == "ammo":
				junk += int(e.get("n", 1))
	var BotBrain := preload("res://src/ai/bot_brain.gd")
	log_event("[lootstats] bots on the ground %d (in water %d); armed %d; armed with ammo for a gun %d; long guns %d; attachments fitted %d; rounds of unusable ammo carried %d; items on the ground %d; bot pickups %s"
		% [alive, wet, armed, fed, long_guns, atts, junk, world.map.dyn.items.size(), str(BotBrain.counts)])


func on_killed(ch: Character, attacker: int) -> void:
	if stats.has(attacker) and attacker != ch.eid and world.team_of(attacker) != ch.team:
		stats[attacker].kills += 1
	if stats.has(ch.eid):
		stats[ch.eid].placed = _alive_team_count()
	log_event("%s killed by %s (%s); %d teams left" % [ch.pname, _name(attacker), ch.health.last_cause, _alive_team_count()])


func _alive_team_count() -> int:
	var teams := {}
	for c in world.characters.values():
		if c.mode in [Motor.GROUND, Motor.FREEFALL, Motor.CHUTE, Motor.PLANE] or (c.mode == Motor.DOWNED and _team_has_standing(c.team)):
			teams[c.team] = true
	return teams.size()


func _team_has_standing(team: int) -> bool:
	for c in world.characters.values():
		if c.team == team and c.mode in [Motor.GROUND, Motor.FREEFALL, Motor.CHUTE, Motor.PLANE]:
			return true
	return false


func _check_end() -> void:
	# A team whose only survivors are downed is finished: nobody is left to revive them.
	for c in world.characters.values():
		if c.mode == Motor.DOWNED and not _team_has_standing(c.team):
			var res: Dictionary = c.health.apply_simple(9999.0, "bled out")
			world._after_damage(c, res, c.health.last_attacker)
	var alive := _alive_team_count()
	if phase != "playing":
		return
	if (initial_teams > 1 and alive <= 1) or alive == 0:
		phase = "ended"
		var winner := -1
		for c in world.characters.values():
			winner = c.team
		log_event("match over: winner team %d after %.0f s, %d shots fired" % [winner, _t, shots_fired])
		Game.end_match_to_results(_summary(winner))


func _summary(winner: int) -> Dictionary:
	var rows := []
	for eid in stats:
		var s: Dictionary = stats[eid]
		rows.append({"name": s.name, "team": s.team, "kills": s.kills, "downs": s.downs, "time": int(s.alive_t), "winner": int(s.team) == winner, "bot": s.bot})
	rows.sort_custom(func(a, b): return (a.winner and not b.winner) or (a.winner == b.winner and a.kills > b.kills))
	var names := []
	for r in rows:
		if r.winner:
			names.append(r.name)
	return {"winner_team": winner, "winners": names, "rows": rows, "duration": int(_t)}


# ------------------------------------------------------------------ replication

func _state() -> Dictionary:
	return {"phase": phase, "plane": plane, "zone": zone}


func _broadcast() -> void:
	world.match_state.rpc(_state())
	world.match_state(_state())


func sync_peer(pid: int) -> void:
	world.match_state.rpc_id(pid, _state())


static func plane_at(pl: Dictionary, tick: float) -> Vector3:
	if pl.is_empty():
		return Vector3.ZERO
	var t := clampf((tick - float(pl.t0)) / Defs.TICK_RATE / float(pl.dur), 0.0, 1.0)
	return (pl.a as Vector3).lerp(pl.b, t)


static func circle_at(z: Dictionary, tick: float) -> Array:
	if z.is_empty():
		return [Vector2.ZERO, 99999.0]
	if z.state != "shrink":
		return [z.c0, z.r0]
	var t := clampf((tick - float(z.t0)) / maxf(float(z.t1) - float(z.t0), 1.0), 0.0, 1.0)
	return [(z.c0 as Vector2).lerp(z.c1, t), lerpf(float(z.r0), float(z.r1), t)]
