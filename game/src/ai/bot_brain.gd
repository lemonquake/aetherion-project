extends RefCounted
## A server-side bot that plays through the same command interface as a human (it cannot cheat movement or aim
## through walls; it only presses virtual buttons). States: deploy, loot, roam, investigate, fight, heal, zone, and
## (r10) camp, overwatch, hunt, follow.
##
## Every bot has a brain of its own and a role that decides what it does when nobody is in sight:
##   looter   hurries into a house, searches it, closes the door behind it and holds the room, watching the door;
##   rusher   fearless: hunts in the open toward the latest sighting, noise or ping, sprinting;
##   sniper   takes a waypoint with cover beside it and a long sightline (or one the team learned was good) and
##            watches through the scope, moving on after a kill or when shot at;
##   stalker  tactical: hunts from cover waypoint to cover waypoint, walking quietly and crouching when close, flanking.
## About half the bots of a team pair up or make threes behind a leader (bot_team.gd); some attach themselves to a human
## teammate ("I'll go with you"). Bots talk on the team radio (real voice lines, rate-limited), react to the team's
## pings by role, can follow an enemy laser beam back to whoever holds it, and fear the haze: they work out how long the
## run to the next circle takes and leave in time. Stuck bots jump or vault, open the door in front of them, back off
## and sidestep, then mark the spot so the walk grid avoids it (learned across matches with Settings > Bots learn).
##
## Perception is darkness-aware: a player is seen within ~14 m in the dark, ~30 m in moonlight on open ground,
## and up to 70 m when their flashlight is on or they just fired. Gunshots and nearby running are heard.
const DayCycle := preload("res://src/world/day_cycle.gd")

const NavGrid := preload("res://src/ai/nav_grid.gd")
const LootSense := preload("res://src/ai/loot_sense.gd")

var world = null
var ch = null
var rng := RandomNumberGenerator.new()
var state := "deploy"
var seq := 0
var yaw := 0.0
var pitch := 0.0
var path: Array = []
var path_i := 0
var goal := Vector3.INF
var target_eid := -1
var last_seen := Vector3.INF
var investigate := Vector3.INF
var reaction := 0.0
var aim_err := Vector2.ZERO
var _stuck_t := 0.0
var _wet_t := 0.0
var _last_pos := Vector3.ZERO
var _repath_t := 0.0
var _think_t := 0.0
var _land_target := Vector3.INF
var _jump_at := -1.0
var _visited := {}
var _fire_hold := 0.0
var _use_t := 0.0
var _light_on := false
var _wander_t := 0.0
## House search: a list of steps {p, nav, door, search} walked in order (outside the door, through it, to each
## container on that floor, and back out).
var plan: Array = []
var plan_i := 0
var _step_t := 0.0
var _door_hold := 0.0
var _searched := {}
var _best_d := INF
var _no_progress := 0.0
## Loose loot: an item the bot is walking to (detour from a house search), a fetch target outside, and what it gave
## up on.
var _detour := -1
var _detour_t := 0.0
var _fetch := {}          # {kind: "item"/"container", id, p}
var _skip := {}           # "item:12" / "container:40" -> true
var _scan_t := 0.0
var _scan_why := {}
var _junk_t := 0.0
var _slot_hold := 0.0
static var site_boxes := []   # containers outside houses (bid -1)
## Match-wide looting counters for the [lootstats] log line.
static var counts := {"detours": 0, "detour_taken": 0, "fetches": 0, "fetch_done": 0, "items_taken": 0}
static var nav = null
## Path searches run on a worker thread, one at a time (NavGrid.request/take); a bot walks straight toward its goal
## until its path arrives.
const MAX_EXPAND := 2200
const BCELL := 40.0
var _path_pending := false
var _path_req := 0
## Per-map lookups shared by every bot: building id -> outer doors / containers.
static var _index_layout = null
static var doors_by_bid := {}
static var conts_by_bid := {}
static var bgrid := {}   # Vector2i(40 m cell) -> [building]
## Team landing spots for the current match: "seed:team" -> Vector3.
static var team_targets := {}
## r7 Deathmatch: bots start armed on the ground, so they skip the early looting. Each team advances on the other
## side in a loose group, shares sightings (a teammate's callout: "seed:team" -> {p: Vector3, t: msec}), keeps
## inside the haze line, and loots only when it helps (low on rounds, or a clearly better gun close by).
var dm := false
var _dm_offset := Vector3.ZERO     # this bot's place in the loose group
var _dm_goal_t := 0.0
var _dm_obj := Vector3.INF
var _dm_hold := 0.0               # the first seconds of a round: everyone gets ready at the spawn
static var team_intel := {}
# --- r10: roles, squads, radio, waypoints
const BotTeam := preload("res://src/ai/bot_team.gd")
const ROLES := ["looter", "rusher", "sniper", "stalker"]
static var lines := {}            # data/bot_radio.json: line -> phrasings
var role := "looter"
var voice := "m1"
var squad_id := -1
var aggr := 0.5                   # how readily it pushes a fight
var patience := 0.5               # how long it holds a spot; how early it leaves for the next circle
var _say_t := -100000
var _obj := Vector3.INF           # the role's current objective
var _obj_t := 0.0                 # seconds before it is rethought
var _hold_t := 0.0                # camp / overwatch time left
var _look_at := Vector3.INF       # where to face while holding or following
var _hold_base_yaw := 0.0
var _ping := {}                   # a teammate's ping being acted on: {p, t, how}
var _laser_cd := 0.0
var _hit_t := -100.0              # seconds (Time) of the last hit taken
var _no_prog := 0.0               # seconds without getting closer to the next waypoint
var _best_wp := INF
var _wp_key := Vector3.INF
var _vault_cd := 0.0
var _unstick_t := 0.0             # backing off / sidestepping while > 0
var _unstick_dir := 1.0
var _social_t := 0.0
var _decided_human := false
var _follow_off := Vector3.ZERO
var _follow_far_t := 0.0
var _follow_goal_t := 0.0
var _safe_t := 0.0
var _camp_done := {}              # building id -> true (houses already held)
var _door_close := -1             # door id to shut behind us (looter on the way in)
var _seen_t := 0.0                # seconds the current target has been in sight
var _goal_raw := Vector3.INF      # the goal as asked for (goal itself may be snapped to this side of a wall)
var _haze_said := -2              # zone phase this bot last called the haze in
var _chat_t := -100000            # msec of the last "hunting"/"sneaking"/"sniping" remark
var _trail: Array = []            # recent positions (debug: --radiolog prints them when a bot ends up in a canal)
var _house_exit: Array = []       # [just inside the door, outside it] of the house this bot went into


func _init(w, c) -> void:
	world = w
	ch = c
	rng.seed = hash(c.eid * 7919 + Game.match_seed)
	var fresh_nav: bool = nav == null or nav.layout != world.map.layout
	if fresh_nav:
		nav = NavGrid.new(world.map.layout)
	if _index_layout != world.map.layout:
		_build_index()
	BotTeam.begin(world)
	if fresh_nav:
		BotTeam.apply_blocked(nav)
	BotTeam.ensure_spots(nav)
	if lines.is_empty():
		var f := FileAccess.open("res://data/bot_radio.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				lines = d.get("lines", {})
	# A role of its own, spread so every team gets a mix; a voice of its own.
	var rr := RandomNumberGenerator.new()
	rr.seed = hash(c.eid * 104729 + Game.match_seed * 31)
	role = str(ROLES[(int(c.eid) + rr.randi_range(0, 3)) % ROLES.size()]) if Game.arg("bot_role") == null else str(Game.arg("bot_role"))
	voice = ["m1", "m2", "f1", "f2"][rr.randi_range(0, 3)]
	aggr = {"looter": 0.35, "rusher": 0.95, "sniper": 0.25, "stalker": 0.6}[role] + rr.randf_range(-0.1, 0.1)
	patience = {"looter": 0.8, "rusher": 0.2, "sniper": 0.9, "stalker": 0.6}[role] + rr.randf_range(-0.1, 0.1)
	var fa := rr.randf() * TAU
	_follow_off = Vector3(cos(fa) * 3.5, 0, absf(sin(fa)) * 3.0 + 2.0)
	_social_t = rr.randf_range(0.0, 1.0)
	dm = Net.is_dm()
	if dm:
		state = "roam"
		var a := rng.randf() * TAU
		_dm_offset = Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.0, 13.0)
		_dm_goal_t = rng.randf_range(0.0, 1.5)
		_dm_hold = float(Defs.rule("deathmatch.start_hold_s", 4.0)) + rng.randf_range(0.0, 1.5)
		return
	_pick_landing()


func lead_rank() -> int:
	return {"rusher": 3, "stalker": 2, "sniper": 1, "looter": 0}.get(role, 0)


func _build_index() -> void:
	_index_layout = world.map.layout
	doors_by_bid = {}
	conts_by_bid = {}
	bgrid = {}
	for b in world.map.buildings:
		var o: Vector3 = (b.xf as Transform3D).origin
		var k := Vector2i(floori(o.x / BCELL), floori(o.z / BCELL))
		if not bgrid.has(k):
			bgrid[k] = []
		bgrid[k].append(b)
	team_targets = {}
	team_intel = {}
	counts = {"detours": 0, "detour_taken": 0, "fetches": 0, "fetch_done": 0, "items_taken": 0}
	for d in world.map.dyn.doors:
		if d.get("outer", false) and d.has("bid") and d.has("outward"):
			if not doors_by_bid.has(d.bid):
				doors_by_bid[d.bid] = []
			doors_by_bid[d.bid].append(d)
	site_boxes = []
	for c in world.map.dyn.containers:
		if int(c.bid) < 0:
			site_boxes.append(c)
			continue
		if not conts_by_bid.has(c.bid):
			conts_by_bid[c.bid] = []
		conts_by_bid[c.bid].append(c)


func _human_mate():
	for o in world.characters.values():
		if o != ch and o.team == ch.team and not Net.is_bot(o.pid):
			return o
	return null


