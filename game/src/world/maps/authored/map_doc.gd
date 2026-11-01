@tool
extends RefCounted
## (r26) A map made in the map editor: res://maps/<id>/map.json. The file is the map's source. The game builds it at
## load (JsonLayout), the Godot map editor (addons/aetherion_mapedit) shows and edits it, and tools/map_plan.py draws
## its plan. Every solid piece compiles into convex brushes, the same brushes a TrenchBroom map gives
## addons/aetherion_map/map_scene.gd, so materials, collision, lights, spawns, stairs and the bots' walk grids come
## from one code path.
##
## Units are metres. x east, z south, y up (Godot's axes). "yaw" is a compass bearing in degrees: 0 north (-z),
## 90 east (+x), 180 south, 270 west. Materials are textures "folder/name" under res://assets/maps/textures
## (surfaces.json: physical surface, roughness, size of one repeat).
##
## The file:
##   {"format": "aetherion-map/1", "id", "name", "code" (two letters: waypoint ids), "modes": ["deathmatch"],
##    "bounds": [x0, z0, x1, z1] (play area), "levels": 2, "level_height": 3.2, "night_only": false,
##    "field_optional": true, "teams": {"max_teams", "max_team_size", "team_size"}, "night_grade": {...},
##    "pieces": [...]}
## Every piece: {"id" (unique, e.g. "court_w1"), "type", "layer" (a group in the editor), "name"?, "note"?,
## "tex_size"? (metres one texture repeat covers on this piece, instead of the material's own size)}.
## Geometry (solid unless "solid": false, which makes it drawn only):
##   box     at [x, y, z] (centre of its base), size [w, h, d], yaw, tilt [pitch, roll] (degrees), mat, top?, under?
##   floor   at [x, y, z] (centre, y = its top), size [w, d], t (thickness, 0.2), yaw, tilt, mat, under?, edge?
##   wall    from [x, z], to [x, z], y (base), h, t (0.2), mat (both faces), mat2 (the face on your left walking
##           from -> to), edge?, openings [{at (metres from "from" to the opening's centre), w, h, sill (0 = a door
##           opening), door? ("plywood" | {"mat", "locked"}: a real door leaf the game swings)}]
##   poly    at [x, y, z] (base), points [[dx, dz], ...] (around at; any simple polygon), h, yaw, mat, top?, under?
##   column  at [x, y, z] (base centre), r, h, sides (8), mat
##   stairs  at [x, y, z] (foot: the middle of the first riser, on the lower floor), yaw (the way up), w, rise,
##           run (0.28 per step), mat, rail (side rails), landing (metres of landing slab at the top; 0 when a floor
##           is there already). Steps are drawn; feet walk an invisible ramp over the nosings (clip_<surface>), and
##           the bots link the floors at its ends.
##   ramp    at [x, y, z] (foot centre), yaw (the way up), w, len, rise, mat: a solid wedge to walk up
## Things:
##   light     at, kind (bulb | tube | lamp | flood | street | down | candle), color "#rrggbb", energy, range,
##             fault ("" | flicker | dying | starter | sag | candle), yaw, pitch (spots, 90 = straight down), cone
##   spawn     at, team (1 | 2 | 3), yaw (facing), for ("" both team layouts | "2" | "3")
##   landmark  at, name (a place on the SmarTab map)
##   spot      at, kind (hide | snipe | cover), yaw (the way a bot watches), name: designated bot spots
##   prop      at, model (a model library name: crate_wood, sandbag, basketball_hoop...), yaw, physics (false:
##             static; true: it can be pushed and knocked over), foot (r, or [w, d]): an invisible collider round its
##             base, foot_h tall (2.5), the bots' walk grid sees it (trees, rocks, statues that keep no collision)
## (r27) Hidden Forest's additions:
##   light     kind torch | brazier: an open fire (a drawn flame, a fire flicker); mount (pole | wall | stand | bowl |
##             none): what it burns on, pole (metres up a pole); minor (true: on phones only the flame, no light)
##   vines     from [x, y, z], to [x, y, z], drop, density, sag, w, seed: hanging strands along a line (map_nature.gd)
## The header may name a Terrain3D ground: "terrain": {...} (map_terrain.gd).
## The QA notes people pin in the editor are kept apart, in res://maps/<id>/qa.json.

const FORMAT := "aetherion-map/1"
const ROOT := "res://maps"
const UPM := 32.0
const TEX_ROOT := "res://assets/maps/textures"
const SURFACES := "res://assets/maps/surfaces.json"
const GEOMETRY := ["box", "floor", "wall", "poly", "column", "stairs", "ramp"]
const THINGS := ["light", "spawn", "landmark", "spot", "prop", "vines"]
const TYPES := ["box", "floor", "wall", "poly", "column", "stairs", "ramp", "light", "spawn", "landmark", "spot", "prop", "vines"]
const MapNature := preload("res://src/world/maps/authored/map_nature.gd")
const FIRE_KINDS := ["torch", "brazier"]
const DEFAULT_MAT := {"box": "freight/concrete_rough", "floor": "freight/concrete_rough", "wall": "freight/chb_white",
	"poly": "freight/concrete_rough", "column": "freight/concrete_rough", "stairs": "freight/concrete_rough",
	"ramp": "freight/concrete_rough"}
