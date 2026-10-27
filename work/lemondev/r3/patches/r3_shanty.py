import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from plib import patch

P = 'A:/Python/aetherion-project/game/src/world/shanty.gd'
patch(P, [
# ---- header doc
("""## its doors and windows matter to sound.
""", """## its doors and windows matter to sound.
##
## Spec options added for the r3 map: covered (the front faces a roofed-over lane: its outer faces go on the Interior
## render layer, so neither the sun nor the sky fill lights them), roof_deck (a flat concrete roof with a parapet
## and the usual rooftop life), ladder (a ladder up the front wall to that deck), side_holes (crawl-through holes
## into the neighbour's house at world points), front_gy (ground height in front of the house).
"""),
# ---- state
("""var flights: Array = []
""", """var flights: Array = []
## Ladders built by the last build(): {base (world, on the climbing line at the foot), top_y, n (outward), w}.
var ladders: Array = []
"""),
# ---- options
("""	var overhang := 0.0
	if floors >= 2 and bool(spec.get("can_overhang", true)) and rng.randf() < 0.45:
		overhang = rng.randf_range(0.5, 1.0)
""", """	var covered := bool(spec.get("covered", false))
	var deck := bool(spec.get("roof_deck", false))
	var want_ladder := deck and bool(spec.get("ladder", false))
	var overhang := 0.0
	if floors >= 2 and bool(spec.get("can_overhang", true)) and rng.randf() < 0.45 and not covered and not want_ladder:
		overhang = rng.randf_range(0.5, 1.0)
"""),
# ---- ladder position (after the front door is placed), front window clash, vault windows, side holes
("""	# ---- ground floor walls
	var y0 := 0.0
	var walls0 := {"front": [], "back": [], "left": [], "right": []}
	var front_kind := str(spec.get("front", "door"))
""", """	# A ladder goes up the front wall at the corner away from the door.
	var ladder_x := INF
	if want_ladder and str(spec.get("front", "door")) == "door":
		var lx := (w * 0.5 - 0.42) if front_door_x + 0.42 < 0.0 else (-w * 0.5 + 0.42)
		if absf(lx - (front_door_x + 0.42)) > 1.0:
			ladder_x = lx
	# ---- ground floor walls
	var y0 := 0.0
	var walls0 := {"front": [], "back": [], "left": [], "right": []}
	var front_kind := str(spec.get("front", "door"))
"""),
("""		if w > 3.4 and rng.randf() < 0.75:
			var wx := front_door_x + 0.42 + (1.3 if front_door_x < 0 else -1.3)
			if absf(wx) < w * 0.5 - 0.5:
				walls0.front.append({"type": "window", "x": wx, "w": rng.randf_range(0.8, 1.05), "y": 0.9, "h": rng.randf_range(0.95, 1.1), "win": _win_type()})
	if rng.randf() < 0.35:
		walls0.back.append({"type": "door", "x": rng.randf_range(-0.25, 0.25) * w, "w": 0.75, "y": 0.0, "h": 1.9})
	elif rng.randf() < 0.85:
		walls0.back.append({"type": "window", "x": rng.randf_range(-0.25, 0.25) * w, "w": rng.randf_range(0.8, 1.0), "y": 0.95, "h": rng.randf_range(0.9, 1.05), "win": _win_type()})
	for side in ["left", "right"]:
		if rng.randf() < 0.85:
			var zc := rng.randf_range(-0.3, 0.3) * d
			walls0[side].append({"type": "window", "x": zc, "w": rng.randf_range(0.75, 1.0), "y": 0.9, "h": rng.randf_range(0.95, 1.1), "win": _win_type()})
""", """		if w > 3.4 and rng.randf() < 0.75:
			var wx := front_door_x + 0.42 + (1.3 if front_door_x < 0 else -1.3)
			var fwin := _ground_window(0.0)
			fwin.x = wx
			if absf(wx) < w * 0.5 - 0.5 and absf(wx - ladder_x) > float(fwin.w) * 0.5 + 0.4:
				walls0.front.append(fwin)
	if rng.randf() < 0.35:
		walls0.back.append({"type": "door", "x": rng.randf_range(-0.25, 0.25) * w, "w": 0.75, "y": 0.0, "h": 1.9})
	elif rng.randf() < 0.85:
		walls0.back.append(_ground_window(w * 0.25))
	# Holes knocked through into the next house (the row's builder passes the same world point to both neighbours).
	var holed := {}
	for hp in spec.get("side_holes", []):
		var rel: Vector2 = (hp as Vector2) - Vector2(xf.origin.x, xf.origin.z)
		var lx2 := rel.dot(Vector2(xf.basis.x.x, xf.basis.x.z).normalized())
		var zl := clampf(rel.dot(Vector2(xf.basis.z.x, xf.basis.z.z).normalized()), -d * 0.5 + 0.65, minf(d * 0.5 - 1.75, d * 0.1))
		var hside := "right" if lx2 > 0.0 else "left"
		if (stair and ((stair_side > 0) == (hside == "right")) and zl > d * 0.5 - stair_run - 1.15) or zl < -d * 0.5 + 0.6:
			continue
		walls0[hside].append({"type": "window", "x": zl, "w": 0.86, "y": 0.5, "h": 1.22, "win": "open", "hole": true})
		holed[hside] = true
	for side in ["left", "right"]:
		if rng.randf() < 0.85 and not holed.has(side):
			walls0[side].append(_ground_window(d * 0.3))
"""),
# ---- covered front: ground-floor walls
("""	_walls(xf, w, d, y0, h0, gmat, walls0, painted, paint_col, dirt, bid, outer0, split, z_split, zf, zb)
""", """	_walls(xf, w, d, y0, h0, gmat, walls0, painted, paint_col, dirt, bid, outer0, split, z_split, zf, zb, covered)
"""),
# ---- roof or deck
("""	_roof(xf * Transform3D(Basis(), Vector3(0, 0, roof_off)), w, roof_d, top, dirt, bid, spec)
	# ---- exterior details
	_details(xf, w, d, h0, floors, front_door_x, dirt, gmat, kind)
	out.top = top
""", """	if deck:
		_deck(xf * Transform3D(Basis(), Vector3(0, 0, roof_off)), w, roof_d, top, dirt, bid, spec, ladder_x, style_name)
	else:
		_roof(xf * Transform3D(Basis(), Vector3(0, 0, roof_off)), w, roof_d, top, dirt, bid, spec)
	if ladder_x != INF:
		_ladder(xf, ladder_x, d, top + 0.13, float(spec.get("front_gy", xf.origin.y)), dirt)
	# ---- exterior details
	_details(xf, w, d, h0, floors, front_door_x, dirt, gmat, kind, ladder_x)
	out.top = top + (0.6 if deck else 0.0)
	out.deck = deck
"""),
# ---- _walls signature and covered faces
("""func _walls(xf: Transform3D, w: float, d: float, y: float, h: float, mat: String, openings: Dictionary, painted: bool,
		paint: Color, dirt: float, bid: int, zones: Dictionary, split: bool, z_split: float, zf: int, zb: int) -> void:
""", """func _walls(xf: Transform3D, w: float, d: float, y: float, h: float, mat: String, openings: Dictionary, painted: bool,
		paint: Color, dirt: float, bid: int, zones: Dictionary, split: bool, z_split: float, zf: int, zb: int, covered: bool = false) -> void:
"""),
("""		var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
		var seg_start := -length * 0.5
		var wall_mat := mat
		for hole in holes:
			var a0: float = hole.c - hole.w * 0.5
			var a1: float = hole.c + hole.w * 0.5
			if a0 - seg_start > 0.02:
				_wall_piece(xf, center, along, basis, (seg_start + a0) * 0.5, a0 - seg_start, y, h, 0.0, t, wall_mat, painted, paint, dirt)
			# below sill
			if hole.y > 0.02:
				_wall_piece(xf, center, along, basis, hole.c, hole.w, y, hole.y, 0.0, t, wall_mat, painted, paint, dirt)
			# above lintel
			if hole.y + hole.h < h - 0.02:
				_wall_piece(xf, center, along, basis, hole.c, hole.w, y + hole.y + hole.h, h - hole.y - hole.h, 0.0, t, wall_mat, painted, paint, dirt)
			seg_start = a1
			_opening(xf, center + along * hole.c, along, normal, y, hole, t, dirt, bid, zones.get(side, zf), side, split, z_split, zb)
		if length * 0.5 - seg_start > 0.02:
			_wall_piece(xf, center, along, basis, (seg_start + length * 0.5) * 0.5, length * 0.5 - seg_start, y, h, 0.0, t, wall_mat, painted, paint, dirt)
""", """		var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
		var seg_start := -length * 0.5
		var wall_mat := mat
		var cov := covered and side == "front"
		for hole in holes:
			var a0: float = hole.c - hole.w * 0.5
			var a1: float = hole.c + hole.w * 0.5
			if a0 - seg_start > 0.02:
				_wall_piece(xf, center, along, basis, (seg_start + a0) * 0.5, a0 - seg_start, y, h, 0.0, t, wall_mat, painted, paint, dirt, cov)
			# below sill
			if hole.y > 0.02:
				_wall_piece(xf, center, along, basis, hole.c, hole.w, y, hole.y, 0.0, t, wall_mat, painted, paint, dirt, cov)
			# above lintel
			if hole.y + hole.h < h - 0.02:
				_wall_piece(xf, center, along, basis, hole.c, hole.w, y + hole.y + hole.h, h - hole.y - hole.h, 0.0, t, wall_mat, painted, paint, dirt, cov)
			seg_start = a1
			_opening(xf, center + along * hole.c, along, normal, y, hole, t, dirt, bid, zones.get(side, zf), side, split, z_split, zb)
		if length * 0.5 - seg_start > 0.02:
			_wall_piece(xf, center, along, basis, (seg_start + length * 0.5) * 0.5, length * 0.5 - seg_start, y, h, 0.0, t, wall_mat, painted, paint, dirt, cov)
"""),
("""			var pos := center + along * pc + Vector3.UP * (py + ph * 0.5) + normal * (t * 0.5 + 0.012)
			ctx.sink.box(xf * Transform3D(basis, pos), Vector3(pw, ph, 0.012), pm, {"dirt": dirt, "collide": false, "faces": 32,
				"tint": ctx.mats.PAINTS[rng.randi_range(0, ctx.mats.PAINTS.size() - 1)], "paint": 0.4 if rng.randf() < 0.3 else 0.0})
		# Corner posts
		ctx.sink.box(xf * Transform3D(Basis(), center - along * length * 0.5 + Vector3.UP * (y + h * 0.5) + normal * 0.02), Vector3(0.09, h, 0.09),
			"timber" if t < 0.1 else mat, {"dirt": dirt, "collide": false})
""", """			var pos := center + along * pc + Vector3.UP * (py + ph * 0.5) + normal * (t * 0.5 + 0.012)
			ctx.sink.box(xf * Transform3D(basis, pos), Vector3(pw, ph, 0.012), pm, {"dirt": dirt, "collide": false, "faces": 32,
				"tint": ctx.mats.PAINTS[rng.randi_range(0, ctx.mats.PAINTS.size() - 1)], "paint": 0.4 if rng.randf() < 0.3 else 0.0,
				"layer": "int" if cov else "ext"})
		# Corner posts
		ctx.sink.box(xf * Transform3D(Basis(), center - along * length * 0.5 + Vector3.UP * (y + h * 0.5) + normal * 0.02), Vector3(0.09, h, 0.09),
			"timber" if t < 0.1 else mat, {"dirt": dirt, "collide": false, "layer": "int" if cov else "ext"})
"""),
("""func _wall_piece(xf: Transform3D, center: Vector3, along: Vector3, basis: Basis, c: float, length: float, y: float, h: float,
		_x: float, t: float, mat: String, painted: bool, paint: Color, dirt: float) -> void:
	var pos := center + along * c + Vector3.UP * (y + h * 0.5)
	var opt := {"dirt": dirt, "base_y": xf.origin.y, "occlude": t >= 0.1 and h > 1.5, "faces": 55, "inner_faces": 16}
""", """func _wall_piece(xf: Transform3D, center: Vector3, along: Vector3, basis: Basis, c: float, length: float, y: float, h: float,
		_x: float, t: float, mat: String, painted: bool, paint: Color, dirt: float, covered: bool = false) -> void:
	var pos := center + along * c + Vector3.UP * (y + h * 0.5)
	# A wall under a roofed-over lane is lit like an inside wall: both faces on the Interior layer.
	var opt := {"dirt": dirt, "base_y": xf.origin.y, "occlude": t >= 0.1 and h > 1.5, "faces": 55, "inner_faces": 16 | 32 if covered else 16}
"""),
# ---- vault windows: a sill board on open windows
("""		"window":
			var wt := str(o.get("win", "glass"))
""", """		"window":
			var wt := str(o.get("win", "glass"))
			if wt == "open":
				# Glassless: a worn sill board to vault over, and (through a party wall) a lining across the gap
				# between the two houses so the sill is one surface.
				var depth := t + (0.34 if o.get("hole", false) else 0.08)
				ctx.sink.box(xf * Transform3D(basis, pos + Vector3.UP * (y + hole.y - 0.025) + normal * (depth * 0.5 - t * 0.5)),
					Vector3(fw + 0.08, 0.05, depth), "timber", {"dirt": dirt})
"""),
# ---- ground window helper
("""func _win_type() -> String:
""", """func _ground_window(span: float) -> Dictionary:
	## A ground-floor window: a third are glassless and sized to vault through (sill at hip height, tall, wide).
	if rng.randf() < 0.36:
		return {"type": "window", "x": rng.randf_range(-1.0, 1.0) * span, "w": rng.randf_range(0.95, 1.2), "y": rng.randf_range(0.78, 0.9),
			"h": rng.randf_range(1.1, 1.24), "win": "open", "vault": true}
	return {"type": "window", "x": rng.randf_range(-1.0, 1.0) * span, "w": rng.randf_range(0.8, 1.0), "y": 0.9, "h": rng.randf_range(0.95, 1.1), "win": _win_type()}


func _win_type() -> String:
"""),
# ---- details: keep the ladder clear
("""func _details(xf: Transform3D, w: float, d: float, h0: float, floors: int, door_x: float, dirt: float, gmat: String, kind: String) -> void:
	# Awning over the door.
	if rng.randf() < 0.55:
		var aw := rng.randf_range(1.2, 2.2)
		var ad := rng.randf_range(0.6, 1.0)
		var ax := clampf(door_x + 0.42, -w * 0.5 + aw * 0.5, w * 0.5 - aw * 0.5)
""", """func _details(xf: Transform3D, w: float, d: float, h0: float, floors: int, door_x: float, dirt: float, gmat: String, kind: String, ladder_x: float = INF) -> void:
	# Awning over the door (kept off the ladder).
	if rng.randf() < 0.55:
		var aw := rng.randf_range(1.2, 2.2)
		var ad := rng.randf_range(0.6, 1.0)
		if ladder_x != INF:
			aw = minf(aw, maxf(absf(ladder_x - (door_x + 0.42)) * 2.0 - 1.0, 0.0))
		var ax := clampf(door_x + 0.42, -w * 0.5 + aw * 0.5, w * 0.5 - aw * 0.5)
"""),
("""	# Electric meter box and a sagging service cable.
	if rng.randf() < 0.7:
""", """	# Electric meter box and a sagging service cable.
	if rng.randf() < 0.7 and ladder_x == INF:
"""),
("""	# Water drum / pails by the door.
	if rng.randf() < 0.5:
""", """	# Water drum / pails by the door.
	if rng.randf() < 0.5 and ladder_x == INF:
"""),
# ---- deck and ladder builders
("""func _roof_sheets(""", """func _deck(xf: Transform3D, w: float, d: float, top: float, dirt: float, bid: int, spec: Dictionary, ladder_x: float, style: String) -> void:
	## A flat concrete roof: a slab with a low hollow-block parapet (a gap where the ladder arrives), and what people
	## keep up there - a water tank on a stand, washing, potted plants, a chair, an antenna, rebar left for the next
	## storey, sometimes something worth taking.
	var slab_t := 0.14
	var y := top + slab_t
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, top + slab_t * 0.5, 0)), Vector3(w + 0.12, slab_t, d + 0.12), "cement",
		{"dirt": dirt, "inner_faces": 8, "phys": "concrete"})
	var pm: String = _pick(["chb", "chb2", "plaster_damaged", "plaster"])
	var ph := 0.55
	var skip_back := rng.randf() < 0.25
	for side in ["front", "back", "left", "right"]:
		if side == "back" and skip_back:
			continue
		var along_x := side in ["front", "back"]
		var length := (w + 0.12) if along_x else (d - 0.12)
		var off := (-(d + 0.12) * 0.5 + 0.06) if side == "front" else ((d + 0.12) * 0.5 - 0.06 if side == "back" else 0.0)
		var offx := (-(w + 0.12) * 0.5 + 0.06) if side == "left" else ((w + 0.12) * 0.5 - 0.06 if side == "right" else 0.0)
		var gaps := []
		if side == "front" and ladder_x != INF:
			gaps.append([ladder_x - 0.42, ladder_x + 0.42])
		var a := -length * 0.5
		for gp in gaps + [[length * 0.5, length * 0.5]]:
			var b := float(gp[0])
			if b - a > 0.05:
				var mid := (a + b) * 0.5
				var c := Vector3(mid, y + ph * 0.5, off) if along_x else Vector3(offx, y + ph * 0.5, mid)
				var sz := Vector3(b - a, ph, 0.12) if along_x else Vector3(0.12, ph, b - a)
				ctx.sink.box(xf * Transform3D(Basis(), c), sz, pm, {"dirt": dirt, "phys": "hollow_block"})
			a = float(gp[1])
	# Water tank on a timber stand in a back corner.
	var cx := (w * 0.5 - 0.65) * (1.0 if rng.randf() < 0.5 else -1.0)
	var cz := d * 0.5 - 0.65
	if absf(cx - ladder_x) < 1.2:
		cx = -cx
	for lxz in [Vector2(-0.35, -0.35), Vector2(0.35, -0.35), Vector2(-0.35, 0.35), Vector2(0.35, 0.35)]:
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(cx + lxz.x, y + 0.45, cz + lxz.y)), Vector3(0.08, 0.9, 0.08), "timber", {"dirt": dirt})
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(cx, y + 0.93, cz)), Vector3(0.9, 0.06, 0.9), "planks", {"dirt": dirt})
	ctx.dyn.add_prop_spec("drum_blue", xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(cx, y + 0.96, cz)))
	# Washing on a line across the deck.
	if rng.randf() < 0.6:
		var lz := rng.randf_range(-d * 0.25, d * 0.15)
		var hw := w * 0.5 - 0.25
		for sx in [-1.0, 1.0]:
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(sx * hw, y + 0.85, lz)), Vector3(0.05, 1.7, 0.05), "timber", {"dirt": dirt, "collide": false})
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, y + 1.66, lz)), Vector3(hw * 2.0, 0.012, 0.012), "wire", {"collide": false, "layer": "mid"})
		var n := int(hw * 2.0 / 0.5)
		for i in n:
			if rng.randf() < 0.35:
				continue
			var cw := rng.randf_range(0.3, 0.55)
			var chh := rng.randf_range(0.35, 0.75)
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(-hw + (i + 0.5) * hw * 2.0 / n, y + 1.66 - chh * 0.5, lz)), Vector3(cw, chh, 0.01), "cloth",
				{"collide": false, "faces": 16 | 32, "tint": ctx.mats.PAINTS[rng.randi_range(0, ctx.mats.PAINTS.size() - 1)], "paint": 1.0, "dirt": 0.15, "layer": "mid"})
	# Plants in old pails and paint cans along the parapet.
	for i in rng.randi_range(1, 4):
		var px := rng.randf_range(-w * 0.5 + 0.35, w * 0.5 - 0.35)
		if absf(px - ladder_x) < 0.7:
			continue
		var pz := -d * 0.5 + 0.35 if rng.randf() < 0.5 else rng.randf_range(-d * 0.3, d * 0.3)
		ctx.sink.cylinder(xf * Vector3(px, y, pz), Vector3.UP, 0.28, 0.16, _pick(["metal_paint", "metal_rust", "tarp"]), {"sides": 8, "collide": false,
			"tint": ctx.mats.PAINTS[rng.randi_range(0, ctx.mats.PAINTS.size() - 1)], "paint": 0.7})
		ctx.dyn.add_static_prop(_pick(["fern", "weeds", "grass_clump", "fern"]), xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(px, y + 0.26, pz)))
	if rng.randf() < 0.5:
		ctx.dyn.add_prop_spec("monobloc", xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(-w * 0.25, w * 0.25), y, rng.randf_range(-d * 0.2, d * 0.2))))
	# A TV antenna on a pipe, guyed with wire.
	if rng.randf() < 0.55:
		var ax := -cx * 0.8
		var base := xf * Vector3(ax, y, d * 0.5 - 0.3)
		ctx.sink.cylinder(base, Vector3.UP, 2.6, 0.025, "metal_rust", {"sides": 6, "collide": false})
		for k in 4:
			var bl := 0.9 - k * 0.18
			ctx.sink.box(Transform3D(xf.basis, base + Vector3.UP * (2.0 + k * 0.17)), Vector3(bl, 0.015, 0.015), "metal_rust", {"collide": false, "layer": "mid"})
	# Rebar left sticking out of the corner columns for the storey that was never built.
	if style in ["chb", "concrete"] and rng.randf() < 0.55:
		for cxz in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var cp := Vector3(cxz.x * (w * 0.5 - 0.1), y, cxz.y * (d * 0.5 - 0.1))
			for k in 4:
				var o := Vector3((k % 2) * 0.08 - 0.04, 0, (k / 2) * 0.08 - 0.04)
				ctx.sink.box(xf * Transform3D(Basis(Vector3(1, 0, 0.3).normalized(), rng.randf_range(-0.12, 0.12)), cp + o + Vector3.UP * 0.4), Vector3(0.014, 0.8, 0.014), "metal_rust", {"collide": false, "layer": "mid"})
	# A stash: people keep things on the roof.
	if rng.randf() < 0.45:
		ctx.dyn.add_loot_spot(xf * Vector3(rng.randf_range(-w * 0.3, w * 0.3), y + 0.02, rng.randf_range(-d * 0.3, d * 0.3)), "floor_street", bid)


func _ladder(xf: Transform3D, lx: float, d: float, top_y_local: float, ground_y: float, dirt: float) -> void:
	## A ladder up the front wall from the lane to the roof deck: two rails and rungs every 30 cm, standing just off
	## the wall, its rails reaching a metre above the deck to step off by. Registered for the climbing movement.
	var steel := rng.randf() < 0.45
	var mat := "metal_rust" if steel else _pick(["timber", "bamboo"])
	var foot_local := ground_y - xf.origin.y
	var top := top_y_local + 0.9
	var hgt := top - foot_local
	var zr := -d * 0.5 - 0.09
	for sx in [-0.22, 0.22]:
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(lx + sx, foot_local + hgt * 0.5, zr)), Vector3(0.05, hgt, 0.06), mat, {"dirt": dirt, "collide": false})
	var y := foot_local + 0.3
	while y < top - 0.1:
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(lx, y, zr)), Vector3(0.44, 0.035, 0.035), mat, {"dirt": dirt, "collide": false})
		y += 0.3
	# Brackets into the wall at the deck edge.
	for sx in [-0.22, 0.22]:
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(lx + sx, top_y_local - 0.05, -d * 0.5 - 0.045)), Vector3(0.04, 0.04, 0.09), "metal_rust", {"collide": false})
	var outward := (xf.basis * Vector3(0, 0, -1)).normalized()
	var base: Vector3 = xf * Vector3(lx, foot_local, -d * 0.5 - 0.42)
	ladders.append({"base": base, "top_y": xf.origin.y + top_y_local, "n": outward, "w": 0.5})


func _roof_sheets("""),
])
