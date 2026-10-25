extends RefCounted
## Geography of Sitio Kalinaw, a riverside informal settlement on a bay. x = east, z = south (north is -z).
##
## The Ilog Kalinaw runs north to south through the middle of the map into the bay and splits it into a west bank
## and an east bank; a narrow estero joins it from the west. Every slum district is bounded by water, roads, the
## old railway or the bay, and players cross between them over a handful of bridges of very different exposure.

const HALF := 560.0
const PLAY_HALF := 500.0
const WATER_Y := -0.6
const LAND_Y := 0.9
const GRID := 2.0  # mask resolution (m)

var rng := RandomNumberGenerator.new()
var river: PackedVector2Array
var river_w: PackedFloat32Array
var estero: PackedVector2Array
var estero_w := 7.0
var railway: PackedVector2Array
var roads: Array = []        # [{name, pts: PackedVector2Array, w, mat, curb}]
var districts: Array = []    # [{name, kind, c: Vector2, half: Vector2, ang (rad), density}]
var sites: Array = []        # [{type, pos: Vector2, ang, name}]
var crossings: Array = []    # [{type, a: Vector2, b: Vector2, w, name}]
var landmarks: Array = []    # [{name, pos: Vector2}]
var highway_x := 468.0
var dump_c := Vector2(-462, -468)
var dump_r := 78.0
var dump_h := 24.0

var _n: int
var _water: PackedByteArray  # 1 = water (river/estero/sea)
var _reserved: PackedByteArray  # 1 road, 2 site, 3 lot, 4 bank walk
var _noise := FastNoiseLite.new()
var _river_lut_x: PackedFloat32Array
var _river_lut_w: PackedFloat32Array
var _river_lut_c: PackedFloat32Array
var _estero_lut: PackedFloat32Array
var _estero_c: PackedFloat32Array
var _rail_lut: PackedFloat32Array


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	_noise.seed = seed_value
	_noise.frequency = 0.006
	_noise.fractal_octaves = 3
	_n = int(HALF * 2.0 / GRID)
	_water = PackedByteArray()
	_water.resize(_n * _n)
	_reserved = PackedByteArray()
	_reserved.resize(_n * _n)
	_define()
	_build_luts()
	_rasterize()


