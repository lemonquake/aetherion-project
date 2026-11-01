@tool
extends RefCounted
## (r27) The living and burning parts of a map-editor map, drawn the same in the game and in the map editor:
##   vines    hanging strands along a line (a branch, a lintel, a wall's top): from [x, y, z], to [x, y, z],
##            drop (longest strand, m), density (strands a metre), seed, sag (the line's own droop, m), w (strand width)
##   fixtures what a torch or brazier light burns on ("mount" on a light of kind torch / brazier): pole (a torch on a
##            pole stuck in the ground, the flame "pole" metres up), wall (a bracket; the flame stands out from the wall
##            toward the light's yaw), stand (a brazier on a stone pedestal), bowl (a brazier bowl on the floor), none.
## Everything here is batched by the game: a vines piece is one mesh, the fixtures are one MultiMesh per kind.

const TEX := "res://assets/maps/textures"
const NRM := "res://assets/maps/normals"
const VINE_SHADER := preload("res://src/world/vines.gdshader")
const VINE_TEX := "jungle/vine_strand"
const MOUNTS := ["pole", "wall", "stand", "bowl", "none"]

static var _vine_mat: ShaderMaterial = null
static var _fix_meshes := {}
static var _mats := {}


# ------------------------------------------------------------------ vines

static func vine_material() -> ShaderMaterial:
	if _vine_mat == null:
		_vine_mat = ShaderMaterial.new()
		_vine_mat.shader = VINE_SHADER
		var a := "%s/%s.png" % [TEX, VINE_TEX]
		var n := "%s/%s_normal.png" % [NRM, VINE_TEX]
		if ResourceLoader.exists(a):
			_vine_mat.set_shader_parameter("albedo_tex", load(a))
		if ResourceLoader.exists(n):
			_vine_mat.set_shader_parameter("normal_tex", load(n))
	return _vine_mat


static func vines_frame(p: Dictionary) -> Transform3D:
	## The piece's frame: the middle of its line, turned along it.
	var a := _v3(p.get("from"), Vector3(-1, 3, 0))
	var b := _v3(p.get("to"), Vector3(1, 3, 0))
	var d := b - a
	var yaw := rad_to_deg(atan2(d.x, -d.z)) - 90.0
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(yaw)), (a + b) * 0.5)


