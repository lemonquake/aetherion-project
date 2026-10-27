extends RefCounted
## --autotest=fixes: measured checks for the 2026-10-27 fix list (stairs, loot on the floor, Tab on a box, doors,
## T to grab, the lite minimap and pings, vaulting, trash without collision, windows, weapons). Every check measures
## the effect the player sees or feels (positions reached, pixels, item counts), not a state flag.
##   godot --path game -- --host --bots=3 --autostart=1 --autotest=fixes --shots=<dir>

var t = null       # the autotest node (helpers: _teleport, _until, _hold, _shot, _check ...)
var world = null


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	## --fixes_only=stairs,vault,... runs just those checks (after the deploy) while iterating on one of them.
	var only := str(Game.arg("fixes_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	if want.call("loot"):
		_floor_weapons_census()
	await t._deploy()
	if not is_instance_valid(t.ch):
		return
	if not t.ch.light.on:
		await t._tap("flashlight")
	for step in [["use", _use_takes_items], ["stairs", _stairs_climb], ["loot", _floor_weapon_visible], ["tab", _tab_opens_box], ["grab", _grab_vs_use],
			["ping", _ping_minimap], ["doors", _doors], ["vault", _vault_window], ["trash", _trash_pass], ["weapons", _all_weapons],
			["grenade", _grenade]]:
		if want.call(step[0]) and is_instance_valid(t.ch):
			await (step[1] as Callable).call()
	if want.call("sounds"):
		_work_sounds()


## Further checks registered by later fixes (each a Callable returning after its awaits).
var extra: Array = []


# ------------------------------------------------------------------ loot on the floor

func _floor_weapons_census() -> void:
	## Guns lie on the floor of most houses: count floor weapon spots that produced a gun, per building.
	var dyn = world.map.dyn
	var with_gun := {}
	var guns := 0
	for id in dyn.items:
		var e: Dictionary = dyn.items[id].entry
		if Defs.is_weapon(str(e.id)):
			guns += 1
	for s in dyn.loot_spots:
		if str(s.table) == "floor_weapon" and not s.get("dropped", false) and int(s.bid) >= 0:
			with_gun[int(s.bid)] = true
	var houses := 0
	var houses_with := 0
	for b in world.map.buildings:
		if str(b.get("kind", "house")) in ["house", "apartment", "shop"]:
			houses += 1
			if with_gun.has(int(b.id)):
				houses_with += 1
	var frac := float(houses_with) / maxf(houses, 1)
	t._check("floor_guns_in_houses", frac >= 0.7 and guns > 2000,
		"%d guns on the ground; %d of %d houses/shops/apartments (%.0f%%) have one lying on a floor" % [guns, houses_with, houses, frac * 100.0])
	# Balikbayan boxes: share of rolls that are guns (from the table itself, the same odds the server rolls).
	var tb: Dictionary = Defs.loot.tables.box_balikbayan
	var tot := 0.0
	var gun_w := 0.0
	for e in tb.entries:
		tot += float(e[1])
		if Defs.is_weapon(str(e[0])):
			gun_w += float(e[1])
	t._check("balikbayan_has_guns", gun_w / tot > 0.25, "%.0f%% of balikbayan box rolls are a gun" % (gun_w / tot * 100.0))


func _floor_weapon_visible() -> void:
	## Stand 3 m from a gun on a house floor and measure it against the floor around it on screen.
	var dyn = world.map.dyn
	var ch = t.ch
	var best := -1
	var bd := INF
	for id in dyn.items:
		var e: Dictionary = dyn.items[id].entry
		if not Defs.is_weapon(str(e.id)):
			continue
		var p: Vector3 = (dyn.items[id].xf as Transform3D).origin
		if world.map.acoustics.zone_at(p + Vector3.UP * 0.3) == 0:
			continue
		var d := p.distance_to(ch.global_position)
		if d < bd:
			bd = d
			best = id
	if best < 0:
		t._check("floor_gun_visible", false, "no gun indoors")
		return
	var gp: Vector3 = (dyn.items[best].xf as Transform3D).origin
	if not t._stand_by(gp, gp.y, 2.6):
		t._stand_by(gp, gp.y, 1.6)
	await t._wait(0.6)
	t._look_at(gp)
	await t._wait(0.4)
	var cam: Camera3D = t.ctl.cam
	var inst: RID = dyn.items[best].get("inst", RID())
	var shown: Image = await _grab_view()
	RenderingServer.instance_set_visible(inst, false)
	var hidden: Image = await _grab_view()
	RenderingServer.instance_set_visible(inst, true)
	var sp := cam.unproject_position(gp + Vector3.UP * 0.03) * Vector2(shown.get_size()) / Vector2(t.get_viewport().get_visible_rect().size)
	var box := Rect2i(Vector2i(sp) - Vector2i(120, 80), Vector2i(240, 160)).intersection(Rect2i(Vector2i.ZERO, shown.get_size()))
	var changed := 0
	var lsum := 0.0
	for y in box.size.y:
		for x in box.size.x:
			var a := shown.get_pixel(box.position.x + x, box.position.y + y).get_luminance()
			var b := hidden.get_pixel(box.position.x + x, box.position.y + y).get_luminance()
			if absf(a - b) * 255.0 > 4.0:
				changed += 1
				lsum += a * 255.0
	await t._shot("floor_gun_%s" % str(dyn.items[best].entry.id))
	t._check("floor_gun_visible", changed >= 150,
		"%s at %.1f m in an unlit room, no flashlight: %d pixels show the gun (mean luma %.1f)" % [str(dyn.items[best].entry.id),
			gp.distance_to(ch.eye_position()), changed, lsum / maxf(changed, 1)])


func _grab_view() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return t.get_viewport().get_texture().get_image()


func _region_luma(img: Image, r: Rect2i) -> float:
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return 0.0
	var sum := 0.0
	for y in r.size.y:
		for x in r.size.x:
			sum += img.get_pixel(r.position.x + x, r.position.y + y).get_luminance()
	return sum / float(r.size.x * r.size.y) * 255.0


# ------------------------------------------------------------------ stairs

func _stairs_climb() -> void:
	## Walk up real flights in several houses: the player must reach the upper floor and step off on to it.
	var flights: Array = world.map.stairs
	t._check("stairs_recorded", flights.size() > 50, "%d indoor flights" % flights.size())
	if flights.is_empty():
		return
	var climbed := 0
	var landed := 0
	var fails := []
	var n := 24
	for k in n:
		var f: Dictionary = flights[(k * flights.size()) / n + (k * 7) % maxi(flights.size() / n, 1)]
		var dir: Vector3 = f.dir
		t._teleport((f.foot as Vector3) + Vector3.UP * 0.1, atan2(-dir.x, -dir.z))
		await t._wait(0.3)
		t._act_press("move_forward")
		var top: Vector3 = f.top
		var ok: bool = await t._until(func(): return t.ch.global_position.y > top.y - 0.4, 6.0)
		await t._wait(0.5)
		t._act_release("move_forward")
		if ok:
			climbed += 1
			# Step off sideways on to the landing.
			if fails.size() < 2:
				t.ctl.pitch = -0.2
				await t._shot("stair_top_%d" % k)
			var top_at: Vector3 = t.ch.global_position
			# Off the flight and into the room: toward the landing point, then a metre on across the floor.
			var inward: Vector3 = top - (f.foot as Vector3)
			inward = inward - dir * inward.dot(dir)
			inward.y = 0.0
			inward = inward.normalized()
			var goal: Vector3 = top + inward * 1.0
			var to: Vector3 = goal - t.ch.global_position
			t.ctl.yaw = atan2(-to.x, -to.z)
			t._act_press("move_forward")
			await t._until(func(): return Vector2(t.ch.global_position.x - goal.x, t.ch.global_position.z - goal.z).length() < 0.4, 1.6)
			t._act_release("move_forward")
			await t._wait(0.3)
			if t.ch.is_on_floor() and absf(t.ch.global_position.y - top.y) < 0.2:
				landed += 1
			else:
				fails.append("no landing at %s (got %s; at the top of the flight was %s)" % [str(top.snapped(Vector3.ONE * 0.1)), str(t.ch.global_position.snapped(Vector3.ONE * 0.1)),
					str(top_at.snapped(Vector3.ONE * 0.1))])
		else:
			var hits := []
			for i in t.ch.get_slide_collision_count():
				var sc: KinematicCollision3D = t.ch.get_slide_collision(i)
				var o = sc.get_collider()
				hits.append("%s n=%s" % [str(o.get_meta("prop_id", o.get_meta("door_id", o.name))) if o is Object else "?", str(sc.get_normal().snapped(Vector3.ONE * 0.01))])
			fails.append("stuck at %s, top %s, foot %s, hits %s, blocking boxes %s" % [str(t.ch.global_position.snapped(Vector3.ONE * 0.1)), str(top.snapped(Vector3.ONE * 0.1)),
				str((f.foot as Vector3).snapped(Vector3.ONE * 0.1)), str(hits), str(_blockers(f))])
			if fails.size() <= 2:
				t.ctl.pitch = -0.3
				await t._shot("stair_stuck_%d" % k)
		if k == 0:
			t.ctl.pitch = -0.5
			t.ctl.yaw += PI
			await t._shot("stair_down_view")
	t._check("stairs_climbable", climbed == n and landed == n, "%d of %d flights climbed, %d stepped off on the upper floor; %s" % [climbed, n, landed, str(fails)])


func _blockers(f: Dictionary) -> Array:
	## What the stuck player touches, probed with short rays (head up, forward at knee / chest / head, sideways),
	## in flight coordinates (x toward the landing side, y up from the foot, z along the flight).
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var dir: Vector3 = f.dir
	var side: Vector3 = ((f.top as Vector3) - (f.foot as Vector3))
	side = side - dir * side.dot(dir)
	side.y = 0.0
	side = side.normalized()
	var fb := Basis(side, Vector3.UP, dir)
	var p: Vector3 = t.ch.global_position
	var out := []
	for b in world.map.buildings:
		var lp: Vector3 = (b.xf as Transform3D).affine_inverse() * (f.foot as Vector3)
		if absf(lp.x) < float(b.w) * 0.5 + 0.1 and absf(lp.z) < float(b.d) * 0.5 + 0.6:
			out.append("building %d %s/%s %.1fx%.1f, foot at local %s" % [int(b.id), str(b.kind), str(b.district), float(b.w), float(b.d), str(lp.snapped(Vector3.ONE * 0.01))])
	var probes := {"up": [p + Vector3.UP * 1.5, Vector3.UP * 0.6], "fwd_knee": [p + Vector3.UP * 0.4, dir * 0.6],
		"fwd_chest": [p + Vector3.UP * 1.2, dir * 0.6], "fwd_head": [p + Vector3.UP * 1.7, dir * 0.6],
		"side_in": [p + Vector3.UP * 1.0, side * 0.6], "side_out": [p + Vector3.UP * 1.0, -side * 0.6],
		"up_fwd": [p + Vector3.UP * 1.5, (Vector3.UP + dir).normalized() * 0.8]}
	# Overhead, across the capsule's footprint: the lowest thing above the head.
	for ox in [-0.25, 0.0, 0.25]:
		for oz in [-0.25, 0.0, 0.25]:
			probes["up_%+.2f_%+.2f" % [ox, oz]] = [p + side * ox + dir * oz + Vector3.UP * 0.4, Vector3.UP * 1.6]
	for k in probes:
		var a: Vector3 = probes[k][0]
		var q := PhysicsRayQueryParameters3D.create(a, a + (probes[k][1] as Vector3), Defs.MOVE_MASK)
		q.exclude = [t.ch.get_rid()]
		var r := space.intersect_ray(q)
		if not r.is_empty():
			var rel: Vector3 = fb.inverse() * ((r.position as Vector3) - (f.foot as Vector3))
			var tri := ""
			if k.begins_with("up"):
				tri = str(r.keys()) + " shape " + str(r.get("shape", -1)) + " face " + str(r.get("face_index", -1))
			if k.begins_with("up") and int(r.get("face_index", -1)) >= 0:
				# The triangle hit, in flight coordinates: tells which piece of the house it is.
				var data = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(r.rid, int(r.shape)))
				if data is Dictionary and data.has("faces"):
					var fa: PackedVector3Array = data.faces
					var fi := int(r.face_index) * 3
					var bx: Transform3D = PhysicsServer3D.body_get_state(r.rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
					for j in 3:
						tri += str((fb.inverse() * (bx * fa[fi + j] - (f.foot as Vector3))).snapped(Vector3.ONE * 0.01))
			out.append("%s hit at %s n %s %s" % [k, str(rel.snapped(Vector3.ONE * 0.01)), str((fb.inverse() * (r.normal as Vector3)).snapped(Vector3.ONE * 0.01)), tri])
	return out


# ------------------------------------------------------------------ Tab on a loot box

func _tab_opens_box() -> void:
	## Stand beside a closed loot box (not pointing at it) and raise the SmarTab: its contents show on the Items page.
	var b := {}
	var bd := INF
	for lb in world.map.dyn.loot_boxes:
		var cc: Dictionary = world.map.dyn.containers[int(lb.cid)]
		if lb.open or str(lb.name) != "lootbox_balikbayan" or (cc.entries as Array).is_empty() or int(cc.bid) < 0:
			continue
		var dd := (cc.pos as Vector3).distance_to(t.ch.global_position)
		if dd < bd:
			bd = dd
			b = lb
	if b.is_empty():
		t._check("tab_opens_box", false, "no unopened balikbayan box with something in it")
		return
	var c: Dictionary = world.map.dyn.containers[int(b.cid)]
	if not t._stand_by(c.pos, (c.pos as Vector3).y - (c.size as Vector3).y * 0.5, 1.1):
		t._check("tab_opens_box", false, "no room beside the box")
		return
	await t._wait(0.4)
	t.ctl.yaw += 1.2  # looking past it, not at it
	t._act_press("smartab")
	var ok: bool = await t._until(func(): return not world.hud.smartab.container.is_empty(), 2.0)
	await t._wait(0.5)
	await t._shot("tab_box_items")
	var page := str(world.hud.smartab.PAGES[world.hud.smartab.page])
	var shown_id := int(world.hud.smartab.container.get("id", -1)) if ok else -1
	var shown_n := (world.hud.smartab.container.get("entries", []) as Array).size() if ok else 0
	var want_n := (world.map.dyn.containers[int(b.cid)].entries as Array).size()
	t._act_release("smartab")
	await t._wait(0.3)
	var shown_box: bool = shown_id >= 0 and world.map.dyn.containers[shown_id].has("box")
	var lid_open: bool = shown_box and bool(world.map.dyn.loot_boxes[int(world.map.dyn.containers[shown_id].box)].open)
	t._check("tab_opens_box", ok and page == "Items" and shown_box and lid_open and (shown_id != int(b.cid) or shown_n == want_n) and shown_n > 0,
		"beside %s: container shown %s (id %d, a loot box %s, walked to %d), page %s, its lid opened %s, %d entries listed (the box holds %d)" % [str(b.name), str(ok), shown_id, str(shown_box), int(b.cid), page, str(lid_open), shown_n, want_n])


# ------------------------------------------------------------------ T grabs, E uses

func _nearest_prop(pred: Callable) -> int:
	var dyn = world.map.dyn
	var best := -1
	var bd := INF
	for pr in dyn.props:
		if str(pr.state) != "dormant" or not pred.call(world.map.models.spec(str(pr.name))):
			continue
		var d := (pr.xf as Transform3D).origin.distance_to(t.ch.global_position)
		if d < bd:
			bd = d
			best = int(pr.id)
	return best


func _grab_vs_use() -> void:
	## Pointing at a loose object: E does nothing to it, T picks it up, T again puts it down.
	var pid := _nearest_prop(func(s): return float(s.get("mass", 99.0)) <= 6.0 and not s.get("no_block", false) and str(s.get("kind", "")) == "small")
	if pid < 0:
		t._check("grab_with_t", false, "no small prop")
		return
	var pr: Dictionary = world.map.dyn.props[pid]
	var pp: Vector3 = (pr.xf as Transform3D).origin
	if not t._stand_by(pp, pp.y, 1.1):
		t._check("grab_with_t", false, "no room beside %s" % str(pr.name))
		return
	await t._wait(0.4)
	t._look_at(pp + Vector3.UP * 0.08)
	await t._wait(0.2)
	var prompt := str(world.hud._prompt_text())
	await t._tap("interact")
	await t._wait(0.3)
	var after_e: int = t.ch.held_prop_id
	await t._tap("grab")
	var held: bool = await t._until(func(): return t.ch.held_prop_id >= 0, 1.0)
	await t._wait(0.3)
	await t._shot("grab_holding_%s" % str(pr.name))
	await t._tap("grab")
	var dropped: bool = await t._until(func(): return t.ch.held_prop_id < 0, 1.0)
	t._check("grab_with_t", after_e < 0 and held and dropped and prompt.begins_with("T "),
		"%s: prompt '%s', after E held %d, after T held %s, after second T dropped %s" % [str(pr.name), prompt, after_e, str(held), str(dropped)])


# ------------------------------------------------------------------ ping and the lite minimap

func _ping_minimap() -> void:
	## V: a radio click and your position blinking green on the minimap (top-left) for 5 s; enemies never shown.
	var mm = world.hud.minimap
	await t._shot("minimap_before_ping")
	await t._tap("ping")
	var ok: bool = await t._until(func(): return not mm.pings.is_empty(), 1.0)
	await t._wait(0.2)
	await RenderingServer.frame_post_draw
	var img: Image = t.get_viewport().get_texture().get_image()
	var scale := Vector2(img.get_size()) / Vector2(t.get_viewport().get_visible_rect().size)
	var r := Rect2i(Vector2i(mm.global_position * scale), Vector2i(mm.size * scale))
	var green := 0
	for y in r.size.y:
		for x in r.size.x:
			var c := img.get_pixel(r.position.x + x, r.position.y + y)
			if c.g > 0.55 and c.g > c.r * 1.5 and c.g > c.b * 1.4:
				green += 1
	await t._shot("minimap_ping")
	await t._wait(5.3)
	var gone: bool = mm.pings.is_empty()
	t._check("ping_minimap", ok and green > 12 and gone and mm.visible,
		"ping shown %s, %d green pixels in the minimap, cleared after 5 s %s, minimap visible %s at %s" % [str(ok), green, str(gone), str(mm.visible), str(mm.position)])


# ------------------------------------------------------------------ doors

func _nearest_door(shut: bool) -> Object:
	var best = null
	var bd := INF
	var space = world.get_world_3d().direct_space_state
	for dd in world.map.dyn.doors:
		var dn = dd.get("node")
		if dn == null or dn.locked or (shut and absf(dn.angle) > 0.01):
			continue
		if dn.center().distance_to(t.ch.global_position) > bd:
			continue
		# Both sides walkable: floor 1.2 m out on each side and nothing across the way at chest height.
		var n0: Vector3 = dn.base.basis.z.normalized()
		var mid: Vector3 = dn.base * Vector3(dn.w * 0.5, 0.0, 0.0)
		var ok := true
		for side in [1.0, -1.0]:
			var spot: Vector3 = mid + n0 * side * 1.2
			var fl = space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 0.5, Defs.PHYS_WORLD))
			if fl.is_empty() or absf((fl.position as Vector3).y - mid.y) > 0.25:
				ok = false
			var q := PhysicsRayQueryParameters3D.create(mid + Vector3.UP * 1.2, spot + Vector3.UP * 1.2, Defs.MOVE_MASK)
			q.exclude = [dn.body]
			if not space.intersect_ray(q).is_empty():
				ok = false
		if not ok:
			continue
		var d: float = dn.center().distance_to(t.ch.global_position)
		if d < bd:
			bd = d
			best = dn
	return best


