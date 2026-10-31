extends RefCounted
## (r15) Bot navigation on a storeyed map (Malasugue Mall): one walk grid per level (layout.nav_open, 1 m cells, closed
## under every wall, counter and balustrade the builder drew) joined by one-way links along the escalators (the way
## they move) and links up and down the fire stairs, searched as one graph (AStar3D). It answers the calls the bots
## make of NavGrid (request / take / cancel, reachable_near, line_clear, walkable_at, _idx / block_cell); searches are
## quick enough to run at once, so take() has the path on the next call.
##
## (r21) The layout's grids only know the walls the builder drew. BotNav (bot_nav.gd) checks every open cell against
## the real collision (a body standing there fits, with floor under it) and hands back the cells that fail (apply_bake);
## then finish() keeps the one connected walk (pockets bots could be sent into but never reach are dropped), weights
## the cells beside walls so paths run down the middle of a corridor, and the straightening of paths only skips
## corners where a body-wide band of open cells, and then a body-sized sweep through the real collision, is clear.

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
# r21
var world = null               # for the physics sweeps that confirm a straightened stretch (set by BotNav)
var clear_d: Array = []        # [level] -> PackedByteArray: cells to the nearest closed cell (1 = beside a wall), capped
var comp := PackedInt32Array() # point id -> component (the main walk is main_comp)
var main_comp := -1
var baked := 0                 # cells the physics check closed
var cut := 0                   # links between open cells the physics check cut (a wall on the line between them)
var _cut_cells: Array = []     # [level] -> {cell index: true}: cells beside a cut link (they count as beside a wall)
var _doors := {}               # Vector2i(4 m bucket) -> [{c, n, u, hw}]: every door's frame (centre on the floor, normal,
                               # along, half width): paths go through a doorway on its centre line
const BODY_R := 0.3            # Character capsule radius (rules movement.radius)
const BAND := 0.36             # half width of the band of open cells a straightened stretch needs
var _sweep_shape: CylinderShape3D = null
var _link_ends := {}           # point id -> true: the cells the escalators and stairs land on (the bake keeps them)
var _link_pts := PackedInt64Array()  # every point on an escalator or a stair (via points and landing cells)
var _escape := Vector3.INF     # a step out first, when the start had no straight way onto the walk (_start_near)
var _grid_pts := 0             # ids below this are grid cells; at or above, links' via points


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
	_grid_pts = pid
	for lk in L.nav_links:
		var a2 := _point_near(lk.a, 3)
		var b2 := _point_near(lk.b, 3)
		if a2 < 0 or b2 < 0:
			continue
		_link_ends[a2] = true
		_link_ends[b2] = true
		_link_pts.append(a2)
		_link_pts.append(b2)
		var prev := a2
		for v in lk.get("via", []):
			_astar.add_point(pid, v)
			_link_pts.append(pid)
			_astar.connect_points(prev, pid, bool(lk.get("both", false)))
			prev = pid
			pid += 1
		_astar.connect_points(prev, b2, bool(lk.get("both", false)))
		stats.links += 1
	stats.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("[nav] levels: %d points, %d links, %.0f ms" % [stats.points, stats.links, stats.build_ms])


# ------------------------------------------------------------------ r21: the physics check, components, clearance

func apply_bake(closed: Array, cuts: Array = []) -> void:
	## closed: [level] -> cell indices whose standing body hits geometry or has no floor (BotNav). Their points go.
	## cuts: [level] -> [i, j, ...] pairs of open cells with a wall on the line between them: disconnected.
	_cut_cells = []
	for lv2 in levels:
		var cc := {}
		if lv2 < cuts.size():
			var ids2: PackedInt32Array = _ids[lv2]
			var arr: Array = cuts[lv2]
			for k in range(0, arr.size() - 1, 2):
				var a := ids2[int(arr[k])]
				var b := ids2[int(arr[k + 1])]
				if a >= 0 and b >= 0 and _astar.are_points_connected(a, b):
					_astar.disconnect_points(a, b)
					cut += 1
				cc[int(arr[k])] = true
				cc[int(arr[k + 1])] = true
		_cut_cells.append(cc)
	for lv in mini(closed.size(), levels):
		var ids: PackedInt32Array = _ids[lv]
		for i in closed[lv]:
			var id := ids[int(i)]
			if id >= 0 and not _link_ends.has(id):
				_astar.remove_point(id)
				ids[int(i)] = -1
				baked += 1
		_ids[lv] = ids


