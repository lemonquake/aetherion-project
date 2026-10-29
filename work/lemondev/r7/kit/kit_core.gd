extends RefCounted
## Building kit: the pieces every generated building is made of, extracted from shanty.gd (r7) so other generators
## (house_plan.gd, the Lawless Sub builders) build walls, openings, doors, windows, partitions, stairs, floors, roofs,
## ladders and acoustic zones the same way. Shanty extends this script and calls the underscore functions in the same
## order as before (Kalinaw stays byte-identical); the public functions below them are the general versions.
##
## Everything draws into ctx.sink (GeoSink), registers doors/windows/doorways/clearances with ctx.dyn and rooms and
## portals with ctx.acoustics. rng is the per-building generator: pass one in to share it, or seed this one.

const WALL_T := {"chb": 0.12, "chb2": 0.12, "plaster": 0.13, "plaster_damaged": 0.13, "plaster_cracked": 0.13, "plaster_white": 0.13,
	"plaster_peel": 0.13, "plaster_blue": 0.13, "plaster_yellow": 0.13, "concrete": 0.18}

var ctx = null
var rng := RandomNumberGenerator.new()
## Stair flights built by the last build(): {foot, top} in world space (foot: on the floor a step before the first
## tread; top: on the upper floor beside the last tread, where the flight lets out).
var flights: Array = []
## Ladders built by the last build(): {base (world, on the climbing line at the foot), top_y, n (outward), w}.
var ladders: Array = []


func _init(context, r: RandomNumberGenerator = null) -> void:
	ctx = context
	if r != null:
		rng = r

func _aabb(xf: Transform3D, r: Dictionary, y: float, h: float) -> AABB:
	var pts := [Vector3(r.x0, 0, r.z0), Vector3(r.x1, 0, r.z0), Vector3(r.x0, 0, r.z1), Vector3(r.x1, 0, r.z1)]
	var lo := Vector3(INF, y, INF)
	var hi := Vector3(-INF, y + h, -INF)
	for p in pts:
		var wp: Vector3 = xf * p
		lo.x = minf(lo.x, wp.x)
		lo.z = minf(lo.z, wp.z)
		hi.x = maxf(hi.x, wp.x)
		hi.z = maxf(hi.z, wp.z)
	# Shrink slightly so neighbouring rooms do not overlap through shared walls.
	var aabb := AABB(lo, hi - lo)
	return aabb.grow(-0.08)


# ------------------------------------------------------------------ walls

