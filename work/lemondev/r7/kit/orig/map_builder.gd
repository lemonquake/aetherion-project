extends RefCounted
## Builds Sitio Kalinaw from the layout: terrain, water, roads, the railway, bridges, every district of shanties,
## special sites, night lighting and the acoustic model. Also the runtime facade the World talks to.

const Layout := preload("res://src/world/layout.gd")
const Materials := preload("res://src/world/materials.gd")
const GeoSink := preload("res://src/world/geo_sink.gd")
const Shanty := preload("res://src/world/shanty.gd")
const ModelLib := preload("res://src/world/model_lib.gd")
const Dynamics := preload("res://src/world/dynamics.gd")
const Acoustics := preload("res://src/audio/acoustics.gd")
const Districts := preload("res://src/world/districts.gd")
const Sites := preload("res://src/world/sites.gd")
const Dresser := preload("res://src/world/dresser.gd")
const Lighting := preload("res://src/world/lighting.gd")
const StreetDress := preload("res://src/world/street_dress.gd")
const PracticalLights := preload("res://src/world/practical_lights.gd")
const Entrances := preload("res://src/world/entrances.gd")
const ViewLod := preload("res://src/world/view_lod.gd")
const Lagusan := preload("res://src/world/lagusan.gd")
const Looban := preload("res://src/world/looban.gd")
const Vandal := preload("res://src/world/vandal.gd")
const PaSystem := preload("res://src/world/pa_system.gd")

const GROUND_SHADER := preload("res://src/world/ground.gdshader")
const WATER_SHADER := preload("res://src/world/water.gdshader")
const TEX := "res://assets/thirdparty/polyhaven/textures/"

var layout = null
var mats = null
var models = null
var sink = null
var dyn = null
var acoustics = null
var dresser = null
var lighting = null
var practical = null
var view_lod = null
var match_seed := 0
var root: Node3D
var world = null
var buildings: Array = []
## Every room the shanty builder made (type, xf at floor centre, size, h, bid, zone); used by tests and bots.
var rooms: Array = []
var stairs: Array = []  # [{foot, top}] every indoor stair flight
var alleys: Array = []  # [{a: Vector2, b: Vector2, w: float, kind}] walkable lanes between houses
var tunnels: Array = []   # [{a, b, w, kind: lane|walk, y?, house_side?}] lanes and walks roofed over (lagusan.gd)
var loobans: Array = []   # [{c, half, ang}] open courtyards left in dense blocks (looban.gd)
var barricades: Array = []  # [{c, along, w}] junk walls across lanes
var yard_walls: Array = []  # [{c, along, len}] low front walls in the mixed district
var ladders: Array = []   # [{base, top_y, n, w}] climbable (Ladder in the movement code)
var vandal_spots: Array = []  # [{pos, n, kind}] extra places that want a decal (barricades)
var vault_spots: Array = []   # [{pos (top centre), size, yaw}] crates built to vault on to (looban.gd)
var cover = null          # Lagusan: which ground is roofed over
var pole_tops: Array = []   # [[top: Vector3, along: Vector2]] street utility poles (pa_system.gd picks some)
var pa_speakers: Array = [] # [{pos, along}] loudspeaker horns the announcer talks through
var _ladder_grid := {}    # Vector2i (4 m) -> [ladder index]
var stats := {}
var map_image: Image
var _next_bid := 1


