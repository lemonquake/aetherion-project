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
				_wall_piece(xf, center, along, basis, hole.c, hole.w, y, hole.y, 0.0, t, wall_mat, painted, paint, dirt, cov, false)
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
			# Each patch a few millimetres further out than the one before: two in one place would z-fight.
			var pos := center + along * pc + Vector3.UP * (py + ph * 0.5) + normal * (t * 0.5 + 0.012 + i * 0.006)
			ctx.sink.box(xf * Transform3D(basis, pos), Vector3(pw, ph, 0.012), pm, {"dirt": dirt, "collide": false, "faces": 32,
				"tint": ctx.mats.PAINTS[rng.randi_range(0, ctx.mats.PAINTS.size() - 1)], "paint": 0.4 if rng.randf() < 0.3 else 0.0,
				"layer": "int" if cov else "ext"})
		# Corner posts
		ctx.sink.box(xf * Transform3D(Basis(), center - along * length * 0.5 + Vector3.UP * (y + h * 0.5) + normal * (t * 0.5 + 0.03)), Vector3(0.09, h, 0.09),
			"timber" if t < 0.1 else mat, {"dirt": dirt, "collide": false, "layer": "int" if cov else "ext"})
	# Top plate / ring beam, standing 3 cm proud of the wall face (flush, it z-fought with the gable and the storey above).
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, y + h, -d * 0.5 + 0.02)), Vector3(w + 0.06, 0.08, 0.1), "timber", {"dirt": dirt, "collide": false})
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(0, y + h, d * 0.5 - 0.02)), Vector3(w + 0.06, 0.08, 0.1), "timber", {"dirt": dirt, "collide": false})


func _wall_piece(xf: Transform3D, center: Vector3, along: Vector3, basis: Basis, c: float, length: float, y: float, h: float,
		_x: float, t: float, mat: String, painted: bool, paint: Color, dirt: float, covered: bool = false, cap: bool = true) -> void:
	var pos := center + along * c + Vector3.UP * (y + h * 0.5)
	# A wall under a roofed-over lane is lit like an inside wall: both faces on the Interior layer. A piece that runs
	# up to the wall top has no top face: the plate, the floor or the ceiling above covers it, and the face flush with
	# that floor z-fought with it. Below a sill the top is the sill and stays.
	var opt := {"dirt": dirt, "base_y": xf.origin.y, "occlude": t >= 0.1 and h > 1.5, "faces": 51 if cap else 55, "inner_faces": 16 | 32 if covered else 16, "what": "wall"}
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
		# 3 cm proud of each face: 1.5 cm was too close to the wall for the depth buffer at a distance (z-fighting).
		# Jambs start 3 cm into the wall: flush with the reveal (or 1 cm behind it), their faces z-fought with it.
		ctx.sink.box(xf * Transform3D(basis, c + along * (fw * 0.5 + 0.06) * sx), Vector3(0.06, fh + 0.12, t + 0.06), frame_mat, {"dirt": dirt, "collide": false})
	ctx.sink.box(xf * Transform3D(basis, c + Vector3.UP * (fh * 0.5 + 0.06)), Vector3(fw + 0.18, 0.06, t + 0.06), frame_mat, {"dirt": dirt, "collide": false})
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
		# 3 cm clear of the wall the flight runs along (1 cm off it, the stringer z-fought with the wall).
		var c := Vector3(sx + k * (sw * 0.5 - 0.04), y + rise * 0.5 - 0.08, z_start + run * 0.5)
		ctx.sink.box(xf * Transform3D(Basis(Vector3.RIGHT, -ang), c), Vector3(0.04, 0.2, len), "timber", {"dirt": dirt, "collide": false, "layer": "int"})
	# Walkable ramp under the steps, rising with them toward the back wall (Basis(RIGHT, -ang) tips +z upward).
	var rc := Vector3(sx, y + rise * 0.5 - 0.02, z_start + run * 0.5)
	ctx.sink.col_box(xf * Transform3D(Basis(Vector3.RIGHT, -ang), rc), Vector3(sw - 0.05, 0.06, len + 0.1), "wood", "stair_ramp")


func _upper_floor(xf: Transform3D, w: float, d: float, fy: float, hole: Rect2, dirt: float) -> void:
	## Plank floor with an optional stair hole (local XZ rect). Its edges stop 2 cm inside the outer wall faces
	## (flush, the floor's edge z-fought with the wall).
	w -= 0.04
	d -= 0.04
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


# ================================================================== general kit (r7)
# Used by house_plan.gd and the Lawless Sub builders. Coordinates are building-local: x right, y up, z back (-z is the
# front), origin at the footprint centre on the ground-floor level. Rects are Rect2(x, z, width, depth).

