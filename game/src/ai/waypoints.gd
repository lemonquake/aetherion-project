extends RefCounted
## (r23) The waypoint graph: the roads bots walk, on every map. Bots no longer walk a line the walk grid merely
## allows: they go node to node along edges that a body-sized cylinder was swept along through the real collision,
## with a margin, so a bot that keeps to its edge cannot touch a wall.
##
## Nodes (each with an id such as "MM3-0412", a kind, a priority and a place name):
##   road      on the middle line of a corridor, lane or street (the cells farthest from a wall), every 3.5 m indoors
##             and 8 m outdoors; junction where such a road meets two others or more;
##   area      filling the open ground the roads do not reach (no open cell is far from a node);
##   corner    the same, beside a wall (alcoves, the ends of shop aisles, nooks behind counters);
##   door      1.1 m either side of every door both of whose sides are walked;
##   stair / escalator   the ends and points of every stair flight and escalator (escalators one way);
##   hide / snipe / cover   the map's designated places and the best of the hiding and sniping spots (a facing too).
## Priority 1 (main road), 2 (secondary), 3 (side way, dead end): from how many of 400 sample routes across the map
## pass a node. Routes prefer high priorities (a lower priority costs 15% or 35% more to cross), so bots keep to the
## main roads the way players do. A map editor (the mall's: editor/malasugue_mall_editor.tscn) can set any of these.
## Edges: kind walk (the wide sweep passed: radius 0.40 m), tight (only the body-sized sweep passed: costs more), door
## (through a door, which the bot opens), stair, escalator (one way), wade (shallow water).
##
## The file: res://data/waypoints/<map>.json (shipped; made by tools/bake_botnav.sh), else user://waypoints/<map>.json.
## Its key is the map's geometry (map id, fingerprint, walk grids), not the game version. A graph made by the
## generator ("auto") is made again when the geometry changed; one saved from the editor ("edited") is kept and only
## its edges are checked again (an edge through a wall is dropped, with a warning).

const FORMAT := 1
const R_WIDE := 0.40          # body 0.30 m + 0.10 m margin
const R_TIGHT := 0.31
const R_FROM := 0.26          # from where a bot stands: thinner than the body (it may stand against a wall already)
const SWEEP_LO := 0.42        # above step height (rules movement.step_height 0.36): sills and thresholds are walked
const SWEEP_H := 1.2
const PRI_W := {1: 1.0, 2: 1.15, 3: 1.35}
const CODES := {"malasugue_mall": "MM", "freight_delight": "FD", "lawless_sub": "LS", "kalinaw": "SK"}
const KINDS := ["road", "junction", "plaza", "bridge", "area", "corner", "door", "stair", "escalator", "hide", "snipe", "cover"]
const EDGE_CODE := {"walk": "w", "tight": "t", "door": "d", "stair": "s", "escalator": "e", "wade": "v"}

static var world = null
static var nav = null
static var map_id := ""
static var key := ""
static var levels := false
static var phase := "off"      # off | ready
static var source := ""        # auto | edited
static var verified := ""      # the geometry key an edited graph was last checked against
static var nodes: Array = []   # [{id, p, lv, kind, pri, name, dir: Vector2, via, comp}]
static var edges: Array = []   # [{a, b, kind, door, one}]
static var adj: Array = []     # node -> [edge indices]
static var astar: AStar3D = null
static var main_comp := 0
static var stats := {}
static var _grid := {}         # Vector3i(cell, lv, cell) -> [node indices]
static var _bk := 6.0          # bucket size
static var _edge_of := {}      # a * 1000003 + b -> edge index (both orders)
static var _blocked := {}      # edge index -> {until, n}
static var _hits := {}         # edge index -> stuck reports this match
static var _learned := {}      # "idA|idB" -> stuck reports kept from earlier matches (user://waypoints/<map>_learn.json)
static var _doors_ex: Array = []
static var _door_list: Array = []   # [{c, n, u, hw, i}]
static var _deck := {}          # flat maps: walk-grid cells under a bridge deck (Sitio Kalinaw's crossings are not on the grid)
static var _shapes := {}
static var _q: PhysicsShapeQueryParameters3D = null


# ------------------------------------------------------------------ setup

static func prepare(w, n) -> void:
	## Once per new nav (a new map build), after BotNav: the graph from the saved file, else made now.
	world = w
	nav = n
	map_id = str(w.cfg.get("map", "kalinaw"))
	levels = n.get("levels") != null
	_bk = 6.0 if levels else 12.0
	phase = "off"
	stats = {"source": "", "nodes": 0, "edges": 0, "ms": 0.0}
	_blocked = {}
	_hits = {}
	_doors_ex = _door_rids()
	_door_list = _doors()
	_deck_cells()
	if Game.arg("waypoints_off") != null:
		print("[waypoints] off (--waypoints_off): bots walk the grid paths")
		return
	var gh := 0
	if levels:
		for g in w.map.layout.nav_open:
			gh = hash([gh, hash(g)])
	else:
		gh = hash(n.walk)
	key = "%s|%s|%08x|wp%d" % [map_id, str(w.map.fingerprint), gh & 0xFFFFFFFF, FORMAT]
	if Game.arg("botnav_bake") != null:
		return   # made after BotNav's spots, by bake_to_res()
	var t0 := Time.get_ticks_usec()
	var d := {} if Game.arg("waypoints_bake") != null else _read()
	if not d.is_empty() and _load(d):
		stats.source = str(d.get("_from", ""))
		if source == "edited" and verified != key:
			# hand-edited (or the map changed since): every edge proven again now, then kept checked in user://
			var dropped := _reverify()
			print("[waypoints] %s: the edited graph was checked against the map: %d edges failed and were dropped" % [map_id, dropped.size()])
			for e in dropped.slice(0, 20):
				print("[waypoints]   %s - %s: %s" % e)
			stats.source += " (checked now)"
			_finish()
			verified = key
			_write(false)
	else:
		generate()
		stats.source = "generated"
		_write(false)
	_finish()
	stats.ms = (Time.get_ticks_usec() - t0) / 1000.0
	phase = "ready"
	if Game.arg("wpcheck") != null:
		check_to_res()
	print("[waypoints] %s: %d nodes, %d edges (%s, %s), %d off the main graph, %.0f ms %s" % [map_id, nodes.size(), edges.size(),
		source, stats.source, int(stats.get("orphans", 0)), float(stats.ms), str(stats.get("kinds", {}))])


static func ready() -> bool:
	return phase == "ready" and astar != null


# ------------------------------------------------------------------ generation

static func generate() -> void:
	var t0 := Time.get_ticks_usec()
	nodes = []
	edges = []
	_grid = {}
	_edge_of = {}
	source = "auto"
	if levels:
		_gen_levels()
	else:
		_gen_flat()
	stats.gen_nodes_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_gen_crossings()
	_gen_links()
	_gen_doors()
	_gen_spots()
	var t1 := Time.get_ticks_usec()
	_gen_edges()
	stats.gen_edges_ms = (Time.get_ticks_usec() - t1) / 1000.0
	_join_components()
	_bridge()
	_build_astar()
	_priorities()
	_junctions()
	_name_all()
	stats.gen_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("[waypoints] %s: generated %d nodes and %d edges in %.0f ms (nodes %.0f, edges %.0f)" % [map_id, nodes.size(), edges.size(),
		float(stats.gen_ms), float(stats.gen_nodes_ms), float(stats.gen_edges_ms)])


