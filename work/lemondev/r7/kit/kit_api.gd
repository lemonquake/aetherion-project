

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
			ctx.sink.box(xf * Transform3D(basis, c + along * (hw * 0.5 + 0.025) * sx), Vector3(0.05, hh + 0.05, t + 0.03), fmat, fopt)
		ctx.sink.box(xf * Transform3D(basis, c + Vector3.UP * (hh * 0.5 + 0.025)), Vector3(hw + 0.1, 0.05, t + 0.03), fmat, fopt)
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
			var opt := {"layer": str(o.get("layer", "inner")), "dirt": float(o.get("dirt", 0.3)), "what": str(o.get("what", "slab")),
				"collide": bool(o.get("collide", true)), "faces": int(o.get("faces", 63)), "inner_faces": int(o.get("inner_faces", 0))}
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