## Vault-sized ground-floor window (player/vault.gd: a top 0.45-1.5 m above the feet, at least 0.62 m clear above
## it, a landing past it): sill 0.85 m, opening 1.2 m tall, 1.05 m wide.
const VAULT_SILL := 0.85
const VAULT_H := 1.2
const VAULT_W := 1.05
## Stair geometry: risers of at most 0.21 m (the corpse steps in dynamics.gd rebuild them with the same rule).
const RISER := 0.21
const TREAD := 0.27


func aabb_rect(xf: Transform3D, r: Rect2, y: float, h: float) -> AABB:
	## World AABB of a local rect from world height y, h tall (shrunk 8 cm like every room zone).
	return _aabb(xf, {"x0": r.position.x, "x1": r.end.x, "z0": r.position.y, "z1": r.end.y}, y, h)


func wall_seg(xf: Transform3D, a: Vector2, b: Vector2, y: float, h: float, t: float, mat: String, openings: Array, o: Dictionary = {}) -> void:
	## A straight wall on the centre line a -> b (local XZ), standing on local height y, h tall and t thick, cut round
	## its openings. The wall's local +z side (Basis(along, UP, along x UP)) is "p", the other "n": for an outer wall
	## walk the footprint so that p is indoors (front +x, right +z, back -x, left -z).
	## openings: [{type: door|window|opening, c (metres from a to the opening's centre), w, y (sill above the floor), h,
	##   win (window type), vault, door_mat, role, frame, zone_p, zone_n (override), clr (Vector2), portal, kind}]
	## o: zone_p / zone_n (acoustic zones either side; 0 = outdoors), outer (an outer wall: n is outdoors), bid, dirt,
	##   tint + paint (paint amount on mat), layer (main box layer, default "ext"), inner_p (the p face goes on the
	##   Interior layer), lin_p / lin_n: [[c0, c1, mat, tint]] linings over that face (room finishes; Interior layer),
	##   frame (frame material, "" for none), frame_tint, sill_mat, collide (default true), what.
	var seg := b - a
	var length := seg.length()
	if length < 0.02:
		return
	var al := seg / length
	var along := Vector3(al.x, 0.0, al.y)
	var nz := along.cross(Vector3.UP)
	var basis := Basis(along, Vector3.UP, nz)
	var base := Vector3(a.x, 0.0, a.y)
	var holes := []
	for op in openings:
		var c := float(op.c)
		var ow := float(op.w)
		if c - ow * 0.5 < 0.02 or c + ow * 0.5 > length - 0.02:
			continue
		holes.append(op)
	holes.sort_custom(func(p, q): return float(p.c) < float(q.c))
	var pieces := []   # [c0, c1, y0, y1]
	var s0 := 0.0
	for hole in holes:
		var c0 := float(hole.c) - float(hole.w) * 0.5
		var c1 := float(hole.c) + float(hole.w) * 0.5
		var hy := float(hole.get("y", 0.0))
		var hh := float(hole.h)
		if c0 - s0 > 0.01:
			pieces.append([s0, c0, 0.0, h])
		if hy > 0.01:
			pieces.append([c0, c1, 0.0, hy])
		if hy + hh < h - 0.01:
			pieces.append([c0, c1, hy + hh, h])
		s0 = c1
	if length - s0 > 0.01:
		pieces.append([s0, length, 0.0, h])
	var layer := str(o.get("layer", "ext"))
	var lin_p: Array = o.get("lin_p", [])
	var lin_n: Array = o.get("lin_n", [])
	var dirt := float(o.get("dirt", 0.4))
	for pc in pieces:
		var pc0: float = pc[0]
		var pc1: float = pc[1]
		var py0: float = pc[2]
		var py1: float = pc[3]
		var faces := 55
		# Pieces up to the wall top lose the top face (covered by the slab above; flush with it, it z-fought).
		if py1 >= h - 0.005 and bool(o.get("capped", true)):
			faces &= ~4
		var inner := 16 if bool(o.get("inner_p", false)) else 0
		if _covered(lin_p, pc0, pc1):
			faces &= ~16
		if _covered(lin_n, pc0, pc1):
			faces &= ~32
		var pos := base + along * ((pc0 + pc1) * 0.5) + Vector3.UP * (y + (py0 + py1) * 0.5)
		var opt := {"dirt": dirt, "base_y": xf.origin.y, "occlude": t >= 0.1 and py1 - py0 > 1.5, "faces": faces, "inner_faces": inner & faces,
			"layer": layer, "what": str(o.get("what", "wall")), "collide": bool(o.get("collide", true))}
		if o.has("tint"):
			opt.tint = o.tint
			opt.paint = float(o.get("paint", 0.85))
		ctx.sink.box(xf * Transform3D(basis, pos), Vector3(pc1 - pc0, py1 - py0, t), mat, opt)
		for side in [1.0, -1.0]:
			for ln in (lin_p if side > 0.0 else lin_n):
				var l0 := maxf(float(ln[0]), pc0)
				var l1 := minf(float(ln[1]), pc1)
				if l1 - l0 < 0.01:
					continue
				var lpos: Vector3 = base + along * ((l0 + l1) * 0.5) + Vector3.UP * (y + (py0 + py1) * 0.5) + nz * side * (t * 0.5 + 0.004)
				var lopt := {"dirt": dirt * 0.4, "collide": false, "faces": 16 if side > 0.0 else 32, "layer": "inner", "base_y": xf.origin.y + y}
				if ln.size() > 3 and ln[3] is Color:
					lopt.tint = ln[3]
					lopt.paint = 0.8
				ctx.sink.box(xf * Transform3D(basis, lpos), Vector3(l1 - l0, py1 - py0, 0.008), str(ln[2]), lopt)
	for hole in holes:
		_opening2(xf, base + along * float(hole.c), along, nz, y, hole, t, o)


