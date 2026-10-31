extends RefCounted
## (r15) Malasugue Mall's shops: every unit's dividing walls, its glass front (plate-glass panes between slim steel
## mullions and a pair of glass doors, all of which shatter; big stores get a wide open entrance under a rolled
## shutter), the lit fascia sign and a projecting blade sign, then the inside dressed for what the shop sells: rails
## of clothes and mannequins, shoe walls, glass jewellery counters, gondolas of groceries, gaming PCs, cafe tables,
## a cinema with stadium seating... Loot goes on counters and floors like any building. Each recipe works in the
## unit's own frame: x across the front (right to left seen from outside: the frame is right-handed), z from the front
## (0) to the back (depth).

var B = null   # MallBuilder
var mb = null
var L = null
var S = null
var rng := RandomNumberGenerator.new()
var stats := {"units": 0, "panes": 0, "doors": 0, "fixtures": 0}

# The unit being built: its level, floor height, frame (x across, z inward) and size.
var _lv := 0
var _y := 0.0
var _xf := Transform3D()
var _w := 0.0
var _d := 0.0
var _bid := 0
var _shop: Dictionary = {}
## (r16) The unit's power after the outbreak (MallBuilder.POWER_*), and where its one faulty fitting hangs.
var _power := 1
var _lamp_at := Vector3.INF
var dept = null    # MallDept, for Alex Jackie's floors

const WALL_COLOURS := {
	"fashion": Color(0.94, 0.93, 0.9), "fashion_lux": Color(0.12, 0.11, 0.1), "fashion_kids": Color(0.98, 0.93, 0.8),
	"shoes": Color(0.9, 0.9, 0.9), "bags": Color(0.95, 0.88, 0.86), "beauty": Color(0.98, 0.96, 0.96), "jewelry": Color(0.2, 0.17, 0.15),
	"toys": Color(0.99, 0.92, 0.6), "hobby": Color(0.18, 0.24, 0.32), "vape": Color(0.07, 0.08, 0.1), "tech": Color(0.93, 0.94, 0.95),
	"games": Color(0.1, 0.1, 0.16), "esports": Color(0.05, 0.05, 0.07), "cafe": Color(0.72, 0.6, 0.48), "food": Color(0.95, 0.9, 0.82),
	"bakery": Color(0.9, 0.82, 0.68), "restaurant": Color(0.32, 0.22, 0.16), "supermarket": Color(0.95, 0.95, 0.93),
	"department": Color(0.95, 0.94, 0.92), "books": Color(0.8, 0.72, 0.6), "cinema": Color(0.12, 0.06, 0.14), "kids_play": Color(0.6, 0.86, 0.95),
	"gym": Color(0.2, 0.2, 0.22), "home": Color(0.92, 0.89, 0.84), "salon": Color(0.95, 0.9, 0.96), "barber": Color(0.22, 0.24, 0.28),
	"spa": Color(0.82, 0.86, 0.76), "service": Color(0.93, 0.94, 0.95), "closed": Color(0.85, 0.85, 0.84), "pharmacy": Color(0.97, 0.97, 0.97),
	"convenience": Color(0.97, 0.97, 0.95), "optical": Color(0.96, 0.96, 0.96), "sports": Color(0.9, 0.9, 0.9), "music": Color(0.28, 0.2, 0.16),
	"pets": Color(0.98, 0.95, 0.85), "clinic": Color(0.96, 0.98, 1.0), "appliances": Color(0.95, 0.95, 0.96), "gifts": Color(0.93, 0.85, 0.72),
	"plants": Color(0.86, 0.92, 0.84), "arcade": Color(0.1, 0.06, 0.18), "tailor": Color(0.86, 0.82, 0.74), "bridal": Color(0.99, 0.97, 0.95),
	"food_hall": Color(0.95, 0.9, 0.82), "restroom": Color(0.9, 0.9, 0.88),
}
const FLOORS := {
	"fashion": "oak", "fashion_lux": "mall_marble", "fashion_kids": "laminate", "shoes": "oak", "bags": "white_oak", "beauty": "mall_granite",
	"jewelry": "mall_granite", "toys": "mall_rubber", "hobby": "mall_grey", "vape": "mall_grey", "tech": "mall_grey", "games": "mall_grey",
	"esports": "carpet", "cafe": "walnut", "food": "mall_tiles", "bakery": "mall_tiles", "restaurant": "walnut", "supermarket": "mall_grey",
	"department": "mall_granite", "books": "oak", "cinema": "carpet", "kids_play": "mall_rubber", "gym": "mall_rubber", "home": "white_oak",
	"salon": "mall_tiles", "barber": "parquet", "spa": "white_oak", "service": "mall_grey", "closed": "concrete_floor2", "pharmacy": "mall_grey",
	"convenience": "mall_grey", "optical": "white_oak", "sports": "laminate", "music": "walnut", "pets": "mall_tiles", "clinic": "mall_grey",
	"appliances": "mall_grey", "gifts": "oak", "plants": "terrazzo", "arcade": "carpet", "tailor": "parquet", "bridal": "mall_marble",
	"food_hall": "mall_tiles", "restroom": "mall_grey",
}
const CLOTH := [Color(0.08, 0.08, 0.09), Color(0.95, 0.95, 0.93), Color(0.55, 0.08, 0.1), Color(0.1, 0.2, 0.42), Color(0.78, 0.68, 0.5),
	Color(0.32, 0.42, 0.26), Color(0.85, 0.5, 0.58), Color(0.42, 0.42, 0.44), Color(0.55, 0.7, 0.86), Color(0.92, 0.78, 0.25)]


func _init(builder) -> void:
	B = builder
	mb = builder.mb
	L = builder.L
	S = builder.S
	rng.seed = 7151


func build_all() -> void:
	dept = B.MallDept.new(B)
	for u in L.units:
		_unit(u)
		stats.units += 1
	B.stats.dept_rooms = dept.stats
	dept.sh = null   # (it held this builder while dressing: a cycle would keep the whole map alive)
	dept = null


# ------------------------------------------------------------------ the unit frame

func P(x: float, z: float, h: float = 0.0) -> Vector3:
	## A point in the unit: x across the front from its left end, z inward from the front, h above the floor.
	return _xf * Vector3(x, _y + h, z)


func YAW(local_yaw: float = 0.0) -> float:
	return _xf.basis.get_euler().y + local_yaw


func box(x: float, z: float, h: float, size: Vector3, mat: String, opt: Dictionary = {}, yaw: float = 0.0) -> void:
	## A box centred at (x, h, z) in the unit, size in the unit's axes; opt.solid blocks bodies and bots.
	var op = B.o(opt)
	var xf := Transform3D(_xf.basis * Basis(Vector3.UP, yaw), P(x, z, h))
	if not op.has("layer"):
		op.layer = "int"
	if opt.get("solid", false):
		op.collide = true
		var c := P(x, z, h)
		L.block_rect(_lv, Vector2(c.x, c.z), Vector2(size.x, size.z) * 0.5, -(YAW(yaw)), float(opt.get("pad", 0.25)))
	S.box(xf, size, mat, op)
	stats.fixtures += 1


func prop(name: String, x: float, z: float, yaw: float = 0.0, dynamic: bool = false, h: float = 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, YAW(yaw)), P(x, z, h))
	if mb.models.spec(name).is_empty():
		return
	if dynamic:
		mb.dyn.add_prop_spec(name, mb.dyn.seat(name, xf))
	else:
		mb.dyn.add_static_prop(name, mb.dyn.seat(name, xf))
	var c := xf.origin
	L.block_rect(_lv, Vector2(c.x, c.z), Vector2(0.35, 0.35), 0.0, 0.2)


func quad_wall(x: float, z: float, h: float, w: float, hh: float, uv: Rect2, mat: String, facing_yaw: float = 0.0, layer: String = "int") -> void:
	## A picture (atlas cell) on a vertical plane, facing local -z rotated by facing_yaw (0: toward the front).
	var bas := _xf.basis * Basis(Vector3.UP, facing_yaw)
	var right := -(bas * Vector3(1, 0, 0))
	S.atlas_quad(P(x, z, h), right, Vector3.UP, w, hh, uv, mat, {"layer": layer})


func loot(x: float, z: float, h: float, table: String) -> void:
	mb.dyn.add_loot_spot(P(x, z, h), table, _bid)


func counter_loot(x: float, z: float, h: float, size: Vector3 = Vector3(0.8, 0.5, 0.5)) -> void:
	mb.dyn.add_container(P(x, z, h), "store_counter", _bid, size)


static func goods_uv(row: int, frac0: float = 0.0, frac1: float = 1.0) -> Rect2:
	return Rect2(frac0, row * 0.25, frac1 - frac0, 0.25)


# ------------------------------------------------------------------ one unit

func _unit(u: Dictionary) -> void:
	var r: Rect2 = u.rect
	var face: Vector2 = u.face
	_lv = int(u.level)
	_y = L.level_y(_lv)
	_shop = u.shop
	_bid = mb.new_building_id()
	var kind := str(u.kind)
	if kind == "lifts":
		B.MallHorror.new(B).lifts(u)
		return
	_power = _shop_power(u, kind)
	_lamp_at = Vector3.INF
	if bool(u.get("whole", false)):
		_whole_island(u, r, kind)
		_record(kind)
		return
	_set_frame(r, face)
	_shell(kind, u)
	if kind == "closed":
		_hoarding()
		_record(kind)
		return
	if kind == "restroom":
		# (r16) Level 3's public restrooms (MallRestrooms draws the front, the fittings and the lights)
		mb.dyn.interior_scope = true
		B.MallRestrooms.new(B).big(self)
		mb.dyn.interior_scope = false
		_record(kind)
		return
	_front(kind, u)
	mb.dyn.interior_scope = true
	_dress(kind, u)
	mb.dyn.interior_scope = false
	_lights(kind)
	_record(kind)


func _record(kind: String) -> void:
	B.rooms.append({"lv": _lv, "xf": _xf, "w": _w, "d": _d, "kind": kind, "power": _power, "bid": _bid, "name": str(_shop.get("name", ""))})


func _shop_power(u: Dictionary, kind: String) -> int:
	## (r16) A third of the shops dark (flashlights), a fifth with one fitting flickering, the rest still lit.
	var c: Vector2 = (u.rect as Rect2).get_center()
	if kind == "closed" or B.burnt(int(u.level), c):
		return B.POWER_DEAD
	var h: float = B.h01(int(c.x * 3.0), int(c.y * 3.0), 300 + int(u.level))
	if kind in ["cinema", "esports", "arcade", "restroom"]:
		return B.POWER_DEAD if h < 0.45 else B.POWER_FAULTY
	if h < 0.34:
		return B.POWER_DEAD
	if h < 0.54:
		return B.POWER_FAULTY
	return B.POWER_ON


func _seg_power(x: float) -> int:
	## Along a long anchor (Level 1-5 ends): stretches of about 8 m, each on, faulty or dead.
	var h: float = B.h01(int(x / 8.0), _lv, 520 + int(absf(_xf.origin.x)))
	return B.POWER_ON if h < 0.38 else (B.POWER_FAULTY if h < 0.55 else B.POWER_DEAD)


func sign_mat() -> String:
	return "mall_signs_dead" if _power == B.POWER_DEAD else "mall_signs"

