extends RefCounted
## Geography of Lawless Sub (Deathmatch map, r7): a walled Philippine subdivision at a city edge, cut by a walled
## canal, its basin and an estero, crossed by a 4-lane avenue and a boulevard. x = east, z = south, y = up, metres,
## built at full scale. The plan is data (res://data/maps/lawless_sub.json); this file turns it into masks, heights
## and lots, and exposes the same members the rest of the game reads from Sitio Kalinaw's layout (layout.gd), as
## plain vars. See work/lemondev/r7/map/INTERFACE.md.

const PLAN_PATH := "res://data/maps/lawless_sub.json"
const MAP_ID := "lawless_sub"

# --- the members other systems read (same names as layout.gd; plain vars, so nothing shadows a constant)
var MAP_SCALE := 1.0
var HALF := 280.0
var PLAY_HALF := 220.0
var WATER_Y := -0.6
var LAND_Y := 0.9
var GRID := 2.0
var rng := RandomNumberGenerator.new()
var roads: Array = []        # [{name, pts: PackedVector2Array (2 points, axis-aligned), w, mat, curb, sidewalk, median, lanes, prio, axis, c, lo, hi}]
var districts: Array = []    # [{name, kind, c, half, ang}] (informational: Phase 1, Phase 2, Old Barangay, ...)
var sites: Array = []        # [{type, pos, ang, name}] one per big-building lot
var crossings: Array = []    # [{type, a, b, w, name}] bridges, footbridge, pipe crossing
var railway := PackedVector2Array()
var river := PackedVector2Array()
var estero := PackedVector2Array()
var landmarks: Array = []    # [{name, pos: Vector2}]
var _n: int
var _water: PackedByteArray      # 1 = water
var _reserved: PackedByteArray   # 1 road/paved, 2 big building, 3 house envelope, 4 canal walk / wall top, 5 wall line

# --- Lawless Sub specifics
var plan: Dictionary = {}
var lots: Array = []         # see INTERFACE.md
var parking: Array = []      # [{name, rect: Rect2, mat, stalls, out?, in?}]
var walls: Array = []        # [{name, a, b, h, gaps: [[t0, t1, kind]], collapsed: [[t0, t1]]}] t along the wall from a
var water_polys: Array = []  # [{name, pts: PackedVector2Array, bed, deep, bbox: Rect2}]
var esteros: Array = []      # [{name, a, b, hw, bank, bed}]
var bridges: Array = []      # plan bridges; road bridges carry rect: Rect2
var ladder_spots: Array = [] # [[x, z, dir]]
var spawns: Array = [[], []] # [team] -> Array[Vector3] feet positions on the walkable surface
var spawn_yaw: Array = [0.0, 0.0]  # [team] -> rotation.y (radians) facing dm_centre
var spawn_centres: Array = []
var spawn_zone_r := 17.0
var dm_centre := Vector2(-20, 0)
var edge := 224.0            # the perimeter wall around the play area
var obstacles: Array = []    # [[Vector2 centre, radius]] street furniture placed by the builder (spawn picking avoids it)
var bridge_rects: Array = [] # [Rect2] road decks over water: ground_height is the deck there
var lamp_spots: Array = []   # filled by the builder
var dump_c := Vector2(1e6, 1e6)  # no dump here (the shared terrain code asks)
var dump_r := 0.0

const WALL_T := 0.6          # canal wall thickness
const APRON := 6.5           # concrete walk beside a walled canal (covers the terrain's ramp down to the bed)
const BED_SD := 3.0          # terrain is the bed up to this far outside the water's edge...
const RAMP_SD := 3.5         # ...and climbs back to land by here (both inside the apron, so the ramp never shows)
const APRON_TOP := 0.02      # above LAND_Y
const WALL_TOP := 0.045
const ROAD_TOP := 0.06
const WALK_TOP := 0.18       # sidewalk top above the ground

