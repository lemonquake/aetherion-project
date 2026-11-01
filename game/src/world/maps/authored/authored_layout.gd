extends RefCounted
## A map whose geometry is authored rather than generated: a scene built by addons/aetherion_map/map_scene.gd, from a
## TrenchBroom .map (Freight Delight, FreightLayout) or from a map editor file (res://maps/<id>/map.json, JsonLayout).
## This reads what the scene carries: the team spawns (info_team_spawn), the landmarks, the stair flights
## (func_stairs) and every solid brush as planes, from which it surveys one walk grid per level for the bots (level k
## at y = k * FH) and links the levels at the stairs. The subclass sets MAP_ID, FH, LEVELS, bounds and the rest, then
## calls load_scene().

var MAP_ID := ""
var FH := 3.2                # metres from one level's floor to the next (worldspawn level_height overrides)
var LEVELS := 2
const NAV_CELL := 0.5          # half-metre cells: a 1.2 m shanty door always has a cell through it
const BODY_R := 0.25         # cells closer than this to a wall are closed (bodies are 0.3: they brush past)
const CLEAR_LO := 0.45       # the body column checked for headroom, above the floor
const CLEAR_HI := 1.75

var MAP_SCALE := 1.0
var HALF := 70.0             # the map image covers [-HALF, HALF] on both axes
var PLAY_HALF := 62.0
var WATER_Y := -60.0
var LAND_Y := 0.0
var GRID := 2.0
var ROAD_TOP := 0.0
var WALK_TOP := 0.0
var rng := RandomNumberGenerator.new()
var roads: Array = []
var districts: Array = []
var sites: Array = []
var crossings: Array = []
var railway := PackedVector2Array()
var river := PackedVector2Array()
var estero := PackedVector2Array()
var landmarks: Array = []    # [{name, pos: Vector2}] for the SmarTab map
var edge := 62.0
var obstacles: Array = []
var bridge_rects: Array = []
var lamp_spots: Array = []
var dump_c := Vector2(1e6, 1e6)
var dump_r := 0.0
var zone_jitter := 6.0
var night_only := true
## Lighting's outdoor night, darker (src/world/lighting.gd _apply_night): a thin moon behind haze, a low brown sky
## glow from the port, little ambient, so the yard is lit mostly by its own bulbs, tubes and floodlights.
var night_grade := {"moon_k": 0.42, "ambient": Color(0.11, 0.12, 0.17), "ambient_energy": 0.12, "fog": 0.0062,
	"fog_color": Color(0.024, 0.022, 0.026), "vol_fog": 0.011, "exposure_k": 1.08, "saturation": 0.88, "contrast": 1.1,
	"sky_glow": Color(0.11, 0.06, 0.03), "sky_cloud": 0.8}
var bounds := Rect2(-62.0, -42.0, 124.0, 84.0)
var designated: Array = []   # designated_spots()
var spawns: Array = [[], []]
var spawn_yaw: Array = [0.0, 0.0]
var spawns3 = null           # three-team spawns [[...], [...], [...]] when the map has team 3 spawns (match_server)
var spawn_yaw3 = null
var dm_centre := Vector2.ZERO
var scene: Node3D            # the instanced map scene (MapBuilder adds it under the map root)
var flights: Array = []      # [{name, foot: Vector3, top: Vector3, dir: Vector3, width}]
var stats := {}
## Bot walk grids (NavLevels): one per level, 1 m cells over the play area, 1 = open; links are the stairs.
var nav_nx := 0
var nav_nz := 0
var nav_x0 := 0.0
var nav_z0 := 0.0
var nav_open: Array = []
var nav_links: Array = []
var _water := PackedByteArray()
var _fh := FH
var _aabb := PackedFloat32Array()
var _planes := PackedFloat32Array()
var _start := PackedInt32Array()
var _flags := PackedByteArray()
var _bucket := {}            # Vector2i (4 m) -> PackedInt32Array of brush indices


