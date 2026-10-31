@tool
extends RefCounted
## Builds a scene from a TrenchBroom map (Valve 220; the older Standard face format is read too).
##
## Brush entities:
##   worldspawn, func_group (TrenchBroom layers and groups), func_detail, func_wall: drawn and solid.
##   func_stairs: the steps, drawn only (feet would snag on every riser); also recorded as a flight (foot, top,
##                width) for the game's bots and level map. The flight's collision is a ramp over the step nosings in
##                a clip_<surface> texture, the way the game's own stairs are built (a box per step for the eye, a
##                smooth ramp for the feet).
##   func_illusionary: drawn only (wires, laundry, banners overhead, the scenery past the play area).
## Textures (materials) are "folder/name" under textures_root (PNG). Special names: */skip (nothing), */clip
## (invisible, blocks movement only), */clip_<surface> (invisible but solid: stair ramps; its surfaces.json entry gives
## the physical surface, so footsteps and bullets match the steps it covers). surfaces.json gives each material its physical surface (bullets, footsteps),
## roughness, metal, emission, alpha and sidedness; a material saved as <material_overrides>/<folder>/<name>.tres
## replaces the generated one.
## Point entities:
##   light: an OmniLight3D (or SpotLight3D for kind flood / street / down), with the game's lamp kind and fault as
##          metadata (the game turns them into its own managed, flickering lamps).
##   info_team_spawn: a Marker3D (meta team = 1 or 2, facing its angle). info_landmark: a Marker3D (meta landmark).
##   anything else: a Marker3D carrying the entity's properties as metadata.
## The root carries the worldspawn properties (meta "worldspawn"), the stair flights (meta "stairs") and every
## solid brush as planes and bounds (metas "brush_*"), which the game uses to lay out its bot walk grids.

const PHYS_WORLD := 1        # Defs.PHYS_WORLD (layer "World")
const PHYS_BLOCKER := 1024   # Defs.PHYS_BLOCKER (layer "Blockers": stops bodies, not bullets)
const SOLID := ["worldspawn", "func_group", "func_detail", "func_wall"]
const NO_FACE := ["skip", "nodraw", "trigger", "hint", "origin", "clip"]
const SPOT_KINDS := ["flood", "street", "down", "shaft"]

var upm := 32.0
var tex_root := "res://assets/maps/textures"
var overrides := "res://assets/maps/materials"
var chunk := 24.0
var surfaces := {}
var stats := {"brushes": 0, "faces": 0, "tris": 0, "col_tris": 0, "meshes": 0, "bodies": 0, "lights": 0, "spawns": 0, "missing": []}

var _mats := {}
var _tex_px := {}
var _surf_tools := {}      # "cx,cz|tex" -> SurfaceTool
var _col := {}             # "cx,cz|phys" -> PackedVector3Array
var _brush_aabbs := PackedFloat32Array()
var _brush_planes := PackedFloat32Array()
var _brush_start := PackedInt32Array()
var _brush_flags := PackedByteArray()


# ------------------------------------------------------------------ parsing

func parse(text: String) -> Array:
	## [{props: Dictionary, brushes: [[face...]]}], face = {n: Vector3 (Quake), d: float, tex, u, uo, v, vo, sx, sy}
	var ents := []
	var ent = null
	var brush = null
	var re_kv := RegEx.new()
	re_kv.compile("^\"((?:[^\"\\\\]|\\\\.)*)\"\\s+\"((?:[^\"\\\\]|\\\\.)*)\"")
	for raw in text.split("\n"):
		var s := raw.strip_edges()
		if s.is_empty() or s.begins_with("//"):
			continue
		if s == "{":
			if ent == null:
				ent = {"props": {}, "brushes": []}
			else:
				brush = []
			continue
		if s == "}":
			if brush != null:
				ent.brushes.append(brush)
				brush = null
			elif ent != null:
				ents.append(ent)
				ent = null
			continue
		if s.begins_with("\""):
			var m := re_kv.search(s)
			if m and ent != null:
				ent.props[m.get_string(1)] = m.get_string(2).c_unescape()
			continue
		if s.begins_with("(") and brush != null:
			var f = _parse_face(s)
			if f != null:
				brush.append(f)
	return ents


