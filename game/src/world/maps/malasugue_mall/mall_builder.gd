extends RefCounted
## (r15) Builds Malasugue Mall (MallLayout's plan) into the shared geometry sink: the site and the plaza, every level's
## floor (polished concourse tiles, marble courts), the slab edges round the courts with their white fascias, glass
## balustrades with oak handrails and the blue kick strip, suspended ceilings with downlights, columns, the outer
## shell and facade, the fire-stair cores, restrooms, every shop unit (walls, glass shopfronts and doors that shatter,
## lit fascia signs) and their insides (MallShops), the escalator banks (MallEscalators), the court centrepieces, the
## roof and the lighting. Bots get their walk grids from the same calls (layout.block_rect / add_link).

const MallShops := preload("res://src/world/maps/malasugue_mall/mall_shops.gd")
const MallEscalators := preload("res://src/world/maps/malasugue_mall/mall_escalators.gd")
const MallDecor := preload("res://src/world/maps/malasugue_mall/mall_decor.gd")
const MallLights := preload("res://src/world/maps/malasugue_mall/mall_lights.gd")
const MallWreck := preload("res://src/world/maps/malasugue_mall/mall_wreck.gd")
const MallRestrooms := preload("res://src/world/maps/malasugue_mall/mall_restrooms.gd")
const MallDept := preload("res://src/world/maps/malasugue_mall/mall_dept.gd")
const MallHorror := preload("res://src/world/maps/malasugue_mall/mall_horror.gd")

var mb = null      # MapBuilder
var L = null       # MallLayout
var S = null       # GeoSink
var rng := RandomNumberGenerator.new()
var stats := {}
## Ceiling downlights and other emitters gathered as transforms, made into one MultiMesh per level at the end.
## (r16) Each with its power: [Transform3D, state] (POWER_*); MallLights turns some into lamps of its own.
var downlights: Array = []   # [level] -> Array[[Transform3D, int]]
var light_panels: Array = [] # [level] -> Array[[Transform3D, int]] (square ceiling panels in back-of-house rooms)
var unit_rects: Array = []   # [level] -> Array[Rect2]: shop units, cores and restrooms (not the walks)
const POWER_DEAD := 0
const POWER_ON := 1
const POWER_FAULTY := 2
const POWER_LAMP := 3        # drawn by Lighting as the emitter of a faulty lamp
const FAULTS := ["flicker", "starter", "dying", "sag", "flicker", "starter"]
## (r16) The unit on Level 4 (north band, x -19..-6) that burnt out (MallWreck): no power, every pane gone.
const BURNT := {"lv": 3, "p": Vector2(-12.5, -40.25)}
## (r16) Every room the shops built, for MallWreck to make a mess of: {lv, xf, w, d, kind, power, bid, name}.
var rooms: Array = []
## (r16) The after-the-outbreak decals (tools/make_mall_apoc.py), the blood cards (tools/make_blood_textures.py) and
## the walls' vandal atlas (tools/make_vandal_atlas.py): name -> UV rect.
const APOC := "decal:res://assets/mall/apoc.png"
const BLOOD := "decal:res://assets/fx/blood_albedo.png"
const VANDAL := "decal_atlas"
var _cells := {}

const WHITE := Color(0.95, 0.94, 0.92)
const CREAM := Color(0.93, 0.9, 0.84)
const NAVY := Color(0.07, 0.1, 0.2)
const BLUE_STRIP := Color(0.1, 0.32, 0.72)
const DARK := Color(0.16, 0.17, 0.19)
const FACADE := Color(0.86, 0.85, 0.82)


func _init(map_builder, layout) -> void:
	mb = map_builder
	L = layout
	S = map_builder.sink
	rng.seed = 151515
	for lv in L.LEVELS:
		downlights.append([])
		light_panels.append([])
		var rs: Array = L.CORES + L.RESTROOMS
		for u in L.units:
			if int(u.level) == lv:
				rs.append(u.rect)
		unit_rects.append(rs)


# ------------------------------------------------------------------ small helpers

static func o(opt: Dictionary = {}) -> Dictionary:
	var r := opt.duplicate()
	if not r.has("dirt"):
		r.dirt = 0.5   # (r16) grime at the foot of everything (surface.gdshader / mall_vc.gdshader)
	if not r.has("collide"):
		r.collide = false
	return r


func bx(c: Vector3, size: Vector3, mat: String, opt: Dictionary = {}) -> void:
	S.box(Transform3D(Basis(), c), size, mat, o(opt))


func bxr(c: Vector3, size: Vector3, yaw: float, mat: String, opt: Dictionary = {}) -> void:
	S.box(Transform3D(Basis(Vector3.UP, yaw), c), size, mat, o(opt))


func solid(lv: int, c: Vector3, size: Vector3, mat: String, opt: Dictionary = {}, yaw: float = 0.0, pad: float = 0.3) -> void:
	## A box that blocks bodies, rounds and bots.
	var op := o(opt)
	op.collide = true
	S.box(Transform3D(Basis(Vector3.UP, yaw), c), size, mat, op)
	if lv >= 0:
		L.block_rect(lv, Vector2(c.x, c.z), Vector2(size.x, size.z) * 0.5, -yaw, pad)


static func seg_yaw(a: Vector2, b: Vector2) -> float:
	## The yaw that turns a box's local x along a -> b.
	return atan2(-(b.y - a.y), b.x - a.x)


func wall(lv: int, a: Vector2, b: Vector2, y0: float, h: float, t: float, mat: String, opt: Dictionary = {}, block: bool = true) -> void:
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var op := o(opt)
	op.collide = op.get("collide", true) if opt.has("collide") else true
	var m := (a + b) * 0.5
	S.box(Transform3D(Basis(Vector3.UP, seg_yaw(a, b)), Vector3(m.x, y0 + h * 0.5, m.y)), Vector3(len, h, t), mat, op)
	if block and op.collide:
		L.block_seg(lv, a, b, t, 0.3)


func hquad(r: Rect2, y: float, mat: String, up: bool, opt: Dictionary = {}) -> void:
	## A horizontal rectangle at height y, facing up (floor) or down (ceiling).
	var op := o(opt)
	op.facing = Vector3.UP if up else Vector3.DOWN
	S.quad(Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y), mat, op)


func hpoly(pts: PackedVector2Array, y: float, mat: String, up: bool, opt: Dictionary = {}) -> void:
	## A convex horizontal polygon as a fan of quads (each a triangle pair sharing the centre).
	if pts.size() < 3:
		return
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var op := o(opt)
	op.facing = Vector3.UP if up else Vector3.DOWN
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var m := (a + b) * 0.5
		S.quad(Vector3(c.x, y, c.y), Vector3(a.x, y, a.y), Vector3(m.x, y, m.y), Vector3(b.x, y, b.y), mat, op)


func hquad4(q: Array, y: float, mat: String, up: bool, opt: Dictionary = {}) -> void:
	var op := o(opt)
	op.facing = Vector3.UP if up else Vector3.DOWN
	S.quad(Vector3(q[0].x, y, q[0].y), Vector3(q[1].x, y, q[1].y), Vector3(q[2].x, y, q[2].y), Vector3(q[3].x, y, q[3].y), mat, op)


func downlight(lv: int, p: Vector3, state: int = -1) -> void:
	## A ceiling downlight at p; its power from the walk's zone (power) unless the room says (shops, restrooms).
	if state < 0:
		state = power(lv, Vector2(p.x, p.z))
	downlights[lv].append([Transform3D(Basis(), p), state if state in [POWER_ON, POWER_LAMP] else POWER_DEAD])


# ------------------------------------------------------------------ (r16) decals

func _load_cells() -> void:
	for pair in [["res://assets/mall/apoc.json", ""], ["res://assets/fx/vandal_atlas.json", "v:"]]:
		var d = JSON.parse_string(FileAccess.get_file_as_string(pair[0]))
		if not d is Dictionary:
			continue
		var sz: Vector2 = Vector2(d.size[0], d.size[1]) if d.size is Array else Vector2(float(d.size), float(d.size))
		for c in d.get("cells", []):
			var r: Array = c.rect
			# half a texel in from the edges so the neighbours' mipmaps do not bleed in
			_cells[str(pair[1]) + str(c.name)] = Rect2((float(r[0]) + 1.0) / sz.x, (float(r[1]) + 1.0) / sz.y, (float(r[2]) - 2.0) / sz.x, (float(r[3]) - 2.0) / sz.y)
	for i in 16:
		_cells["b:%d" % i] = Rect2((i % 4) * 0.25 + 0.002, (i / 4) * 0.25 + 0.002, 0.246, 0.246)


func cell(name: String) -> Rect2:
	## An atlas cell by name: apoc cells as they are, "v:<name>" the vandal atlas, "b:<0-15>" the blood cards.
	if _cells.is_empty():
		_load_cells()
	return _cells.get(name, Rect2(0, 0, 0.01, 0.01))


static func cell_mat(name: String) -> String:
	return VANDAL if name.begins_with("v:") else (BLOOD if name.begins_with("b:") else APOC)


