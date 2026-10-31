extends RefCounted
## (r15) Malasugue Mall, the second Deathmatch map: a five-storey shopping mall on its own block.
##
## Plan (x east, z south, metres; floor tops at y = level * FH):
##   outer walls at x = +-MX, z = +-MZ (144 x 92 m), a paved drop-off plaza around it out to the site fence.
##   West and east ends: anchor stores (x beyond +-ANCHOR_X), full depth, one tenant per level; on Level 1 an entrance
##   hall cuts through each (the West and East entrances).
##   North and south bands (|z| > BAND_Z): shop units facing the concourses, the four fire-stair cores and two
##   restroom blocks; on Level 1 the middle unit of each band is the North / South (main) entrance.
##   Central band: three courts open through Levels 2-5 (West Court, rectangular; the Grand Atrium, an ellipse; the
##   East Court, round) and two island blocks of shops between them. The West Court and the Grand Atrium each carry an
##   escalator bank: a 4-lane criss-cross well (up and down, every level) between landing "tongues" that reach into
##   the court from both sides.
## Everything a system outside the map asks of a layout (ground_height, is_water, in_play_area, the DM spawns...) is
## here, plus what the mall's own builder and bots need: floor_at / void_at per level, the escalator belts the
## movement code rides (belt_at), the stair flights, and per-level walk grids the builder fills (NavLevels).

const MAP_ID := "malasugue_mall"
const SHOPS_PATH := "res://data/maps/malasugue_shops.json"

const FH := 5.0             # floor to floor
const LEVELS := 5
const SLAB := 0.32          # structural slab under each floor top
const CEIL := 4.2           # suspended ceiling height above each floor
const MX := 72.0            # outer wall faces
const MZ := 46.0
const WALL_T := 0.5
const ANCHOR_X := 57.0      # anchors beyond |x| > ANCHOR_X
const BAND_Z := 35.0        # north / south shop bands beyond |z| > BAND_Z
const SITE_X := 88.0        # site fence
const SITE_Z := 64.0
const ESC_RUN := 8.66       # escalator incline: 5 m rise at 30 degrees
const ESC_FLAT := 1.25      # flat run at each end (comb plate and the first steps)
const ESC_LANE := 1.8       # lane pitch across the well
const ESC_SPEED := 0.75     # m/s along the incline
const STEP_RISE := 0.1667

# Courts (open through Levels 2-5): West Court (rectangle, chamfered), Grand Atrium (ellipse), East Court (circle).
const WEST_COURT := Rect2(-53.0, -13.0, 18.0, 26.0)
const WEST_CHAMFER := 3.0
const GRAND_C := Vector2(0.0, 0.0)
const GRAND_R := Vector2(17.0, 15.0)
const EAST_C := Vector2(46.0, 0.0)
const EAST_R := 9.0
# Island blocks of shops between the courts.
const ISLANDS := [Rect2(-31.0, -20.0, 9.0, 40.0), Rect2(22.0, -20.0, 9.0, 40.0)]
# Escalator banks: centre x of the well (z centred on 0), lanes across z.
const BANKS := [{"name": "West Court", "cx": -44.0}, {"name": "Grand Atrium", "cx": 0.0}]
const WELL_HZ := 3.7        # half width of a well across z
# Fire-stair cores and restrooms in the bands.
const CORES := [Rect2(-57.0, -45.5, 7.0, 10.5), Rect2(50.0, -45.5, 7.0, 10.5), Rect2(-57.0, 35.0, 7.0, 10.5), Rect2(50.0, 35.0, 7.0, 10.5)]
const RESTROOMS := [Rect2(-50.0, -45.5, 6.0, 10.5), Rect2(44.0, 35.0, 6.0, 10.5)]
# Unit splits along x in the bands (between the cores / restrooms); the middle one is an entrance on Level 1.
const NORTH_CUTS := [-44.0, -31.0, -19.0, -6.0, 6.0, 19.0, 31.0, 44.0, 50.0]
const SOUTH_CUTS := [-50.0, -44.0, -31.0, -19.0, -6.0, 6.0, 19.0, 31.0, 44.0]
const ENTRANCE_HZ := 4.0    # half width of the West / East entrance halls through the anchors (Level 1)
## (r16) Alex Jackie, the department store, fills the east anchor on Levels 1-3; inside it two escalators that stopped
## when the power went (stairs now) join its floors: from Level t+1 at z0 rising along dir (z) to Level t+2, at x.
const DEPT_ESC := [{"t": 0, "x": 66.6, "z0": 15.0, "dir": 1.0}, {"t": 1, "x": 66.6, "z0": -15.0, "dir": -1.0}]
const DEPT_ESC_HW := 0.8    # half width of an escalator's opening in the floor above
## (r16) Level 3's public restrooms: the north band unit beside the north-west restroom block.
const BIG_RESTROOM := {"level": 2, "x0": -44.0, "x1": -31.0}
const LIFT_CENTRES := [9.0,16.0]


