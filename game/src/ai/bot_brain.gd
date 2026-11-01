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
##
## (r21) Moving through the map: every goal is put on the walk first (a goal off it, in a wall or a sealed pocket,
## becomes the nearest waypoint), a path that ends short of its goal is the end of the walk (no more pushing straight at
## a goal behind a wall), and whiskers either side of the way the bot walks steer it off walls, pillars and corners.
## Holding a spot or standing by its leader it faces open floor, never a wall. In Deathmatch the looters, with no houses
## to search, become ambushers: they take a hiding spot (bot_nav.gd), popular ones first, and watch its approach.
##
## (r22) A bot remembers its holds and does not take the same spot, or one within 20 m of its last, again for three
## minutes (the spot it stood on used to win every pick: it camped there for good). Deathmatch endgame (a side down to two
## standing, or the team has seen nobody for a while): holds are cut short, one now and then at most, and in between the
## bots sweep the map with their team, the cells nobody has looked at for longest first (bot_team.gd); a long quiet gives
## the team a rough idea of the nearest enemy. Bot skill (rules.json bot_skill: easy, normal, hard, pro) sets reaction,
## aim, vision and hold times; pro bots also fight by their gun and the moment (the pro tactics).
##
## (r22) What to do is decided by the bot's mind (bot_mind.gd), built on the LimboAI architecture (src/ai/limbo): a body
## machine every tick (airborne, downed, out of the water, playing), a mind machine four times a second (combat,
## recover, evacuate, directed, ready, objective; one ordered table of guards picks the mode, and each mode is a
## behaviour tree of decisions), and a motor machine every tick running the activity the state label names (move,
## hold, fetch, order, follow, heal, and fight: the combat tree of aim, trigger and footwork). This file keeps the senses
## and the skills those trees call: perception, the walk and paths, doors, unsticking, the house search, holds, aim and
## the trigger. `state` is still the activity label the logs, tests and the motor read.
const DayCycle := preload("res://src/world/day_cycle.gd")

const NavGrid := preload("res://src/ai/nav_grid.gd")
const NavLevels := preload("res://src/ai/nav_levels.gd")
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
# r23: the waypoint graph (waypoints.gd). A path from it is a list of nodes; the bot walks edge to edge.
var path_wp := PackedInt32Array() # the node of each path point (-1: a grid point or the goal)
var _wp_prev := -1                # the node last reached: the edge walked now starts there (-1: from where the bot set off)
var _seg_from := Vector3.INF      # where the stretch walked now starts
var _wp_tail := {}                # the graph's part of a route waiting for the grid's way onto the graph
var _wp_head := {}                # the graph's part of a route waiting for the grid's way from its end to a door
var _wp_route := false            # the path in hand came from the graph
var _wp_check_t := 0.0
var _wp_ok_next := false
var _off_line_t := 0.0
var _wpdoor_t := 0.0
var _ended_short := false         # the last walk ended at the nearest point the roads reach (the goal out of plain sight)
static var wp_stats := {"routes": 0, "leads": 0, "grid": 0, "off_line": 0, "stuck_edges": 0, "door_waits": 0, "locked": 0}
## Per-map lookups shared by every bot: building id -> outer doors / containers.
static var _index_layout = null
static var doors_by_bid := {}
static var conts_by_bid := {}
static var bgrid := {}   # Vector2i(40 m cell) -> [building]
static var house_nodes := {}   # r12: bid -> [{c, n, door}]: the doorways of a building (room to room, and out)
## Team landing spots for the current match: "seed:team" -> Vector3.
static var team_targets := {}
## r7 Deathmatch: bots start armed on the ground, so they skip the early looting. Each team advances on the other
## side in a loose group, shares sightings (a teammate's callout: "seed:team" -> {p: Vector3, t: msec}), keeps
## inside the haze line, and loots only when it helps (low on rounds, or a clearly better gun close by). (r22) The
## callout is the team's blackboard "intel" (BotTeam.board).
var dm := false
var _dm_offset := Vector3.ZERO     # this bot's place in the loose group
var _dm_goal_t := 0.0
var _dm_obj := Vector3.INF
var _dm_hold := 0.0               # the first seconds of a round: everyone gets ready at the spawn
# --- r10: roles, squads, radio, waypoints
const BotTeam := preload("res://src/ai/bot_team.gd")
const BotNav := preload("res://src/ai/bot_nav.gd")
const Waypoints := preload("res://src/ai/waypoints.gd")
const ROLES := ["looter", "rusher", "sniper", "stalker"]
static var lines := {}            # data/bot_radio.json: line -> phrasings
static var recorded := {}         # r13: data/bot_radio.json "recorded": line -> {name, n}: the user's recordings (vox_<name>_<k>)
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
var _house_exit_door := -1        # that door (opened on the way out if it has swung shut)
var _house_way: Array = []        # r12: [{p, door}] through the rooms to it, when the walk there is not straight
var _house_exit_bid := -1         # r12: the building it belongs to
var _exit_tried := {}             # r12: door id -> match time this bot last set off for it on its way out
const EXIT_IN := 1.6              # r12: the way out starts this far inside its door (clear of a door swinging in)
var _spot_i := -1                 # r21: the waypoint this bot is heading for or holding (claimed)
var _hold_len := 0.0              # r21: how long the current hold was meant to last (for the spot's record)
var _feel_t := 0.0                # r21: whiskers
var _feel_mx := 0.0
var _slot := Vector3.INF          # r21: the place beside the leader this bot keeps
var _slot_t := 0.0
var _idle_yaw := INF              # r21: where to look while standing by the leader
var _idle_t := 0.0
var _sweep_amp := 1.0             # r21: how far a holding bot looks round (shrinks while that swings into a wall)
var _sweep_t := 0.0
var _face_t := 0.0                # r21: standing with nowhere to go: turned away from a wall in front
var _face_yaw := INF
# --- r22: bot skill (rules.json bot_skill; the defaults are normal), hold memory, the endgame, measurement
const WeaponState := preload("res://src/weapons/weapon_state.gd")
const HOLD_MEMORY_S := 180.0      # a spot held this recently is not taken again
const HOLD_AWAY_M := 20.0         # nor one this close to the last hold
var skill := "normal"
var _sk_react := Vector2(0.35, 0.8)
var _sk_err := Vector2(6.0, 4.0)
var _sk_settle := 4.0
var _sk_lerp := 8.0
var _sk_wobble := 0.0
var _sk_gate := 0.12
var _sk_fire := 0.85
var _sk_burst := Vector2(0.2, 0.5)
var _sk_vision := 1.0
var _sk_behind := 0.2
var _sk_hurt := 0.3
var _sk_hold := 1.0
var _sk_end_alive := 2
var _sk_end_contact := 45.0
var _sk_end_hint := 60.0
var _sk_end_camp := 12.0
var _sk_end_watch := 20.0
var _sk_end_gap := 60.0
var _sk_head := 0.0
var _sk_tactics := false
var _holds: Array = []            # recent holds: [spot index, position, match second last held]
var _last_hold_t := -1000.0       # seconds (Time) the last hold began
var _end := false                 # Deathmatch endgame pressure on this bot's team
var _sweeping := false            # on a sweep leg (a waypoint in a stale cell)
var _sweep_log_t := -100.0
var _preaim_t := 0.0              # pro: the target just broke line of sight
var _tac_t := 0.0
var _push := false                # pro: an opening to push
var _rush := false                # pro: out of rounds (or a handgun is all that is left): close in
var _shots_seen := -1
var _dmg_seen := -1.0
var _acq_t := -1.0                # seconds (Time) the current target was first seen (for reaction_avg)
# --- r22: the decision layer (bot_mind.gd) and what its leaves share this tick
const BotMind := preload("res://src/ai/bot_mind.gd")
var mind = null                   # BotMind: the state machine and trees (made on the first think)
var _cmd: Dictionary = {}         # the command being built this tick
var _dt := 0.0
var _tick := 0
var _f_o = null                   # fight: the target, its range and the yaw that is on it (set by _fight_aim)
var _f_d := 0.0
var _f_want_yaw := 0.0
var _f_side := 0.0                # pro: which way it strafes, and the class of the gun in hand (set by _pro_tick)
var _f_cls := ""


func _init(w, c) -> void:
	world = w
	ch = c
	rng.seed = hash(c.eid * 7919 + Game.match_seed)
	var fresh_nav: bool = nav == null or nav.layout != world.map.layout
	if fresh_nav:
		# (r15) A storeyed map (Malasugue Mall) has a walk grid per level joined by escalators and stairs.
		nav = NavLevels.new(world.map.layout) if world.map.layout.get("nav_open") != null else NavGrid.new(world.map.layout)
		BotNav.prepare(world, nav)   # r21: the walk checked against the real collision; waypoints and hiding spots
		Waypoints.prepare(world, nav)   # r23: the waypoint graph bots walk (waypoints.gd)
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
				recorded = d.get("recorded", {})
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
	_read_skill()
	BotTeam.team_round(c.team)
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


func _read_skill() -> void:
	## r22: the lobby's Bot skill (--bot_skill=<skill> on a server overrides it), its numbers read once from rules.json
	## bot_skill. Anything unknown plays normal; a number missing keeps normal's.
	skill = str(Game.arg("bot_skill")) if Game.arg("bot_skill") != null else str(Net.config.get("bot_skill", "normal"))
	if not skill in ["easy", "normal", "hard", "pro"]:
		skill = "normal"
	var k = Defs.rule("bot_skill." + skill, {})
	if typeof(k) != TYPE_DICTIONARY:
		return
	_sk_react = _v2(k.get("reaction"), _sk_react)
	_sk_err = _v2(k.get("aim_err"), _sk_err)
	_sk_burst = _v2(k.get("burst"), _sk_burst)
	_sk_settle = float(k.get("settle", _sk_settle))
	_sk_lerp = float(k.get("aim_lerp", _sk_lerp))
	_sk_wobble = float(k.get("wobble", _sk_wobble))
	_sk_gate = float(k.get("fire_gate", _sk_gate))
	_sk_fire = float(k.get("fire_chance", _sk_fire))
	_sk_vision = float(k.get("vision", _sk_vision))
	_sk_behind = float(k.get("behind_dot", _sk_behind))
	_sk_hurt = float(k.get("hurt_react", _sk_hurt))
	_sk_hold = float(k.get("hold", _sk_hold))
	_sk_end_alive = int(k.get("end_alive", _sk_end_alive))
	_sk_end_contact = float(k.get("end_contact_s", _sk_end_contact))
	_sk_end_hint = float(k.get("end_hint_s", _sk_end_hint))
	_sk_end_camp = float(k.get("end_camp_s", _sk_end_camp))
	_sk_end_watch = float(k.get("end_watch_s", _sk_end_watch))
	_sk_end_gap = float(k.get("end_hold_gap_s", _sk_end_gap))
	_sk_head = float(k.get("head_m", _sk_head))
	_sk_tactics = bool(k.get("tactics", _sk_tactics))


