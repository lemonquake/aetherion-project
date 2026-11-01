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
##
## (r21) The waypoints now come from BotNav (bot_nav.gd), the same way on every map: hiding spots, sniping spots, cover
## and open ground, looked round with the real collision, each facing the way it watches, worked out once per map build
## and saved. The quick grid survey below only stands in until that is done. Learning grew with it:
##   popular spots   every spot keeps uses (held by a bot, or camped by a player), time held, kills scored from it and
##                   deaths in it; bots pick spots by that as well as by what the spot is;
##   learned spots   where a human player camps (still for 8 s) or scores from, away from every known spot, becomes a
##                   spot of its own (looked round like the others), so bots learn the places players like;
##   stuck cells     now kept per floor on storeyed maps, and dropped when the map's build changes.
## Bots claim the spot they are heading for, so two do not stack on one.
##
## (r22) The endgame (Deathmatch): per team, when its bots last saw or were hit by an enemy, whether it is in the endgame
## (few left on a side, or no contact for a while: bot_brain.gd decides), and a sweep map: every 16 m cell (per floor on
## storeyed maps) keeps when a bot of the team last walked through or beside it, so sweeping bots go where nobody has
## looked for longest, each claiming its cell so teammates spread. After a long quiet in the endgame the team gets a
## rough idea (within 20 m) of the nearest enemy, so a hidden last player is always found. Also the [botskill] numbers.
##
## (r22) Each team has a blackboard (board(team), src/ai/limbo): the parent scope of its bots' own blackboards in their
## minds (bot_mind.gd). It holds what the whole team knows: "intel", the latest callout {p, t} (a sighting, or the
## endgame's hint), and "endgame" (whether the team is in it). Fresh each round.

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
# r21
const BotNav := preload("res://src/ai/bot_nav.gd")
const Waypoints := preload("res://src/ai/waypoints.gd")
static var learned: Array = []     # spots learned from play (appended to spots)
static var spot_stats := {}        # spot key -> [uses, held_s, kills, deaths]
static var claims := {}            # spot index -> [eid, msec until]
static var _watch := {}            # human eid -> [anchor Vector3, seconds still]
static var _watch_t := 0.0
const LEARNED_MAX := 150
const CAMP_S := 8.0
# r22
const SWEEP_CELL := 16.0
const HINT_EVERY_S := 30.0
const HINT_FUZZ := 20.0
static var _round_key := {}        # team -> "seed:round" the endgame state below belongs to
static var _t0 := {}               # team -> msec its round began (cells never checked count from here)
static var contact_t := {}         # team -> msec one of its bots last saw an enemy or was hit
static var end_t := {}             # team -> msec its endgame began (absent: not in it)
static var _end_log := {}          # team -> msec of the last [endgame] line
static var _hint_t := {}           # team -> msec of the last hint
static var checked := {}           # team -> {Vector3i(cell x, cell z, floor): msec last checked}
static var sweep_claims := {}      # team -> {Vector3i: [eid, msec until]}
static var _cnt := {}              # team -> {t, mates, foes, quiet_s} (recounted twice a second)
static var _cells := {}            # Vector3i -> [spot index]: the waypoints by sweep cell
static var _cells_n := -1          # spots.size() the buckets were made for
static var _storeyed := -1
static var skill_stats := {}       # skill -> {shots, hits, dmg, react_s, react_n}
static var _skill_t := 0.0
const Blackboard := preload("res://src/ai/limbo/blackboard.gd")
static var boards := {}            # team -> Blackboard: the team's scope of its bots' minds
static var state_s := {}           # activity label -> bot-seconds spent in it this match (the [botstates] line)


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
	laser_claims = {}
	memory = {}
	stuck_cells = {}
	learned = []
	spot_stats = {}
	claims = {}
	_watch = {}
	_round_key = {}
	_t0 = {}
	contact_t = {}
	end_t = {}
	_end_log = {}
	_hint_t = {}
	checked = {}
	sweep_claims = {}
	_cnt = {}
	_cells_n = -1
	_storeyed = -1
	skill_stats = {}
	_skill_t = 0.0
	boards = {}
	state_s = {}
	if learning():
		_load()
	set_spots(BotNav.spots if BotNav.phase == "done" else [])


static func learning() -> bool:
	return bool(Settings.get_value("gameplay", "bot_learning"))