static func lift_holes() -> Array:
	return [Rect2(7.25,-44.95,3.5,4.65),Rect2(14.25,-44.95,3.5,4.65)]


static func floor_inlays() -> Array:
	var out := []
	for side in [-1,1]:
		var z: float = side*28.5
		out.append([Rect2(-55,z-1.4,110,2.8),"mall_geometric"])
		for edge in [-1,1]:
			out.append([Rect2(-55,z+edge*1.65-.13,110,.26),"mall_green_stone"])
	for x in [-53.5,53.5]:
		for side in [-1,1]:
			out.append([Rect2(x-2,side*32-1.4,4,2.8),"mall_green_stone"])
	return out


static func floor_repairs(level: int) -> Array:
	var out := []
	var rr := RandomNumberGenerator.new()
	rr.seed = 4019+level
	for i in 3:
		var p := Vector2([-18.5,34.0,-48.0][i]+level*.7,[-23.0,24.0,18.0][i])
		var w := rr.randf_range(1.6,3.4)
		var h := rr.randf_range(1.1,2.4)
		for row in 3:
			var inset := rr.randf_range(0.0,.25)*w
			out.append(Rect2(p.x-w*.5+inset,p.y-h*.5+row*h/3.0,w-inset-rr.randf_range(0.0,.2)*w,h/3.0))
	return out

var MAP_SCALE := 1.0
var HALF := 120.0
var PLAY_HALF := 80.0
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
var edge := 86.0
var obstacles: Array = []
var bridge_rects: Array = []
var lamp_spots: Array = []
var dump_c := Vector2(1e6, 1e6)
var dump_r := 0.0
var zone_jitter := 18.0      # the first DM circle's centre stays near the Grand Atrium
## Indoor lighting profile read by Lighting (src/world/lighting.gd): the mall is lit by its own fittings, day or night.
## (r16) After the outbreak most of them are out: a faint cold fill stands for the emergency circuits and the daylight
## that leaks in, the rest is pools under the downlights that still work, flickering ones, emergency lamps and the
## skylights; dust in the air (volumetric fog) and a dark depth haze.
var indoor_light := {"fill": Color(0.55, 0.68, 0.78), "fill_energy": 0.13, "ambient": Color(0.48, 0.59, 0.67), "ambient_energy": 0.15,
	"fill_dir": Vector3(0.18, 1.0, 0.32), "fog": 0.0, "vol_fog": 0.0,
	"saturation": 0.94, "contrast": 1.04, "ssao": 1.45, "exposure": 1.22, "horror_grade": true,
	"sky_dim": 0.24, "sky_cloud": 0.92, "sky_glow": Color(0.14, 0.045, 0.025), "buzz": true}
var _n: int
var _water: PackedByteArray
var _reserved: PackedByteArray

