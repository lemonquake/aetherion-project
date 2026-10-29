extends RefCounted
## --autotest=r6: measured checks for the 2026-10-28 r6 run (blood, sounds, camera bob).
##   godot --path game -- --host --bots=11 --autostart=1 --autotest=r6 --shots=<dir> --port=27515 [--r6_only=blood]
##   [--r6_fast=1] skips the parachute and drops the player straight on to the ground.
##
## blood: three rifle rounds through a bot standing in front of a sunlit house front; counts the blood marks placed
## and the blood-red pixels that appear on the wall behind and the ground where the bot stood (captured with the bot
## moved away). Then a body: the pool under it must spread on screen, and rounds into it must throw new blood.
## sounds: every sound an impact material, gun, reload step or body asks for exists and every file loads.
## bob: the walking camera's vertical and side sway, measured from the camera over two seconds of walking.

const Anims := preload("res://src/player/weapon_anims.gd")
const WeaponState := preload("res://src/weapons/weapon_state.gd")
const SURF := Defs.PHYS_WORLD | Defs.PHYS_PROP | Defs.PHYS_GLASS

var t = null
var world = null


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("r6_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	if Game.arg("r6_fast") != null:
		await t._wait(1.0)
		world.server_set_mode(t.ch, Motor.GROUND)
		t._teleport(Vector3(40, world.map.ground_height(40, 40) + 0.3, 40), 0.0)
		await t._wait(1.0)
	else:
		await t._deploy()
	if not is_instance_valid(t.ch):
		return
	if want.call("sounds"):
		_sounds()
	if want.call("bob"):
		await _bob()
	if want.call("cues"):
		await _cues()
	if want.call("smartab"):
		await _smartab()
	if want.call("blood"):
		world.map.lighting.forced_time = 450.0
		await _blood()
		world.map.lighting.forced_time = -1.0


# ------------------------------------------------------------------ helpers

func _space() -> PhysicsDirectSpaceState3D:
	return world.get_world_3d().direct_space_state


func _surface_at(from: Vector3, length: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * length, SURF)
	var r := _space().intersect_ray(q)
	if r.is_empty():
		return {}
	return {"y": (r.position as Vector3).y, "collider": r.collider, "normal": r.normal}


func _clear_around(p: Vector3, r: float) -> bool:
	for a in 8:
		var d := Vector3(cos(TAU * a / 8.0), 0, sin(TAU * a / 8.0))
		for h in [0.3, 1.0]:
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * h, p + Vector3.UP * h + d * r, SURF | Defs.PHYS_BLOCKER)
			if not _space().intersect_ray(q).is_empty():
				return false
	return true


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return t.get_viewport().get_texture().get_image()


func _red_px(img: Image, rect: Rect2i = Rect2i()) -> int:
	## Pixels that read as blood: clearly red, not merely warm (bulbs, brick and rust are orange-brown). Counted on a
	## half-size copy.
	var r: Image = img.get_region(rect) if rect.size.x > 0 else img.duplicate()
	r.resize(maxi(r.get_width() / 2, 1), maxi(r.get_height() / 2, 1))
	var n := 0
	for y in r.get_height():
		for x in r.get_width():
			var c := r.get_pixel(x, y)
			if c.r > 0.1 and c.r > c.g * 2.6 and c.r > c.b * 2.2:
				n += 1
	return n


func _new_red(before: Image, after: Image, rect: Rect2i = Rect2i()) -> int:
	## Pixels that turned to blood between two captures of the same view: clearly redder than they were (red over
	## green up by half again) and red enough to see. Works on any surface colour and light; half-size copies.
	var a: Image = before.get_region(rect) if rect.size.x > 0 else before.duplicate()
	var b: Image = after.get_region(rect) if rect.size.x > 0 else after.duplicate()
	var w := maxi(a.get_width() / 2, 1)
	var h := maxi(a.get_height() / 2, 1)
	a.resize(w, h)
	b.resize(w, h)
	var n := 0
	for y in h:
		for x in w:
			var c0 := a.get_pixel(x, y)
			var c1 := b.get_pixel(x, y)
			if c1.r > 0.05 and c1.r / maxf(c1.g, 0.01) > 1.5 * c0.r / maxf(c0.g, 0.01) and c1.r > c1.b * 1.6:
				n += 1
	return n