func _doors() -> void:
	var dn = _nearest_door(true)
	if dn == null:
		t._check("door_opens_forward", false, "no shut door")
		return
	var n0: Vector3 = dn.base.basis.z.normalized()
	var mid: Vector3 = dn.base * Vector3(dn.w * 0.5, 0.0, 0.0)
	# Stand in front of the doorway on whichever side has floor, facing through it.
	var stood := false
	var space = world.get_world_3d().direct_space_state
	for side in [1.0, -1.0]:
		var spot: Vector3 = mid + n0 * side * 1.1
		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.0, spot + Vector3.DOWN * 0.6, Defs.PHYS_WORLD))
		if hit.is_empty() or absf((hit.position as Vector3).y - mid.y) > 0.3:
			continue
		t._teleport((hit.position as Vector3) + Vector3.UP * 0.05, 0.0)
		stood = true
		break
	if not stood:
		t._check("door_opens_forward", false, "no floor in front of door %d" % dn.id)
		return
	await t._wait(0.3)
	t._look_at(dn.center())
	var me_side := signf((t.ch.global_position - mid).dot(n0))
	await t._tap("interact")
	await t._until(func(): return not dn.moving, 2.0)
	var leaf_side := signf((dn.center() - mid).dot(n0))
	await t._shot("door_opened_forward")
	t._check("door_opens_forward", absf(dn.angle) > 1.2 and leaf_side != me_side,
		"door %d swung %.0f deg, leaf on the far side %s (player side %+.0f, leaf side %+.0f)" % [dn.id, rad_to_deg(dn.angle), str(leaf_side != me_side), me_side, leaf_side])
	# Walk through: the open leaf does not stop anyone.
	var start: Vector3 = t.ch.global_position
	var to_mid: Vector3 = mid - start
	t.ctl.yaw = atan2(-to_mid.x, -to_mid.z)
	t.ctl.pitch = 0.0
	t._act_press("move_forward")
	await t._until(func(): return signf((t.ch.global_position - mid).dot(n0)) != me_side, 3.0)
	await t._wait(0.5)
	t._act_release("move_forward")
	var through := signf((t.ch.global_position - mid).dot(n0)) != me_side
	var why := ""
	if not through:
		for i in t.ch.get_slide_collision_count():
			var sc: KinematicCollision3D = t.ch.get_slide_collision(i)
			why += " hit %s n %s at %s;" % [str(sc.get_collider()), str(sc.get_normal().snapped(Vector3.ONE * 0.01)), str(sc.get_position().snapped(Vector3.ONE * 0.01))]
		why += " door %d at %.0f deg, solid %s, mid %s, threshold heights %s" % [dn.id, rad_to_deg(dn.angle), str(dn._solid), str(mid.snapped(Vector3.ONE * 0.01)),
			str([-0.6, -0.3, 0.0, 0.3, 0.6].map(func(o): var hh = space.intersect_ray(PhysicsRayQueryParameters3D.create(mid + n0 * o + Vector3.UP * 1.5, mid + n0 * o + Vector3.DOWN * 1.0, Defs.MOVE_MASK)); return snappedf((hh.position as Vector3).y - mid.y, 0.01) if not hh.is_empty() else 99.0))]
	t._check("door_walk_through", through, "walked from %s through the doorway to %s%s" % [str(start.snapped(Vector3.ONE * 0.1)), str(t.ch.global_position.snapped(Vector3.ONE * 0.1)), why])
	# Push: stand facing the open leaf and run into it; it must swing away and keep going after contact.
	var a0: float = dn.angle
	dn.reset_state(0.9 * (signf(a0) if a0 != 0.0 else 1.0), false)
	world.map_door_ev.rpc(dn.id, false, dn.angle, dn.angle, false, "open")
	await t._wait(0.2)
	var b: Basis = dn.current_transform().basis
	var u: Vector3 = Vector3(b.x.x, 0.0, b.x.z).normalized()
	var n := Vector3(-u.z, 0.0, u.x)
	var leaf_mid: Vector3 = dn.base.origin + u * dn.w * 0.6
	# Stand facing the leaf's open-side face (from where a push opens it further) with a clear run at it.
	var spot2: Vector3 = leaf_mid + n * 1.2
	for cand in [leaf_mid + n * 1.1 - n0 * 0.7, leaf_mid + n * 0.9 - n0 * 1.0, leaf_mid + n * 1.2 - n0 * 0.4, leaf_mid + n * 1.2]:
		var cq := PhysicsRayQueryParameters3D.create((cand as Vector3) + Vector3.UP * 1.2, leaf_mid + Vector3.UP * 1.2, Defs.MOVE_MASK)
		cq.exclude = [dn.body]
		var cf = space.intersect_ray(PhysicsRayQueryParameters3D.create((cand as Vector3) + Vector3.UP * 1.0, (cand as Vector3) + Vector3.DOWN * 1.0, Defs.PHYS_WORLD))
		if space.intersect_ray(cq).is_empty() and not cf.is_empty() and absf((cf.position as Vector3).y - mid.y) < 0.3:
			spot2 = cand
			break
	var fl = space.intersect_ray(PhysicsRayQueryParameters3D.create(spot2 + Vector3.UP * 1.0, spot2 + Vector3.DOWN * 1.0, Defs.PHYS_WORLD))
	if fl.is_empty() or not t._stand_by(leaf_mid + Vector3.UP * 0.0, mid.y, 1.2):
		pass
	t._teleport(((fl.position as Vector3) if not fl.is_empty() else spot2) + Vector3.UP * 0.05, 0.0)
	var tl: Vector3 = leaf_mid - t.ch.global_position
	t.ctl.yaw = atan2(-tl.x, -tl.z)
	await t._wait(0.3)
	var before: float = dn.angle
	t._act_press("sprint")
	t._act_press("move_forward")
	await t._until(func(): return absf(dn.angle - before) > 0.15, 1.5)
	t._act_release("move_forward")
	t._act_release("sprint")
	# Step back off the leaf: whatever it does now is its own swing.
	t._teleport(t.ch.global_position + n * 1.0, t.ctl.yaw)
	var a1: float = dn.angle
	await t._wait(0.12)
	var swung := absf(dn.angle - before)
	var still_moving: bool = absf(dn.angle - a1) > 0.01
	await t._shot("door_pushed")
	await t._until(func(): return not dn.moving, 4.0)
	t._check("door_push_swings", swung > 0.3 and still_moving,
		"leaf at %.0f deg, shoved %.0f deg by a running player (swinging on its own afterwards %s), now %.0f deg" % [rad_to_deg(before), rad_to_deg(swung), str(still_moving), rad_to_deg(dn.angle)])
	# Swung back into the frame: latches shut (solid again, closing sound on the server). Nobody near it.
	t._teleport(mid + n0 * 4.0 + Vector3.UP * 0.1, 0.0)
	await t._wait(0.2)
	dn.reset_state(0.6, false)
	dn.free = true
	dn.omega = -3.0
	dn._start()
	var latched: bool = await t._until(func(): return absf(dn.angle) < 0.001 and not dn.moving, 2.0)
	t._check("door_latches_shut", latched and dn._solid, "angle %.3f, solid %s" % [dn.angle, str(dn._solid)])