## The fields each type starts with (the editor's "Add" and the defaults filled in on load).
const DEFAULTS := {
	"box": {"at": [0, 0, 0], "size": [2, 2, 2], "yaw": 0},
	"floor": {"at": [0, 0, 0], "size": [4, 4], "t": 0.2, "yaw": 0},
	"wall": {"from": [-2, 0], "to": [2, 0], "y": 0, "h": 3, "t": 0.2, "openings": []},
	"poly": {"at": [0, 0, 0], "points": [[-2, -2], [2, -2], [2, 2], [-2, 2]], "h": 0.2, "yaw": 0},
	"column": {"at": [0, 0, 0], "r": 0.2, "h": 3, "sides": 8},
	"stairs": {"at": [0, 0, 0], "yaw": 0, "w": 1.2, "rise": 3.2, "run": 0.28, "rail": false, "landing": 0},
	"ramp": {"at": [0, 0, 0], "yaw": 0, "w": 2, "len": 4, "rise": 1},
	"light": {"at": [0, 2.6, 0], "kind": "bulb", "color": "#ffc98a", "energy": 1.2, "range": 9, "fault": ""},
	"spawn": {"at": [0, 0, 0], "team": 1, "yaw": 0},
	"landmark": {"at": [0, 0, 0], "name": "Place"},
	"spot": {"at": [0, 0, 0], "kind": "hide", "yaw": 0, "name": ""},
	"prop": {"at": [0, 0, 0], "model": "crate_wood", "yaw": 0, "physics": false},
	"vines": {"from": [-1, 3, 0], "to": [1, 3, 0], "drop": 3.0, "density": 3.0, "sag": 0.0},
}
const SPOT_LIGHTS := ["flood", "street", "down", "shaft"]

static var _surfaces := {}


# ------------------------------------------------------------------ files and the catalogue

static func path_of(id: String) -> String:
	return "%s/%s/map.json" % [ROOT, id]


static func qa_path_of(id: String) -> String:
	return "%s/%s/qa.json" % [ROOT, id]


static func ids() -> Array:
	## Every map made in the map editor (a folder under res://maps with a map.json).
	var out := []
	var d := DirAccess.open(ROOT)
	if d == null:
		return out
	for sub in d.get_directories():
		if FileAccess.file_exists(path_of(sub)):
			out.append(sub)
	out.sort()
	return out


static func exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(path_of(id))


static func load_doc(id: String) -> Dictionary:
	## The map file with every piece's defaults filled in, or {} when it is missing or broken.
	var p := path_of(id)
	if not FileAccess.file_exists(p):
		return {}
	var js = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (js is Dictionary):
		push_error("[map] %s is not valid JSON" % p)
		return {}
	return normalise(js, id)


static func normalise(js: Dictionary, id: String = "") -> Dictionary:
	var doc: Dictionary = js.duplicate(true)
	if id != "":
		doc.id = id
	doc.format = FORMAT
	if not doc.has("name"):
		doc.name = str(doc.get("id", "Map")).capitalize()
	if not doc.has("levels"):
		doc.levels = 1
	if not doc.has("level_height"):
		doc.level_height = 3.2
	if not doc.has("bounds"):
		doc.bounds = [-40, -40, 40, 40]
	if not doc.has("modes"):
		doc.modes = ["deathmatch"]
	var seen := {}
	var n := 0
	var pieces: Array = doc.get("pieces", [])
	for p in pieces:
		n += 1
		if not (p is Dictionary):
			continue
		var t := str(p.get("type", "box"))
		for k in DEFAULTS.get(t, {}):
			if not p.has(k):
				var dv = DEFAULTS[t][k]
				p[k] = dv.duplicate(true) if dv is Array else dv
		var pid := str(p.get("id", ""))
		if pid == "" or seen.has(pid):
			pid = "%s%d" % [t.substr(0, 1).to_upper(), n]
			while seen.has(pid):
				n += 1
				pid = "%s%d" % [t.substr(0, 1).to_upper(), n]
			p.id = pid
		seen[pid] = true
		if not p.has("layer"):
			p.layer = "Things" if t in THINGS else "Geometry"
	doc.pieces = pieces
	return doc


static func to_json(doc: Dictionary) -> String:
	## Stable, readable text: the header keys first, then one piece per line (diffs stay small, people can read it).
	var head := ["format", "id", "name", "code", "modes", "bounds", "levels", "level_height", "night_only",
		"field_optional", "teams", "night_grade", "terrain", "note"]
	var lines := ["{"]
	for k in head:
		if doc.has(k):
			lines.append(" %s: %s," % [JSON.stringify(k), JSON.stringify(doc[k])])
	for k in doc:
		if not (k in head) and k != "pieces":
			lines.append(" %s: %s," % [JSON.stringify(k), JSON.stringify(doc[k])])
	lines.append(" \"pieces\": [")
	var pieces: Array = doc.get("pieces", [])
	for i in pieces.size():
		lines.append("  %s%s" % [_piece_json(pieces[i]), "," if i < pieces.size() - 1 else ""])
	lines.append(" ]")
	lines.append("}")
	return "\n".join(lines) + "\n"


static func _piece_json(p: Dictionary) -> String:
	var order := ["id", "type", "layer", "name"]
	var parts := []
	for k in order:
		if p.has(k):
			parts.append("%s: %s" % [JSON.stringify(k), JSON.stringify(_tidy(p[k]))])
	for k in p:
		if not (k in order):
			parts.append("%s: %s" % [JSON.stringify(k), JSON.stringify(_tidy(p[k]))])
	return "{" + ", ".join(parts) + "}"