func _pick_landing() -> void:
	## One spot per team, near the flight path; each member aims for a house close to it.
	var key := "%d:%d" % [Game.match_seed, ch.team]
	var bs: Array = world.map.buildings
	if bs.is_empty():
		_land_target = Vector3.ZERO
		return
	if not team_targets.has(key):
		var pl: Dictionary = world.match_server.plane if world.match_server else {}
		var spot := Vector3.ZERO
		if not pl.is_empty():
			var t := rng.randf_range(0.2, 0.8)
			var p: Vector3 = (pl.a as Vector3).lerp(pl.b, t)
			var side: Vector3 = ((pl.b as Vector3) - (pl.a as Vector3)).cross(Vector3.UP).normalized()
			spot = p + side * rng.randf_range(-160.0, 160.0) * float(world.map.layout.MAP_SCALE)
		var best = bs[0]
		var bd := INF
		for b in bs:
			if not conts_by_bid.has(b.id) or not doors_by_bid.has(b.id):
				continue
			var o: Vector3 = (b.xf as Transform3D).origin
			var d := Vector2(o.x - spot.x, o.z - spot.z).length() + rng.randf_range(0.0, 40.0)
			if d < bd and world.map.layout.in_play_area(Vector2(o.x, o.z)):
				bd = d
				best = b
		team_targets[key] = (best.xf as Transform3D).origin
	var centre: Vector3 = team_targets[key]
	# My own house: a random one with loot within 45 m of the team spot.
	var options := []
	for b in bs:
		var o: Vector3 = (b.xf as Transform3D).origin
		if conts_by_bid.has(b.id) and doors_by_bid.has(b.id) and Vector2(o.x - centre.x, o.z - centre.z).length() < 45.0:
			options.append(b)
	var mine: Dictionary = options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else {}
	if mine.is_empty():
		_land_target = centre
		return
	var dd: Dictionary = (doors_by_bid[mine.id] as Array)[0]
	_land_target = (dd.xf as Transform3D).origin + (dd.outward as Vector3) * 3.0
	_land_target.y = (mine.xf as Transform3D).origin.y


func wants_jump(plane_p: Vector3) -> bool:
	## Bots never push a human teammate out of the plane: that team leaves when the human jumps.
	if _human_mate() != null:
		return false
	if _land_target == Vector3.INF:
		return true
	var d := Vector2(plane_p.x - _land_target.x, plane_p.z - _land_target.z).length()
	if _jump_at < 0.0:
		_jump_at = rng.randf_range(150.0, 210.0)
	return d < _jump_at


func on_flyby(pos: Vector3) -> void:
	investigate = pos
	reaction = 0.0
	if state == "overwatch":
		_look_at = pos


func hear(pos: Vector3, loudness: float) -> void:
	if state in ["fight"]:
		return
	if ch.global_position.distance_to(pos) < loudness:
		investigate = pos


# ------------------------------------------------------------------ main

func think(dt: float, tick: int) -> Dictionary:
	seq += 1
	var cmd := {"seq": seq, "mx": 0.0, "my": 0.0, "yaw": yaw, "pitch": pitch, "btn": 0, "slot": ch.wpn.want, "view_tick": tick, "tick": tick}
	match ch.mode:
		Motor.PLANE:
			return cmd
		Motor.FREEFALL, Motor.CHUTE:
			return _deploy(cmd, dt)
		Motor.DOWNED:
			cmd.my = 0.5
			return cmd
		Motor.DEAD, Motor.SPECTATE:
			return cmd
	# Down in a walled canal (wading the estero is fine): get out first, up a ladder or to the nearest dry ground.
	if (ch.water_depth() > 0.45 and _in_canal()) or (bool(ch.get_meta("ladder_ok", false)) and not ch.is_on_floor()):
		if _wet_t == 0.0 and Game.arg("radiolog") != null and world.match_server:
			world.match_server.log_event("[canal] %s (%s) fell in at %s from %s, state %s goal %s path %d/%d, last move %s" % [ch.pname, role, str(ch.global_position.snapped(Vector3.ONE * 0.1)),
				str(_trail), state, str(goal.snapped(Vector3.ONE * 0.1)) if goal != Vector3.INF else "-", path_i, path.size(), str(path.slice(maxi(path_i - 1, 0), path_i + 2))])
		if _escape_water(cmd, dt):
			yaw = float(cmd.yaw)
			pitch = float(cmd.pitch)
			return cmd
	else:
		_wet_t = 0.0
		if ch.has_meta("ladder_ok"):
			ch.remove_meta("ladder_ok")
	_think_t -= dt
	_laser_cd = maxf(_laser_cd - dt, 0.0)
	_vault_cd = maxf(_vault_cd - dt, 0.0)
	if _think_t <= 0.0:
		_think_t = 0.25
		_trail.append(ch.global_position.snapped(Vector3.ONE * 0.1))
		if _trail.size() > 6:
			_trail.pop_front()
		_perceive()
		_social(0.25)
		_choose_state()
	match state:
		"fight":
			_fight(cmd, dt)
		"heal":
			cmd.btn |= Motor.B_HEAL if ch.health.treatment.is_empty() and rng.randf() < 0.2 else 0
			_move(cmd, dt, true)
		"fetch":
			_fetch_step(cmd, dt)
		"camp", "overwatch":
			_hold_step(cmd, dt)
			_upkeep(cmd, dt)
		"follow":
			_follow_step(cmd, dt)
			_upkeep(cmd, dt)
		_:
			if _detour >= 0:
				_detour_step(cmd, dt)
			else:
				_move(cmd, dt, false)
			_loot_actions(cmd, dt)
	_lights(cmd)
	_guard_edges(cmd)
	yaw = float(cmd.yaw)
	pitch = float(cmd.pitch)
	_trace(cmd, dt)
	return cmd


func _guard_edges(cmd: Dictionary) -> void:
	## Whatever the bot is doing (strafing in a fight, backing off a wall, keeping formation), it does not step off a
	## canal wall or into deep water: the part of the move that leads there is dropped.
	if ch.mode != Motor.GROUND or ch.water_depth() > 0.3:
		return
	var mv := Vector2(float(cmd.mx), float(cmd.my))
	if mv.length() < 0.05:
		return
	var b := Basis(Vector3.UP, float(cmd.yaw))
	var p: Vector3 = ch.global_position
	var reach: float = 1.9 if (int(cmd.btn) & Motor.B_SPRINT) != 0 else 1.2
	for comp in [Vector2(mv.x, 0.0), Vector2(0.0, mv.y)]:
		if comp.length() < 0.05:
			continue
		var d: Vector3 = b * Vector3(comp.x, 0.0, -comp.y).normalized()
		for k in [0.5, 1.0]:
			if _deep_at(p + d * reach * float(k)):
				if comp.x != 0.0:
					cmd.mx = 0.0
				else:
					cmd.my = 0.0
					cmd.btn &= ~Motor.B_SPRINT
				break


func _deep_at(q: Vector3) -> bool:
	## Water a bot should not walk into: a walled canal (Lawless Sub), or anywhere the bed is more than a metre down.
	var L = world.map.layout
	if L.has_method("water_sd"):
		# The estero (outside every walled canal) may be waded; the canals may not. Exact distance to the canal's edge,
		# not the 2 m grid: the drop can start a metre before the first cell the grid calls water. A bridge deck over
		# the canal is ground, of course.
		var q2 := Vector2(q.x, q.z)
		for r in L.bridge_rects:
			if (r as Rect2).has_point(q2):
				return false
		return (L.water_sd(q2) as Vector2).x < 0.15
	return L.is_water(q.x, q.z) and L.water_height(q.x, q.z) - L.ground_height(q.x, q.z) > 1.4


var _trace_t := 0.0


func _trace(cmd: Dictionary, dt: float) -> void:
	var who = Game.arg("bottrace")
	if who == null:
		return
	if str(who) == "first":
		if ch.eid != world.bots.keys().min():
			return
	elif str(who) not in ch.pname:
		return
	_trace_t -= dt
	if _trace_t > 0.0:
		return
	_trace_t = 1.0
	var step: Dictionary = plan[plan_i] if plan_i < plan.size() else {}
	var extra := ""
	if step.has("door"):
		var dn = world.map.dyn.doors[int(step.door)].get("node")
		extra = " door %d target %.2f locked %s" % [int(step.door), dn.target if dn else -1.0, str(dn.locked) if dn else "?"]
	if step.has("search"):
		var c: Dictionary = world.map.dyn.containers[int(step.search)]
		var t: Dictionary = world.interaction.target(ch, cmd)
		extra = " container %d at %s dist %.2f; use ray sees %s" % [int(step.search), str((c.pos as Vector3).snapped(Vector3.ONE * 0.01)),
			ch.eye_position().distance_to(c.pos), str(t.get("kind", "-")) + str(t.get("id", ""))]
	if _detour >= 0:
		extra += " detour item %d" % _detour
	if not _fetch.is_empty():
		extra += " fetch %s %d %.0f m" % [str(_fetch.kind), int(_fetch.id), (_fetch.p as Vector3).distance_to(ch.global_position)]
	var guns := []
	for sl in [1, 2, 3]:
		if ch.wpn.slots[sl] != null:
			guns.append("%s(%d+%d)" % [ch.wpn.slots[sl].id, int(ch.wpn.slots[sl].mag), ch.inv.count(Defs.ammo_item(str(ch.wpn.slots[sl].id)))])
	extra += " guns " + ",".join(guns)
	if not _scan_why.is_empty():
		extra += " scan " + str(_scan_why)
	print("[bot %s] %s step %d/%d %s at %s -> %s (%.1f m) path %d/%d stuck %.1f btn %d%s" % [ch.pname, state, plan_i, plan.size(),
		"nav" if step.get("nav", false) else ("search" if step.has("search") else ("door" if step.has("door") else "walk")),
		str(ch.global_position.snapped(Vector3.ONE * 0.1)), str((step.get("p", goal) as Vector3).snapped(Vector3.ONE * 0.1)),
		Vector2(ch.global_position.x - (step.get("p", goal) as Vector3).x, ch.global_position.z - (step.get("p", goal) as Vector3).z).length(),
		path_i, path.size(), _stuck_t, int(cmd.btn), extra])


