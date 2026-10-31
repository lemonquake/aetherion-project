class_name Vault
## Vaulting, PUBG style: jump close to a low wall, a fence, a crate, a table or a window and the character goes over
## or through it in one smooth move instead of jumping. Part of the shared movement simulation (Motor), so the
## server, the owner's prediction and replays all vault the same way; the state travels with the character's state.
##
## A vault needs: something solid within reach in front, its top between MIN_H and MAX_H above the feet, enough
## free height above that top to get the body through (a window opening), and somewhere to land: past the obstacle
## when it is thin, on top of it when it is deep. The body is lowered to fit the opening while it goes through.
## (r17) Past a balcony rail, a mall balustrade or an upper-floor window there is often no floor within reach: the
## vault still goes over and the body falls from the far side (fall damage as usual; "drop" says how far). Bots do
## not take a vault into a long drop (Motor). Thin railings (posts and a top rail) are found with a body-wide sweep
## as well as the rays, which slipped between the posts.

const REACH := 0.75      # from the capsule surface to the obstacle face
const MIN_H := 0.45
const LOW_H := 0.3       # (r17) a lower sill or kick plate is vaulted only when a drop lies past it (a French window)
const MAX_H := 1.5
const GAP := 0.62        # free height needed above the top (head and shoulders through a window)
const DEEP := 1.1        # deeper than this: climb on to it instead of over it

static var why := ""     # why the last find() found nothing (tests and debugging)