static func _add_node(p: Vector3, lv: int, kind: String, gap: float) -> int:
	## A node at p unless another of this level is within gap and in sight of it on the walk grid (gap 0: always): a
	## node in the next aisle, behind a shelf or a wall, does not count. Returns its index or -1.
	if gap > 0.0 and _seen_near(p, lv, gap):
		return -1
	var i := nodes.size()
	nodes.append({"id": "", "p": p, "lv": lv, "kind": kind, "pri": 2, "name": "", "dir": Vector2.ZERO, "via": false, "comp": 0})
	var k := _bucket(p, lv)
	if not _grid.has(k):
		_grid[k] = []
	_grid[k].append(i)
	return i


static func _seen_near(p: Vector3, lv: int, gap: float) -> bool:
	var rb := int(ceil(gap / _bk))
	var c := _bucket(p, lv)
	for dz in range(-rb, rb + 1):
		for dx in range(-rb, rb + 1):
			for i in _grid.get(Vector3i(c.x + dx, lv, c.z + dz), []):
				var q: Vector3 = nodes[i].p
				if q.distance_to(p) > gap:
					continue
				if levels:
					if nav._cells_clear(p, q):
						return true
				elif q.distance_to(p) < 2.5 or nav.line_clear(p, q):
					return true
	return false


static func _bucket(p: Vector3, lv: int) -> Vector3i:
	return Vector3i(floori(p.x / _bk), lv, floori(p.z / _bk))


static func _near(p: Vector3, lv: int, r: float, any_level: bool = false) -> Array:
	## Node indices within r of p on level lv (sorted by distance), via points left out.
	var out := []
	var rb := int(ceil(r / _bk))
	var c := _bucket(p, lv)
	var lvs := [lv] if not any_level else [lv - 1, lv, lv + 1]
	for l in lvs:
		for dz in range(-rb, rb + 1):
			for dx in range(-rb, rb + 1):
				for i in _grid.get(Vector3i(c.x + dx, l, c.z + dz), []):
					var q: Vector3 = nodes[i].p
					var dd := q.distance_to(p)
					if dd <= r and not nodes[i].via:
						out.append([dd, i])
	out.sort_custom(func(u, v): return float(u[0]) < float(v[0]))
	var ids := []
	for e in out:
		ids.append(int(e[1]))
	return ids


static func _nearest(p: Vector3, lv: int, r: float, include_via: bool = false) -> int:
	var rb := int(ceil(r / _bk))
	var c := _bucket(p, lv)
	var best := -1
	var bd := r
	for dz in range(-rb, rb + 1):
		for dx in range(-rb, rb + 1):
			for i in _grid.get(Vector3i(c.x + dx, lv, c.z + dz), []):
				if nodes[i].via and not include_via:
					continue
				var dd: float = (nodes[i].p as Vector3).distance_to(p)
				if dd < bd:
					bd = dd
					best = i
	return best


static func _gen_levels() -> void:
	## Storeyed maps (1 m walk grids, already checked against the collision by BotNav): roads on the cells farthest
	## from a wall, then fill so no open cell of the main walk is more than 2.6 m from a node.
	var nx: int = nav.nx
	var nz: int = nav.nz
	for lv in int(nav.levels):
		var cells: PackedInt32Array = nav.open_cells(lv)
		var d: PackedByteArray = nav.clear_d[lv]
		var ridge := []
		var all := []
		for i in cells:
			var di := int(d[i])
			var x := i % nx
			var z := i / nx
			var l := int(d[i - 1]) if x > 0 else 0
			var r := int(d[i + 1]) if x < nx - 1 else 0
			var u := int(d[i - nx]) if z > 0 else 0
			var dn := int(d[i + nx]) if z < nz - 1 else 0
			if di >= 2 and ((l <= di and r <= di) or (u <= di and dn <= di)):
				ridge.append([di, i])
			all.append([di, i])
		ridge.sort_custom(_by_clear)
		all.sort_custom(_by_clear)
		for e in ridge:
			_add_node(nav.cell_pos(lv, int(e[1])), lv, "road" if int(e[0]) < 5 else "plaza", 3.5)
		for e in all:
			var c: Vector3 = nav.cell_pos(lv, int(e[1]))
			if int(e[0]) <= 1:
				# beside a wall: where in the cell a body with the margin fits (the centre is 0.5 m from the wall's cell)
				if _seen_near(c, lv, 2.6):
					continue
				c = _settle(c)
				if c == Vector3.INF:
					continue
			_add_node(c, lv, "corner" if int(e[0]) <= 1 else "area", 2.6)


static func _by_clear(u: Array, v: Array) -> bool:
	return int(u[0]) > int(v[0]) or (int(u[0]) == int(v[0]) and int(u[1]) < int(v[1]))


static func _gen_flat() -> void:
	## Flat maps (2 m walk grid of streets, lanes and yards; houses are entered by the house plans): the same rule,
	## roads every 8 m, fill every 6 m, each node checked where it stands (props, cars, stalls are not on the grid).
	var L = world.map.layout
	var n: int = nav.n
	var walk: PackedByteArray = nav.walk
	var d := PackedByteArray()
	d.resize(n * n)
	d.fill(0)
	var front := PackedInt32Array()
	for z in n:
		for x in n:
			var i := z * n + x
			if walk[i] == 0:
				continue
			var edge := x == 0 or z == 0 or x == n - 1 or z == n - 1
			if not edge:
				edge = walk[i - 1] == 0 or walk[i + 1] == 0 or walk[i - n] == 0 or walk[i + n] == 0
			if edge:
				d[i] = 1
				front.append(i)
	var k := 1
	while not front.is_empty() and k < 6:
		var nxt := PackedInt32Array()
		for i in front:
			var x2 := i % n
			var z2 := i / n
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var xx: int = x2 + o.x
				var zz: int = z2 + o.y
				if xx < 0 or zz < 0 or xx >= n or zz >= n:
					continue
				var j := zz * n + xx
				if walk[j] == 1 and d[j] == 0:
					d[j] = k + 1
					nxt.append(j)
		front = nxt
		k += 1
	var ridge := []
	var all := []
	for z3 in range(1, n - 1):
		for x3 in range(1, n - 1):
			var i3 := z3 * n + x3
			if walk[i3] == 0:
				continue
			var di := int(d[i3])
			if di == 0:
				di = 6
			var c: Vector3 = nav._world(Vector2i(x3, z3))
			if not L.in_play_area(Vector2(c.x, c.z)):
				continue
			if di >= 2 and ((d[i3 - 1] <= di and d[i3 + 1] <= di) or (d[i3 - n] <= di and d[i3 + n] <= di)):
				ridge.append([di, i3])
			all.append([di, i3])
	ridge.sort_custom(_by_clear)
	all.sort_custom(_by_clear)
	var tried := 0
	for pass_i in 2:
		var arr: Array = ridge if pass_i == 0 else all
		var gap := 8.0 if pass_i == 0 else 6.0
		for e in arr:
			var i4 := int(e[1])
			var c2: Vector3 = nav._world(Vector2i(i4 % n, i4 / n))
			if _seen_near(c2, 0, gap):
				continue
			tried += 1
			var p := _stand(c2)
			if p == Vector3.INF:
				continue
			var kind := "road" if pass_i == 0 else ("corner" if int(e[0]) <= 1 else "area")
			_add_node(p, 0, kind, gap * 0.75)
	stats.flat_tried = tried


static func _stand(c: Vector3) -> Vector3:
	## Where a body stands at or near c (flat maps): floor under it and nothing in the way of a standing body. INF if
	## nowhere within 1.6 m.
	var space := _space()
	for r in [0.0, 0.8, 1.6]:
		var nk := 1 if r == 0.0 else 8
		for k in nk:
			var a := TAU * k / 8.0
			var q := c + Vector3(cos(a), 0.0, sin(a)) * float(r)
			var rq := PhysicsRayQueryParameters3D.create(q + Vector3.UP * 2.0, q + Vector3.DOWN * 3.0, Defs.MOVE_MASK)
			rq.exclude = _doors_ex
			var hit := space.intersect_ray(rq)
			if hit.is_empty():
				continue
			var fy: float = (hit.position as Vector3).y
			if absf(fy - c.y) > 1.2:
				continue
			if _deep(Vector3(q.x, fy, q.z)):
				continue
			var p := Vector3(q.x, fy, q.z)
			if _fits(p):
				return p
	return Vector3.INF


