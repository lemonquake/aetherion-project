extends RefCounted
## r14 checks on a listen host (`--autotest=r14`, `--r14_only=zone,scopes,attach,smartab,highlight,grenade,spectate`):
##   godot --path game -- --host --game_mode=deathmatch --bots=20 --autostart=1 --autotest=r14 --shots=<dir>
## zone: Deathmatch runs its field at the fixed fast speed whatever the lobby said. scopes: each sight on a rifle,
## aimed, captured; the reticle drawn differs from every other one (pixel diff). attach: the new attachments change
## the numbers they say they change. smartab: the holographic SmarTab comes up from the watch, fills most of the
## view, drag and drop moves an attachment, swaps two guns, takes from the ground; useless items are red.
## highlight: loot that suits the player's guns is outlined green on the ground (captured with and without).
## grenade: cooked in the hand, thrown, explodes: door blown apart, props pushed, damage, the muffled hearing; held
## past the fuse it goes off in the hand. spectate (last, the player dies): frame times while watching a bot, and
## how evenly the bots near it move from frame to frame (stepping = the bot only simulated every few ticks).
## Measurements go to <shots>/r14_measure.json.

const WeaponState := preload("res://src/weapons/weapon_state.gd")

var t = null
var world = null
var measure := {}


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("r14_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 40.0)
	await t._wait(1.5)
	if want.call("zone"):
		_zone()
	world.map.lighting.forced_time = float(Game.arg("r14_time", 450.0))
	_freeze_zone()
	# Everyone waits at the spawn and the player cannot be hurt until the spectator check (which releases the bots
	# and kills the player itself).
	_holding = true
	_keep_holding()
	_freeze_bots(true)   # brains off too: a held bot still fights back, and a test's subject must not be shot
	t.ch.health.test_invulnerable = true
	for n in ["scopes", "attach", "smartab", "highlight", "grenade", "spectate"]:
		if want.call(n):
			if not is_instance_valid(t.ch) and n != "spectate":
				continue
			if n == "spectate":
				t.ch.health.test_invulnerable = false
				_holding = false
				_freeze_bots(false)
				_hold_bots(false)
			await (Callable(self, "_" + n)).call()
	var f := FileAccess.open(t.out_dir + "/r14_measure.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


# ------------------------------------------------------------------ helpers

func _freeze_zone() -> void:
	var ms = world.match_server
	if ms and not ms.zone.is_empty():
		ms.zone = {"i": 0, "state": "wait", "t0": Net.tick, "t1": Net.tick + 100000000, "c0": Vector2.ZERO, "r0": 9000.0, "c1": Vector2.ZERO,
			"r1": 9000.0, "dps": 0.0, "shrink_s": 60.0}
		ms._broadcast()


var _holding := false


func _keep_holding() -> void:
	## The round start (and every respawn) sets each bot's own hold again: keep them all holding until released.
	while _holding:
		_hold_bots(true)
		if not _frozen.is_empty() and not world.bots.is_empty():
			_freeze_bots(true)   # bots respawned since (Deathmatch) join the frozen ones
		await t._wait(0.25)


func _hold_bots(on: bool) -> void:
	for b in world.bots.values():
		b._dm_hold = 1.0e9 if on else 0.0


func _gun(wid: String, att: Array, slot: int = 1) -> void:
	## Only this gun carried (with ammunition), drawn and ready.
	for s in [1, 2, 3]:
		t.ch.wpn.slots[s] = null
	var w = WeaponState.new_instance(wid, null, 1.0)
	w.att = att.duplicate()
	t.ch.wpn.slots[slot] = w
	var ammo := "ammo_" + str(Defs.weapon(wid).get("ammo", ""))
	if t.ch.inv.count(ammo) < 60:
		t.ch.inv.add({"id": ammo, "n": 60}, true)
	t.ch.inv.mark_dirty()
	await t._tap("holster")
	await t._wait(0.25)
	await t._tap("weapon_%d" % slot)
	await t._until(func(): return t.ch.wpn.current_id() == wid and t.ch.wpn.state == WeaponState.IDLE, 4.0)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return t.get_viewport().get_texture().get_image()


func _spawn_at(entry: Dictionary, p: Vector3) -> int:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.DOWN * 2.0, Defs.PHYS_WORLD | Defs.PHYS_PROP))
	if not r.is_empty():
		p = r.position
	var id: int = world.map.dyn._next_item
	world.map_item_spawn_server(entry, Transform3D(Basis(Vector3.UP, 0.4), p + Vector3.UP * 0.01))
	return id


var _frozen := {}   # eid -> brain taken out of world.bots (it neither thinks nor sends commands)


func _freeze_bots(on: bool) -> void:
	## Every bot stops thinking and stands where it is (none shoots another mid-check); off puts the brains back.
	if on:
		for eid in world.bots.keys():
			_frozen[eid] = world.bots[eid]
			world.bots.erase(eid)
			world._bot_dt.erase(eid)
			world._queues[eid] = []
			if world.characters.has(eid):
				world.characters[eid].last_cmd = {}
	else:
		for eid in _frozen:
			if world.characters.has(eid) and is_instance_valid(world.characters[eid]):
				world._queues[eid] = []
				world.bots[eid] = _frozen[eid]
		_frozen.clear()


func _bots(team_mates: bool) -> Array:
	var out := []
	for b in world.bots.values() + _frozen.values():
		if is_instance_valid(b.ch) and b.ch.mode == Motor.GROUND and (b.ch.team == t.ch.team) == team_mates:
			out.append(b)
	return out


func _open_spot(centre: Vector3, dist: float, ang0: float) -> Vector3:
	## An outdoor spot about dist from centre, where a body fits, on the ground.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for k in 24:
		var a := ang0 + k * TAU / 24.0
		var p := centre + Vector3(cos(a), 0.0, sin(a)) * dist
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, centre.y + 6.0, p.z), Vector3(p.x, centre.y - 6.0, p.z), Defs.MOVE_MASK)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		p = (hit.position as Vector3) + Vector3.UP * 0.05
		if absf(p.y - centre.y) > 1.5 or world.map.acoustics.zone_at(p + Vector3.UP * 0.5) != 0:
			continue
		var sq := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.32
		cap.height = 1.7
		sq.shape = cap
		sq.transform = Transform3D(Basis(), p + Vector3.UP * 0.92)
		sq.collision_mask = Defs.MOVE_MASK
		if space.intersect_shape(sq, 1).is_empty():
			return p
	return centre


# ------------------------------------------------------------------ zone