func finish() -> void:
	## After the bake: clearance per cell (and the weights that keep paths off walls), then the components (pockets
	## dropped).
	var t0 := Time.get_ticks_usec()
	clear_d = []
	for lv in levels:
		var ids: PackedInt32Array = _ids[lv]
		var d := PackedByteArray()
		d.resize(nx * nz)
		d.fill(0)
		var front := PackedInt32Array()
		for i in nx * nz:
			if ids[i] < 0:
				continue
			var x := i % nx
			var z := i / nx
			var edge := x == 0 or z == 0 or x == nx - 1 or z == nz - 1
			if not edge:
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if ids[(z + dz) * nx + x + dx] < 0:
							edge = true
			if not edge and lv < _cut_cells.size() and (_cut_cells[lv] as Dictionary).has(i):
				edge = true   # a wall stands on the line to a neighbour
			if edge:
				d[i] = 1
				front.append(i)
		var k := 1
		while not front.is_empty() and k < 8:
			var nxt := PackedInt32Array()
			for i in front:
				var x2 := i % nx
				var z2 := i / nx
				for dz2 in range(-1, 2):
					for dx2 in range(-1, 2):
						var xx := x2 + dx2
						var zz := z2 + dz2
						if xx < 0 or zz < 0 or xx >= nx or zz >= nz:
							continue
						var j := zz * nx + xx
						if ids[j] >= 0 and d[j] == 0:
							d[j] = k + 1
							nxt.append(j)
			front = nxt
			k += 1
		for i2 in nx * nz:
			if ids[i2] >= 0 and d[i2] == 0:
				d[i2] = 8
		clear_d.append(d)
		# Paths keep off walls: a cell whose centre is under 0.6 m from a closed cell costs three times as much to cross.
		for i3 in nx * nz:
			var id3 := ids[i3]
			if id3 < 0:
				continue
			var m := (float(d[i3]) - 0.5) * cell
			_astar.set_point_weight_scale(id3, 3.0 if m < 0.6 else (1.6 if m < 1.0 else 1.0))
	_relink()
	_components()
	stats.finish_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("[nav] r21: %d cells closed by the physics check, main walk %d of %d points (%d in pockets), %.0f ms" % [baked,
		int(stats.get("main", 0)), _astar.get_point_count(), int(stats.get("pockets", 0)), stats.finish_ms])


func _ray_clear(a: Vector3, b: Vector3) -> bool:
	## Nothing solid across the line from a to b at hip height (a's floor).
	if world == null:
		return true
	var y = layout.level_y(_level(a)) + 0.9
	var rq := PhysicsRayQueryParameters3D.create(Vector3(a.x, y, a.z), Vector3(b.x, y, b.z), Defs.PHYS_WORLD | Defs.PHYS_GLASS)
	return world.get_world_3d().direct_space_state.intersect_ray(rq).is_empty()


func _nearest_link_point(p: Vector3, r: float) -> int:
	## The escalator or stair point nearest p (within r, and 1.5 m of its height), or -1.
	var best := -1
	var bd := r
	for id in _link_pts:
		if not _astar.has_point(id) or _astar.is_point_disabled(id):
			continue
		var q := _astar.get_point_position(id)
		if absf(q.y - p.y) > 1.5:
			continue
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = id
	return best


func _relink() -> void:
	## A link's landing cell kept by the bake but cut off from the floor around it (the cells beside it failed):
	## joined straight to the nearest open cells within two metres, both ways.
	for id in _link_ends:
		var grid_n := 0
		for o in _astar.get_point_connections(id):
			if o < _grid_pts:
				grid_n += 1
		if grid_n > 0:
			continue
		var p := _astar.get_point_position(id)
		var lv := _level(p)
		var ids: PackedInt32Array = _ids[lv]
		var c := _cell_of(p)
		var r := int(ceil(2.0 / cell))
		var joined := 0
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := c.x + dx
				var z := c.y + dz
				if (dx == 0 and dz == 0) or x < 0 or z < 0 or x >= nx or z >= nz:
					continue
				var o2 := ids[z * nx + x]
				if o2 >= 0 and joined < 3 and _ray_clear(p, _astar.get_point_position(o2)):
					_astar.connect_points(id, o2, true)
					joined += 1
		stats.relinked = int(stats.get("relinked", 0)) + 1


