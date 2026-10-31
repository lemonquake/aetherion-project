extends RefCounted
## r15 checks on Malasugue Mall, on a listen host (`--autotest=mall`, `--mall_only=build,ride_up,ride_down,stairs,
## glass,door,bot,parachute,views`):
##   godot --path game -- --host --game_mode=deathmatch --map=malasugue_mall --bots=20 --autostart=1 --autotest=mall --shots=<dir>
## build: the plan made it into the world (units, glass, doors, escalators, walk graph). ride_up / ride_down: standing
## still on an escalator carries the player up (down) a whole storey. stairs: walking up a fire-stair flight climbs
## half a storey. glass: a round through a shopfront pane breaks it (and the way through opens). door: a round through
## a glass door bursts the whole leaf. bot: a bot ordered from Level 1 to Level 5 gets there (escalators / stairs).
## views: captures on every level. Measurements go to <shots>/mall_measure.json.
## (r16) dept: walking up the department store's stopped escalators climbs Level 1 -> 2 -> 3. dark: the frames on
## every level are dark with lit pools (mean brightness, the share of near-black and of lit pixels). flicker: the
## floor under a faulty fitting changes brightness over a few seconds, under a working one it holds. restroom: the
## Level 3 restrooms are there (captures). dept_bot: a bot ordered from the store's Level 1 to its Level 3.