func build(world_node: Node3D, map_seed: int, match_seed: int, opts: Dictionary = {}) -> void:
	world = world_node
	root = Node3D.new()
	root.name = "Map"
	world_node.add_child(root)
	var t0 := Time.get_ticks_msec()
	layout = Layout.new(map_seed)
	stats.layout_ms = Time.get_ticks_msec() - t0
	mats = Materials.new()
	models = ModelLib.new(mats)
	acoustics = Acoustics.new()
	sink = GeoSink.new(mats, root, map_seed)
	# The map scan names what it bumps into from the collision boxes as they were made (test runs only).
	sink.record = str(Game.arg("autotest", "")) == "mapscan" or opts.get("record", false)
	dyn = Dynamics.new(self, world_node, root, mats, models, map_seed, match_seed)
	# Bodies and render instances made directly on the servers (ground items, dormant props, glass, open box lids)
	# are freed before the map leaves the tree: on teardown and when the game quits.
	root.tree_exiting.connect(dyn.dispose)
	dresser = Dresser.new(self)
	lighting = Lighting.new(self)
	self.match_seed = match_seed
	practical = PracticalLights.new(self, match_seed)
	t0 = Time.get_ticks_msec()
	_terrain()
	_water()
	stats.terrain_ms = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_roads()
	_railway()
	var sites := Sites.new(self)
	sites.build_all()
	var bridges_t := Time.get_ticks_msec()
	sites.build_crossings()
	var districts := Districts.new(self)
	if opts.get("districts", true):
		districts.build_all(opts.get("only", []))
	# Water drums by the doors: now every house of the districts stands, so none ends up in a doorway across the lane.
	dyn.place_deferred()
	cover = Lagusan.new(self)
	cover.build()
	stats.tunnels = cover.stats
	var lb := Looban.new(self)
	lb.build()
	stats.looban = lb.stats
	var ent := Entrances.new(self)
	ent.build()
	stats.entrances = ent.stats
	if opts.get("dress", true):
		StreetDress.new(self).build()
		PaSystem.new(self).build()
		practical.porch_lights()
		var vd := Vandal.new(self)
		vd.build()
		stats.decals = vd.stats
	_index_ladders()
	stats.ladders = ladders.size()
	if DisplayServer.get_name() != "headless":
		_paint_lanes()
	stats.lights = practical.stats
	stats.towns_ms = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	sink.finish()
	dyn.instantiate()
	stats.finish_ms = Time.get_ticks_msec() - t0
	lighting.build(world_node)
	view_lod = ViewLod.new(self)
	stats.buildings = buildings.size()
	stats.sink = sink.stats
	stats.doors = dyn.doors.size()
	stats.windows = dyn.windows.size()
	stats.props = dyn.props.size()
	stats.zones = acoustics.zones.size()
	stats.containers = dyn.containers.size()
	fingerprint = _fingerprint()
	dyn.randomize_for_match(world_node.get("is_server") == true)
	_make_map_image()


var fingerprint := ""
var ground_mat: ShaderMaterial
var ground_splat: Image


func _paint_lanes() -> void:
	## Once the districts exist: lanes and courtyards are trodden hard (the splat map's path channel), and the open
	## ground between them breaks into weeds and mud, so the settlement reads from the air as lanes and yards rather
	## than one sheet of dirt.
	if ground_mat == null or ground_splat == null:
		return
	var img := ground_splat
	var size := img.get_width()
	var half: float = layout.HALF
	var s := size / (half * 2.0)
	var nz := FastNoiseLite.new()
	nz.seed = layout.rng.seed + 77
	nz.frequency = 0.04
	for iz in size:
		for ix in size:
			var c := img.get_pixel(ix, iz)
			if c.b < 0.5 and c.r < 0.6:
				var x := -half + (ix + 0.5) / s
				var z := -half + (iz + 0.5) / s
				var n := nz.get_noise_2d(x, z)
				c.g = clampf(c.g + n * 0.45, 0.0, 1.0)
				c.r = clampf(c.r + maxf(-n - 0.25, 0.0) * 0.8, 0.0, 1.0)
				img.set_pixel(ix, iz, c)
	for a in alleys:
		var pa: Vector2 = a.a
		var pb: Vector2 = a.b
		var hw := float(a.w) * 0.5 * s + 0.5
		var n2 := int(pa.distance_to(pb) * s) + 1
		for k in n2 + 1:
			var p := pa.lerp(pb, float(k) / n2)
			var cx := int((p.x + half) * s)
			var cz := int((p.y + half) * s)
			var r := int(ceil(hw))
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					var px := cx + dx
					var pz := cz + dz
					if px < 0 or pz < 0 or px >= size or pz >= size or dx * dx + dz * dz > hw * hw:
						continue
					var c2 := img.get_pixel(px, pz)
					c2.a = 0.85
					c2.g *= 0.3
					img.set_pixel(px, pz, c2)
	ground_mat.set_shader_parameter("splat", ImageTexture.create_from_image(img))


