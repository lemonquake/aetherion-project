extends RefCounted
## Coarse walkability grid for bots (2 m cells from the map layout: lanes, roads and open ground are walkable;
## water and house footprints are not). Searches run in the engine's AStarGrid2D (jump point search, octile) within
## one connected region; then line-of-sight smoothing. A goal in a region the bot cannot reach falls back to the
## old bounded GDScript search toward the closest reachable cell.

var layout = null
var n := 0
var half := 0.0
var cell := 2.0
var walk: PackedByteArray
var _g := PackedFloat32Array()
var _came := PackedInt32Array()
var _stamp := PackedInt32Array()
var _gen := 0
var _astar := AStarGrid2D.new()
var _region := PackedInt32Array()   # connected region id per cell (0 = not walkable)
var _edge := PackedByteArray()       # 1: walkable but beside something that is not (a wall, a house, a car)
var _block_queue: Array[Vector2i] = []  # cells to close once no search is running (bots got stuck there)
## Searches run one at a time on a worker thread (a long search across the slum takes tens of milliseconds);
## bots ask with request() and collect the path with take() on a later tick.
var _jobs: Array = []        # [id, from, to, max_expand] waiting
var _done := {}              # id -> path
var _task := -1
var _job: Array = []
var _job_cancelled := false
var _result: Array = []
var _next_id := 1
var stats := {"searches": 0, "ms_total": 0.0, "ms_max": 0.0}
const DX := [1, -1, 0, 0, 1, 1, -1, -1]
const DZ := [0, 0, 1, -1, 1, -1, 1, -1]


func _init(L) -> void:
	layout = L
	n = L._n
	half = L.HALF
	cell = L.GRID
	walk = PackedByteArray()
	walk.resize(n * n)
	# Lawless Sub (its layout has team spawns): its walls (5) block too, and paths keep a cell back from the walled
	# canals (no railing; bots slid in). The estero is a metre deep: bots may wade across it, at five times the cost
	# of dry ground, so they take a bridge when one is near.
	var sub_map: bool = "spawn_centres" in L
	var wade := PackedInt32Array()
	for i in n * n:
		var r: int = L._reserved[i]
		walk[i] = 1 if L._water[i] == 0 and r != 2 and r != 3 and not (sub_map and r == 5) else 0
	if sub_map:
		var edge := PackedInt32Array()
		for z in range(1, n - 1):
			for x in range(1, n - 1):
				var i2 := z * n + x
				if walk[i2] == 1 and int(L._reserved[i2]) == 4 and (L._water[i2 - 1] == 1 or L._water[i2 + 1] == 1 or L._water[i2 - n] == 1 or L._water[i2 + n] == 1):
					edge.append(i2)
		for i3 in edge:
			walk[i3] = 0
		for z2 in n:
			for x2 in n:
				var i4 := z2 * n + x2
				if L._water[i4] == 1 and (L.water_sd(L._cell(x2, z2)) as Vector2).x >= 0.0:
					walk[i4] = 1
					wade.append(i4)
		# (r10) Every standing stretch of the subdivision walls blocks, whatever else claimed its cells first: the layout
		# marks a wall cell only where nothing (a yard, a lot) had, which left long stretches of wall open on this grid
		# and bots walked into them and stayed there.
		for w in L.walls:
			var a: Vector2 = w.a
			var b: Vector2 = w.b
			var len := a.distance_to(b)
			var dir := (b - a) / maxf(len, 0.001)
			var t := 0.0
			while t <= len:
				if L.wall_open_at(w, t) == "":
					var c := _idx(Vector3(a.x + dir.x * t, 0.0, a.y + dir.y * t))
					walk[c.y * n + c.x] = 0
				t += 0.5
		# The estero beside a bridge: its bank under the deck is a wall two metres high, not a way onto the bridge.
		for r in L.bridge_rects:
			var rr: Rect2 = (r as Rect2).grow(3.0)
			for z3 in range(maxi(int((rr.position.y + half) / cell), 0), mini(int((rr.end.y + half) / cell) + 1, n)):
				for x3 in range(maxi(int((rr.position.x + half) / cell), 0), mini(int((rr.end.x + half) / cell) + 1, n)):
					var i6 := z3 * n + x3
					if L._water[i6] == 1:
						walk[i6] = 0
		# Bridge parapets run the whole length of each deck, over the banks too: no way on or off the deck across them
		# (bots took that line, slid along the parapet and off the end of the bank into the canal).
		for r2 in L.bridge_rects:
			var br: Rect2 = r2
			var along_x := br.size.x >= br.size.y
			for side in [0, 1]:
				var t2 := 0.0
				var length := br.size.x if along_x else br.size.y
				while t2 <= length:
					var pp: Vector2
					if along_x:
						pp = Vector2(br.position.x + t2, (br.position.y - 0.15) if side == 0 else (br.end.y + 0.15))
					else:
						pp = Vector2((br.position.x - 0.15) if side == 0 else (br.end.x + 0.15), br.position.y + t2)
					var c2 := _idx(Vector3(pp.x, 0.0, pp.y))
					walk[c2.y * n + c2.x] = 0
					t2 += 0.5
		var keep := PackedInt32Array()
		for i7 in wade:
			if walk[i7] == 1:
				keep.append(i7)
		wade = keep
	_astar.region = Rect2i(0, 0, n, n)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.jumping_enabled = not sub_map  # jump point search ignores the wading weights
	_astar.update()
	for i5 in wade:
		_astar.set_point_weight_scale(Vector2i(i5 % n, i5 / n), 5.0)
	for z in n:
		var x := 0
		while x < n:
			if walk[z * n + x] == 0:
				var x0 := x
				while x < n and walk[z * n + x] == 0:
					x += 1
				_astar.fill_solid_region(Rect2i(x0, z, x - x0, 1), true)
			else:
				x += 1
	_label_regions()
	_mark_edges()


