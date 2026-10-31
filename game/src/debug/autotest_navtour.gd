extends RefCounted
## (r21) The bots' walk, on any map (`--autotest=navtour`, on a listen host with bots):
##   godot --path game -- --host --game_mode=deathmatch --map=malasugue_mall --bots=11 --autostart=1 --dm_time=30 --autotest=navtour --shots=<dir>
## analysis: BotNav finished (walk check, waypoints, hiding spots) and says what it found.
## tour: one teammate bot (invulnerable; every other bot frozen where it stands)
## is ordered from waypoint to waypoint across the map, every floor, legs at least 15 m long, in a seeded order
## (--navtour_seed, --navtour_legs, default 24); the bot sees and hears nobody (test_blind), so it never stops to fight.
## Each leg must arrive (the bot's own measure for a "go" order: within 4 m, same floor) in time, and the bot must not
## stand stuck (no progress for 2 s while it is still on its way). Legs, times and stalls go to <shots>/navtour_<map>.json.

const BotNav := preload("res://src/ai/bot_nav.gd")
const BotTeam := preload("res://src/ai/bot_team.gd")

var t = null
var world = null
var measure := {}
var _frozen := {}


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 60.0)
	await t._wait(1.0)
	t.ch.health.test_invulnerable = true
	await t._until(func(): return BotNav.phase == "done", 180.0)
	var kinds: Dictionary = BotNav.stats.get("kinds", {})
	measure.analysis = BotNav.stats.duplicate()
	t._check("navtour_analysis", BotNav.phase == "done" and BotTeam.spots.size() > 20 and int(kinds.get("hide", 0)) > 0,
		"%s: %d spots %s from %s, walk check closed %d cells, analysis %.0f ms" % [BotNav.map_id, BotTeam.spots.size(), str(kinds),
		str(BotNav.stats.get("source", "")), int(BotNav.stats.get("closed", 0)), float(BotNav.stats.get("spots_ms", 0.0))])
	await _tour()
	var f := FileAccess.open(t.out_dir + "/navtour_%s.json" % BotNav.map_id, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


func _legs(start: Vector3, n: int) -> Array:
	if Game.arg("navtour_to") != null:
		# explicit legs: --navtour_to=x,y,z;x,y,z (replaying one that failed; with --navtour_from=x,y,z to start there)
		var out0 := []
		for e in str(Game.arg("navtour_to")).split(";", false):
			var v := e.split(",")
			if v.size() == 3:
				var q := Vector3(float(v[0]), float(v[1]), float(v[2]))
				out0.append(["given %s" % str(q), q])
		return out0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Game.arg("navtour_seed", 7))
	var pool := []
	for s in BotTeam.spots:
		if str(s.get("src", "")) != "learned":
			pool.append(s)
	var out := []
	var at := start
	var tries := 0
	while out.size() < n and tries < 4000 and not pool.is_empty():
		tries += 1
		var s: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var p: Vector3 = s.p
		if p.distance_to(at) < 15.0:
			continue
		# mix the floors: every third leg changes floor when the map has more than one
		out.append(["%s %s (%s)" % [str(s.kind), str(p.snapped(Vector3.ONE * 0.1)), str(s.get("name", "")) if str(s.get("name", "")) != "" else str(s.get("src", ""))], p])
		at = p
	return out


func _tour() -> void:
	var eid := -1
	for k in world.bots.keys():
		if world.characters.has(k) and world.characters[k].team == t.ch.team and world.characters[k].mode == Motor.GROUND:
			eid = k
			break
	if eid < 0:
		t._check("navtour_route", false, "no teammate bot on the ground")
		return
	var ch = world.characters[eid]
	var b = world.bots[eid]
	for k in world.bots.keys():
		if k == eid:
			continue
		_frozen[k] = world.bots[k]
		world.bots.erase(k)
		world._bot_dt.erase(k)
		world._queues[k] = []
		if world.characters.has(k):
			world.characters[k].last_cmd = {}
	ch.health.test_invulnerable = true
	b.test_blind = true
	Field.test_only = [-1]   # nobody feels the field (Lawless Sub's closes on the bot; a route test is about the walk)
	if Game.arg("navtour_from") != null:
		var f := str(Game.arg("navtour_from")).split(",")
		ch.global_position = Vector3(float(f[0]), float(f[1]) + 0.1, float(f[2]))
		ch.velocity = Vector3.ZERO
		await t._wait(0.5)
	var legs := _legs(ch.global_position, int(Game.arg("navtour_legs", 24)))
	var out := []
	var passed := 0
	var stalls_total := 0
	for leg in legs:
		var goal: Vector3 = leg[1]
		var p0: Vector3 = ch.global_position
		var t0 := Time.get_ticks_msec()
		var ok := false
		var stalls := 0
		var stalled := false
		var stall_at := []
		var budget := 30.0 + p0.distance_to(goal) / 2.0
		b.take_order("go", null, goal)
		while (Time.get_ticks_msec() - t0) < budget * 1000.0:
			if b.order.is_empty() or b.state != "order" or (b.order.p as Vector3) != goal:
				b.take_order("go", null, goal)
			await t._wait(0.25)
			if not is_instance_valid(ch) or ch.mode != Motor.GROUND:
				break
			var p: Vector3 = ch.global_position
			var np := float(b._no_prog) if not bool(b.order.get("arrived", false)) else 0.0
			if np > 2.0 and not stalled:
				stalled = true
				stalls += 1
				stall_at.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1), b._ahead()])
			elif np < 0.5:
				stalled = false
			if absf(p.y - goal.y) < 1.0 and Vector2(p.x - goal.x, p.z - goal.z).length() < 4.2:
				ok = true
				break
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		if not is_instance_valid(ch):
			t._check("navtour_route", false, "the tour bot was removed (round over?) on leg %s" % leg[0])
			return
		var pe: Vector3 = ch.global_position
		out.append({"leg": leg[0], "ok": ok, "seconds": snappedf(secs, 0.1), "metres": snappedf(p0.distance_to(goal), 0.1), "stalls": stalls,
			"stalled_at": stall_at, "end": [snappedf(pe.x, 0.1), snappedf(pe.y, 0.1), snappedf(pe.z, 0.1)]})
		print("[navtour] %s %s: %.1f s, %d stalls, ended at %s" % ["PASS" if ok else "FAIL", leg[0], secs, stalls, str(pe.snapped(Vector3.ONE * 0.1))])
		if ok:
			passed += 1
		else:
			ch.global_position = goal + Vector3(0, 0.1, 0)   # carry on from the goal so one bad leg does not fail the rest
			ch.velocity = Vector3.ZERO
		stalls_total += stalls
	measure.legs = out
	t._check("navtour_route", passed >= int(ceil(legs.size() * 0.9)), "bot reached %d of %d waypoints across the map, %d stalls" % [passed, legs.size(), stalls_total])
	t._check("navtour_no_wall_stalls", stalls_total <= maxi(legs.size() / 6, 2), "%d stalls over %d legs (no progress for 2 s or more)" % [stalls_total, legs.size()])