static func _v2(a, d: Vector2) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) if a is Array and (a as Array).size() >= 2 else d


func _build_index() -> void:
	_index_layout = world.map.layout
	doors_by_bid = {}
	conts_by_bid = {}
	bgrid = {}
	house_nodes = {}
	exits_by_bid = {}
	for b in world.map.buildings:
		var o: Vector3 = (b.xf as Transform3D).origin
		var k := Vector2i(floori(o.x / BCELL), floori(o.z / BCELL))
		if not bgrid.has(k):
			bgrid[k] = []
		bgrid[k].append(b)
	team_targets = {}
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

var test_idle := false   # autotests: stand still, think nothing (a dummy for the field crush check)
var test_blind := false  # r21 autotests: sees and hears nobody (a route test walks without fighting)
var test_fire := false   # r22 autotests (firefight): with test_idle, holds the trigger toward test_yaw / test_pitch
var test_yaw := 0.0
var test_pitch := 0.0


func think(dt: float, tick: int) -> Dictionary:
	## One server tick: the decision layer (bot_mind.gd, a LimboAI-style state machine with behaviour trees) picks what
	## to do and drives the leaf skills below, which fill in the command (virtual buttons, view) returned here.
	seq += 1
	var cmd := {"seq": seq, "mx": 0.0, "my": 0.0, "yaw": yaw, "pitch": pitch, "btn": 0, "slot": ch.wpn.want, "view_tick": tick, "tick": tick}
	if test_idle:
		if test_fire and ch.mode == Motor.GROUND:
			cmd.yaw = test_yaw
			cmd.pitch = test_pitch
			if ch.wpn.loaded() == 0:
				cmd.btn = Motor.B_RELOAD
			elif ch.wpn.fire_mode() == "auto" or seq % 6 < 3:
				cmd.btn = Motor.B_FIRE
		return cmd
	if mind == null:
		mind = BotMind.new(self)
	_cmd = cmd
	_dt = dt
	_tick = tick
	mind.update(dt)
	return cmd


# ------------------------------------------------------------------ r22: per-tick upkeep the mind calls

func _crawl() -> void:
	## Downed: crawl, away from the field when it is on us.
	_cmd.my = 0.5
	var fd := Field.at(world, ch.global_position, float(_tick))
	if float(fd.pen) > -4.0 and fd.n != Vector3.ZERO:
		_cmd.yaw = atan2(-(fd.n as Vector3).x, -(fd.n as Vector3).z)
		_cmd.my = 1.0


func _wet_step(dt: float) -> bool:
	## Down in a walled canal (wading the estero is fine), on a ladder or hauling out over a canal wall: true when getting
	## out of the water is this tick's job (after a moment's wading; at once on a ladder). Out of it: the flags cleared.
	if (ch.water_depth() > 0.45 and _in_canal()) or (bool(ch.get_meta("ladder_ok", false)) and not ch.is_on_floor()) \
			or (_haul and (ch.ledge_t >= 0.0 or ch.vault_t >= 0.0)):
		if _wet_t == 0.0 and Game.arg("radiolog") != null and world.match_server:
			world.match_server.log_event("[canal] %s (%s) fell in at %s from %s, state %s goal %s path %d/%d, last move %s" % [ch.pname, role, str(ch.global_position.snapped(Vector3.ONE * 0.1)),
				str(_trail), state, str(goal.snapped(Vector3.ONE * 0.1)) if goal != Vector3.INF else "-", path_i, path.size(), str(path.slice(maxi(path_i - 1, 0), path_i + 2))])
		_wet_t += dt
		return _wet_t >= 1.5 or bool(ch.get_meta("ladder_ok", false))
	_wet_t = 0.0
	if ch.has_meta("ladder_ok"):
		ch.remove_meta("ladder_ok")
	if _haul:
		_haul = false
		if _field_t == 0.0:
			ch.remove_meta("climb_ok")
	return false


func _think_tick(dt: float) -> bool:
	## Timers every tick; true on a decision tick (every 0.25 s), after perception, the squad and the endgame are updated.
	_think_t -= dt
	_laser_cd = maxf(_laser_cd - dt, 0.0)
	_vault_cd = maxf(_vault_cd - dt, 0.0)
	if _think_t > 0.0:
		return false
	_think_t = 0.25
	_trail.append(ch.global_position.snapped(Vector3.ONE * 0.1))
	if _trail.size() > 6:
		_trail.pop_front()
	_perceive()
	_social(0.25)
	if dm:
		BotTeam.mark_seen(ch.team, ch.global_position)   # r22: the team's sweep map
		_endgame_eval()
	return true


func _finish(dt: float) -> void:
	## After the activity: the light, the field, edges, then the view is kept and the debug traces written.
	_lights(_cmd)
	_field_escape(_cmd, dt)
	_guard_edges(_cmd)
	yaw = float(_cmd.yaw)
	pitch = float(_cmd.pitch)
	BotTeam.note_state(state, dt)
	_trace(_cmd, dt)
	_history(_cmd, dt)


# r12 match log: the last half minute of what this bot did, one line a second (dumped when the field kills it).
var hist: Array = []
var _hist_t := 0.0


func _history(cmd: Dictionary, dt: float) -> void:
	if not world.match_server or not world.match_server._log_on:
		return
	_hist_t -= dt
	if _hist_t > 0.0:
		return
	_hist_t = 1.0
	var step: Dictionary = plan[plan_i] if plan_i < plan.size() else {}
	var kind := "nav" if step.get("nav", false) else ("search" if step.has("search") else ("door" if step.has("door") else ("exit" if step.get("exit", false) else "walk")))
	hist.append("%.0f %s %s step %d/%d %s path %d/%d stuck %.1f in %s exit %d field %.1f btn %d esc %.1f" % [world.match_server._t, state,
		str(ch.global_position.round()), plan_i, plan.size(), kind if not step.is_empty() else "-", path_i, path.size(), _stuck_t,
		str(world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5) != 0), _house_exit.size(),
		float(Field.at(world, ch.global_position, float(Net.tick)).pen), int(cmd.btn), _field_t])
	if hist.size() > 30:
		hist.pop_front()


# ------------------------------------------------------------------ r12: the forcefield

var _field_t := 0.0          # seconds the field has been on (or just behind) this bot
var _field_pick_t := 0.0
var _field_dir := Vector3.ZERO
var _field_clear := 9.0      # metres of room ahead along _field_dir


func _field_escape(cmd: Dictionary, dt: float) -> void:
	## The field is on this bot, or a few metres off and closing: get out of its way, whatever the state. It does not
	## hurt, but it crushes anyone it presses against a wall, so the way in has to be open: the most inward direction
	## with room ahead, at a sprint, jumping over (or climbing, with the hands on the top) what is in the way.
	var fi := Field.at(world, ch.global_position, float(Net.tick))
	var lead := 3.0 + float(fi.v) * 2.5
	if not Field.live(world.match_info.get("zone", {})) or float(fi.pen) < -lead or (not Field.test_only.is_empty() and not (ch.eid in Field.test_only)):
		if _field_t > 0.0:
			_field_t = 0.0
			ch.remove_meta("climb_ok")
		return
	if _field_t == 0.0:
		_field_pick_t = 0.0
	_field_t += dt
	ch.set_meta("climb_ok", true)
	# Indoors the most open way in is a room, not the way out: keep to the door (sprinting), or find one.
	if world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5) != 0:
		if not _exiting() and _find_exit():
			_leave_house()
		if _exiting():
			cmd.btn = (int(cmd.btn) | Motor.B_SPRINT) & ~(Motor.B_WALK | Motor.B_CROUCH | Motor.B_AIM | Motor.B_HEAL)
			return
	_field_pick_t -= dt
	var n: Vector3 = fi.n
	if n == Vector3.ZERO:
		return
	# Already on a path for the circle that heads in and is moving: keep to it (at a sprint).
	if state == "zone" and path_i < path.size() and _stuck_t < 0.5:
		var to_wp: Vector3 = path[path_i] - ch.global_position
		to_wp.y = 0.0
		# (Only when the way to the next waypoint is open: a path through a wall the walk grid does not know pressed the
		# bot into it until the field crushed it.)
		var reach := minf(to_wp.length(), 3.0)
		if to_wp.length() > 0.5 and to_wp.normalized().dot(n) > 0.25 and float(fi.pen) < -1.0 \
				and _clearance(to_wp.normalized(), reach) >= reach - 0.4:
			cmd.btn = (int(cmd.btn) | Motor.B_SPRINT) & ~(Motor.B_WALK | Motor.B_CROUCH | Motor.B_AIM | Motor.B_HEAL)
			return
	if _field_pick_t <= 0.0 or _field_clear < 0.9:
		_field_pick_t = 0.2
		var best := n
		var best_s := -INF
		var best_c := 0.0
		for deg in [0.0, 25.0, -25.0, 50.0, -50.0, 75.0, -75.0, 100.0, -100.0]:
			var d := n.rotated(Vector3.UP, deg_to_rad(deg))
			var c := _clearance(d, 4.5)
			var s := c / 4.5 * (0.3 + 0.7 * maxf(cos(deg_to_rad(deg)), 0.0))
			if _field_dir != Vector3.ZERO and d.dot(_field_dir) > 0.95:
				s += 0.08   # keep a way that is working
			if s > best_s:
				best_s = s
				best = d
				best_c = c
		_field_dir = best
		_field_clear = best_c
	else:
		_field_clear = _clearance(_field_dir, 4.5)
	cmd.yaw = atan2(-_field_dir.x, -_field_dir.z)
	cmd.mx = 0.0
	cmd.my = 1.0
	cmd.btn = (int(cmd.btn) | Motor.B_SPRINT) & ~(Motor.B_WALK | Motor.B_CROUCH | Motor.B_AIM | Motor.B_HEAL)
	# Something in the way: over it (a vault, a jump to grab the top) rather than be pressed into it.
	if (_field_clear < 1.1 or ch.field_pin > 0.02) and _vault_cd <= 0.0:
		_vault_cd = 0.7
		cmd.btn |= Motor.B_JUMP
	if _leads() and _haze_said != int(world.match_info.get("zone", {}).get("i", -1)) and float(fi.pen) > -1.0:
		_haze_said = int(world.match_info.get("zone", {}).get("i", -1))
		say("haze", true)


func _walk_line(q: Vector3) -> bool:
	## Nothing solid between this bot and q at knee and chest height.
	var p: Vector3 = ch.global_position
	return _walk_clear(p, Vector3(q.x, p.y, q.z))


