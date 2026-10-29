extends RefCounted
## What people and weather leave on walls: spray tags and throw-ups, stencilled "BAWAL" signs, election and
## missing-person posters, house numbers from the census, prayers, and in the roofed lanes the frightened writing -
## handprints, eyes, X marks on searched houses, tally marks, "HUWAG KANG LALABAS SA GABI". Also rust running down
## from the eaves, rising damp along the foot of walls, mould, and oil and mud on the ground.
##
## All from one atlas (tools/make_vandal_atlas.py): one draw call per chunk however many decals there are. Decals on
## walls along roofed-over lanes go on the interior layer, like the walls they are on.

const ATLAS_JSON := "res://assets/fx/vandal_atlas.json"
const MAT := "decal_atlas"

var mb = null
var L = null
var sink = null
var rng := RandomNumberGenerator.new()
var _kinds := {}   # kind -> [{uv: Rect2, aspect}]
var stats := {"wall": 0, "covered": 0, "stains": 0, "ground": 0, "spots": 0}


func _init(map_builder) -> void:
	mb = map_builder
	L = mb.layout
	sink = mb.sink
	rng.seed = L.rng.seed + 1201
	var f := FileAccess.open(ATLAS_JSON, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	var size := float(d.get("size", 2048))
	for c in d.get("cells", []):
		var r: Array = c.rect
		# Half a texel in from the edges so mipmaps of the neighbouring cell do not bleed in.
		var uv := Rect2((float(r[0]) + 1.0) / size, (float(r[1]) + 1.0) / size, (float(r[2]) - 2.0) / size, (float(r[3]) - 2.0) / size)
		var k := str(c.kind)
		if not _kinds.has(k):
			_kinds[k] = []
		_kinds[k].append({"uv": uv, "aspect": float(c.aspect), "name": str(c.name)})


func _cell(kinds: Array) -> Dictionary:
	var k: String = kinds[rng.randi_range(0, kinds.size() - 1)]
	var arr: Array = _kinds.get(k, [])
	if arr.is_empty():
		return {}
	return arr[rng.randi_range(0, arr.size() - 1)]


func build() -> void:
	if _kinds.is_empty():
		push_warning("vandal: no atlas (run tools/make_vandal_atlas.py)")
		return
	for bd in mb.buildings:
		_building(bd)
	for s in mb.vandal_spots:
		_spot(s)
	for a in mb.alleys:
		_ground(a)
	print("[vandal] ", stats)


func _building(bd: Dictionary) -> void:
	var xf: Transform3D = bd.xf
	var w := float(bd.w)
	var d := float(bd.d)
	var h0 := float(bd.get("h0", 2.4))
	var covered := bool(bd.get("covered", false))
	var style := str(bd.get("style", "wood"))
	var layer := "int" if covered else "mid"
	var n := (-xf.basis.z).normalized()
	var up := Vector3.UP
	var right := up.cross(n).normalized()
	var opens: Array = bd.get("front_open", [])
	var placed := []   # Rect2 in wall coordinates (x along the wall, y up)
	var off := 0.022
	# Tags, signs, posters, numbers; under a lane roof, mostly the scared writing.
	var count := rng.randi_range(2, 4) if covered else (rng.randi_range(0, 3) if rng.randf() < 0.8 else 0)
	for i in count:
		var kinds: Array
		if covered:
			kinds = ["eerie", "eerie", "tag", "throw", "census", "stencil"]
		else:
			kinds = ["tag", "tag", "throw", "graffiti", "stencil", "poster", "census", "sign", "eerie"]
		var cell := _cell(kinds)
		if cell.is_empty():
			continue
		var big: bool = cell.aspect > 1.5
		var sw := rng.randf_range(0.9, 1.7) if big else rng.randf_range(0.35, 0.75)
		var sh := sw / float(cell.aspect)
		if sw > w - 0.3:
			continue
		for attempt in 6:
			var lx := rng.randf_range(-w * 0.5 + sw * 0.5 + 0.1, w * 0.5 - sw * 0.5 - 0.1)
			var ly := rng.randf_range(0.35, maxf(h0 - 0.2 - sh, 0.4))
			var r := Rect2(lx - sw * 0.5, ly, sw, sh)
			if _blocked(r, opens, placed):
				continue
			placed.append(r)
			var c: Vector3 = xf * Vector3(lx, ly + sh * 0.5, -d * 0.5) + n * off
			off += 0.004
			var a := rng.randf_range(0.6, 0.95)
			sink.atlas_quad(c, right, up, sw, sh, cell.uv, MAT, {"layer": layer, "tint": Color(1, 1, 1, a)})
			stats.wall += 1
			if covered:
				stats.covered += 1
			break
	# Rising damp along the foot of the wall.
	if rng.randf() < 0.55:
		var cell2 := _cell(["damp"])
		if not cell2.is_empty():
			var hh := rng.randf_range(0.35, 0.6)
			var c2: Vector3 = xf * Vector3(rng.randf_range(-0.2, 0.2), hh * 0.5 - 0.02, -d * 0.5) + n * 0.016
			sink.atlas_quad(c2, right, up, w - 0.06, hh, cell2.uv, MAT, {"layer": layer, "tint": Color(1, 1, 1, rng.randf_range(0.55, 0.9))})
			stats.stains += 1
	# Rust running down from the eaves of tin and block houses, water stains on the rest.
	if rng.randf() < (0.6 if style in ["yero", "patch", "chb"] else 0.35):
		for k in rng.randi_range(1, 2):
			var cell3 := _cell(["streak"])
			if cell3.is_empty():
				continue
			var sw3 := rng.randf_range(0.4, 0.9)
			var sh3 := minf(sw3 / float(cell3.aspect), h0 - 0.3)
			var lx3 := rng.randf_range(-w * 0.5 + sw3 * 0.5, w * 0.5 - sw3 * 0.5)
			var c3: Vector3 = xf * Vector3(lx3, h0 - 0.05 - sh3 * 0.5, -d * 0.5) + n * 0.018
			sink.atlas_quad(c3, right, up, sw3, sh3, cell3.uv, MAT, {"layer": layer, "tint": Color(1, 1, 1, rng.randf_range(0.5, 0.85))})
			stats.stains += 1
	# Mould in a lower corner.
	if rng.randf() < 0.3:
		var cell4 := _cell(["stain"])
		if not cell4.is_empty():
			var s4 := rng.randf_range(0.5, 1.1)
			var c4: Vector3 = xf * Vector3((w * 0.5 - s4 * 0.4) * (1.0 if rng.randf() < 0.5 else -1.0), s4 * 0.45, -d * 0.5) + n * 0.02
			sink.atlas_quad(c4, right, up, s4, s4, cell4.uv, MAT, {"layer": layer, "tint": Color(1, 1, 1, rng.randf_range(0.4, 0.75))})
			stats.stains += 1


func _blocked(r: Rect2, opens: Array, placed: Array) -> bool:
	for o in opens:
		var v: Vector4 = o
		var orc := Rect2(v.x - v.y * 0.5 - 0.08, v.z - 0.08, v.y + 0.16, v.w + 0.16)
		if orc.intersects(r):
			return true
	for p in placed:
		if (p as Rect2).grow(0.05).intersects(r):
			return true
	return false


func _spot(s: Dictionary) -> void:
	var n: Vector3 = s.n
	var right := Vector3.UP.cross(n).normalized()
	var cell := _cell(["stencil", "eerie"])
	if cell.is_empty():
		return
	var sw := rng.randf_range(0.6, 1.0)
	var sh := sw / float(cell.aspect)
	sink.atlas_quad((s.pos as Vector3) + n * 0.33, right, Vector3.UP, sw, sh, cell.uv, MAT, {"tint": Color(1, 1, 1, 0.85)})
	stats.spots += 1


func _ground(a: Dictionary) -> void:
	## Oil and mud on lanes: flat decals a couple of centimetres up.
	if str(a.kind) == "walk":
		return
	var pa: Vector2 = a.a
	var pb: Vector2 = a.b
	var len := pa.distance_to(pb)
	if len < 3.0:
		return
	var dir := (pb - pa) / len
	var side := Vector2(-dir.y, dir.x)
	var t := rng.randf_range(2.0, 9.0)
	while t < len:
		var p := pa + dir * t + side * rng.randf_range(-0.35, 0.35) * float(a.w)
		if not L.is_water(p.x, p.y) and rng.randf() < 0.45:
			var cell := _cell(["ground"])
			if not cell.is_empty():
				var under = mb.cover != null and mb.cover.covered(p)
				var s := rng.randf_range(0.6, minf(1.6, float(a.w) + 0.2))
				var ang := rng.randf() * TAU
				var r3 := Vector3(cos(ang), 0, sin(ang))
				var upv := Vector3.UP.cross(r3)
				var y: float = L.ground_height(p.x, p.y) + (0.045 if under else 0.03)
				sink.atlas_quad(Vector3(p.x, y, p.y), r3, upv, s, s * rng.randf_range(0.6, 1.0), cell.uv, MAT,
					{"layer": "int" if under else "mid", "tint": Color(1, 1, 1, rng.randf_range(0.45, 0.8))})
				stats.ground += 1
		t += rng.randf_range(5.0, 12.0)