static func find(ch) -> Dictionary:
	why = ""
	if not ch.is_inside_tree():
		return {}
	var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	var fwd: Vector3 = -Basis(Vector3.UP, ch.yaw).z
	var p: Vector3 = ch.global_position
	var r := Defs.move("radius")
	var ex := [ch.get_rid()]
	# 1. A face in front, knee to chest high.
	var near := INF
	for hh in [0.35, 0.6, 0.85, 1.1]:
		var hit := _ray(space, p + Vector3.UP * hh, p + Vector3.UP * hh + fwd * (r + REACH), ex)
		if not hit.is_empty() and (hit.normal as Vector3).y < 0.6:
			near = minf(near, p.distance_to(Vector3(hit.position.x, p.y, hit.position.z)) - r)
	if near == INF:
		# (r17) Posts and a top rail: rays at four heights can all pass between them, a body-wide sweep cannot.
		for hh in [0.55, 0.85, 1.05]:
			var d := _sweep(space, p + Vector3.UP * hh, fwd, r + REACH, ex)
			if d >= 0.0:
				near = minf(near, d - r)
	if near == INF:
		why = "nothing in front"
		return {}
	var face := r + maxf(near, 0.0)
	# 2. The lowest free height just past the face: the top of a wall, the sill of a window.
	var clear := -1.0
	var hh2 := 0.3
	while hh2 <= MAX_H + 0.12:
		if _ray(space, p + Vector3.UP * hh2, p + Vector3.UP * hh2 + fwd * (face + 0.3), ex).is_empty() \
				and _sweep(space, p + Vector3.UP * hh2, fwd, face + 0.3, ex) < 0.0:
			clear = hh2
			break
		hh2 += 0.08
	if clear < 0.0:
		why = "no top within %.1f m (face %.2f)" % [MAX_H, face]
		return {}
	# 3. The top itself, measured straight down just past the face.
	var probe := p + fwd * (face + 0.06)
	var down := _ray(space, probe + Vector3.UP * (clear + 0.12), probe + Vector3.UP * 0.15, ex)
	var top_y: float = (down.position as Vector3).y if not down.is_empty() else p.y + clear - 0.04
	var top := top_y - p.y
	var low := top >= LOW_H and top < MIN_H
	if (top < MIN_H and not low) or top > MAX_H:
		why = "top %.2f m out of range" % top
		return {}
	# 4. Room above the top to get through: how tall the opening is (open sky counts as tall). Low clutter just past
	# a sill (a pail, a plank) can stop the lowest rays; the opening starts at the first clear one.
	var gap := 0.0
	var g := 0.12
	var start := -1.0
	while g <= 1.8:
		var a := Vector3(p.x, top_y + g, p.z)
		var blocked := not _ray(space, a, a + fwd * (face + 0.35), ex).is_empty()
		if blocked and start >= 0.0:
			break
		if not blocked and start < 0.0:
			start = g
		if start < 0.0 and g > 0.45:
			break
		if start >= 0.0:
			gap = g - start + 0.12
		g += 0.1
	if gap < GAP:
		why = "opening %.2f m too low (face %.2f, clear %.2f, top %.2f)" % [gap, face, clear, top]
		return {}
	# 5. Where to land: past the far edge when the obstacle is thin, on top when it is deep.
	var land := Vector3.INF
	var depth := 0.0
	var climb := false
	var k := 0
	while k <= 12:
		var x := face + 0.12 + k * 0.1
		var q := p + fwd * x
		var h := _ray(space, Vector3(q.x, top_y + 0.25, q.z), Vector3(q.x, top_y - 0.12, q.z), ex)
		if h.is_empty():
			depth = x - face
			break
		k += 1
	if k > 12 or depth > DEEP:
		climb = true
		var on := p + fwd * (face + r + 0.12)
		var h2 := _ray(space, Vector3(on.x, top_y + 0.3, on.z), Vector3(on.x, top_y - 0.2, on.z), ex)
		if h2.is_empty():
			why = "no surface on top"
			return {}
		land = Vector3(on.x, (h2.position as Vector3).y + 0.02, on.z)
	else:
		for extra in [0.0, 0.15, 0.3]:
			var beyond = p + fwd * (face + depth + r + 0.08 + extra)
			var h3 := _ray(space, Vector3(beyond.x, top_y + 0.3, beyond.z), Vector3(beyond.x, p.y - 2.2, beyond.z), ex)
			if h3.is_empty():
				continue
			var cand := Vector3(beyond.x, (h3.position as Vector3).y + 0.02, beyond.z)
			if _fits(ch, space, cand, Defs.move("crouch_height")):
				land = cand
				break
	var drop := 0.0
	if low and (climb or land != Vector3.INF):
		why = "top %.2f m out of range" % top   # low, with floor past it: an ordinary jump or step
		return {}
	if land == Vector3.INF and not climb:
		# (r17) No floor within reach past it: a drop. Over the top and out into the air beside its far face, at the
		# height the body started from (or just under the top when that is too low to fit), then a fall.
		for extra in [0.0, 0.15, 0.3]:
			var beyond2 = p + fwd * (face + depth + r + 0.1 + extra)
			for y in [p.y, top_y - 0.45]:
				var cand2 := Vector3(beyond2.x, y, beyond2.z)
				if _fits(ch, space, cand2, Defs.move("crouch_height")):
					land = cand2
					break
			if land != Vector3.INF:
				break
		if land != Vector3.INF:
			var hd := _ray(space, land + Vector3.UP * 0.1, land + Vector3.DOWN * 60.0, ex)
			drop = land.y - (hd.position as Vector3).y if not hd.is_empty() else 60.0
	if land == Vector3.INF or not _fits(ch, space, land, Defs.move("crouch_height")):
		why = "no room to land (face %.2f, top %.2f, depth %.2f, climb %s)" % [face, top, depth, str(climb)]
		return {}
	# 6. The way over: nothing at body height between the face and the landing spot. (r17) A raised outer sill or a
	# frame lip past the inner one: try a higher pass, within the opening, and carry the body over that high.
	var lift := 0.2
	if not climb:
		var blk := {}
		for l in [0.2, 0.45, 0.7]:
			if l > 0.2 and l + 0.35 > gap:
				break
			var from := Vector3(p.x, top_y + l, p.z) + fwd * face
			blk = _ray(space, from, Vector3(land.x, top_y + l, land.z), ex)
			if blk.is_empty():
				lift = l
				break
		if not blk.is_empty():
			var col = blk.get("collider")
			why = "path over blocked %.2f m past the face by %s" % [(blk.position as Vector3).distance_to(p + fwd * face), str(col.name) if col is Node else str(blk.get("collider_id", "?"))]
			return {}
	var over := p + fwd * (face + minf(depth, 0.5) * 0.5 + 0.05)
	return {"a": p, "m": Vector3(over.x, top_y + lift - 0.14, over.z), "b": land, "top": top, "gap": gap, "climb": climb,
		"stand": _fits(ch, space, land, Defs.move("stand_height") - 0.05), "drop": drop}