func floor_decal(p: Vector3, size: Vector2, yaw: float, name: String, alpha: float = 1.0, tint: Color = Color(1, 1, 1), layer: String = "int") -> void:
	## A decal lying on a floor at p (size across x it, along yaw's forward); drawn only, never collides.
	var r := Vector3(cos(yaw), 0.0, -sin(yaw))
	var u := Vector3(-sin(yaw), 0.0, -cos(yaw))
	S.atlas_quad(p + Vector3(0, 0.006, 0), r, u, size.x, size.y, cell(name), cell_mat(name), {"layer": layer, "tint": Color(tint.r, tint.g, tint.b, alpha)})


func wall_decal(p: Vector3, n: Vector3, size: Vector2, name: String, alpha: float = 1.0, roll: float = 0.0, layer: String = "int") -> void:
	## A decal on a wall at p, facing n (horizontal), turned roll about n.
	var nn := Vector3(n.x, 0.0, n.z).normalized()
	var r := Vector3.UP.cross(nn).normalized()
	var u := Vector3.UP
	if roll != 0.0:
		r = r.rotated(nn, roll)
		u = u.rotated(nn, roll)
	S.atlas_quad(p + nn * 0.012, r, u, size.x, size.y, cell(name), cell_mat(name), {"layer": layer, "tint": Color(1, 1, 1, alpha)})


func ceil_decal(p: Vector3, size: Vector2, yaw: float, name: String, alpha: float = 1.0) -> void:
	## A decal on a ceiling at p, seen from below.
	var r := Vector3(cos(yaw), 0.0, -sin(yaw))
	var u := Vector3(sin(yaw), 0.0, cos(yaw))
	S.atlas_quad(p - Vector3(0, 0.008, 0), r, u, size.x, size.y, cell(name), cell_mat(name), {"layer": "mid", "tint": Color(1, 1, 1, alpha)})


func panel(lv: int, p: Vector3, state: int = POWER_ON) -> void:
	light_panels[lv].append([Transform3D(Basis(), p), state])


# ------------------------------------------------------------------ (r16) power after the outbreak

static func h01(x: int, z: int, s: int) -> float:
	return float(hash(Vector3i(x, z, s)) & 0xFFFF) / 65535.0


static func vnoise(p: Vector2, s: int) -> float:
	## Smooth value noise, one feature per unit.
	var i := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(i)
	f = f * f * (Vector2(3, 3) - f * 2.0)
	return lerpf(lerpf(h01(i.x, i.y, s), h01(i.x + 1, i.y, s), f.x), lerpf(h01(i.x, i.y + 1, s), h01(i.x + 1, i.y + 1, s), f.x), f.y)


func power(lv: int, p: Vector2) -> int:
	## Which of the walks' fittings still work: blacked-out stretches tens of metres across (with the odd lamp
	## flickering in them), well-lit ones, and between them a patchwork of working, dead and faulty fittings.
	var n := vnoise(p / 21.0, 40 + lv)
	var h := h01(floori(p.x / 9.0), floori(p.y / 9.0), 90 + lv)
	if n < 0.4:
		return POWER_FAULTY if h < 0.12 else POWER_DEAD
	if n > 0.64:
		return POWER_ON if h > 0.14 else POWER_FAULTY
	return POWER_ON if h < 0.4 else (POWER_FAULTY if h < 0.62 else POWER_DEAD)


func burnt(lv: int, p: Vector2) -> bool:
	return lv == int(BURNT.lv) and absf(p.x - (BURNT.p as Vector2).x) < 6.6 and absf(p.y - (BURNT.p as Vector2).y) < 6.0


func light_mat(lv: int, p: Vector2) -> String:
	return "mall_light" if power(lv, p) == POWER_ON else "mall_light_dead"


func is_walk(lv: int, p: Vector2) -> bool:
	## On a concourse (not in a shop, core or restroom, not over a court).
	if not L.floor_at(lv, p) or not L.inside(p, 0.3):
		return false
	for r in unit_rects[lv]:
		if (r as Rect2).has_point(p):
			return false
	return true


func holes_at(lv: int) -> Array:
	## (r16) Openings in Level lv's floor (and so in the ceiling of the level below): the department store's escalators.
	if lv < 0 or lv >= L.LEVELS:
		return []
	var w: Rect2 = L.dept_well(lv)
	var openings: Array = [] if w.size == Vector2.ZERO else [w]
	if lv > 0:
		openings.append_array(L.lift_holes())
	return openings


static func minus_holes(r: Rect2, holes: Array) -> Array:
	## r less the holes (each split off as up to four rectangles round it).
	var out := [r]
	for h in holes:
		var next := []
		for q in out:
			var a: Rect2 = q
			if not a.intersects(h):
				next.append(a)
				continue
			var c: Rect2 = a.intersection(h)
			if c.size.x < 0.001 or c.size.y < 0.001:
				next.append(a)
				continue
			if c.position.y > a.position.y:
				next.append(Rect2(a.position.x, a.position.y, a.size.x, c.position.y - a.position.y))
			if c.end.y < a.end.y:
				next.append(Rect2(a.position.x, c.end.y, a.size.x, a.end.y - c.end.y))
			if c.position.x > a.position.x:
				next.append(Rect2(a.position.x, c.position.y, c.position.x - a.position.x, c.size.y))
			if c.end.x < a.end.x:
				next.append(Rect2(c.end.x, c.position.y, a.end.x - c.end.x, c.size.y))
		out = next
	return out


func sign_uv(tile: int) -> Rect2:
	## A shop's sign in assets/mall/signs.png (4 x 32 tiles of 512 x 128).
	return Rect2((tile % 4) * 0.25, (tile / 4) / 32.0, 0.25, 1.0 / 32.0)


# ------------------------------------------------------------------ build

func build() -> void:
	var t0 := Time.get_ticks_msec()
	mb._progress(0.06, "Pouring the plaza")
	_site()
	mb._progress(0.12, "Pouring five floors of polished tile")
	for lv in L.LEVELS:
		_floors(lv)
		_ceilings(lv)
	stats.floors_ms = Time.get_ticks_msec() - t0
	mb._progress(0.24, "Hanging glass round the courts")
	for lv in range(1, L.LEVELS):
		_court_edges(lv)
	_roof_edges()
	_columns()
	mb._progress(0.32, "Raising the outer walls")
	_shell()
	_entrances()
	mb._progress(0.38, "Building the fire stairs")
	_cores()
	_restrooms()
	stats.shell_ms = Time.get_ticks_msec() - t0
	mb._progress(0.44, "Fitting out a hundred shops")
	var shops := MallShops.new(self)
	shops.build_all()
	stats.shops = shops.stats
	stats.shops_ms = Time.get_ticks_msec() - t0
	mb._progress(0.62, "Installing the escalators (they actually move)")
	var esc := MallEscalators.new(self)
	esc.build()
	stats.escalators = esc.stats
	var dept := MallDept.new(self)
	dept.build_escalators()
	stats.dept = dept.stats
	mb._progress(0.68, "Decorating for the holidays (before it all went wrong)")
	var decor := MallDecor.new(self)
	decor.build()
	stats.decor = decor.stats
	_roof()
	mb._progress(0.72, "Leaving the place exactly as they fled it")
	var wreck := MallWreck.new(self)
	wreck.build()
	stats.wreck = wreck.stats
	var horror := MallHorror.new(self)
	horror.build()
	stats.horror = horror.stats
	var lights := MallLights.new(self)
	lights.build()
	stats.lights = lights.stats
	_emitters()
	_probes()
	stats.build_ms = Time.get_ticks_msec() - t0


func _probes() -> void:
	## Reflection probes, rendered once on load, so the polished floors, glass and steel reflect the mall (the courts,
	## the north and south walks, the anchors' halls) instead of a grey void.
	if DisplayServer.get_name() == "headless":
		return
	var specs := [[Vector3(0, 12.6, 0), Vector3(42, 26.5, 34)], [Vector3(-44, 12.6, 0), Vector3(28, 26.5, 30)], [Vector3(46, 12.6, 0), Vector3(26, 26.5, 26)],
		[Vector3(-28, 12.6, -30), Vector3(60, 26.5, 12)], [Vector3(28, 12.6, -30), Vector3(60, 26.5, 12)],
		[Vector3(-28, 12.6, 30), Vector3(60, 26.5, 12)], [Vector3(28, 12.6, 30), Vector3(60, 26.5, 12)]]
	for s in specs:
		var rp := ReflectionProbe.new()
		rp.size = s[1]
		rp.position = s[0]
		rp.origin_offset = Vector3(0, -10.0, 0)
		rp.box_projection = true
		rp.interior = true
		rp.update_mode = ReflectionProbe.UPDATE_ONCE
		rp.max_distance = 90.0
		rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		rp.intensity = 0.9
		mb.root.add_child(rp)


# ------------------------------------------------------------------ the site