# ------------------------------------------------------------------ vaulting

func _vault_window() -> void:
	## Jump right in front of an open window from inside: the player goes through it, the gun drops out of sight
	## while vaulting and comes back afterwards.
	world.interaction.give(t.ch, {"id": "rifle_556", "n": 1})
	var slot := 1
	for s in [1, 2, 3]:
		if t.ch.wpn.slots[s] != null and str(t.ch.wpn.slots[s].id) == "rifle_556":
			slot = s
	await t._tap("weapon_%d" % slot)
	await t._until(func(): return t.ch.wpn.current_id() == "rifle_556", 3.0)
	var tried := 0
	var done := 0
	var lowered := false
	var back := false
	var fails := []
	var space = world.get_world_3d().direct_space_state
	var wins := []
	for wnd in world.map.dyn.windows:
		if str(wnd.type) in ["open", "plastic"] and float(wnd.w) >= 0.75 and float(wnd.h) >= 0.9:
			wins.append(wnd)
	var here: Vector3 = t.ch.global_position
	wins.sort_custom(func(a, b): return (a.xf as Transform3D).origin.distance_to(here) < (b.xf as Transform3D).origin.distance_to(here))
	for wnd in wins:
		if tried >= 6:
			break
		var xf: Transform3D = wnd.xf
		var out: Vector3 = wnd.outward
		out.y = 0.0
		out = out.normalized()
		var sill: Vector3 = xf.origin - Vector3.UP * float(wnd.h) * 0.5
		var stand := sill - out * 0.75
		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 0.3, stand + Vector3.DOWN * 1.6, Defs.MOVE_MASK))
		if hit.is_empty():
			continue
		var feet: Vector3 = hit.position
		if sill.y - feet.y < 0.6 or sill.y - feet.y > 1.3:
			continue
		# Only windows with somewhere to land: open ground a step outside and nothing just beyond the opening (in the
		# packed rows many look straight at the next house's wall, which a vault rightly refuses).
		var outside := sill + out * 0.95
		var og = space.intersect_ray(PhysicsRayQueryParameters3D.create(outside + Vector3.UP * 0.3, outside + Vector3.DOWN * 2.0, Defs.MOVE_MASK))
		var through = space.intersect_ray(PhysicsRayQueryParameters3D.create(sill - out * 0.4 + Vector3.UP * 0.45, sill + out * 1.3 + Vector3.UP * 0.45, Defs.MOVE_MASK))
		if og.is_empty() or not through.is_empty():
			continue
		tried += 1
		t._teleport(feet + Vector3.UP * 0.05, atan2(-out.x, -out.z))
		await t._wait(0.5)
		var side0 = (t.ch.global_position - xf.origin).dot(out)
		Vault.find(t.ch)
		var reason := Vault.why
		await t._tap("jump")
		await t._wait(0.1)
		if t.ch.vault_t >= 0.0:
			await t._wait(0.12)
			if done == 0:
				await t._shot("vault_through_window")
			lowered = lowered or world.controller.vm._lower > 0.8
		await t._wait(0.9)
		var side1 = (t.ch.global_position - xf.origin).dot(out)
		if side0 < 0.0 and side1 > 0.2:
			done += 1
			await t._wait(0.5)
			back = back or (world.controller.vm._lower < 0.1 and t.ch.wpn.current_id() == "rifle_556")
		else:
			fails.append("window %d (%s, %.2fx%.2f, sill %.2f m): stayed at side %.2f (%s)" % [int(wnd.id), str(wnd.type), float(wnd.w), float(wnd.h), sill.y - feet.y, side1, reason])
	t._check("vault_through_window", done >= maxi(tried - 1, 1) and tried >= 3, "%d of %d windows vaulted through; %s" % [done, tried, str(fails)])
	t._check("vault_hides_weapon", lowered and back, "gun lowered while vaulting %s, back up after %s" % [str(lowered), str(back)])