func _set_frame(r: Rect2, face: Vector2) -> void:
	## Frame: origin at the front's left end (seen from outside, standing in the walkway), x along the front,
	## z inward (opposite face).
	var inward := -face
	var along := Vector2(inward.y, -inward.x)   # x = y cross z: a right-handed frame (doors and glass need one)
	var c := r.get_center()
	var hw := absf(along.x) * r.size.x * 0.5 + absf(along.y) * r.size.y * 0.5
	var hd := absf(face.x) * r.size.x * 0.5 + absf(face.y) * r.size.y * 0.5
	_w = hw * 2.0
	_d = hd * 2.0
	var front_c := c + face * hd
	var origin := front_c - along * hw
	_xf = Transform3D(Basis(Vector3(along.x, 0, along.y), Vector3.UP, Vector3(inward.x, 0, inward.y)), Vector3(origin.x, 0.0, origin.y))


func _shell(kind: String, u: Dictionary) -> void:
	## Dividing walls on both sides and at the back (the outer shell and the island cores are there already for band
	## units: lining only), the shop's floor, its ceiling with downlights, painted linings.
	var col: Color = WALL_COLOURS.get(kind, Color(0.93, 0.92, 0.9))
	var finishes := ["mall_wall_cream","mall_wall_sage","mall_wall_buff"]
	var skin: String = finishes[abs(hash(Vector3i(int(_xf.origin.x),int(_xf.origin.z),_lv)))%3]
	if kind in ["closed","service","gym"]:
		skin = "mall_repair"
	var h: float = L.CEIL
	# side dividers (structure, shared by the neighbours: identical boxes are drawn once)
	for sx in [0.0, _w]:
		var a := P(sx, 0.0)
		var b := P(sx, _d)
		B.wall(_lv, Vector2(a.x, a.z), Vector2(b.x, b.z), _y, h + 0.4, 0.2, "mall_paint", {"tint": B.WHITE, "paint": 1.0, "layer": "ext"})
	# back wall: islands and anchors need one; band units back onto the shell
	var back := P(_w * 0.5, _d)
	if absf(back.z) < L.MZ - L.WALL_T - 0.05 and absf(back.x) < L.MX - L.WALL_T - 0.05:
		var a2 := P(0.0, _d)
		var b2 := P(_w, _d)
		B.wall(_lv, Vector2(a2.x, a2.z), Vector2(b2.x, b2.z), _y, h + 0.4, 0.2, "mall_paint", {"tint": B.WHITE, "paint": 1.0, "layer": "ext"})
	# linings (the shop's colour), 2 cm proud of the structure
	box(0.11, _d * 0.5, h * 0.5, Vector3(0.02, h, _d - 0.25), skin, {"tint": col, "paint": .45})
	box(_w - 0.11, _d * 0.5, h * 0.5, Vector3(0.02, h, _d - 0.25), skin, {"tint": col, "paint": .45})
	box(_w * 0.5, _d - 0.11, h * 0.5, Vector3(_w - 0.25, h, 0.02), skin, {"tint": col, "paint": .45})
	# Different tenants retained different lower wall finishes and trim.
	var lower := "oak" if kind in ["books","cafe","restaurant","fashion_lux"] else ("tiles_white" if kind in ["clinic","food","pharmacy","restroom"] else "mall_wall_sage")
	for sx in [.13,_w-.13]:
		box(sx,_d*.5,.57,Vector3(.025,1.14,_d-.3),lower,{"paint":.0})
		box(sx,_d*.5,1.16,Vector3(.045,.045,_d-.3),"mall_steel")
	box(_w*.5,_d-.13,.57,Vector3(_w-.3,1.14,.025),lower,{"paint":.0})
	box(_w*.5,_d-.15,1.16,Vector3(_w-.3,.045,.04),"mall_steel")
	# floor and ceiling
	var fm: String = FLOORS.get(kind, "oak")
	var c0 := P(0.0, 0.0)
	var c1 := P(_w, _d)
	var fr := Rect2(Vector2(minf(c0.x, c1.x), minf(c0.z, c1.z)), Vector2(absf(c1.x - c0.x), absf(c1.z - c0.z)))
	for fq in B.minus_holes(fr, B.holes_at(_lv)):
		B.hquad(fq, _y, fm, true, {"collide": true, "layer": "ext", "dirt": 0.9})
	var ch: float = _y + h
	var above: Array = B.holes_at(_lv + 1)
	for cq in B.minus_holes(fr, above):
		B.hquad(cq, ch, "mall_ceiling", false, {"tint": Color(0.97, 0.97, 0.96) if col.v > 0.4 else Color(0.08, 0.08, 0.1), "paint": 1.0, "layer": "ext"})
	if kind != "closed" and kind != "restroom":
		var nx := maxi(int(_w / 2.4), 1)
		var nz := maxi(int(_d / 2.4), 1)
		# (r16) the fittings take the shop's power (an anchor's by stretches); a faulty shop's one lamp is the
		# fitting nearest its middle (Lighting draws it, flickering)
		var lamp_ij := Vector2i(-1, -1)
		if _power == B.POWER_FAULTY and _w <= 24.0:
			lamp_ij = Vector2i(nx / 2, nz / 2)
		for i in nx:
			for k in nz:
				var dp := P((i + 0.5) * _w / nx, (k + 0.5) * _d / nz, h - 0.004)
				var in_hole := false
				for hr in above:
					if (hr as Rect2).grow(0.3).has_point(Vector2(dp.x, dp.z)):
						in_hole = true
				if in_hole:
					continue
				var st := _power
				if kind == "department":
					st = dept.power_at(dp) if dept else B.POWER_DEAD
				elif _w > 24.0:
					st = _seg_power((i + 0.5) * _w / nx)
				if Vector2i(i, k) == lamp_ij:
					st = B.POWER_LAMP
					_lamp_at = dp
				elif st == B.POWER_FAULTY:
					st = B.POWER_DEAD
				B.downlight(_lv, dp, st)
	# skirting
	box(_w * 0.5, _d - 0.13, 0.05, Vector3(_w - 0.3, 0.1, 0.02), "mall_satin", {"tint": col.darkened(0.35), "paint": 1.0})


func _front(kind: String, u: Dictionary) -> void:
	## The shopfront across x in [0, w] at z = 0: pilasters, glass panes, the doors (or a wide opening), the fascia band
	## with the sign, and a blade sign.
	var h_glass := 3.3
	var w := _w
	var big := w >= 12.0 or bool(u.get("anchor", false)) or kind in ["supermarket", "department", "food_hall", "food", "cinema", "esports", "kids_play"]
	var open_front := big and kind in ["supermarket", "department", "food_hall", "food", "kids_play", "esports", "books", "appliances"]
	var door_w := (5.0 if open_front else 2.1)
	if bool(u.get("anchor", false)):
		door_w = 7.0 if open_front else 4.2
	var dx0 := w * 0.5 - door_w * 0.5
	var dx1 := w * 0.5 + door_w * 0.5
	# pilasters at both ends, stone
	for px in [0.15, w - 0.15]:
		box(px, 0.0, h_glass * 0.5, Vector3(0.3, h_glass, 0.36), "mall_granite", {"solid": true, "layer": "ext"})
	# fascia band over the whole front: the shop's colour
	var bg := Color.html(str(_shop.get("bg", "#333333")))
	box(w * 0.5, 0.0, (h_glass + L.CEIL) * 0.5, Vector3(w, L.CEIL - h_glass, 0.4), "mall_satin", {"tint": bg, "paint": 1.0, "collide": true, "layer": "ext"})
	# steel head and sill rails along the glass
	box(w * 0.5, 0.0, h_glass - 0.04, Vector3(w - 0.3, 0.08, 0.12), "mall_steel", {"layer": "mid"})
	box(w * 0.5, 0.0, 0.05, Vector3(w - 0.3, 0.1, 0.12), "mall_steel", {"layer": "mid"})
	# glass panes either side of the entrance; (r16) a dark shop may have pulled one side's shutter down
	var cpos := P(w * 0.5, 0.0)
	var shut := -1
	if _power == B.POWER_DEAD and not open_front and B.h01(int(cpos.x * 2.0), int(cpos.z * 2.0), 640 + _lv) < 0.45:
		shut = 0 if B.h01(int(cpos.x), int(cpos.z), 641) < 0.5 else 1
	var si := -1
	for span in [[0.3, dx0], [dx1, w - 0.3]]:
		si += 1
		var s0: float = span[0]
		var s1: float = span[1]
		if s1 - s0 < 0.3:
			continue
		if si == shut:
			_shutter(s0, s1, h_glass, 0.0)
			continue
		var n := maxi(int(ceil((s1 - s0) / 2.6)), 1)
		for k in n:
			var a := s0 + (s1 - s0) * k / n
			var b := s0 + (s1 - s0) * (k + 1) / n
			_pane(a, b, 0.1, h_glass - 0.08)
			if k > 0:
				box(a, 0.0, h_glass * 0.5, Vector3(0.05, h_glass, 0.1), "mall_steel", {"layer": "mid"})
		var pa := P(s0, 0.0)
		var pb := P(s1, 0.0)
		L.block_seg(_lv, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), 0.1, 0.3)
	if open_front:
		# a wide opening: the rolled shutter's box in the head, a threshold strip
		box(w * 0.5, 0.15, h_glass - 0.15, Vector3(door_w, 0.3, 0.3), "mall_steel", {"layer": "mid"})
		box(w * 0.5, 0.0, 0.003, Vector3(door_w, 0.006, 0.3), "mall_steel", {"layer": "mid"})
		if _power != B.POWER_ON:
			# (r16) the shutter stuck half way down when the power went (just over head height), bent at one end
			_shutter(w * 0.5 - door_w * 0.5, w * 0.5 + door_w * 0.5, h_glass - 0.3, 2.3)
	else:
		# a pair (or two pairs) of glass doors and a glass transom over them
		var leaves := 2 if door_w < 3.0 else 4
		var lw := door_w / leaves
		for k in leaves:
			var hinge_left := k % 2 == 0
			var hx := dx0 + k * lw if hinge_left else dx0 + (k + 1) * lw
			var dir := 1.0 if hinge_left else -1.0
			var bas := _xf.basis * Basis(Vector3.UP, 0.0 if hinge_left else PI)
			mb.dyn.add_door({"xf": Transform3D(bas, P(hx, 0.0)), "w": lw - 0.02, "h": 2.5, "t": 0.022, "mat": "mall_glass", "glass": true,
				"outer": false, "bid": _bid, "role": "shop", "clr": Vector2(1.0, 1.0)})
			stats.doors += 1
			# a long steel pull handle on each leaf
			box(hx + dir * (lw - 0.15), -0.04, 1.1, Vector3(0.03, 0.9, 0.03), "mall_chrome", {"layer": "int"})
		_pane(dx0, dx1, 2.56, h_glass - 0.08)
		box(w * 0.5, 0.0, 2.53, Vector3(door_w, 0.06, 0.1), "mall_steel", {"layer": "mid"})
	# the sign on the fascia, and a blade sign at the right-hand end
	var tile := int(_shop.get("tile", -1))
	if tile >= 0:
		var sh := minf(0.78, (L.CEIL - h_glass) - 0.12)
		var sw := minf(sh * 4.0, w - 0.8)
		quad_wall(w * 0.5, -0.215, (h_glass + L.CEIL) * 0.5, sw, sw / 4.0, B.sign_uv(tile), sign_mat(), 0.0, "mid")
		for s in [1.0, -1.0]:
			var bas2 := _xf.basis * Basis(Vector3.UP, PI * 0.5 * s)
			S.atlas_quad(P(w - 0.4 - s * 0.012, -0.9, 3.05), -(bas2 * Vector3(1, 0, 0)), Vector3.UP, 1.0, 0.25, B.sign_uv(tile), sign_mat(), {"layer": "mid"})
		box(w - 0.4, -0.9, 3.05, Vector3(0.02, 0.27, 1.04), "mall_black", {"layer": "mid"})
		box(w - 0.4, -0.45, 3.2, Vector3(0.03, 0.03, 0.9), "mall_steel", {"layer": "mid"})
	# a lit display platform behind the glass (most shops)
	if not open_front and w > 5.0:
		for span2 in [[0.5, dx0 - 0.3], [dx1 + 0.3, w - 0.5]]:
			if float(span2[1]) - float(span2[0]) > 1.2:
				box((float(span2[0]) + float(span2[1])) * 0.5, 0.75, 0.15, Vector3(float(span2[1]) - float(span2[0]), 0.3, 1.1), "mall_gloss", {"tint": Color(0.92, 0.92, 0.9), "paint": 1.0, "solid": true})