func _mark_edges() -> void:
	## Straightened paths may not run through cells that touch an obstacle (except where they start or end): a line
	## cut across them grazed house corners and ran bots along walls, where a pilaster or a downpipe stopped them.
	_edge.resize(n * n)
	_edge.fill(0)
	for z in range(1, n - 1):
		for x in range(1, n - 1):
			var i := z * n + x
			if walk[i] == 0:
				continue
			for k in 8:
				var j: int = (z + int(DZ[k])) * n + x + int(DX[k])
				if walk[j] == 0 and layout._water[j] == 0:
					_edge[i] = 1
					break


func block_cell(c: Vector2i) -> void:
	## Close a cell the grid called open (bots kept getting stuck there). Applied between searches.
	if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
		return
	_block_queue.append(c)
	if _task < 0:
		_apply_blocks()


func _apply_blocks() -> void:
	for c in _block_queue:
		var i := c.y * n + c.x
		if walk[i] == 1:
			walk[i] = 0
			_astar.set_point_solid(c, true)
	_block_queue.clear()


func walkable_at(p: Vector3) -> bool:
	var c := _idx(p)
	return walk[c.y * n + c.x] == 1


func same_region(a: Vector3, b: Vector3) -> bool:
	var ca := _nearest_walkable(_idx(a))
	var cb := _nearest_walkable(_idx(b))
	var ra := _region[ca.y * n + ca.x]
	return ra != 0 and ra == _region[cb.y * n + cb.x]


func reachable_near(from: Vector3, goal: Vector3, max_cells: int = 20) -> Vector3:
	## The goal itself when a bot at `from` can walk there; otherwise the nearest open cell to it in the bot's own
	## region (within max_cells), or Vector3.INF. Stops bots pressing into a wall toward a goal on its far side.
	var cf := _nearest_walkable(_idx(from))
	var rf := _region[cf.y * n + cf.x]
	var cg := _idx(goal)
	if rf == 0:
		return goal
	if walk[cg.y * n + cg.x] == 1 and _region[cg.y * n + cg.x] == rf:
		return goal
	for r in range(1, max_cells + 1):
		var best := Vector2i(-1, -1)
		var bd := INF
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var q := cg + Vector2i(dx, dz)
				if q.x < 0 or q.y < 0 or q.x >= n or q.y >= n:
					continue
				var qi := q.y * n + q.x
				if walk[qi] == 1 and _region[qi] == rf:
					var dd := float(dx * dx + dz * dz)
					if dd < bd:
						bd = dd
						best = q
		if best.x >= 0:
			return _world(best)
	return Vector3.INF