static func _settle(c: Vector3) -> Vector3:
	## A cell centre beside a wall, or the nearest point of its cell (a quarter metre steps) where a wide body fits;
	## else the centre when a body fits there at all; else INF.
	if _fits(c):
		return c
	for o in [Vector3(0.25, 0, 0), Vector3(-0.25, 0, 0), Vector3(0, 0, 0.25), Vector3(0, 0, -0.25), Vector3(0.25, 0, 0.25),
			Vector3(-0.25, 0, 0.25), Vector3(0.25, 0, -0.25), Vector3(-0.25, 0, -0.25)]:
		if _fits(c + o):
			return c + o
	return c if _fits(c, R_TIGHT) else Vector3.INF


static func _fits(p: Vector3, r: float = R_WIDE) -> bool:
	var sq := _query(r)
	sq.transform = Transform3D(Basis(), p + Vector3.UP * (SWEEP_LO + SWEEP_H * 0.5))
	sq.motion = Vector3.ZERO
	return _space().intersect_shape(sq, 1).is_empty()


static func _deck_cells() -> void:
	## The walk grid's cells a crossing's deck covers (Sitio Kalinaw: river bridges, the estero's planks, the culvert):
	## the grid calls them water, but a body walks there.
	_deck = {}
	if levels:
		return
	var cr = world.map.layout.get("crossings")
	if not (cr is Array):
		return
	for c in cr:
		var a: Vector2 = c.a
		var b: Vector2 = c.b
		var dir := (b - a).normalized()
		var side := Vector2(-dir.y, dir.x)
		var hw := maxf(float(c.get("w", 2.0)) * 0.5, 0.5)
		var t := -4.0
		var len := a.distance_to(b) + 4.0
		while t <= len:
			var o := -hw
			while o <= hw:
				var q := a + dir * t + side * o
				var cc: Vector2i = nav._idx(Vector3(q.x, 0.0, q.y))
				_deck[cc.y * int(nav.n) + cc.x] = true
				o += 0.5
			t += 0.5


static func _walk_ok(q: Vector3) -> bool:
	if nav.walkable_at(q):
		return true
	if _deck.is_empty():
		return false
	var c: Vector2i = nav._idx(q)
	return _deck.has(c.y * int(nav.n) + c.x)


static func _gen_crossings() -> void:
	## Nodes along every crossing's deck (every 5 m, from 4 m before one bank to 4 m past the other), a main road each.
	if levels or _deck.is_empty():
		return
	var L = world.map.layout
	var space := _space()
	for c in L.crossings:
		var a: Vector2 = c.a
		var b: Vector2 = c.b
		var dir := (b - a).normalized()
		var a2 := a - dir * 4.0
		var b2 := b + dir * 4.0
		var n := maxi(int(ceil(a2.distance_to(b2) / 5.0)), 2)
		var prev := -1
		for k in n + 1:
			var q2 := a2.lerp(b2, float(k) / n)
			var top := maxf(float(L.ground_height(q2.x, q2.y)), float(L.get("LAND_Y") if L.get("LAND_Y") != null else 0.0)) + 4.0
			var rq := PhysicsRayQueryParameters3D.create(Vector3(q2.x, top, q2.y), Vector3(q2.x, top - 14.0, q2.y), Defs.MOVE_MASK)
			rq.exclude = _doors_ex
			var hit := space.intersect_ray(rq)
			if hit.is_empty() or _deep(hit.position):
				prev = -1
				stats.cross_gaps = int(stats.get("cross_gaps", 0)) + 1
				continue
			var p: Vector3 = hit.position
			if not _fits(p, R_TIGHT):
				prev = -1
				stats.cross_gaps = int(stats.get("cross_gaps", 0)) + 1
				continue
			var idx := _add_node(p, 0, "bridge", 0.0)
			nodes[idx].name = str(c.get("name", "bridge"))
			if prev >= 0:
				var v := verify(nodes[prev].p, p)
				if not v.is_empty():
					_add_edge(prev, idx, str(v.kind), -1, false)
				else:
					stats.cross_fail = int(stats.get("cross_fail", 0)) + 1
			prev = idx
		stats.crossings = int(stats.get("crossings", 0)) + 1


static func _gen_links() -> void:
	## Stairs and escalators (storeyed maps): their landing points and the points along them, joined in their order
	## (escalators one way). The ends join the floor's nodes in _gen_edges like any other node.
	if not levels:
		return
	var L = world.map.layout
	for lk in L.nav_links:
		var both := bool(lk.get("both", false))
		var kind := "stair" if both else "escalator"
		var pts: Array = [lk.a]
		pts.append_array(lk.get("via", []))
		pts.append(lk.b)
		var prev := -1
		for j in pts.size():
			var p: Vector3 = pts[j]
			var lv: int = nav.level_of(p)
			var end := j == 0 or j == pts.size() - 1
			var idx := -1
			if end:
				idx = _nearest(p, lv, 0.6, false)
				if idx >= 0 and str(nodes[idx].kind) in ["stair", "escalator"]:
					pass
				else:
					idx = _add_node(p, lv, kind, 0.0)
			else:
				idx = _add_node(p, lv, kind, 0.0)
				nodes[idx].via = true
			if prev >= 0:
				_add_edge(prev, idx, kind, -1, not both)
			prev = idx


static func _gen_doors() -> void:
	## A node 1.1 m either side of every door whose both sides are walked, and the edge through it.
	for dd in _door_list:
		var c: Vector3 = dd.c
		var nn: Vector3 = dd.n
		var sides := []
		for s in [1.0, -1.0]:
			var p: Vector3 = c + nn * s * 1.1
			if levels:
				p.y = world.map.layout.level_y(nav.level_of(p + Vector3.UP * 0.2))
				if not nav.walkable_at(p):
					break
			else:
				if not nav.walkable_at(p):
					break
				p = _stand(p)
				if p == Vector3.INF:
					break
			sides.append(p)
		if sides.size() < 2:
			continue
		var v := verify(sides[0], sides[1])
		if v.is_empty() or str(v.kind) != "door":
			stats.doors_failed = int(stats.get("doors_failed", 0)) + 1
			continue
		var ia := _add_node(sides[0], _lv(sides[0]), "door", 0.0)
		var ib := _add_node(sides[1], _lv(sides[1]), "door", 0.0)
		_add_edge(ia, ib, "door", int(dd.i), false)


