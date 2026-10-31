extends Node
## Server-side match flow: aircraft pass and team jumps, the encroaching haze (shrinking safe zone), eliminations,
## the winner, and the results summary. Clients receive compact state through World.match_state RPCs and compute
## the plane position and the zone circle from shared start ticks.

const WeaponState := preload("res://src/weapons/weapon_state.gd")
const Attach := preload("res://src/weapons/attachments.gd")
const DayCycle := preload("res://src/world/day_cycle.gd")

var world = null
var phase := "idle"          # idle, plane, playing, round_end, ended
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
var landed_tick := {}   # eid -> Net.tick of the first touch-down after the jump
const DEPLOY_GRACE_S := 4.0
## Match log on stdout: always on a dedicated server, or with --matchlog.
var _log_on := false
## r7 Deathmatch: two or three teams (r11) start on the ground at their spawns, armed; no plane, no downed state.
var dm := false
var match_t0 := 0             # tick the match clock (day/night) counts from: the aircraft's start, or the DM start
var day_offset := 0.0         # seconds added to the match clock (Deathmatch starts at a seeded time of day)
var team_names: Array = []
var spawn_info: Dictionary = {}  # team -> {pts: Array[Vector3], yaw: float, anchor: Vector3}
var _last_dead_team := -1
## "wipe": last team standing earns one point each round; "score" and "time" count kills with respawns;
## "elim" ends after one elimination round. Malasugue Mall's optional field stops at half its initial radius.
var win_by := "wipe"
var score_limit := 10
var time_limit_s := 840.0
var team_score := {}          # team -> round points (wipe) or enemy kills (score/time)
var _respawn_at := {}         # pid -> tick the player comes back
var _pid_stats := {}          # pid -> their stats (one Dictionary shared by every life's eid)
var _hold_r := 0.0
var _spawn_rng := RandomNumberGenerator.new()
var _crush_snd := {}          # eid -> seconds to the next zap while the field squeezes them
var round_number := 1
var _next_round_at := 0
var _round_winner := -1
var _field_enabled := true


func setup(w) -> void:
	world = w
	_zone_rng.seed = Game.match_seed + 31
	_log_on = Net.dedicated or Game.arg("matchlog") != null


func log_event(msg: String) -> void:
	if _log_on:
		print("[match %6.1f] %s" % [_t, msg])


# ------------------------------------------------------------------ start

func start() -> void:
	dm = Net.is_dm()
	if dm:
		_start_dm()
		return
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
	match_t0 = int(plane.t0)
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


# ------------------------------------------------------------------ Deathmatch start

func _dm_rule(key: String, default_value):
	return Defs.rule("deathmatch." + key, default_value)


func zone_speed() -> float:
	## r14: Deathmatch's field is always fast (rules deathmatch.zone_speed); the lobby choice is for Classic.
	if dm:
		return float(_dm_rule("zone_speed", 1.6))
	return float(Net.config.get("zone_speed", 1.0))


func _start_dm() -> void:
	var L = world.map.layout
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.match_seed * 3 + 17
	var n_teams := Net.dm_teams()
	team_names = UITheme.dm_team_names(n_teams).duplicate()
	win_by = str(Net.config.get("dm_win", "wipe"))
	if not win_by in Net.DM_WINS:
		win_by = "wipe"
	score_limit = maxi(int(Net.config.get("dm_score", 10)), 1)
	time_limit_s = maxf(float(Net.config.get("dm_time", 14)), 1.0) * 60.0
	team_score.clear()
	for t in n_teams:
		team_score[t] = 0
	_respawn_at.clear()
	_pid_stats.clear()
	_spawn_rng.seed = Game.match_seed + 977
	var offs: Array = _dm_rule("day_offsets", [0])
	day_offset = float(offs[rng.randi() % offs.size()]) if not offs.is_empty() else 0.0
	match_t0 = Net.tick
	spawn_info = dm_spawns(Game.match_seed, n_teams)
	var pids: Array = Net.players.keys()
	# Humans take the front-centre places of their team's formation, bots fill around them.
	pids.sort_custom(func(a, b): return (not Net.is_bot(a) and Net.is_bot(b)) or (Net.is_bot(a) == Net.is_bot(b) and a < b))
	var idx := {}
	var teams := {}
	var gear_rng := RandomNumberGenerator.new()
	gear_rng.seed = Game.match_seed + 4441
	for pid in pids:
		var p: Dictionary = Net.players[pid]
		var team := clampi(int(p.team), 0, n_teams - 1)
		var k := int(idx.get(team, 0))
		idx[team] = k + 1
		var slot: Array = _spawn_slot(team, k)
		var ch: Character = world.server_spawn_character(pid, team, str(p.name), slot[0], Motor.GROUND, float(slot[1]))
		_loadout(ch)
		_dm_loadout(ch, pid, gear_rng)
		stats[ch.eid] = {"pid": pid, "name": p.name, "team": team, "kills": 0, "damage": 0.0, "downs": 0, "alive_t": 0.0, "placed": 0, "bot": p.bot}
		_pid_stats[pid] = stats[ch.eid]
		teams[team] = true
	initial_teams = teams.size()
	phase = "playing"
	_reset_dm_field(rng)
	var c: Vector2 = zone.c0
	var r0: float = zone.r0
	var anchors := []
	var gaps := []
	for t in n_teams:
		if spawn_info.has(t):
			anchors.append(str((spawn_info[t].anchor as Vector3).round()))
			var a: Vector3 = spawn_info[t].anchor
			var b: Vector3 = spawn_info.get((t + 1) % n_teams, spawn_info[t]).anchor
			gaps.append("%.0f" % Vector2(a.x - b.x, a.z - b.z).length())
	log_event("deathmatch start on %s: %d players, %d teams; spawns %s (%s m apart, %s); day offset %.0f s; zone centre %s r=%.0f; win by %s%s"
		% [str(Net.config.get("map", "kalinaw")), stats.size(), initial_teams, ", ".join(anchors), "/".join(gaps),
		str(spawn_info.get("source", "?")), day_offset, str(c.round()), r0, win_by,
		(" %d" % score_limit) if win_by == "score" else ((" %.0f min" % (time_limit_s / 60.0)) if win_by == "time" else "")]
		+ ((", field holds at r=%.0f" % _hold_r) if respawns() else ""))
	_broadcast()


