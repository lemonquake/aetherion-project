extends "res://src/world/building_kit.gd"
## Generates one informal house ("barong-barong"): patchwork walls split around real door and window openings,
## a partition and comfort room, a steep stair to an upper floor that often overhangs the alley, a corrugated roof
## weighed down with tyres, optional stilts over water or a slope, and the acoustic rooms and portals that make
## its doors and windows matter to sound.
##
## Spec options added for the r3 map: covered (the front faces a roofed-over lane: its outer faces go on the Interior
## render layer, so neither the sun nor the sky fill lights them), roof_deck (a flat concrete roof with a parapet
## and the usual rooftop life), ladder (a ladder up the front wall to that deck), side_holes (crawl-through holes
## into the neighbour's house at world points), front_gy (ground height in front of the house).
##
## Local frame: origin at the footprint centre on the ground-floor level, -Z is the front (facing the alley),
## +X is the right side when looking out of the front door.
##
## The reusable pieces (walls with openings, partitions, the comfort room, stairs, upper floors, roof infill, ladders,
## acoustic AABBs) live in building_kit.gd (r7); this file keeps what is particular to the informal house.

const STYLES := {
	"chb": {"g": ["chb", "plaster", "plaster_damaged", "plaster_cracked"], "u": ["plywood", "planks", "siding", "yero_rust"], "paint": 0.6},
	"wood": {"g": ["planks", "planks_paint", "siding", "planks_peel", "plywood"], "u": ["planks", "plywood", "planks_blue", "yero_rust"], "paint": 0.45},
	"yero": {"g": ["yero_rust", "yero_worn", "yero_paint", "plywood"], "u": ["yero_rust", "yero_worn", "plywood"], "paint": 0.3},
	"bamboo": {"g": ["bamboo", "bamboo2", "plywood"], "u": ["bamboo", "plywood", "yero_rust"], "paint": 0.0},
	"concrete": {"g": ["plaster", "plaster_white", "plaster_peel", "plaster_blue", "plaster_yellow"], "u": ["plaster", "plaster_white", "plaster_peel", "chb"], "paint": 0.75},
	"patch": {"g": ["plywood", "yero_rust", "planks", "chb2", "osb"], "u": ["yero_rust", "plywood", "planks_green", "tarp"], "paint": 0.25},
}
const ROOF_MATS := ["yero_rust", "yero_rust", "yero", "yero_worn", "yero_paint", "asbestos"]