func _components() -> void:
	## A flood over every connection (links both ways): the largest set is the walk; the rest are pockets.
	var cap := 0
	for id0 in _astar.get_point_ids():
		cap = maxi(cap, id0 + 1)
	comp.resize(cap)
	comp.fill(-1)
	# links are one-way in AStar: note the reverse of each so the flood can cross them either way
	var back := {}
	var from_links: Array = range(_grid_pts, cap)
	from_links.append_array(_link_ends.keys())
	for id1 in from_links:
		if not _astar.has_point(id1):
			continue
		for o1 in _astar.get_point_connections(id1):
			if not back.has(o1):
				back[o1] = []
			back[o1].append(id1)
	var size := {}
	var label := 0
	for id in _astar.get_point_ids():
		if comp[id] >= 0:
			continue
		var stack := PackedInt64Array([id])
		comp[id] = label
		var n := 0
		while not stack.is_empty():
			var a := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			n += 1
			var nb := Array(_astar.get_point_connections(a))
			nb.append_array(back.get(a, []))
			for o in nb:
				if comp[o] < 0:
					comp[o] = label
					stack.append(o)
		size[label] = n
		label += 1
	var best := -1
	var bn := 0
	for l in size:
		if int(size[l]) > bn:
			bn = int(size[l])
			best = l
	main_comp = best
	var dropped := 0
	for id3 in _astar.get_point_ids():
		if comp[id3] != best:
			_astar.set_point_disabled(id3, true)
			dropped += 1
	stats.main = bn
	stats.pockets = dropped
	if Game.arg("navdebug") != null:
		# where the pockets are (level, bounds, size), largest first
		var boxes := {}
		for id4 in _astar.get_point_ids():
			var l4: int = comp[id4]
			if l4 == best:
				continue
			var p4 := _astar.get_point_position(id4)
			var bx: Array = boxes.get(l4, [p4, p4, 0])
			bx[0] = (bx[0] as Vector3).min(p4)
			bx[1] = (bx[1] as Vector3).max(p4)
			bx[2] = int(bx[2]) + 1
			boxes[l4] = bx
		var ls := boxes.keys()
		ls.sort_custom(func(u, v): return int(boxes[u][2]) > int(boxes[v][2]))
		for l5 in ls.slice(0, 25):
			print("[nav] pocket %d points, %s .. %s" % [int(boxes[l5][2]), str((boxes[l5][0] as Vector3).round()), str((boxes[l5][1] as Vector3).round())])


func level_of(p: Vector3) -> int:
	return _level(p)


func clearance_at(p: Vector3) -> float:
	## Metres from p's cell centre to the nearest closed cell (0 when p's cell is closed).
	if clear_d.is_empty():
		return 1.0
	var lv := _level(p)
	var c := _cell_of(p)
	var d: int = (clear_d[lv] as PackedByteArray)[c.y * nx + c.x]
	return 0.0 if d == 0 else (float(d) - 0.5) * cell


func open_cells(lv: int) -> PackedInt32Array:
	## Cell indices of the main walk on a level (BotNav samples its spots from these).
	var out := PackedInt32Array()
	var ids: PackedInt32Array = _ids[lv]
	for i in nx * nz:
		var id := ids[i]
		if id >= 0 and not _astar.is_point_disabled(id):
			out.append(i)
	return out


func cell_d(lv: int, i: int) -> int:
	return (clear_d[lv] as PackedByteArray)[i] if not clear_d.is_empty() else 3


func cell_pos(lv: int, i: int) -> Vector3:
	return Vector3(layout.nav_x0 + ((i % nx) + 0.5) * cell, layout.level_y(lv), layout.nav_z0 + ((i / nx) + 0.5) * cell)


func snap(p: Vector3, max_cells: int = 4) -> Vector3:
	## The centre of the open cell of the walk nearest p (or INF).
	var id := _point_near(p, max_cells)
	return _astar.get_point_position(id) if id >= 0 else Vector3.INF


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
	_escape = Vector3.INF
	var a := _start_near(from)
	var b := _point_near(to, 12)
	var out: Array = []
	if a >= 0 and b >= 0:
		var pts := _astar.get_point_path(a, b, true)
		out = _smooth(_through_doors(pts))
		if _escape != Vector3.INF:
			out.push_front(_escape)   # the step out of the dead end comes first
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats.searches += 1
	stats.ms_total += ms
	stats.ms_max = maxf(stats.ms_max, ms)
	return out


