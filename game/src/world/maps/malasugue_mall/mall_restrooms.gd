extends RefCounted
## (r16) Malasugue Mall's restrooms, fitted out properly: tiled walls with a dark band, a vanity counter with basins,
## taps and a long mirror, soap and hand dryers, cubicles with laminate partitions, doors (most hanging open, some
## off a hinge), toilets with cisterns and seats, urinals with privacy screens in the gents, bins, the signs. The
## blocks by the north-west and south-east stair cores on every level (blocks), and on Level 3 the big public
## restrooms in the unit beside the north-west block (big): gents with five urinals and four cubicles, ladies with
## seven cubicles, vanities for both, a baby-changing shelf.
##
## Left as people left them: water on the floors, toilet paper trailed out, mirrors cracked, writing in the
## cubicles; on Level 3 people sheltered in there (mattresses, cans, a radio) until something got in - one cubicle
## still shut and wedged, blood seeping under its door, "MAMA I'M OK" on the mirror.

var B = null
var mb = null
var L = null
var S = null
var stats := {"toilets": 0, "urinals": 0, "stalls": 0, "basins": 0}
var _F := Transform3D()   # the room's frame: x across, z inward from the front, y up from the floor
var _lv := 0

const WHITE := Color(0.96, 0.96, 0.95)
const LAMINATE := [Color(0.3, 0.4, 0.52), Color(0.72, 0.64, 0.52), Color(0.36, 0.46, 0.38)]


func _init(builder) -> void:
	B = builder
	mb = builder.mb
	L = builder.L
	S = builder.S


# ------------------------------------------------------------------ frame helpers

func p(x: float, z: float, h: float = 0.0) -> Vector3:
	return _F * Vector3(x, h, z)


func fb(x: float, z: float, h: float, size: Vector3, mat: String, opt: Dictionary = {}, yaw: float = 0.0) -> void:
	## A box in the room frame (centre x, h, z); opt.collide makes it solid, opt.block also closes the bots' grid.
	var op = B.o(opt)
	if not op.has("layer"):
		op.layer = "int"
	S.box(Transform3D(_F.basis * Basis(Vector3.UP, yaw), p(x, z, h)), size, mat, op)
	if opt.get("block", false):
		var c := p(x, z, h)
		L.block_rect(_lv, Vector2(c.x, c.z), Vector2(size.x, size.z) * 0.5, -(_F.basis.get_euler().y + yaw), 0.15)


func cyl(x: float, z: float, h: float, len: float, r: float, mat: String, tint: Color = Color(1, 1, 1), sides: int = 12) -> void:
	S.cylinder(p(x, z, h), Vector3.UP, len, r, mat, B.o({"sides": sides, "tint": tint, "paint": 1.0 if tint != Color(1, 1, 1) else 0.0, "layer": "int"}))


func wdecal(x: float, z: float, h: float, facing_yaw: float, size: Vector2, name: String, alpha: float = 1.0) -> void:
	## A decal on a wall of the room, facing local -z turned by facing_yaw (0: toward the front).
	var n := _F.basis * Basis(Vector3.UP, facing_yaw) * Vector3(0, 0, -1)
	B.wall_decal(p(x, z, h), n, size, name, alpha, 0.0, "int")


func fdecal(x: float, z: float, size: Vector2, name: String, alpha: float = 1.0, yaw: float = 0.0) -> void:
	B.floor_decal(p(x, z), size, _F.basis.get_euler().y + yaw, name, alpha)


func puddle(x: float, z: float, w: float, d: float) -> void:
	S.atlas_quad(p(x, z, 0.004), _F.basis.x, -_F.basis.z, w, d, Rect2(0, 0, 1, 1), "puddle", {"layer": "int"})


func frame_for(r: Rect2) -> void:
	## A restroom block's frame: x across (right-handed), z from its front on the walk to the back.
	var inner_z := r.end.y if r.position.y < 0.0 else r.position.y
	var outer_z := r.position.y if r.position.y < 0.0 else r.end.y
	var Z := Vector3(0, 0, signf(outer_z - inner_z))
	var X := Vector3.UP.cross(Z)
	var front_c := Vector3(r.get_center().x, L.level_y(_lv), inner_z)
	_F = Transform3D(Basis(X, Vector3.UP, Z), front_c - X * r.size.x * 0.5)