static func _tidy(v):
	## Numbers rounded to the millimetre (and whole numbers written as such) so saved files stay readable.
	if v is float:
		var r := snappedf(v, 0.001)
		return int(r) if is_equal_approx(r, roundf(r)) else r
	if v is Array:
		var out := []
		for x in v:
			out.append(_tidy(x))
		return out
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _tidy(v[k])
		return o
	return v


static func save_doc(doc: Dictionary, id: String = "") -> Error:
	var mid := id if id != "" else str(doc.get("id", ""))
	if mid == "":
		return ERR_INVALID_PARAMETER
	var p := path_of(mid)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.get_base_dir()))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json(doc))
	f.close()
	return OK


static func title(id: String) -> String:
	var p := path_of(id)
	if not FileAccess.file_exists(p):
		return id
	var js = JSON.parse_string(FileAccess.get_file_as_string(p))
	return str(js.get("name", id)) if js is Dictionary else id


static func code_of(id: String) -> String:
	## The two letters this map's waypoint ids start with (the file's "code", else the id's first two letters).
	var p := path_of(id)
	if FileAccess.file_exists(p):
		var js = JSON.parse_string(FileAccess.get_file_as_string(p))
		if js is Dictionary and str(js.get("code", "")) != "":
			return str(js.code).to_upper()
	return id.substr(0, 2).to_upper()


static func merge_rules(rules: Dictionary) -> void:
	## Adds every editor map to the rules the game reads its maps from: the mode's map list, Deathmatch team limits,
	## the optional field, night only.
	for id in ids():
		var p := path_of(id)
		var js = JSON.parse_string(FileAccess.get_file_as_string(p))
		if not (js is Dictionary):
			continue
		for m in js.get("modes", ["deathmatch"]):
			var gm: Dictionary = rules.get("game_modes", {}).get(str(m), {})
			if gm.is_empty():
				continue
			var maps: Array = gm.get("maps", [gm.get("map", "")])
			if not (id in maps):
				maps.append(id)
			gm.maps = maps
		var dm: Dictionary = rules.get("deathmatch", {})
		if js.has("teams") and js.teams is Dictionary:
			var lim: Dictionary = dm.get("map_limits", {})
			lim[id] = js.teams
			dm.map_limits = lim
		if bool(js.get("field_optional", true)):
			var fo: Array = dm.get("field_optional_maps", [])
			if not (id in fo):
				fo.append(id)
			dm.field_optional_maps = fo
		if bool(js.get("night_only", false)):
			var dc: Dictionary = rules.get("day_cycle", {})
			var no: Array = dc.get("night_only_maps", [])
			if not (id in no):
				no.append(id)
			dc.night_only_maps = no


# ------------------------------------------------------------------ piece frames

static func v3(a, fallback := Vector3.ZERO) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


static func v2(a, fallback := Vector2.ZERO) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return fallback


static func yaw_basis(yaw_deg: float) -> Basis:
	## Compass bearing (clockwise from north) as a rotation about up: local -z faces the bearing, local +x its right.
	return Basis(Vector3.UP, -deg_to_rad(yaw_deg))


static func frame(p: Dictionary) -> Transform3D:
	## The piece's own frame: where its node sits in the editor and what its local geometry is relative to.
	if str(p.get("type", "")) == "vines":
		return MapNature.vines_frame(p)
	if str(p.get("type", "")) == "wall":
		var a := v2(p.get("from"))
		var b := v2(p.get("to"), Vector2(1, 0))
		var d := b - a
		var yaw := rad_to_deg(atan2(d.y, d.x))
		var mid := (a + b) * 0.5
		return Transform3D(yaw_basis(yaw), Vector3(mid.x, float(p.get("y", 0.0)), mid.y))
	return Transform3D(yaw_basis(float(p.get("yaw", 0.0))), v3(p.get("at")))


static func set_frame(p: Dictionary, xf: Transform3D) -> void:
	## The piece moved and turned in the editor: write its position and bearing back (keeping a wall's length).
	var f := -xf.basis.z
	var yaw := snappedf(fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0), 0.001)
	if str(p.get("type", "")) == "vines":
		# keep the line's own shape (its length, how its ends differ in height), moved and turned with the node
		var old := MapNature.vines_frame(p)
		var rel := xf * old.affine_inverse()
		for k in ["from", "to"]:
			var q: Vector3 = rel * v3(p.get(k))
			p[k] = [snappedf(q.x, 0.001), snappedf(q.y, 0.001), snappedf(q.z, 0.001)]
		return
	if str(p.get("type", "")) == "wall":
		var ln := wall_len(p)
		var dir := xf.basis.x.normalized()
		var o := xf.origin
		p.from = [snappedf(o.x - dir.x * ln * 0.5, 0.001), snappedf(o.z - dir.z * ln * 0.5, 0.001)]
		p.to = [snappedf(o.x + dir.x * ln * 0.5, 0.001), snappedf(o.z + dir.z * ln * 0.5, 0.001)]
		p.y = snappedf(o.y, 0.001)
		return
	p.at = [snappedf(xf.origin.x, 0.001), snappedf(xf.origin.y, 0.001), snappedf(xf.origin.z, 0.001)]
	if p.has("yaw") or yaw != 0.0:
		p.yaw = yaw


static func wall_len(p: Dictionary) -> float:
	return v2(p.get("from")).distance_to(v2(p.get("to"), Vector2(1, 0)))


# ------------------------------------------------------------------ brushes (local to the piece's frame)