# ------------------------------------------------------------------ trash

func _trash_pass() -> void:
	## A trash bag stops neither the player nor bullets; garbage heaps have no collision.
	var pid := _nearest_prop(func(s): return s.get("no_block", false))
	if pid < 0:
		t._check("trash_no_block", false, "no trash prop")
		return
	var pr: Dictionary = world.map.dyn.props[pid]
	var pp: Vector3 = (pr.xf as Transform3D).origin
	var space = world.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	q.shape = cap
	q.transform = Transform3D(Basis(), pp + Vector3.UP * 0.9)
	q.collision_mask = Defs.MOVE_MASK
	var blocked := false
	for b in space.intersect_shape(q, 8):
		if b.collider != null and b.collider.has_meta("prop_id") and int(b.collider.get_meta("prop_id")) == pid:
			blocked = true
	var shot := PhysicsRayQueryParameters3D.create(pp + Vector3(0, 0.15, -1.0), pp + Vector3(0, 0.15, 1.0), Defs.SHOT_MASK)
	var shot_hit = space.intersect_ray(shot)
	var hits_bag: bool = not shot_hit.is_empty() and shot_hit.collider != null and shot_hit.collider.has_meta("prop_id") and int(shot_hit.collider.get_meta("prop_id")) == pid
	var heaps := 0
	for sp in world.map.dyn.static_props:
		if str(sp[0]).begins_with("heap_"):
			heaps += 1
	t._check("trash_no_block", not blocked and not hits_bag,
		"%s: blocks movement %s, stops bullets %s; %d garbage heaps placed without collision" % [str(pr.name), str(blocked), str(hits_bag), heaps])