func _screen_rect(img: Image, p: Vector3, half_px: int) -> Rect2i:
	## A square around world point p, in the captured image's pixels (the viewport may be stretched from the window).
	var cam: Camera3D = t.get_viewport().get_camera_3d()
	var vs: Vector2 = t.get_viewport().get_visible_rect().size
	var k := float(img.get_width()) / vs.x
	var sp := cam.unproject_position(p) * k
	var x := clampi(int(sp.x) - half_px, 0, img.get_width() - half_px * 2)
	var y := clampi(int(sp.y) - half_px, 0, img.get_height() - half_px * 2)
	return Rect2i(x, y, half_px * 2, half_px * 2)


func _fire_at(target: Vector3, ammo: String, v0: float) -> void:
	## A real round on the server from the player's eyes: ballistics, damage, the hit event and every effect.
	var eye: Vector3 = t.ch.eye_position()
	world.projectiles.spawn(t.ch, {"ammo": ammo, "velocity": v0, "origin": eye, "dir": (target - eye).normalized(), "seed": randi()}, Net.tick, Net.tick)


func _pick_bot():
	## A living bot, brought down to the ground if it is still in the aircraft or the air.
	for o in world.characters.values():
		if o != t.ch and world.bots.has(o.eid) and o.mode not in [Motor.DEAD, Motor.SPECTATE, Motor.DOWNED]:
			if o.mode != Motor.GROUND:
				world.server_set_mode(o, Motor.GROUND)
			return o
	return null


# ------------------------------------------------------------------ blood

func _blood_walls() -> Array:
	## House fronts beside doors under open sky, each with a standing spot 0.9 m in front of it for the victim and one
	## 4.2 m out for the shooter, both on the same floor level with a clear line between them (nearest first).
	var out_spots := []
	var dyn = world.map.dyn
	var me: Vector3 = t.ch.global_position
	var doors: Array = dyn.doors.filter(func(d): return d.get("node") != null and not d.node.destroyed and d.has("outward"))
	doors.sort_custom(func(a, b): return (a.xf as Transform3D).origin.distance_to(me) < (b.xf as Transform3D).origin.distance_to(me))
	for d in doors.slice(0, 80):
		var dn = d.node
		var xf: Transform3D = dn.current_transform()
		var side: Vector3 = xf.basis.x.normalized()
		var out: Vector3 = d.outward
		out.y = 0.0
		out = out.normalized()
		for ss in [-1.0, 1.0]:
			var near: Vector3 = dn.center() + side * ss * (float(dn.w) * 0.5 + 0.8) + out * 1.0
			var q := PhysicsRayQueryParameters3D.create(near + Vector3.UP * 0.2, near - out * 1.6 + Vector3.UP * 0.2, Defs.PHYS_WORLD)
			var w := _space().intersect_ray(q)
			if w.is_empty() or absf((w.normal as Vector3).y) > 0.25 or w.collider.has_meta("door_id"):
				continue
			var n: Vector3 = w.normal
			n.y = 0.0
			n = n.normalized()
			var victim: Vector3 = (w.position as Vector3) + n * 0.9
			var stand: Vector3 = (w.position as Vector3) + n * 4.2
			var fv := _surface_at(victim + Vector3.UP * 1.2, 2.5)
			var fs := _surface_at(stand + Vector3.UP * 1.2, 2.5)
			if fv.is_empty() or fs.is_empty() or absf(float(fv.y) - float(fs.y)) > 0.25:
				continue
			victim.y = float(fv.y)
			stand.y = float(fs.y)
			if not _clear_around(victim, 0.5):
				continue
			var sky := PhysicsRayQueryParameters3D.create(victim + Vector3.UP * 2.2, victim + Vector3.UP * 40.0, Defs.SHOT_MASK)
			if not _space().intersect_ray(sky).is_empty():
				continue
			var clear := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 1.6, victim + Vector3.UP * 1.3, SURF)
			if not _space().intersect_ray(clear).is_empty():
				continue
			out_spots.append({"victim": victim, "stand": stand, "wall": w.position, "normal": n})
			if out_spots.size() >= 10:
				return out_spots
	return out_spots