func _deploy(cmd: Dictionary, dt: float) -> Dictionary:
	var hm = _human_mate()
	if hm != null and hm.mode in [Motor.FREEFALL, Motor.CHUTE, Motor.GROUND]:
		# Follow the human's lead, keeping a few metres of formation offset.
		var off := Vector3(cos(ch.eid * 2.1), 0, sin(ch.eid * 2.1)) * 9.0
		_land_target = hm.global_position + off + Vector3(hm.velocity.x, 0, hm.velocity.z) * 2.0
	var to = _land_target - ch.global_position
	var flat := Vector2(to.x, to.z)
	var want_yaw := atan2(-flat.x, -flat.y)
	if ch.mode == Motor.FREEFALL:
		cmd.yaw = want_yaw
		cmd.my = 1.0 if flat.length() > 30.0 else 0.0
		if ch.height_above_ground() < 160.0 and rng.randf() < 0.05:
			cmd.btn |= Motor.B_JUMP
		return cmd
	# Canopy: turn toward the target with A/D, speed up when far, brake when overshooting.
	var diff := wrapf(want_yaw - ch.chute_yaw, -PI, PI)
	cmd.mx = clampf(-diff * 2.0, -1.0, 1.0)
	cmd.my = 1.0 if flat.length() > 80.0 else (-1.0 if flat.length() < 15.0 else 0.0)
	cmd.yaw = want_yaw
	if ch.height_above_ground() < 3.5 and ch.flare_t <= 0.0:
		cmd.btn |= Motor.B_JUMP
	return cmd


func _perceive() -> void:
	var best := -1
	var best_d := INF
	var eye: Vector3 = ch.eye_position()
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	# Under the artificial sun an open lane is seen far; rooms and roofed lanes stay dark.
	var day: float = DayCycle.daylight(world.map.lighting.match_time()) if world.map and world.map.lighting else 0.0
	for o in world.characters.values():
		if o == ch or o.team == ch.team or o.mode not in [Motor.GROUND, Motor.DOWNED, Motor.CHUTE]:
			continue
		var d: float = o.global_position.distance_to(ch.global_position)
		var lit: bool = (o.flags & Character.F_LIGHT) != 0 or (o.flags & Character.F_FIRED) != 0
		var open: bool = world.map.acoustics.zone_at(o.global_position) == 0 and not (world.map.cover and world.map.cover.covered(Vector2(o.global_position.x, o.global_position.z)))
		var vis_range := 70.0 if lit else (lerpf(30.0, 75.0, day) if open else 12.0)
		if role == "sniper" and state == "overwatch":
			vis_range *= 1.5   # watching through the scope
		if o.mode == Motor.CHUTE:
			vis_range = 90.0
		if d > vis_range:
			continue
		var to: Vector3 = (o.global_position + Vector3.UP * 1.2) - eye
		var fwd := -Basis.from_euler(Vector3(0, yaw, 0)).z
		if d > 6.0 and fwd.dot(to.normalized()) < 0.2 and not lit:
			continue  # behind and quiet
		var q := PhysicsRayQueryParameters3D.create(eye, eye + to, Defs.SIGHT_MASK)
		if not space.intersect_ray(q).is_empty():
			continue
		if d < best_d:
			best_d = d
			best = o.eid
	if best != target_eid and best >= 0:
		reaction = rng.randf_range(0.35, 0.8)
		aim_err = Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4))
		if target_eid < 0:
			say("contact")
	target_eid = best
	if best >= 0:
		last_seen = world.characters[best].global_position
		# The callout: the whole team knows where (each decides on its own what to do about it).
		team_intel["%d:%d" % [Game.match_seed, ch.team]] = {"p": last_seen, "t": Time.get_ticks_msec()}


func _choose_state() -> void:
	var h = ch.health
	if target_eid >= 0:
		# Caught in the haze with the enemy not close: keep running for the circle (it kills faster than they do).
		var tc = world.characters.get(target_eid)
		var hz0 := _haze()
		if bool(hz0.urgent) and tc != null and (tc.global_position as Vector3).distance_to(ch.global_position) > 15.0:
			if state != "zone" or goal == Vector3.INF:
				_set_goal(hz0.p)
			state = "zone"
			return
		state = "fight"
		_seen_t += 0.25
		return
	_seen_t = 0.0
	if h.bleeding_level() > 0 or (h.health < (60.0 if not dm else 50.0) and ch.inv.count("first_aid") > 0):
		state = "heal"
		return
	# Inside a house and about to go anywhere else: out of the door first (the walk grid does not reach indoors, so a
	# path from in here led straight into the walls).
	if _exiting():
		return
	# The haze: leave in time for the next circle (sooner the less patient), and run when caught in it.
	var hz := _haze()
	if bool(hz.go) and _leave_house():
		return
	if bool(hz.go):
		if state != "zone" or goal == Vector3.INF or _goal_raw.distance_to(hz.p) > 25.0:
			_set_goal(hz.p)
			var phase := int(world.match_info.get("zone", {}).get("i", -1))
			if _leads() and _haze_said != phase:
				_haze_said = phase
				say("haze", bool(hz.urgent))
		state = "zone"
		plan = []
		return
	if dm and _dm_hold > 0.0:
		_dm_hold -= 0.25
		state = "roam"
		goal = Vector3.INF
		return
	# A teammate's ping this bot chose to act on.
	if not _ping.is_empty() and _ping_step():
		return
	# Following a squad leader or a human.
	var lead = _leader()
	if lead != null:
		if state != "follow":
			_follow_goal_t = 0.0
		state = "follow"
		return
	if investigate != Vector3.INF:
		if state in ["camp", "overwatch"] and ch.global_position.distance_to(investigate) > 18.0:
			# Holding a spot: look that way rather than leave it.
			_look_at = investigate
			investigate = Vector3.INF
			return
		if state != "investigate":
			_set_goal(_inside_zone(investigate) if dm else investigate)
		state = "investigate"
		if ch.global_position.distance_to(investigate) < 4.5 or goal == Vector3.INF:
			investigate = Vector3.INF
			if rng.randf() < 0.35:
				say("clear")
		return
	if state == "fetch" and not _fetch.is_empty():
		return
	if state == "loot" and plan_i < plan.size():
		return
	if state in ["camp", "overwatch"] and _hold_t > 0.0:
		return
	if _leave_house():
		return
	# Classic: everyone loots until armed; Deathmatch bots start armed and loot only when low on rounds.
	var armed: bool = LootSense.armed_ok(ch)
	if (not armed or not dm) and _pick_fetch():
		return
	if not dm and not armed:
		if state == "roam" and goal != Vector3.INF and path_i < path.size():
			return
		_pick_loot_goal()
		return
	_role_objective()


# ------------------------------------------------------------------ zone

func _inside_zone(p: Vector3) -> Vector3:
	## Pulls a goal inside the next safe circle (or the current one before the first is announced).
	var zone: Dictionary = world.match_info.get("zone", {})
	var circ: Array = world.zone_circle(float(Net.tick))
	var c: Vector2 = zone.get("c1", circ[0])
	var r := float(zone.get("r1", circ[1])) * 0.85
	var q := Vector2(p.x, p.z)
	if q.distance_to(c) > r:
		q = c + (q - c).limit_length(r)
	return Vector3(q.x, p.y, q.y)


func _pick_loot_goal() -> void:
	# Nearest unvisited house with loot within 80 m; otherwise wander toward the zone centre.
	var best = null
	var bd := INF
	var here := Vector2i(floori(ch.global_position.x / BCELL), floori(ch.global_position.z / BCELL))
	var near := []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			near.append_array(bgrid.get(here + Vector2i(dx, dz), []))
	for b in near:
		if _visited.has(b.id) or not doors_by_bid.has(b.id) or not conts_by_bid.has(b.id):
			continue
		var o: Vector3 = (b.xf as Transform3D).origin
		var d := o.distance_to(ch.global_position)
		if d > 80.0:
			continue
		d += rng.randf_range(0.0, 12.0)
		if d < bd:
			bd = d
			best = b
	if best != null:
		_visited[best.id] = true
		if _plan_house(best):
			state = "loot"
			return
	state = "roam"
	plan = []
	var circ: Array = world.zone_circle(float(Net.tick))
	var c: Vector2 = circ[0]
	_set_goal(Vector3(c.x + rng.randf_range(-80, 80), 0, c.y + rng.randf_range(-80, 80)))


func _plan_house(b: Dictionary) -> bool:
	## Outside the nearest outer door -> just inside -> each container on that floor (nearest first) -> back out.
	var doors: Array = doors_by_bid.get(b.id, [])
	if doors.is_empty():
		return false
	var door: Dictionary = doors[0]
	var dc := INF
	for d in doors:
		var c0: Vector3 = (d.xf as Transform3D).origin
		if c0.distance_to(ch.global_position) < dc:
			dc = c0.distance_to(ch.global_position)
			door = d
	var out_dir: Vector3 = door.outward
	out_dir.y = 0.0
	out_dir = out_dir.normalized()
	var dxf: Transform3D = door.xf
	var centre: Vector3 = dxf * Vector3(float(door.w) * 0.5, 0.0, 0.0)
	var inside := centre - out_dir * 1.0
	var foot_of_steps := float(door.get("steps_out", 0.0))
	plan = [{"p": centre + out_dir * (1.2 + foot_of_steps), "nav": true}, {"p": inside, "nav": false, "door": int(door.id)}]
	_house_exit = [inside, centre + out_dir * (1.4 + foot_of_steps)]
	var conts := []
	for c in conts_by_bid.get(b.id, []):
		if absf((c.pos as Vector3).y - centre.y) < 1.7 and not _searched.has(c.id):
			conts.append(c)
	var at := inside
	while not conts.is_empty():
		var bi := 0
		for i in conts.size():
			if (conts[i].pos as Vector3).distance_to(at) < (conts[bi].pos as Vector3).distance_to(at):
				bi = i
		var c: Dictionary = conts[bi]
		conts.remove_at(bi)
		var cp: Vector3 = c.pos
		var stand := cp + (inside - cp) * Vector3(1, 0, 1)
		stand = cp + (stand - cp).limit_length(0.95)
		stand.y = centre.y
		plan.append({"p": stand, "nav": false, "search": int(c.id)})
		at = stand
	if role == "looter" and not _camp_done.has(int(b.id)) and (dm or LootSense.armed_ok(ch) or rng.randf() < 0.5):
		# Hold the house: back to just inside the door, facing it, and stay (the door shut behind on the way in).
		_camp_done[int(b.id)] = true
		plan.insert(2, {"p": inside, "nav": false, "close": int(door.id)})
		var camp_at := inside - out_dir * 1.6
		camp_at.y = centre.y
		plan.append({"p": camp_at, "nav": false, "camp": true, "face": centre + out_dir * 3.0})
	else:
		plan.append({"p": inside, "nav": false})
		plan.append({"p": centre + out_dir * (1.4 + foot_of_steps), "nav": false})
	plan_i = 0
	_step_t = 0.0
	_best_d = INF
	_no_progress = 0.0
	_door_hold = 0.0
	_set_goal(plan[0].p)
	return true


