extends RefCounted
## Analytic hit volumes for the six body parts (head, torso, both arms, both legs).
##
## The server tests projectiles against these capsules, rebuilt from a character's recorded state at the time the
## shooter saw it (lag compensation). They depend only on position, yaw, pitch, stance, mode and whether a weapon is
## raised, so they are identical on every machine and need no animation data.

const STAND_H := 1.78


static func capsules(pos: Vector3, yaw: float, pitch: float, crouch: float, mode: int, armed: bool) -> Array:
	var out := []
	var basis := Basis(Vector3.UP, yaw)
	if mode == Motor.DOWNED or mode == Motor.DEAD:
		# Lying face down along the facing direction.
		var y := 0.18
		_add(out, "head", basis, pos, Vector3(0, y + 0.05, -0.85), Vector3(0, y + 0.05, -0.85), 0.115)
		_add(out, "torso", basis, pos, Vector3(0, y, -0.55), Vector3(0, y, 0.05), 0.17)
		_add(out, "arm_l", basis, pos, Vector3(-0.22, y, -0.5), Vector3(-0.3, y - 0.05, -1.05), 0.055)
		_add(out, "arm_r", basis, pos, Vector3(0.22, y, -0.5), Vector3(0.3, y - 0.05, -1.05), 0.055)
		_add(out, "leg_l", basis, pos, Vector3(-0.1, y, 0.12), Vector3(-0.14, y - 0.06, 0.95), 0.075)
		_add(out, "leg_r", basis, pos, Vector3(0.1, y, 0.12), Vector3(0.14, y - 0.06, 0.95), 0.075)
		return out
	var c := clampf(crouch, 0.0, 1.0)
	var h := lerpf(STAND_H, 1.15, c)
	var s := h / STAND_H
	var hip_y := lerpf(0.94, 0.55, c)
	var chest_y := h - 0.33
	var lean := -0.12 * c - 0.06 * clampf(pitch, -1.0, 1.0)
	var head_c := Vector3(0, h - 0.12, lean - 0.02)
	_add(out, "head", basis, pos, head_c, head_c, 0.115)
	_add(out, "torso", basis, pos, Vector3(0, hip_y + 0.02, 0.0), Vector3(0, chest_y, lean), 0.175)
	var sh_y := chest_y + 0.02
	if armed:
		var p := clampf(pitch, -1.2, 1.2)
		var reach_r := Vector3(0.04, sh_y - 0.14 + p * 0.12, -0.32)
		var reach_l := Vector3(-0.02, sh_y - 0.1 + p * 0.25, -0.55)
		_add(out, "arm_r", basis, pos, Vector3(0.2, sh_y, lean), reach_r, 0.055)
		_add(out, "arm_l", basis, pos, Vector3(-0.2, sh_y, lean), reach_l, 0.055)
	else:
		_add(out, "arm_r", basis, pos, Vector3(0.21, sh_y, lean), Vector3(0.25, hip_y - 0.08, 0.0), 0.055)
		_add(out, "arm_l", basis, pos, Vector3(-0.21, sh_y, lean), Vector3(-0.25, hip_y - 0.08, 0.0), 0.055)
	var knee_fwd := -0.28 * c
	_add(out, "leg_r", basis, pos, Vector3(0.1, hip_y, 0.0), Vector3(0.12, 0.42 * s + 0.05 * c, knee_fwd), 0.08)
	_add(out, "leg_r", basis, pos, Vector3(0.12, 0.42 * s + 0.05 * c, knee_fwd), Vector3(0.12, 0.08, 0.02), 0.065)
	_add(out, "leg_l", basis, pos, Vector3(-0.1, hip_y, 0.0), Vector3(-0.12, 0.42 * s + 0.05 * c, knee_fwd), 0.08)
	_add(out, "leg_l", basis, pos, Vector3(-0.12, 0.42 * s + 0.05 * c, knee_fwd), Vector3(-0.12, 0.08, 0.02), 0.065)
	return out


static func _add(out: Array, part: String, basis: Basis, pos: Vector3, a: Vector3, b: Vector3, r: float) -> void:
	out.append({"part": part, "a": pos + basis * a, "b": pos + basis * b, "r": r})


static func bounds_radius() -> float:
	return 1.3


static func intersect(caps: Array, from: Vector3, to: Vector3) -> Dictionary:
	## Earliest hit of segment from->to against the capsules. Returns {part, t, pos, normal} or {}.
	var best := {}
	var best_t := INF
	var d := to - from
	for c in caps:
		var t := ray_capsule(from, d, c.a, c.b, c.r)
		if t >= 0.0 and t <= 1.0 and t < best_t:
			best_t = t
			var p := from + d * t
			var axis: Vector3 = c.b - c.a
			var k := 0.0 if axis.length_squared() < 1e-8 else clampf((p - c.a).dot(axis) / axis.length_squared(), 0.0, 1.0)
			var n := (p - ((c.a as Vector3) + axis * k)).normalized()
			best = {"part": c.part, "t": t, "pos": p, "normal": n}
	return best


static func ray_capsule(ro: Vector3, rd: Vector3, pa: Vector3, pb: Vector3, r: float) -> float:
	## Inigo Quilez's capsule intersection. Returns the parametric t along rd (rd not normalised), or -1.
	var ba := pb - pa
	var oa := ro - pa
	var baba := ba.dot(ba)
	var bard := ba.dot(rd)
	var baoa := ba.dot(oa)
	var rdoa := rd.dot(oa)
	var oaoa := oa.dot(oa)
	var a := baba * rd.dot(rd) - bard * bard
	var b := baba * rdoa - baoa * bard
	var c := baba * oaoa - baoa * baoa - r * r * baba
	if baba < 1e-8:
		return _ray_sphere(ro, rd, pa, r)
	var h := b * b - a * c
	if h >= 0.0 and absf(a) > 1e-12:
		var t := (-b - sqrt(h)) / a
		var y := baoa + t * bard
		if y > 0.0 and y < baba:
			return t
		var oc := oa if y <= 0.0 else ro - pb
		b = rd.dot(oc)
		c = oc.dot(oc) - r * r
		var rr := rd.dot(rd)
		h = b * b - rr * c
		if h > 0.0:
			return (-b - sqrt(h)) / rr
	return -1.0


static func _ray_sphere(ro: Vector3, rd: Vector3, c: Vector3, r: float) -> float:
	var oc := ro - c
	var a := rd.dot(rd)
	var b := oc.dot(rd)
	var cc := oc.dot(oc) - r * r
	var h := b * b - a * cc
	if h < 0.0 or a < 1e-12:
		return -1.0
	return (-b - sqrt(h)) / a