func _zone() -> void:
	## The lobby's safe-zone speed is ignored in Deathmatch: its field always runs at rules deathmatch.zone_speed.
	var ms = world.match_server
	if ms == null or not Net.is_dm():
		t._check("r14_dm_zone_fixed", false, "not a deathmatch host")
		return
	var saved: float = float(Net.config.get("zone_speed", 1.0))
	var rows := []
	var ok := true
	var fast := float(Defs.rule("deathmatch.zone_speed", 1.6))
	for sp in [1.0, 2.5]:
		Net.config.zone_speed = sp
		ms.zone = {"i": -1, "state": "hold", "t0": Net.tick, "t1": Net.tick, "c0": Vector2.ZERO, "r0": 600.0, "c1": Vector2.ZERO, "r1": 600.0, "dps": 0.0}
		ms._next_zone()
		var wait_s := float(int(ms.zone.t1) - int(ms.zone.t0)) / Defs.TICK_RATE
		var want_s := float(Defs.rule("deathmatch.zone.phases", [])[0].wait) / fast
		rows.append([sp, snappedf(wait_s, 0.1), snappedf(float(ms.zone.shrink_s), 0.1)])
		ok = ok and absf(wait_s - want_s) < 0.2
	Net.config.zone_speed = saved
	var total := 0.0
	for ph in Defs.rule("deathmatch.zone.phases", []):
		total += (float(ph.wait) + float(ph.shrink)) / fast
	measure["zone"] = {"lobby_speed_vs_phase0": rows, "dm_total_s": total, "fast": fast}
	t._check("r14_dm_zone_fixed", ok, "lobby speed -> first wait/shrink (s): %s; the whole DM field closes in %.0f s at x%.1f" % [str(rows), total, fast])


# ------------------------------------------------------------------ spectate

func _spectate() -> void:
	## The player is killed; after the death camera the view follows a teammate bot. Measured over 8 s: frame times,
	## and for the bots within 60 m of the one watched, how evenly each moves per frame (the share of frames a moving
	## bot did not move at all; a bot simulated every 4th tick stands still three frames out of four at 60 fps).
	if not is_instance_valid(t.ch):
		return
	for b in world.bots.values():
		b._dm_hold = 0.0
	var en := _bots(false)
	var mates := _bots(true)
	if en.is_empty() or mates.is_empty():
		t._check("r14_spectate_smooth", false, "need an enemy and a teammate bot (%d / %d)" % [en.size(), mates.size()])
		return
	# A few enemies near the teammate who will be watched, so there is something to watch.
	var watch_b = mates[0]
	for i in mini(4, en.size()):
		en[i].ch.global_position = _open_spot(watch_b.ch.global_position, 18.0 + i * 6.0, float(i) * 1.3)
	var k = en[0]
	# Frame rate without the vsync cap: first alive (first person, facing the bot that will be watched), then dead.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	t._look_at(watch_b.ch.global_position + Vector3.UP)
	t._perf_begin("alive_ref")
	await t._wait(5.0)
	t._perf_end()
	var alive_row: Dictionary = t._perf_report[-1] if not t._perf_report.is_empty() else {}
	if is_instance_valid(t.ch) and t.ch.mode != Motor.DEAD and is_instance_valid(k.ch):
		var pos: Vector3 = t.ch.global_position
		var res: Dictionary = t.ch.health.apply_simple(999.0, "gunshot", "torso", k.ch.eid)
		res["hit_part"] = "torso"
		res["hit_dir"] = (pos - k.ch.global_position).normalized()
		world._after_damage(t.ch, res, k.ch.eid)
	await t._until(func(): return t.ctl._death.is_empty() and t.ctl.spectating >= 0, 12.0)
	await t._wait(1.0)
	var watched = world.characters.get(t.ctl.spectating)
	if watched == null:
		t._check("r14_spectate_smooth", false, "not spectating anyone")
		return
	await t._shot("spectate")
	var near := []
	for c in world.characters.values():
		if c != watched and c.mode == Motor.GROUND and c.global_position.distance_to(watched.global_position) < 60.0:
			near.append(c)
	near.append(watched)
	var last := {}
	var steps := {}
	for c in near:
		steps[c.eid] = []
	t._perf_begin("spectate")
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await t.get_tree().process_frame
		frames += 1
		for c in near:
			if not is_instance_valid(c):
				continue
			var p: Vector3 = c.get_global_transform_interpolated().origin
			if last.has(c.eid):
				(steps[c.eid] as Array).append(p.distance_to(last[c.eid]))
			last[c.eid] = p
	t._perf_end()
	var row: Dictionary = t._perf_report[-1] if not t._perf_report.is_empty() else {}
	var still_frames := 0
	var moving_frames := 0
	var per_bot := []
	for eid in steps:
		var arr: Array = steps[eid]
		if arr.size() < 30:
			continue
		var total := 0.0
		for v in arr:
			total += v
		if total < 1.0:
			continue  # standing about: nothing to judge
		# Frames it stood still in the middle of moving (moved within 3 frames either side): a bot that stops for a
		# while is not counted, one that steps every few ticks is.
		var still := 0
		var n_mid := 0
		for i in range(3, arr.size() - 3):
			var moving := false
			for j in range(i - 3, i + 4):
				if j != i and float(arr[j]) > 0.002:
					moving = true
			if not moving:
				continue
			n_mid += 1
			if float(arr[i]) < 0.0005:
				still += 1
		still_frames += still
		moving_frames += n_mid
		per_bot.append([str(world.characters[eid].pname) if world.characters.has(eid) else str(eid), n_mid, snappedf(float(still) / maxf(n_mid, 1.0), 0.01)])
	var still_share := float(still_frames) / maxf(moving_frames, 1.0)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	measure["spectate"] = {"fps": row.get("fps", 0.0), "p99_ms": row.get("p99", 0.0), "over_16ms": row.get("over_16ms", 0), "still_share": still_share,
		"per_bot": per_bot, "frames": frames, "watched": watched.pname, "near": near.size(), "alive_fps": alive_row.get("fps", 0.0), "alive_p99": alive_row.get("p99", 0.0)}
	t._check("r14_spectate_fps", float(row.get("fps", 0.0)) >= 0.8 * float(alive_row.get("fps", 0.0)) and float(row.get("p99", 99.0)) < 25.0,
		"watching %s: %.0f fps, p99 %.1f ms, %d frames over 16.7 ms (alive, first person at the same spot: %.0f fps, p99 %.1f ms)" % [watched.pname,
		float(row.get("fps", 0.0)), float(row.get("p99", 0.0)), int(row.get("over_16ms", 0)), float(alive_row.get("fps", 0.0)), float(alive_row.get("p99", 0.0))])
	t._check("r14_spectate_smooth", moving_frames > 0 and still_share < 0.12,
		"moving bots near the one watched stood still in %.0f%% of frames (%s)" % [still_share * 100.0, str(per_bot)])


# ------------------------------------------------------------------ scopes

const Attach := preload("res://src/weapons/attachments.gd")
const SIGHTS := ["sight_reddot", "sight_holo", "sight_reflex", "scope_2x", "scope_3x", "scope_4x", "scope_lpvo", "scope_6x",
	"scope_8x", "scope_night", "scope_thermal", "scope_15x"]