static func _gen_spots() -> void:
	## The map's designated places and the best hiding and sniping spots BotNav found: nodes with their kind and the
	## way they watch. An existing node within a metre takes the spot's kind instead.
	var arr := []
	var L = world.map.layout
	if L.has_method("designated_spots"):
		for s in L.designated_spots():
			arr.append({"p": s.p, "kind": str(s.get("kind", "hide")), "face": s.get("face", Vector3.INF), "name": str(s.get("name", "")), "map": true})
	var bn = load("res://src/ai/bot_nav.gd")
	if bn.phase == "done":
		for s2 in bn.spots:
			if str(s2.kind) in ["hide", "snipe"] and str(s2.src) != "map":
				arr.append({"p": s2.p, "kind": str(s2.kind), "dir": s2.dir, "name": "", "map": false})
	var gap_of := {"hide": 6.0, "snipe": 6.0, "cover": 6.0}
	for s3 in arr:
		var p: Vector3 = s3.p
		if levels:
			var sp: Vector3 = nav.snap(p, 3)
			if sp == Vector3.INF:
				continue
			p = sp
		else:
			p = _stand(p)
			if p == Vector3.INF:
				continue
		var lv := _lv(p)
		var kind := str(s3.kind)
		if kind not in ["hide", "snipe", "cover"]:
			continue
		if not bool(s3.map):
			var other := false
			for j in _near(p, lv, float(gap_of.get(kind, 6.0))):
				if str(nodes[j].kind) == kind:
					other = true
					break
			if other:
				continue
		var near := _nearest(p, lv, 1.0)
		var idx := near if near >= 0 and str(nodes[near].kind) in ["road", "area", "corner"] else _add_node(p, lv, kind, 0.0)
		nodes[idx].kind = kind
		nodes[idx].name = str(s3.name)
		var face = s3.get("face", Vector3.INF)
		if face is Vector3 and face != Vector3.INF:
			var fv: Vector3 = (face as Vector3) - p
			nodes[idx].dir = Vector2(fv.x, fv.z).normalized()
		elif s3.has("dir"):
			nodes[idx].dir = s3.dir


static func _lv(p: Vector3) -> int:
	return int(nav.level_of(p)) if levels else 0


static func _add_edge(a: int, b: int, kind: String, door: int = -1, one: bool = false) -> int:
	if a == b or a < 0 or b < 0:
		return -1
	var k := a * 1000003 + b
	if _edge_of.has(k):
		return int(_edge_of[k])
	var i := edges.size()
	edges.append({"a": a, "b": b, "kind": kind, "door": door, "one": one})
	_edge_of[k] = i
	_edge_of[b * 1000003 + a] = i
	return i


static func _gen_edges() -> void:
	## Each node to its nearest proven neighbour in each of 12 directions (30 degrees each), up to 8 m indoors and
	## 16 m outdoors: a sparse graph whose every edge a wide body was swept along.
	var r_link := 8.0 if levels else 16.0
	var tests := 0
	for ai in nodes.size():
		var na: Dictionary = nodes[ai]
		if na.via:
			continue
		var pa: Vector3 = na.p
		var cone := {}
		var made := 0
		var tried := 0
		for bi in _near(pa, int(na.lv), r_link):
			if bi == ai:
				continue
			var pb: Vector3 = nodes[bi].p
			if absf(pb.y - pa.y) > (0.8 if levels else maxf(2.0, pa.distance_to(pb) * 0.45)):
				continue
			var cn := int(floor(wrapf(atan2(pb.z - pa.z, pb.x - pa.x), 0.0, TAU) / (TAU / 12.0))) % 12
			if _edge_of.has(ai * 1000003 + bi):
				cone[cn] = true
				made += 1
				continue
			if cone.has(cn):
				continue
			tried += 1
			if tried > 28 or made >= 12:
				break
			tests += 1
			var v := verify(pa, pb)
			if v.is_empty():
				continue
			_add_edge(ai, bi, str(v.kind), int(v.get("door", -1)), false)
			cone[cn] = true
			made += 1
	stats.edge_tests = tests


static func verify(a: Vector3, b: Vector3) -> Dictionary:
	## Can a body walk straight from a to b and keep off everything? {} if not, else {kind, door?}.
	## Storeyed: open cells under a body-wide band on the walk grid, then the sweep. Flat: open cells along the line,
	## floor every metre within a step of the last (no drop, no deep water), then the sweep along that floor.
	var door = _door_crossed(a, b)
	if door is Dictionary and door.is_empty():
		return {}   # across a doorway, but not straight through the middle of it
	var wade := false
	var band := true
	var pts: Array = [a]
	if levels:
		if nav.level_of(a) != nav.level_of(b):
			return {}
		if not nav._band_clear(a, b):
			# a 1 m aisle between shelves: the band of cells is closed off the middle of it. The cells on the line itself
			# open and the body-sized sweep clear will do (a tight edge).
			if not nav._cells_clear(a, b):
				return {}
			band = false
		pts.append(b)
	else:
		var L = world.map.layout
		var dist := Vector2(b.x - a.x, b.z - a.z).length()
		var steps := maxi(int(ceil(dist / 1.0)), 1)
		var prev_y := a.y
		var space := _space()
		for s in range(1, steps + 1):
			var t := float(s) / steps
			var q := a.lerp(b, t)
			if not _walk_ok(q):
				return {}
			var top := maxf(prev_y, q.y) + 1.4
			var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, top, q.z), Vector3(q.x, top - 3.4, q.z), Defs.MOVE_MASK)
			rq.exclude = _doors_ex
			var hit := space.intersect_ray(rq)
			if hit.is_empty():
				return {}
			var fy: float = (hit.position as Vector3).y
			if absf(fy - prev_y) > 0.5:
				return {}
			var fq := Vector3(q.x, fy, q.z)
			if _deep(fq):
				return {}
			if L.is_water(q.x, q.z) and L.water_height(q.x, q.z) > fy + 0.25:
				wade = true
			prev_y = fy
			pts.append(fq)
	var kind := "walk"
	if not band or not _sweep_pts(pts, R_WIDE):
		if not _sweep_pts(pts, R_TIGHT):
			return {}
		kind = "tight"
	if wade:
		kind = "wade"
	if door is Dictionary:
		return {"kind": "door", "door": int(door.i)}
	return {"kind": kind}


static func why(a: Vector3, b: Vector3) -> String:
	## What stops a body walking straight from a to b (QA): "" when nothing does.
	var door = _door_crossed(a, b)
	if door is Dictionary and door.is_empty():
		return "crosses a doorway off its middle or at a slant"
	if levels:
		if nav.level_of(a) != nav.level_of(b):
			return "different levels"
		if not nav._cells_clear(a, b):
			return "closed cells on the line (a wall, a shelf, a void)"
	if not _sweep_pts([a, b], R_TIGHT):
		var sq := _query(R_TIGHT)
		sq.transform = Transform3D(Basis(), a + Vector3.UP * (SWEEP_LO + SWEEP_H * 0.5))
		sq.motion = b - a
		var res := _space().cast_motion(sq)
		var t := float(res[0]) if res.size() == 2 else -1.0
		sq.transform = Transform3D(Basis(), a + (b - a) * maxf(t, 0.0) + Vector3.UP * (SWEEP_LO + SWEEP_H * 0.5))
		sq.motion = (b - a).normalized() * 0.05
		var info := _space().get_rest_info(sq)
		var what := "?"
		if not info.is_empty():
			var o = instance_from_id(int(info.collider_id))
			what = "%s (rid %s) at %s" % [str(o.name) if o is Node else "server body", str(info.rid), str((info.point as Vector3).snapped(Vector3.ONE * 0.01))]
		return "the body sweep stops at %.2f of the way: %s" % [t, what]
	return ""


static func _sweep_pts(pts: Array, r: float) -> bool:
	## The cylinder swept from point to point (in stretches of about 4 m on flat maps, following the floor).
	var i := 0
	while i < pts.size() - 1:
		var j := mini(i + 4, pts.size() - 1)
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[j]
		var hi := maxf(a.y, b.y)
		for k in range(i, j + 1):
			hi = maxf(hi, (pts[k] as Vector3).y)
		# a bump in the middle of a stretch: start the cylinder high enough to clear it
		var lift := hi - minf(a.y, b.y)
		if not sweep(Vector3(a.x, a.y + lift, a.z), Vector3(b.x, b.y + lift, b.z), r):
			return false
		i = j
	return true


static func sweep(a: Vector3, b: Vector3, r: float) -> bool:
	## A cylinder of radius r from just above step height to head height, moved from a to b (feet positions), meets
	## nothing (doors left out: bots open them). A start already touching something fails too.
	var sq := _query(r)
	sq.transform = Transform3D(Basis(), a + Vector3.UP * (SWEEP_LO + SWEEP_H * 0.5))
	sq.motion = b - a
	var res := _space().cast_motion(sq)
	return res.size() == 2 and float(res[0]) >= 0.999