func _define() -> void:
	river = PackedVector2Array([Vector2(30, -600), Vector2(22, -470), Vector2(-4, -400), Vector2(14, -330), Vector2(52, -262),
		Vector2(58, -190), Vector2(30, -120), Vector2(-12, -52), Vector2(-22, 18), Vector2(4, 90), Vector2(22, 160),
		Vector2(4, 232), Vector2(-28, 300), Vector2(-48, 370), Vector2(-58, 460), Vector2(-60, 600)])
	river_w = PackedFloat32Array()
	for i in river.size():
		river_w.append(lerpf(22.0, 34.0, float(i) / (river.size() - 1)))
	estero = PackedVector2Array([Vector2(-600, -42), Vector2(-470, -56), Vector2(-380, -36), Vector2(-292, -60), Vector2(-200, -42),
		Vector2(-112, -56), Vector2(-48, -42), Vector2(-14, -36)])
	railway = PackedVector2Array([Vector2(-600, -420), Vector2(-300, -428), Vector2(-60, -440), Vector2(200, -455), Vector2(600, -470)])

	roads = [
		{"name": "Coastal Road", "pts": PackedVector2Array([Vector2(-600, 336), Vector2(-300, 330), Vector2(-120, 342), Vector2(40, 338), Vector2(250, 328), Vector2(600, 334)]), "w": 9.0, "mat": "asphalt", "curb": true},
		{"name": "Riverside Avenue", "pts": PackedVector2Array([Vector2(-420, -202), Vector2(-150, -196), Vector2(0, -192), Vector2(150, -190), Vector2(330, -200), Vector2(600, -206)]), "w": 7.0, "mat": "pavement", "curb": true},
		{"name": "Main Road", "pts": PackedVector2Array([Vector2(200, -600), Vector2(196, -400), Vector2(186, -200), Vector2(176, 0), Vector2(170, 200), Vector2(174, 336)]), "w": 8.0, "mat": "asphalt", "curb": true},
		{"name": "Barangay Road", "pts": PackedVector2Array([Vector2(-232, -600), Vector2(-226, -430), Vector2(-216, -200), Vector2(-210, -80), Vector2(-205, 60), Vector2(-200, 200), Vector2(-205, 336)]), "w": 5.5, "mat": "pavement", "curb": false},
		{"name": "Kalye Mabini", "pts": PackedVector2Array([Vector2(-480, 120), Vector2(-300, 118), Vector2(-120, 124), Vector2(-48, 122)]), "w": 4.5, "mat": "pavement", "curb": false},
		{"name": "Kalye Rizal", "pts": PackedVector2Array([Vector2(60, 82), Vector2(176, 80), Vector2(300, 84), Vector2(440, 80)]), "w": 4.5, "mat": "pavement", "curb": false},
		{"name": "Kalye Bonifacio", "pts": PackedVector2Array([Vector2(-480, -322), Vector2(-226, -320), Vector2(-40, -318)]), "w": 4.0, "mat": "pavement", "curb": false},
		{"name": "Daang Bukid", "pts": PackedVector2Array([Vector2(196, -330), Vector2(330, -334), Vector2(440, -326)]), "w": 4.5, "mat": "gravel", "curb": false},
	]

	districts = [
		{"name": "Looban", "kind": "dense", "c": Vector2(-118, -262), "half": Vector2(98, 58), "ang": deg_to_rad(6.0), "density": 1.0},
		{"name": "Looban Kanluran", "kind": "dense", "c": Vector2(-388, -236), "half": Vector2(80, 70), "ang": deg_to_rad(-4.0), "density": 0.95},
		{"name": "Riles", "kind": "rail", "c": Vector2(-250, -428), "half": Vector2(240, 18), "ang": atan2(-12.0, 300.0), "density": 1.0},
		{"name": "Riles Silangan", "kind": "rail", "c": Vector2(160, -452), "half": Vector2(120, 16), "ang": atan2(-15.0, 260.0), "density": 0.85},
		{"name": "Estero Kalinaw", "kind": "stilt_creek", "c": Vector2(-250, -48), "half": Vector2(240, 30), "ang": 0.0, "density": 1.0},
		{"name": "Pampang Kanluran", "kind": "stilt_river", "side": -1, "z0": -160.0, "z1": 310.0, "density": 1.0},
		{"name": "Pampang Silangan", "kind": "stilt_river", "side": 1, "z0": -110.0, "z1": 300.0, "density": 0.9},
		{"name": "Kalinaw Proper", "kind": "mixed", "c": Vector2(-330, 200), "half": Vector2(140, 62), "ang": deg_to_rad(2.0), "density": 0.8},
		{"name": "Purok Dos", "kind": "mixed", "c": Vector2(-120, 210), "half": Vector2(52, 70), "ang": deg_to_rad(-3.0), "density": 0.9},
		{"name": "Baybayin", "kind": "fishing", "c": Vector2(-330, 368), "half": Vector2(210, 24), "ang": deg_to_rad(-1.0), "density": 1.0},
		{"name": "Looban Silangan", "kind": "dense", "c": Vector2(300, -24), "half": Vector2(112, 88), "ang": deg_to_rad(3.0), "density": 1.0},
		{"name": "Purok Tres", "kind": "dense", "c": Vector2(90, 150), "half": Vector2(52, 50), "ang": deg_to_rad(-6.0), "density": 0.9},
		{"name": "Talyer", "kind": "workshops", "c": Vector2(250, 230), "half": Vector2(56, 64), "ang": deg_to_rad(1.0), "density": 0.8},
		{"name": "Villa Esperanza", "kind": "subdivision", "c": Vector2(330, -340), "half": Vector2(100, 80), "ang": 0.0, "density": 1.0},
		{"name": "Ilalim", "kind": "under_highway", "c": Vector2(468, 0), "half": Vector2(10, 300), "ang": 0.0, "density": 1.0},
		{"name": "Pantalan", "kind": "port", "c": Vector2(330, 366), "half": Vector2(200, 24), "ang": 0.0, "density": 1.0},
		{"name": "Tambakan", "kind": "dump", "c": dump_c, "half": Vector2(70, 70), "ang": 0.0, "density": 0.6},
	]

	sites = [
		{"type": "chapel", "pos": Vector2(-118, -262), "ang": deg_to_rad(6.0), "name": "Kapilya ni San Roque"},
		{"type": "court", "pos": Vector2(-150, -236), "ang": deg_to_rad(6.0), "name": "Looban half-court"},
		{"type": "school", "pos": Vector2(-360, 64), "ang": deg_to_rad(2.0), "name": "Kalinaw Elementary School"},
		{"type": "barangay_hall", "pos": Vector2(-262, 72), "ang": deg_to_rad(1.0), "name": "Barangay Hall"},
		{"type": "clinic", "pos": Vector2(-232, 108), "ang": deg_to_rad(1.0), "name": "Health Center"},
		{"type": "covered_court", "pos": Vector2(-300, 150), "ang": deg_to_rad(2.0), "name": "Covered Court"},
		{"type": "water_tower", "pos": Vector2(-420, 150), "ang": 0.0, "name": "Water Tower"},
		{"type": "outpost", "pos": Vector2(-200, -178), "ang": 0.0, "name": "Tanod Outpost"},
		{"type": "pump_station", "pos": Vector2(-56, -12), "ang": deg_to_rad(-4.0), "name": "Pumping Station"},
		{"type": "junkshop", "pos": Vector2(-400, -372), "ang": deg_to_rad(-2.0), "name": "Junk Shop"},
		{"type": "market", "pos": Vector2(124, -146), "ang": deg_to_rad(-2.0), "name": "Palengke"},
		{"type": "church", "pos": Vector2(236, -124), "ang": deg_to_rad(-2.0), "name": "Simbahan ng Kalinaw"},
		{"type": "shophouses", "pos": Vector2(214, -250), "ang": deg_to_rad(-88.0), "name": "Main Road shops", "count": 7},
		{"type": "shophouses", "pos": Vector2(156, -40), "ang": deg_to_rad(-92.0), "name": "Main Road shops south", "count": 5},
		{"type": "gas_station", "pos": Vector2(200, 30), "ang": deg_to_rad(-2.0), "name": "Old Gas Station"},
		{"type": "apartment", "pos": Vector2(64, 252), "ang": deg_to_rad(-4.0), "name": "Paupahan"},
		{"type": "apartment", "pos": Vector2(380, 160), "ang": deg_to_rad(2.0), "name": "Paupahan Silangan"},
		{"type": "scrapyard", "pos": Vector2(310, 236), "ang": deg_to_rad(1.0), "name": "Scrapyard"},
		{"type": "warehouse", "pos": Vector2(220, 372), "ang": 0.0, "name": "Bodega 1"},
		{"type": "warehouse", "pos": Vector2(290, 372), "ang": 0.0, "name": "Bodega 2"},
		{"type": "container_yard", "pos": Vector2(400, 372), "ang": 0.0, "name": "Container Yard"},
		{"type": "fish_port", "pos": Vector2(120, 380), "ang": 0.0, "name": "Fish Port"},
		{"type": "cell_tower", "pos": Vector2(410, -200), "ang": 0.0, "name": "Cell Tower"},
		{"type": "police", "pos": Vector2(220, 124), "ang": deg_to_rad(-2.0), "name": "Police Community Precinct"},
	]

	crossings = [
		{"type": "road_bridge", "a": Vector2(30, -193), "b": Vector2(88, -191), "w": 7.0, "name": "Riverside Avenue Bridge"},
		{"type": "rail_bridge", "a": Vector2(-34, -439), "b": Vector2(40, -443), "w": 4.0, "name": "Rail Bridge"},
		{"type": "road_bridge", "a": Vector2(-82, 341), "b": Vector2(-14, 341), "w": 9.0, "name": "Coastal Bridge"},
		{"type": "steel_footbridge", "a": Vector2(-50, 40), "b": Vector2(14, 40), "w": 2.2, "name": "Steel Footbridge"},
		{"type": "plank_bridge", "a": Vector2(-30, -96), "b": Vector2(30, -96), "w": 1.3, "name": "Plank Bridge North"},
		{"type": "plank_bridge", "a": Vector2(-24, 228), "b": Vector2(34, 228), "w": 1.2, "name": "Plank Bridge South"},
		{"type": "pipe_bridge", "a": Vector2(-20, 130), "b": Vector2(44, 130), "w": 1.0, "name": "Pipe Crossing"},
	]
	for x in [-520.0, -420.0, -330.0, -255.0, -160.0, -80.0]:
		var z := _estero_z_slow(x)
		crossings.append({"type": "plank_bridge", "a": Vector2(x, z - 6.5), "b": Vector2(x, z + 6.5), "w": 1.2, "name": "Estero planks"})
	crossings.append({"type": "culvert", "a": Vector2(-212, -58), "b": Vector2(-210, -30), "w": 6.0, "name": "Barangay Road culvert"})

	landmarks = [
		{"name": "Cell Tower", "pos": Vector2(410, -200)}, {"name": "Water Tower", "pos": Vector2(-420, 150)},
		{"name": "Church", "pos": Vector2(236, -124)}, {"name": "Tambakan", "pos": dump_c},
		{"name": "Crane", "pos": Vector2(400, 372)}, {"name": "Expressway", "pos": Vector2(highway_x, -80)},
		{"name": "Rail Bridge", "pos": Vector2(4, -441)}, {"name": "Pumping Station", "pos": Vector2(-56, -12)},
		{"name": "Palengke", "pos": Vector2(124, -146)}, {"name": "School", "pos": Vector2(-360, 64)},
	]