func _walls(xf: Transform3D, w: float, d: float, y: float, h: float, mat: String, openings: Dictionary, painted: bool,
		paint: Color, dirt: float, bid: int, zones: Dictionary, split: bool, z_split: float, zf: int, zb: int, covered: bool = false) -> void:
	var t := float(WALL_T.get(mat, 0.05))
	# Each side: (centre, along-axis, normal-out, length)
	var sides := {
		"front": [Vector3(0, 0, -d * 0.5 + t * 0.5), Vector3.RIGHT, Vector3.FORWARD, w],
		"back": [Vector3(0, 0, d * 0.5 - t * 0.5), Vector3.LEFT, Vector3.BACK, w],
		"left": [Vector3(-w * 0.5 + t * 0.5, 0, 0), Vector3.FORWARD, Vector3.LEFT, d - t * 2.0],
		"right": [Vector3(w * 0.5 - t * 0.5, 0, 0), Vector3.BACK, Vector3.RIGHT, d - t * 2.0],
	}
	for side in sides:
		var s: Array = sides[side]
		var center: Vector3 = s[0]
		var along: Vector3 = s[1]
		var normal: Vector3 = s[2]
		var length: float = s[3]
		var ops: Array = openings.get(side, [])
		# along-axis coordinate for openings: front uses +x, back -x, left -z (front->back reversed), right +z
		var sign := 1.0
		if side == "back":
			sign = -1.0
		var holes := []
		for o in ops:
			var c := float(o.x)
			if side == "back":
				c = -c
			elif side == "left":
				c = -c
			holes.append({"c": c, "w": float(o.w), "y": float(o.y), "h": float(o.h), "o": o})
		holes.sort_custom(func(a, b): return a.c < b.c)
		var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
		var seg_start := -length * 0.5
		var wall_mat := mat
		var cov = covered and side == "front"
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
		# Patchwork: odd panels nailed over the wall outside.
		var n_patch := rng.randi_range(0, 3)
		for i in n_patch:
			var pm: String = _pick(["plywood", "yero_rust", "planks", "tarp", "yero_worn", "osb"])
			if pm == mat:
				continue
			var pw := rng.randf_range(0.4, minf(1.6, length * 0.5))
			var ph := rng.randf_range(0.4, minf(1.4, h * 0.6))
			var pc := rng.randf_range(-length * 0.5 + pw * 0.5, length * 0.5 - pw * 0.5)
			var py := rng.randf_range(y + 0.1, y + h - ph - 0.05)
			var blocked := false
			for hole in holes:
				if absf(pc - hole.c) < (pw + hole.w) * 0.5 + 0.05 and py < y + hole.y + hole.h and py + ph > y + hole.y:
					blocked = true
			if blocked:
				continue
			var pos := center + along * pc + Vector3.UP * (py + ph * 0.5) + normal * (t * 0.5 + 0.012)
			ctx.sink.box(xf * Transform3D(basis, pos), Vector3(pw, ph, 0.012), pm, {"dirt": dirt, "collide": false, "faces": 32,
				"tint": ctx.mats.PAINTS[rng.randi_range(0, ctx.mats.PAINTS.size() - 1)], "paint": 0.4 if rng.randf() < 0.3 else 0.0,
				"layer": "int" if cov else "ext"})
		# Corner posts
		ctx.sink.box(xf * Transform3D(Basis(), center - along * length * 0.5 + Vector3.UP * (y + h * 0.5) + normal * 0.02), Vector3(0.09, h, 0.09),
			"timber" if t < 0.1 else mat, {"dirt": dirt, "collide": false, "layer": "int" if cov else "ext"})
	# Top plate / ring beam
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, y + h + 0.04, -d * 0.5 + 0.05)), Vector3(w, 0.08, 0.1), "timber", {"dirt": dirt, "collide": false})
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, y + h + 0.04, d * 0.5 - 0.05)), Vector3(w, 0.08, 0.1), "timber", {"dirt": dirt, "collide": false})


func _wall_piece(xf: Transform3D, center: Vector3, along: Vector3, basis: Basis, c: float, length: float, y: float, h: float,
		_x: float, t: float, mat: String, painted: bool, paint: Color, dirt: float, covered: bool = false) -> void:
	var pos := center + along * c + Vector3.UP * (y + h * 0.5)
	# A wall under a roofed-over lane is lit like an inside wall: both faces on the Interior layer.
	var opt := {"dirt": dirt, "base_y": xf.origin.y, "occlude": t >= 0.1 and h > 1.5, "faces": 55, "inner_faces": 16 | 32 if covered else 16, "what": "wall"}
	if painted:
		opt.tint = paint
		opt.paint = 0.85
	ctx.sink.box(xf * Transform3D(basis, pos), Vector3(length, h, t), mat, opt)