func _parse_face(s: String):
	var t := s.replace("(", " ").replace(")", " ").replace("[", " ").replace("]", " ").split(" ", false)
	if t.size() < 15:
		return null
	var p := []
	for k in 3:
		p.append([float(t[k * 3]), float(t[k * 3 + 1]), float(t[k * 3 + 2])])
	# normal = (p3 - p1) x (p2 - p1), pointing out of the brush (TrenchBroom's winding); in doubles
	var a := [p[2][0] - p[0][0], p[2][1] - p[0][1], p[2][2] - p[0][2]]
	var b := [p[1][0] - p[0][0], p[1][1] - p[0][1], p[1][2] - p[0][2]]
	var n := [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
	var ln := sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2])
	if ln < 1e-9:
		return null
	n = [n[0] / ln, n[1] / ln, n[2] / ln]
	var d: float = n[0] * p[0][0] + n[1] * p[0][1] + n[2] * p[0][2]
	var f := {"n": n, "d": d, "tex": t[9]}
	if t.size() >= 21:
		f.u = Vector3(float(t[10]), float(t[11]), float(t[12]))
		f.uo = float(t[13])
		f.v = Vector3(float(t[14]), float(t[15]), float(t[16]))
		f.vo = float(t[17])
		f.sx = float(t[19])
		f.sy = float(t[20])
	else:
		# Standard (Quake) format: offsets, rotation and scale on the axis plane nearest the normal
		var ax := _paraxial(Vector3(n[0], n[1], n[2]))
		var rot := deg_to_rad(float(t[12]))
		var ua: Vector3 = ax[0]
		var va: Vector3 = ax[1]
		var nrm: Vector3 = ua.cross(va).normalized()
		f.u = ua.rotated(nrm, rot)
		f.v = va.rotated(nrm, rot)
		f.uo = float(t[10])
		f.vo = float(t[11])
		f.sx = float(t[13])
		f.sy = float(t[14])
	if absf(f.sx) < 1e-6:
		f.sx = 1.0
	if absf(f.sy) < 1e-6:
		f.sy = 1.0
	return f


static func _paraxial(n: Vector3) -> Array:
	var an := n.abs()
	if an.z >= an.x and an.z >= an.y:
		return [Vector3(1, 0, 0), Vector3(0, -1, 0)]
	if an.x >= an.y:
		return [Vector3(0, 1, 0), Vector3(0, 0, -1)]
	return [Vector3(1, 0, 0), Vector3(0, 0, -1)]


# ------------------------------------------------------------------ geometry

func _face_polygon(faces: Array, i: int) -> PackedFloat64Array:
	## The face's polygon (Quake units, doubles, x y z per corner), counter-clockwise seen from outside: a big square
	## on its plane cut down by every other plane of the brush.
	var f: Dictionary = faces[i]
	var n: Array = f.n
	var nv := Vector3(n[0], n[1], n[2])
	var up := Vector3(0, 0, 1) if absf(nv.z) < 0.9 else Vector3(1, 0, 0)
	var ua := up.cross(nv).normalized()
	var va := nv.cross(ua).normalized()   # ua x va = n: counter-clockwise from outside
	var c := [n[0] * f.d, n[1] * f.d, n[2] * f.d]
	var R := 32768.0
	var poly := PackedFloat64Array()
	for k in 4:
		var su := R if k == 0 or k == 3 else -R
		var sv := R if k < 2 else -R
		poly.append(c[0] + ua.x * su + va.x * sv)
		poly.append(c[1] + ua.y * su + va.y * sv)
		poly.append(c[2] + ua.z * su + va.z * sv)
	# corners in order: (+,+), (-,+), (-,-), (+,-): counter-clockwise around n
	for j in faces.size():
		if j == i:
			continue
		var g: Dictionary = faces[j]
		poly = _clip(poly, g.n, g.d)
		if poly.size() < 9:
			return PackedFloat64Array()
	return poly