# ------------------------------------------------------------------ fittings

func toilet(x: float, z: float, yaw: float, lid_up: bool = true) -> void:
	## Back to the wall at local +z (turned by yaw): pedestal, bowl, seat, lid, cistern and its button.
	var bas := Basis(Vector3.UP, yaw)
	var c := Vector3(x, 0, z)
	var at := func(o: Vector3) -> Vector3: return c + bas * o
	var q: Vector3 = at.call(Vector3(0, 0, -0.08))
	cyl(q.x, q.z, 0.0, 0.3, 0.15, "mall_gloss", WHITE, 12)
	cyl(q.x, q.z, 0.3, 0.1, 0.2, "mall_gloss", WHITE, 14)
	var s: Vector3 = at.call(Vector3(0, 0, -0.06))
	fb(s.x, s.z, 0.415, Vector3(0.4, 0.03, 0.46), "mall_gloss", {"tint": Color(0.92, 0.92, 0.9), "paint": 1.0}, yaw)
	var t: Vector3 = at.call(Vector3(0, 0, 0.24))
	fb(t.x, t.z, 0.66, Vector3(0.44, 0.4, 0.18), "mall_gloss", {"tint": WHITE, "paint": 1.0}, yaw)
	fb(t.x, t.z, 0.87, Vector3(0.46, 0.03, 0.2), "mall_gloss", {"tint": WHITE, "paint": 1.0}, yaw)
	var bt: Vector3 = at.call(Vector3(0.1, 0, 0.24))
	fb(bt.x, bt.z, 0.89, Vector3(0.06, 0.012, 0.06), "mall_chrome", {}, yaw)
	if lid_up:
		var l: Vector3 = at.call(Vector3(0, 0, 0.1))
		S.box(Transform3D(_F.basis * bas * Basis(Vector3(1, 0, 0), -1.35), p(l.x, l.z, 0.64)), Vector3(0.4, 0.45, 0.025), "mall_gloss", B.o({"tint": Color(0.92, 0.92, 0.9), "paint": 1.0, "layer": "int"}))
	var cc: Vector3 = at.call(Vector3(0, 0, 0.0))
	S.col_box(Transform3D(_F.basis * bas, p(cc.x, cc.z, 0.4)), Vector3(0.45, 0.8, 0.7), "concrete", "toilet")
	L.block_rect(_lv, Vector2(p(cc.x, cc.z).x, p(cc.x, cc.z).z), Vector2(0.25, 0.35), 0.0, 0.1)
	stats.toilets += 1


func urinal(x: float, z: float, yaw: float, screen: bool = true) -> void:
	## On the wall behind it (local +z turned by yaw): the bowl, its dark lip, the flush pipe, a screen to one side.
	var bas := Basis(Vector3.UP, yaw)
	var c := Vector3(x, 0, z)
	fb(x, z, 0.85, Vector3(0.38, 0.62, 0.3), "mall_gloss", {"tint": WHITE, "paint": 1.0}, yaw)
	var f: Vector3 = c + bas * Vector3(0, 0, -0.152)
	fb(f.x, f.z, 0.8, Vector3(0.26, 0.38, 0.01), "mall_satin", {"tint": Color(0.62, 0.64, 0.62), "paint": 1.0}, yaw)
	var pp: Vector3 = c + bas * Vector3(0, 0, 0.06)
	fb(pp.x, pp.z, 1.38, Vector3(0.035, 0.45, 0.035), "mall_chrome", {}, yaw)
	if screen:
		var sc: Vector3 = c + bas * Vector3(0.42, 0, -0.08)
		fb(sc.x, sc.z, 1.05, Vector3(0.02, 0.85, 0.45), "mall_satin", {"tint": Color(0.82, 0.82, 0.8), "paint": 1.0, "collide": true}, yaw)
	stats.urinals += 1