func _opening(xf: Transform3D, pos: Vector3, along: Vector3, normal: Vector3, y: float, hole: Dictionary, t: float, dirt: float,
		bid: int, inner_zone: int, side: String, split: bool, z_split: float, zb: int) -> void:
	var o: Dictionary = hole.o
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var c = pos + Vector3.UP * (y + hole.y + hole.h * 0.5)
	# Frame
	var fw: float = hole.w
	var fh: float = hole.h
	var frame_mat := "timber"
	for sx in [-1.0, 1.0]:
		ctx.sink.box(xf * Transform3D(basis, c + along * (fw * 0.5 + 0.03) * sx), Vector3(0.06, fh + 0.06, t + 0.03), frame_mat, {"dirt": dirt, "collide": false})
	ctx.sink.box(xf * Transform3D(basis, c + Vector3.UP * (fh * 0.5 + 0.03)), Vector3(fw + 0.12, 0.06, t + 0.03), frame_mat, {"dirt": dirt, "collide": false})
	var zone := inner_zone
	var world_c: Vector3 = xf * c
	var outward: Vector3 = (xf.basis * normal).normalized()
	match str(o.type):
		"door":
			var pid: int = ctx.acoustics.add_portal(zone, 0, world_c, "door", 0.0)
			var hinge_local = c - along * (fw * 0.5) - Vector3.UP * (fh * 0.5)
			ctx.dyn.add_door({"xf": xf * Transform3D(basis, hinge_local), "w": fw, "h": fh, "t": 0.035, "mat": _pick(["plywood", "planks", "planks_paint", "metal_paint", "planks_blue"]),
				"portal": pid, "bid": bid, "outer": true, "outward": outward, "seed": rng.randi(), "role": side})
		"window":
			var wt := str(o.get("win", "glass"))
			if wt == "open":
				# Glassless: a worn sill board to vault over, and (through a party wall) a lining across the gap
				# between the two houses so the sill is one surface.
				var depth := t + (0.34 if o.get("hole", false) else 0.08)
				ctx.sink.box(xf * Transform3D(basis, pos + Vector3.UP * (y + hole.y - 0.025) + normal * (depth * 0.5 - t * 0.5)),
					Vector3(fw + 0.08, 0.05, depth), "timber", {"dirt": dirt, "what": "sill"})
			var kind = {"glass": "window", "shutter": "shutter", "bars": "opening", "plastic": "curtain", "open": "opening", "store": "opening"}[wt]
			var pid2: int = ctx.acoustics.add_portal(zone, 0, world_c, kind, 1.0 if kind == "opening" else 0.0)
			ctx.dyn.add_window({"xf": xf * Transform3D(basis, c), "w": fw, "h": fh, "type": wt, "portal": pid2, "bid": bid, "outward": outward, "t": t, "seed": rng.randi(),
				"vault": bool(o.get("vault", false)), "hole": bool(o.get("hole", false)), "sill_y": (xf * (pos + Vector3.UP * (y + hole.y))).y})
		"opening":
			ctx.acoustics.add_portal(zone, 0, world_c, "opening", 1.0)
			ctx.dyn.add_doorway({"c": xf * (pos + Vector3.UP * y), "u": (xf.basis * along).normalized(), "n": outward, "w": fw, "h": fh,
				"kind": "front_open", "bid": bid})


func _partition_x(xf: Transform3D, w: float, z: float, y: float, h: float, px: float, dw: float, mat: String, open_kind: String,
		dirt: float, bid: int, zf: int, zb: int, stair: bool, stair_side: float, stair_w: float, stair_crosses: bool = true) -> void:
	## Wall across the house at depth z with a doorway centred at px.
	var x0 := -w * 0.5 + 0.05
	var x1 := w * 0.5 - 0.05
	# The stair flight along a side wall passes through here when it crosses this depth: the wall stops at its edge.
	if stair and stair_crosses:
		if stair_side > 0:
			x1 = w * 0.5 - stair_w - 0.08
		else:
			x0 = -w * 0.5 + stair_w + 0.08
	var a0 := px - dw * 0.5
	var a1 := px + dw * 0.5
	var basis := Basis()
	var t := 0.04 if mat != "chb" else 0.1
	if a0 > x0:
		ctx.sink.box(xf * Transform3D(basis, Vector3((x0 + a0) * 0.5, y + h * 0.5, z)), Vector3(a0 - x0, h, t), mat, {"dirt": dirt * 0.6, "layer": "int", "what": "partition"})
	if x1 > a1:
		ctx.sink.box(xf * Transform3D(basis, Vector3((a1 + x1) * 0.5, y + h * 0.5, z)), Vector3(x1 - a1, h, t), mat, {"dirt": dirt * 0.6, "layer": "int", "what": "partition"})
	ctx.sink.box(xf * Transform3D(basis, Vector3(px, y + 1.97 + (h - 1.97) * 0.5, z)), Vector3(dw, h - 1.97, t), mat, {"dirt": dirt * 0.6, "layer": "int", "what": "partition_lintel"})
	var wc: Vector3 = xf * Vector3(px, y + 1.0, z)
	var dway := {"c": xf * Vector3(px, y, z), "u": xf.basis.x.normalized(), "n": xf.basis.z.normalized(), "w": dw, "h": 1.97, "kind": "partition_" + open_kind, "bid": bid}
	match open_kind:
		"curtain":
			ctx.acoustics.add_portal(zf, zb, wc, "curtain", 0.0)
			ctx.dyn.add_curtain({"xf": xf * Transform3D(basis, Vector3(px, y + 1.0, z)), "w": dw, "h": 1.95, "seed": rng.randi()})
			ctx.dyn.add_doorway(dway)
		"door":
			var pid: int = ctx.acoustics.add_portal(zf, zb, wc, "door", 0.0)
			ctx.dyn.add_door({"xf": xf * Transform3D(basis, Vector3(px - dw * 0.5, y, z)), "w": dw - 0.02, "h": 1.92, "t": 0.03, "mat": "plywood",
				"portal": pid, "bid": bid, "outer": false, "seed": rng.randi(), "role": "partition"})
		_:
			ctx.acoustics.add_portal(zf, zb, wc, "opening", 1.0)
			ctx.dyn.add_doorway(dway)