func _in_canal() -> bool:
	var L = world.map.layout
	if not L.has_method("water_sd"):
		return true
	return (L.water_sd(Vector2(ch.global_position.x, ch.global_position.z)) as Vector2).x < 0.0


func _escape_water(cmd: Dictionary, dt: float) -> bool:
	## Wading a moment is fine; after that, head for the nearest ladder whose foot is down here and climb it facing
	## the wall, or (no ladder near, a sloped bank) walk to the nearest dry ground. False: not yet, carry on as usual.
	_wet_t += dt
	if _wet_t < 1.5 and not bool(ch.get_meta("ladder_ok", false)):
		return false
	var p: Vector3 = ch.global_position
	var best := {}
	var bd := 90.0
	for ld in world.map.ladders:
		var b: Vector3 = ld.base
		if b.y > p.y + 1.0:
			continue
		var dd := Vector2(b.x - p.x, b.z - p.z).length()
		if dd < bd:
			bd = dd
			best = ld
	cmd.pitch = lerpf(pitch, 0.25, 0.2)
	cmd.my = 1.0
	if not best.is_empty():
		ch.set_meta("ladder_ok", true)
		var n: Vector3 = best.n
		var foot: Vector3 = (best.base as Vector3) + n * 0.3
		var to := Vector2(foot.x - p.x, foot.z - p.z)
		if to.length() > 0.35 and ch.is_on_floor():
			cmd.yaw = lerp_angle(yaw, atan2(-to.x, -to.y), 0.3)
		else:
			cmd.yaw = lerp_angle(yaw, atan2(n.x, n.z), 0.5)
		return true
	# No ladder: the closest dry point round about.
	for r in [2.0, 4.0, 7.0, 11.0, 16.0, 22.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var q = Vector2(p.x, p.z) + Vector2(cos(a), sin(a)) * r
			if not world.map.layout.is_water(q.x, q.y):
				var to2 = q - Vector2(p.x, p.z)
				cmd.yaw = lerp_angle(yaw, atan2(-to2.x, -to2.y), 0.3)
				if _stuck_t > 1.0:
					cmd.btn |= Motor.B_JUMP
				var moved := p.distance_to(_last_pos)
				_last_pos = p
				_stuck_t = _stuck_t + dt if moved < 0.4 * dt else 0.0
				return true
	return false


func _set_goal(g: Vector3) -> void:
	# A goal on the far side of a wall (another region of the walk grid) becomes the nearest point this side of it:
	# without this, bots walked into the wall toward it and stayed there.
	_goal_raw = g
	if g != Vector3.INF and nav != null:
		g = nav.reachable_near(ch.global_position, g)
	goal = g
	_no_prog = 0.0
	_best_wp = INF
	path = []
	path_i = 0
	_path_pending = true
	_repath_t = 6.0
	if _path_req != 0:
		nav.cancel(_path_req)
		_path_req = 0
	_ensure_path()


func _ensure_path() -> void:
	if _path_req != 0:
		var r = nav.take(_path_req)
		if r != null:
			_path_req = 0
			path = r
			path_i = 0
		return
	if not _path_pending or goal == Vector3.INF:
		return
	_path_pending = false
	_path_req = nav.request(ch.global_position, goal, MAX_EXPAND)


func _move(cmd: Dictionary, dt: float, slow: bool) -> void:
	_ensure_path()
	if state == "loot" and plan_i < plan.size():
		_plan_step(cmd, dt)
		return
	if goal == Vector3.INF:
		return
	var target := goal
	if path_i < path.size():
		target = path[path_i]
		if Vector2(target.x - ch.global_position.x, target.z - ch.global_position.z).length() < 1.2:
			path_i += 1
			_best_wp = INF
	var to = target - ch.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 0.6 and path_i >= path.size():
		goal = Vector3.INF
		return
	var want_yaw := atan2(-flat.x, -flat.y)
	cmd.yaw = lerp_angle(yaw, want_yaw, 0.2)
	cmd.pitch = lerpf(pitch, 0.0, 0.1)
	cmd.my = 1.0
	# No path yet (searches queue on a worker thread): walk straight only if nothing is in the way; otherwise turn
	# toward the goal and wait. Walking straight at a goal behind a wall is how bots ended up stuck on walls.
	if path.is_empty() and _path_req != 0 and not nav.line_clear(ch.global_position, goal):
		cmd.my = 0.0
		return
	_gait(cmd, flat.length(), slow)
	_unstick(cmd, dt, target, flat.length())
	_repath_t -= dt
	if _repath_t <= 0.0 and goal != Vector3.INF:
		_set_goal(goal)


func _gait(cmd: Dictionary, dist: float, slow: bool) -> void:
	## How a bot moves, by state and role: running from the haze, rushers sprinting, stalkers walking quietly and
	## crouching close to their quarry, looters hurrying to their house.
	if slow:
		cmd.btn |= Motor.B_WALK
		return
	var to_obj: float = ch.global_position.distance_to(_obj) if _obj != Vector3.INF else INF
	match state:
		"zone":
			cmd.btn |= Motor.B_SPRINT
		"investigate", "hunt":
			if role == "stalker" and to_obj < 45.0:
				cmd.btn |= Motor.B_WALK
				if to_obj < 16.0:
					cmd.btn |= Motor.B_CROUCH
			elif role == "sniper" and to_obj < 20.0:
				cmd.btn |= Motor.B_WALK
			elif dist > 4.0 and rng.randf() < 0.9:
				cmd.btn |= Motor.B_SPRINT
		"roam":
			if role == "rusher" or (role == "looter" and dist > 6.0) or to_obj > 60.0:
				cmd.btn |= Motor.B_SPRINT
			elif role == "stalker" and to_obj < 30.0:
				cmd.btn |= Motor.B_WALK
		"follow":
			pass


func _unstick(cmd: Dictionary, dt: float, target: Vector3, dist: float) -> void:
	## Progress, not motion, toward the next waypoint. Stuck: jump (a vault over a low wall or through a window when
	## there is one), open a door that is in the way, back off and sidestep, then tell the team the cell is blocked
	## (the walk grid closes it the second time) and search again; give up on the goal after that.
	if _wp_key != target:
		_wp_key = target
		_best_wp = INF
		_no_prog = 0.0
	if dist < _best_wp - 0.15:
		_best_wp = dist
		_no_prog = maxf(_no_prog - dt * 2.0, 0.0)
	else:
		_no_prog += dt
	_stuck_t = _no_prog
	if _unstick_t > 0.0:
		_unstick_t -= dt
		cmd.my = -0.6
		cmd.mx = _unstick_dir
		cmd.btn &= ~Motor.B_SPRINT
		return
	if _no_prog > 0.7 and _vault_cd <= 0.0:
		_vault_cd = 1.6
		match _ahead():
			"low", "":
				# A vault or a hop, only where the walk grid has open ground beyond (not onto a parapet or a wall top).
				var fwd0 := -Basis(Vector3.UP, yaw).z
				if nav.walkable_at(ch.global_position + fwd0 * 1.6):
					cmd.btn |= Motor.B_JUMP
			"char":
				_unstick_t = 0.5           # a teammate in the way: step round, do not hop on them
				_unstick_dir = 1.0 if (ch.eid % 2) == 0 else -1.0
	if _no_prog > 1.1:
		var t: Dictionary = world.interaction.target(ch, cmd)
		if not t.is_empty() and str(t.kind) == "door" and absf(t.obj.target) < 0.05 and not t.obj.locked:
			cmd.btn |= Motor.B_USE
	if _no_prog > 1.6 and _no_prog < 1.7:
		_unstick_t = 0.6
		_unstick_dir = 1.0 if rng.randf() < 0.5 else -1.0
	if _no_prog > 3.2:
		var fwd := -Basis(Vector3.UP, yaw).z
		if _ahead() in ["wall", "low"]:
			BotTeam.note_stuck(nav, ch.global_position + fwd * 1.2, ch.eid)
		_no_prog = 0.0
		_best_wp = INF
		_stuck_hits += 1
		if _stuck_hits >= 3:
			_stuck_hits = 0
			goal = Vector3.INF
			_obj = Vector3.INF
			_obj_t = 0.0
		elif goal != Vector3.INF:
			_set_goal(goal)


var _stuck_hits := 0


func _ahead() -> String:
	## What is in front at knee and chest height within a metre: "low" (an obstacle to vault or hop), "wall", "char"
	## (a person), or "" (nothing: stuck on something else).
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var fwd := -Basis(Vector3.UP, yaw).z
	var base = ch.global_position
	var hits := []
	for h in [0.45, 1.25]:
		var q := PhysicsRayQueryParameters3D.create(base + Vector3.UP * h, base + Vector3.UP * h + fwd * 1.0, Defs.MOVE_MASK | Defs.PHYS_CHAR)
		q.exclude = [ch.get_rid()]
		hits.append(space.intersect_ray(q))
	for r in hits:
		if not (r as Dictionary).is_empty() and (r.collider is Character):
			return "char"
	if not (hits[0] as Dictionary).is_empty() and (hits[1] as Dictionary).is_empty():
		# Something to vault, unless the far side is a canal or a long drop (bridge parapets, canal walls).
		var L = world.map.layout
		for k in [1.4, 2.4]:
			var q = base + fwd * k
			if L.is_water(q.x, q.z) and _deep_at(q):
				return "wall"
			var dq := PhysicsRayQueryParameters3D.create(q + Vector3.UP * 1.5, q + Vector3.DOWN * 3.0, Defs.MOVE_MASK)
			var dr := space.intersect_ray(dq)
			if dr.is_empty() or (dr.position as Vector3).y < base.y - 1.6:
				return "wall"
		return "low"
	if not (hits[1] as Dictionary).is_empty():
		return "wall"
	return ""


func _plan_step(cmd: Dictionary, dt: float) -> void:
	var step: Dictionary = plan[plan_i]
	_step_t += dt
	var target: Vector3 = step.p
	if step.nav and path_i < path.size():
		target = path[path_i]
		if Vector2(target.x - ch.global_position.x, target.z - ch.global_position.z).length() < 1.2:
			path_i += 1
			return
	var to: Vector3 = target - ch.global_position
	var flat := Vector2(to.x, to.z)
	var reach := 0.45 if not step.nav else 0.9
	var arrived = flat.length() < reach and (not step.nav or path_i >= path.size())
	if step.has("search") and flat.length() < 1.3:
		arrived = true
	if step.has("close") and (arrived or flat.length() < 1.0):
		# Shut the door behind: turn to it, one press while it stands open.
		var dn0 = world.map.dyn.doors[int(step.close)].get("node")
		if dn0 and _step_t < 3.0 and absf(dn0.target) > 0.05 and ch.eye_position().distance_to(dn0.center()) < 2.4:
			var tv0: Vector3 = dn0.center() - ch.eye_position()
			cmd.yaw = atan2(-tv0.x, -tv0.z)
			cmd.pitch = atan2(tv0.y, Vector2(tv0.x, tv0.z).length())
			if fmod(_step_t, 1.2) < 0.1:
				cmd.btn |= Motor.B_USE
			return
		arrived = true
	if step.has("camp") and (arrived or _step_t > 6.0):
		plan_i = plan.size()
		state = "camp"
		_hold_t = rng.randf_range(35.0, 80.0) * (0.5 + patience)
		_look_at = step.get("face", Vector3.INF)
		var fv: Vector3 = (_look_at - ch.global_position) if _look_at != Vector3.INF else -Basis(Vector3.UP, yaw).z
		_hold_base_yaw = atan2(-fv.x, -fv.z)
		say("inside")
		return
	if arrived or _step_t > (40.0 if step.nav else 9.0):
		if arrived and step.has("search"):
			if not _search(cmd, int(step.search)):
				return
		if not arrived and (step.has("door") or step.nav):
			# Could not get to or through the door: leave this house alone.
			if Game.arg("bottrace") != null:
				var dn2 = world.map.dyn.doors[int(step.door)].get("node") if step.has("door") else null
				print("[bot %s] gave up on a house at %s step %s: %.1f m from %s, door %s, eye-to-door %.2f" % [ch.pname, str(ch.global_position.snapped(Vector3.ONE * 0.1)),
					"door" if step.has("door") else "approach", flat.length(), str((step.p as Vector3).snapped(Vector3.ONE * 0.1)),
					("angle %.2f target %.2f locked %s" % [dn2.angle, dn2.target, str(dn2.locked)]) if dn2 else "-",
					ch.eye_position().distance_to(dn2.center()) if dn2 else -1.0])
			plan_i = plan.size()
			return
		plan_i += 1
		_step_t = 0.0
		_stuck_t = 0.0
		_best_d = INF
		_no_progress = 0.0
		if plan_i < plan.size() and plan[plan_i].nav:
			_set_goal(plan[plan_i].p)
		return
	# The door on the way in: open it from outside its swing, wait for it to swing clear, then walk through.
	if step.has("door") and flat.length() < 2.4:
		var dn = world.map.dyn.doors[int(step.door)].get("node")
		if dn:
			var ang := absf(dn.angle)
			var shut: bool = ang <= dn.OPEN_PASS and absf(dn.target) < 0.05 and not dn.free
			var in_reach: bool = ch.eye_position().distance_to(dn.center()) < 2.0
			if shut and in_reach:
				var dc: Vector3 = dn.center()
				var tv: Vector3 = dc - ch.eye_position()
				cmd.yaw = atan2(-tv.x, -tv.z)
				cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
				_door_hold += dt
				if dn.locked:
					# A fresh press, then hold to force it.
					if _door_hold > 0.15 and _door_hold < 4.0:
						cmd.btn |= Motor.B_USE
				elif fmod(_door_hold, 1.6) > 0.15 and fmod(_door_hold, 1.6) < 0.3:
					cmd.btn |= Motor.B_USE  # one press per attempt (a second press would close it again)
				if flat.length() < 0.9:
					cmd.my = -0.5  # stand back out of the swing
				if _door_hold > 9.0:
					_step_t = 999.0
				return
			if dn.moving and not dn.free and ang <= dn.OPEN_PASS:
				cmd.my = -0.3
				return
	_door_hold = 0.0
	var want_yaw := atan2(-flat.x, -flat.y)
	cmd.yaw = lerp_angle(yaw, want_yaw, 0.25)
	cmd.pitch = lerpf(pitch, 0.0, 0.1)
	cmd.my = 1.0 if flat.length() > 0.8 else 0.5
	if not step.nav:
		cmd.btn |= Motor.B_WALK
	# Progress, not motion: sliding back and forth against a door leaf is still stuck.
	if flat.length() < _best_d - 0.2:
		_best_d = flat.length()
		_no_progress = 0.0
	else:
		_no_progress += dt
	_stuck_t = _no_progress
	if _no_progress > 1.0:
		cmd.mx = 1.0 if int(_no_progress * 1.5) % 2 == 0 else -1.0
		if rng.randf() < 0.08 and _ahead() in ["low", ""]:
			cmd.btn |= Motor.B_JUMP
	if _no_progress > 4.0:
		_step_t = 999.0


func _search(cmd: Dictionary, cid: int) -> bool:
	## Look at the container, press Use, take what fits. Returns true when done with it.
	var c: Dictionary = world.map.dyn.containers[cid]
	var tv: Vector3 = (c.pos as Vector3) - ch.eye_position()
	cmd.yaw = atan2(-tv.x, -tv.z)
	cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
	yaw = cmd.yaw
	pitch = cmd.pitch
	var o: Dictionary = world.interaction._open.get(ch.eid, {})
	if str(o.get("kind", "")) == "container" and int(o.get("id", -1)) == cid:
		world.interaction.bot_take_all(ch, "container", cid)
		world.interaction.server_inventory_request(ch, {"op": "close"})
		_searched[cid] = true
		_equip_best(cmd)
		return true
	if _step_t > 9.0:
		_searched[cid] = true
		return true
	if int(_step_t * 4.0) % 2 == 0:
		cmd.btn |= Motor.B_USE
	return false


func _loot_actions(cmd: Dictionary, dt: float) -> void:
	_upkeep(cmd, dt)
	_use_t -= dt
	if _use_t > 0.0:
		return
	_use_t = 0.5
	# Look for something to use right in front: an item, a container or a door in the way.
	var t: Dictionary = world.interaction.target(ch, cmd)
	if t.is_empty():
		# Glance around for loot within reach.
		for cont in world.map.dyn.containers_near(ch.eye_position(), 2.2):
			if not cont.searched or not (cont.entries as Array).is_empty():
				var to: Vector3 = (cont.pos as Vector3) - ch.eye_position()
				cmd.yaw = atan2(-to.x, -to.z)
				cmd.pitch = atan2(to.y, Vector2(to.x, to.z).length())
				break
		return
	match str(t.kind):
		"item":
			if not world.interaction.bot_take_item(ch, int(t.id)):
				_skip["item:%d" % int(t.id)] = true
		"container", "corpse":
			cmd.btn |= Motor.B_USE
			world.interaction.bot_take_all(ch, str(t.kind), int(t.get("id", -1)))
		"door":
			if absf(t.obj.target) < 0.05:
				cmd.btn |= Motor.B_USE
	_equip_best(cmd)


func _upkeep(cmd: Dictionary, dt: float) -> void:
	## Between fights: reload a half-empty gun, drop what the bot cannot use when overloaded, and look for loose loot
	## close by in the same room (or the same stretch of street).
	if ch.wpn.current_id() != "" and ch.wpn.state == 0 and ch.wpn.loaded() < int(ch.wpn.mag_cap() * 0.5) \
			and ch.wpn.reserve(str(ch.wpn.def().get("ammo", ""))) > 0 and rng.randf() < 0.3:
		cmd.btn |= Motor.B_RELOAD
	_junk_t -= dt
	if _junk_t <= 0.0:
		_junk_t = 4.0
		world.interaction.bot_drop_junk(ch, ch.inv.bag_mass() > ch.inv.capacity())
	_scan_t -= dt
	if _scan_t > 0.0 or _detour >= 0:
		return
	_scan_t = 0.8
	# Deathmatch: only a short look around for what is clearly worth it (rounds when low, a much better gun).
	var min_v := 0.6 if not dm else (2.0 if not LootSense.armed_ok(ch) else 3.5)
	var eye: Vector3 = ch.eye_position()
	var zone: int = world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5)
	var best := -1
	var bv := min_v
	var near: Array = world.map.dyn.items_near(ch.global_position, 7.0)
	var why := {"near": near.size(), "skip": 0, "height": 0, "zone": 0, "value": 0}
	for id in near:
		if _skip.has("item:%d" % id):
			why.skip += 1
			continue
		var it: Dictionary = world.map.dyn.items[id]
		var p: Vector3 = (it.xf as Transform3D).origin
		if absf(p.y - ch.global_position.y) > 1.5:
			why.height += 1
			continue
		if world.map.acoustics.zone_at(p + Vector3.UP * 0.3) != zone:
			why.zone += 1
			continue
		var v = LootSense.value(ch, it.entry) - ch.global_position.distance_to(p) * 0.05
		if v <= bv:
			why.value += 1
		if v > bv:
			bv = v
			best = id
	_scan_why = why
	if best >= 0:
		var p2: Vector3 = (world.map.dyn.items[best].xf as Transform3D).origin
		var q := PhysicsRayQueryParameters3D.create(eye, p2 + Vector3.UP * 0.15, Defs.SIGHT_MASK)
		if world.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			_detour = best
			_detour_t = 0.0
			counts.detours += 1
		else:
			_skip["item:%d" % best] = true