# ------------------------------------------------------------------ weapons, grenades, sounds

const WS := preload("res://src/weapons/weapon_state.gd")


func _rounds() -> int:
	## Rounds in the gun: magazine (tube, cylinder, barrels) plus the one in the chamber.
	var w: Dictionary = t.ch.wpn.weapon()
	return int(w.get("mag", 0)) + (1 if w.get("chamber", false) else 0)


func _all_weapons() -> void:
	## Every gun: has its own model and a gunshot sound, draws, fires, kicks the view up (recoil is meant to be
	## hard), reloads to a full magazine. Guns of one calibre share one ammunition (and its colour).
	var rows := []
	var bad := []
	var cal := {}
	for wid in Defs.weapons:
		var d: Dictionary = Defs.weapon(wid)
		cal[str(d.ammo)] = (cal.get(str(d.ammo), []) as Array) + [str(d.name)]
		var md: Dictionary = world.map.item_visual(wid)
		var snd := "shot_" + str(d.get("sound", ""))
		if md.get("mesh") == null or md.get("placeholder", false) or not SoundSys.defs.has(snd):
			bad.append("%s: model %s, sound %s" % [wid, str(md.get("mesh") != null), str(SoundSys.defs.has(snd))])
	var tested := 0
	for wid in Defs.weapons:
		var d: Dictionary = Defs.weapon(wid)
		# Fresh hands: empty the slots so the new gun is the one drawn.
		for s in [1, 2, 3]:
			t.ch.wpn.slots[s] = null
		world.interaction.give(t.ch, {"id": wid, "n": 1})
		world.interaction.give(t.ch, {"id": Defs.ammo_item(wid), "n": int(d.mag_size) * 3})
		var slot := 1
		for s in [1, 2, 3]:
			if t.ch.wpn.slots[s] != null and str(t.ch.wpn.slots[s].id) == wid:
				slot = s
		t.ctl.slot = slot
		var drawn: bool = await t._until(func(): return t.ch.wpn.current_id() == wid and t.ch.wpn.can_fire(), 4.0)
		if not drawn:
			bad.append("%s: not drawn" % wid)
			continue
		# Load it, and set full auto where the gun has it (B cycles the fire mode).
		await t._tap("reload")
		await t._until(func(): return t.ch.wpn.state == WS.IDLE and _rounds() >= int(d.mag_size), 12.0)
		var auto: bool = "auto" in (d.fire_modes as Array)
		for k in 3:
			if not auto or t.ch.wpn.fire_mode() == "auto":
				break
			await t._tap("fire_mode")
		t.ctl.pitch = 0.0
		var p0: float = t.ctl.pitch
		var shots0: int = t.ch.wpn.shots
		if auto:
			t._act_press("fire")
			await t._wait(0.6)
			t._act_release("fire")
		else:
			for k in 3:
				await t._tap("fire")
				await t._wait(maxf(60.0 / float(d.rpm), float(d.get("cycle_time", 0.0))) + 0.05)
		await t._wait(0.15)
		var fired: int = t.ch.wpn.shots - shots0
		var climb := rad_to_deg(t.ctl.pitch - p0)
		t.ctl.pitch = 0.0
		await t._tap("reload")
		var full: bool = await t._until(func(): return _rounds() >= int(d.mag_size) and t.ch.wpn.state != WS.RELOAD, 12.0)
		rows.append("%s %d shots, view +%.1f deg, reload %s" % [str(d.name), fired, climb, "ok" if full else "FAILED"])
		if fired < mini(3 if not auto else 2, int(d.mag_size)) or climb < 0.8 or not full:
			bad.append("%s: %d shots, climb %.1f deg, reloaded %s" % [wid, fired, climb, str(full)])
		tested += 1
		if tested == 1 or wid in ["rifle_scar", "smg_vector", "pistol_deagle"]:
			await t._shot("weapon_%s" % wid)
	print("[autotest] weapons: " + "; ".join(rows))
	t._check("all_weapons_work", bad.is_empty() and tested >= 24, "%d guns tested; problems: %s" % [tested, str(bad)])
	t._check("shared_calibres", (cal.get("556", []) as Array).size() >= 4 and (cal.get("762x39", []) as Array).size() >= 3,
		"by calibre: %s" % str(cal))