## A brush: {cls: worldspawn | func_detail | func_illusionary | func_stairs, faces: [{n: Vector3, d: float, tex}]},
## each face the plane n . p <= d (n outward, unit), in metres.

static func _box(c: Vector3, size: Vector3, basis: Basis, texf: Callable, cls := "worldspawn") -> Dictionary:
	## An oriented box: centre c, full size, its axes basis (orthonormal); texf(n_local) picks each face's texture.
	var faces := []
	for ax in 3:
		for sg in [-1.0, 1.0]:
			var nl := Vector3.ZERO
			nl[ax] = sg
			var n: Vector3 = (basis * nl).normalized()
			faces.append({"n": n, "d": n.dot(c) + size[ax] * 0.5, "tex": texf.call(nl)})
	return {"cls": cls, "faces": faces}


static func _hull(planes: Array, cls := "worldspawn") -> Dictionary:
	return {"cls": cls, "faces": planes}


static func _plane(n: Vector3, pt: Vector3, tex: String) -> Dictionary:
	var nn := n.normalized()
	return {"n": nn, "d": nn.dot(pt), "tex": tex}


static func _mats(p: Dictionary) -> Dictionary:
	var t := str(p.get("type", "box"))
	var m := str(p.get("mat", DEFAULT_MAT.get(t, "freight/concrete_rough")))
	return {"side": m, "top": str(p.get("top", m)), "under": str(p.get("under", m)), "edge": str(p.get("edge", m)),
		"mat2": str(p.get("mat2", m))}


static func _cls(p: Dictionary) -> String:
	return "worldspawn" if bool(p.get("solid", true)) else "func_illusionary"


static func _tilt(p: Dictionary) -> Basis:
	var tl := v2(p.get("tilt"))
	return Basis(Vector3.RIGHT, deg_to_rad(tl.x)) * Basis(Vector3.BACK, deg_to_rad(tl.y))


static func brushes(p: Dictionary) -> Array:
	## The piece's brushes in its own frame (frame(p) puts them in the world).
	var m := _mats(p)
	var cls := _cls(p)
	match str(p.get("type", "")):
		"box":
			var s := v3(p.get("size"), Vector3(2, 2, 2))
			var tb := _tilt(p)
			return [_box(tb * Vector3(0, s.y * 0.5, 0), s, tb, func(nl: Vector3): return m.top if nl.y > 0.5 else (m.under if nl.y < -0.5 else m.side), cls)]
		"floor":
			var s2 := v2(p.get("size"), Vector2(4, 4))
			var t := float(p.get("t", 0.2))
			var tb2 := _tilt(p)
			var mt: String = str(p.get("mat", DEFAULT_MAT.floor))
			return [_box(tb2 * Vector3(0, -t * 0.5, 0), Vector3(s2.x, t, s2.y), tb2, func(nl: Vector3): return mt if nl.y > 0.5 else (m.under if nl.y < -0.5 else m.edge), cls)]
		"wall":
			return _wall(p, m, cls)
		"poly":
			return _poly(p, m, cls)
		"column":
			var pts := []
			var r := float(p.get("r", 0.2))
			var ns := clampi(int(p.get("sides", 8)), 3, 32)
			for k in ns:
				var a := TAU * (k + 0.5) / ns
				pts.append([cos(a) * r, sin(a) * r])
			return [_prism(pts, 0.0, float(p.get("h", 3.0)), m.side, m.top, m.under, cls)]
		"stairs":
			return _stairs(p, m)
		"ramp":
			var w := float(p.get("w", 2.0))
			var ln := float(p.get("len", 4.0))
			var rise := float(p.get("rise", 1.0))
			return [_wedge(w, ln, rise, 0.0, m.top, m.side, cls)]
	return []


static func _wedge(w: float, ln: float, rise: float, z0: float, top: String, side: String, cls: String) -> Dictionary:
	## A ramp rising toward local -z: its foot edge at z = z0 on y = 0, its top edge at z = z0 - ln, y = rise.
	return _hull([
		_plane(Vector3.DOWN, Vector3.ZERO, side),
		_plane(Vector3(0, 0, -1), Vector3(0, 0, z0 - ln), side),
		_plane(Vector3.LEFT, Vector3(-w * 0.5, 0, 0), side),
		_plane(Vector3.RIGHT, Vector3(w * 0.5, 0, 0), side),
		_plane(Vector3(0, 1.0, rise / maxf(ln, 0.01)), Vector3(0, 0, z0), top),
	], cls)