func line_clear(a: Vector3, b: Vector3) -> bool:
	## A straight walk from a to b stays on open cells (used while a path is still being searched).
	return _clear(_nearest_walkable(_idx(a)), _idx(b))


func _label_regions() -> void:
	## Connected walkable regions. Diagonal steps may not cut corners, so regions are 4-connected: union the
	## horizontal runs of walkable cells that overlap a run in the row above.
	var rx0 := PackedInt32Array()
	var rx1 := PackedInt32Array()
	var rz := PackedInt32Array()
	var row_first := PackedInt32Array()
	row_first.resize(n + 1)
	for z in n:
		row_first[z] = rx0.size()
		var x := 0
		while x < n:
			if walk[z * n + x] == 1:
				var x0 := x
				while x < n and walk[z * n + x] == 1:
					x += 1
				rx0.append(x0)
				rx1.append(x - 1)
				rz.append(z)
			else:
				x += 1
	row_first[n] = rx0.size()
	var parent := PackedInt32Array()
	parent.resize(rx0.size())
	for i in parent.size():
		parent[i] = i
	for z in range(1, n):
		var a := row_first[z - 1]
		var b := row_first[z]
		while a < row_first[z] and b < row_first[z + 1]:
			if rx1[a] >= rx0[b] and rx1[b] >= rx0[a]:
				var ra := _find(parent, a)
				var rb := _find(parent, b)
				if ra != rb:
					parent[maxi(ra, rb)] = mini(ra, rb)
			if rx1[a] < rx1[b]:
				a += 1
			else:
				b += 1
	_region.resize(n * n)
	_region.fill(0)
	for i in rx0.size():
		var id := _find(parent, i) + 1
		var base := rz[i] * n
		for x in range(rx0[i], rx1[i] + 1):
			_region[base + x] = id


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		i = parent[i]
	return i


func _idx(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int((p.x + half) / cell), 0, n - 1), clampi(int((p.z + half) / cell), 0, n - 1))


func _nearest_walkable(c: Vector2i) -> Vector2i:
	if walk[c.y * n + c.x] == 1:
		return c
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var q := c + Vector2i(dx, dz)
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and walk[q.y * n + q.x] == 1:
					return q
	return c


func request(from: Vector3, to: Vector3, max_expand: int = 9000) -> int:
	var id := _next_id
	_next_id += 1
	_jobs.append([id, from, to, max_expand])
	pump()
	return id


func take(id: int):
	## The path for a request, or null while it is still being searched.
	pump()
	if _done.has(id):
		var p: Array = _done[id]
		_done.erase(id)
		return p
	return null


func cancel(id: int) -> void:
	_done.erase(id)
	for i in _jobs.size():
		if int(_jobs[i][0]) == id:
			_jobs.remove_at(i)
			return
	if not _job.is_empty() and int(_job[0]) == id:
		_job_cancelled = true


func pump() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if not _job_cancelled:
			_done[_job[0]] = _result
		_job = []
	if not _block_queue.is_empty():
		_apply_blocks()
	if _jobs.is_empty():
		return
	_job = _jobs.pop_front()
	_job_cancelled = false
	_task = WorkerThreadPool.add_task(_run_job, false, "bot path search")


func _run_job() -> void:
	var t0 := Time.get_ticks_usec()
	_result = find_path(_job[1], _job[2], _job[3])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats.searches += 1
	stats.ms_total += ms
	stats.ms_max = maxf(float(stats.ms_max), ms)