func _grenade() -> void:
	## A frag thrown at a teammate standing in the open hurts them; the bag loses one; the blast is loud.
	var mates: Array = t._teammates()
	if mates.is_empty():
		t._check("frag_grenade", false, "no teammate")
		return
	var mate = mates[0]
	t.ch.inv.bag.clear()  # the weapons check filled the bag with ammunition
	world.interaction.give(t.ch, {"id": "frag_grenade", "n": 2})
	var n0: int = t.ch.inv.take("frag_grenade", 0)
	var space = world.get_world_3d().direct_space_state
	var fwd: Vector3 = -Basis(Vector3.UP, t.ctl.yaw).z
	var spot: Vector3 = t.ch.global_position + fwd * 5.0
	var h = space.intersect_ray(PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 2.0, spot + Vector3.DOWN * 3.0, Defs.PHYS_WORLD))
	if not h.is_empty():
		spot = (h.position as Vector3) + Vector3.UP * 0.05
	var hp0: float = mate.health.health
	t.ctl.pitch = -0.35
	await t._tap("throw_grenade")
	var thrown: bool = await t._until(func(): return not world.grenades.live.is_empty(), 1.0)
	var count_after := 0
	for e in t.ch.inv.bag:
		if str(e.id) == "frag_grenade":
			count_after += int(e.n)
	var g_pos := Vector3.ZERO
	var shot_taken := false
	for i in 300:
		await t.get_tree().physics_frame
		if world.grenades.live.is_empty():
			break
		var g: Dictionary = world.grenades.live.values()[0]
		g_pos = g.p
		# Keep the teammate standing 2 m from the grenade on the side it came from (a clear line), and the thrower
		# well out of range.
		var back: Vector3 = -(g.v as Vector3) if (g.v as Vector3).length() > 0.1 else -fwd
		back.y = 0.0
		back = back.normalized() if back.length() > 0.01 else -fwd
		# Once it has stopped: stand the teammate 2 m off, on a side with a clear line from the blast.
		var spot_m: Vector3 = (g.p as Vector3) + back * 2.0
		if g.rest:
			for k in 8:
				var dv := Vector3(cos(k * TAU / 8.0), 0.0, sin(k * TAU / 8.0))
				var cand: Vector3 = (g.p as Vector3) + dv * 2.0
				var fl2 = space.intersect_ray(PhysicsRayQueryParameters3D.create(cand + Vector3.UP * 1.0, cand + Vector3.DOWN * 1.5, Defs.PHYS_WORLD))
				if fl2.is_empty():
					continue
				cand = fl2.position
				var los = space.intersect_ray(PhysicsRayQueryParameters3D.create((g.p as Vector3) + Vector3.UP * 0.15, cand + Vector3.UP * 1.0, Defs.PHYS_WORLD | Defs.PHYS_GLASS))
				if los.is_empty():
					spot_m = cand
					break
		mate.global_position = spot_m
		mate.velocity = Vector3.ZERO
		if t.ch.global_position.distance_to(g.p) < 14.0:
			t.ch.global_position = (g.p as Vector3) + back * 16.0 + Vector3.UP * 0.5
		t._look_at(g.p)
		if float(g.t) < 0.05 and not shot_taken:
			shot_taken = true
			_shoot_later("frag_explosion", 0.06)
	var hp1: float = mate.health.health
	t._check("frag_grenade", thrown and count_after == 1 and hp1 < hp0 - 10.0 and SoundSys.defs.has("explosion"),
		"thrown %s, frags left %d, teammate 2 m away %.0f -> %.0f health, exploded at %s" % [str(thrown), count_after, hp0, hp1, str(g_pos.snapped(Vector3.ONE * 0.1))])