func _walk_clear(a: Vector3, b: Vector3) -> bool:
	## A body (a capsule from step height to the head) can walk straight from a to b: furniture and low walls count.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.27
	cap.height = 1.3
	q.shape = cap
	q.transform = Transform3D(Basis(), a + Vector3.UP * (0.42 + 0.65))
	q.motion = b - a
	q.collision_mask = Defs.MOVE_MASK
	q.exclude = [ch.get_rid()]
	var r := space.cast_motion(q)
	return r.size() > 0 and float(r[0]) >= 1.0


static var exits_by_bid := {}   # r12: bid -> its outer doors and its open outer doorways (no leaf), as door records


func _exits_of(bid: int) -> Array:
	## The ways out of a building: its outer doors, and doorways with no leaf whose far side is outdoors (an open
	## shopfront, an arch). Open ones have id -1 (nothing to open on the way).
	if exits_by_bid.has(bid):
		return exits_by_bid[bid]
	var out: Array = (doors_by_bid.get(bid, []) as Array).duplicate()
	for dw in world.map.dyn.doorways:
		if int(dw.get("bid", -1)) != bid:
			continue
		var n: Vector3 = dw.n
		n.y = 0.0
		n = n.normalized()
		var c: Vector3 = dw.c
		var outdoors_n = world.map.acoustics.zone_at(c + n * 1.2 + Vector3.UP * 0.5) == 0
		var outdoors_b = world.map.acoustics.zone_at(c - n * 1.2 + Vector3.UP * 0.5) == 0
		if outdoors_n == outdoors_b:
			continue   # between two rooms (or both sides outdoors)
		var o := n if outdoors_n else -n
		var u: Vector3 = dw.u
		var w := float(dw.w)
		# As a door record: xf at one jamb with the opening along +x, so xf * (w/2, 0, 0) is the middle.
		out.append({"id": -1, "xf": Transform3D(Basis(u, Vector3.UP, u.cross(Vector3.UP)), c - u * w * 0.5), "w": w, "outward": o})
	exits_by_bid[bid] = out
	return out


func _house_doorways(bid: int) -> Array:
	if house_nodes.has(bid):
		return house_nodes[bid]
	var out := []
	var dyn = world.map.dyn
	var leaves := []
	for d in dyn.doors:
		if int(d.get("bid", -1)) == bid:
			leaves.append(d)
	for dw in dyn.doorways:
		if int(dw.get("bid", -1)) != bid:
			continue
		var n: Vector3 = dw.n
		n.y = 0.0
		var door := -1
		for d in leaves:
			if ((d.xf as Transform3D) * Vector3(float(d.w) * 0.5, 0.0, 0.0)).distance_to(dw.c) < 0.8:
				door = int(d.id)
				break
		out.append({"c": dw.c, "n": n.normalized(), "door": door})
	# Inner doors with no doorway record (a comfort room's door): the leaf itself, across its own face.
	for d in leaves:
		if bool(d.get("outer", false)):
			continue
		var dc: Vector3 = (d.xf as Transform3D) * Vector3(float(d.w) * 0.5, 0.0, 0.0)
		var known := false
		for o in out:
			if (o.c as Vector3).distance_to(dc) < 0.8:
				known = true
				break
		if not known:
			var dn: Vector3 = (d.xf as Transform3D).basis.z
			dn.y = 0.0
			out.append({"c": dc, "n": dn.normalized(), "door": int(d.id)})
	for d in doors_by_bid.get(bid, []):
		var n2: Vector3 = d.outward
		n2.y = 0.0
		out.append({"c": (d.xf as Transform3D) * Vector3(float(d.w) * 0.5, 0.0, 0.0), "n": n2.normalized(), "door": int(d.id)})
	house_nodes[bid] = out
	return out


func _house_route(bid: int, from: Vector3, to: Vector3) -> Array:
	## r12: waypoints [{p, door}] from a spot in building bid to another (the inside of its way out) through the
	## doorways between its rooms (the walk grid does not reach indoors): a shortest path over a point either side of
	## each doorway on this floor, linked where a straight walk is clear. [] when the straight walk is clear or there
	## is no route.
	if _walk_clear(from, to):
		return []
	var pts := [from, to]
	var door_of := [-1, -1]
	var mate := [-1, -1]
	for dw in _house_doorways(bid):
		var c: Vector3 = dw.c
		if absf(c.y - from.y) > 1.2 or Vector2(c.x - from.x, c.z - from.z).length() > 35.0:
			continue
		var n: Vector3 = dw.n
		pts.append(c + n * 0.6 + Vector3.UP * 0.05)
		pts.append(c - n * 0.6 + Vector3.UP * 0.05)
		door_of.append_array([int(dw.door), int(dw.door)])
		mate.append_array([pts.size() - 1, pts.size() - 2])
	var np := pts.size()
	var dist := []
	var prev := []
	var done := []
	dist.resize(np)
	prev.resize(np)
	done.resize(np)
	dist.fill(INF)
	prev.fill(-1)
	done.fill(false)
	dist[0] = 0.0
	while true:
		var u := -1
		var bu := INF
		for i in np:
			if not done[i] and float(dist[i]) < bu:
				bu = dist[i]
				u = i
		if u < 0 or u == 1:
			break
		done[u] = true
		for v in np:
			if done[v]:
				continue
			var w := (pts[u] as Vector3).distance_to(pts[v])
			if float(dist[u]) + w < float(dist[v]) and (int(mate[u]) == v or _walk_clear(pts[u], pts[v])):
				dist[v] = float(dist[u]) + w
				prev[v] = u
	if int(prev[1]) < 0:
		return []
	var route := []
	var k := int(prev[1])
	while k > 0:
		# The step through a doorway (to its far point, from its mate) opens its door if it has one.
		route.push_front({"p": pts[k], "door": int(door_of[k]) if int(mate[k]) == int(prev[k]) else -1})
		k = int(prev[k])
	return route


func _clearance(d: Vector3, reach: float) -> float:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var p: Vector3 = ch.global_position
	var best := reach
	for hh in [0.5, 1.25]:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * hh, p + Vector3.UP * hh + d * reach, Defs.MOVE_MASK)
		q.exclude = [ch.get_rid()]
		var r := space.intersect_ray(q)
		if not r.is_empty():
			best = minf(best, Vector2(r.position.x - p.x, r.position.z - p.z).length())
	# r12: outdoors, a doorway is not a way out of the field: a building is where it crushes you.
	if world.map.acoustics.zone_at(p + Vector3.UP * 0.5) == 0:
		for s in [1.0, 2.0, 3.0, 4.0]:
			if s < best and world.map.acoustics.zone_at(p + d * s + Vector3.UP * 0.5) != 0:
				best = s - 0.6
				break
	return best


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
	extra += " indoors %s exit %d field %.1f m" % [str(world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5) != 0), _house_exit.size(),
		float(Field.at(world, ch.global_position, float(Net.tick)).pen)]
	if mind != null:
		extra += " | " + str(mind.describe())
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
	if test_blind:
		target_eid = -1
		investigate = Vector3.INF
		return
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
		vis_range *= _sk_vision   # (r22) bot skill
		if d > vis_range:
			continue
		var to: Vector3 = (o.global_position + Vector3.UP * 1.2) - eye
		var fwd := -Basis.from_euler(Vector3(0, yaw, 0)).z
		if d > 6.0 and fwd.dot(to.normalized()) < _sk_behind and not lit:
			continue  # behind and quiet
		var q := PhysicsRayQueryParameters3D.create(eye, eye + to, Defs.SIGHT_MASK)
		if not space.intersect_ray(q).is_empty():
			continue
		if d < best_d:
			best_d = d
			best = o.eid
	if best != target_eid and best >= 0:
		reaction = rng.randf_range(_sk_react.x, _sk_react.y)
		aim_err = Vector2(rng.randf_range(-_sk_err.x, _sk_err.x), rng.randf_range(-_sk_err.y, _sk_err.y))
		_acq_t = Time.get_ticks_msec() / 1000.0
		if target_eid < 0:
			say("contact")
	if best < 0:
		_acq_t = -1.0
		var lost = world.characters.get(target_eid) if target_eid >= 0 and _sk_tactics else null
		if lost != null and lost.mode == Motor.GROUND and last_seen != Vector3.INF and state == "fight":
			# (r22) pro: it broke line of sight (still standing): after it, aimed where it was last seen
			investigate = last_seen
			_preaim_t = 6.0
	target_eid = best
	if best >= 0:
		last_seen = world.characters[best].global_position
		# The callout: the whole team knows where (each decides on its own what to do about it).
		BotTeam.board(ch.team).set_var(&"intel", {"p": last_seen, "t": Time.get_ticks_msec()})
		BotTeam.contact(ch.team)


# ------------------------------------------------------------------ zone

func _inside_zone(p: Vector3) -> Vector3:
	## Pulls a goal inside the next safe circle (or the current one before the first is announced).
	var zone: Dictionary = world.match_info.get("zone", {})
	var circ: Array = world.zone_circle(float(Net.tick))
	var c: Vector2 = zone.get("c1", circ[0])
	var r := float(zone.get("r1", circ[1])) * 0.75   # r12: well clear of the field's edge
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
	_house_exit = [centre - out_dir * EXIT_IN, centre + out_dir * (1.4 + foot_of_steps)]
	_house_exit_door = int(door.id)
	_house_exit_bid = int(b.id)
	_house_way = []
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


var _haul := false   # climbing out of the water over a canal wall (Parkour.water_grab): climb_ok is ours to clear


