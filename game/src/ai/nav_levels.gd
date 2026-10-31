extends RefCounted
## (r15) Bot navigation on a storeyed map (Malasugue Mall): one walk grid per level (layout.nav_open, 1 m cells, closed
## under every wall, counter and balustrade the builder drew) joined by one-way links along the escalators (the way
## they move) and links up and down the fire stairs, searched as one graph (AStar3D). It answers the calls the bots
## make of NavGrid (request / take / cancel, reachable_near, line_clear, walkable_at, _idx / block_cell); searches are
## quick enough to run at once, so take() has the path on the next call.

var layout = null
var levels := 0
var nx := 0
var nz := 0
var cell := 1.0
var n := 0                     # NavGrid's square size: 0 here (the waypoint survey skips a level map)
var walk := PackedByteArray()  # Level 1's grid, for callers that look at one
var _astar := AStar3D.new()
var _ids: Array = []           # [level] -> PackedInt32Array: cell -> point id (-1 closed)
var _done := {}
var _next_id := 1
var _last_lv := 0
var stats := {"searches": 0, "ms_total": 0.0, "ms_max": 0.0, "points": 0, "links": 0}


func _init(L) -> void:
	var t0 := Time.get_ticks_usec()
	layout = L
	levels = int(L.LEVELS)
	nx = int(L.nav_nx)
	nz = int(L.nav_nz)
	cell = float(L.NAV_CELL)
	walk = L.nav_open[0]
	var pid := 0
	_astar.reserve_space(nx * nz * 2)
	for lv in levels:
		var g: PackedByteArray = L.nav_open[lv]
		var ids := PackedInt32Array()
		ids.resize(nx * nz)
		ids.fill(-1)
		var y: float = L.level_y(lv)
		for iz in nz:
			for ix in nx:
				var i := iz * nx + ix
				if g[i] == 1:
					_astar.add_point(pid, Vector3(L.nav_x0 + (ix + 0.5) * cell, y, L.nav_z0 + (iz + 0.5) * cell))
					ids[i] = pid
					pid += 1
		_ids.append(ids)
	for lv in levels:
		var ids2: PackedInt32Array = _ids[lv]
		for iz in nz:
			for ix in nx:
				var a := ids2[iz * nx + ix]
				if a < 0:
					continue
				var r := ids2[iz * nx + ix + 1] if ix + 1 < nx else -1
				var d := ids2[(iz + 1) * nx + ix] if iz + 1 < nz else -1
				if r >= 0:
					_astar.connect_points(a, r)
				if d >= 0:
					_astar.connect_points(a, d)
				# diagonals only where both straight neighbours are open (no cutting a wall's corner)
				if r >= 0 and d >= 0:
					var rd := ids2[(iz + 1) * nx + ix + 1]
					if rd >= 0:
						_astar.connect_points(a, rd)
				if ix > 0 and d >= 0:
					var l := ids2[iz * nx + ix - 1]
					var ld := ids2[(iz + 1) * nx + ix - 1]
					if l >= 0 and ld >= 0:
						_astar.connect_points(a, ld)
	stats.points = pid
	for lk in L.nav_links:
		var a2 := _point_near(lk.a, 3)
		var b2 := _point_near(lk.b, 3)
		if a2 < 0 or b2 < 0:
			continue
		var prev := a2
		for v in lk.get("via", []):
			_astar.add_point(pid, v)
			_astar.connect_points(prev, pid, bool(lk.get("both", false)))
			prev = pid
			pid += 1
		_astar.connect_points(prev, b2, bool(lk.get("both", false)))
		stats.links += 1
	stats.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("[nav] levels: %d points, %d links, %.0f ms" % [stats.points, stats.links, stats.build_ms])


func _level(p: Vector3) -> int:
	return layout.level_of(p.y)


func _cell_of(p: Vector3) -> Vector2i:
	return layout.nav_cell(Vector2(p.x, p.z))