static func map_id() -> String:
	return str(world.cfg.get("map", "kalinaw")) if world else "kalinaw"


# ------------------------------------------------------------------ waypoints

static func ensure_spots(nav) -> void:
	## Starts the survey on a worker thread the first time; until it is done spots stays empty.
	if BotNav.phase == "done":
		_spots_layout = nav.layout   # (r21) the map's analysis is in (a stand-in survey still running is let finish)
		if _spots_task >= 0:
			WorkerThreadPool.wait_for_task_completion(_spots_task)
			_spots_task = -1
		return
	if _spots_layout == nav.layout:
		if _spots_task >= 0 and WorkerThreadPool.is_task_completed(_spots_task):
			WorkerThreadPool.wait_for_task_completion(_spots_task)
			_spots_task = -1
			if BotNav.phase != "done":
				set_spots(_spots_tmp)
		return
	_spots_layout = nav.layout
	set_spots([])
	_spots_tmp = []
	if nav.get("levels") != null:
		# (r15) a storeyed map: no waypoint survey (it reads one square grid). A map that knows its own vantage points
		# on every floor hands them over instead (Freight Delight: its decks, bridges and windows).
		if nav.layout.has_method("bot_spots"):
			set_spots(nav.layout.bot_spots())
		return
	_spots_task = WorkerThreadPool.add_task(func(): _survey(nav), false, "bot waypoints")


static func set_spots(arr: Array) -> void:
	## The waypoints in use: the map's (BotNav's analysis, or the stand-in survey) and the ones learned from play.
	spots = arr.duplicate()
	spots.append_array(learned)
	spot_grid = {}
	claims = {}
	_cells_n = -1
	for i in spots.size():
		var k := _sg(spots[i].p)
		if not spot_grid.has(k):
			spot_grid[k] = []
		spot_grid[k].append(i)


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
	if nav.get("levels") != null:
		k += ",%d" % int(nav._last_lv)   # (r21) a storeyed map: the cell on this floor
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
	var levels: bool = nav.get("levels") != null
	for k in stuck_cells:
		var e = stuck_cells[k]
		if typeof(e) == TYPE_ARRAY and int(e[0]) >= BLOCK_AT and (e[1] as Array).size() >= 2 and stats.blocked_cells < MAX_BLOCKED:
			var s := str(k).split(",")
			if levels != (s.size() == 3):
				continue   # a file from before r21 (no floor in the key) or from another kind of map
			if levels:
				nav._last_lv = int(s[2])
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
	# (r21) stuck cells belong to one build of the map: a new build (a fixed wall, a moved shop) starts them afresh.
	var same_build: bool = str(d.get("key", "")) == BotNav.key
	if not same_build:
		d["stuck"] = {}
	for k3 in d.get("spot_stats", {}):
		var v3: Array = d.spot_stats[k3]
		if v3.size() == 4:
			spot_stats[str(k3)] = [float(v3[0]) * 0.8, float(v3[1]) * 0.8, float(v3[2]) * 0.8, float(v3[3]) * 0.8]
	for s0 in d.get("learned", []):
		var sp := _spot_in(s0)
		if sp.is_empty():
			continue
		if BotNav.nav != null and not BotNav.nav.walkable_at(sp.p):
			continue
		learned.append(sp)
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
	stats.learned_spots = learned.size()
	print("[bots] learned from %d cells, %d stuck spots, %d spots learned from play, %d spot records (%s)" % [memory.size(),
		stuck_cells.size(), learned.size(), spot_stats.size(), _path()])


static func save() -> void:
	if world == null or not learning():
		return
	Waypoints.save_learned()   # r23: the waypoint edges bots got stuck on
	var cells := {}
	for k in memory:
		var v: Array = memory[k]
		if float(v[0]) + float(v[1]) + float(v[2]) + float(v[3]) > 0.05:
			cells[k] = [snappedf(float(v[0]), 0.01), snappedf(float(v[1]), 0.01), snappedf(float(v[2]), 0.01), snappedf(float(v[3]), 0.01)]
	var ss := {}
	for k2 in spot_stats:
		var v2: Array = spot_stats[k2]
		if float(v2[0]) + float(v2[1]) / 60.0 + float(v2[2]) + float(v2[3]) > 0.05:
			ss[k2] = [snappedf(float(v2[0]), 0.01), snappedf(float(v2[1]), 0.1), snappedf(float(v2[2]), 0.01), snappedf(float(v2[3]), 0.01)]
	var ls := []
	for s in learned:
		ls.append(_spot_out(s))
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": 2, "map": map_id(), "key": BotNav.key, "cells": cells, "stuck": stuck_cells,
			"spot_stats": ss, "learned": ls}))
		print("[bots] saved %d learned cells, %d spot records, %d spots learned from play to %s" % [cells.size(), ss.size(), ls.size(), _path()])


