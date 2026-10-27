extends RefCounted
## A server-side bot that plays through the same command interface as a human (it cannot cheat movement or aim
## through walls; it only presses virtual buttons). States: deploy, loot, roam, investigate, fight, heal, zone.
##
## Perception is darkness-aware: a player is seen within ~14 m in the dark, ~30 m in moonlight on open ground,
## and up to 70 m when their flashlight is on or they just fired. Gunshots and nearby running are heard.

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


func _init(w, c) -> void:
	world = w
	ch = c
	rng.seed = hash(c.eid * 7919 + Game.match_seed)
	if nav == null or nav.layout != world.map.layout:
		nav = NavGrid.new(world.map.layout)
	if _index_layout != world.map.layout:
		_build_index()
	_pick_landing()


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
	_think_t -= dt
	if _think_t <= 0.0:
		_think_t = 0.25
		_perceive()
		_choose_state()
	match state:
		"fight":
			_fight(cmd, dt)
		"heal":
			cmd.btn |= Motor.B_HEAL if ch.health.treatment.is_empty() and rng.randf() < 0.2 else 0
			_move(cmd, dt, true)
		"fetch":
			_fetch_step(cmd, dt)
		_:
			if _detour >= 0:
				_detour_step(cmd, dt)
			else:
				_move(cmd, dt, false)
			_loot_actions(cmd, dt)
	_lights(cmd)
	yaw = float(cmd.yaw)
	pitch = float(cmd.pitch)
	_trace(cmd, dt)
	return cmd


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
	for o in world.characters.values():
		if o == ch or o.team == ch.team or o.mode not in [Motor.GROUND, Motor.DOWNED, Motor.CHUTE]:
			continue
		var d: float = o.global_position.distance_to(ch.global_position)
		var lit: bool = (o.flags & Character.F_LIGHT) != 0 or (o.flags & Character.F_FIRED) != 0
		var vis_range := 70.0 if lit else (30.0 if world.map.acoustics.zone_at(o.global_position) == 0 else 12.0)
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
	target_eid = best
	if best >= 0:
		last_seen = world.characters[best].global_position


func _choose_state() -> void:
	var h = ch.health
	if target_eid >= 0:
		state = "fight"
		return
	if h.bleeding_level() > 0 or (h.health < 60.0 and ch.inv.count("first_aid") > 0):
		state = "heal"
		return
	var circ: Array = world.zone_circle(float(Net.tick))
	var p2 := Vector2(ch.global_position.x, ch.global_position.z)
	var zone: Dictionary = world.match_info.get("zone", {})
	if p2.distance_to(circ[0]) > float(circ[1]) * 0.92 or (not zone.is_empty() and int(zone.get("i", -1)) >= 0 and p2.distance_to(zone.c1) > float(zone.r1)):
		if state != "zone":
			var c: Vector2 = zone.get("c1", circ[0])
			_set_goal(Vector3(c.x, 0, c.y) + Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30)))
		state = "zone"
		return
	if investigate != Vector3.INF:
		if state != "investigate":
			_set_goal(investigate)
		state = "investigate"
		if ch.global_position.distance_to(investigate) < 4.0:
			investigate = Vector3.INF
		return
	if state == "fetch" and not _fetch.is_empty():
		return
	if state == "loot" and plan_i < plan.size():
		return
	if _pick_fetch():
		return
	if state == "roam" and goal != Vector3.INF and path_i < path.size():
		return
	_pick_loot_goal()


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
	plan.append({"p": inside, "nav": false})
	plan.append({"p": centre + out_dir * (1.4 + foot_of_steps), "nav": false})
	plan_i = 0
	_step_t = 0.0
	_best_d = INF
	_no_progress = 0.0
	_door_hold = 0.0
	_set_goal(plan[0].p)
	return true


func _set_goal(g: Vector3) -> void:
	goal = g
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
	var to = target - ch.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 0.6 and path_i >= path.size():
		goal = Vector3.INF
		return
	var want_yaw := atan2(-flat.x, -flat.y)
	cmd.yaw = lerp_angle(yaw, want_yaw, 0.2)
	cmd.pitch = lerpf(pitch, 0.0, 0.1)
	cmd.my = 1.0
	if not slow and state in ["zone", "investigate"] and rng.randf() < 0.9:
		cmd.btn |= Motor.B_SPRINT
	if slow:
		cmd.btn |= Motor.B_WALK
	# Stuck: jump, strafe, then give up on this goal.
	var moved = ch.global_position.distance_to(_last_pos)
	_last_pos = ch.global_position
	if moved < 0.5 * dt:
		_stuck_t += dt
	else:
		_stuck_t = maxf(_stuck_t - dt, 0.0)
	if _stuck_t > 0.8:
		cmd.btn |= Motor.B_JUMP if rng.randf() < 0.3 else 0
		cmd.mx = 1.0 if int(_stuck_t * 2.0) % 2 == 0 else -1.0
	if _stuck_t > 3.0:
		_stuck_t = 0.0
		goal = Vector3.INF
	_repath_t -= dt
	if _repath_t <= 0.0 and goal != Vector3.INF:
		_set_goal(goal)


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
		if rng.randf() < 0.08:
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
	var eye: Vector3 = ch.eye_position()
	var zone: int = world.map.acoustics.zone_at(ch.global_position + Vector3.UP * 0.5)
	var best := -1
	var bv := 0.6
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
	if moved < 0.3 * dt and _detour_t > 1.5:
		cmd.btn |= Motor.B_JUMP if rng.randf() < 0.1 else 0


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
	elif reaction <= 0.0 and absf(wrapf(want_yaw - yaw, -PI, PI)) < 0.12:
		_fire_hold -= dt
		if _fire_hold < 0.0:
			_fire_hold = rng.randf_range(0.2, 0.5)
		if _fire_hold > 0.1 or ch.wpn.fire_mode() != "auto":
			cmd.btn |= Motor.B_FIRE if rng.randf() < 0.85 else 0
	# Strafe a little while shooting.
	cmd.mx = sin(Time.get_ticks_msec() * 0.002 + ch.eid) * 0.8
	if d > 30.0:
		cmd.my = 0.6


func _lights(cmd: Dictionary) -> void:
	## Bots use their light indoors when nobody is around, and turn it off when fighting.
	var indoor: bool = world.map.acoustics.zone_at(ch.global_position) != 0
	var want = indoor and state in ["loot", "roam"] and ch.light.charge() > 0.1
	if want != ch.light.on and rng.randf() < 0.05:
		cmd.btn |= Motor.B_LIGHT  # a tap toggles (pressed this tick, released next)