func build(spec: Dictionary) -> Dictionary:
	rng.seed = int(spec.seed)
	var bid := int(spec.id)
	var xf: Transform3D = spec.xf
	var w := float(spec.w)
	var d := float(spec.d)
	var floors := int(spec.get("floors", 1))
	var style_name := str(spec.get("style", "wood"))
	var style: Dictionary = STYLES.get(style_name, STYLES.wood)
	var kind := str(spec.get("kind", "house"))
	var stilts := bool(spec.get("stilts", false))
	var ground_y := float(spec.get("ground_y", 0.0))
	var base_y := xf.origin.y
	var paint_col: Color = ctx.mats.PAINTS[rng.randi_range(0, ctx.mats.PAINTS.size() - 1)]
	var painted := rng.randf() < float(style.paint)
	var gmat: String = style.g[rng.randi_range(0, style.g.size() - 1)]
	var umat: String = style.u[rng.randi_range(0, style.u.size() - 1)]
	var dirt := rng.randf_range(0.45, 1.0)
	var h0 := rng.randf_range(2.35, 2.6)
	var h1 := rng.randf_range(2.15, 2.4)
	var covered := bool(spec.get("covered", false))
	var deck := bool(spec.get("roof_deck", false))
	var want_ladder := deck and bool(spec.get("ladder", false))
	var overhang := 0.0
	if floors >= 2 and bool(spec.get("can_overhang", true)) and rng.randf() < 0.45 and not covered and not want_ladder:
		overhang = rng.randf_range(0.5, 1.0)
		# Over a narrow lane the house opposite may lean out too: together they must leave the lane open above.
		overhang = minf(overhang, float(spec.get("front_lane_w", 9.0)) * 0.5 - 0.2)
		if overhang < 0.3:
			overhang = 0.0
	var out := {"id": bid, "rooms": [], "doors": [], "top": 0.0}
	var floor_t := 0.1
	# ---- foundation / stilts
	if stilts:
		_stilts(xf, w, d, base_y, ground_y, dirt)
		_floor_deck(xf, w, d, 0.0, "floor_planks", bid)
	else:
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, -0.06, 0)), Vector3(w + 0.06, 0.16, d + 0.06),
			"cement" if style_name in ["chb", "concrete"] else _pick(["cement", "floor_planks", "concrete_floor"]),
			{"dirt": dirt, "layer": "ext", "what": "floor_slab"})
	# ---- plan
	var cr := w * d > 13.0 and rng.randf() < 0.75 and kind == "house"
	var split := d >= 5.4 and rng.randf() < 0.8
	var z_split := rng.randf_range(-0.1, 0.4) * d if split else 999.0
	# The comfort room in a back corner: 1.2 x 1.4 m with a door wide enough to walk through.
	var crw := 1.2
	var crd := 1.4
	if split:
		# Both rooms deep enough to step into and turn round in (a back room under a metre deep was a cupboard the back
		# door opened on to), and a metre clear in front of the comfort room's door before the partition.
		z_split = clampf(z_split, -d * 0.5 + 1.9, d * 0.5 - 1.9)
		if cr:
			z_split = minf(z_split, d * 0.5 - crd - 1.2)
	var stair := floors >= 2
	var stair_side := 1.0 if rng.randf() < 0.5 else -1.0
	var stair_w := 0.78
	var stair_run := h0 * 1.05
	# A shallow house gets a steeper flight (up to about 47 degrees, still walkable) so there is room to step on to
	# it inside the front wall; one too shallow even for that keeps to one storey.
	if stair and d < stair_run + 0.9:
		stair_run = maxf(h0 * 0.93, d - 0.9)
		if d < stair_run + 0.8:
			floors = 1
			stair = false
	# A three-storey building climbs on to its top floor by a second flight along the other side wall.
	var stair2 := floors >= 3
	var run2 := h1 * 1.05
	var stair2_box := Rect2()
	if stair2:
		stair2_box = Rect2(Vector2((w * 0.5 - stair_w) if stair_side < 0 else -w * 0.5, d * 0.5 - run2 - 1.0), Vector2(stair_w, run2 + 1.0))
	var front_door_x := rng.randf_range(-w * 0.5 + 0.6, w * 0.5 - 0.6 - 0.8)
	if stair and stair_side > 0 and front_door_x + 0.8 > w * 0.5 - stair_w - 0.1:
		front_door_x = -w * 0.5 + 0.5
	elif stair and stair_side < 0 and front_door_x < -w * 0.5 + stair_w + 0.1:
		front_door_x = w * 0.5 - 1.4
	# A ladder goes up the front wall at the corner away from the door.
	var ladder_x := INF
	if want_ladder and str(spec.get("front", "door")) == "door":
		var lx := (w * 0.5 - 0.42) if front_door_x + 0.42 < 0.0 else (-w * 0.5 + 0.42)
		if absf(lx - (front_door_x + 0.42)) > 1.0:
			ladder_x = lx
	# ---- ground floor walls
	var y0 := 0.0
	var walls0 := {"front": [], "back": [], "left": [], "right": []}
	var front_kind := str(spec.get("front", "door"))
	if front_kind == "store":
		var sw_x := rng.randf_range(-0.2, 0.3) * w
		var sw_w := minf(w * 0.5, 2.0)
		front_door_x = -w * 0.5 + 0.45 if rng.randf() < 0.5 else w * 0.5 - 1.3
		# The barred shop window goes in the wall beside the door, never across it (it used to overlap the doorway: a
		# sill wall and window bars filled the door).
		var dc := front_door_x + 0.42
		var lo := (dc + 0.41 + 0.25) if dc < 0.0 else (-w * 0.5 + 0.35)
		var hi := (w * 0.5 - 0.35) if dc < 0.0 else (dc - 0.41 - 0.25)
		sw_w = minf(sw_w, hi - lo)
		if sw_w >= 0.6:
			walls0.front.append({"type": "window", "x": clampf(sw_x, lo + sw_w * 0.5, hi - sw_w * 0.5), "w": sw_w, "y": 0.9, "h": 1.0, "win": "store"})
		walls0.front.append({"type": "door", "x": dc, "w": 0.82, "y": 0.0, "h": 1.95})
	elif front_kind == "open":
		walls0.front.append({"type": "opening", "x": 0.0, "w": w - 0.5, "y": 0.0, "h": h0 - 0.3})
	else:
		walls0.front.append({"type": "door", "x": front_door_x + 0.42, "w": 0.82, "y": 0.0, "h": 1.95})
		if w > 3.4 and rng.randf() < 0.75:
			var wx := front_door_x + 0.42 + (1.3 if front_door_x < 0 else -1.3)
			var fwin := _ground_window(0.0)
			fwin.x = wx
			if absf(wx) < w * 0.5 - 0.5 and absf(wx - ladder_x) > float(fwin.w) * 0.5 + 0.4:
				walls0.front.append(fwin)
	# A back door only where there is somewhere to go (spec.back_blocked: the row behind stands against this back
	# wall), clear of the comfort room in one back corner and of the stair's top along a side wall.
	var bx_lo := -w * 0.5 + 0.5
	var bx_hi := w * 0.5 - 0.5
	if cr:
		if stair_side > 0:
			bx_lo = maxf(bx_lo, -w * 0.5 + crw + 0.5)
		else:
			bx_hi = minf(bx_hi, w * 0.5 - crw - 0.5)
	if stair:
		if stair_side > 0:
			bx_hi = minf(bx_hi, w * 0.5 - stair_w - 0.5)
		else:
			bx_lo = maxf(bx_lo, -w * 0.5 + stair_w + 0.5)
	var back_blocked := bool(spec.get("back_blocked", false))
	if rng.randf() < 0.35 and not back_blocked and bx_hi >= bx_lo:
		walls0.back.append({"type": "door", "x": lerpf(bx_lo, bx_hi, rng.randf()), "w": 0.75, "y": 0.0, "h": 1.9})
	elif rng.randf() < 0.85:
		var bwin := _ground_window(w * 0.25)
		if back_blocked and bwin.get("vault", false):
			# Nobody vaults out into the wall of the house behind.
			bwin = {"type": "window", "x": bwin.x, "w": 0.9, "y": 0.9, "h": 1.0, "win": "bars"}
		walls0.back.append(bwin)
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
	var room_front := {"x0": -w * 0.5, "x1": w * 0.5, "z0": -d * 0.5, "z1": minf(z_split, d * 0.5)}
	var zones0 := []
	var zf: int = ctx.acoustics.add_zone(_aabb(xf, room_front, base_y + y0, h0), bid, 0, "small" if w * d < 14 else "medium", "wood" if stilts else "concrete")
	zones0.append(zf)
	var zb := -1
	if split:
		var room_back := {"x0": -w * 0.5, "x1": w * 0.5, "z0": z_split, "z1": d * 0.5}
		zb = ctx.acoustics.add_zone(_aabb(xf, room_back, base_y + y0, h0), bid, 0, "small", "wood" if stilts else "concrete")
		zones0.append(zb)
	var outer0 := {"front": zf, "back": zb if split else zf, "left": zf, "right": zf}
	_walls(xf, w, d, y0, h0, gmat, walls0, painted, paint_col, dirt, bid, outer0, split, z_split, zf, zb, covered)
	# Partition between front and back rooms
	if split:
		var px := rng.randf_range(-0.25, 0.15) * w
		if stair:
			px = clampf(px, -w * 0.5 + 0.5 - (0.0 if stair_side < 0 else 0.0), w * 0.5 - stair_w - 0.9) if stair_side > 0 else clampf(px, -w * 0.5 + stair_w + 0.6, w * 0.5 - 0.9)
		var part_mat: String = _pick(["plywood", "planks", "bamboo", gmat])
		var open_kind: String = _pick(["curtain", "curtain", "door", "opening"])
		_partition_x(xf, w, z_split, y0, h0, px, 0.8, part_mat, open_kind, dirt, bid, zf, zb, stair, stair_side, stair_w,
			z_split > d * 0.5 - stair_run - 0.8)
	# Comfort room in a back corner
	var cr_rect := Rect2()
	if cr:
		var cx := (-w * 0.5 + crw * 0.5) if stair_side > 0 else (w * 0.5 - crw * 0.5)
		cr_rect = Rect2(Vector2(cx - crw * 0.5 - 0.05, d * 0.5 - crd - 0.05), Vector2(crw + 0.1, crd + 0.1))
		var cz := d * 0.5 - crd * 0.5
		var crz: int = ctx.acoustics.add_zone(_aabb(xf, {"x0": cx - crw * 0.5, "x1": cx + crw * 0.5, "z0": cz - crd * 0.5, "z1": cz + crd * 0.5}, base_y, 2.2), bid, 0, "small", "concrete")
		_comfort_room(xf, cx, cz, crw, crd, y0, minf(h0, 2.2), dirt, bid, zb if split else zf, crz)
		out.rooms.append({"type": "cr", "xf": xf * Transform3D(Basis(), Vector3(cx, y0, cz)), "size": Vector2(crw - 0.15, crd - 0.15), "h": 2.1, "bid": bid, "zone": crz})
	# Rooms for dressing
	var stair_box := Rect2()
	if stair:
		stair_box = Rect2(Vector2((w * 0.5 - stair_w) if stair_side > 0 else -w * 0.5, d * 0.5 - stair_run - 1.0), Vector2(stair_w, stair_run + 1.0))
	var t_front := "store" if front_kind == "store" else ("workshop" if front_kind == "open" else "sala")
	out.rooms.append({"type": t_front, "xf": xf * Transform3D(Basis(), Vector3(0, y0, (room_front.z0 + room_front.z1) * 0.5)),
		"size": Vector2(w - 0.3, room_front.z1 - room_front.z0 - 0.3), "h": h0, "bid": bid, "zone": zf, "avoid": stair_box,
		"door_x": front_door_x + 0.42, "local_z": (room_front.z0 + room_front.z1) * 0.5, "avoid3": cr_rect if not split else Rect2()})
	if split:
		out.rooms.append({"type": "kitchen" if floors > 1 or rng.randf() < 0.5 else "bed", "xf": xf * Transform3D(Basis(), Vector3(0, y0, (z_split + d * 0.5) * 0.5)),
			"size": Vector2(w - 0.3, d * 0.5 - z_split - 0.3), "h": h0, "bid": bid, "zone": zb, "avoid": stair_box, "cr": cr,
			"local_z": (z_split + d * 0.5) * 0.5, "avoid3": cr_rect})
	# ---- stair
	var top := h0
	var upper_zone := -1
	if stair:
		var sx := (w * 0.5 - stair_w * 0.5 - 0.02) * stair_side
		_stair(xf, sx, d * 0.5 - 0.15, stair_w, stair_run, h0, y0, dirt)
	# ---- upper floors
	var prev_zone := zb if split and stair else zf
	for f in range(1, floors):
		var fy := h0 + (f - 1) * h1
		var fw := w
		var fd := d + overhang
		var fz_off := -overhang * 0.5
		var fxf := xf * Transform3D(Basis(), Vector3(0, 0, fz_off))
		var floor_hole := Rect2()
		var hole_side := 0.0     # the side wall the flight up to this floor runs along
		var hole_run := 0.0
		if f == 1 and stair:
			hole_side = stair_side
			hole_run = stair_run
		elif f == 2 and stair2:
			hole_side = -stair_side
			hole_run = run2
		if hole_side != 0.0:
			# The opening runs 0.6 m past the foot of the flight: on a low storey the floor's edge over the first
			# treads caught the climber's head (seen on second flights in three-storey houses).
			floor_hole = Rect2(Vector2((w * 0.5 - stair_w - 0.05) if hole_side > 0 else -w * 0.5, d * 0.5 - hole_run - 0.6 - fz_off), Vector2(stair_w + 0.05, hole_run + 0.65))
		_upper_floor(fxf, fw, fd, fy, floor_hole, dirt)
		if f == 1 and stair2:
			_stair(xf, (w * 0.5 - stair_w * 0.5 - 0.02) * -stair_side, d * 0.5 - 0.15, stair_w, run2, h1, fy, dirt)
		if overhang > 0.0 and f == 1:
			# Beams carry the overhang over the alley.
			for bx in [-w * 0.5 + 0.1, 0.0, w * 0.5 - 0.1]:
				ctx.sink.box(xf * Transform3D(Basis(), Vector3(bx, fy - 0.12, -d * 0.5 - overhang * 0.5 + 0.1)), Vector3(0.08, 0.14, overhang + 0.4), "timber", {"dirt": dirt, "what": "overhang_beam"})
		var walls1 := {"front": [], "back": [], "left": [], "right": []}
		walls1.front.append({"type": "window", "x": rng.randf_range(-0.25, 0.25) * fw, "w": rng.randf_range(0.8, 1.2), "y": 0.9, "h": rng.randf_range(0.95, 1.1), "win": _win_type()})
		if rng.randf() < 0.75:
			walls1.left.append({"type": "window", "x": rng.randf_range(-0.2, 0.2) * fd, "w": rng.randf_range(0.75, 0.95), "y": 0.9, "h": rng.randf_range(0.9, 1.05), "win": _win_type()})
		if rng.randf() < 0.75:
			walls1.right.append({"type": "window", "x": rng.randf_range(-0.2, 0.2) * fd, "w": rng.randf_range(0.75, 0.95), "y": 0.9, "h": rng.randf_range(0.9, 1.05), "win": _win_type()})
		var uz: int = ctx.acoustics.add_zone(_aabb(fxf, {"x0": -fw * 0.5, "x1": fw * 0.5, "z0": -fd * 0.5, "z1": fd * 0.5}, base_y + fy, h1), bid, f, "small", "wood")
		var outer1 := {"front": uz, "back": uz, "left": uz, "right": uz}
		var umat_f: String = umat if rng.randf() < 0.8 else _pick(["yero_rust", "plywood"])
		_walls(fxf, fw, fd, fy, h1, umat_f, walls1, painted and rng.randf() < 0.7, paint_col, dirt, bid, outer1, false, 999.0, uz, -1)
		if hole_side != 0.0:
			var sp := xf * Vector3((w * 0.5 - stair_w * 0.5) * hole_side, fy, d * 0.5 - hole_run * 0.5)
			ctx.acoustics.add_portal(prev_zone, uz, sp, "stair", 1.0)
			# Railing across the low end of the hole and down its open side, stopping a metre short of the top step
			# so the flight lets out sideways on to the floor.
			var rx := (w * 0.5 - stair_w - 0.05) * hole_side
			var z_lo := d * 0.5 - hole_run - 0.6
			var rail_len := hole_run - 0.45
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(rx, fy + 0.9, z_lo + rail_len * 0.5)), Vector3(0.05, 0.05, rail_len), "timber", {"dirt": dirt, "layer": "int"})
			for k in 3:
				ctx.sink.box(xf * Transform3D(Basis(), Vector3(rx, fy + 0.45, z_lo + 0.03 + (rail_len - 0.06) * k / 2.0)), Vector3(0.05, 0.9, 0.05), "timber", {"dirt": dirt, "layer": "int"})
			var cx := (w * 0.5 - (stair_w + 0.05) * 0.5) * hole_side
			for ry in [0.45, 0.9]:
				ctx.sink.box(xf * Transform3D(Basis(), Vector3(cx, fy + ry, z_lo)), Vector3(stair_w + 0.05, 0.05, 0.05), "timber", {"dirt": dirt, "layer": "int"})
		else:
			ctx.acoustics.add_portal(prev_zone, uz, fxf * Vector3(0, fy, 0), "floor_gap", 1.0)
		# Furniture keeps off the hole into this floor and off the flight up from it (rects in house coordinates, like
		# the ground floor's: the dresser subtracts local_z).
		var hole_xf := Rect2(floor_hole.position + Vector2(0, fz_off), floor_hole.size) if hole_side != 0.0 else Rect2()
		out.rooms.append({"type": "bed", "xf": fxf * Transform3D(Basis(), Vector3(0, fy, 0)), "size": Vector2(fw - 0.3, fd - 0.3), "h": h1, "bid": bid, "zone": uz,
			"avoid": hole_xf, "avoid2": stair2_box if f == 1 else Rect2(), "local_z": fz_off})
		prev_zone = uz
		upper_zone = uz
		top = fy + h1
	# ---- roof
	var roof_d := d + (overhang if floors > 1 else 0.0)
	var roof_off := -(overhang * 0.5) if floors > 1 else 0.0
	if deck:
		_deck(xf * Transform3D(Basis(), Vector3(0, 0, roof_off)), w, roof_d, top, dirt, bid, spec, ladder_x, style_name)
	else:
		_roof(xf * Transform3D(Basis(), Vector3(0, 0, roof_off)), w, roof_d, top, dirt, bid, spec)
	if ladder_x != INF:
		_ladder(xf, ladder_x, d, top + 0.13, float(spec.get("front_gy", xf.origin.y)), dirt)
	# ---- exterior details
	var fgy := float(spec.get("front_gy", xf.origin.y))
	_details(xf, w, d, h0, floors, front_door_x, dirt, gmat, kind, ladder_x, (fgy - xf.origin.y) if is_finite(fgy) else NAN,
		float(spec.get("front_lane_w", 9.0)), stilts)
	out.top = top + (0.6 if deck else 0.0)
	out.deck = deck
	# Ground-floor front openings and the ladder, so wall decals keep off them.
	var fo := []
	for o in walls0.front:
		fo.append(Vector4(float(o.x), float(o.w), float(o.y), float(o.h)))
	if ladder_x != INF:
		fo.append(Vector4(ladder_x, 0.9, 0.0, 9.0))
	out.front_open = fo
	out.h0 = h0
	out.zone_front = zf
	return out