static func _query(r: float) -> PhysicsShapeQueryParameters3D:
	var rk := snappedf(r, 0.01)
	if not _shapes.has(rk):
		var sh := CylinderShape3D.new()
		sh.radius = r
		sh.height = SWEEP_H
		_shapes[rk] = sh
	if _q == null:
		_q = PhysicsShapeQueryParameters3D.new()
	_q.shape = _shapes[rk]
	_q.collision_mask = Defs.MOVE_MASK
	_q.exclude = _doors_ex
	return _q


static func _space() -> PhysicsDirectSpaceState3D:
	return world.get_world_3d().direct_space_state


static func _deep(q: Vector3) -> bool:
	var L = world.map.layout
	if L.has_method("water_sd"):
		var q2 := Vector2(q.x, q.z)
		for r in L.bridge_rects:
			if (r as Rect2).has_point(q2):
				return false
		return (L.water_sd(q2) as Vector2).x < 0.15
	return L.is_water(q.x, q.z) and L.water_height(q.x, q.z) - q.y > 1.1


static func _door_rids() -> Array:
	var out := []
	for d in world.map.dyn.doors:
		var node = d.get("node")
		if node != null and node.get("body") is RID and (node.body as RID).is_valid():
			out.append(node.body)
	return out


static func _doors() -> Array:
	var out := []
	var i := 0
	for d in world.map.dyn.doors:
		var node = d.get("node")
		if node != null and node.get("base") is Transform3D:
			var bt: Transform3D = node.base
			var c: Vector3 = bt * Vector3(float(node.w) * 0.5, 0.0, 0.0)
			out.append({"c": c, "n": Vector3(bt.basis.z.x, 0.0, bt.basis.z.z).normalized(),
				"u": Vector3(bt.basis.x.x, 0.0, bt.basis.x.z).normalized(), "hw": float(node.w) * 0.5, "i": i})
		i += 1
	return out


static func _door_crossed(a: Vector3, b: Vector3):
	## The door the line from a to b goes through (a Dictionary), {} when it crosses a doorway off its middle or at a
	## slant, null when it crosses none. Of a row of leaves (the entrances' double doors), the leaf it passes nearest
	## the middle of.
	var best = null
	var best_off := INF
	for dd in _door_list:
		var c: Vector3 = dd.c
		if absf(c.y - a.y) > 1.5 or Vector2(c.x - a.x, c.z - a.z).length() > a.distance_to(b) + 2.0:
			continue
		var nn: Vector3 = dd.n
		var sa := (a - c).dot(nn)
		var sb := (b - c).dot(nn)
		if sa * sb >= 0.0:
			continue
		var x := a + (b - a) * (sa / (sa - sb))
		var off := absf((x - c).dot(dd.u))
		if off > float(dd.hw) + 0.6 or off >= best_off:
			continue
		best_off = off
		best = dd
	if best == null:
		return null
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	if best_off > maxf(float(best.hw) - 0.3, 0.12) or absf(dir.dot(best.n)) < 0.8:
		return {}
	return best


static func _join_components() -> void:
	## The largest connected set is the graph; each other set tries once to join it with an edge up to twice as long.
	## What still cannot is left out (and reported: stats.orphans).
	for round_i in 2:
		_label_components()
		var size := {}
		for nd in nodes:
			size[int(nd.comp)] = int(size.get(int(nd.comp), 0)) + 1
		if size.size() <= 1:
			break
		var joined := 0
		for ci in size:
			if int(ci) == main_comp:
				continue
			var done := false
			for i in nodes.size():
				if done:
					break
				if int(nodes[i].comp) != int(ci) or nodes[i].via:
					continue
				var p: Vector3 = nodes[i].p
				for j in _near(p, int(nodes[i].lv), 16.0 if levels else 30.0):
					if int(nodes[j].comp) != main_comp:
						continue
					var v := verify(p, nodes[j].p)
					if not v.is_empty():
						_add_edge(i, j, str(v.kind), int(v.get("door", -1)), false)
						done = true
						joined += 1
						break
		if joined == 0:
			break
	_label_components()
	var orphans := 0
	var where := []
	for nd2 in nodes:
		if int(nd2.comp) != main_comp:
			orphans += 1
			if where.size() < 40:
				where.append(nd2.p)
	stats.orphans = orphans
	stats.orphan_at = where


static func _bridge() -> void:
	## Every set of nodes still apart from the main graph: the walk grid's own path from it to the nearest main node,
	## threaded with nodes (each stretch proven like any edge). What still cannot join is too narrow for a body.
	var t0 := Time.get_ticks_usec()
	var bridged := 0
	for round_i in 3:
		_label_components()
		var sets := {}
		for i in nodes.size():
			var c := int(nodes[i].comp)
			if c != main_comp and not nodes[i].via:
				if not sets.has(c):
					sets[c] = []
				sets[c].append(i)
		if sets.is_empty():
			break
		var n_round := 0
		for c2 in sets:
			var arr: Array = sets[c2]
			# pairs (a node of the set, the nearest main node to it), nearest first; the first four tried
			var pairs := []
			for k in mini(arr.size(), 40):
				var oi: int = arr[int(float(k) * arr.size() / mini(arr.size(), 40))]
				for mi in _near(nodes[oi].p, int(nodes[oi].lv), 30.0 if levels else 60.0):
					if int(nodes[mi].comp) != main_comp:
						continue
					pairs.append([(nodes[oi].p as Vector3).distance_to(nodes[mi].p), oi, mi])
					break
			pairs.sort_custom(func(u, v): return float(u[0]) < float(v[0]))
			var used := {}
			var tries := 0
			for pr in pairs:
				if tries >= 4:
					break
				if used.has(int(pr[2])):
					continue
				used[int(pr[2])] = true
				tries += 1
				if _thread(int(pr[1]), int(pr[2]), _grid_path(nodes[int(pr[1])].p, nodes[int(pr[2])].p)):
					n_round += 1
					break
		bridged += n_round
		if n_round == 0:
			break
	stats.bridged = bridged
	stats.bridge_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_label_components()


static func _grid_path(p: Vector3, q: Vector3) -> Array:
	## The walk grid's cells from p to q (every cell, not straightened), on p's level; [] when there is none.
	var out := []
	if levels:
		var a: int = nav._point_near(p, 3)
		var b: int = nav._point_near(q, 3)
		if a < 0 or b < 0:
			return out
		for v in nav._astar.get_point_path(a, b):
			if absf(v.y - p.y) > 0.5:
				return []
			out.append(v)
	else:
		var ca: Vector2i = nav._idx(p)
		var cb: Vector2i = nav._idx(q)
		if not nav.same_region(p, q):
			return out
		for c in nav._astar.get_id_path(ca, cb):
			out.append(nav._world(c))
	return out


static func _thread(oi: int, mi: int, pts: Array) -> bool:
	## Nodes along pts from node oi to node mi: from each, on to the farthest point it is proven to reach.
	if pts.size() < 2:
		return false
	pts[pts.size() - 1] = nodes[mi].p
	var cur := oi
	var i := 0
	var guard := 0
	while i < pts.size() - 1 and guard < 200:
		guard += 1
		var from: Vector3 = nodes[cur].p
		var nxt := -1
		var kind := ""
		var door := -1
		for k in range(mini(i + 16, pts.size() - 1), i, -1):
			var to: Vector3 = pts[k]
			if not levels and k < pts.size() - 1:
				to = _stand(to)
				if to == Vector3.INF:
					continue
				pts[k] = to
			var v := verify(from, to)
			if not v.is_empty():
				nxt = k
				kind = str(v.kind)
				door = int(v.get("door", -1))
				break
		if nxt < 0:
			return false
		var ni := mi if nxt == pts.size() - 1 else _add_node(pts[nxt], int(nodes[oi].lv), "corner", 0.0)
		_add_edge(cur, ni, kind, door, false)
		cur = ni
		i = nxt
	return cur == mi