const MASK_N := 128


func _reticle_mask(img: Image) -> PackedByteArray:
	## The middle of the view (a square 60% of its height) at MASK_N x MASK_N: 1 where a pixel differs clearly from
	## the median colour of its row (the sky behind the reticle), else 0.
	var sz := img.get_size()
	var side := int(sz.y * 0.6)
	var c := img.get_region(Rect2i((sz.x - side) / 2, (sz.y - side) / 2, side, side))
	c.convert(Image.FORMAT_RGB8)
	c.resize(MASK_N, MASK_N, Image.INTERPOLATE_BILINEAR)
	var out := PackedByteArray()
	out.resize(MASK_N * MASK_N)
	for y in MASK_N:
		var rs := []
		var gs := []
		var bs := []
		for x in MASK_N:
			var px := c.get_pixel(x, y)
			rs.append(px.r)
			gs.append(px.g)
			bs.append(px.b)
		rs.sort()
		gs.sort()
		bs.sort()
		var med := Color(rs[MASK_N / 2], gs[MASK_N / 2], bs[MASK_N / 2])
		for x in MASK_N:
			var px := c.get_pixel(x, y)
			var d := maxf(absf(px.r - med.r), maxf(absf(px.g - med.g), absf(px.b - med.b)))
			out[y * MASK_N + x] = 1 if d > 0.09 else 0
	return out


static func _iou(a: PackedByteArray, b: PackedByteArray) -> float:
	var inter := 0
	var uni := 0
	for i in a.size():
		if a[i] or b[i]:
			uni += 1
			if a[i] and b[i]:
				inter += 1
	return float(inter) / maxf(uni, 1.0)


func _scopes() -> void:
	## Every sight fitted in turn and aimed at an empty patch of sky: the eyepiece is captured and the reticle cut out
	## of it (pixels unlike the sky round them). No two reticles may overlap by more than 70%. The night vision and
	## thermal scopes filter the picture; the thermal scope shows a body in the open white hot; the wheel turns the
	## 1-4x scope's magnification ring.
	if t.ch.light.on:
		await t._tap("flashlight")
	var spot: Vector3 = t._open_patch(t.ch.global_position)
	t._teleport(spot + Vector3.UP * 0.1, 0.0)
	await t._wait(0.5)
	var masks := {}
	var counts := {}
	var aligned := {}
	for sid in SIGHTS:
		var wid := "rifle_556" if Attach.compatible("rifle_556", sid) else "marksman_308"
		await _gun(wid, [sid])
		t.ctl.pitch = deg_to_rad(62.0)   # high up: plain sky behind the reticle
		t._act_press("aim")
		await t._wait(1.3)
		var img := await _grab()
		await t._shot("sight_" + sid)
		if not bool(Defs.attachments[sid].get("scope", false)):
			# A sight seen through (not magnified): its window must sit on the line the bullets take, up or level.
			var err_up: float = t._sight_screen_error(wid, sid)
			t.ctl.pitch = 0.0
			await t._wait(0.6)
			aligned[sid] = [snappedf(err_up, 0.1), snappedf(t._sight_screen_error(wid, sid), 0.1)]
		t._act_release("aim")
		await t._wait(0.3)
		masks[sid] = _reticle_mask(img)
		var n := 0
		for v in masks[sid]:
			n += v
		counts[sid] = n
	var worst := ["", "", 0.0]
	var empty := []
	for i in SIGHTS.size():
		if int(counts[SIGHTS[i]]) < 25:
			empty.append(SIGHTS[i])
		for j in range(i + 1, SIGHTS.size()):
			var o := _iou(masks[SIGHTS[i]], masks[SIGHTS[j]])
			if o > float(worst[2]):
				worst = [SIGHTS[i], SIGHTS[j], o]
	var styles := {}
	for sid in SIGHTS:
		styles[str(Defs.attachments[sid].get("reticle", ""))] = true
	measure["scopes"] = {"pixels": counts, "most_alike": worst, "styles": styles.keys(), "sight_error_px_up_level": aligned}
	var off_line := []
	for sid in aligned:
		if float(aligned[sid][0]) > 8.0 or float(aligned[sid][1]) > 8.0:
			off_line.append(sid)
	t._check("r14_sights_on_line", off_line.is_empty() and aligned.size() == 3,
		"sight window vs where the bullets go, px (looking up 62 deg, level): %s" % str(aligned))
	t._check("r14_scopes_unique", empty.is_empty() and float(worst[2]) < 0.7 and styles.size() == SIGHTS.size(),
		"%d sights, %d reticle styles; most alike: %s / %s overlap %.0f%%; reticle pixels %s%s" % [SIGHTS.size(), styles.size(),
		worst[0], worst[1], float(worst[2]) * 100.0, str(counts), ("; nothing drawn for " + str(empty)) if not empty.is_empty() else ""])
	# Night vision: the eyepiece goes green. Thermal: an enemy standing 22 m away in the open shows white hot.
	var en := _bots(false)
	var filters := {}
	for sid in ["scope_night", "scope_thermal"]:
		await _gun("rifle_556", [sid])
		en = _bots(false)
		var fwd: Vector3 = -Basis.from_euler(Vector3(0, t.ctl.yaw, 0)).z
		var body_at := Vector3.INF
		if not en.is_empty():
			body_at = _open_spot(t.ch.global_position + fwd * 22.0, 0.5, 0.0)
			en[0].ch.global_position = body_at
			en[0].ch.velocity = Vector3.ZERO
			await t._wait(0.3)
			t._look_at(body_at + Vector3.UP * 1.2)
		t._act_press("aim")
		await t._wait(1.3)
		var img2 := await _grab()
		await t._shot("sight_%s_body" % sid)
		var sc = world.hud.scope
		var vs: Vector2 = t.get_viewport().get_visible_rect().size
		var isz := img2.get_size()
		var mid := img2.get_region(Rect2i(int(isz.x * 0.5 - isz.y * 0.3), int(isz.y * 0.2), int(isz.y * 0.6), int(isz.y * 0.6)))
		mid.convert(Image.FORMAT_RGB8)
		mid.resize(48, 48)
		var sum := Color(0, 0, 0)
		for y in 48:
			for x in 48:
				sum += mid.get_pixel(x, y)
		sum /= 48.0 * 48.0
		var hot := 0.0
		if sid == "scope_thermal" and body_at != Vector3.INF:
			var bp: Vector2 = t.ctl.cam.unproject_position(body_at + Vector3.UP * 1.2) * (Vector2(isz) / vs)
			var bimg := img2.get_region(Rect2i(int(bp.x) - 3, int(bp.y) - 3, 7, 7))
			for y in 7:
				for x in 7:
					hot = maxf(hot, bimg.get_pixel(x, y).get_luminance())
		filters[sid] = {"on": sc._filter.visible, "mode": sc._mode, "mean": [snappedf(sum.r, 0.01), snappedf(sum.g, 0.01), snappedf(sum.b, 0.01)],
			"heat_bodies": sc._heat.size(), "body_luma": snappedf(hot, 0.01)}
		if sid == "scope_thermal" and not en.is_empty() and is_instance_valid(en[0].ch):
			# Why a body would not show: what the overlay's own tests see for it.
			var c = en[0].ch
			var eye: Vector3 = t.ctl.cam.global_position
			var chest: Vector3 = c.get_global_transform_interpolated().origin + Vector3.UP * c.height() * 0.72
			var hit = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, chest, Defs.PHYS_WORLD))
			filters[sid]["probe"] = {"mode": c.mode, "dist": snappedf(eye.distance_to(chest), 0.1), "behind": t.ctl.cam.is_position_behind(chest),
				"from_centre_px": snappedf(t.ctl.cam.unproject_position(chest).distance_to(sc._center), 0.1), "radius": sc._radius,
				"blocked_by": str(hit.collider.name) if not hit.is_empty() and hit.collider else "", "world_set": sc.world != null, "chars": world.characters.size()}
			print("[r14] thermal probe ", filters[sid]["probe"])
		t._act_release("aim")
		await t._wait(0.3)
	measure["scope_filters"] = filters
	var nv: Dictionary = filters.get("scope_night", {})
	var th: Dictionary = filters.get("scope_thermal", {})
	var green: bool = not nv.is_empty() and float(nv.mean[1]) > float(nv.mean[0]) * 1.3 and float(nv.mean[1]) > float(nv.mean[2]) * 1.3
	t._check("r14_scope_night", bool(nv.get("on", false)) and green, "night vision filter %s, eyepiece mean colour %s" % [str(nv.get("on")), str(nv.get("mean"))])
	t._check("r14_scope_thermal", bool(th.get("on", false)) and int(th.get("heat_bodies", 0)) >= 1 and float(th.get("body_luma", 0.0)) > 0.75,
		"thermal filter %s, %d warm bodies in the lens, brightest pixel on the enemy %.2f" % [str(th.get("on")), int(th.get("heat_bodies", 0)), float(th.get("body_luma", 0.0))])
	# The 1-4x scope: the wheel (next weapon) while aiming turns the ring down and keeps the gun in hand.
	await _gun("rifle_556", ["scope_lpvo"])
	t._act_press("aim")
	await t._wait(1.2)
	var z0: float = t.ch.wpn.zoom()
	var fov0: float = t.ctl.cam.fov
	for i in 3:
		await t._tap("next_weapon")
	await t._wait(0.6)
	var z1: float = t.ch.wpn.zoom()
	var fov1: float = t.ctl.cam.fov
	await t._shot("sight_scope_lpvo_turned_down")
	t._act_release("aim")
	await t._wait(0.3)
	t._check("r14_scope_variable", z0 > 3.9 and z1 < z0 * 0.6 and fov1 > fov0 * 1.4 and t.ch.wpn.current_id() == "rifle_556",
		"1-4x scope: %.2fx -> %.2fx after three wheel steps, field of view %.1f -> %.1f, gun in hand %s" % [z0, z1, fov0, fov1, t.ch.wpn.current_id()])