func load_scene(sc: Node3D) -> void:
	## Survey the built map scene (MapScene's root somewhere inside sc): markers, stairs, brushes, the walk grids.
	var t0 := Time.get_ticks_msec()
	scene = sc
	var data := _map_root(scene)
	if data == null:
		push_error("[%s] no built map inside the scene" % MAP_ID)
		return
	var ws: Dictionary = data.get_meta("worldspawn", {})
	_fh = float(ws.get("level_height", FH))
	FH = _fh
	_aabb = data.get_meta("brush_aabbs", PackedFloat32Array())
	_planes = data.get_meta("brush_planes", PackedFloat32Array())
	_start = data.get_meta("brush_start", PackedInt32Array())
	_flags = data.get_meta("brush_flags", PackedByteArray())
	flights = data.get_meta("stairs", [])
	_index_brushes()
	_read_markers(scene)
	stats.load_ms = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_init_nav()
	stats.nav_ms = Time.get_ticks_msec() - t0


static func _map_root(n: Node) -> Node:
	## The imported map's root (the node carrying the brush data), wherever it sits in the scene.
	if n.has_meta("brush_aabbs"):
		return n
	for c in n.get_children():
		var r := _map_root(c)
		if r != null:
			return r
	return null


func _read_markers(n: Node) -> void:
	## Team spawns and landmarks: from the map's entities, and from any Marker3D given the same metadata in Godot.
	## A spawn's "for" meta says which team layout uses it: "2" (two teams), "3" (three teams) or "" (both).
	var pts := {1: [], 2: [], 3: []}
	var pts3 := {1: [], 2: [], 3: []}
	var yaws := {1: [], 2: [], 3: []}
	var yaws3 := {1: [], 2: [], 3: []}
	var stack := [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		stack.append_array(c.get_children())
		if not c is Node3D:
			continue
		var p: Vector3 = _local_to_scene(c as Node3D)
		if c.has_meta("team"):
			var t := clampi(int(c.get_meta("team")), 1, 3)
			var use := str(c.get_meta("for", ""))
			if t <= 2 and use != "3":
				pts[t].append(p + Vector3(0, 0.02, 0))
				yaws[t].append(_yaw_of(c as Node3D))
			if use != "2":
				pts3[t].append(p + Vector3(0, 0.02, 0))
				yaws3[t].append(_yaw_of(c as Node3D))
		elif c.has_meta("landmark"):
			landmarks.append({"name": str(c.get_meta("landmark")), "pos": Vector2(p.x, p.z)})
	for t in [1, 2]:
		spawns[t - 1] = pts[t]
		var ys: Array = yaws[t]
		spawn_yaw[t - 1] = float(ys[0]) if not ys.is_empty() else 0.0
	if not pts3[1].is_empty() and not pts3[2].is_empty() and not pts3[3].is_empty():
		spawns3 = [pts3[1], pts3[2], pts3[3]]
		spawn_yaw3 = []
		for t in [1, 2, 3]:
			var ys3: Array = yaws3[t]
			spawn_yaw3.append(float(ys3[0]) if not ys3.is_empty() else 0.0)
	stats.spawns = [spawns[0].size(), spawns[1].size()]
	if spawns3 != null:
		stats.spawns3 = [spawns3[0].size(), spawns3[1].size(), spawns3[2].size()]


func _local_to_scene(n: Node3D) -> Vector3:
	## Position relative to the scene root (the scene is not in the tree yet, so no global_transform).
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != scene:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf.origin


func _yaw_of(n: Node3D) -> float:
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != scene:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	var f := -xf.basis.z
	return atan2(-f.x, -f.z)


# ------------------------------------------------------------------ the layout interface (shared with the other maps)

func ground_height(_x: float, _z: float) -> float:
	return LAND_Y


func terrain_height(_x: float, _z: float) -> float:
	return LAND_Y - 0.02


func is_water(_x: float, _z: float) -> bool:
	return false


func water_height(_x: float, _z: float) -> float:
	return WATER_Y


func water_sd(_p: Vector2) -> Vector2:
	return Vector2(99.0, 0.0)


func in_play_area(p: Vector2) -> bool:
	return bounds.grow(-1.0).has_point(p)


func inside(p: Vector2, margin: float = 0.0) -> bool:
	return bounds.grow(-margin).has_point(p)


func coast_z(_x: float) -> float:
	return 1e5


func reserved_at(_x: float, _z: float) -> int:
	return 0


func surface_y(_p: Vector2) -> float:
	return LAND_Y


func level_y(level: int) -> float:
	return level * _fh


func level_of(y: float) -> int:
	return clampi(int(floor((y + 1.2) / _fh)), 0, LEVELS - 1)


func pick_spawns() -> void:
	pass   # the spawns are the map's own entities


func dm_centre_for(_n_teams: int) -> Vector2:
	return dm_centre


# ------------------------------------------------------------------ brushes

func _index_brushes() -> void:
	_bucket.clear()
	for i in _flags.size():
		var a := i * 6
		var lo := Vector2i(floori(_aabb[a] / 4.0), floori(_aabb[a + 2] / 4.0))
		var hi := Vector2i(floori(_aabb[a + 3] / 4.0), floori(_aabb[a + 5] / 4.0))
		for bx in range(lo.x, hi.x + 1):
			for bz in range(lo.y, hi.y + 1):
				var k := Vector2i(bx, bz)
				if not _bucket.has(k):
					_bucket[k] = PackedInt32Array()
				_bucket[k].append(i)


func _span(i: int, x: float, z: float) -> Vector2:
	## The brush's extent along the vertical line through (x, z): Vector2(bottom, top), or x > y when it misses.
	var a := i * 6
	if x < _aabb[a] - 1e-4 or x > _aabb[a + 3] + 1e-4 or z < _aabb[a + 2] - 1e-4 or z > _aabb[a + 5] + 1e-4:
		return Vector2(1.0, -1.0)
	var lo := -1e9
	var hi := 1e9
	var s := _start[i]
	var e := _start[i + 1] if i + 1 < _start.size() else _planes.size()
	var k := s
	while k < e:
		var nx := _planes[k]
		var ny := _planes[k + 1]
		var nz := _planes[k + 2]
		var d := _planes[k + 3]
		# n . (x, y, z) <= d
		var rest := d - nx * x - nz * z
		if absf(ny) < 1e-6:
			if rest < -1e-4:
				return Vector2(1.0, -1.0)
		elif ny > 0.0:
			hi = minf(hi, rest / ny)
		else:
			lo = maxf(lo, rest / ny)
		k += 4
	return Vector2(lo, hi)


func spans_at(x: float, z: float) -> Array:
	## Every solid brush's [bottom, top] on the vertical through (x, z).
	var out := []
	for i in _bucket.get(Vector2i(floori(x / 4.0), floori(z / 4.0)), PackedInt32Array()):
		var sp := _span(i, x, z)
		if sp.x <= sp.y:
			out.append(sp)
	return out


func floor_below(x: float, z: float, y: float) -> float:
	## The highest solid top at or below y (+ a step) on the vertical through (x, z); -INF if none.
	var best := -INF
	for sp in spans_at(x, z):
		if sp.y <= y + 0.05 and sp.y > best:
			best = sp.y
	return best


# ------------------------------------------------------------------ bot walk grids

func _init_nav() -> void:
	## Each brush is drawn into the grids rather than each cell asking every brush: first the floors (the highest
	## solid top within a step of the level, under the cell's centre), then whatever stands in the body's way above
	## that floor, within a body's radius of the cell.
	nav_x0 = bounds.position.x
	nav_z0 = bounds.position.y
	nav_nx = int(bounds.size.x / NAV_CELL)
	nav_nz = int(bounds.size.y / NAV_CELL)
	_water.resize(nav_nx * nav_nz)
	nav_open.clear()
	var nb := _flags.size()
	var boxy := PackedByteArray()
	boxy.resize(nb)
	for i in nb:
		var s := _start[i]
		var e := _start[i + 1] if i + 1 < _start.size() else _planes.size()
		var ax := 1
		var k := s
		while k < e:
			if maxf(absf(_planes[k]), maxf(absf(_planes[k + 1]), absf(_planes[k + 2]))) < 0.9999:
				ax = 0
				break
			k += 4
		boxy[i] = ax
	var open_n := []
	for lv in LEVELS:
		var ly := level_y(lv)
		var sup := PackedFloat32Array()
		sup.resize(nav_nx * nav_nz)
		sup.fill(-1e9)
		for i in nb:
			var r := _cells(i, 0.0)
			for iz in range(r.position.y, r.end.y):
				for ix in range(r.position.x, r.end.x):
					var c := nav_cell_centre(ix, iz)
					var sp := _span_fast(i, c.x, c.y, boxy[i] == 1)
					if sp.x <= sp.y and sp.y >= ly - 0.5 and sp.y <= ly + 0.45:
						var j := iz * nav_nx + ix
						if sp.y > sup[j]:
							sup[j] = sp.y
		# (r27) Terrain3D ground: the heightfield is a floor wherever it lies within this level's step band and no
		# neighbouring cell is steeper than a body walks; where it rises into the body (a bank beside a trail, the
		# ground over a buried slab) the cell is closed. One height per cell, sampled once for every level.
		if has_terrain and _cell_th.is_empty():
			_cell_th.resize(nav_nx * nav_nz)
			for iz in nav_nz:
				for ix in nav_nx:
					var c3 := nav_cell_centre(ix, iz)
					_cell_th[iz * nav_nx + ix] = _terrain_h(c3.x, c3.y)
		if has_terrain and lv == 0:
			# (the ground is level 0's floor only: a bank's top that happens to reach an upper level is not a floor)
			var lim := MAX_SLOPE * NAV_CELL
			for iz in nav_nz:
				for ix in nav_nx:
					var j3 := iz * nav_nx + ix
					var th := _cell_th[j3]
					if is_nan(th) or th < ly - 0.5 or th > ly + 0.45 or th <= sup[j3]:
						continue
					var steep := false
					for nb2 in [j3 - 1 if ix > 0 else -1, j3 + 1 if ix < nav_nx - 1 else -1, j3 - nav_nx if iz > 0 else -1, j3 + nav_nx if iz < nav_nz - 1 else -1]:
						if nb2 >= 0 and not is_nan(_cell_th[nb2]) and absf(_cell_th[nb2] - th) > lim:
							steep = true
							break
					if not steep:
						sup[j3] = th
		var g := PackedByteArray()
		g.resize(nav_nx * nav_nz)
		for j in g.size():
			g[j] = 1 if sup[j] > -1e8 else 0
		if has_terrain:
			for iz in nav_nz:
				for ix in nav_nx:
					var j4 := iz * nav_nx + ix
					if g[j4] == 0:
						continue
					for nb4 in [j4, j4 - 1 if ix > 0 else -1, j4 + 1 if ix < nav_nx - 1 else -1, j4 - nav_nx if iz > 0 else -1, j4 + nav_nx if iz < nav_nz - 1 else -1]:
						if nb4 >= 0 and not is_nan(_cell_th[nb4]) and _cell_th[nb4] > sup[j4] + CLEAR_LO and _cell_th[nb4] < sup[j4] + 40.0:
							g[j4] = 0
							break
		for i in nb:
			var r2 := _cells(i, BODY_R)
			var a := i * 6
			for iz in range(r2.position.y, r2.end.y):
				for ix in range(r2.position.x, r2.end.x):
					var j2 := iz * nav_nx + ix
					if g[j2] == 0:
						continue
					var c2 := nav_cell_centre(ix, iz)
					var sp2 := _span_fast(i, clampf(c2.x, _aabb[a], _aabb[a + 3]), clampf(c2.y, _aabb[a + 2], _aabb[a + 5]), boxy[i] == 1)
					if sp2.x <= sp2.y and sp2.y > sup[j2] + CLEAR_LO and sp2.x < sup[j2] + CLEAR_HI:
						g[j2] = 0
		nav_open.append(g)
	# Keep what a body can reach: the ground from the team spawns, the second floor from the stair tops. Container
	# tops and shanty roofs at the second floor's height are islands nobody walks onto (and bots must not aim for).
	var seeds := []
	for lv in LEVELS:
		seeds.append([])
	var all_spawns: Array = spawns.duplicate()
	if spawns3 != null:
		all_spawns.append_array(spawns3)
	for set in all_spawns:
		for p in set:
			seeds[level_of((p as Vector3).y)].append(Vector2((p as Vector3).x, (p as Vector3).z))
	for f in flights:
		seeds[level_of((f.foot as Vector3).y)].append(Vector2((f.foot as Vector3).x, (f.foot as Vector3).z))
		seeds[level_of((f.top as Vector3).y)].append(Vector2((f.top as Vector3).x, (f.top as Vector3).z))
	for lv in LEVELS:
		nav_open[lv] = _reachable(nav_open[lv], seeds[lv])
		var n_open := 0
		for b in (nav_open[lv] as PackedByteArray):
			n_open += b
		open_n.append(n_open)
	stats.nav_open = open_n
	nav_links.clear()
	for f in flights:
		var foot: Vector3 = f.foot
		var top: Vector3 = f.top
		var via := []
		for k in range(1, 4):
			via.append(foot.lerp(top, k / 4.0) + Vector3(0, 0.1, 0))
		var la := level_of(foot.y)
		var lb := level_of(top.y)
		if la != lb:
			add_link(Vector3(foot.x, level_y(la), foot.z), Vector3(top.x, level_y(lb), top.z), via, foot.distance_to(top) * 1.3, true)
	stats.links = nav_links.size()


## (r27) Uneven ground (a JsonLayout with Terrain3D): the subclass sets has_terrain and answers _terrain_h.
var has_terrain := false
const MAX_SLOPE := 0.8       # rise per metre a body walks up (about 39 degrees)
var _cell_th := PackedFloat32Array()


func _terrain_h(_x: float, _z: float) -> float:
	return NAN


func _reachable(g: PackedByteArray, from: Array) -> PackedByteArray:
	## The open cells connected (4-way) to any seed's nearest open cell; the rest closed.
	var keep := PackedByteArray()
	keep.resize(g.size())
	var queue := PackedInt32Array()
	for p in from:
		var c := nav_cell(p)
		var best := -1
		for r in 3:
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var x := c.x + dx
					var z := c.y + dz
					if best < 0 and x >= 0 and z >= 0 and x < nav_nx and z < nav_nz and g[z * nav_nx + x] == 1:
						best = z * nav_nx + x
		if best >= 0 and keep[best] == 0:
			keep[best] = 1
			queue.append(best)
	var head := 0
	while head < queue.size():
		var j := queue[head]
		head += 1
		var x0 := j % nav_nx
		for nb in [j - 1 if x0 > 0 else -1, j + 1 if x0 < nav_nx - 1 else -1, j - nav_nx, j + nav_nx]:
			if nb >= 0 and nb < g.size() and g[nb] == 1 and keep[nb] == 0:
				keep[nb] = 1
				queue.append(nb)
	return keep


func _cells(i: int, grow: float) -> Rect2i:
	## The grid cells whose centres lie within brush i's bounds grown by grow (clamped to the grid).
	var a := i * 6
	var x0 := clampi(ceili((_aabb[a] - grow - nav_x0) / NAV_CELL - 0.5), 0, nav_nx)
	var x1 := clampi(floori((_aabb[a + 3] + grow - nav_x0) / NAV_CELL - 0.5) + 1, 0, nav_nx)
	var z0 := clampi(ceili((_aabb[a + 2] - grow - nav_z0) / NAV_CELL - 0.5), 0, nav_nz)
	var z1 := clampi(floori((_aabb[a + 5] + grow - nav_z0) / NAV_CELL - 0.5) + 1, 0, nav_nz)
	return Rect2i(x0, z0, maxi(x1 - x0, 0), maxi(z1 - z0, 0))


func _span_fast(i: int, x: float, z: float, box: bool) -> Vector2:
	if box:
		var a := i * 6
		if x < _aabb[a] - 1e-4 or x > _aabb[a + 3] + 1e-4 or z < _aabb[a + 2] - 1e-4 or z > _aabb[a + 5] + 1e-4:
			return Vector2(1.0, -1.0)
		return Vector2(_aabb[a + 1], _aabb[a + 4])
	return _span(i, x, z)


func nav_cell_centre(ix: int, iz: int) -> Vector2:
	return Vector2(nav_x0 + (ix + 0.5) * NAV_CELL, nav_z0 + (iz + 0.5) * NAV_CELL)


func nav_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - nav_x0) / NAV_CELL)), 0, nav_nx - 1), clampi(int(floor((p.y - nav_z0) / NAV_CELL)), 0, nav_nz - 1))


