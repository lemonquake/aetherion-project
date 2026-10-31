extends RefCounted
## r11 checks on a listen host on Lawless Sub (`--autotest=r11`, `--r11_only=teams,walk,kerbs,cage,pa,haze`):
##   godot --path game -- --host --game_mode=deathmatch --bots=20 --autostart=1 --autotest=r11 --shots=<dir>
## teams: three teams of seven, each at its own spawn, the spawns 300+ m apart. walk: the local player walks every
## sidewalk in 30 m legs (walk speed, no jumping) and each leg must cover most of its length; a leg that stalls is a
## blocked spot (logged with its position). kerbs: from the carriageway straight at the kerb, square and at 35
## degrees, the player ends on the sidewalk. cage: walking into the cage wall for 3 s leaves you inside it, and a
## ray at chest height from inside stops on it. pa: the cage announcer played its start line from cage speakers.
## haze: a hit on a wall leaves a cloud still visible 1.5 s later (luma change against the same view before).

var t = null
var world = null
var walk_log: Array = []


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("r11_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 40.0)
	await t._wait(1.5)
	if not is_instance_valid(t.ch):
		t._check("r11_spawn", false, "no local character")
		return
	world.map.lighting.forced_time = 450.0
	if want.call("teams"):
		_teams()
	for b in world.bots.values():
		b._dm_hold = 9999.0   # keep the bots at their spawns while the player walks the map
	t.ch.health.test_invulnerable = true   # bots at their spawns still shoot at a player who walks past
	if world.match_server and not world.match_server.zone.is_empty():
		world.match_server.zone.t1 = Net.tick + 100000000   # the first circle never starts closing (no haze damage)
	if want.call("pa"):
		await _pa()
	if want.call("cage"):
		await _cage()
	if want.call("haze"):
		await _haze()
	if want.call("kerbs"):
		await _kerbs()
	if want.call("stairs"):
		await _stairs()
	if want.call("walk"):
		await _walk()


func _teams() -> void:
	var per := {}
	for ch in world.characters.values():
		per[ch.team] = int(per.get(ch.team, 0)) + 1
	var ms = world.match_server
	var anchors := []
	if ms:
		for k in ms.spawn_info:
			if k is int:
				anchors.append(ms.spawn_info[k].anchor)
	var min_gap := INF
	for i in anchors.size():
		for j in range(i + 1, anchors.size()):
			min_gap = minf(min_gap, Vector2(anchors[i].x - anchors[j].x, anchors[i].z - anchors[j].z).length())
	var ok := per.size() == 3 and per.values().all(func(n): return int(n) == 7) and min_gap > 300.0
	t._check("r11_three_teams", ok, "players per team %s, spawns %s, closest spawns %.0f m apart" % [str(per), str(anchors.map(func(a): return (a as Vector3).round())), min_gap])


func _pa() -> void:
	var ann = world.announcer
	if ann == null:
		t._check("r11_cage_pa", false, "no announcer node")
		return
	var kinds := {}
	for s in world.map.pa_speakers:
		kinds[str(s.get("kind", ""))] = int(kinds.get(str(s.get("kind", "")), 0)) + 1
	await t._until(func(): return ann.played.any(func(e): return str(e[1]) == "pa_cage_start"), 12.0)
	var started: bool = ann.played.any(func(e): return str(e[1]) == "pa_cage_start")
	var near: Array = ann.nearest(t.ch.global_position, 3)
	var far_ok := true
	for q in near:
		far_ok = far_ok and absf(maxf(absf(q.x), absf(q.z)) - world.map.layout.edge) < 12.0
	t._check("r11_cage_pa", ann.is_cage() and started and int(kinds.get("cage", 0)) >= 24 and far_ok,
		"speakers %s; start line played: %s; the 3 nearest stacks are on the cage: %s (%s)" % [str(kinds), started, far_ok, str(near.map(func(q): return (q as Vector3).round()))])


func _cage() -> void:
	## Walk into the north cage wall from 6 m inside; then a chest-height ray from inside toward it.
	var L = world.map.layout
	var e: float = L.edge
	var x := 64.0 + 8.0
	var start := Vector3(x, L.surface_y(Vector2(x, -e + 6.0)) + 0.1, -e + 6.0)
	t._teleport(start, 0.0)   # yaw 0 faces -z (north)
	await t._wait(0.5)
	t._act_press("move_forward")
	t._act_press("sprint")
	await t._wait(3.0)
	t._act_press("jump")
	await t._wait(0.3)
	t._act_release("jump")
	await t._wait(1.0)
	t._act_release("move_forward")
	t._act_release("sprint")
	var p: Vector3 = t.ch.global_position
	var space: PhysicsDirectSpaceState3D = t.ch.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, start.y + 1.3, -e + 5.0), Vector3(x, start.y + 1.3, -e - 5.0))
	q.exclude = [t.ch.get_rid()]
	var hit := space.intersect_ray(q)
	var hz: float = (hit.position as Vector3).z if not hit.is_empty() else -INF
	t._check("r11_cage_holds", p.z > -e + 0.2 and hz > -e - 0.5, "walked into the north cage from z %.1f: stopped at z %.2f (wall line %.1f); chest ray stops at z %.2f" % [start.z, p.z, -e, hz])
	t._look_at(Vector3(x, start.y + 7.0, -e))
	await t._wait(0.4)
	await t._shot("cage_wall")


func _haze() -> void:
	## A wall in view; the same view before, just after, 1.5 s and 4 s after a hit on it (no bullet, the client
	## effect the server's impact message plays).
	var L = world.map.layout
	var e: float = L.edge
	var x := 30.0
	var pos := Vector3(x + 1.0, L.surface_y(Vector2(x, -e + 5.0)) + 0.1, -e + 5.0)
	t._teleport(pos, 0.0)
	await t._wait(0.3)
	var target := Vector3(x, pos.y + 1.6, -e + 0.08)
	t._look_at(target)
	await t._wait(0.8)
	# Control: the same view and timings with no hit (lighting, flicker and moving bots change pixels too).
	var c_base: Image = await _grab()
	await t._wait(1.5)
	var c_1: Image = await _grab()
	var control := _diff(c_base, c_1)
	var base: Image = await _grab()
	world.effects.impact(target, Vector3(0, 0, 1), "concrete", "hole", "concrete")
	await t._wait(0.15)
	var i0: Image = await _grab()
	await t._wait(1.35)
	var i1: Image = await _grab()
	await t._shot("haze_1_5s")
	await t._wait(2.5)
	var i2: Image = await _grab()
	var d0 := _diff(base, i0)
	var d1 := _diff(base, i1)
	var d2 := _diff(base, i2)
	t._check("r11_impact_haze", d1 > control + 1.2 and d1 > d2, "centre change against the view before the hit: %.2f at 0.15 s, %.2f at 1.5 s, %.2f at 4 s (no-hit control over 1.5 s: %.2f)" % [d0, d1, d2, control])


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return t.get_viewport().get_texture().get_image()


static func _diff(a: Image, b: Image) -> float:
	## Mean absolute luma difference (0-255) over the middle fifth of the view.
	var sz := a.get_size()
	var r := Rect2i(sz.x * 2 / 5, sz.y * 2 / 5, sz.x / 5, sz.y / 5)
	var s := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			s += absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance())
			n += 1
	return s / maxf(n, 1) * 255.0


func _legs() -> Array:
	## [start, direction, length, road, side] for 30 m legs along the middle of every sidewalk.
	var out := []
	var L = world.map.layout
	for rd in L.roads:
		var sw := float(rd.sidewalk)
		if sw <= 0.0:
			continue
		for side in [-1.0, 1.0]:
			var off = (float(rd.w) * 0.5 + sw * 0.5) * side
			var s: float = float(rd.lo) + 6.0
			while s + 30.0 < float(rd.hi) - 6.0:
				var a: Vector2
				var dir: Vector2
				if int(rd.axis) == 0:
					a = Vector2(s, float(rd.c) + off)
					dir = Vector2(1, 0)
				else:
					a = Vector2(float(rd.c) + off, s)
					dir = Vector2(0, 1)
				if L.in_play_area(a) and L.in_play_area(a + dir * 30.0):
					out.append([a, dir, 30.0, str(rd.name), side])
				s += 34.0
	return out