# ------------------------------------------------------------------ attach

const NEW_ATT := ["sight_reflex", "scope_lpvo", "scope_night", "scope_thermal", "scope_15x", "muzzle_brake", "duckbill", "grip_thumb",
	"grip_light", "grip_ergonomic", "stock_heavy", "mag_extquick_light", "mag_extquick_rifle", "mag_quick_light", "mag_quick_rifle"]
const STAT_KEYS := ["recoil_up_mult", "recoil_side_mult", "recovery_mult", "ads_time_mult", "reload_mult", "sway_mult",
	"spread_hip_mult", "move_spread_mult", "pellet_spread_mult", "loudness_mult", "flash_mult"]


func _gun_for(att: String) -> String:
	for wid in ["rifle_m416", "rifle_556", "smg_9", "marksman_308", "shotgun_pump", "machine_pistol", "bolt_308"]:
		if Attach.compatible(wid, att):
			return wid
	for wid in Defs.weapons:
		if Attach.compatible(str(wid), att):
			return str(wid)
	return ""


func _measure_gun(wid: String, att: Array) -> Dictionary:
	## The numbers the weapon code works with, measured on a gun held by the player (a separate weapon state, so the
	## player's own is untouched): first-shot recoil, recoil recovery, aim time, reload time, sway, spread.
	var ws = WeaponState.new(t.ch)
	var w = WeaponState.new_instance(wid, null, 1.0)
	w.att = att.duplicate()
	ws.slots[1] = w
	ws.cur = 1
	ws.want = 1
	ws.ads = 0.0
	var out := {}
	ws.burst = 1
	ws._apply_recoil(424242)
	out["recoil_up_mult"] = ws.climb_pending + ws.kick.y
	out["recoil_side_mult"] = absf(ws.yaw_pending + ws.kick.x)
	ws.kick = Vector2(0.0, 5.0)
	ws.since_shot = 1.0
	ws._recover(0.05)
	out["recovery_mult"] = 5.0 - ws.kick.y
	out["ads_time_mult"] = ws._ads_mult()
	w.mag = 0
	w.chamber = true
	ws.state = WeaponState.IDLE
	ws.start_reload()
	out["reload_mult"] = ws.timer if ws.state == WeaponState.RELOAD else -1.0
	ws.state = WeaponState.IDLE
	out["sway_mult"] = ws.sway_deg(777).length()
	out["spread_hip_mult"] = ws.spread_deg(0.0, false)
	out["move_spread_mult"] = ws.spread_deg(4.0, false) / maxf(ws.spread_deg(0.0, false), 1e-6) - 1.0
	out["pellet_spread_mult"] = Attach.mult(w, "pellet_spread_mult")
	out["loudness_mult"] = Attach.mult(w, "loudness_mult")
	out["flash_mult"] = Attach.mult(w, "flash_mult")
	out["zoom"] = ws.zoom()
	out["mag"] = ws.mag_cap()
	return out


