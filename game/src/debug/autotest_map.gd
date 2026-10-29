extends RefCounted
## --autotest=mapscan: sweeps the whole map for places a player cannot go and things that look wrong, with physics
## queries against the built map (no sampling of a few houses: every door, doorway, stair, ladder, lane and prop).
##   godot --path game -- --host --bots=0 --autostart=1 --autotest=mapscan --shots=<dir> --port=<p> [--seed=N]
##     [--map_only=doors,ways,stairs,ladders,lanes,props,faces,views] [--map_views=<views.json from an earlier run>]
##
## - Doors and doorways: a character-sized capsule (radius 0.3 m, from 0.3 m above the floor - the step-up climbs
##   0.36 m - to 1.8 m) is swept through the opening in both directions, following the floor, with the leaf out of
##   the way; whatever stops it is named from the collision box it belongs to (wall, partition, static furniture,
##   loot box, crate, terrain...). Doors are also swung both ways through 90 degrees: what stops the leaf.
## - Stairs (foot, flight headroom, landing), ladders (foot and the deck where you step off), lanes (a capsule must
##   fit somewhere across the lane every metre), props, loot boxes and ground items (floating, sunk, inside a wall).
## - See-through: rays against the drawn geometry only, front faces only (what back-face culling shows), from inside
##   every room and from outside every wall, compared with physics rays: a solid wall with no face drawn toward the
##   viewer, and gaps through which a room sees the sky (not through a window or door).
## Logs to <shots>/mapscan.log and mapscan.json; captures of examples by day and by night.

const R := 0.3
const LIFT := 0.3
const TOP := 1.8
const HEAVY := 6.0
## Architecture that must be drawn from every side it can be seen from.
const SOLID_ARCH := ["wall", "partition", "partition_lintel", "cr_wall", "parapet", "floor_slab", "upper_floor", "deck", "roof_gable", "low_wall"]
const WALLISH := ["wall", "partition", "partition_lintel", "cr_wall", "parapet", "low_wall", "stilt"]

var t = null
var world = null
var map = null
var dyn = null
var sink = null
var space: PhysicsDirectSpaceState3D
var out_dir := ""
var lines: PackedStringArray = []
var data := {}
var cap := CapsuleShape3D.new()
var views: Array = []      # captures to take: {name, pos, look}


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func _log(s: String) -> void:
	lines.append(s)
	print("[mapscan] " + s)


func run() -> void:
	map = world.map
	dyn = map.dyn
	sink = map.sink
	out_dir = t.out_dir
	space = world.get_world_3d().direct_space_state
	cap.radius = R
	cap.height = TOP - LIFT
	for i in 3:
		await t.get_tree().physics_frame
	var only := str(Game.arg("map_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	_log("map %s, seed %s, %d collision boxes recorded" % [map.fingerprint, str(Net.config.get("map_seed", "?")), sink.rec.size()])
	for nm in ["cabinet_paint", "cabinet_paint2", "nightstand", "school_desk", "old_tyre", "drum_blue", "Barrel_01", "bottle", "tricycle_a", "food_cart_a"]:
		var md: Dictionary = map.models.get_model(nm)
		if not md.is_empty():
			_log("model %s bounds %s" % [nm, str(md.aabb)])
	if sink.rec.is_empty():
		t._check("mapscan_record", false, "collision boxes were not recorded (map built without --autotest=mapscan)")
		return
	var t0 := Time.get_ticks_msec()
	if want.call("doors"):
		_scan_doors()
	if want.call("ways"):
		_scan_doorways()
	if want.call("stairs"):
		_scan_stairs()
	if want.call("ladders"):
		_scan_ladders()
	if want.call("lanes"):
		_scan_lanes()
	if want.call("props"):
		_scan_props()
	if want.call("faces"):
		await _scan_faces()
	_log("scan took %d ms" % (Time.get_ticks_msec() - t0))
	if want.call("views"):
		await _captures()
	_write()


# ------------------------------------------------------------------ naming what is hit

func _obj_label(c) -> String:
	if c == null:
		return ""
	if c.has_meta("prop_id"):
		var p: Dictionary = dyn.props[int(c.get_meta("prop_id"))]
		var mass := float(map.models.spec(str(p.name)).get("mass", 99.0))
		return ("prop:" if mass >= HEAVY else "light_prop:") + str(p.name)
	if c.has_meta("door_id"):
		return "door_leaf"
	if c.has_meta("shutter_id"):
		return "shutter"
	if c.has_meta("window_id"):
		return "glass"
	if c is Node and str((c as Node).name) == "Terrain":
		return "terrain"
	if c is RigidBody3D:
		return "loose_prop"
	return ""


func _what_at(p: Vector3) -> String:
	var hits: Array = sink.recorded_at(p, 0.05)
	if hits.is_empty():
		return "unrecorded"
	return str(hits[0][2])


func _what_strict(p: Vector3) -> String:
	## Only a box the point is on (1 cm), so a hit on a shutter or a window's glass beside a wall is not the wall.
	var hits: Array = sink.recorded_at(p, 0.01)
	return "unrecorded" if hits.is_empty() else str(hits[0][2])


func _hits(xf: Transform3D, shape: Shape3D, exclude: Array, mask: int = Defs.MOVE_MASK) -> Array:
	## Everything the shape overlaps at xf: [{what, pos, hard}].
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = xf
	q.collision_mask = mask
	q.exclude = exclude
	var res := space.intersect_shape(q, 16)
	if res.is_empty():
		return []
	var out := []
	var seen := {}
	var need_pts := false
	for r in res:
		var lab := _obj_label(r.collider)
		if lab == "":
			need_pts = true
			continue
		if seen.has(lab):
			continue
		seen[lab] = true
		out.append({"what": lab, "pos": xf.origin, "hard": not lab.begins_with("light_prop:")})
	if need_pts:
		var pts := space.collide_shape(q, 24)
		for i in range(1, pts.size(), 2):
			var p: Vector3 = pts[i]
			var lab2 := _what_at(p)
			if lab2 == "unrecorded":
				# A dormant prop or terrain already named above, or something made without a recorded box.
				if not out.is_empty():
					continue
				if absf(p.y - map.ground_height(p.x, p.z)) < 0.15:
					lab2 = "terrain"
			if seen.has(lab2):
				continue
			seen[lab2] = true
			out.append({"what": lab2, "pos": p, "hard": true})
	return out


func _floor_at(p: Vector3, y_ref: float, above: float = 0.4, below: float = 0.6) -> float:
	## Highest walkable surface within [y_ref - below, y_ref + above] under p (NAN if none: a drop or water).
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y_ref + above, p.z), Vector3(p.x, y_ref - below, p.z), Defs.PHYS_WORLD)
	var r := space.intersect_ray(q)
	if r.is_empty():
		return NAN
	return (r.position as Vector3).y