static func _wall(p: Dictionary, m: Dictionary, cls: String) -> Array:
	## The wall cut into columns at every opening's sides; in each column, the solid spans between the openings that
	## cover it (a door below and a window above on a two-storey wall). Neighbouring columns with the same spans are
	## one brush. Local frame: x along the wall (from -len/2 at "from" to +len/2 at "to"), y up from its base, z across
	## it (+z on your right walking from -> to).
	var ln := wall_len(p)
	var h := float(p.get("h", 3.0))
	var t := float(p.get("t", 0.2))
	var ops := []
	var cuts := [0.0, ln]
	for o in p.get("openings", []):
		var c := float(o.get("at", 0.0))
		var w := float(o.get("w", 1.0))
		var x0 := clampf(c - w * 0.5, 0.0, ln)
		var x1 := clampf(c + w * 0.5, 0.0, ln)
		var sill := clampf(float(o.get("sill", 0.0)), 0.0, h)
		var top := clampf(sill + float(o.get("h", 2.1)), 0.0, h)
		if x1 - x0 < 0.005 or top - sill < 0.005:
			continue
		ops.append([x0, x1, sill, top])
		cuts.append(x0)
		cuts.append(x1)
	cuts.sort()
	var texf := func(nl: Vector3): return m.side if nl.z > 0.5 else (m.mat2 if nl.z < -0.5 else m.edge)
	var out := []
	var run_x0 := 0.0
	var run_spans = null
	var cols := []
	for i in cuts.size() - 1:
		var a: float = cuts[i]
		var b: float = cuts[i + 1]
		if b - a < 0.005:
			continue
		var holes := []
		for o in ops:
			if o[0] <= a + 1e-4 and o[1] >= b - 1e-4:
				holes.append([o[2], o[3]])
		holes.sort_custom(func(u, v): return u[0] < v[0])
		var spans := []
		var y := 0.0
		for hl in holes:
			if hl[0] - y > 0.005:
				spans.append([y, hl[0]])
			y = maxf(y, hl[1])
		if h - y > 0.005:
			spans.append([y, h])
		cols.append([a, b, spans])
	cols.append([ln, ln, null])   # flushes the last run
	for c in cols:
		if run_spans != null and (c[2] == null or str(c[2]) != str(run_spans)):
			for sp in run_spans:
				out.append(_box(Vector3((run_x0 + c[0]) * 0.5 - ln * 0.5, (sp[0] + sp[1]) * 0.5, 0), Vector3(c[0] - run_x0, sp[1] - sp[0], t), Basis(), texf, cls))
			run_spans = null
		if run_spans == null and c[2] != null:
			run_x0 = c[0]
			run_spans = c[2]
	return out


static func _prism(pts: Array, y0: float, y1: float, side: String, top: String, under: String, cls: String) -> Dictionary:
	## A convex polygon (local x, z; either winding) extruded from y0 to y1.
	var poly := PackedVector2Array()
	for q in pts:
		poly.append(v2(q))
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	var planes := [_plane(Vector3.UP, Vector3(0, y1, 0), top), _plane(Vector3.DOWN, Vector3(0, y0, 0), under)]
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var e := b - a
		if e.length() < 1e-4:
			continue
		# counter-clockwise in (x, z) seen from above: (x right, z down on screen), outward is (e.y, -e.x)
		var nrm := Vector3(e.y, 0, -e.x)
		planes.append(_plane(nrm, Vector3(a.x, 0, a.y), side))
	return _hull(planes, cls)


static func _poly(p: Dictionary, m: Dictionary, cls: String) -> Array:
	var poly := PackedVector2Array()
	for q in p.get("points", []):
		poly.append(v2(q))
	if poly.size() < 3:
		return []
	var out := []
	var parts := Geometry2D.decompose_polygon_in_convex(poly)
	if parts.is_empty():
		parts = [poly]
	for part in parts:
		var arr := []
		for q in part:
			arr.append([q.x, q.y])
		out.append(_prism(arr, 0.0, float(p.get("h", 0.2)), m.side, m.top, m.under, cls))
	return out


static func stair_steps(p: Dictionary) -> Dictionary:
	var rise := float(p.get("rise", 3.2))
	var n := maxi(2, int(round(rise / 0.18)))
	return {"n": n, "r": rise / n, "run": float(p.get("run", 0.28)), "w": float(p.get("w", 1.2)), "rise": rise}


static func _stairs(p: Dictionary, m: Dictionary) -> Array:
	## n risers: n - 1 steps (a solid block each, from the floor up, drawn only), the last riser is the landing's edge.
	## The way up local -z; the first riser at z = 0. A clip ramp over the nosings carries the feet.
	var st := stair_steps(p)
	var n: int = st.n
	var r: float = st.r
	var run: float = st.run
	var w: float = st.w
	var out := []
	var side: String = m.side
	var top: String = m.top
	for i in n - 1:
		var z1 := -i * run
		var hgt := (i + 1) * r
		out.append(_box(Vector3(0, hgt * 0.5, z1 - run * 0.5), Vector3(w, hgt, run), Basis(),
			func(nl: Vector3): return top if nl.y > 0.5 else side, "func_stairs"))
	var phys := str(_surface(side).get("phys", "concrete"))
	var clip := "freight/clip_%s" % ("wood" if phys == "wood" else ("steel" if phys in ["steel", "metal"] else "concrete"))
	out.append(_wedge(w, n * run, n * r, run, clip, clip, "worldspawn"))
	var landing := float(p.get("landing", 0.0))
	if landing > 0.01:
		var z0 := -(n - 1) * run
		out.append(_box(Vector3(0, st.rise - 0.1, z0 - landing * 0.5), Vector3(w, 0.2, landing), Basis(),
			func(nl: Vector3): return top if nl.y > 0.5 else side, "worldspawn"))
	if bool(p.get("rail", false)):
		var ln := n * run
		var ang := atan2(st.rise, ln)
		var b := Basis(Vector3.RIGHT, ang)
		var mid := Vector3(0, st.rise * 0.5 + 0.9, -ln * 0.5 + run)
		for sx in [-1.0, 1.0]:
			out.append(_box(mid + Vector3(sx * (w * 0.5 + 0.03), 0, 0), Vector3(0.05, 0.08, sqrt(ln * ln + st.rise * st.rise)), b,
				func(_nl: Vector3): return "freight/steel_rust", "func_detail"))
			out.append(_box(Vector3(sx * (w * 0.5 + 0.03), st.rise * 0.5 + 0.45, -ln * 0.5 + run), Vector3(0.04, 0.9, sqrt(ln * ln + st.rise * st.rise)), b,
				func(_nl: Vector3): return "freight/chain_link", "func_illusionary"))
	return out