func _detour_step(cmd: Dictionary, dt: float) -> void:
	## Walk straight to a loose item in sight, pick it up, then carry on with whatever the bot was doing.
	var it: Dictionary = world.map.dyn.items.get(_detour, {})
	_detour_t += dt
	if it.is_empty() or _detour_t > 7.0:
		if not it.is_empty():
			_skip["item:%d" % _detour] = true
		_detour = -1
		return
	var p: Vector3 = (it.xf as Transform3D).origin
	var to = p - ch.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 1.3:
		if not world.interaction.bot_take_item(ch, _detour):
			_skip["item:%d" % _detour] = true
		else:
			counts.detour_taken += 1
		_detour = -1
		_equip_best(cmd)
		return
	cmd.yaw = lerp_angle(yaw, atan2(-flat.x, -flat.y), 0.3)
	cmd.pitch = lerpf(pitch, -0.5, 0.1)
	cmd.my = 1.0
	cmd.btn |= Motor.B_WALK
	var moved = ch.global_position.distance_to(_last_pos)
	_last_pos = ch.global_position
	if moved < 0.3 * dt and _detour_t > 1.5 and rng.randf() < 0.1 and _ahead() in ["low", ""]:
		cmd.btn |= Motor.B_JUMP


func _pick_fetch() -> bool:
	## Outside a house plan: a wanted item lying in the open or an unsearched loot box at a site, within a short
	## walk. Bots without a usable gun look further.
	var need := not LootSense.armed_ok(ch)
	var reach := 30.0 if need else 18.0
	var min_v := 2.0 if need else 2.5
	var best := {}
	var bd := INF
	var here: Vector3 = ch.global_position
	for id in world.map.dyn.items_near(here, reach):
		if _skip.has("item:%d" % id):
			continue
		var it: Dictionary = world.map.dyn.items[id]
		var p: Vector3 = (it.xf as Transform3D).origin
		if world.map.acoustics.zone_at(p + Vector3.UP * 0.3) != 0:
			continue  # indoors: found by house searches
		var v := LootSense.value(ch, it.entry)
		if v < min_v or absf(p.y - here.y) > 1.2:
			continue
		var dd := p.distance_to(here) / v
		if dd < bd and _in_sight(p + Vector3.UP * 0.1):
			bd = dd
			best = {"kind": "item", "id": id, "p": p}
	for c in site_boxes:
		if c.searched or _skip.has("container:%d" % int(c.id)):
			continue
		var p2: Vector3 = c.pos
		var dist := p2.distance_to(here)
		if dist > reach or absf(p2.y - here.y) > 1.8:
			continue
		var dd2 := dist / 1.5
		if dd2 < bd and _in_sight(p2):
			bd = dd2
			best = {"kind": "container", "id": int(c.id), "p": p2}
	if best.is_empty():
		return false
	_fetch = best
	counts.fetches += 1
	_fetch.t = 0.0
	_fetch.best = INF
	_fetch.still = 0.0
	state = "fetch"
	plan = []
	_set_goal(best.p)
	return true


