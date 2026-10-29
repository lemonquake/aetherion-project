extends RefCounted
## --autotest=r4: measured checks for the 2026-10-27 r4 run - the day/night loudspeakers (cue schedule against forced
## match times, horns placed across the map, sounds actually started), impact particles and bullet holes, chunk-by-
## chunk destruction of props and doors, and outfits. Each check measures what the player sees, hears or where
## things end up.
##   godot --path game -- --host --bots=3 --autostart=1 --autotest=r4 --shots=<dir>   [--r4_only=pa,holes,...]

const DayCycle := preload("res://src/world/day_cycle.gd")
const Announcer := preload("res://src/audio/announcer.gd")
const Destruct := preload("res://src/world/destruct.gd")

var t = null
var world = null


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("r4_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	if want.call("pa_census"):
		_pa_census()
	await t._deploy()
	if not is_instance_valid(t.ch):
		return
	for step in [["outfits", _outfits], ["pa", _pa_schedule], ["holes", _holes], ["chunks", _chunks], ["doors", _door_panels], ["blast", _blast], ["realism", _realism], ["fx_perf", _fx_perf]]:
		if want.call(step[0]) and is_instance_valid(t.ch):
			# The visual checks run at noon: holes on a wall at night are (rightly) invisible in a capture.
			world.map.lighting.forced_time = 450.0 if step[0] in ["holes", "chunks", "doors", "blast", "outfits"] else -1.0
			await (step[1] as Callable).call()
	world.map.lighting.forced_time = -1.0


# ------------------------------------------------------------------ loudspeakers

func _pa_census() -> void:
	var m = world.map
	var sp: Array = m.pa_speakers
	# Coverage: the farthest any building is from its nearest horn.
	var worst := 0.0
	var step := maxi(m.buildings.size() / 400, 1)
	for i in range(0, m.buildings.size(), step):
		var o: Vector3 = (m.buildings[i].xf as Transform3D).origin
		var best := INF
		for s in sp:
			best = minf(best, Vector2((s.pos as Vector3).x - o.x, (s.pos as Vector3).z - o.z).length())
		worst = maxf(worst, best)
	t._check("pa_horns", sp.size() >= 20 and worst < 220.0, "%d loudspeaker poles; the farthest sampled house is %.0f m from a horn" % [sp.size(), worst])


func _pa_schedule() -> void:
	var L = world.map.lighting
	var ann = world.announcer
	if ann == null:
		t._check("pa_schedule", false, "no announcer on this machine")
		return
	# Stand in a street near a horn and look at it, for the picture.
	var best: Dictionary = {}
	for s in world.map.pa_speakers:
		if best.is_empty() or (s.pos as Vector3).distance_to(t.ch.global_position) < (best.pos as Vector3).distance_to(t.ch.global_position):
			best = s
	if not best.is_empty():
		var hp: Vector3 = best.pos
		var a: Vector2 = best.along
		var stand := Vector2(hp.x, hp.z) + a.normalized() * 9.0
		t._teleport(Vector3(stand.x, world.map.ground_height(stand.x, stand.y) + 0.2, stand.y), 0.0)
		await t._wait(0.6)
		t._look_at(hp + Vector3.DOWN * 1.5)
		await t._wait(0.4)
		t._shot("pa_horn")
	for kind in ["ignite", "dusk"]:
		var change: float = DayCycle.night_s() if kind == "ignite" else DayCycle.night_s() + DayCycle.day_s() - DayCycle.DUSK_S
		ann.played.clear()
		var heard := {}   # cue index -> an announcer sound was playing within a second after it
		var tt := change - 63.0
		while tt < change + 2.0:
			L.forced_time = tt
			await t.world.get_tree().process_frame
			ann._process(0.0)
			if not ann.played.is_empty() and tt - float(ann.played[-1][0]) < 1.0 and _pa_playing() > 0:
				heard[ann.played.size() - 1] = true
			if kind == "ignite" and absf(tt - (change - 6.0)) < 0.05:
				t._shot("pa_countdown")
			tt += 0.1
		var want := ["chime", "60", "chime", "30", "n10", "n9", "n8", "n7", "n6", "n5", "n4", "n3", "n2", "n1", "siren"]
		var got: Array = ann.played.map(func(e): return e[1])
		var timing_ok := true
		var detail := []
		for e in ann.played:
			var before := change - float(e[0])
			for c in Announcer.CUES:
				if c[1] == e[1] and absf(before - float(c[0])) < 0.25:
					break
				if c == Announcer.CUES[-1]:
					pass
			detail.append("%s@-%.1f" % [e[1], before])
		for i in mini(got.size(), want.size()):
			var cue_before: float = Announcer.CUES[i][0]
			if absf((change - float(ann.played[i][0])) - cue_before) > 0.25:
				timing_ok = false
		t._check("pa_schedule_" + kind, got == want and timing_ok and heard.size() >= want.size() - 1,
			"%s; %d of %d cues heard from a horn; %s" % [", ".join(detail), heard.size(), got.size(), "" if got == want else "expected " + ", ".join(want)])
	L.forced_time = -1.0


func _pa_playing() -> int:
	## 1 if a loudspeaker sound is playing in the 3D pool right now.
	for p in SoundSys._pool:
		if p.playing and p.stream and str(p.stream.resource_path).find("announcer") >= 0:
			return 1
	return 0

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


func _open_sky(p: Vector3) -> bool:
	## Nothing overhead for 40 m: a spot the sun reaches.
	var space: PhysicsDirectSpaceState3D = t.ch.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.UP * 40.0, Defs.SHOT_MASK)).is_empty()


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
	# A house front: stand 2 m in front of a nearby door (on a side with floor under it) and aim at the wall beside it.
	var ch = t.ch
	var wall := {}
	var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	var doors: Array = world.map.dyn.doors.filter(func(d): return d.get("node") != null and not d.node.destroyed and d.has("outward"))
	doors.sort_custom(func(a, b): return (a.xf as Transform3D).origin.distance_to(ch.global_position) < (b.xf as Transform3D).origin.distance_to(ch.global_position))
	for d in doors.slice(0, 40):
		var dn = d.node
		var xf: Transform3D = dn.current_transform()
		var side: Vector3 = xf.basis.x.normalized()
		for sgn in [1.0, -1.0]:
			var fr: Vector3 = xf.basis.z.normalized() * sgn
			if fr.dot(d.outward) < 0.3:
				continue   # the street side only
			var stand: Vector3 = dn.center() + fr * 2.0
			var fl := space.intersect_ray(PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.4, stand + Vector3.DOWN * 1.2, Defs.PHYS_WORLD))
			if fl.is_empty() or absf((fl.position as Vector3).y - xf.origin.y) > 0.3:
				continue
			var eye := Vector3(stand.x, xf.origin.y + 1.6, stand.z)
			for ss in [-1.0, 1.0]:
				var target: Vector3 = dn.center() + side * ss * (float(dn.w) * 0.5 + 0.55) + fr * 0.01
				var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + (target - eye) * 1.25, Defs.SHOT_MASK))
				if not h.is_empty() and h.collider and h.collider.has_meta("mat") and not h.collider.has_meta("door_id") \
						and str(h.collider.get_meta("mat")) != "glass" and absf((h.normal as Vector3).y) < 0.3 and (h.position as Vector3).distance_to(target) < 0.5 \
						and _open_sky(h.position + (h.normal as Vector3) * 0.4):   # roofed lanes leave the wall black at noon
					t._teleport(Vector3(stand.x, xf.origin.y + 0.1, stand.z), 0.0)
					await t._wait(0.3)
					t._look_at(h.position)
					wall = h
					break
			if not wall.is_empty():
				break
		if not wall.is_empty():
			break
	if wall.is_empty():
		t._check("holes_wall", false, "no house front found beside the 25 nearest doors")
		return
	var mat := str(wall.collider.get_meta("mat"))
	if not (ch.flags & Character.F_LIGHT):
		await t._tap("flashlight")
	await t._wait(0.5)
	var before := await _grab()
	var n0: int = fx.holes.count
	var e0: Dictionary = fx.particles.emitted.duplicate()
	var p: Vector3 = wall.position
	var side := (wall.normal as Vector3).cross(Vector3.UP).normalized()
	var spots: Array = []
	for k in 3:
		var aim: Vector3 = p + side * (k - 1) * 0.25 + Vector3.UP * (0.1 * k)
		spots.append(aim)
		_fire_at(aim)
		await t._wait(0.05)
	await t._wait(0.15)
	var during := await _grab()
	t._shot("holes_impact_%s" % mat)
	await t._wait(2.5)
	var after := await _grab()
	await t._shot("holes_after_%s" % mat)   # awaited: the next test moves the player before an unawaited shot saves
	var rect := _screen_rect(p)
	# Each hole measured on its own small patch of the screen (a wide region dilutes a 4 cm crater to nothing).
	var d_after := 0.0
	# The holes are in both later frames, so whatever differs between them is the dust and sparks still flying.
	var d_during := _region_diff(during, after, rect)
	for s in spots:
		d_after = maxf(d_after, _region_diff(before, after, _screen_rect(s, 22)))
		d_during = maxf(d_during, _region_diff(during, after, _screen_rect(s, 40)))
	var fx_n := 0
	for k in fx.particles.emitted:
		fx_n += int(fx.particles.emitted[k]) - int(e0.get(k, 0))
	t._check("holes_wall", fx.holes.count - n0 >= 3 and d_after > 2.5,
		"%d holes on %s; the most-changed hole spot differs by %.1f luma from before the shots, once the dust settled" % [fx.holes.count - n0, mat, d_after])
	t._check("impact_particles", fx_n >= 3 and d_during > 1.0,
		"%d particle bursts; the frame with the dust flying differs from the settled one by %.1f luma (holes are in both)" % [fx_n, d_during])