func stall(x0: float, x1: float, z0: float, z1: float, toilet_at_back: bool, door: float, col: Color, closed: bool = false) -> void:
	## A cubicle from x0 to x1, its door in the front at z0, the back at z1 (a wall). door: how far the leaf hangs
	## open (radians, 0 shut, negative: off its top hinge and leaning). Partitions stand 15 cm off the floor.
	var w := x1 - x0
	var dz := signf(z1 - z0)
	var yaw_front := 0.0 if dz > 0.0 else PI
	var lam := {"tint": col, "paint": 1.0, "collide": true}
	for sx in [x0, x1]:
		fb(sx, (z0 + z1) * 0.5, 1.08, Vector3(0.03, 1.85, absf(z1 - z0)), "mall_satin", lam)
		var a := p(sx, z0)
		var b := p(sx, z1)
		L.block_seg(_lv, Vector2(a.x, a.z), Vector2(b.x, b.z), 0.05, 0.25)
	var dw := minf(0.68, w - 0.24)
	var dx0 := x0 + (w - dw) * 0.5
	# the front: narrow fixed panels either side of the door, a head rail over all
	fb((x0 + dx0) * 0.5, z0, 1.08, Vector3(dx0 - x0, 1.85, 0.03), "mall_satin", lam)
	fb((dx0 + dw + x1) * 0.5, z0, 1.08, Vector3(x1 - dx0 - dw, 1.85, 0.03), "mall_satin", lam)
	fb((x0 + x1) * 0.5, z0, 2.03, Vector3(w + 0.06, 0.04, 0.05), "mall_chrome", {})
	var hinge := Vector3(dx0, 0, z0)
	if door < 0.0:
		# off its top hinge, leaning into the cubicle
		S.box(Transform3D(_F.basis * Basis(Vector3.UP, yaw_front) * Basis(Vector3(0, 0, 1), 0.12) * Basis(Vector3(1, 0, 0), -0.25),
			p(dx0 + dw * 0.5, z0 + dz * 0.25, 0.95)), Vector3(dw, 1.7, 0.03), "mall_satin", B.o({"tint": col.darkened(0.08), "paint": 1.0, "layer": "int"}))
	else:
		var bas := Basis(Vector3.UP, yaw_front - door * dz)
		var dc := hinge + bas * Vector3(dw * 0.5 * (1.0 if dz > 0.0 else -1.0), 0, 0)
		var dopt := {"tint": col.darkened(0.08), "paint": 1.0, "collide": closed}
		fb(dc.x, dc.z, 1.08, Vector3(dw, 1.7, 0.03), "mall_satin", dopt, yaw_front - door * dz)
		var lk := hinge + bas * Vector3((dw - 0.08) * (1.0 if dz > 0.0 else -1.0), 0, -0.02 * dz)
		fb(lk.x, lk.z, 0.95, Vector3(0.05, 0.05, 0.02), "mall_flat", {"tint": Color(0.8, 0.1, 0.1) if closed else Color(0.1, 0.65, 0.2), "paint": 1.0}, yaw_front)
		if closed:
			var da := p(dx0, z0)
			var db := p(dx0 + dw, z0)
			L.block_seg(_lv, Vector2(da.x, da.z), Vector2(db.x, db.z), 0.05, 0.2)
	if toilet_at_back:
		toilet((x0 + x1) * 0.5, z1 - dz * 0.36, 0.0 if dz > 0.0 else PI, (int(x0 * 7.0) % 3) != 0)
		var hold := Vector3(x1 - 0.06, 0, z1 - dz * 0.75)
		fb(hold.x, hold.z, 0.7, Vector3(0.04, 0.12, 0.12), "mall_chrome", {})
	stats.stalls += 1