func _covered(lins: Array, c0: float, c1: float) -> bool:
	## True when the linings cover [c0, c1] with no gap.
	if lins.is_empty():
		return false
	var spans := []
	for ln in lins:
		spans.append([float(ln[0]), float(ln[1])])
	spans.sort_custom(func(p, q): return p[0] < q[0])
	var at := c0
	for sp in spans:
		if float(sp[0]) > at + 0.005:
			return false
		at = maxf(at, float(sp[1]))
		if at >= c1 - 0.005:
			return true
	return at >= c1 - 0.005


func _opening2(xf: Transform3D, pos: Vector3, along: Vector3, nz: Vector3, y: float, hole: Dictionary, t: float, o: Dictionary) -> void:
	## Frame, leaf or glass, and registration of one opening in a wall_seg wall. pos: the opening's centre on the
	## wall's centre line at floor level (local).
	var basis := Basis(along, Vector3.UP, nz)
	var hw := float(hole.w)
	var hh := float(hole.h)
	var hy := float(hole.get("y", 0.0))
	var c := pos + Vector3.UP * (y + hy + hh * 0.5)
	var bid := int(o.get("bid", -1))
	var dirt := float(o.get("dirt", 0.4))
	var outer := bool(o.get("outer", false))
	var zp := int(hole.get("zone_p", o.get("zone_p", 0)))
	var zn := int(hole.get("zone_n", o.get("zone_n", 0)))
	var fmat := str(hole.get("frame", o.get("frame", "timber")))
	var fopt := {"dirt": dirt * 0.5, "collide": false}
	if o.has("frame_tint"):
		fopt.tint = o.frame_tint
		fopt.paint = 0.9
	var typ := str(hole.type)
	if fmat != "":
		for sx in [-1.0, 1.0]:
			ctx.sink.box(xf * Transform3D(basis, c + along * (hw * 0.5 + 0.055) * sx), Vector3(0.05, hh + 0.11, t + 0.07), fmat, fopt)
		ctx.sink.box(xf * Transform3D(basis, c + Vector3.UP * (hh * 0.5 + 0.055)), Vector3(hw + 0.16, 0.05, t + 0.07), fmat, fopt)
	var world_c: Vector3 = xf * c
	var outward: Vector3 = (xf.basis * -nz).normalized()
	match typ:
		"door":
			var pid: int = ctx.acoustics.add_portal(zp, zn, world_c, str(hole.get("portal", "door")), 0.0)
			var hinge := c - along * (hw * 0.5) - Vector3.UP * (hh * 0.5)
			var spec := {"xf": xf * Transform3D(basis, hinge), "w": hw - 0.02, "h": hh - 0.02, "t": float(hole.get("leaf_t", 0.04)),
				"mat": str(hole.get("door_mat", "planks_dark")), "portal": pid, "bid": bid, "outer": outer, "seed": rng.randi(),
				"role": str(hole.get("role", "front" if outer else "partition"))}
			if outer:
				spec.outward = outward
			if hole.has("clr"):
				spec.clr = hole.clr
			ctx.dyn.add_door(spec)
		"window":
			var wt := str(hole.get("win", "glass"))
			# A sill: a concrete ledge outside (inside, the wall's own top is what a vault stands on).
			if outer:
				var sopt := {"dirt": dirt, "collide": false}
				ctx.sink.box(xf * Transform3D(basis, pos + Vector3.UP * (y + hy - 0.03) - nz * (t * 0.5 + 0.03)), Vector3(hw + 0.16, 0.06, 0.08),
					str(o.get("sill_mat", "concrete")), sopt)
			if wt == "open" and t < 0.1:
				ctx.sink.box(xf * Transform3D(basis, pos + Vector3.UP * (y + hy - 0.025)), Vector3(hw + 0.08, 0.05, t + 0.08), "timber", {"dirt": dirt, "what": "sill"})
			var kind: String = {"glass": "window", "shutter": "shutter", "bars": "opening", "plastic": "curtain", "open": "opening", "store": "opening"}.get(wt, "window")
			var pid2: int = ctx.acoustics.add_portal(zp, zn, world_c, kind, 1.0 if kind == "opening" else 0.0)
			ctx.dyn.add_window({"xf": xf * Transform3D(basis, c), "w": hw, "h": hh, "type": wt, "portal": pid2, "bid": bid, "outward": outward, "t": t,
				"seed": rng.randi(), "vault": bool(hole.get("vault", false)), "hole": false, "sill_y": (xf * (pos + Vector3.UP * (y + hy))).y})
			if bool(hole.get("vault", false)):
				# Nothing stands under a vault window on either side: the landing must stay free.
				ctx.dyn.add_clearance(xf * (pos + Vector3.UP * y), (xf.basis * along).normalized(), (xf.basis * nz).normalized(), hw * 0.5 + 0.1, 0.9, 1.0, "vault")
		"opening":
			ctx.acoustics.add_portal(zp, zn, world_c, "opening", 1.0)
			ctx.dyn.add_doorway({"c": xf * (pos + Vector3.UP * y), "u": (xf.basis * along).normalized(), "n": outward, "w": hw, "h": hh,
				"kind": str(hole.get("kind", "front_open" if outer else "partition_opening")), "bid": bid})