func _in_sight(p: Vector3) -> bool:
	## A clear line from the bot's eyes (walls, props and glass block it; the loot itself does not).
	var q := PhysicsRayQueryParameters3D.create(ch.eye_position(), p, Defs.SIGHT_MASK)
	q.exclude = [ch.get_rid()]
	var r = world.get_world_3d().direct_space_state.intersect_ray(q)
	return r.is_empty() or (r.position as Vector3).distance_to(p) < 0.6


func _fetch_step(cmd: Dictionary, dt: float) -> void:
	_fetch.t = float(_fetch.t) + dt
	var p: Vector3 = _fetch.p
	var key := "%s:%d" % [_fetch.kind, int(_fetch.id)]
	var gone: bool = (_fetch.kind == "item" and not world.map.dyn.items.has(int(_fetch.id))) \
		or (_fetch.kind == "container" and world.map.dyn.containers[int(_fetch.id)].searched)
	var d_now := Vector2(p.x - ch.global_position.x, p.z - ch.global_position.z).length()
	if d_now < float(_fetch.best) - 0.4:
		_fetch.best = d_now
		_fetch.still = 0.0
	else:
		_fetch.still = float(_fetch.still) + dt
	if gone or float(_fetch.t) > 25.0 or float(_fetch.still) > 4.0:
		_skip[key] = true
		_fetch = {}
		state = "roam"
		goal = Vector3.INF
		return
	var flat := Vector2(p.x - ch.global_position.x, p.z - ch.global_position.z)
	if flat.length() < 1.4:
		counts.fetch_done += 1
		if _fetch.kind == "item":
			world.interaction.bot_take_item(ch, int(_fetch.id))
		else:
			var tv: Vector3 = p - ch.eye_position()
			cmd.yaw = atan2(-tv.x, -tv.z)
			cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
			cmd.btn |= Motor.B_USE
			world.interaction.bot_take_all(ch, "container", int(_fetch.id))
		_skip[key] = true
		_fetch = {}
		state = "roam"
		goal = Vector3.INF
		_equip_best(cmd)
		return
	_move(cmd, dt, false)
	if goal == Vector3.INF:
		# Path ran out short of the target: the last stretch in a straight line.
		cmd.yaw = lerp_angle(yaw, atan2(-flat.x, -flat.y), 0.3)
		cmd.my = 1.0


func _equip_best(cmd: Dictionary, dist: float = 20.0) -> void:
	## The gun for the range among those with rounds for them; holds a choice for a moment so a bot does not keep
	## swapping (each draw takes time).
	var best := -1
	var bs := -INF
	for s in [1, 2, 3]:
		var w = ch.wpn.slots[s]
		if w == null:
			continue
		var d := Defs.weapon(str(w.id))
		var rounds = int(w.mag) + (1 if w.chamber else 0) + ch.inv.count(Defs.ammo_item(str(w.id)))
		var v := float(d.get("value", 1.0)) if rounds > 0 else -10.0
		var cls := str(d.get("class", ""))
		if dist < 12.0 and cls in ["shotgun", "smg"]:
			v += 2.5
		elif dist > 45.0 and cls in ["rifle", "marksman", "precision"]:
			v += 2.0
		elif dist > 45.0 and cls in ["shotgun", "handgun"]:
			v -= 3.0
		if s == ch.wpn.cur:
			v += 0.8
		if v > bs:
			bs = v
			best = s
	if best >= 0:
		cmd.slot = best


func _fight(cmd: Dictionary, dt: float) -> void:
	var o = world.characters.get(target_eid)
	if o == null:
		target_eid = -1
		return
	_equip_best(cmd, o.global_position.distance_to(ch.global_position))
	var aim_pt: Vector3 = o.global_position + Vector3.UP * (1.25 if o.mode != Motor.DOWNED else 0.25)
	var to = aim_pt - ch.eye_position()
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	aim_err = aim_err.move_toward(Vector2.ZERO, dt * 4.0)
	cmd.yaw = lerp_angle(yaw, want_yaw + deg_to_rad(aim_err.x), minf(dt * 8.0, 1.0))
	cmd.pitch = lerpf(pitch, want_pitch + deg_to_rad(aim_err.y), minf(dt * 8.0, 1.0))
	var d = to.length()
	reaction -= dt
	if ch.wpn.current_id() == "":
		# Unarmed: get away.
		cmd.yaw = want_yaw + PI
		cmd.my = 1.0
		cmd.btn |= Motor.B_SPRINT
		return
	if d < 25.0 or ch.wpn.zoom() > 1.5:
		cmd.btn |= Motor.B_AIM
	if ch.wpn.loaded() == 0:
		cmd.btn |= Motor.B_RELOAD
		if ch.wpn.state == 0:
			say("reloading")
	elif reaction <= 0.0 and absf(wrapf(want_yaw - yaw, -PI, PI)) < 0.12:
		_fire_hold -= dt
		if _fire_hold < 0.0:
			_fire_hold = rng.randf_range(0.2, 0.5)
		if _fire_hold > 0.1 or ch.wpn.fire_mode() != "auto":
			cmd.btn |= Motor.B_FIRE if rng.randf() < 0.85 else 0
	# Footwork by temperament: rushers close in, snipers and campers keep still (crouched at range), the rest strafe.
	match role:
		"rusher":
			cmd.mx = sin(Time.get_ticks_msec() * 0.003 + ch.eid) * 1.0
			cmd.my = 1.0 if d > 7.0 else 0.0
		"sniper":
			cmd.mx = 0.0
			cmd.my = 0.0
			if d > 30.0:
				cmd.btn |= Motor.B_CROUCH
		"looter":
			cmd.mx = sin(Time.get_ticks_msec() * 0.0015 + ch.eid) * 0.5
			if state == "fight" and _hold_t > 0.0:
				cmd.btn |= Motor.B_CROUCH if d > 12.0 else 0
		_:
			cmd.mx = sin(Time.get_ticks_msec() * 0.002 + ch.eid) * 0.8
			if d > 30.0:
				cmd.my = 0.6
	# Hurt and empty: back away while reloading (not the fearless).
	if role != "rusher" and (ch.wpn.state != 0 or ch.health.health < 35.0) and d < 25.0:
		cmd.my = -0.7


func _lights(cmd: Dictionary) -> void:
	## Bots use their light indoors when nobody is around, and turn it off when fighting.
	var indoor: bool = world.map.acoustics.zone_at(ch.global_position) != 0
	var want = indoor and state in ["loot", "roam"] and ch.light.charge() > 0.1
	if want != ch.light.on and rng.randf() < 0.05:
		cmd.btn |= Motor.B_LIGHT  # a tap toggles (pressed this tick, released next)


# ------------------------------------------------------------------ r10: roles

func _exiting() -> bool:
	return state == "loot" and plan_i < plan.size() and bool(plan[-1].get("exit", false))