func _water_way() -> Dictionary:
	## The way out of the water: {ladder} when one is close, else {dry: the closest dry point round about}, else {} (no
	## dry ground near at all: carry on as usual). (r22) _wet_step decides when (and counts the time wading).
	var p: Vector3 = ch.global_position
	var best := {}
	var bd := 12.0
	for ld in world.map.ladders:
		var b: Vector3 = ld.base
		if b.y > p.y + 1.0:
			continue
		var dd := Vector2(b.x - p.x, b.z - p.z).length()
		if dd < bd:
			bd = dd
			best = ld
	if not best.is_empty():
		return {"ladder": best}
	for r in [2.0, 4.0, 7.0, 11.0, 16.0, 22.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var q = Vector2(p.x, p.z) + Vector2(cos(a), sin(a)) * r
			if not world.map.layout.is_water(q.x, q.y):
				return {"dry": q}
	return {}


func _escape_water(cmd: Dictionary, dt: float, way: Dictionary) -> void:
	## Wading a moment is fine; after that, climb a ladder if one is close, else walk to the nearest dry ground: into a
	## canal wall the hands catch its coping and the bot climbs out (Parkour.water_grab), up a sloped bank it walks out.
	var p: Vector3 = ch.global_position
	cmd.pitch = lerpf(pitch, 0.25, 0.2)
	cmd.my = 1.0
	if way.has("ladder"):
		var best: Dictionary = way.ladder
		ch.set_meta("ladder_ok", true)
		var n: Vector3 = best.n
		var foot: Vector3 = (best.base as Vector3) + n * 0.3
		var to := Vector2(foot.x - p.x, foot.z - p.z)
		if to.length() > 0.35 and ch.is_on_floor():
			cmd.yaw = lerp_angle(yaw, atan2(-to.x, -to.y), 0.3)
		else:
			cmd.yaw = lerp_angle(yaw, atan2(n.x, n.z), 0.5)
		return
	ch.set_meta("climb_ok", true)
	_haul = true
	var to2: Vector2 = (way.dry as Vector2) - Vector2(p.x, p.z)
	cmd.yaw = lerp_angle(yaw, atan2(-to2.x, -to2.y), 0.3)
	if _stuck_t > 1.0:
		cmd.btn |= Motor.B_JUMP
	var moved := p.distance_to(_last_pos)
	_last_pos = p
	_stuck_t = _stuck_t + dt if moved < 0.4 * dt else 0.0


func _set_goal(g: Vector3) -> void:
	# A goal on the far side of a wall (another region of the walk grid) becomes the nearest point this side of it:
	# without this, bots walked into the wall toward it and stayed there.
	_goal_raw = g
	if g != Vector3.INF and nav != null and not Waypoints.ready():
		# (r23: with the waypoint graph a goal stays where it is: the route ends at the node nearest it the roads reach.
		# The grid's region test pulled every goal across Sitio Kalinaw's river back to the near bank: its bridges are
		# not on the grid.)
		g = nav.reachable_near(ch.global_position, g)
		if g != Vector3.INF and not nav.walkable_at(g):
			# r21: still off the walk (outside the building, inside a sealed shop): the nearest waypoint instead
			var best := Vector3.INF
			var bd := INF
			for i in BotTeam.spots_near(g, 48.0):
				var q: Vector3 = BotTeam.spots[i].p
				var d := q.distance_to(g) + absf(q.y - g.y) * 2.0
				if d < bd:
					bd = d
					best = q
			g = best
	goal = g
	_no_prog = 0.0
	_best_wp = INF
	path = []
	path_i = 0
	path_wp = PackedInt32Array()
	_wp_tail = {}
	_wp_head = {}
	_wp_route = false
	_wp_prev = -1
	_ended_short = false
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
			path_wp = PackedInt32Array()
			path_wp.resize(path.size())
			path_wp.fill(-1)
			_wp_prev = -1
			_seg_from = ch.global_position
			if not _wp_tail.is_empty():
				# (r23) the grid's way onto the graph, then the graph's route
				path.append_array(_wp_tail.pts)
				path_wp.append_array(_wp_tail.wps)
				_wp_tail = {}
				_wp_route = true
			elif not _wp_head.is_empty():
				# (r23) the graph's route, then the grid's way from its last waypoint to the house door
				var hp: Array = (_wp_head.pts as Array).duplicate()
				hp.append_array(path)
				var hw: PackedInt32Array = _wp_head.wps
				hw.append_array(path_wp)
				path = hp
				path_wp = hw
				_wp_head = {}
				_seg_from = ch.global_position
			# r12: the search starts from the open cell nearest the bot, which can be on the far side of a wall (just
			# out of a door it led straight back into the house): start from the furthest of the first few waypoints
			# in plain sight.
			for k in range(mini(3, path.size() - 1), 0, -1):
				if _walk_line(path[k]):
					path_i = k
					break
		return
	if not _path_pending or goal == Vector3.INF:
		return
	_path_pending = false
	if Waypoints.ready():
		# r23: the waypoint graph: from the node the bot can walk straight to, along proven edges, to the node the goal
		# is in plain sight of (and the goal), or to the node nearest it when it is not.
		var rt := Waypoints.route(ch.global_position, goal)
		if rt.has("pts"):
			if rt.has("lead"):
				# nowhere near a node it can walk straight to (pushed into a corner, fallen somewhere): the grid's way to
				# the nearest node first
				_wp_tail = {"pts": rt.pts, "wps": rt.wps}
				_path_req = nav.request(ch.global_position, rt.lead, MAX_EXPAND)
				wp_stats.leads += 1
				return
			if plan_i < plan.size() and (rt.wps as PackedInt32Array)[(rt.wps as PackedInt32Array).size() - 1] >= 0 \
					and (rt.pts[rt.pts.size() - 1] as Vector3).distance_to(goal) > 0.6:
				# a house plan's door is out of sight of every waypoint (doors in the lanes between houses): the graph's
				# route, then the grid's way from its last waypoint to the door, as house plans always walked it
				_wp_head = {"pts": rt.pts, "wps": rt.wps}
				_path_req = nav.request(rt.pts[rt.pts.size() - 1], goal, MAX_EXPAND)
				return
			path = rt.pts
			path_wp = rt.wps
			path_i = 0
			_wp_prev = -1
			_wp_route = true
			_seg_from = ch.global_position
			# already past the first node (a new route every few seconds): on to the next when the way there is clear
			if path.size() > 1 and path_wp[0] >= 0 and (path[0] as Vector3).distance_to(ch.global_position) < 4.0 \
					and Waypoints.clear(ch.global_position, path[1]):
				path_i = 1
			wp_stats.routes += 1
			return
	wp_stats.grid += 1
	if Waypoints.ready():
		# no route on the graph (the goal far off every road): the grid's way to the nearest place it reaches
		var g2: Vector3 = nav.reachable_near(ch.global_position, goal)
		if g2 == Vector3.INF:
			goal = Vector3.INF
			return
		goal = g2
	_path_req = nav.request(ch.global_position, goal, MAX_EXPAND)


func _move(cmd: Dictionary, dt: float, slow: bool) -> void:
	_ensure_path()
	if state == "loot" and plan_i < plan.size():
		_plan_step(cmd, dt)
		return
	if goal == Vector3.INF:
		_idle_face(cmd, dt)
		return
	_face_yaw = INF
	var target := goal
	var node := -1
	if path_i < path.size():
		target = path[path_i]
		node = path_wp[path_i] if path_i < path_wp.size() else -1
		var dw := Vector2(target.x - ch.global_position.x, target.z - ch.global_position.z).length()
		if node >= 0 and not (str(Waypoints.nodes[node].kind) in ["stair", "escalator"]):
			# (r23) a waypoint node: reached at 0.45 m, or at 1.2 m when a body can walk straight on to the next point
			# from here (swept, checked five times a second). Never on round a corner it cannot see past.
			var adv := dw < 0.45
			if not adv and dw < 1.2 and path_i + 1 < path.size():
				_wp_check_t -= dt
				if _wp_check_t <= 0.0:
					_wp_check_t = 0.2
					var nx_p: Vector3 = path[path_i + 1]
					_wp_ok_next = absf(nx_p.y - target.y) < 0.5 and Waypoints.clear(ch.global_position, nx_p)
				adv = _wp_ok_next
			if adv:
				_wp_prev = node
				_seg_from = target
				_wp_ok_next = false
				_wp_check_t = 0.0
				path_i += 1
				_best_wp = INF
		# (r21) on to the next waypoint only when right at this one, or when the next is in plain sight from here: a
		# waypoint just through a doorway counted as reached from inside the room sent bots along the inside of the
		# wall toward the one after it. (Stair and escalator points, off the floor's walk grid, keep the loose reach.)
		elif dw < 0.45 or (dw < 1.2 and (path_i + 1 >= path.size() or absf((path[path_i + 1] as Vector3).y - target.y) > 0.5
				or not nav.walkable_at(target) or nav.line_clear(ch.global_position, path[path_i + 1]))):
			if node >= 0:
				_wp_prev = node
			_seg_from = target
			path_i += 1
			_best_wp = INF
		if path_i < path.size():
			target = path[path_i]
			node = path_wp[path_i] if path_i < path_wp.size() else -1
		else:
			target = goal
			node = -1
	var to = target - ch.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 0.6 and path_i >= path.size():
		goal = Vector3.INF
		return
	# r21: the path is walked and the goal is still off, behind something: that path ended as near as the walk gets
	# (the goal is in a pocket or on another floor with no way there). Done, rather than pushing at the wall. (On a
	# storeyed map only: on the flat maps a long search stops early on purpose and the next one carries on from its end.
	# (r23) A route of the waypoint graph ends at the goal only when the goal is in plain sight of its last node: on
	# every map its end is as near as the roads get.)
	if path_i >= path.size() and not _path_pending and _path_req == 0 and flat.length() > 1.5 and (_wp_route or nav.get("levels") != null) \
			and not nav.line_clear(ch.global_position, goal):
		goal = Vector3.INF
		_ended_short = true
		return
	# r23: on an edge of the graph the bot steers for a point a metre ahead of itself on the edge, not for its end, so
	# it keeps to the line that was swept clear; pushed well off it (a crowd, a fight), it plans again from where it is.
	var steer := target
	if node >= 0 and _seg_from != Vector3.INF:
		var ab := Vector2(target.x - _seg_from.x, target.z - _seg_from.z)
		var seg_len := ab.length()
		if seg_len > 0.6:
			var u := ab / seg_len
			var rel := Vector2(ch.global_position.x - _seg_from.x, ch.global_position.z - _seg_from.z)
			var along := clampf(rel.dot(u) + 1.0, 0.0, seg_len)
			steer = Vector3(_seg_from.x + u.x * along, target.y, _seg_from.z + u.y * along)
			if absf(rel.cross(u)) > 1.8 and not _off_floor():
				_off_line_t += dt
				if _off_line_t > 1.0:
					_off_line_t = 0.0
					wp_stats.off_line += 1
					_set_goal(goal)
					return
			else:
				_off_line_t = 0.0
		# a door on this edge: open it first
		if _wp_prev >= 0:
			var e := Waypoints.edge(Waypoints.edge_between(_wp_prev, node))
			if not e.is_empty() and str(e.kind) == "door" and int(e.door) >= 0 and _wp_door(cmd, dt, int(e.door), _wp_prev, node):
				return
	var sv := Vector2(steer.x - ch.global_position.x, steer.z - ch.global_position.z)
	if sv.length() < 0.05:
		sv = flat
	var want_yaw := atan2(-sv.x, -sv.y)
	cmd.yaw = lerp_angle(yaw, want_yaw, 0.2)
	cmd.pitch = lerpf(pitch, 0.0, 0.1)
	cmd.my = 1.0
	# No path yet (searches queue on a worker thread): walk straight only if nothing is in the way; otherwise turn
	# toward the goal and wait. Walking straight at a goal behind a wall is how bots ended up stuck on walls.
	if path.is_empty() and _path_req != 0 and not nav.line_clear(ch.global_position, goal):
		cmd.my = 0.0
		return
	_gait(cmd, flat.length(), slow)
	_feel_walls(cmd, dt, flat.length())
	_unstick(cmd, dt, target, flat.length())
	_repath_t -= dt
	if _repath_t <= 0.0 and goal != Vector3.INF:
		if _off_floor():
			_repath_t = 1.0   # (r21) on a stair or an escalator: finish it on the path in hand (a new one from
			                  # mid-flight could start at a stair point behind the bot and walk it back down)
		else:
			_set_goal(goal)


func _wp_door(cmd: Dictionary, dt: float, di: int, a: int, b: int) -> bool:
	## r23: the edge walked goes through door di. Shut and within reach: face it and open it (one press per try), out
	## of its swing, and wait while it swings open. Locked, or still shut after 8 s: that edge closes for a while and
	## the bot routes round it. True while the door holds the bot up.
	var dn = world.map.dyn.doors[di].get("node") if di < world.map.dyn.doors.size() else null
	if dn == null or bool(dn.get("destroyed")):
		return false
	var ang := absf(float(dn.angle))
	var shut: bool = ang <= dn.OPEN_PASS and absf(float(dn.target)) < 0.05 and not dn.free
	if not shut:
		if dn.moving and ang <= dn.OPEN_PASS:
			cmd.my = 0.0
			return true
		_wpdoor_t = 0.0
		return false
	var dc: Vector3 = dn.center()
	var eye: Vector3 = ch.eye_position()
	if eye.distance_to(dc) > 2.0:
		return false
	if _wpdoor_t > 8.0:
		# it will not open (locked fast, jammed): that edge closes for a while and the bot goes round; when it is the only
		# way (Waypoints.block keeps such an edge open), this walk ends here instead of coming back to the door for ever
		wp_stats.locked += 1
		var ei := Waypoints.edge_between(a, b)
		Waypoints.block(ei, 120.0)
		_wpdoor_t = 0.0
		if Waypoints._blocked.has(ei):
			_set_goal(goal)
		else:
			goal = Vector3.INF
			_ended_short = true
		return true
	if _wpdoor_t == 0.0:
		wp_stats.door_waits += 1
	_wpdoor_t += dt
	var tv: Vector3 = dc - eye
	cmd.yaw = atan2(-tv.x, -tv.z)
	cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
	if dn.locked:
		# locked: a fresh press, then held to force it (as on the way into a house)
		if _wpdoor_t > 0.15 and _wpdoor_t < 4.0:
			cmd.btn |= Motor.B_USE
	elif fmod(_wpdoor_t, 1.6) > 0.15 and fmod(_wpdoor_t, 1.6) < 0.3:
		cmd.btn |= Motor.B_USE
	cmd.my = -0.5 if Vector2(dc.x - ch.global_position.x, dc.z - ch.global_position.z).length() < 0.9 else 0.0
	return true


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
		"order":
			if dist > 5.0:
				cmd.btn |= Motor.B_SPRINT
			elif str(order.get("kind", "")) == "check":
				cmd.btn |= Motor.B_WALK
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
				# A vault or a hop, only where the walk grid has open ground beyond (not onto a parapet or a wall top);
				# (r21) and on a storeyed map only from a floor: from a stair's half landing the grid "ahead" is the
				# floor below, and the hop went over the stair's railing into the space under the flights.
				var fwd0 := -Basis(Vector3.UP, yaw).z
				if not _off_floor() and nav.walkable_at(ch.global_position + fwd0 * 1.6):
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
		# (r23) stuck on an edge of the waypoint graph: it closes for every bot for a while (and for the rest of the
		# match after three reports), so the next route goes another way
		var wn: int = path_wp[path_i] if path_i < path_wp.size() else -1
		if wn >= 0 and _wp_prev >= 0 and _ahead() != "char":
			Waypoints.report_stuck(_wp_prev, wn, ch.eid)   # (someone in the way is a queue, not a blocked edge)
			wp_stats.stuck_edges += 1
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


func _idle_face(cmd: Dictionary, dt: float) -> void:
	## r21: standing with nowhere to go for the moment (between objectives, the start of a round, a walk that ended
	## at a wall): a wall within 1.5 m in front turns the bot to the most open way instead of leaving it staring at it.
	_face_t -= dt
	if _face_t <= 0.0:
		_face_t = 1.0
		_face_yaw = _open_yaw(yaw, PI) if _wall_close(yaw, 1.5) else INF
	if _face_yaw != INF:
		cmd.yaw = lerp_angle(yaw, _face_yaw, 0.12)


func _off_floor() -> bool:
	## r21: on a storeyed map, between floors (a stair, its half landing, an escalator).
	if nav == null or nav.get("levels") == null:
		return false
	var p: Vector3 = ch.global_position
	return absf(p.y - float(world.map.layout.level_y(nav.level_of(p)))) > 0.7


func _feel_walls(cmd: Dictionary, dt: float, dist: float) -> void:
	## r21: whiskers. Two short rays at knee height, 30 degrees either side of the way the bot walks: a wall, pillar
	## or counter edge closing in on one side pushes it to the other, so it slides past corners instead of grinding
	## into them. In a doorway both sides touch and the pushes cancel.
	if ch.mode != Motor.GROUND or float(cmd.my) <= 0.0 or dist < 0.9 or _unstick_t > 0.0:
		_feel_mx = 0.0
		return
	_feel_t -= dt
	if _feel_t <= 0.0:
		_feel_t = 0.1
		var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		var p: Vector3 = ch.global_position + Vector3.UP * 0.55
		var push := 0.0
		for side in [-1.0, 1.0]:
			var d: Vector3 = Basis(Vector3.UP, float(cmd.yaw) - side * 0.52) * Vector3.FORWARD
			var q := PhysicsRayQueryParameters3D.create(p, p + d * 1.1, Defs.MOVE_MASK)
			q.exclude = [ch.get_rid()]
			var r := space.intersect_ray(q)
			if not r.is_empty():
				push -= side * (1.0 - Vector2((r.position as Vector3).x - p.x, (r.position as Vector3).z - p.z).length() / 1.1)
		_feel_mx = clampf(push * 1.5, -0.9, 0.9)
		if path_i < path_wp.size() and path_wp[path_i] >= 0:
			_feel_mx *= 0.5   # (r23) on a swept edge: the line itself keeps off the walls; whiskers only nudge
	if absf(_feel_mx) > 0.05:
		cmd.mx = clampf(float(cmd.mx) + _feel_mx, -1.0, 1.0)


func _open_yaw(pref: float, spread: float) -> float:
	## r21: of nine directions within spread of pref, the one with the most open floor ahead at eye height (ties go
	## to the one nearest pref): where to face while standing still.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var eye: Vector3 = ch.eye_position()
	var best := pref
	var bs := -INF
	for k in 9:
		var a := pref + spread * (float(k) / 4.0 - 1.0)
		var d: Vector3 = Basis(Vector3.UP, a) * Vector3.FORWARD
		var q := PhysicsRayQueryParameters3D.create(eye, eye + d * 20.0, Defs.SIGHT_MASK)
		q.exclude = [ch.get_rid()]
		var r := space.intersect_ray(q)
		var dist := 20.0 if r.is_empty() else eye.distance_to(r.position)
		var sc := minf(dist, 12.0) - absf(wrapf(a - pref, -PI, PI)) * 1.5
		if sc > bs:
			bs = sc
			best = a
	return best


func _wall_close(a: float, reach: float = 2.0) -> bool:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var eye: Vector3 = ch.eye_position()
	var q := PhysicsRayQueryParameters3D.create(eye, eye + (Basis(Vector3.UP, a) * Vector3.FORWARD) * reach, Defs.SIGHT_MASK)
	q.exclude = [ch.get_rid()]
	return not space.intersect_ray(q).is_empty()


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
		_hold_said = false
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
				elif step.get("exit", false) and Vector2(dc.x - ch.global_position.x, dc.z - ch.global_position.z).length() < 1.3:
					cmd.my = -0.6  # on the way out the door may swing in: back off it before pulling it open
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
	if not step.nav and not (_zone_go and _exiting()):
		cmd.btn |= Motor.B_WALK   # (out of a house with the field coming: at a run)
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
		if _sk_tactics and rounds > 0 and cls in ["marksman", "precision"]:
			# (r22) pro: the long gun from range, never up close (the handgun or a close gun then)
			v += 3.0 if dist > 30.0 else (-3.0 if dist < 20.0 else 0.0)
		if s == ch.wpn.cur:
			v += 0.8
		if v > bs:
			bs = v
			best = s
	if best >= 0:
		cmd.slot = best


# r22: the fight's leaf skills. The combat tree (bot_mind.gd) runs them every tick: _fight_aim, then unarmed
# _fight_flee, else _fight_trigger and the footwork (_pro_* for pro bots, else _fight_temperament).

func _fight_aim(cmd: Dictionary, dt: float) -> bool:
	## On the target (its head at range for pro), off by the skill's aim error as it settles. False: it is gone.
	var o = world.characters.get(target_eid)
	if o == null:
		target_eid = -1
		return false
	var d0: float = o.global_position.distance_to(ch.global_position)
	_equip_best(cmd, d0)
	var aim_pt: Vector3 = o.global_position + Vector3.UP * (1.25 if o.mode != Motor.DOWNED else 0.25)
	if _sk_head > 0.0 and d0 > _sk_head and o.mode != Motor.DOWNED:
		aim_pt = o.eye_position() + Vector3.UP * 0.03   # (r22) pro: the head, at range
	var to = aim_pt - ch.eye_position()
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	# (r22) bot skill: how far off the first aim is, how fast it settles and follows, and a shake that never settles
	aim_err = aim_err.move_toward(Vector2.ZERO, dt * _sk_settle)
	var err := aim_err
	if _sk_wobble > 0.0:
		var tw: float = Time.get_ticks_msec() * 0.001 + ch.eid * 1.7
		err += Vector2(sin(tw * 1.9) + 0.5 * sin(tw * 4.3), 0.6 * sin(tw * 2.6 + 1.0) + 0.3 * sin(tw * 5.1)) * _sk_wobble
	cmd.yaw = lerp_angle(yaw, want_yaw + deg_to_rad(err.x), minf(dt * _sk_lerp, 1.0))
	cmd.pitch = lerpf(pitch, want_pitch + deg_to_rad(err.y), minf(dt * _sk_lerp, 1.0))
	_f_o = o
	_f_d = to.length()
	_f_want_yaw = want_yaw
	reaction -= dt
	return true


func _fight_flee(cmd: Dictionary) -> void:
	## Unarmed: get away.
	cmd.yaw = _f_want_yaw + PI
	cmd.my = 1.0
	cmd.btn |= Motor.B_SPRINT


func _fight_trigger(cmd: Dictionary, dt: float) -> void:
	## Aim down the sights close or scoped; reload an empty gun; once reacted and on target, fire (bursts with an auto).
	var d := _f_d
	if d < 25.0 or ch.wpn.zoom() > 1.5:
		cmd.btn |= Motor.B_AIM
	if ch.wpn.loaded() == 0:
		cmd.btn |= Motor.B_RELOAD
		if ch.wpn.state == 0:
			say("reloading")
	elif reaction <= 0.0 and absf(wrapf(_f_want_yaw - yaw, -PI, PI)) < _sk_gate:
		_fire_hold -= dt
		if _fire_hold < 0.0:
			_fire_hold = rng.randf_range(_sk_burst.x, _sk_burst.y)
		if _fire_hold > 0.1 or ch.wpn.fire_mode() != "auto":
			cmd.btn |= Motor.B_FIRE if rng.randf() < _sk_fire else 0


func _fight_temperament(cmd: Dictionary) -> void:
	## Footwork by temperament: rushers close in, snipers and campers keep still (crouched at range), the rest strafe.
	var d := _f_d
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


func _pro_read(o, d: float) -> void:
	## r22 pro, four times a second: what it has rounds for, and whether the fight is open to a push (the target
	## reloading, hurt, looking away, or more of this side close than of the target's).
	var any := false
	var only_hand := true
	for s in [1, 2, 3]:
		var w = ch.wpn.slots[s]
		if w == null:
			continue
		if int(w.mag) + (1 if w.chamber else 0) + ch.inv.count(Defs.ammo_item(str(w.id))) > 0:
			any = true
			if str(Defs.weapon(str(w.id)).get("class", "")) != "handgun":
				only_hand = false
	_rush = not any or only_hand
	var op: Vector3 = o.global_position
	var open: bool = (o.wpn != null and o.wpn.state == WeaponState.RELOAD) or float(o.health.health) < 50.0
	if not open:
		var away: Vector3 = ch.global_position - op
		away.y = 0.0
		open = d > 3.0 and (-Basis(Vector3.UP, float(o.yaw)).z).dot(away.normalized()) < 0.2
	if not open:
		var mine := 0
		var theirs := 0
		for c in world.characters.values():
			if c.mode != Motor.GROUND:
				continue
			if c.team == ch.team and c.global_position.distance_to(ch.global_position) < 25.0:
				mine += 1
			elif c.team == o.team and c.global_position.distance_to(op) < 25.0:
				theirs += 1
		open = mine > theirs
	_push = open


# r22 pro: fights by what it holds and what it sees. A marksman or bolt gun stays at range, crouched behind the scope,
# and backs off (to its handgun) when the enemy closes; out of rounds, or down to a handgun, it rushes; with an smg,
# rifle, shotgun or lmg it pushes an opening; reloading it gets out of the line of fire. The combat tree picks the
# first that applies (bot_mind.gd), in that order: reloading, rush, long gun, opening, else strafe.

func _pro_tick(dt: float) -> void:
	## Every tick: the strafe side and the gun's class; four times a second, the read of the fight (_pro_read).
	_tac_t -= dt
	if _tac_t <= 0.0:
		_tac_t = 0.25
		_pro_read(_f_o, _f_d)
	_f_side = sin(Time.get_ticks_msec() * 0.003 + ch.eid)
	_f_cls = str(ch.wpn.def().get("class", ""))


func _pro_reloading_exposed() -> bool:
	return ch.wpn.state == WeaponState.RELOAD and not _rush and _f_d < 40.0


func _pro_back_off(cmd: Dictionary) -> void:
	cmd.my = -0.8
	cmd.mx = 1.0 if _f_side >= 0.0 else -1.0
	cmd.btn = int(cmd.btn) & ~Motor.B_AIM


func _pro_rush(cmd: Dictionary) -> void:
	cmd.mx = _f_side
	cmd.my = 1.0 if _f_d > 3.0 else 0.0
	if _f_d > 8.0:
		cmd.btn = (int(cmd.btn) | Motor.B_SPRINT) & ~Motor.B_AIM


func _pro_range(cmd: Dictionary) -> void:
	if _f_d > 30.0:
		cmd.mx = 0.0
		cmd.my = 0.0
		cmd.btn = int(cmd.btn) | Motor.B_CROUCH | Motor.B_AIM
	elif _f_d < 20.0:
		cmd.my = -1.0
		cmd.mx = _f_side * 0.7
	else:
		cmd.mx = _f_side * 0.5
		cmd.btn = int(cmd.btn) | Motor.B_AIM


func _pro_push(cmd: Dictionary) -> void:
	cmd.mx = _f_side
	cmd.my = 1.0
	if _f_d > 15.0 and _f_cls != "lmg":
		cmd.btn = (int(cmd.btn) | Motor.B_SPRINT) & ~Motor.B_AIM


func _pro_strafe(cmd: Dictionary) -> void:
	cmd.mx = _f_side * 0.8
	if _f_d > 35.0:
		cmd.my = 0.5
	if ch.health.health < 35.0 and _f_d < 25.0:
		cmd.my = -0.7


func _pre_aim(cmd: Dictionary, dt: float) -> void:
	## r22 pro: after a target that broke line of sight, at a run, looking where it was last seen (aimed when close):
	## the walk the path asks for, re-expressed for that facing.
	_preaim_t -= dt
	if state != "investigate" or last_seen == Vector3.INF or goal == Vector3.INF:
		return
	var to: Vector3 = last_seen + Vector3.UP * 1.25 - ch.eye_position()
	var dl := Vector2(to.x, to.z).length()
	var tgt: Vector3 = path[path_i] if path_i < path.size() else goal
	var mv := Vector2(tgt.x - ch.global_position.x, tgt.z - ch.global_position.z)
	if dl > 45.0 or dl < 1.5 or mv.length() < 0.3:
		return
	var wv := Basis(Vector3.UP, atan2(-mv.x, -mv.y)) * Vector3(float(cmd.mx), 0.0, -float(cmd.my))
	var face := lerp_angle(yaw, atan2(-to.x, -to.z), 0.3)
	var lv := Basis(Vector3.UP, face).inverse() * wv
	cmd.yaw = face
	cmd.pitch = lerpf(pitch, atan2(to.y, dl), 0.3)
	cmd.mx = lv.x
	cmd.my = -lv.z
	if dl < 15.0:
		cmd.btn = (int(cmd.btn) | Motor.B_AIM) & ~Motor.B_SPRINT
	elif -lv.z > 0.3:
		cmd.btn = int(cmd.btn) | Motor.B_SPRINT


func _tally() -> void:
	## r22 [botskill] numbers: rounds fired (the gun's own count), hits (damage dealt went up within 2 s of a round),
	## and the time from first sight of a target to the first round fired.
	var n: int = ch.wpn.shots
	if _shots_seen < 0 or n < _shots_seen:
		_shots_seen = n
	elif n > _shots_seen:
		BotTeam.skill_note(skill, "shots", n - _shots_seen)
		_shots_seen = n
		if _acq_t >= 0.0:
			BotTeam.skill_note(skill, "react", Time.get_ticks_msec() / 1000.0 - _acq_t)
			_acq_t = -1.0
	var ms = world.match_server
	if ms == null:
		return
	var st = ms.stats.get(ch.eid)
	if st == null:
		return
	var dmg := float(st.damage)
	if _dmg_seen >= 0.0 and dmg > _dmg_seen + 0.01 and ch.wpn.since_shot < 2.0:
		BotTeam.skill_note(skill, "hits", dmg - _dmg_seen)
	_dmg_seen = dmg


func _lights(cmd: Dictionary) -> void:
	## Bots use their light indoors when nobody is around, and turn it off when fighting.
	var indoor: bool = world.map.acoustics.zone_at(ch.global_position) != 0
	var want = indoor and state in ["loot", "roam"] and ch.light.charge() > 0.1
	if want != ch.light.on and rng.randf() < 0.05:
		cmd.btn |= Motor.B_LIGHT  # a tap toggles (pressed this tick, released next)


# ------------------------------------------------------------------ r10: roles

func _exiting() -> bool:
	return state == "loot" and plan_i < plan.size() and bool(plan[-1].get("exit", false))


var _zone_go := false   # _haze() said to leave for the next circle (the last time the state was chosen)


func _find_exit() -> bool:
	## r12: true when this bot knows a way out of the building it is in (or is not in one). Indoors with no door
	## remembered (in through a window, a fight, or a way out that failed): the nearest outer door on this floor of the
	## building around it, the one with a clear walk to it if any, and one that opens on to the safe area if any.
	var p: Vector3 = ch.global_position
	if _house_exit.size() == 2 or world.map.acoustics.zone_at(p + Vector3.UP * 0.5) == 0:
		return true
	var here := Vector2i(floori(p.x / BCELL), floori(p.z / BCELL))
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var zone: Dictionary = world.match_info.get("zone", {})
	var c1: Vector2 = zone.get("c1", Vector2.INF) if not zone.is_empty() else Vector2.INF
	var best := {}
	var bd := INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for b in bgrid.get(here + Vector2i(dx, dz), []):
				var lp: Vector3 = (b.xf as Transform3D).affine_inverse() * p
				if absf(lp.x) > float(b.w) * 0.5 + 0.5 or absf(lp.z) > float(b.d) * 0.5 + 0.5:
					continue
				for door in _exits_of(int(b.id)):
					var out_dir: Vector3 = door.outward
					out_dir.y = 0.0
					out_dir = out_dir.normalized()
					var centre: Vector3 = (door.xf as Transform3D) * Vector3(float(door.w) * 0.5, 0.0, 0.0)
					if absf(centre.y - p.y) > 1.2:
						continue   # another floor
					var inside := centre - out_dir * EXIT_IN
					# How far it is to walk there: straight, or through the rooms (no way there: only if nothing better).
					var d := Vector2(inside.x - p.x, inside.z - p.z).length()
					var way := []
					if not _walk_clear(p, inside):
						way = _house_route(int(b.id), p, inside)
						if way.is_empty():
							d += 30.0
						else:
							d = 0.0
							var prev_p := p
							for w in way:
								d += prev_p.distance_to(w.p)
								prev_p = w.p
							d += prev_p.distance_to(inside)
					var outside := centre + out_dir * 1.4
					if float(Field.at(world, outside, float(Net.tick)).pen) > -1.0:
						d += 25.0   # opens into the field, which pushes whoever steps out straight back in
					if float(_exit_tried.get(int(door.id), -99.0)) > world.match_server._t - 15.0:
						d += 40.0   # tried that way out a moment ago and it did not work: another door first
					if c1 != Vector2.INF:
						# A door on the far side from the next circle leads toward the field: the way it comes from.
						d += maxf(Vector2(outside.x, outside.z).distance_to(c1) - Vector2(p.x, p.z).distance_to(c1), 0.0) * 1.5
					if Game.arg("exitdebug") != null:
						print("[exit %s] house %d door %d at %s: way %d steps, score %.1f" % [ch.pname, int(b.id), int(door.id), str(centre.round()), way.size(), d])
					if d < bd:
						bd = d
						best = {"inside": inside, "out": centre + out_dir * (1.4 + float(door.get("steps_out", 0.0))), "door": int(door.id), "bid": int(b.id),
							"way": way}
	if best.is_empty():
		return false
	_house_exit = [best.inside, best.out]
	_house_exit_door = int(best.door)
	_house_exit_bid = int(best.bid)
	_house_way = best.way
	return true


func _leave_house() -> bool:
	## Indoors with a door to leave by: walk out through it (a short plan) before anything that needs the walk grid.
	if _house_exit.size() != 2 or _exiting():
		return false
	if world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5) == 0:
		_house_exit = []
		return false
	plan = [{"p": _house_exit[0], "nav": false}, {"p": _house_exit[1], "nav": false, "exit": true}]
	if _house_exit_door >= 0:
		plan[1]["door"] = _house_exit_door
		if world.match_server:
			_exit_tried[_house_exit_door] = world.match_server._t
	# Through the rooms to that door first.
	if _house_way.is_empty() and _house_exit_bid >= 0:
		_house_way = _house_route(_house_exit_bid, ch.global_position, _house_exit[0])
	for i in range(_house_way.size() - 1, -1, -1):
		var w: Dictionary = _house_way[i]
		var st := {"p": w.p, "nav": false}
		if int(w.door) >= 0:
			st["door"] = int(w.door)
		plan.push_front(st)
	_house_way = []
	_house_exit = []
	_house_exit_door = -1
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