func _ground_window(span: float) -> Dictionary:
	## A ground-floor window: a third are glassless and sized to vault through (sill at hip height, tall, wide).
	if rng.randf() < 0.36:
		return {"type": "window", "x": rng.randf_range(-1.0, 1.0) * span, "w": rng.randf_range(0.95, 1.2), "y": rng.randf_range(0.78, 0.9),
			"h": rng.randf_range(1.1, 1.24), "win": "open", "vault": true}
	return {"type": "window", "x": rng.randf_range(-1.0, 1.0) * span, "w": rng.randf_range(0.8, 1.0), "y": 0.9, "h": rng.randf_range(0.95, 1.1), "win": _win_type()}


func _win_type() -> String:
	var r := rng.randf()
	if r < 0.3:
		return "glass"
	if r < 0.54:
		return "shutter"
	if r < 0.66:
		return "bars"
	if r < 0.8:
		return "plastic"
	return "open"


func _stilts(xf: Transform3D, w: float, d: float, base_y: float, ground_y: float, dirt: float) -> void:
	var drop := base_y - ground_y + 0.6
	if drop < 0.3:
		return
	var nx := maxi(int(w / 1.6) + 1, 2)
	var nz := maxi(int(d / 1.6) + 1, 2)
	for i in nx:
		for j in nz:
			var x := -w * 0.5 + 0.1 + (w - 0.2) * i / (nx - 1)
			var z := -d * 0.5 + 0.1 + (d - 0.2) * j / (nz - 1)
			var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.05))
			ctx.sink.box(xf * Transform3D(tilt, Vector3(x, -drop * 0.5, z)), Vector3(0.11, drop, 0.11), "timber", {"dirt": 1.0, "base_y": ground_y, "what": "stilt"})
	# Cross bracing on the outer rows.
	for j in [0, nz - 1]:
		var z = -d * 0.5 + 0.1 + (d - 0.2) * j / maxf(nz - 1, 1)
		var ang := atan2(drop * 0.7, w)
		ctx.sink.box(xf * Transform3D(Basis(Vector3.BACK, ang), Vector3(0, -drop * 0.45, z)), Vector3(sqrt(w * w + drop * drop * 0.49), 0.06, 0.04), "timber", {"dirt": 1.0, "collide": false})