func _luma(img: Image, rect: Rect2i) -> float:
	var r := img.get_region(rect)
	r.resize(24, 24)
	var s := 0.0
	for y in 24:
		for x in 24:
			s += r.get_pixel(x, y).get_luminance()
	return s / 576.0 * 255.0


func _blood() -> void:
	var fx = world.effects
	# A wall bright enough in the capture that blood on it can be seen at all (dark-painted planks in shade read
	# near black with or without blood on them, as they would to a player).
	var spot := {}
	var before: Image = null
	for cand in _blood_walls():
		t._teleport(cand.stand + Vector3.UP * 0.05, 0.0)
		await t._wait(0.5)
		t._look_at(cand.victim + Vector3.UP * 0.6)
		await t._wait(0.3)
		var img := await _grab()
		if _luma(img, _screen_rect(img, cand.wall, 80)) > 70.0 and _luma(img, _screen_rect(img, cand.victim, 60)) > 60.0:
			spot = cand
			before = img
			break
	if spot.is_empty():
		t._check("blood_spatter_visible", false, "no light, open-sky house front with room in front of it near the player")
		return
	var bot = _pick_bot()
	if bot == null:
		t._check("blood_spatter_visible", false, "no bot to shoot")
		return
	var keep: Vector3 = bot.global_position
	await t._shot("blood_before")
	var m0: int = fx.blood.marks_made
	# Three rifle rounds through the victim's chest and shoulder, each from a slightly different angle.
	var aims := [Vector3(0, 1.3, 0), Vector3(0.15, 1.45, 0), Vector3(-0.12, 1.1, 0)]
	for k in 3:
		# Standing and whole for each round (other bots may have shot it meanwhile).
		bot.health.reset()
		if bot.mode != Motor.GROUND:
			world.server_set_mode(bot, Motor.GROUND)
		bot.global_position = spot.victim
		bot.velocity = Vector3.ZERO
		await t.world.get_tree().physics_frame
		await t.world.get_tree().physics_frame
		_fire_at(spot.victim + aims[k], "556", 920.0)
		await t._wait(0.12)
		bot.health.reset()
	await t._wait(0.25)
	await t._shot("blood_on_hit")
	bot.global_position = keep
	bot.velocity = Vector3.ZERO
	await t._wait(0.8)
	var after := await _grab()
	await t._shot("blood_after")
	var made: int = fx.blood.marks_made - m0
	var near := 0
	var on_obj := 0
	var cam3: Camera3D = t.get_viewport().get_camera_3d()
	for r in fx.blood.recent:
		if (r[0] as Vector3).distance_to(spot.victim) < 4.0:
			near += 1
		if r[3]:
			on_obj += 1
	print("[r6] victim %s, camera %s; of the last %d marks %d within 4 m of the victim, %d on moving objects; first: %s" % [str(spot.victim), str(cam3.global_position), fx.blood.recent.size(), near, on_obj, str(fx.blood.recent.slice(0, 6))])
	var feet := _screen_rect(before, spot.victim, 70)
	var wall := _screen_rect(before, spot.wall, 90)
	var all_n := _new_red(before, after)
	var f_n := _new_red(before, after, feet)
	var w_n := _new_red(before, after, wall)
	var frame: int = before.get_width() * before.get_height() / 4
	t._check("blood_spatter_visible", made >= 15 and all_n > frame / 400,
		"%d blood marks from 3 hits; %d pixels turned blood red (%.2f%% of the view)" % [made, all_n, 100.0 * all_n / frame])
	t._check("blood_on_wall", w_n > 60, "%d pixels turned blood red on the wall behind the victim" % w_n)
	t._check("blood_at_feet", f_n > 30, "%d pixels turned blood red on the ground where they stood" % f_n)
	# The wounded bot walks 3 m across the view: its drip trail must leave marks on the ground behind it.
	var trail0: int = fx.blood.marks_made
	var side: Vector3 = spot.normal.cross(Vector3.UP).normalized()
	var start: Vector3 = spot.victim + spot.normal * 0.8 - side * 1.5
	for i in 30:
		bot.health.reset()
		if bot.mode != Motor.GROUND:
			world.server_set_mode(bot, Motor.GROUND)
		bot.global_position = start + side * (3.0 * i / 29.0)
		bot.velocity = side * 1.5
		await t._wait(0.1)
	bot.global_position = keep
	bot.velocity = Vector3.ZERO
	t._check("blood_drip_trail", fx.blood.marks_made - trail0 >= 4, "%d drops left by the wounded bot over 3 m in 3 s" % (fx.blood.marks_made - trail0))
	# A body: the pool spreading under it, and rounds into it throwing new blood.
	var p0: int = fx.blood.pools_made
	var before_c: Array = world.map.dyn.corpses.keys()
	bot.global_position = spot.victim + spot.normal * 0.6
	bot.velocity = Vector3.ZERO
	await t.world.get_tree().physics_frame
	world.map.server_spawn_corpse(bot, -spot.normal * 30.0)
	bot.global_position = keep
	var cid := -1
	for k in world.map.dyn.corpses.keys():
		if k not in before_c:
			cid = k
	var c = world.map.dyn.corpses.get(cid)
	if c == null:
		t._check("blood_pool_spreads", false, "no body spawned")
		return
	await t._until(func(): return c.settled, 8.0)
	await t._wait(0.6)
	t._look_at(c.center())
	await t._wait(0.3)
	var early := await _grab()
	var pool_rect := _screen_rect(early, c.center(), 130)
	await t._shot("blood_pool_early")
	await t._wait(14.0)
	var late := await _grab()
	await t._shot("blood_pool_late")
	var grown := _new_red(early, late, pool_rect)
	t._check("blood_pool_spreads", fx.blood.pools_made - p0 >= 1 and grown > 80,
		"%d pools under the body; %d pixels around it turned blood red in the 14 s after it came to rest" % [fx.blood.pools_made - p0, grown])
	var m1: int = fx.blood.marks_made
	var cc: Vector3 = c.center()
	for k in 2:
		_fire_at(cc + Vector3(randf_range(-0.1, 0.1), 0.05, randf_range(-0.1, 0.1)), "9x19", 360.0)
		await t._wait(0.15)
	await t._wait(0.6)
	await t._shot("blood_corpse_shot")
	t._check("blood_corpse_hit", fx.blood.marks_made - m1 >= 4, "%d new marks from 2 rounds into the body on the ground" % (fx.blood.marks_made - m1))
	# Last (it floods this spot with marks):
	# Cost of one hit's spray on this machine (all its droplet arcs and marks), and how many draw sets blood uses.
	var us := 0
	for k in 20:
		var t1 := Time.get_ticks_usec()
		fx.blood.shot_through(spot.victim + Vector3.UP * 1.3, (spot.victim - spot.stand).normalized(), 0.6)
		us += Time.get_ticks_usec() - t1
	var sets := 0
	for node in fx.blood.get_children():
		if node is MultiMeshInstance3D:
			sets += 1
	t._check("blood_cost", us / 20.0 < 1000.0, "%.2f ms per hit's spray (mean of 20), %d marks alive in %d draw sets (budget %d)" % [us / 20000.0, fx.blood.count, sets, fx.blood.budget])