func _pane(a: float, b: float, y0: float, y1: float) -> void:
	var w := b - a - 0.04
	if w < 0.2:
		return
	var c := P((a + b) * 0.5, 0.0, (y0 + y1) * 0.5)
	if y1 - y0 > 2.0 and (B.h01(int(c.x * 5.0), int(c.z * 5.0), 600 + _lv) < 0.17 or B.burnt(_lv, Vector2(c.x, c.z))):
		# (r16) smashed in the panic: glass all over the floor both sides, jagged pieces left in the frame
		stats.smashed = int(stats.get("smashed", 0)) + 1
		for side in [-1.0, 1.0]:
			B.floor_decal(P((a + b) * 0.5, side * 1.1, 0.0), Vector2(minf(w + 0.6, 3.2), 2.2), YAW(B.h01(int(c.x), int(c.z), 7) * TAU), "floor_glass", 0.95)
		for k in 3:
			var gx = a + 0.15 + (w - 0.3) * (k + B.h01(int(c.x * 7.0), k, 8)) / 3.0
			var gh = 0.15 + B.h01(int(c.z * 7.0), k, 9) * 0.5
			box(gx, 0.0, y0 + gh * 0.5, Vector3(0.18 + gh * 0.4, gh, 0.012), "mall_glass", {"layer": "mid"}, 0.0)
		return
	mb.dyn.add_window({"xf": Transform3D(_xf.basis, c), "w": w, "h": y1 - y0, "type": "plate", "t": 0.02, "mat": "mall_glass", "bid": _bid})
	stats.panes += 1


func _shutter(a: float, b: float, top: float, bottom: float) -> void:
	## (r16) A roller shutter down from the head over x in [a, b] to bottom: corrugated steel, its box and guides,
	## scuffed and sprayed on. Closed to the floor it is a wall.
	var w := b - a
	var hh := top - bottom
	box((a + b) * 0.5, 0.06, bottom + hh * 0.5, Vector3(w, hh, 0.04), "factory_wall", {"tint": Color(0.6, 0.62, 0.62), "paint": 0.7, "layer": "ext",
		"collide": true, "tile": 1.2}, 0.0)
	box((a + b) * 0.5, 0.06, bottom + 0.03, Vector3(w, 0.06, 0.07), "mall_steel", {"layer": "mid"})
	for gx in [a + 0.03, b - 0.03]:
		box(gx, 0.06, top * 0.5, Vector3(0.06, top, 0.1), "mall_steel", {"layer": "mid"})
	if bottom < 0.1:
		var pa := P(a, 0.0)
		var pb := P(b, 0.0)
		L.block_seg(_lv, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), 0.1, 0.3)
	var c := P((a + b) * 0.5, 0.0)
	var h: float = B.h01(int(c.x * 3.0), int(c.z * 3.0), 650)
	if w > 1.6 and hh > 1.2:
		var names := ["spray_00", "spray_05", "spray_09", "spray_10", "spray_12", "v:spray_03", "v:tag_04", "spray_06"]
		var nm: String = names[int(h * names.size()) % names.size()]
		var dw := minf(w - 0.3, 2.4)
		B.wall_decal(P((a + b) * 0.5, 0.0, bottom + hh * 0.55), -(_xf.basis.z), Vector2(dw, dw * 0.5), nm, 0.92, (h - 0.5) * 0.15, "mid")
	stats.shutters = int(stats.get("shutters", 0)) + 1


func _hoarding() -> void:
	## A unit being fitted out: painted plywood hoarding across the front with the Coming Soon graphic.
	var w := _w
	box(w * 0.5, 0.05, L.CEIL * 0.5, Vector3(w, L.CEIL, 0.1), "plywood", {"solid": true, "tint": Color(0.86, 0.86, 0.84), "paint": 0.95, "layer": "ext"})
	var tile := int(_shop.get("tile", -1))
	if tile >= 0:
		quad_wall(w * 0.5, -0.01, 2.4, minf(w - 1.0, 4.0), minf(w - 1.0, 4.0) / 4.0, B.sign_uv(tile), "mall_signs", 0.0, "mid")
	for k in int(w / 2.4):
		quad_wall(1.2 + k * 2.4, -0.012, 1.0, 1.0, 1.0, Rect2((k % 4) * 0.25, ((k / 4) % 4) * 0.25, 0.25, 0.25), "mall_posters", 0.0, "mid")


func _lights(kind: String) -> void:
	## (r16) After the outbreak: a lit shop keeps its downlights (a pool of light from each), a faulty one has one
	## fitting flickering or dying in the dark, a dark one nothing (flashlights). A long anchor goes by stretches; the
	## department store lights itself (MallDept). Ranges stop short of the next shop and the floor below.
	if kind == "department":
		return
	var warm := kind in ["restaurant", "cafe", "jewelry", "fashion_lux", "bakery", "home", "spa", "books", "bridal"]
	var col := Color(1.0, 0.84, 0.64) if warm else Color(1.0, 0.94, 0.86)
	if kind in ["cinema", "esports", "arcade", "vape", "games"]:
		col = Color(0.62, 0.52, 1.0)
	var c := P(_w * 0.5, _d * 0.5)
	var fault: String = B.FAULTS[int(B.h01(int(c.x), int(c.z), 660) * 6.0) % 6]
	if _w > 24.0:
		var n := maxi(int(_w / 8.0), 1)
		for k in n:
			var x := (k + 0.5) * _w / n
			var st := _seg_power(x)
			if st == B.POWER_DEAD:
				continue
			mb.dyn.add_light({"pos": P(x, _d * 0.5, L.CEIL - 0.3), "kind": "down", "angle": 72.0, "color": col, "energy": 2.6, "range": 7.2, "fade": 32.0,
				"emitter": st == B.POWER_FAULTY, "fault": fault if st == B.POWER_FAULTY else "", "attenuation": 0.8})
		return
	if _power == B.POWER_DEAD:
		return
	var rr := clampf(minf(_w, _d) * 0.55 + 1.0, 4.5, 7.4)
	if _power == B.POWER_FAULTY:
		if _lamp_at != Vector3.INF:
			mb.dyn.add_light({"pos": _lamp_at, "kind": "down", "angle": 74.0, "color": col, "energy": 3.0, "range": rr, "fade": 30.0, "emitter": true,
				"fault": fault, "attenuation": 0.8})
		return
	var nx := maxi(int(round(_w / 6.5)), 1)
	var nz := maxi(int(round(_d / 6.5)), 1)
	for i in nx:
		for k in nz:
			mb.dyn.add_light({"pos": P((i + 0.5) * _w / nx, (k + 0.5) * _d / nz, L.CEIL - 0.25), "kind": "down", "angle": 74.0, "color": col, "energy": 2.2,
				"range": rr, "fade": 30.0, "emitter": false, "attenuation": 0.8})


# ------------------------------------------------------------------ the flagships that take a whole island

func _whole_island(u: Dictionary, r: Rect2, kind: String) -> void:
	## Azrin & Azrael's (Level 1), Toys by EZ-RR (Level 4), Buchokan (Level 5): fronts on the north and south ends and
	## the side toward the Grand Atrium, a solid side toward the other court.
	var toward := -signf(r.get_center().x)
	# Treat it as one unit facing south for the inside, then add the other fronts.
	_set_frame(r, Vector2(0, 1))
	_shell(kind, u)
	_front(kind, u)
	var keep_xf := _xf
	var keep_w := _w
	var keep_d := _d
	_set_frame(r, Vector2(0, -1))
	_front(kind, u)
	# the long side toward the Grand Atrium: a run of display windows, no door
	_set_frame(r, Vector2(toward, 0))
	var w := _w
	for k in int(w / 3.0):
		_pane(0.6 + k * 3.0, 0.6 + (k + 1) * 3.0 - 0.1, 0.1, 3.22)
		box(0.6 + k * 3.0, 0.0, 1.65, Vector3(0.06, 3.3, 0.12), "mall_steel", {"layer": "mid"})
	box(w * 0.5, 0.0, (3.3 + L.CEIL) * 0.5, Vector3(w, L.CEIL - 3.3, 0.4), "mall_satin", {"tint": Color.html(str(_shop.get("bg", "#333"))), "paint": 1.0, "collide": true, "layer": "ext"})
	var pa := P(0.0, 0.0)
	var pb := P(w, 0.0)
	L.block_seg(_lv, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), 0.1, 0.3)
	var tile := int(_shop.get("tile", -1))
	if tile >= 0:
		quad_wall(w * 0.5, -0.215, (3.3 + L.CEIL) * 0.5, 3.1, 0.775, B.sign_uv(tile), "mall_signs", 0.0, "mid")
	# the far side: a solid wall (other court), with the sign too
	_set_frame(r, Vector2(-toward, 0))
	box(_w * 0.5, 0.05, L.CEIL * 0.5, Vector3(_w - 0.2, L.CEIL, 0.1), "mall_paint", {"tint": B.WHITE, "paint": 1.0, "solid": true, "layer": "ext"})
	if tile >= 0:
		quad_wall(_w * 0.5, -0.01, 3.4, 3.1, 0.775, B.sign_uv(tile), "mall_signs", 0.0, "mid")
	_xf = keep_xf
	_w = keep_w
	_d = keep_d
	mb.dyn.interior_scope = true
	_dress(kind, u)
	mb.dyn.interior_scope = false
	_lights(kind)


# ------------------------------------------------------------------ fixtures