func _cap_xf(foot: Vector3) -> Transform3D:
	return Transform3D(Basis(), foot + Vector3.UP * (LIFT + (TOP - LIFT) * 0.5))


func _sweep(mid: Vector3, nrm: Vector3, d_neg: float, d_pos: float, exclude: Array) -> Dictionary:
	## Capsule through an opening along nrm, from mid - nrm*d_neg to mid + nrm*d_pos, riding the floor: forward and
	## back. Returns {ok, blockers: [{what, pos, hard}], drop: [side], soft: [..]}.
	var pts := []
	var drop := []
	var gaps := {"+": 0, "-": 0}
	var n := maxi(int(ceil((d_neg + d_pos) / 0.08)), 2)
	for i in n + 1:
		var s := -d_neg + (d_neg + d_pos) * float(i) / n
		var p := mid + nrm * s
		var fy := _floor_at(p, mid.y)
		if is_nan(fy):
			if absf(s) > 0.12:
				gaps["+" if s > 0.0 else "-"] += 1
			fy = mid.y
		pts.append(Vector3(p.x, fy, p.z))
	for side in gaps:
		if int(gaps[side]) >= 4:
			drop.append(side)
	var blockers := []
	var seen := {}
	var moved_ok := true
	for dirn in [1, -1]:
		var order := range(pts.size()) if dirn == 1 else range(pts.size() - 1, -1, -1)
		var prev = null
		for i in order:
			var cur: Vector3 = pts[i]
			if prev != null:
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = cap
				q.transform = _cap_xf(prev)
				q.motion = cur - (prev as Vector3)
				q.collision_mask = Defs.MOVE_MASK
				q.exclude = exclude
				var cm := space.cast_motion(q)
				if cm.size() == 2 and float(cm[0]) < 1.0:
					moved_ok = false
			prev = cur
	for p in pts:
		for h in _hits(_cap_xf(p), cap, exclude):
			var key := str(h.what)
			if seen.has(key):
				continue
			seen[key] = true
			blockers.append(h)
	var hard := blockers.filter(func(b): return b.hard)
	var soft := blockers.filter(func(b): return not b.hard)
	# Blocked: something solid in the way, or the capsule stopped with nothing but a pushable prop to show for it.
	return {"blocked": not hard.is_empty() or (not moved_ok and soft.is_empty()), "moved": moved_ok, "blockers": blockers, "hard": hard, "drop": drop}


# ------------------------------------------------------------------ bookkeeping

func _count(cat: String, what: String = "", example: String = "") -> void:
	if not data.has(cat):
		data[cat] = {"n": 0, "what": {}, "examples": []}
	var e: Dictionary = data[cat]
	e.n = int(e.n) + 1
	if what != "":
		e.what[what] = int(e.what.get(what, 0)) + 1
	if example != "" and (e.examples as Array).size() < 14:
		(e.examples as Array).append(example)


func _n(cat: String) -> int:
	return int(data.get(cat, {}).get("n", 0))


func _v(p: Vector3) -> String:
	return "(%.1f, %.2f, %.1f)" % [p.x, p.y, p.z]


func _whats(arr: Array) -> String:
	var s := []
	for b in arr:
		s.append("%s@%s" % [b.what, _v(b.pos)])
	return ", ".join(s)


# ------------------------------------------------------------------ doors

func _scan_doors() -> void:
	var total := 0
	var by_role := {}
	var dist := {}
	for b in map.buildings:
		dist[int(b.id)] = "%s/%s" % [str(b.kind), str(b.district)]
	for d in dyn.doors:
		var dn = d.get("node")
		if dn == null or dn.destroyed:
			continue
		total += 1
		var role := str(d.get("role", "outer" if d.get("outer", false) else "inner"))
		by_role[role] = int(by_role.get(role, 0)) + 1
		var xf: Transform3D = dn.base
		var nrm := xf.basis.z.normalized()
		var mid: Vector3 = xf * Vector3(dn.w * 0.5, 0.0, 0.0)
		var clr: Vector2 = d.get("clr", Vector2(1.0, 1.0))
		var res := _sweep(mid, nrm, clampf(clr.x - 0.1, 0.35, 0.75), clampf(clr.y - 0.1, 0.35, 0.75), [dn.body])
		var tag := "door %d (%s, building %d %s) at %s" % [int(d.id), role, int(d.get("bid", -1)), str(dist.get(int(d.get("bid", -1)), "?")), _v(mid)]
		if res.blocked:
			_count("door_blocked", "", "%s: %s%s" % [tag, _whats(res.hard), "" if res.moved else " (capsule stopped)"])
			for b in res.hard:
				_count("door_blocked_by", str(b.what))
			if (res.hard as Array).is_empty():
				_count("door_blocked_by", "unnamed")
			if views.size() < 40:
				views.append({"name": "door%d" % int(d.id), "pos": mid - nrm * 1.6 + Vector3.UP * 1.6, "look": mid + Vector3.UP * 0.9, "kind": "door"})
		var soft: Array = (res.blockers as Array).filter(func(b): return not b.hard)
		if not soft.is_empty():
			_count("door_light_props", "", "%s: %s" % [tag, _whats(soft)])
		for side in res.drop:
			var probe: Vector3 = mid + nrm * (0.6 if side == "+" else -0.6)
			var deep := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 0.3, probe + Vector3.DOWN * 8.0, Defs.PHYS_WORLD))
			var depth := "%.1f m down to %s" % [mid.y - (deep.position as Vector3).y, _what_at(deep.position)] if not deep.is_empty() else "nothing within 8 m"
			var water := " over water" if map.layout.is_water(probe.x, probe.z) else ""
			_count("door_drop", role, "%s: no floor within 0.6 m on the %s side (%s%s)" % [tag, side, depth, water])
			if views.filter(func(v): return v.kind == "drop").size() < 4:
				views.append({"name": "drop%d" % int(d.id), "pos": mid + nrm * (2.2 if side == "+" else -2.2) + Vector3.UP * 1.4, "look": mid + Vector3.UP * 0.6, "kind": "drop"})
		# The leaf through 90 degrees each way (starting 12 cm off the hinge: the frame and the jamb are not obstacles).
		for sgn in [1.0, -1.0]:
			var stop := _swing_stop(dn, sgn)
			if not stop.is_empty():
				_count("door_swing_blocked", "", "%s swinging %s: %s at %.0f deg" % [tag, "+" if sgn > 0 else "-", stop.what, rad_to_deg(float(stop.angle))])
				_count("door_swing_blocked_by", str(stop.what))
	_log("doors: %d (%s)" % [total, JSON.stringify(by_role)])
	data["doors_total"] = total