func _comfort_room(xf: Transform3D, cx: float, cz: float, cw: float, cd: float, y: float, h: float, dirt: float, bid: int, outer_zone: int, crz: int) -> void:
	var t := 0.06
	var mat: String = _pick(["tiles_wall", "plywood", "chb", "plaster"])
	# Wall facing the room (along x, at front of CR) with a door, and the inner side wall (along z).
	var front_z := cz - cd * 0.5
	var inner_x := cx + cw * 0.5 if cx < 0 else cx - cw * 0.5
	# 0.62 m was narrower than a person (0.6 m across plus the movement margin): nobody could get in.
	var dw := 0.76
	var door_c := cx
	var left := cx - cw * 0.5
	var right := cx + cw * 0.5
	if door_c - dw * 0.5 > left:
		ctx.sink.box(xf * Transform3D(Basis(), Vector3((left + door_c - dw * 0.5) * 0.5, y + h * 0.5, front_z)), Vector3(door_c - dw * 0.5 - left, h, t), mat, {"dirt": dirt * 0.5, "layer": "int", "what": "cr_wall"})
	if right > door_c + dw * 0.5:
		ctx.sink.box(xf * Transform3D(Basis(), Vector3((door_c + dw * 0.5 + right) * 0.5, y + h * 0.5, front_z)), Vector3(right - door_c - dw * 0.5, h, t), mat, {"dirt": dirt * 0.5, "layer": "int", "what": "cr_wall"})
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(door_c, y + 1.9 + (h - 1.9) * 0.5, front_z)), Vector3(dw, h - 1.9, t), mat, {"dirt": dirt * 0.5, "layer": "int", "what": "cr_wall"})
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(inner_x, y + h * 0.5, cz)), Vector3(t, h, cd), mat, {"dirt": dirt * 0.5, "layer": "int", "what": "cr_wall"})
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(cx, y + 0.02, cz)), Vector3(cw - 0.1, 0.04, cd - 0.1), "tiles", {"dirt": dirt, "layer": "int"})
	var pid: int = ctx.acoustics.add_portal(outer_zone, crz, xf * Vector3(door_c, y + 1.0, front_z), "door", 0.0)
	ctx.dyn.add_door({"xf": xf * Transform3D(Basis(), Vector3(door_c - dw * 0.5, y, front_z)), "w": dw - 0.02, "h": 1.86, "t": 0.03,
		"mat": _pick(["plywood", "planks_blue", "metal_paint"]), "portal": pid, "bid": bid, "outer": false, "seed": rng.randi(), "role": "cr",
		"clr": Vector2(1.0, 0.45)})