var shops_catalog: Array = []
var units: Array = []        # [{level, rect: Rect2, face: Vector2 (outward, toward the walk), shop: Dictionary, kind, anchor?}]
var escalators: Array = []   # [{bank, t, lane, up, a: Vector3 (bottom of incline), b: Vector3 (top), dir: Vector3 (unit, a->b), z, w}]
var flights: Array = []      # [{core, level, foot: Vector3, top: Vector3, w, along: Vector3}] one per half storey
var entrances: Array = []    # [{name, c: Vector2, door_x | door_z, out: Vector2}]
var spawns: Array = [[], []]
var spawn_yaw: Array = [0.0, 0.0]
var spawns3: Array = [[], [], []]
var spawn_yaw3: Array = [0.0, 0.0, 0.0]
var dm_centre := Vector2.ZERO
## Bot walk grids (NavLevels): one per level, 1 m cells over the site, 1 = open. The builder closes cells under every
## wall, counter and fitting it draws (block_rect / block_seg); links are the escalators and stairs.
const NAV_CELL := 1.0
var nav_nx := 0
var nav_nz := 0
var nav_x0 := 0.0
var nav_z0 := 0.0
var nav_open: Array = []     # [level] -> PackedByteArray
var nav_links: Array = []    # [{a: Vector3, b: Vector3, via: Array[Vector3], cost, oneway}]


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	_n = int(HALF * 2.0 / GRID)
	_water = PackedByteArray()
	_water.resize(_n * _n)
	_reserved = PackedByteArray()
	_reserved.resize(_n * _n)
	var data = JSON.parse_string(FileAccess.get_file_as_string(SHOPS_PATH))
	if data is Dictionary:
		shops_catalog = data.get("shops", [])
	_make_units()
	_make_escalators()
	_make_flights()
	_make_entrances()
	_make_spawns()
	_init_nav()
	landmarks = [{"name": "Grand Atrium", "pos": GRAND_C}, {"name": "West Court", "pos": WEST_COURT.get_center()},
		{"name": "East Court", "pos": EAST_C}, {"name": "Cineplex (L5)", "pos": Vector2(64.5, 0)}]


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
	return absf(p.x) < SITE_X - 2.0 and absf(p.y) < SITE_Z - 2.0


func coast_z(_x: float) -> float:
	return 1e5


func reserved_at(_x: float, _z: float) -> int:
	return 0


func surface_y(_p: Vector2) -> float:
	return LAND_Y


func _cell(ix: int, iz: int) -> Vector2:
	return Vector2(-HALF + (ix + 0.5) * GRID, -HALF + (iz + 0.5) * GRID)


func level_y(level: int) -> float:
	return level * FH


func level_of(y: float) -> int:
	return clampi(int(floor((y + 1.2) / FH)), 0, LEVELS - 1)


# ------------------------------------------------------------------ plan queries

static func in_ellipse(p: Vector2, c: Vector2, r: Vector2) -> bool:
	var d := (p - c) / r
	return d.length_squared() <= 1.0


func in_west_court(p: Vector2) -> bool:
	var r := WEST_COURT
	if not r.has_point(p):
		return false
	# chamfered corners
	var lx := minf(p.x - r.position.x, r.end.x - p.x)
	var lz := minf(p.y - r.position.y, r.end.y - p.y)
	return lx + lz >= WEST_CHAMFER


func in_court(p: Vector2) -> bool:
	return in_west_court(p) or in_ellipse(p, GRAND_C, GRAND_R) or p.distance_to(EAST_C) <= EAST_R


func in_tongue(p: Vector2) -> bool:
	## The landing strips that reach into a court on either side of an escalator well (floor on every level).
	if absf(p.y) > WELL_HZ:
		return false
	for bk in BANKS:
		var x0 := float(bk.cx) - ESC_RUN * 0.5
		var x1 := float(bk.cx) + ESC_RUN * 0.5
		if (p.x <= x0 or p.x >= x1) and absf(p.x - float(bk.cx)) < 20.0:
			return true
	return false