# ------------------------------------------------------------------ roof

func _roof(xf: Transform3D, w: float, d: float, top: float, dirt: float, bid: int, spec: Dictionary) -> void:
	var over := rng.randf_range(0.25, 0.55)
	var slope_up := rng.randf_range(0.35, 0.7)
	var gable := str(spec.get("style", "")) == "concrete" and rng.randf() < 0.6
	var mat: String = _pick(ROOF_MATS)
	var rw := w + over * 2.0
	var run := d * 0.5 + over
	var rd := d + over * 2.0
	# Height of the sheets' underside over local z, the same plane the sheets are laid in.
	var roof_y := func(z: float) -> float:
		if gable:
			return top + 0.1 + slope_up * (1.0 - absf(z) / run) - 0.01
		return top + 0.1 + slope_up * (0.5 + z / rd) - 0.01
	if gable:
		for side in [-1.0, 1.0]:
			var ang = atan2(slope_up, run) * side
			var c := Vector3(0, top + 0.1 + slope_up * 0.5, side * run * 0.5)
			var b := Basis(Vector3.RIGHT, ang)
			_roof_sheets(xf * Transform3D(b, c), rw, sqrt(run * run + slope_up * slope_up), mat, dirt, w - 0.05)
		# Ridge cap over the joint: the two slopes' sheets stop short of each other by a few centimetres (sky showed
		# through along the ridge).
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, top + 0.1 + slope_up + 0.012, 0)), Vector3(rw, 0.012, 0.4), mat, {"dirt": dirt * 0.6, "collide": false, "inner_faces": 8})
	else:
		# Shed roof: it rises toward the back wall (Basis(RIGHT, -ang) tips +z up).
		var ang := atan2(slope_up, rd)
		var c := Vector3(0, top + 0.1 + slope_up * 0.5, 0)
		_roof_sheets(xf * Transform3D(Basis(Vector3.RIGHT, -ang), c), rw, sqrt(rd * rd + slope_up * slope_up), mat, dirt, w - 0.05, d * sqrt(rd * rd + slope_up * slope_up) / rd)
	# Close the gap between the wall tops and the sheets on all four sides, cut to the roof's line. It used to be
	# left open (gable ends) or patched with half-height planks that left a strip of sky over the back and side
	# walls and stuck up through the roof at the front: from inside, by day, the walls looked see-through.
	_roof_infill(xf, w, d, top, roof_y, gable, dirt)
	# Roof weights: tyres, hollow blocks and stones keep the sheets on in typhoon season. They lie on the sheets,
	# tilted with them.
	var nweights := rng.randi_range(0, 4)
	for i in nweights:
		var lx := rng.randf_range(-w * 0.4, w * 0.4)
		var lz := rng.randf_range(-d * 0.4, d * 0.4)
		var tilt := Basis(Vector3.RIGHT, -atan2(slope_up, rd)) if not gable else Basis(Vector3.RIGHT, atan2(slope_up, run) * (1.0 if lz > 0.0 else -1.0))
		var wname: String = _pick(["old_tyre", "old_tyre", "hollow_block", "stone"])
		# Bottom on the sheets (a tyre's model is centred on its middle: it hung through the roof into the room).
		var hy: float = roof_y.call(lz) + 0.016 - _model_bottom(wname)
		ctx.dyn.add_static_prop(wname, xf * Transform3D(tilt * Basis(Vector3.UP, rng.randf() * TAU), Vector3(lx, hy, lz)))