func slab(xf: Transform3D, r: Rect2, y_top: float, t: float, mat: String, holes: Array = [], o: Dictionary = {}) -> void:
	## A floor or roof slab over local rect r with its top at local height y_top, cut round holes (local rects).
	## o: layer (default "inner"), faces, inner_faces, tint, paint, dirt, phys, occlude, collide, what, under (material
	## of a ceiling skin drawn under it on the Interior layer), under_tint.
	var xs := [r.position.x, r.end.x]
	var zs := [r.position.y, r.end.y]
	var hs := []
	for hr in holes:
		var hc: Rect2 = (hr as Rect2).intersection(r)
		if hc.size.x > 0.01 and hc.size.y > 0.01:
			hs.append(hc)
			xs.append_array([hc.position.x, hc.end.x])
			zs.append_array([hc.position.y, hc.end.y])
	xs.sort()
	zs.sort()
	xs = _uniq(xs)
	zs = _uniq(zs)
	# Cells outside every hole, merged along x into strips.
	for j in zs.size() - 1:
		var z0: float = zs[j]
		var z1: float = zs[j + 1]
		var i := 0
		while i < xs.size() - 1:
			var x0: float = xs[i]
			if _in_holes(hs, Vector2((x0 + float(xs[i + 1])) * 0.5, (z0 + z1) * 0.5)):
				i += 1
				continue
			var k := i + 1
			while k < xs.size() - 1 and not _in_holes(hs, Vector2((float(xs[k]) + float(xs[k + 1])) * 0.5, (z0 + z1) * 0.5)):
				k += 1
			var x1: float = xs[k]
			# With a ceiling skin under it the slab's own underside is hidden (and 8 mm from the skin it z-fought).
			var sfaces := int(o.get("faces", 63)) & (~8 if o.has("under") else 63)
			var opt := {"layer": str(o.get("layer", "inner")), "dirt": float(o.get("dirt", 0.3)), "what": str(o.get("what", "slab")),
				"collide": bool(o.get("collide", true)), "faces": sfaces, "inner_faces": int(o.get("inner_faces", 0)) & sfaces}
			for key in ["tint", "paint", "phys", "occlude"]:
				if o.has(key):
					opt[key] = o[key]
			ctx.sink.box(xf * Transform3D(Basis(), Vector3((x0 + x1) * 0.5, y_top - t * 0.5, (z0 + z1) * 0.5)), Vector3(x1 - x0, t, z1 - z0), mat, opt)
			if o.has("under"):
				var uopt := {"layer": "inner", "collide": false, "faces": 8, "dirt": 0.15}
				if o.has("under_tint"):
					uopt.tint = o.under_tint
					uopt.paint = 0.7
				ctx.sink.box(xf * Transform3D(Basis(), Vector3((x0 + x1) * 0.5, y_top - t - 0.004, (z0 + z1) * 0.5)), Vector3(x1 - x0, 0.008, z1 - z0), str(o.under), uopt)
			i = k


func _uniq(a: Array) -> Array:
	var out := []
	for v in a:
		if out.is_empty() or absf(float(v) - float(out[-1])) > 0.005:
			out.append(v)
	return out


func _in_holes(hs: Array, p: Vector2) -> bool:
	for h in hs:
		if (h as Rect2).has_point(p):
			return true
	return false


