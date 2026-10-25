extends RefCounted
## Acoustic model of the map: rooms (zones) connected by openings (portals).
##
## Zone 0 is the outdoors. Each indoor zone is an axis-aligned box (one room on one floor of one building).
## A portal joins two zones at a point: a door (loss depends on how far it is open), a window (intact glass,
## shutters or open), a curtain doorway, or a stair/ladder hole between floors. Walls also transmit sound
## directly with a loss that depends on their material.
##
## propagate() answers "how does a sound at A reach a listener at B": it compares the best path through openings
## (Dijkstra over zones) with the direct path through walls, and returns where the listener should hear the
## sound come from, how much quieter it is, how muffled (0..3) and which reverb applies.

const CELL := 6.0
const OUTDOOR := 0

## Loss in dB when a portal is fully closed; interpolates to `open` as openness -> 1.
const PORTAL_LOSS := {
	"door": {"closed": 16.0, "open": 0.5, "occ_closed": 2},
	"door_metal": {"closed": 20.0, "open": 0.5, "occ_closed": 3},
	"window": {"closed": 11.0, "open": 0.5, "occ_closed": 1},
	"shutter": {"closed": 9.0, "open": 0.5, "occ_closed": 1},
	"curtain": {"closed": 2.5, "open": 0.5, "occ_closed": 0},
	"opening": {"closed": 0.5, "open": 0.5, "occ_closed": 0},
	"stair": {"closed": 1.5, "open": 1.5, "occ_closed": 0},
	"floor_gap": {"closed": 7.0, "open": 7.0, "occ_closed": 1},
}
## Transmission loss through one wall / floor of a material.
const WALL_LOSS := {
	"sheet_metal": 8.0, "plywood": 10.0, "wood": 11.0, "bamboo": 7.0, "fabric": 3.0, "glass": 9.0,
	"hollow_block": 21.0, "plaster": 19.0, "concrete": 28.0, "steel": 18.0, "default": 15.0,
}

var zones: Array = []        # [{aabb, building, floor, reverb, floor_mat}]
var portals: Array = []      # [{a, b, pos, kind, open}]
var _adj: Dictionary = {}    # zone -> [portal ids]
var _grid: Dictionary = {}   # Vector2i -> [zone ids]
var space: PhysicsDirectSpaceState3D = null


func _init() -> void:
	zones.append({"aabb": AABB(), "building": -1, "floor": 0, "reverb": "outdoor", "floor_mat": "dirt"})
	_adj[OUTDOOR] = []


func add_zone(aabb: AABB, building: int, floor: int, reverb: String, floor_mat: String = "wood") -> int:
	var id := zones.size()
	zones.append({"aabb": aabb, "building": building, "floor": floor, "reverb": reverb, "floor_mat": floor_mat})
	_adj[id] = []
	var a := Vector2i(floori(aabb.position.x / CELL), floori(aabb.position.z / CELL))
	var b := Vector2i(floori(aabb.end.x / CELL), floori(aabb.end.z / CELL))
	for x in range(a.x, b.x + 1):
		for z in range(a.y, b.y + 1):
			var k := Vector2i(x, z)
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(id)
	return id


func add_portal(a: int, b: int, pos: Vector3, kind: String, openness: float = 1.0) -> int:
	var id := portals.size()
	portals.append({"a": a, "b": b, "pos": pos, "kind": kind, "open": openness})
	_adj[a].append(id)
	_adj[b].append(id)
	return id


func set_portal_open(id: int, openness: float) -> void:
	if id >= 0 and id < portals.size():
		portals[id].open = clampf(openness, 0.0, 1.0)


func set_portal_kind(id: int, kind: String) -> void:
	if id >= 0 and id < portals.size():
		portals[id].kind = kind


func zone_at(p: Vector3) -> int:
	var k := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var best := OUTDOOR
	var best_vol := INF
	for id in _grid.get(k, []):
		var bb: AABB = zones[id].aabb
		if bb.grow(0.05).has_point(p):
			var vol := bb.get_volume()
			if vol < best_vol:
				best = id
				best_vol = vol
	return best


func reverb_at(p: Vector3) -> String:
	return zones[zone_at(p)].reverb


func portal_loss(pid: int) -> Vector2:
	## x = loss dB, y = muffling level contribution
	var P: Dictionary = portals[pid]
	var cfg: Dictionary = PORTAL_LOSS.get(P.kind, PORTAL_LOSS.opening)
	var o: float = P.open
	var loss := lerpf(cfg.closed, cfg.open, clampf(o, 0.0, 1.0))
	var occ := 0.0 if o > 0.35 else float(cfg.occ_closed)
	return Vector2(loss, occ)