func _leave_house() -> bool:
	## Indoors with a door to leave by: walk out through it (a short plan) before anything that needs the walk grid.
	if _house_exit.size() != 2 or _exiting():
		return false
	if world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5) == 0:
		_house_exit = []
		return false
	plan = [{"p": _house_exit[0], "nav": false}, {"p": _house_exit[1], "nav": false, "exit": true}]
	_house_exit = []
	plan_i = 0
	_step_t = 0.0
	_best_d = INF
	_no_progress = 0.0
	state = "loot"
	return true


func _leads() -> bool:
	## Talks for its group: alone, or the leader of its squad.
	var s: Dictionary = BotTeam.squads.get(squad_id, {})
	return s.is_empty() or int(s.leader) == ch.eid


func _leader():
	## The character this bot follows (its squad leader, or the human it joined), or null.
	if squad_id < 0:
		return null
	var s: Dictionary = BotTeam.squads.get(squad_id, {})
	if s.is_empty():
		squad_id = -1
		return null
	var le := int(s.leader)
	if le == ch.eid or le < 0:
		return null
	var c = world.characters.get(le)
	if c == null or c.mode in [Motor.DEAD, Motor.SPECTATE]:
		BotTeam.leave_squad(ch.eid)
		squad_id = -1
		return null
	if c.mode in [Motor.PLANE, Motor.FREEFALL, Motor.CHUTE]:
		return null
	return c


func _social(dt: float) -> void:
	_social_t -= dt
	if _social_t > 0.0:
		return
	_social_t = 1.0
	BotTeam.ensure_spots(nav)
	if ch.mode != Motor.GROUND or (dm and _dm_hold > 0.0):
		return
	BotTeam.form_squads(ch.team, rng)
	# Join a human teammate close by (once per match, at most two bots each).
	if not _decided_human and squad_id < 0:
		for o in world.characters.values():
			if o.team != ch.team or Net.is_bot(o.pid) or o.mode != Motor.GROUND:
				continue
			if o.global_position.distance_to(ch.global_position) > 30.0:
				continue
			_decided_human = true
			var want: float = {"looter": 0.25, "rusher": 0.4, "sniper": 0.1, "stalker": 0.45}.get(role, 0.3)
			if BotTeam.human_followers(o.eid) < 2 and rng.randf() < want:
				BotTeam.follow_human(ch.eid, o.eid)
				say("go_with", true)
			break
	# Time spent unhurt in a held spot: it is safe.
	if state in ["camp", "overwatch"]:
		_safe_t += 1.0
		if _safe_t >= 20.0 and Time.get_ticks_msec() / 1000.0 - _hit_t > 20.0:
			_safe_t = 0.0
			BotTeam.mark(ch.global_position, "safe", 0.5)


func _role_objective() -> void:
	_obj_t -= 0.25
	match role:
		"looter":
			if state == "camp" and _hold_t > 0.0:
				return
			if state == "camp":
				# Done holding: out of the door and on to the next house.
				state = "roam"
			if state == "roam" and goal != Vector3.INF and _obj_t > 0.0:
				return
			_pick_loot_goal()
			_obj_t = 8.0
		"sniper":
			if state == "overwatch" and _hold_t > 0.0:
				return
			if state == "hunt" and goal != Vector3.INF and _obj_t > 0.0:
				return
			if state == "roam" and _obj != Vector3.INF and goal == Vector3.INF and ch.global_position.distance_to(_obj) < 4.0:
				_start_hold("overwatch", rng.randf_range(40.0, 80.0) * (0.5 + patience))
				return
			if state == "roam" and goal != Vector3.INF and _obj_t > 0.0:
				return
			var sp := _pick_spot("snipe")
			if sp < 0:
				sp = _pick_spot("cover")
			if sp >= 0:
				var s: Dictionary = BotTeam.spots[sp]
				_obj = s.p
				_look_at = (s.p as Vector3) + Vector3((s.dir as Vector2).x, 0, (s.dir as Vector2).y) * 40.0
				_set_goal(_obj)
				state = "roam"
				_obj_t = 25.0
				if _leads() and Time.get_ticks_msec() - _chat_t > 60000:
					_chat_t = Time.get_ticks_msec()
					say("sniping")
			else:
				_hunt_target(false)
		"rusher":
			if state == "hunt" and goal != Vector3.INF and _obj_t > 0.0:
				return
			_hunt_target(true)
		"stalker":
			if state == "hunt" and goal != Vector3.INF and _obj_t > 0.0:
				return
			_hunt_target(false)


func _intel() -> Vector3:
	var it: Dictionary = team_intel.get("%d:%d" % [Game.match_seed, ch.team], {})
	if not it.is_empty() and Time.get_ticks_msec() - int(it.t) < 30000:
		return it.p
	return Vector3.INF


func _hunt_target(open: bool) -> void:
	## Somewhere enemies are likely: the freshest sighting, else the enemy's side (Deathmatch, early), else toward the
	## middle of the next circle, by a way of this bot's own (rushers straight across the open, stalkers by the cover
	## waypoint closest to the line, off to one side).
	var tgt := _intel()
	var zone: Dictionary = world.match_info.get("zone", {})
	var circ: Array = world.zone_circle(float(Net.tick))
	var c1: Vector2 = zone.get("c1", circ[0])
	if tgt == Vector3.INF:
		if dm and world.match_server and not world.match_server.spawn_info.is_empty() and int(zone.get("i", 0)) <= 1:
			var other: Dictionary = world.match_server.spawn_info.get(1 - ch.team, {})
			if not other.is_empty():
				tgt = (other.anchor as Vector3).lerp(Vector3(c1.x, 0, c1.y), rng.randf_range(0.2, 0.6))
		if tgt == Vector3.INF:
			# Somewhere in the circle this bot has not been: its own random bearing.
			var r := float(zone.get("r1", circ[1])) * 0.6
			var a := rng.randf() * TAU
			tgt = Vector3(c1.x + cos(a) * r * rng.randf(), 0, c1.y + sin(a) * r * rng.randf())
	tgt += _dm_offset
	_obj = _inside_zone(tgt)
	var via := _obj
	if not open:
		# A cover waypoint part way there, to one side of the straight line (a flank).
		var me = ch.global_position
		var mid = me.lerp(_obj, 0.55)
		var side := Vector3(-(_obj - me).z, 0, (_obj - me).x).normalized() * rng.randf_range(-14.0, 14.0)
		var best := -1
		var bs := -INF
		for i in BotTeam.spots_near(mid + side, 30.0):
			var s: Dictionary = BotTeam.spots[i]
			if str(s.kind) == "open":
				continue
			var l: Array = BotTeam.lesson(s.p)
			var sc: float = float(s.cover) - (s.p as Vector3).distance_to(mid + side) * 0.08 - float(l[3]) * 0.8 + float(l[2]) * 0.3
			if sc > bs:
				bs = sc
				best = i
		if best >= 0 and me.distance_to(_obj) > 25.0:
			via = BotTeam.spots[best].p
	_set_goal(via)
	state = "hunt"
	_obj_t = rng.randf_range(8.0, 14.0)
	if _leads() and Time.get_ticks_msec() - _chat_t > 60000 and rng.randf() < 0.5:
		_chat_t = Time.get_ticks_msec()
		say("hunting" if open else "sneaking")


func _pick_spot(kind: String) -> int:
	## The best waypoint of a kind within reach, inside the circle, scored by what the team has learned (good and
	## sniping spots up, places where bots died down) and by distance.
	if BotTeam.spots.is_empty():
		return -1
	var me = ch.global_position
	var best := -1
	var bs := -INF
	for i in BotTeam.spots_near(me, 140.0):
		var s: Dictionary = BotTeam.spots[i]
		if str(s.kind) != kind:
			continue
		var p: Vector3 = s.p
		if _inside_zone(p).distance_to(p) > 1.0:
			continue
		var l: Array = BotTeam.lesson(p)
		var sc = float(s.sight) * 0.05 + float(s.cover) * 0.6 + float(l[0]) * 1.5 + float(l[1]) * (3.0 if role == "sniper" else 0.5) \
			+ float(l[2]) * 0.4 - float(l[3]) * 1.2 - me.distance_to(p) * 0.03 + rng.randf_range(0.0, 2.5)
		if sc > bs:
			bs = sc
			best = i
	return best


func _start_hold(kind: String, secs: float) -> void:
	state = kind
	_hold_t = secs
	goal = Vector3.INF
	var fv: Vector3 = (_look_at - ch.global_position) if _look_at != Vector3.INF else -Basis(Vector3.UP, yaw).z
	_hold_base_yaw = atan2(-fv.x, -fv.z)
	_safe_t = 0.0


func _hold_step(cmd: Dictionary, dt: float) -> void:
	## Camping a room or watching from a sniping spot: still, scanning a sector, scope up now and then.
	_hold_t -= dt
	cmd.my = 0.0
	cmd.mx = 0.0
	if _look_at != Vector3.INF:
		var fv = _look_at - ch.eye_position()
		_hold_base_yaw = lerp_angle(_hold_base_yaw, atan2(-fv.x, -fv.z), 0.08)
	var sweep := (0.35 if state == "overwatch" else 0.6) * sin(Time.get_ticks_msec() * 0.00045 + ch.eid)
	cmd.yaw = lerp_angle(yaw, _hold_base_yaw + sweep, 0.06)
	cmd.pitch = lerpf(pitch, -0.03, 0.05)
	if state == "overwatch":
		if ch.wpn.zoom() > 1.4 or fmod(Time.get_ticks_msec() / 1000.0 + ch.eid, 9.0) < 4.0:
			cmd.btn |= Motor.B_AIM
		cmd.btn |= Motor.B_CROUCH
	elif fmod(Time.get_ticks_msec() / 1000.0 + ch.eid * 0.37, 14.0) < 6.0:
		cmd.btn |= Motor.B_CROUCH
	# Shot at while holding: a sniper moves on, a camper turns to face it.
	if Time.get_ticks_msec() / 1000.0 - _hit_t < 1.0 and state == "overwatch":
		_hold_t = 0.0
		_obj = Vector3.INF
	if _hold_t <= 0.0:
		_look_at = Vector3.INF
		if state == "camp":
			# Walk back out of the house.
			state = "roam"
			goal = Vector3.INF
		else:
			state = "roam"
			_obj = Vector3.INF
			_obj_t = 0.0