func _door_index() -> void:
	_doors = {}
	if world == null:
		return
	for d in world.map.dyn.doors:
		var node = d.get("node")
		if node == null or not (node.get("base") is Transform3D):
			continue
		var b: Transform3D = node.base
		var c: Vector3 = b * Vector3(float(node.w) * 0.5, 0.0, 0.0)
		var n := Vector3(b.basis.z.x, 0.0, b.basis.z.z).normalized()
		var u := Vector3(b.basis.x.x, 0.0, b.basis.x.z).normalized()
		var k := Vector2i(floori(c.x / 4.0), floori(c.z / 4.0))
		if not _doors.has(k):
			_doors[k] = []
		_doors[k].append({"c": c, "n": n, "u": u, "hw": float(node.w) * 0.5})
	_doors[Vector2i(1 << 20, 0)] = []   # indexed (even with no doors)


func _through_doors(pts: PackedVector3Array) -> PackedVector3Array:
	## r21: a step of the path that crosses a doorway is bent through the middle of it: 1.4 m before the door on its
	## centre line, then 0.8 m beyond. The 1 m cells rarely line up with a 1.2 m door, and a path through a cell centre
	## at the edge of the opening ran the body into the frame.
	if world == null or pts.size() < 2:
		return pts
	if _doors.is_empty():
		_door_index()
	var out := PackedVector3Array()
	out.append(pts[0])
	for i in range(1, pts.size()):
		var p := pts[i - 1]
		var q := pts[i]
		if absf(p.y - q.y) < 0.1:
			var mid := (p + q) * 0.5
			var k := Vector2i(floori(mid.x / 4.0), floori(mid.z / 4.0))
			var done := false
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if done:
						break
					for d in _doors.get(k + Vector2i(dx, dz), []):
						var c: Vector3 = d.c
						if absf(c.y - p.y) > 1.2:
							continue
						var sp := (p - c).dot(d.n)
						var sq := (q - c).dot(d.n)
						if sp * sq >= 0.0:
							continue
						var x := p + (q - p) * (sp / (sp - sq))
						if absf((x - c).dot(d.u)) > float(d.hw) + 0.8:
							continue
						var s := signf(sp)
						var cy := Vector3(c.x, p.y, c.z)
						out.append(cy + (d.n as Vector3) * s * 1.4)
						out.append(cy - (d.n as Vector3) * s * 0.8)
						done = true
						break
		out.append(q)
	return out


func _start_near(p: Vector3) -> int:
	## r21: the open cell nearest p that a body can walk to from p in a straight line (the nearest one can be on the
	## far side of a thin wall: the path then led back into it). On a stair or an escalator, off the floor's grid: the
	## nearest point of that stair or escalator (the nearest floor cell to a half landing was behind the core's wall).
	var lv := _level(p)
	if absf(p.y - layout.level_y(lv)) > 0.7:
		var v := _nearest_link_point(p, 3.0)
		if v >= 0:
			return v
	var ids: PackedInt32Array = _ids[lv]
	var c := _cell_of(p)
	var r := int(ceil(2.0 / cell))
	var cands := []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := c.x + dx
			var z := c.y + dz
			if x < 0 or z < 0 or x >= nx or z >= nz:
				continue
			var id := ids[z * nx + x]
			if id >= 0 and not _astar.is_point_disabled(id):
				cands.append([dx * dx + dz * dz, id])
	if cands.is_empty():
		return _point_near(p, 8)
	cands.sort_custom(func(u, v): return int(u[0]) < int(v[0]))
	for k in mini(cands.size(), 6):
		var q := _astar.get_point_position(int(cands[k][1]))
		if int(cands[k][0]) == 0 or _sweep_clear(p, q):
			return int(cands[k][1])
	# none in plain sight: a stair or escalator point close by
	var v2 := _nearest_link_point(p, 2.5)
	if v2 >= 0:
		return v2
	# still none: the bot is somewhere the walk does not go (the dead end under a fire stair, behind a counter). The
	# nearest cells were outside the building's wall there; look further, up to 8 m, for one it can walk to.
	var far := _reachable_cell(p, int(ceil(8.0 / cell)))
	if far >= 0:
		return far
	# no straight way out at all (under a fire stair the first flight's underside is in the way): one step to the side
	# first (1.5 or 3 m, sixteen ways), then a straight line from there
	for dist in [1.5, 3.0]:
		for k in 16:
			var d := Vector3(cos(TAU * k / 16.0), 0.0, sin(TAU * k / 16.0))
			var m := p + d * float(dist)
			if not _sweep_clear(p, m):
				continue
			var q := _reachable_cell(m, int(ceil(6.0 / cell)))
			if q >= 0:
				_escape = m
				return q
	return int(cands[0][1])


