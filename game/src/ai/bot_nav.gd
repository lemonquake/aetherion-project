extends RefCounted
## (r21) What the bots work out about a map before they play it, the way a player learns a level, saved so it is only
## worked out once. One system for every map:
##
## 1. The walk check (storeyed maps: the mall, Freight Delight). The layout's walk grids only know the walls the builder
##    drew; every open cell is tried against the real collision: floor under it within a step, and a standing body
##    (radius 0.32 m, from above step height to head height) fits there without touching anything (counters, kiosks,
##    wreckage, planters, shelving). Cells that fail close. Then every link between two open neighbours (straight and
##    diagonal) is tried with a ray between their centres at hip height: a wall or a pane of glass standing on the line
##    between two cells (on a 1 m grid a wall on a whole-metre line closed no cell at all, and paths ran through it)
##    cuts the link. NavLevels then drops unreachable pockets and keeps paths off walls (nav_levels.gd).
## 2. Waypoints and hiding spots. Candidate places (every couple of metres along walls, sparser in the open, plus the
##    places a map designates itself: layout.designated_spots()) are looked round from crouching eye height in 16
##    directions: how many directions are closed within 1.3 m (cover at the back and sides), how many open past 6 m
##    (exposure) and the longest view (and which way it looks). Kinds:
##      hide   low exposure, cover on three sides or more, a view of at least 6 m down an approach (ambush, camping);
##      snipe  a long view (35 m on a storeyed map, 60 m outdoors) with cover beside it;
##      cover  something solid beside it;
##      open   none of those (kept sparse: hunting routes use them).
##    Each spot faces the way it watches (dir), never a wall.
## 3. The file. Everything above is saved under the map's name and build (map id, fingerprint, game version):
##    res://data/botnav/<map>.json ships with the game (made with --botnav_bake), user://botnav/<map>.json is made on
##    a player's or server's first match on a build the shipped file does not match (the key also carries a hash of
##    the walk grids, so a moved wall or floor in the same version is noticed). The walk check runs at once
##    (a second or two, then never again); the spot analysis runs a few milliseconds a tick while the bots play, using
##    a quick grid survey until it is done.
##
## What the bots learn from play (which spots are popular: held, scored from, died at, and the places human players
## camp) is bot_team.gd's memory, saved per map after every match.

const VERSION := 1
const BODY_R := 0.32
const BAKE_LO := 0.40          # above step height (rules movement.step_height 0.36): sills and thresholds are walked
const BAKE_HI := 1.75
const RAYS := 16
const EYE := 1.05              # crouching eye height
const COVER_R := 1.3
const OPEN_R := 6.0

static var world = null
static var nav = null
static var key := ""
static var map_id := ""
static var phase := "idle"     # idle -> spots -> done
static var spots: Array = []   # the finished analysis (BotTeam.spots is set from it)
static var _cands: Array = []  # [{p, lv, src, kind?, name?, face?}]
static var _ci := 0
static var _out: Array = []
static var _closed: Array = []
static var _cuts: Array = []     # [level] -> [i, j, i, j, ...]: links between open cells that cross a wall
static var stats := {}
static var _bake_shape: CylinderShape3D = null


static func prepare(w, n) -> void:
	## Once per new nav (a new map build): the walk check from the saved file or worked out now, then the spots from
	## the file or a start on the analysis.
	world = w
	nav = n
	map_id = str(w.cfg.get("map", "kalinaw"))
	# The map's build: its fingerprint (doors, containers, props), its walk grids (any wall or floor that moved), the
	# game version and this file's format. Anything else and the saved analysis is not used.
	var gh := 0
	if n.get("levels") != null:
		for g in w.map.layout.nav_open:
			gh = hash([gh, hash(g)])
	else:
		gh = hash(n.walk)
	key = "%s|%s|%08x|%s|v%d" % [map_id, str(w.map.fingerprint), gh & 0xFFFFFFFF, str(ProjectSettings.get_setting("application/config/version", "")), VERSION]
	phase = "idle"
	spots = []
	_cands = []
	_out = []
	_ci = 0
	stats = {"source": "", "bake_ms": 0.0, "closed": 0, "candidates": 0, "spots_ms": 0.0, "kinds": {}}
	var levels: bool = n.get("levels") != null
	if levels:
		n.world = w
	# (--botnav_nobake: A/B without the walk check; --botnav_bake: making the shipped file, always from scratch)
	var cache := _read() if Game.arg("botnav_nobake") == null and Game.arg("botnav_bake") == null else {}
	if levels:
		if Game.arg("botnav_nobake") != null:
			_closed = []   # A/B: the layout's grid as it was, without the walk check
			_cuts = []
		elif cache.has("closed") and cache.has("cuts"):
			_closed = cache.closed
			_cuts = cache.cuts
		else:
			_closed = _bake()
			_cuts = _bake_links()
		n.apply_bake(_closed, _cuts)
		n.finish()
		stats.closed = int(n.baked)
		stats.cut = int(n.cut)
	if cache.has("spots"):
		spots = _spots_from(cache.spots)
		phase = "done"
		stats.source = str(cache.get("_from", ""))
		_publish()
		print("[botnav] %s: walk check and %d spots from %s %s" % [map_id, spots.size(), stats.source, str(stats.kinds)])
		return
	_make_candidates()
	phase = "spots"
	stats.source = "analysed"
	print("[botnav] %s: analysing %d candidate spots (walk check %s)" % [map_id, _cands.size(),
		"from file" if cache.has("closed") else "%.0f ms" % float(stats.bake_ms)])