func _estero_z_slow(x: float) -> float:
	for i in estero.size() - 1:
		if x >= estero[i].x and x <= estero[i + 1].x:
			return lerpf(estero[i].y, estero[i + 1].y, (x - estero[i].x) / (estero[i + 1].x - estero[i].x))
	return estero[-1].y


# ------------------------------------------------------------------ geometry helpers

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


static func poly_point(pts: PackedVector2Array, u: float) -> Vector2:
	var i := clampi(int(u), 0, pts.size() - 2)
	return pts[i].lerp(pts[i + 1], u - i)


static func poly_dir(pts: PackedVector2Array, u: float) -> Vector2:
	var i := clampi(int(u), 0, pts.size() - 2)
	return (pts[i + 1] - pts[i]).normalized()


func river_half_width(u: float) -> float:
	var i := clampi(int(u), 0, river_w.size() - 2)
	return lerpf(river_w[i], river_w[i + 1], u - i) * 0.5


func river_x(z: float) -> float:
	return _river_lut_x[clampi(int((z + HALF) * 0.5), 0, _river_lut_x.size() - 1)]


func river_hw(z: float) -> float:
	return _river_lut_w[clampi(int((z + HALF) * 0.5), 0, _river_lut_w.size() - 1)]


func estero_z(x: float) -> float:
	return _estero_lut[clampi(int((x + HALF) * 0.5), 0, _estero_lut.size() - 1)]