func railing(xf: Transform3D, a: Vector2, b: Vector2, y: float, o: Dictionary = {}) -> void:
	## A rail from a to b on local floor height y: posts, a top and a middle rail, and an invisible blocker (bullets
	## pass) so nobody walks off the edge.
	var seg := b - a
	var length := seg.length()
	if length < 0.15:
		return
	var al := seg / length
	var along := Vector3(al.x, 0.0, al.y)
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var mat := str(o.get("mat", "metal_paint"))
	var hgt := float(o.get("h", 1.0))
	var opt := {"collide": false, "dirt": 0.3, "layer": str(o.get("layer", "int")), "tint": o.get("tint", Color(0.12, 0.12, 0.12)), "paint": 0.9}
	var mid := Vector3((a.x + b.x) * 0.5, y, (a.y + b.y) * 0.5)
	for ry in [hgt, hgt * 0.5]:
		ctx.sink.box(xf * Transform3D(basis, mid + Vector3.UP * ry), Vector3(length, 0.045, 0.045), mat, opt)
	var n := maxi(int(ceil(length / 1.2)), 1)
	for k in n + 1:
		var p := Vector3(a.x, y, a.y) + along * (length * k / n)
		ctx.sink.box(xf * Transform3D(basis, p + Vector3.UP * (hgt * 0.5)), Vector3(0.045, hgt, 0.045), mat, opt)
	ctx.sink.col_box(xf * Transform3D(basis, mid + Vector3.UP * (hgt * 0.5 + 0.05)), Vector3(length, hgt + 0.1, 0.06), "blocker", "railing")


func stair_flight(xf: Transform3D, start: Vector2, dir: Vector2, w: float, rise: float, y: float, side: Vector2, o: Dictionary = {}) -> Dictionary:
	## A straight flight rising from local floor height y by `rise`: the leading edge of its first tread centred on
	## `start`, climbing along unit `dir`, w wide. `side` (unit, across the flight) is the way it lets out sideways at
	## the top (it also lets out straight on). Visual treads, risers and a soffit; a walkable ramp collider like the
	## shanty stair; the record goes into flights ({foot, top, dir, start, run, rise, w, side}) with clearances at the
	## foot and the top. o: mat, soffit, tint, tread, dirt, rail (a handrail on the side opposite `side`, or
	## rail_side). Returns {run, steps, end (Vector2), rect (local Rect2 of the flight)}.
	var steps := int(ceil(rise / RISER))
	var sh := rise / steps
	var sd := float(o.get("tread", TREAD))
	var run := sd * steps
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var s3 := Vector3(side.x, 0.0, side.y)
	var st := Vector3(start.x, y, start.y)
	var basis := Basis(Vector3.UP.cross(d3).normalized(), Vector3.UP, d3)   # local z = climbing direction
	var mat := str(o.get("mat", "concrete"))
	var dirt := float(o.get("dirt", 0.3))
	var topt := {"dirt": dirt, "collide": false, "layer": "int"}
	if o.has("tint"):
		topt.tint = o.tint
		topt.paint = 0.7
	for i in steps:
		var zc := sd * (i + 0.5)
		ctx.sink.box(xf * Transform3D(basis, st + d3 * zc + Vector3.UP * (sh * (i + 1) - 0.025)), Vector3(w, 0.05, sd + 0.03), mat, topt)
		ctx.sink.box(xf * Transform3D(basis, st + d3 * (zc - sd * 0.5 + 0.01) + Vector3.UP * (sh * (i + 0.5))), Vector3(w, sh, 0.02), mat, topt)
	var ang := atan2(rise, run)
	var len := sqrt(rise * rise + run * run)
	var tilt := basis * Basis(Vector3.RIGHT, -ang)
	# Soffit under the flight (a concrete stair is a slab) and the walkable ramp the movement uses.
	ctx.sink.box(xf * Transform3D(tilt, st + d3 * (run * 0.5) + Vector3.UP * (rise * 0.5 - 0.16)), Vector3(w, 0.12, len), str(o.get("soffit", mat)),
		{"dirt": dirt, "collide": false, "layer": "int"})
	ctx.sink.col_box(xf * Transform3D(tilt, st + d3 * (run * 0.5) + Vector3.UP * (rise * 0.5 - 0.02)), Vector3(w - 0.05, 0.06, len + 0.1), "concrete", "stair_ramp")
	var end := start + dir * run
	var top_l := st + d3 * (run - 0.45) + s3 * w + Vector3.UP * rise
	flights.append({"foot": xf * (st - d3 * 0.5), "top": xf * top_l, "dir": (xf.basis * d3).normalized(), "start": xf * st, "run": run, "rise": rise,
		"w": w, "side": (xf.basis * s3).normalized()})
	var u: Vector3 = (xf.basis * s3).normalized()
	var nd: Vector3 = (xf.basis * d3).normalized()
	ctx.dyn.add_clearance(xf * st, u, nd, w * 0.5 + 0.05, 0.9, 0.1, "stair_foot")
	ctx.dyn.add_clearance(xf * (st + d3 * run + s3 * (w * 0.5 + 0.45) + Vector3.UP * rise), u, nd, 0.5, 1.2, 0.1, "stair_top")
	ctx.dyn.add_clearance(xf * (st + d3 * run + Vector3.UP * rise), u, nd, w * 0.5, 0.0, 1.0, "stair_top")
	if bool(o.get("rail", false)):
		var rs: Vector2 = o.get("rail_side", -side)
		var off := rs * (w * 0.5 + 0.03)
		var lo := start + off
		var hi := end + off
		# A handrail rising with the flight, on posts, solid for movement (bullets pass).
		var rmid := Vector3((lo.x + hi.x) * 0.5, y + rise * 0.5 + 0.9, (lo.y + hi.y) * 0.5)
		var rcol := {"collide": false, "layer": "int", "tint": Color(0.12, 0.12, 0.12), "paint": 0.9}
		ctx.sink.box(xf * Transform3D(tilt, rmid), Vector3(0.05, 0.05, len), "metal_paint", rcol)
		for k in 5:
			var f := k / 4.0
			var pp := Vector3(lerpf(lo.x, hi.x, f), y + rise * f, lerpf(lo.y, hi.y, f))
			ctx.sink.box(xf * Transform3D(basis, pp + Vector3.UP * 0.45), Vector3(0.04, 0.9, 0.04), "metal_paint", rcol)
		ctx.sink.col_box(xf * Transform3D(tilt, rmid - Vector3.UP * 0.35), Vector3(0.06, 1.1, len), "blocker", "stair_rail")
	var across := Vector2(absf(dir.y), absf(dir.x)) * (w * 0.5)
	var rmin := Vector2(minf(start.x, end.x), minf(start.y, end.y)) - across
	var rmax := Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + across
	return {"run": run, "steps": steps, "end": end, "rect": Rect2(rmin, rmax - rmin)}