func in_well(p: Vector2) -> bool:
	if absf(p.y) > WELL_HZ:
		return false
	for bk in BANKS:
		if absf(p.x - float(bk.cx)) < ESC_RUN * 0.5:
			return true
	return false


func void_at(level: int, p: Vector2) -> bool:
	## Open to the level below (the courts minus their landing tongues, and the escalator wells), Levels 2-5.
	if level <= 0:
		return false
	for hole in lift_holes():
		if (hole as Rect2).has_point(p):
			return true
	if in_well(p):
		return true
	return in_court(p) and not in_tongue(p)


func inside(p: Vector2, margin: float = 0.0) -> bool:
	return absf(p.x) < MX - margin and absf(p.y) < MZ - margin


func floor_at(level: int, p: Vector2) -> bool:
	if level == 0:
		return absf(p.x) < SITE_X and absf(p.y) < SITE_Z
	return inside(p) and not void_at(level, p)


func dept_well(level: int) -> Rect2:
	## (r16) The opening in Level level's floor over a department-store escalator (no size: none on that level).
	for e in DEPT_ESC:
		if int(e.t) + 1 == level:
			var z0 := float(e.z0) + float(e.dir) * 3.3
			var z1 := float(e.z0) + float(e.dir) * ESC_RUN
			return Rect2(float(e.x) - DEPT_ESC_HW, minf(z0, z1), DEPT_ESC_HW * 2.0, absf(z1 - z0))
	return Rect2()


func core_at(p: Vector2) -> int:
	for i in CORES.size():
		if (CORES[i] as Rect2).has_point(p):
			return i
	return -1


# ------------------------------------------------------------------ shops

func _catalog_by(kind_or_name: String) -> Dictionary:
	for s in shops_catalog:
		if str(s.name) == kind_or_name:
			return s
	return {}