func vanity(cx: float, cz: float, len: float, yaw: float, basins: int, mirror_name: String = "") -> void:
	## A granite counter len long against a wall, (cx, cz) the middle of its back edge on the wall's face; yaw turns
	## it so that local +z points into the wall (0: a wall at the back). Basins and taps, soap, the mirror over it,
	## optionally a decal on the mirror.
	var bas := Basis(Vector3.UP, yaw)
	var into := bas * Vector3(0, 0, 1)
	var along := bas * Vector3(1, 0, 0)
	var c0 := Vector3(cx, 0, cz)
	var c := c0 - into * 0.28
	fb(c.x, c.z, 0.84, Vector3(len, 0.05, 0.56), "mall_granite", {"collide": true, "block": true}, yaw)
	var ap := c0 - into * 0.54
	fb(ap.x, ap.z, 0.62, Vector3(len, 0.4, 0.04), "mall_satin", {"tint": Color(0.2, 0.2, 0.22), "paint": 1.0}, yaw)
	for k in basins:
		var bx := c0 + along * (-len * 0.5 + len * (k + 0.5) / basins)
		var bc := bx - into * 0.3
		cyl(bc.x, bc.z, 0.855, 0.012, 0.19, "mall_gloss", WHITE, 14)
		cyl(bc.x, bc.z, 0.858, 0.012, 0.15, "mall_satin", Color(0.55, 0.57, 0.58), 12)
		var tp := bx - into * 0.08
		fb(tp.x, tp.z, 0.98, Vector3(0.04, 0.22, 0.04), "mall_chrome", {}, yaw)
		var sp := bx - into * 0.15
		fb(sp.x, sp.z, 1.07, Vector3(0.04, 0.03, 0.14), "mall_chrome", {}, yaw)
		var sd := bx + along * 0.28 - into * 0.05
		fb(sd.x, sd.z, 1.22, Vector3(0.1, 0.18, 0.08), "mall_gloss", {"tint": Color(0.9, 0.9, 0.9), "paint": 1.0}, yaw)
		stats.basins += 1
	var mc := c0 - into * 0.008
	fb(mc.x, mc.z, 1.6, Vector3(len - 0.1, 1.0, 0.012), "mall_mirror", {}, yaw)
	if mirror_name != "":
		var md := c0 - into * 0.02
		wdecal(md.x, md.z, 1.6, yaw, Vector2(minf(len - 0.3, 2.0), minf(len - 0.3, 2.0) * 0.5), mirror_name, 0.95)


func with_frame(sub: Transform3D, fn: Callable) -> void:
	## Run fn with the room frame turned (sub, in room coordinates): fittings along another wall.
	var keep := _F
	_F = _F * sub
	fn.call()
	_F = keep


func dryer(x: float, z: float, facing: float) -> void:
	var bas := Basis(Vector3.UP, facing)
	var c := Vector3(x, 0, z) - bas * Vector3(0, 0, 0.11)
	fb(c.x, c.z, 1.25, Vector3(0.3, 0.26, 0.2), "mall_gloss", {"tint": Color(0.92, 0.92, 0.9), "paint": 1.0}, facing)
	var n := c - bas * Vector3(0, 0, 0.08)
	fb(n.x, n.z, 1.1, Vector3(0.08, 0.06, 0.08), "mall_chrome", {}, facing)


func bin(x: float, z: float, tipped: bool = false) -> void:
	if tipped:
		S.cylinder(p(x, z, 0.2), _F.basis.x, 0.55, 0.18, "mall_steel", B.o({"sides": 10, "layer": "int"}))
		fdecal(x + 0.6, z, Vector2(1.2, 1.2), "floor_papers_1", 0.9)
	else:
		cyl(x, z, 0.0, 0.55, 0.18, "mall_steel", Color(1, 1, 1), 10)


func paper_trail(x: float, z: float, yaw: float, len: float) -> void:
	## Toilet paper unrolled across the floor.
	var bas := _F.basis * Basis(Vector3.UP, yaw)
	S.box(Transform3D(bas, p(x, z, 0.004) + bas * Vector3(len * 0.5, 0, 0)), Vector3(len, 0.004, 0.1), "mall_cloth", B.o({"tint": Color(0.95, 0.95, 0.93), "paint": 1.0, "layer": "int"}))


func blade(x: float, h: float) -> void:
	## A sign standing out from the front into the walk (both faces), seen from along the walk either way.
	var n: Vector3 = _F.basis.x.normalized()
	var c := p(x, -0.85, h)
	fb(x, -0.85, h, Vector3(0.04, 0.46, 1.62), "mall_satin", {"tint": Color(0.12, 0.14, 0.18), "paint": 1.0, "layer": "mid"})
	fb(x, -0.03, h + 0.26, Vector3(0.03, 0.03, 0.06), "mall_steel", {"layer": "mid"})
	for s in [1.0, -1.0]:
		var nn = n * s
		S.atlas_quad(c + nn * 0.024, Vector3.UP.cross(nn), Vector3.UP, 1.6, 0.4, B.cell("wc_restrooms"), B.APOC, {"layer": "mid"})


