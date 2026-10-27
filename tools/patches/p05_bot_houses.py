"""Patch: bots search houses through their doors (plan of steps to every container on the floor), share a team
landing spot near the flight path, and follow a human teammate's jump instead of forcing it."""
G = 'A:/Python/aetherion-project/game/'
p = G + 'src/ai/bot_brain.gd'
s = open(p, encoding='utf-8').read()


def sub(old, new, cnt=1):
    global s
    assert s.count(old) == cnt, (s.count(old), old[:80])
    s = s.replace(old, new)


sub('''var _wander_t := 0.0
static var nav = null
''', '''var _wander_t := 0.0
## House search: a list of steps {p, nav, door, search} walked in order (outside the door, through it, to each
## container on that floor, and back out).
var plan: Array = []
var plan_i := 0
var _step_t := 0.0
var _door_hold := 0.0
var _searched := {}
static var nav = null
## Per-map lookups shared by every bot: building id -> outer doors / containers.
static var _index_layout = null
static var doors_by_bid := {}
static var conts_by_bid := {}
## Team landing spots for the current match: "seed:team" -> Vector3.
static var team_targets := {}
''')

sub('''	rng.seed = hash(c.eid * 7919 + Game.match_seed)
	if nav == null or nav.layout != world.map.layout:
		nav = NavGrid.new(world.map.layout)
	_pick_landing()


func _pick_landing() -> void:
	var bs: Array = world.map.buildings
	if bs.is_empty():
		_land_target = Vector3.ZERO
		return
	var b: Dictionary = bs[rng.randi_range(0, bs.size() - 1)]
	var o: Vector3 = (b.xf as Transform3D).origin
	_land_target = o + (b.xf as Transform3D).basis.z * -(float(b.d) * 0.5 + 2.0)


func wants_jump(plane_p: Vector3) -> bool:
	if _land_target == Vector3.INF:
		return true
	var d := Vector2(plane_p.x - _land_target.x, plane_p.z - _land_target.z).length()
	if _jump_at < 0.0:
		_jump_at = rng.randf_range(220.0, 380.0)
	return d < _jump_at
''', '''	rng.seed = hash(c.eid * 7919 + Game.match_seed)
	if nav == null or nav.layout != world.map.layout:
		nav = NavGrid.new(world.map.layout)
	if _index_layout != world.map.layout:
		_build_index()
	_pick_landing()


func _build_index() -> void:
	_index_layout = world.map.layout
	doors_by_bid = {}
	conts_by_bid = {}
	team_targets = {}
	for d in world.map.dyn.doors:
		if d.get("outer", false) and d.has("bid") and d.has("outward"):
			if not doors_by_bid.has(d.bid):
				doors_by_bid[d.bid] = []
			doors_by_bid[d.bid].append(d)
	for c in world.map.dyn.containers:
		if int(c.bid) < 0:
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
			spot = p + side * rng.randf_range(-160.0, 160.0)
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
''')

sub('''func _deploy(cmd: Dictionary, dt: float) -> Dictionary:
	var to = _land_target - ch.global_position''', '''func _deploy(cmd: Dictionary, dt: float) -> Dictionary:
	var hm = _human_mate()
	if hm != null and hm.mode in [Motor.FREEFALL, Motor.CHUTE, Motor.GROUND]:
		# Follow the human's lead, keeping a few metres of formation offset.
		var off := Vector3(cos(ch.eid * 2.1), 0, sin(ch.eid * 2.1)) * 9.0
		_land_target = hm.global_position + off + Vector3(hm.velocity.x, 0, hm.velocity.z) * 2.0
	var to = _land_target - ch.global_position''')

