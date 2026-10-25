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
var root: Node3D
var world = null
var buildings: Array = []
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
	dyn = Dynamics.new(self, world_node, root, mats, models, map_seed, match_seed)
	dresser = Dresser.new(self)
	lighting = Lighting.new(self)
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
	stats.towns_ms = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	sink.finish()
	dyn.instantiate()
	stats.finish_ms = Time.get_ticks_msec() - t0
	lighting.build(world_node)
	stats.buildings = buildings.size()
	stats.sink = sink.stats
	stats.doors = dyn.doors.size()
	stats.windows = dyn.windows.size()
	stats.props = dyn.props.size()
	stats.zones = acoustics.zones.size()
	stats.containers = dyn.containers.size()
	dyn.randomize_for_match(world_node.get("is_server") == true)
	_make_map_image()


func new_building_id() -> int:
	_next_bid += 1
	return _next_bid


func shanty(spec: Dictionary) -> Dictionary:
	spec.id = new_building_id()
	var ctx := {"sink": sink, "mats": mats, "acoustics": acoustics, "dyn": dyn}
	var s := Shanty.new(ctx)
	var out := s.build(spec)
	buildings.append({"id": spec.id, "xf": spec.xf, "w": spec.w, "d": spec.d, "kind": spec.get("kind", "house"), "district": spec.get("district", "")})
	for r in out.rooms:
		dresser.dress_room(r, spec)
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
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("splat", ImageTexture.create_from_image(splat))
	mat.set_shader_parameter("splat_origin", Vector2(-half, -half))
	mat.set_shader_parameter("splat_size", half * 2.0)
	for pair in [["dirt", "dirt_floor"], ["mud", "brown_mud_02"], ["grass", "sparse_grass"], ["sand", "coast_sand_01"], ["path", "stony_dirt_path"]]:
		mat.set_shader_parameter(pair[0] + "_alb", _tex(TEX + pair[1] + "/albedo.jpg"))
		mat.set_shader_parameter(pair[0] + "_nrm", _tex(TEX + pair[1] + "/normal.jpg"))
	mat.set_shader_parameter("water_y", layout.WATER_Y)
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
			if absf(x) > 430.0 or z < -480.0 or (x > 230.0 and z < -260.0):
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
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = WATER_SHADER
	sea_mat.set_shader_parameter("sea", 1.0)
	sea_mat.set_shader_parameter("deep_color", Color(0.02, 0.03, 0.04))
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
				sink.quad(q0, q3, q2, q1, str(r.mat), {"collide": true, "phys": "concrete", "dirt": 0.3, "tile": mats.tile(str(r.mat))})
				# Slab edge so the road reads as poured concrete / asphalt over the dirt.
				for side in [-1.0, 1.0]:
					var e0 := Vector3(p0.x + nrm.x * side, h0 - 0.1, p0.y + nrm.y * side)
					var e1 := Vector3(p1.x + nrm.x * side, h1 - 0.1, p1.y + nrm.y * side)
					var t0 := e0 + Vector3(0, 0.16, 0)
					var t1 := e1 + Vector3(0, 0.16, 0)
					if side < 0:
						sink.quad(e0, e1, t1, t0, "concrete_dirty", {"dirt": 0.7})
					else:
						sink.quad(e1, e0, t0, t1, "concrete_dirty", {"dirt": 0.7})
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
	map_image = img


# ------------------------------------------------------------------ runtime facade

func physics_tick(dt: float) -> void:
	dyn.tick(dt)
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