static func pump(budget_us: int = 2500) -> void:
	## A few milliseconds a server tick until the spot analysis is done; then saved.
	if phase != "spots" or world == null:
		return
	var t0 := Time.get_ticks_usec()
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	while _ci < _cands.size() and Time.get_ticks_usec() - t0 < budget_us:
		var s = _analyse(space, _cands[_ci])
		if s != null:
			_out.append(s)
		_ci += 1
	stats.spots_ms = float(stats.spots_ms) + (Time.get_ticks_usec() - t0) / 1000.0
	if _ci >= _cands.size():
		spots = _thin(_out)
		phase = "done"
		_publish()
		_write()
		print("[botnav] %s: %d spots from %d candidates in %.0f ms of ticks %s" % [map_id, spots.size(), _cands.size(), float(stats.spots_ms), str(stats.kinds)])


static func finish_now() -> void:
	## (--botnav_bake) the whole analysis at once.
	while phase == "spots":
		pump(1000000)


# ------------------------------------------------------------------ 1. the walk check

static func _bake() -> Array:
	var t0 := Time.get_ticks_usec()
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	if _bake_shape == null:
		_bake_shape = CylinderShape3D.new()
		_bake_shape.radius = BODY_R
		_bake_shape.height = BAKE_HI - BAKE_LO
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _bake_shape
	q.collision_mask = Defs.MOVE_MASK
	q.exclude = _door_rids()
	var out := []
	var tried := 0
	for lv in int(nav.levels):
		var closed := PackedInt32Array()
		var ids: PackedInt32Array = nav._ids[lv]
		for i in ids.size():
			if ids[i] < 0:
				continue
			tried += 1
			var c: Vector3 = nav.cell_pos(lv, i)
			# floor within a step of the level (a raised container floor counts; a counter top does not)
			var rq := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 1.0, c + Vector3.DOWN * 0.8, Defs.MOVE_MASK)
			rq.exclude = q.exclude
			var hit := space.intersect_ray(rq)
			if hit.is_empty() or (hit.position as Vector3).y > c.y + 0.55:
				closed.append(i)
				continue
			var fy: float = (hit.position as Vector3).y
			q.transform = Transform3D(Basis(), Vector3(c.x, fy + (BAKE_LO + BAKE_HI) * 0.5, c.z))
			if not space.intersect_shape(q, 1).is_empty():
				closed.append(i)
		out.append(Array(closed))
	stats.bake_ms = (Time.get_ticks_usec() - t0) / 1000.0
	var n_closed := 0
	for a in out:
		n_closed += (a as Array).size()
	print("[botnav] walk check: %d of %d cells closed by the real collision, %.0f ms" % [n_closed, tried, float(stats.bake_ms)])
	return out