func _deck(xf: Transform3D, w: float, d: float, top: float, dirt: float, bid: int, spec: Dictionary, ladder_x: float, style: String) -> void:
	## A flat concrete roof: a slab with a low hollow-block parapet (a gap where the ladder arrives), and what people
	## keep up there - a water tank on a stand, washing, potted plants, a chair, an antenna, rebar left for the next
	## storey, sometimes something worth taking.
	var slab_t := 0.14
	var y := top + slab_t
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, top + slab_t * 0.5, 0)), Vector3(w + 0.12, slab_t, d + 0.12), "cement",
		{"dirt": dirt, "inner_faces": 8, "phys": "concrete", "what": "deck"})
	var pm: String = _pick(["chb", "chb2", "plaster_damaged", "plaster"])
	var ph := 0.55
	var skip_back := rng.randf() < 0.25
	for side in ["front", "back", "left", "right"]:
		if side == "back" and skip_back:
			continue
		var along_x = side in ["front", "back"]
		var length := (w + 0.12) if along_x else (d - 0.12)
		var off := (-(d + 0.12) * 0.5 + 0.06) if side == "front" else ((d + 0.12) * 0.5 - 0.06 if side == "back" else 0.0)
		var offx := (-(w + 0.12) * 0.5 + 0.06) if side == "left" else ((w + 0.12) * 0.5 - 0.06 if side == "right" else 0.0)
		var gaps := []
		if side == "front" and ladder_x != INF:
			gaps.append([ladder_x - 0.42, ladder_x + 0.42])
		var a := -length * 0.5
		if not bool(spec.get("parapet", true)):
			break
		for gp in gaps + [[length * 0.5, length * 0.5]]:
			var b := float(gp[0])
			if b - a > 0.05:
				var mid := (a + b) * 0.5
				var c := Vector3(mid, y + ph * 0.5, off) if along_x else Vector3(offx, y + ph * 0.5, mid)
				var sz := Vector3(b - a, ph, 0.12) if along_x else Vector3(0.12, ph, b - a)
				ctx.sink.box(xf * Transform3D(Basis(), c), sz, pm, {"dirt": dirt, "phys": "hollow_block", "what": "parapet"})
			a = float(gp[1])
	# Water tank on a timber stand in a back corner.
	var cx := (w * 0.5 - 0.65) * (1.0 if rng.randf() < 0.5 else -1.0)
	var cz := d * 0.5 - 0.65
	if absf(cx - ladder_x) < 1.2:
		cx = -cx
	for lxz in [Vector2(-0.35, -0.35), Vector2(0.35, -0.35), Vector2(-0.35, 0.35), Vector2(0.35, 0.35)]:
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(cx + lxz.x, y + 0.45, cz + lxz.y)), Vector3(0.08, 0.9, 0.08), "timber", {"dirt": dirt, "what": "tank_stand"})
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(cx, y + 0.93, cz)), Vector3(0.9, 0.06, 0.9), "planks", {"dirt": dirt, "what": "tank_stand"})
	ctx.dyn.add_prop_spec("drum_blue", ctx.dyn.seat("drum_blue", xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(cx, y + 0.96, cz))))
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
		var plant: String = _pick(["fern", "weeds", "grass_clump", "fern"])
		ctx.dyn.add_static_prop(plant, ctx.dyn.seat(plant, xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(px, y + 0.26, pz))))
	if rng.randf() < 0.5:
		ctx.dyn.add_prop_spec("monobloc", ctx.dyn.seat("monobloc", xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(-w * 0.25, w * 0.25), y, rng.randf_range(-d * 0.2, d * 0.2)))))
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