func _attach() -> void:
	## Each new attachment on a gun that takes it: every number it lists changes by that factor and nothing else
	## moves; scopes have their magnification, extended magazines hold more.
	var rows := []
	var bad := []
	for att in NEW_ATT:
		var wid := _gun_for(att)
		if wid == "":
			bad.append("%s: no gun takes it" % att)
			continue
		var a: Dictionary = Defs.attachments[att]
		var base := _measure_gun(wid, [])
		var with := _measure_gun(wid, [att])
		var changed := []
		for key in STAT_KEYS:
			var b := float(base[key])
			var v := float(with[key])
			if absf(b) < 1e-6:
				continue
			var ratio := v / b
			var want := float(a.get(key, 1.0))
			if absf(ratio - want) > 0.02 * maxf(want, 0.1):
				bad.append("%s on %s: %s x%.3f, says x%.2f" % [att, wid, key, ratio, want])
			elif a.has(key):
				changed.append("%s x%.2f" % [key.trim_suffix("_mult"), ratio])
		if a.has("zoom"):
			if absf(float(with.zoom) - float(a.zoom)) > 0.01:
				bad.append("%s: zoom %.2f, says %.2f" % [att, float(with.zoom), float(a.zoom)])
			else:
				changed.append("zoom %.1fx" % float(with.zoom))
		if bool(a.get("ext", false)):
			if int(with.mag) <= int(base.mag):
				bad.append("%s on %s: magazine %d -> %d" % [att, wid, int(base.mag), int(with.mag)])
			else:
				changed.append("mag %d->%d" % [int(base.mag), int(with.mag)])
		rows.append([att, wid, changed])
	measure["attach"] = {"rows": rows, "bad": bad}
	var lines := []
	for r in rows:
		lines.append("%s (%s): %s" % [r[0], r[1], ", ".join(r[2])])
	t._check("r14_attach_numbers", bad.is_empty() and rows.size() == NEW_ATT.size(), "%d attachments measured: %s%s" % [rows.size(),
		"; ".join(lines), ("; WRONG: " + "; ".join(bad)) if not bad.is_empty() else ""])
	# Their models on the gun in first person (one capture with a full new kit).
	await _gun("rifle_m416", ["sight_reflex", "muzzle_brake", "grip_ergonomic", "stock_heavy", "mag_extquick_rifle"])
	t.ctl.pitch = -0.05
	await t._wait(0.6)
	await t._shot("attach_m416_new_kit")


# ------------------------------------------------------------------ smartab

func _holo_to_window(p: Vector2) -> Vector2:
	## A point on the SmarTab picture (design units, 1600 x 960) to window pixels, through the hologram in 3D.
	var vm = t.ctl.vm
	var uv := p / Vector2(1600.0, 960.0)
	var wp: Vector3 = vm.tab_screen.global_transform * Vector3(uv.x - 0.5, 0.5 - uv.y, 0.0)
	var vp: Vector2 = vm.cam.unproject_position(wp)
	return t.get_tree().root.get_final_transform() * vp


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)


func _mouse_move(pos: Vector2, mask: int) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.button_mask = mask
	Input.parse_input_event(ev)


func _holo_drag(from_d: Vector2, to_d: Vector2) -> void:
	## Press on one point of the hologram, move the mouse over, let go on another (as a player drags).
	var a := _holo_to_window(from_d)
	_mouse_move(a, 0)
	await t.get_tree().process_frame
	_mouse_button(a, true)
	for i in 3:
		await t.get_tree().process_frame
	for i in 14:
		_mouse_move(_holo_to_window(from_d.lerp(to_d, float(i + 1) / 14.0)), MOUSE_BUTTON_MASK_LEFT)
		await t.get_tree().process_frame
	await t._wait(0.15)
	_mouse_button(_holo_to_window(to_d), false)
	await t._wait(0.5)


func _hit_rect(pred: Callable) -> Rect2:
	var st = world.hud.smartab
	for i in range(st._hits.size() - 1, -1, -1):
		if pred.call(st._hits[i][1]):
			return st._hits[i][0]
	return Rect2()


func _smartab() -> void:
	## Hold TAB: the arm comes up, the watch projects the hologram, which fills most of the view. Real mouse drags on
	## it (through the hologram in 3D, as the player's mouse goes): a grip from the bag onto the rifle's grip mount,
	## the rifle's card onto the SMG's (they swap, the rifle stays in hand), a box of rounds from the ground into the
	## bag. Rounds no carried gun fires are red in the bag.
	var spot: Vector3 = t._open_patch(t.ch.global_position)
	t._teleport(spot + Vector3.UP * 0.1, 0.0)
	await t._wait(0.4)
	await _gun("rifle_556", [], 1)
	t.ch.wpn.slots[2] = WeaponState.new_instance("smg_9", null, 1.0)
	t.ch.inv.add({"id": "grip_thumb", "n": 1}, true)
	t.ch.inv.add({"id": "ammo_308", "n": 20}, true)
	t.ch.inv.add({"id": "bandage", "n": 2}, true)
	t.ch.inv.mark_dirty()
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, t.ctl.yaw, 0)).z
	var gid := _spawn_at({"id": "ammo_9x19", "n": 30}, t.ch.global_position + fwd * 1.3)
	var n9: int = t.ch.inv.count("ammo_9x19")
	t.ctl.pitch = -0.2
	t._act_press("smartab")
	await t._wait(0.18)
	await t._shot("smartab_rising")
	var watch_on: bool = t.ctl.vm.watch.visible
	await t._wait(1.1)
	var vm = t.ctl.vm
	var st = world.hud.smartab
	var vs: Vector2 = t.get_viewport().get_visible_rect().size
	var frac_h: float = float(vm.panel_px_h) / vs.y
	var c0 := _holo_to_window(Vector2(0, 0))
	var c1 := _holo_to_window(Vector2(1600, 960))
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	var frac_w := absf(c1.x - c0.x) / win.x
	await t._shot("smartab_inventory")
	# Red: the .308 rounds in the bag (neither gun fires them), drawn with a red edge in the picture itself.
	var r308 := _hit_rect(func(h): return str(h.get("kind", "")) == "bag" and str(h.e.id) == "ammo_308")
	var red := false
	if r308.has_area():
		var pic: Image = world.hud.smartab_vp.get_texture().get_image()
		var k: float = st.scale.x
		var px := pic.get_pixel(int((r308.position.x + 2.0) * k), int((r308.position.y + r308.size.y * 0.5) * k))
		red = px.r > 0.7 and px.g < 0.5 and px.b < 0.5
	var mark308: String = st._mark(t.ch, {"id": "ammo_308", "n": 20}, false)
	t._check("r14_smartab_up", watch_on and frac_h > 0.72 and frac_w > 0.6 and vm.tab_root.visible,
		"watch on the wrist %s; hologram %.0f%% of the view's height, %.0f%% of its width" % [str(watch_on), frac_h * 100.0, frac_w * 100.0])
	t._check("r14_smartab_useless_red", mark308 == "bad" and red, ".308 rounds with a 5.56 rifle and a 9 mm SMG: marked '%s', red edge in the picture %s" % [mark308, str(red)])
	# 1) Grip from the bag onto the rifle's grip mount.
	var rg := _hit_rect(func(h): return str(h.get("kind", "")) == "bag" and str(h.e.id) == "grip_thumb")
	var rm := _hit_rect(func(h): return str(h.get("kind", "")) == "mount" and int(h.get("slot", 0)) == 1 and str(h.get("mount", "")) == "grip")
	if rg.has_area() and rm.has_area():
		await _holo_drag(rg.get_center(), rm.get_center())
	var on_gun: bool = t.ch.wpn.slots[1] != null and "grip_thumb" in t.ch.wpn.slots[1].att
	await t._shot("smartab_grip_fitted")
	t._check("r14_smartab_drag_attachment", on_gun and t.ch.inv.count("grip_thumb") == 0,
		"thumb grip dragged from the bag (row %s) onto the rifle's grip mount (%s): fitted %s, left in the bag %d" % [str(rg.has_area()), str(rm.has_area()), str(on_gun), t.ch.inv.count("grip_thumb")])
	# 2) The rifle's card onto the SMG's: they change places, the rifle stays in hand.
	var r1 := _hit_rect(func(h): return str(h.get("kind", "")) == "weapon" and int(h.get("slot", 0)) == 1)
	var r2 := _hit_rect(func(h): return str(h.get("kind", "")) == "weapon" and int(h.get("slot", 0)) == 2)
	if r1.has_area() and r2.has_area():
		await _holo_drag(r1.position + Vector2(r1.size.x * 0.5, 40.0), r2.position + Vector2(r2.size.x * 0.5, 40.0))
	await t._wait(0.4)
	var s1 := str(t.ch.wpn.slots[1].id) if t.ch.wpn.slots[1] != null else ""
	var s2 := str(t.ch.wpn.slots[2].id) if t.ch.wpn.slots[2] != null else ""
	t._check("r14_smartab_swap_guns", s1 == "smg_9" and s2 == "rifle_556" and t.ch.wpn.current_id() == "rifle_556" and t.ctl.slot == 2,
		"after the drag: slot 1 %s, slot 2 %s, in hand %s (controller slot %d)" % [s1, s2, t.ch.wpn.current_id(), t.ctl.slot])
	# 3) The box of 9 mm on the ground into the bag.
	await t._wait(0.3)
	var rv := _hit_rect(func(h): return str(h.get("kind", "")) == "vic" and str(h.get("src", "")) == "ground" and int(h.get("id", -1)) == gid)
	var rb := _hit_rect(func(h): return str(h.get("kind", "")) == "bag_area")
	if rv.has_area() and rb.has_area():
		await _holo_drag(rv.get_center(), Vector2(rb.get_center().x, rb.end.y - 60.0))
	await t._shot("smartab_took_from_ground")
	t._check("r14_smartab_take_ground", t.ch.inv.count("ammo_9x19") == n9 + 30 and not world.map.dyn.items.has(gid),
		"9 mm box on the ground (row %s) dragged into the bag: carrying %d (was %d), still on the ground %s" % [str(rv.has_area()), t.ch.inv.count("ammo_9x19"), n9, str(world.map.dyn.items.has(gid))])
	# The other pages.
	for i in 4:
		await t._tap("smartab_next")
		await t._wait(0.5)
		await t._shot("smartab_page_%s" % str(st.PAGES[st.page]).to_lower())
	await t._tap("smartab_next")
	t._act_release("smartab")
	await t._wait(0.8)


# ------------------------------------------------------------------ highlight

static func _green_pixels(img: Image, around: Vector2) -> int:
	## Bright green pixels at full resolution in a 520 x 220 box round a screen point (the thin outline vanishes in
	## a scaled-down picture).
	var sz := img.get_size()
	var r := Rect2i(Vector2i(around) - Vector2i(260, 110), Vector2i(520, 220)).intersection(Rect2i(Vector2i.ZERO, sz))
	var c := img.get_region(r)
	c.convert(Image.FORMAT_RGB8)
	var n := 0
	for y in c.get_height():
		for x in c.get_width():
			var p := c.get_pixel(x, y)
			if p.g > 0.45 and p.g > p.r * 1.6 and p.g > p.b * 1.25:
				n += 1
	return n


func _highlight() -> void:
	## Four things on the ground in front of a player carrying a 9 mm SMG: 9 mm rounds (a yellow box) and a thumb grip
	## suit it (outlined green), .308 rounds and a 15x scope do not. Captured with the highlight on and off.
	var spot: Vector3 = t._open_patch(t.ch.global_position)
	t._teleport(spot + Vector3.UP * 0.1, 0.0)
	await t._wait(0.4)
	await _gun("smg_9", [])
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, t.ctl.yaw, 0)).z
	var side := fwd.cross(Vector3.UP).normalized()
	var base: Vector3 = t.ch.global_position + fwd * 2.4
	var ids := {}
	var k := 0
	for id in ["ammo_9x19", "grip_thumb", "ammo_308", "scope_15x"]:
		ids[id] = _spawn_at({"id": id, "n": 30 if id.begins_with("ammo_") else 1}, base + side * (k - 1.5) * 0.7)
		k += 1
	t._look_at(base)
	Settings.set_value("gameplay", "loot_highlight", true)
	await t._wait(0.9)
	var lit: Array = world.loot_highlight.lit_ids() if world.loot_highlight else []
	var img_on := await _grab()
	await t._shot("loot_highlight_on")
	Settings.set_value("gameplay", "loot_highlight", false)
	await t._wait(0.9)
	var lit_off: Array = world.loot_highlight.lit_ids() if world.loot_highlight else []
	var img_off := await _grab()
	await t._shot("loot_highlight_off")
	Settings.set_value("gameplay", "loot_highlight", true)
	var at: Vector2 = t.ctl.cam.unproject_position(base) * (Vector2(img_on.get_size()) / t.get_viewport().get_visible_rect().size)
	var g_on := _green_pixels(img_on, at)
	var g_off := _green_pixels(img_off, at)
	var want_lit: bool = int(ids.ammo_9x19) in lit and int(ids.grip_thumb) in lit and not int(ids.ammo_308) in lit and not int(ids.scope_15x) in lit
	measure["highlight"] = {"lit": lit, "ids": ids, "green_on": g_on, "green_off": g_off}
	t._check("r14_loot_highlight", want_lit and lit_off.is_empty() and g_on > g_off + 40,
		"outlined: %s of %s; off -> %d outlined; green pixels on %d / off %d" % [str(lit), str(ids), lit_off.size(), g_on, g_off])
	for id in ids.values():
		if world.map.dyn.items.has(int(id)):
			world.map_item_remove(int(id))


# ------------------------------------------------------------------ grenade

func _blast_door() -> Dictionary:
	## A door on a street front with flat floor 1, 4 and 8 m out from it, preferring one with movable props close by.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var doors: Array = world.map.dyn.doors.filter(func(d): return d.get("node") != null and not d.node.destroyed and d.has("outward"))
	doors.sort_custom(func(a, b): return (a.xf as Transform3D).origin.distance_to(t.ch.global_position) < (b.xf as Transform3D).origin.distance_to(t.ch.global_position))
	var fallback := {}
	for d in doors.slice(0, 60):
		var dn = d.node
		var xf: Transform3D = dn.current_transform()
		for sgn in [1.0, -1.0]:
			var fr: Vector3 = xf.basis.z.normalized() * sgn
			if fr.dot(d.outward) < 0.3:
				continue
			fr = Vector3(fr.x, 0.0, fr.z).normalized()
			var ok := true
			var floor_y := xf.origin.y
			for dist in [1.0, 4.0, 8.0]:
				var p: Vector3 = dn.center() + fr * dist
				var fl := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, floor_y + 0.8, p.z), Vector3(p.x, floor_y - 1.0, p.z), Defs.PHYS_WORLD))
				if fl.is_empty() or absf((fl.position as Vector3).y - floor_y) > 0.35:
					ok = false
					break
			if not ok:
				continue
			var eye: Vector3 = dn.center() + fr * 8.0
			eye.y = floor_y + 1.6
			if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, dn.center() + fr * 0.3, Defs.PHYS_WORLD)).is_empty():
				continue
			var blast: Vector3 = dn.center() + fr * 0.9
			blast.y = floor_y + 0.15
			var near := 0
			for pr in world.map.dyn.props:
				if str(pr.get("state", "")) != "broken" and (pr.xf as Transform3D).origin.distance_to(blast) < 5.5:
					near += 1
			var r := {"spec": d, "node": dn, "fr": fr, "blast": blast, "floor": floor_y, "props": near}
			if near > 0:
				return r
			if fallback.is_empty():
				fallback = r
	return fallback


func _prop_pos(pid: int) -> Vector3:
	var dyn = world.map.dyn
	if dyn._active.has(pid) and is_instance_valid(dyn._active[pid]):
		return (dyn._active[pid] as Node3D).global_position
	return (dyn.props[pid].xf as Transform3D).origin


func _grenade() -> void:
	## 1) Hold G 1.5 s: the pin comes out, the fuse ring runs, the grenade is in the hand; let go: thrown with 2.5 s
	## left, it goes off on time. 2) One going off by a house door, the player 8 m out, one enemy 2.5 m from it and
	## another 8.5 m: the door is blown apart, props round it thrown, the near enemy killed outright and thrown through
	## the air, the far one badly hurt, the player's hearing muffled and ringing. 3) An enemy holding the key past the
	## fuse: it goes off in their hand. The bots' brains are off throughout (no one shoots anyone).
	var gr = world.grenades
	_freeze_bots(true)   # (already frozen in a whole r14 run; needed for --r14_only=grenade)
	if t.ch.light.on:
		await t._tap("flashlight")
	await _gun("rifle_556", [])
	t.ch.inv.add({"id": "frag_grenade", "n": 3}, true)
	t.ch.inv.mark_dirty()
	var spot: Vector3 = t._open_patch(t.ch.global_position)
	t._teleport(spot + Vector3.UP * 0.1, 0.0)
	await t._wait(0.5)
	t.ctl.pitch = 0.3
	var n0: int = t.ch.inv.count("frag_grenade")
	var ids0: Array = gr.live.keys()
	t._act_press("throw_grenade")
	await t._wait(1.0)
	var cooking: bool = gr.cooking.has(t.ch.eid) and (t.ch.flags & Character.F_COOK) != 0
	var ring: float = t.ctl.cook_t
	var in_hand: bool = t.ctl.vm._nade.visible
	await t._shot("grenade_cooking")
	await t._wait(0.5)
	t._act_release("throw_grenade")
	var t_rel := Time.get_ticks_msec()
	await t._until(func(): return gr.live.size() > ids0.size(), 2.0)
	var gid := -1
	for kk in gr.live:
		if not kk in ids0:
			gid = int(kk)
	var fuse_left: float = float(gr.live[gid].t) if gid >= 0 else -1.0
	await t._wait(0.25)
	await t._shot("grenade_thrown")
	var went: bool = await t._until(func(): return gid >= 0 and not gr.live.has(gid), 6.0)
	var boom_s := (Time.get_ticks_msec() - t_rel) / 1000.0
	await t._wait(0.1)
	await t._shot("grenade_thrown_blast")
	t._check("r14_grenade_cook_throw", cooking and ring > 0.8 and in_hand and t.ch.inv.count("frag_grenade") == n0 - 1 and absf(fuse_left - 2.5) < 0.25 \
		and went and absf(boom_s - 2.5) < 0.5,
		"held 1 s: cooking %s, fuse ring %.2f s, in hand %s; thrown with %.2f s left, went off %.2f s after release; grenades %d -> %d" % [str(cooking), ring,
		str(in_hand), fuse_left, boom_s, n0, t.ch.inv.count("frag_grenade")])
	await t._wait(2.0)
	# 2) By a door.
	var door := _blast_door()
	if door.is_empty():
		t._check("r14_grenade_door", false, "no street door with open ground in front found")
		return
	var dn = door.node
	var fr: Vector3 = door.fr
	var blast: Vector3 = door.blast
	var stand: Vector3 = dn.center() + fr * 8.0
	stand.y = float(door.floor) + 0.1
	t._teleport(stand, 0.0)
	await t._wait(0.4)
	t._look_at(blast + Vector3.UP * 0.8)
	var en := _bots(false)
	var victim = en[0] if en.size() > 0 else null
	var far_v = en[1] if en.size() > 1 else null
	var side := fr.cross(Vector3.UP).normalized()
	var hp0 := 0.0
	var hp_far0 := 0.0
	if victim:
		victim.ch.global_position = _open_spot(blast + side * 2.5, 0.3, 0.0)
		victim.ch.velocity = Vector3.ZERO
		hp0 = float(victim.ch.health.health)
	if far_v:
		far_v.ch.global_position = _open_spot(blast + fr * 1.5 - side * 8.4, 0.3, 0.0)
		far_v.ch.velocity = Vector3.ZERO
		hp_far0 = float(far_v.ch.health.health)
	var far_d: float = far_v.ch.global_position.distance_to(blast) if far_v else 0.0
	var near_ch = victim.ch if victim else null
	var near_eid: int = near_ch.eid if near_ch else -1
	var far_ch = far_v.ch if far_v else null
	var corpses0: Array = world.map.dyn.corpses.keys()
	var props := {}
	for pr in world.map.dyn.props:
		if str(pr.get("state", "")) != "broken" and (pr.xf as Transform3D).origin.distance_to(blast) < 5.5:
			props[int(pr.id)] = _prop_pos(int(pr.id))
	await t._wait(0.6)
	await t._shot("grenade_door_before")
	var luma0: float = await t._view_luma()
	SoundSys.trace = []
	SoundSys.trace_on = true
	var bid: int = gr._spawn_live(blast, Vector3.ZERO, 0.8)
	await t._until(func(): return not gr.live.has(bid), 3.0)
	var near_dead: bool = not is_instance_valid(near_ch) or not world.characters.has(near_eid) or near_ch.mode == Motor.DEAD
	await t._wait(0.05)
	var luma1: float = await t._view_luma()
	await t._shot("grenade_door_fireball")
	# The near enemy's body: how far and how high it flies in the next second and a half.
	var body = null
	for cid in world.map.dyn.corpses:
		if not cid in corpses0:
			var cb = world.map.dyn.corpses[cid]
			if is_instance_valid(cb) and int(cb.eid) == near_eid:
				body = cb
	var fly0: Vector3 = body.center() if body else Vector3.ZERO
	var fly_far := 0.0
	var fly_up := 0.0
	await t._wait(0.25)
	var cutoff: float = SoundSys.deaf_cutoff()
	var deaf_s: float = float(SoundSys.deaf.s)
	var fx_on := false
	if not SoundSys._deaf_fx.is_empty():
		var f0: Array = SoundSys._deaf_fx[0]
		fx_on = AudioServer.is_bus_effect_enabled(int(f0[0]), int(f0[1]))
	await t._shot("grenade_door_smoke")
	var tf := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tf < 1300:
		await t.get_tree().physics_frame
		if body and is_instance_valid(body):
			var cc: Vector3 = body.center()
			fly_far = maxf(fly_far, Vector2(cc.x - fly0.x, cc.z - fly0.z).length())
			fly_up = maxf(fly_up, cc.y - fly0.y)
	await t._shot("grenade_door_after")
	SoundSys.trace_on = false
	var rang := SoundSys.trace.any(func(e): return str(e[1]) == "tinnitus")
	var moved := 0
	for pid in props:
		if str(world.map.dyn.props[pid].get("state", "")) == "broken" or _prop_pos(pid).distance_to(props[pid]) > 0.25:
			moved += 1
	var far_gone: bool = far_ch == null or not is_instance_valid(far_ch) or not world.characters.has(far_ch.eid)
	var hp_far1 := 0.0 if far_gone else float(far_ch.health.health)
	var far_hurt: bool = far_ch != null and (far_gone or hp_far1 < hp_far0 - 25.0 or far_ch.mode in [Motor.DEAD, Motor.DOWNED])
	measure["grenade_door"] = {"door": int(door.spec.id), "destroyed": dn.destroyed, "props_near": props.size(), "props_moved": moved,
		"near_killed": near_dead, "body_flew_m": [snappedf(fly_far, 0.1), snappedf(fly_up, 0.1)], "far_m": snappedf(far_d, 0.1), "far_hp": [hp_far0, hp_far1],
		"luma": [luma0, luma1], "deaf": deaf_s, "cutoff_hz": cutoff, "lowpass_on": fx_on, "tinnitus": rang}
	t._check("r14_grenade_door", dn.destroyed and (props.is_empty() or moved >= 1) and luma1 > luma0 + 8.0,
		"door %d blown apart %s; %d of %d props near it thrown or broken; view brightness %.0f -> %.0f at the blast" % [int(door.spec.id),
		str(dn.destroyed), moved, props.size(), luma0, luma1])
	t._check("r14_grenade_lethal", victim != null and near_dead and body != null and fly_far > 3.0 and far_hurt,
		"enemy 2.5 m away (%.0f HP): killed outright %s, the body thrown %.1f m and %.1f m up; enemy %.1f m away %.0f -> %.0f HP%s" % [hp0, str(near_dead),
		fly_far, fly_up, far_d, hp_far0, hp_far1, " (killed)" if far_gone else ""])
	t._check("r14_grenade_muffle", deaf_s > 0.4 and cutoff < 3000.0 and fx_on and rang,
		"player 8 m from the blast: hearing strength %.2f, world sound low-passed at %.0f Hz (filter on %s), ears ringing %s" % [deaf_s, cutoff, str(fx_on), str(rang)])
	await t._wait(2.0)
	# 3) Held past the fuse: an enemy keeps the key down (commands fed straight to the server).
	var holder = null
	for b in _bots(false):
		if b != victim:
			holder = b
			break
	if holder == null:
		t._check("r14_grenade_in_hand", false, "no second enemy bot")
		return
	var hch = holder.ch
	var heid: int = hch.eid
	world._queues[heid] = []
	hch.inv.add({"id": "frag_grenade", "n": 1}, true)
	var fwd2: Vector3 = -Basis.from_euler(Vector3(0, t.ctl.yaw, 0)).z
	hch.global_position = _open_spot(t.ch.global_position + fwd2 * 9.0, 0.5, 0.0)
	hch.velocity = Vector3.ZERO
	await t._wait(0.3)
	t._look_at(hch.global_position + Vector3.UP * 1.0)
	var hp_h := float(hch.health.health)
	var seq := 60000000
	var pulled_ms := -1
	var boom_ms := -1
	var t0 := Time.get_ticks_msec()
	var thrown := false
	var live_before: Array = gr.live.keys()
	while Time.get_ticks_msec() - t0 < 6500:
		seq += 1
		world.server_queue_cmds(heid, [{"seq": seq, "btn": Motor.B_THROW, "mx": 0.0, "my": 0.0, "yaw": hch.yaw, "pitch": 0.0, "slot": 0,
			"view_tick": Net.tick, "tick": Net.tick}])
		await t.get_tree().physics_frame
		if pulled_ms < 0 and gr.cooking.has(heid):
			pulled_ms = Time.get_ticks_msec()
		for kk in gr.live:
			if not kk in live_before and float(gr.live[kk].t) > 0.1:
				thrown = true
		if pulled_ms >= 0 and not gr.cooking.has(heid):
			boom_ms = Time.get_ticks_msec()
			break
	await t._wait(0.08)
	await t._shot("grenade_in_hand")
	var held_s := (boom_ms - pulled_ms) / 1000.0 if boom_ms > 0 and pulled_ms > 0 else -1.0
	# Killed outright, a Deathmatch body is removed at once (the bot comes back as a new character).
	var gone = not is_instance_valid(hch) or not world.characters.has(heid)
	var hp_h1 := 0.0 if gone else float(hch.health.health)
	var down: bool = gone or hch.mode in [Motor.DEAD, Motor.DOWNED]
	t._check("r14_grenade_in_hand", pulled_ms > 0 and absf(held_s - 4.0) < 0.35 and not thrown and (down or hp_h1 < hp_h - 60.0),
		"enemy kept the key down: went off %.2f s after the pin came out, never thrown %s, %.0f -> %.0f HP (%s)" % [held_s, str(not thrown), hp_h, hp_h1,
		"killed" if gone else ("down" if down else "standing")])
	if not _holding:
		_freeze_bots(false)   # (--r14_only=grenade; the whole run thaws them before the spectator check)