# ------------------------------------------------------------------ sounds

func _sounds() -> void:
	## Every sound the game asks for exists, every file of every sound loads, and each impact material has several
	## takes.
	var bad_files := []
	for sid in SoundSys.defs:
		for f in SoundSys.defs[sid].get("files", []):
			if not ResourceLoader.exists("res://" + str(f)):
				bad_files.append(str(f))
	var need := ["impact_concrete", "impact_wood", "impact_metal", "impact_metal_sheet", "impact_dirt", "impact_water", "impact_glass",
		"impact_fabric", "impact_plastic", "impact_foliage", "impact_tile", "impact_flesh", "impact_flesh_head", "impact_armor", "ricochet",
		"flyby_crack", "flyby_whiz", "casing_drop", "shell_drop", "bodyfall", "dry_fire"]
	for c in Anims.CUES:
		need.append(c)
	for wid in Defs.weapons:
		if Defs.weapons[wid] is Dictionary and Defs.weapons[wid].has("sound"):
			need.append("shot_" + str(Defs.weapons[wid].sound))
	var missing := []
	var thin := []
	for sid in need:
		if not SoundSys.defs.has(sid):
			missing.append(sid)
		elif sid.begins_with("impact_") and (SoundSys.defs[sid].files as Array).size() < 3:
			thin.append(sid)
	t._check("sounds_complete", missing.is_empty() and bad_files.is_empty(),
		"%d sounds needed by impacts, guns, reload steps and bodies; missing %s; unloadable files %s" % [need.size(), str(missing), str(bad_files.slice(0, 8))])
	t._check("impact_variety", thin.is_empty(), "impact sets with fewer than 3 takes: %s" % str(thin))