func add_link(a: Vector3, b: Vector3, via: Array = [], cost: float = 1.0, both: bool = false) -> void:
	nav_links.append({"a": a, "b": b, "via": via, "cost": cost, "both": both})


## Bot waypoints (BotTeam.spots), worked out once: a sample every 4 m of reachable floor on both levels, with the
## cover beside it and its longest sightline. Seen from the second floor, the yard below counts as open (the eye is
## above the containers and the shanty roofs). Upstairs spots with a long view are "snipe": the deck, the bridges, the
## crane platform and the Taas windows are where the snipers go.
var _bot_spots: Array = []


func designated_spots() -> Array:
	## The places this map offers bots by design ({p, kind hide | snipe, face?, name}): BotNav looks each one round.
	return designated


func bot_spots() -> Array:
	if not _bot_spots.is_empty() or nav_open.size() < LEVELS or LEVELS < 1:
		return _bot_spots
	var step := int(round(4.0 / NAV_CELL))
	var reach := int(round(70.0 / NAV_CELL))
	var dirs := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
	for lv in LEVELS:
		var g: PackedByteArray = nav_open[lv]
		for iz in range(step / 2, nav_nz, step if lv == 0 else 3):
			for ix in range(step / 2, nav_nx, step if lv == 0 else 3):
				if g[iz * nav_nx + ix] == 0:
					continue
				var cover := 0
				for dz in range(-2, 3):
					for dx in range(-2, 3):
						var x := ix + dx
						var z := iz + dz
						if x < 0 or z < 0 or x >= nav_nx or z >= nav_nz or g[z * nav_nx + x] == 0:
							cover += 1
				var best := 0.0
				var bdir := Vector2i(1, 0)
				for d in dirs:
					var k := 1
					while k < reach:
						var cx: int = ix + d.x * k
						var cz: int = iz + d.y * k
						if cx < 0 or cz < 0 or cx >= nav_nx or cz >= nav_nz:
							break
						var c := cz * nav_nx + cx
						var seen := false
						for kl in lv + 1:
							if (nav_open[kl] as PackedByteArray)[c] == 1:
								seen = true
								break
						if not seen:
							break
						k += 2
					var ln := k * NAV_CELL * (1.4142 if d.x != 0 and d.y != 0 else 1.0)
					if ln > best:
						best = ln
						bdir = d
				var kind := "open"
				if lv >= 1 and best >= 35.0:
					kind = "snipe"
				elif cover >= 3 and best >= 60.0:
					kind = "snipe"
				elif cover >= 5:
					kind = "cover"
				var p := nav_cell_centre(ix, iz)
				_bot_spots.append({"p": Vector3(p.x, level_y(lv), p.y), "cover": mini(cover / 3, 8), "sight": best, "dir": Vector2(bdir).normalized(), "kind": kind})
	return _bot_spots