func _site() -> void:
	## The block the mall stands on: hex pavers round the building, a drop-off lane with kerbs past each entrance,
	## planted strips along the fence, and the fence itself (the edge of play).
	var y := 0.0
	var sx: float = L.SITE_X
	var sz: float = L.SITE_Z
	var mx: float = L.MX
	var mz: float = L.MZ
	# Plaza ring (outside the walls), in four pieces.
	for r in [Rect2(-sx, -sz, sx * 2.0, sz - mz), Rect2(-sx, mz, sx * 2.0, sz - mz), Rect2(-sx, -mz, sx - mx, mz * 2.0), Rect2(mx, -mz, sx - mx, mz * 2.0)]:
		hquad(r, y + 0.001, "plaza_hex", true, {"collide": true, "tile": 2.5})
	# A drop-off lane on the south (main entrance) and north sides, asphalt between kerbs.
	for side in [-1.0, 1.0]:
		var z0 = side * (mz + 7.0)
		var lane := Rect2(-40.0, z0 - 3.5, 80.0, 7.0)
		hquad(lane, y + 0.012, "lot_asphalt", true, {"collide": true, "tile": 5.0})
		for k in [-1.0, 1.0]:
			bx(Vector3(0, y + 0.06, z0 + k * 3.6), Vector3(80.0, 0.14, 0.22), "concrete", {"collide": true, "tint": Color(0.8, 0.8, 0.78), "paint": 0.6})
		# Bollards between the lane and the doors.
		for i in 15:
			var bxp := -21.0 + i * 3.0
			if absf(bxp) < 7.0:
				continue
			S.cylinder(Vector3(bxp, y, side * (mz + 3.0)), Vector3.UP, 0.9, 0.11, "mall_steel", {"sides": 10, "collide": true})
	# Planted strips and palms along the fence.
	var palm_models := ["island_tree_01", "island_tree_02"]
	for side in [-1.0, 1.0]:
		var zf = side * (sz - 3.0)
		bx(Vector3(0, y + 0.2, zf), Vector3(sx * 2.0 - 4.0, 0.4, 3.0), "concrete", {"collide": true, "tint": Color(0.7, 0.7, 0.68), "paint": 0.5})
		hquad(Rect2(-sx + 2.2, zf - 1.3, sx * 2.0 - 4.4, 2.6), y + 0.41, "lawn_leafy", true, {"tile": 3.0})
		for i in 13:
			var px := -sx + 8.0 + i * 13.5
			mb.dyn.add_static_prop("money_tree", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(px, y + 0.4, zf)))
	for side in [-1.0, 1.0]:
		var xf2 = side * (sx - 3.0)
		bx(Vector3(xf2, y + 0.2, 0), Vector3(3.0, 0.4, sz * 2.0 - 10.0), "concrete", {"collide": true, "tint": Color(0.7, 0.7, 0.68), "paint": 0.5})
		hquad(Rect2(xf2 - 1.3, -sz + 5.2, 2.6, sz * 2.0 - 10.4), y + 0.41, "lawn_leafy", true, {"tile": 3.0})
	# The fence: concrete posts and steel railings, 2.4 m.
	for side in [-1.0, 1.0]:
		bx(Vector3(0, 1.2, side * sz), Vector3(sx * 2.0, 2.4, 0.25), "mall_metal_vc", {"collide": true, "tint": Color(0.15, 0.17, 0.18), "paint": 1.0})
		bx(Vector3(side * sx, 1.2, 0), Vector3(0.25, 2.4, sz * 2.0), "mall_metal_vc", {"collide": true, "tint": Color(0.15, 0.17, 0.18), "paint": 1.0})
	# Street lamps round the plaza (real lights, the fill does the rest).
	var li := 0
	for p in [Vector2(-60, -54), Vector2(-20, -54), Vector2(20, -54), Vector2(60, -54), Vector2(-60, 54), Vector2(-20, 54), Vector2(20, 54), Vector2(60, 54),
			Vector2(-80, -20), Vector2(-80, 20), Vector2(80, -20), Vector2(80, 20)]:
		S.cylinder(Vector3(p.x, 0, p.y), Vector3.UP, 6.5, 0.09, "mall_metal_vc", {"sides": 10, "collide": true, "tint": Color(0.12, 0.13, 0.14), "paint": 1.0})
		bx(Vector3(p.x, 6.55, p.y), Vector3(0.7, 0.12, 0.35), "mall_metal_vc", {"tint": Color(0.12, 0.13, 0.14), "paint": 1.0})
		# (r16) a third of them dead, a few flickering
		var st: int = [POWER_ON, POWER_DEAD, POWER_FAULTY, POWER_ON, POWER_DEAD, POWER_ON][li % 6]
		li += 1
		bx(Vector3(p.x, 6.48, p.y), Vector3(0.6, 0.02, 0.28), "mall_light" if st == POWER_ON else "mall_light_dead", {})
		if st != POWER_DEAD:
			mb.dyn.add_light({"pos": Vector3(p.x, 6.2, p.y), "kind": "lamp", "color": Color(1.0, 0.86, 0.66), "energy": 1.4, "range": 16.0, "outdoor": true,
				"emitter": st == POWER_FAULTY, "fault": "flicker" if st == POWER_FAULTY else "", "flicker": 0.6})


# ------------------------------------------------------------------ floors and ceilings

func _plan_mask(lv: int) -> Array:
	## Common floor (concourses, entrance halls) on a 0.5 m grid as greedy rectangles: the footprint inside the walls,
	## less every shop unit, core and restroom block, and the courts' bounding boxes (drawn separately).
	var cell := 0.5
	var x0: float = -L.MX + L.WALL_T
	var z0: float = -L.MZ + L.WALL_T
	var nx := int(round((L.MX - L.WALL_T) * 2.0 / cell))
	var nz := int(round((L.MZ - L.WALL_T) * 2.0 / cell))
	var m := PackedByteArray()
	m.resize(nx * nz)
	m.fill(1)
	var cut := func(r: Rect2) -> void:
		var ix0 := clampi(int(round((r.position.x - x0) / cell)), 0, nx)
		var ix1 := clampi(int(round((r.end.x - x0) / cell)), 0, nx)
		var iz0 := clampi(int(round((r.position.y - z0) / cell)), 0, nz)
		var iz1 := clampi(int(round((r.end.y - z0) / cell)), 0, nz)
		for iz in range(iz0, iz1):
			for ix in range(ix0, ix1):
				m[iz * nx + ix] = 0
	for u in L.units:
		if int(u.level) == lv:
			cut.call(u.rect)
	for r in L.CORES + L.RESTROOMS:
		cut.call(r)
	for r in court_boxes():
		cut.call(r)
	var rects: Array = []
	for iz in nz:
		var ix := 0
		while ix < nx:
			if m[iz * nx + ix] == 0:
				ix += 1
				continue
			var ix1 := ix
			while ix1 < nx and m[iz * nx + ix1] == 1:
				ix1 += 1
			var iz1 := iz + 1
			while iz1 < nz:
				var full := true
				for k in range(ix, ix1):
					if m[iz1 * nx + k] == 0:
						full = false
						break
				if not full:
					break
				iz1 += 1
			for zz in range(iz, iz1):
				for xx in range(ix, ix1):
					m[zz * nx + xx] = 0
			rects.append(Rect2(x0 + ix * cell, z0 + iz * cell, (ix1 - ix) * cell, (iz1 - iz) * cell))
			ix = ix1
	return rects


func court_boxes() -> Array:
	return [L.WEST_COURT, Rect2(L.GRAND_C - L.GRAND_R, L.GRAND_R * 2.0), Rect2(L.EAST_C - Vector2(L.EAST_R, L.EAST_R), Vector2(L.EAST_R, L.EAST_R) * 2.0)]


func _court_shape(i: int, n: int = 72) -> PackedVector2Array:
	## Court i's outline (counter-clockwise in x/z), sampled by direction from its centre, including the bounding box
	## corner directions so the ring pieces tile the box exactly.
	var out := PackedVector2Array()
	match i:
		0:
			var r: Rect2 = L.WEST_COURT
			var ch: float = L.WEST_CHAMFER
			out = PackedVector2Array([Vector2(r.position.x + ch, r.position.y), Vector2(r.end.x - ch, r.position.y), Vector2(r.end.x, r.position.y + ch),
				Vector2(r.end.x, r.end.y - ch), Vector2(r.end.x - ch, r.end.y), Vector2(r.position.x + ch, r.end.y), Vector2(r.position.x, r.end.y - ch),
				Vector2(r.position.x, r.position.y + ch)])
		_:
			var c: Vector2 = L.GRAND_C if i == 1 else L.EAST_C
			var rr: Vector2 = L.GRAND_R if i == 1 else Vector2(L.EAST_R, L.EAST_R)
			for k in n:
				var t := TAU * k / n
				out.append(c + Vector2(cos(t) * rr.x, sin(t) * rr.y))
	return out