func _reset_dm_field(rng: RandomNumberGenerator) -> void:
	var L = world.map.layout
	var c := _dm_centre(rng, Net.dm_teams())
	var r0: float = L.PLAY_HALF * 1.45 + c.length()
	var optional := Net.dm_field_optional()   # Malasugue Mall, Freight Delight: off unless the host turns it on
	_field_enabled = not optional or bool(Net.config.get("dm_field", false))
	_hold_r = r0 * 0.5 if optional else 0.0
	if respawns():
		# Keep respawn positions inside the final circle.
		for t in Net.dm_teams():
			var si: Dictionary = spawn_info.get(t, {})
			for sp in (si.get("pts", []) as Array) + [si.get("anchor", Vector3(c.x, 0.0, c.y))]:
				_hold_r = maxf(_hold_r, Vector2((sp as Vector3).x, (sp as Vector3).z).distance_to(c) + float(_dm_rule("hold_margin", 10.0)))
	zone = {"i": -1, "state": "hold", "t0": Net.tick, "t1": Net.tick, "c0": c, "r0": r0, "c1": c, "r1": r0, "dps": 0.0}
	_warned.clear()
	_field_watch.clear()
	_crush_snd.clear()
	_next_zone()


func _start_next_round() -> void:
	# Keep match totals while replacing every life, including the winning survivors.
	for ch in world.characters.values():
		world.interaction.server_drop_held(ch, false)
		world.server_remove_character(ch)
	var bot_team := preload("res://src/ai/bot_team.gd")
	bot_team.squads.clear()
	bot_team.laser_claims.clear()
	stats.clear()
	landed.clear()
	landed_tick.clear()
	_respawn_at.clear()
	_last_dead_team = -1
	eliminated_order.clear()
	round_number += 1
	_next_round_at = 0
	_round_winner = -1
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.match_seed + round_number * 31
	_reset_dm_field(rng)
	for pid in Net.players:
		var p: Dictionary = Net.players[pid]
		if not p.bot and not p.connected:
			continue
		if _pid_stats.has(pid):
			_pid_stats[pid].placed = 0
		_respawn(pid)
	phase = "playing"
	_broadcast()
	log_event("round %d started; scores %s" % [round_number, str(team_score)])


func _dm_centre(rng: RandomNumberGenerator, n_teams: int = 2) -> Vector2:
	## The centre of the first circle: within centre_jitter of the map centre (or the layout's dm_centre; with three
	## teams the middle of their spawns), on dry land inside the play area.
	var L = world.map.layout
	var base := Vector2.ZERO
	var dc = L.get("dm_centre") if L is Object else null
	if n_teams == 3 and L is Object and L.has_method("dm_centre_for"):
		dc = L.dm_centre_for(3)
	if dc is Vector2:
		base = dc
	elif dc is Vector3:
		base = Vector2(dc.x, dc.z)
	var jit := float(_dm_rule("zone.centre_jitter", 60.0))
	if L is Object and L.get("zone_jitter") != null:
		jit = float(L.get("zone_jitter"))   # (r15) a small map keeps its first circle near its middle
	for attempt in 30:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * jit
		var cand := base + Vector2(cos(a), sin(a)) * d
		if not L.is_water(cand.x, cand.y) and L.in_play_area(cand):
			return cand
	return base