func _roof_sheets(xf: Transform3D, w: float, length: float, mat: String, dirt: float, col_w: float = -1.0, col_len: float = -1.0) -> void:
	## col_w / col_len: the part that collides (the house's own footprint). The eaves beyond it are drawn but solid
	## for nobody: in a packed row they reach over, and through, the wall of the house next door.
	var sheet_w := 0.82
	var n := maxi(int(ceil(w / (sheet_w - 0.08))), 1)
	var step := (w - sheet_w) / maxf(n - 1, 1)
	for i in n:
		var x := -w * 0.5 + sheet_w * 0.5 + step * i
		var m = mat if rng.randf() > 0.15 else _pick(["yero_rust", "yero", "yero_worn"])
		var lift := 0.004 * (i % 2)
		var jitter := Basis(Vector3.FORWARD, rng.randf_range(-0.01, 0.01))
		ctx.sink.corrugated(xf * Transform3D(jitter, Vector3(x, lift, rng.randf_range(-0.05, 0.05))), length + rng.randf_range(-0.05, 0.1), sheet_w, m,
			{"dirt": dirt * 0.6, "collide": false, "inner_faces": 8, "tint": ctx.mats.PAINTS[rng.randi_range(0, ctx.mats.PAINTS.size() - 1)], "paint": 0.6 if m == "yero_paint" else 0.0})
	ctx.sink.col_box(xf * Transform3D(Basis(), Vector3(0, -0.02, 0)), Vector3(col_w if col_w > 0.0 else w, 0.06, col_len if col_len > 0.0 else length), "sheet_metal", "roof")