func rack(x: float, z: float, len: float, yaw: float = 0.0, palette: Array = []) -> void:
	## A chrome clothes rail on two posts with garments hanging from it.
	var pal: Array = palette if not palette.is_empty() else CLOTH
	box(x, z, 1.42, Vector3(len, 0.03, 0.03), "mall_chrome", {}, yaw)
	for s in [-1.0, 1.0]:
		var o := Vector3(s * len * 0.5, 0, 0).rotated(Vector3.UP, yaw)
		box(x + o.x, z + o.z, 0.71, Vector3(0.04, 1.42, 0.04), "mall_chrome", {}, yaw)
		box(x + o.x, z + o.z, 0.02, Vector3(0.06, 0.04, 0.5), "mall_chrome", {}, yaw)
	var n := int(len / 0.09)
	for i in n:
		var t := -len * 0.5 + (i + 0.5) * len / n
		var o2 := Vector3(t, 0, 0).rotated(Vector3.UP, yaw)
		var c: Color = pal[rng.randi() % pal.size()]
		var hh := rng.randf_range(0.75, 1.05)
		box(x + o2.x, z + o2.z, 1.4 - hh * 0.5, Vector3(0.05, hh, 0.46), "mall_cloth", {"tint": c, "paint": 1.0}, yaw)
	var cc := P(x, z)
	var hl := Vector2(len * 0.5, 0.3)
	L.block_rect(_lv, Vector2(cc.x, cc.z), hl, -YAW(yaw), 0.25)


func round_rack(x: float, z: float) -> void:
	S.cylinder(P(x, z, 1.3), Vector3.UP, 0.03, 0.55, "mall_chrome", B.o({"sides": 16}))
	S.cylinder(P(x, z, 0.0), Vector3.UP, 1.3, 0.025, "mall_chrome", B.o({"sides": 8}))
	for k in 16:
		var a := TAU * k / 16.0
		var c: Color = CLOTH[rng.randi() % CLOTH.size()]
		box(x + cos(a) * 0.55, z + sin(a) * 0.55, 0.85, Vector3(0.05, 0.9, 0.4), "mall_cloth", {"tint": c, "paint": 1.0}, -a)
	var cc := P(x, z)
	L.block_rect(_lv, Vector2(cc.x, cc.z), Vector2(0.7, 0.7), 0.0, 0.2)


func mannequin(x: float, z: float, yaw: float = 0.0, top: Color = Color(0.1, 0.1, 0.1), bottom: Color = Color(0.2, 0.25, 0.4), gown: bool = false, h0: float = 0.0) -> void:
	## A gloss-white display figure on a steel stand, dressed in two colours (a gown for bridal).
	var skin := Color(0.96, 0.96, 0.95)
	var p := P(x, z, h0)
	var bas := _xf.basis * Basis(Vector3.UP, yaw)
	var m := func(off: Vector3, size: Vector3, mat: String, col: Color) -> void:
		S.box(Transform3D(bas, p + bas * off), size, mat, B.o({"tint": col, "paint": 1.0, "layer": "int"}))
	m.call(Vector3(0, 0.02, 0), Vector3(0.4, 0.04, 0.4), "mall_steel", Color(1, 1, 1))
	m.call(Vector3(0, 0.4, 0), Vector3(0.03, 0.8, 0.03), "mall_steel", Color(1, 1, 1))
	if gown:
		S.cylinder(p + Vector3(0, 0.05, 0), Vector3.UP, 1.05, 0.45, "mall_cloth", B.o({"sides": 14, "tint": top, "paint": 1.0, "layer": "int"}))
		S.cylinder(p + Vector3(0, 1.0, 0), Vector3.UP, 0.25, 0.25, "mall_cloth", B.o({"sides": 12, "tint": top, "paint": 1.0, "layer": "int"}))
	else:
		m.call(Vector3(-0.09, 0.5, 0), Vector3(0.13, 0.85, 0.15), "mall_cloth", bottom)
		m.call(Vector3(0.09, 0.5, 0), Vector3(0.13, 0.85, 0.15), "mall_cloth", bottom)
	m.call(Vector3(0, 1.22, 0), Vector3(0.38, 0.55, 0.22), "mall_cloth", top)
	m.call(Vector3(-0.24, 1.15, 0), Vector3(0.09, 0.6, 0.1), "mall_cloth", top)
	m.call(Vector3(0.24, 1.15, 0), Vector3(0.09, 0.6, 0.1), "mall_cloth", top)
	m.call(Vector3(0, 1.55, 0), Vector3(0.08, 0.1, 0.08), "mall_gloss", skin)
	m.call(Vector3(0, 1.7, 0.01), Vector3(0.17, 0.22, 0.2), "mall_gloss", skin)
	L.block_rect(_lv, Vector2(p.x, p.z), Vector2(0.25, 0.25), 0.0, 0.2)


func wall_shelf(x0: float, x1: float, z: float, row: int, levels: int = 4, facing: float = 0.0, h_top: float = 2.2) -> void:
	## Shelving against a wall (z at its back), stocked: a printed face of goods (assets/mall/goods.png row) or of
	## folded clothes / shoes / books (rails.png) behind each shelf board.
	var len := x1 - x0
	var depth := 0.45
	var zc := z - depth * 0.5
	box((x0 + x1) * 0.5, zc, h_top * 0.5, Vector3(len, h_top, 0.03), "white_oak" if row < 4 else "oak", {"solid": false})
	box((x0 + x1) * 0.5, zc - 0.0, h_top * 0.5, Vector3(len + 0.04, h_top, depth), "mall_satin", {"tint": Color(0.92, 0.92, 0.9), "paint": 1.0, "solid": true, "faces": 1 | 2 | 4})
	for k in levels:
		var hy := 0.12 + k * (h_top - 0.2) / levels
		box((x0 + x1) * 0.5, zc - 0.01, hy, Vector3(len, 0.025, depth), "white_oak", {})
		var mat := "mall_goods" if row < 4 else "mall_rails"
		var rr := row % 4
		var span := len / 4.0
		var f0 := fposmod(rng.randf(), 1.0 - minf(span, 0.9))
		quad_wall((x0 + x1) * 0.5, zc - depth * 0.5 + 0.12, hy + 0.17, len - 0.04, 0.32, Rect2(f0, rr * 0.25 + 0.04, minf(span, 0.98), 0.21), mat, facing)


func gondola(x: float, z: float, len: float, yaw: float = 0.0, row: int = 0, h: float = 1.6) -> void:
	## A double-sided store shelf: steel ends, shelves, goods printed on both faces.
	box(x, z, h * 0.5, Vector3(len, h, 0.9), "mall_satin", {"tint": Color(0.88, 0.88, 0.87), "paint": 1.0, "solid": true}, yaw)
	for s in [-1.0, 1.0]:
		var off := Vector3(0, 0, s * 0.46).rotated(Vector3.UP, yaw)
		for k in 4:
			var hy := 0.18 + k * (h - 0.3) / 4.0
			box(x + off.x, z + off.z, hy, Vector3(len, 0.025, 0.06), "mall_steel", {}, yaw)
			var f0 := rng.randf() * 0.6
			quad_wall(x + off.x * 1.01, z + off.z * 1.01, hy + 0.17, len - 0.06, 0.3, Rect2(f0, (row % 4) * 0.25 + 0.04, 0.38, 0.21), "mall_goods", yaw + (0.0 if s < 0.0 else PI))
	box(x, z, h + 0.18, Vector3(len, 0.3, 0.04), "mall_satin", {"tint": Color.html(str(_shop.get("bg", "#2a5")))}, yaw)


func counter(x: float, z: float, w: float, d: float = 0.7, yaw: float = 0.0, mat: String = "white_oak", top: String = "mall_granite", register: bool = true) -> void:
	box(x, z, 0.5, Vector3(w, 1.0, d), mat, {"solid": true}, yaw)
	box(x, z, 1.02, Vector3(w + 0.06, 0.04, d + 0.06), top, {}, yaw)
	if register:
		prop("cash_register", x + 0.2, z + 0.05, yaw + PI, false, 1.04)
	counter_loot(x - w * 0.25, z, 0.55)


func glass_case(x: float, z: float, w: float, d: float = 0.6, yaw: float = 0.0, items: Color = Color(0.85, 0.7, 0.25), h: float = 0.95) -> void:
	## A glass-topped display counter: dark base, a lit glass box with things on a velvet pad.
	box(x, z, (h - 0.35) * 0.5, Vector3(w, h - 0.35, d), "mall_black", {"solid": true}, yaw)
	box(x, z, h - 0.35 + 0.012, Vector3(w - 0.04, 0.02, d - 0.04), "velvet", {}, yaw)
	box(x, z, h - 0.175, Vector3(w, 0.35, d), "mall_glass", {"collide": true}, yaw)
	box(x, z, h - 0.01, Vector3(w - 0.06, 0.01, 0.03), "mall_light_warm", {}, yaw)
	for k in int(w / 0.18):
		var o := Vector3(-w * 0.5 + 0.1 + k * 0.18, 0, rng.randf_range(-0.15, 0.15)).rotated(Vector3.UP, yaw)
		box(x + o.x, z + o.z, h - 0.31, Vector3(0.07, 0.04, 0.07), "mall_metal_vc", {"tint": items, "paint": 1.0}, yaw + rng.randf())


func table_set(x: float, z: float, chairs: int = 4, table: String = "cafe_table", chair: String = "fc_chair") -> void:
	prop(table, x, z, rng.randf() * TAU, true)
	for k in chairs:
		var a := TAU * k / chairs + rng.randf_range(-0.2, 0.2)
		prop(chair, x + cos(a) * 0.8, z + sin(a) * 0.8, atan2(-cos(a), -sin(a)), true)


func screen(x: float, z: float, h: float, w: float, hh: float, facing: float = 0.0, phase: float = -1.0) -> void:
	## A wall screen showing the mall's adverts (the LED shader), black bezel.
	box(x, z + 0.04, h, Vector3(w + 0.08, hh + 0.08, 0.06), "mall_black", {}, facing)
	var bas := _xf.basis * Basis(Vector3.UP, facing)
	var right := -(bas * Vector3(1, 0, 0))
	S.atlas_quad(P(x, z, h) - bas * Vector3(0, 0, 0.012), right, Vector3.UP, w, hh, Rect2(0, 0, 0.5, 0.25), "mall_ads",
		{"layer": "mid", "tint": Color(phase if phase >= 0.0 else rng.randf(), 0, 0, 1)})


func pc_desk(x: float, z: float, yaw: float = 0.0, glow: Color = Color(0.9, 0.1, 0.2)) -> void:
	box(x, z, 0.73, Vector3(1.2, 0.04, 0.65), "mall_black", {"solid": true}, yaw)
	for s in [-1.0, 1.0]:
		var o := Vector3(s * 0.55, 0, 0).rotated(Vector3.UP, yaw)
		box(x + o.x, z + o.z, 0.36, Vector3(0.04, 0.72, 0.6), "mall_black", {}, yaw)
	var mo := Vector3(0, 0, 0.18).rotated(Vector3.UP, yaw)
	box(x + mo.x, z + mo.z, 1.05, Vector3(0.62, 0.36, 0.03), "mall_black", {}, yaw)
	box(x + mo.x * 0.92, z + mo.z * 0.92, 1.05, Vector3(0.58, 0.32, 0.005), "mall_glow", {"tint": Color(0.2, 0.45, 0.9).lerp(glow, rng.randf() * 0.5)}, yaw)
	box(x, z, 0.76, Vector3(0.45, 0.02, 0.15), "mall_glow", {"tint": glow * 0.8}, yaw)
	var co := Vector3(0.45, 0, -0.05).rotated(Vector3.UP, yaw)
	box(x + co.x, z + co.z, 0.95, Vector3(0.2, 0.45, 0.45), "mall_black", {}, yaw)
	box(x + co.x * 1.0, z + co.z * 1.0, 0.95, Vector3(0.205, 0.02, 0.4), "mall_glow", {"tint": glow}, yaw)
	var so := Vector3(0, 0, -0.65).rotated(Vector3.UP, yaw)
	prop("bar_stool", x + so.x, z + so.z, yaw, true)