func gable_roof(xf: Transform3D, w: float, d: float, top: float, o: Dictionary = {}) -> float:
	## A pitched roof over the w x d footprint whose walls end at local height top: two slopes meeting at a ridge along
	## local x (o.ridge "z" turns it), eaves o.over beyond the walls, the gable ends filled with o.gable_mat. Solid.
	## o: pitch (rise per metre, default 0.45), over, mat, t, gable_mat, tint, paint, inner (underside on the Interior
	## layer: an open hall seen from inside), fascia, fascia_tint, dirt. Returns the ridge height (local).
	var along_x := str(o.get("ridge", "x")) == "x"
	var span := d if along_x else w
	var length := w if along_x else d
	var pitch := float(o.get("pitch", 0.45))
	var over := float(o.get("over", 0.5))
	var mat := str(o.get("mat", "roof_tiles"))
	var t := float(o.get("t", 0.06))
	var dirt := float(o.get("dirt", 0.4))
	var base_y := top + 0.06
	var run := span * 0.5 + over
	var ridge := base_y + span * 0.5 * pitch
	var ang := atan(pitch)
	var slope_len := run / cos(ang)
	var rot := Basis() if along_x else Basis(Vector3.UP, PI * 0.5)
	var ropt := {"dirt": dirt, "what": "roof", "inner_faces": 8 if bool(o.get("inner", false)) else 0}
	for side in [-1.0, 1.0]:
		var c := Vector3(0, ridge - run * pitch * 0.5 - t * 0.5, side * run * 0.5)
		var b := rot * Basis(Vector3.RIGHT, ang * side)
		ctx.sink.box(xf * Transform3D(b, rot * c), Vector3(length + over * 2.0, t, slope_len + 0.04), mat, ropt)
	ctx.sink.box(xf * Transform3D(rot, rot * Vector3(0, ridge + 0.02, 0)), Vector3(length + over * 2.0 + 0.04, 0.08, 0.26), mat, {"dirt": dirt, "collide": false})
	# Gable ends (triangles) over the two end walls, outside and in.
	var gm := str(o.get("gable_mat", "wall_beige"))
	for e in [-1.0, 1.0]:
		var xl: float = e * (length * 0.5 - 0.01)
		var p0: Vector3 = xf * (rot * Vector3(xl, top - 0.02, -span * 0.5))
		var p1: Vector3 = xf * (rot * Vector3(xl, top - 0.02, span * 0.5))
		var p2: Vector3 = xf * (rot * Vector3(xl, ridge - 0.02, 0.0))
		var outn: Vector3 = (xf.basis * (rot * Vector3(e, 0, 0))).normalized()
		var gopt := {"dirt": dirt, "collide": true, "phys": "plaster", "facing": outn, "what": "gable"}
		if o.has("tint"):
			gopt.tint = o.tint
			gopt.paint = float(o.get("paint", 0.85))
		ctx.sink.quad(p0, p1, p2, p2, gm, gopt)
		ctx.sink.quad(p0, p1, p2, p2, gm, {"facing": -outn, "layer": "inner", "dirt": dirt})
	# Fascia boards along the eaves.
	for side in [-1.0, 1.0]:
		var ey := base_y - over * pitch - 0.08
		ctx.sink.box(xf * Transform3D(rot, rot * Vector3(0, ey, side * (span * 0.5 + over))), Vector3(length + over * 2.0, 0.2, 0.04), str(o.get("fascia", "planks_paint")),
			{"dirt": dirt, "collide": false, "tint": o.get("fascia_tint", Color(0.92, 0.9, 0.85)), "paint": 0.9})
	# The strip between the wall tops and the slopes along the eave walls.
	for side in [-1.0, 1.0]:
		var sopt := {"dirt": dirt, "collide": false, "faces": 32 | 16}
		if o.has("tint"):
			sopt.tint = o.tint
			sopt.paint = float(o.get("paint", 0.85))
		ctx.sink.box(xf * Transform3D(rot, rot * Vector3(0, top + 0.04, side * (span * 0.5 - 0.08))), Vector3(length, 0.1, 0.16), gm, sopt)
	return ridge