static func start(ch, v: Dictionary) -> void:
	# A speed vault: taken at a run the move is quicker and the body comes out the far side still running.
	var speed := Vector2(ch.velocity.x, ch.velocity.z).length()
	ch.vault_s = speed if not v.climb else 0.0
	ch.pk_bits &= ~Parkour.PK_CLIMB
	ch.vault_t = 0.0
	ch.vault_d = (0.38 + 0.2 * clampf(float(v.top) / MAX_H, 0.0, 1.0)) * lerpf(1.0, 0.78, clampf(speed / 6.3, 0.0, 1.0)) \
		+ (0.12 if v.climb else 0.0)
	ch.vault_a = v.a
	ch.vault_m = v.m
	ch.vault_b = v.b
	# Through a window the body folds to fit the opening (head and shoulders first).
	ch.vault_h = clampf(float(v.gap) + 0.05, Defs.move("crouch_height") * 0.8, Defs.move("stand_height"))
	if not v.stand:
		ch.crouching = true
	ch.velocity = Vector3.ZERO
	ch.emit_motion_event("vault", float(v.top))


static func step(ch, dt: float) -> void:
	## Moves along the vault path (no collision: the path was checked when the vault started).
	ch.vault_t += dt
	var u := clampf(ch.vault_t / maxf(ch.vault_d, 0.05), 0.0, 1.0)
	var a: Vector3 = ch.vault_a
	var m: Vector3 = ch.vault_m
	var b: Vector3 = ch.vault_b
	var pos: Vector3
	if u < 0.45:
		# Up and on to the top: fast at first, settling over the edge.
		var k := u / 0.45
		var ky := 1.0 - (1.0 - k) * (1.0 - k)
		pos = Vector3(lerpf(a.x, m.x, k), lerpf(a.y, m.y, ky), lerpf(a.z, m.z, k))
	else:
		# Over and down: the drop speeds up like a fall.
		var k2 := (u - 0.45) / 0.55
		pos = Vector3(lerpf(m.x, b.x, k2), lerpf(m.y, b.y, k2 * k2) if b.y < m.y else lerpf(m.y, b.y, k2), lerpf(m.z, b.z, k2))
	var prev: Vector3 = ch.global_position
	ch.global_position = pos
	ch.velocity = (pos - prev) / maxf(dt, 0.001)
	ch.apply_height()
	if u >= 1.0:
		ch.vault_t = -1.0
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var out := 1.0 if (ch.pk_bits & Parkour.PK_CLIMB) != 0 else maxf(2.2, ch.vault_s * 0.9)
		ch.pk_bits &= ~Parkour.PK_CLIMB
		ch.velocity = dir.normalized() * out if dir.length() > 0.01 else Vector3.ZERO
		ch.apply_height()
		ch.emit_motion_event("land", 2.5)


static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, ex: Array) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, Defs.MOVE_MASK)
	q.exclude = ex
	return space.intersect_ray(q)


static var _box: BoxShape3D = null


static func _sweep(space: PhysicsDirectSpaceState3D, from: Vector3, fwd: Vector3, dist: float, ex: Array) -> float:
	## A slab 0.26 m wide and 0.1 m tall pushed forward from the body's centre line at this height: how far it gets
	## before touching something (-1: nothing within dist). Catches railing posts the rays pass between.
	if _box == null:
		_box = BoxShape3D.new()
		_box.size = Vector3(0.26, 0.1, 0.04)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _box
	q.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), from)
	q.motion = fwd * dist
	q.collision_mask = Defs.MOVE_MASK
	q.exclude = ex
	var f := space.cast_motion(q)
	if f.is_empty() or float(f[1]) >= 1.0:
		return -1.0
	return float(f[0]) * dist


static func _fits(ch, space: PhysicsDirectSpaceState3D, feet: Vector3, height: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Defs.move("radius") - 0.03
	cap.height = height
	q.shape = cap
	q.transform = Transform3D(Basis(), feet + Vector3.UP * (height * 0.5 + 0.06))
	q.collision_mask = Defs.MOVE_MASK
	q.exclude = [ch.get_rid()]
	return space.intersect_shape(q, 1).is_empty()