# ------------------------------------------------------------------ props breaking chunk by chunk

func _chunks() -> void:
	var dyn = world.map.dyn
	var ch = t.ch
	var cands: Array = []
	for p in dyn.props:
		var s: Dictionary = dyn.models.spec(str(p.name))
		if str(s.get("kind", "")) in ["chair", "table"] and p.state == "dormant" \
				and (Destruct.chunks_for(dyn.models, str(p.name)).get("keys", []) as Array).size() >= 6:
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
			# The lowest chunk the eye can see (a ray reaches the prop there): legs first, so the rest falls.
			var order: Array = body.alive.duplicate()
			order.sort_custom(func(a, b): return (info.chunks[a].center as Vector3).y < (info.chunks[b].center as Vector3).y)
			var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
			for k in order:
				var p: Vector3 = (body as Node3D).global_transform * (info.chunks[k].center as Vector3)
				var hh := space.intersect_ray(PhysicsRayQueryParameters3D.create(ch.eye_position(), p + (p - ch.eye_position()).normalized() * 0.3, Defs.SHOT_MASK))
				if not hh.is_empty() and hh.collider == body:
					aim = hh.position
					break
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
	var space: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	var cands: Array = []
	for d in dyn.doors:
		var dn = d.get("node")
		if dn == null or dn.destroyed or absf(dn.angle) > 0.01 or dn.locked:
			continue
		var dist: float = dn.center().distance_to(ch.global_position)
		if dist < 150.0:
			cands.append([dist, dn])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var door = null
	var stand := Vector3.ZERO
	var front := Vector3.ZERO
	var xf := Transform3D()
	for c in cands.slice(0, 250):
		var dn = c[1]
		var dxf: Transform3D = dn.current_transform()
		for opt in [[1.0, 2.4], [-1.0, 2.4], [1.0, 1.8], [-1.0, 1.8]]:
			var fr: Vector3 = dxf.basis.z.normalized() * float(opt[0])
			var st: Vector3 = dn.center() + fr * float(opt[1])
			var floor_y: float = dxf.origin.y + 0.1
			var eye := Vector3(st.x, floor_y + 1.6, st.z)
			# Every panel row in plain view from here, nothing in between.
			var clear := true
			for r in Destruct.DOOR_ROWS:
				var p: Vector3 = dxf * dn.panel_box(r).get_center()
				var hh := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, p + (p - eye).normalized() * 0.05, Defs.SHOT_MASK))
				if hh.is_empty() or hh.collider != dn:
					clear = false
					break
			var dn_ray := space.intersect_ray(PhysicsRayQueryParameters3D.create(st + Vector3.UP * 0.5, st + Vector3.DOWN * 0.8, Defs.PHYS_WORLD))
			if clear and not dn_ray.is_empty() and absf((dn_ray.position as Vector3).y - dxf.origin.y) < 0.4:
				door = dn
				stand = Vector3(st.x, floor_y, st.z)
				front = fr
				xf = dxf
				break
		if door:
			break
	if door == null:
		t._check("door_panels", false, "no closed door with a clear line of fire in the 250 nearest")
		return
	t._teleport(stand, 0.0)
	await t._wait(0.4)
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
			var h = ch.get_world_3d().direct_space_state.intersect_ray(q)
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
	var h2 = ch.get_world_3d().direct_space_state.intersect_ray(q2)
	var open_way = h2.is_empty() or h2.collider != door
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
	var p0 = best.state
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
	await t._wait(0.5)
	var vp: RID = t.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var parts := {}
	for mode in ["quiet", "all", "particles", "holes", "sound", "quiet2"]:
		var times: Array = []
		var cpu: Array = []
		var gpu: Array = []
		for f3 in 90:
			var t1 := Time.get_ticks_usec()
			var c0 := Time.get_ticks_usec()
			if f3 < 60 and not spots.is_empty() and not mode.begins_with("quiet"):
				var s: Array = spots[(f3 * 7) % spots.size()]
				var kind: String = kinds[f3 % kinds.size()]
				match mode:
					"all":
						fx.impact(s[0], s[1], kind, "hole", "")
					"particles":
						for k in fx.IMPACT_FX.get(kind, ["dust"]):
							fx.particles.emit(k, s[0], s[1])
					"holes":
						fx.holes.add(s[0], s[1], kind)
					"sound":
						SoundSys.play_at("impact_" + kind, s[0], 0.0)
			cpu.append((Time.get_ticks_usec() - c0) / 1000.0)
			await t.get_tree().process_frame
			times.append((Time.get_ticks_usec() - t1) / 1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		times.sort()
		gpu.sort()
		var c_sum := 0.0
		for c in cpu:
			c_sum += c
		parts[mode] = [times[times.size() / 2], times[int(times.size() * 0.95)], c_sum / 60.0, gpu[gpu.size() / 2]]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var gb: float = (parts.quiet[3] + parts.quiet2[3]) * 0.5
	var detail := []
	for m in parts:
		detail.append("%s %.2f ms (p95 %.2f, GPU %.2f, call %.3f ms)" % [m, parts[m][0], parts[m][1], parts[m][3], parts[m][2]])
	# Judged on GPU time and the calls' own CPU time: wall-clock frame times swing with other work on this machine.
	t._check("fx_perf", parts.all[3] - gb < 1.5 and parts.all[2] < 1.0, "an impact every frame for 60 frames vs quiet: " + "; ".join(detail))

# ------------------------------------------------------------------ outfits

func _outfits() -> void:
	const Outfit := preload("res://src/player/outfit.gd")
	var ch = t.ch
	var others: Array = world.characters.values().filter(func(c): return c != ch and c.visual != null)
	if others.is_empty():
		t._check("outfits", false, "no other characters")
		return
	# Stand somewhere open and line them up 4.5 m ahead, facing us.
	var spot: Vector3 = ch.global_position
	t._teleport(spot + Vector3.UP * 0.1, 0.0)
	await t._wait(0.3)
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, t.ctl.yaw, 0)).z
	var side := fwd.cross(Vector3.UP).normalized()
	var n := mini(others.size(), 7)
	var keys := {}
	var surf_max := 0
	var worst_list := []
	var looks := 0
	for i in n:
		var o = others[i]
		var p := spot + fwd * 4.5 + side * (float(i) - (n - 1) * 0.5) * 1.0
		p.y = world.map.ground_height(p.x, p.z) + 0.05
		o.global_position = p
		o.velocity = Vector3.ZERO
		o.yaw = t.ctl.yaw + PI
		var look: Dictionary = Net.players.get(o.pid, {}).get("look", {})
		if not look.is_empty():
			looks += 1
			keys[Outfit.key(Outfit.normalized(look))] = true
		var surfaces := 0
		var parts := []
		for mi in _meshes(o.visual.model if o.visual.model else o.visual):
			# The body only: the gun and its attachments are drawn the same as before.
			if mi.is_visible_in_tree() and mi.mesh and not o.visual.weapon_node.is_ancestor_of(mi):
				surfaces += mi.mesh.get_surface_count()
				parts.append("%s:%d" % [mi.name, mi.mesh.get_surface_count()])
		if surfaces > surf_max:
			worst_list = parts
		surf_max = maxi(surf_max, surfaces)
	t._look_at(spot + fwd * 4.5 + Vector3.UP * 1.0)
	await t._wait(0.5)
	for i in n:
		others[i].global_position.y = world.map.ground_height(others[i].global_position.x, others[i].global_position.z) + 0.05
	await t._wait(0.2)
	t._shot("outfits_lineup")
	t._check("outfits_vary", keys.size() >= mini(n, 5), "%d of %d characters carry a look; %d different outfits among them" % [looks, n, keys.size()])
	t._check("outfits_draws", surf_max <= 2 or worst_list.size() > 0 and false, "at most %d mesh surfaces per character body (outfit and head; the gun as before; the hooded body had 8): %s" % [surf_max, ", ".join(worst_list)])


