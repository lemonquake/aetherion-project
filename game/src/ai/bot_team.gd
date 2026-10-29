extends RefCounted
## What bots share, as opposed to what each one thinks (bot_brain.gd): the map's tactical waypoints, what the bots
## have learned about them, squads, and the team radio.
##
## Waypoints are worked out once per map from the walkability grid on a worker thread: a sample every 8 m of open
## ground, with how much cover stands right beside it (a wall, a house, a parked car's cell) and the longest clear line
## of sight from it (over water too). Kinds: "cover", "snipe" (cover beside and a sightline of 60 m or more), "open".
##
## Learning (Settings > Gameplay > Bots learn): every 8 m cell keeps four numbers: good (kills scored from it), snipe
## (kills from it at 45 m or more), safe (time bots spent there unhurt) and danger (deaths in it). Bots mark them as
## things happen, so a spot one bot found is known to its whole team at once; when a match ends they are saved per map
## (user://bot_memory_<map>.json, older lessons fading by a fifth each match) and loaded by the next match. Cells where
## bots kept getting stuck are remembered too and closed on the walk grid from the start.

const CELL := 8.0
const STEP := 4                  # walk-grid cells between samples
const SIGHT_MAX := 70            # walk-grid cells a sightline is followed (140 m on a 2 m grid)
const DIRS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

static var world = null
static var match_key := ""
static var spots: Array = []     # [{p: Vector3, cover: int, sight: float, dir: Vector2, kind: String}]
static var spot_grid := {}       # Vector2i(32 m) -> [index]
static var _spots_layout = null
static var _spots_task := -1
static var _spots_tmp: Array = []
static var memory := {}          # "x,z" (8 m cell) -> [good, snipe, safe, danger]
static var stuck_cells := {}     # "x,z" (walk-grid cell) -> times bots got stuck there
static var squads := {}          # id -> {team, leader: eid, members: [eid], human: bool}
static var radio_t := {}         # team -> msec of the last callout
static var stats := {"lines": 0, "pings": 0, "laser_follow": 0, "learned_cells": 0, "blocked_cells": 0, "squads": 0, "following_humans": 0}


static func begin(w) -> void:
	## Once per match, from the first bot made: fresh squads, radio and stats; last match's lessons loaded.
	var key := "%d:%s" % [Game.match_seed, str(w.cfg.get("map", "kalinaw"))]
	if key == match_key and world == w:
		return
	world = w
	match_key = key
	squads = {}
	radio_t = {}
	stats = {"lines": 0, "pings": 0, "laser_follow": 0, "learned_cells": 0, "blocked_cells": 0, "squads": 0, "following_humans": 0}
	memory = {}
	stuck_cells = {}
	if learning():
		_load()


static func learning() -> bool:
	return bool(Settings.get_value("gameplay", "bot_learning"))


static func map_id() -> String:
	return str(world.cfg.get("map", "kalinaw")) if world else "kalinaw"


# ------------------------------------------------------------------ waypoints

static func ensure_spots(nav) -> void:
	## Starts the survey on a worker thread the first time; until it is done spots stays empty.
	if _spots_layout == nav.layout:
		if _spots_task >= 0 and WorkerThreadPool.is_task_completed(_spots_task):
			WorkerThreadPool.wait_for_task_completion(_spots_task)
			_spots_task = -1
			spots = _spots_tmp
			spot_grid = {}
			for i in spots.size():
				var k := _sg(spots[i].p)
				if not spot_grid.has(k):
					spot_grid[k] = []
				spot_grid[k].append(i)
		return
	_spots_layout = nav.layout
	spots = []
	spot_grid = {}
	_spots_tmp = []
	_spots_task = WorkerThreadPool.add_task(func(): _survey(nav), false, "bot waypoints")


static func _sg(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / 32.0), floori(p.z / 32.0))


static func _survey(nav) -> void:
	var n: int = nav.n
	var L = nav.layout
	var out := []
	var water: PackedByteArray = L._water
	for z in range(STEP / 2, n - 1, STEP):
		for x in range(STEP / 2, n - 1, STEP):
			var i := z * n + x
			if nav.walk[i] == 0:
				continue
			var p: Vector3 = nav._world(Vector2i(x, z))
			if not L.in_play_area(Vector2(p.x, p.z)):
				continue
			var cover := 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var j := (z + dz) * n + (x + dx)
					if nav.walk[j] == 0 and water[j] == 0:
						cover += 1
			var best := 0
			var bdir := Vector2i(1, 0)
			for d in DIRS:
				var k := 1
				while k < SIGHT_MAX:
					var cx: int = x + d.x * k
					var cz: int = z + d.y * k
					if cx < 0 or cz < 0 or cx >= n or cz >= n:
						break
					var c := cz * n + cx
					if nav.walk[c] == 0 and water[c] == 0:
						break
					k += 1
				var len := k * (1.4142 if d.x != 0 and d.y != 0 else 1.0)
				if len > best:
					best = int(len)
					bdir = d
			var sight := best * float(nav.cell)
			var kind := "open"
			if cover >= 1 and sight >= 60.0:
				kind = "snipe"
			elif cover >= 2:
				kind = "cover"
			out.append({"p": p, "cover": cover, "sight": sight, "dir": Vector2(bdir).normalized(), "kind": kind})
	_spots_tmp = out