func neon(x0: float, x1: float, z: float, h: float, col: Color, facing: float = 0.0) -> void:
	box((x0 + x1) * 0.5, z, h, Vector3(x1 - x0, 0.04, 0.04), "mall_glow", {"tint": col}, facing)


func poster(x: float, z: float, h: float, idx: int, size: float = 1.1, facing: float = 0.0) -> void:
	quad_wall(x, z, h, size, size, Rect2((idx % 4) * 0.25, ((idx / 4) % 4) * 0.25, 0.25, 0.25), "mall_posters", facing)


func plant(x: float, z: float, big: bool = false) -> void:
	box(x, z, 0.3, Vector3(0.55, 0.6, 0.55), "mall_satin", {"tint": Color(0.18, 0.18, 0.2), "paint": 1.0, "solid": true})
	prop("money_tree" if big else "plant_calathea", x, z, rng.randf() * TAU, false, 0.6)


# ------------------------------------------------------------------ dressing by kind

func _dress(kind: String, u: Dictionary) -> void:
	if kind == "department" and dept:
		dept.dress(self, u)
		return
	if _w > 18.0 and not kind in ["supermarket", "cinema", "esports", "kids_play", "gym", "restaurant", "food_hall"]:
		# A long anchor front (up to 91 m): the recipe in bays of about 12 m, each with its own cash point.
		var keep_xf := _xf
		var keep_w := _w
		var n := int(round(keep_w / 12.0))
		var bw := keep_w / n
		for i in n:
			_xf = keep_xf * Transform3D(Basis(), Vector3(i * bw, 0, 0))
			_w = bw
			_dress_one(kind, u)
			if i > 0:
				# a light partition with a wide opening between bays, to break the long room up
				box(0.0, _d * 0.3, 1.2, Vector3(0.12, 2.4, _d * 0.35), "mall_satin", {"tint": Color(0.9, 0.89, 0.86), "paint": 1.0, "solid": true})
		_xf = keep_xf
		_w = keep_w
		return
	_dress_one(kind, u)


func _dress_one(kind: String, u: Dictionary) -> void:
	var w := _w
	var d := _d
	match kind:
		"fashion", "fashion_kids", "department", "tailor":
			_fashion(kind)
		"fashion_lux":
			_fashion_lux()
		"bridal":
			for k in 4:
				mannequin(1.2 + k * (w - 2.4) / 3.0, 0.75, PI, Color(0.98, 0.97, 0.94), Color.WHITE, true, 0.3)
			prop("sofa_modern", w * 0.5, d * 0.55, PI, false)
			box(w - 0.2, d * 0.5, 1.4, Vector3(0.02, 2.2, 2.4), "mall_mirror", {}, PI * 0.5)
			rack(w * 0.3, d - 0.8, w * 0.5)
			counter(w * 0.75, d - 1.4, 1.6)
		"shoes", "sports":
			_shoes(kind)
		"bags":
			_bags()
		"beauty":
			_beauty()
		"jewelry", "optical":
			_jewelry(kind)
		"toys", "gifts", "hobby":
			_toys(kind)
		"vape":
			_vape()
		"tech", "games", "appliances", "music":
			_tech(kind)
		"esports", "arcade":
			_esports(kind)
		"cafe", "bakery":
			_cafe(kind)
		"food", "food_hall":
			_food(kind)
		"restaurant":
			_restaurant()
		"supermarket", "convenience", "pharmacy":
			_market(kind)
		"books":
			_books()
		"cinema":
			_cinema()
		"kids_play":
			_kids_play()
		"gym":
			_gym()
		"home", "plants":
			_home(kind)
		"salon", "barber", "spa", "clinic":
			_salon(kind)
		"service", "pets":
			_service(kind)
		_:
			counter(w * 0.5, d - 1.5, 2.0)
	# a gun or two lying about, as in every building
	if rng.randf() < 0.55:
		loot(w * rng.randf_range(0.25, 0.75), d * rng.randf_range(0.4, 0.8), 0.02, "floor_weapon")
	loot(w * rng.randf_range(0.2, 0.8), d * rng.randf_range(0.3, 0.85), 0.02, "floor_contested")


func _fashion(kind: String) -> void:
	var w := _w
	var d := _d
	var kids := kind == "fashion_kids"
	var pal := CLOTH if not kids else [Color(1, 0.5, 0.6), Color(0.4, 0.8, 0.95), Color(1, 0.85, 0.3), Color(0.6, 0.9, 0.5), Color(0.8, 0.6, 1.0)]
	# window mannequins
	if w > 5.0:
		for k in 2:
			var c1: Color = pal[rng.randi() % pal.size()]
			var c2: Color = pal[rng.randi() % pal.size()]
			mannequin(0.9 + k * 0.7, 0.75, PI + rng.randf_range(-0.4, 0.4), c1, c2, false, 0.3)
			mannequin(w - 0.9 - k * 0.7, 0.75, PI + rng.randf_range(-0.4, 0.4), c2, c1, false, 0.3)
	# wall bays: folded stacks on the side walls
	_side_shelves(5)
	var rows := maxi(int((d - 3.0) / 2.2), 1)
	var cols := maxi(int((w - 2.0) / 3.2), 1)
	for i in cols:
		for k in rows:
			var x := 1.0 + (i + 0.5) * (w - 2.0) / cols
			var z := 2.6 + k * 2.2
			if z > d - 1.6:
				continue
			if (i + k) % 3 == 2:
				round_rack(x, z)
			else:
				rack(x, z, minf(2.2, (w - 2.0) / cols - 0.8), 0.0, pal)
	# fitting rooms at the back right, a cash desk at the back left
	_fitting_rooms(w - 3.2, d - 0.2)
	counter(1.6, d - 1.3, 2.2)
	poster(w * 0.5, d - 0.13, 2.6, rng.randi() % 16, 1.4, 0.0)


func _side_shelves(row: int) -> void:
	## Stocked shelving along both side walls (row: 4 = hanging clothes, 5 = folded stacks, 6 = shoes, 7 = books).
	var d := _d
	var w := _w
	for s in [0, 1]:
		var x := 0.35 if s == 0 else w - 0.35
		var yaw := -PI * 0.5 if s == 0 else PI * 0.5
		var z0 := 1.8
		var z1 := d - 0.6
		if z1 - z0 < 1.0:
			continue
		box(x, (z0 + z1) * 0.5, 1.15, Vector3(0.45, 2.3, z1 - z0), "mall_satin", {"tint": Color(0.92, 0.91, 0.88), "paint": 1.0, "solid": true})
		for k in 4:
			var hy := 0.25 + k * 0.52
			box(x + (0.235 if s == 0 else -0.235), (z0 + z1) * 0.5, hy, Vector3(0.02, 0.02, z1 - z0), "white_oak", {})
			var bas := Basis(Vector3.UP, yaw)
			var right := -((_xf.basis * bas) * Vector3(1, 0, 0))
			S.atlas_quad(P(x + (0.235 if s == 0 else -0.235), (z0 + z1) * 0.5, hy + 0.22), right, Vector3.UP, z1 - z0 - 0.05, 0.42,
				Rect2(rng.randf() * 0.4, (row % 4) * 0.25 + 0.03, 0.55, 0.2), "mall_rails" if row >= 4 else "mall_goods", {"layer": "int"})


func _fitting_rooms(x_left: float, z_back: float) -> void:
	for k in 3:
		var x := x_left + k * 1.0
		if x > _w - 0.4:
			break
		box(x, z_back - 0.6, 1.1, Vector3(0.04, 2.2, 1.2), "mall_satin", {"tint": Color(0.85, 0.82, 0.78), "paint": 1.0, "solid": true})
		box(x + 0.5, z_back - 1.22, 1.05, Vector3(0.95, 1.9, 0.02), "mall_cloth", {"tint": Color(0.35, 0.3, 0.28), "paint": 1.0})


func _fashion_lux() -> void:
	## Azrin & Azrael's: marble, a few rails spaced like a gallery, mannequins on plinths, a chandelier, velvet seats.
	var w := _w
	var d := _d
	var gold := Color(0.83, 0.68, 0.38)
	for k in 6:
		var z := 3.0 + k * (d - 6.0) / 5.0
		box(w * 0.5, z, 0.12, Vector3(1.2, 0.24, 1.2), "mall_marble", {"solid": true})
		mannequin(w * 0.5, z, rng.randf() * TAU, CLOTH[k % CLOTH.size()], Color(0.08, 0.08, 0.09), k % 3 == 1, 0.24)
	for s in [-1.0, 1.0]:
		for k in 5:
			var z2 := 4.0 + k * (d - 8.0) / 4.0
			rack(w * 0.5 + s * (w * 0.32), z2, 1.6, PI * 0.5, [Color(0.05, 0.05, 0.06), Color(0.95, 0.94, 0.9), gold, Color(0.5, 0.05, 0.08)])
	prop("chandelier", w * 0.5, d * 0.5, 0.0, false, L.CEIL - 0.82)
	prop("chandelier", w * 0.5, d * 0.25, 0.0, false, L.CEIL - 0.82)
	prop("chandelier", w * 0.5, d * 0.75, 0.0, false, L.CEIL - 0.82)
	prop("sofa_modern", w * 0.5 - 2.0, d * 0.5, PI * 0.5, false)
	glass_case(w * 0.5 + 1.8, d * 0.5, 1.8, 0.6, PI * 0.5, gold)
	counter(w * 0.5, d - 1.6, 2.6, 0.7, 0.0, "walnut", "mall_marble")
	for k in 4:
		box(0.2, 2.0 + k * (d - 4.0) / 3.0, 2.0, Vector3(0.02, 2.4, 0.04), "mall_metal_vc", {"tint": gold, "paint": 1.0})
		box(w - 0.2, 2.0 + k * (d - 4.0) / 3.0, 2.0, Vector3(0.02, 2.4, 0.04), "mall_metal_vc", {"tint": gold, "paint": 1.0})


func _shoes(kind: String) -> void:
	var w := _w
	var d := _d
	_side_shelves(6)
	box(w * 0.5, d - 0.35, 1.15, Vector3(w - 1.0, 2.3, 0.45), "mall_satin", {"tint": Color(0.92, 0.92, 0.92), "paint": 1.0, "solid": true})
	for k in 4:
		quad_wall(w * 0.5, d - 0.58, 0.47 + k * 0.52, w - 1.1, 0.42, Rect2(rng.randf() * 0.4, 0.5 + 0.03, 0.55, 0.2), "mall_rails", 0.0)
	for k in maxi(int((d - 4.0) / 2.5), 1):
		var z := 2.8 + k * 2.5
		prop("ottoman", w * 0.35, z, 0.0, true)
		prop("ottoman", w * 0.65, z, 0.0, true)
		box(w * 0.5, z, 0.45, Vector3(1.6, 0.9, 0.7), "white_oak", {"solid": true})
		for j in 4:
			var c: Color = CLOTH[rng.randi() % CLOTH.size()]
			box(w * 0.5 - 0.6 + j * 0.4, z, 0.97, Vector3(0.12, 0.12, 0.3), "mall_satin", {"tint": c, "paint": 1.0})
	if kind == "sports":
		for k2 in 6:
			S.cylinder(P(w * 0.25 + k2 * 0.18, 1.5, 0.11), Vector3.UP, 0.22, 0.11, "mall_flat", B.o({"sides": 10, "tint": Color(0.95, 0.5, 0.1), "paint": 1.0, "layer": "int"}))
	counter(w - 1.8, 1.8, 1.8)


