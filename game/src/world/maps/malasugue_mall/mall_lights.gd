extends RefCounted
## (r16) Malasugue Mall's lights after the outbreak. The walks keep the fittings MallBuilder.power gives them: where a
## stretch still has power, a pool of light falls from its downlights (one spot every 9 m, from the fitting nearest
## that point); where it is faulty one fitting flickers, sputters or browns out (Lighting animates it and draws its
## lens); the blacked-out stretches are dark but for battery emergency lamps on the shopfronts, some of them dying.
## Over the courts: daylight (moonlight at night) falls in shafts through the East Court's dome and the West Court's
## vault, and a few of the Grand Atrium's ceiling spots still throw narrow beams to the floor five levels down. The
## dust in the air (Lighting's indoor volumetric fog) shows the cones.

var B = null
var mb = null
var L = null
var S = null
var stats := {"down": 0, "faulty": 0, "emergency": 0, "shafts": 0, "beams": 0}

const WARM := Color(0.9, 0.93, 0.76)
const COOL := Color(0.57, 0.81, 0.87)
const STEP := 9.0
var _grid := {}   # [level] -> {Vector2i (3 m cell) -> [downlight indices]}


func _init(builder) -> void:
	B = builder
	mb = builder.mb
	L = builder.L
	S = builder.S


func build() -> void:
	for lv in L.LEVELS:
		_index(lv)
		_walks(lv)
		_emergency(lv)
	_shafts()
	_atrium_beams()


func _index(lv: int) -> void:
	var g := {}
	var list: Array = B.downlights[lv]
	for i in list.size():
		var p: Vector3 = (list[i][0] as Transform3D).origin
		var k := Vector2i(floori(p.x / 3.0), floori(p.z / 3.0))
		if not g.has(k):
			g[k] = []
		g[k].append(i)
	_grid[lv] = g


func _nearest(lv: int, p: Vector2, max_d: float = 2.2) -> int:
	var g: Dictionary = _grid[lv]
	var k := Vector2i(floori(p.x / 3.0), floori(p.y / 3.0))
	var best := -1
	var bd := max_d * max_d
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for i in g.get(k + Vector2i(dx, dz), []):
				var q: Vector3 = (B.downlights[lv][i][0] as Transform3D).origin
				var d2 := Vector2(q.x, q.z).distance_squared_to(p)
				if d2 < bd:
					bd = d2
					best = i
	return best


func _walks(lv: int) -> void:
	## One spot per 9 m of walk with power, from the fitting nearest the lattice point (or the point itself).
	var y: float = L.level_y(lv) + L.CEIL - 0.03
	var x: float = -L.MX + 4.5
	while x < L.MX:
		var z: float = -L.MZ + 4.5
		while z < L.MZ:
			var p := Vector2(x, z)
			z += STEP
			if not B.is_walk(lv, p):
				continue
			var st: int = B.power(lv, p)
			if st == B.POWER_DEAD:
				continue
			var at := Vector3(p.x, y, p.y)
			var di := _nearest(lv, p)
			if di >= 0:
				var q: Vector3 = (B.downlights[lv][di][0] as Transform3D).origin
				at = Vector3(q.x, y, q.z)
			var spec := {"pos": at, "kind": "down", "angle": 67.0, "color": WARM, "energy": 4.1, "range": 9.0, "fade": 40.0, "emitter": false,
				"attenuation": 0.8, "fog": 0.0}
			if st == B.POWER_FAULTY:
				spec.fault = B.FAULTS[int(B.h01(int(p.x), int(p.y), 800 + lv) * 6.0) % 6]
				spec.emitter = true
				spec.color = COOL if B.h01(int(p.x), int(p.y), 801) < 0.4 else WARM
				if di >= 0:
					B.downlights[lv][di][1] = B.POWER_LAMP   # Lighting draws this lens, flickering with its lamp
				stats.faulty += 1
			mb.dyn.add_light(spec)
			stats.down += 1
		x += STEP


func _emergency(lv: int) -> void:
	## Battery emergency lamps (twin heads on a white box) on the band shopfronts' fascias and the island ends, where
	## the walk is dark. A third of the batteries are going (sag, dying).
	var y: float = L.level_y(lv)
	var spots := []
	for side in [-1.0, 1.0]:
		var x := -52.0
		while x <= 52.0:
			spots.append([Vector3(x, y + 3.05, side * (L.BAND_Z - 0.25)), Vector3(0, 0, -side)])
			x += 13.0
	for ir in L.ISLANDS:
		var r: Rect2 = ir
		for side2 in [-1.0, 1.0]:
			spots.append([Vector3(r.get_center().x, y + 3.05, r.get_center().y + side2 * (r.size.y * 0.5 + 0.25)), Vector3(0, 0, side2)])
	for s in spots:
		var p: Vector3 = s[0]
		var n: Vector3 = s[1]
		var floor_p := Vector2(p.x + n.x * 2.0, p.z + n.z * 2.0)
		if not B.is_walk(lv, floor_p) or B.power(lv, floor_p) != B.POWER_DEAD:
			continue
		if lv == 0 and absf(p.x) < 6.5:
			continue   # the main entrances
		var h: float = B.h01(int(p.x), int(p.z), 820 + lv)
		var yaw := atan2(n.x, n.z)
		var bas := Basis(Vector3.UP, yaw)
		var c := p + n * 0.08
		S.box(Transform3D(bas, c), Vector3(0.44, 0.15, 0.1), "mall_gloss", B.o({"tint": Color(0.92, 0.92, 0.9), "paint": 1.0, "layer": "mid"}))
		var fault := "" if h < 0.66 else ("sag" if h < 0.85 else "dying")
		for sx in [-0.14, 0.14]:
			var hp := c + bas * Vector3(sx, -0.1, 0.06)
			S.box(Transform3D(bas * Basis(Vector3(1, 0, 0), 0.6), hp), Vector3(0.09, 0.07, 0.09), "mall_gloss", B.o({"tint": Color(0.9, 0.9, 0.88), "paint": 1.0, "layer": "int"}))
			S.box(Transform3D(bas * Basis(Vector3(1, 0, 0), 0.6), hp + bas * Vector3(0, -0.02, 0.04)), Vector3(0.07, 0.05, 0.01),
				"mall_light_warm" if fault == "" else "mall_light_dead", B.o({"layer": "int"}))
		# the green running man over it, a little dusty
		S.atlas_quad(c + Vector3(0, 0.32, 0) + n * 0.02, bas * Vector3(-1, 0, 0) * -1.0, Vector3.UP, 0.5, 0.25, Rect2(0.0, 0.0, 0.25, 0.25), "mall_wayfind", {"layer": "mid"})
		mb.dyn.add_light({"pos": c + n * 0.35 + Vector3(0, -0.2, 0), "kind": "lamp", "color": Color(1.0, 0.84, 0.6), "energy": 0.7, "range": 6.5,
			"fade": 28.0, "emitter": fault != "", "fault": fault})
		stats.emergency += 1


func _shafts() -> void:
	## Light through the skylights: one shaft down the East Court from its dome, two down the West Court from the
	## vault. Strong enough to read on Level 1, cold and dim at night (Lighting scales them with the daylight).
	var top: float = L.level_y(L.LEVELS - 1) + L.FH
	var specs := [[Vector3(L.EAST_C.x, top + 4.6, L.EAST_C.y), 21.0, 3.2], [Vector3(-48.0, top + 3.6, -2.0), 17.0, 2.4], [Vector3(-40.0, top + 3.6, 3.0), 17.0, 2.4]]
	for s in specs:
		mb.dyn.add_light({"pos": s[0], "kind": "shaft", "angle": s[1], "color": Color(0.9, 0.93, 1.0), "energy": s[2], "range": 42.0, "fade": 70.0,
			"emitter": false, "attenuation": 0.35, "fog": 4.0})
		stats.shafts += 1


func _atrium_beams() -> void:
	## Four of the Grand Atrium's ceiling spots still on: narrow beams through the dust to the floor below.
	var gy: float = L.level_y(L.LEVELS - 1) + L.FH + 1.5
	for p in [Vector2(-9.0, -4.0), Vector2(6.5, 6.0), Vector2(11.0, -6.5), Vector2(-3.0, 9.5)]:
		mb.dyn.add_light({"pos": Vector3(p.x, gy, p.y), "kind": "down", "angle": 9.0, "color": Color(1.0, 0.9, 0.78), "energy": 3.0, "range": 34.0,
			"fade": 60.0, "emitter": true, "attenuation": 0.35, "fog": 1.6, "fault": "flicker" if p.x > 10.0 else ""})
		stats.beams += 1