static func spots_near(p: Vector3, r: float) -> Array:
	var out := []
	var k := _sg(p)
	var span := int(ceil(r / 32.0))
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			for i in spot_grid.get(k + Vector2i(dx, dz), []):
				if (spots[i].p as Vector3).distance_to(p) <= r:
					out.append(i)
	return out


# ------------------------------------------------------------------ learning

static func _mk(p: Vector3) -> String:
	return "%d,%d" % [floori(p.x / CELL), floori(p.z / CELL)]


static func mark(p: Vector3, kind: String, amount: float = 1.0) -> void:
	var k := _mk(p)
	if not memory.has(k):
		memory[k] = [0.0, 0.0, 0.0, 0.0]
		stats.learned_cells = memory.size()
	var idx: int = {"good": 0, "snipe": 1, "safe": 2, "danger": 3}.get(kind, 0)
	memory[k][idx] = float(memory[k][idx]) + amount


static func lesson(p: Vector3) -> Array:
	## [good, snipe, safe, danger] around p (this cell, plus a third of each neighbour).
	var out := [0.0, 0.0, 0.0, 0.0]
	var cx := floori(p.x / CELL)
	var cz := floori(p.z / CELL)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var m = memory.get("%d,%d" % [cx + dx, cz + dz])
			if m == null:
				continue
			var w := 1.0 if dx == 0 and dz == 0 else 0.33
			for i in 4:
				out[i] += float(m[i]) * w
	return out


const BLOCK_AT := 3          # stuck reports (from two bots or more) before a cell is closed
const MAX_BLOCKED := 60      # closed cells kept per map: a few bad spots, never the map


static func note_stuck(nav, p: Vector3, eid: int) -> bool:
	## A bot got stuck against world geometry here although the walk grid says it is open. Three reports from at least
	## two different bots close the cell (up to MAX_BLOCKED per map).
	var c: Vector2i = nav._idx(p)
	var k := "%d,%d" % [c.x, c.y]
	var e: Array = stuck_cells.get(k, [0, []])
	e[0] = int(e[0]) + 1
	if not eid in (e[1] as Array):
		(e[1] as Array).append(eid)
	stuck_cells[k] = e
	if int(e[0]) == BLOCK_AT and (e[1] as Array).size() >= 2 and stats.blocked_cells < MAX_BLOCKED:
		nav.block_cell(c)
		stats.blocked_cells += 1
		return true
	return false


static func apply_blocked(nav) -> void:
	for k in stuck_cells:
		var e = stuck_cells[k]
		if typeof(e) == TYPE_ARRAY and int(e[0]) >= BLOCK_AT and (e[1] as Array).size() >= 2 and stats.blocked_cells < MAX_BLOCKED:
			var s := str(k).split(",")
			nav.block_cell(Vector2i(int(s[0]), int(s[1])))
			stats.blocked_cells += 1


static func _path() -> String:
	return "user://bot_memory_%s.json" % map_id()


static func _load() -> void:
	var f := FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	for k in d.get("cells", {}):
		var v: Array = d.cells[k]
		if v.size() == 4:
			memory[str(k)] = [float(v[0]) * 0.8, float(v[1]) * 0.8, float(v[2]) * 0.8, float(v[3]) * 0.8]
	for k2 in d.get("stuck", {}):
		var e = d.stuck[k2]
		# Older files kept a bare count; each match a report fades (so a spot fixed in a new build reopens).
		if typeof(e) == TYPE_ARRAY and e.size() == 2:
			var n := int(e[0]) - 1
			if n > 0:
				stuck_cells[str(k2)] = [n, (e[1] as Array).slice(0, 2).map(func(x): return -1 - int(x) if int(x) >= 0 else int(x))]
	stats.learned_cells = memory.size()
	print("[bots] learned from %d cells, %d stuck spots (%s)" % [memory.size(), stuck_cells.size(), _path()])


static func save() -> void:
	if world == null or not learning():
		return
	var cells := {}
	for k in memory:
		var v: Array = memory[k]
		if float(v[0]) + float(v[1]) + float(v[2]) + float(v[3]) > 0.05:
			cells[k] = [snappedf(float(v[0]), 0.01), snappedf(float(v[1]), 0.01), snappedf(float(v[2]), 0.01), snappedf(float(v[3]), 0.01)]
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"map": map_id(), "cells": cells, "stuck": stuck_cells}))
		print("[bots] saved %d learned cells to %s" % [cells.size(), _path()])