func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

# ------------------------------------------------------------------ casings, muzzle smoke, suppression

func _realism() -> void:
	var fx = world.effects
	var ch = t.ch
	world.interaction.give(ch, {"id": "rifle_556", "n": 1})
	world.interaction.give(ch, {"id": "ammo_556", "n": 60})
	for s in [1, 2, 3]:
		if ch.wpn.slots[s] != null and str(ch.wpn.slots[s].id) == "rifle_556":
			await t._tap("weapon_%d" % s)
	await t._until(func(): return ch.wpn.current_id() == "rifle_556" and ch.wpn.can_fire(), 4.0)
	var c0 := int(fx.particles.emitted.get("casing", 0))
	var m0 := int(fx.particles.emitted.get("muzzle", 0))
	t.ctl.pitch = -0.1
	for i in 4:
		t._act_press("fire")
		await t._wait(0.08)
		if i == 1:
			t._shot("realism_firing")
		t._act_release("fire")
		await t._wait(0.18)
	await t._wait(0.3)
	var shots: int = ch.wpn.shots
	var casings := int(fx.particles.emitted.get("casing", 0)) - c0
	var smoke := int(fx.particles.emitted.get("muzzle", 0)) - m0
	t._check("casings", casings >= 2 and smoke >= 2, "%d casings and %d muzzle smoke puffs from a burst" % [casings, smoke])
	# A round from 30 m away passing 0.8 m from the player's head.
	var head: Vector3 = ch.eye_position()
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, t.ctl.yaw, 0)).z
	# A direction with nothing in the way for 9 m (indoors most directions end at a wall).
	var sp: PhysicsDirectSpaceState3D = ch.get_world_3d().direct_space_state
	for k in 16:
		var d := Basis(Vector3.UP, TAU * k / 16.0) * fwd
		var probe := PhysicsRayQueryParameters3D.create(head, head + d * 9.5 + d.cross(Vector3.UP).normalized() * 0.8, Defs.SHOT_MASK)
		probe.exclude = [ch.get_rid()]
		if sp.intersect_ray(probe).is_empty():
			fwd = d
			break
	var side := fwd.cross(Vector3.UP).normalized()
	var origin := head + fwd * 9.0 + side * 0.8
	var shooter = null
	for c in world.characters.values():
		if c != ch:
			shooter = c
			break
	if shooter:
		world.projectiles.spawn(shooter, {"ammo": "556", "velocity": 900.0, "origin": origin, "dir": (head + side * 0.8 - fwd * 5.0 - origin).normalized(), "seed": 5}, Net.tick, Net.tick)
		var seen := 0.0
		for i in 30:
			await t.get_tree().physics_frame
			seen = maxf(seen, world.hud._supp)
		t._check("suppression", seen > 0.15, "a supersonic round passing 0.8 m away darkened the view edges to %.2f" % seen)