func _make_units() -> void:
	## Every shop unit on every level and which shop takes it. Anchors and the big rooms are fixed by name; the rest
	## of each level is filled in catalogue order from that level's shops (a few stay boarded up: Coming Soon).
	units.clear()
	var pools := []
	for lv in LEVELS:
		var pool := []
		for s in shops_catalog:
			if int(s.floor) == lv:
				pool.append(s)
		pools.append(pool)
	var closed := _catalog_by("Coming Soon")
	var anchors_w := ["Malasugue Supermart", "Airah's Collections", "Bayanihan Books", "Kidz Kingdom", "Quake Team"]
	var anchors_e := ["Alex Jackie", "Alex Jackie", "Alex Jackie", "Takbo Fitness", "Malasugue Cineplex"]
	var islands := [["Azrin & Azrael's", ""], ["", ""], ["", ""], ["", "Toys by EZ-RR"], ["Buchokan", ""]]
	var used := {}
	for n in anchors_w + anchors_e + ["Azrin & Azrael's", "Toys by EZ-RR", "Buchokan"]:
		used[n] = true
	var pick_rng := RandomNumberGenerator.new()
	pick_rng.seed = 1515
	for lv in LEVELS:
		var pool: Array = (pools[lv] as Array).filter(func(s): return not used.has(str(s.name)))
		var take := func() -> Dictionary:
			if pool.is_empty() or pick_rng.randf() < 0.03:
				return closed
			return pool.pop_front()
		# Anchors (the entrance halls cut them on Level 1).
		for side in [-1, 1]:
			var nm: String = (anchors_w if side < 0 else anchors_e)[lv]
			var x0 := -MX + WALL_T if side < 0 else ANCHOR_X
			var r := Rect2(x0, -MZ + WALL_T, MX - WALL_T - ANCHOR_X, (MZ - WALL_T) * 2.0)
			var face := Vector2(float(-side), 0.0)
			if lv == 0:
				for half in [-1, 1]:
					var rz := Rect2(r.position.x, -MZ + WALL_T if half < 0 else ENTRANCE_HZ, r.size.x, MZ - WALL_T - ENTRANCE_HZ)
					var shop := _catalog_by(nm) if half < 0 or nm == "Alex Jackie" else (_catalog_by("Botika Malasugue") if side < 0 else _catalog_by(nm))
					used[str(shop.get("name", ""))] = true
					units.append({"level": lv, "rect": rz, "face": face, "shop": shop, "kind": str(shop.get("kind", "closed")), "anchor": true})
			else:
				var shop2 := _catalog_by(nm)
				units.append({"level": lv, "rect": r, "face": face, "shop": shop2, "kind": str(shop2.get("kind", "closed")), "anchor": true})
		# Islands: one flagship takes the whole block, otherwise three units (north, south, and one facing the Grand
		# Atrium between them).
		for k in 2:
			var ir: Rect2 = ISLANDS[k]
			var whole: String = islands[lv][k]
			if whole != "":
				var shop3 := _catalog_by(whole)
				units.append({"level": lv, "rect": ir, "face": Vector2(0, 1), "shop": shop3, "kind": str(shop3.get("kind", "closed")), "island": true, "whole": true})
				continue
			var parts := [[Rect2(ir.position.x, ir.position.y, ir.size.x, 13.0), Vector2(0, -1)],
				[Rect2(ir.position.x, ir.end.y - 13.0, ir.size.x, 13.0), Vector2(0, 1)],
				[Rect2(ir.position.x, ir.position.y + 13.0, ir.size.x, ir.size.y - 26.0), Vector2(-signf(ir.get_center().x), 0)]]
			for pr in parts:
				var s4: Dictionary = take.call()
				units.append({"level": lv, "rect": pr[0], "face": pr[1], "shop": s4, "kind": str(s4.get("kind", "closed")), "island": true})
		# Bands.
		for side in [-1, 1]:
			var cuts: Array = NORTH_CUTS if side < 0 else SOUTH_CUTS
			for i in cuts.size() - 1:
				var xa := float(cuts[i])
				var xb := float(cuts[i + 1])
				var r2 := Rect2(xa, -MZ + WALL_T if side < 0 else BAND_Z, xb - xa, MZ - WALL_T - BAND_Z)
				var mid := absf((xa + xb) * 0.5) < 0.5
				if mid and lv == 0:
					continue   # the North / South entrance
				if lv == int(BIG_RESTROOM.level) and side < 0 and absf(xa - float(BIG_RESTROOM.x0)) < 0.1:
					units.append({"level": lv, "rect": r2, "face": Vector2(0, float(-side)), "shop": {"name": "Restrooms", "kind": "restroom", "tile": -1},
						"kind": "restroom"})
					continue
				var s5: Dictionary = take.call()
				if side < 0 and xa == 6.0:
					units.append({"level":lv,"rect":r2,"face":Vector2(0,1),"shop":{"name":"Elevators","kind":"lifts"},"kind":"lifts"})
					continue
				if mid and lv == 4:
					s5 = {"name": "Food Hall", "kind": "food_hall", "line": "", "tile": -1}
				units.append({"level": lv, "rect": r2, "face": Vector2(0, float(-side)), "shop": s5, "kind": str(s5.get("kind", "closed"))})


# ------------------------------------------------------------------ escalators and stairs

func _make_escalators() -> void:
	## Two criss-cross banks. In each well the lanes across z are: 0 up (rises toward +x), 1 up (rises toward -x),
	## 2 down (rises toward -x), 3 down (rises toward +x). Transition t (Level t+1 -> t+2) rises toward +x when t is
	## even, so going up you step off one escalator and turn round onto the next in the lane beside it; going down the
	## same on the other side of the well.
	escalators.clear()
	for bk in BANKS:
		var cx := float(bk.cx)
		var x0 := cx - ESC_RUN * 0.5
		var x1 := cx + ESC_RUN * 0.5
		for t in LEVELS - 1:
			var plus := t % 2 == 0
			for up in [true, false]:
				var lane := (0 if plus else 1) if up else (3 if plus else 2)
				var z := (-1.5 + lane) * ESC_LANE
				var a := Vector3(x0 if plus else x1, t * FH, z)
				var b := Vector3(x1 if plus else x0, (t + 1) * FH, z)
				escalators.append({"bank": str(bk.name), "t": t, "lane": lane, "up": up, "a": a, "b": b, "dir": (b - a).normalized(), "z": z, "w": 1.0})


func belt_at(p: Vector3) -> Vector3:
	## The moving steps under a body standing at p (feet): their velocity, or ZERO off every escalator. Pure geometry,
	## so the server, the shooter's own prediction and every bot agree.
	if absf(p.z) > WELL_HZ + 0.5:
		return Vector3.ZERO
	for e in escalators:
		if absf(p.z - float(e.z)) > 0.55:
			continue
		var a: Vector3 = e.a
		var b: Vector3 = e.b
		var sx := signf(b.x - a.x)
		var u := (p.x - a.x) * sx   # along the run from the bottom of the incline
		if u < -ESC_FLAT or u > ESC_RUN + ESC_FLAT:
			continue
		var y_belt := a.y + clampf(u / ESC_RUN, 0.0, 1.0) * FH
		if absf(p.y - y_belt) > 0.6:
			continue
		var d: Vector3 = e.dir if u > 0.05 and u < ESC_RUN - 0.05 else Vector3(sx, 0.0, 0.0)
		if not bool(e.up):
			d = -d
		return d * ESC_SPEED
	return Vector3.ZERO


func _make_flights() -> void:
	## Each fire-stair core: a switchback, two flights per storey side by side along z, landings at both ends. The
	## door from the concourse opens on the core's inner side.
	flights.clear()
	for ci in CORES.size():
		var r: Rect2 = CORES[ci]
		var inner_z := r.end.y if r.position.y < 0.0 else r.position.y   # the side toward the concourse
		var outer_z := r.position.y if r.position.y < 0.0 else r.end.y
		var inward := signf(inner_z - outer_z)        # from the back wall toward the concourse
		var cx := r.get_center().x
		var run := 14.0 * 0.28
		var land := 1.5
		# Flights run along z between a landing at the back (by the outer wall) and one toward the door.
		var z_back := outer_z + inward * (WALL_T * 0.5 + 0.15 + land)
		var z_front := z_back + inward * run
		for lv in LEVELS - 1:
			var y0 := lv * FH
			# First flight up from the front landing toward the back, on the -x side; the second back toward the
			# front on the +x side.
			var xa := cx - 0.85
			var xb := cx + 0.85
			flights.append({"core": ci, "level": lv, "half": 0, "foot": Vector3(xa, y0, z_front), "top": Vector3(xa, y0 + FH * 0.5, z_back), "w": 1.5})
			flights.append({"core": ci, "level": lv, "half": 1, "foot": Vector3(xb, y0 + FH * 0.5, z_back), "top": Vector3(xb, y0 + FH, z_front), "w": 1.5})


# ------------------------------------------------------------------ entrances and the Deathmatch spawns

func _make_entrances() -> void:
	entrances = [
		{"name": "West Entrance", "c": Vector2(-64.5, 0.0), "out": Vector2(-1, 0), "hall": Rect2(-MX, -ENTRANCE_HZ, MX - ANCHOR_X, ENTRANCE_HZ * 2.0)},
		{"name": "East Entrance", "c": Vector2(64.5, 0.0), "out": Vector2(1, 0), "hall": Rect2(ANCHOR_X, -ENTRANCE_HZ, MX - ANCHOR_X, ENTRANCE_HZ * 2.0)},
		{"name": "North Entrance", "c": Vector2(0.0, -40.5), "out": Vector2(0, -1), "hall": Rect2(-6.0, -MZ, 12.0, MZ - BAND_Z)},
		{"name": "South Entrance", "c": Vector2(0.0, 40.5), "out": Vector2(0, 1), "hall": Rect2(-6.0, BAND_Z, 12.0, MZ - BAND_Z)},
	]