static func bounds_local(p: Dictionary) -> AABB:
	## The piece's extent in its own frame (the editor's outline and picking box).
	var t := str(p.get("type", ""))
	match t:
		"box":
			var s := v3(p.get("size"), Vector3(2, 2, 2))
			return AABB(Vector3(-s.x * 0.5, 0, -s.z * 0.5), s)
		"floor":
			var s2 := v2(p.get("size"), Vector2(4, 4))
			var th := float(p.get("t", 0.2))
			return AABB(Vector3(-s2.x * 0.5, -th, -s2.y * 0.5), Vector3(s2.x, th, s2.y))
		"wall":
			var ln := wall_len(p)
			var tw := float(p.get("t", 0.2))
			return AABB(Vector3(-ln * 0.5, 0, -tw * 0.5), Vector3(ln, float(p.get("h", 3.0)), tw))
		"poly":
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for q in p.get("points", []):
				lo = lo.min(v2(q))
				hi = hi.max(v2(q))
			if lo.x == INF:
				return AABB()
			return AABB(Vector3(lo.x, 0, lo.y), Vector3(hi.x - lo.x, float(p.get("h", 0.2)), hi.y - lo.y))
		"column":
			var r := float(p.get("r", 0.2))
			return AABB(Vector3(-r, 0, -r), Vector3(r * 2, float(p.get("h", 3.0)), r * 2))
		"stairs":
			var st := stair_steps(p)
			var ln: float = st.n * st.run + float(p.get("landing", 0.0))
			return AABB(Vector3(-st.w * 0.5, 0, -ln), Vector3(st.w, st.rise, ln))
		"ramp":
			var w := float(p.get("w", 2.0))
			var lr := float(p.get("len", 4.0))
			return AABB(Vector3(-w * 0.5, 0, -lr), Vector3(w, float(p.get("rise", 1.0)), lr))
		"light":
			return AABB(Vector3(-0.15, -0.15, -0.15), Vector3(0.3, 0.3, 0.3))
		"spawn":
			return AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.8, 0.6))
		"prop":
			return AABB(Vector3(-0.4, 0, -0.4), Vector3(0.8, 1.0, 0.8))
		"vines":
			return MapNature.vines_bounds(p)
	return AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.2, 0.6))


static func face_polys(br: Dictionary) -> Array:
	## Each face of a brush as its polygon (PackedVector3Array, the piece's frame): a big square on the face's plane
	## cut by every other plane. The editor's outlines and click picking use them.
	var out := []
	var faces: Array = br.faces
	for i in faces.size():
		var n: Vector3 = faces[i].n
		var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
		var ua := up.cross(n).normalized()
		var va := n.cross(ua).normalized()
		var c := n * float(faces[i].d)
		var R := 500.0
		var poly := PackedVector3Array([c + ua * R + va * R, c - ua * R + va * R, c - ua * R - va * R, c + ua * R - va * R])
		for j in faces.size():
			if j == i or poly.size() < 3:
				continue
			var nj: Vector3 = faces[j].n
			var dj := float(faces[j].d)
			var cut := PackedVector3Array()
			for k in poly.size():
				var pa := poly[k]
				var pb := poly[(k + 1) % poly.size()]
				var da := nj.dot(pa) - dj
				var db := nj.dot(pb) - dj
				if da <= 1e-5:
					cut.append(pa)
				if (da < -1e-5 and db > 1e-5) or (da > 1e-5 and db < -1e-5):
					cut.append(pa.lerp(pb, da / (da - db)))
			poly = cut
		if poly.size() >= 3:
			out.append(poly)
	return out


static func ray_brush(br: Dictionary, o: Vector3, d: Vector3) -> float:
	## Where a ray (the piece's frame) enters a brush: the distance along d, or -1 when it misses.
	var t0 := 0.0
	var t1 := INF
	for f in br.faces:
		var n: Vector3 = f.n
		var den := n.dot(d)
		var dist := float(f.d) - n.dot(o)
		if absf(den) < 1e-9:
			if dist < 0.0:
				return -1.0
		elif den < 0.0:
			t0 = maxf(t0, dist / den)
		else:
			t1 = minf(t1, dist / den)
		if t0 > t1:
			return -1.0
	return t0


# ------------------------------------------------------------------ to MapScene entities

static func _surface(tex: String) -> Dictionary:
	if _surfaces.is_empty() and FileAccess.file_exists(SURFACES):
		var js = JSON.parse_string(FileAccess.get_file_as_string(SURFACES))
		if js is Dictionary:
			_surfaces = js
	return _surfaces.get(tex, {})