func rail_z(x: float) -> float:
	return _rail_lut[clampi(int((x + HALF) * 0.5), 0, _rail_lut.size() - 1)]


func coast_z(x: float) -> float:
	return 398.0 + 16.0 * sin(x * 0.011) + 9.0 * sin(x * 0.031 + 1.0)


func river_info(p: Vector2) -> Vector3:
	## x = approximate distance from the centreline, y = half width there.
	var i := clampi(int((p.y + HALF) * 0.5), 0, _river_lut_x.size() - 1)
	return Vector3(absf(p.x - _river_lut_x[i]) * _river_lut_c[i], _river_lut_w[i], 0.0)


func estero_info(p: Vector2) -> Vector2:
	if p.x > estero[-1].x + 4.0:
		return Vector2(INF, estero_w * 0.5)
	var i := clampi(int((p.x + HALF) * 0.5), 0, _estero_lut.size() - 1)
	return Vector2(absf(p.y - _estero_lut[i]) * _estero_c[i], estero_w * 0.5)


func _build_luts() -> void:
	## Lookup tables (every 2 m) for the river (monotonic in z), estero and railway (monotonic in x).
	var n := int(HALF * 2.0 / 2.0) + 1
	_river_lut_x = PackedFloat32Array(); _river_lut_w = PackedFloat32Array(); _river_lut_c = PackedFloat32Array()
	_estero_lut = PackedFloat32Array(); _estero_c = PackedFloat32Array(); _rail_lut = PackedFloat32Array()
	for k in n:
		var z := -HALF + k * 2.0
		var x := river[0].x
		var w := river_w[0]
		var slope := 0.0
		for i in river.size() - 1:
			if z >= river[i].y and z <= river[i + 1].y:
				var t := (z - river[i].y) / (river[i + 1].y - river[i].y)
				x = lerpf(river[i].x, river[i + 1].x, t)
				w = lerpf(river_w[i], river_w[i + 1], t)
				slope = (river[i + 1].x - river[i].x) / (river[i + 1].y - river[i].y)
				break
		_river_lut_x.append(x)
		_river_lut_w.append(w * 0.5)
		_river_lut_c.append(1.0 / sqrt(1.0 + slope * slope))
		var xx := -HALF + k * 2.0
		var ez := estero[0].y
		var es := 0.0
		for i in estero.size() - 1:
			if xx >= estero[i].x and xx <= estero[i + 1].x:
				var t2 := (xx - estero[i].x) / (estero[i + 1].x - estero[i].x)
				ez = lerpf(estero[i].y, estero[i + 1].y, t2)
				es = (estero[i + 1].y - estero[i].y) / (estero[i + 1].x - estero[i].x)
				break
		_estero_lut.append(ez)
		_estero_c.append(1.0 / sqrt(1.0 + es * es))
		var rz := railway[0].y
		for i in railway.size() - 1:
			if xx >= railway[i].x and xx <= railway[i + 1].x:
				rz = lerpf(railway[i].y, railway[i + 1].y, (xx - railway[i].x) / (railway[i + 1].x - railway[i].x))
				break
		_rail_lut.append(rz)