func _make_spawns() -> void:
	## Two teams (West Team, East Team): the West and East entrance halls. Three (North, East, South Team): the North,
	## East and South entrances. Points 1.6 m apart inside each hall, facing into the mall.
	var sets := {0: entrances[0], 1: entrances[1], 2: entrances[2], 3: entrances[3]}
	var pts := {}
	for k in sets:
		var e: Dictionary = sets[k]
		var hall: Rect2 = e.hall
		var out := []
		var c := hall.get_center()
		var cand := []
		for i in range(-6, 7):
			for j in range(-6, 7):
				var p := c + Vector2(i, j) * 1.6
				if hall.grow(-0.9).has_point(p):
					cand.append([p.distance_squared_to(c) + i * 1e-3 + j * 1e-5, p])
		cand.sort_custom(func(a, b): return a[0] < b[0])
		for q in cand.slice(0, 14):
			out.append(Vector3(q[1].x, 0.02, q[1].y))
		pts[k] = out
	spawns = [pts[0], pts[1]]
	spawn_yaw = [atan2(-1.0, 0.0), atan2(1.0, 0.0)]   # yaw: facing -z is 0; West faces +x (in), East faces -x
	spawn_yaw[0] = _yaw_toward(entrances[0].c, Vector2.ZERO)
	spawn_yaw[1] = _yaw_toward(entrances[1].c, Vector2.ZERO)
	spawns3 = [pts[2], pts[1], pts[3]]
	spawn_yaw3 = [_yaw_toward(entrances[2].c, Vector2.ZERO), spawn_yaw[1], _yaw_toward(entrances[3].c, Vector2.ZERO)]
	dm_centre = Vector2.ZERO


static func _yaw_toward(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(-d.x, -d.y)


func pick_spawns() -> void:
	pass   # fixed in _make_spawns (the halls are the same every match)


## (r17) Deathmatch teams start on different floors: Level 1, Level 3 and Level 5, dealt to the teams at random each
## match (two teams get two of the three). Each of those floors has its own gathering spot on a concourse in a
## different part of the mall (Level 1 north-west, Level 3 east, Level 5 south), away from the open courts, so no team
## starts in sight of another's balcony.
const FLOOR_SPAWN_LEVELS := [0, 2, 4]
const FLOOR_SPAWN_SPOTS := [Vector2(-40.0, -27.0), Vector2(42.0, -26.0), Vector2(0.0, 27.0)]


func dm_floor_spawns(seed_value: int, n_teams: int) -> Dictionary:
	## {team: {pts: Array[Vector3], anchor, yaw, level}}: 14 points 1.6 m apart on open concourse floor round the
	## floor's spot, facing the middle of the mall.
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 13 + 5
	var order := [0, 1, 2]
	for i in range(order.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var out := {}
	for t in mini(n_teams, order.size()):
		var k: int = order[t]
		var lv: int = FLOOR_SPAWN_LEVELS[k]
		var spot: Vector2 = FLOOR_SPAWN_SPOTS[k]
		var cand := []
		for i in range(-5, 6):
			for j in range(-5, 6):
				var p := spot + Vector2(i, j) * 1.6
				if _open_concourse(lv, p):
					cand.append([p.distance_squared_to(spot) + i * 1e-3 + j * 1e-5, p])
		cand.sort_custom(func(a, b): return a[0] < b[0])
		var pts := []
		for q in cand.slice(0, 14):
			pts.append(Vector3(q[1].x, level_y(lv) + 0.02, q[1].y))
		out[t] = {"pts": pts, "anchor": Vector3(spot.x, level_y(lv) + 0.02, spot.y), "yaw": _yaw_toward(spot, Vector2.ZERO), "level": lv}
	return out


func _open_concourse(lv: int, p: Vector2) -> bool:
	## Walkable public floor on this level: inside the mall, not over a court or a well, not inside a shop unit, a
	## fire-stair core or a restroom block (with a metre to spare).
	if not inside(p, 2.0) or not floor_at(lv, p) or in_court(p) or in_well(p) or core_at(p) >= 0:
		return false
	for rr in RESTROOMS:
		if (rr as Rect2).grow(1.0).has_point(p):
			return false
	for u in units:
		if int(u.level) == lv and (u.rect as Rect2).grow(1.0).has_point(p):
			return false
	return true


func dm_centre_for(_n_teams: int) -> Vector2:
	return Vector2.ZERO


# ------------------------------------------------------------------ bot walk grids

func _init_nav() -> void:
	nav_x0 = -SITE_X
	nav_z0 = -SITE_Z
	nav_nx = int(SITE_X * 2.0 / NAV_CELL)
	nav_nz = int(SITE_Z * 2.0 / NAV_CELL)
	nav_open.clear()
	for lv in LEVELS:
		var g := PackedByteArray()
		g.resize(nav_nx * nav_nz)
		for iz in nav_nz:
			for ix in nav_nx:
				var p := nav_cell_centre(ix, iz)
				g[iz * nav_nx + ix] = 1 if floor_at(lv, p) else 0
		nav_open.append(g)
	nav_links.clear()


func nav_cell_centre(ix: int, iz: int) -> Vector2:
	return Vector2(nav_x0 + (ix + 0.5) * NAV_CELL, nav_z0 + (iz + 0.5) * NAV_CELL)


func nav_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - nav_x0) / NAV_CELL)), 0, nav_nx - 1), clampi(int(floor((p.y - nav_z0) / NAV_CELL)), 0, nav_nz - 1))