var t = null
var world = null
var measure := {}
var _frozen := {}


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("mall_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	if "parachute" in only:
		await _parachute()
		return
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 60.0)
	await t._wait(1.0)
	world.map.lighting.forced_time = 450.0
	_freeze_zone()
	_freeze_bots(true)
	t.ch.health.test_invulnerable = true
	for n in ["build", "touch", "ride_up", "ride_down", "stairs", "glass", "door", "views", "dept", "dark", "flicker", "restroom", "perf", "bot", "dept_bot"]:
		if want.call(n) and is_instance_valid(t.ch):
			await (Callable(self, "_" + n)).call()
	var f := FileAccess.open(t.out_dir + "/mall_measure.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


func _freeze_zone() -> void:
	var ms = world.match_server
	if ms and not ms.zone.is_empty():
		ms.zone = {"i": 0, "state": "wait", "t0": Net.tick, "t1": Net.tick + 100000000, "c0": Vector2.ZERO, "r0": 9000.0, "c1": Vector2.ZERO,
			"r1": 9000.0, "dps": 0.0, "shrink_s": 60.0}
		ms._broadcast()


func _freeze_bots(on: bool) -> void:
	if on:
		for eid in world.bots.keys():
			_frozen[eid] = world.bots[eid]
			world.bots.erase(eid)
			world._bot_dt.erase(eid)
			world._queues[eid] = []
			if world.characters.has(eid):
				world.characters[eid].last_cmd = {}
	else:
		for eid in _frozen:
			if world.characters.has(eid) and is_instance_valid(world.characters[eid]):
				world._queues[eid] = []
				world.bots[eid] = _frozen[eid]
		_frozen.clear()


func _L():
	return world.map.layout


func _park_enemies(team: int, x: float) -> void:
	## (r17) Teams now start on Levels 1, 3 and 5 (the Level 1 one on the north-west concourse, in sight of the West
	## Court): the frozen enemies wait out on the plaza at the other end, out of a test bot's sight, as they did in the
## entrance halls.
	var i := 0
	for k in _frozen:
		var c = world.characters.get(k)
		if c and c.team != team:
			c.global_position = Vector3(x + (i % 3) * 1.6 * signf(x), 0.05, 40.0 + (i / 3) * 1.6)
			c.velocity = Vector3.ZERO
			i += 1


func _build() -> void:
	var L = _L()
	var plates := 0
	for w in world.map.dyn.windows:
		if str(w.type) == "plate":
			plates += 1
	var glass_doors := 0
	for d in world.map.dyn.doors:
		if d.get("glass", false):
			glass_doors += 1
	var esc := 0
	for c in world.map.root.get_children():
		if str(c.name).begins_with("Escalator_"):
			esc += 1
	measure.build = {"units": L.units.size(), "plates": plates, "glass_doors": glass_doors, "escalators": esc, "levels": L.LEVELS,
		"fingerprint": world.map.fingerprint, "stats": world.map.stats.get("mall", {})}
	t._check("mall_build", L.units.size() >= 100 and plates >= 600 and glass_doors >= 150 and esc == 16 and L.LEVELS == 5,
		"%d units, %d plate-glass sheets, %d glass doors, %d escalators, %d levels" % [L.units.size(), plates, glass_doors, esc, L.LEVELS])


func _escalator(bank: String, t_: int, up: bool) -> Dictionary:
	for e in _L().escalators:
		if str(e.bank) == bank and int(e.t) == t_ and bool(e.up) == up:
			return e
	return {}


func _ride(e: Dictionary, name: String) -> void:
	## Stand on the boarding landing of escalator e with no input and see where it carries the player.
	var L = _L()
	var a: Vector3 = e.a
	var b: Vector3 = e.b
	var sx := signf(b.x - a.x)
	var start: Vector3 = (Vector3(a.x - sx * 0.5, a.y + 0.05, a.z)) if bool(e.up) else (Vector3(b.x + sx * 0.5, b.y + 0.05, b.z))
	var end_y: float = b.y if bool(e.up) else a.y
	t._teleport(start, atan2(-sx, 0.0) if bool(e.up) else atan2(sx, 0.0))
	await t._wait(0.3)
	var y0: float = t.ch.global_position.y
	var t0 := Time.get_ticks_msec()
	var past_x: float = b.x if bool(e.up) else a.x
	var way := sx if bool(e.up) else -sx
	var ok = await t._until(func(): return absf(t.ch.global_position.y - end_y) < 0.25 and (t.ch.global_position.x - past_x) * way > 0.2, 25.0)
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	await t._wait(0.2)
	var p: Vector3 = t.ch.global_position
	measure[name] = {"from": [start.x, start.y, start.z], "to": [p.x, p.y, p.z], "seconds": secs}
	t._check("mall_" + name, ok, "%s escalator %s: y %.2f -> %.2f in %.1f s standing still (want %.1f)" % [str(e.bank), "up" if bool(e.up) else "down", y0, p.y, secs, end_y])
	await t._shot(name)


func _ride_up() -> void:
	await _ride(_escalator("Grand Atrium", 0, true), "ride_up")


func _ride_down() -> void:
	await _ride(_escalator("West Court", 1, false), "ride_down")


func _stairs() -> void:
	## The north-west core: from the landing by the door, walk the first flight up to the half landing.
	var L = _L()
	var f: Dictionary = {}
	for fl in L.flights:
		if int(fl.core) == 0 and int(fl.level) == 0 and int(fl.half) == 0:
			f = fl
	var foot: Vector3 = f.foot
	var top: Vector3 = f.top
	var dz := signf(top.z - foot.z)
	t._teleport(Vector3(foot.x, 0.05, foot.z - dz * 0.8), atan2(0.0, -dz))
	await t._wait(0.3)
	t._act("move_forward", true)
	var ok = await t._until(func(): return t.ch.global_position.y > top.y - 0.15, 8.0)
	t._act("move_forward", false)
	await t._wait(0.3)
	var p: Vector3 = t.ch.global_position
	measure.stairs = {"y": p.y, "want": top.y}
	t._check("mall_stairs", ok, "fire stair: walked up to y %.2f (half landing %.2f)" % [p.y, top.y])
	await t._shot("stairs")


func _nearest_plate(p: Vector3, max_d: float = 30.0) -> Dictionary:
	var best := {}
	var bd := max_d
	for w in world.map.dyn.windows:
		if str(w.type) != "plate" or w.get("broken", false) or float(w.h) < 2.0:
			continue
		var d := (w.xf as Transform3D).origin.distance_to(p)
		if d < bd:
			bd = d
			best = w
	return best


func _fire_at(target: Vector3, secs: float = 0.25) -> void:
	t._look_at(target)
	await t._wait(0.2)
	t._act("fire", true)
	await t._wait(secs)
	t._act("fire", false)
	await t._wait(0.5)


func _glass() -> void:
	## A shopfront pane on Level 1: stand 4 m out in the walk, shoot its middle.
	var w := _nearest_plate(Vector3(-25, 1.6, -34.5))
	if w.is_empty():
		t._check("mall_glass", false, "no shopfront pane found")
		return
	var xf: Transform3D = w.xf
	var n := xf.basis.z.normalized()
	var stand := xf.origin + n * 4.0
	if world.map.layout.inside(Vector2(stand.x, stand.z), 0.6) == false or absf(stand.z) > 35.0 and absf(xf.origin.z) >= 35.0 and absf(stand.z) > absf(xf.origin.z):
		stand = xf.origin - n * 4.0
	t._teleport(Vector3(stand.x, world.map.layout.level_y(world.map.layout.level_of(xf.origin.y - 1.0)) + 0.05, stand.z), 0.0)
	await t._wait(0.4)
	await t._shot("glass_before")
	await _fire_at(xf.origin)
	var broke: bool = w.get("broken", false)
	measure.glass = {"window": int(w.id), "w": float(w.w), "h": float(w.h), "broken": broke}
	t._check("mall_glass", broke, "shopfront pane %d (%.1f x %.1f m): %s" % [int(w.id), float(w.w), float(w.h), "shattered" if broke else "still standing"])
	await t._wait(0.3)
	await t._shot("glass_after")


func _door() -> void:
	## A glass shop door on Level 1, shot.
	var best = null
	var bd := 1e9
	for d in world.map.dyn.doors:
		if not d.get("glass", false) or d.get("node") == null or d.node.destroyed:
			continue
		var o: Vector3 = (d.xf as Transform3D).origin
		if absf(o.y) > 0.5:
			continue
		var dd := o.distance_to(t.ch.global_position)
		if dd < bd:
			bd = dd
			best = d
	if best == null:
		t._check("mall_glass_door", false, "no glass door found")
		return
	var node = best.node
	var c: Vector3 = node.center()
	var n: Vector3 = (best.xf as Transform3D).basis.z.normalized()
	var stand := c + n * 3.5
	if not world.map.layout.inside(Vector2(stand.x, stand.z), 0.6) or absf(stand.z) > 34.0 and absf(c.z) > 34.0:
		stand = c - n * 3.5
	t._teleport(Vector3(stand.x, 0.05, stand.z), 0.0)
	await t._wait(0.4)
	await t._shot("door_before")
	await _fire_at(c)
	measure.door = {"door": int(best.id), "destroyed": node.destroyed}
	t._check("mall_glass_door", node.destroyed, "glass door %d: %s" % [int(best.id), "burst" if node.destroyed else "still there"])
	await t._wait(0.3)
	await t._shot("door_after")


func _views() -> void:
	## One look across each level from the north walk toward the Grand Atrium (and the top of the escalators).
	var L = _L()
	for lv in L.LEVELS:
		t._teleport(Vector3(-10.0, L.level_y(lv) + 0.05, -27.0), 0.0)
		t._look_at(Vector3(4.0, L.level_y(lv) + 1.2, 6.0))
		await t._wait(1.2)
		await t._shot("level%d" % (lv + 1))


func _bot() -> void:
	## One bot, alone (the others still frozen), ordered from the West entrance on Level 1 to the food hall on Level 5.
	var L = _L()
	var eid := -1
	for k in _frozen.keys():
		if world.characters.has(k) and world.characters[k].team == t.ch.team:
			eid = k
			break
	if eid < 0:
		t._check("mall_bot_climb", false, "no teammate bot")
		return
	var ch = world.characters[eid]
	var b = _frozen[eid]
	_park_enemies(ch.team, 80.0)
	ch.global_position = Vector3(-50.0, 0.05, 0.0)
	ch.velocity = Vector3.ZERO
	ch.health.test_invulnerable = true
	world._queues[eid] = []
	world.bots[eid] = b
	_frozen.erase(eid)
	var goal := Vector3(-6.0, L.level_y(4), -26.0)
	var p0: Vector3 = ch.global_position
	var max_y := 0.0
	var t0 := Time.get_ticks_msec()
	var trail := []
	var ok := false
	while (Time.get_ticks_msec() - t0) < 150000:
		if b.order.is_empty() or b.state != "order":
			b.take_order("go", null, goal)
		await t._wait(0.5)
		var p: Vector3 = ch.global_position
		max_y = maxf(max_y, p.y)
		if trail.is_empty() or (trail[-1] as Vector3).distance_to(p) > 3.0:
			trail.append(p)
		if absf(p.y - goal.y) < 0.6 and Vector2(p.x - goal.x, p.z - goal.z).length() < 6.0:
			ok = true
			break
		if not is_instance_valid(ch) or ch.mode != Motor.GROUND:
			break
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var pe: Vector3 = ch.global_position
	measure.bot = {"from": [p0.x, p0.y, p0.z], "to": [pe.x, pe.y, pe.z], "seconds": secs, "max_y": max_y,
		"trail": trail.map(func(q): return [snappedf(q.x, 0.1), snappedf(q.y, 0.1), snappedf(q.z, 0.1)])}
	t._check("mall_bot_climb", ok, "bot from L1 (%.0f, %.0f) to the L5 food hall: reached %s in %.0f s (highest y %.1f)" % [p0.x, p0.z, str(pe.round()), secs, max_y])


func _dept() -> void:
	## Up the department store's two stopped escalators on foot: Level 1 -> 2 (rising toward +z), then 2 -> 3.
	var L = _L()
	var ok_all := true
	var res := []
	for e in L.DEPT_ESC:
		var tt := int(e.t)
		var dir := float(e.dir)
		var start := Vector3(float(e.x), L.level_y(tt) + 0.05, float(e.z0) - dir * 2.0)
		var want: float = L.level_y(tt + 1)
		t._teleport(start, 0.0 if dir < 0.0 else PI)
		await t._wait(0.4)
		t._act("move_forward", true)
		var t0 := Time.get_ticks_msec()
		var ok = await t._until(func(): return t.ch.global_position.y > want - 0.1, 14.0)
		await t._wait(0.4)
		t._act("move_forward", false)
		var p: Vector3 = t.ch.global_position
		res.append({"from": tt + 1, "to": tt + 2, "y": p.y, "seconds": (Time.get_ticks_msec() - t0) / 1000.0})
		ok_all = ok_all and bool(ok)
		t._check("mall_dept_stairs_L%d" % (tt + 2), ok, "stopped escalator Level %d -> %d: y %.2f (want %.1f) in %.1f s" % [tt + 1, tt + 2, p.y, want, res[-1].seconds])
		await t._shot("dept_esc_L%d" % (tt + 2))
	measure.dept = res


func _frame_stats() -> Dictionary:
	## Brightness over the view (the middle 80 %, clear of the HUD): mean, share of near-black pixels, share of lit.
	await RenderingServer.frame_post_draw
	var img: Image = t.get_viewport().get_texture().get_image()
	var sz := img.get_size()
	var c := img.get_region(Rect2i(sz.x / 10, sz.y / 10, sz.x * 4 / 5, sz.y * 4 / 5))
	c.resize(160, 90)
	var sum := 0.0
	var dark := 0
	var lit := 0
	for y in 90:
		for x in 160:
			var l := c.get_pixel(x, y).get_luminance() * 255.0
			sum += l
			dark += 1 if l < 22.0 else 0
			lit += 1 if l > 110.0 else 0
	return {"mean": sum / 14400.0, "dark": dark / 14400.0, "lit": lit / 14400.0}


func _dark() -> void:
	## Every level, looking along a walk: dark overall with pools of light (r15 frames were ~150 mean, no black).
	var L = _L()
	var spots := [[Vector3(-10.0, 0.05, -27.0), Vector3(4.0, 1.2, 6.0)], [Vector3(-30.0, 5.05, -30.0), Vector3(10.0, 6.4, -28.0)],
		[Vector3(32.0, 10.05, -12.0), Vector3(46.0, 10.5, 0.0)], [Vector3(20.0, 15.05, 30.0), Vector3(-20.0, 16.3, 30.0)],
		[Vector3(-6.0, 20.05, 26.0), Vector3(12.0, 21.0, 30.0)], [Vector3(59.0, 5.05, 30.0), Vector3(64.0, 6.2, -10.0)]]
	var rows := []
	var dark_views := 0
	var mean_sum := 0.0
	var lit_views := 0
	for i in spots.size():
		t._teleport(spots[i][0], 0.0)
		t._look_at(spots[i][1])
		await t._wait(1.0)
		var st: Dictionary = await _frame_stats()
		rows.append(st)
		mean_sum += float(st.mean)
		dark_views += 1 if float(st.dark) > 0.12 else 0
		lit_views += 1 if float(st.lit) > 0.005 else 0
		await t._shot("dark_%d" % i)
	measure.dark = rows
	var mean := mean_sum / spots.size()
	t._check("mall_dark", mean < 80.0 and dark_views >= 3 and lit_views >= 4,
		"mean brightness %.0f over %d views (want < 80), %d with >12%% near-black, %d with lit pools" % [mean, spots.size(), dark_views, lit_views])


func _flicker() -> void:
	## Under a faulty downlight on a walk, then under a working one: sample the floor's brightness for 4 s.
	var lt = world.map.lighting
	var faulty = null
	var steady = null
	for rec in lt.lamps:
		if str(rec.kind) != "down" or rec.light == null:
			continue
		var p: Vector3 = rec.pos
		if absf(p.y - 4.17) > 0.2:
			continue   # Level 1 walks only
		if faulty == null and str(rec.fault) in ["flicker", "starter"]:
			faulty = rec
		elif steady == null and str(rec.fault) == "" and float(rec.base) > 3.0:
			steady = rec
	if faulty == null or steady == null:
		t._check("mall_flicker", false, "no faulty / steady downlight found on Level 1")
		return
	var res := {}
	for pair in [["faulty", faulty], ["steady", steady]]:
		var p2: Vector3 = (pair[1] as Dictionary).pos
		t._teleport(Vector3(p2.x + 2.2, 0.05, p2.z + 2.2), 0.0)
		t._look_at(Vector3(p2.x, 0.0, p2.z))
		await t._wait(0.8)
		var lo := 999.0
		var hi := -1.0
		for k in 24:
			var l: float = await t._view_luma()
			lo = minf(lo, l)
			hi = maxf(hi, l)
			await t._wait(0.17)
		res[pair[0]] = {"min": lo, "max": hi, "fault": str((pair[1] as Dictionary).fault), "pos": [p2.x, p2.y, p2.z]}
	measure.flicker = res
	var sf: float = res.faulty.max - res.faulty.min
	var ss: float = res.steady.max - res.steady.min
	t._check("mall_flicker", sf > 6.0 and sf > ss * 3.0, "floor brightness under a %s downlight swings %.1f, under a working one %.1f" % [res.faulty.fault, sf, ss])


func _restroom() -> void:
	## Level 3's public restrooms: in the gents, then the ladies (the shut cubicle).
	var L = _L()
	var found := false
	for u in L.units:
		if str(u.kind) == "restroom" and int(u.level) == 2:
			found = true
	t._check("mall_restroom_L3", found, "Level 3 public restrooms in the plan: %s" % str(found))
	for v in [["restroom_gents", Vector3(-34.2, 10.05, -38.0), Vector3(-37.2, 11.0, -40.5)], ["restroom_ladies", Vector3(-40.0, 10.05, -38.6), Vector3(-42.4, 10.9, -44.2)],
			["restroom_front", Vector3(-36.0, 10.05, -29.5), Vector3(-37.5, 11.6, -35.0)]]:
		t._teleport(v[1], 0.0)
		t._look_at(v[2])
		await t._wait(1.0)
		await t._shot(v[0])


func _dept_bot() -> void:
	## A bot from the store's Level 1 to its Level 3 (only by its stopped escalators, or the long way round).
	var L = _L()
	var eid := -1
	for k in _frozen.keys():
		if world.characters.has(k) and world.characters[k].team == t.ch.team:
			eid = k
			break
	if eid < 0:
		return
	var ch = world.characters[eid]
	var b = _frozen[eid]
	_park_enemies(ch.team, -80.0)
	ch.global_position = Vector3(64.0, 0.05, 30.0)
	ch.velocity = Vector3.ZERO
	ch.health.test_invulnerable = true
	world._queues[eid] = []
	world.bots[eid] = b
	_frozen.erase(eid)
	var goal := Vector3(63.0, L.level_y(2), -30.0)
	var t0 := Time.get_ticks_msec()
	var ok := false
	var max_y := 0.0
	while (Time.get_ticks_msec() - t0) < 120000:
		if b.order.is_empty() or b.state != "order":
			b.take_order("go", null, goal)
		await t._wait(0.5)
		var p: Vector3 = ch.global_position
		max_y = maxf(max_y, p.y)
		if absf(p.y - goal.y) < 0.6 and Vector2(p.x - goal.x, p.z - goal.z).length() < 6.0:
			ok = true
			break
	var pe: Vector3 = ch.global_position
	measure.dept_bot = {"to": [pe.x, pe.y, pe.z], "seconds": (Time.get_ticks_msec() - t0) / 1000.0, "max_y": max_y}
	t._check("mall_dept_bot", ok, "bot from the store's Level 1 to its Level 3: reached %s in %.0f s" % [str(pe.round()), (Time.get_ticks_msec() - t0) / 1000.0])


func _parachute() -> void:
	## Classic (any map): out of the aircraft, a canopy cut high up drops the player 14 m at speed: the jump hurts no
	## one. A few seconds after that first touch-down the same drop hurts as any fall does.
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.PLANE, 40.0)
	await t._until(func(): return (Net.tick - int(world.match_server.plane.t0)) > int((float(world.match_server.plane.open_s) + 1.0) * Defs.TICK_RATE), 60.0)
	await t._hold("jump", 0.2)
	var out = await t._until(func(): return t.ch.mode in [Motor.FREEFALL, Motor.CHUTE], 20.0)
	t._check("chute_jumped", out, "mode %d" % t.ch.mode)
	await t._wait(1.0)
	var L = _L()
	var p: Vector3 = t.ch.global_position
	var spot := Vector2(p.x, p.z)
	for k in 40:
		if not L.is_water(spot.x, spot.y) and L.in_play_area(spot):
			break
		spot = spot.move_toward(Vector2.ZERO, 12.0)
	var gy: float = L.ground_height(spot.x, spot.y)
	world.server_set_mode(t.ch, Motor.GROUND)
	t.ch.global_position = Vector3(spot.x, gy + 14.0, spot.y)
	t.ch.velocity = Vector3(0, -20.0, 0)
	var h0: float = t.ch.health.health
	await t._until(func(): return t.ch.is_on_floor(), 6.0)
	await t._wait(1.0)
	var h1: float = t.ch.health.health
	t._check("chute_landing_safe", h1 >= h0 - 0.01, "a 14 m drop at 20 m/s right after the jump: health %.0f -> %.0f" % [h0, h1])
	await t._wait(5.0)
	var q: Vector3 = t.ch.global_position
	t.ch.global_position = q + Vector3(0, 14.0, 0)
	t.ch.velocity = Vector3(0, -12.0, 0)
	await t._wait(0.3)
	await t._until(func(): return t.ch.is_on_floor(), 6.0)
	await t._wait(1.0)
	var h2: float = t.ch.health.health
	t._check("later_fall_hurts", h2 < h1 - 1.0, "the same drop 6 s after landing: health %.0f -> %.0f" % [h1, h2])