func dm_spawns(seed_value: int, n_teams: int = 2) -> Dictionary:
	## Team spawn areas: the layout's own (Lawless Sub: layout.spawns[team], layout.spawn_yaw[team]; three teams use
	## layout.spawns3 / spawn_yaw3), or two dry, open, in-play areas about 300+ m apart picked from the match seed.
	## Each team faces the middle. Returns {0: {pts, yaw, anchor}, 1: {...}[, 2: ...], "source": "layout" | "computed"}.
	var L = world.map.layout
	var out := {}
	if L is Object and L.has_method("dm_floor_spawns"):
		# (r17) Malasugue Mall: each team on its own floor (1, 3 or 5, at random).
		out = L.dm_floor_spawns(seed_value, n_teams)
		if out.size() >= n_teams:
			out["source"] = "floors"
			return out
		out = {}
	var ls = L.get("spawns") if L is Object else null
	var ly = L.get("spawn_yaw") if L is Object else null
	if n_teams == 3 and L is Object and L.get("spawns3") != null and (L.get("spawns3") as Array).size() >= 3:
		ls = L.get("spawns3")
		ly = L.get("spawn_yaw3")
	if ls != null and (ls is Array or ls is Dictionary) and ls.size() >= n_teams:
		for t in n_teams:
			var pts: Array = []
			for q in ls[t]:
				pts.append(q as Vector3)
			if pts.is_empty():
				continue
			var anchor := Vector3.ZERO
			for q in pts:
				anchor += q
			anchor /= float(pts.size())
			var yv := 0.0
			if ly != null and (ly is Array or ly is Dictionary) and ly.size() > t:
				yv = float(ly[t])
			out[t] = {"pts": pts, "anchor": anchor, "yaw": yv}
		if out.size() == n_teams:
			if ly == null and n_teams == 2:
				for t in 2:
					var to: Vector3 = (out[1 - t].anchor as Vector3) - (out[t].anchor as Vector3)
					out[t].yaw = atan2(-to.x, -to.z)
			out["source"] = "layout"
			return out
		out = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7 + 911
	var half: float = L.PLAY_HALF
	var want_d := clampf(half * 0.5, 155.0, 420.0)
	var best := []
	for strict in [true, false]:
		for attempt in 48:
			var ang := rng.randf() * TAU
			var dir := Vector2(cos(ang), sin(ang))
			var d := want_d + rng.randf_range(0.0, 30.0)
			var a := _open_spot(dir * d, strict)
			if a == Vector3.INF:
				continue
			var b := _open_spot(-dir * d, strict)
			if b == Vector3.INF:
				continue
			if Vector2(a.x - b.x, a.z - b.z).length() >= 300.0:
				best = [a, b]
				break
		if not best.is_empty():
			break
	if best.is_empty():
		var g0 := Vector3(-want_d, 0, 0)
		var g1 := Vector3(want_d, 0, 0)
		g0.y = L.ground_height(g0.x, g0.z)
		g1.y = L.ground_height(g1.x, g1.z)
		best = [g0, g1]
	for t in 2:
		var me: Vector3 = best[t]
		var other: Vector3 = best[1 - t]
		var to := other - me
		out[t] = {"pts": [], "anchor": me, "yaw": atan2(-to.x, -to.z)}
	out["source"] = "computed"
	return out


func _open_spot(near: Vector2, strict: bool) -> Vector3:
	## A dry, fairly flat, open patch (no walls, props or roof over it) close to near; Vector3.INF if none.
	var L = world.map.layout
	var r := 14.0 if strict else 8.0  # the whole formation (rows of five, spawn_spacing apart) fits inside
	for ring in [0.0, 12.0, 24.0, 36.0, 50.0, 65.0]:
		var n := 1 if ring == 0.0 else 10
		for k in n:
			var p: Vector2 = near + Vector2(cos(k * TAU / n), sin(k * TAU / n)) * ring
			if not L.in_play_area(p) or not L.in_play_area(p * 1.1):
				continue
			var ok := true
			var hmin := INF
			var hmax := -INF
			for s in 9:
				var q: Vector2 = p + (Vector2.ZERO if s == 0 else Vector2(cos(s * TAU / 8.0), sin(s * TAU / 8.0)) * r)
				if L.is_water(q.x, q.y):
					ok = false
					break
				var h: float = L.ground_height(q.x, q.y)
				hmin = minf(hmin, h)
				hmax = maxf(hmax, h)
			if not ok or hmax - hmin > (1.6 if strict else 2.5):
				continue
			if not _clear_box(Vector3(p.x, hmax + 0.45, p.y), Vector3(r, 2.2, r)):
				continue
			if strict and not _sky_clear(Vector3(p.x, hmax + 2.5, p.y)):
				continue
			return Vector3(p.x, L.ground_height(p.x, p.y), p.y)
	return Vector3.INF


func _clear_box(bottom_centre: Vector3, size: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis(), bottom_centre + Vector3.UP * size.y * 0.5)
	q.collision_mask = Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS | Defs.PHYS_BLOCKER
	return space.intersect_shape(q, 1).is_empty()


func _sky_clear(p: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 40.0, Defs.PHYS_WORLD | Defs.PHYS_PROP)
	return space.intersect_ray(q).is_empty()


func _spawn_slot(team: int, k: int) -> Array:
	## [position, yaw] of the k-th member of a team: the layout's points in order, otherwise rows of five spaced
	## spawn_spacing behind the anchor, each nudged clear of walls and props and set on the floor.
	var info: Dictionary = spawn_info.get(team, {})
	var yaw := float(info.get("yaw", 0.0))
	var pts: Array = info.get("pts", [])
	var spacing := float(_dm_rule("spawn_spacing", 3.2))
	var anchor: Vector3 = info.get("anchor", Vector3.ZERO)
	var want: Vector3
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	if k < pts.size():
		want = pts[k]
	elif not pts.is_empty():
		want = (pts[k % pts.size()] as Vector3) - fwd * spacing * float(1 + k / pts.size())
	else:
		var row := k / 5
		var col: int = [2, 1, 3, 0, 4][k % 5]  # centre first, then outward
		want = anchor + right * (float(col) - 2.0) * spacing - fwd * (float(row) - 0.5) * spacing
	var L = world.map.layout
	for tries in 12:
		var p := want
		if tries > 0:
			var a := tries * 2.4
			p = want + Vector3(cos(a), 0, sin(a)) * (0.8 * tries)
		var gy: float = L.ground_height(p.x, p.z) if pts.is_empty() else want.y
		var floor_y := _floor_at(p.x, p.z, gy)
		# Room to turn and shoot: nothing within ~0.8 m (a wall right against the face reads as a black screen).
		if _clear_box(Vector3(p.x, floor_y + 0.15, p.z), Vector3(1.6, 1.7, 1.6)):
			return [Vector3(p.x, floor_y + 0.08, p.z), yaw]
	var fy := _floor_at(want.x, want.z, want.y if not pts.is_empty() else L.ground_height(want.x, want.z))
	return [Vector3(want.x, fy + 0.08, want.z), yaw]