func _court_ring(i: int) -> Array:
	## The floor between court i's outline and its bounding box, as quads [a, b, B, A] (outline edge a-b, box edge A-B).
	var box: Rect2 = court_boxes()[i]
	var c := box.get_center()
	var hw := box.size * 0.5
	var quads: Array = []
	if i == 0:
		var r: Rect2 = L.WEST_COURT
		var ch: float = L.WEST_CHAMFER
		for corner in [[r.position, Vector2(1, 0), Vector2(0, 1)], [Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
				[r.end, Vector2(-1, 0), Vector2(0, -1)], [Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)]]:
			var p: Vector2 = corner[0]
			quads.append([p, p + corner[1] * ch, p + corner[2] * ch, p])
		return quads
	var rr: Vector2 = L.GRAND_R if i == 1 else Vector2(L.EAST_R, L.EAST_R)
	var angs: Array = []
	for k in 72:
		angs.append(TAU * k / 72.0)
	for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		angs.append(fposmod(atan2(s.y * hw.y, s.x * hw.x), TAU))
	angs.sort()
	var pts_in: Array = []
	var pts_box: Array = []
	for a in angs:
		var d := Vector2(cos(a), sin(a))
		var re := 1.0 / sqrt(pow(d.x / rr.x, 2) + pow(d.y / rr.y, 2))
		pts_in.append(c + d * re)
		var tb := minf(hw.x / maxf(absf(d.x), 1e-6), hw.y / maxf(absf(d.y), 1e-6))
		pts_box.append(c + d * tb)
	for k in angs.size():
		var k2 := (k + 1) % angs.size()
		quads.append([pts_in[k], pts_in[k2], pts_box[k2], pts_box[k]])
	return quads


func _tongues(i: int) -> Array:
	## Court i's landing tongues (floor inside the court on every level) as convex polygons.
	var out: Array = []
	if i == 2:
		return out
	var cx := float(L.BANKS[0 if i == 0 else 1].cx)
	var x0 = cx - L.ESC_RUN * 0.5
	var x1 = cx + L.ESC_RUN * 0.5
	var hz: float = L.WELL_HZ
	if i == 0:
		var r: Rect2 = L.WEST_COURT
		out.append(PackedVector2Array([Vector2(r.position.x, -hz), Vector2(x0, -hz), Vector2(x0, hz), Vector2(r.position.x, hz)]))
		out.append(PackedVector2Array([Vector2(x1, -hz), Vector2(r.end.x, -hz), Vector2(r.end.x, hz), Vector2(x1, hz)]))
		return out
	var rr: Vector2 = L.GRAND_R
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		var xe = side * L.ESC_RUN * 0.5
		pts.append(Vector2(xe, -hz))
		for k in 9:
			var z := lerpf(-hz, hz, k / 8.0)
			pts.append(Vector2(side * rr.x * sqrt(1.0 - pow(z / rr.y, 2)), z))
		pts.append(Vector2(xe, hz))
		if side < 0.0:
			pts.reverse()
		out.append(pts)
	return out


func floor_mat(lv: int) -> String:
	return "mall_cream"


func _floors(lv: int) -> void:
	## Level lv's walking surface (with its collision): concourses, the court rings and tongues (Level 1: the court
	## floors themselves, in marble), shop floors (MallShops lays its own finish on the unit), cores (landings, see
	## _cores) and restrooms.
	var y: float = L.level_y(lv)
	var fo := {"collide": true, "layer": "ext", "dirt": 1.0}   # (r16) dirt tracked over every walk
	var finish_holes: Array = L.floor_repairs(lv)
	for inlay in L.floor_inlays():
		finish_holes.append(inlay[0])
	for r in _plan_mask(lv):
		for piece in minus_holes(r,finish_holes):
			hquad(piece,y,floor_mat(lv),true,fo)
	for i in 3:
		for q in _court_ring(i):
			hquad4(q, y, floor_mat(lv), true, fo)
		if lv == 0:
			var shape := _court_shape(i)
			hpoly(shape, y, ["mall_mosaic", "mall_atrium", "mall_geometric"][i], true, fo)
		else:
			for t in _tongues(i):
				hpoly(t, y, floor_mat(lv), true, fo)
	# Restrooms: their own tiles (the fixtures are in _restrooms).
	for r in L.RESTROOMS:
		hquad(r, y, "tiles_white", true, fo)
	# Borders and repair sections fill the cutouts via MallHorror._floor_design.


func _ceilings(lv: int) -> void:
	## The suspended ceiling of level lv (CEIL above its floor) under the next level's floor, white, with downlights
	## every 3 m over the concourses; the roof (Level 5) the same over everything but the courts. Shops and cores light
	## their own ceilings (MallShops / _cores).
	var y: float = L.level_y(lv) + L.CEIL
	var co := {"layer": "ext", "tint": WHITE, "paint": 1.0}
	# Over this level's own walks (the shops close their own ceilings): where a hall on Level 1 runs under a shop on
	# Level 2 (the entrances), the shop's floor is not a ceiling seen from below.
	for r in _plan_mask(lv):
		hquad(r, y, "mall_ceiling", false, co)
		var nx := maxi(int(r.size.x / 3.0), 1)
		var nz := maxi(int(r.size.y / 3.0), 1)
		for i in nx:
			for k in nz:
				downlight(lv, Vector3(r.position.x + (i + 0.5) * r.size.x / nx, y - 0.004, r.position.y + (k + 0.5) * r.size.y / nz))
		# black linear slots with a lit strip down the long walks (the reference's ceilings)
		if r.size.x > 8.0 and r.size.y >= 1.0:
			var zz = r.get_center().y
			if int(floor(zz)) % 6 == 0 or r.size.y < 2.5:
				bx(Vector3(r.get_center().x, y - 0.006, zz), Vector3(r.size.x - 0.6, 0.012, 0.16), "mall_black", {"layer": "mid"})
				# (r16) the lit strip in 6 m lengths, each lit or dead with the zone it is in
				var ns := maxi(int(round((r.size.x - 0.8) / 6.0)), 1)
				var sl = (r.size.x - 0.8) / ns
				for si in ns:
					var sx: float = r.position.x + 0.4 + (si + 0.5) * sl
					bx(Vector3(sx, y - 0.013, zz), Vector3(sl - 0.02, 0.004, 0.04), light_mat(lv, Vector2(sx, zz)), {"layer": "mid"})
	for i in 3:
		for q in _court_ring(i):
			hquad4(q, y, "mall_ceiling", false, co)
		if lv == L.LEVELS - 1:
			continue
		for t in _tongues(i):
			hpoly(t, y, "mall_ceiling", false, co)
			# a row of lights under each tongue (the escalators run beside them)
			var c := Vector2.ZERO
			for p in t:
				c += p
			c /= float(t.size())
			for k in [-1.6, 1.6]:
				downlight(lv, Vector3(c.x, y - 0.004, c.y + k))
	for r in L.RESTROOMS:
		hquad(r, y, "mall_ceiling", false, co)


# ------------------------------------------------------------------ court edges

func court_edges(lv: int) -> Array:
	## The open edges of level lv round the courts: [{a, b, n (into the void), kind: edge|end, x}] where "end" is a
	## landing tongue's end at the escalator well (closed only where no escalator lands there on this level).
	var out: Array = []
	var hz: float = L.WELL_HZ
	for i in 3:
		var shape := _court_shape(i, 72)
		var c := (court_boxes()[i] as Rect2).get_center()
		var pts: Array = []
		for p in shape:
			pts.append(p)
		for k in pts.size():
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[(k + 1) % pts.size()]
			var n := (((a + b) * 0.5) - c).normalized() * -1.0
			if i == 2:
				out.append({"a": a, "b": b, "n": n, "kind": "edge", "court": i})
				continue
			# where a tongue joins the outline (|z| < hz) there is floor on both sides: keep only the parts outside
			for piece in _clip_z(a, b, hz):
				out.append({"a": piece[0], "b": piece[1], "n": n, "kind": "edge", "court": i})
		if i < 2:
			var cx := float(L.BANKS[0 if i == 0 else 1].cx)
			var x0 = cx - L.ESC_RUN * 0.5
			var x1 = cx + L.ESC_RUN * 0.5
			var xo0: float
			var xo1: float
			if i == 0:
				xo0 = L.WEST_COURT.position.x
				xo1 = L.WEST_COURT.end.x
			else:
				xo0 = -L.GRAND_R.x * sqrt(1.0 - pow(hz / L.GRAND_R.y, 2))
				xo1 = -xo0
			for zs in [-1.0, 1.0]:
				out.append({"a": Vector2(xo0, zs * hz), "b": Vector2(x0, zs * hz), "n": Vector2(0, zs), "kind": "edge", "court": i})
				out.append({"a": Vector2(x1, zs * hz), "b": Vector2(xo1, zs * hz), "n": Vector2(0, zs), "kind": "edge", "court": i})
			out.append({"a": Vector2(x0, -hz), "b": Vector2(x0, hz), "n": Vector2(1, 0), "kind": "end", "x": x0, "court": i})
			out.append({"a": Vector2(x1, -hz), "b": Vector2(x1, hz), "n": Vector2(-1, 0), "kind": "end", "x": x1, "court": i})
	return out


static func _clip_z(a: Vector2, b: Vector2, hz: float) -> Array:
	## The parts of segment a-b with |z| >= hz.
	var out: Array = []
	var ts := [0.0, 1.0]
	for zz in [-hz, hz]:
		if (a.y - zz) * (b.y - zz) < 0.0:
			ts.append((zz - a.y) / (b.y - a.y))
	ts.sort()
	for k in ts.size() - 1:
		var t0: float = ts[k]
		var t1: float = ts[k + 1]
		if t1 - t0 < 1e-4:
			continue
		var m := a.lerp(b, (t0 + t1) * 0.5)
		if absf(m.y) >= hz:
			out.append([a.lerp(b, t0), a.lerp(b, t1)])
	return out


func lane_served(lv: int, x: float, lane: int, bank: String) -> bool:
	for e in L.escalators:
		if str(e.bank) != bank or int(e.lane) != lane:
			continue
		if int(e.t) == lv and absf((e.a as Vector3).x - x) < 0.1:
			return true
		if int(e.t) + 1 == lv and absf((e.b as Vector3).x - x) < 0.1:
			return true
	return false


func _court_edges(lv: int) -> void:
	## Every open edge of level lv: the slab edge clad in a white fascia (from the ceiling below to the floor), a soft
	## light line under it, and on top a balustrade - 1.1 m of plate glass between brushed steel posts, an oak
	## handrail and a blue kick strip. The glass shatters like the shopfronts.
	var y: float = L.level_y(lv)
	for e in court_edges(lv):
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var n: Vector2 = e.n
		var len := a.distance_to(b)
		if len < 0.05:
			continue
		var yaw := seg_yaw(a, b)
		var m := (a + b) * 0.5
		# fascia: a band 0.9 m deep, its face 0.06 m out over the void, its top just under the floor (no lip to trip on
		# at an escalator's comb plate)
		bxr(Vector3(m.x + n.x * 0.03, y - 0.453, m.y + n.y * 0.03), Vector3(len + 0.02, 0.9, 0.12), yaw, "mall_paint", {"tint": WHITE, "paint": 1.0,
			"collide": str(e.kind) != "end", "layer": "ext"})   # (the escalators' own ramps meet the floor at a tongue's end)
		# the light line under the fascia
		bxr(Vector3(m.x + n.x * 0.12, y - 0.87, m.y + n.y * 0.12), Vector3(len, 0.03, 0.05), yaw, light_mat(lv - 1, m), {"layer": "mid"})
		if str(e.kind) == "end":
			var bank: String = str(L.BANKS[int(e.court)].name)
			for lane in 4:
				if lane_served(lv, float(e.x), lane, bank):
					continue
				var z = (-1.5 + lane) * L.ESC_LANE
				_balustrade(lv, Vector2(a.x, z - L.ESC_LANE * 0.5), Vector2(a.x, z + L.ESC_LANE * 0.5), n)
			continue
		_balustrade(lv, a, b, n)


func _balustrade(lv: int, a: Vector2, b: Vector2, n: Vector2) -> void:
	var y: float = L.level_y(lv)
	var len := a.distance_to(b)
	var inset := 0.12
	var a2 := a - n * inset
	var b2 := b - n * inset
	var yaw := seg_yaw(a2, b2)
	var panels := maxi(int(ceil(len / 1.6)), 1)
	var dir := (b2 - a2) / len
	for k in panels:
		var p0 := a2 + dir * (len * k / panels)
		var p1 := a2 + dir * (len * (k + 1) / panels)
		var pm := (p0 + p1) * 0.5
		var pw := p0.distance_to(p1) - 0.07
		# glass panel (a breakable sheet)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pm.x, y + 0.62, pm.y))
		mb.dyn.add_window({"xf": xf, "w": pw, "h": 0.96, "type": "plate", "t": 0.02, "mat": "mall_glass", "bid": 0})
		# post
		S.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(p0.x, y + 0.55, p0.y)), Vector3(0.05, 1.1, 0.05), "mall_steel", o({"collide": true, "layer": "mid"}))
	S.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(b2.x, y + 0.55, b2.y)), Vector3(0.05, 1.1, 0.05), "mall_steel", o({"collide": true, "layer": "mid"}))
	var m := (a2 + b2) * 0.5
	# oak handrail and its steel channel, the blue kick strip at the foot
	bxr(Vector3(m.x, y + 1.11, m.y), Vector3(len + 0.04, 0.07, 0.11), yaw, "oak", {"collide": true, "layer": "mid"})
	bxr(Vector3(m.x, y + 1.06, m.y), Vector3(len, 0.03, 0.05), yaw, "mall_steel", {"layer": "mid"})
	bxr(Vector3(m.x, y + 0.07, m.y), Vector3(len, 0.14, 0.08), yaw, "mall_gloss", {"tint": BLUE_STRIP, "paint": 1.0, "collide": true, "layer": "mid"})
	L.block_seg(lv, a2, b2, 0.1, 0.35)


func _roof_edges() -> void:
	## Above Level 5 the courts rise to the roof: their edges carry a taller fascia up to the roof structure.
	var y: float = L.level_y(L.LEVELS - 1) + L.CEIL
	for e in court_edges(L.LEVELS - 1):
		if str(e.kind) == "end":
			continue
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var n: Vector2 = e.n
		var m := (a + b) * 0.5
		bxr(Vector3(m.x + n.x * 0.03, y + 0.6, m.y + n.y * 0.03), Vector3(a.distance_to(b) + 0.02, 1.2, 0.12), seg_yaw(a, b), "mall_paint", {"tint": WHITE, "paint": 1.0, "layer": "ext"})
	# the tongue ends at the top level: fascia across the escalator well ends
	for e in court_edges(L.LEVELS - 1):
		if str(e.kind) == "end":
			var a2: Vector2 = e.a
			var b2: Vector2 = e.b
			var m2 := (a2 + b2) * 0.5
			bxr(Vector3(m2.x, y + 0.6, m2.y), Vector3(0.12, 1.2, a2.distance_to(b2)), 0.0, "mall_paint", {"tint": WHITE, "paint": 1.0, "layer": "ext"})


func _columns() -> void:
	## Round columns, clad white, rising through every level round the East Court (the reference court's columns);
	## square ones at the Grand Atrium's diagonals and the West Court's corners, clad in pale stone.
	var top: float = L.level_y(L.LEVELS - 1) + L.CEIL
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p: Vector2 = L.EAST_C + Vector2(cos(a), sin(a)) * (L.EAST_R + 0.75)
		S.cylinder(Vector3(p.x, 0, p.y), Vector3.UP, top, 0.55, "mall_paint", o({"sides": 20, "collide": true, "tint": CREAM, "paint": 1.0}))
		for lv in L.LEVELS:
			L.block_rect(lv, p, Vector2(0.55, 0.55), 0.0, 0.3)
	for s in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var p2: Vector2 = Vector2(s.x * (L.GRAND_R.x * 0.78 + 1.6), s.y * (L.GRAND_R.y * 0.78 + 1.6))
		for lv in L.LEVELS:
			solid(lv, Vector3(p2.x, L.level_y(lv) + L.CEIL * 0.5, p2.y), Vector3(0.9, L.CEIL, 0.9), "mall_paint", {"layer": "ext", "tint": Color(0.94, 0.86, 0.82), "paint": 1.0})
			bx(Vector3(p2.x, L.level_y(lv) + 0.06, p2.y), Vector3(0.94, 0.12, 0.94), "mall_steel", {"layer": "mid"})
		var r: Rect2 = L.WEST_COURT
		var p3 := Vector2(r.get_center().x + s.x * (r.size.x * 0.5 + 1.2), r.get_center().y + s.y * (r.size.y * 0.5 - 1.5))
		for lv in L.LEVELS:
			solid(lv, Vector3(p3.x, L.level_y(lv) + L.CEIL * 0.5, p3.y), Vector3(0.8, L.CEIL, 0.8), "mall_paint", {"layer": "ext", "tint": Color(0.94, 0.86, 0.82), "paint": 1.0})
			bx(Vector3(p3.x, L.level_y(lv) + 0.06, p3.y), Vector3(0.84, 0.12, 0.84), "mall_steel", {"layer": "mid"})


# ------------------------------------------------------------------ shell, facade, entrances

func _shell() -> void:
	## The outer walls, ground to parapet, with the entrance openings on Level 1. Outside: pale cladding with dark
	## slab bands, a glazed band on each upper level (dark glass over the shop backs), the parapet and the name.
	var mx: float = L.MX
	var mz: float = L.MZ
	var t: float = L.WALL_T
	var top: float = L.level_y(L.LEVELS) + 1.6
	var door_hw := 4.0
	var hall: float = L.ENTRANCE_HZ
	for side in [-1.0, 1.0]:
		# North / south walls (opening x in [-6, 6] on Level 1 for the entrances)
		var z = side * (mz - t * 0.5)
		for seg in [[-mx, -6.0], [6.0, mx]]:
			_facade_wall(Vector2(seg[0], z), Vector2(seg[1], z), 0.0, top, t, Vector2(0, side))
		_facade_wall(Vector2(-6.0, z), Vector2(6.0, z), 3.5, top - 3.5, t, Vector2(0, side))
		# West / east walls (opening z in [-hall, hall] on Level 1)
		var x = side * (mx - t * 0.5)
		for seg2 in [[-mz, -hall], [hall, mz]]:
			_facade_wall(Vector2(x, seg2[0]), Vector2(x, seg2[1]), 0.0, top, t, Vector2(side, 0))
		_facade_wall(Vector2(x, -hall), Vector2(x, hall), 3.5, top - 3.5, t, Vector2(side, 0))
	# Roof slab and parapet cap
	for lv in L.LEVELS:
		for side2 in [-1.0, 1.0]:
			# dark slab band outside each floor line
			bx(Vector3(0, L.level_y(lv) - 0.15, side2 * (mz + 0.04)), Vector3(mx * 2.0 + 0.1, 0.55, 0.08), "mall_satin", {"tint": DARK, "paint": 1.0})
			bx(Vector3(side2 * (mx + 0.04), L.level_y(lv) - 0.15, 0), Vector3(0.08, 0.55, mz * 2.0 + 0.1), "mall_satin", {"tint": DARK, "paint": 1.0})
	for side3 in [-1.0, 1.0]:
		bx(Vector3(0, top + 0.08, side3 * (mz - t * 0.5)), Vector3(mx * 2.0 + 0.3, 0.16, t + 0.3), "mall_satin", {"tint": DARK, "paint": 1.0})
		bx(Vector3(side3 * (mx - t * 0.5), top + 0.08, 0), Vector3(t + 0.3, 0.16, mz * 2.0 + 0.3), "mall_satin", {"tint": DARK, "paint": 1.0})


func _facade_wall(a: Vector2, b: Vector2, y0: float, h: float, t: float, out: Vector2) -> void:
	## One run of outer wall: the structure (shared by every level it spans) and, on its outer face, glazed bands
	## between the slab lines from Level 2 up.
	var len := a.distance_to(b)
	if len < 0.05:
		return
	var yaw := seg_yaw(a, b)
	var m := (a + b) * 0.5
	S.box(Transform3D(Basis(Vector3.UP, yaw), Vector3(m.x, y0 + h * 0.5, m.y)), Vector3(len, h, t), "mall_paint", o({"collide": true, "tint": FACADE, "paint": 1.0, "layer": "ext", "occlude": true}))
	for lv in L.LEVELS:
		var gy0: float = L.level_y(lv) + 1.0
		if lv == 0 or gy0 < y0:
			continue
		var gh := 2.6
		var p := m + out * (t * 0.5 + 0.02)
		bxr(Vector3(p.x, gy0 + gh * 0.5, p.y), Vector3(len - 1.2, gh, 0.03), yaw, "mall_gloss", {"tint": Color(0.06, 0.08, 0.1), "paint": 1.0, "layer": "ext"})
		# mullions
		var nm := int(len / 2.4)
		var d := (b - a) / len
		for k in range(1, nm):
			var q := a + d * (len * k / nm) + out * (t * 0.5 + 0.05)
			bxr(Vector3(q.x, gy0 + gh * 0.5, q.y), Vector3(0.07, gh, 0.06), yaw, "mall_steel", {"layer": "mid"})
	for lv2 in L.LEVELS:
		if y0 <= L.level_y(lv2) + 0.5:
			L.block_seg(lv2, a, b, t, 0.3)


func _entrances() -> void:
	## The four Level 1 entrances: a glass wall of doors (two pairs) across each opening, a canopy outside, the name
	## over the main (south) entrance, mats, and the hall finishes inside.
	for e in L.entrances:
		var out: Vector2 = e.out
		var along := Vector2(-out.y, out.x)
		var hw := 4.0 if absf(out.x) > 0.5 else 6.0
		var wall_c: Vector2 = Vector2(out.x * (L.MX - L.WALL_T * 0.5), out.y * (L.MZ - L.WALL_T * 0.5)) + (Vector2(0, (e.c as Vector2).y) if absf(out.x) > 0.5 else Vector2((e.c as Vector2).x, 0))
		var yaw := seg_yaw(wall_c - along, wall_c + along)
		# glass entrance wall: fixed panes either side, two pairs of doors
		var doors_hw := 2.1
		for s in [-1.0, 1.0]:
			var pane_c = wall_c + along * s * (doors_hw + (hw - doors_hw) * 0.5)
			var pw := hw - doors_hw - 0.1
			mb.dyn.add_window({"xf": Transform3D(Basis(Vector3.UP, yaw), Vector3(pane_c.x, 1.65, pane_c.y)), "w": pw, "h": 3.2, "type": "plate", "t": 0.02, "mat": "mall_glass", "bid": 0})
			L.block_seg(0, pane_c - along * pw * 0.5, pane_c + along * pw * 0.5, 0.1, 0.3)
		# Doors: four leaves of 1.05 m across [-2.1, 2.1].
		for k in 4:
			var hx := -doors_hw + k * 1.05
			var hinge_left := k % 2 == 0
			var hp := wall_c + along * (hx if hinge_left else hx + 1.05)
			var dir := along if hinge_left else -along
			var bas := Basis(Vector3.UP, seg_yaw(Vector2.ZERO, dir))
			mb.dyn.add_door({"xf": Transform3D(bas, Vector3(hp.x, 0.0, hp.y)), "w": 1.03, "h": 2.6, "t": 0.025, "mat": "mall_glass", "glass": true,
				"outer": false, "bid": 0, "role": "mall_entrance", "clr": Vector2(1.2, 1.2)})
		# frame: head over the doors, mullions, pull handles
		bxr(Vector3(wall_c.x, 2.95, wall_c.y), Vector3(hw * 2.0, 0.7, 0.14), yaw, "mall_steel", {"collide": true, "layer": "mid"})
		bxr(Vector3(wall_c.x, 3.4, wall_c.y), Vector3(hw * 2.0, 0.2, 0.18), yaw, "mall_steel", {"collide": true, "layer": "mid"})
		for k2 in 5:
			var mp := wall_c + along * (-doors_hw + k2 * 1.05)
			bxr(Vector3(mp.x, 1.3, mp.y), Vector3(0.08, 2.6, 0.12), yaw, "mall_steel", {"layer": "mid"})
		# canopy outside: a steel and glass awning on two posts
		var cc := wall_c + out * 3.2
		bxr(Vector3(cc.x, 4.1, cc.y), Vector3(hw * 2.0 + 2.0, 0.12, 6.0), yaw, "mall_glass", {"layer": "ext"})
		for s2 in [-1.0, 1.0]:
			var pp = wall_c + out * 6.0 + along * s2 * (hw + 0.6)
			S.cylinder(Vector3(pp.x, 0, pp.y), Vector3.UP, 4.1, 0.12, "mall_steel", o({"sides": 12, "collide": true}))
			L.block_rect(0, pp, Vector2(0.12, 0.12), 0.0, 0.3)
			bxr(Vector3((wall_c + out * 3.2 + along * s2 * (hw + 0.6)).x, 4.0, (wall_c + out * 3.2 + along * s2 * (hw + 0.6)).y), Vector3(0.14, 0.18, 6.0), yaw, "mall_steel", {})
		bxr(Vector3((wall_c + out * 6.1).x, 4.0, (wall_c + out * 6.1).y), Vector3(hw * 2.0 + 2.0, 0.22, 0.16), yaw, "mall_steel", {})
		for k3 in 4:
			var lp := wall_c + out * (1.5 + k3 * 1.4)
			downlight(0, Vector3(lp.x, 4.03, lp.y))
		# entrance mat inside
		var mat_c := wall_c - out * 1.6
		var mr := Rect2(mat_c - Vector2(absf(along.x) * hw + absf(out.x) * 1.2, absf(along.y) * hw + absf(out.y) * 1.2),
			Vector2(absf(along.x) * hw + absf(out.x) * 1.2, absf(along.y) * hw + absf(out.y) * 1.2) * 2.0)
		hquad(mr, 0.004, "mall_cloth", true, {"tint": Color(0.18, 0.18, 0.2), "paint": 1.0, "layer": "mid"})
		# name over the doors, outside
		var sp = wall_c + out * (L.WALL_T * 0.5 + 0.03)
		S.atlas_quad(Vector3(sp.x, 4.9, sp.y), Vector3(out.y, 0, -out.x), Vector3.UP, 7.0, 1.75,
			sign_uv(_mall_sign_tile()), "mall_signs", {"layer": "ext"})
		# exit sign inside over the doors
		var xs := wall_c - out * 0.2
		S.atlas_quad(Vector3(xs.x, 3.75, xs.y), Vector3(-out.y, 0, out.x), Vector3.UP, 0.9, 0.45,
			Rect2(0.0, 0.0, 0.25, 0.25), "mall_wayfind", {"layer": "mid"})
	# The big name on the south facade, over the main entrance.
	S.atlas_quad(Vector3(0, 11.5, L.MZ + 0.05), Vector3(1, 0, 0), Vector3.UP, 22.0, 5.5, sign_uv(_mall_sign_tile()), "mall_signs", {"layer": "ext"})
	S.atlas_quad(Vector3(0, 11.5, -L.MZ - 0.05), Vector3(-1, 0, 0), Vector3.UP, 22.0, 5.5, sign_uv(_mall_sign_tile()), "mall_signs", {"layer": "ext"})


func _mall_sign_tile() -> int:
	for s in L.shops_catalog:
		if str(s.name) == "Malasugue Mall":
			return int(s.tile)
	return 0


# ------------------------------------------------------------------ fire stairs and restrooms

func _cores() -> void:
	## Four fire-stair cores, every level: concrete walls, a steel fire door to the concourse (it swings both ways),
	## landings, two flights per storey with steel handrails, painted floor numbers, green exit signs, emergency
	## lights. The stairs: a box per step for the eye, a smooth ramp under them for the feet (as in the houses).
	for ci in L.CORES.size():
		var r: Rect2 = L.CORES[ci]
		var inner_z: float = r.end.y if r.position.y < 0.0 else r.position.y
		var inward := signf(inner_z - (r.position.y if r.position.y < 0.0 else r.end.y))
		var cx := r.get_center().x
		for lv in L.LEVELS:
			var y: float = L.level_y(lv)
			var h: float = L.FH if lv < L.LEVELS - 1 else L.CEIL + 0.4
			# side walls and back (the outer wall is the shell)
			wall(lv, Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y), y, h, 0.25, "concrete", {"tint": Color(0.82, 0.82, 0.8), "paint": 0.9, "layer": "ext"})
			wall(lv, Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), y, h, 0.25, "concrete", {"tint": Color(0.82, 0.82, 0.8), "paint": 0.9, "layer": "ext"})
			# front wall with the fire door at its -x end
			var door_x0 := r.position.x + 0.45
			var door_w := 1.2
			wall(lv, Vector2(door_x0 + door_w, inner_z), Vector2(r.end.x, inner_z), y, h, 0.25, "concrete", {"tint": Color(0.82, 0.82, 0.8), "paint": 0.9, "layer": "ext"})
			wall(lv, Vector2(r.position.x, inner_z), Vector2(door_x0, inner_z), y, h, 0.25, "concrete", {"tint": Color(0.82, 0.82, 0.8), "paint": 0.9, "layer": "ext"})
			bx(Vector3(door_x0 + door_w * 0.5, y + 2.25 + (h - 2.25) * 0.5, inner_z), Vector3(door_w, h - 2.25, 0.25), "concrete", {"collide": true, "tint": Color(0.82, 0.82, 0.8), "paint": 0.9, "layer": "ext"})
			mb.dyn.add_door({"xf": Transform3D(Basis(), Vector3(door_x0, y, inner_z)), "w": door_w - 0.02, "h": 2.2, "t": 0.05, "mat": "metal_paint",
				"outer": false, "bid": 0, "role": "fire_door", "clr": Vector2(1.0, 1.0)})
			# the concourse side of the door: frame, push bar, sign
			var fz := inner_z + inward * 0.14
			S.atlas_quad(Vector3(door_x0 + door_w * 0.5, y + 2.55, fz), Vector3(inward, 0, 0), Vector3.UP, 0.8, 0.4, Rect2(0.25, 0.0, 0.25, 0.25), "mall_wayfind", {"layer": "mid"})
			# landings: the floor at this level by the door (out to where the flights start) and the half landing at
			# the back, both from the flights' own ends
			var f0: Dictionary = _core_flight(ci, mini(lv, L.LEVELS - 2), 0)
			var z_front: float = (f0.foot as Vector3).z
			var z_back: float = (f0.top as Vector3).z
			var outer_z: float = r.position.y if r.position.y < 0.0 else r.end.y
			var land_front := Rect2(r.position.x + 0.13, minf(inner_z, z_front), r.size.x - 0.26, absf(inner_z - z_front))
			hquad(land_front, y, "stair_concrete", true, {"collide": true})
			# the core's inside is closed to bots except this landing
			L.block_rect(lv, r.get_center(), r.size * 0.5, 0.0, 0.0)
			L.open_rect(lv, land_front.get_center(), land_front.size * 0.5 - Vector2(0.4, 0.3))
			if lv < L.LEVELS - 1:
				var my = y + L.FH * 0.5
				var mid_land := Rect2(r.position.x + 0.13, minf(z_back, outer_z), r.size.x - 0.26, absf(z_back - outer_z) - L.WALL_T * 0.5)
				if inward < 0.0:
					mid_land.position.y += L.WALL_T * 0.5
				bx(Vector3(mid_land.get_center().x, my - 0.12, mid_land.get_center().y), Vector3(mid_land.size.x, 0.24, mid_land.size.y), "stair_concrete", {"collide": true, "layer": "ext"})
				panel(lv, Vector3(cx, my + 2.3, mid_land.get_center().y), POWER_ON if h01(ci, lv, 31) > 0.4 else POWER_DEAD)
				var f1: Dictionary = _core_flight(ci, lv, 1)
				L.add_link(f0.foot + Vector3(0, 0, inward * 0.7), (f1.top as Vector3) + Vector3(0, 0, inward * 0.7),
					[f0.top - Vector3(0, 0, inward * 0.5), f1.foot - Vector3(0, 0, inward * 0.5)], 1.4, true)
			# (r16) the stairs on the emergency circuit: a cold panel by each door, some dead, some failing
			var cst := h01(ci, lv, 37)
			var cpos := Vector3(cx, y + 2.9, land_front.get_center().y)
			if cst < 0.3:
				panel(lv, cpos, POWER_DEAD)
			elif cst < 0.55:
				panel(lv, cpos, POWER_DEAD)
				mb.dyn.add_light({"pos": Vector3(cx, y + 2.6, inner_z - inward * 1.0), "kind": "tube", "axis": Vector3(1, 0, 0), "color": Color(0.8, 0.9, 1.0),
					"energy": 0.7, "range": 7.0, "fault": "starter" if cst < 0.45 else "dying", "fade": 26.0})
			else:
				panel(lv, cpos, POWER_ON)
				mb.dyn.add_light({"pos": Vector3(cx, y + 2.6, inner_z - inward * 1.0), "kind": "lamp", "color": Color(0.8, 0.9, 1.0), "energy": 0.6, "range": 7.0,
					"emitter": false, "fade": 26.0})
			# level number painted on the wall by the door
			S.atlas_quad(Vector3(r.end.x - 0.14, y + 1.7, inner_z - inward * 1.2), Vector3(0, 0, 1), Vector3.UP, 0.9, 0.45,
				Rect2((8 + lv) % 4 * 0.25, ((8 + lv) / 4) * 0.25, 0.25, 0.25), "mall_wayfind", {"layer": "int"})
			# the ceiling over the top level's core
			if lv == L.LEVELS - 1:
				hquad(Rect2(r.position.x, r.position.y, r.size.x, r.size.y), y + L.CEIL + 0.4, "concrete", false, {"tint": Color(0.82, 0.82, 0.8), "paint": 0.9})
	for f in L.flights:
		_flight(f)


func _flight(f: Dictionary) -> void:
	var foot: Vector3 = f.foot
	var top: Vector3 = f.top
	var w := float(f.w)
	var rise := top.y - foot.y
	var run := Vector2(top.x - foot.x, top.z - foot.z).length()
	var n := int(round(rise / L.STEP_RISE))
	var dz := signf(top.z - foot.z)
	var lv := int(f.level)
	for i in n:
		var sy := foot.y + (i + 1) * rise / n
		var sz := foot.z + dz * (i + 0.5) * run / n
		bx(Vector3(foot.x, sy - rise / n * 0.5, sz), Vector3(w, rise / n, run / n + 0.02), "stair_concrete", {"layer": "ext"})
		# yellow nosing strip
		bx(Vector3(foot.x, sy + 0.002, foot.z + dz * (i * run / n + 0.04)), Vector3(w - 0.1, 0.006, 0.05), "mall_flat", {"tint": Color(0.95, 0.75, 0.1), "paint": 1.0, "layer": "int"})
	# the ramp the feet use (invisible)
	var mid := (foot + top) * 0.5
	var ang := atan2(rise, run)
	var bas := Basis(Vector3.RIGHT, -ang * dz)   # the box's length (z) along the flight, rising toward its top
	S.col_box(Transform3D(bas, mid + Vector3(0, -0.12, 0)), Vector3(w, 0.2, sqrt(run * run + rise * rise)), "concrete", "stair_ramp")
	# the soffit under the flight
	S.box(Transform3D(bas, mid + Vector3(0, -0.32, 0)), Vector3(w, 0.18, sqrt(run * run + rise * rise)), "concrete", o({"tint": Color(0.8, 0.8, 0.78), "paint": 0.9, "layer": "ext"}))
	# handrails on both sides
	for s in [-1.0, 1.0]:
		var hx = foot.x + s * (w * 0.5 - 0.04)
		S.box(Transform3D(bas, Vector3(hx, mid.y + 0.9, mid.z)), Vector3(0.05, 0.05, sqrt(run * run + rise * rise)), "mall_steel", o({"layer": "int"}))
	mb.stairs.append({"foot": foot, "top": top})