func _bags() -> void:
	var w := _w
	var d := _d
	# cube shelving with handbags on the walls
	for s in [0, 1]:
		var x := 0.4 if s == 0 else w - 0.4
		var z0 := 1.6
		var z1 := d - 0.6
		box(x, (z0 + z1) * 0.5, 1.2, Vector3(0.5, 2.4, z1 - z0), "white_oak", {"solid": true})
		for k in int((z1 - z0) / 0.6):
			for j in 4:
				var c: Color = [Color(0.45, 0.2, 0.1), Color(0.1, 0.1, 0.1), Color(0.75, 0.6, 0.45), Color(0.6, 0.1, 0.18), Color(0.9, 0.88, 0.8)][rng.randi() % 5]
				box(x + (0.27 if s == 0 else -0.27), z0 + 0.3 + k * 0.6, 0.3 + j * 0.55, Vector3(0.2, 0.28, 0.36), "leather" if rng.randf() < 0.5 else "mall_satin", {"tint": c, "paint": 1.0})
	for k in maxi(int((d - 4.0) / 3.0), 1):
		glass_case(w * 0.5, 2.8 + k * 3.0, minf(w - 3.0, 2.4), 0.6, 0.0, Color(0.9, 0.8, 0.5))
	counter(w * 0.5, d - 1.5, 2.2, 0.7, 0.0, "white_oak")
	for k2 in 2:
		mannequin(1.0 + k2 * (w - 2.0), 0.8, PI, Color(0.85, 0.75, 0.65), Color(0.1, 0.1, 0.12), false, 0.3)


func _beauty() -> void:
	var w := _w
	var d := _d
	for k in maxi(int((d - 3.0) / 2.6), 1):
		var z := 2.4 + k * 2.6
		box(w * 0.5, z, 0.5, Vector3(minf(w - 3.0, 3.0), 1.0, 1.0), "mall_gloss", {"tint": Color(0.98, 0.98, 0.98), "paint": 1.0, "solid": true})
		for j in 10:
			var c: Color = [Color(0.95, 0.75, 0.8), Color(0.8, 0.9, 0.95), Color(0.95, 0.9, 0.6), Color(0.2, 0.2, 0.2)][j % 4]
			S.cylinder(P(w * 0.5 - 1.2 + j * 0.26, z - 0.2 + (j % 2) * 0.4, 1.0), Vector3.UP, rng.randf_range(0.1, 0.22), 0.035, "mall_gloss", B.o({"sides": 8, "tint": c, "paint": 1.0, "layer": "int"}))
	for s in [0, 1]:
		var x := 0.25 if s == 0 else w - 0.25
		box(x, d * 0.5 + 0.5, 1.3, Vector3(0.3, 2.6, d - 3.0), "mall_gloss", {"tint": Color(0.98, 0.96, 0.97), "paint": 1.0, "solid": true})
		box(x + (0.16 if s == 0 else -0.16), d * 0.5 + 0.5, 1.6, Vector3(0.01, 0.6, d - 3.4), "mall_mirror", {})
		box(x + (0.17 if s == 0 else -0.17), d * 0.5 + 0.5, 1.95, Vector3(0.01, 0.04, d - 3.4), "mall_light", {})
	counter(w * 0.5, d - 1.3, 2.0, 0.7, 0.0, "mall_gloss")


func _jewelry(kind: String) -> void:
	var w := _w
	var d := _d
	var items := Color(0.85, 0.7, 0.3) if kind == "jewelry" else Color(0.2, 0.2, 0.22)
	# a U of glass counters, staff behind, a wall display
	glass_case(w * 0.5, d * 0.45, minf(w - 2.4, 4.0), 0.6, 0.0, items)
	glass_case(1.4, d * 0.6, d * 0.4, 0.6, PI * 0.5, items)
	glass_case(w - 1.4, d * 0.6, d * 0.4, 0.6, PI * 0.5, items)
	box(w * 0.5, d - 0.3, 1.4, Vector3(w - 1.0, 1.8, 0.35), "mall_black" if kind == "jewelry" else "white_oak", {"solid": true})
	for k in int((w - 1.4) / 0.5):
		box(0.9 + k * 0.5, d - 0.5, 1.4, Vector3(0.25, 0.25, 0.05), "mall_metal_vc", {"tint": items, "paint": 1.0})
	box(w * 0.5, d - 0.48, 2.25, Vector3(w - 1.2, 0.03, 0.03), "mall_light_warm", {})
	for s in [-1.0, 1.0]:
		prop("bar_stool", w * 0.5 + s * 0.9, d * 0.45 - 0.7, PI, true)
	counter_loot(w * 0.5, d * 0.45, 0.4)


func _toys(kind: String) -> void:
	var w := _w
	var d := _d
	_side_shelves(1)
	var rows := maxi(int((d - 3.0) / 2.6), 1)
	for k in rows:
		gondola(w * 0.5, 2.6 + k * 2.6, minf(w - 3.0, 4.0), 0.0, 1, 1.4)
	if kind == "hobby":
		for k2 in 3:
			glass_case(1.5 + k2 * 1.6, d - 1.4, 1.3, 0.6, 0.0, Color(0.9, 0.3, 0.3), 1.6)
		# capsule machines by the door
		for j in 3:
			var c: Color = [Color(1, 0.3, 0.4), Color(0.3, 0.7, 1), Color(1, 0.85, 0.2)][j]
			box(0.8 + j * 0.6, 1.2, 0.55, Vector3(0.5, 1.1, 0.45), "mall_gloss", {"tint": c, "paint": 1.0, "solid": true})
			S.cylinder(P(0.8 + j * 0.6, 1.2, 1.1), Vector3.UP, 0.42, 0.22, "mall_glass", B.o({"sides": 12, "layer": "int"}))
	else:
		# a giant plush bear and a play table
		var bear := Color(0.72, 0.5, 0.32)
		S.cylinder(P(w - 1.2, 1.4, 0.0), Vector3.UP, 0.9, 0.45, "mall_cloth", B.o({"sides": 14, "tint": bear, "paint": 1.0, "layer": "int"}))
		S.cylinder(P(w - 1.2, 1.4, 0.9), Vector3.UP, 0.55, 0.32, "mall_cloth", B.o({"sides": 14, "tint": bear, "paint": 1.0, "layer": "int"}))
		box(w - 1.2, 1.4, 0.8, Vector3(1.0, 1.6, 1.0), "mall_cloth", {"tint": bear, "paint": 0.0, "solid": true, "faces": 0})
		box(1.8, d - 1.6, 0.3, Vector3(1.6, 0.6, 1.0), "mall_gloss", {"tint": Color(0.3, 0.75, 0.95), "paint": 1.0, "solid": true})
	counter(w * 0.5, d - 0.9, 2.0, 0.6, 0.0, "mall_gloss")


func _vape() -> void:
	## TCD Vapes: dark room, teal light lines, back-lit wall shelves, a long glass counter, a lounge corner.
	var w := _w
	var d := _d
	var teal := Color(0.21, 0.95, 0.8)
	glass_case(w * 0.5, d * 0.55, minf(w - 2.0, 4.5), 0.6, 0.0, Color(0.6, 0.6, 0.65), 1.0)
	neon(w * 0.5 - 2.2, w * 0.5 + 2.2, d * 0.55 + 0.32, 0.12, teal)
	box(w * 0.5, d - 0.3, 1.3, Vector3(w - 1.0, 2.4, 0.3), "mall_black", {"solid": true})
	for k in 4:
		box(w * 0.5, d - 0.46, 0.5 + k * 0.5, Vector3(w - 1.2, 0.02, 0.02), "mall_glow", {"tint": teal})
		for j in int((w - 1.4) / 0.14):
			var c: Color = [Color(0.9, 0.3, 0.5), Color(0.3, 0.9, 0.6), Color(0.4, 0.6, 1.0), Color(0.95, 0.8, 0.3)][(j + k) % 4]
			box(0.75 + j * 0.14, d - 0.5, 0.6 + k * 0.5, Vector3(0.05, 0.14, 0.05), "mall_gloss", {"tint": c, "paint": 1.0})
	neon(0.4, w - 0.4, 0.4, L.CEIL - 0.2, teal, 0.0)
	prop("lounge_chair", 1.2, 2.0, PI * 0.75, true)
	prop("lounge_chair", w - 1.2, 2.0, -PI * 0.75, true)
	for s in [-1.0, 1.0]:
		prop("bar_stool", w * 0.5 + s * 1.0, d * 0.55 - 0.7, PI, true)
	counter_loot(w * 0.5, d * 0.55, 0.4)


func _tech(kind: String) -> void:
	var w := _w
	var d := _d
	# display tables with devices, a screen wall at the back, accessories on the side walls
	var rows := maxi(int((d - 3.5) / 2.6), 1)
	for k in rows:
		var z := 2.8 + k * 2.6
		box(w * 0.5, z, 0.45, Vector3(minf(w - 3.0, 3.6), 0.9, 1.1), "white_oak" if kind != "games" else "mall_black", {"solid": true})
		for j in 6:
			var px := w * 0.5 - 1.4 + j * 0.56
			if kind == "appliances":
				continue
			box(px, z + rng.randf_range(-0.25, 0.25), 0.915, Vector3(0.09, 0.012, 0.17), "mall_black", {}, rng.randf_range(-0.3, 0.3))
			box(px, z + rng.randf_range(-0.25, 0.25), 0.923, Vector3(0.08, 0.004, 0.15), "mall_glow", {"tint": Color(0.3, 0.5, 0.9)}, 0.0)
	if kind == "appliances":
		for k2 in int((w - 1.0) / 0.85):
			box(0.8 + k2 * 0.85, d - 0.6, 0.9, Vector3(0.75, 1.8, 0.7), "mall_gloss", {"tint": Color(0.95, 0.95, 0.96) if k2 % 3 else Color(0.6, 0.62, 0.64), "paint": 1.0, "solid": true})
			box(0.8 + k2 * 0.85 + 0.3, d - 0.96, 1.2, Vector3(0.03, 0.5, 0.03), "mall_chrome", {})
	elif kind == "music":
		for k3 in int((w - 1.0) / 0.5):
			box(0.8 + k3 * 0.5, d - 0.3, 1.6, Vector3(0.35, 1.0, 0.08), "walnut", {}, 0.0)
			box(0.8 + k3 * 0.5, d - 0.3, 2.25, Vector3(0.06, 0.45, 0.06), "walnut", {})
		box(w * 0.3, d * 0.6, 0.5, Vector3(1.5, 1.0, 0.6), "mall_black", {"solid": true})
	else:
		screen(w * 0.5, d - 0.25, 2.1, minf(w - 1.5, 3.2), minf(w - 1.5, 3.2) * 0.5, 0.0)
		_side_shelves(2 if kind == "tech" else 1)
	counter(w * 0.5, 1.6 if kind == "appliances" else d - 1.3, 2.0, 0.7, 0.0, "mall_gloss")


