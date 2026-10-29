extends RefCounted
## Outfits: a look ({slot: item id, slot + "_c": colourway index, "skin": tone index}) becomes one skinned mesh.
## The pieces (assets/models/gear/gear.glb, tools/blender/make_gear.py) are all bound to the character rig and share
## one material: a texture array picked per vertex (UV2.x layer, UV2.y roughness), coloured by the vertex colour,
## whose alpha marks the parts a colourway recolours. Building a look concatenates the chosen pieces into a single
## surface, so a whole outfit is one draw call; bare skin under clothes is only included where nothing covers it.
## Looks are cached: bots and players wearing the same thing share the mesh.

const GEAR := "res://assets/models/gear/gear.glb"
const DATA := "res://data/cosmetics.json"
const SHADER := """
shader_type spatial;
uniform sampler2DArray albedo_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_arr : filter_linear_mipmap_anisotropic, repeat_enable;
varying flat float v_layer;
varying float v_rough;
void vertex() {
	v_layer = floor(UV2.x);
	v_rough = 1.0 - UV2.y;   // glTF stores V flipped
}
// How many times finer than the pieces' own mapping each layer's weave repeats (camo, plaid and stripes keep
// their size; knits, twills and ripstop are fine).
const float TILE[16] = float[](2.0, 2.8, 2.6, 2.2, 3.0, 2.4, 1.6, 1.4, 1.0, 1.0, 2.2, 2.6, 1.4, 1.2, 1.4, 1.6);
void fragment() {
	vec3 uvw = vec3(UV * TILE[int(v_layer)], v_layer);
	ALBEDO = texture(albedo_arr, uvw).rgb * COLOR.rgb;
	ROUGHNESS = v_rough;
	METALLIC = v_layer > 14.5 ? 0.55 : 0.0;
	NORMAL_MAP = texture(normal_arr, uvw).rgb;
	NORMAL_MAP_DEPTH = 0.7;
}
"""
const SKIN_REGIONS := ["torso", "upperarm", "forearm", "thigh", "shin", "feet"]
const SLOT_ORDER := ["hair", "helmet", "face", "jacket", "shirt", "gloves", "elbow", "knee", "pants", "boots", "pack"]

static var data: Dictionary = {}
static var pieces: Dictionary = {}     # piece name -> surface arrays
static var skin: Skin = null
static var head_mesh: Mesh = null
static var head_skin: Skin = null
static var material: ShaderMaterial = null
static var _head_mats: Dictionary = {} # tone index -> material
static var _cache: Dictionary = {}     # look key -> ArrayMesh
static var _items: Dictionary = {}     # slot -> {item id -> item}
static var skin_color := Color(0.51, 0.36, 0.28)


static func ensure() -> bool:
	if not pieces.is_empty():
		return true
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		for s in data.slots:
			var m := {}
			for it in s.items:
				m[str(it.id)] = it
			_items[str(s.id)] = m
	if not ResourceLoader.exists(GEAR):
		return false
	var scn: Node = (load(GEAR) as PackedScene).instantiate()
	for mi in _all_meshes(scn):
		var n := str(mi.name)
		if n == "body_head":
			head_mesh = mi.mesh
			head_skin = mi.skin
			continue
		pieces[n] = mi.mesh.surface_get_arrays(0)
		if skin == null:
			skin = mi.skin
	scn.free()
	var sh := Shader.new()
	sh.code = SHADER
	material = ShaderMaterial.new()
	material.shader = sh
	material.set_shader_parameter("albedo_arr", load("res://assets/models/gear/gear_albedo.png"))
	material.set_shader_parameter("normal_arr", load("res://assets/models/gear/gear_normal.png"))
	if pieces.has("skin_torso"):
		var c: PackedColorArray = pieces.skin_torso[Mesh.ARRAY_COLOR]
		if not c.is_empty():
			# Sampled from the face's own texture by tools/blender/make_gear.py, so bare arms and legs match it.
			skin_color = c[0]
	return true


static func _all_meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


static func slots() -> Array:
	ensure()
	return data.get("slots", [])


static func item(slot: String, id: String) -> Dictionary:
	ensure()
	return _items.get(slot, {}).get(id, {})


static func default_look() -> Dictionary:
	ensure()
	return (data.get("default_look", {}) as Dictionary).duplicate()


static func normalized(look: Dictionary) -> Dictionary:
	## Fills missing slots from the default and drops unknown items (an older or newer client's look).
	var out := default_look()
	for k in look:
		var key := str(k)
		if key == "skin":
			out.skin = clampi(int(look[k]), 0, (data.skin_tones as Array).size() - 1)
		elif key.ends_with("_c"):
			out[key] = maxi(int(look[k]), 0)
		elif _items.has(key) and _items[key].has(str(look[k])):
			out[key] = str(look[k])
	return out


static func random_look(seed_value: int) -> Dictionary:
	## Bots: a believable mix (most wear pants, shoes and a shirt; a jacket half the time; gear now and then).
	ensure()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var look := {}
	var odds := {"hair": 0.85, "helmet": 0.45, "face": 0.3, "jacket": 0.55, "gloves": 0.35, "elbow": 0.2, "knee": 0.25, "pack": 0.4}
	for s in data.slots:
		var sid := str(s.id)
		var items: Array = (s.items as Array).filter(func(i): return str(i.id) != "none")
		var pick: Dictionary = items[rng.randi() % items.size()]
		if odds.has(sid) and rng.randf() > float(odds[sid]):
			look[sid] = "none"
		else:
			look[sid] = str(pick.id)
			look[sid + "_c"] = rng.randi() % maxi((pick.get("colors", [""]) as Array).size(), 1)
	look.skin = rng.randi() % (data.skin_tones as Array).size()
	return normalized(look)