func _fingerprint() -> String:
	## Every machine builds the map from the seed, so all must agree: doors, containers and props are referred to by
	## index. Counts plus a checksum of positions in whole centimetres. A phone (ARM, its own maths library) that came
	## down the other side of one comparison would place a house differently and shift every index after it.
	var h := 0
	for b in buildings:
		h = hash([h, Vector3i(((b.xf as Transform3D).origin * 100.0).round())])
	for d in dyn.doors:
		h = hash([h, Vector3i(((d.xf as Transform3D).origin * 100.0).round())])
	for c in dyn.containers:
		h = hash([h, Vector3i(((c.pos as Vector3) * 100.0).round())])
	for p in dyn.props:
		h = hash([h, Vector3i(((p.xf as Transform3D).origin * 100.0).round())])
	return "%d buildings, %d doors, %d containers, %d props, #%08x" % [buildings.size(), dyn.doors.size(), dyn.containers.size(), dyn.props.size(), h & 0xFFFFFFFF]


func warm_up(parent: Node3D) -> void:
	## Draws every material and model the map uses once, in front of a camera of its own, while the loading screen is
	## up: their shaders compile now instead of the first time each comes into view (a 100-380 ms stall on phones).
	var holder := Node3D.new()
	holder.name = "Warmup"
	parent.add_child(holder)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 400, 0)
	cam.near = 0.05
	holder.add_child(cam)
	cam.current = true
	var items := []
	for m in mats._cache.values():
		if m is Material:
			var q := QuadMesh.new()
			q.size = Vector2(0.2, 0.2)
			q.material = m
			items.append(q)
	for md in models._cache.values():
		if md is Dictionary and md.get("mesh") is Mesh:
			items.append(md.mesh)
	for m2 in lighting._mats.values():
		var s := SphereMesh.new()
		s.radius = 0.05
		s.height = 0.1
		s.material = m2
		items.append(s)
	var cols := 24
	for i in items.size():
		var mi := MeshInstance3D.new()
		mi.mesh = items[i]
		var x := (i % cols - cols * 0.5) * 0.25
		var y := (i / cols - 6) * 0.25
		mi.position = Vector3(x, 400.0 + y, -6.0)
		var aabb: AABB = (items[i] as Mesh).get_aabb()
		var sz := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		if sz > 0.2:
			mi.scale = Vector3.ONE * (0.2 / sz)
		mi.layers = Defs.RENDER_INTERIOR | 1
		holder.add_child(mi)
	for f in 4:
		await parent.get_tree().process_frame
	if is_instance_valid(holder):
		cam.current = false
		holder.queue_free()
	stats.warmed = items.size()


func _index_ladders() -> void:
	_ladder_grid.clear()
	for i in ladders.size():
		var b: Vector3 = ladders[i].base
		var k := Vector2i(floori(b.x / 4.0), floori(b.z / 4.0))
		if not _ladder_grid.has(k):
			_ladder_grid[k] = []
		_ladder_grid[k].append(i)


func ladders_near(p: Vector3) -> Array:
	## Ladders whose foot is within ~4 m (horizontally) of p.
	var out := []
	var k := Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for i in _ladder_grid.get(k + Vector2i(dx, dz), []):
				out.append(ladders[i])
	return out


func new_building_id() -> int:
	_next_bid += 1
	return _next_bid


func shanty(spec: Dictionary) -> Dictionary:
	spec.id = new_building_id()
	var ctx := {"sink": sink, "mats": mats, "acoustics": acoustics, "dyn": dyn}
	var s := Shanty.new(ctx)
	var out := s.build(spec)
	stairs.append_array(s.flights)
	ladders.append_array(s.ladders)
	buildings.append({"id": spec.id, "xf": spec.xf, "w": spec.w, "d": spec.d, "kind": spec.get("kind", "house"), "district": spec.get("district", ""),
		"style": spec.get("style", "wood"), "floors": spec.get("floors", 1), "covered": spec.get("covered", false), "deck": out.get("deck", false),
		"top": out.top, "front_open": out.get("front_open", []), "h0": out.get("h0", 2.4)})
	var body := {"chb": Color(0.3, 0.29, 0.27), "concrete": Color(0.42, 0.42, 0.4), "wood": Color(0.22, 0.17, 0.12),
		"yero": Color(0.26, 0.18, 0.13), "bamboo": Color(0.3, 0.26, 0.17), "patch": Color(0.25, 0.2, 0.16)}.get(str(spec.get("style", "wood")), Color(0.25, 0.2, 0.15))
	var roof := Color(0.22, 0.14, 0.1) if sink.rng.randf() < 0.6 else Color(0.3, 0.3, 0.3)
	var top: float = out.top + 0.4
	var fx: Transform3D = spec.xf
	sink.far_block(fx * Transform3D(Basis(), Vector3(0, top * 0.5, 0)), Vector3(float(spec.w) + 0.6, top, float(spec.d) + 0.6), body, roof)
	for r in out.rooms:
		dresser.dress_room(r, spec)
	rooms.append_array(out.rooms)
	practical.house(spec, out.rooms)
	return out