func _swing_stop(dn, sgn: float) -> Dictionary:
	var bs := BoxShape3D.new()
	var lw: float = dn.w - 0.15
	bs.size = Vector3(lw, dn.h - 0.15, dn.t + 0.02)
	for k in range(1, 12):
		var a := 1.57 * sgn * k / 11.0
		var xf: Transform3D = dn.base * Transform3D(Basis(Vector3.UP, a), Vector3.ZERO) * Transform3D(Basis(), Vector3(0.12 + lw * 0.5, (dn.h + 0.05) * 0.5, 0))
		for h in _hits(xf, bs, [dn.body], Defs.MOVE_MASK):
			if h.hard:
				if absf(a) < 1.31:
					return {"what": h.what, "angle": a}
				return {}
	return {}


# ------------------------------------------------------------------ doorways without a leaf

func _scan_doorways() -> void:
	var total := 0
	for w in dyn.doorways:
		total += 1
		var mid: Vector3 = w.c
		var nrm: Vector3 = w.n
		var clr: Vector2 = w.get("clr", Vector2(1.0, 1.0))
		var res := _sweep(mid, nrm, clampf(clr.x - 0.1, 0.35, 0.75), clampf(clr.y - 0.1, 0.35, 0.75), [])
		var tag := "doorway %d (%s, building %d) at %s" % [int(w.id), str(w.kind), int(w.bid), _v(mid)]
		if res.blocked:
			_count("doorway_blocked", "", "%s: %s%s" % [tag, _whats(res.hard), "" if res.moved else " (capsule stopped)"])
			for b in res.hard:
				_count("doorway_blocked_by", str(b.what))
			if (res.hard as Array).is_empty():
				_count("doorway_blocked_by", "unnamed")
			if views.size() < 40:
				views.append({"name": "way%d" % int(w.id), "pos": mid - nrm * 1.6 + Vector3.UP * 1.6, "look": mid + Vector3.UP * 0.9, "kind": "doorway"})
		var soft: Array = (res.blockers as Array).filter(func(b): return not b.hard)
		if not soft.is_empty():
			_count("doorway_light_props", "", "%s: %s" % [tag, _whats(soft)])
		for side in res.drop:
			_count("doorway_drop", str(w.kind), "%s: no floor on the %s side" % [tag, side])
	data["doorways_total"] = total
	_log("doorways: %d" % total)


# ------------------------------------------------------------------ stairs and ladders

func _scan_stairs() -> void:
	var total := 0
	var c := CapsuleShape3D.new()
	c.radius = R
	for f in map.stairs:
		total += 1
		var foot: Vector3 = f.foot
		var top: Vector3 = f.top
		var tag := "flight at %s" % _v(foot)
		# Where a player stands to step on: just short of the first tread (a little off the side wall if need be).
		var hf := []
		if f.has("start"):
			var st: Vector3 = (f.start as Vector3) - (f.dir as Vector3).normalized() * (R + 0.04)
			var sd: Vector3 = f.get("side", Vector3.ZERO)
			for off in [0.0, 0.05, 0.1]:
				var sp: Vector3 = st + sd * off
				var fy := _floor_at(sp, foot.y)
				hf = _hits(_cap_xf(Vector3(sp.x, fy if not is_nan(fy) else foot.y, sp.z)), cap, []).filter(func(b): return b.hard and b.what != "stair_ramp")
				if hf.is_empty():
					break
		if not hf.is_empty():
			_count("stair_foot_blocked", "", "%s: %s" % [tag, _whats(hf)])
			for b in hf:
				_count("stair_blocked_by", "foot:" + str(b.what))
		if f.has("run"):
			var dir: Vector3 = f.dir
			var side: Vector3 = f.get("side", Vector3.ZERO)
			var start: Vector3 = f.start
			var run := float(f.run)
			var rise := float(f.rise)
			c.height = 1.65
			for s in [0.15, 0.35, 0.55, 0.75]:
				var best := []
				var clear := false
				for off in [0.0, 0.05, -0.05, 0.1, -0.1]:
					var p: Vector3 = start + dir.normalized() * run * s + side * off
					var y = start.y + rise * s
					var xf := Transform3D(Basis(), Vector3(p.x, y + 0.2 + c.height * 0.5, p.z))
					var hh := _hits(xf, c, []).filter(func(b): return b.hard and b.what != "stair_ramp")
					if hh.is_empty():
						clear = true
						break
					if best.is_empty():
						best = hh
				if not clear:
					_count("stair_flight_blocked", "", "%s at %.0f%% of the flight: %s" % [tag, s * 100.0, _whats(best)])
					for b in best:
						_count("stair_blocked_by", "flight:" + str(b.what))
					break
		var ty := _floor_at(top, top.y)
		if is_nan(ty):
			_count("stair_top_no_floor", "", "%s: no floor at the landing %s" % [tag, _v(top)])
		else:
			var ht := _hits(_cap_xf(Vector3(top.x, ty, top.z)), cap, []).filter(func(b): return b.hard and b.what != "stair_ramp")
			if not ht.is_empty():
				_count("stair_top_blocked", "", "%s: landing %s: %s" % [tag, _v(top), _whats(ht)])
				for b in ht:
					_count("stair_blocked_by", "top:" + str(b.what))
				if views.size() < 60:
					views.append({"name": "stairtop%d" % total, "pos": top + Vector3.UP * 1.6 - (f.dir as Vector3) * 0.2, "look": top + Vector3.UP * 0.5 + (f.dir as Vector3) * 0.3, "kind": "stair"})
	data["stairs_total"] = total
	_log("stairs: %d flights" % total)


func _scan_ladders() -> void:
	var total := 0
	for ld in map.ladders:
		total += 1
		var base: Vector3 = ld.base
		var n: Vector3 = ld.n
		var tag := "ladder at %s" % _v(base)
		var fy := _floor_at(base + n * 0.1, base.y, 0.5, 1.0)
		if is_nan(fy):
			_count("ladder_foot_no_ground", "", tag)
		else:
			var hb := _hits(_cap_xf(Vector3(base.x, fy, base.z) + n * 0.1), cap, []).filter(func(b): return b.hard)
			if not hb.is_empty():
				_count("ladder_foot_blocked", "", "%s: %s" % [tag, _whats(hb)])
		# Off at the top: a step over the parapet gap on to the deck.
		var exit: Vector3 = Vector3(base.x, float(ld.top_y), base.z) - n * 1.1
		var ty := _floor_at(exit, float(ld.top_y) + 0.15, 0.4, 0.4)
		if is_nan(ty):
			_count("ladder_top_no_deck", "", "%s: nothing to step on at %s" % [tag, _v(exit)])
		else:
			var ht := _hits(_cap_xf(Vector3(exit.x, ty, exit.z)), cap, []).filter(func(b): return b.hard)
			if not ht.is_empty():
				_count("ladder_top_blocked", "", "%s: %s" % [tag, _whats(ht)])
	data["ladders_total"] = total
	_log("ladders: %d" % total)


# ------------------------------------------------------------------ lanes

func _scan_lanes() -> void:
	var samples := 0
	var lanes := 0
	for a in map.alleys:
		if str(a.kind) == "looban":
			continue
		lanes += 1
		var pa: Vector2 = a.a
		var pb: Vector2 = a.b
		var len := pa.distance_to(pb)
		if len < 1.0:
			continue
		var dir := (pb - pa) / len
		var side := Vector2(-dir.y, dir.x)
		var w := float(a.w)
		var half_free := maxf(w * 0.5 - R - 0.02, 0.0)
		var in_block := false
		var block_start := 0.0
		var block_what := {}
		var s := 0.5
		while s < len - 0.5:
			var p := pa + dir * s
			s += 1.0
			if map.layout.is_water(p.x, p.y) and not a.has("y"):
				continue
			samples += 1
			var y_ref: float = float(a.y) if a.has("y") else map.ground_height(p.x, p.y)
			var clear := false
			var first := []
			var off := -half_free
			while off <= half_free + 0.001:
				var q := p + side * off
				off += 0.1
				var fy := _floor_at(Vector3(q.x, 0, q.y), y_ref, 0.5, 0.8)
				if is_nan(fy):
					continue
				var hh := _hits(_cap_xf(Vector3(q.x, fy, q.y)), cap, []).filter(func(b): return b.hard)
				if hh.is_empty():
					clear = true
					break
				if first.is_empty():
					first = hh
			if not clear:
				if not in_block:
					in_block = true
					block_start = s - 1.0
					block_what = {}
				for b in first:
					block_what[str(b.what)] = true
			elif in_block:
				in_block = false
				_lane_block(a, pa + dir * block_start, s - 1.0 - block_start, block_what)
		if in_block:
			_lane_block(a, pa + dir * block_start, len - block_start, block_what)
	data["lanes_total"] = lanes
	data["lane_samples"] = samples
	_log("lanes: %d, %d samples" % [lanes, samples])


func _lane_block(a: Dictionary, p: Vector2, length: float, what: Dictionary) -> void:
	var names: Array = what.keys()
	var intentional := names.size() > 0 and names.all(func(x): return str(x) in ["barricade", "crate"])
	var cat := "lane_barricade" if intentional else "lane_blocked"
	_count(cat, "", "%s lane w %.1f at (%.1f, %.1f), %.0f m: %s" % [str(a.kind), float(a.w), p.x, p.y, maxf(length, 1.0), ", ".join(names)])
	if not intentional and views.filter(func(v): return v.kind == "lane").size() < 4:
		var pa: Vector2 = a.a
		var pb: Vector2 = a.b
		var dirl := (pb - pa).normalized()
		var gy: float = map.ground_height(p.x, p.y)
		views.append({"name": "lane_%d_%d" % [int(p.x), int(p.y)], "pos": Vector3(p.x - dirl.x * 4.0, gy + 1.7, p.y - dirl.y * 4.0), "look": Vector3(p.x, gy + 0.8, p.y), "kind": "lane"})
	if not intentional:
		for x in names:
			_count("lane_blocked_by", str(x))


# ------------------------------------------------------------------ props, loot boxes, ground items

var _sunk_by := 0.0
var _sunk_in := ""
var _support_what := ""


func _line_span(e: Array, x: float, z: float) -> Vector2:
	## Where the vertical line through (x, z) is inside a recorded box: (y in, y out), or (INF, -INF).
	var inv: Transform3D = (e[0] as Transform3D).affine_inverse()
	var o: Vector3 = inv * Vector3(x, 0.0, z)
	var dl: Vector3 = inv.basis * Vector3.UP
	var h: Vector3 = (e[1] as Vector3) * 0.5
	var lo := -INF
	var hi := INF
	for i in 3:
		if absf(dl[i]) < 1e-6:
			if absf(o[i]) > h[i]:
				return Vector2(INF, -INF)
			continue
		var t0: float = (-h[i] - o[i]) / dl[i]
		var t1: float = (h[i] - o[i]) / dl[i]
		lo = maxf(lo, minf(t0, t1))
		hi = minf(hi, maxf(t0, t1))
	return Vector2(lo, hi) if lo <= hi else Vector2(INF, -INF)


func _terrain_y(x: float, z: float) -> float:
	## The ground as drawn: the 2 m height grid split into triangles the way the terrain mesh splits it.
	var L = map.layout
	var half: float = L.HALF
	var fx := (x + half) / 2.0
	var fz := (z + half) / 2.0
	var ix := floori(fx)
	var iz := floori(fz)
	var u := fx - ix
	var v := fz - iz
	var x0 := -half + ix * 2.0
	var z0 := -half + iz * 2.0
	var h00: float = L.ground_height(x0, z0)
	var h10: float = L.ground_height(x0 + 2.0, z0)
	var h01: float = L.ground_height(x0, z0 + 2.0)
	if u + v <= 1.0:
		return h00 + (h10 - h00) * u + (h01 - h00) * v
	var h11: float = L.ground_height(x0 + 2.0, z0 + 2.0)
	return h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)


func _support(top: Vector3, bottom_y: float, exclude: Array, own: String, own_c: Vector3) -> float:
	## The highest surface under (x, z) from 1.5 m below the bottom up to 0.35 m above it (NAN if none): recorded
	## collision boxes other than the thing's own, the ground as drawn, and resting props. Also notes in _sunk_by
	## how far the bottom is inside a floor, a slab or another box (not walls: those are the in-wall check).
	var x := top.x
	var z := top.z
	var lim := bottom_y + 0.35
	var best := -INF
	_sunk_by = 0.0
	_sunk_in = ""
	for e in sink.recorded_near(Vector3(x, 0.0, z)):
		var lab := str(e[2])
		if own != "" and lab == own and ((e[0] as Transform3D).origin - own_c).length() < 0.8:
			continue
		var sp := _line_span(e, x, z)
		if sp.x > sp.y:
			continue
		if sp.y <= lim:
			if sp.y > best:
				best = sp.y
				_support_what = lab
		elif sp.x < bottom_y - 0.02 and not lab in WALLISH and sp.y - bottom_y > _sunk_by:
			_sunk_by = minf(sp.y, lim) - bottom_y
			_sunk_in = "%s (box at %s, %s)" % [lab, _v((e[0] as Transform3D).origin), str((e[1] as Vector3).snapped(Vector3.ONE * 0.01))]
	if not map.layout.is_water(x, z):
		var gy := _terrain_y(x, z)
		if gy <= lim and gy > best:
			best = gy
			_support_what = "terrain"
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, lim, z), Vector3(x, bottom_y - 1.5, z), Defs.PHYS_PROP)
	q.exclude = exclude
	var r := space.intersect_ray(q)
	if not r.is_empty() and (r.position as Vector3).y > best:
		best = (r.position as Vector3).y
		_support_what = _obj_label(r.collider)
	if best < bottom_y - 1.5:
		return NAN
	return best


func _in_wall(pts: Array) -> String:
	for p in pts:
		for e in sink.recorded_at(p, -0.03):
			if str(e[2]) in WALLISH:
				return str(e[2])
	return ""


func _scan_props() -> void:
	var n := 0
	for p in dyn.props:
		if str(p.get("state", "")) != "dormant":
			continue
		n += 1
		var md: Dictionary = map.models.get_model(str(p.name))
		if md.is_empty():
			continue
		var xf: Transform3D = p.xf
		var a: AABB = md.aabb
		var off: Vector3 = md.get("offset", Vector3.ZERO)
		var lc := a.get_center()
		var bottom: Vector3 = xf * Vector3(lc.x, a.position.y, lc.z)
		_prop_check("prop", str(p.name), xf, a, off, bottom, [p.rid], "")
	for sp in dyn.static_props:
		var name := str(sp[0])
		var md2: Dictionary = map.models.get_model(name)
		var s: Dictionary = map.models.spec(name)
		if md2.is_empty() or s.get("no_collide", false) or s.has("trunk"):
			continue
		n += 1
		var xf2: Transform3D = sp[1]
		var a2: AABB = md2.aabb
		var off2: Vector3 = md2.get("offset", Vector3.ZERO)
		var lc2 := a2.get_center()
		_prop_check("static", name, xf2, a2, off2, xf2 * Vector3(lc2.x, a2.position.y, lc2.z), [], "static:" + name)
	for b in dyn.loot_boxes:
		var name3 := str(b.name)
		var md3: Dictionary = map.models.get_model(name3)
		if md3.is_empty():
			continue
		n += 1
		var xf3: Transform3D = b.xf
		var a3: AABB = md3.aabb
		var off3: Vector3 = md3.get("offset", Vector3.ZERO)
		var lc3 := a3.get_center()
		_prop_check("lootbox", name3, xf3, a3, off3, xf3 * Vector3(lc3.x, a3.position.y, lc3.z), [], "lootbox:" + name3)
	var items := 0
	for id in dyn.items:
		var it: Dictionary = dyn.items[id]
		var ixf: Transform3D = it.xf
		var o := ixf.origin
		items += 1
		var sy := _support(o, o.y, [], "", Vector3.ZERO)
		var tag := "item %s at %s" % [str(it.entry.id), _v(o)]
		if is_nan(sy) or o.y - sy > 0.08:
			_count("item_floating", "", "%s, %s" % [tag, "nothing below" if is_nan(sy) else "%.2f m above the surface" % (o.y - sy)])
		elif sy - o.y > 0.06 or _sunk_by > 0.06:
			_count("item_sunk", "", "%s: %.2f m under the surface (%s)" % [tag, maxf(sy - o.y, _sunk_by), _sunk_in])
		var w := _in_wall([o + Vector3.UP * 0.05])
		if w != "":
			_count("item_in_wall", w, tag)
	data["props_checked"] = n
	data["items_checked"] = items
	_log("props/static/loot boxes checked: %d, ground items: %d" % [n, items])


func _prop_check(kind: String, name: String, xf: Transform3D, a: AABB, off: Vector3, bottom: Vector3, exclude: Array, own: String) -> void:
	## The model's bounds (md.aabb) are where it is drawn (a primitive's offset is already in them).
	var lc := a.get_center()
	var tag := "%s %s at %s" % [kind, name, _v(bottom)]
	if xf.basis.y.normalized().y < 0.995:
		# Tilted (a toppled tricycle, a weight on a sloping roof): its lowest bottom corner must rest on something.
		var low := Vector3(0, INF, 0)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var cp: Vector3 = xf * Vector3(lc.x + a.size.x * 0.45 * sx, a.position.y, lc.z + a.size.z * 0.45 * sz)
				if cp.y < low.y:
					low = cp
		var sy2 := _support(low, low.y, exclude, own, xf * lc)
		if is_nan(sy2) or low.y - sy2 > 0.08:
			_count(kind + "_floating", name, "%s (tilted), %s" % [tag, "nothing below within 1.5 m" if is_nan(sy2) else "lowest corner %.2f m above the surface" % (low.y - sy2)])
	else:
		_support_check(kind, name, tag, bottom, exclude, own, xf * lc)
	# Inside a wall: the centre and the four corners pulled 35% in, at mid height.
	var h := a.size * 0.5 * 0.65
	var pts := [xf * lc]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pts.append(xf * (lc + Vector3(h.x * sx, 0.0, h.z * sz)))
	var w := _in_wall(pts)
	if w != "":
		_count(kind + "_in_wall", w, "%s inside a %s" % [tag, w])


func _support_check(kind: String, name: String, tag: String, bottom: Vector3, exclude: Array, own: String, own_c: Vector3) -> void:
	var sy := _support(bottom, bottom.y, exclude, own, own_c)
	if map.layout.is_water(bottom.x, bottom.z) and absf(bottom.y - float(map.layout.WATER_Y)) < 1.0 and (is_nan(sy) or sy < bottom.y):
		return   # afloat (boats, rubbish on the water)
	if is_nan(sy) or bottom.y - sy > 0.08:
		_count(kind + "_floating", name, "%s, %s" % [tag, "nothing below within 1.5 m" if is_nan(sy) else "%.2f m above the surface" % (bottom.y - sy)])
	elif sy - bottom.y > 0.08 or _sunk_by > 0.08:
		_count(kind + "_sunk", name, "%s: %.2f m into %s" % [tag, maxf(sy - bottom.y, _sunk_by), _sunk_in if _sunk_by > sy - bottom.y else _support_what])


# ------------------------------------------------------------------ see-through faces

var _vspace := RID()
var _vbodies: Array = []
var _vshapes: Array = []


func _build_visual(reverse: bool) -> int:
	## A physics space holding the drawn architecture only (batched near meshes: exteriors, inside faces, interiors),
	## as one-sided triangles in their drawn winding.
	_free_visual(false)
	if not _vspace.is_valid():
		_vspace = PhysicsServer3D.space_create()
		PhysicsServer3D.space_set_active(_vspace, true)
	var tris := 0
	for chunk in map.root.get_children():
		if not str(chunk.name).begins_with("Chunk_"):
			continue
		for mi in chunk.get_children():
			if not (mi is MeshInstance3D):
				continue
			var m := mi as MeshInstance3D
			if m.visibility_range_begin > 0.0 or is_equal_approx(m.visibility_range_end, 140.0) or m.mesh == null:
				continue   # far stand-ins and the "mid" layer (decals, wires, washing)
			var mat := m.mesh.surface_get_material(0)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			var faces: PackedVector3Array = m.mesh.get_faces()
			if faces.is_empty():
				continue
			if reverse:
				for i in range(0, faces.size(), 3):
					var tmp := faces[i + 1]
					faces[i + 1] = faces[i + 2]
					faces[i + 2] = tmp
			# One body per mesh: a single body holding thousands of big mesh shapes is never hit by a ray in Jolt.
			var sh := PhysicsServer3D.concave_polygon_shape_create()
			PhysicsServer3D.shape_set_data(sh, {"faces": faces, "backface_collision": false})
			var body := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
			PhysicsServer3D.body_set_space(body, _vspace)
			PhysicsServer3D.body_add_shape(body, sh, Transform3D())
			PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, m.global_transform)
			_vbodies.append(body)
			_vshapes.append(sh)
			tris += faces.size() / 3
	return tris


func _vray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.hit_back_faces = false
	q.hit_from_inside = false
	return PhysicsServer3D.space_get_direct_state(_vspace).intersect_ray(q)


func _pray(from: Vector3, to: Vector3) -> Dictionary:
	## Physics ray against the built walls (doors, glass and props ignored).
	var q := PhysicsRayQueryParameters3D.create(from, to, Defs.PHYS_WORLD)
	var ex := []
	for k in 4:
		q.exclude = ex
		var r := space.intersect_ray(q)
		if r.is_empty():
			return {}
		if r.collider != null and ((r.collider as Object).has_meta("door_id") or (r.collider as Object).has_meta("shutter_id")):
			ex.append(r.rid)
			continue
		return r
	return {}


func _calibrate() -> int:
	## Rays from 3 m outside ground-floor back walls straight at them: the drawn outer face must be hit about where
	## the physics wall is. Returns how many of the samples agree.
	var good := 0
	var n := 0
	for b in map.buildings:
		if n >= 40:
			break
		var xf: Transform3D = b.xf
		var w := float(b.w)
		var d := float(b.d)
		for lx in [-w * 0.3, w * 0.3]:
			var wall_p: Vector3 = xf * Vector3(lx, 1.3, d * 0.5)
			var out_p: Vector3 = xf * Vector3(lx, 1.3, d * 0.5 + 3.0)
			var pr := _pray(out_p, wall_p + (wall_p - out_p).normalized() * 0.5)
			if pr.is_empty() or _what_at(pr.position) != "wall":
				continue
			n += 1
			var vr := _vray(out_p, wall_p + (wall_p - out_p).normalized() * 0.5)
			if not vr.is_empty() and (vr.position as Vector3).distance_to(pr.position) < 0.1:
				good += 1
			elif n <= 3:
				_log("  calibration miss: physics %s at %s, drawn %s" % [_what_at(pr.position), _v(pr.position), "nothing" if vr.is_empty() else "%s n %s" % [_v(vr.position), str(vr.normal)]])
	_log("visual calibration: %d of %d back-wall rays hit the drawn outer face where the wall is" % [good, n])
	return good * 100 / maxi(n, 1)


func _openings_of(bid: int) -> Array:
	## [xf (centre, x along, y up, z through), half size] of every window, door and doorway of a building.
	var out := []
	for w in dyn.windows:
		if int(w.get("bid", -2)) == bid:
			out.append([w.xf, Vector2(float(w.w) * 0.5 + 0.08, float(w.h) * 0.5 + 0.08)])
	for d in dyn.doors:
		if int(d.get("bid", -2)) == bid:
			var xf: Transform3D = d.xf
			out.append([xf * Transform3D(Basis(), Vector3(float(d.w) * 0.5, float(d.h) * 0.5, 0)), Vector2(float(d.w) * 0.5 + 0.1, float(d.h) * 0.5 + 0.1)])
	for dw in dyn.doorways:
		if int(dw.bid) == bid:
			var u: Vector3 = dw.u
			var nn: Vector3 = dw.n
			var c: Vector3 = (dw.c as Vector3) + Vector3.UP * float(dw.h) * 0.5
			out.append([Transform3D(Basis(u, Vector3.UP, nn).orthonormalized(), c), Vector2(float(dw.w) * 0.5 + 0.1, float(dw.h) * 0.5 + 0.1)])
	return out


func _through_opening(from: Vector3, to: Vector3, ops: Array) -> bool:
	var dirv := to - from
	for o in ops:
		var oxf: Transform3D = o[0]
		var hs: Vector2 = o[1]
		var a: Vector3 = oxf.affine_inverse() * from
		var b: Vector3 = oxf.affine_inverse() * to
		if signf(a.z) == signf(b.z) and absf(a.z) > 0.3 and absf(b.z) > 0.3:
			continue
		var k := 0.5 if is_equal_approx(a.z, b.z) else clampf(-a.z / (b.z - a.z), 0.0, 1.0)
		var p := a.lerp(b, k)
		if absf(p.x) <= hs.x and absf(p.y) <= hs.y:
			return true
	return false


func _scan_faces() -> void:
	var t0 := Time.get_ticks_msec()
	var tris := _build_visual(false)
	for i in 3:
		await t.get_tree().physics_frame
	var cal := _calibrate()
	if cal < 50:
		_log("calibration %d%%: rebuilding with the other winding" % cal)
		tris = _build_visual(true)
		for i in 3:
			await t.get_tree().physics_frame
		cal = _calibrate()
	data["visual_tris"] = tris
	data["visual_calibration_pct"] = cal
	_log("visual space: %d triangles in %d ms" % [tris, Time.get_ticks_msec() - t0])
	var by_bid := {}
	for b in map.buildings:
		by_bid[int(b.id)] = b
	var leaky := {}
	var invisible := {}
	var rays := 0
	var dirs := []
	for el in [0.0, 22.0, 45.0, 68.0]:
		var n_az := 16 if el < 60.0 else 8
		for k in n_az:
			var az := TAU * k / n_az
			dirs.append(Vector3(cos(az) * cos(deg_to_rad(el)), sin(deg_to_rad(el)), sin(az) * cos(deg_to_rad(el))))
	dirs.append(Vector3.UP)
	for r in map.rooms:
		if str(r.type) == "cr":
			continue
		var bid := int(r.bid)
		var b: Dictionary = by_bid.get(bid, {})
		if b.is_empty():
			continue
		var bxf: Transform3D = b.xf
		var binv := bxf.affine_inverse()
		var hw := float(b.w) * 0.5
		var hd := float(b.d) * 0.5
		var ops := _openings_of(bid)
		var rxf: Transform3D = r.xf
		var h := float(r.h)
		for oy in [h * 0.5, h - 0.25]:
			var o: Vector3 = rxf.origin + Vector3.UP * oy
			var inside: Array = sink.recorded_at(o, -0.01)
			if not inside.is_empty():
				_count("room_centre_in_geometry", str(inside[0][2]), "building %d room %s: its middle %s is inside a %s" % [bid, str(r.type), _v(o), str(inside[0][2])])
				continue
			for dv in dirs:
				rays += 1
				var to: Vector3 = o + (dv as Vector3) * 12.0
				var vr := _vray(o, to)
				var pr := _pray(o, to)
				# 1. Solid architecture with no face drawn toward this room.
				if not pr.is_empty():
					var lab := _what_strict(pr.position)
					var dp := o.distance_to(pr.position)
					if lab in SOLID_ARCH and (vr.is_empty() or o.distance_to(vr.position) > dp + 0.15):
						var key := "%d|%s" % [bid, lab]
						if not invisible.has(key):
							invisible[key] = true
							_count("invisible_from_inside", lab, "building %d room %s: %s at %s has no face toward %s" % [bid, str(r.type), lab, _v(pr.position), _v(o)])
							if views.filter(func(v): return v.kind == "invisible").size() < 4:
								views.append({"name": "inv_b%d" % bid, "pos": o, "look": pr.position, "kind": "invisible"})
				# 2. Out of the house into daylight without a window or door: a gap.
				var hit_inside := false
				if not vr.is_empty():
					var lp: Vector3 = binv * (vr.position as Vector3)
					hit_inside = absf(lp.x) <= hw + 0.7 and lp.z >= -hd - 1.7 and lp.z <= hd + 0.7 and lp.y <= float(b.top) + 1.6
				if hit_inside:
					continue
				var end: Vector3 = vr.position if not vr.is_empty() else to
				if _through_opening(o, end, ops):
					continue
				# Where the ray left the room: through a wall band, over the wall top, or through the ceiling.
				var where := _exit_kind(rxf, r, o, dv)
				var key2 := "%d|%s" % [bid, where]
				if not leaky.has(key2):
					leaky[key2] = true
					_count("sky_gap", where, "building %d (%s, %s, %.1fx%.1f, top %.2f) room %s: ray %s from %s leaves through the %s; crosses the walls' line at house-local %s; drawn hit %s" % [bid, str(b.kind), str(b.style), float(b.w), float(b.d), float(b.top), str(r.type), _v(dv), _v(o), where, _v(_wall_cross(binv * o, binv.basis * (dv as Vector3), hw, hd)), "none" if vr.is_empty() else _v(binv * (vr.position as Vector3))])
					if views.filter(func(v): return v.kind == "gap").size() < 6:
						views.append({"name": "gap_b%d_%s" % [bid, where], "pos": o, "look": o + (dv as Vector3) * 3.0, "kind": "gap"})
	# From outside: every outer wall of every building, at chest height and under the eaves, from 2.5 m out.
	for b in map.buildings:
		var bxf2: Transform3D = b.xf
		var w := float(b.w)
		var d := float(b.d)
		var top_l := float(b.top)  # local: height of the top floor's ceiling (deck parapet included)
		for side in [[Vector3(0, 0, -1), w, d], [Vector3(0, 0, 1), w, d], [Vector3(-1, 0, 0), d, w], [Vector3(1, 0, 0), d, w]]:
			var nl: Vector3 = side[0]
			var along := Vector3(-nl.z, 0, nl.x)
			var length := float(side[1])
			var depth := float(side[2])
			for fa in [-0.3, 0.0, 0.3]:
				for yl in [1.2, top_l - 0.35]:
					var lp2: Vector3 = nl * (depth * 0.5) + along * (fa * length) + Vector3.UP * yl
					var wall_p: Vector3 = bxf2 * lp2
					var out_p: Vector3 = bxf2 * (lp2 + nl * 2.5)
					rays += 1
					var target := wall_p - (out_p - wall_p).normalized() * 0.6
					var pr2 := _pray(out_p, target)
					if pr2.is_empty():
						continue
					var dp2 := out_p.distance_to(pr2.position)
					if dp2 < 2.0:
						continue   # something stands in front (the next house): nowhere to look from
					var lab2 := _what_strict(pr2.position)
					if not lab2 in SOLID_ARCH:
						continue
					var vr2 := _vray(out_p, target)
					if vr2.is_empty() or out_p.distance_to(vr2.position) > dp2 + 0.15:
						var key3 := "%d|%s" % [int(b.id), lab2]
						if not invisible.has("o" + key3):
							invisible["o" + key3] = true
							_count("invisible_from_outside", lab2, "building %d: %s at %s has no face toward %s" % [int(b.id), lab2, _v(pr2.position), _v(out_p)])
							if views.filter(func(v): return v.kind == "invisible_out").size() < 4:
								views.append({"name": "invout_b%d" % int(b.id), "pos": out_p, "look": pr2.position, "kind": "invisible_out"})
	data["face_rays"] = rays
	data["buildings_with_sky_gap"] = _distinct_bids(leaky)
	_log("faces: %d rays; %d buildings with a gap to the outside, %d invisible solid faces" % [rays, data.buildings_with_sky_gap, invisible.size()])
	_free_visual(true)


func _free_visual(space_too: bool) -> void:
	for b in _vbodies:
		PhysicsServer3D.free_rid(b)
	for s in _vshapes:
		PhysicsServer3D.free_rid(s)
	_vbodies.clear()
	_vshapes.clear()
	if space_too and _vspace.is_valid():
		PhysicsServer3D.free_rid(_vspace)
		_vspace = RID()


func _wall_cross(a: Vector3, dl: Vector3, hw: float, hd: float) -> Vector3:
	## Where a ray from a (house-local) first reaches the house's outer wall line (|x| = hw or |z| = hd).
	var best := INF
	for ax in [0, 2]:
		var dd: float = dl[ax]
		if absf(dd) < 1e-5:
			continue
		var lim: float = hw if ax == 0 else hd
		var tt: float = (signf(dd) * lim - a[ax]) / dd
		if tt > 0.0 and tt < best:
			best = tt
	return a + dl * best if best < INF else a