# ------------------------------------------------------------------ reload sounds

func _cues() -> void:
	## Empty reloads of a rifle, a pistol, a pump gun and a bolt rifle: every step's sound must play, in order, within
	## 80 ms of where its hands animation puts it; a bot's reload next to the player must be heard step by step too.
	var ch = t.ch
	var cases := [["rifle_m416", "ammo_556"], ["pistol_9", "ammo_9x19"], ["shotgun_pump", "ammo_12buck"], ["bolt_kar98", "ammo_308"]]
	var report := []
	var all_ok := true
	for c in cases:
		var wid: String = c[0]
		world.interaction.give(ch, {"id": wid, "n": 1})
		world.interaction.give(ch, {"id": c[1], "n": 60})
		var slot := -1
		for s in [1, 2, 3]:
			if ch.wpn.slots[s] != null and str(ch.wpn.slots[s].id) == wid:
				slot = s
		if slot < 0:
			report.append("%s: not in a slot" % wid)
			all_ok = false
			continue
		await t._tap("weapon_%d" % slot)
		await t._until(func(): return ch.wpn.current_id() == wid and ch.wpn.can_fire(), 4.0)
		# Empty: magazine and chamber, so the full sequence (bolt / slide / charging handle) runs.
		var w: Dictionary = ch.wpn.weapon()
		w.mag = 0
		w.chamber = false
		SoundSys.trace.clear()
		SoundSys.trace_on = true
		var t0 := Time.get_ticks_msec()
		await t._tap("reload")
		await t._until(func(): return ch.wpn.state != WeaponState.RELOAD and int(ch.wpn.weapon().get("mag", 0)) > 0, 12.0)
		await t._wait(0.3)
		SoundSys.trace_on = false
		var heard := []
		for e in SoundSys.trace:
			if str(e[1]) in Anims.CUES:
				heard.append("%s@%d" % [e[1], int(e[0]) - t0])
		var ids := heard.map(func(h): return str(h).split("@")[0])
		var need: Array = {"rifle_m416": ["mag_out", "mag_in", "charge_back", "charge_release"], "pistol_9": ["mag_out_pistol", "mag_in_pistol", "slide_back", "slide_release"],
			"shotgun_pump": ["shell_insert", "pump_back", "pump_fwd"], "bolt_kar98": ["bolt_up", "bolt_back", "bolt_fwd", "bolt_down"]}[wid]
		var order_ok := true
		var at := -1
		for n in need:
			var i: int = ids.find(n, at + 1)
			if i < 0:
				order_ok = false
				break
			at = i
		all_ok = all_ok and order_ok
		report.append("%s: %s" % [wid, " ".join(heard)])
	t._check("reload_step_sounds", all_ok, "; ".join(report))
	# A bot reloading beside the player: its steps arrive as an event and play at its position.
	var bot = null
	for o in world.characters.values():
		if o != ch and world.bots.has(o.eid) and o.mode not in [Motor.DEAD, Motor.SPECTATE]:
			bot = o
			break
	if bot == null:
		return
	if bot.mode != Motor.GROUND:
		world.server_set_mode(bot, Motor.GROUND)
	world.interaction.give(bot, {"id": "rifle_m416", "n": 1})
	world.interaction.give(bot, {"id": "ammo_556", "n": 60})
	bot.global_position = ch.global_position + Vector3(2.5, 0.2, 0)
	await t._wait(0.3)
	for s in [1, 2, 3]:
		if bot.wpn.slots[s] != null and str(bot.wpn.slots[s].id) == "rifle_m416":
			bot.wpn.cur = s
			bot.wpn.state = WeaponState.IDLE
	var bw: Dictionary = bot.wpn.weapon()
	bw.mag = 0
	bw.chamber = false
	SoundSys.trace.clear()
	SoundSys.trace_on = true
	var st0: int = bot.wpn.state
	bot.wpn.start_reload()
	world._reload_sounds(bot, st0, bot.wpn.reload_phase, 0.0)   # what the server's character step does on that tick
	print("[r6] bot reload: state %d -> %d, weapon %s, mag %d, timer %.2f" % [st0, bot.wpn.state, str(bot.wpn.weapon().get("id", "")), int(bot.wpn.weapon().get("mag", 0)), float(bot.wpn.timer)])
	var keep_pos: Vector3 = bot.global_position
	for i in 40:
		bot.global_position = keep_pos
		await t._wait(0.1)
	SoundSys.trace_on = false
	var bot_heard := []
	for e in SoundSys.trace:
		if str(e[1]) in Anims.CUES and str(e[2]) == "world":
			bot_heard.append(str(e[1]))
	t._check("bot_reload_heard", "mag_out" in bot_heard and "mag_in" in bot_heard, "steps heard from a bot 2.5 m away: %s" % str(bot_heard))


# ------------------------------------------------------------------ SmarTab

func _smartab() -> void:
	## With the SmarTab up: how much of the view its screen fills, how tall its smallest text is in window pixels,
	## and whether any part of the arms shows on the screen (the same view drawn with and without the arms must not
	## differ inside the screen).
	var vm = t.ctl.vm
	world.map.lighting.forced_time = 450.0
	t._act_press("smartab")
	# Fully up and still (with a gun in hand it comes up only once the gun is lowered).
	await t._until(func(): return float(vm._tab) >= 0.999, 4.0)
	await t._wait(0.4)
	var img := await _grab()
	var cam: Camera3D = t.get_viewport().get_camera_3d()
	var vs: Vector2 = t.get_viewport().get_visible_rect().size
	var k := float(img.get_width()) / vs.x
	var xf: Transform3D = vm.tab_screen.global_transform
	var lo := Vector2(INF, INF)
	var hi := -Vector2(INF, INF)
	for c in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var sp := cam.unproject_position(xf * Vector3(c.x * vm.screen_size.x, c.y * vm.screen_size.y, 0.0)) * k
		lo = lo.min(sp)
		hi = hi.max(sp)
	var rect := Rect2i(Vector2i(lo), Vector2i(hi - lo))
	var inner := rect.grow(-int(rect.size.y * 0.04)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	await t._shot("smartab_up")
	vm.test_hide_arms = true
	await t._wait(0.1)
	var bare := await _grab()
	vm.test_hide_arms = false
	t._act_release("smartab")
	world.map.lighting.forced_time = -1.0
	var worst := 0.0
	var bad_px := 0
	var a := img.get_region(inner)
	var b := bare.get_region(inner)
	a.resize(inner.size.x / 2, inner.size.y / 2)
	b.resize(inner.size.x / 2, inner.size.y / 2)
	for y in a.get_height():
		for x in a.get_width():
			var d := absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance())
			worst = maxf(worst, d)
			if d > 0.08:
				bad_px += 1
	var frac := float(rect.size.y) / float(img.get_height())
	var small_px := 19.0 * float(rect.size.y) / 720.0
	t._check("smartab_size", frac > 0.55, "screen %dx%d px = %.0f%% of the view height; smallest text about %.0f px tall (was ~7 px on a 900 px window)" % [rect.size.x, rect.size.y, frac * 100.0, small_px])
	t._check("smartab_no_hands_on_screen", bad_px < 20, "%d pixels of the screen change when the arms are hidden (worst %.2f luma)" % [bad_px, worst])


# ------------------------------------------------------------------ camera bob

func _bob() -> void:
	## Walk forward for two seconds and measure how far the camera sways from the smooth path (vertical and side).
	var ctl = t.ctl
	var cam: Camera3D = t.get_viewport().get_camera_3d()
	# Flat, clear ground (8 m of path with under 10 cm of rise), uninjured, any landing jolt long gone: the sway
	# measured is the gait alone, not a step, a slope or a limp.
	var found := false
	for centre in [t.ch.global_position, Vector3(40, 0, 40)]:   # near where they are, else the open ground by the drop
		var me: Vector3 = centre
		if found:
			break
		for r in [0.0, 6.0, 12.0, 20.0, 30.0, 45.0]:
			for k in 12:
				var p: Vector3 = me + Vector3(cos(k * TAU / 12.0), 0, sin(k * TAU / 12.0)) * r
				var yaw := k * TAU / 12.0
				var fwd := -Basis(Vector3.UP, yaw).z
				var hs := []
				for i in 9:
					var q: Vector3 = p + fwd * i
					hs.append(world.map.ground_height(q.x, q.z))
				if float(hs.max()) - float(hs.min()) > 0.1:
					continue
				var g := Vector3(p.x, float(hs[0]), p.z)
				var top := _surface_at(g + Vector3.UP * 2.5, 3.0)   # the ground itself is the first thing under head height
				if top.is_empty() or absf(float(top.y) - g.y) > 0.15:
					continue
				var ray := PhysicsRayQueryParameters3D.create(g + Vector3.UP * 0.6, g + Vector3.UP * 0.6 + fwd * 8.5, SURF | Defs.PHYS_BLOCKER)
				if not _space().intersect_ray(ray).is_empty() or world.map.layout.is_water(p.x, p.z) or world.map.layout.is_water(p.x + fwd.x * 8.0, p.z + fwd.z * 8.0):
					continue
				t._teleport(g + Vector3.UP * 0.1, yaw)
				found = true
				break
			if found:
				break
	t.ch.health.reset()
	await t._wait(1.5)
	print("[r6] bob: flat spot %s, at %s, mode %d, floor %s" % [str(found), str(t.ch.global_position), t.ch.mode, str(t.ch.is_on_floor())])
	var ys := []
	var xs := []
	t._act_press("move_forward")
	await t._wait(0.6)
	for i in 90:
		await t.world.get_tree().process_frame
		var rel: Vector3 = cam.global_position - t.ch.get_global_transform_interpolated().origin
		var side := Basis(Vector3.UP, ctl.yaw).x
		ys.append(rel.y)
		xs.append(rel.dot(side))
	print("[r6] bob: walked to %s, speed %.2f" % [str(t.ch.global_position), Vector2(t.ch.velocity.x, t.ch.velocity.z).length()])
	t._act_release("move_forward")
	var span := func(a: Array) -> float: return float(a.max()) - float(a.min())
	var sy: float = span.call(ys)
	var sx: float = span.call(xs)
	# Before the change the walk bob swung 2 x 0.025 m up/down and 2 x 0.018 m sideways at full walking speed.
	t._check("walk_bob_halved", sy < 0.034 and sx < 0.024 and sy > 0.004,
		"camera sway over 1.5 s of walking: %.3f m up/down, %.3f m side to side (old peak-to-peak 0.050 / 0.036)" % [sy, sx])