func _head_for_spot(sp: int, secs: float) -> void:
	var s: Dictionary = BotTeam.spots[sp]
	_obj = s.p
	_look_at = (s.p as Vector3) + Vector3((s.dir as Vector2).x, 0, (s.dir as Vector2).y) * 25.0 + Vector3.UP * 1.2
	BotTeam.release(ch.eid)
	BotTeam.claim(sp, ch.eid, secs + 60.0)
	_spot_i = sp
	_set_goal(_obj)
	state = "roam"
	_obj_t = secs


func _intel() -> Vector3:
	var it: Dictionary = BotTeam.board(ch.team).get_var(&"intel", {})
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
			var foes := []
			for t in world.match_server.spawn_info:
				if t is int and t != ch.team:
					foes.append(t)
			var other: Dictionary = world.match_server.spawn_info.get(foes[rng.randi() % foes.size()], {}) if not foes.is_empty() else {}
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
	# (r22) not a spot held in the last three minutes, nor one beside the last hold (the one it stood on won every time)
	var now_s := Time.get_ticks_msec() / 1000.0
	var recent := {}
	for h in _holds:
		if now_s - float(h[2]) < HOLD_MEMORY_S:
			recent[int(h[0])] = true
	var last_p: Vector3 = _holds[-1][1] if not _holds.is_empty() and now_s - float(_holds[-1][2]) < HOLD_MEMORY_S else Vector3.INF
	for i in BotTeam.spots_near(me, 140.0):
		var s: Dictionary = BotTeam.spots[i]
		if str(s.kind) != kind or recent.has(i):
			continue
		var p: Vector3 = s.p
		if last_p != Vector3.INF and p.distance_to(last_p) < HOLD_AWAY_M:
			continue
		if _inside_zone(p).distance_to(p) > 1.0 or BotTeam.claimed(i, ch.eid):
			continue
		var l: Array = BotTeam.lesson(p)
		# (r21) what the team learned of this very spot: held often, scored from, not died in; a spot the map
		# designates gets a little extra
		var sc = float(s.sight) * 0.05 + float(s.cover) * 0.6 + float(l[0]) * 1.5 + float(l[1]) * (3.0 if role == "sniper" else 0.5) \
			+ float(l[2]) * 0.4 - float(l[3]) * 1.2 - me.distance_to(p) * 0.03 + rng.randf_range(0.0, 2.5) \
			+ clampf(BotTeam.popularity(i), -4.0, 6.0) + (1.0 if str(s.get("src", "")) == "map" else 0.0) - float(s.get("expo", 0.5)) * 2.0
		if sc > bs:
			bs = sc
			best = i
	return best


