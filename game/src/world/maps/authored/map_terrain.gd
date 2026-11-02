@tool
extends RefCounted
## (r27) A map's uneven ground, made with Terrain3D (addons/terrain_3d, built from the source the user keeps at
## A:\Python\terrain). Standing rule from 2026-11-02: every map with uneven ground uses Terrain3D, under the pieces of
## its map file. The ground is sculpted, painted (textures) and planted (ground cover) in the Godot editor with
## Terrain3D's own tools, in the map's editor scene (editor/maps/<id>.tscn, a Terrain3D node beside the pieces).
##
## The map file names it in its header:
##   "terrain": {"dir": "res://maps/<id>/terrain" (Terrain3D's data directory: one file per region),
##               "spacing": 0.5 (metres between height samples), "region_size": 256 (samples per region side),
##               "area": [x0, z0, x1, z1] (what the baked heights cover), "phys": "dirt" (footsteps, bullets),
##               "assets" / "material" / "mobile_material": Terrain3D resources (defaults in the data directory)}
##
## Saving the map in the map editor bakes the heights into <dir>/heights.res (an Image of 32-bit floats over "area",
## one sample per "spacing"). The game collides with that heightfield on every machine, the bots survey it and
## ground_height() reads it, so a server never needs the extension; clients draw the ground with Terrain3D itself
## (on phones with Terrain3D's lightweight shader). Where the extension is missing (a platform it was not built
## for), a plain mesh made from the baked heights stands in.

const DEF_SPACING := 0.5
const DEF_REGION := 256

var spec := {}
var x0 := 0.0
var z0 := 0.0
var step := DEF_SPACING
var nx := 0
var nz := 0
var h := PackedFloat32Array()
var lo := 0.0
var hi := 0.0


static func spec_of(doc: Dictionary) -> Dictionary:
	## The header's "terrain" block with every default filled in, or {} when the map has flat ground.
	var t = doc.get("terrain", null)
	if not (t is Dictionary):
		return {}
	var id := str(doc.get("id", ""))
	var dir := str(t.get("dir", "res://maps/%s/terrain" % id))
	var area = t.get("area", doc.get("bounds", [-64, -64, 64, 64]))
	return {"dir": dir, "spacing": float(t.get("spacing", DEF_SPACING)), "region_size": int(t.get("region_size", DEF_REGION)),
		"area": [float(area[0]), float(area[1]), float(area[2]), float(area[3])],
		"assets": str(t.get("assets", dir + "/assets.tres")), "material": str(t.get("material", dir + "/material.tres")),
		"mobile_material": str(t.get("mobile_material", dir + "/material_mobile.tres")),
		"heights": str(t.get("heights", dir + "/heights.res")), "phys": str(t.get("phys", "dirt")),
		"mesh_size": int(t.get("mesh_size", 48)), "mesh_lods": int(t.get("mesh_lods", 7)),
		"cast_shadows": bool(t.get("cast_shadows", true))}


static func load_for(doc: Dictionary):
	## The baked heights of a map with Terrain3D ground, or null (flat ground, or not baked yet).
	var s := spec_of(doc)
	if s.is_empty():
		return null
	if not ResourceLoader.exists(s.heights):
		push_warning("[map] %s has Terrain3D ground but no baked heights (%s): save it in the map editor" % [str(doc.get("id", "")), s.heights])
		return null
	var img = load(s.heights)
	if not (img is Image):
		return null
	var t = load("res://src/world/maps/authored/map_terrain.gd").new()
	t.set_image(img as Image, s)
	return t


func set_image(img: Image, s: Dictionary) -> void:
	spec = s
	var im := img
	if im.get_format() != Image.FORMAT_RF:
		im = img.duplicate()
		im.convert(Image.FORMAT_RF)
	nx = im.get_width()
	nz = im.get_height()
	h = im.get_data().to_float32_array()
	var a: Array = s.area
	x0 = float(a[0])
	z0 = float(a[1])
	step = (float(a[2]) - x0) / maxf(nx - 1, 1)
	lo = INF
	hi = -INF
	for v in h:
		lo = minf(lo, v)
		hi = maxf(hi, v)


func covers(x: float, z: float) -> bool:
	return x >= x0 and z >= z0 and x <= x0 + (nx - 1) * step and z <= z0 + (nz - 1) * step


func height_at(x: float, z: float) -> float:
	## The ground's height (bilinear between samples, as the heightfield collides), or NAN outside the area.
	if nx < 2 or not covers(x, z):
		return NAN
	var fx := (x - x0) / step
	var fz := (z - z0) / step
	var ix := mini(int(fx), nx - 2)
	var iz := mini(int(fz), nz - 2)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * nx + ix
	var a := lerpf(h[i], h[i + 1], tx)
	var b := lerpf(h[i + nx], h[i + nx + 1], tx)
	return lerpf(a, b, tz)


func collision_body(layer: int) -> StaticBody3D:
	## The heightfield the game collides with (Jolt takes the scaled heightfield as it is).
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = layer
	body.collision_mask = 0
	body.set_meta("mat", str(spec.get("phys", "dirt")))
	var shape := HeightMapShape3D.new()
	shape.map_width = nx
	shape.map_depth = nz
	shape.map_data = h
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(step, 1.0, step)
	cs.position = Vector3(x0 + (nx - 1) * step * 0.5, 0.0, z0 + (nz - 1) * step * 0.5)
	body.add_child(cs)
	return body