# ------------------------------------------------------------------ r21: popular spots, spots learned from play

static func skey(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x), roundi(p.y), roundi(p.z)]


static func _st(p: Vector3) -> Array:
	var k := skey(p)
	if not spot_stats.has(k):
		spot_stats[k] = [0.0, 0.0, 0.0, 0.0]
	return spot_stats[k]


static func popularity(i: int) -> float:
	## How much the bots (and the players they watched) like a spot: held often and long, scored from, not died in.
	var v = spot_stats.get(skey(spots[i].p))
	if v == null:
		return 0.0
	return float(v[0]) * 0.6 + float(v[1]) / 45.0 + float(v[2]) * 2.0 - float(v[3]) * 1.5


static func spot_at(p: Vector3, r: float) -> int:
	## The nearest spot within r of p on p's floor, or -1.
	var best := -1
	var bd := r
	for i in spots_near(p, r):
		var q: Vector3 = spots[i].p
		if absf(q.y - p.y) > 1.6:
			continue
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


static func spot_used(i: int, secs: float = 0.0) -> void:
	if i < 0 or i >= spots.size():
		return
	var v := _st(spots[i].p)
	if secs <= 0.0:
		v[0] = float(v[0]) + 1.0
	else:
		v[1] = float(v[1]) + secs


static func claim(i: int, eid: int, secs: float) -> void:
	claims[i] = [eid, Time.get_ticks_msec() + int(secs * 1000.0)]


static func claimed(i: int, eid: int) -> bool:
	## Another bot is heading for (or holding) this spot, or one within 3 m of it.
	var now := Time.get_ticks_msec()
	var p: Vector3 = spots[i].p
	for j in claims:
		var c: Array = claims[j]
		if int(c[0]) == eid or int(c[1]) < now or j >= spots.size():
			continue
		if j == i or (spots[j].p as Vector3).distance_to(p) < 3.0:
			return true
	return false


static func release(eid: int) -> void:
	for j in claims.keys():
		if int(claims[j][0]) == eid:
			claims.erase(j)


static func _learn_spot(p: Vector3, why: String) -> int:
	## A place a player camped or scored from: counted on the spot there, or a new learned spot when none is near.
	var i := spot_at(p, 2.2)
	if i >= 0:
		return i
	if learned.size() >= LEARNED_MAX or BotNav.nav == null or not BotNav.nav.walkable_at(p):
		return -1
	var s: Dictionary = BotNav.look_round(p)
	if s.is_empty() or str(s.kind) == "open":
		return -1
	s.src = "learned"
	s.name = why
	learned.append(s)
	spots.append(s)
	var k := _sg(s.p)
	if not spot_grid.has(k):
		spot_grid[k] = []
	spot_grid[k].append(spots.size() - 1)
	stats.learned_spots = learned.size()
	return spots.size() - 1


static func tick(dt: float) -> void:
	## Every server tick while bots play: the map analysis, and (twice a second) where the human players camp.
	if world == null:
		return
	if Game.arg("navdebug_quit") != null or Game.arg("navprobe") != null:
		# --navdebug / --navprobe runs that only want the nav report (debug/nav_probe.gd), then quit
		BotNav.finish_now()
		if Game.arg("navprobe") != null:
			preload("res://src/debug/nav_probe.gd").run(world, BotNav.nav)
		_quit()
		return
	if Game.arg("wpcheck") != null:
		_quit()   # r23: the editor's check ran in Waypoints.prepare
		return
	if Game.arg("wpqa") != null and Waypoints.ready():
		# r23: the waypoint graph's strict check (debug/waypoint_qa.gd), then quit
		preload("res://src/debug/waypoint_qa.gd").run(world, BotNav.nav, str(Game.arg("wpqa")))
		_quit()
		return
	if Game.arg("botnav_bake") != null and BotNav.phase == "spots":
		# Making the file the game ships with: the whole analysis now, written under res://data/botnav, then quit.
		BotNav.bake_to_res()
		print("[botnav] baked %s: %s" % [BotNav.map_id, str(BotNav.stats)])
		Waypoints.bake_to_res()   # r23: the waypoint graph, now the spots are known
		print("[waypoints] baked %s: %s" % [Waypoints.map_id, str(Waypoints.stats)])
		_quit()
		return
	BotNav.pump()
	Waypoints.tick()
	_skill_t += dt
	if _skill_t >= 15.0:
		_skill_t = 0.0
		_log_skill()
		if Game.arg("botlog") != null and log_on():
			_log_bots()
	_watch_t += dt
	if _watch_t < 0.5 or not learning():
		return
	var step := _watch_t
	_watch_t = 0.0
	for eid in world.characters:
		var c = world.characters[eid]
		if world.bots.has(eid) or c.mode != Motor.GROUND:
			_watch.erase(eid)
			continue
		var p: Vector3 = c.global_position
		var w: Array = _watch.get(eid, [p, 0.0])
		if (w[0] as Vector3).distance_to(p) > 1.2:
			w = [p, 0.0]
		else:
			w[1] = float(w[1]) + step
			if float(w[1]) >= CAMP_S:
				var i := _learn_spot(p, "camped by players")
				if i >= 0:
					var v := _st(spots[i].p)
					v[0] = float(v[0]) + 1.0
					v[1] = float(v[1]) + float(w[1])
				w = [p, -30.0]   # the same stay counts again only after another half minute
		_watch[eid] = w


static func _quit() -> void:
	## Debug and bake runs: let the stand-in survey's worker thread finish first (quitting under it crashed).
	if _spots_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_spots_task)
		_spots_task = -1
	world.get_tree().quit()


static func _spot_out(s: Dictionary) -> Dictionary:
	var p: Vector3 = s.p
	return {"p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "lv": int(s.get("lv", 0)), "kind": str(s.kind),
		"cover": int(s.cover), "sight": float(s.sight), "dir": [snappedf((s.dir as Vector2).x, 0.001), snappedf((s.dir as Vector2).y, 0.001)],
		"expo": float(s.get("expo", 0.5)), "src": "learned", "name": str(s.get("name", ""))}


static func _spot_in(d) -> Dictionary:
	if typeof(d) != TYPE_DICTIONARY or not d.has("p") or not d.has("dir"):
		return {}
	var p: Array = d.p
	var dv: Array = d.dir
	return {"p": Vector3(float(p[0]), float(p[1]), float(p[2])), "lv": int(d.get("lv", 0)), "kind": str(d.get("kind", "cover")),
		"cover": int(d.get("cover", 0)), "sight": float(d.get("sight", 0.0)), "dir": Vector2(float(dv[0]), float(dv[1])),
		"expo": float(d.get("expo", 0.5)), "src": "learned", "name": str(d.get("name", ""))}


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


# ------------------------------------------------------------------ r13: voice commands and lasers

static var laser_claims := {}   # holder eid -> [{p, eids, t}]: spots a teammate's laser picked out, and who went to check


static func laser_claim(holder_eid: int, p: Vector3, eid: int) -> bool:
	## A bot wants to go and check what holder's laser points at: yes for the first two bots per spot (within 6 m)
	## in 10 s.
	var now := Time.get_ticks_msec() / 1000.0
	var list: Array = laser_claims.get(holder_eid, [])
	list = list.filter(func(c): return now - float(c.t) < 10.0)
	for c in list:
		if (c.p as Vector3).distance_to(p) < 6.0:
			if eid in c.eids:
				return false
			if (c.eids as Array).size() >= 2:
				laser_claims[holder_eid] = list
				return false
			c.eids.append(eid)
			laser_claims[holder_eid] = list
			return true
	list.append({"p": p, "eids": [eid], "t": now})
	laser_claims[holder_eid] = list
	return true


const ORDER_OF := {"need_help": "help", "follow_me": "follow", "lets_go": "go", "fall_back": "fall_back"}