func find_path(from: Vector3, to: Vector3, max_expand: int = 9000) -> Array:
	## Weighted A* (w = 1.3) over the grid. Per-cell scratch arrays persist between calls and are invalidated by a
	## generation stamp, so a search allocates nothing proportional to the map. If the goal is not reached within
	## the budget, the path leads to the reached cell closest to it.
	var s := _nearest_walkable(_idx(from))
	var g := _nearest_walkable(_idx(to))
	if s == g:
		return [to]
	var rs := _region[s.y * n + s.x]
	if rs != 0 and rs == _region[g.y * n + g.x]:
		var ids: Array[Vector2i] = _astar.get_id_path(s, g)
		if ids.size() > 1:
			var cells_n := []
			for i in range(1, ids.size()):
				cells_n.append(ids[i].y * n + ids[i].x)
			return _smooth(s, cells_n, true, to)
	if _g.size() != n * n:
		_g.resize(n * n)
		_came.resize(n * n)
		_stamp.resize(n * n)
	_gen += 1
	var si := s.y * n + s.x
	var gi := g.y * n + g.x
	_g[si] = 0.0
	_came[si] = -1
	_stamp[si] = _gen
	var open := []  # binary heap of [f, idx, g]
	_push(open, [_h(s, g) * 1.3, si, 0.0])
	var best_i := si
	var best_h := _h(s, g)
	var expanded := 0
	var found := false
	while not open.is_empty() and expanded < max_expand:
		var cur: Array = _pop(open)
		var ci: int = cur[1]
		var cg: float = cur[2]
		if cg > _g[ci] + 1e-4:
			continue  # stale heap entry
		if ci == gi:
			found = true
			break
		expanded += 1
		var cx := ci % n
		var cz := ci / n
		for k in 8:
			var dx: int = DX[k]
			var dz: int = DZ[k]
			var nx: int = cx + dx
			var nz: int = cz + dz
			if nx < 0 or nz < 0 or nx >= n or nz >= n:
				continue
			var ni := nz * n + nx
			if walk[ni] == 0:
				continue
			if dx != 0 and dz != 0 and (walk[cz * n + nx] == 0 or walk[nz * n + cx] == 0):
				continue
			var ng: float = cg + (1.4142 if dx != 0 and dz != 0 else 1.0)
			if _stamp[ni] != _gen or ng < _g[ni]:
				_stamp[ni] = _gen
				_g[ni] = ng
				_came[ni] = ci
				var hh := _h(Vector2i(nx, nz), g)
				if hh < best_h:
					best_h = hh
					best_i = ni
				_push(open, [ng + hh * 1.3, ni, ng])
	var end_i := gi if found else best_i
	if end_i == si:
		return [to]
	var cells := []
	var k2 := end_i
	while k2 != si and k2 >= 0:
		cells.append(k2)
		k2 = _came[k2]
	cells.reverse()
	return _smooth(s, cells, found, to)


func _smooth(s: Vector2i, cells: Array, found: bool, to: Vector3) -> Array:
	## Keep only the cells where straight walking would leave the walkable area. Jump point search returns only the
	## turning points, so straight runs between them are checked the same way.
	var out := []
	var anchor := s
	var prev := s
	for ci in cells:
		var c := Vector2i(ci % n, ci / n)
		if not _clear(anchor, c):
			out.append(_world(prev))
			anchor = prev
		prev = c
	if not found:
		out.append(_world(prev))
	out.append(to)
	return out


func _world(c: Vector2i) -> Vector3:
	var x := -half + (c.x + 0.5) * cell
	var z := -half + (c.y + 0.5) * cell
	return Vector3(x, layout.ground_height(x, z), z)


func _clear(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	var steps := maxi(absi(d.x), absi(d.y))
	for i in steps + 1:
		var t := float(i) / maxf(steps, 1)
		var x := int(round(a.x + d.x * t))
		var z := int(round(a.y + d.y * t))
		var ci := z * n + x
		if walk[ci] == 0:
			return false
		# Beside an obstacle only at the ends (a lane one cell wide is all edge: its path keeps every cell).
		if i > 1 and i < steps - 1 and not _edge.is_empty() and _edge[ci] == 1:
			return false
	return true


func _h(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dz := absi(a.y - b.y)
	return float(maxi(dx, dz)) + 0.4142 * float(mini(dx, dz))


static func _push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if float(h[p][0]) <= float(h[i][0]):
			break
		var t = h[p]
		h[p] = h[i]
		h[i] = t
		i = p


static func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < h.size() and float(h[l][0]) < float(h[m][0]):
				m = l
			if r < h.size() and float(h[r][0]) < float(h[m][0]):
				m = r
			if m == i:
				break
			var t = h[m]
			h[m] = h[i]
			h[i] = t
			i = m
	return top