func hip_roof(xf: Transform3D, w: float, d: float, top: float, o: Dictionary = {}) -> float:
	## A hipped roof (four slopes, the ridge along the longer side): the usual roof of a Filipino concrete house. Tiles
	## on solid quads with a plastered underside, eaves o.over beyond the walls. Options as gable_roof. Returns the
	## ridge height.
	var pitch := float(o.get("pitch", 0.45))
	var over := float(o.get("over", 0.55))
	var mat := str(o.get("mat", "roof_tiles"))
	var dirt := float(o.get("dirt", 0.4))
	var base_y := top + 0.06
	var hw := w * 0.5 + over
	var hd := d * 0.5 + over
	var short := minf(w, d) * 0.5
	var ridge := base_y + short * pitch
	var ey := base_y - over * pitch
	var rx := maxf(w * 0.5 - short, 0.0)   # ridge half-length along x (w >= d) or z
	var rz := maxf(d * 0.5 - short, 0.0)
	var c := [Vector3(-hw, ey, -hd), Vector3(hw, ey, -hd), Vector3(hw, ey, hd), Vector3(-hw, ey, hd)]
	var ra := Vector3(-rx, ridge, -rz)
	var rb := Vector3(rx, ridge, rz)
	var planes := []
	if rz == 0.0:
		planes = [[c[0], c[1], rb, ra], [c[1], c[2], rb, rb], [c[2], c[3], ra, rb], [c[3], c[0], ra, ra]]
	else:
		planes = [[c[0], c[1], ra, ra], [c[1], c[2], rb, ra], [c[2], c[3], rb, rb], [c[3], c[0], ra, rb]]
	for pl in planes:
		var q0: Vector3 = xf * (pl[0] as Vector3)
		var q1: Vector3 = xf * (pl[1] as Vector3)
		var q2: Vector3 = xf * (pl[2] as Vector3)
		var q3: Vector3 = xf * (pl[3] as Vector3)
		ctx.sink.quad(q0, q1, q2, q3, mat, {"dirt": dirt, "facing": xf.basis * Vector3.UP, "collide": true, "what": "roof"})
		ctx.sink.quad(q0, q1, q2, q3, "cement", {"dirt": dirt * 0.5, "facing": xf.basis * Vector3.DOWN, "layer": "inner" if bool(o.get("inner", false)) else "ext",
			"tint": Color(0.85, 0.83, 0.78), "paint": 0.6})
	# Ridge and hip caps.
	var caps := [[ra, rb]]
	for k in 4:
		caps.append([c[k], ra if (rz == 0.0 and (k == 0 or k == 3)) or (rz > 0.0 and k < 2) else rb])
	for cp in caps:
		var a: Vector3 = cp[0]
		var b: Vector3 = cp[1]
		var len := a.distance_to(b)
		if len < 0.05:
			continue
		var dz := (b - a) / len
		var bx := Vector3.UP.cross(dz)
		if bx.length() < 0.01:
			continue
		bx = bx.normalized()
		ctx.sink.box(xf * Transform3D(Basis(bx, dz.cross(bx), dz), (a + b) * 0.5 + Vector3.UP * 0.03), Vector3(0.2, 0.07, len), mat, {"dirt": dirt, "collide": false})
	# Fascia round the eaves and the strip between the wall tops and the slopes.
	var gm := str(o.get("gable_mat", "wall_beige"))
	for k in 4:
		var horiz := k % 2 == 0
		var sgn := -1.0 if k < 2 else 1.0
		var fpos := Vector3(0, ey - 0.08, sgn * hd) if horiz else Vector3(sgn * hw, ey - 0.08, 0)
		var fsize := Vector3(hw * 2.0, 0.2, 0.04) if horiz else Vector3(0.04, 0.2, hd * 2.0)
		ctx.sink.box(xf * Transform3D(Basis(), fpos), fsize, str(o.get("fascia", "planks_paint")), {"dirt": dirt, "collide": false,
			"tint": o.get("fascia_tint", Color(0.92, 0.9, 0.85)), "paint": 0.9})
		var spos := Vector3(0, top + 0.04, sgn * (d * 0.5 - 0.08)) if horiz else Vector3(sgn * (w * 0.5 - 0.08), top + 0.04, 0)
		var ssize := Vector3(w, 0.1, 0.16) if horiz else Vector3(0.16, 0.1, d)
		var sopt := {"dirt": dirt, "collide": false}
		if o.has("tint"):
			sopt.tint = o.tint
			sopt.paint = 0.85
		ctx.sink.box(xf * Transform3D(Basis(), spos), ssize, gm, sopt)
	return ridge