static func on_voice(speaker, line: String, aim: Vector3) -> Dictionary:
	## r13: speaker (a player, or a bot calling for help) said line on the team radio. The teammate bots it concerns
	## answer: those that answer "affirmative" have taken the order and do it; if none can, one says "negative".
	## Returns {took: [eids], refused: eid or -1}.
	var out := {"took": [], "refused": -1}
	if world == null or speaker == null:
		return out
	if line == "enemy_spotted":
		# Everyone near looks there; hunters go and have a look.
		for eid in world.bots:
			var b = world.bots[eid]
			if b.ch != speaker and b.ch.team == speaker.team and b.ch.mode == Motor.GROUND 					and (b.ch.global_position as Vector3).distance_to(speaker.global_position) < 120.0:
				b._look_at = aim
				if b.role in ["stalker", "rusher"] and b.target_eid < 0 and b.investigate == Vector3.INF:
					b.investigate = aim
		return out
	var kind: String = ORDER_OF.get(line, "")
	if kind == "":
		return out
	var reach: float = {"help": 160.0, "follow": 70.0, "go": 70.0, "fall_back": 90.0}[kind]
	var want: int = {"help": 2, "follow": 3, "go": 4, "fall_back": 8}[kind]
	var cands := []
	for eid in world.bots:
		var b = world.bots[eid]
		if b.ch == speaker or b.ch.team != speaker.team or b.ch.mode != Motor.GROUND:
			continue
		var d: float = (b.ch.global_position as Vector3).distance_to(speaker.global_position)
		if d <= reach:
			cands.append([d, b])
	cands.sort_custom(func(a, c): return float(a[0]) < float(c[0]))
	var fwd: Vector3 = -Basis(Vector3.UP, speaker.yaw).z
	var refused = null
	for c in cands:
		var b = c[1]
		if (out.took as Array).size() >= want:
			break
		if not b.can_take(kind):
			if refused == null:
				refused = b
			continue
		match kind:
			"follow":
				if Net.is_bot(speaker.pid):
					continue
				b.order = {}
				follow_human(b.ch.eid, speaker.eid)
			"help":
				b.take_order("help", speaker, speaker.global_position)
			"go":
				# Spread out round the point the caller is looking at.
				var off := Vector3(fwd.z, 0.0, -fwd.x) * (((out.took as Array).size() % 3) - 1) * 3.0
				b.take_order("go", speaker, aim + off)
			"fall_back":
				# Back to the caller, a few metres behind them.
				var off2 := Vector3(fwd.z, 0.0, -fwd.x) * (((out.took as Array).size() % 3) - 1) * 2.5
				b.take_order("fall_back", speaker, (speaker.global_position as Vector3) - fwd * 5.0 + off2)
		(out.took as Array).append(b.ch.eid)
		if (out.took as Array).size() <= 2:
			b.reply("affirmative", (out.took as Array).size() - 1)
	if (out.took as Array).is_empty() and refused != null:
		refused.reply("negative", 0)
		out.refused = refused.ch.eid
	return out


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
	if world.bots.has(victim.eid) and str(victim.health.last_cause) == "field" and world.match_server:
		var b = world.bots[victim.eid]
		world.match_server.log_event("[field death] %s (%s) state %s at %s goal %s path %d/%d no_prog %.1f pending %s" % [victim.pname, b.role, b.state,
			str(victim.global_position.round()), str((b.goal as Vector3).round()) if b.goal != Vector3.INF else "-", b.path_i, b.path.size(), b._no_prog, str(b._path_req != 0)])
		for line in b.hist:
			world.match_server.log_event("[field death]   %s" % line)
	var k = world.characters.get(attacker)
	mark(victim.global_position, "danger", 1.0)
	# (r21) the spots: died in, scored from (a player's kill from a new place teaches the bots that place)
	var vi := spot_at(victim.global_position, 2.0)
	if vi >= 0:
		var vv := _st(spots[vi].p)
		vv[3] = float(vv[3]) + 1.0
	if k != null and k != victim and k.team != victim.team and learning():
		var ki := spot_at(k.global_position, 2.2) if world.bots.has(attacker) else _learn_spot(k.global_position, "players scored from here")
		if ki >= 0:
			var kv := _st(spots[ki].p)
			kv[2] = float(kv[2]) + 1.0
	var kh: Array = victim.get_meta("killing_hit", [])
	var headshot: bool = not kh.is_empty() and str(kh[0]) == "head" and str(victim.health.last_cause) == "gunshot"
	if k != null and k != victim:
		var d: float = (k.global_position as Vector3).distance_to(victim.global_position)
		mark(k.global_position, "good", 1.0)
		if d > 45.0:
			mark(k.global_position, "snipe", 1.0)
		if world.bots.has(attacker):
			world.bots[attacker].on_scored(victim, d, headshot)
		elif k.team != victim.team:
			# r13: a player's kill: a teammate bot confirms it on the radio (the nearest one still standing).
			var best = null
			var bd := INF
			for eid in world.bots:
				var b0 = world.bots[eid]
				if b0.ch.team == k.team and b0.ch.mode in [Motor.GROUND, Motor.DOWNED]:
					var dd: float = (b0.ch.global_position as Vector3).distance_to(k.global_position)
					if dd < bd:
						bd = dd
						best = b0
			if best != null:
				best.reply("headshot_kill" if headshot else "kill", 0)
	# A teammate nearby says so.
	for eid in world.bots:
		var b = world.bots[eid]
		if b.ch != victim and b.ch.team == victim.team and b.ch.mode == Motor.GROUND \
				and b.ch.global_position.distance_to(victim.global_position) < 70.0:
			b.reply("down", 0)
			break
	leave_squad(victim.eid)
	sweep_done(victim.team, victim.eid)   # r22: its sweep cell is free for a teammate
	# Bots following a human who fell go their own way.
	var hs: Dictionary = squads.get(10000 + int(victim.eid), {})
	if not hs.is_empty():
		for e in (hs.members as Array).duplicate():
			if world.bots.has(e):
				world.bots[e].squad_id = -1
		squads.erase(10000 + int(victim.eid))