static func _qface(f: Dictionary, xf: Transform3D, tex_size := 0.0) -> Dictionary:
	## A face in the world (xf) as MapScene reads it: Quake axes (x east, y north, z up), 32 units a metre, and
	## world-aligned texture axes so one repeat covers the material's size in metres.
	var n: Vector3 = (xf.basis * (f.n as Vector3)).normalized()
	var pt: Vector3 = xf * ((f.n as Vector3) * float(f.d))
	var d := n.dot(pt)
	var tex := str(f.tex)
	var sd := _surface(tex)
	var size := tex_size if tex_size > 0.0 else float(sd.get("size", 2.0))
	var px: Array = sd.get("px", [512, 512])
	var u: Vector3
	var v: Vector3
	if absf(n.y) > 0.7:
		u = Vector3(1, 0, 0)
		v = Vector3(0, 0, 1)
	else:
		u = Vector3.UP.cross(n).normalized()
		v = Vector3.DOWN
	return {"n": [n.x, -n.z, n.y], "d": d * UPM, "tex": tex,
		"u": Vector3(u.x, -u.z, u.y), "uo": 0.0, "v": Vector3(v.x, -v.z, v.y), "vo": 0.0,
		"sx": size * UPM / float(px[0]), "sy": size * UPM / float(px[1])}


static func _fit(qf: Array, br: Dictionary, polys: Array, xf: Transform3D) -> void:
	## Signs and banners ("fit" in surfaces.json): the picture covers each face exactly once instead of tiling.
	## face_polys skips faces that come out empty, so each polygon is matched to its face by its plane.
	for i in qf.size():
		var f: Dictionary = br.faces[i]
		if not bool(_surface(str(f.tex)).get("fit", false)):
			continue
		var poly = null
		for pg in polys:
			var c := Vector3.ZERO
			for q in pg:
				c += q
			c /= float(pg.size())
			if absf((f.n as Vector3).dot(c) - float(f.d)) < 1e-3:
				poly = pg
				break
		if poly == null:
			continue
		var g: Dictionary = qf[i]
		var px: Array = _surface(str(f.tex)).get("px", [512, 512])
		var u: Vector3 = g.u
		var v: Vector3 = g.v
		var ua := INF
		var ub := -INF
		var va := INF
		var vb := -INF
		for q in poly:
			var w: Vector3 = xf * (q as Vector3)
			var qq := Vector3(w.x, -w.z, w.y) * UPM
			ua = minf(ua, qq.dot(u))
			ub = maxf(ub, qq.dot(u))
			va = minf(va, qq.dot(v))
			vb = maxf(vb, qq.dot(v))
		if ub - ua < 1e-3 or vb - va < 1e-3:
			continue
		g.sx = (ub - ua) / float(px[0])
		g.sy = (vb - va) / float(px[1])
		g.uo = -ua / g.sx
		g.vo = -va / g.sy


static func _origin(p: Vector3) -> String:
	return "%f %f %f" % [p.x * UPM, -p.z * UPM, p.y * UPM]


static func _hex_rgb(s: String) -> String:
	var c := Color.from_string(s, Color(1.0, 0.8, 0.55))
	return "%f %f %f" % [c.r, c.g, c.b]


static func entities(doc: Dictionary, only: Array = [], local := false) -> Array:
	## MapScene's entities for the pieces (every piece, or the ids in only). local: in each piece's own frame (the
	## editor's preview of one piece).
	var world := {"props": {"classname": "worldspawn", "map_id": str(doc.get("id", "")), "message": str(doc.get("name", "")),
		"level_height": str(doc.get("level_height", 3.2))}, "brushes": []}
	var ents := [world]
	var by_cls := {}
	for p in doc.get("pieces", []):
		if not only.is_empty() and not (str(p.get("id", "")) in only):
			continue
		var xf := Transform3D() if local else frame(p)
		var t := str(p.get("type", ""))
		if t in GEOMETRY:
			var stair_faces := []
			var ts := float(p.get("tex_size", 0.0))
			for br in brushes(p):
				var qf := []
				var polys := []
				for f in br.faces:
					qf.append(_qface(f, xf, ts))
					if bool(_surface(str(f.tex)).get("fit", false)) and polys.is_empty():
						polys = face_polys(br)
				if not polys.is_empty():
					_fit(qf, br, polys, xf)
				if br.cls == "worldspawn":
					world.brushes.append(qf)
				elif br.cls == "func_stairs":
					stair_faces.append(qf)
				else:
					if not by_cls.has(br.cls):
						by_cls[br.cls] = {"props": {"classname": br.cls}, "brushes": []}
						ents.append(by_cls[br.cls])
					by_cls[br.cls].brushes.append(qf)
			if not stair_faces.is_empty():
				ents.append({"props": {"classname": "func_stairs", "targetname": str(p.get("name", p.get("id", "stairs")))}, "brushes": stair_faces})
			continue
		var at: Vector3 = xf.origin if not local else Vector3.ZERO
		var yaw := float(p.get("yaw", 0.0))
		var q_angle := "%f" % (90.0 - yaw)
		match t:
			"light":
				ents.append({"props": {"classname": "light", "origin": _origin(at), "kind": str(p.get("kind", "bulb")),
					"_color": _hex_rgb(str(p.get("color", "#ffc98a"))), "energy": str(p.get("energy", 1.2)),
					"range": str(p.get("range", 9)), "fault": str(p.get("fault", "")), "angle": q_angle,
					"pitch": str(p.get("pitch", 90)), "cone": str(p.get("cone", 45)),
					"minor": "1" if bool(p.get("minor", false)) else "0"}, "brushes": []})
			"prop":
				# (r27) an invisible collider round the base of a tree, rock or statue (its model keeps none)
				var ft = p.get("foot", null)
				if ft == null or local:
					continue
				var fh := float(p.get("foot_h", 2.5))
				var clip := {"type": "column", "r": float(ft), "h": fh, "sides": 8, "mat": "freight/clip"} if (ft is float or ft is int) 					else {"type": "box", "size": [float(ft[0]), fh, float(ft[1])], "mat": "freight/clip"}
				for br in brushes(clip):
					var qf := []
					for f in br.faces:
						qf.append(_qface(f, xf))
					world.brushes.append(qf)
			"spawn":
				ents.append({"props": {"classname": "info_team_spawn", "origin": _origin(at), "team": str(int(p.get("team", 1))),
					"angle": q_angle, "for": str(p.get("for", ""))}, "brushes": []})
			"landmark":
				ents.append({"props": {"classname": "info_landmark", "origin": _origin(at), "name": str(p.get("name", ""))}, "brushes": []})
	return ents