# ------------------------------------------------------------------ terrain height

func ground_height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := LAND_Y + _noise.get_noise_2d(x, z) * 0.35
	# Bay: beach then sea floor.
	var cz := coast_z(x)
	if z > cz - 18.0:
		var t := (z - (cz - 18.0)) / 18.0
		h = lerpf(h, WATER_Y - 0.15, clampf(t, 0.0, 1.0))
		if z > cz:
			h = lerpf(WATER_Y - 0.15, -4.5, clampf((z - cz) / 90.0, 0.0, 1.0))
	# River channel with sloped mud banks.
	var r := river_info(p)
	var bank := 7.0
	if r.x < r.y + bank:
		var bed := -3.2 + pow(clampf(r.x / r.y, 0.0, 1.0), 2.0) * 2.2
		if r.x < r.y:
			h = minf(h, bed)
		else:
			var t2 := (r.x - r.y) / bank
			h = minf(h, lerpf(-1.0, h, smoothstep(0.0, 1.0, t2)))
	# Estero: a steep-sided drainage channel.
	var e := estero_info(p)
	if e.x < e.y + 2.5:
		if e.x < e.y:
			h = minf(h, -2.1 + pow(e.x / e.y, 2.0) * 0.8)
		else:
			h = minf(h, lerpf(-1.3, h, (e.x - e.y) / 2.5))
	# Dump hill: a mound of compacted garbage.
	var dd := p.distance_to(dump_c)
	if dd < dump_r:
		var k := 1.0 - dd / dump_r
		h += dump_h * (k * k * (3.0 - 2.0 * k)) + _noise.get_noise_2d(x * 3.0, z * 3.0) * 1.6 * k
	# Railway embankment
	var rd := absf(z - rail_z(x))
	if rd < 6.0:
		h += 0.7 * (1.0 - smoothstep(2.4, 6.0, rd))
	return h