func walls_tiled(w: float, d: float, lv: int) -> void:
	## Tile skins on the inside faces (a dark band at 1.4 m), so every block reads as a restroom.
	for sx in [0.135, w - 0.135]:
		fb(sx, d * 0.5, L.CEIL * 0.5, Vector3(0.02, L.CEIL, d - 0.3), "tiles_white", {"tile": 1.2})
		fb(sx + (0.012 if sx < 1.0 else -0.012), d * 0.5, 1.4, Vector3(0.012, 0.1, d - 0.32), "mall_satin", {"tint": Color(0.18, 0.2, 0.24), "paint": 1.0})


# ------------------------------------------------------------------ the blocks by the cores

func blocks() -> void:
	for r in L.RESTROOMS:
		for lv in L.LEVELS:
			_lv = lv
			frame_for(r)
			_block(r as Rect2, lv)


func _block(r: Rect2, lv: int) -> void:
	var w := r.size.x
	var d := r.size.y
	var h: float = L.CEIL
	var y: float = L.level_y(lv)
	var tag = B.h01(int(r.position.x), lv, 960)
	# walls: sides tiled, the front painted outside with the entry in the middle, a header over it
	for sx in [0.0, w]:
		var a := p(sx, 0.0)
		var b := p(sx, d)
		B.wall(lv, Vector2(a.x, a.z), Vector2(b.x, b.z), y, h, 0.2, "tiles_white", {"layer": "ext", "tile": 1.2})
	var ex0 := w * 0.5 - 0.8
	var ex1 := w * 0.5 + 0.8
	for seg in [[0.0, ex0], [ex1, w]]:
		var a2 := p(seg[0], 0.0)
		var b2 := p(seg[1], 0.0)
		B.wall(lv, Vector2(a2.x, a2.z), Vector2(b2.x, b2.z), y, h, 0.2, "mall_paint", {"tint": B.CREAM, "paint": 1.0, "layer": "ext"})
	fb(w * 0.5, 0.0, 2.6 + (h - 2.6) * 0.5, Vector3(1.6, h - 2.6, 0.2), "mall_paint", {"tint": B.CREAM, "paint": 1.0, "collide": true, "layer": "ext"})
	S.atlas_quad(p(w * 0.5, -0.115, 3.05), -_F.basis.x, Vector3.UP, 1.5, 0.375, B.cell("wc_restrooms"), B.APOC, {"layer": "mid"})
	blade(w * 0.5 - 1.6, 3.0)
	walls_tiled(w, d, lv)
	# the privacy screen and the partition (gents on the left, ladies on the right)
	var sz := 1.6
	var a3 := p(w * 0.5 - 1.4, sz)
	var b3 := p(w * 0.5 + 1.4, sz)
	B.wall(lv, Vector2(a3.x, a3.z), Vector2(b3.x, b3.z), y, 2.3, 0.12, "tiles_white", {"layer": "int", "tile": 1.2})
	var a4 := p(w * 0.5, sz + 0.1)
	var b4 := p(w * 0.5, d)
	B.wall(lv, Vector2(a4.x, a4.z), Vector2(b4.x, b4.z), y, 2.4, 0.12, "tiles_white", {"layer": "int", "tile": 1.2})
	S.atlas_quad(p(w * 0.25, sz - 0.07, 2.0), -_F.basis.x, Vector3.UP, 0.75, 0.3, B.cell("wc_gents"), B.APOC, {"layer": "int"})
	S.atlas_quad(p(w * 0.75, sz - 0.07, 2.0), -_F.basis.x, Vector3.UP, 0.75, 0.3, B.cell("wc_ladies"), B.APOC, {"layer": "int"})
	var col: Color = LAMINATE[int(tag * 3.0) % 3]
	# each half: a vanity along its outer wall, two cubicles at the back; urinals in the gents
	vanity(0.15, 3.5, 1.8, -PI * 0.5, 2, "glass_cracked_0" if tag < 0.4 else "")
	vanity(w - 0.15, 3.5, 1.8, PI * 0.5, 2)
	dryer(0.15, 5.0, -PI * 0.5)
	dryer(w - 0.15, 5.0, PI * 0.5)
	stall(0.2, 1.5, 8.85, d - 0.15, true, 0.9 + tag, col)
	stall(1.5, w * 0.5 - 0.08, 8.85, d - 0.15, true, -1.0 if tag > 0.7 else 1.3, col)
	stall(w * 0.5 + 0.08, w - 1.5, 8.85, d - 0.15, true, 0.7, col, lv == 2 and tag > 0.5)
	stall(w - 1.5, w - 0.2, 8.85, d - 0.15, true, 1.2, col)
	for k in 2:
		urinal(w * 0.5 - 0.22, 5.4 + k * 1.0, PI * 0.5, k == 0)
	bin(0.4, 6.6, tag > 0.6)
	bin(w - 0.4, 6.6)
	# lights: two ceiling panels, one of them faulty (a tube on a dying starter) or dead
	var ly: float = L.CEIL - 0.01
	B.panel(lv, p(w * 0.25, d * 0.55, ly), B.POWER_DEAD if tag < 0.5 else B.POWER_ON)
	if tag < 0.75:
		B.panel(lv, p(w * 0.75, d * 0.55, ly), B.POWER_DEAD)
		mb.dyn.add_light({"pos": p(w * 0.75, d * 0.55, ly - 0.06), "kind": "tube", "axis": _F.basis.z, "color": Color(0.86, 0.94, 1.0), "energy": 1.1, "range": 6.0,
			"fault": B.FAULTS[int(tag * 6.0) % 6], "fade": 26.0})
	else:
		B.panel(lv, p(w * 0.75, d * 0.55, ly), B.POWER_ON)
		mb.dyn.add_light({"pos": p(w * 0.75, d * 0.55, ly - 0.1), "kind": "lamp", "color": Color(0.9, 0.95, 1.0), "energy": 0.8, "range": 6.0, "emitter": false, "fade": 26.0})
	if tag >= 0.5:
		mb.dyn.add_light({"pos": p(w * 0.25, d * 0.55, ly - 0.1), "kind": "lamp", "color": Color(0.9, 0.95, 1.0), "energy": 0.8, "range": 6.0, "emitter": false, "fade": 26.0})
	# what was left
	puddle(w * 0.3, 7.0, 2.2, 1.8)
	paper_trail(1.0, 8.6, 0.3 + tag, 1.6)
	fdecal(w * 0.7, 4.5, Vector2(2.0, 2.0), "floor_grime_%d" % (lv % 2), 0.85)
	wdecal(1.0, 8.86, 1.4, PI, Vector2(0.9, 0.45), "v:tag_%02d" % (int(tag * 16.0) % 16), 0.9)
	if lv == 2 or tag > 0.8:
		fdecal(w * 0.75, 7.6, Vector2(1.8, 1.8), "b:12", 0.95)
		fdecal(w * 0.75, 5.6, Vector2(3.0, 0.8), "blood_drag_1", 0.9, PI * 0.5)
		wdecal(w - 0.15, 6.4, 1.3, -PI * 0.5, Vector2(0.8, 0.8), "blood_hands_1", 0.9)