func _start_hold(kind: String, secs: float) -> void:
	state = kind
	_hold_t = secs
	_hold_len = secs
	_hold_said = false
	goal = Vector3.INF
	var fv: Vector3 = (_look_at - ch.global_position) if _look_at != Vector3.INF else -Basis(Vector3.UP, yaw).z
	_hold_base_yaw = atan2(-fv.x, -fv.z)
	# r21: never hold a spot staring at a wall: the most open way near the one asked for (all round if need be)
	if _wall_close(_hold_base_yaw, 2.5):
		_hold_base_yaw = _open_yaw(_hold_base_yaw, PI)
		_look_at = Vector3.INF
	_safe_t = 0.0
	if _spot_i >= 0 and _spot_i < BotTeam.spots.size() and (BotTeam.spots[_spot_i].p as Vector3).distance_to(ch.global_position) < 3.5:
		BotTeam.spot_used(_spot_i)
	else:
		_spot_i = BotTeam.spot_at(ch.global_position, 2.5)
		if _spot_i >= 0:
			BotTeam.claim(_spot_i, ch.eid, secs + 5.0)
			BotTeam.spot_used(_spot_i)
	# r22: remembered (the next pick goes elsewhere), and logged
	var now_s := Time.get_ticks_msec() / 1000.0
	_last_hold_t = now_s
	_holds.append([_spot_i, ch.global_position, now_s])
	if _holds.size() > 8:
		_holds.pop_front()
	_sweeping = false
	if _logging():
		world.match_server.log_event("[hold] %s %s spot %d %.0fs%s" % [ch.pname, kind, _spot_i, secs, " (endgame)" if _end else ""])