func _work_sounds() -> void:
	## Every file from work/sounds is used by some sound and loads.
	var used := {}
	for sid in SoundSys.defs:
		for f in SoundSys.defs[sid].files:
			if str(f).begins_with("assets/audio/work/"):
				used[str(f)] = sid
	var missing := []
	var unloadable := []
	for group in ["buttons", "guns", "player"]:
		var dir := DirAccess.open("res://assets/audio/work/" + group)
		if dir == null:
			missing.append(group)
			continue
		for fn in dir.get_files():
			if not fn.ends_with(".mp3"):
				continue
			var path := "assets/audio/work/%s/%s" % [group, fn]
			if not used.has(path):
				missing.append(path)
			elif load("res://" + path) == null:
				unloadable.append(path)
	t._check("work_sounds_used", missing.is_empty() and unloadable.is_empty() and used.size() >= 46,
		"%d work/sounds files in use; unused %s; not loading %s" % [used.size(), str(missing), str(unloadable)])
	var dd: Dictionary = SoundSys.defs
	t._check("door_sounds_60", absf(float(dd.door_open.db) - (float(dd.door_open.db_full) - 4.437)) < 0.05 and absf(float(Settings.DEFAULTS.audio.ambience) - 0.6) < 0.001,
		"door open %.1f dB (was %.1f), door close %.1f dB (was %.1f), ambience default %.0f%%" % [float(dd.door_open.db), float(dd.door_open.db_full),
			float(dd.door_close.db), float(dd.door_close.db_full), float(Settings.DEFAULTS.audio.ambience) * 100.0])


func _shoot_later(name: String, s: float) -> void:
	await t._wait(s)
	await t._shot(name)


# ------------------------------------------------------------------ E takes weapons, ammunition, items

func _use_takes_items() -> void:
	## Items lying in front of the player: E takes a box of rounds, then a gun (T does not pick them up).
	t.ch.inv.bag.clear()
	var got := []
	for e in [{"id": "ammo_556", "n": 30}, {"id": "rifle_scar", "n": 1, "w": WS.new_instance("rifle_scar")}]:
		var id: int = t._spawn_in_front(e, 1.2)
		await t._wait(0.3)
		var it: Dictionary = world.map.dyn.items.get(id, {})
		if it.is_empty():
			got.append("%s: not spawned" % e.id)
			continue
		t._look_at((it.xf as Transform3D).origin + Vector3.UP * 0.03)
		await t._wait(0.2)
		await t._tap("grab")
		await t._wait(0.2)
		var after_t = world.map.dyn.items.has(id)
		await t._tap("interact")
		var taken: bool = await t._until(func(): return not world.map.dyn.items.has(id), 1.0)
		got.append("%s: T left it %s, E took it %s" % [str(e.id), str(after_t), str(taken)])
	var rounds: int = t.ch.inv.count("ammo_556")
	var has_scar := false
	for s in [1, 2, 3]:
		if t.ch.wpn.slots[s] != null and str(t.ch.wpn.slots[s].id) == "rifle_scar":
			has_scar = true
	t._check("use_takes_items", rounds >= 30 and has_scar and not ("T left it false" in str(got)),
		"%s; carrying %d 5.56 rounds, SCAR-L in a slot %s" % [str(got), rounds, str(has_scar)])