var _noise := FastNoiseLite.new()
var _wbox := Rect2()         # bounding box of every walled water polygon (+ apron)


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	_noise.seed = seed_value
	_noise.frequency = 0.0045
	_noise.fractal_octaves = 2
	var txt := FileAccess.get_file_as_string(PLAN_PATH)
	var parsed = JSON.parse_string(txt)
	plan = parsed if parsed is Dictionary else {}
	HALF = float(plan.get("half", 280))
	PLAY_HALF = float(plan.get("play_half", 220))
	LAND_Y = float(plan.get("land_y", 0.9))
	WATER_Y = float(plan.get("water_y", -0.6))
	edge = float(plan.get("edge", 224))
	dm_centre = _v2(plan.get("dm_centre", [-20, 0]))
	spawn_zone_r = float(plan.get("spawn_zone_r", 17))
	for c in plan.get("spawn_centres", []):
		spawn_centres.append(_v2(c))
	_n = int(HALF * 2.0 / GRID)
	_water = PackedByteArray()
	_water.resize(_n * _n)
	_reserved = PackedByteArray()
	_reserved.resize(_n * _n)
	_define()
	_rasterize()
	_make_lots()


static func _v2(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


# ------------------------------------------------------------------ plan

func _define() -> void:
	for r in plan.get("roads", []):
		var a := _v2(r.a)
		var b := _v2(r.b)
		var axis := 0 if absf(b.x - a.x) > absf(b.y - a.y) else 1   # 0: runs along x (E-W), 1: along z (N-S)
		var rd := {"name": str(r.name), "pts": PackedVector2Array([a, b]), "w": float(r.w), "mat": str(r.get("mat", "road_asphalt")),
			"curb": float(r.get("sidewalk", 0)) > 0.0, "sidewalk": float(r.get("sidewalk", 0)), "median": float(r.get("median", 0)),
			"lanes": int(r.get("lanes", 0)), "prio": int(r.get("prio", 3)), "lamps": str(r.get("lamps", "one")), "axis": axis,
			"c": a.y if axis == 0 else a.x, "lo": minf(a.x, b.x) if axis == 0 else minf(a.y, b.y), "hi": maxf(a.x, b.x) if axis == 0 else maxf(a.y, b.y)}
		roads.append(rd)
	for w in plan.get("water", []):
		if str(w.kind) == "walled":
			var pts := PackedVector2Array()
			for q in w.poly:
				pts.append(_v2(q))
			var bb := Rect2(pts[0], Vector2.ZERO)
			for q in pts:
				bb = bb.expand(q)
			water_polys.append({"name": str(w.name), "pts": pts, "bed": float(w.get("bed", -1.5)), "deep": float(w.get("deep", -1.5)), "bbox": bb})
			_wbox = bb.grow(APRON + 3.0) if _wbox.size == Vector2.ZERO else _wbox.merge(bb.grow(APRON + 3.0))
		else:
			esteros.append({"name": str(w.name), "a": _v2(w.a), "b": _v2(w.b), "hw": float(w.w) * 0.5, "bank": float(w.get("bank", 4)), "bed": float(w.get("bed", -1.6))})
			estero = PackedVector2Array([_v2(w.a), _v2(w.b)])
	for b in plan.get("bridges", []):
		var bd: Dictionary = b.duplicate()
		if b.has("rect"):
			var rr: Array = b.rect
			bd.rect = Rect2(Vector2(rr[0], rr[1]), Vector2(float(rr[2]) - float(rr[0]), float(rr[3]) - float(rr[1])))
			bridge_rects.append(bd.rect)
			var r2: Rect2 = bd.rect
			var horiz := r2.size.x > r2.size.y
			var ca := r2.get_center()
			crossings.append({"type": str(b.type), "a": Vector2(r2.position.x, ca.y) if horiz else Vector2(ca.x, r2.position.y),
				"b": Vector2(r2.end.x, ca.y) if horiz else Vector2(ca.x, r2.end.y), "w": r2.size.y if horiz else r2.size.x, "name": str(b.name)})
		else:
			bd.a = _v2(b.a)
			bd.b = _v2(b.b)
			crossings.append({"type": str(b.type), "a": bd.a, "b": bd.b, "w": float(b.get("w", 1.0)), "name": str(b.name)})
		bridges.append(bd)
	ladder_spots = plan.get("ladders", [])
	for p in plan.get("parking", []):
		var rr: Array = p.rect
		var pd: Dictionary = p.duplicate()
		pd.rect = Rect2(Vector2(rr[0], rr[1]), Vector2(float(rr[2]) - float(rr[0]), float(rr[3]) - float(rr[1])))
		parking.append(pd)
	for w in plan.get("walls", []):
		var wd: Dictionary = w.duplicate()
		wd.a = _v2(w.a)
		wd.b = _v2(w.b)
		walls.append(wd)
	for m in plan.get("landmarks", []):
		landmarks.append({"name": str(m.name), "pos": _v2(m.pos)})
	districts = [
		{"name": "Phase 1", "kind": "subdivision", "c": Vector2(105, -113), "half": Vector2(111, 101), "ang": 0.0},
		{"name": "Phase 2", "kind": "subdivision", "c": Vector2(105, 61), "half": Vector2(111, 49), "ang": 0.0},
		{"name": "Old Barangay", "kind": "mixed", "c": Vector2(-178, 50), "half": Vector2(40, 165), "ang": 0.0},
		{"name": "Canal Row", "kind": "shops", "c": Vector2(-39, -119), "half": Vector2(7, 87), "ang": 0.0},
		{"name": "Lawless Plastics", "kind": "industrial", "c": Vector2(110, 168), "half": Vector2(105, 45), "ang": 0.0},
	]


# ------------------------------------------------------------------ geometry helpers (as layout.gd)

static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func poly_dist(p: Vector2, pts: PackedVector2Array) -> Vector2:
	## x = distance to the polyline, y = parametric position (segment index + t)
	var best := INF
	var best_u := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			best_u = i + t
	return Vector2(best, best_u)


static func _inside(p: Vector2, pts: PackedVector2Array) -> bool:
	var c := false
	var j := pts.size() - 1
	for i in pts.size():
		var a := pts[i]
		var b := pts[j]
		if (a.y > p.y) != (b.y > p.y) and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			c = not c
		j = i
	return c


func water_sd(p: Vector2) -> Vector2:
	## Signed distance to the nearest walled water polygon's edge (negative inside the water), and that polygon's index.
	## Far from every walled water body: (INF, -1).
	if not _wbox.has_point(p):
		return Vector2(INF, -1)
	var best := INF
	var bi := -1
	for k in water_polys.size():
		var wp: Dictionary = water_polys[k]
		if not (wp.bbox as Rect2).grow(APRON + 3.0).has_point(p):
			continue
		var pts: PackedVector2Array = wp.pts
		var d := INF
		var j := pts.size() - 1
		for i in pts.size():
			d = minf(d, seg_dist(p, pts[j], pts[i]))
			j = i
		if _inside(p, pts):
			d = -d
		if d < best:
			best = d
			bi = k
	return Vector2(best, bi)


func estero_d(p: Vector2) -> Vector2:
	## Distance from the estero's centre line, and its half width (INF when there is none near).
	for e in esteros:
		var d := seg_dist(p, e.a, e.b)
		if d < float(e.hw) + float(e.bank) + 2.0:
			return Vector2(d, float(e.hw))
	return Vector2(INF, 0.0)


# ------------------------------------------------------------------ heights

func land_height(x: float, z: float) -> float:
	## The open ground: a gentle swell, flattened to LAND_Y within 20 m of the canals so their walls meet it flush.
	var h := LAND_Y + _noise.get_noise_2d(x, z) * 0.28
	var sd := water_sd(Vector2(x, z)).x
	if sd < 22.0:
		h = lerpf(LAND_Y, h, clampf((sd - 12.0) / 10.0, 0.0, 1.0))
	return h


func terrain_height(x: float, z: float) -> float:
	## The heightfield (mesh and collision): the bed under walled water and under the first metres of its walk (the
	## wall and the walk slab cover the ramp back up), the estero's sloped channel, land elsewhere.
	var p := Vector2(x, z)
	var w := water_sd(p)
	if w.x < RAMP_SD:
		var wp: Dictionary = water_polys[int(w.y)]
		var bed := lerpf(float(wp.bed), float(wp.deep), clampf(-w.x / 10.0, 0.0, 1.0))
		if w.x < BED_SD:
			return bed
		return lerpf(bed, LAND_Y, (w.x - BED_SD) / (RAMP_SD - BED_SD))
	var h := land_height(x, z)
	var e := estero_d(p)
	if e.x < INF:
		var hw := e.y
		var bank := 4.0
		if e.x < hw:
			return lerpf(-1.6, WATER_Y - 0.25, pow(e.x / hw, 2.0))
		if e.x < hw + bank:
			return lerpf(WATER_Y - 0.25, h, smoothstep(0.0, 1.0, (e.x - hw) / bank))
	return h


func ground_height(x: float, z: float) -> float:
	## The walkable surface: road decks on bridges, the canal walk slab and wall tops, the bed in the water, the
	## terrain elsewhere (roads and sidewalks sit a few cm above it).
	var p := Vector2(x, z)
	for r in bridge_rects:
		if (r as Rect2).has_point(p):
			return LAND_Y + ROAD_TOP
	var w := water_sd(p)
	if w.x < INF:
		if w.x >= 0.0 and w.x < WALL_T:
			return LAND_Y + WALL_TOP
		if w.x >= WALL_T and w.x < APRON:
			return LAND_Y + APRON_TOP
	return terrain_height(x, z)


func is_water(x: float, z: float) -> bool:
	var ix := int((x + HALF) / GRID)
	var iz := int((z + HALF) / GRID)
	if ix < 0 or iz < 0 or ix >= _n or iz >= _n:
		return false
	return _water[iz * _n + ix] == 1


func water_height(x: float, z: float) -> float:
	return WATER_Y if is_water(x, z) else -INF


func in_play_area(p: Vector2) -> bool:
	return absf(p.x) < PLAY_HALF and absf(p.y) < PLAY_HALF


func coast_z(_x: float) -> float:
	## No sea here: far off the map so any coast logic stays out of the way.
	return 100000.0


# ------------------------------------------------------------------ masks

func _cell(ix: int, iz: int) -> Vector2:
	return Vector2(-HALF + (ix + 0.5) * GRID, -HALF + (iz + 0.5) * GRID)


func _rasterize() -> void:
	# Water: walled polygons by their edge, the estero by its channel height (sampled per cell, never per tile).
	for iz in _n:
		for ix in _n:
			var c := _cell(ix, iz)
			var w := water_sd(c)
			if w.x < 0.0:
				_water[iz * _n + ix] = 1
			elif w.x < APRON:
				_reserved[iz * _n + ix] = 4
			else:
				var e := estero_d(c)
				if e.x < e.y + 1.0 and terrain_height(c.x, c.y) < WATER_Y + 0.05:
					_water[iz * _n + ix] = 1
	# Road decks: dry walkable ground over the water.
	for r in bridge_rects:
		_fill_rect(r, 1, true)
	# Roads with their sidewalks (paved, walkable).
	for rd in roads:
		var hw := float(rd.w) * 0.5 + float(rd.sidewalk)
		_fill_rect(road_rect(rd, hw), 1, false)
	for p in parking:
		_fill_rect(p.rect, 1, false, true)
	# Walls: the cells on the wall line (gaps stay open), so bots path through the gate and the breaches.
	for w in walls:
		var a: Vector2 = w.a
		var b: Vector2 = w.b
		var len := a.distance_to(b)
		var dir := (b - a) / len
		var t := 0.0
		while t <= len:
			if wall_open_at(w, t) == "":
				var p := a + dir * t
				var ix := int((p.x + HALF) / GRID)
				var iz := int((p.y + HALF) / GRID)
				if ix >= 0 and iz >= 0 and ix < _n and iz < _n and _reserved[iz * _n + ix] == 0:
					_reserved[iz * _n + ix] = 5
			t += 0.5


func road_rect(rd: Dictionary, hw: float) -> Rect2:
	## The rectangle a road covers at half width hw (road + sidewalk, or just the carriageway).
	if int(rd.axis) == 0:
		return Rect2(Vector2(float(rd.lo), float(rd.c) - hw), Vector2(float(rd.hi) - float(rd.lo), hw * 2.0))
	return Rect2(Vector2(float(rd.c) - hw, float(rd.lo)), Vector2(hw * 2.0, float(rd.hi) - float(rd.lo)))


func wall_open_at(w: Dictionary, t: float) -> String:
	## "" where the wall stands at distance t from its start; else the gap's kind (gate, street, breach).
	var a: Vector2 = w.a
	var b: Vector2 = w.b
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var coord := (a.x if along_x else a.y) + t * signf((b.x - a.x) if along_x else (b.y - a.y))
	for g in w.get("gaps", []):
		if coord >= minf(float(g[0]), float(g[1])) and coord <= maxf(float(g[0]), float(g[1])):
			return str(g[2]) if g.size() > 2 else "gap"
	return ""


func wall_coord(w: Dictionary, t: float) -> float:
	var a: Vector2 = w.a
	var b: Vector2 = w.b
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	return (a.x if along_x else a.y) + t * signf((b.x - a.x) if along_x else (b.y - a.y))


func _fill_rect(r: Rect2, value: int, clear_water: bool, only_free: bool = false) -> void:
	for iz in range(maxi(int((r.position.y + HALF) / GRID), 0), mini(int((r.end.y + HALF) / GRID) + 1, _n)):
		for ix in range(maxi(int((r.position.x + HALF) / GRID), 0), mini(int((r.end.x + HALF) / GRID) + 1, _n)):
			if not r.has_point(_cell(ix, iz)):
				continue
			var i := iz * _n + ix
			if clear_water:
				_water[i] = 0
			elif _water[i] == 1:
				continue
			if only_free and _reserved[i] != 0:
				continue
			if _reserved[i] == 0 or _reserved[i] == 4 or value == 1:
				_reserved[i] = value


func reserve_rect(center: Vector2, half: Vector2, ang: float, value: int, margin: float = 0.0, only_free: bool = false) -> void:
	var r := maxf(half.x, half.y) * 1.5 + margin
	var c := cos(-ang)
	var s := sin(-ang)
	for iz in range(maxi(int((center.y - r + HALF) / GRID), 0), mini(int((center.y + r + HALF) / GRID) + 1, _n)):
		for ix in range(maxi(int((center.x - r + HALF) / GRID), 0), mini(int((center.x + r + HALF) / GRID) + 1, _n)):
			var p := _cell(ix, iz) - center
			var lp := Vector2(p.x * c - p.y * s, p.x * s + p.y * c)
			if absf(lp.x) <= half.x + margin and absf(lp.y) <= half.y + margin:
				if not only_free or _reserved[iz * _n + ix] == 0:
					_reserved[iz * _n + ix] = value


func rect_free(center: Vector2, half: Vector2, ang: float, allow_water: bool = false, margin: float = 0.3) -> bool:
	## True when the rotated rectangle covers no reserved cell (and no water unless allowed).
	var xa := Vector2(cos(ang), sin(ang))
	var za := Vector2(-sin(ang), cos(ang))
	var steps_u := maxi(int((half.x + margin) * 2.0 / GRID * 1.4), 1)
	var steps_v := maxi(int((half.y + margin) * 2.0 / GRID * 1.4), 1)
	for i in steps_u + 1:
		for j in steps_v + 1:
			var lu := -half.x - margin + (half.x + margin) * 2.0 * i / steps_u
			var lv := -half.y - margin + (half.y + margin) * 2.0 * j / steps_v
			var p := center + xa * lu + za * lv
			var ix := int((p.x + HALF) / GRID)
			var iz := int((p.y + HALF) / GRID)
			if ix < 0 or iz < 0 or ix >= _n or iz >= _n:
				return false
			if _reserved[iz * _n + ix] != 0:
				return false
			if not allow_water and _water[iz * _n + ix] == 1:
				return false
	return true


func reserved_at(x: float, z: float) -> int:
	var ix := int((x + HALF) / GRID)
	var iz := int((z + HALF) / GRID)
	if ix < 0 or iz < 0 or ix >= _n or iz >= _n:
		return 255
	return _reserved[iz * _n + ix]


# ------------------------------------------------------------------ lots

const FRONTS := {"N": Vector2(0, -1), "S": Vector2(0, 1), "E": Vector2(1, 0), "W": Vector2(-1, 0)}
const YAWS := {"N": 0, "W": 90, "S": 180, "E": 270}
const BIG_KINDS := ["office_tower", "guard_booth", "apartment", "gas_station", "guardhouse", "clubhouse", "pool", "court", "playground",
	"water_tower", "chapel", "store", "strip_shops", "factory", "tank", "warehouse", "container_yard"]


func _lot(kind: String, c: Vector2, world_size: Vector2, front: String, floors: int, name: String, district: String) -> Dictionary:
	var ns := front == "N" or front == "S"
	var half := Vector2(world_size.x, world_size.y) * 0.5 if ns else Vector2(world_size.y, world_size.x) * 0.5
	var lot := {"id": lots.size(), "kind": kind, "name": name, "district": district, "center": c, "half": half,
		"yaw": int(YAWS[front]), "front": FRONTS[front], "front_side": front, "floors": floors, "style": rng.randi_range(0, 7),
		"seed": rng.randi(), "rect": Rect2(c - world_size * 0.5, world_size)}
	var y0 := -INF
	for i in 3:
		for j in 3:
			var q := c + Vector2((i - 1) * world_size.x * 0.5, (j - 1) * world_size.y * 0.5)
			y0 = maxf(y0, land_height(q.x, q.y))
	lot.plinth_y = snappedf(y0 + 0.15, 0.01)
	return lot


func _make_lots() -> void:
	## Big buildings first (they win where a house row runs into one), then the house rows in plan order.
	var big: Array = []
	for b in plan.get("lots", []):
		var sz := _v2(b.size)
		var lot := _lot(str(b.kind), _v2(b.c), sz, str(b.front), int(b.get("floors", 1)), str(b.get("name", b.kind)), str(b.get("district", "")))
		lot.big = true
		lot.envelope = {"center": lot.center, "half": lot.half}
		lots.append(lot)
		big.append(lot.rect)
		sites.append({"type": lot.kind, "pos": lot.center, "ang": deg_to_rad(float(lot.yaw)), "name": lot.name})
	for row in plan.get("rows", []):
		var kind := str(row.get("kind", "house"))
		var x0 := float(row.x[0])
		var x1 := float(row.x[1])
		var z0 := float(row.z[0])
		var z1 := float(row.z[1])
		var front := str(row.front)
		var along_z := front == "E" or front == "W"
		var span := (z1 - z0) if along_z else (x1 - x0)
		var lot_w := float(row.get("lot_w", 12.0))
		var group := int(row.get("group", 0))
		var gap := float(row.get("gap", 0.0))
		var n := maxi(int(round(span / lot_w)), 1)
		var fl: Array = row.get("floors", [2, 2])
		if group > 0:
			n = int((span + gap) / (lot_w * group + gap)) * group
			var used := n * lot_w + (n / group - 1) * gap
			var off := (span - used) * 0.5
			lot_w = lot_w
			for i in n:
				var s0 := off + i * lot_w + (i / group) * gap
				_row_lot(kind, row, along_z, x0, x1, z0, z1, s0, lot_w, front, fl, big)
		else:
			var w := span / n
			for i in n:
				_row_lot(kind, row, along_z, x0, x1, z0, z1, i * w, w, front, fl, big)
	var counts := {}
	for l in lots:
		counts[l.kind] = int(counts.get(l.kind, 0)) + 1
	stats_lots = counts
	# Reserve: big buildings (2) on their footprints, houses (3) on their envelopes.
	for l in lots:
		var env: Dictionary = l.envelope
		reserve_rect(env.center, _world_half(env.half, int(l.yaw)), 0.0, 2 if l.big else 3)


var stats_lots := {}


static func _world_half(local_half: Vector2, yaw: int) -> Vector2:
	return local_half if yaw == 0 or yaw == 180 else Vector2(local_half.y, local_half.x)


func _row_lot(kind: String, row: Dictionary, along_z: bool, x0: float, x1: float, z0: float, z1: float, s0: float, w: float, front: String, fl: Array, big: Array) -> void:
	var c: Vector2
	var size: Vector2
	if along_z:
		c = Vector2((x0 + x1) * 0.5, z0 + s0 + w * 0.5)
		size = Vector2(x1 - x0, w)
	else:
		c = Vector2(x0 + s0 + w * 0.5, (z0 + z1) * 0.5)
		size = Vector2(w, z1 - z0)
	var r := Rect2(c - size * 0.5, size)
	for b in big:
		if (b as Rect2).grow(1.0).intersects(r):
			return
	var floors := rng.randi_range(int(fl[0]), int(fl[1]))
	var lot := _lot(kind, c, size, front, floors, "%s %d" % [str(row.get("district", "")), lots.size()], str(row.get("district", "")))
	lot.big = false
	# The buildable envelope: front yard (gate, carport) and a strip at the back and sides stay open ground.
	var hx: float = lot.half.x
	var hz: float = lot.half.y
	var front_set := 4.0 if kind == "house" else 1.0
	var back_set := 2.0 if kind == "house" else 1.5
	var side_set := 1.0 if kind == "house" else 0.0
	var env_half := Vector2(hx - side_set, hz - (front_set + back_set) * 0.5)
	# Local -z is the front: the envelope's centre moves back by (front_set - back_set) / 2.
	var shift := (front_set - back_set) * 0.5
	var fv: Vector2 = lot.front
	lot.envelope = {"center": c - fv * shift, "half": env_half}
	lots.append(lot)


# ------------------------------------------------------------------ spawns

func pick_spawns() -> void:
	## Ten-plus clear standing spots per team, 3.2 m apart, around the team's spawn centre: dry, not on a wall, a
	## building or a reserved lot, clear of the street furniture the builder recorded in `obstacles`.
	spawns = [[], []]
	for team in spawn_centres.size():
		var c: Vector2 = spawn_centres[team]
		var cand: Array = []
		for i in range(-7, 8):
			for j in range(-7, 8):
				var p := c + Vector2(i, j) * 3.2
				if p.distance_to(c) > spawn_zone_r:
					continue
				if not _spot_ok(p):
					continue
				cand.append([p.distance_squared_to(c) + (i + 7) * 1e-4 + (j + 7) * 1e-6, p])
		cand.sort_custom(func(a, b): return a[0] < b[0])
		var out: Array = []
		for e in cand.slice(0, 14):
			var p2: Vector2 = e[1]
			out.append(Vector3(p2.x, surface_y(p2), p2.y))
		spawns[team] = out
		var to := dm_centre - c
		spawn_yaw[team] = atan2(-to.x, -to.y)


func _spot_ok(p: Vector2) -> bool:
	for dx in [-1.0, 0.0, 1.0]:
		for dz in [-1.0, 0.0, 1.0]:
			var q := p + Vector2(dx, dz) * 0.9
			if is_water(q.x, q.y):
				return false
			var r := reserved_at(q.x, q.y)
			if r == 2 or r == 3 or r == 5 or r == 255:
				return false
	for o in obstacles:
		if p.distance_to(o[0]) < float(o[1]) + 1.0:
			return false
	return true


func surface_y(p: Vector2) -> float:
	## Height of the paved or bare surface a character stands on at p (roads, lots and sidewalks sit above the ground).
	var g := ground_height(p.x, p.y)
	for pk in parking:
		if (pk.rect as Rect2).has_point(p):
			return g + ROAD_TOP + 0.01
	for rd in roads:
		if road_rect(rd, float(rd.w) * 0.5).has_point(p):
			return g + ROAD_TOP
		if float(rd.sidewalk) > 0.0 and road_rect(rd, float(rd.w) * 0.5 + float(rd.sidewalk)).has_point(p):
			return g + WALK_TOP
	return g


func in_spawn_zone(p: Vector2, margin: float = 0.0) -> bool:
	for c in spawn_centres:
		if p.distance_to(c) < spawn_zone_r + margin:
			return true
	return false
