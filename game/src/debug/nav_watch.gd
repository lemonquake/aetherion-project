extends RefCounted
## Evidence for "bots get stuck in walls" (`--navwatch[=<file.json>]` on a server or host, any map): every half second
## each bot on the ground is sampled. A bot that wants to go somewhere (it has a goal) but has covered under 0.25 m/s
## for 2 s is a stall; a bot standing still for 3 s with a wall within a metre straight in front of its eyes is "facing
## a wall". Both are counted with where they happened (level and 2 m cell), and printed every minute and at the end
## ([navwatch] lines); with a file name the totals and the worst places are written there as JSON too.

const SAMPLE := 0.5
const STALL_SPEED := 0.25
const STALL_S := 2.0
const WALL_S := 3.0

var world = null
var _t := 0.0
var _log_t := 0.0
var _bots := {}        # eid -> {p, stall, wall, stalled, walled}
var totals := {"bot_s": 0.0, "moving_s": 0.0, "stall_events": 0, "stall_s": 0.0, "wall_events": 0, "wall_s": 0.0}
var places := {}       # "lv:x,z" -> {stall, wall, states: {}}


func _init(w) -> void:
	world = w


func tick(dt: float) -> void:
	_t += dt
	if _t < SAMPLE:
		return
	var step := _t
	_t = 0.0
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for eid in world.bots:
		var b = world.bots[eid]
		var ch = world.characters.get(eid)
		if ch == null or ch.mode != Motor.GROUND:
			_bots.erase(eid)
			continue
		var p: Vector3 = ch.global_position
		var e: Dictionary = _bots.get(eid, {})
		if e.is_empty():
			_bots[eid] = {"p": p, "stall": 0.0, "wall": 0.0, "stalled": false, "walled": false}
			continue
		totals.bot_s += step
		var moved := Vector2(p.x - (e.p as Vector3).x, p.z - (e.p as Vector3).z).length()
		e.p = p
		var wants: bool = b.goal != Vector3.INF and b.state not in ["fight", "camp", "overwatch"]
		if wants:
			totals.moving_s += step
		if wants and moved < STALL_SPEED * step:
			e.stall = float(e.stall) + step
		else:
			e.stall = 0.0
			e.stalled = false
		if float(e.stall) >= STALL_S:
			totals.stall_s += step
			if not e.stalled:
				e.stalled = true
				totals.stall_events += 1
				_place(p, "stall", str(b.state))
		# standing still, a wall right in front of the eyes
		var still: bool = moved < 0.1 * step
		var wall := false
		if still:
			var eye: Vector3 = ch.eye_position()
			var fwd := -Basis(Vector3.UP, float(ch.yaw)).z
			var q := PhysicsRayQueryParameters3D.create(eye, eye + fwd * 1.0, Defs.MOVE_MASK)
			q.exclude = [ch.get_rid()]
			wall = not space.intersect_ray(q).is_empty()
		if still and wall:
			e.wall = float(e.wall) + step
		else:
			e.wall = 0.0
			e.walled = false
		if float(e.wall) >= WALL_S:
			totals.wall_s += step
			if not e.walled:
				e.walled = true
				totals.wall_events += 1
				_place(p, "wall", str(b.state))
	_log_t += step
	if _log_t >= 60.0:
		_log_t = 0.0
		print(summary_line())


func _place(p: Vector3, kind: String, st: String) -> void:
	var L = world.map.layout
	var lv: int = L.level_of(p.y) if L.has_method("level_of") else 0
	var k := "%d:%d,%d" % [lv, floori(p.x / 2.0) * 2, floori(p.z / 2.0) * 2]
	var e: Dictionary = places.get(k, {"stall": 0, "wall": 0, "states": {}})
	e[kind] = int(e[kind]) + 1
	e.states[st] = int(e.states.get(st, 0)) + 1
	places[k] = e


func summary_line() -> String:
	var per_min := 60.0 / maxf(float(totals.bot_s), 1.0)
	return "[navwatch] %s: %.0f bot-s (%.0f moving), stalls %d (%.1f/bot-min, %.1f%% of moving time), facing a wall %d (%.1f/bot-min)" % [
		str(world.map.layout.get("MAP_ID") if world.map.layout.get("MAP_ID") != null else world.cfg.get("map", "?")),
		float(totals.bot_s), float(totals.moving_s), int(totals.stall_events), float(totals.stall_events) * per_min,
		100.0 * float(totals.stall_s) / maxf(float(totals.moving_s), 1.0), int(totals.wall_events), float(totals.wall_events) * per_min]


func worst(n: int = 15) -> Array:
	var ks := places.keys()
	ks.sort_custom(func(a, b): return int(places[a].stall) + int(places[a].wall) > int(places[b].stall) + int(places[b].wall))
	var out := []
	for k in ks.slice(0, n):
		out.append([k, places[k]])
	return out


func finish() -> void:
	print(summary_line())
	for w in worst(12):
		print("[navwatch]   %s %s" % [w[0], str(w[1])])
	var path := str(Game.arg("navwatch", ""))
	if path.ends_with(".json"):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"map": str(world.cfg.get("map", "?")), "totals": totals, "worst": worst(40)}, "  "))