# ------------------------------------------------------------------ Level 3's public restrooms

func big(sh) -> void:
	## The unit beside the Level 3 north-west block (MallShops has built its side walls, floor and ceiling): gents on
	## the left, ladies on the right, each with its own way in from the walk.
	_lv = sh._lv
	_F = sh._xf * Transform3D(Basis(), Vector3(0, sh._y, 0))
	var w: float = sh._w
	var d: float = sh._d
	var h: float = L.CEIL
	var y: float = L.level_y(_lv)
	var mid := w * 0.5
	var ent := [[1.0, 2.4], [w - 2.4, w - 1.0]]
	# the front: painted outside, tiled inside, two entries, the signs
	var xs := [0.0, ent[0][0], ent[0][1], ent[1][0], ent[1][1], w]
	for k in [0, 2, 4]:
		var a: float = xs[k]
		var b: float = xs[k + 1]
		var pa := p(a, 0.05)
		var pb := p(b, 0.05)
		B.wall(_lv, Vector2(pa.x, pa.z), Vector2(pb.x, pb.z), y, h, 0.1, "mall_paint", {"tint": B.CREAM, "paint": 1.0, "layer": "ext"})
		fb((a + b) * 0.5, 0.15, h * 0.5, Vector3(b - a, h, 0.1), "tiles_white", {"tile": 1.2})
	for e in ent:
		fb((float(e[0]) + float(e[1])) * 0.5, 0.1, 2.5 + (h - 2.5) * 0.5, Vector3(float(e[1]) - float(e[0]), h - 2.5, 0.2), "mall_paint", {"tint": B.CREAM, "paint": 1.0, "collide": true, "layer": "ext"})
	fb(mid, -0.03, 3.3, Vector3(w - 0.2, 0.16, 0.06), "mall_satin", {"tint": Color(0.16, 0.18, 0.22), "paint": 1.0, "layer": "ext"})
	S.atlas_quad(p(mid, -0.07, 3.0), -_F.basis.x, Vector3.UP, 2.6, 0.65, B.cell("wc_restrooms"), B.APOC, {"layer": "mid"})
	S.atlas_quad(p(1.7, -0.07, 2.85), -_F.basis.x, Vector3.UP, 1.1, 0.44, B.cell("wc_gents"), B.APOC, {"layer": "mid"})
	S.atlas_quad(p(w - 1.7, -0.07, 2.85), -_F.basis.x, Vector3.UP, 1.1, 0.44, B.cell("wc_ladies"), B.APOC, {"layer": "mid"})
	blade(mid, 3.0)
	wdecal(mid + 2.2, 0.0, 1.5, 0.0, Vector2(0.5, 0.68), "notice_missing")
	wdecal(mid - 1.6, 0.0, 1.45, 0.0, Vector2(0.5, 0.68), "notice_evac")
	walls_tiled(w, d, _lv)
	# the partition between gents and ladies, full height
	var a1 := p(mid, 0.2)
	var b1 := p(mid, d)
	B.wall(_lv, Vector2(a1.x, a1.z), Vector2(b1.x, b1.z), y, h, 0.15, "tiles_white", {"layer": "int", "tile": 1.2})
	# privacy walls inside each entry
	for e2 in ent:
		var cx := (float(e2[0]) + float(e2[1])) * 0.5
		var pa2 := p(cx - 1.3, 1.7)
		var pb2 := p(cx + 1.3, 1.7)
		B.wall(_lv, Vector2(pa2.x, pa2.z), Vector2(pb2.x, pb2.z), y, 2.3, 0.12, "tiles_white", {"layer": "int", "tile": 1.2})
	var col := Color(0.3, 0.4, 0.52)
	# --- gents (x 0 .. mid): vanity along the front, urinals along the partition, four cubicles at the back
	vanity((3.1 + mid - 0.25) * 0.5, 0.21, mid - 0.25 - 3.1, PI, 3, "glass_cracked_1")
	dryer(0.15, 3.2, -PI * 0.5)
	dryer(0.15, 4.4, -PI * 0.5)
	for k in 5:
		urinal(mid - 0.28, 2.6 + k * 0.95, PI * 0.5, true)
	var sw := (mid - 0.3) / 4.0
	for k2 in 4:
		stall(0.2 + k2 * sw, 0.2 + (k2 + 1) * sw, 8.7, d - 0.15, true, [1.1, -1.0, 0.6, 1.4][k2], col)
	bin(0.45, 6.6, true)
	puddle(2.4, 5.2, 3.6, 2.8)
	puddle(1.4, 7.9, 2.0, 1.4)
	paper_trail(1.2, 8.4, 0.2, 2.2)
	fdecal(3.4, 6.2, Vector2(2.2, 2.2), "floor_grime_0", 0.9)
	wdecal(0.15, 6.2, 1.2, PI * 0.5, Vector2(1.6, 0.8), "spray_07", 0.9)
	wdecal(mid - 0.08, 7.6, 1.3, -PI * 0.5, Vector2(0.9, 0.9), "wall_bullets")
	# --- ladies (x mid .. w): vanity along the front, three cubicles along the partition, four at the back
	vanity((mid + 0.25 + w - 3.1) * 0.5, 0.21, w - 3.1 - mid - 0.25, PI, 3, "bloodtext_2")
	dryer(w - 0.15, 3.0, PI * 0.5)
	S.box(Transform3D(_F.basis, p(w - 0.5, 4.6, 0.95)), Vector3(0.9, 0.06, 0.6), "mall_gloss", B.o({"tint": Color(0.93, 0.92, 0.9), "paint": 1.0, "layer": "int"}))
	# three cubicles against the partition, their doors toward the room (built in a frame turned to that wall)
	var side := Transform3D(Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0)), Vector3(mid + 1.6, 0, 0))
	with_frame(side, func() -> void:
		for k3 in 3:
			stall(3.0 + k3 * 1.45, 3.0 + (k3 + 1) * 1.45, 0.0, 1.45, true, [0.8, 1.3, 0.5][k3], col))
	var lw := (w - mid - 0.3) / 4.0
	for k4 in 4:
		var shut := k4 == 3
		stall(mid + 0.1 + k4 * lw, mid + 0.1 + (k4 + 1) * lw, 8.7, d - 0.15, true, 0.0 if shut else [0.9, 1.4, -1.0][k4], col, shut)
	# the shut cubicle: wedged with a broom, sprayed, blood out from under the door
	var sx0 := mid + 0.1 + 3.0 * lw
	fb(sx0 + lw * 0.5, 8.62, 1.25, Vector3(0.03, 1.5, 0.03), "walnut", {}, 0.0)
	S.box(Transform3D(_F.basis * Basis(Vector3(1, 0, 0), 0.75), p(sx0 + lw * 0.5, 8.1, 0.6)), Vector3(0.03, 1.4, 0.03), "walnut", B.o({"layer": "int"}))
	wdecal(sx0 + lw * 0.5, 8.68, 1.35, 0.0, Vector2(lw - 0.2, (lw - 0.2) * 0.5), "spray_12", 0.95)
	fdecal(sx0 + lw * 0.5, 8.3, Vector2(1.8, 1.4), "b:13", 1.0)
	fdecal(sx0 + lw * 0.3, 7.5, Vector2(0.8, 0.8), "b:2", 0.9)
	# people sheltered here: bedding, cans, water, a radio, a lamp that ran down
	for mp in [[mid + 3.5, 5.6, 0.2], [mid + 2.0, 7.4, 1.4]]:
		if not mb.models.spec("old_mattress").is_empty():
			mb.dyn.add_static_prop("old_mattress", Transform3D(_F.basis * Basis(Vector3.UP, float(mp[2])), p(mp[0], mp[1])))
	for k6 in 6:
		var cp := p(mid + 2.2 + (k6 % 3) * 0.3, 6.6 + (k6 / 3) * 0.25)
		mb.dyn.add_prop_spec("can", mb.dyn.seat("can", Transform3D(Basis(Vector3.UP, k6 * 1.3), cp)))
	mb.dyn.add_prop_spec("gallon", mb.dyn.seat("gallon", Transform3D(Basis(), p(w - 0.6, 7.6))))
	mb.dyn.add_prop_spec("boombox", mb.dyn.seat("boombox", Transform3D(Basis(Vector3.UP, 2.0), p(mid + 4.4, 6.9))))
	fdecal(mid + 3.0, 6.4, Vector2(2.6, 2.6), "floor_papers_0", 0.9)
	fdecal(mid + 1.6, 4.4, Vector2(3.0, 0.8), "blood_steps", 0.85, PI * 0.5)
	wdecal(w - 0.15, 6.0, 1.4, -PI * 0.5, Vector2(1.6, 0.6), "v:tally", 0.9)
	# lights: four panels; one tube flickering in each half, the rest dead
	var ly: float = L.CEIL - 0.01
	for q in [[mid * 0.5, 3.0], [mid * 0.5, 7.0], [mid * 1.5, 3.0], [mid * 1.5, 7.0]]:
		B.panel(_lv, p(q[0], q[1], ly), B.POWER_DEAD)
	mb.dyn.add_light({"pos": p(mid * 0.5, 3.0, ly - 0.06), "kind": "tube", "axis": _F.basis.x, "color": Color(0.85, 0.94, 1.0), "energy": 1.4, "range": 7.0,
		"fault": "starter", "fade": 28.0})
	mb.dyn.add_light({"pos": p(mid * 1.5, 7.0, ly - 0.06), "kind": "tube", "axis": _F.basis.x, "color": Color(0.85, 0.94, 1.0), "energy": 1.2, "range": 7.0,
		"fault": "dying", "fade": 28.0})
	mb.dyn.add_light({"pos": p(mid * 1.5, 2.8, ly - 0.1), "kind": "lamp", "color": Color(1.0, 0.86, 0.66), "energy": 0.5, "range": 5.0, "emitter": false,
		"fault": "sag", "fade": 28.0})
	stats.big = true