func _point_near(p: Vector3, max_r: int = 6) -> int:
	## The open cell nearest p on p's level (spiralling out up to max_r cells), as an AStar point id, or -1.
	var lv := _level(p)
	var ids: PackedInt32Array = _ids[lv]
	var c := _cell_of(p)
	var best := -1
	var best_d := INF
	for r in max_r + 1:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var x := c.x + dx
				var z := c.y + dz
				if x < 0 or z < 0 or x >= nx or z >= nz:
					continue
				var id := ids[z * nx + x]
				if id >= 0 and not _astar.is_point_disabled(id):
					var d := float(dx * dx + dz * dz)
					if d < best_d:
						best_d = d
						best = id
		if best >= 0:
			return best
	return -1


# ------------------------------------------------------------------ the NavGrid interface

func request(from: Vector3, to: Vector3, _max_expand: int = 9000) -> int:
	var id := _next_id
	_next_id += 1
	_done[id] = find_path(from, to)
	return id


func take(id: int):
	if _done.has(id):
		var p = _done[id]
		_done.erase(id)
		return p
	return null


func cancel(id: int) -> void:
	_done.erase(id)


func pump() -> void:
	pass


func find_path(from: Vector3, to: Vector3) -> Array:
	var t0 := Time.get_ticks_usec()
	var a := _point_near(from, 6)
	var b := _point_near(to, 12)
	var out: Array = []
	if a >= 0 and b >= 0:
		var pts := _astar.get_point_path(a, b, true)
		out = _smooth(pts)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats.searches += 1
	stats.ms_total += ms
	stats.ms_max = maxf(stats.ms_max, ms)
	return out


func _smooth(pts: PackedVector3Array) -> Array:
	## Drop the waypoints a body can skip: on one level, any point between two that see each other across open cells.
	## Changes of level (escalators, stairs) keep both their ends.
	var out: Array = []
	if pts.is_empty():
		return out
	var i := 0
	out.append(pts[0])
	while i < pts.size() - 1:
		var j := i + 1
		var k := mini(i + 24, pts.size() - 1)
		while k > i + 1:
			if absf(pts[k].y - pts[i].y) < 0.1 and _same_level_run(pts, i, k) and line_clear(pts[i], pts[k]):
				j = k
				break
			k -= 1
		out.append(pts[j])
		i = j
	return out


func _same_level_run(pts: PackedVector3Array, i: int, k: int) -> bool:
	for q in range(i + 1, k):
		if absf(pts[q].y - pts[i].y) > 0.1:
			return false
	return true


func reachable_near(from: Vector3, goal: Vector3, max_cells: int = 20) -> Vector3:
	var id := _point_near(goal, mini(max_cells, 12))
	if id < 0:
		return goal
	var p := _astar.get_point_position(id)
	return Vector3(p.x, goal.y if absf(goal.y - p.y) < 1.0 else p.y, p.z)


func line_clear(a: Vector3, b: Vector3) -> bool:
	## Open cells all the way from a to b on a's level (b on another level: not clear).
	var lv := _level(a)
	if _level(b) != lv:
		return false
	var ids: PackedInt32Array = _ids[lv]
	var ca := _cell_of(a)
	var cb := _cell_of(b)
	var steps := maxi(absi(cb.x - ca.x), absi(cb.y - ca.y))
	if steps == 0:
		return true
	for s in steps + 1:
		var t := float(s) / steps
		var x := int(round(lerpf(ca.x, cb.x, t)))
		var z := int(round(lerpf(ca.y, cb.y, t)))
		var id := ids[z * nx + x]
		if id < 0 or _astar.is_point_disabled(id):
			return false
	return true


func walkable_at(p: Vector3) -> bool:
	var c := _cell_of(p)
	var id: int = _ids[_level(p)][c.y * nx + c.x]
	return id >= 0 and not _astar.is_point_disabled(id)


func same_region(a: Vector3, b: Vector3) -> bool:
	return true


func _idx(p: Vector3) -> Vector2i:
	_last_lv = _level(p)
	return _cell_of(p)


func _world(c: Vector2i) -> Vector3:
	return Vector3(layout.nav_x0 + (c.x + 0.5) * cell, layout.level_y(_last_lv), layout.nav_z0 + (c.y + 0.5) * cell)


func block_cell(c: Vector2i) -> void:
	## Bots stuck here twice: the cell closes (on the level last asked about by _idx).
	if c.x < 0 or c.y < 0 or c.x >= nx or c.y >= nz:
		return
	var id: int = _ids[_last_lv][c.y * nx + c.x]
	if id >= 0:
		_astar.set_point_disabled(id, true)