sub('''	if state not in ["loot", "roam"] or goal == Vector3.INF or path_i >= path.size():
		_pick_loot_goal()


func _pick_loot_goal() -> void:
	# Nearest unvisited house front within 60 m; otherwise wander toward the zone centre.
	var best := Vector3.INF
	var bd := INF
	for b in world.map.buildings:
		var o: Vector3 = (b.xf as Transform3D).origin
		var d := o.distance_to(ch.global_position)
		if d > 70.0 or _visited.has(b.id):
			continue
		d += rng.randf_range(0.0, 15.0)
		if d < bd:
			bd = d
			best = o + (b.xf as Transform3D).basis.z * -(float(b.d) * 0.5 - 0.8)
			_visited[b.id] = true
	if best != Vector3.INF:
		state = "loot"
		_set_goal(best)
	else:
		state = "roam"
		var circ: Array = world.zone_circle(float(Net.tick))
		var c: Vector2 = circ[0]
		_set_goal(Vector3(c.x + rng.randf_range(-80, 80), 0, c.y + rng.randf_range(-80, 80)))
''', '''	if state == "loot" and plan_i < plan.size():
		return
	if state == "roam" and goal != Vector3.INF and path_i < path.size():
		return
	_pick_loot_goal()


func _pick_loot_goal() -> void:
	# Nearest unvisited house with loot within 80 m; otherwise wander toward the zone centre.
	var best = null
	var bd := INF
	for b in world.map.buildings:
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
	plan = [{"p": centre + out_dir * 1.4, "nav": true}, {"p": inside, "nav": false, "door": int(door.id)}]
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
	plan.append({"p": centre + out_dir * 1.6, "nav": false})
	plan_i = 0
	_step_t = 0.0
	_set_goal(plan[0].p)
	return true
''')

sub('''func _move(cmd: Dictionary, dt: float, slow: bool) -> void:
	if goal == Vector3.INF:
		return
	var target := goal
	if path_i < path.size():''', '''func _move(cmd: Dictionary, dt: float, slow: bool) -> void:
	if state == "loot" and plan_i < plan.size():
		_plan_step(cmd, dt)
		return
	if goal == Vector3.INF:
		return
	var target := goal
	if path_i < path.size():''')

sub('''func _loot_actions(cmd: Dictionary, dt: float) -> void:''', '''func _plan_step(cmd: Dictionary, dt: float) -> void:
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
	var arrived := flat.length() < reach and (not step.nav or path_i >= path.size())
	if step.has("search") and flat.length() < 1.3:
		arrived = true
	if arrived or _step_t > (40.0 if step.nav else 9.0):
		if arrived and step.has("search"):
			if not _search(cmd, int(step.search)):
				return
		plan_i += 1
		_step_t = 0.0
		_stuck_t = 0.0
		if plan_i < plan.size() and plan[plan_i].nav:
			_set_goal(plan[plan_i].p)
		return
	# A closed door on the way in: face it and press Use; hold Use to force a locked one.
	if step.has("door") and flat.length() < 2.2:
		var dn = world.map.dyn.doors[int(step.door)].get("node")
		if dn and absf(dn.target) < 0.05:
			var dc: Vector3 = dn.center()
			var tv: Vector3 = dc - ch.eye_position()
			cmd.yaw = atan2(-tv.x, -tv.z)
			cmd.pitch = atan2(tv.y, Vector2(tv.x, tv.z).length())
			_door_hold += dt
			if _door_hold < 3.5:
				cmd.btn |= Motor.B_USE
			if int(Time.get_ticks_msec() / 400) % 3 == 0 and not dn.locked:
				cmd.btn &= ~Motor.B_USE  # release now and then so a plain door gets a fresh press
			return
	_door_hold = 0.0
	var want_yaw := atan2(-flat.x, -flat.y)
	cmd.yaw = lerp_angle(yaw, want_yaw, 0.25)
	cmd.pitch = lerpf(pitch, 0.0, 0.1)
	cmd.my = 1.0 if flat.length() > 0.8 else 0.5
	if not step.nav:
		cmd.btn |= Motor.B_WALK
	var moved = ch.global_position.distance_to(_last_pos)
	_last_pos = ch.global_position
	_stuck_t = _stuck_t + dt if moved < 0.4 * dt else maxf(_stuck_t - dt, 0.0)
	if _stuck_t > 0.8:
		cmd.mx = 1.0 if int(_stuck_t * 2.0) % 2 == 0 else -1.0
		if rng.randf() < 0.1:
			cmd.btn |= Motor.B_JUMP
	if _stuck_t > 3.5:
		_stuck_t = 0.0
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


func _loot_actions(cmd: Dictionary, dt: float) -> void:''')

open(p, 'w', encoding='utf-8').write(s)
print('patched', p)