static func _label_components() -> void:
	_index_adj()
	for nd in nodes:
		nd.comp = -1
	var label := 0
	var best := 0
	var best_n := 0
	for s in nodes.size():
		if int(nodes[s].comp) >= 0:
			continue
		var stack := PackedInt32Array([s])
		nodes[s].comp = label
		var n := 0
		while not stack.is_empty():
			var a := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			n += 1
			for ei in adj[a]:
				var e: Dictionary = edges[ei]
				var o: int = int(e.b) if int(e.a) == a else int(e.a)
				if int(nodes[o].comp) < 0:
					nodes[o].comp = label
					stack.append(o)
		if n > best_n:
			best_n = n
			best = label
		label += 1
	main_comp = best


static func _index_adj() -> void:
	adj = []
	adj.resize(nodes.size())
	for i in nodes.size():
		adj[i] = []
	for ei in edges.size():
		adj[int(edges[ei].a)].append(ei)
		adj[int(edges[ei].b)].append(ei)


static func _build_astar() -> void:
	astar = AStar3D.new()
	if nodes.is_empty():
		return
	astar.reserve_space(nodes.size())
	for i in nodes.size():
		astar.add_point(i, nodes[i].p, _weight(i))
		if int(nodes[i].comp) != main_comp:
			astar.set_point_disabled(i, true)
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		if _blocked.has(ei):
			continue
		astar.connect_points(int(e.a), int(e.b), not bool(e.one))


static func _weight(i: int) -> float:
	var w: float = PRI_W.get(int(nodes[i].pri), 1.15)
	var tight := 0
	var wade := false
	for ei in (adj[i] if i < adj.size() else []):
		var k := str(edges[ei].kind)
		if k == "tight":
			tight += 1
		elif k == "wade":
			wade = true
	if wade:
		w *= 4.0
	elif tight > 0 and tight * 2 >= (adj[i] as Array).size():
		w *= 1.3
	var learned := int(_learned_at(i))
	if learned > 0:
		w *= 1.0 + minf(learned, 6) * 0.25
	return w


static func _learned_at(i: int) -> int:
	if _learned.is_empty():
		return 0
	var n := 0
	for ei in adj[i]:
		n += int(_learned.get(_ekey(ei), 0))
	return n


static func _priorities() -> void:
	## Priority from traffic: 400 sample routes between nodes spread over the map; the most used 15% are main roads
	## (1), the next 35% secondary (2), the rest and every dead end side ways (3). Doors, stairs and escalators are never
	## below 2 (they are how one gets anywhere).
	var mains := []
	for i in nodes.size():
		if int(nodes[i].comp) == main_comp and not nodes[i].via:
			mains.append(i)
	if mains.size() < 4:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_id + "|waypoints")
	var use := PackedInt32Array()
	use.resize(nodes.size())
	use.fill(0)
	for k in 400:
		var a: int = mains[rng.randi_range(0, mains.size() - 1)]
		var b: int = mains[rng.randi_range(0, mains.size() - 1)]
		if a == b:
			continue
		for id in astar.get_id_path(a, b):
			use[id] += 1
	var order := mains.duplicate()
	order.sort_custom(func(u, v): return use[u] > use[v] or (use[u] == use[v] and u < v))
	var n1 := int(order.size() * 0.15)
	var n2 := int(order.size() * 0.5)
	for r in order.size():
		var i2: int = order[r]
		var pri := 1 if r < n1 else (2 if r < n2 else 3)
		if use[i2] == 0 or (adj[i2] as Array).size() <= 1:
			pri = 3
		if str(nodes[i2].kind) in ["door", "stair", "escalator"]:
			pri = mini(pri, 2)
		nodes[i2].pri = pri
	for i3 in nodes.size():
		if nodes[i3].via:
			nodes[i3].pri = 2
	stats.traffic_max = use[order[0]] if not order.is_empty() else 0
	_build_astar()


static func _junctions() -> void:
	## A road (a corridor or a lane, not an open court) meeting other roads three ways or more (edges to roads in three
	## of the four quarters round it) is a junction.
	for i in nodes.size():
		if str(nodes[i].kind) != "road":
			continue
		if levels and nav.clearance_at(nodes[i].p) >= 4.0:
			continue
		var quads := {}
		var p: Vector3 = nodes[i].p
		for ei in adj[i]:
			var e: Dictionary = edges[ei]
			var o: int = int(e.b) if int(e.a) == i else int(e.a)
			if str(nodes[o].kind) not in ["road", "junction", "plaza", "door", "stair", "escalator"]:
				continue
			var q: Vector3 = nodes[o].p
			quads[int(floor(wrapf(atan2(q.z - p.z, q.x - p.x) + PI / 4.0, 0.0, TAU) / (PI / 2.0))) % 4] = true
		if quads.size() >= 3:
			nodes[i].kind = "junction"


static func _name_all() -> void:
	var code: String = CODES.get(map_id, preload("res://src/world/maps/authored/map_doc.gd").code_of(map_id))
	var per_level := {}
	for nd in nodes:
		var lv := int(nd.lv)
		var k := int(per_level.get(lv, 0)) + 1
		per_level[lv] = k
		nd.id = "%s%d-%04d" % [code, lv + 1, k]
		if str(nd.name) == "":
			nd.name = place_name(nd.p, lv)


static func place_name(p: Vector3, lv: int) -> String:
	## A shop's name (the mall: the unit p stands in), else the nearest landmark within 40 m, with the level on storeyed maps.
	var L = world.map.layout
	var lvs := ", Level %d" % (lv + 1) if levels else ""
	var units = L.get("units")
	if units is Array:
		for u in units:
			if int(u.get("level", -1)) == lv and (u.rect as Rect2).has_point(Vector2(p.x, p.z)):
				var shop: Dictionary = u.get("shop", {})
				if shop.has("name"):
					return "%s%s" % [str(shop.name), lvs]
	var best := ""
	var bd := 40.0
	for m in L.landmarks:
		var dd := Vector2(p.x, p.z).distance_to(m.pos)
		if dd < bd:
			bd = dd
			best = str(m.name)
	return ("%s%s" % [best, lvs]) if best != "" else ("Level %d" % (lv + 1) if levels else "")


static func _finish() -> void:
	_grid = {}
	_edge_of = {}
	for i in nodes.size():
		var nd: Dictionary = nodes[i]
		var k := _bucket(nd.p, int(nd.lv))
		if not _grid.has(k):
			_grid[k] = []
		_grid[k].append(i)
	for ei in edges.size():
		var e: Dictionary = edges[ei]
		_edge_of[int(e.a) * 1000003 + int(e.b)] = ei
		_edge_of[int(e.b) * 1000003 + int(e.a)] = ei
	_read_learned()
	_label_components()
	_build_astar()
	var kinds := {}
	var pris := {}
	for nd2 in nodes:
		kinds[str(nd2.kind)] = int(kinds.get(str(nd2.kind), 0)) + 1
		pris[int(nd2.pri)] = int(pris.get(int(nd2.pri), 0)) + 1
	var ek := {}
	for e2 in edges:
		ek[str(e2.kind)] = int(ek.get(str(e2.kind), 0)) + 1
	stats.kinds = kinds
	stats.pri = pris
	stats.edge_kinds = ek
	stats.nodes = nodes.size()
	stats.edges = edges.size()
	var orphans := 0
	for nd3 in nodes:
		if int(nd3.comp) != main_comp:
			orphans += 1
	stats.orphans = orphans