static func _bake_links() -> Array:
	## Every link between two open neighbours (right, down and both diagonals; the cells _bake closed left out) gets a
	## ray at 0.9 m between the cell centres. A hit cuts it.
	var t0 := Time.get_ticks_usec()
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var ex := _door_rids()
	var nx: int = nav.nx
	var nz: int = nav.nz
	var out := []
	var n_cut := 0
	for lv in int(nav.levels):
		var ids: PackedInt32Array = nav._ids[lv]
		var shut := {}
		for i0 in _closed[lv]:
			shut[int(i0)] = true
		var cuts := PackedInt32Array()
		var y: float = world.map.layout.level_y(lv) + 0.9
		for i in ids.size():
			if ids[i] < 0 or shut.has(i):
				continue
			var x := i % nx
			var z := i / nx
			var a: Vector3 = nav.cell_pos(lv, i)
			a.y = y
			for o in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				var xx: int = x + o.x
				var zz: int = z + o.y
				if xx < 0 or xx >= nx or zz >= nz:
					continue
				var j := zz * nx + xx
				if ids[j] < 0 or shut.has(j):
					continue
				var b: Vector3 = nav.cell_pos(lv, j)
				b.y = y
				var rq := PhysicsRayQueryParameters3D.create(a, b, Defs.MOVE_MASK)
				rq.exclude = ex
				rq.hit_from_inside = true
				if not space.intersect_ray(rq).is_empty():
					cuts.append(i)
					cuts.append(j)
		out.append(Array(cuts))
		n_cut += cuts.size() / 2
	stats.links_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("[botnav] link check: %d links between open cells cross a wall, %.0f ms" % [n_cut, float(stats.links_ms)])
	return out


static func _door_rids() -> Array:
	## Doors open: the walk check leaves their cells to the bots (which open them).
	var out := []
	for d in world.map.dyn.doors:
		var node = d.get("node")   # door.gd: a kinematic body by RID, no scene node
		if node != null and node.get("body") is RID and (node.body as RID).is_valid():
			out.append(node.body)
	return out


# ------------------------------------------------------------------ 2. spots

static func _make_candidates() -> void:
	_cands = []
	var L = world.map.layout
	if L.has_method("designated_spots"):
		for d in L.designated_spots():
			var p: Vector3 = d.p
			var snapped: Vector3 = nav.snap(p, 3) if nav.has_method("snap") else p
			if snapped == Vector3.INF:
				continue
			_cands.append({"p": snapped, "src": "map", "kind": str(d.get("kind", "")), "name": str(d.get("name", "")),
				"face": d.get("face", Vector3.INF)})
	if nav.get("levels") != null:
		# Along walls every 2 m (corners and recesses are where hiding spots are), in the open every 4 m.
		var wall_step := maxi(int(round(2.0 / float(nav.cell))), 1)
		var open_step := maxi(int(round(4.0 / float(nav.cell))), 1)
		for lv in int(nav.levels):
			for i in nav.open_cells(lv):
				var x: int = i % int(nav.nx)
				var z: int = i / int(nav.nx)
				var d2: int = nav.cell_d(lv, i)
				var near_wall: bool = float(d2) * float(nav.cell) <= 1.0
				var step := wall_step if near_wall else open_step
				if x % step == 0 and z % step == 0:
					_cands.append({"p": nav.cell_pos(lv, i), "src": "auto"})
	else:
		# A flat map (2 m walk grid): every 8 m of open ground in the play area, as the old survey did.
		var n: int = nav.n
		for z2 in range(2, n - 1, 4):
			for x2 in range(2, n - 1, 4):
				if nav.walk[z2 * n + x2] == 0:
					continue
				var p2: Vector3 = nav._world(Vector2i(x2, z2))
				if not L.in_play_area(Vector2(p2.x, p2.z)):
					continue
				_cands.append({"p": p2, "src": "auto"})
	stats.candidates = _cands.size()


static func _analyse(space: PhysicsDirectSpaceState3D, c: Dictionary):
	var p: Vector3 = c.p
	var levels: bool = nav.get("levels") != null
	var reach := 45.0 if levels else 70.0
	var eye := p + Vector3.UP * EYE
	var dists := PackedFloat32Array()
	dists.resize(RAYS)
	var cover := 0
	var open := 0
	var best := 0.0
	var best_k := 0
	for k in RAYS:
		var a := TAU * k / RAYS
		var d := Vector3(cos(a), 0.0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + d * reach, Defs.SIGHT_MASK)
		var r := space.intersect_ray(q)
		var dist := reach if r.is_empty() else Vector2((r.position as Vector3).x - eye.x, (r.position as Vector3).z - eye.z).length()
		dists[k] = dist
		if dist < COVER_R:
			cover += 1
		if dist >= OPEN_R:
			open += 1
		if dist > best:
			best = dist
			best_k = k
	var expo := float(open) / RAYS
	# The way it watches: the longest view, or the designated facing.
	var face = c.get("face", Vector3.INF)
	var dir := Vector2(cos(TAU * best_k / RAYS), sin(TAU * best_k / RAYS))
	if face is Vector3 and face != Vector3.INF:
		var fv: Vector3 = (face as Vector3) - p
		if Vector2(fv.x, fv.z).length() > 0.1:
			dir = Vector2(fv.x, fv.z).normalized()
	var snipe_m := 35.0 if levels else 60.0
	var kind := str(c.get("kind", ""))
	if kind == "":
		if expo <= 0.3 and cover >= 3 and best >= OPEN_R:
			kind = "hide"
		elif best >= snipe_m and cover >= 1 and expo <= 0.6:
			kind = "snipe"
		elif cover >= 2:
			kind = "cover"
		else:
			kind = "open"
	var lv: int = nav.level_of(p) if nav.has_method("level_of") else 0
	return {"p": p, "lv": lv, "kind": kind, "cover": cover, "sight": snappedf(best, 0.1), "dir": dir, "expo": snappedf(expo, 0.01),
		"src": str(c.get("src", "auto")), "name": str(c.get("name", ""))}