func _esports(kind: String) -> void:
	## Quake Team's arena (and the arcade): rows of gaming PCs in red light, a stage with a big screen.
	var w := _w
	var d := _d
	var glow := Color(1.0, 0.15, 0.2) if kind == "esports" else Color(0.95, 0.2, 0.75)
	if kind == "arcade":
		for k in int((d - 2.5) / 1.6):
			for s in [0, 1]:
				var x := 0.7 if s == 0 else w - 0.7
				box(x, 2.0 + k * 1.6, 0.9, Vector3(0.8, 1.8, 0.75), "mall_black", {"solid": true})
				box(x + (0.41 if s == 0 else -0.41), 2.0 + k * 1.6, 1.25, Vector3(0.01, 0.5, 0.6), "mall_ads", {})
				box(x + (0.41 if s == 0 else -0.41), 2.0 + k * 1.6, 1.75, Vector3(0.01, 0.12, 0.7), "mall_glow", {"tint": glow})
		counter(w * 0.5, d - 1.2, 2.4, 0.7, 0.0, "mall_gloss")
		return
	var rows := int((d - 8.0) / 2.6)
	var per := int((w - 2.0) / 1.4)
	for k in rows:
		for j in per:
			pc_desk(1.4 + j * 1.4, 4.0 + k * 2.6, 0.0, glow)
	# stage at the back
	box(w * 0.5, d - 2.2, 0.3, Vector3(minf(w - 2.0, 16.0), 0.6, 3.6), "mall_black", {"solid": true})
	screen(w * 0.5, d - 0.3, 3.0, minf(w - 3.0, 9.0), minf(w - 3.0, 9.0) * 0.5 * 0.6, 0.0, 0.3)
	for j2 in 4:
		pc_desk(w * 0.5 - 2.4 + j2 * 1.6, d - 2.6, PI, glow)
	neon(0.5, w - 0.5, 0.5, L.CEIL - 0.25, glow)
	neon(0.5, w - 0.5, d - 0.45, 0.2, glow)
	counter(w * 0.5, 1.8, 3.0, 0.7, 0.0, "mall_black")


func _cafe(kind: String) -> void:
	var w := _w
	var d := _d
	# counter along the back with a pastry case and the espresso machine, menu boards above, tables
	counter(w * 0.5, d - 1.6, minf(w - 1.6, 4.0), 0.75, 0.0, "walnut", "mall_marble")
	glass_case(w * 0.5 - 1.0, d - 2.25, 1.4, 0.55, 0.0, Color(0.85, 0.6, 0.35), 1.05)
	box(w * 0.5 + 1.0, d - 1.6, 1.25, Vector3(0.6, 0.45, 0.45), "mall_chrome", {})
	box(w * 0.5, d - 0.4, 0.9, Vector3(w - 1.0, 1.8, 0.6), "mall_steel", {"solid": true})
	for k in 3:
		quad_wall(w * 0.5 - 1.6 + k * 1.6, d - 0.12, 2.9, 1.4, 0.7, Rect2(0.5, 0.0, 0.25, 0.25) if kind == "bakery" else Rect2((k % 4) * 0.25, 0.75, 0.25, 0.25), "mall_posters", 0.0)
	var n := maxi(int((d - 4.0) / 2.2), 1)
	for k2 in n:
		for s in [0.3, 0.7]:
			table_set(w * s, 1.8 + k2 * 2.2, 2, "round_table2", "bar_stool" if k2 % 2 == 0 else "dining_chair")
	prop("plant_anthurium", 0.6, d - 0.8, 0.0, false)


func _food(kind: String) -> void:
	## A food-court stall: a counter across the front third, menu boards over it, the kitchen behind (steel), and
	## (the Food Hall) tables in the room.
	var w := _w
	var d := _d
	var zc := 2.2 if kind == "food" else d - 3.0
	counter(w * 0.5, zc, w - 1.2, 0.8, 0.0, "mall_satin", "mall_steel")
	box(w * 0.5, zc, 0.5, Vector3(w - 1.2, 1.0, 0.82), "mall_satin", {"tint": Color.html(str(_shop.get("bg", "#a33"))), "paint": 1.0})
	for k in 3:
		screen(w * 0.5 - (w - 2.0) / 3.0 + k * (w - 2.0) / 3.0, zc + 1.3, 3.2, minf((w - 2.0) / 3.0 - 0.2, 1.6), 0.8, 0.0)
	for j in int((w - 1.0) / 1.2):
		box(0.9 + j * 1.2, d - 0.5, 0.45, Vector3(1.1, 0.9, 0.7), "mall_steel", {"solid": true})
		box(0.9 + j * 1.2, d - 0.5, 1.6, Vector3(1.1, 0.5, 0.5), "mall_steel", {})
	if kind == "food_hall":
		for k2 in maxi(int((d - 5.0) / 2.4), 1):
			for s in [0.25, 0.75]:
				table_set(w * s, 1.6 + k2 * 2.4, 4, "round_table2", "dining_chair")


func _restaurant() -> void:
	## Buchokan: walnut and warm light, booths along the walls, tables down the middle, a bar, the kitchen pass.
	var w := _w
	var d := _d
	for k in int((d - 6.0) / 2.4):
		var z := 2.6 + k * 2.4
		for s in [0, 1]:
			var x := 0.9 if s == 0 else w - 0.9
			box(x, z, 0.35, Vector3(1.2, 0.7, 1.9), "leather", {"solid": true, "tint": Color(0.5, 0.18, 0.12), "paint": 0.6})
			box(x + (0.5 if s == 0 else -0.5), z, 0.85, Vector3(0.2, 1.0, 1.9), "leather", {"tint": Color(0.5, 0.18, 0.12), "paint": 0.6})
		if k % 2 == 0:
			table_set(w * 0.5, z, 4, "round_table2", "dining_chair")
		prop("ceiling_lamp_modern", w * 0.5, z, 0.0, false, L.CEIL - 0.95)
	counter(w * 0.5, d - 2.6, w - 2.0, 0.7, 0.0, "walnut", "mall_marble")
	for j in 6:
		prop("bar_stool", w * 0.5 - 2.5 + j, d - 3.3, PI, true)
	box(w * 0.5, d - 0.6, 1.6, Vector3(w - 1.0, 0.8, 0.5), "walnut", {})
	for j2 in int((w - 1.2) / 0.12):
		box(0.7 + j2 * 0.12, d - 0.6, 2.15, Vector3(0.07, 0.28, 0.07), "glass", {})
	prop("whale_statue", w * 0.5, 1.6, PI, false)


func _market(kind: String) -> void:
	## Supermarket / convenience / pharmacy: aisles of gondolas, chillers on the back wall, checkouts by the door.
	var w := _w
	var d := _d
	var aisle_w := 2.4
	var n := maxi(int((w - 2.0) / aisle_w), 1)
	var z0 := 4.5 if kind == "supermarket" else 3.0
	var z1 := d - 2.4
	for i in n:
		var x := 1.4 + (i + 0.5) * (w - 2.8) / n
		var seg := 0
		var z := z0
		while z + 4.0 < z1:
			gondola(x, z + 2.0, 4.0, PI * 0.5, (i + seg) % 4, 1.7 if kind == "supermarket" else 1.5)
			z += 5.0
			seg += 1
	# chillers along the back
	for j in int((w - 1.0) / 1.3):
		box(0.9 + j * 1.3, d - 0.55, 1.05, Vector3(1.2, 2.1, 0.8), "mall_steel", {"solid": true})
		box(0.9 + j * 1.3, d - 0.96, 1.15, Vector3(1.1, 1.7, 0.02), "mall_glass", {})
		quad_wall(0.9 + j * 1.3, d - 0.98, 1.15, 1.05, 0.55, Rect2(rng.randf() * 0.5, 0.75 + 0.02, 0.45, 0.22), "mall_goods", 0.0)
		box(0.9 + j * 1.3, d - 0.97, 2.05, Vector3(1.1, 0.04, 0.02), "mall_light", {})
	# checkouts
	var checks := clampi(int(w / 3.0), 1, 6) if kind == "supermarket" else 1
	for c in checks:
		var x2 := 1.6 + c * 3.0 if kind == "supermarket" else w - 1.8
		counter(x2, 2.4 if kind == "supermarket" else 1.6, 1.8, 0.7, PI * 0.5 if kind == "supermarket" else 0.0, "mall_satin", "mall_steel")
	if kind == "pharmacy":
		box(w * 0.5, d - 1.6, 0.55, Vector3(w - 2.0, 1.1, 0.7), "mall_gloss", {"tint": Color(0.97, 0.97, 0.97), "paint": 1.0, "solid": true})
		mb.dyn.add_container(P(w * 0.5, d - 1.6, 0.6), "clinic", _bid, Vector3(1.2, 0.5, 0.5))


func _books() -> void:
	var w := _w
	var d := _d
	_side_shelves(7)
	var rows := maxi(int((d - 4.0) / 2.4), 1)
	for k in rows:
		var z := 3.0 + k * 2.4
		if k % 3 == 1:
			box(w * 0.5, z, 0.42, Vector3(minf(w - 3.0, 2.6), 0.84, 1.0), "oak", {"solid": true})
			for j in 8:
				var c: Color = CLOTH[rng.randi() % CLOTH.size()]
				box(w * 0.5 - 1.1 + j * 0.3, z + rng.randf_range(-0.2, 0.2), 0.9, Vector3(0.22, 0.05 * rng.randi_range(1, 4), 0.3), "mall_satin", {"tint": c, "paint": 1.0}, rng.randf() * 0.4)
		else:
			box(w * 0.5, z, 0.85, Vector3(minf(w - 3.0, 3.6), 1.7, 0.6), "oak", {"solid": true})
			for s in [-1.0, 1.0]:
				for lvl in 4:
					quad_wall(w * 0.5, z + s * 0.31, 0.3 + lvl * 0.4, minf(w - 3.0, 3.6) - 0.05, 0.36, Rect2(rng.randf() * 0.4, 0.75 + 0.03, 0.55, 0.2), "mall_rails", 0.0 if s < 0.0 else PI)
	prop("lounge_chair", 1.2, d - 1.4, 0.4, true)
	counter(w - 2.0, 1.8, 1.8, 0.7, 0.0, "oak")