func propagate(src: Vector3, lis: Vector3, max_dist: float) -> Dictionary:
	var zs := zone_at(src)
	var zl := zone_at(lis)
	var straight := src.distance_to(lis)
	var reverb: String = zones[zl].reverb if zl != OUTDOOR else zones[zs].reverb
	if zs == zl:
		var res := {"pos": src, "gain_db": 0.0, "occ": 0, "reverb": reverb, "dist": straight}
		if zs == OUTDOOR and space and straight > 2.0:
			var w := _walls_between(src + Vector3.UP * 0.3, lis, 3)
			if w.x > 0.0:
				# Outdoors sound also bends around buildings, so walls cost less than indoors.
				res.gain_db = -minf(w.x * 0.45, 14.0)
				res.occ = mini(int(w.y), 2)
		return res
	# Best path through openings.
	var best_path := _route(zs, zl, src, lis, max_dist * 1.4)
	# Direct path through walls and floors.
	var direct_db := -INF
	var direct_occ := 3
	if space:
		var w := _walls_between(src, lis, 4)
		direct_db = -w.x
		direct_occ = mini(3, int(w.y) + (1 if w.x > 8.0 else 0))
	else:
		direct_db = -30.0
	if best_path.is_empty() or (direct_db - 20.0 * log(maxf(straight, 1.0)) / log(10.0)) > \
			(-float(best_path.loss) - 20.0 * log(maxf(float(best_path.length), 1.0)) / log(10.0)):
		return {"pos": src, "gain_db": direct_db, "occ": direct_occ, "reverb": reverb, "dist": straight}
	var last: Vector3 = best_path.last
	var dir := (last - lis)
	if dir.length() < 0.05:
		dir = src - lis
	var vpos := lis + dir.normalized() * maxf(float(best_path.length), 0.5)
	return {"pos": vpos, "gain_db": -float(best_path.loss), "occ": mini(int(best_path.occ), 3), "reverb": reverb,
		"dist": float(best_path.length)}


func _route(zs: int, zl: int, src: Vector3, lis: Vector3, max_len: float) -> Dictionary:
	## Dijkstra over portals. State = (zone, entry point). Cost = path length + loss expressed as distance.
	var dist := {zs: 0.0}
	var loss := {zs: 0.0}
	var occ := {zs: 0.0}
	var point := {zs: src}
	var lastp := {zs: src}
	var open := [zs]
	var visited := {}
	var hops := {zs: 0}
	while not open.is_empty():
		var bi := 0
		for i in open.size():
			if _score(dist[open[i]], loss[open[i]]) < _score(dist[open[bi]], loss[open[bi]]):
				bi = i
		var z: int = open[bi]
		open.remove_at(bi)
		if visited.has(z):
			continue
		visited[z] = true
		if z == zl:
			var total: float = dist[z] + (point[z] as Vector3).distance_to(lis)
			return {"length": total, "loss": loss[z], "occ": occ[z], "last": lastp[z]}
		if hops[z] >= 6:
			continue
		for pid in _adj[z]:
			var P: Dictionary = portals[pid]
			var nz: int = P.b if P.a == z else P.a
			if visited.has(nz):
				continue
			var step: float = (point[z] as Vector3).distance_to(P.pos)
			var nd: float = dist[z] + step
			if nd > max_len:
				continue
			var pl := portal_loss(pid)
			var nl: float = loss[z] + pl.x
			if not dist.has(nz) or _score(nd, nl) < _score(dist[nz], loss[nz]):
				dist[nz] = nd
				loss[nz] = nl
				occ[nz] = occ[z] + pl.y
				point[nz] = P.pos
				lastp[nz] = P.pos
				hops[nz] = hops[z] + 1
				open.append(nz)
	return {}


func _score(d: float, l: float) -> float:
	# 6 dB of loss is treated like doubling the distance.
	return d * pow(2.0, l / 6.0)


func _walls_between(a: Vector3, b: Vector3, max_hits: int) -> Vector2:
	## Sums transmission loss of walls crossed between a and b. x = dB, y = muffling hits.
	var total := 0.0
	var hits := 0
	var from := a
	for i in max_hits:
		# Rays starting inside a wall ignore it, so stepping just past each hit finds the next wall.
		var q := PhysicsRayQueryParameters3D.create(from, b, Defs.PHYS_WORLD | Defs.PHYS_GLASS)
		q.hit_back_faces = false
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		var mat := "default"
		if r.collider and r.collider.has_meta("mat"):
			mat = str(r.collider.get_meta("mat"))
		total += float(WALL_LOSS.get(mat, WALL_LOSS.default))
		hits += 1
		from = r.position + (b - a).normalized() * 0.06
	if hits >= max_hits:
		total += 8.0
	return Vector2(total, hits)