func _stair(xf: Transform3D, sx: float, z_back: float, sw: float, run: float, rise: float, y: float, dirt: float) -> void:
	## A steep straight stair climbing from front (toward -z) to back... it rises toward the back wall.
	var steps := int(ceil(rise / 0.21))
	var sh := rise / steps
	var sd := run / steps
	var z_start := z_back - run
	flights.append({"foot": xf * Vector3(sx, y, z_start - 0.5), "top": xf * Vector3(sx - signf(sx) * sw, y + rise, z_back - 0.45), "dir": xf.basis.z,
		"start": xf * Vector3(sx, y, z_start), "run": run, "rise": rise, "w": sw, "side": (xf.basis.x * -signf(sx)).normalized()})
	# Nothing stands at the foot of the flight or on the landing beside its top step, where it lets out on to the floor.
	var ux: Vector3 = xf.basis.x.normalized()
	var nz: Vector3 = xf.basis.z.normalized()
	ctx.dyn.add_clearance(xf * Vector3(sx, y, z_start), ux, nz, sw * 0.5 + 0.05, 0.9, 0.1, "stair_foot")
	ctx.dyn.add_clearance(xf * Vector3(sx - signf(sx) * (sw * 0.5 + 0.45), y + rise, z_back), ux, nz, 0.5, 1.2, 0.1, "stair_top")
	for i in steps:
		var zc := z_start + sd * (i + 0.5)
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(sx, y + sh * (i + 1) - 0.025, zc)), Vector3(sw, 0.05, sd + 0.04), "timber", {"dirt": dirt, "collide": false, "layer": "int"})
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(sx, y + sh * (i + 0.5), zc - sd * 0.5 + 0.01)), Vector3(sw, sh, 0.02), "timber", {"dirt": dirt, "collide": false, "layer": "int"})
	# Stringers
	var ang := atan2(rise, run)
	var len := sqrt(rise * rise + run * run)
	for k in [-1.0, 1.0]:
		var c := Vector3(sx + k * (sw * 0.5 - 0.02), y + rise * 0.5 - 0.08, z_start + run * 0.5)
		ctx.sink.box(xf * Transform3D(Basis(Vector3.RIGHT, -ang), c), Vector3(0.04, 0.2, len), "timber", {"dirt": dirt, "collide": false, "layer": "int"})
	# Walkable ramp under the steps, rising with them toward the back wall (Basis(RIGHT, -ang) tips +z upward).
	var rc := Vector3(sx, y + rise * 0.5 - 0.02, z_start + run * 0.5)
	ctx.sink.col_box(xf * Transform3D(Basis(Vector3.RIGHT, -ang), rc), Vector3(sw - 0.05, 0.06, len + 0.1), "wood", "stair_ramp")


func _upper_floor(xf: Transform3D, w: float, d: float, fy: float, hole: Rect2, dirt: float) -> void:
	## Plank floor with an optional stair hole (local XZ rect).
	var t := 0.06
	if hole.size == Vector2.ZERO:
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, fy - t * 0.5, 0)), Vector3(w, t, d), "floor_planks", {"dirt": dirt * 0.5, "inner_faces": 4 | 8, "what": "upper_floor"})
	else:
		var hx0 := hole.position.x
		var hx1 := hole.end.x
		var hz0 := hole.position.y
		var hz1 := hole.end.y
		var x0 := -w * 0.5
		var x1 := w * 0.5
		var z0 := -d * 0.5
		var z1 := d * 0.5
		# Four pieces around the hole.
		if hz0 > z0:
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, fy - t * 0.5, (z0 + hz0) * 0.5)), Vector3(w, t, hz0 - z0), "floor_planks", {"dirt": dirt * 0.5, "inner_faces": 4 | 8, "what": "upper_floor"})
		if z1 > hz1:
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, fy - t * 0.5, (hz1 + z1) * 0.5)), Vector3(w, t, z1 - hz1), "floor_planks", {"dirt": dirt * 0.5, "inner_faces": 4 | 8, "what": "upper_floor"})
		if hx0 > x0:
			ctx.sink.box(xf * Transform3D(Basis(), Vector3((x0 + hx0) * 0.5, fy - t * 0.5, (hz0 + hz1) * 0.5)), Vector3(hx0 - x0, t, hz1 - hz0), "floor_planks", {"dirt": dirt * 0.5, "inner_faces": 4 | 8, "what": "upper_floor"})
		if x1 > hx1:
			ctx.sink.box(xf * Transform3D(Basis(), Vector3((hx1 + x1) * 0.5, fy - t * 0.5, (hz0 + hz1) * 0.5)), Vector3(x1 - hx1, t, hz1 - hz0), "floor_planks", {"dirt": dirt * 0.5, "inner_faces": 4 | 8, "what": "upper_floor"})
	# Joists visible from below.
	var n := int(w / 0.6)
	for i in n:
		var x := -w * 0.5 + (i + 0.5) * w / n
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(x, fy - t - 0.06, 0)), Vector3(0.06, 0.12, d - 0.1), "timber", {"dirt": dirt, "collide": false, "layer": "int"})