static func _clip(poly: PackedFloat64Array, n: Array, d: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var cnt := poly.size() / 3
	for k in cnt:
		var a := k * 3
		var b := ((k + 1) % cnt) * 3
		var da: float = n[0] * poly[a] + n[1] * poly[a + 1] + n[2] * poly[a + 2] - d
		var db: float = n[0] * poly[b] + n[1] * poly[b + 1] + n[2] * poly[b + 2] - d
		if da <= 0.001:
			out.append(poly[a]); out.append(poly[a + 1]); out.append(poly[a + 2])
		if (da < -0.001 and db > 0.001) or (da > 0.001 and db < -0.001):
			var t := da / (da - db)
			out.append(poly[a] + (poly[b] - poly[a]) * t)
			out.append(poly[a + 1] + (poly[b + 1] - poly[a + 1]) * t)
			out.append(poly[a + 2] + (poly[b + 2] - poly[a + 2]) * t)
	return out


func _g(x: float, y: float, z: float) -> Vector3:
	## Quake units (z up) -> Godot metres (y up, -z north)
	return Vector3(x / upm, z / upm, -y / upm)


# ------------------------------------------------------------------ materials

func _leaf(tex: String) -> String:
	return tex.get_file().to_lower()


func _surface(tex: String) -> Dictionary:
	return surfaces.get(tex, surfaces.get(tex.to_lower(), {}))


func _material(tex: String) -> Material:
	if _mats.has(tex):
		return _mats[tex]
	var ov := "%s/%s.tres" % [overrides, tex]
	if ResourceLoader.exists(ov):
		_mats[tex] = load(ov)
		return _mats[tex]
	var sd := _surface(tex)
	var m := StandardMaterial3D.new()
	m.resource_name = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var alb := "%s/%s.png" % [tex_root, tex]
	if ResourceLoader.exists(alb):
		m.albedo_texture = load(alb)
	else:
		m.albedo_color = Color(1.0, 0.0, 1.0)
		if not tex in stats.missing:
			stats.missing.append(tex)
	var base := tex_root.get_base_dir()
	var nrm := "%s/normals/%s_normal.png" % [base, tex]
	if sd.get("normal", false) and ResourceLoader.exists(nrm):
		m.normal_enabled = true
		m.normal_texture = load(nrm)
		m.normal_scale = 1.0
	var rgh := "%s/roughness/%s_rough.png" % [base, tex]
	m.roughness = float(sd.get("rough", 0.85))
	if sd.get("rough_map", false) and ResourceLoader.exists(rgh):
		m.roughness_texture = load(rgh)
		m.roughness = 1.0
	m.metallic = float(sd.get("metal", 0.0))
	m.metallic_specular = 0.45
	var emit := float(sd.get("emit", 0.0))
	if emit > 0.0:
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = emit
		if sd.get("unshaded", false):
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if str(sd.get("alpha", "")) == "scissor":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	if sd.get("two_sided", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[tex] = m
	return m


func _tex_size(tex: String) -> Vector2:
	if _tex_px.has(tex):
		return _tex_px[tex]
	var sd := _surface(tex)
	var sz := Vector2(512, 512)
	if sd.has("px"):
		sz = Vector2(float(sd.px[0]), float(sd.px[1]))
	else:
		var path := "%s/%s.png" % [tex_root, tex]
		if ResourceLoader.exists(path):
			var t: Texture2D = load(path)
			sz = Vector2(t.get_width(), t.get_height())
	_tex_px[tex] = sz
	return sz


func _phys(tex: String) -> String:
	if _leaf(tex) == "clip":
		return "clip"
	return str(_surface(tex).get("phys", "concrete"))


# ------------------------------------------------------------------ build

func build(text: String, options: Dictionary = {}, map_name: String = "map") -> Node3D:
	upm = float(options.get("units_per_metre", 32.0))
	tex_root = str(options.get("textures_root", tex_root)).trim_suffix("/")
	overrides = str(options.get("material_overrides", overrides)).trim_suffix("/")
	chunk = float(options.get("chunk_size", 24.0))
	var sp := str(options.get("surfaces", "res://assets/maps/surfaces.json"))
	if FileAccess.file_exists(sp):
		var js = JSON.parse_string(FileAccess.get_file_as_string(sp))
		if js is Dictionary:
			surfaces = js
	var ents := parse(text)
	if ents.is_empty():
		push_error("[map import] no entities in the map")
		return null
	var root := Node3D.new()
	root.name = map_name.to_pascal_case() if map_name != "" else "Map"
	var groups := {}
	for nm in ["Geometry", "Collision", "Lights", "Spawns", "Landmarks", "Entities"]:
		var g := Node3D.new()
		g.name = nm
		root.add_child(g)
		g.owner = root
		groups[nm] = g
	var stairs := []
	var n_light := 0
	for e in ents:
		var cls := str(e.props.get("classname", ""))
		if cls == "worldspawn":
			var ws := {}
			for k in e.props:
				ws[k] = e.props[k]
			root.set_meta("worldspawn", ws)
		if not e.brushes.is_empty():
			var solid := cls in SOLID or cls.begins_with("func_detail")
			var flight := []
			for br in e.brushes:
				var info := _add_brush(br, solid, cls == "func_stairs")
				if cls == "func_stairs" and not info.is_empty():
					flight.append(info)
			if cls == "func_stairs" and flight.size() >= 2:
				stairs.append(_flight(flight, str(e.props.get("targetname", "stairs"))))
			continue
		if not e.props.has("origin"):
			continue
		var o := str(e.props.origin).split(" ", false)
		if o.size() < 3:
			continue
		var pos := _g(float(o[0]), float(o[1]), float(o[2]))
		var yaw_q := deg_to_rad(float(e.props.get("angle", "0")))
		var dir := Vector3(cos(yaw_q), 0.0, -sin(yaw_q))
		match cls:
			"light":
				n_light += 1
				var node := _light(e.props, pos, dir)
				node.name = "Light%03d_%s" % [n_light, str(e.props.get("kind", "bulb"))]
				groups.Lights.add_child(node)
				node.owner = root
				stats.lights += 1
			"info_team_spawn", "info_player_team1", "info_player_team2":
				var mk := Marker3D.new()
				var team := int(e.props.get("team", "2" if cls.ends_with("2") else "1"))
				mk.name = "Team%d_%02d" % [team, stats.spawns + 1]
				mk.position = pos
				mk.rotation.y = atan2(-dir.x, -dir.z)
				mk.set_meta("team", team)
				mk.gizmo_extents = 0.4
				groups.Spawns.add_child(mk)
				mk.owner = root
				stats.spawns += 1
			"info_landmark":
				var lm := Marker3D.new()
				lm.name = str(e.props.get("name", "Landmark")).validate_node_name()
				lm.position = pos
				lm.set_meta("landmark", str(e.props.get("name", "")))
				groups.Landmarks.add_child(lm)
				lm.owner = root
			_:
				var mk2 := Marker3D.new()
				mk2.name = cls.validate_node_name()
				mk2.position = pos
				var pr := {}
				for k in e.props:
					pr[k] = e.props[k]
				mk2.set_meta("entity", pr)
				groups.Entities.add_child(mk2)
				mk2.owner = root
	_emit_meshes(groups.Geometry, root)
	_emit_collision(groups.Collision, root)
	root.set_meta("stairs", stairs)
	root.set_meta("brush_aabbs", _brush_aabbs)
	root.set_meta("brush_planes", _brush_planes)
	root.set_meta("brush_start", _brush_start)
	root.set_meta("brush_flags", _brush_flags)
	root.set_meta("units_per_metre", upm)
	return root


func _add_brush(faces: Array, solid: bool, is_stair: bool) -> Dictionary:
	## Draws the brush's faces, adds its collision, records it for the walk grids; returns its bounds (Godot) or {}.
	stats.brushes += 1
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var visible_faces := 0
	var all_clip := true
	for i in faces.size():
		var f: Dictionary = faces[i]
		var poly := _face_polygon(faces, i)
		if poly.size() < 9:
			continue
		var pts := PackedVector3Array()
		for k in poly.size() / 3:
			var p := _g(poly[k * 3], poly[k * 3 + 1], poly[k * 3 + 2])
			pts.append(p)
			lo = lo.min(p)
			hi = hi.max(p)
		var leaf := _leaf(f.tex)
		if leaf != "clip":
			all_clip = false
		var drawn := not (leaf in NO_FACE) and not leaf.begins_with("clip_")
		if drawn:
			_draw_face(f, poly, pts)
			visible_faces += 1
		if solid and leaf not in ["skip", "nodraw", "trigger", "hint", "origin"]:
			var key := "%s|%s" % [_ckey(pts), _phys(f.tex)]
			if not _col.has(key):
				_col[key] = PackedVector3Array()
			var arr: PackedVector3Array = _col[key]
			for k in range(1, pts.size() - 1):
				arr.append(pts[0]); arr.append(pts[k]); arr.append(pts[k + 1])
				stats.col_tris += 1
			_col[key] = arr
	if lo.x == INF:
		return {}
	if solid:
		# planes in Godot space (outward normal, distance), for the game's walk-grid survey
		_brush_start.append(_brush_planes.size())
		for f in faces:
			var n: Array = f.n
			var gn := Vector3(n[0], n[2], -n[1])
			_brush_planes.append(gn.x); _brush_planes.append(gn.y); _brush_planes.append(gn.z)
			_brush_planes.append(float(f.d) / upm)
		for c in [lo.x, lo.y, lo.z, hi.x, hi.y, hi.z]:
			_brush_aabbs.append(c)
		var fl := 1
		if is_stair:
			fl |= 2
		if all_clip:
			fl |= 4
		_brush_flags.append(fl)
	return {"lo": lo, "hi": hi}


func _ckey(pts: PackedVector3Array) -> String:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	return "%d,%d" % [floori(c.x / chunk), floori(c.z / chunk)]


func _draw_face(f: Dictionary, poly: PackedFloat64Array, pts: PackedVector3Array) -> void:
	stats.faces += 1
	var tex: String = f.tex
	var key := "%s|%s" % [_ckey(pts), tex]
	var st: SurfaceTool = _surf_tools.get(key)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(_material(tex))
		_surf_tools[key] = st
	var n: Array = f.n
	var gn := Vector3(n[0], n[2], -n[1])
	var px := _tex_size(tex)
	var u: Vector3 = f.u
	var v: Vector3 = f.v
	var cnt := pts.size()
	var uvs := PackedVector2Array()
	for k in cnt:
		var qx := poly[k * 3]
		var qy := poly[k * 3 + 1]
		var qz := poly[k * 3 + 2]
		var uu: float = (qx * u.x + qy * u.y + qz * u.z) / float(f.sx) + float(f.uo)
		var vv: float = (qx * v.x + qy * v.y + qz * v.z) / float(f.sy) + float(f.vo)
		uvs.append(Vector2(uu / px.x, vv / px.y))
	# the polygon is counter-clockwise seen from outside; Godot's front faces are clockwise
	for k in range(1, cnt - 1):
		for idx in [0, k + 1, k]:
			st.set_normal(gn)
			st.set_uv(uvs[idx])
			st.add_vertex(pts[idx])
		stats.tris += 1


func _emit_meshes(parent: Node3D, root: Node3D) -> void:
	var per_chunk := {}
	for key in _surf_tools:
		var ck: String = key.split("|")[0]
		if not per_chunk.has(ck):
			per_chunk[ck] = []
		per_chunk[ck].append(key)
	var keys := per_chunk.keys()
	keys.sort()
	for ck in keys:
		var mesh := ArrayMesh.new()
		var names: Array = per_chunk[ck]
		names.sort()
		for key in names:
			var st: SurfaceTool = _surf_tools[key]
			st.generate_tangents()
			st.commit(mesh)
			mesh.surface_set_name(mesh.get_surface_count() - 1, key.split("|")[1])
		var mi := MeshInstance3D.new()
		mi.name = "Chunk_%s" % ck.replace(",", "_").replace("-", "m")
		mi.mesh = mesh
		parent.add_child(mi)
		mi.owner = root
		stats.meshes += 1
	_surf_tools.clear()


func _emit_collision(parent: Node3D, root: Node3D) -> void:
	var keys := _col.keys()
	keys.sort()
	for key in keys:
		var parts: PackedStringArray = key.split("|")
		var phys := parts[1]
		var body := StaticBody3D.new()
		body.name = "Col_%s_%s" % [phys, parts[0].replace(",", "_").replace("-", "m")]
		var blocker := phys in ["clip", "blocker"]
		body.collision_layer = PHYS_BLOCKER if blocker else PHYS_WORLD
		body.collision_mask = 0
		body.set_meta("mat", "steel" if blocker else phys)
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true   # bullets measure a wall's thickness by casting back through it
		shape.set_faces(_col[key])
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
		body.owner = root
		cs.owner = root
		stats.bodies += 1
	_col.clear()


func _light(props: Dictionary, pos: Vector3, dir: Vector3) -> Light3D:
	var kind := str(props.get("kind", "bulb"))
	var col := Color(1.0, 0.75, 0.5)
	var c := str(props.get("_color", props.get("color", ""))).split(" ", false)
	if c.size() >= 3:
		var r := float(c[0])
		var g := float(c[1])
		var b := float(c[2])
		var k := 255.0 if maxf(r, maxf(g, b)) > 1.0 else 1.0
		col = Color(r / k, g / k, b / k)
	var energy := float(props.get("energy", "1.0"))
	var rng := float(props.get("range", "9"))
	var l: Light3D
	if kind in SPOT_KINDS:
		var sl := SpotLight3D.new()
		sl.spot_range = rng
		sl.spot_angle = float(props.get("cone", "45" if kind == "flood" else "60"))
		var pitch := deg_to_rad(float(props.get("pitch", "90")))
		var aim := Vector3(dir.x * cos(pitch), -sin(pitch), dir.z * cos(pitch)).normalized()
		sl.position = pos
		sl.basis = Basis.looking_at(aim, Vector3.UP if absf(aim.y) < 0.99 else Vector3.FORWARD)
		l = sl
	else:
		var ol := OmniLight3D.new()
		ol.omni_range = rng
		ol.omni_attenuation = 1.8 if kind == "candle" else 1.4
		ol.position = pos
		l = ol
	l.light_color = col
	l.light_energy = energy
	l.shadow_enabled = false
	l.set_meta("kind", kind)
	l.set_meta("fault", str(props.get("fault", "")))
	l.set_meta("axis", dir)
	return l


func _flight(steps: Array, name: String) -> Dictionary:
	## A stair from its step brushes: lowest and highest step, the direction it rises, foot and top on the floors.
	steps.sort_custom(func(a, b): return (a.hi as Vector3).y < (b.hi as Vector3).y)
	var first: Dictionary = steps[0]
	var last: Dictionary = steps[steps.size() - 1]
	var c0: Vector3 = (first.lo + first.hi) * 0.5
	var c1: Vector3 = (last.lo + last.hi) * 0.5
	var d := Vector3(c1.x - c0.x, 0.0, c1.z - c0.z)
	var run := d.length() / maxf(steps.size() - 1, 1)
	d = d.normalized()
	var rise := ((last.hi as Vector3).y - (first.hi as Vector3).y) / maxf(steps.size() - 1, 1)
	var ext: Vector3 = first.hi - first.lo
	var width := absf(ext.x) if absf(d.z) > absf(d.x) else absf(ext.z)
	var foot := Vector3(c0.x, (first.lo as Vector3).y, c0.z) - d * (run * 0.5 + 0.7)
	var top := Vector3(c1.x, (last.hi as Vector3).y + rise, c1.z) + d * (run * 0.5 + 0.7)
	return {"name": name, "foot": foot, "top": top, "dir": d, "width": width, "steps": steps.size()}