func _core_flight(ci: int, lv: int, half: int) -> Dictionary:
	for f in L.flights:
		if int(f.core) == ci and int(f.level) == lv and int(f.half) == half:
			return f
	return {}


func _restrooms() -> void:
	## Two restroom blocks per level (by the north-west and south-east cores): a lobby with a mirror wall and basins,
	## ladies' and gents' sides behind a partition, cubicles. The walls are tiled, the lights square panels.
	## (r16) The fittings and the state they were left in: MallRestrooms.
	MallRestrooms.new(self).blocks()


# ------------------------------------------------------------------ the roof over the courts

func _roof() -> void:
	## The roof slab (over Level 5's ceiling) and what closes each court at the top: the Grand Atrium's navy ceiling
	## of white discs and spotlights (the reference mall's), a glazed barrel vault over the West Court and a glass dome
	## over the East Court.
	var ry: float = L.level_y(L.LEVELS - 1) + L.FH
	for r in _plan_mask(L.LEVELS - 1):
		hquad(r, ry + 0.4, "concrete_panels", true, {"collide": true, "tile": 4.0})
	for i in 3:
		for q in _court_ring(i):
			hquad4(q, ry + 0.4, "concrete_panels", true, {"collide": true})
		for t in _tongues(i):
			hpoly(t, ry + 0.4, "concrete_panels", true, {"collide": true})
	for r2 in L.CORES + L.RESTROOMS:
		hquad(r2, ry + 0.4, "concrete_panels", true, {"collide": true})
	# Grand Atrium: a flat navy ceiling 2 m above the roof line, white discs on it (MallDecor builds the discs).
	var gy := ry + 1.6
	var gb: Rect2 = court_boxes()[1]
	hquad(gb.grow(0.5), gy, "mall_satin", false, {"tint": NAVY, "paint": 1.0, "layer": "ext"})
	hquad(gb.grow(0.5), gy + 0.3, "concrete_panels", true, {"collide": true})
	for e in court_edges(L.LEVELS - 1):
		if int(e.court) == 1 and str(e.kind) == "edge":
			var a: Vector2 = e.a
			var b: Vector2 = e.b
			var m := (a + b) * 0.5
			bxr(Vector3(m.x, ry + 0.9, m.y), Vector3(a.distance_to(b) + 0.03, 1.4, 0.15), seg_yaw(a, b), "mall_satin", {"tint": NAVY, "paint": 1.0, "layer": "ext"})
	# West Court: glazed barrel vault on steel ribs.
	var w: Rect2 = L.WEST_COURT
	var ribs := 9
	for k in ribs + 1:
		var x := w.position.x + w.size.x * k / ribs
		for j in 12:
			var a0 := PI * j / 12.0
			var a1 := PI * (j + 1) / 12.0
			var r0 := w.size.y * 0.5
			var p0 := Vector3(x, ry + 0.4 + sin(a0) * 4.0, -cos(a0) * r0)
			var p1 := Vector3(x, ry + 0.4 + sin(a1) * 4.0, -cos(a1) * r0)
			S.box(Transform3D(Basis.looking_at((p1 - p0).normalized(), Vector3.RIGHT if absf((p1 - p0).normalized().dot(Vector3.RIGHT)) < 0.9 else Vector3.UP), (p0 + p1) * 0.5),
				Vector3(0.12, 0.2, p0.distance_to(p1)), "mall_metal_vc", o({"tint": Color(0.9, 0.9, 0.9), "paint": 1.0, "layer": "ext"}))
	for j2 in 12:
		var a2 := PI * j2 / 12.0
		var a3 := PI * (j2 + 1) / 12.0
		var r1 := w.size.y * 0.5
		var q0 := Vector3(w.position.x, ry + 0.4 + sin(a2) * 4.0, -cos(a2) * r1)
		var q1 := Vector3(w.position.x, ry + 0.4 + sin(a3) * 4.0, -cos(a3) * r1)
		S.quad(q0, q0 + Vector3(w.size.x, 0, 0), q1 + Vector3(w.size.x, 0, 0), q1, "mall_glass", o({"double": true, "collide": true, "layer": "ext"}))
	# East Court: a glass dome on a ring beam.
	var ec: Vector2 = L.EAST_C
	var er: float = L.EAST_R + 0.5
	var segs := 24
	for k2 in segs:
		var t0 := TAU * k2 / segs
		var t1 := TAU * (k2 + 1) / segs
		for j3 in 5:
			var e0 := PI * 0.5 * j3 / 5.0
			var e1 := PI * 0.5 * (j3 + 1) / 5.0
			var pa := Vector3(ec.x + cos(t0) * cos(e0) * er, ry + 0.4 + sin(e0) * 5.0, ec.y + sin(t0) * cos(e0) * er)
			var pb := Vector3(ec.x + cos(t1) * cos(e0) * er, ry + 0.4 + sin(e0) * 5.0, ec.y + sin(t1) * cos(e0) * er)
			var pc := Vector3(ec.x + cos(t1) * cos(e1) * er, ry + 0.4 + sin(e1) * 5.0, ec.y + sin(t1) * cos(e1) * er)
			var pd := Vector3(ec.x + cos(t0) * cos(e1) * er, ry + 0.4 + sin(e1) * 5.0, ec.y + sin(t0) * cos(e1) * er)
			S.quad(pa, pb, pc, pd, "mall_glass", o({"double": true, "collide": true, "layer": "ext"}))
			S.box(Transform3D(Basis.looking_at((pd - pa).normalized(), Vector3.UP if absf((pd - pa).normalized().y) < 0.95 else Vector3.RIGHT), (pa + pd) * 0.5),
				Vector3(0.1, 0.1, pa.distance_to(pd)), "mall_metal_vc", o({"tint": Color(0.92, 0.92, 0.92), "paint": 1.0, "layer": "ext"}))
	S.cylinder(Vector3(ec.x, ry + 0.2, ec.y), Vector3.UP, 0.4, er + 0.2, "mall_paint", o({"sides": 32, "tint": WHITE, "paint": 1.0}))


# ------------------------------------------------------------------ emitters

func _emitters() -> void:
	## Every ceiling downlight as one MultiMesh per level (a draw call each), and the square panels likewise.
	var disc := CylinderMesh.new()
	disc.top_radius = 0.085
	disc.bottom_radius = 0.085
	disc.height = 0.012
	disc.radial_segments = 12
	disc.rings = 1
	disc.material = mb.mats.get_material("mall_light")
	var ring := CylinderMesh.new()
	ring.top_radius = 0.11
	ring.bottom_radius = 0.11
	ring.height = 0.008
	ring.radial_segments = 12
	ring.rings = 1
	ring.material = mb.mats.get_material("mall_chrome")
	var panel_m := BoxMesh.new()
	panel_m.size = Vector3(0.6, 0.015, 0.6)
	panel_m.material = mb.mats.get_material("mall_light")
	# (r16) the same fittings with no power
	var disc_dead: CylinderMesh = disc.duplicate()
	disc_dead.material = mb.mats.get_material("mall_light_dead")
	var panel_dead: BoxMesh = panel_m.duplicate()
	panel_dead.material = mb.mats.get_material("mall_light_dead")
	var n := 0
	for lv in L.LEVELS:
		var lit := []
		var dead := []
		var rings := []
		for d in downlights[lv]:
			if int(d[1]) == POWER_LAMP:
				continue
			(lit if int(d[1]) == POWER_ON else dead).append(d[0])
			rings.append(d[0])
		var p_lit := []
		var p_dead := []
		for q in light_panels[lv]:
			if int(q[1]) != POWER_LAMP:
				(p_lit if int(q[1]) == POWER_ON else p_dead).append(q[0])
		for pair in [[disc, lit, 120.0], [disc_dead, dead, 90.0], [ring, rings, 70.0], [panel_m, p_lit, 80.0], [panel_dead, p_dead, 60.0]]:
			var xs: Array = pair[1]
			if xs.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pair[0]
			mm.instance_count = xs.size()
			for i in xs.size():
				var x: Transform3D = xs[i]
				if pair[0] == ring:
					x.origin.y += 0.006
				mm.set_instance_transform(i, x)
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = float(pair[2])
			mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			mi.name = "MallEmitters_L%d_%d" % [lv + 1, n]
			mb.root.add_child(mi)
			n += 1
		stats["downlights_L%d" % (lv + 1)] = "%d lit / %d dead" % [lit.size(), dead.size()]