# ------------------------------------------------------------------ r22: the endgame, the team sweep, skill numbers

static func log_on() -> bool:
	return world != null and world.match_server != null and bool(world.match_server._log_on)


static func team_round(team: int) -> void:
	## The first bot of a team made for a round (Deathmatch rounds make every bot afresh) starts the team's endgame
	## state over: contact counted from now, no sweep cells checked, no endgame.
	if world == null:
		return
	var ms = world.match_server
	var key := "%d:%d" % [Game.match_seed, int(ms.round_number) if ms != null else 1]
	if str(_round_key.get(team, "")) == key:
		return
	_round_key[team] = key
	var now := Time.get_ticks_msec()
	_t0[team] = now
	contact_t[team] = now
	end_t.erase(team)
	_hint_t.erase(team)
	_cnt.erase(team)
	checked[team] = {}
	sweep_claims[team] = {}
	boards.erase(team)   # (a new round's bots get a fresh one)


static func board(team: int):
	## The team's blackboard (made on first use; a new one each round).
	if not boards.has(team):
		boards[team] = Blackboard.new()
	return boards[team]


static func contact(team: int) -> void:
	## One of the team's bots saw an enemy or was hit.
	contact_t[team] = Time.get_ticks_msec()


static func counts(team: int) -> Dictionary:
	## {mates, foes, quiet_s}: the team's standing members, the smallest other team still standing (99: none), and the
	## seconds since its bots last saw or were hit by an enemy. Recounted at most twice a second.
	var now := Time.get_ticks_msec()
	var c: Dictionary = _cnt.get(team, {})
	if c.is_empty() or now - int(c.t) >= 500:
		var per := {}
		for o in world.characters.values():
			if o.mode in [Motor.GROUND, Motor.DOWNED]:
				per[o.team] = int(per.get(o.team, 0)) + 1
		var foes := 99
		for t in per:
			if int(t) != team:
				foes = mini(foes, int(per[t]))
		c = {"t": now, "mates": int(per.get(team, 0)), "foes": foes}
		_cnt[team] = c
	c.quiet_s = (now - int(contact_t.get(team, now))) / 1000.0
	return c


static func note_endgame(team: int, on: bool, c: Dictionary) -> void:
	## A bot of the team found it in the endgame (or not): the start is kept for the hint, and logged once per entry.
	board(team).set_var(&"endgame", on)
	if not on:
		end_t.erase(team)
		return
	if end_t.has(team):
		return
	var now := Time.get_ticks_msec()
	end_t[team] = now
	if log_on() and now - int(_end_log.get(team, -100000)) > 10000:
		_end_log[team] = now
		world.match_server.log_event("[endgame] %s mates %d foes %d nocontact %ds" % [world.match_server.team_name(team),
			int(c.mates), int(c.foes), int(c.quiet_s)])