func is_water(x: float, z: float) -> bool:
	var ix := int((x + HALF) / GRID)
	var iz := int((z + HALF) / GRID)
	if ix < 0 or iz < 0 or ix >= _n or iz >= _n:
		return z > 300.0
	return _water[iz * _n + ix] == 1


func water_height(x: float, z: float) -> float:
	return WATER_Y if is_water(x, z) else -INF


# ------------------------------------------------------------------ masks

func _rasterize() -> void:
	for iz in _n:
		var z := -HALF + (iz + 0.5) * GRID
		var rx := river_x(z)
		var rw := river_hw(z)
		for ix in _n:
			var x := -HALF + (ix + 0.5) * GRID
			var near := absf(x - rx) < rw + 3.0 or z > coast_z(x) - 20.0 or (x < estero[-1].x + 6.0 and absf(z - estero_z(x)) < estero_w)
			if near and ground_height(x, z) < WATER_Y + 0.05:
				_water[iz * _n + ix] = 1
	for r in roads:
		_mark_poly(r.pts, float(r.w) * 0.5 + 1.0, 1)
	_mark_poly(railway, 3.2, 1)
	# Keep the space under the expressway mostly open (the Ilalim district fills it deliberately).


func _mark_poly(pts: PackedVector2Array, half_w: float, value: int) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * half_w
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * half_w
		for iz in range(maxi(int((lo.y + HALF) / GRID), 0), mini(int((hi.y + HALF) / GRID) + 1, _n)):
			for ix in range(maxi(int((lo.x + HALF) / GRID), 0), mini(int((hi.x + HALF) / GRID) + 1, _n)):
				var p := Vector2(-HALF + (ix + 0.5) * GRID, -HALF + (iz + 0.5) * GRID)
				if seg_dist(p, a, b) <= half_w:
					if _reserved[iz * _n + ix] == 0:
						_reserved[iz * _n + ix] = value


func reserve_rect(center: Vector2, half: Vector2, ang: float, value: int, margin: float = 0.0) -> void:
	var r := maxf(half.x, half.y) * 1.5 + margin
	var c := cos(-ang)
	var s := sin(-ang)
	for iz in range(maxi(int((center.y - r + HALF) / GRID), 0), mini(int((center.y + r + HALF) / GRID) + 1, _n)):
		for ix in range(maxi(int((center.x - r + HALF) / GRID), 0), mini(int((center.x + r + HALF) / GRID) + 1, _n)):
			var p := Vector2(-HALF + (ix + 0.5) * GRID, -HALF + (iz + 0.5) * GRID) - center
			var lp := Vector2(p.x * c - p.y * s, p.x * s + p.y * c)
			if absf(lp.x) <= half.x + margin and absf(lp.y) <= half.y + margin:
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


func water_fraction(center: Vector2, half: Vector2, ang: float) -> float:
	var xa := Vector2(cos(ang), sin(ang))
	var za := Vector2(-sin(ang), cos(ang))
	var n := 0
	var w := 0
	for i in 5:
		for j in 5:
			var p := center + xa * (-half.x + half.x * 0.5 * i) + za * (-half.y + half.y * 0.5 * j)
			n += 1
			if is_water(p.x, p.y):
				w += 1
	return float(w) / n


func in_play_area(p: Vector2) -> bool:
	return absf(p.x) < PLAY_HALF and p.y > -PLAY_HALF and p.y < coast_z(p.x) + 60.0
