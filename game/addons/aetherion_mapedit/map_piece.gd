@tool
extends Node3D
## (r26) One piece of a map-editor map (a wall, a floor, stairs, a light, a spawn...) in the Godot map editor. Its
## node name is the piece's id. Move and turn it with the gizmo (only the turn about up is kept: tilt a box with
## "Tilt"); scaling a box, floor or wall changes its size. Drag the orange handles for a wall's ends or a box's size.
## Everything else is in the Inspector. The map file is written by the map's root (Save map, or Ctrl+S).

const MapDoc := preload("res://src/world/maps/authored/map_doc.gd")
const MapScene := preload("res://addons/aetherion_map/map_scene.gd")

const LIGHT_KINDS := "bulb,tube,lamp,flood,street,down,candle"
const FAULTS := ",flicker,dying,starter,sag,candle"
const TEAM_COLORS := {1: Color(0.25, 0.5, 1.0), 2: Color(1.0, 0.35, 0.25), 3: Color(0.3, 0.9, 0.35)}
const SPOT_COLORS := {"hide": Color(0.65, 0.35, 1.0), "snipe": Color(1.0, 0.2, 0.2), "cover": Color(1.0, 0.6, 0.8)}

## The fields each type shows in the Inspector: [key, type, hint, hint string, what it is].
const FIELDS := {
	"box": [["size", TYPE_VECTOR3, 0, "", "width (x), height, depth (z), metres"], ["tilt", TYPE_VECTOR2, 0, "", "pitch, roll in degrees (ramps, roofs)"],
		["mat", TYPE_STRING, -1, "", "texture"], ["top", TYPE_STRING, -1, "", "texture on top (empty: mat)"],
		["under", TYPE_STRING, -1, "", "texture underneath"], ["solid", TYPE_BOOL, 0, "", "collides (off: drawn only)"]],
	"floor": [["size", TYPE_VECTOR2, 0, "", "width (x), depth (z)"], ["t", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.02,2,0.01", "thickness below the top"],
		["tilt", TYPE_VECTOR2, 0, "", "pitch, roll in degrees"], ["mat", TYPE_STRING, -1, "", "texture on top"],
		["under", TYPE_STRING, -1, "", "texture underneath (a ceiling)"], ["edge", TYPE_STRING, -1, "", "texture on the edges"],
		["solid", TYPE_BOOL, 0, "", "collides"]],
	"wall": [["len", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.05,200,0.01", "length (from -> to)"], ["h", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.05,30,0.01", "height"],
		["t", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.02,3,0.01", "thickness"], ["mat", TYPE_STRING, -1, "", "texture (both faces)"],
		["mat2", TYPE_STRING, -1, "", "texture on the left face, walking from -> to (empty: mat)"], ["edge", TYPE_STRING, -1, "", "texture on ends, top and reveals"],
		["openings", TYPE_ARRAY, 0, "", "doors and windows: {at (m from 'from' to its centre), w, h, sill, door}"],
		["solid", TYPE_BOOL, 0, "", "collides"]],
	"poly": [["points", TYPE_PACKED_VECTOR2_ARRAY, 0, "", "outline around the node (x, z)"], ["h", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.02,30,0.01", "height"],
		["mat", TYPE_STRING, -1, "", "texture"], ["top", TYPE_STRING, -1, "", "texture on top"], ["under", TYPE_STRING, -1, "", "texture underneath"],
		["solid", TYPE_BOOL, 0, "", "collides"]],
	"column": [["r", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.02,5,0.01", "radius"], ["h", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.05,30,0.01", "height"],
		["sides", TYPE_INT, PROPERTY_HINT_RANGE, "3,32", "sides"], ["mat", TYPE_STRING, -1, "", "texture"], ["solid", TYPE_BOOL, 0, "", "collides"]],
	"stairs": [["w", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.6,10,0.01", "width"], ["rise", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.2,20,0.01", "height climbed"],
		["run", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.2,0.5,0.01", "depth of each step"], ["landing", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,10,0.01", "landing slab at the top (0: a floor is there)"],
		["rail", TYPE_BOOL, 0, "", "side rails"], ["mat", TYPE_STRING, -1, "", "texture"], ["top", TYPE_STRING, -1, "", "texture of the treads"]],
	"ramp": [["w", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.3,20,0.01", "width"], ["len", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.2,50,0.01", "length"],
		["rise", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.05,20,0.01", "height"], ["mat", TYPE_STRING, -1, "", "texture"], ["top", TYPE_STRING, -1, "", "texture of the slope"],
		["solid", TYPE_BOOL, 0, "", "collides"]],
	"light": [["kind", TYPE_STRING, PROPERTY_HINT_ENUM, LIGHT_KINDS, "fitting"], ["color", TYPE_COLOR, PROPERTY_HINT_COLOR_NO_ALPHA, "", "colour"],
		["energy", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,16,0.05", "brightness"], ["range", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.5,80,0.1", "reach, metres"],
		["fault", TYPE_STRING, PROPERTY_HINT_ENUM, FAULTS, "fault (faulty lamps flicker)"], ["pitch", TYPE_FLOAT, PROPERTY_HINT_RANGE, "-90,90,1", "spots: aim below level"],
		["cone", TYPE_FLOAT, PROPERTY_HINT_RANGE, "5,170,1", "spots: cone angle"]],
	"spawn": [["team", TYPE_INT, PROPERTY_HINT_RANGE, "1,3", "team"], ["for", TYPE_STRING, PROPERTY_HINT_ENUM, ",2,3", "used with two teams (2), three (3), or both (empty)"]],
	"landmark": [],
	"spot": [["kind", TYPE_STRING, PROPERTY_HINT_ENUM, "hide,snipe,cover", "what bots do here"]],
	"prop": [["model", TYPE_STRING, -2, "", "model library name"], ["physics", TYPE_BOOL, 0, "", "can be pushed and knocked over"]],
}

var data: Dictionary = {}:
	set(v):
		data = v.duplicate(true)
		_apply_data()
var _built := false
var _syncing := false
var _rebuild_queued := false
var _preview: Node3D = null
var _label: Label3D = null
static var _ms = null
static var _tex_list := ""
static var _prop_list := ""
static var _mats := {}


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	set_notify_local_transform(true)
	_queue_rebuild()


func setup(p: Dictionary) -> void:
	data = p


func piece_type() -> String:
	return str(data.get("type", "box"))


func _apply_data() -> void:
	_syncing = true
	transform = MapDoc.frame(data)
	_syncing = false
	var pid := str(data.get("id", ""))
	if pid != "" and str(name) != pid:
		name = pid.validate_node_name()
	_queue_rebuild()


func to_piece() -> Dictionary:
	## The piece as the file stores it (its id from the node name, its position and bearing from the node).
	var p := data.duplicate(true)
	p.id = str(name)
	MapDoc.set_frame(p, transform)
	var par := get_parent()
	if par != null and par.has_meta("layer"):
		p.layer = str(par.get_meta("layer"))
	return p


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and not _syncing and Engine.is_editor_hint():
		_on_moved()
	elif what == NOTIFICATION_PATH_RENAMED and Engine.is_editor_hint():
		data.id = str(name)
		_update_label()


func _on_moved() -> void:
	## A move or a turn writes the frame back. Scaling a box, a floor or a wall resizes it; a tilt or a scale left on
	## the node is taken off again (the file keeps a bearing only).
	var xf := transform
	var sc := xf.basis.get_scale()
	var t := piece_type()
	if not sc.is_equal_approx(Vector3.ONE):
		match t:
			"box":
				var s := MapDoc.v3(data.get("size"), Vector3(2, 2, 2)) * sc
				data.size = [snappedf(s.x, 0.01), snappedf(s.y, 0.01), snappedf(s.z, 0.01)]
			"floor":
				var s2 := MapDoc.v2(data.get("size"), Vector2(4, 4))
				data.size = [snappedf(s2.x * sc.x, 0.01), snappedf(s2.y * sc.z, 0.01)]
			"wall":
				var ln := MapDoc.wall_len(data) * sc.x
				_set_wall_len(ln)
				data.h = snappedf(float(data.get("h", 3.0)) * sc.y, 0.01)
				data.t = snappedf(float(data.get("t", 0.2)) * sc.z, 0.01)
		_queue_rebuild()
	MapDoc.set_frame(data, xf.orthonormalized())
	var clean := MapDoc.frame(data)
	if not clean.basis.is_equal_approx(xf.basis):
		_syncing = true
		transform = clean
		_syncing = false
	_dirty()


func _set_wall_len(ln: float) -> void:
	var a := MapDoc.v2(data.get("from"))
	var b := MapDoc.v2(data.get("to"), Vector2(1, 0))
	var mid := (a + b) * 0.5
	var dir := (b - a).normalized() if a.distance_to(b) > 1e-4 else Vector2(1, 0)
	ln = maxf(ln, 0.05)
	data.from = [snappedf(mid.x - dir.x * ln * 0.5, 0.001), snappedf(mid.y - dir.y * ln * 0.5, 0.001)]
	data.to = [snappedf(mid.x + dir.x * ln * 0.5, 0.001), snappedf(mid.y + dir.y * ln * 0.5, 0.001)]


func _dirty() -> void:
	var r = _root()
	if r != null:
		r.mark_dirty()
	update_gizmos()


func _root():
	var n := get_parent()
	while n != null:
		if n.has_method("mark_dirty"):
			return n
		n = n.get_parent()
	return null


# ------------------------------------------------------------------ the Inspector

func _get_property_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"name": "Piece", "type": TYPE_NIL, "usage": PROPERTY_USAGE_CATEGORY})
	out.append({"name": "data", "type": TYPE_DICTIONARY, "usage": PROPERTY_USAGE_STORAGE})
	out.append({"name": "piece_kind", "type": TYPE_STRING, "usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY})
	out.append({"name": "piece_name", "type": TYPE_STRING, "usage": PROPERTY_USAGE_EDITOR})
	out.append({"name": "piece_note", "type": TYPE_STRING, "hint": PROPERTY_HINT_MULTILINE_TEXT, "usage": PROPERTY_USAGE_EDITOR})
	# the piece's own fields, shown without their "p_" prefix under the piece's type
	out.append({"name": piece_type().capitalize(), "type": TYPE_NIL, "usage": PROPERTY_USAGE_GROUP, "hint_string": "p_"})
	if piece_type() in MapDoc.GEOMETRY:
		out.append({"name": "p_tex_size", "type": TYPE_FLOAT, "hint": PROPERTY_HINT_RANGE, "hint_string": "0,64,0.1", "usage": PROPERTY_USAGE_EDITOR})
	for f in FIELDS.get(piece_type(), []):
		var hint := int(f[2])
		var hs := str(f[3])
		if hint == -1:
			hint = PROPERTY_HINT_ENUM_SUGGESTION
			hs = _textures()
		elif hint == -2:
			hint = PROPERTY_HINT_ENUM_SUGGESTION
			hs = _props()
		out.append({"name": "p_" + str(f[0]), "type": int(f[1]), "hint": hint, "hint_string": hs, "usage": PROPERTY_USAGE_EDITOR})
	return out


func _get(prop: StringName):
	var k := str(prop)
	match k:
		"piece_kind":
			return piece_type()
		"piece_name":
			return str(data.get("name", ""))
		"piece_note":
			return str(data.get("note", ""))
	if not k.begins_with("p_"):
		return null
	k = k.substr(2)
	var f := _field(k)
	if f.is_empty():
		return null
	var v = data.get(k, null)
	match int(f[1]):
		TYPE_VECTOR3:
			return MapDoc.v3(v)
		TYPE_VECTOR2:
			return MapDoc.v2(v)
		TYPE_FLOAT:
			if k == "len":
				return MapDoc.wall_len(data)
			return float(v) if v != null else 0.0
		TYPE_INT:
			return int(v) if v != null else 0
		TYPE_BOOL:
			return bool(v) if v != null else (k == "solid")
		TYPE_COLOR:
			return Color.from_string(str(v), Color(1, 0.8, 0.55))
		TYPE_PACKED_VECTOR2_ARRAY:
			var pa := PackedVector2Array()
			for q in (v if v is Array else []):
				pa.append(MapDoc.v2(q))
			return pa
		TYPE_ARRAY:
			return v if v is Array else []
	return str(v) if v != null else ""


func _set(prop: StringName, value) -> bool:
	var k := str(prop)
	match k:
		"piece_name":
			_put("name", str(value))
			_update_label()
			return true
		"piece_note":
			_put("note", str(value))
			return true
	if not k.begins_with("p_"):
		return false
	k = k.substr(2)
	var f := _field(k)
	if f.is_empty():
		return false
	match int(f[1]):
		TYPE_VECTOR3:
			var v3: Vector3 = value
			data[k] = [snappedf(v3.x, 0.001), snappedf(v3.y, 0.001), snappedf(v3.z, 0.001)]
		TYPE_VECTOR2:
			var v2: Vector2 = value
			data[k] = [snappedf(v2.x, 0.001), snappedf(v2.y, 0.001)]
		TYPE_FLOAT:
			if k == "len":
				_set_wall_len(float(value))
			else:
				data[k] = snappedf(float(value), 0.001)
		TYPE_COLOR:
			data[k] = "#" + (value as Color).to_html(false)
		TYPE_PACKED_VECTOR2_ARRAY:
			var arr := []
			for q in (value as PackedVector2Array):
				arr.append([snappedf(q.x, 0.001), snappedf(q.y, 0.001)])
			data[k] = arr
		TYPE_STRING:
			_put(k, str(value))
		_:
			data[k] = value
	_queue_rebuild()
	_dirty()
	return true


func _put(k: String, v: String) -> void:
	if v == "":
		data.erase(k)
	else:
		data[k] = v
	_dirty()


func _property_can_revert(prop: StringName) -> bool:
	return str(prop).begins_with("p_")


func _property_get_revert(prop: StringName):
	var k := str(prop).substr(2)
	var dv = MapDoc.DEFAULTS.get(piece_type(), {}).get(k, null)
	if dv == null:
		return null
	var f := _field(k)
	match int(f[1]):
		TYPE_VECTOR3:
			return MapDoc.v3(dv)
		TYPE_VECTOR2:
			return MapDoc.v2(dv)
		TYPE_COLOR:
			return Color.from_string(str(dv), Color.WHITE)
	return dv


func _field(k: String) -> Array:
	if k == "tex_size":
		return ["tex_size", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,64,0.1", "metres one texture repeat covers (0: the material's own)"]
	for f in FIELDS.get(piece_type(), []):
		if str(f[0]) == k:
			return f
	return []


static func _textures() -> String:
	if _tex_list == "":
		var names := []
		var d := DirAccess.open(MapDoc.TEX_ROOT)
		if d != null:
			for sub in d.get_directories():
				for fn in DirAccess.get_files_at(MapDoc.TEX_ROOT + "/" + sub):
					if fn.ends_with(".png"):
						names.append("%s/%s" % [sub, fn.get_basename()])
		names.sort()
		_tex_list = ",".join(PackedStringArray(names))
	return _tex_list


static func _props() -> String:
	if _prop_list == "":
		var lib = load("res://src/world/model_lib.gd")
		var names: Array = (lib.PROPS as Dictionary).keys() if lib != null else []
		names.sort()
		_prop_list = ",".join(PackedStringArray(names))
	return _prop_list


# ------------------------------------------------------------------ the preview

func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree() or not Engine.is_editor_hint():
		return
	if _preview != null:
		_preview.free()
	_preview = Node3D.new()
	_preview.name = "_preview"
	add_child(_preview, false, Node.INTERNAL_MODE_FRONT)
	var t := piece_type()
	if t in MapDoc.GEOMETRY:
		_build_geometry()
	else:
		_build_thing(t)
	_update_label()
	update_gizmos()


func _build_geometry() -> void:
	if _ms == null:
		_ms = MapScene.new()
		_ms.configure({"chunk_size": 100000.0})
	var local := data.duplicate(true)
	var sc: Node3D = _ms.build_entities(MapDoc.entities({"pieces": [local]}, [], true), "piece")
	if sc == null:
		return
	var geo := sc.get_node_or_null("Geometry")
	if geo != null:
		for c in geo.get_children():
			geo.remove_child(c)
			c.owner = null
			_preview.add_child(c)
	sc.free()


func _build_thing(t: String) -> void:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match t:
		"spawn":
			var cap := CapsuleMesh.new()
			cap.radius = 0.28
			cap.height = 1.75
			mi.mesh = cap
			mi.position = Vector3(0, 0.875, 0)
			mi.material_override = _mat(TEAM_COLORS.get(int(data.get("team", 1)), Color.WHITE), 0.55)
			_preview.add_child(mi)
			_arrow(Color(1, 1, 1), 1.0)
		"light":
			var sp := SphereMesh.new()
			sp.radius = 0.12
			sp.height = 0.24
			mi.mesh = sp
			var col := Color.from_string(str(data.get("color", "#ffc98a")), Color(1, 0.8, 0.55))
			var m := _mat(col, 1.0)
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 3.0
			mi.material_override = m
			_preview.add_child(mi)
			# the lamp itself, so the editor shows how the place is lit (the game takes the lamp over)
			if _ms == null:
				_ms = MapScene.new()
				_ms.configure({"chunk_size": 100000.0})
			var sc: Node3D = _ms.build_entities(MapDoc.entities({"pieces": [data.duplicate(true)]}, [], true), "piece")
			if sc != null:
				for l in sc.get_node("Lights").get_children():
					l.get_parent().remove_child(l)
					l.owner = null
					(l as Light3D).shadow_enabled = true
					_preview.add_child(l)
				sc.free()
			if str(data.get("kind", "")) in MapDoc.SPOT_LIGHTS:
				_arrow(col, 0.7)
		"landmark":
			var cy := CylinderMesh.new()
			cy.top_radius = 0.04
			cy.bottom_radius = 0.04
			cy.height = 2.4
			mi.mesh = cy
			mi.position = Vector3(0, 1.2, 0)
			mi.material_override = _mat(Color(1.0, 0.85, 0.2), 1.0)
			_preview.add_child(mi)
			var flag := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(0.7, 0.4, 0.02)
			flag.mesh = bx
			flag.position = Vector3(0.37, 2.2, 0)
			flag.material_override = _mat(Color(1.0, 0.85, 0.2), 1.0)
			_preview.add_child(flag)
		"spot":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.3
			cone.height = 0.6
			mi.mesh = cone
			mi.position = Vector3(0, 0.3, 0)
			mi.material_override = _mat(SPOT_COLORS.get(str(data.get("kind", "hide")), Color.WHITE), 0.8)
			_preview.add_child(mi)
			_arrow(SPOT_COLORS.get(str(data.get("kind", "hide")), Color.WHITE), 1.3)
		"prop":
			var shown := _prop_preview(str(data.get("model", "")))
			if shown == null:
				var b2 := BoxMesh.new()
				b2.size = Vector3(0.8, 0.8, 0.8)
				mi.mesh = b2
				mi.position = Vector3(0, 0.4, 0)
				mi.material_override = _mat(Color(1, 0, 1), 0.6)
				_preview.add_child(mi)
			else:
				_preview.add_child(shown)
				mi.free()


func _arrow(col: Color, ln: float) -> void:
	var a := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.06, 0.06, ln)
	a.mesh = bx
	a.position = Vector3(0, 0.05 + (1.2 if piece_type() == "spawn" else 0.0), -ln * 0.5)
	a.material_override = _mat(col, 1.0)
	_preview.add_child(a)
	var tip := MeshInstance3D.new()
	var cn := CylinderMesh.new()
	cn.top_radius = 0.0
	cn.bottom_radius = 0.14
	cn.height = 0.3
	tip.mesh = cn
	tip.rotation = Vector3(-PI / 2.0, 0, 0)
	tip.position = Vector3(0, a.position.y, -ln - 0.12)
	tip.material_override = _mat(col, 1.0)
	_preview.add_child(tip)


func _prop_preview(model: String) -> Node3D:
	## The model the game will place, as the model library finds it (a box for primitives).
	var lib = load("res://src/world/model_lib.gd")
	if lib == null:
		return null
	var s: Dictionary = (lib.PROPS as Dictionary).get(model, {})
	if s.is_empty():
		return null
	if s.has("prim"):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s.size
		mi.mesh = bm
		mi.position = Vector3(0, (s.size as Vector3).y * 0.5, 0)
		mi.material_override = _mat(Color(0.7, 0.62, 0.48), 1.0)
		return mi
	var path := str(s.get("path", ""))
	if path == "":
		var id := str(s.get("model", model))
		for cand in [lib.PH_PROCESSED + id + ".gltf", lib.PROCESSED + id + ".glb", lib.PH + id + "/" + id + "_1k.gltf"]:
			if ResourceLoader.exists(cand):
				path = cand
				break
	if path == "" or not ResourceLoader.exists(path):
		return null
	var ps = load(path)
	if not (ps is PackedScene):
		return null
	var n: Node3D = (ps as PackedScene).instantiate()
	# seated like the game seats it: its lowest point on the floor
	var lo := INF
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi2 := c as MeshInstance3D
		if mi2.mesh == null:
			continue
		var xf := Transform3D()
		var q: Node = mi2
		while q != null and q != n:
			if q is Node3D:
				xf = (q as Node3D).transform * xf
			q = q.get_parent()
		var ab: AABB = xf * mi2.mesh.get_aabb()
		lo = minf(lo, ab.position.y)
	if lo != INF:
		n.position.y = -lo
	return n


static func _mat(c: Color, alpha: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [c.to_html(), alpha]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(c.r, c.g, c.b, alpha)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if alpha < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return _mats[key]


func _update_label() -> void:
	if not is_inside_tree() or _preview == null:
		return
	if _label == null or not is_instance_valid(_label):
		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 30
		_label.pixel_size = 0.004
		_label.outline_size = 8
		_label.no_depth_test = false
		_label.visibility_range_end = 28.0
		add_child(_label, false, Node.INTERNAL_MODE_FRONT)
	var r = _root()
	_label.visible = r == null or bool(r.get("show_labels"))
	var ab := MapDoc.bounds_local(data)
	_label.position = Vector3(ab.get_center().x, ab.end.y + 0.35, ab.get_center().z)
	var nm := str(data.get("name", ""))
	var t := piece_type()
	var line2 := t
	match t:
		"spawn":
			line2 = "team %d" % int(data.get("team", 1))
		"spot":
			line2 = str(data.get("kind", "hide"))
		"prop":
			line2 = str(data.get("model", ""))
		"light":
			line2 = "%s %s" % [str(data.get("kind", "")), str(data.get("fault", ""))]
	_label.text = "%s%s\n%s" % [str(name), (" · " + nm) if nm != "" else "", line2.strip_edges()]


# ------------------------------------------------------------------ picking (the plugin and the gizmo use these)

func local_brushes() -> Array:
	return MapDoc.brushes(data) if piece_type() in MapDoc.GEOMETRY else []


func ray_hit(o: Vector3, d: Vector3) -> float:
	## Where a world ray first meets this piece (distance along d), or -1.
	var inv := global_transform.affine_inverse()
	var lo: Vector3 = inv * o
	var ld: Vector3 = (inv.basis * d)
	var best := -1.0
	var brs := local_brushes()
	if brs.is_empty():
		var ab := MapDoc.bounds_local(data)
		var hit = ab.intersects_ray(lo, ld)
		if hit != null:
			return ((hit as Vector3) - lo).dot(ld) / maxf(ld.length_squared(), 1e-12)
		return -1.0
	for br in brs:
		var t := MapDoc.ray_brush(br, lo, ld)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best