static func vines_mesh(p: Dictionary) -> ArrayMesh:
	## Every strand of a vines piece, in the piece's own frame (vines_frame): two crossed ribbons each, cut in four
	## so the shader can swing the lower part.
	var a := _v3(p.get("from"), Vector3(-1, 3, 0))
	var b := _v3(p.get("to"), Vector3(1, 3, 0))
	var inv := vines_frame(p).affine_inverse()
	var la: Vector3 = inv * a
	var lb: Vector3 = inv * b
	var drop := float(p.get("drop", 3.0))
	var dens := float(p.get("density", 3.0))
	var sag := float(p.get("sag", 0.0))
	var w := float(p.get("w", 0.32))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.get("seed", hash(str(p.get("id", "vines")))))
	var ln := la.distance_to(lb)
	var n := maxi(1, int(round(ln * dens)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n:
		var t := (k + rng.randf_range(0.15, 0.85)) / n
		var top := la.lerp(lb, t) + Vector3(0, -sag * 4.0 * t * (1.0 - t), 0) + Vector3(0, 0, rng.randf_range(-0.12, 0.12))
		var L := drop * rng.randf_range(float(p.get("min", 0.35)), 1.0)
		var tint := Color(rng.randf_range(0.82, 1.05), rng.randf_range(0.88, 1.08), rng.randf_range(0.78, 1.0), rng.randf())
		var ang := rng.randf() * PI
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		for cross in 2:
			var dir := Vector3(cos(ang + cross * PI * 0.5), 0, sin(ang + cross * PI * 0.5)) * w * 0.5
			var segs := 4
			for s in segs:
				var v0 := float(s) / segs
				var v1 := float(s + 1) / segs
				var p0 := top + Vector3(0, -L * v0, 0) + lean * v0 * v0 * L
				var p1 := top + Vector3(0, -L * v1, 0) + lean * v1 * v1 * L
				var nrm := dir.cross(Vector3.UP).normalized()
				var quad := [[p0 - dir, Vector2(0, v0)], [p0 + dir, Vector2(1, v0)], [p1 + dir, Vector2(1, v1)], [p1 - dir, Vector2(0, v1)]]
				for i in [0, 1, 2, 0, 2, 3]:
					st.set_color(tint)
					st.set_normal(nrm)
					st.set_uv(Vector2(quad[i][1].x, quad[i][1].y * minf(L / maxf(drop, 0.1), 1.0)))
					st.add_vertex(quad[i][0])
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, vine_material())
	return m


static func vines_node(p: Dictionary, local := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = str(p.get("id", "vines"))
	mi.mesh = vines_mesh(p)
	if not local:
		mi.transform = vines_frame(p)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 75.0
	mi.visibility_range_end_margin = 8.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return mi


static func vines_bounds(p: Dictionary) -> AABB:
	var inv := vines_frame(p).affine_inverse()
	var la: Vector3 = inv * _v3(p.get("from"), Vector3(-1, 3, 0))
	var lb: Vector3 = inv * _v3(p.get("to"), Vector3(1, 3, 0))
	var bb := AABB(la, Vector3.ZERO).expand(lb)
	bb = bb.expand(la - Vector3(0, float(p.get("drop", 3.0)), 0)).expand(lb - Vector3(0, float(p.get("drop", 3.0)), 0))
	return bb.grow(0.25)


# ------------------------------------------------------------------ torch and brazier fixtures

static func fixture_xf(p: Dictionary) -> Transform3D:
	## Where a fire light's fixture stands: its frame (yaw) at the flame's foot, its own origin at its base.
	var at := _v3(p.get("at"))
	var yb := Basis(Vector3.UP, -deg_to_rad(float(p.get("yaw", 0.0))))
	match str(p.get("mount", "pole")):
		"pole":
			return Transform3D(yb, at - Vector3(0, float(p.get("pole", 1.9)), 0))
		"wall":
			return Transform3D(yb, at)
		"stand":
			return Transform3D(yb, at - Vector3(0, 1.08, 0))
		"bowl":
			return Transform3D(yb, at - Vector3(0, 0.42, 0))
	return Transform3D(yb, at)


static func fixture_mesh(mount: String, pole := 1.9) -> Mesh:
	## The fixture, built once per kind from a few turned and boxed parts (the pole's length in the key).
	var key := "%s|%.2f" % [mount, pole if mount == "pole" else 0.0]
	if _fix_meshes.has(key):
		return _fix_meshes[key]
	var wood := _mat("jungle/torch_wood")
	var stone := _mat("jungle/temple_stone")
	var cloth := _mat("jungle/torch_wrap")
	var ember := _ember_mat()
	var am := ArrayMesh.new()
	var parts := {}
	match mount:
		"pole":
			_cyl(parts, wood, Vector3(0, -0.25, 0), 0.045, 0.035, pole + 0.2, 7)        # the pole, its foot in the ground
			_cyl(parts, cloth, Vector3(0, pole - 0.24, 0), 0.075, 0.068, 0.22, 8)        # the pitch-soaked wrap
			_cyl(parts, ember, Vector3(0, pole - 0.03, 0), 0.06, 0.05, 0.04, 8)
			_cyl(parts, cloth, Vector3(0, pole - 0.62, 0), 0.05, 0.05, 0.05, 7)          # a lashing lower down
		"wall":
			# a bracket on the wall behind the flame (the light's yaw points away from the wall)
			_box(parts, stone, Transform3D(Basis(), Vector3(0, -0.42, 0.34)), Vector3(0.16, 0.26, 0.08))
			_box(parts, wood, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-35.0)), Vector3(0, -0.3, 0.2)), Vector3(0.06, 0.06, 0.36))
			_cyl(parts, wood, Vector3(0, -0.5, 0.05), 0.04, 0.032, 0.42, 7)
			_cyl(parts, cloth, Vector3(0, -0.2, 0.05), 0.07, 0.062, 0.2, 8)
			_cyl(parts, ember, Vector3(0, -0.01, 0.05), 0.055, 0.045, 0.03, 8)
		"stand":
			_cyl(parts, stone, Vector3(0, 0, 0), 0.3, 0.32, 0.12, 8)
			_cyl(parts, stone, Vector3(0, 0.12, 0), 0.2, 0.24, 0.62, 8)
			_cyl(parts, stone, Vector3(0, 0.74, 0), 0.24, 0.2, 0.08, 8)
			_cyl(parts, stone, Vector3(0, 0.82, 0), 0.5, 0.26, 0.22, 10)
			_cyl(parts, ember, Vector3(0, 1.03, 0), 0.42, 0.42, 0.02, 10)
		"bowl":
			_cyl(parts, stone, Vector3(0, 0, 0), 0.34, 0.4, 0.1, 10)
			_cyl(parts, stone, Vector3(0, 0.1, 0), 0.56, 0.34, 0.26, 12)
			_cyl(parts, ember, Vector3(0, 0.37, 0), 0.48, 0.48, 0.02, 12)
	for m in parts:
		(parts[m] as SurfaceTool).commit(am)
	_fix_meshes[key] = am
	return am