func _floor_at(x: float, z: float, near_y: float) -> float:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, near_y + 2.0, z), Vector3(x, near_y - 4.0, z), Defs.PHYS_WORLD | Defs.PHYS_PROP)
	var r := space.intersect_ray(q)
	return float((r.position as Vector3).y) if not r.is_empty() else near_y


func pick_loadout(pid: int, rng: RandomNumberGenerator) -> Dictionary:
	## The player's Deathmatch guns: their Game Setup choice (validated by Net), the defaults for a human who chose
	## nothing, a random pick for a bot. (r22) With the attachments for each ("att_primary", "att_secondary"): the
	## player's own (checked again against the guns they end up with), or a bot's pick (Attach.bot_pick).
	var prim_list: Array = (_dm_rule("primary", []) as Array).filter(func(i): return Defs.weapons.has(str(i)))
	var sec_list: Array = (_dm_rule("secondary", []) as Array).filter(func(i): return Defs.weapons.has(str(i)))
	var lo: Dictionary = Net.players.get(pid, {}).get("loadout", {})
	var prim := str(lo.get("primary", ""))
	var sec := str(lo.get("secondary", ""))
	if Net.is_bot(pid) and lo.is_empty():
		prim = str(prim_list[rng.randi() % prim_list.size()]) if not prim_list.is_empty() else ""
		sec = str(sec_list[rng.randi() % sec_list.size()]) if not sec_list.is_empty() else ""
	if not prim in prim_list:
		prim = str(_dm_rule("default_primary", "rifle_m416"))
	if not sec in sec_list:
		sec = str(_dm_rule("default_secondary", "pistol_9"))
	var out := {"primary": prim, "secondary": sec}
	var chance := float(_dm_rule("bot_attachment_chance", 0.75))
	for which in ["primary", "secondary"]:
		var ids = lo.get("att_" + which, [])
		if Net.is_bot(pid) and lo.is_empty():
			out["att_" + which] = Attach.bot_pick(str(out[which]), rng, chance)
		else:
			out["att_" + which] = Attach.sanitize(str(out[which]), ids if ids is Array else [])
	return out


func _dm_loadout(ch: Character, pid: int, rng: RandomNumberGenerator) -> void:
	## Primary in slot 1 and handgun in slot 3, both loaded, spare magazines as ammunition, plate carrier and
	## heavy-plate helmet worn, the extras (bandages) in the bag. The primary is drawn.
	var lo := pick_loadout(pid, rng)
	var spare := {"primary": int(_dm_rule("spare_mags_primary", 3)), "secondary": int(_dm_rule("spare_mags_secondary", 2))}
	var min_rounds := int(_dm_rule("spare_rounds_min", 12))
	for which in ["primary", "secondary"]:
		var wid := str(lo[which])
		if not Defs.weapons.has(wid):
			continue
		var w := WeaponState.new_instance(wid)
		_fit_kit(w, lo.get("att_" + which, []))
		ch.wpn.slots[1 if which == "primary" else 3] = w
		var n := maxi(Attach.mag_cap(w) * int(spare[which]), min_rounds)
		ch.inv.add({"id": Defs.ammo_item(wid), "n": n}, true)
	for g in _dm_rule("gear", ["vest_heavy", "helmet_heavy"]):
		var it: Dictionary = Defs.item(str(g))
		if it.is_empty():
			continue
		ch.inv.equip_gear({"id": str(g), "n": 1, "d": float(it.get("durability", 100.0))})
	for e in _dm_rule("extras", []):
		ch.inv.add({"id": str(e[0]), "n": int(e[1])}, true)
	ch.wpn.want = 1
	ch.wpn.cur = 1
	ch.inv.mark_dirty()
	ch.health.dirty = true
	ch.set_meta("dm_loadout", lo)
	if _log_on:
		# (r22) The kit this life starts with: guns, fitted attachments, rounds loaded / magazine capacity.
		var parts := []
		for s in [1, 3]:
			var w = ch.wpn.slots[s]
			if w != null:
				parts.append("%s [%s] mag %d/%d" % [str(w.id), ",".join(w.att), int(w.mag) + (1 if w.chamber else 0), Attach.mag_cap(w)])
		print("[loadout] %s %s" % [ch.pname, " | ".join(parts)])


func _fit_kit(w: Dictionary, ids) -> void:
	## (r22) Fits a Deathmatch gun's chosen attachments (as a loot pickup would leave them) and fills the magazine to
	## what it now holds (an extended magazine holds more), the next round chambered as WeaponState.new_instance does.
	w.att = Attach.sanitize(str(w.id), ids if ids is Array else [])
	if "weapon_light" in w.att:
		w.wl = 1.0   # a fresh battery in the weapon light
	var cap := Attach.mag_cap(w)
	w.mag = maxi(cap - (1 if w.chamber else 0), 0)


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
	if phase == "ended":
		return
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
		"round_end":
			if Net.tick >= _next_round_at:
				_start_next_round()
	for eid in stats:
		if phase in ["plane", "playing"] and world.characters.has(eid) and world.characters[eid].mode != Motor.DEAD:
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
	if dm and not _field_enabled:
		return
	var phases: Array = Defs.rule("deathmatch.zone.phases", []) if dm else Defs.rule("zone.phases", [])
	var i := int(zone.i) + 1
	if i >= phases.size():
		return
	var ph: Dictionary = phases[i]
	var L = world.map.layout
	var cur := zone_circle(Net.tick)
	var r1: float = float(ph.radius) * L.PLAY_HALF * 1.6
	var r0: float = cur[1]
	r1 = minf(r1, r0 * 0.9)
	if dm and _hold_r > 0.0:
		# (r17) A respawn round: the field closes on its own centre and holds round the team spawns.
		if r0 <= _hold_r + 1.0:
			return
		r1 = maxf(r1, _hold_r)
	# The next centre lies inside the current circle, biased toward dry land.
	var c1: Vector2 = cur[0]
	for attempt in (0 if dm and _hold_r > 0.0 else 40):
		var a := _zone_rng.randf() * TAU
		var d := sqrt(_zone_rng.randf()) * maxf(r0 - r1, 0.0)
		var cand: Vector2 = (cur[0] as Vector2) + Vector2(cos(a), sin(a)) * d
		if not L.is_water(cand.x, cand.y) and L.in_play_area(cand):
			c1 = cand
			break
	var wait := float(ph.wait) / zone_speed()
	var shrink := float(ph.shrink) / zone_speed()
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
				world.match_toast.rpc("The field moves in %d seconds. Check the map." % int(w), "zone_warning")
				if not world.is_server_dedicated():
					world.match_toast("The field moves in %d seconds. Check the map." % int(w), "zone_warning")
		if now >= int(zone.t1):
			zone.state = "shrink"
			zone.t0 = now
			zone.t1 = now + int(float(zone.shrink_s) * Defs.TICK_RATE)
			_broadcast()
			log_event("zone %d shrinking to r=%.0f at %s" % [int(zone.i), float(zone.r1), str((zone.c1 as Vector2).round())])
			world.match_toast.rpc("The field is closing in. It pushes you inward: don't get pinned against a wall.", "zone_move")
			if not world.is_server_dedicated():
				world.match_toast("The field is closing in. It pushes you inward: don't get pinned against a wall.", "zone_move")
			_field_watch_start()
	elif zone.state == "shrink" and now >= int(zone.t1):
		_field_watch_end()
		zone.c0 = zone.c1
		zone.r0 = zone.r1
		zone.state = "hold"
		_next_zone()
		_broadcast()
	if not _field_watch.is_empty():
		_field_watch_tick()
	# r12: the forcefield does no damage to anyone it can move. It pushes (Motor, Field.apply); (r17) anyone it holds
	# deep inside it, pinned against a wall or caught on something, is squeezed: heavy damage that grows the longer
	# they stay pinned, until it kills them (about two seconds from full health).
	if Field.live(zone):
		for ch in world.characters.values():
			if ch.mode not in [Motor.GROUND, Motor.DOWNED] or ch.field_pin < Field.CRUSH_PIN_S or ch.health.test_invulnerable:
				_crush_snd.erase(ch.eid)
				continue
			var dmg := Field.crush_dps(ch.field_pin) * dt
			var kill = ch.health.health - dmg <= 0.0
			if kill:
				ch.health.catastrophic = true   # squeezed to death: never downed
			var res: Dictionary = ch.health.apply_simple(dmg, "field")
			_crush_snd[ch.eid] = float(_crush_snd.get(ch.eid, 0.0)) - dt
			if float(_crush_snd[ch.eid]) <= 0.0 and not kill:
				_crush_snd[ch.eid] = 0.45
				world.server_sound("field_zap", ch.global_position + Vector3.UP, -4.0, -1)
			if kill or bool(res.get("killed", false)):
				_crush_snd.erase(ch.eid)
				log_event("%s crushed by the field at %s (r=%.1f, %s, %.1f m into it, pinned %.1f s)" % [ch.pname, str(ch.global_position.round()),
					float(zone_circle(now)[1]), "indoors" if _indoors(ch) else "outdoors", float(Field.at(world, ch.global_position, float(now)).pen), ch.field_pin])
				world.server_sound("field_crush", ch.global_position + Vector3.UP, 0.0, -1)
			world._after_damage(ch, res, -1)


# r12 match log (--matchlog): bots indoors in the field's path when it starts closing, and whether they got out of the
# building before its edge reached them. eid -> {name, out (seconds to get out, -1 still in), pen (field depth then)}.
var _field_watch := {}


func _indoors(ch) -> bool:
	return world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5) != 0


func _field_watch_start() -> void:
	_field_watch.clear()
	if not _log_on:
		return
	for eid in world.bots:
		var ch = world.characters.get(eid)
		if ch == null or ch.mode != Motor.GROUND or not _indoors(ch):
			continue
		var p := Vector2(ch.global_position.x, ch.global_position.z)
		if p.distance_to(zone.c1) > float(zone.r1) - 2.0:   # the field will pass over this building
			_field_watch[eid] = {"name": ch.pname, "out": -1.0, "pen": 0.0, "t0": _t}


func _field_watch_tick() -> void:
	for eid in _field_watch:
		var w: Dictionary = _field_watch[eid]
		var ch = world.characters.get(eid)
		if float(w.out) >= 0.0 or ch == null or ch.mode != Motor.GROUND:
			continue
		if not _indoors(ch):
			w.out = _t - float(w.t0)
			w.pen = float(Field.at(world, ch.global_position, float(Net.tick)).pen)


func _field_watch_end() -> void:
	if not _log_on:
		return
	var early := 0
	var late := 0
	var stayed := []
	var dead := 0
	for eid in _field_watch:
		var w: Dictionary = _field_watch[eid]
		var ch = world.characters.get(eid)
		if ch == null or ch.mode == Motor.DEAD:
			dead += 1
		if float(w.out) < 0.0:
			stayed.append(str(w.name))
		elif float(w.pen) < 0.0:
			early += 1
		else:
			late += 1
	log_event("[field watch] zone %d: %d bots indoors in the field's path when it started closing: %d out before the edge reached them, %d out after it, %d never out (%s); %d of them dead by the end" % [
		int(zone.i), _field_watch.size(), early, late, stayed.size(), ", ".join(stayed), dead])
	_field_watch.clear()


# ------------------------------------------------------------------ eliminations

func on_shot(ch: Character) -> void:
	shots_fired += 1
	ch.health.shield_until = -1   # (r17) firing ends spawn protection


func on_landed(ch: Character, speed: float) -> void:
	if landed.has(ch.eid):
		return
	landed[ch.eid] = true
	landed_tick[ch.eid] = Net.tick
	var mates := []
	for o in world.characters.values():
		if o != ch and o.team == ch.team and landed.has(o.eid):
			mates.append("%.0f m" % o.global_position.distance_to(ch.global_position))
	log_event("%s (team %d) landed at %s, %.1f m/s, health %.0f; teammates %s" % [ch.pname, ch.team, str(ch.global_position.round()),
		speed, ch.health.health, ", ".join(mates) if not mates.is_empty() else "-"])


func deploy_safe(ch: Character) -> bool:
	## (r15) Classic: the jump never hurts. From the aircraft until DEPLOY_GRACE_S after the first touch-down (a canopy
	## cut a metre or two up, rolling off the roof it came down on) no fall or landing takes health or hurts a leg.
	if dm:
		return false
	if not landed_tick.has(ch.eid):
		return true
	return Net.tick - int(landed_tick[ch.eid]) < int(DEPLOY_GRACE_S * Defs.TICK_RATE)


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
		# (r22) objects alive: a leak (bots rebuilt each round) shows as a count that keeps climbing round after round
		perf += "; objects %d" % int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var modes := {}
	var armed := 0
	for c in world.characters.values():
		var m: String = ["plane", "freefall", "chute", "ground", "downed", "dead", "spectate"][c.mode] if c.mode < 7 else str(c.mode)
		modes[m] = modes.get(m, 0) + 1
		if c.wpn.current_id() != "":
			armed += 1
	var circ := zone_circle(Net.tick)
	var lvls := ""
	if world.map.layout.has_method("level_of"):
		# (r15) a storeyed map: how many of the living stand on each level (and on escalators / stairs between)
		var per := {}
		for c2 in world.characters.values():
			if c2.mode in [Motor.GROUND, Motor.DOWNED]:
				var y: float = c2.global_position.y
				var lv: int = world.map.layout.level_of(y)
				var key := "L%d" % (lv + 1) if absf(y - world.map.layout.level_y(lv)) < 0.6 else "between"
				per[key] = int(per.get(key, 0)) + 1
		lvls = "; levels %s" % str(per)
	log_event("status: %s; armed %d; shots %d; zone %d %s r=%.0f; corpses %d%s%s" % [str(modes), armed, shots_fired, int(zone.get("i", -1)),
		str(zone.get("state", "")), float(circ[1]), world.map.dyn.corpses.size(), lvls, perf])
	if dm:
		# Where each team is: centroid, spread (mean distance from it), and how far apart the first two groups are.
		var parts := []
		var cents := {}
		for t in team_names.size():
			var sum := Vector3.ZERO
			var n := 0
			for c in world.characters.values():
				if c.team == t and c.mode == Motor.GROUND:
					sum += c.global_position
					n += 1
			if n == 0:
				continue
			var cen := sum / n
			cents[t] = cen
			var spread := 0.0
			for c in world.characters.values():
				if c.team == t and c.mode == Motor.GROUND:
					spread += c.global_position.distance_to(cen) / n
			parts.append("%s %d at %s spread %.0f m" % [team_name(t), n, str(Vector2(cen.x, cen.z).round()), spread])
		var gap := (cents[0] as Vector3).distance_to(cents[1]) if cents.has(0) and cents.has(1) else -1.0
		log_event("dm teams: %s; gap %.0f m; zone centre %s" % ["; ".join(parts), gap, str((zone_circle(Net.tick)[0] as Vector2).round())])
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
		# r10: what each role is doing, squads, radio, waypoints, learning.
		var by_role := {}
		var stuck := 0
		for b in world.bots.values():
			if b.ch.mode in [Motor.DEAD, Motor.SPECTATE]:
				continue
			var k := str(b.role)
			if not by_role.has(k):
				by_role[k] = {}
			by_role[k][b.state] = int(by_role[k].get(b.state, 0)) + 1
			if float(b._no_prog) > 1.5:
				stuck += 1
				if Game.arg("radiolog") != null:
					var wp = b.path[b.path_i] if b.path_i < b.path.size() else b.goal
					log_event("[stuck] %s (%s, %s) at %s -> %s, ahead %s, no_prog %.1f" % [b.ch.pname, b.role, b.state, str(b.ch.global_position.snapped(Vector3.ONE * 0.1)),
						str((wp as Vector3).snapped(Vector3.ONE * 0.1)) if wp != Vector3.INF else "-", b._ahead(), float(b._no_prog)])
		var BT := preload("res://src/ai/bot_team.gd")
		log_event("roles: %s; stuck now %d; waypoints %d; team %s" % [str(by_role), stuck, BT.spots.size(), str(BT.stats)])
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
	var wet_at: Array = []
	for b in world.bots.values():
		var c = b.ch
		if c.mode != Motor.GROUND:
			continue
		alive += 1
		if c.water_depth() > 0.3:
			wet += 1
			wet_at.append(Vector2(c.global_position.x, c.global_position.z).round())
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
		% [alive, wet, armed, fed, long_guns, atts, junk, world.map.dyn.items.size(), str(BotBrain.counts)] + (" wet at %s" % str(wet_at) if wet > 0 else ""))


func on_killed(ch: Character, attacker: int) -> void:
	if stats.has(attacker) and attacker != ch.eid and world.team_of(attacker) != ch.team:
		stats[attacker].kills += 1
	preload("res://src/ai/bot_team.gd").on_killed(ch, attacker)
	if stats.has(ch.eid):
		stats[ch.eid].placed = _alive_team_count()
	log_event("%s killed by %s (%s); %d teams left" % [ch.pname, _name(attacker), ch.health.last_cause, _alive_team_count()])
	if dm and respawns() and phase == "playing":
		var kt: int = int(stats[attacker].team) if stats.has(attacker) else world.team_of(attacker)
		if attacker >= 0 and attacker != ch.eid and kt >= 0 and kt != ch.team:
			team_score[kt] = int(team_score.get(kt, 0)) + 1
		if Net.players.has(ch.pid):
			_respawn_at[ch.pid] = Net.tick + int(float(_dm_rule("respawn_s", 5.0)) * Defs.TICK_RATE)
	if dm:
		_last_dead_team = ch.team
		var killer = world.characters.get(attacker)
		var cause := str(ch.health.last_cause)
		# A grenade kill is the grenade's, not the gun the thrower happens to hold.
		var wid: String = killer.wpn.current_id() if killer != null and killer != ch and cause != "explosion" else ""
		if cause == "field":
			cause = "the field"
		elif cause == "explosion":
			cause = Defs.item_name("frag_grenade")
		var kname := _name(attacker) if attacker >= 0 and attacker != ch.eid else ""
		world.server_kill_feed(kname, world.team_of(attacker) if attacker >= 0 else -1, ch.pname, ch.team, Defs.item_name(wid) if wid != "" else cause)
		var al := alive_counts()
		log_event("alive: %s %d, %s %d; score %s" % [team_name(0), int(al.get(0, 0)), team_name(1), int(al.get(1, 0)), str(team_score)])
		_broadcast()


func respawns() -> bool:
	## (r17) A Deathmatch won on score or on the clock: the dead come back.
	return dm and win_by in ["score", "time"]


func round_time() -> float:
	return float(Net.tick - match_t0) / Defs.TICK_RATE


func _respawn_tick() -> void:
	if _respawn_at.is_empty():
		return
	for pid in _respawn_at.keys():
		if Net.tick < int(_respawn_at[pid]):
			continue
		_respawn_at.erase(pid)
		if Net.players.has(pid) and world.char_by_pid(pid) == null:
			_respawn(pid)


func late_join(pid: int) -> void:
	## (r17) Someone who joins a respawn round after it started plays too: on the smallest team, at its spawn.
	if not respawns() or phase != "playing" or not Net.players.has(pid) or world.char_by_pid(pid) != null:
		return
	var p: Dictionary = Net.players[pid]
	var n := Net.dm_teams()
	if int(p.team) < 0 or int(p.team) >= n:
		var counts := {}
		for q in Net.players.values():
			counts[int(q.team)] = int(counts.get(int(q.team), 0)) + 1
		var best := 0
		for t in n:
			if int(counts.get(t, 0)) < int(counts.get(best, 0)):
				best = t
		p.team = best
		Net._broadcast_lobby()
	_respawn_at[pid] = Net.tick + int(1.5 * Defs.TICK_RATE)


func _respawn(pid: int) -> void:
	## (r17) Back in at the team's spawn, on the free spot farthest from the enemy, with the Deathmatch kit again and a
	## few seconds of spawn protection (gone at the first shot).
	var p: Dictionary = Net.players[pid]
	var team := clampi(int(p.team), 0, maxi(Net.dm_teams() - 1, 0))
	var n := maxi((spawn_info.get(team, {}).get("pts", []) as Array).size(), 5)
	var best: Array = []
	var best_d := -INF
	for i in 8:
		var slot: Array = _spawn_slot(team, _spawn_rng.randi() % n)
		var d := 1000.0
		for c in world.characters.values():
			if c.mode in [Motor.DEAD, Motor.SPECTATE]:
				continue
			var dc: float = (c.global_position as Vector3).distance_to(slot[0])
			if c.team != team:
				d = minf(d, dc)
			elif dc < 1.0:
				d = minf(d, -1.0)   # someone is standing on this spot
		if d > best_d:
			best_d = d
			best = slot
	var ch: Character = world.server_spawn_character(pid, team, str(p.name), best[0], Motor.GROUND, float(best[1]))
	_loadout(ch)
	_dm_loadout(ch, pid, _spawn_rng)
	ch.health.shield_until = Net.tick + int(float(_dm_rule("spawn_shield_s", 3.0)) * Defs.TICK_RATE)
	if not _pid_stats.has(pid):
		_pid_stats[pid] = {"pid": pid, "name": p.name, "team": team, "kills": 0, "damage": 0.0, "downs": 0, "alive_t": 0.0, "placed": 0, "bot": p.bot}
	stats[ch.eid] = _pid_stats[pid]
	log_event("%s respawned at %s (nearest enemy %.0f m)" % [ch.pname, str(ch.global_position.round()), best_d])
	_broadcast()


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


func alive_counts() -> Dictionary:
	## team -> characters still standing (Deathmatch has no downed state; Classic counts the downed too).
	var out := {}
	if dm:
		for t in Net.dm_teams():
			out[t] = 0
	for c in world.characters.values():
		if c.mode in [Motor.GROUND, Motor.FREEFALL, Motor.CHUTE, Motor.PLANE, Motor.DOWNED]:
			out[c.team] = int(out.get(c.team, 0)) + 1
	return out


func team_name(t: int) -> String:
	if t >= 0 and t < team_names.size():
		return str(team_names[t])
	return "Team %d" % (t + 1)


func _check_end_dm() -> void:
	if respawns():
		_respawn_tick()
		var top := -1
		var top_s := -1
		var tie := false
		for t in team_score:
			var s := int(team_score[t])
			if s > top_s:
				top_s = s
				top = int(t)
				tie = false
			elif s == top_s:
				tie = true
		var over := (win_by == "score" and top_s >= score_limit) or (win_by == "time" and round_time() >= time_limit_s)
		if not over:
			return
		phase = "ended"
		var winner := -1 if tie else top
		log_event("match over (%s): winner team %d (%s) with %d after %.0f s, scores %s, %d shots fired" % [win_by, winner,
			team_name(winner) if winner >= 0 else "draw", top_s, round_time(), str(team_score), shots_fired])
		_broadcast()
		Game.end_match_to_results(_summary(winner))
		return
	var al := alive_counts()
	var standing := []
	for t in al:
		if int(al[t]) > 0:
			standing.append(int(t))
	if standing.size() > 1 or (initial_teams <= 1 and not standing.is_empty()):
		return
	# One team left; nobody left at all (the last two died together in the haze): the team that died last wins.
	var winner: int = standing[0] if standing.size() == 1 else (-1 if win_by == "wipe" else _last_dead_team)
	if win_by == "wipe":
		if winner >= 0:
			team_score[winner] = int(team_score.get(winner, 0)) + 1
		if winner < 0 or int(team_score[winner]) < score_limit:
			phase = "round_end"
			_round_winner = winner
			_next_round_at = Net.tick + int(float(_dm_rule("round_break_s", 4.0)) * Defs.TICK_RATE)
			world.server_clear_round_actions()
			_broadcast()
			log_event("round %d over: winner %d, scores %s" % [round_number, winner, str(team_score)])
			return
	phase = "ended"
	log_event("match over: winner team %d (%s) after %.0f s, %d shots fired" % [winner, team_name(winner), _t, shots_fired])
	_broadcast()
	Game.end_match_to_results(_summary(winner))


func _check_end() -> void:
	if dm:
		if phase == "playing":
			_check_end_dm()
		return
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


func force_end() -> void:
	## Tests (--end_after): finish now; the team with most standing wins.
	if phase == "ended":
		return
	phase = "ended"
	var count := {}
	for c in world.characters.values():
		if c.mode in [Motor.GROUND, Motor.FREEFALL, Motor.CHUTE, Motor.PLANE]:
			count[c.team] = int(count.get(c.team, 0)) + 1
	var winner := -1
	for t in count:
		if winner < 0 or int(count[t]) > int(count[winner]):
			winner = t
	log_event("match ended early (test): winner team %d after %.0f s" % [winner, _t])
	Game.end_match_to_results(_summary(winner))


func _summary(winner: int) -> Dictionary:
	var rows := []
	var seen := {}
	for s in (_pid_stats.values() if dm else stats.values()):
		if seen.has(int(s.pid)):
			continue
		seen[int(s.pid)] = true
		var place := 1 if int(s.team) == winner else maxi(int(s.placed), 2)
		rows.append({"pid": int(s.pid), "name": s.name, "team": s.team, "kills": s.kills, "downs": s.downs, "time": int(s.alive_t), "winner": int(s.team) == winner,
			"bot": s.bot, "damage": int(float(s.damage)), "place": place})
	rows.sort_custom(func(a, b): return (a.winner and not b.winner) or (a.winner == b.winner and a.kills > b.kills))
	var names := []
	for r in rows:
		if r.winner:
			names.append(r.name)
	var out := {"winner_team": winner, "winners": names, "rows": rows, "duration": int(_t), "teams": initial_teams,
		"game_mode": "deathmatch" if dm else "classic"}
	if dm:
		out.team_names = team_names
		out.winner_name = team_name(winner) if winner >= 0 else ""
		out.win_by = win_by
		out.score = team_score.duplicate()
		out.rounds = round_number
	return out


# ------------------------------------------------------------------ replication

func _state() -> Dictionary:
	var s := {"phase": phase, "plane": plane, "zone": zone if not dm or _field_enabled else {}, "t0": match_t0, "day_offset": day_offset,
		"game_mode": "deathmatch" if dm else "classic", "alive": alive_counts(),
		"day_len": DayCycle.phase_len, "night_only": DayCycle.night_only}
	if dm:
		s.team_names = team_names
		s.win_by = win_by
		s.field_enabled = _field_enabled
		if win_by == "wipe":
			s.score = team_score.duplicate()
			s.score_limit = score_limit
			s.round = round_number
			s.round_winner = _round_winner
			s.next_round_at = _next_round_at
		if respawns():
			s.score = team_score
			s.score_limit = score_limit
			s.time_limit = time_limit_s
			s.respawn_s = float(_dm_rule("respawn_s", 5.0))
	return s


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