static func hint(team: int, after_s: float, rng: RandomNumberGenerator) -> Vector3:
	## The backstop: after_s seconds into the endgame without contact, the team learns roughly (within HINT_FUZZ) where
	## the nearest enemy to it is, again every HINT_EVERY_S. INF when none is due.
	if not end_t.has(team):
		return Vector3.INF
	var now := Time.get_ticks_msec()
	if now - maxi(int(end_t[team]), int(contact_t.get(team, 0))) < int(after_s * 1000.0) \
			or now - int(_hint_t.get(team, -10000000)) < int(HINT_EVERY_S * 1000.0):
		return Vector3.INF
	var sum := Vector3.ZERO
	var n := 0
	for o in world.characters.values():
		if o.team == team and o.mode == Motor.GROUND:
			sum += o.global_position
			n += 1
	if n == 0:
		return Vector3.INF
	var cen := sum / n
	var best = null
	var bd := INF
	for o in world.characters.values():
		if o.team != team and o.mode in [Motor.GROUND, Motor.DOWNED]:
			var d: float = (o.global_position as Vector3).distance_to(cen)
			if d < bd:
				bd = d
				best = o
	if best == null:
		return Vector3.INF
	_hint_t[team] = now
	var a := rng.randf() * TAU
	var r := rng.randf() * HINT_FUZZ
	var p: Vector3 = (best.global_position as Vector3) + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if log_on():
		world.match_server.log_event("[hint] %s: nearest enemy %s, %.0f m from the team, hint %.0f m off" % [
			world.match_server.team_name(team), best.pname, bd, r])
	return p


static func cell_of(p: Vector3) -> Vector3i:
	## The sweep cell: (x, z, floor). Floors only on storeyed maps (Malasugue Mall, Freight Delight).
	if _storeyed < 0:
		_storeyed = 1 if world != null and world.map.layout.has_method("level_of") else 0
	var fl: int = int(world.map.layout.level_of(p.y)) if _storeyed == 1 else 0
	return Vector3i(floori(p.x / SWEEP_CELL), floori(p.z / SWEEP_CELL), fl)