static func _ember_mat() -> StandardMaterial3D:
	if _mats.has("_ember"):
		return _mats["_ember"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.03, 0.01)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.36, 0.06)
	m.emission_energy_multiplier = 2.2
	m.roughness = 0.9
	_mats["_ember"] = m
	return m


static func _mat(tex: String) -> StandardMaterial3D:
	if _mats.has(tex):
		return _mats[tex]
	var m := StandardMaterial3D.new()
	m.resource_name = tex
	var a := "%s/%s.png" % [TEX, tex]
	if ResourceLoader.exists(a):
		m.albedo_texture = load(a)
	else:
		m.albedo_color = Color(0.35, 0.3, 0.25)
	var n := "%s/%s_normal.png" % [NRM, tex]
	if ResourceLoader.exists(n):
		m.normal_enabled = true
		m.normal_texture = load(n)
	m.roughness = 0.88
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(2.0, 2.0, 2.0)
	_mats[tex] = m
	return m


static func _cyl(parts: Dictionary, mat: Material, base: Vector3, r_bottom: float, r_top: float, h: float, sides: int) -> void:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bottom
	cm.top_radius = r_top
	cm.height = h
	cm.radial_segments = sides
	cm.rings = 1
	_add(parts, mat, cm.get_mesh_arrays(), Transform3D(Basis(), base + Vector3(0, h * 0.5, 0)))


static func _box(parts: Dictionary, mat: Material, xf: Transform3D, size: Vector3) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_add(parts, mat, bm.get_mesh_arrays(), xf)


static func _add(parts: Dictionary, mat: Material, arrays: Array, xf: Transform3D) -> void:
	## Adds a part's triangles to its material's SurfaceTool (one surface per material).
	if not parts.has(mat):
		var st0 := SurfaceTool.new()
		st0.begin(Mesh.PRIMITIVE_TRIANGLES)
		st0.set_material(mat)
		parts[mat] = st0
	var st: SurfaceTool = parts[mat]
	var vin: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var nin: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uin: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		st.set_normal((xf.basis * nin[i]).normalized())
		st.set_uv(uin[i])
		st.add_vertex(xf * vin[i])


static func _v3(a, fallback := Vector3.ZERO) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback
