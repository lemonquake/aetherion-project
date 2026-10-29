"""r4: blast finds doors by distance (world shapes swamped the query); tests: wall beside a door, props with 6+ chunks,
impact cost broken down by part."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import patch

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game'))
f = 'src/world/map_builder.gd'
patch(f, '''	q.collision_mask = Defs.PHYS_PROP | Defs.PHYS_WORLD | Defs.PHYS_PROJ_ONLY
	var seen := {}
	for r in space.intersect_shape(q, 96):
		var c = r.collider
		if c == null:
			continue
		if c.has_meta("prop_id"):''', '''	q.collision_mask = Defs.PHYS_PROP
	var seen := {}
	var hits := space.intersect_shape(q, 64)
	# Doors and shutters by distance: the world's own shapes would fill any shape query's result list.
	for d in dyn.doors:
		var dn = d.get("node")
		if dn and not dn.destroyed and (d.xf as Transform3D).origin.distance_to(pos) < radius + 1.0:
			hits.append({"collider": dn})
	for w in dyn.windows:
		if w.has("door") and not w.door.destroyed and (w.xf as Transform3D).origin.distance_to(pos) < radius + 1.0:
			hits.append({"collider": w.door})
	for r in hits:
		var c = r.collider
		if c == null:
			continue
		if c.has_meta("prop_id"):''')

f = 'src/debug/autotest_r4.gd'
patch(f, '''	var fx = world.effects
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
			break''', '''	var fx = world.effects
	# A house front: stand in front of the nearest outer door and aim at the wall beside it.
	var ch = t.ch
	var wall := {}
	var doors: Array = world.map.dyn.doors.filter(func(d): return d.get("node") != null and not d.node.destroyed and d.has("outward"))
	doors.sort_custom(func(a, b): return (a.xf as Transform3D).origin.distance_to(ch.global_position) < (b.xf as Transform3D).origin.distance_to(ch.global_position))
	for d in doors.slice(0, 25):
		var dn = d.node
		var xf: Transform3D = dn.current_transform()
		var out: Vector3 = d.outward
		var stand: Vector3 = dn.center() + out * 3.5
		var gy: float = world.map.ground_height(stand.x, stand.z)
		if absf(gy - xf.origin.y) > 0.6:
			continue
		t._teleport(Vector3(stand.x, xf.origin.y + 0.1, stand.z), 0.0)
		await t._wait(0.2)
		var side: Vector3 = xf.basis.x.normalized()
		for sgn in [-1.0, 1.0]:
			var target: Vector3 = dn.center() + side * sgn * (float(dn.w) * 0.5 + 0.7) + out * 0.02
			var eye: Vector3 = ch.eye_position()
			var q := PhysicsRayQueryParameters3D.create(eye, eye + (target - eye) * 1.3, Defs.SHOT_MASK)
			var h := ch.get_world_3d().direct_space_state.intersect_ray(q)
			if not h.is_empty() and h.collider and h.collider.has_meta("mat") and not h.collider.has_meta("door_id") \\
					and absf((h.normal as Vector3).y) < 0.3 and (h.position as Vector3).distance_to(target) < 0.6:
				wall = h
				t._look_at(h.position)
				break
		if not wall.is_empty():
			break''')
patch(f, '''		t._check("holes_wall", false, "no wall within 7 m of the landing spot")''', '''		t._check("holes_wall", false, "no house front found beside the 25 nearest doors")''')
patch(f, '''		if str(s.get("kind", "")) in ["chair", "table"] and p.state == "dormant":
			cands.append(p)''', '''		if str(s.get("kind", "")) in ["chair", "table"] and p.state == "dormant" \\
				and (Destruct.chunks_for(dyn.models, str(p.name)).get("keys", []) as Array).size() >= 6:
			cands.append(p)''')
patch(f, '''	var base: Array = []
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
		spots.size(), base[int(base.size() * 0.95)], busy[int(busy.size() * 0.95)]])''', '''	await t._wait(0.5)
	var parts := {}
	for mode in ["quiet", "all", "particles", "holes", "sound", "quiet2"]:
		var times: Array = []
		var cpu: Array = []
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
		times.sort()
		var c_sum := 0.0
		for c in cpu:
			c_sum += c
		parts[mode] = [times[times.size() / 2], times[int(times.size() * 0.95)], c_sum / 60.0]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var mb: float = (parts.quiet[0] + parts.quiet2[0]) * 0.5
	var detail := []
	for m in parts:
		detail.append("%s %.2f ms (p95 %.2f, call %.3f ms)" % [m, parts[m][0], parts[m][1], parts[m][2]])
	t._check("fx_perf", parts.all[0] - mb < 1.5, "median frame with an impact every frame vs quiet: " + "; ".join(detail))''')