func parapet(xf: Transform3D, r: Rect2, y: float, h: float, t: float, mat: String, gaps: Array = [], o: Dictionary = {}) -> void:
	## A low wall round the edge of a flat roof (local rect r, standing on height y). gaps: [[side, c0, c1]] with side
	## front/right/back/left and c measured along the edge from its start (front +x, right +z, back -x, left -z).
	var x0 := r.position.x
	var x1 := r.end.x
	var z0 := r.position.y
	var z1 := r.end.y
	var edges := {"front": [Vector2(x0, z0 + t * 0.5), Vector2(x1, z0 + t * 0.5)], "right": [Vector2(x1 - t * 0.5, z0 + t), Vector2(x1 - t * 0.5, z1 - t)],
		"back": [Vector2(x1, z1 - t * 0.5), Vector2(x0, z1 - t * 0.5)], "left": [Vector2(x0 + t * 0.5, z1 - t), Vector2(x0 + t * 0.5, z0 + t)]}
	for side in edges:
		var a: Vector2 = edges[side][0]
		var b: Vector2 = edges[side][1]
		var ops := []
		for g in gaps:
			if str(g[0]) == side:
				ops.append({"c": (float(g[1]) + float(g[2])) * 0.5, "w": float(g[2]) - float(g[1])})
		var oo := o.duplicate()
		oo.what = "parapet"
		_wall_holes_only(xf, a, b, y, h, t, mat, ops, oo)
		var seg := b - a
		var mid := (a + b) * 0.5
		var size := Vector3(seg.length() + 0.04, 0.05, t + 0.06) if absf(seg.x) > absf(seg.y) else Vector3(t + 0.06, 0.05, seg.length() + 0.04)
		ctx.sink.box(xf * Transform3D(Basis(), Vector3(mid.x, y + h + 0.025, mid.y)), size, "concrete", {"dirt": 0.6, "collide": false})


func _wall_holes_only(xf: Transform3D, a: Vector2, b: Vector2, y: float, h: float, t: float, mat: String, gaps: Array, o: Dictionary) -> void:
	## wall_seg without any opening registration: plain gaps (parapets, fences, low walls). gaps: [{c, w}].
	var seg := b - a
	var length := seg.length()
	if length < 0.02:
		return
	var al := seg / length
	var along := Vector3(al.x, 0.0, al.y)
	var basis := Basis(along, Vector3.UP, along.cross(Vector3.UP))
	var s0 := 0.0
	var cuts := []
	for g in gaps:
		cuts.append([float(g.c) - float(g.w) * 0.5, float(g.c) + float(g.w) * 0.5])
	cuts.sort_custom(func(p, q): return p[0] < q[0])
	cuts.append([length, length])
	for cu in cuts:
		var e := clampf(float(cu[0]), 0.0, length)
		if e - s0 > 0.02:
			var opt := {"dirt": float(o.get("dirt", 0.5)), "what": str(o.get("what", "wall")), "faces": 55, "layer": str(o.get("layer", "ext"))}
			if o.has("tint"):
				opt.tint = o.tint
				opt.paint = float(o.get("paint", 0.85))
			if o.has("phys"):
				opt.phys = o.phys
			ctx.sink.box(xf * Transform3D(basis, Vector3(a.x, y, a.y) + along * ((s0 + e) * 0.5) + Vector3.UP * (h * 0.5)), Vector3(e - s0, h, t), mat, opt)
		s0 = maxf(s0, clampf(float(cu[1]), 0.0, length))


func column(xf: Transform3D, p: Vector2, y0: float, y1: float, size: float, mat: String, o: Dictionary = {}) -> void:
	## A square post from local height y0 to y1 at local p.
	var opt := {"dirt": float(o.get("dirt", 0.4)), "what": "column", "layer": str(o.get("layer", "ext"))}
	if o.has("tint"):
		opt.tint = o.tint
		opt.paint = 0.8
	ctx.sink.box(xf * Transform3D(Basis(), Vector3(p.x, (y0 + y1) * 0.5, p.y)), Vector3(size, y1 - y0, size), mat, opt)


func ladder_at(xf: Transform3D, lx: float, d: float, top_y_local: float, ground_y: float, dirt: float = 0.5) -> void:
	## Public wrapper of the shanty ladder: up the local front wall (-z) at local x lx; turn xf to put it on another
	## wall. Registers it in ladders (the climbing movement) with a clearance at its foot.
	_ladder(xf, lx, d, top_y_local, ground_y, dirt)