static func key(look: Dictionary) -> String:
	var parts := []
	for s in SLOT_ORDER:
		parts.append("%s=%s:%d" % [s, str(look.get(s, "none")), int(look.get(s + "_c", 0))])
	parts.append("skin=%d" % int(look.get("skin", 0)))
	return ",".join(parts)


static func tone(look: Dictionary) -> Color:
	var tones: Array = data.get("skin_tones", [])
	var i := clampi(int(look.get("skin", 0)), 0, maxi(tones.size() - 1, 0))
	return Color.html(str(tones[i].mult)) if not tones.is_empty() else Color.WHITE


static func pieces_for(look: Dictionary) -> Array:
	## [[piece name, tint Color or null]] for a look, inner layers first, bare skin only where it shows.
	ensure()
	look = normalized(look)
	var covered := {}
	var jacket: Dictionary = item("jacket", str(look.jacket))
	var out: Array = []
	for s in SLOT_ORDER:
		var it: Dictionary = item(s, str(look.get(s, "none")))
		for c in it.get("covers", []):
			covered[c] = true
	var t := tone(look)
	var skin_tint := Color(skin_color.r * t.r, skin_color.g * t.g, skin_color.b * t.b)
	for r in SKIN_REGIONS:
		if not covered.has(r):
			out.append(["skin_" + r, skin_tint])
	var jacket_on := not jacket.is_empty() and str(jacket.get("id", "none")) != "none"
	# The hood goes up when nothing else is on the head; hair shows when neither hood nor headwear covers it.
	var helmet_on := str(look.get("helmet", "none")) != "none"
	var hood_up := jacket.has("hood") and not helmet_on
	for s in SLOT_ORDER:
		var it: Dictionary = item(s, str(look.get(s, "none")))
		if it.is_empty() or str(it.id) == "none":
			continue
		if s == "hair" and (helmet_on or hood_up):
			continue
		if s == "shirt" and jacket.get("closed", false):
			continue   # hidden under a closed jacket
		var cols: Array = it.get("colors", [])
		var tint = null
		if not cols.is_empty():
			tint = Color.html(str(cols[clampi(int(look.get(s + "_c", 0)), 0, cols.size() - 1)])).srgb_to_linear()
		var names: Array = it.get("over", it.pieces) if jacket_on and it.has("over") else it.get("pieces", [])
		for n in names:
			out.append([str(n), tint])
		if s == "jacket" and hood_up:
			out.append([str(it.hood), tint])
	return out


static func build(look: Dictionary) -> ArrayMesh:
	if not ensure():
		return null
	look = normalized(look)
	var k := key(look)
	if _cache.has(k):
		return _cache[k]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tangs := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	var has_tan := true
	for p in pieces_for(look):
		var a: Array = pieces.get(p[0], [])
		if a.is_empty():
			continue
		var base := verts.size()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		verts.append_array(v)
		norms.append_array(a[Mesh.ARRAY_NORMAL])
		if a[Mesh.ARRAY_TANGENT] != null and has_tan:
			tangs.append_array(a[Mesh.ARRAY_TANGENT])
		else:
			has_tan = false
		uv.append_array(a[Mesh.ARRAY_TEX_UV])
		uv2.append_array(a[Mesh.ARRAY_TEX_UV2])
		var c: PackedColorArray = (a[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
		if p[1] != null:
			var tint: Color = p[1]
			for i in c.size():
				if c[i].a > 0.5:
					c[i] = Color(tint.r, tint.g, tint.b, 1.0)
		col.append_array(c)
		bones.append_array(a[Mesh.ARRAY_BONES])
		weights.append_array(a[Mesh.ARRAY_WEIGHTS])
		var ii: PackedInt32Array = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
		for i in ii.size():
			ii[i] += base
		idx.append_array(ii)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	if has_tan and tangs.size() == verts.size() * 4:
		arr[Mesh.ARRAY_TANGENT] = tangs
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, material)
	_cache[k] = m
	return m


static func head_material(look: Dictionary) -> Material:
	## The face and hands keep their painted texture, darkened or lightened for the skin tone.
	var i := int(normalized(look).get("skin", 0))
	if _head_mats.has(i):
		return _head_mats[i]
	var base: Material = head_mesh.surface_get_material(0) if head_mesh else null
	var m: Material = base
	if base is StandardMaterial3D:
		m = base.duplicate()
		var t := tone(look)
		(m as StandardMaterial3D).albedo_color = Color(t.r, t.g, t.b) * (base as StandardMaterial3D).albedo_color
	_head_mats[i] = m
	return m


static func dress(skel: Skeleton3D, look: Dictionary, layers: int, shadow: GeometryInstance3D.ShadowCastingSetting) -> Array:
	## Adds the head and the outfit under a character's skeleton. Returns the two MeshInstance3D nodes.
	if not ensure() or skel == null:
		return []
	var out := []
	var head := MeshInstance3D.new()
	head.name = "OutfitHead"
	head.mesh = head_mesh
	head.skin = head_skin
	head.material_override = head_material(look)
	var gear := MeshInstance3D.new()
	gear.name = "Outfit"
	gear.mesh = build(look)
	gear.skin = skin
	for mi in [head, gear]:
		skel.add_child(mi)
		mi.skeleton = mi.get_path_to(skel)
		mi.layers = layers
		mi.cast_shadow = shadow
		out.append(mi)
	return out