# ------------------------------------------------------------------ squads

static func squad_of(eid: int) -> Dictionary:
	for id in squads:
		if eid in squads[id].members:
			return squads[id]
	return {}


static func form_squads(team: int, rng: RandomNumberGenerator) -> void:
	## Once per team: about half the bots pair up or make threes (each squad with a leader the others follow); the rest
	## go alone. Called again it does nothing.
	for id in squads:
		if int(squads[id].team) == team:
			return
	var ids := []
	for eid in world.bots:
		var b = world.bots[eid]
		if b.ch.team == team and b.ch.mode not in [Motor.DEAD, Motor.SPECTATE]:
			ids.append(eid)
	ids.sort()
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	var grouped := int(round(ids.size() * 0.55))
	var at := 0
	var sid := team * 100
	while grouped - at >= 2:
		var size := 3 if grouped - at >= 5 and rng.randf() < 0.4 else 2
		var members: Array = ids.slice(at, at + size)
		at += size
		# The boldest leads: rushers and stalkers before snipers and house campers.
		members.sort_custom(func(a, b): return int(world.bots[a].lead_rank()) > int(world.bots[b].lead_rank()))
		sid += 1
		squads[sid] = {"team": team, "leader": members[0], "members": members, "human": false}
		for e in members:
			world.bots[e].squad_id = sid
		stats.squads += 1
	# A team placeholder so a team with too few bots is not formed again.
	squads[team * 100] = {"team": team, "leader": -1, "members": [], "human": false}


static func leave_squad(eid: int) -> void:
	for id in squads.keys():
		var s: Dictionary = squads[id]
		if not eid in s.members:
			continue
		s.members.erase(eid)
		if int(s.leader) == eid:
			s.leader = int(s.members[0]) if not s.members.is_empty() else -1
		if s.members.size() < 2 and not bool(s.human):
			for e in s.members:
				if world.bots.has(e):
					world.bots[e].squad_id = -1
			squads.erase(id)
		elif bool(s.human) and s.members.is_empty():
			squads.erase(id)
		return


static func follow_human(eid: int, human_eid: int) -> void:
	leave_squad(eid)
	var key := 10000 + human_eid
	if not squads.has(key):
		squads[key] = {"team": world.characters[human_eid].team, "leader": human_eid, "members": [], "human": true}
	if not eid in squads[key].members:
		squads[key].members.append(eid)
		stats.following_humans += 1
	world.bots[eid].squad_id = key


static func human_followers(human_eid: int) -> int:
	var s: Dictionary = squads.get(10000 + human_eid, {})
	return (s.members as Array).size() if not s.is_empty() else 0


# ------------------------------------------------------------------ radio

static func can_talk(team: int, priority: bool) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(radio_t.get(team, -100000)) < (700 if priority else 1800):
		return false
	radio_t[team] = now
	return true


# ------------------------------------------------------------------ events from the match

static func on_killed(victim, attacker: int) -> void:
	if world == null:
		return
	if world.bots.has(victim.eid) and str(victim.health.last_cause) == "haze" and world.match_server:
		var b = world.bots[victim.eid]
		world.match_server.log_event("[haze death] %s (%s) state %s at %s goal %s path %d/%d no_prog %.1f pending %s" % [victim.pname, b.role, b.state,
			str(victim.global_position.round()), str((b.goal as Vector3).round()) if b.goal != Vector3.INF else "-", b.path_i, b.path.size(), b._no_prog, str(b._path_req != 0)])
	var k = world.characters.get(attacker)
	mark(victim.global_position, "danger", 1.0)
	if k != null and k != victim:
		var d: float = (k.global_position as Vector3).distance_to(victim.global_position)
		mark(k.global_position, "good", 1.0)
		if d > 45.0:
			mark(k.global_position, "snipe", 1.0)
		if world.bots.has(attacker):
			world.bots[attacker].on_scored(victim, d)
	# A teammate nearby says so.
	for eid in world.bots:
		var b = world.bots[eid]
		if b.ch != victim and b.ch.team == victim.team and b.ch.mode == Motor.GROUND \
				and b.ch.global_position.distance_to(victim.global_position) < 70.0:
			b.say("down", true)
			break
	leave_squad(victim.eid)
	# Bots following a human who fell go their own way.
	var hs: Dictionary = squads.get(10000 + int(victim.eid), {})
	if not hs.is_empty():
		for e in (hs.members as Array).duplicate():
			if world.bots.has(e):
				world.bots[e].squad_id = -1
		squads.erase(10000 + int(victim.eid))