static func mark_seen(team: int, p: Vector3) -> void:
	## A bot of the team is here: its cell, and the neighbouring cells whose middle is within 18 m, are checked now.
	if not checked.has(team):
		checked[team] = {}
	var m: Dictionary = checked[team]
	var c := cell_of(p)
	var now := Time.get_ticks_msec()
	var q := Vector2(p.x, p.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector3i(c.x + dx, c.y + dz, c.z)
			if (dx != 0 or dz != 0) and Vector2((k.x + 0.5) * SWEEP_CELL, (k.y + 0.5) * SWEEP_CELL).distance_to(q) > 18.0:
				continue
			m[k] = now


static func _bucket() -> void:
	if _cells_n == spots.size():
		return
	_cells = {}
	for i in spots.size():
		var k := cell_of(spots[i].p)
		if not _cells.has(k):
			_cells[k] = []
		_cells[k].append(i)
	_cells_n = spots.size()


static func sweep_pick(team: int, eid: int, me: Vector3, lean: Vector3, rng: RandomNumberGenerator, usable: Callable) -> Dictionary:
	## Where a sweeping bot goes next: a waypoint (any kind, anywhere on the map) in the cell its team checked longest ago,
	## weighed against the walk there and leaning toward lean (the enemy's last known place, or its side), skipping cells
	## a teammate is sweeping and their neighbours. Claims the cell. {i, cell, stale} or {} when nowhere is stale.
	if spots.is_empty() or world == null:
		return {}
	_bucket()
	var now := Time.get_ticks_msec()
	var m: Dictionary = checked.get(team, {})
	if not sweep_claims.has(team):
		sweep_claims[team] = {}
	var cl: Dictionary = sweep_claims[team]
	var taken := {}
	for k0: Vector3i in cl.keys():
		var c0: Array = cl[k0]
		if int(c0[1]) < now:
			cl.erase(k0)
			continue
		if int(c0[0]) == eid:
			continue
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				taken[Vector3i(k0.x + dx, k0.y + dz, k0.z)] = true
	var never := int(_t0.get(team, now)) - 30000   # never checked: as if checked half a minute before the round
	var mc := cell_of(me)
	var best = null
	var bs := -INF
	var b_stale := 0.0
	for k: Vector3i in _cells:
		if taken.has(k):
			continue
		var stale: float = (now - int(m.get(k, never))) / 1000.0
		if stale < 25.0:
			continue
		var mx: float = (k.x + 0.5) * SWEEP_CELL
		var mz: float = (k.y + 0.5) * SWEEP_CELL
		var d: float = Vector2(mx - me.x, mz - me.z).length() + absf(float(k.z - mc.z)) * 12.0
		var sc := minf(stale, 240.0) * 0.25 - d * 0.12 + rng.randf_range(0.0, 6.0)
		if lean != Vector3.INF:
			sc += 15.0 * clampf(1.0 - Vector2(mx - lean.x, mz - lean.z).length() / 150.0, 0.0, 1.0)
		if sc > bs:
			bs = sc
			best = k
			b_stale = stale
	if best == null:
		return {}
	# The waypoint in that cell with the widest view (where a look round covers most).
	var sp := -1
	var ss := -INF
	for i in _cells[best]:
		var s: Dictionary = spots[i]
		if claimed(i, eid) or not bool(usable.call(s.p)):
			continue
		var v := float(s.sight) * 0.05 + rng.randf_range(0.0, 1.5)
		if v > ss:
			ss = v
			sp = i
	if sp < 0:
		m[best] = now   # nowhere to stand there: counted as checked, so the next pick goes elsewhere
		checked[team] = m
		return {}
	cl[best] = [eid, now + 90000]
	return {"i": sp, "cell": best, "stale": b_stale}


static func sweep_done(team: int, eid: int) -> void:
	var cl: Dictionary = sweep_claims.get(team, {})
	for k in cl.keys():
		if int(cl[k][0]) == eid:
			cl.erase(k)


static func skill_note(sk: String, what: String, v: float) -> void:
	## A bot's measured play, by skill: rounds fired, hits, damage dealt, seconds from first sight to first round.
	if not skill_stats.has(sk):
		skill_stats[sk] = {"shots": 0, "hits": 0, "dmg": 0.0, "react_s": 0.0, "react_n": 0}
	var s: Dictionary = skill_stats[sk]
	match what:
		"shots":
			s.shots = int(s.shots) + int(v)
		"hits":
			s.hits = int(s.hits) + 1
			s.dmg = float(s.dmg) + v
		"react":
			s.react_s = float(s.react_s) + v
			s.react_n = int(s.react_n) + 1


static func _log_bots() -> void:
	## --botlog: every standing bot, what it is doing (r22 diagnostics): name, state label, mind mode, order, goal distance.
	for eid in world.bots:
		var b = world.bots[eid]
		if b.ch.mode != Motor.GROUND:
			continue
		var p: Vector3 = b.ch.global_position
		var md: String = str(b.mind.mode()) if b.get("mind") != null else "-"
		world.match_server.log_event("[bot] %s t%d %s/%s role %s order %s goal %s end %s sq %d hold %.0f at %s" % [b.ch.pname, b.ch.team, b.state, md,
			b.role, str(b.order.get("kind", "-")), ("%.0fm" % p.distance_to(b.goal)) if b.goal != Vector3.INF else "-", str(b._end), b.squad_id,
			b._hold_t, str(p.round())])


static func note_state(label: String, dt: float) -> void:
	state_s[label] = float(state_s.get(label, 0.0)) + dt


static func _log_skill() -> void:
	if not log_on() or skill_stats.is_empty():
		return
	if not state_s.is_empty():
		var tot := 0.0
		for k in state_s:
			tot += float(state_s[k])
		var keys: Array = state_s.keys()
		keys.sort_custom(func(a, c): return float(state_s[a]) > float(state_s[c]))
		var parts := []
		for k in keys:
			parts.append("%s %.0f%%" % [k, 100.0 * float(state_s[k]) / maxf(tot, 0.001)])
		world.match_server.log_event("[botstates] %.0f bot-s: %s" % [tot, ", ".join(parts)])
	var per := {}
	for eid in world.bots:
		var sk := str(world.bots[eid].skill)
		per[sk] = int(per.get(sk, 0)) + 1
	for sk in skill_stats:
		var s: Dictionary = skill_stats[sk]
		var n := int(s.react_n)
		world.match_server.log_event("[botskill] %s shots %d hits %d reaction_avg %.2f (n %d) dmg %.0f bots %d" % [sk, int(s.shots),
			int(s.hits), float(s.react_s) / n if n > 0 else 0.0, n, float(s.dmg), int(per.get(sk, 0))])