func _cinema() -> void:
	## Malasugue Cineplex (Level 5, the whole east anchor, 91 m of front and 14.5 m deep): the lobby in the middle with
	## the ticket and concession counters, posters and a big screen; a hall at each end, its screen on the end wall and
	## stadium seating stepping up toward the lobby, dark but for the screen and the step lights.
	var w := _w
	var d := _d
	var lob0 := w * 0.5 - 9.0
	var lob1 := w * 0.5 + 9.0
	counter(w * 0.5, d - 3.0, 9.0, 0.8, 0.0, "mall_black", "mall_steel")
	for k in 4:
		S.cylinder(P(w * 0.5 - 3.0 + k * 2.0, d - 3.0, 1.04), Vector3.UP, 0.45, 0.22, "mall_glass", B.o({"sides": 10, "layer": "int"}))
		box(w * 0.5 - 3.0 + k * 2.0, d - 3.0, 1.15, Vector3(0.36, 0.2, 0.36), "mall_flat", {"tint": Color(0.98, 0.88, 0.5), "paint": 1.0})
	screen(w * 0.5, d - 0.3, 3.0, 7.0, 2.0, 0.0, 0.6)
	for k2 in 3:
		poster(lob0 + 2.0 + k2 * 2.0, d - 0.13, 1.9, 8 + k2, 1.4, 0.0)
		poster(lob1 - 2.0 - k2 * 2.0, d - 0.13, 1.9, 11 + k2, 1.4, 0.0)
	prop("sofa_modern", w * 0.5 - 4.0, 3.0, 0.0, false)
	prop("sofa_modern", w * 0.5 + 4.0, 3.0, 0.0, false)
	for s in [-1.0, 1.0]:
		var wall_x := lob0 if s < 0.0 else lob1
		# the hall's wall to the lobby, with an opening (curtained) by the front
		box(wall_x, (d + 2.4) * 0.5, L.CEIL * 0.5, Vector3(0.3, L.CEIL, d - 2.4), "mall_paint", {"tint": Color(0.16, 0.07, 0.18), "paint": 1.0, "solid": true, "layer": "ext"})
		box(wall_x, 1.2, 3.3, Vector3(0.3, 1.8, 2.4), "mall_paint", {"tint": Color(0.16, 0.07, 0.18), "paint": 1.0, "collide": true, "layer": "ext"})
		box(wall_x - s * 0.3, 1.2, 1.2, Vector3(0.04, 2.4, 2.2), "velvet", {"tint": Color(0.45, 0.05, 0.08), "paint": 0.8})
		# the screen on the end wall and the seats stepping up toward the lobby
		var end_x := 0.4 if s < 0.0 else w - 0.4
		screen(end_x, d * 0.5, 2.7, d - 3.0, (d - 3.0) * 0.42, PI * 0.5 * s, 0.15 + 0.4 * s)
		var hall_len := absf(wall_x - end_x)
		var tiers := int((hall_len - 8.0) / 1.0)
		for t in tiers:
			var x = end_x - s * (6.0 + t * 1.0)
			var hy := 0.2 * (t + 1)
			box(x, d * 0.5, hy * 0.5, Vector3(1.0, hy, d - 1.0), "carpet", {"collide": true, "tint": Color(0.25, 0.08, 0.1), "paint": 0.6})
			box(x + s * 0.48, d * 0.5, hy + 0.01, Vector3(0.04, 0.02, d - 1.2), "mall_light_warm", {})
			for j in int((d - 3.0) / 0.6):
				box(x + s * 0.15, 1.6 + j * 0.6, hy + 0.25, Vector3(0.5, 0.5, 0.52), "velvet", {"tint": Color(0.6, 0.08, 0.1), "paint": 0.7})
				box(x + s * 0.38, 1.6 + j * 0.6, hy + 0.55, Vector3(0.12, 0.6, 0.52), "velvet", {"tint": Color(0.6, 0.08, 0.1), "paint": 0.7})
			var c := P(x, d * 0.5)
			L.block_rect(_lv, Vector2(c.x, c.z), Vector2(0.5, d * 0.5 - 1.5), -YAW(), 0.0)
			if t > 0:
				# a step up from the last tier: bots link the aisle
				pass


func _kids_play() -> void:
	## Kidz Kingdom: modules of padded platforms on posts, a ball pit between them, bright rubber floor, along the
	## whole anchor.
	var w := _w
	var d := _d
	var cols := [Color(1, 0.35, 0.4), Color(0.3, 0.75, 1), Color(1, 0.85, 0.2), Color(0.45, 0.85, 0.45), Color(0.7, 0.5, 1)]
	var n := maxi(int((w - 4.0) / 8.0), 1)
	for i in n:
		var x := 2.0 + (i + 0.5) * (w - 4.0) / n
		var c: Color = cols[i % cols.size()]
		if i % 3 == 2:
			box(x, d * 0.55, 0.35, Vector3(5.0, 0.7, 4.0), "mall_flat", {"tint": Color(0.3, 0.75, 1), "paint": 1.0, "solid": true})
			for j2 in 70:
				var c2: Color = cols[j2 % cols.size()]
				box(x + rng.randf_range(-2.3, 2.3), d * 0.55 + rng.randf_range(-1.8, 1.8), 0.72 + rng.randf() * 0.04, Vector3(0.09, 0.09, 0.09), "mall_gloss", {"tint": c2, "paint": 1.0}, rng.randf())
			continue
		box(x, d * 0.55, 0.6, Vector3(5.0, 1.2, 4.0), "mall_flat", {"tint": c, "paint": 1.0, "solid": true})
		box(x + 1.5, d * 0.55, 1.8, Vector3(2.0, 0.3, 4.0), "mall_flat", {"tint": cols[(i + 2) % cols.size()], "paint": 1.0, "collide": true})
		for j in 4:
			S.cylinder(P(x - 2.4 + j * 1.6, d * 0.55 - 2.0, 0.0), Vector3.UP, 2.6, 0.06, "mall_flat", B.o({"sides": 8, "tint": Color(0.95, 0.95, 0.95), "paint": 1.0, "layer": "int"}))
		# a slide off the top deck toward the front
		var bas := _xf.basis * Basis(Vector3.RIGHT, -0.5)
		S.box(Transform3D(bas, P(x - 1.0, d * 0.55 - 3.0, 1.0)), Vector3(0.8, 0.06, 2.6), "mall_gloss", B.o({"tint": cols[(i + 1) % cols.size()], "paint": 1.0, "layer": "int"}))
	counter(w * 0.5, 2.0, 2.4, 0.7, 0.0, "mall_gloss")


func _gym() -> void:
	var w := _w
	var d := _d
	for k in int((d - 4.0) / 2.2):
		var z := 2.6 + k * 2.2
		for j in int((w - 2.0) / 1.2):
			if j % 8 == 7:
				continue   # aisles between the blocks of machines
			var x := 1.4 + j * 1.2
			if k < 3:
				box(x, z, 0.12, Vector3(0.8, 0.24, 1.8), "mall_black", {"solid": true})
				box(x, z - 0.7, 0.75, Vector3(0.08, 1.3, 0.08), "mall_black", {})
				box(x, z - 0.75, 1.35, Vector3(0.6, 0.35, 0.08), "mall_black", {})
				box(x, z - 0.79, 1.35, Vector3(0.5, 0.25, 0.01), "mall_glow", {"tint": Color(0.3, 0.9, 0.4)})
			elif k % 2 == 0:
				box(x, z, 0.25, Vector3(0.4, 0.5, 1.2), "leather", {"solid": true, "tint": Color(0.1, 0.1, 0.1), "paint": 0.5})
	box(w * 0.5, d - 0.2, 1.4, Vector3(w - 1.0, 2.0, 0.02), "mall_mirror", {})
	for j2 in int((w - 2.0) / 0.4):
		S.cylinder(P(1.0 + j2 * 0.4, d - 0.6, 0.25), Vector3.RIGHT.rotated(Vector3.UP, YAW()), 0.06, 0.18, "mall_black", B.o({"sides": 10, "layer": "int"}))
	counter(w * 0.5, 1.6, 2.4, 0.7, 0.0, "mall_black")


func _home(kind: String) -> void:
	var w := _w
	var d := _d
	if kind == "plants":
		for k in int((d - 3.0) / 1.6):
			for j in int((w - 2.0) / 1.6):
				plant(1.4 + j * 1.6, 2.4 + k * 1.6, (j + k) % 3 == 0)
		counter(w - 1.6, 1.6, 1.6, 0.7, 0.0, "oak")
		return
	# room sets: a sofa, a coffee table, a rug, a lamp
	var sets := maxi(int((d - 3.0) / 3.6), 1)
	for k in sets:
		var z := 3.0 + k * 3.6
		box(w * 0.5, z, 0.004, Vector3(minf(w - 2.0, 3.2), 0.008, 2.4), "boucle", {"tint": Color(0.86, 0.82, 0.74), "paint": 0.5})
		prop("sofa_modern" if k % 2 == 0 else "sofa_leather", w * 0.5, z + 0.8, PI, false)
		prop("coffee_table_modern", w * 0.5, z - 0.3, 0.0, true)
		prop("lounge_chair", w * 0.5 + 1.8, z - 0.2, -PI * 0.6, true)
		prop("side_table_tall", w * 0.5 - 1.8, z + 0.6, 0.0, true)
		prop("vase_ceramic", w * 0.5 - 1.8, z + 0.6, 0.0, true, 0.76)
	_side_shelves(0)
	counter(1.6, d - 1.3, 1.6, 0.7, 0.0, "white_oak")


func _salon(kind: String) -> void:
	var w := _w
	var d := _d
	var n := int((w - 1.6) / 1.4)
	for k in n:
		var x := 1.2 + k * 1.4
		if kind in ["barber", "salon"]:
			prop("barber_chair", x, d - 1.6, 0.0, false)
			box(x, d - 0.3, 1.5, Vector3(0.9, 1.1, 0.04), "mall_mirror", {})
			box(x, d - 0.35, 0.8, Vector3(1.0, 0.06, 0.4), "white_oak" if kind == "salon" else "walnut", {})
		elif kind == "spa":
			prop("lounge_chair", x, d - 1.8, PI, true)
			box(x + 0.65, d - 1.8, 1.1, Vector3(0.02, 2.2, 2.0), "mall_cloth", {"tint": Color(0.86, 0.8, 0.68), "paint": 1.0})
		else:
			prop("barber_chair", x, d - 1.8, 0.0, false)
			box(x, d - 0.4, 1.2, Vector3(0.8, 0.8, 0.5), "mall_gloss", {"tint": Color(0.97, 0.98, 1.0), "paint": 1.0, "solid": true})
	for j in 3:
		prop("ottoman", 1.0 + j * 0.9, 1.8, 0.0, true)
	counter(w - 1.6, 1.6, 1.6, 0.6, 0.0, "white_oak")
	plant(w - 0.6, 3.4, true)
	if kind == "clinic":
		mb.dyn.add_container(P(w * 0.5, d - 0.6, 0.8), "clinic", _bid, Vector3(0.8, 0.6, 0.4))


func _service(kind: String) -> void:
	var w := _w
	var d := _d
	if kind == "pets":
		for k in int((w - 1.6) / 1.2):
			box(0.9 + k * 1.2, d - 0.5, 0.9, Vector3(1.1, 0.7, 0.6), "mall_glass", {"collide": true})
			box(0.9 + k * 1.2, d - 0.5, 0.75, Vector3(1.05, 0.4, 0.55), "mall_glow", {"tint": Color(0.15, 0.45, 0.8)})
			box(0.9 + k * 1.2, d - 0.5, 0.27, Vector3(1.1, 0.54, 0.6), "mall_black", {"solid": true})
		_side_shelves(3)
		counter(w * 0.5, 2.0, 2.0)
		return
	# counters with screens between, a queue line, chairs
	var n := maxi(int((w - 1.6) / 1.6), 1)
	for k2 in n:
		var x := 1.2 + k2 * 1.6
		counter(x, d - 1.8, 1.4, 0.6, 0.0, "mall_satin", "mall_granite", k2 == 0)
		box(x + 0.75, d - 1.8, 1.5, Vector3(0.02, 0.9, 0.6), "mall_glass", {})
	for j in 4:
		prop("fc_chair", 1.0 + j * 0.7, 2.0, PI, true)
	box(w * 0.5, d - 0.15, 2.4, Vector3(w - 1.0, 0.9, 0.02), "mall_flat", {"tint": Color.html(str(_shop.get("bg", "#2a9d8f"))), "paint": 1.0})