func _distinct_bids(d: Dictionary) -> int:
	var s := {}
	for k in d:
		s[str(k).split("|")[0]] = true
	return s.size()


func _exit_kind(rxf: Transform3D, r: Dictionary, o: Vector3, dv: Vector3) -> String:
	var inv := rxf.affine_inverse()
	var a: Vector3 = inv * o
	var dl: Vector3 = inv.basis * dv
	var hs: Vector2 = (r.size as Vector2) * 0.5 + Vector2(0.15, 0.15)
	var h := float(r.h)
	var best := INF
	var kind := "wall"
	for ax in [0, 2]:
		var dd: float = dl[ax]
		if absf(dd) < 1e-5:
			continue
		var lim: float = hs.x if ax == 0 else hs.y
		var tt: float = (signf(dd) * lim - a[ax]) / dd
		if tt > 0.0 and tt < best:
			best = tt
			var y: float = a.y + dl.y * tt
			kind = "wall" if y < h - 0.05 else ("wall_top_gap" if y < h + 1.5 else "above_roof")
	if dl.y > 1e-5:
		var ty := (h + 0.05 - a.y) / dl.y
		if ty > 0.0 and ty < best:
			kind = "ceiling"
	return kind


# ------------------------------------------------------------------ captures

func _captures() -> void:
	var vfile := str(Game.arg("map_views", ""))
	var list: Array = []
	if vfile != "" and FileAccess.file_exists(vfile):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(vfile))
		if parsed is Array:
			for v in parsed:
				list.append({"name": str(v.name), "pos": _vec(v.pos), "look": _vec(v.look), "kind": str(v.kind)})
	else:
		# A few of each kind found by this scan.
		var per := {}
		for v in views:
			var k := str(v.kind)
			if int(per.get(k, 0)) < int(Game.arg("map_views_per", 6 if k == "gap" else 4)):
				per[k] = int(per.get(k, 0)) + 1
				list.append(v)
	var save := []
	for v in list:
		save.append({"name": v.name, "pos": [v.pos.x, v.pos.y, v.pos.z], "look": [v.look.x, v.look.y, v.look.z], "kind": v.kind})
	var f := FileAccess.open(out_dir + "/views.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save, "  "))
		f.close()
	if list.is_empty():
		return
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 1500.0
	cam.cull_mask = Defs.RENDER_WORLD | Defs.RENDER_CHARACTERS | Defs.RENDER_INTERIOR | Defs.RENDER_INTERIOR_PROPS
	world.add_child(cam)
	cam.current = true
	var hud = world.get("hud")
	if hud:
		hud.visible = false
	var L = map.lighting
	for v in list:
		cam.global_position = v.pos
		if (v.look - v.pos).length() > 0.01:
			cam.look_at(v.look, Vector3.UP if absf((v.look - v.pos).normalized().y) < 0.98 else Vector3.FORWARD)
		for tm in [450.0, 60.0]:
			L.forced_time = tm
			for i in 40:
				await t.get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img = t.get_viewport().get_texture().get_image()
			var path := "%s/%s_%s.png" % [out_dir, v.name, "day" if tm > 300.0 else "night"]
			img.save_png(path)
			_log("capture %s (luma %.1f)" % [path, _luma(img)])
	L.forced_time = -1.0
	if hud:
		hud.visible = true
	cam.current = false
	cam.queue_free()


func _vec(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _luma(img: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			s += (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255.0
			n += 1
	return s / maxf(n, 1)


# ------------------------------------------------------------------ report

func _write() -> void:
	var checks := [
		["doors_passable", "door_blocked", "doors_total"],
		["doors_swing_open", "door_swing_blocked", "doors_total"],
		["door_light_props", "door_light_props", "doors_total"],
		["doorways_passable", "doorway_blocked", "doorways_total"],
		["doorway_light_props", "doorway_light_props", "doorways_total"],
		["stairs_foot", "stair_foot_blocked", "stairs_total"],
		["stairs_flight", "stair_flight_blocked", "stairs_total"],
		["stairs_landing", "stair_top_blocked", "stairs_total"],
		["ladders_foot", "ladder_foot_blocked", "ladders_total"],
		["ladders_top", "ladder_top_blocked", "ladders_total"],
		["lanes_open", "lane_blocked", "lanes_total"],
		["props_supported", "prop_floating", "props_checked"],
		["props_not_sunk", "prop_sunk", "props_checked"],
		["static_supported", "static_floating", "props_checked"],
		["static_not_sunk", "static_sunk", "props_checked"],
		["lootbox_supported", "lootbox_floating", "props_checked"],
		["lootbox_not_sunk", "lootbox_sunk", "props_checked"],
		["props_not_in_walls", "prop_in_wall", "props_checked"],
		["static_not_in_walls", "static_in_wall", "props_checked"],
		["lootbox_not_in_walls", "lootbox_in_wall", "props_checked"],
		["items_supported", "item_floating", "items_checked"],
		["items_not_sunk", "item_sunk", "items_checked"],
		["items_not_in_walls", "item_in_wall", "items_checked"],
		["no_sky_gaps", "sky_gap", "face_rays"],
		["no_invisible_inside", "invisible_from_inside", "face_rays"],
		["no_invisible_outside", "invisible_from_outside", "face_rays"],
	]
	_log("---------------- PASS/FAIL ----------------")
	for c in checks:
		if not data.has(c[2]):
			continue
		var n := _n(c[1])
		var e: Dictionary = data.get(c[1], {})
		var detail := "%d of %s" % [n, str(data[c[2]])]
		if not (e.get("what", {}) as Dictionary).is_empty():
			detail += " " + JSON.stringify(e.what)
		t._check("map_" + str(c[0]), n == 0, detail)
		lines.append("%s %s: %s" % ["PASS" if n == 0 else "FAIL", c[0], detail])
	for k in ["door_blocked_by", "doorway_blocked_by", "door_swing_blocked_by", "stair_blocked_by", "lane_blocked_by", "door_drop", "doorway_drop",
			"lane_barricade", "stair_top_no_floor", "ladder_foot_no_ground", "ladder_top_no_deck"]:
		if data.has(k):
			_log("%s: %d %s" % [k, _n(k), JSON.stringify(data[k].what)])
	for k in data:
		var e2 = data[k]
		if e2 is Dictionary and not (e2.examples as Array).is_empty():
			lines.append("== %s (%d)" % [k, int(e2.n)])
			for x in e2.examples:
				lines.append("   " + str(x))
	var f := FileAccess.open(out_dir + "/mapscan.log", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	var f2 := FileAccess.open(out_dir + "/mapscan.json", FileAccess.WRITE)
	if f2:
		f2.store_string(JSON.stringify(data, "  "))
		f2.close()