static func _reverify() -> Array:
	## Every edge of an edited graph (or one on a map that changed) proven again, its kind found again (walk, tight,
	## door, wade); stairs and escalators kept as drawn. Returns the dropped ones: [[id, id, why]].
	var keep := []
	var dropped := []
	for e in edges:
		var k := str(e.kind)
		if k in ["stair", "escalator"]:
			keep.append(e)
			continue
		var pa: Vector3 = nodes[int(e.a)].p
		var pb: Vector3 = nodes[int(e.b)].p
		var v := verify(pa, pb)
		if v.is_empty():
			dropped.append([str(nodes[int(e.a)].id), str(nodes[int(e.b)].id), why(pa, pb)])
			continue
		e.kind = str(v.kind)
		e.door = int(v.get("door", -1))
		keep.append(e)
	edges = keep
	return dropped


static func check_to_res() -> void:
	## --wpcheck (the map editor's "Check in game"): the shipped graph proven against the map as built, stamped and
	## written back under res://data, and a report for the editor (user://waypoints/<map>_check.json): the edges that
	## failed (and why), nodes where a body does not fit, nodes off the main graph.
	var dropped := _reverify()
	_finish()
	verified = key
	var blocked := []
	var orphans := []
	for nd in nodes:
		if nd.via:
			continue
		if not _fits(nd.p, R_TIGHT):
			blocked.append(str(nd.id))
		if int(nd.comp) != main_comp:
			orphans.append(str(nd.id))
	_write(true)
	DirAccess.make_dir_recursive_absolute("user://waypoints")
	var f := FileAccess.open("user://waypoints/%s_check.json" % map_id, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"map": map_id, "key": key, "nodes": nodes.size(), "edges": edges.size(), "dropped": dropped,
			"blocked": blocked, "orphans": orphans, "time": Time.get_datetime_string_from_system()}, "  "))
	print("[wpcheck] %s: %d edges dropped, %d nodes where a body does not fit, %d nodes off the main graph" % [map_id, dropped.size(),
		blocked.size(), orphans.size()])


# ------------------------------------------------------------------ routes

static func route(from: Vector3, to: Vector3) -> Dictionary:
	## The way from a bot's feet to a goal on the graph:
	##   {pts, wps}: the points to walk (nodes, then the goal itself when it is in plain sight of the last node) and
	##               the node index of each (-1 for the goal);
	##   {lead, pts, wps}: the bot stands where no node is in plain sight (pushed into a corner, fallen somewhere):
	##               walk a grid path to the node `lead` first, then pts;
	##   {} when there is no way at all.
	if not ready():
		return {}
	var s := attach(from, true)
	var lead := -1
	if s < 0:
		lead = _nearest_main(from)
		if lead < 0:
			_fail("no_start_node", from)
			return {}
		s = lead
	var gs := _goal_nodes(to)
	if gs.is_empty():
		_fail("no_goal_node", to)
		return {}
	var best: PackedInt64Array = PackedInt64Array()
	var goal_clear := false
	for g in gs:
		var ids := astar.get_id_path(s, int(g[0])) if s != int(g[0]) else PackedInt64Array([s])
		if ids.is_empty():
			continue
		best = ids
		goal_clear = bool(g[1])
		break
	if best.is_empty():
		# the waypoints the goal is in sight of are cut off for now: the nearest ones that can be reached instead
		for i in _near(to, _lv(to), 40.0 if levels else 60.0, true):
			if int(nodes[i].comp) != main_comp or astar.is_point_disabled(i):
				continue
			var ids2 := astar.get_id_path(s, i) if s != i else PackedInt64Array([s])
			if not ids2.is_empty():
				best = ids2
				goal_clear = false
				break
	if best.is_empty():
		_fail("no_path", to)
		return {}
	var pts := []
	var wps := PackedInt32Array()
	for id in best:
		pts.append(nodes[id].p)
		wps.append(int(id))
	if goal_clear and (pts[pts.size() - 1] as Vector3).distance_to(to) > 0.3:
		pts.append(to)
		wps.append(-1)
	var out := {"pts": pts, "wps": wps}
	if lead >= 0:
		out["lead"] = nodes[lead].p
	return out


static func _fail(why_s: String, p: Vector3) -> void:
	var f: Dictionary = stats.get("route_fail", {})
	f[why_s] = int(f.get(why_s, 0)) + 1
	stats.route_fail = f
	if int(f[why_s]) <= 5 and (Game.arg("navwatch") != null or Game.arg("bottrace") != null):
		print("[waypoints] no route (%s) at %s" % [why_s, str(p.snapped(Vector3.ONE * 0.1))])


static func attach(p: Vector3, _start: bool) -> int:
	## The nearest main-graph node a body at p can walk to in a straight line (tight sweep), or -1.
	var lv := _lv(p)
	var cands := _near(p, lv, 10.0 if levels else 18.0, true)
	var tested := 0
	for i in cands:
		if int(nodes[i].comp) != main_comp or astar.is_point_disabled(i):
			continue
		var q: Vector3 = nodes[i].p
		if absf(q.y - p.y) > 1.4:
			continue
		if q.distance_to(p) < 0.35:
			return i
		tested += 1
		if tested > 8:
			break
		if clear(p, q, R_FROM):
			return i
	return -1


static func _goal_nodes(to: Vector3) -> Array:
	## [[node, goal in plain sight of it]]: the nodes a goal can be reached from (nearest first), else the nearest node.
	var lv := _lv(to)
	var out := []
	var tested := 0
	var first := -1
	for i in _near(to, lv, 12.0 if levels else 20.0, true):
		if int(nodes[i].comp) != main_comp or astar.is_point_disabled(i):
			continue
		var q: Vector3 = nodes[i].p
		if absf(q.y - to.y) > 1.6:
			continue
		if first < 0:
			first = i
		tested += 1
		if tested > 8:
			break
		if q.distance_to(to) < 0.35 or clear(q, to):
			out.append([i, true])
			if out.size() >= 2:
				return out
	if out.is_empty():
		var n := first if first >= 0 else _nearest_main(to)
		if n >= 0:
			out.append([n, false])
	return out


static func _nearest_main(p: Vector3) -> int:
	var lv := _lv(p)
	for r in [8.0, 20.0, 50.0]:
		for i in _near(p, lv, r, true):
			if int(nodes[i].comp) == main_comp and not astar.is_point_disabled(i):
				return i
	return -1


static func clear(a: Vector3, b: Vector3, r: float = R_TIGHT) -> bool:
	## A body can walk straight from a to b: the grid agrees and the body-sized sweep meets nothing.
	if levels:
		if nav.level_of(a) != nav.level_of(b):
			return false
		if not nav._cells_clear(a, b):
			return false
		return sweep(a, Vector3(b.x, a.y, b.z), r)
	var dist := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(int(ceil(dist / 1.0)), 1)
	for k in range(1, steps + 1):
		if not _walk_ok(a.lerp(b, float(k) / steps)):
			return false
	var lift := maxf(b.y - a.y, 0.0)
	return sweep(Vector3(a.x, a.y + lift, a.z), Vector3(b.x, b.y + maxf(a.y - b.y, 0.0), b.z), r)


static func edge_between(a: int, b: int) -> int:
	return int(_edge_of.get(a * 1000003 + b, -1))


static func edge(ei: int) -> Dictionary:
	return edges[ei] if ei >= 0 and ei < edges.size() else {}


# ------------------------------------------------------------------ what bots report

