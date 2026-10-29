extends "res://src/fx/holes.gd"
## Blood: wet red marks where people are shot. A round through a body throws droplets on along its path and a few
## back toward the shooter; each flies a short ballistic arc and leaves a mark where it lands, round if it fell
## straight on, stretched with a tail if it hit at a glancing angle (the way real spatter reads). Close walls take a
## burst with runs dripping down, the floor under the victim takes drops, the wounded leave a drip trail, the downed
## smear the ground, and the dead lie in a pool that spreads for half a minute. Bodies shot again bleed again.
## Cards from one atlas (tools/make_blood_textures.py) through the same MultiMesh sets as bullet holes, so this works
## on every renderer and costs a few draw calls. Client-side and cosmetic; nothing here is replicated.

const PS := preload("res://src/weapons/projectile_server.gd")
const BLOOD_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic, repeat_disable;
varying float v_alpha;
varying float v_tint;
void vertex() {
	float c = INSTANCE_CUSTOM.x;
	vec2 cell = vec2(mod(c, 4.0), floor(c / 4.0));
	UV = (cell + UV) * 0.25;
	v_alpha = INSTANCE_CUSTOM.y;
	// Collision surfaces can sit a few centimetres behind the drawn ones (plank tops, wall cladding): pull the card
	// toward the eye along its own view ray, which keeps its place on screen but lets it win the depth test.
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vp.xyz *= max(1.0 - 0.06 / max(length(vp.xyz), 0.1), 0.2);
	POSITION = PROJECTION_MATRIX * vp;
	v_tint = INSTANCE_CUSTOM.z;
}
void fragment() {
	vec4 a = texture(albedo_tex, UV);
	vec4 n = texture(normal_tex, UV);
	ALBEDO = a.rgb * v_tint;
	ALPHA = a.a * v_alpha;
	NORMAL_MAP = n.rgb;
	ROUGHNESS = n.a;
	SPECULAR = 0.6;
}
"""
const DROPS := [0, 1, 2, 3]
const STREAKS := [4, 5, 6, 7]
const BURSTS := [8, 9]
const MIST := 10
const HEAVY := 11
const POOLS := [12, 13]
const SMEAR := 14
const TRAIL := 15
const MASK := Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS
const G := 9.8

var world = null
var _space: PhysicsDirectSpaceState3D
var _mobile := false
var _growing: Array = []     # {h, basis, origin, s0, s1, t, dur}
var _bleeders := {}          # eid -> {until, next, last_pos}
var marks_made := 0          # for tests: marks placed since start
var pools_made := 0
var recent: Array = []       # for tests: world positions of the last marks placed


func setup() -> void:
	_rng.randomize()
	_mobile = Settings.is_mobile()
	budget = 420 if _mobile else 1400
	world_cap = 220 if _mobile else 520   # marks per 48 m map cell before the oldest there go
	obj_cap = 48
	world_range = 70.0 if _mobile else 110.0
	var sh := Shader.new()
	sh.code = BLOOD_SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("albedo_tex", load("res://assets/fx/blood_albedo.png"))
	mat.set_shader_parameter("normal_tex", load("res://assets/fx/blood_normal.png"))
	# Drawn before bullet holes, so a hole through a bloodied wall still shows on top of the blood.
	mat.render_priority = -1
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = mat


func _ready_space() -> bool:
	if _space == null and is_inside_tree():
		_space = get_world_3d().direct_space_state
	return _space != null


# ------------------------------------------------------------------ events

func shot_through(pos: Vector3, dir: Vector3, power: float, exclude: Array = [], eid: int = -1) -> void:
	## A round hit a body at pos travelling along dir. power 0..1 (damage, calibre); exclude: RIDs to ignore.
	if not _ready_space():
		return
	dir = dir.normalized()
	var k := 0.55 if _mobile else 1.0
	# Exit spray: on along the bullet's path, a tight cone of fast droplets and a looser one of slower drops.
	for i in int(lerpf(7.0, 18.0, power) * k):
		var fast := i % 3 != 0
		var d := _cone(dir, deg_to_rad(16.0 if fast else 34.0))
		var v := d * _rng.randf_range(4.5, 10.0) * (0.75 + 0.5 * power) if fast else d * _rng.randf_range(2.0, 4.5)
		_fly(pos + dir * 0.12, v, _rng.randf_range(0.008, 0.02) * (1.0 + power * 0.6), exclude)
	# Back spatter toward the shooter: few and fine.
	for i in int(lerpf(2.0, 6.0, power) * k):
		_fly(pos - dir * 0.04, _cone(-dir, deg_to_rad(40.0)) * _rng.randf_range(1.5, 4.0), _rng.randf_range(0.005, 0.012), exclude)
	# A wall or door right behind takes the burst, sized by how far the spray had to spread.
	var q := PhysicsRayQueryParameters3D.create(pos + dir * 0.1, pos + dir * 2.8, MASK)
	q.exclude = exclude
	var hit := _space.intersect_ray(q)
	if not hit.is_empty():
		var dist: float = (hit.position as Vector3).distance_to(pos)
		var size := clampf(0.32 + dist * 0.28 + power * 0.35, 0.3, 1.25)
		var cell: int = HEAVY if power > 0.75 else BURSTS[_rng.randi() % 2]
		_mark(hit.position, hit.normal, cell, Vector2(size, size), dir, _on(hit.collider), 1.0)
		if dist < 1.6:
			_mark(hit.position + Vector3(_rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.1, 0.1)), hit.normal, MIST, Vector2(size * 1.4, size * 1.4), dir, _on(hit.collider), 0.85)
	# Drops straight down from the wound on to the floor where they stand.
	for i in int(lerpf(2.0, 6.0, power) * k):
		var off := Vector3(_rng.randf_range(-0.25, 0.25), 0.0, _rng.randf_range(-0.25, 0.25)) + dir * _rng.randf_range(0.0, 0.35)
		_drip(pos + off, _rng.randf_range(0.022, 0.045) * (1.0 + power * 0.5) * (1.8 if _rng.randf() < 0.25 else 1.0), exclude)
	if eid >= 0:
		bleed(eid, 6.0 + power * 10.0)


func corpse_hit(pos: Vector3, dir: Vector3, exclude: Array = []) -> void:
	## A dead body shot again: no pulse behind it, so less spray, but it still splashes and drips.
	shot_through(pos, dir, 0.45, exclude)


func pool_under(at: Vector3, size: float, grow_time: float, exclude: Array = []) -> void:
	## A pool spreading on the floor below `at` (a body's chest), from a palm-sized stain to `size` metres.
	if not _ready_space():
		return
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * 1.6, MASK)
	q.exclude = exclude
	var hit := _space.intersect_ray(q)
	if hit.is_empty():
		return
	var n: Vector3 = hit.normal
	var b := _basis(n, Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)))
	# It spreads only as far as the floor goes (not out over a step or a ledge).
	size = _fit(hit.position, n, b, Vector2(size, size), exclude).x
	if size <= 0.0:
		return
	var origin: Vector3 = (hit.position as Vector3) + n * (0.005 + 0.001 * (pools_made % 4))
	var cell: int = POOLS[_rng.randi() % 2]
	var h := place_xf(Transform3D(Basis(b.x * 0.12, b.y * 0.12, b.z), origin), Color(float(cell), 1.0, _rng.randf_range(0.85, 1.0), 0.0))
	if h.is_empty():
		return
	marks_made += 1
	pools_made += 1
	_growing.append({"h": h, "basis": b, "origin": origin, "s0": 0.12, "s1": size, "t": 0.0, "dur": grow_time})


func bleed(eid: int, seconds: float) -> void:
	## The character drips as they move for a while after being hit (longer the worse the wound).
	var e: Dictionary = _bleeders.get(eid, {"until": 0.0, "next": 0.0, "last": Vector3.INF})
	var now := Time.get_ticks_msec() / 1000.0
	e.until = maxf(float(e.until), now + seconds)
	_bleeders[eid] = e


# ------------------------------------------------------------------ per frame

func update(dt: float, characters: Dictionary, cam_pos: Vector3) -> void:
	for i in range(_growing.size() - 1, -1, -1):
		var g: Dictionary = _growing[i]
		g.t = float(g.t) + dt
		var f := clampf(float(g.t) / float(g.dur), 0.0, 1.0)
		var s := lerpf(float(g.s0), float(g.s1), 1.0 - pow(1.0 - f, 2.2))
		var gb: Basis = g.basis
		var ok := set_mark_xf(g.h, Transform3D(Basis(gb.x * s, gb.y * s, gb.z), g.origin))
		if f >= 1.0 or not ok:
			_growing.remove_at(i)
	if not _ready_space():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for eid in _bleeders.keys():
		var ch = characters.get(eid)
		var e: Dictionary = _bleeders[eid]
		var downed: bool = ch != null and is_instance_valid(ch) and ch.mode == Motor.DOWNED
		if ch == null or not is_instance_valid(ch) or ch.mode == Motor.DEAD or (now > float(e.until) and not downed):
			_bleeders.erase(eid)
			continue
		if now < float(e.next) or (ch.global_position as Vector3).distance_to(cam_pos) > 70.0:
			continue
		var p: Vector3 = ch.global_position
		var moved: float = 0.0 if e.last == Vector3.INF else Vector2(p.x - e.last.x, p.z - e.last.z).length()
		e.next = now + (_rng.randf_range(0.25, 0.5) if moved > 0.05 else _rng.randf_range(0.9, 1.6))
		var ex := [ch.get_rid()]
		if downed:
			if moved > 0.15:
				var along := Vector3(p.x - e.last.x, 0.0, p.z - e.last.z).normalized()
				_floor_mark(p + Vector3.UP * 0.4 - along * 0.2, SMEAR, Vector2(minf(moved + 0.3, 0.9), 0.55), along, ex, 0.9)
			else:
				_drip(p + Vector3(_rng.randf_range(-0.3, 0.3), 0.5, _rng.randf_range(-0.3, 0.3)), _rng.randf_range(0.035, 0.06), ex)
		elif moved > 0.05:
			_drip(p + Vector3(_rng.randf_range(-0.2, 0.2), 1.0, _rng.randf_range(-0.2, 0.2)), _rng.randf_range(0.02, 0.04), ex)
		e.last = p


func bleeding(eid: int) -> bool:
	return _bleeders.has(eid)


# ------------------------------------------------------------------ marks

func _fly(p: Vector3, v: Vector3, size: float, exclude: Array) -> void:
	## Follows one droplet's arc in 60 ms steps (at most ~0.7 s) and marks where it lands.
	var step := 0.06
	for i in 12:
		var nv := v + Vector3.DOWN * G * step
		var np := p + (v + nv) * 0.5 * step
		var q := PhysicsRayQueryParameters3D.create(p, np, MASK)
		q.exclude = exclude
		var hit := _space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			var vin := nv.normalized()
			var sin_a := clampf(absf(vin.dot(n)), 0.05, 1.0)
			var stretch := clampf(1.0 / sin_a, 1.0, 6.0)
			if stretch < 1.35:
				_mark(hit.position, n, DROPS[_rng.randi() % 4], Vector2.ONE * size * 4.2, vin, _on(hit.collider), 1.0)
			else:
				# Directional cell: body near the top, tail running down the image; the tail points the way it flew.
				_mark(hit.position, n, STREAKS[_rng.randi() % 4], Vector2(size * 3.6, size * 1.8 * (1.0 + stretch)), vin, _on(hit.collider), 1.0, true)
			return
		p = np
		v = nv


func _drip(from: Vector3, size: float, exclude: Array) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, MASK)
	q.exclude = exclude
	var hit := _space.intersect_ray(q)
	if not hit.is_empty():
		var cell: int = DROPS[_rng.randi() % 4] if _rng.randf() < 0.85 else TRAIL
		_mark(hit.position, hit.normal, cell, Vector2.ONE * size * (4.2 if cell != TRAIL else 6.0), Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)), _on(hit.collider), 1.0)


func _floor_mark(from: Vector3, cell: int, size: Vector2, along: Vector3, exclude: Array, alpha: float) -> void:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, MASK)
	q.exclude = exclude
	var hit := _space.intersect_ray(q)
	if not hit.is_empty():
		_mark(hit.position, hit.normal, cell, size, along, _on(hit.collider), alpha, false, true)


func _mark(pos: Vector3, normal: Vector3, cell: int, size: Vector2, travel: Vector3, on: Node3D, alpha: float, streak: bool = false, along_u: bool = false) -> void:
	## size.x across the image (U), size.y down it (V). Streaks run their image-down axis along the travel direction;
	## smears their image-right axis; everything else on a wall hangs with image-down pointing down the wall (runs drip
	## down), and on a floor turns with the travel direction.
	var n := normal.normalized()
	var b: Basis
	if streak:
		b = _basis_down(n, travel)
	elif along_u:
		b = _basis_right(n, travel)
	elif absf(n.y) < 0.7:
		b = _basis_down(n, Vector3.DOWN)
	else:
		b = _basis_right(n, travel if travel.length() > 0.01 else Vector3.RIGHT)
	if maxf(size.x, size.y) > 0.25:
		size = _fit(pos, n, b, size, [])
		if size.x <= 0.0:
			return
	var xf := Transform3D(Basis(b.x * size.x, b.y * size.y, b.z), pos + n * (0.006 + _rng.randf() * 0.002))
	if not place_xf(xf, Color(float(cell), alpha, _rng.randf_range(0.8, 1.05), 0.0), on).is_empty():
		marks_made += 1
		recent.append([pos, cell, size.x, on != null])
		if recent.size() > 64:
			recent.pop_front()


func _fit(pos: Vector3, n: Vector3, b: Basis, size: Vector2, exclude: Array) -> Vector2:
	## A big card must have the surface under its corners (the drawn mark fills ~80 % of the card): otherwise it would
	## hang off a wall's edge or a step into thin air. Shrinks it until it fits; Vector2.ZERO if even small won't.
	for k in 3:
		var ok := true
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var p: Vector3 = pos + b.x * (c.x * size.x * 0.4) + b.y * (c.y * size.y * 0.4)
			var q := PhysicsRayQueryParameters3D.create(p + n * 0.08, p - n * 0.12, MASK)
			q.exclude = exclude
			var h := _space.intersect_ray(q)
			if h.is_empty() or (h.normal as Vector3).dot(n) < 0.8:
				ok = false
				break
		if ok:
			return size
		size *= 0.6
		if maxf(size.x, size.y) < 0.15:
			break
	return Vector2.ZERO


func _basis(n: Vector3, right_hint: Vector3) -> Basis:
	return _basis_right(n, right_hint)


func _basis_right(n: Vector3, right: Vector3) -> Basis:
	## Image right (+X) along `right` projected on the surface.
	var x := (right - n * right.dot(n))
	if x.length() < 0.01:
		x = (Vector3.UP if absf(n.y) < 0.9 else Vector3.FORWARD).cross(n)
	x = x.normalized()
	var y := n.cross(x).normalized()
	return Basis(x, y, n)


func _basis_down(n: Vector3, down: Vector3) -> Basis:
	## Image down (-Y of the quad) along `down` projected on the surface.
	var d := (down - n * down.dot(n))
	if d.length() < 0.01:
		return _basis_right(n, Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)))
	var y := -d.normalized()
	var x := y.cross(n).normalized()
	return Basis(x, y, n)


func _cone(axis: Vector3, half: float) -> Vector3:
	var a := axis.normalized()
	var ref := Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT
	var u := a.cross(ref).normalized()
	var w := a.cross(u)
	var r := tan(half) * sqrt(_rng.randf())
	var t := _rng.randf() * TAU
	return (a + u * cos(t) * r + w * sin(t) * r).normalized()


func _on(col) -> Node3D:
	## What the mark hangs on so it moves with it (a door, a shutter, a loose prop), or null for the static world.
	if world == null or world.effects == null:
		return null
	return world.effects._attach(PS._attach_code(col))