func _hold_step(cmd: Dictionary, dt: float) -> void:
	## Camping a room or watching from a sniping spot: still, scanning a sector, scope up now and then.
	_hold_t -= dt
	if not _hold_said:
		_hold_said = true
		if rng.randf() < 0.6:
			say("in_position")
	cmd.my = 0.0
	cmd.mx = 0.0
	if _look_at != Vector3.INF:
		var fv = _look_at - ch.eye_position()
		_hold_base_yaw = lerp_angle(_hold_base_yaw, atan2(-fv.x, -fv.z), 0.08)
	var sweep := (0.35 if state == "overwatch" else 0.6) * sin(Time.get_ticks_msec() * 0.00045 + ch.eid)
	# (r21) in a corner the sweep swung the view onto the wall beside it: look round less there
	_sweep_t -= dt
	if _sweep_t <= 0.0:
		_sweep_t = 0.4
		_sweep_amp = maxf(_sweep_amp * 0.6, 0.1) if _wall_close(yaw, 1.5) else minf(_sweep_amp + 0.1, 1.0)
	sweep *= _sweep_amp
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
		if not _holds.is_empty():
			_holds[-1][2] = Time.get_ticks_msec() / 1000.0   # r22: held until now
		if _spot_i >= 0:
			BotTeam.spot_used(_spot_i, _hold_len - maxf(_hold_t, 0.0))
			BotTeam.release(ch.eid)
			_spot_i = -1
		if state == "camp":
			# Walk back out of the house.
			state = "roam"
			goal = Vector3.INF
		else:
			state = "roam"
			_obj = Vector3.INF
			_obj_t = 0.0


# ------------------------------------------------------------------ r22: the endgame

func _logging() -> bool:
	return world.match_server != null and bool(world.match_server._log_on)


func _endgame_eval() -> void:
	## Deathmatch, every think: endgame pressure when a side is down to a few standing (rounds without respawns), or this
	## team has not seen or been hit by an enemy for a while. A hold under way is cut to the endgame's length; after a
	## long quiet the team is given a rough idea of the nearest enemy (as a teammate's callout).
	if world.match_server == null:
		_end = false
		return
	var c := BotTeam.counts(ch.team)
	var by_count: bool = not world.match_server.respawns() and (int(c.mates) <= _sk_end_alive or int(c.foes) <= _sk_end_alive)
	var on: bool = by_count or float(c.quiet_s) >= _sk_end_contact
	BotTeam.note_endgame(ch.team, on, c)
	if not on and _sweeping:
		_sweeping = false
		BotTeam.sweep_done(ch.team, ch.eid)
	_end = on
	if not on:
		return
	if state in ["camp", "overwatch"] and _hold_t > 0.0:
		var cap := _sk_end_watch if state == "overwatch" else _sk_end_camp
		_hold_t = minf(_hold_t, maxf(cap - (_hold_len - _hold_t), 0.0))
	var h := BotTeam.hint(ch.team, _sk_end_hint, rng)
	if h != Vector3.INF:
		BotTeam.board(ch.team).set_var(&"intel", {"p": h, "t": Time.get_ticks_msec()})


func _hold_ok() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _last_hold_t >= _sk_end_gap


func _zone_ok(p: Vector3) -> bool:
	return _inside_zone(p).distance_to(p) <= 1.0


func _foe_side() -> Vector3:
	## The middle of the other teams' spawns (where to lean a sweep with no word of anyone), or INF.
	var ms = world.match_server
	if ms == null or ms.spawn_info.is_empty():
		return Vector3.INF
	var sum := Vector3.ZERO
	var n := 0
	for t in ms.spawn_info:
		if t is int and t != ch.team:
			sum += ms.spawn_info[t].anchor as Vector3
			n += 1
	return sum / n if n > 0 else Vector3.INF


func _sweep() -> void:
	## A sweep leg: to a waypoint in the stalest cell of the map nobody else of the team is sweeping (BotTeam.sweep_pick),
	## by the walk. Nowhere stale: hunt as the role would.
	var lean := _intel()
	if lean == Vector3.INF:
		lean = _foe_side()
	var pk := BotTeam.sweep_pick(ch.team, ch.eid, ch.global_position, lean, rng, _zone_ok)
	if pk.is_empty():
		_hunt_target(role == "rusher")
		return
	var sp := int(pk.i)
	_obj = BotTeam.spots[sp].p
	_look_at = Vector3.INF
	BotTeam.release(ch.eid)
	BotTeam.claim(sp, ch.eid, 90.0)
	_spot_i = sp
	_set_goal(_obj)
	state = "hunt"
	_sweeping = true
	var d: float = ch.global_position.distance_to(_obj)
	_obj_t = clampf(d / 4.0 + 10.0, 15.0, 90.0)
	var now_s := Time.get_ticks_msec() / 1000.0
	if _logging() and now_s - _sweep_log_t > 10.0:
		_sweep_log_t = now_s
		world.match_server.log_event("[sweep] %s -> cell %s spot %d stale %.0fs %.0f m" % [ch.pname, str(pk.cell), sp, float(pk.stale), d])