# ------------------------------------------------------------------ what the game places itself

static func doors(doc: Dictionary) -> Array:
	## Door leaves in wall openings: [{xf (the hinge, at the opening's bottom left; x along the leaf), w, h, mat,
	## locked, outward, id}] for Dynamics.add_door.
	var out := []
	for p in doc.get("pieces", []):
		if str(p.get("type", "")) != "wall":
			continue
		var xf := frame(p)
		var ln := wall_len(p)
		for o in p.get("openings", []):
			var dv = o.get("door", null)
			if dv == null or (dv is bool and not dv) or str(dv) == "":
				continue
			var spec: Dictionary = dv if dv is Dictionary else {"mat": str(dv) if not (dv is bool) else "plywood"}
			var w := float(o.get("w", 0.9))
			var h := minf(float(o.get("h", 2.0)), float(p.get("h", 3.0)) - float(o.get("sill", 0.0)))
			var c := float(o.get("at", 0.0)) - ln * 0.5
			var hinge := Vector3(c - w * 0.5 + 0.01, float(o.get("sill", 0.0)), 0.0)
			out.append({"xf": xf * Transform3D(Basis(), hinge), "w": w - 0.02, "h": h - 0.02, "t": 0.035,
				"mat": str(spec.get("mat", "plywood")), "locked": bool(spec.get("locked", false)),
				"outward": (xf.basis * Vector3(0, 0, 1)).normalized(), "piece": str(p.get("id", ""))})
	return out


static func props(doc: Dictionary) -> Array:
	var out := []
	for p in doc.get("pieces", []):
		if str(p.get("type", "")) == "prop":
			out.append({"model": str(p.get("model", "crate_wood")), "xf": frame(p), "physics": bool(p.get("physics", false))})
	return out


static func fires(doc: Dictionary) -> Array:
	## (r27) What every torch and brazier burns on: [{mount, pole, xf (the fixture's base)}].
	var out := []
	for p in doc.get("pieces", []):
		if str(p.get("type", "")) != "light" or not (str(p.get("kind", "")) in FIRE_KINDS):
			continue
		var mount := str(p.get("mount", "pole" if str(p.get("kind", "")) == "torch" else "stand"))
		if mount == "none" or mount == "":
			continue
		var q: Dictionary = (p as Dictionary).duplicate()
		q.mount = mount
		out.append({"mount": mount, "pole": float(p.get("pole", 1.9)), "xf": MapNature.fixture_xf(q)})
	return out


static func vines(doc: Dictionary) -> Array:
	var out := []
	for p in doc.get("pieces", []):
		if str(p.get("type", "")) == "vines":
			out.append(p)
	return out


static func spots(doc: Dictionary) -> Array:
	## Designated bot spots ({p, kind, face, name}) as layouts give BotNav.
	var out := []
	for p in doc.get("pieces", []):
		if str(p.get("type", "")) != "spot":
			continue
		var xf := frame(p)
		var f := -xf.basis.z
		out.append({"p": xf.origin, "kind": str(p.get("kind", "hide")), "face": xf.origin + f * 12.0 + Vector3(0, 1.0, 0),
			"name": str(p.get("name", ""))})
	return out


# ------------------------------------------------------------------ checks

static func check(doc: Dictionary) -> Array:
	## Problems a person should fix before playing: [{id, msg}].
	var out := []
	var seen := {}
	var teams := {}
	for p in doc.get("pieces", []):
		var pid := str(p.get("id", ""))
		if seen.has(pid):
			out.append({"id": pid, "msg": "the id is used twice"})
		seen[pid] = true
		var t := str(p.get("type", ""))
		if not (t in TYPES):
			out.append({"id": pid, "msg": "unknown type %s" % t})
			continue
		for k in ["mat", "mat2", "top", "under", "edge"]:
			if p.has(k) and not ResourceLoader.exists("%s/%s.png" % [TEX_ROOT, str(p[k])]):
				out.append({"id": pid, "msg": "no texture %s (%s)" % [str(p[k]), k]})
		if t == "wall" and wall_len(p) < 0.05:
			out.append({"id": pid, "msg": "the wall has no length"})
		if t == "wall":
			var ln := wall_len(p)
			for o in p.get("openings", []):
				var c := float(o.get("at", 0.0))
				if c - float(o.get("w", 1.0)) * 0.5 < -0.01 or c + float(o.get("w", 1.0)) * 0.5 > ln + 0.01:
					out.append({"id": pid, "msg": "an opening runs past the wall's end (at %.2f, wall %.2f m)" % [c, ln]})
		if t == "spawn":
			teams[int(p.get("team", 1))] = int(teams.get(int(p.get("team", 1)), 0)) + 1
	for tm in [1, 2]:
		if int(teams.get(tm, 0)) == 0:
			out.append({"id": "", "msg": "no spawn for team %d" % tm})
	return out