func _floor_deck(xf: Transform3D, w: float, d: float, y: float, mat: String, bid: int) -> void:
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, y - 0.04, 0)), Vector3(w, 0.08, d), mat, {"dirt": 0.6, "inner_faces": 4})


func _roof_infill(xf: Transform3D, w: float, d: float, top: float, roof_y: Callable, gable: bool, dirt: float) -> void:
	## Boards from the top of the walls up to the underside of the roof: strips over the front and back walls, and
	## the gable (or the shed's tapering side) over each side wall, drawn on both faces and solid.
	var t := 0.03
	for zs in [-1.0, 1.0]:
		var z: float = zs * (d * 0.5 - t * 0.5)
		var hgt: float = roof_y.call(z) - top + 0.024
		if hgt > 0.01:
			ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, top - 0.01 + hgt * 0.5, z)), Vector3(w, hgt, t), "planks", {"dirt": dirt, "what": "roof_gable"})
	var zs2: Array = [-d * 0.5, 0.0, d * 0.5] if gable else [-d * 0.5, d * 0.5]
	for sx in [-1.0, 1.0]:
		var x: float = sx * (w * 0.5 - t * 0.5)
		for k in zs2.size() - 1:
			var za: float = zs2[k]
			var zb: float = zs2[k + 1]
			var p0: Vector3 = xf * Vector3(x, top - 0.01, za)
			var p1: Vector3 = xf * Vector3(x, top - 0.01, zb)
			var p2: Vector3 = xf * Vector3(x, roof_y.call(zb) + 0.014, zb)
			var p3: Vector3 = xf * Vector3(x, roof_y.call(za) + 0.014, za)
			var out: Vector3 = (xf.basis * Vector3(sx, 0, 0)).normalized()
			ctx.sink.quad(p0, p1, p2, p3, "planks", {"dirt": dirt, "facing": out, "collide": true, "phys": "wood", "what": "roof_gable"})
			ctx.sink.quad(p0, p1, p2, p3, "planks", {"dirt": dirt, "facing": -out, "layer": "inner"})


func _ladder(xf: Transform3D, lx: float, d: float, top_y_local: float, ground_y: float, dirt: float) -> void:
	## A ladder up the front wall from the lane to the roof deck: two rails and rungs every 30 cm, standing just off
	## the wall, its rails reaching a metre above the deck to step off by. Registered for the climbing movement.
	var steel := rng.randf() < 0.45
	var mat = "metal_rust" if steel else _pick(["timber", "bamboo"])
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
	# Room to stand at its foot (yard walls and junk keep off).
	ctx.dyn.add_clearance(xf * Vector3(lx, foot_local, -d * 0.5), xf.basis.x.normalized(), -outward, 0.45, 1.0, 0.0, "ladder")


func _model_bottom(name: String) -> float:
	var md: Dictionary = ctx.dyn.models.get_model(name)
	return (md.aabb as AABB).position.y if not md.is_empty() else 0.0


func _pick(a: Array):
	return a[rng.randi_range(0, a.size() - 1)]