static func report_stuck(a: int, b: int, bot_eid: int) -> void:
	## A bot could not get along the edge a-b: closed to every bot for 45 s (the third report this match: for the
	## rest of it), and remembered for the next matches (it costs more to route through).
	var ei := edge_between(a, b)
	if ei < 0:
		return
	var n := int(_hits.get(ei, 0)) + 1
	_hits[ei] = n
	var secs := 45.0 if n < 3 else 3600.0
	block(ei, secs)
	_learned[_ekey(ei)] = int(_learned.get(_ekey(ei), 0)) + 1
	stats.stuck_reports = int(stats.get("stuck_reports", 0)) + 1
	if Game.arg("bottrace") != null or Game.arg("navwatch") != null:
		print("[waypoints] bot %d stuck on %s -> %s (%s), report %d: closed %.0f s" % [bot_eid, nodes[a].id, nodes[b].id, str(edges[ei].kind), n, secs])


static func block(ei: int, secs: float) -> void:
	var e: Dictionary = edges[ei]
	if not astar.are_points_connected(int(e.a), int(e.b), false):
		return
	astar.disconnect_points(int(e.a), int(e.b), true)
	# never the only way between its ends (a bridge, the one doorway of a room): closing it would cut the graph in two,
	# and every bot on the far side would be left without a route. It stays open; the bots queue there.
	var alt := astar.get_id_path(int(e.a), int(e.b))
	var direct := (nodes[int(e.a)].p as Vector3).distance_to(nodes[int(e.b)].p)
	var alt_len := 0.0
	for k in range(1, alt.size()):
		alt_len += (nodes[alt[k - 1]].p as Vector3).distance_to(nodes[alt[k]].p)
	if alt.is_empty() or alt_len > direct * 6.0 + 40.0:
		astar.connect_points(int(e.a), int(e.b), not bool(e.one))
		stats.kept_open = int(stats.get("kept_open", 0)) + 1
		return
	_blocked[ei] = Time.get_ticks_msec() + int(secs * 1000.0)


static func tick() -> void:
	if _blocked.is_empty():
		return
	var now := Time.get_ticks_msec()
	for ei in _blocked.keys():
		if now >= int(_blocked[ei]):
			_blocked.erase(ei)
			var e: Dictionary = edges[ei]
			astar.connect_points(int(e.a), int(e.b), not bool(e.one))


static func _ekey(ei: int) -> String:
	var e: Dictionary = edges[ei]
	return "%s|%s" % [nodes[int(e.a)].id, nodes[int(e.b)].id]


static func _read_learned() -> void:
	_learned = {}
	var path := "user://waypoints/%s_learn.json" % map_id
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY or str(d.get("key", "")) != key:
		return
	for k in d.get("stuck", {}):
		var v := int(floor(float(d.stuck[k]) * 0.8))   # fades by a fifth a load
		if v > 0:
			_learned[str(k)] = v


static func save_learned() -> void:
	## After a match: the edges bots got stuck on (they cost more next time).
	if map_id == "" or _learned.is_empty():
		return
	DirAccess.make_dir_recursive_absolute("user://waypoints")
	var f := FileAccess.open("user://waypoints/%s_learn.json" % map_id, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"key": key, "stuck": _learned}))


# ------------------------------------------------------------------ the file

static func _paths() -> Array:
	return ["res://data/waypoints/%s.json" % map_id, "user://waypoints/%s.json" % map_id]


static func _read() -> Dictionary:
	## The shipped file, else the user's; an edited file is used whatever its key, an auto one only for this geometry.
	for path in _paths():
		if not FileAccess.file_exists(path):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) != TYPE_DICTIONARY or int(d.get("format", 0)) != FORMAT:
			continue
		if str(d.get("key", "")) == key or str(d.get("source", "")) == "edited":
			d["_from"] = path
			return d
	return {}


static func _load(d: Dictionary) -> bool:
	nodes = []
	edges = []
	source = str(d.get("source", "auto"))
	verified = str(d.get("verified", ""))
	var index := {}
	for r in d.get("nodes", []):
		var p: Array = r.p
		var dv: Array = r.get("d", [0, 0])
		var nd := {"id": str(r.id), "p": Vector3(float(p[0]), float(p[1]), float(p[2])), "lv": int(r.get("lv", 0)), "kind": str(r.get("k", "area")),
			"pri": clampi(int(r.get("pri", 2)), 1, 3), "name": str(r.get("n", "")), "dir": Vector2(float(dv[0]), float(dv[1])),
			"via": bool(r.get("via", false)), "comp": 0}
		index[nd.id] = nodes.size()
		nodes.append(nd)
	var inv := {}
	for k in EDGE_CODE:
		inv[EDGE_CODE[k]] = k
	for e in d.get("edges", []):
		var a = e[0]
		var b = e[1]
		# indices (generated files) or ids (the editor writes ids, so hand-made nodes and deletions stay consistent)
		var ia := int(index.get(str(a), -1)) if a is String else int(a)
		var ib := int(index.get(str(b), -1)) if b is String else int(b)
		if ia < 0 or ib < 0 or ia >= nodes.size() or ib >= nodes.size() or ia == ib:
			continue
		var code := str(e[2]) if e.size() > 2 else "w"
		var kind: String = inv.get(code.substr(0, 1), "walk")
		var door := int(code.substr(1)) if kind == "door" and code.length() > 1 else -1
		edges.append({"a": ia, "b": ib, "kind": kind, "door": door, "one": kind == "escalator" or (e.size() > 3 and bool(e[3]))})
	# an edited door edge names no door: the one it crosses
	for e2 in edges:
		if str(e2.kind) == "door" and int(e2.door) < 0:
			var dd = _door_crossed(nodes[int(e2.a)].p, nodes[int(e2.b)].p)
			if dd is Dictionary and not dd.is_empty():
				e2.door = int(dd.i)
	return not nodes.is_empty()


static func to_json() -> Dictionary:
	var out_n := []
	for nd in nodes:
		var p: Vector3 = nd.p
		var r := {"id": str(nd.id), "p": [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)], "lv": int(nd.lv), "k": str(nd.kind),
			"pri": int(nd.pri)}
		if str(nd.name) != "":
			r["n"] = str(nd.name)
		if (nd.dir as Vector2) != Vector2.ZERO:
			r["d"] = [snappedf((nd.dir as Vector2).x, 0.001), snappedf((nd.dir as Vector2).y, 0.001)]
		if nd.via:
			r["via"] = true
		out_n.append(r)
	var out_e := []
	for e in edges:
		var code: String = EDGE_CODE.get(str(e.kind), "w")
		if str(e.kind) == "door" and int(e.door) >= 0:
			code += str(int(e.door))
		var row := [int(e.a), int(e.b), code]
		if bool(e.one) and str(e.kind) != "escalator":
			row.append(true)
		out_e.append(row)
	return {"format": FORMAT, "map": map_id, "key": key, "source": source, "verified": verified, "nodes": out_n, "edges": out_e,
		"stats": {"nodes": nodes.size(), "edges": edges.size(), "orphans": int(stats.get("orphans", 0))}}


static func _write(to_res: bool) -> void:
	var path: String = _paths()[0] if to_res else _paths()[1]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_json()))
		print("[waypoints] saved %s (%d nodes, %d edges)" % [path, nodes.size(), edges.size()])


static func bake_to_res() -> void:
	## --waypoints_bake (tools/bake_botnav.sh): generated now (after BotNav's spots) and written under res://data.
	## An edited shipped graph is kept: its edges are checked again instead.
	var d := _read()
	if not d.is_empty() and str(d.get("source", "")) == "edited" and Game.arg("waypoints_regen") == null:
		_load(d)
		var dropped := _reverify()
		print("[waypoints] %s: kept the edited graph, %d edges dropped by the check" % [map_id, dropped.size()])
		verified = key
	else:
		generate()
		verified = ""
	_finish()
	phase = "ready"
	_write(true)