func _walk() -> void:
	var L = world.map.layout
	var legs := _legs()
	var stalls := []
	var done := 0
	var total := 0.0
	var max_legs := int(Game.arg("r11_legs", 400))
	var road_filter := str(Game.arg("r11_road", "")).replace("_", " ")
	if road_filter != "":
		legs = legs.filter(func(l): return str(l[3]) == road_filter)
	Engine.time_scale = float(Game.arg("r11_speed", 1.0))   # 3x sped the sweep up but made the step-up code pop the player
	for leg in legs.slice(0, max_legs):
		var a: Vector2 = leg[0]
		var dir: Vector2 = leg[1]
		var y: float = L.surface_y(a) + 0.15
		# A leg that would start under or inside something (a stair, a shelter) starts beside it, on the curb side.
		var space0: PhysicsDirectSpaceState3D = t.ch.get_world_3d().direct_space_state
		for tries in 3:
			var q0 := PhysicsRayQueryParameters3D.create(Vector3(a.x, y + 0.3, a.y), Vector3(a.x, y + 2.0, a.y))
			q0.exclude = [t.ch.get_rid()]
			if space0.intersect_ray(q0).is_empty():
				break
			a += (Vector2(-float(leg[4]), 0) if absf(dir.x) < 0.5 else Vector2(0, -float(leg[4]))) * 0.6
		t._teleport(Vector3(a.x, y, a.y), atan2(-dir.x, -dir.y))
		await t._wait(0.25)
		var p0: Vector3 = t.ch.global_position
		t._act_press("move_forward")
		t._act_press("sprint")
		var worst_gap := 0.0
		var last := p0
		var still := 0.0
		var elapsed := 0.0
		var first_off := {}
		while elapsed < 6.5:
			await t.get_tree().physics_frame
			var dt := 1.0 / float(Engine.physics_ticks_per_second)
			elapsed += dt
			var p: Vector3 = t.ch.global_position
			if p.distance_to(last) < 0.02:
				still += dt
			else:
				still = 0.0
			last = p
			var lat := Vector2(p.x - p0.x, p.z - p0.z).dot(Vector2(-dir.y, dir.x))
			if first_off.is_empty() and (absf(lat) > 0.5 or still > 0.3):
				# What turned the player: a ray straight ahead from the leg's line at this point.
				var on_line := Vector3(p0.x, p.y, p0.z) + Vector3(dir.x, 0, dir.y) * Vector2(p.x - p0.x, p.z - p0.z).dot(dir)
				var space: PhysicsDirectSpaceState3D = t.ch.get_world_3d().direct_space_state
				var q := PhysicsRayQueryParameters3D.create(on_line + Vector3(0, 0.5, 0) - Vector3(dir.x, 0, dir.y) * 0.8, on_line + Vector3(0, 0.5, 0) + Vector3(dir.x, 0, dir.y) * 2.5)
				q.exclude = [t.ch.get_rid()]
				var hit := space.intersect_ray(q)
				var what := "nothing ahead on the line"
				if not hit.is_empty():
					var col = hit.collider
					what = "%s %s at %s" % [col.get_class(), str(col.name) if col is Node else "", str((hit.position as Vector3).snapped(Vector3.ONE * 0.1))]
					if col is Object and col.has_meta("what"):
						what += " (%s)" % str(col.get_meta("what"))
				first_off = {"at": Vector2(p.x, p.z).snapped(Vector2.ONE * 0.1), "lat": snappedf(lat, 0.1), "y": snappedf(p.y, 0.01), "ahead": what}
			if still > 0.6 or Vector2(p.x - p0.x, p.z - p0.z).dot(dir) > 30.0:
				break
		t._act_release("move_forward")
		t._act_release("sprint")
		var p1: Vector3 = t.ch.global_position
		var along := Vector2(p1.x - p0.x, p1.z - p0.z).dot(dir)
		var side_drift := absf(Vector2(p1.x - p0.x, p1.z - p0.z).dot(Vector2(-dir.y, dir.x)))
		total += along
		done += 1
		var rec := {"road": leg[3], "side": leg[4], "from": a.round(), "along": snappedf(along, 0.1), "drift": snappedf(side_drift, 0.1),
			"stuck_at": Vector2(p1.x, p1.z).round(), "y": snappedf(p1.y, 0.01), "first_off": first_off}
		walk_log.append(rec)
		if along < 24.0 or side_drift > 1.2:
			stalls.append(rec)
			print("[r11 walk] STALL %s" % str(rec))
	Engine.time_scale = 1.0
	var f := FileAccess.open(str(t.out_dir) + "/walk_log.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(walk_log, " "))
	t._check("r11_sidewalks_walkable", stalls.is_empty() and done > 20, "%d legs of 30 m walked (%.0f m in all); %d stalled%s" % [done, total, stalls.size(),
		(": " + str(stalls.slice(0, 6))) if not stalls.is_empty() else ""])


func _stairs() -> void:
	## Upper flights (third floors, roof decks, the mall's grand stair): from the first tread, walk up the flight
	## for 4 s; the player must end at least 80 % of the rise above the flight's foot.
	var L = world.map.layout
	var picks := []
	for f in world.map.stairs:
		var top: Vector3 = f.top
		var foot: Vector3 = f.foot
		if top.y - L.LAND_Y > 5.0 and top.y - foot.y > 2.0 and float(f.get("w", 1.0)) >= 0.85:
			picks.append(f)
	picks.shuffle()
	var tried := 0
	var fails := []
	var roofs := 0
	for f in picks.slice(0, int(Game.arg("r11_stairs", 14))):
		var foot: Vector3 = f.foot
		var top: Vector3 = f.top
		var dir: Vector3 = f.dir
		dir.y = 0.0
		dir = dir.normalized()
		# House flights start against a wall and are entered from the side: begin on the first tread.
		var start := foot + dir * 0.4 + Vector3.UP * 0.3
		t._teleport(start, atan2(-dir.x, -dir.z))
		await t._wait(0.3)
		var y0: float = foot.y
		t._act_press("move_forward")
		await t._wait(4.0)
		t._act_release("move_forward")
		var gain: float = t.ch.global_position.y - y0
		var rise := top.y - foot.y
		tried += 1
		if top.y - L.LAND_Y > 8.5:
			roofs += 1
		if gain < rise * 0.8:
			fails.append("foot %s rise %.1f: gained %.2f" % [str(foot.snapped(Vector3.ONE * 0.1)), rise, gain])
	t._check("r11_upper_stairs_climb", tried >= 8 and fails.is_empty(), "%d upper flights tried (%d ending above 8.5 m: roofs, top floors); %d failed %s" % [tried, roofs, fails.size(), str(fails.slice(0, 4))])


func _kerbs() -> void:
	## From the carriageway at the kerb: square on and 35 degrees off, at points along the avenue and two streets.
	var L = world.map.layout
	var fails := []
	var n := 0
	for spot in [["Lawless Avenue", -150.0], ["Lawless Avenue", 95.0], ["Sub Boulevard", 60.0], ["Sub Boulevard", -190.0], ["Narra St", -100.0], ["Gumamela St", 140.0]]:
		var rd: Dictionary = {}
		for r in L.roads:
			if str(r.name) == str(spot[0]):
				rd = r
		if rd.is_empty():
			continue
		for ang in [0.0, 35.0]:
			for side in [-1.0, 1.0]:
				var s := float(spot[1])
				var edge = float(rd.w) * 0.5 * side
				var a: Vector2
				var to: Vector2
				if int(rd.axis) == 0:
					a = Vector2(s, float(rd.c) + edge - side * 1.6)
					to = Vector2(sin(deg_to_rad(ang)), side * cos(deg_to_rad(ang)))
				else:
					a = Vector2(float(rd.c) + edge - side * 1.6, s)
					to = Vector2(side * cos(deg_to_rad(ang)), sin(deg_to_rad(ang)))
				t._teleport(Vector3(a.x, L.surface_y(a) + 0.1, a.y), atan2(-to.x, -to.y))
				await t._wait(0.3)
				var y0: float = t.ch.global_position.y
				var y_top := y0
				t._act_press("move_forward")
				for k in 84:
					await t.get_tree().physics_frame
					y_top = maxf(y_top, t.ch.global_position.y)
				t._act_release("move_forward")
				var p: Vector3 = t.ch.global_position
				var across := Vector2(p.x - a.x, p.z - a.y).dot(Vector2(0, side) if int(rd.axis) == 0 else Vector2(side, 0))
				n += 1
				if across < 2.0 or y_top < y0 + 0.08:
					fails.append("%s @%.0f side %d %.0f deg: %.1f m across, height %.2f -> top %.2f" % [spot[0], s, int(side), ang, across, y0, y_top])
	t._check("r11_kerbs_step_up", fails.is_empty() and n >= 12, "%d kerb approaches walking (no jump); %d failed %s" % [n, fails.size(), str(fails.slice(0, 5))])