# ------------------------------------------------------------------ the level map (minimap and SmarTab)

func map_image() -> Image:
	## Ground walkable dark grey, second floor lighter, solid black; spawns tinted by team.
	var size := 512
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var s := size / (HALF * 2.0)
	for py in size:
		for px in size:
			var x := -HALF + (px + 0.5) / s
			var z := -HALF + (py + 0.5) / s
			var c := Color(0.06, 0.07, 0.08)
			if inside(Vector2(x, z)):
				var cell := nav_cell(Vector2(x, z))
				var i := cell.y * nav_nx + cell.x
				c = Color(0.11, 0.1, 0.09)
				for lv in range(nav_open.size() - 1, -1, -1):
					if (nav_open[lv] as PackedByteArray)[i] == 1:
						c = Color(0.24, 0.25, 0.25).lerp(Color(0.46, 0.43, 0.36), float(lv) / maxf(nav_open.size() - 1, 1))
						break
			img.set_pixel(px, py, c)
	for t in 2:
		var tint := Color(0.25, 0.45, 0.85) if t == 0 else Color(0.85, 0.35, 0.25)
		for p in spawns[t]:
			var q: Vector3 = p
			var cx := int((q.x + HALF) * s)
			var cz := int((q.z + HALF) * s)
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					if cx + dx >= 0 and cx + dx < size and cz + dz >= 0 and cz + dz < size:
						img.set_pixel(cx + dx, cz + dz, tint)
	for f in flights:
		var a: Vector3 = f.foot
		var b: Vector3 = f.top
		for k in 21:
			var q := a.lerp(b, k / 20.0)
			var cx := int((q.x + HALF) * s)
			var cz := int((q.z + HALF) * s)
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if cx + dx >= 0 and cx + dx < size and cz + dz >= 0 and cz + dz < size:
						img.set_pixel(cx + dx, cz + dz, Color(0.95, 0.8, 0.3))
	return img