func block_rect(level: int, c: Vector2, half: Vector2, ang: float = 0.0, pad: float = 0.3) -> void:
	## Close every walk cell whose centre lies within the rectangle (centre c, half extents, turned ang about y) grown
	## by pad: bodies need that much room beside a wall.
	if level < 0 or level >= LEVELS:
		return
	var g: PackedByteArray = nav_open[level]
	var h := half + Vector2(pad, pad)
	var ca := cos(ang)
	var sa := sin(ang)
	var ext := Vector2(absf(ca) * h.x + absf(sa) * h.y, absf(sa) * h.x + absf(ca) * h.y)
	var lo := nav_cell(c - ext)
	var hi := nav_cell(c + ext)
	for iz in range(lo.y, hi.y + 1):
		for ix in range(lo.x, hi.x + 1):
			var q := nav_cell_centre(ix, iz) - c
			var lx := q.x * ca + q.y * sa
			var lz := -q.x * sa + q.y * ca
			if absf(lx) <= h.x and absf(lz) <= h.y:
				g[iz * nav_nx + ix] = 0
	nav_open[level] = g


func block_seg(level: int, a: Vector2, b: Vector2, thick: float, pad: float = 0.3) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	block_rect(level, (a + b) * 0.5, Vector2(len * 0.5, thick * 0.5), atan2(d.y, d.x), pad)


func open_rect(level: int, c: Vector2, half: Vector2) -> void:
	## Reopen cells (a doorway through a wall the builder closed whole).
	var g: PackedByteArray = nav_open[level]
	var lo := nav_cell(c - half)
	var hi := nav_cell(c + half)
	for iz in range(lo.y, hi.y + 1):
		for ix in range(lo.x, hi.x + 1):
			if floor_at(level, nav_cell_centre(ix, iz)):
				g[iz * nav_nx + ix] = 1
	nav_open[level] = g


func add_link(a: Vector3, b: Vector3, via: Array = [], cost: float = 1.0, both: bool = false) -> void:
	## A way between levels for bots: a -> (via...) -> b, one way unless both.
	nav_links.append({"a": a, "b": b, "via": via, "cost": cost, "both": both})