## The render layer the ground and its plants go on in the game: the one lamps and muzzle flashes leave out of
## their shadow maps (Defs.RENDER_INTERIOR_PROPS), which the camera draws. A torch's shadow pass would otherwise draw
## the whole terrain and every fern again (millions of triangles a frame); the moon still shadows them.
const GAME_LAYER := 32
## On phones the ground cover is drawn this much nearer.
const MOBILE_COVER_RANGE := 0.6


static func make_node(s: Dictionary, mobile: bool, in_game := true) -> Node3D:
	## Terrain3D drawing the ground (no collision of its own: the baked heightfield collides). null without the
	## extension.
	if s.is_empty() or not ClassDB.class_exists("Terrain3D"):
		return null
	var t: Node3D = ClassDB.instantiate("Terrain3D")
	t.name = "Terrain3D"
	# No "region_size": its setter resizes the data (an editor action) and crashes on a node not yet set up; the
	# region size comes from the data directory's own files.
	t.set("vertex_spacing", float(s.spacing))
	t.set("collision_mode", 0)
	var mp: String = s.mobile_material if mobile and ResourceLoader.exists(s.mobile_material) else s.material
	if ResourceLoader.exists(mp):
		t.set("material", load(mp))
	if ResourceLoader.exists(s.assets):
		t.set("assets", load(s.assets))
	t.set("mesh_size", int(s.mesh_size) if not mobile else mini(int(s.mesh_size), 32))
	t.set("mesh_lods", int(s.mesh_lods) if not mobile else mini(int(s.mesh_lods), 6))
	t.set("cast_shadows", 1 if bool(s.cast_shadows) and not mobile else 0)
	if in_game:
		t.set("render_layers", GAME_LAYER)
		var assets = t.get("assets")
		if assets != null:
			for i in int(assets.get_mesh_count()):
				var ma = assets.get_mesh_asset(i)
				if ma == null:
					continue
				ma.set("visibility_layers", GAME_LAYER)
				ma.set("cast_shadows", 0)
				if mobile:
					ma.set("lod0_range", float(ma.get("lod0_range")) * MOBILE_COVER_RANGE)
	t.set("data_directory", str(s.dir))
	return t


func fallback_mesh(mat: Material) -> MeshInstance3D:
	## The ground as a plain mesh from the baked heights (2 m triangles), for a platform without the extension.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := maxi(1, int(round(2.0 / step)))
	var cx := int((nx - 1) / k) + 1
	var cz := int((nz - 1) / k) + 1
	for jz in cz:
		for jx in cx:
			var x := x0 + jx * k * step
			var z := z0 + jz * k * step
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, h[mini(jz * k, nz - 1) * nx + mini(jx * k, nx - 1)], z))
	for jz in cz - 1:
		for jx in cx - 1:
			var i := jz * cx + jx
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + cx)
			st.add_index(i + 1)
			st.add_index(i + cx + 1)
			st.add_index(i + cx)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "TerrainFallback"
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi


# ------------------------------------------------------------------ baking (the map editor's save, the draft tool)

static func bake(terrain: Node, s: Dictionary) -> Image:
	## The heights a Terrain3D node has now, over the spec's area at its spacing: saved as <dir>/heights.res.
	var a: Array = s.area
	var sp := float(s.spacing)
	var w := int(round((float(a[2]) - float(a[0])) / sp)) + 1
	var d := int(round((float(a[3]) - float(a[1])) / sp)) + 1
	var data = terrain.get("data")
	var buf := PackedFloat32Array()
	buf.resize(w * d)
	for jz in d:
		for jx in w:
			var v: float = data.get_height(Vector3(float(a[0]) + jx * sp, 0.0, float(a[1]) + jz * sp))
			buf[jz * w + jx] = 0.0 if is_nan(v) else v
	var img := Image.create_from_data(w, d, false, Image.FORMAT_RF, buf.to_byte_array())
	return img


static func save_baked(img: Image, s: Dictionary, map_id: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(str(s.dir)))
	var err := ResourceSaver.save(img, str(s.heights), ResourceSaver.FLAG_COMPRESS)
	# A 16-bit picture of it for tools/map_plan.py (outside game/, so it is not imported)
	var root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var out := root.path_join("work/maps/%s" % map_id)
	DirAccess.make_dir_recursive_absolute(out)
	var raw := img.get_data().to_float32_array()
	var mn := INF
	var mx := -INF
	for v in raw:
		mn = minf(mn, v)
		mx = maxf(mx, v)
	var g := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_L8)
	for jz in img.get_height():
		for jx in img.get_width():
			var v := raw[jz * img.get_width() + jx]
			g.set_pixel(jx, jz, Color.from_hsv(0, 0, (v - mn) / maxf(mx - mn, 0.01)))
	g.save_png(out.path_join("heights.png"))
	var f := FileAccess.open(out.path_join("heights.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"area": s.area, "min": mn, "max": mx, "w": img.get_width(), "h": img.get_height()}))
		f.close()
	return err