func _follow_step(cmd: Dictionary, dt: float) -> void:
	## Behind and to one side of the leader, matching its pace; when it stops, cover a different angle.
	var le = _leader()
	if le == null:
		state = "roam"
		return
	var lp: Vector3 = le.global_position
	var lb := Basis(Vector3.UP, le.yaw)
	var spot := lp + lb * _follow_off
	var d = ch.global_position.distance_to(lp)
	if d > 80.0:
		_follow_far_t += dt
		if _follow_far_t > 20.0:
			say("lost_you", true)
			BotTeam.leave_squad(ch.eid)
			squad_id = -1
			state = "roam"
			return
	else:
		_follow_far_t = 0.0
	_follow_goal_t -= dt
	if ch.global_position.distance_to(spot) > 3.0:
		if _follow_goal_t <= 0.0 or goal == Vector3.INF or (goal as Vector3).distance_to(spot) > 4.0:
			_follow_goal_t = 2.0
			_set_goal(spot)
		_move(cmd, dt, false)
		if d > 12.0 or (le.flags & Character.F_SPRINT) != 0:
			cmd.btn |= Motor.B_SPRINT
		elif (le.flags & Character.F_WALK) != 0:
			cmd.btn |= Motor.B_WALK
		if (le.flags & Character.F_CROUCH) != 0:
			cmd.btn |= Motor.B_CROUCH
	else:
		goal = Vector3.INF
		var face = le.yaw + (0.9 if _follow_off.x > 0.0 else -0.9)
		if _look_at != Vector3.INF:
			var fv = _look_at - ch.eye_position()
			face = atan2(-fv.x, -fv.z)
		cmd.yaw = lerp_angle(yaw, face, 0.08)
		cmd.pitch = lerpf(pitch, 0.0, 0.1)
		if (le.flags & Character.F_CROUCH) != 0:
			cmd.btn |= Motor.B_CROUCH


func _haze() -> Dictionary:
	## {go, urgent, p}: whether to leave for the next circle now. Knows when the haze starts closing and how fast its
	## edge moves; leaves when the run (at a sprint, a third longer for the streets) plus a margin would not beat it.
	var zone: Dictionary = world.match_info.get("zone", {})
	var circ: Array = world.zone_circle(float(Net.tick))
	var p2 := Vector2(ch.global_position.x, ch.global_position.z)
	var c_now: Vector2 = circ[0]
	var r_now := float(circ[1])
	var inside_now := p2.distance_to(c_now) < r_now * 0.97
	var known := not zone.is_empty() and int(zone.get("i", -1)) >= 0
	var c1: Vector2 = zone.get("c1", c_now) if known else c_now
	var r1 := float(zone.get("r1", r_now)) if known else r_now
	var to_safe := maxf(p2.distance_to(c1) - r1 * 0.8, 0.0)
	var target := c1 + (p2 - c1).limit_length(r1 * 0.55) + Vector2(_dm_offset.x, _dm_offset.z)
	var out := {"go": false, "urgent": false, "p": Vector3(target.x, ch.global_position.y, target.y)}
	if not inside_now:
		out.go = true
		out.urgent = true
		return out
	if to_safe <= 0.0:
		return out
	# When the closing circle (its centre moving while its radius shrinks) first leaves this spot behind.
	var now := float(Net.tick)
	var t_left := 9999.0
	var st := str(zone.get("state", ""))
	if st == "wait" or st == "shrink":
		var t_start: float = maxf((float(zone.get("t1", now)) - now) / Defs.TICK_RATE, 0.0) if st == "wait" else 0.0
		var rem: float = maxf(float(zone.get("shrink_s", 60.0)), 1.0) if st == "wait" else maxf((float(zone.get("t1", now)) - now) / Defs.TICK_RATE, 0.0)
		for k in range(1, 21):
			var f := k / 20.0
			if p2.distance_to(c_now.lerp(c1, f)) > lerpf(r_now, r1, f):
				t_left = t_start + rem * f
				break
	# Streets, bridges and walls make the run longer than the straight line; patience costs a margin, not a life.
	var need := to_safe / 5.2 * 1.7
	var margin := lerpf(45.0, 10.0, clampf(patience, 0.0, 1.0)) * 0.5 + 15.0
	if world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5) != 0:
		margin += 20.0   # out of the house first, by the door it came in
	if need + margin > t_left:
		out.go = true
	return out


func _ping_step() -> bool:
	## Acting on a teammate's ping (on_team_ping chose how): true while that is what this bot is doing.
	var age := Time.get_ticks_msec() / 1000.0 - float(_ping.t)
	var p: Vector3 = _ping.p
	if age > 30.0:
		_ping = {}
		return false
	match str(_ping.how):
		"go", "flank":
			if ch.global_position.distance_to(p) < 6.0:
				_ping = {}
				_look_at = Vector3.INF
				return false
			if state != "hunt" or _obj.distance_to(p) > 1.0 or goal == Vector3.INF:
				_obj = p
				var via := p
				if str(_ping.how) == "flank" and ch.global_position.distance_to(p) > 25.0:
					var me = ch.global_position
					via = me.lerp(p, 0.6) + Vector3(-(p - me).z, 0, (p - me).x).normalized() * rng.randf_range(10.0, 16.0) * (1.0 if ch.eid % 2 == 0 else -1.0)
				_set_goal(via)
				state = "hunt"
				_obj_t = 12.0
			return true
		"watch":
			_look_at = p
			if state == "overwatch":
				return true
			if state == "roam" and goal != Vector3.INF:
				return true
			# A spot with cover and a view of the ping; else right here.
			var best := -1
			var bs := -INF
			for i in BotTeam.spots_near(p, 110.0):
				var s: Dictionary = BotTeam.spots[i]
				var dd := (s.p as Vector3).distance_to(p)
				if dd < 25.0 or str(s.kind) == "open":
					continue
				var sc: float = float(s.cover) + float(s.sight) * 0.02 - (s.p as Vector3).distance_to(ch.global_position) * 0.04
				if sc > bs:
					bs = sc
					best = i
			if best >= 0 and (BotTeam.spots[best].p as Vector3).distance_to(ch.global_position) > 5.0:
				_obj = BotTeam.spots[best].p
				_set_goal(_obj)
				state = "roam"
				_obj_t = 30.0
			else:
				_start_hold("overwatch", 30.0)
			_ping.how = "watching"
			return true
		"watching":
			if state == "roam" and goal == Vector3.INF:
				_start_hold("overwatch", 30.0)
			return state in ["roam", "overwatch"]
		"look":
			_look_at = p
			if state in ["camp", "overwatch"]:
				return false
			_start_hold("camp", 6.0)
			_ping = {}
			return true
	return false


# ------------------------------------------------------------------ r10: events

func on_team_ping(pos: Vector3, from) -> void:
	## A teammate pinged a spot. Each bot answers by temperament; the human it follows is always answered.
	if ch.mode != Motor.GROUND:
		return
	BotTeam.stats.pings += 1
	var follows_pinger := squad_id >= 0 and int(BotTeam.squads.get(squad_id, {}).get("leader", -1)) == int(from.eid)
	var d = ch.global_position.distance_to(pos)
	var how := ""
	if follows_pinger:
		how = "go" if role != "sniper" else "watch"
	else:
		match role:
			"rusher":
				how = "go" if rng.randf() < 0.85 else ""
			"stalker":
				how = "flank" if rng.randf() < 0.75 else ""
			"sniper":
				how = "watch" if rng.randf() < 0.75 else ""
			"looter":
				how = "look" if (state == "camp" or d > 60.0) else ("go" if rng.randf() < 0.45 else "look")
	if how == "":
		return
	_ping = {"p": pos, "t": Time.get_ticks_msec() / 1000.0, "how": how}
	if how in ["go", "flank"]:
		say("copy")
	elif how == "watch":
		say("watching")


func on_laser(holder, origin: Vector3, dot: Vector3, dist: float) -> void:
	## Saw a laser beam or its dot. An enemy's: maybe follow it back to whoever holds it. A teammate's: look there,
	## and go if following that player.
	if _laser_cd > 0.0 or ch.mode != Motor.GROUND:
		return
	_laser_cd = 2.5
	if holder.team != ch.team:
		var chance: float = {"stalker": 0.55, "rusher": 0.45, "sniper": 0.35, "looter": 0.2}.get(role, 0.3)
		if ch.eye_position().distance_to(dot) < 3.0:
			chance += 0.25   # the dot is on us
		if rng.randf() < chance:
			investigate = origin + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
			BotTeam.stats.laser_follow += 1
			say("laser", true)
			if state in ["camp", "overwatch"]:
				_look_at = origin
		else:
			_look_at = dot
		return
	var follows := squad_id >= 0 and int(BotTeam.squads.get(squad_id, {}).get("leader", -1)) == int(holder.eid)
	if follows and ch.global_position.distance_to(dot) > 5.0:
		_ping = {"p": dot, "t": Time.get_ticks_msec() / 1000.0, "how": "go"}
	else:
		_look_at = dot


func on_damaged(attacker: int) -> void:
	_hit_t = Time.get_ticks_msec() / 1000.0
	var a = world.characters.get(attacker)
	if a == null or a == ch:
		return
	if target_eid < 0:
		# Shot by someone unseen: toward where it came from, roughly.
		investigate = (a.global_position as Vector3) + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
		_look_at = a.global_position
		reaction = minf(reaction, 0.3)
	say("taking_fire", true)


func on_scored(victim, dist: float) -> void:
	if rng.randf() < 0.6:
		say("kill")
	if dist > 45.0 and rng.randf() < 0.5:
		say("good_spot")


func say(line: String, priority: bool = false) -> void:
	## A callout on the team radio (rate-limited per bot and per team so the radio does not turn into a chorus).
	if not lines.has(line) or ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
		return
	var now := Time.get_ticks_msec()
	if now - _say_t < (2500 if priority else 9000):
		return
	if not BotTeam.can_talk(ch.team, priority):
		return
	_say_t = now
	var k := rng.randi_range(0, (lines[line] as Array).size() - 1)
	BotTeam.stats.lines += 1
	world.server_bot_radio(ch, line, voice, k)