# ------------------------------------------------------------------ terrain

func ground_height(x: float, z: float) -> float:
	return layout.ground_height(x, z)


func water_height(x: float, z: float) -> float:
	return layout.water_height(x, z)


func _terrain() -> void:
	var half: float = layout.HALF
	var step := 2.0
	var n := int(half * 2.0 / step) + 1
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for iz in n:
		var z := -half + iz * step
		for ix in n:
			heights[iz * n + ix] = layout.ground_height(-half + ix * step, z)
	# Collision: one heightfield, 2 m spacing.
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.collision_layer = Defs.PHYS_WORLD
	body.collision_mask = 0
	body.set_meta("mat", "dirt")
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(step, 1.0, step)
	body.add_child(cs)
	root.add_child(body)
	# Visual: 64 m chunks.
	var splat := _splat_map()
	var mat := ShaderMaterial.new()
	ground_mat = mat
	ground_splat = splat
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("splat", ImageTexture.create_from_image(splat))
	mat.set_shader_parameter("splat_origin", Vector2(-half, -half))
	mat.set_shader_parameter("splat_size", half * 2.0)
	for pair in [["dirt", "dirt_floor"], ["mud", "brown_mud_02"], ["grass", "sparse_grass"], ["sand", "coast_sand_01"], ["path", "stony_dirt_path"]]:
		mat.set_shader_parameter(pair[0] + "_alb", _tex(TEX + pair[1] + "/albedo.jpg"))
		mat.set_shader_parameter(pair[0] + "_nrm", _tex(TEX + pair[1] + "/normal.jpg"))
	mat.set_shader_parameter("water_y", layout.WATER_Y)
	mat.set_shader_parameter("noise_tex", Materials.NOISE)
	var chunk := 32  # quads per chunk side
	var tr := Node3D.new()
	tr.name = "TerrainMesh"
	root.add_child(tr)
	for cz in range(0, n - 1, chunk):
		for cx in range(0, n - 1, chunk):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var x1 := mini(cx + chunk, n - 1)
			var z1 := mini(cz + chunk, n - 1)
			var w := x1 - cx + 1
			for iz in range(cz, z1 + 1):
				for ix in range(cx, x1 + 1):
					var h := heights[iz * n + ix]
					var hl := heights[iz * n + maxi(ix - 1, 0)]
					var hr := heights[iz * n + mini(ix + 1, n - 1)]
					var hd := heights[maxi(iz - 1, 0) * n + ix]
					var hu := heights[mini(iz + 1, n - 1) * n + ix]
					st.set_normal(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
					st.set_uv(Vector2(ix, iz))
					st.add_vertex(Vector3(-half + ix * step, h, -half + iz * step))
			for iz in range(0, z1 - cz):
				for ix in range(0, x1 - cx):
					var a := iz * w + ix
					st.add_index(a)
					st.add_index(a + 1)
					st.add_index(a + w)
					st.add_index(a + 1)
					st.add_index(a + w + 1)
					st.add_index(a + w)
			st.generate_tangents()
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.visibility_range_end = 900.0
			# Gentle ground under a moon 20 degrees up: its self-shadowing is not worth a pass per cascade.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tr.add_child(mi)
	# Skirts beyond the map edge (north, west, east) so the land does not end in a cliff; the bay fills the south.
	var skirt_mat := StandardMaterial3D.new()
	skirt_mat.albedo_color = Color(0.09, 0.1, 0.07)
	skirt_mat.roughness = 1.0
	var cz_w: float = layout.coast_z(-half) - 20.0
	var cz_e: float = layout.coast_z(half) - 20.0
	for spec in [[Vector3(0, 0, -half - 1500.0), Vector2(6200, 3000)], [Vector3(-half - 1500.0, 0, (-half + cz_w) * 0.5), Vector2(3000, cz_w + half)],
			[Vector3(half + 1500.0, 0, (-half + cz_e) * 0.5), Vector2(3000, cz_e + half)]]:
		var pm := PlaneMesh.new()
		pm.size = spec[1]
		var smi := MeshInstance3D.new()
		smi.mesh = pm
		smi.position = (spec[0] as Vector3) + Vector3(0, layout.LAND_Y - 0.05, 0)
		smi.material_override = skirt_mat
		tr.add_child(smi)


func _splat_map() -> Image:
	var size := 560
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half: float = layout.HALF
	for iz in size:
		var z := -half + (iz + 0.5) * half * 2.0 / size
		for ix in size:
			var x := -half + (ix + 0.5) * half * 2.0 / size
			var h: float = layout.ground_height(x, z)
			var mud := clampf(1.0 - (h - layout.WATER_Y) / 1.4, 0.0, 1.0)
			var sand := 0.0
			var cz: float = layout.coast_z(x)
			if z > cz - 40.0:
				sand = clampf((z - (cz - 40.0)) / 22.0, 0.0, 1.0)
			var grass := 0.35
			# Inhabited districts are trampled bare; the fields and the far east are grassy.
			var k: float = layout.MAP_SCALE
			if absf(x) > 430.0 * k or z < -480.0 * k or (x > 230.0 * k and z < -260.0 * k):
				grass = 0.85
			if Vector2(x, z).distance_to(layout.dump_c) < layout.dump_r:
				grass = 0.05
				mud = maxf(mud, 0.4)
			img.set_pixel(ix, iz, Color(mud, grass * (1.0 - mud), sand, 0.0))
	return img


func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


# ------------------------------------------------------------------ water

func _water() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	nt.noise = noise
	nt.generate_mipmaps = true
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("normal_tex", nt)
	mat.set_shader_parameter("noise_tex", Materials.NOISE)
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = WATER_SHADER
	sea_mat.set_shader_parameter("sea", 1.0)
	sea_mat.set_shader_parameter("deep_color", Color(0.02, 0.03, 0.04))
	sea_mat.set_shader_parameter("normal_tex", nt)
	sea_mat.set_shader_parameter("noise_tex", Materials.NOISE)
	# One plane over the whole map at water level: terrain above it hides it on land.
	var half: float = layout.HALF
	var wr := Node3D.new()
	wr.name = "Water"
	root.add_child(wr)
	for cz in range(-6, 6):
		for cx in range(-6, 6):
			var x0 := cx * 96.0
			var z0 := cz * 96.0
			# Skip tiles with no water at all.
			var any := false
			for sx in 9:
				for sz in 9:
					if layout.is_water(x0 + sx * 12.0, z0 + sz * 12.0):
						any = true
			if not any:
				continue
			var pm := PlaneMesh.new()
			pm.size = Vector2(96, 96)
			pm.subdivide_width = 16
			pm.subdivide_depth = 16
			var mi := MeshInstance3D.new()
			mi.mesh = pm
			mi.position = Vector3(x0 + 48.0, layout.WATER_Y, z0 + 48.0)
			var is_sea: bool = z0 + 48.0 > layout.coast_z(x0 + 48.0) - 30.0
			mi.material_override = sea_mat if is_sea else mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wr.add_child(mi)
	# Far sea beyond the map edge.
	var far := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(4000, 1600)
	far.mesh = fp
	far.position = Vector3(0, layout.WATER_Y - 0.02, half + 600.0)
	far.material_override = sea_mat
	wr.add_child(far)


# ------------------------------------------------------------------ roads and railway

func _roads() -> void:
	for r in layout.roads:
		var pts: PackedVector2Array = r.pts
		var w := float(r.w)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := b - a
			var len := seg.length()
			var dir := seg / len
			var steps := maxi(int(len / 6.0), 1)
			for k in steps:
				var p0 := a + dir * (len * k / steps)
				var p1 := a + dir * (len * (k + 1) / steps)
				var mid := (p0 + p1) * 0.5
				if layout.is_water(mid.x, mid.y):
					continue  # bridges are built separately
				var h0 := maxf(layout.ground_height(p0.x, p0.y), layout.WATER_Y + 1.2)
				var h1 := maxf(layout.ground_height(p1.x, p1.y), layout.WATER_Y + 1.2)
				var nrm := Vector2(-dir.y, dir.x) * w * 0.5
				var q0 := Vector3(p0.x - nrm.x, h0 + 0.06, p0.y - nrm.y)
				var q1 := Vector3(p1.x - nrm.x, h1 + 0.06, p1.y - nrm.y)
				var q2 := Vector3(p1.x + nrm.x, h1 + 0.06, p1.y + nrm.y)
				var q3 := Vector3(p0.x + nrm.x, h0 + 0.06, p0.y + nrm.y)
				sink.quad(q0, q1, q2, q3, str(r.mat), {"collide": true, "phys": "concrete", "dirt": 0.3, "tile": mats.tile(str(r.mat)), "facing": Vector3.UP})
				# Slab edge so the road reads as poured concrete / asphalt over the dirt.
				for side in [-1.0, 1.0]:
					var e0 := Vector3(p0.x + nrm.x * side, h0 - 0.1, p0.y + nrm.y * side)
					var e1 := Vector3(p1.x + nrm.x * side, h1 - 0.1, p1.y + nrm.y * side)
					var t0 := e0 + Vector3(0, 0.16, 0)
					var t1 := e1 + Vector3(0, 0.16, 0)
					sink.quad(e0, e1, t1, t0, "concrete_dirty", {"dirt": 0.7, "facing": Vector3(nrm.x * side, 0, nrm.y * side)})
				if r.get("curb", false) and k % 2 == 0:
					pass


func _railway() -> void:
	var pts: PackedVector2Array = layout.railway
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := b - a
		var len := seg.length()
		var dir := seg / len
		var ang := atan2(-dir.y, dir.x)
		var n := int(len / 0.7)
		for k in n:
			var p := a + dir * (k * 0.7 + 0.35)
			if layout.is_water(p.x, p.y):
				continue
			var h: float = layout.ground_height(p.x, p.y)
			# Sleepers, some missing, some rotten.
			if sink.rng.randf() < 0.08:
				continue
			var basis := Basis(Vector3.UP, ang + sink.rng.randf_range(-0.04, 0.04))
			sink.box(Transform3D(basis, Vector3(p.x, h + 0.05, p.y)), Vector3(0.22, 0.12, 2.3), "timber", {"dirt": 0.9, "collide": false, "layer": "ext"})
		# Rails as long thin boxes per segment chunk.
		var steps := maxi(int(len / 8.0), 1)
		for k in steps:
			var p0 := a + dir * (len * k / steps)
			var p1 := a + dir * (len * (k + 1) / steps)
			var mid := (p0 + p1) * 0.5
			if layout.is_water(mid.x, mid.y):
				continue
			var h0: float = layout.ground_height(mid.x, mid.y)
			for side in [-0.72, 0.72]:
				var off = Vector2(-dir.y, dir.x) * side
				sink.box(Transform3D(Basis(Vector3.UP, ang), Vector3(mid.x + off.x, h0 + 0.18, mid.y + off.y)), Vector3(len / steps, 0.13, 0.07), "metal_rust", {"dirt": 0.3, "collide": true, "layer": "ext"})


# ------------------------------------------------------------------ SmarTab map image

func _make_map_image() -> void:
	## A plain navigation map: land, water, roads, building footprints, landmarks. No dynamic information.
	var size := 512
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half: float = layout.HALF
	var s := size / (half * 2.0)
	for iz in size:
		for ix in size:
			var x := -half + (ix + 0.5) / s
			var z := -half + (iz + 0.5) / s
			var c := Color(0.13, 0.15, 0.13)
			if layout.is_water(x, z):
				c = Color(0.07, 0.11, 0.15)
			img.set_pixel(ix, iz, c)
	for r in layout.roads:
		var pts: PackedVector2Array = r.pts
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var steps := int(a.distance_to(b) * s * 2.0) + 1
			for k in steps + 1:
				var p := a.lerp(b, float(k) / steps)
				var px := int((p.x + half) * s)
				var pz := int((p.y + half) * s)
				var rw := maxi(int(float(r.w) * s * 0.5), 1)
				for dx in range(-rw, rw + 1):
					for dz in range(-rw, rw + 1):
						if px + dx >= 0 and px + dx < size and pz + dz >= 0 and pz + dz < size:
							img.set_pixel(px + dx, pz + dz, Color(0.32, 0.32, 0.3))
	for bd in buildings:
		var xf: Transform3D = bd.xf
		var hw := float(bd.w) * 0.5
		var hd := float(bd.d) * 0.5
		var steps := 6
		for i in steps + 1:
			for j in steps + 1:
				var p: Vector3 = xf * Vector3(-hw + 2.0 * hw * i / steps, 0, -hd + 2.0 * hd * j / steps)
				var px := int((p.x + half) * s)
				var pz := int((p.z + half) * s)
				if px >= 0 and px < size and pz >= 0 and pz < size:
					img.set_pixel(px, pz, Color(0.42, 0.38, 0.33))
	# Roofed lanes (dark: you cannot see in) and the open loobans (lighter), so squads can say "the tunnel by the
	# looban" and find it.
	for tn in tunnels:
		var a: Vector2 = tn.a
		var b: Vector2 = tn.b
		var n := int(a.distance_to(b) * s * 2.0) + 1
		for k in n + 1:
			var p := a.lerp(b, float(k) / n)
			var px := int((p.x + half) * s)
			var pz := int((p.y + half) * s)
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if px + dx >= 0 and px + dx < size and pz + dz >= 0 and pz + dz < size and (dx == 0 or dz == 0):
						img.set_pixel(px + dx, pz + dz, Color(0.2, 0.15, 0.12))
	for lb in loobans:
		var c: Vector2 = lb.c
		var hh: Vector2 = lb.half
		var r := int(minf(hh.x, hh.y) * s * 0.8)
		var cx := int((c.x + half) * s)
		var cz := int((c.y + half) * s)
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if cx + dx >= 0 and cx + dx < size and cz + dz >= 0 and cz + dz < size:
					img.set_pixel(cx + dx, cz + dz, Color(0.3, 0.33, 0.27))
	map_image = img


# ------------------------------------------------------------------ runtime facade

func physics_tick(dt: float) -> void:
	dyn.tick(dt)
	if not lighting._headless:
		view_lod.update(dt)
	lighting.tick(dt)


func server_tick(dt: float) -> void:
	pass


func awake_props_near(pos: Vector3, radius: float) -> Array:
	return dyn.awake_props_near(pos, radius)


func client_prop_snapshot(id: int, pos: Vector3, rot: Quaternion, t: float) -> void:
	dyn.client_prop_snapshot(id, pos, rot, t)


func client_interpolate(render_tick: float) -> void:
	dyn.client_interpolate(render_tick)


func item_visual(id: String) -> Dictionary:
	return dresser.item_visual(id)


func server_spawn_corpse(ch, impulse: Vector3) -> int:
	return dyn.server_spawn_corpse(ch, impulse)


func server_break_glass(collider, pos: Vector3, dir: Vector3) -> void:
	if collider == null or not collider.has_meta("window_id"):
		return
	var wid := int(collider.get_meta("window_id"))
	if dyn.break_window(wid, pos, dir):
		world.map_window_broken.rpc(wid, pos, dir)
		if not world.is_server_dedicated() and world.effects:
			world.effects.glass_break(pos, dir, dyn.windows[wid])
		world.server_sound("glass_break", pos, 0.0, -1)


func server_prop_hit(prop_id: int, pos: Vector3, dir: Vector3, energy: float, momentum: float) -> void:
	var body = dyn.server_activate(prop_id)
	if body and is_instance_valid(body):
		# About the round's own momentum (a pistol round nudges a chair; it does not throw it across the room).
		body.apply_impulse(dir * minf(momentum * 1.5, 12.0), pos - body.global_position)
		body.take_damage(energy * 0.08, dir, pos)


func server_blast(pos: Vector3, radius: float, damage: float) -> void:
	## A grenade: loose props within the radius are thrown and knocked apart, doors and shutters lose panels, nearest
	## the blast first.
	var space := PhysicsServer3D.space_get_direct_state(dyn.space_rid)
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	q.shape = sph
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = Defs.PHYS_PROP
	var seen := {}
	var hits := space.intersect_shape(q, 64)
	# Doors and shutters by distance: the world's own shapes would fill any shape query's result list.
	for d in dyn.doors:
		var dn = d.get("node")
		if dn and not dn.destroyed and (d.xf as Transform3D).origin.distance_to(pos) < radius + 1.0:
			hits.append({"collider": dn})
	for w in dyn.windows:
		if w.has("door") and not w.door.destroyed and (w.xf as Transform3D).origin.distance_to(pos) < radius + 1.0:
			hits.append({"collider": w.door})
	for r in hits:
		var c = r.collider
		if c == null:
			continue
		if c.has_meta("prop_id"):
			var pid := int(c.get_meta("prop_id"))
			if seen.has("p%d" % pid):
				continue
			seen["p%d" % pid] = true
			var body = dyn.server_activate(pid)
			if body and is_instance_valid(body):
				var bp: Vector3 = body.global_position
				var k := clampf(1.0 - bp.distance_to(pos) / radius, 0.0, 1.0)
				body.apply_central_impulse((bp - pos + Vector3.UP * 0.5).normalized() * 9.0 * k * minf(body.mass, 30.0) * 0.4)
				for i in 3:
					if is_instance_valid(body):
						body.take_damage(damage * k * 0.9, (bp - pos).normalized(), bp.lerp(pos, 0.35))
		elif c.has_meta("door_id") or c.has_meta("shutter_id"):
			var key := str(c.get_instance_id())
			if seen.has(key):
				continue
			seen[key] = true
			var d = c
			if d.destroyed:
				continue
			for i in 4:
				var cc: Vector3 = d.center()
				var k2 := clampf(1.0 - cc.distance_to(pos) / radius, 0.0, 1.0)
				var pi: int = d.server_damage(cc.lerp(pos, 0.5), damage * k2 * 1.2)
				if pi >= 0:
					world.server_door_panel(d, pi, (cc - pos).normalized())
				if d.destroyed:
					break


func server_corpse_hit(corpse_id: int, pos: Vector3, dir: Vector3) -> void:
	var c = dyn.corpses.get(corpse_id)
	if c and c.server and not c.settled:
		(c.bodies.chest as RigidBody3D).apply_impulse(dir * 3.0)


func server_push_prop(prop_id: int, by, dir: Vector3, vel: Vector3) -> void:
	if Vector2(vel.x, vel.z).length() < 0.6:
		return
	var body = dyn.server_activate(prop_id)
	if body and is_instance_valid(body):
		body.on_pushed(by, dir, vel, Defs.TICK_DT)


func server_sync_peer(pid: int) -> void:
	## Late joiners: everything that differs from the deterministic start state.
	for d in dyn.doors:
		var dn = d.get("node")
		if dn and (absf(dn.angle - float(d.get("start_angle", 0.0))) > 0.01 or dn.locked != bool(d.get("locked", false))):
			world.map_door_ev.rpc_id(pid, int(d.id), false, dn.angle, dn.target, dn.locked, "")
	for w in dyn.windows:
		if w.get("broken", false):
			world.map_window_broken.rpc_id(pid, int(w.id), (w.xf as Transform3D).origin, Vector3.FORWARD)
		elif w.has("door"):
			var sd = w.door
			if absf(sd.angle) > 0.01:
				world.map_door_ev.rpc_id(pid, int(w.id), true, sd.angle, sd.target, false, "")
	world.server_send_items(pid)
	var opened = dyn.opened_boxes()
	if not opened.is_empty():
		world._box_opened.rpc_id(pid, opened)
	for p in dyn.props:
		if p.state == "broken":
			world.map_prop_break.rpc_id(pid, int(p.id), (p.xf as Transform3D).origin, Vector3.ZERO)
		elif p.state == "active":
			world.map_prop_activate.rpc_id(pid, int(p.id), (p.body as Node3D).global_transform if p.get("body") else p.xf)
			if not (p.get("lost", []) as Array).is_empty():
				world.map_prop_chunks.rpc_id(pid, int(p.id), PackedInt32Array(p.lost))
	for d in dyn.doors:
		var dn2 = d.get("node")
		if dn2 and not dn2.lost.is_empty():
			world.map_door_panels.rpc_id(pid, int(d.id), false, PackedInt32Array(dn2.lost.keys()))
	for w2 in dyn.windows:
		if w2.has("door") and not w2.door.lost.is_empty():
			world.map_door_panels.rpc_id(pid, int(w2.id), true, PackedInt32Array(w2.door.lost.keys()))
	for cid in dyn.corpses:
		var c = dyn.corpses[cid]
		world.map_corpse_spawn.rpc_id(pid, cid, c.pname, c.team, c.pose())