func _touch() -> void:
	## Phones (--mobile): the on-screen stick runs at full speed from about 60 % of its ring and sprints when pushed
	## to the edge (it used to crawl at walking pace and never sprint). Measured on the Level 1 north walk.
	var ctl = t.ctl
	if ctl.touch == null:
		return
	var sz: Vector2 = t.get_viewport().get_visible_rect().size
	var k: float = ctl.touch._k()
	var stick := Vector2(sz.x * 0.16, sz.y * 0.72)
	var results := {}
	for pull in [0.7, 0.97]:
		t._teleport(Vector3(-40.0, 0.05, -30.0), -PI * 0.5)   # facing east along the walk
		await t._wait(0.6)
		t._touch(0, stick, true)
		await t._drag(0, stick, stick + Vector2(0, -ctl.touch.STICK_R * k * pull), 6)
		await t._wait(1.2)
		var p0: Vector3 = t.ch.global_position
		await t._wait(1.5)
		var v := Vector2(t.ch.global_position.x - p0.x, t.ch.global_position.z - p0.z).length() / 1.5
		results[pull] = [v, t.ch.sprinting]
		t._touch(0, stick + Vector2(0, -ctl.touch.STICK_R * k * pull), false)
		await t._wait(0.5)
	var run := Defs.move("run_speed")
	var sprint := Defs.move("sprint_speed")
	measure.touch = {"run_pull_0.7": results[0.7], "sprint_pull_0.97": results[0.97], "run_speed": run, "sprint_speed": sprint}
	t._check("touch_runs", float(results[0.7][0]) > run * 0.85, "stick at 70%%: %.1f m/s (run speed %.1f)" % [results[0.7][0], run])
	t._check("touch_sprints", bool(results[0.97][1]) and float(results[0.97][0]) > run * 1.15, "stick at the ring: %.1f m/s, sprinting %s (sprint speed %.1f)" % [results[0.97][0], str(results[0.97][1]), sprint])


func _perf() -> void:
	## Frame times with vsync off at five places, turning the view right round in each (the [perf] lines and
	## perf.json are the harness's own).
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var L = _L()
	var spots := [["perf_L1_atrium", Vector3(0, 0.05, 24)], ["perf_L3_walk", Vector3(-30, 10.05, -30)], ["perf_L5_food", Vector3(-6, 20.05, 26)],
		["perf_in_shop", Vector3(-26.0, 0.05, -40.0)], ["perf_west_court_L2", Vector3(-44, 5.05, 16)]]
	for s in spots:
		t._teleport(s[1], 0.0)
		await t._wait(1.0)
		t._perf_begin(str(s[0]), 0.9)
		await t._wait(7.0)
		t._perf_end()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