# ------------------------------------------------------------------ exterior details

func _details(xf: Transform3D, w: float, d: float, h0: float, floors: int, door_x: float, dirt: float, gmat: String, kind: String, ladder_x: float = INF,
		front_y: float = 0.0, front_lane_w: float = 9.0, stilts: bool = false) -> void:
	# Awning over the door (kept off the ladder).
	if rng.randf() < 0.55:
		var aw := rng.randf_range(1.2, 2.2)
		var ad := rng.randf_range(0.6, 1.0)
		if ladder_x != INF:
			aw = minf(aw, maxf(absf(ladder_x - (door_x + 0.42)) * 2.0 - 1.0, 0.0))
		var ax := clampf(door_x + 0.42, -w * 0.5 + aw * 0.5, w * 0.5 - aw * 0.5)
		var ab := Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(10, 20)))
		ctx.sink.corrugated(xf * Transform3D(ab, Vector3(ax, h0 * 0.86 + 0.15, -d * 0.5 - ad * 0.5)), ad, aw, _pick(["yero_rust", "yero_worn"]), {"dirt": dirt, "collide": true, "what": "awning"})
		for sx in [-1.0, 1.0]:
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(ax + sx * aw * 0.45, h0 * 0.86 + 0.02, -d * 0.5 - ad * 0.5)), Vector3(0.04, 0.04, ad), "timber", {"dirt": dirt, "collide": false})
	# Electric meter box and a sagging service cable.
	if rng.randf() < 0.7 and ladder_x == INF:
		var mx := w * 0.5 - 0.3 if door_x < 0 else -w * 0.5 + 0.3
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(mx, 1.7, -d * 0.5 - 0.08)), Vector3(0.18, 0.26, 0.12), "metal_paint", {"dirt": dirt, "collide": false, "tint": Color(0.75, 0.75, 0.72), "paint": 0.7})
		ctx.dyn.add_wire_anchor(xf * Vector3(mx, h0 * floors * 0.9 + 0.3, -d * 0.5 - 0.05))
	# Water drum / pails by the door.
	if rng.randf() < 0.5 and ladder_x == INF and not is_nan(front_y) and not stilts:
		var side := 1.0 if door_x < 0 else -1.0
		# On the ground in front of the wall (the house floor is often a step above it: they used to hang in the air).
		var dname := "drum_blue" if rng.randf() < 0.5 else "Barrel_01"
		var dxf := xf * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(side * (w * 0.5 - 0.45), front_y, -d * 0.5 - 0.45))
		# Placed once every house stands (the door across the lane may not exist yet), and only where the lane leaves
		# room to pass it.
		if front_lane_w >= 2.6:
			ctx.dyn.defer_prop(dname, dxf, Vector2(0.35, 0.35))