func _reachable_cell(p: Vector3, r: int) -> int:
	## The nearest open cell within r cells of p that a body can walk to from p in a straight line, or -1.
	var lv := _level(p)
	var ids: PackedInt32Array = _ids[lv]
	var c := _cell_of(p)
	var cands := []
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := c.x + dx
			var z := c.y + dz
			if x < 0 or z < 0 or x >= nx or z >= nz:
				continue
			var id := ids[z * nx + x]
			if id >= 0 and not _astar.is_point_disabled(id):
				cands.append([dx * dx + dz * dz, id])
	cands.sort_custom(func(u, v): return int(u[0]) < int(v[0]))
	var tried := 0
	for e in cands:
		var q := _astar.get_point_position(int(e[1]))
		tried += 1
		if tried > 250:
			break
		# a cheap ray first: most of the near cells there are behind a wall
		if _ray_clear(p, q) and _sweep_clear(p, q):
			return int(e[1])
	return -1


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
			if absf(pts[k].y - pts[i].y) < 0.1 and _same_level_run(pts, i, k) and _band_clear(pts[i], pts[k]) and _sweep_clear(pts[i], pts[k]):
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
	## The nearest point of the walk to goal (on goal's level; on the bot's own when that level has none near).
	var id := _point_near(goal, mini(max_cells, 12))
	if id < 0:
		id = _point_near(Vector3(goal.x, from.y, goal.z), mini(max_cells, 12))
	if id < 0:
		return goal
	var p := _astar.get_point_position(id)
	return Vector3(p.x, goal.y if absf(goal.y - p.y) < 1.0 else p.y, p.z)


func line_clear(a: Vector3, b: Vector3) -> bool:
	## Open cells all the way from a to b on a's level (b on another level: not clear), and (r21) no wall across the
	## line at hip height.
	if not _cells_clear(a, b):
		return false
	if world == null:
		return true
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(Vector3(a.x, layout.level_y(_level(a)) + 0.9, a.z), Vector3(b.x, layout.level_y(_level(a)) + 0.9, b.z), Defs.PHYS_WORLD | Defs.PHYS_GLASS)
	return space.intersect_ray(rq).is_empty()


func _cells_clear(a: Vector3, b: Vector3) -> bool:
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


func _band_clear(a: Vector3, b: Vector3) -> bool:
	## r21: open cells under a body-wide band from a to b on a's level (samples every quarter cell, the centre line and
	## both edges), so a straightened stretch never clips a wall's corner the way a one-cell line did.
	var lv := _level(a)
	if _level(b) != lv:
		return false
	var ids: PackedInt32Array = _ids[lv]
	var d := Vector2(b.x - a.x, b.z - a.z)
	var len := d.length()
	if len < 0.01:
		return true
	var u := d / len
	var side := Vector2(-u.y, u.x) * BAND
	var n2 := int(ceil(len / (cell * 0.25)))
	for s in n2 + 1:
		var q := Vector2(a.x, a.z) + d * (float(s) / n2)
		for o in [Vector2.ZERO, side, -side]:
			var c: Vector2i = layout.nav_cell(q + o)
			var id := ids[c.y * nx + c.x]
			if id < 0 or _astar.is_point_disabled(id):
				return false
	return true


func _sweep_clear(a: Vector3, b: Vector3) -> bool:
	## r21: a body-sized cylinder moved from a to b (above step height) meets nothing: the real collision, not the grid.
	if world == null:
		return true
	if _sweep_shape == null:
		_sweep_shape = CylinderShape3D.new()
		_sweep_shape.radius = BODY_R - 0.02
		_sweep_shape.height = 1.2
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sweep_shape
	q.collision_mask = Defs.MOVE_MASK
	q.transform = Transform3D(Basis(), a + Vector3.UP * 1.05)
	q.motion = Vector3(b.x - a.x, 0.0, b.z - a.z)
	var r := space.cast_motion(q)
	return r.size() == 2 and float(r[0]) >= 0.999


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
	if c.x < 0 or c.y < 0 or c.x >= nx or c.y >= nz or _last_lv < 0 or _last_lv >= levels:
		return
	var id: int = _ids[_last_lv][c.y * nx + c.x]
	if id >= 0:
		_astar.set_point_disabled(id, true)
