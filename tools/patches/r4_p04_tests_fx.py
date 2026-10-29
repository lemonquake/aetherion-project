"""r4: --autotest=r4 checks for impacts, holes, chunked props, doors and blasts."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
f = 'src/debug/autotest_r4.gd'
patch(f, '''	for step in [["pa", _pa_schedule]]:''', '''	for step in [["pa", _pa_schedule], ["holes", _holes], ["chunks", _chunks], ["doors", _door_panels], ["blast", _blast], ["fx_perf", _fx_perf]]:''')
patch(f, '''const DayCycle := preload("res://src/world/day_cycle.gd")
const Announcer := preload("res://src/audio/announcer.gd")
''', '''const DayCycle := preload("res://src/world/day_cycle.gd")
const Announcer := preload("res://src/audio/announcer.gd")
const Destruct := preload("res://src/world/destruct.gd")
''')
ADD = '''

# ------------------------------------------------------------------ shooting helpers

func _fire_at(target: Vector3, ammo: String = "9x19", v0: float = 360.0) -> void:
	## A real round on the server, from the player's eyes at the point: the full ballistics, damage and effects path.
	var ch = t.ch
	var eye: Vector3 = ch.eye_position()
	world.projectiles.spawn(ch, {"ammo": ammo, "velocity": v0, "origin": eye, "dir": (target - eye).normalized(), "seed": randi()}, Net.tick, Net.tick)


func _region_diff(a: Image, b: Image, rect: Rect2i) -> float:
	## Mean absolute luma difference (0-255) of two captures inside rect.
	var ra := a.get_region(rect)
	var rb := b.get_region(rect)
	ra.resize(48, 48)
	rb.resize(48, 48)
	var s := 0.0
	for y in 48:
		for x in 48:
			s += absf(ra.get_pixel(x, y).get_luminance() - rb.get_pixel(x, y).get_luminance())
	return s / (48.0 * 48.0) * 255.0


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return t.get_viewport().get_texture().get_image()


func _screen_rect(p: Vector3, half_px: int = 90) -> Rect2i:
	var cam: Camera3D = t.get_viewport().get_camera_3d()
	var s := cam.unproject_position(p)
	var vs: Vector2 = t.get_viewport().get_visible_rect().size
	var x := clampi(int(s.x) - half_px, 0, int(vs.x) - half_px * 2)
	var y := clampi(int(s.y) - half_px, 0, int(vs.y) - half_px * 2)
	return Rect2i(x, y, half_px * 2, half_px * 2)


# ------------------------------------------------------------------ bullet holes and impact particles

func _holes() -> void:
	var fx = world.effects
	# A plain wall: look along the street from the landing spot until a ray finds masonry 3-7 m away.
	var ch = t.ch
	var wall := {}
	for i in 24:
		var yaw := TAU * i / 24.0
		var dir := Vector3(-sin(yaw), 0, -cos(yaw))
		var eye: Vector3 = ch.eye_position()
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 7.0, Defs.SHOT_MASK)
		var h := ch.get_world_3d().direct_space_state.intersect_ray(q)
		if not h.is_empty() and eye.distance_to(h.position) > 2.5 and h.collider and h.collider.has_meta("mat") \\
				and str(h.collider.get_meta("mat")) in ["concrete", "hollow_block", "plaster", "default", "wood", "sheet_metal"] and absf((h.normal as Vector3).y) < 0.3:
			wall = h
			t.ctl.yaw = yaw
			t.ctl.pitch = 0.0
			break
	if wall.is_empty():
		t._check("holes_wall", false, "no wall within 7 m of the landing spot")
		return
	var mat := str(wall.collider.get_meta("mat"))
	await t._wait(0.5)
	var before := await _grab()
	var n0: int = fx.holes.count
	var e0: Dictionary = fx.particles.emitted.duplicate()
	var p: Vector3 = wall.position
	var side := (wall.normal as Vector3).cross(Vector3.UP).normalized()
	for k in 3:
		_fire_at(p + side * (k - 1) * 0.25 + Vector3.UP * (0.1 * k))
		await t._wait(0.05)
	await t._wait(0.15)
	var during := await _grab()
	t._shot("holes_impact_%s" % mat)
	await t._wait(2.5)
	var after := await _grab()
	t._shot("holes_after_%s" % mat)
	var rect := _screen_rect(p)
	var d_during := _region_diff(before, during, rect)
	var d_after := _region_diff(before, after, rect)
	var fx_n := 0
	for k in fx.particles.emitted:
		fx_n += int(fx.particles.emitted[k]) - int(e0.get(k, 0))
	t._check("holes_wall", fx.holes.count - n0 >= 3 and d_after > 0.6,
		"%d holes on %s; the spot changed by %.1f luma once the dust settled" % [fx.holes.count - n0, mat, d_after])
	t._check("impact_particles", fx_n >= 3 and d_during > d_after,
		"%d particle bursts; %.1f luma change while the dust flies vs %.1f after" % [fx_n, d_during, d_after])


# ------------------------------------------------------------------ props breaking chunk by chunk

func _chunks() -> void:
	var dyn = world.map.dyn
	var ch = t.ch
	var cands: Array = []
	for p in dyn.props:
		var s: Dictionary = dyn.models.spec(str(p.name))
		if str(s.get("kind", "")) in ["chair", "table"] and p.state == "dormant":
			cands.append(p)
	cands.sort_custom(func(a, b): return (a.xf as Transform3D).origin.distance_to(ch.global_position) < (b.xf as Transform3D).origin.distance_to(ch.global_position))
	var chosen: Dictionary = {}
	for p in cands.slice(0, 40):
		var o: Vector3 = (p.xf as Transform3D).origin
		if await t._stand_by(o + Vector3.UP * 0.35, o.y, 2.3):
			chosen = p
			break
	if chosen.is_empty():
		t._check("chunks_prop", false, "no chair or table to stand by")
		return
	var name := str(chosen.name)
	Destruct._cache.erase(name)
	var t0 := Time.get_ticks_usec()
	var info := Destruct.chunks_for(dyn.models, name)
	var cut_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var o2: Vector3 = (chosen.xf as Transform3D).origin
	t._look_at(o2 + Vector3.UP * 0.35)
	await t._wait(0.6)
	t._shot("chunks_%s_0" % name)
	var counts: Array = []
	var shots := 0
	for i in 16:
		if chosen.state == "broken":
			break
		var body = chosen.get("body")
		var aim := o2 + Vector3.UP * 0.3
		if body and is_instance_valid(body) and not body.alive.is_empty():
			# The lowest chunk still there: legs first, so the rest has something to fall from.
			var lowest: int = body.alive[0]
			for k in body.alive:
				if (info.chunks[k].center as Vector3).y < (info.chunks[lowest].center as Vector3).y:
					lowest = k
			aim = (body as Node3D).global_transform * (info.chunks[lowest].center as Vector3)
		_fire_at(aim)
		shots += 1
		await t._wait(0.45)
		body = chosen.get("body")
		counts.append(body.alive.size() if body and is_instance_valid(body) and chosen.state != "broken" else 0)
		if i == 2 or i == 5:
			t._look_at(aim)
			t._shot("chunks_%s_%d" % [name, i + 1])
	await t._wait(0.8)
	t._shot("chunks_%s_end" % name)
	var steps := 0
	var prev := (info.keys as Array).size()
	for c in counts:
		if int(c) < prev and int(c) > 0:
			steps += 1
		prev = int(c)
	t._check("chunks_cut", (info.keys as Array).size() >= 3 and cut_ms < 40.0, "%s cut into %d chunks (grid %s) in %.1f ms" % [name, (info.keys as Array).size(), str(info.dims), cut_ms])
	t._check("chunks_prop", steps >= 2 and chosen.state == "broken", "%s: chunks left after each of %d shots %s; %s" % [name, shots, str(counts), "collapsed" if chosen.state == "broken" else "still standing"])


# ------------------------------------------------------------------ doors losing panels

func _door_panels() -> void:
	var dyn = world.map.dyn
	var ch = t.ch
	var best = null
	var bd := INF
	for d in dyn.doors:
		var dn = d.get("node")
		if dn == null or dn.destroyed or absf(dn.angle) > 0.01 or dn.locked:
			continue
		var dist: float = dn.center().distance_to(ch.global_position)
		if dist < bd and dist < 120.0:
			bd = dist
			best = dn
	if best == null:
		t._check("door_panels", false, "no closed door nearby")
		return
	var door = best
	var xf: Transform3D = door.current_transform()
	var front: Vector3 = xf.basis.z.normalized()
	var stand: Vector3 = door.center() + front * 2.4
	t._teleport(Vector3(stand.x, xf.origin.y + 0.1, stand.z), 0.0)
	await t._wait(0.4)
	# Pick the side we are on (the leaf's +z or -z).
	t._look_at(door.center())
	await t._wait(0.3)
	t._shot("door_0")
	var fx = world.effects
	# Two holes in different panels, then swing the door: the holes must go with the leaf.
	var p_a: Vector3 = xf * Vector3(door.w * 0.5, door.h * 0.75, 0)
	var p_b: Vector3 = xf * Vector3(door.w * 0.75, door.h * 0.35, 0)
	_fire_at(p_a)
	await t._wait(0.2)
	_fire_at(p_b)
	await t._wait(0.5)
	t._shot("door_holes")
	var holes_on := 0
	var an = door.anchor
	if an and is_instance_valid(an):
		for c in an.get_children():
			if c is MultiMeshInstance3D:
				holes_on += (c as MultiMeshInstance3D).multimesh.visible_instance_count
	var a_before: Vector3 = an.global_transform * Vector3(door.w * 0.75, door.h * 0.35, 0) if an else Vector3.ZERO
	door.server_use(stand, (door.center() - stand).normalized())
	world.map_door_state(door, "open")
	await t._wait(1.4)
	t._shot("door_holes_open")
	var a_after: Vector3 = an.global_transform * Vector3(door.w * 0.75, door.h * 0.35, 0) if an else Vector3.ZERO
	t._check("holes_follow_door", holes_on >= 2 and a_before.distance_to(a_after) > 0.3,
		"%d holes hang on the leaf; a hole moved %.2f m when the door swung open" % [holes_on, a_before.distance_to(a_after)])
	door.server_use(stand, (door.center() - stand).normalized())
	world.map_door_state(door, "close")
	await t._wait(1.5)
	# Shoot out the hinge column bottom up, then check a ray goes through the first hole and the doorway opens.
	var lost_seq: Array = []
	var see_through := false
	var shots := 0
	for r in Destruct.DOOR_ROWS:
		for k in 6:
			if door.destroyed or door.lost.has(r):
				break
			var bx: AABB = door.panel_box(r)
			_fire_at(door.current_transform() * bx.get_center(), "9x19", 360.0)
			shots += 1
			await t._wait(0.3)
		lost_seq.append(door.lost.size())
		if r == 0 and door.lost.has(0) and not door.destroyed:
			var c0: Vector3 = door.current_transform() * door.panel_box(0).get_center()
			var nrm: Vector3 = door.current_transform().basis.z.normalized()
			var q := PhysicsRayQueryParameters3D.create(c0 + nrm * 0.5, c0 - nrm * 0.5, Defs.SHOT_MASK)
			var h := ch.get_world_3d().direct_space_state.intersect_ray(q)
			see_through = h.is_empty() or h.collider != door
			t._look_at(c0)
			t._shot("door_panel_out")
		if door.destroyed:
			break
	await t._wait(0.8)
	t._look_at(door.center())
	t._shot("door_destroyed")
	var mid: Vector3 = xf * Vector3(door.w * 0.5, 1.0, 0)
	var q2 := PhysicsRayQueryParameters3D.create(mid + front * 0.6, mid - front * 0.6, Defs.PHYS_WORLD)
	var h2 := ch.get_world_3d().direct_space_state.intersect_ray(q2)
	var open_way := h2.is_empty() or h2.collider != door
	t._check("door_panels", see_through and lost_seq.size() >= 2, "panels lost after each row of shots %s; a ray passes through the first hole: %s" % [str(lost_seq), see_through])
	t._check("door_destroyed", door.destroyed and open_way, "%d shots; leaf %s; doorway clear: %s" % [shots, "fell" if door.destroyed else "still up", open_way])


# ------------------------------------------------------------------ a grenade among furniture

func _blast() -> void:
	var dyn = world.map.dyn
	var ch = t.ch
	var best: Dictionary = {}
	var bd := INF
	for p in dyn.props:
		var s: Dictionary = dyn.models.spec(str(p.name))
		if str(s.get("kind", "")) in ["chair", "table", "crate"] and p.state == "dormant":
			var d: float = (p.xf as Transform3D).origin.distance_to(ch.global_position)
			if d < bd:
				bd = d
				best = p
	if best.is_empty():
		t._check("blast_props", false, "nothing to blow up")
		return
	var o: Vector3 = (best.xf as Transform3D).origin
	await t._stand_by(o + Vector3.UP * 0.3, o.y, 4.0)
	t._look_at(o)
	await t._wait(0.4)
	var p0 := best.state
	var c_before := 0
	var hn0: int = world.effects.holes.count
	world.map.server_blast(o + Vector3(0.6, 0.15, 0.0), 6.0, 130.0)
	world.effects.explosion(o + Vector3(0.6, 0.15, 0.0))
	await t._wait(0.25)
	t._shot("blast")
	await t._wait(1.5)
	t._shot("blast_after")
	var lost: int = (best.get("lost", []) as Array).size()
	t._check("blast_props", best.state == "broken" or lost > 0, "%s was %s, now %s with %d chunks lost; scorch mark %s" % [str(best.name), p0, best.state, lost,
		"laid" if world.effects.holes.count > hn0 else "missing"])


# ------------------------------------------------------------------ cost of a heavy firefight's impacts

func _fx_perf() -> void:
	var fx = world.effects
	var ch = t.ch
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var eye: Vector3 = ch.eye_position()
	var fwd: Vector3 = -Basis.from_euler(Vector3(t.ctl.pitch, t.ctl.yaw, 0)).z
	var spots: Array = []
	var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	for i in 60:
		var d := (fwd + Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.2), randf_range(-0.5, 0.5))).normalized()
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + d * 30.0, Defs.SHOT_MASK))
		if not h.is_empty():
			spots.append([h.position, h.normal])
	var kinds := ["concrete", "wood", "metal", "dirt", "glass", "plastic"]
	var base: Array = []
	var busy: Array = []
	await t._wait(0.5)
	for f2 in 90:
		var t0 := Time.get_ticks_usec()
		await t.get_tree().process_frame
		base.append((Time.get_ticks_usec() - t0) / 1000.0)
	for f3 in 90:
		var t1 := Time.get_ticks_usec()
		if f3 < 60 and not spots.is_empty():
			var s: Array = spots[f3 % spots.size()]
			fx.impact(s[0], s[1], kinds[f3 % kinds.size()], "hole", "")
		await t.get_tree().process_frame
		busy.append((Time.get_ticks_usec() - t1) / 1000.0)
	base.sort()
	busy.sort()
	var mb: float = base[base.size() / 2]
	var mi: float = busy[busy.size() / 2]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	t._check("fx_perf", mi - mb < 1.5, "median frame %.2f ms quiet, %.2f ms with an impact every frame (60 impacts, %d surfaces); p95 %.2f vs %.2f ms" % [mb, mi,
		spots.size(), base[int(base.size() * 0.95)], busy[int(busy.size() * 0.95)]])
'''
b = open(f, 'rb').read()
crlf = b'\r\n' in b
s = b.decode('utf-8').rstrip('\r\n')
s += ADD.replace('\n', '\r\n') if crlf else ADD
open(f, 'wb').write(s.encode('utf-8'))
print('appended tests')