func _follow_step(cmd: Dictionary, dt: float) -> void:
	## Behind and to one side of the leader, matching its pace; when it stops, cover a different angle.
	var le = _leader()
	if le == null:
		state = "roam"
		return
	var lp: Vector3 = le.global_position
	var spot := _follow_slot(le, dt)
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
		# r21: covering an angle means looking down open floor, not at the wall beside the leader
		_idle_t -= dt
		if _idle_t <= 0.0 or _idle_yaw == INF:
			_idle_t = 1.5
			_idle_yaw = _open_yaw(face, 1.4) if _wall_close(face, 3.0) else face
		face = _idle_yaw
		cmd.yaw = lerp_angle(yaw, face, 0.08)
		cmd.pitch = lerpf(pitch, 0.0, 0.1)
		if (le.flags & Character.F_CROUCH) != 0:
			cmd.btn |= Motor.B_CROUCH


func _follow_slot(le, dt: float) -> Vector3:
	## r21: this bot's place by the leader: its own offset behind and to one side when that is open floor the leader
	## could walk to in a straight line; else the mirror of it, or straight behind, or the leader's own spot. (A slot
	## inside a wall used to leave the follower standing against that wall.)
	_slot_t -= dt
	if _slot_t > 0.0 and _slot != Vector3.INF and _slot.distance_to(le.global_position) < 7.0:
		return _slot
	_slot_t = 0.8
	var lp: Vector3 = le.global_position
	var lb := Basis(Vector3.UP, le.yaw)
	for o in [_follow_off, Vector3(-_follow_off.x, 0, _follow_off.z), Vector3(0, 0, 3.0), Vector3(_follow_off.x * 0.5, 0, 1.8)]:
		var q: Vector3 = lp + lb * o
		if nav.walkable_at(q) and nav.line_clear(lp, q):
			_slot = q
			return q
	_slot = lp
	return lp


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
	# r12: the field crushes whoever it catches against a wall, so leave with room to spare, and indoors much sooner
	# (out by the door first: inside, every wall between you and the centre is a wall to be crushed on).
	var need := to_safe / 5.2 * 1.7
	var margin := lerpf(60.0, 25.0, clampf(patience, 0.0, 1.0)) * 0.5 + 25.0
	if world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5) != 0:
		margin += 35.0
	if need + margin > t_left:
		out.go = true
	# Already close to the moving edge: go now, at a run.
	if st == "shrink" and p2.distance_to(c_now) > r_now - 12.0:
		out.go = true
		out.urgent = true
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
	# r13: a teammate's laser: look at what it points at; near it (and not camping or sniping), go and check it. At most
	# two bots answer the same spot; the others just look.
	_look_at = dot
	var near = ch.global_position.distance_to(dot) < 45.0
	if near and state not in ["camp", "overwatch", "fight"] and dot.distance_to(ch.global_position) > 4.0 			and not (str(order.get("kind", "")) == "check" and (order.p as Vector3).distance_to(dot) < 5.0) 			and BotTeam.laser_claim(holder.eid, dot, ch.eid):
		take_order("check", holder, dot)
		if rng.randf() < 0.6:
			reply("affirmative", 0)


# ------------------------------------------------------------------ r13: orders (voice commands, lasers) and replies

var order: Dictionary = {}     # {kind: help|go|fall_back|check, p, from (eid), t, arrived, t_arr}: what this bot agreed to do
var _replies_q: Array = []     # [msec, line]: answers said a moment later, so several bots can answer one call
var _help_t := -99.0           # last time this bot called for help
var _hold_said := false        # said "in position" for the current hold
const ORDER_HOLD := {"help": 25.0, "go": 20.0, "fall_back": 15.0, "check": 5.0}
const ORDER_GIVE_UP := 75.0    # seconds to get there before the order lapses


func can_take(kind: String) -> bool:
	## Whether this bot can do it now: on its feet, not in a close fight (falling back is always possible), and for a
	## check not holding a camping or sniping spot.
	if ch.mode != Motor.GROUND or ch.health.dead:
		return false
	if target_eid >= 0 and kind != "fall_back":
		var tc = world.characters.get(target_eid)
		if tc != null and (tc.global_position as Vector3).distance_to(ch.global_position) < 40.0:
			return false
	if kind == "check" and state in ["camp", "overwatch"]:
		return false
	return true


func take_order(kind: String, from_ch, p: Vector3) -> void:
	order = {"kind": kind, "p": p, "from": int(from_ch.eid) if from_ch else -1, "t": Time.get_ticks_msec() / 1000.0, "arrived": false, "t_arr": 0.0}
	_ping = {}
	if _exiting():
		return   # out of the house first; the order waits (state is chosen again when the way out is done)
	plan = []
	state = "order"
	_set_goal(p)
	_think_t = minf(_think_t, 0.05)


func reply(line: String, nth: int) -> void:
	_replies_q.append([Time.get_ticks_msec() + 350 + nth * 950 + rng.randi_range(0, 250), line])


func _replies() -> void:
	if _replies_q.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now >= int(_replies_q[0][0]):
		var r: Array = _replies_q.pop_front()
		var tries := int(r[2]) if r.size() > 2 else 0
		if not say(str(r[1]), true) and tries < 4 and ch.mode in [Motor.GROUND, Motor.DOWNED]:
			_replies_q.push_front([now + 450, r[1], tries + 1])   # the team radio was busy: a moment later


func _order_expired() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if bool(order.arrived):
		return now - float(order.t_arr) > float(ORDER_HOLD.get(str(order.kind), 15.0))
	if now - float(order.t) > ORDER_GIVE_UP:
		return true
	if str(order.kind) == "help":
		var src = world.characters.get(int(order.from))
		return src == null or src.mode in [Motor.DEAD, Motor.SPECTATE]
	return false


func _order_step(cmd: Dictionary, dt: float) -> void:
	## Going where it was asked, at a run; once there, says so and holds a while, watching.
	if order.is_empty():
		state = "roam"
		return
	var p: Vector3 = order.p
	if str(order.kind) == "help":
		var src = world.characters.get(int(order.from))
		if src != null and (src.global_position as Vector3).distance_to(p) > 4.0:
			p = src.global_position
			order.p = p
			_set_goal(p)
			# (r23) the teammate moved on: after it again (a helper that had got there stood where it was)
			if bool(order.arrived):
				order.arrived = false
				order.said = true
	var flat := Vector2(p.x - ch.global_position.x, p.z - ch.global_position.z).length()
	var reach := {"help": 6.0, "go": 4.0, "fall_back": 4.0, "check": 3.5}.get(str(order.kind), 4.0)
	# There, or at the end of the path to the nearest reachable point (the spot itself may be on a wall or a roof).
	var path_done := (path_i >= path.size() and not path.is_empty() and goal != Vector3.INF 		and Vector2(goal.x - ch.global_position.x, goal.z - ch.global_position.z).length() < 1.5) \
		or (goal == Vector3.INF and _ended_short)   # (r23) the route ended at the waypoint nearest the spot: as near as it gets
	# (r15) On a storeyed map the spot must be on this floor too (a point straight above is not "there"); (r21) and
	# not half way up the stairs to it (Freight Delight's floors are 3.2 m apart: 2.5 m let a bot stop mid-flight).
	var vy := absf(p.y - ch.global_position.y) if world.map.layout.has_method("level_of") else 0.0
	if not bool(order.arrived) and vy < 0.6 and (flat < reach or (path_done and flat < 12.0)):
		order.arrived = true
		order.t_arr = Time.get_ticks_msec() / 1000.0
		goal = Vector3.INF
		if not bool(order.get("said", false)):
			say("clear" if str(order.kind) == "check" else "in_position", true)
		var src2 = world.characters.get(int(order.from))
		_hold_base_yaw = src2.yaw if src2 != null else yaw
		if _wall_close(_hold_base_yaw, 2.5):
			_hold_base_yaw = _open_yaw(_hold_base_yaw, PI)   # (r21) not facing a wall where it was sent
	if bool(order.arrived):
		# Hold here: still, scanning round the way the caller faces (or the checked spot).
		cmd.my = 0.0
		cmd.mx = 0.0
		var sweep := 0.9 * sin(Time.get_ticks_msec() * 0.0006 + ch.eid)
		cmd.yaw = lerp_angle(yaw, _hold_base_yaw + sweep, 0.06)
		cmd.pitch = lerpf(pitch, -0.03, 0.05)
		return
	if goal == Vector3.INF:
		_set_goal(p)
	_move(cmd, dt, false)


func on_damaged(attacker: int) -> void:
	_hit_t = Time.get_ticks_msec() / 1000.0
	var a = world.characters.get(attacker)
	if a == null or a == ch:
		return
	if a.team != ch.team:
		BotTeam.contact(ch.team)   # r22: the endgame clock
	if target_eid < 0:
		# Shot by someone unseen: toward where it came from, roughly.
		investigate = (a.global_position as Vector3) + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
		_look_at = a.global_position
		reaction = minf(reaction, _sk_hurt)
	# r13: hurt badly in a fight: call for help (teammates nearby answer and come); otherwise just say so. (A hit that
	# killed says nothing.)
	if ch.health.dead or ch.health.health <= 0.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if ch.health.health < 45.0 and ch.health.health > 0.0 and not ch.health.dead and now - _help_t > 25.0 and ch.mode == Motor.GROUND:
		_help_t = now
		say("need_help", true)
		BotTeam.on_voice(ch, "need_help", ch.global_position)
	else:
		say("taking_fire", true)


func on_scored(victim, dist: float, headshot: bool = false) -> void:
	reply("headshot_kill" if headshot else "kill", 0)
	if dist > 45.0 and rng.randf() < 0.5:
		say("good_spot")


static func radio_sid(line: String, voice: String, k: int) -> String:
	## The sound for phrasing k of line in voice: the user's recording when there is one, else the spoken voice.
	if recorded.has(line):
		return "vox_%s_%d" % [str(recorded[line].name), k % maxi(int(recorded[line].n), 1)]
	return "botr_%s_%s_%d" % [line, voice, k]


# r13: lines about something that just happened (a kill, a teammate down, an answer to an order): never held back by
# this bot's own last callout, only spaced on the team radio.
const EVENT_LINES := ["kill", "headshot_kill", "down", "affirmative", "negative", "in_position", "clear", "need_help"]


func say(line: String, priority: bool = false) -> bool:
	## A callout on the team radio (rate-limited per bot and per team so the radio does not turn into a chorus).
	## False when it was not said (rate-limited or not a line).
	if not lines.has(line) or ch.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
		return false
	var now := Time.get_ticks_msec()
	if now - _say_t < (0 if line in EVENT_LINES else (2500 if priority else 9000)):
		return false
	if not BotTeam.can_talk(ch.team, priority):
		return false
	_say_t = now
	var k := rng.randi_range(0, (lines[line] as Array).size() - 1)
	if recorded.has(line):
		k = rng.randi_range(0, int(recorded[line].n) - 1)
	BotTeam.stats.lines += 1
	world.server_bot_radio(ch, line, voice, k)
	return true