static func _thin(arr: Array) -> Array:
	## One spot per few metres: designated spots first, then hiding, sniping, cover and open places, best first.
	var rank := {"hide": 0, "snipe": 1, "cover": 2, "open": 3}
	var keyed := []
	for s in arr:
		var r: float = float(rank.get(str(s.kind), 3)) - (10.0 if str(s.src) == "map" else 0.0) + float(s.expo) - float(s.cover) * 0.05
		keyed.append([r, s])
	keyed.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out := []
	var grid := {}
	var levels: bool = nav.get("levels") != null
	for e in keyed:
		var s: Dictionary = e[1]
		var gap: float = {"hide": 2.5, "snipe": 4.0, "cover": 4.0, "open": 8.0}.get(str(s.kind), 6.0) * (1.0 if levels else 2.0)
		if str(s.src) == "map":
			gap = 0.5
		var p: Vector3 = s.p
		var gk := Vector3i(floori(p.x / 8.0), int(s.lv), floori(p.z / 8.0))
		var clash := false
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for o in grid.get(gk + Vector3i(dx, 0, dz), []):
					if (o as Vector3).distance_to(p) < gap:
						clash = true
		if clash:
			continue
		if not grid.has(gk):
			grid[gk] = []
		grid[gk].append(p)
		out.append(s)
	return out


static func _publish() -> void:
	var kinds := {}
	for s in spots:
		kinds[str(s.kind)] = int(kinds.get(str(s.kind), 0)) + 1
	stats.kinds = kinds
	preload("res://src/ai/bot_team.gd").set_spots(spots)


# ------------------------------------------------------------------ 3. the file

static func _paths() -> Array:
	return ["res://data/botnav/%s.json" % map_id, "user://botnav/%s.json" % map_id]


static func _read() -> Dictionary:
	for path in _paths():
		if not FileAccess.file_exists(path):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY and str(d.get("key", "")) == key:
			d["_from"] = path
			return d
	return {}


static func _write(to_res: bool = false) -> void:
	var path: String = _paths()[0] if to_res else _paths()[1]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var out := []
	for s in spots:
		var p: Vector3 = s.p
		out.append({"p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "lv": int(s.lv), "kind": str(s.kind),
			"cover": int(s.cover), "sight": float(s.sight), "dir": [snappedf((s.dir as Vector2).x, 0.001), snappedf((s.dir as Vector2).y, 0.001)],
			"expo": float(s.expo), "src": str(s.src), "name": str(s.name)})
	var d := {"key": key, "map": map_id, "spots": out}
	if nav.get("levels") != null:
		d["closed"] = _closed
		d["cuts"] = _cuts
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		print("[botnav] saved %s (%d spots)" % [path, out.size()])


static func bake_to_res() -> void:
	## --botnav_bake: finish the analysis now and write the file the game ships with (run from the source tree).
	finish_now()
	_write(true)


static func _spots_from(arr: Array) -> Array:
	var out := []
	for s in arr:
		var p: Array = s.p
		var dv: Array = s.dir
		out.append({"p": Vector3(float(p[0]), float(p[1]), float(p[2])), "lv": int(s.get("lv", 0)), "kind": str(s.kind), "cover": int(s.cover),
			"sight": float(s.sight), "dir": Vector2(float(dv[0]), float(dv[1])), "expo": float(s.get("expo", 0.5)), "src": str(s.get("src", "auto")),
			"name": str(s.get("name", ""))})
	return out


# ------------------------------------------------------------------ for one place (learned spots)

static func look_round(p: Vector3) -> Dictionary:
	## The same look round for a single place (a spot learned from play): kind, cover, sight, dir, expo.
	if world == null:
		return {}
	var r = _analyse(world.get_world_3d().direct_space_state, {"p": p, "src": "learned"})
	return r if r != null else {}
