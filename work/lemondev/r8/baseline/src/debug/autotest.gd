extends Node
## Scripted play-through on a host with a window: drives the local player through the real input actions (the
## same path a keyboard takes), checks results against server state, and saves screenshots along the way.
##   godot --path game -- --host --bots=11 --autostart=1 --autotest=tour --shots=<dir> [--size=1920x1080]
## Prints "[autotest] PASS|FAIL <check>: <detail>" lines and quits when done (exit code 1 if anything failed).
## Debug shortcuts it takes (teleporting, giving items, killing a bot) are server-side calls a client cannot make.

const WeaponState := preload("res://src/weapons/weapon_state.gd")
const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")

var world = null
var ctl = null
var ch = null
var out_dir := "user://autotest"
var results: Array = []
var _shot_n := 0
var _lane_spot := Vector3.INF


func _ready() -> void:
	process_priority = -1000
	process_physics_priority = 1000
	world = get_parent()
	out_dir = str(Game.arg("shots", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var size := str(Game.arg("size", "")).split("x")
	if size.size() == 2:
		get_window().size = Vector2i(int(size[0]), int(size[1]))
	get_tree().create_timer(float(Game.arg("autotest_timeout", 420))).timeout.connect(func(): _check("watchdog", false, "timed out"); _finish())
	_run.call_deferred()


func _run() -> void:
	await _until(func(): return world.local_char != null and world.controller != null, 20.0)
	ctl = world.controller
	ch = world.local_char
	if ch == null:
		_check("spawn", false, "no local character")
		_finish()
		return
	if str(Game.arg("autotest", "")) == "perf":
		await _perf_run()
		_finish()
		return
	if str(Game.arg("autotest", "")) == "loot":
		await _loot_run()
		_finish()
		return
	if str(Game.arg("autotest", "")) == "fixes":
		await preload("res://src/debug/autotest_fixes.gd").new(self).run()
		_finish()
		return
	if str(Game.arg("autotest", "")) == "r3":
		await preload("res://src/debug/autotest_r3.gd").new(self).run()
		_finish()
		return
	if str(Game.arg("autotest", "")) == "r4":
		await preload("res://src/debug/autotest_r4.gd").new(self).run()
		_finish()
		return
	if str(Game.arg("autotest", "")) == "r5":
		await preload("res://src/debug/autotest_r5.gd").new(self).run()
		_finish()
		return
	if str(Game.arg("autotest", "")) == "r6":
		await preload("res://src/debug/autotest_r6.gd").new(self).run()
		_finish()
		return
	if str(Game.arg("autotest", "")) == "dm":
		await preload("res://src/debug/autotest_dm.gd").new(self).run()
		_finish()
		return
	if str(Game.arg("autotest", "")) == "mapscan":
		await load("res://src/debug/autotest_map.gd").new(self).run()
		_finish()
		return
	_volume_cap()
	_quality_preset()
	await _deploy()
	if not is_instance_valid(ch):
		return
	await _dark_house()
	await _house_lights()
	await _gallery()
	await _dark_house()
	await _smartab()
	await _weapons()
	await _battery()
	await _corpse()
	await _observer_view()
	_finish()


# ------------------------------------------------------------------ scenarios

func _volume_cap() -> void:
	## Slider 100 plays at 75% of full output; the debug unlock makes 100 full. Restores the player's settings.
	var keep_master = Settings.get_value("audio", "master")
	var keep_unlock = Settings.get_value("debug", "volume_unlock")
	Settings.set_value("debug", "volume_unlock", false)
	Settings.set_value("audio", "master", 1.0)
	var capped := db_to_linear(AudioServer.get_bus_volume_db(0))
	Settings.set_value("debug", "volume_unlock", true)
	var full := db_to_linear(AudioServer.get_bus_volume_db(0))
	Settings.set_value("debug", "volume_unlock", keep_unlock)
	Settings.set_value("audio", "master", keep_master)
	_check("master_volume_cap", absf(capped - 0.75) < 0.005 and absf(full - 1.0) < 0.005,
		"slider 100 -> %.3f of full output; with debug unlock -> %.3f" % [capped, full])


func _quality_preset() -> void:
	## Picking a preset sets the options it covers (and the world follows); the player's own values come back after.
	var keys := ["preset", "shadows", "ssao", "volumetric_fog", "view_distance"]
	var keep := {}
	for k in keys:
		keep[k] = Settings.get_value("graphics", k)
	Settings.set_value("graphics", "preset", "low")
	var L = world.map.lighting
	var ok: bool = int(Settings.get_value("graphics", "shadows")) == 0 and not bool(Settings.get_value("graphics", "ssao")) 		and not L.env.ssao_enabled and not L.moon.shadow_enabled and not L.env.volumetric_fog_enabled
	Settings.set_value("graphics", "preset", "ultra")
	ok = ok and int(Settings.get_value("graphics", "shadows")) == 3 and L.moon.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	for k in keys:
		Settings.set_value("graphics", k, keep[k])
	_check("quality_preset", ok, "low: no shadows, AO or fog; ultra: 4 moon cascades; restored to %s" % str(keep.preset))


func _view_tier(name: String, want: int) -> void:
	## The altitude tiers: in the air the interiors are out of the camera and the AO / local shadows are off.
	var vl = world.map.view_lod
	var cam := get_viewport().get_camera_3d()
	var inside := Defs.RENDER_INTERIOR | Defs.RENDER_INTERIOR_PROPS
	var ok: bool = vl.tier == want and world.map.lighting.air_tier == want
	if want == 0:
		ok = ok and (cam.cull_mask & inside) == inside and world.map.lighting.env.ssao_enabled == bool(Settings.get_value("graphics", "ssao"))
	else:
		ok = ok and (cam.cull_mask & inside) == 0 and not world.map.lighting.env.ssao_enabled and world.map.lighting._shadowed.is_empty()
	_check(name, ok, "tier %d at %.0f m above ground, interiors %s, AO %s, local shadows %d" % [vl.tier, vl.agl,
		"drawn" if (cam.cull_mask & inside) != 0 else "hidden", str(world.map.lighting.env.ssao_enabled), world.map.lighting._shadowed.size()])


func _deploy() -> void:
	await _wait(2.5)
	ctl.pitch = -0.25
	await _shot("plane")
	await _until(func(): return (Net.tick - int(world.match_server.plane.t0)) > int((float(world.match_server.plane.open_s) + 1.0) * Defs.TICK_RATE), 60.0)
	await _hold("jump", 0.2)
	var ok: bool = await _until(func(): return ch.mode == Motor.FREEFALL, 5.0)
	_check("jump", ok, "left the plane" if ok else "still in mode %d" % ch.mode)
	await _wait(2.0)
	ctl.pitch = -0.9
	await _shot("freefall")
	_view_tier("view_tier_freefall", 2)
	await _until(func(): return not is_instance_valid(ch) or ch.mode == Motor.CHUTE, 60.0)
	await _wait(1.5)
	var mates := _teammates()
	var far := 0.0
	for m in mates:
		far = maxf(far, m.global_position.distance_to(ch.global_position))
	_check("team_cluster", mates.is_empty() or far < 60.0, "%d teammates, farthest %.1f m at canopy" % [mates.size(), far])
	if not mates.is_empty():
		_look_at(mates[0].global_position)
	await _shot("canopy_team")
	ctl.pitch = -0.35
	_act_press("move_forward")
	ok = await _until(func(): return not is_instance_valid(ch) or ch.mode == Motor.GROUND, 120.0)
	_act_release("move_forward")
	if not is_instance_valid(ch) or world.local_char == null:
		_check("landed", false, "died during the descent (%s)" % (ch.health.last_cause if is_instance_valid(ch) else "freed"))
		_finish()
		return
	_check("landed", ok and ch.health.health > 60.0, "mode %d, health %.0f at %s" % [ch.mode, ch.health.health, str(ch.global_position.round())])
	await _wait(1.0)
	_view_tier("view_tier_ground", 0)
	ctl.pitch = 0.0
	await _shot("landed")
	if ctl.touch != null:
		await _touch_controls()


func _dark_house() -> void:
	var r := _pick_room()
	if r.is_empty():
		_check("room", false, "no room found")
		return
	var xf: Transform3D = r.xf
	_teleport(xf.origin + Vector3.UP * 0.15, atan2(xf.basis.z.x, xf.basis.z.z))
	ch.light.on = false
	ctl.pitch = -0.15
	await _wait(1.5)
	await _shot("room_dark")
	var dark := await _view_luma()
	await _tap("flashlight")
	await _wait(0.6)
	_check("flashlight_on", ch.light.on, "charge %.2f" % ch.light.charge())
	# The same view lit by the beam: its centre must get clearly brighter (the light being on proves nothing).
	var lit := await _view_luma()
	_check("flashlight_lights_room", lit > dark * 1.5 + 3.0, "centre of view %.1f -> %.1f (0-255)" % [dark, lit])
	await _shot("room_flashlight")
	ctl.yaw += PI * 0.5
	await _wait(0.4)
	await _shot("room_flashlight_turn")


func _house_lights() -> void:
	## A room with a working light and the lane outside, flashlight off: what players see without their own light.
	var best := {}
	var bd := INF
	for spec in world.map.dyn.lights:
		if str(spec.get("kind", "")) not in ["bulb", "tube", "lamp", "candle"] or spec.get("dead", false):
			continue
		for r in world.map.rooms:
			var xf: Transform3D = r.xf
			var local: Vector3 = xf.affine_inverse() * (spec.pos as Vector3)
			var sz: Vector2 = r.size
			if absf(local.x) < sz.x * 0.5 and absf(local.z) < sz.y * 0.5 and local.y > -0.1 and local.y < float(r.h) \
					and str(r.type) != "cr" and sz.x > 2.2 and sz.y > 2.2:
				var d := xf.origin.distance_to(ch.global_position)
				if d < bd:
					bd = d
					best = {"room": r, "light": spec}
		if bd < 60.0:
			break
	if best.is_empty():
		_check("lit_room", false, "no lit room found")
		return
	var r2: Dictionary = best.room
	var xf2: Transform3D = r2.xf
	var sz2: Vector2 = r2.size
	ch.light.on = false
	_teleport(xf2 * Vector3(sz2.x * 0.3, 0.15, -sz2.y * 0.3), 0.0)
	_look_at(best.light.pos)
	ctl.pitch = clampf(ctl.pitch, -0.4, 0.1)
	await _wait(1.5)
	_check("lit_room", true, "%s light in a %s" % [str(best.light.kind), str(r2.type)])
	await _shot("room_lit_%s" % str(best.light.kind))
	# Out into the lane in front of the nearest pole bulb.
	var lane := {}
	var ld := INF
	for spec in world.map.dyn.lights:
		if str(spec.get("kind", "")) == "bulb" and not spec.get("dead", false) and float(spec.get("range", 0)) > 7.0:
			var d2 := (spec.pos as Vector3).distance_to(ch.global_position)
			if d2 < ld:
				ld = d2
				lane = spec
	if not lane.is_empty():
		var p: Vector3 = lane.pos
		var stand := Vector3(p.x + 7.0, world.map.ground_height(p.x + 7.0, p.z), p.z)
		_teleport(stand + Vector3.UP * 0.2, 0.0)
		_lane_spot = stand
		_look_at(p - Vector3.UP * 3.0)
		await _wait(1.5)
		await _shot("lane_bulb")


func _gallery() -> void:
	## Each weapon class in hand under the lane bulb, hip and aimed.
	if _lane_spot == Vector3.INF:
		return
	if not ch.light.on:
		await _tap("flashlight")
	for id in ["pistol_9", "revolver_357", "shotgun_pump", "smg_9", "rifle_762", "rifle_556"]:
		var slot := 3 if Defs.weapon(id).get("slot", "long") == "handgun" else 1
		ch.wpn.slots[slot] = WeaponState.new_instance(id)
		await _tap("holster")
		await _wait(0.3)
		await _tap("weapon_%d" % slot)
		await _wait(1.3)
		await _shot("gun_%s" % id)
		if id in ["pistol_9", "rifle_762"]:
			await _hold("aim", 0.8, "gun_%s_aim" % id)
	ch.wpn.slots[1] = null
	ch.wpn.slots[3] = null
	await _tap("holster")


func _smartab() -> void:
	_act_press("smartab")
	await _wait(1.2)
	_check("smartab_raised", (ch.flags & Character.F_TAB) != 0 and ch.wpn.blocked, "flags %d, weapon blocked %s" % [ch.flags, str(ch.wpn.blocked)])
	await _shot("smartab_status")
	if world.hud and world.hud.smartab:
		world.hud.smartab.next_page(1)
		await _wait(0.4)
		await _shot("smartab_page2")
		world.hud.smartab.open_page("map")
		await _wait(0.4)
		await _shot("smartab_map")
		world.hud.smartab.open_page("status")
	_act_release("smartab")
	await _wait(0.8)
	_check("smartab_lowered", (ch.flags & Character.F_TAB) == 0, "flags %d" % ch.flags)


func _weapons() -> void:
	world.interaction.give(ch, {"id": "rifle_556", "n": 1})
	world.interaction.give(ch, {"id": "ammo_556", "n": 90})
	world.interaction.give(ch, {"id": "pistol_9", "n": 1})
	world.interaction.give(ch, {"id": "ammo_9x19", "n": 45})
	var slot := 1
	for s in [1, 2, 3]:
		if ch.wpn.slots[s] != null and str(ch.wpn.slots[s].id) == "rifle_556":
			slot = s
	await _tap("weapon_%d" % slot)
	var ok: bool = await _until(func(): return ch.wpn.current_id() == "rifle_556" and ch.wpn.can_fire(), 4.0)
	_check("draw_rifle", ok, "current '%s'" % ch.wpn.current_id())
	ctl.pitch = -0.05
	await _shot("rifle_view")
	# Recoil must move the actual aim: compare the view pitch before and after a short burst.
	var p0: float = ctl.pitch
	var shots0: int = ch.wpn.shots
	_act_press("fire")
	await _wait(0.12)
	await _shot("rifle_firing")
	await _wait(0.3)
	_act_release("fire")
	await _wait(0.3)
	_check("rifle_fired", ch.wpn.shots > shots0, "%d shots" % (ch.wpn.shots - shots0))
	_check("recoil_moves_view", ctl.pitch - p0 > 0.004, "pitch climbed %.2f deg" % rad_to_deg(ctl.pitch - p0))
	ctl.pitch = p0
	await _hold("aim", 0.9, "rifle_aim")
	# Long shot outdoors: measure flight time and drop of a real projectile.
	await _ballistics()


func _ballistics() -> void:
	## A level 5.56 shot fired 60 m above the rooftops: follow the server's own projectile tick by tick until it
	## has travelled 300 m, then report its flight time, drop and remaining speed.
	var ps = world.projectiles
	var v0 := float(Defs.weapon("rifle_556").get("muzzle_velocity", 940))
	var origin: Vector3 = ch.global_position + Vector3.UP * 60.0
	var dir := Vector3(1, 0, 0)
	var id: int = ps.spawn(ch, {"ammo": "556", "velocity": v0, "origin": origin, "dir": dir, "seed": 99}, Net.tick, Net.tick)
	var t0 := Net.tick
	var last := {}
	while true:
		await get_tree().physics_frame
		var p = null
		for q in ps.list:
			if int(q.id) == id:
				p = q
		if p == null:
			break
		last = {"pos": p.pos, "vel": p.vel, "ticks": Net.tick - t0}
		if ((p.pos as Vector3) - origin).dot(dir) >= 300.0:
			break
	if last.is_empty():
		_check("bullet_flight", false, "projectile vanished at once")
		return
	var travelled: float = ((last.pos as Vector3) - origin).dot(dir)
	var drop: float = origin.y - (last.pos as Vector3).y
	var secs: float = float(last.ticks) / Defs.TICK_RATE
	_check("bullet_flight", secs > 0.25 and drop > 0.2, "%.0f m in %.3f s (%d ticks), drop %.2f m, %.0f of %.0f m/s left" % [travelled, secs,
		int(last.ticks), drop, (last.vel as Vector3).length(), v0])


func _battery() -> void:
	await _tap("holster")
	world.interaction.give(ch, {"id": "battery", "n": 1, "c": 1.0})
	if not ch.light.on:
		await _tap("flashlight")
	ch.light._set_charge(0.08)
	ch.inv.mark_dirty()
	await _wait(1.0)
	_check("low_battery_flag", ch.light.low(), "charge %.3f" % ch.light.charge())
	await _shot("battery_low")
	ch.light._set_charge(0.0005)
	var died: bool = await _until(func(): return not ch.light.on, 3.0)
	_check("battery_dies", died, "light on %s, charge %.4f" % [str(ch.light.on), ch.light.charge()])
	await _shot("battery_dead")
	var spare = ch.inv.count("battery")
	_act_press("flashlight")
	await _wait(0.7)
	_act_release("flashlight")
	var swapping: bool = ch.light.swapping()
	_check("battery_swap_started", swapping, "swap timer %.2f" % ch.light.swap_t)
	await _shot("battery_swap")
	await _until(func(): return not ch.light.swapping(), 5.0)
	_check("battery_replaced", ch.light.charge() > 0.9 and ch.inv.count("battery") == spare - 1, "charge %.2f, spares %d -> %d" % [ch.light.charge(), spare, ch.inv.count("battery")])
	await _tap("flashlight")


func _corpse() -> void:
	var enemy = null
	for o in world.characters.values():
		if o.team != ch.team and o.mode == Motor.GROUND:
			enemy = o
			break
	if enemy == null:
		_check("corpse", false, "no enemy on the ground")
		return
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, ctl.yaw, 0)).z
	enemy.global_position = ch.global_position + fwd * 2.2 + Vector3.UP * 0.2
	world.interaction.give(enemy, {"id": "battery", "n": 2, "c": 0.77})
	var their_batteries: int = enemy.inv.count("battery")
	await _wait(0.3)
	var before: Array = world.map.dyn.corpses.keys()
	# Squads go down first; a second lethal hit finishes a downed character.
	for i in 2:
		if enemy.mode == Motor.DEAD or not world.characters.has(enemy.eid):
			break
		var res: Dictionary = enemy.health.apply_simple(9999.0, "test", "torso", ch.eid)
		world._after_damage(enemy, res, ch.eid)
	var cid := -1
	for k in world.map.dyn.corpses.keys():
		if k not in before:
			cid = k
	await _wait(3.0)
	var c = world.map.dyn.corpses.get(cid)
	_check("corpse_spawned", c != null, "corpse %d" % cid)
	if c == null:
		return
	# Kneel-distance from the body with a clear view of it (the body may have fallen against furniture).
	var cc: Vector3 = c.center()
	var space = world.get_world_3d().direct_space_state
	var spot := Vector3(cc.x, ch.global_position.y, cc.z) + Vector3(1.1, 0, 0)
	for k in 12:
		var a := TAU * k / 12.0
		var cand := Vector3(cc.x, ch.global_position.y, cc.z) + Vector3(cos(a), 0, sin(a)) * 1.1
		var eye := cand + Vector3.UP * 1.6
		var q := PhysicsRayQueryParameters3D.create(eye, cc, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var q2 := PhysicsRayQueryParameters3D.create(cand + Vector3.UP * 1.0, Vector3(cc.x, cand.y + 1.0, cc.z), Defs.PHYS_WORLD)
		if space.intersect_ray(q).is_empty() and space.intersect_ray(q2).is_empty():
			spot = cand
			break
	ch.global_position = spot
	ch.velocity = Vector3.ZERO
	await _wait(0.2)
	_look_at(cc)
	await _shot("corpse")
	var mine = ch.inv.count("battery")
	var opened := false
	for i in 6:
		await _tap("interact")
		await _wait(0.4)
		if world.interaction._open.has(ch.eid):
			opened = true
			break
		_look_at(cc + Vector3(randf_range(-0.2, 0.2), -0.05 * i, randf_range(-0.2, 0.2)))
	if not opened:
		var tgt: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
		var eye: Vector3 = ch.eye_position()
		var q := PhysicsRayQueryParameters3D.create(eye, cc, 0xFFFFFFFF)
		q.exclude = [ch.get_rid()]
		var hit = world.get_world_3d().direct_space_state.intersect_ray(q)
		print("[autotest] corpse diag: mode %d, eye %s, centre %s (%.2f m), target %s, ray hit %s layer %s meta %s" % [ch.mode, str(eye), str(cc),
			eye.distance_to(cc), str(tgt), str(hit.get("collider")), str(hit.get("collider").collision_layer if hit.get("collider") else -1),
			str(hit.get("collider").get_meta_list() if hit.get("collider") else [])])
	_check("corpse_opened", opened, "%d entries, %d batteries on body" % [(c.entries as Array).size(), their_batteries])
	if opened:
		_act_press("smartab")
		await _wait(1.0)
		await _shot("corpse_loot")
		for i in range((c.entries as Array).size() - 1, -1, -1):
			if str(c.entries[i].id) == "battery":
				world.request_inventory({"op": "take", "index": i})
		await _wait(0.5)
		_act_release("smartab")
	_check("corpse_battery_looted", ch.inv.count("battery") > mine, "batteries %d -> %d" % [mine, ch.inv.count("battery")])
	await _wait(2.0)
	_check("corpse_persists", world.map.dyn.corpses.has(cid) and is_instance_valid(world.map.dyn.corpses[cid]), "after looting")


func _observer_view() -> void:
	## A free camera behind another character, to see bodies, held weapons and flashlights as others see them.
	var target = null
	for o in world.characters.values():
		if o != ch and o.mode == Motor.GROUND:
			target = o
			break
	if target == null:
		return
	# Out in the lane by the bulb: find a clear 5 m line, put them at the far end, armed, light on, facing us.
	var spot: Vector3 = _lane_spot if _lane_spot != Vector3.INF else ch.global_position
	ch.global_position = spot + Vector3.UP * 0.2
	var space = world.get_world_3d().direct_space_state
	for k in 16:
		var a := TAU * k / 16.0
		var dir := Vector3(sin(a), 0, cos(a))
		var q := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 1.4, spot + Vector3.UP * 1.4 + dir * 6.0, Defs.PHYS_WORLD)
		if space.intersect_ray(q).is_empty():
			ctl.yaw = atan2(-dir.x, -dir.z)
			break
	world.interaction.give(target, {"id": "smg_9", "n": 1})
	target.wpn.want = target.wpn.slot_for("smg_9")
	target.wpn.cur = target.wpn.want
	target.light.on = true
	var brain = world.bots.get(target.eid)
	world.bots.erase(target.eid)
	world._queues[target.eid] = []
	target.last_cmd = {}
	var cam := Camera3D.new()
	world.add_child(cam)
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, ctl.yaw, 0)).z
	target.global_position = spot + fwd * 4.5 + Vector3.UP * 0.3
	target.yaw = ctl.yaw + PI
	var eye: Vector3 = spot + Vector3.UP * 1.6 + fwd.cross(Vector3.UP) * 0.6
	cam.look_at_from_position(eye, target.global_position + Vector3.UP * 1.1)
	ch.global_position = spot - fwd * 0.5
	cam.current = true
	await _wait(0.8)
	await _shot("observer_other_player")
	cam.current = false
	ctl.cam.current = true
	cam.queue_free()
	if brain:
		world.bots[target.eid] = brain


# ------------------------------------------------------------------ loot (--autotest=loot)

func _loot_run() -> void:
	_loot_census()
	_attachment_math()
	await _deploy()
	if not is_instance_valid(ch):
		return
	_loot_rest()
	await _loot_box_use()
	await _loot_pickup()
	await _loot_lineup()
	await _attachment_views()
	await _observer_kit()
	if _lamp:
		_lamp.queue_free()


func _droppable_ids() -> Array:
	var ids := {}
	for t in (Defs.loot.get("tables", {}) as Dictionary).values():
		for e in (t.get("entries", []) as Array) + (t.get("guaranteed", []) as Array):
			ids[str(e[0])] = true
	for w in Defs.weapons:
		ids[w] = true
	for a in Defs.attachments:
		ids[a] = true
	ids.erase("nothing")
	var out := ids.keys()
	out.sort()
	return out


func _loot_census() -> void:
	## Every id that can drop has its own model; loot boxes and floor loot across the map.
	var bad := []
	var ids := _droppable_ids()
	for id in ids:
		var md: Dictionary = world.map.item_visual(id)
		if md.get("mesh") == null or md.get("placeholder", false):
			bad.append(id)
	_check("loot_models_census", bad.is_empty(), "%d droppable ids, without a model: %s" % [ids.size(), str(bad)])
	var dyn = world.map.dyn
	var in_houses := 0
	var kinds := {}
	for b in dyn.loot_boxes:
		kinds[b.name] = int(kinds.get(b.name, 0)) + 1
		if int(dyn.containers[int(b.cid)].bid) >= 0:
			in_houses += 1
	var houses := 0
	for b in world.map.buildings:
		if str(b.get("kind", "house")) in ["house", "apartment", "shop"]:
			houses += 1
	_check("loot_boxes_count", dyn.loot_boxes.size() >= 2000 and in_houses >= houses,
		"%d loot boxes (%d inside buildings, %d houses/shops/apartments), by model %s" % [dyn.loot_boxes.size(), in_houses, houses, str(kinds)])
	var cats := {"weapon": 0, "ammo": 0, "attachment": 0, "other": 0}
	for id in dyn.items:
		var k := str(Defs.item(str(dyn.items[id].entry.id)).get("kind", ""))
		cats[k if cats.has(k) else "other"] = int(cats.get(k if cats.has(k) else "other", 0)) + 1
	_check("floor_loot_count", cats.weapon > 300 and cats.ammo > 500 and cats.attachment > 300,
		"%d items on the ground: %s" % [dyn.items.size(), str(cats)])


func _attachment_math() -> void:
	## Each attachment kind changes the stat it is for, measured on a weapon state with no character.
	var ws := WeaponState.new(null)
	var w := WeaponState.new_instance("rifle_556", null, 1.0)
	ws.slots[1] = w
	ws.cur = 1
	var z0 := ws.zoom()
	w.att = ["scope_4x"]
	var z4 := ws.zoom()
	w.att = ["sight_reddot"]
	var z1 := ws.zoom()
	_check("att_sight_zoom", absf(z4 - 4.0) < 0.01 and absf(z1 - 1.3) < 0.01 and ws.scoped() == false,
		"iron %.2f, red dot %.2f (not a scope view), 4x %.2f" % [z0, z1, z4])
	w.att = ["scope_4x", "grip_angled"]
	var ads_m := ws._ads_mult()
	_check("att_ads_time", absf(ads_m - 1.25 * 0.85) < 0.001, "4x scope with angled grip: aiming takes x%.3f" % ads_m)
	# Recoil of one shot, without and with a compensator and a vertical grip.
	var kicks := []
	for kit in [[], ["compensator"], ["compensator", "grip_vertical"]]:
		w.att = kit
		ws.kick = Vector2.ZERO
		ws.climb_pending = 0.0
		ws.burst = 1
		ws._apply_recoil(12345)
		kicks.append(ws.kick.y + ws.climb_pending)
	_check("att_recoil", kicks[1] < kicks[0] * 0.82 and kicks[2] < kicks[1] * 0.87,
		"vertical kick per shot: bare %.3f, compensator %.3f, + vertical grip %.3f deg" % kicks)
	w.att = []
	ws.ads = 0.0
	var sp0 := ws.spread_deg(0.0, false)
	w.att = ["laser_sight"]
	var sp1 := ws.spread_deg(0.0, false)
	_check("att_laser_spread", absf(sp1 - sp0 * 0.65) < 0.001, "hip spread %.2f -> %.2f deg with a laser" % [sp0, sp1])
	w.att = ["mag_ext_rifle"]
	var cap1 := ws.mag_cap()
	w.att = []
	var cap0 := ws.mag_cap()
	_check("att_mag_ext", cap0 == 30 and cap1 == 40, "magazine %d -> %d with the extended magazine" % [cap0, cap1])
	w.att = ["mag_quick_rifle"]
	w.mag = 5
	w.chamber = true
	ws.reserve_cache["556"] = 200
	ws.state = WeaponState.IDLE
	ws.start_reload()
	var t_quick := ws.timer
	w.att = []
	ws.state = WeaponState.IDLE
	ws.start_reload()
	var t_base := ws.timer
	_check("att_quick_reload", absf(t_quick - t_base * 0.7) < 0.01, "reload %.2f s -> %.2f s with the quickdraw magazine" % [t_base, t_quick])
	var sup := {"id": "pistol_9", "att": ["suppressor_light"]}
	_check("att_suppressor", Attach.mult(sup, "loudness_mult") < 0.5 and Attach.mult(sup, "flash_mult") < 0.15 and SoundSys.defs.has("shot_pistol_9_sup"),
		"loudness x%.2f, flash x%.2f, suppressed sound %s" % [Attach.mult(sup, "loudness_mult"), Attach.mult(sup, "flash_mult"), str(SoundSys.defs.has("shot_pistol_9_sup"))])
	_check("att_choke", absf(Attach.mult({"att": ["choke"]}, "pellet_spread_mult") - 0.65) < 0.001, "buckshot pattern x0.65 with a choke")
	# Break action: both barrels load at once.
	var dbl := WeaponState.new_instance("shotgun_double", null, 0.0)
	ws.slots[1] = dbl
	ws.reserve_cache["12buck"] = 10
	ws.state = WeaponState.IDLE
	ws.start_reload()
	ws._reload_step(10.0, false)
	_check("break_action_reload", ws.loaded() == 2 and int(ws.reserve_cache["12buck"]) == 8, "double barrel loaded %d, 8 shells left: %d" % [ws.loaded(), int(ws.reserve_cache["12buck"])])
	# Bitmask round trip (what other players see fitted).
	var kit2 := ["choke", "scope_8x", "weapon_light"]
	var back := Attach.from_bitmask(Attach.bitmask({"att": kit2}))
	back.sort()
	kit2.sort()
	_check("att_replication_mask", back == kit2, "%s -> %s" % [str(kit2), str(back)])


func _loot_rest() -> void:
	## Floor items rest on what is under them: a ray down from each must find a surface 0-5 cm below.
	var space = world.get_world_3d().direct_space_state
	var n := 0
	var ok := 0
	var worst := []
	var dyn = world.map.dyn
	for id in range(1, dyn.floor_count + 1, 7):
		if not dyn.items.has(id):
			continue
		var o: Vector3 = (dyn.items[id].xf as Transform3D).origin
		var q := PhysicsRayQueryParameters3D.create(o + Vector3.UP * 0.3, o + Vector3.DOWN * 0.6, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var r = space.intersect_ray(q)
		n += 1
		var gap := 9.0 if r.is_empty() else o.y - (r.position as Vector3).y
		if gap > -0.005 and gap < 0.05:
			ok += 1
		elif worst.size() < 12:
			var table := "?"
			for sp in dyn.loot_spots:
				if Vector2((sp.pos as Vector3).x - o.x, (sp.pos as Vector3).z - o.z).length() < 0.3:
					table = str(sp.table)
			worst.append("%s %.2f m at %s (%s)" % [str(dyn.items[id].entry.id), gap, str(o.snapped(Vector3.ONE * 0.1)), table])
	_check("floor_items_rest", n > 100 and ok >= n * 0.95, "%d of %d sampled items 0-5 cm above a surface; e.g. %s" % [ok, n, str(worst)])


func _nearest_box(in_house: bool) -> Dictionary:
	var dyn = world.map.dyn
	var best := {}
	var bd := INF
	for b in dyn.loot_boxes:
		var c: Dictionary = dyn.containers[int(b.cid)]
		if b.open or (in_house and int(c.bid) < 0):
			continue
		var d := (c.pos as Vector3).distance_to(ch.global_position)
		if d < bd:
			bd = d
			best = b
	return best


func _nearest_box_excluding(skip: Dictionary) -> Dictionary:
	var dyn = world.map.dyn
	var best := {}
	var bd := INF
	for b in dyn.loot_boxes:
		var c: Dictionary = dyn.containers[int(b.cid)]
		if b.open or int(c.bid) < 0 or skip.has(int(b.cid)):
			continue
		var d := (c.pos as Vector3).distance_to(ch.global_position)
		if d < bd:
			bd = d
			best = b
	return best


func _stand_by(target: Vector3, floor_y: float, dist: float = 1.2) -> bool:
	## Puts the player on open floor next to a point, looking at it, with nothing in between.
	var space = world.get_world_3d().direct_space_state
	for k in 12:
		var a := TAU * k / 12.0
		var stand := Vector3(target.x + cos(a) * dist, floor_y, target.z + sin(a) * dist)
		var down := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 1.0, stand + Vector3.DOWN * 0.4, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var hit = space.intersect_ray(down)
		if hit.is_empty() or absf((hit.position as Vector3).y - floor_y) > 0.25:
			continue
		var body := PhysicsRayQueryParameters3D.create(stand + Vector3.UP * 1.0, target + Vector3.UP * 0.05, Defs.PHYS_WORLD | Defs.PHYS_PROP)
		var head := PhysicsRayQueryParameters3D.create((hit.position as Vector3) + Vector3.UP * 1.65, target, Defs.SIGHT_MASK)
		var h2 = space.intersect_ray(head)
		if not space.intersect_ray(body).is_empty() and (space.intersect_ray(body).position as Vector3).distance_to(target) > 0.45:
			continue
		if not h2.is_empty() and (h2.position as Vector3).distance_to(target) > 0.45:
			continue
		_teleport((hit.position as Vector3) + Vector3.UP * 0.05, 0.0)
		return true
	return false


func _loot_box_use() -> void:
	## Walk up to a loot box in a house, Use it: its contents open on the SmarTab and the lid opens.
	var b := {}
	var c := {}
	var tried := {}
	for attempt in 8:
		var cand := _nearest_box_excluding(tried)
		if cand.is_empty():
			break
		tried[int(cand.cid)] = true
		var cc: Dictionary = world.map.dyn.containers[int(cand.cid)]
		var base_y: float = (cand.xf as Transform3D).origin.y
		if not _stand_by(cc.pos, base_y, 1.0) and not _stand_by(cc.pos, base_y, 1.4):
			continue
		await _wait(0.3)
		_look_at(cc.pos)
		var t0: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
		if str(t0.get("kind", "")) == "container" and int(t0.get("id", -1)) == int(cand.cid):
			b = cand
			c = cc
			break
	if b.is_empty():
		_check("loot_box_opens", false, "no loot box with a clear Use line among %d tried" % tried.size())
		return
	if not ch.light.on:
		await _tap("flashlight")
	await _wait(0.6)
	_look_at(c.pos)
	await _wait(0.5)
	await _shot("lootbox_closed")
	var t: Dictionary = world.interaction.target(ch, {"yaw": ctl.yaw, "pitch": ctl.pitch})
	var prompt: String = world.hud.prompt.text
	await _tap("interact")
	var ok: bool = await _until(func(): return bool(b.open), 3.0)
	await _wait(0.6)
	await _shot("lootbox_open")
	var shown: Dictionary = world.hud.smartab.container
	var lid_drawn: bool = b.get("inst_open", RID()).is_valid()
	_check("loot_box_opens", ok and lid_drawn and t.get("kind", "") == "container" and int(t.get("id", -1)) == int(b.cid),
		"%s: target %s %s, prompt '%s', lid open %s (open model drawn %s), SmarTab shows %d entries" % [str(b.name), str(t.get("kind", "-")),
		str(t.get("id", "")), prompt, str(b.open), str(lid_drawn), (shown.get("entries", []) as Array).size()])
	world.hud.smartab.close_container()


func _spawn_in_front(entry: Dictionary, d: float = 1.0) -> int:
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, ctl.yaw, 0)).z
	var p: Vector3 = ch.global_position + fwd * d
	var space = world.get_world_3d().direct_space_state
	var r = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.DOWN * 2.0, Defs.PHYS_WORLD | Defs.PHYS_PROP))
	if not r.is_empty():
		p = r.position
	var before: int = world.map.dyn._next_item
	world.map_item_spawn_server(entry, Transform3D(Basis(Vector3.UP, 0.4), p + Vector3.UP * 0.01))
	return before


func _loot_pickup() -> void:
	## Floor pickups: a scope goes straight onto the rifle, ammunition is named for the gun it fits, a gun picked up
	## takes compatible attachments from the bag.
	var spot := _open_patch(ch.global_position)
	_teleport(spot + Vector3.UP * 0.1, 0.0)
	await _wait(0.5)
	for s in [1, 2, 3]:
		ch.wpn.slots[s] = null
	world.interaction.give(ch, {"id": "rifle_556", "n": 1, "w": WeaponState.new_instance("rifle_556", null, 1.0)})
	ch.inv.mark_dirty()
	var id := _spawn_in_front({"id": "scope_4x", "n": 1})
	var it: Dictionary = world.map.dyn.items[id]
	_look_at((it.xf as Transform3D).origin + Vector3.UP * 0.03)
	await _wait(0.4)
	world.hud._prompt_t = 0.0
	await _wait(0.2)
	var prompt: String = world.hud.prompt.text
	await _shot("floor_scope_prompt")
	await _tap("interact")
	await _wait(0.3)
	_check("pickup_fits_scope", "scope_4x" in ch.wpn.slots[1].att and not world.map.dyn.items.has(id) and "fits your" in prompt,
		"prompt '%s'; rifle now has %s" % [prompt, str(ch.wpn.slots[1].att)])
	id = _spawn_in_front({"id": "ammo_556", "n": 30})
	_look_at((world.map.dyn.items[id].xf as Transform3D).origin + Vector3.UP * 0.02)
	await _wait(0.4)
	world.hud._prompt_t = 0.0
	await _wait(0.2)
	var prompt2: String = world.hud.prompt.text
	await _tap("interact")
	await _wait(0.3)
	_check("pickup_ammo_named", "for your" in prompt2 and ch.inv.count("ammo_556") >= 30, "prompt '%s'; carrying %d rounds" % [prompt2, ch.inv.count("ammo_556")])
	# A spare that fits nothing carried stays in the bag; picking up a gun it fits mounts it.
	world.interaction.give(ch, {"id": "grip_vertical", "n": 1})
	var in_bag: bool = ch.inv.count("grip_vertical") == 1 or "grip_vertical" in ch.wpn.slots[1].att
	world.interaction.give(ch, {"id": "suppressor_light", "n": 1})
	var sup_bag: bool = ch.inv.count("suppressor_light") == 1
	world.interaction.give(ch, {"id": "smg_9", "n": 1, "w": WeaponState.new_instance("smg_9", null, 1.0)})
	var smg = ch.wpn.slots[2] if ch.wpn.slots[2] != null and str(ch.wpn.slots[2].id) == "smg_9" else ch.wpn.slots[1]
	_check("gun_takes_bag_attachments", sup_bag and in_bag and "suppressor_light" in smg.att,
		"suppressor waited in the bag (%s), SMG picked up with %s" % [str(sup_bag), str(smg.att)])


func _sight_screen_error(wid: String, att: String) -> float:
	## Pixels between the reticle (where bullets go) and the fitted sight's optical axis on screen while aiming.
	var vm = ctl.vm
	var ax: Vector3 = AttachVisual.sight_axis(world.map, wid, att) - vm._grip_vis
	var world_pt: Vector3 = vm.weapon_root.global_transform * ax
	var cam: Camera3D = ctl.cam
	var off: Vector2 = ch.wpn.aim_offset_deg(Net.tick)
	var b: Basis = cam.global_transform.basis * Basis(Vector3.UP, deg_to_rad(-off.x)) * Basis(Vector3.RIGHT, deg_to_rad(off.y))
	var aim := cam.unproject_position(cam.global_position - b.z * 50.0)
	# The sight's line: from the eye through its optical centre.
	var through := cam.unproject_position(cam.global_position + (world_pt - cam.global_position).normalized() * 50.0)
	return aim.distance_to(through)


func _attachment_views() -> void:
	## First-person captures of fitted attachments; aiming lines a red dot up with the bullets; the scope view.
	if ch.light.on:
		await _tap("flashlight")
	for s in [1, 2, 3]:
		ch.wpn.slots[s] = null
	var rifle := WeaponState.new_instance("rifle_556", null, 1.0)
	rifle.att = ["sight_reddot", "suppressor_rifle", "grip_vertical", "mag_ext_rifle", "weapon_light"]
	ch.wpn.slots[1] = rifle
	ch.inv.add({"id": "ammo_556", "n": 60}, true)
	ch.inv.mark_dirty()
	await _tap("weapon_1")
	await _until(func(): return ch.wpn.current_id() == "rifle_556" and ch.wpn.state == WeaponState.IDLE, 4.0)
	ctl.pitch = -0.08
	await _wait(0.6)
	await _shot("rifle_kit_hip")
	_act_press("aim")
	await _wait(0.9)
	var err := _sight_screen_error("rifle_556", "sight_reddot")
	await _shot("rifle_reddot_aim")
	_act_release("aim")
	_check("reddot_on_bullet_line", err < 8.0, "red dot %.1f px from where the bullets go" % err)
	rifle.att = ["sight_holo", "compensator", "grip_angled", "laser_sight"]
	rifle.att.erase("laser_sight")
	rifle.att.append("weapon_light")
	await _wait(0.3)
	_act_press("aim")
	await _wait(0.9)
	var err2 := _sight_screen_error("rifle_556", "sight_holo")
	await _shot("rifle_holo_aim")
	_act_release("aim")
	_check("holo_on_bullet_line", err2 < 8.0, "holographic sight %.1f px from where the bullets go" % err2)
	for kit in [["scope_4x", "flash_hider"], ["scope_6x", "suppressor_rifle"]]:
		rifle.att = kit
		await _wait(0.3)
		_act_press("aim")
		await _wait(1.1)
		var scope_vis: bool = world.hud.scope.visible
		var gun_hidden: bool = not ctl.vm.weapon_root.visible
		var fov: float = ctl.cam.fov
		await _shot("rifle_%s_view" % kit[0])
		_act_release("aim")
		await _wait(0.4)
		var want := float(Settings.get_value("graphics", "fov")) / float(Defs.attachments[kit[0]].zoom)
		_check("scope_view_%s" % kit[0], scope_vis and gun_hidden and absf(fov - want) < 1.0,
			"scope view %s, gun hidden %s, field of view %.1f (want %.1f)" % [str(scope_vis), str(gun_hidden), fov, want])
	# The new guns in hand.
	for wid in ["marksman_308", "shotgun_double", "sumpak"]:
		var w2 := WeaponState.new_instance(wid, null, 1.0)
		if wid == "marksman_308":
			w2.att = ["scope_8x", "cheek_pad", "suppressor_rifle", "mag_ext_sniper"]
		elif wid == "shotgun_double":
			w2.att = ["choke", "bullet_loops"]
		ch.wpn.slots[1] = w2
		await _tap("holster")
		await _wait(0.3)
		await _tap("weapon_1")
		await _wait(1.2)
		await _shot("gun_%s" % wid)
		if wid == "marksman_308":
			_act_press("aim")
			await _wait(1.2)
			await _shot("gun_marksman_8x_view")
			_act_release("aim")
			await _wait(0.4)
	await _tap("holster")


var _lamp: OmniLight3D = null


func _open_patch(near: Vector3) -> Vector3:
	## Open ground with sky above over a 7 x 9 m patch near a point (for laying things out and photographing them).
	var space = world.get_world_3d().direct_space_state
	var L = world.map.layout
	for ring in 60:
		for k in 12:
			var a := k * TAU / 12.0
			var c := Vector2(near.x, near.z) + Vector2(cos(a), sin(a)) * ring * 2.0
			var gy: float = L.ground_height(c.x, c.y)
			var clear := true
			for gx in range(-3, 4):
				for gz in range(-4, 5):
					var p := c + Vector2(gx, gz)
					var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, gy + 30.0, p.y), Vector3(p.x, gy - 5.0, p.y)))
					if hit.is_empty() or absf(hit.position.y - gy) > 0.25 or L.is_water(p.x, p.y):
						clear = false
						break
				if not clear:
					break
			if clear:
				return Vector3(c.x, gy, c.y)
	return near


func _observer_kit() -> void:
	## Another player's rifle with a scope, suppressor, grip, laser and extended magazine, seen by us: the fitted
	## attachments are drawn on their gun (from the replicated mask) and their laser puts a dot on what it points at.
	var target = null
	for o in world.characters.values():
		if o != ch and o.mode == Motor.GROUND and world.bots.has(o.eid):
			target = o
			break
	if target == null:
		_check("observer_attachments", false, "no bot on the ground")
		return
	var brain = world.bots.get(target.eid)
	world.bots.erase(target.eid)
	world._queues[target.eid] = []
	target.last_cmd = {}
	var kit := ["scope_6x", "suppressor_rifle", "grip_vertical", "laser_sight", "mag_ext_rifle"]
	var w := WeaponState.new_instance("rifle_556", null, 1.0)
	w.att = kit.duplicate()
	target.wpn.slots[1] = w
	target.wpn.want = 1
	target.wpn.cur = 1
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, ctl.yaw, 0)).z
	var spot: Vector3 = ch.global_position
	target.global_position = spot + fwd * 3.0 + Vector3.UP * 0.1
	target.yaw = ctl.yaw + PI * 0.75
	target.pitch = -0.1
	await _wait(1.0)
	var vis = target.get("visual")
	var drawn := 0
	var laser := false
	if vis:
		drawn = vis.att_root.get_child_count()
		laser = vis.laser_dot != null and vis.laser_dot.visible
	var cam := Camera3D.new()
	world.add_child(cam)
	var side: Vector3 = fwd.cross(Vector3.UP).normalized()
	cam.look_at_from_position(spot + Vector3.UP * 1.5 + side * 1.2, target.global_position + Vector3.UP * 1.2)
	cam.current = true
	await _wait(0.6)
	await _shot("observer_rifle_kit")
	cam.current = false
	ctl.cam.current = true
	cam.queue_free()
	_check("observer_attachments", drawn == kit.size() and laser and target.weapon_att == Attach.bitmask(w),
		"%d of %d attachments drawn on their gun, laser dot %s, replicated mask %d" % [drawn, kit.size(), "visible" if laser else "not visible", target.weapon_att])
	if brain:
		world.bots[target.eid] = brain


func _loot_lineup() -> void:
	## One of every droppable thing laid out on open ground, captured from above under a work light (an inspection
	## light for the picture only; it is removed afterwards).
	var ids := _droppable_ids()
	var spot := _open_patch(ch.global_position)
	_teleport(spot + Vector3.UP * 0.1, 0.0)
	await _wait(0.5)
	var p0: Vector3 = ch.global_position
	var fwd: Vector3 = -Basis.from_euler(Vector3(0, ctl.yaw, 0)).z
	var right := fwd.cross(Vector3.UP).normalized()
	var space = world.get_world_3d().direct_space_state
	var cols := 8
	var spawned := 0
	for i in ids.size():
		var r := i / cols
		var c := i % cols
		var p := p0 + fwd * (1.4 + r * 0.75) + right * ((c - cols * 0.5 + 0.5) * 0.7)
		var hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.8, p + Vector3.DOWN * 1.5, Defs.PHYS_WORLD | Defs.PHYS_PROP))
		if hit.is_empty():
			continue
		var e := {"id": ids[i], "n": 1}
		if Defs.is_weapon(ids[i]):
			e.w = WeaponState.new_instance(ids[i], null, 1.0)
		world.map_item_spawn_server(e, Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z) + PI * 0.5), (hit.position as Vector3) + Vector3.UP * 0.01))
		spawned += 1
	_lamp = OmniLight3D.new()
	_lamp.omni_range = 10.0
	_lamp.light_energy = 2.5
	_lamp.shadow_enabled = true
	world.add_child(_lamp)
	_lamp.global_position = p0 + fwd * 3.0 + Vector3.UP * 3.0
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(p0 + Vector3.UP * 3.2 - fwd * 0.6, p0 + fwd * 3.2)
	cam.current = true
	await _wait(1.0)
	await _shot("loot_lineup")
	cam.look_at_from_position(p0 + Vector3.UP * 1.0 + fwd * 0.6, p0 + fwd * 2.2)
	await _wait(0.5)
	await _shot("loot_lineup_close")
	cam.current = false
	ctl.cam.current = true
	cam.queue_free()
	# The attachment captures follow here, at the edge of the light, facing away from the laid-out loot.
	_lamp.global_position = p0 + Vector3.UP * 2.6 - fwd * 1.5
	ctl.yaw += PI
	_check("loot_lineup", spawned >= ids.size() * 0.95, "%d of %d ids laid out" % [spawned, ids.size()])


# ------------------------------------------------------------------ helpers

# ------------------------------------------------------------------ performance

## --autotest=perf: a real deploy and a few ground spots with vsync off, recording frame time, the renderer's own
## CPU/GPU timings and draw counts per phase. Prints "[perf] <phase> ..." lines and writes perf.json.
var _perf_phase := ""
var _perf_last_us := 0
var _perf_spin := 0.0
var _perf_s := {}
var _perf_report: Array = []
var _perf_phys0 := 0
var _phys_end_us := 0
var _perf_tier := -1
var _phys_frame := -1


func _physics_process(_dt: float) -> void:
	# Runs after every other physics callback (priority set in _ready): the engine's physics step follows.
	if _perf_phase != "":
		_phys_end_us = Time.get_ticks_usec()
		_phys_frame = Engine.get_process_frames()


func _process(dt: float) -> void:
	if _perf_phase == "":
		return
	if _phys_frame == Engine.get_process_frames() and _phys_end_us > 0:
		# First process callback after this frame's physics: the gap is the physics engine step (plus syncing).
		(_perf_s.step as Array).append((Time.get_ticks_usec() - _phys_end_us) / 1000.0)
		_phys_frame = -1
	if _perf_spin != 0.0 and ctl:
		ctl.yaw += _perf_spin * dt
	var now := Time.get_ticks_usec()
	var vl = world.map.view_lod if world.map else null
	if vl and vl.tier != _perf_tier:
		print("[perf]   view tier %d -> %d at %.0f m above ground (%s)" % [_perf_tier, vl.tier, vl.agl, _perf_phase])
		_perf_tier = vl.tier
	if _perf_last_us > 0 and (now - _perf_last_us) > 25000:
		print("[perf]   hitch %.1f ms in %s, tier %d, %.0f m above ground" % [(now - _perf_last_us) / 1000.0, _perf_phase, vl.tier if vl else -1, vl.agl if vl else 0.0])
	if _perf_last_us > 0:
		var rid := get_viewport().get_viewport_rid()
		(_perf_s.ft as Array).append((now - _perf_last_us) / 1000.0)
		(_perf_s.cpu as Array).append(RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu())
		(_perf_s.gpu as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		(_perf_s.proc as Array).append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		(_perf_s.phys as Array).append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		(_perf_s.draws as Array).append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		(_perf_s.objs as Array).append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
		(_perf_s.prims as Array).append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	_perf_last_us = now


func _perf_begin(phase: String, spin: float = 0.0) -> void:
	_perf_s = {}
	for k in ["ft", "cpu", "gpu", "proc", "phys", "draws", "objs", "prims", "step"]:
		_perf_s[k] = []
	_perf_last_us = 0
	_perf_spin = spin
	_perf_phase = phase
	_perf_phys0 = Engine.get_physics_frames()
	Prof.reset()
	var BotBrain = load("res://src/ai/bot_brain.gd")
	if BotBrain.nav:
		BotBrain.nav.stats = {"searches": 0, "ms_total": 0.0, "ms_max": 0.0}


func _perf_end() -> void:
	if _perf_phase == "":
		return
	var ft: Array = _perf_s.ft
	var row := {"phase": _perf_phase, "frames": ft.size()}
	if ft.size() > 2:
		var sorted := ft.duplicate()
		sorted.sort()
		var n := sorted.size()
		var total := 0.0
		for v in ft:
			total += v
		row.avg_ms = total / n
		row.fps = 1000.0 / row.avg_ms
		row.p50 = sorted[n / 2]
		row.p95 = sorted[mini(int(n * 0.95), n - 1)]
		row.p99 = sorted[mini(int(n * 0.99), n - 1)]
		row.max = sorted[n - 1]
		row.over_16ms = 0
		for v in ft:
			if v > 16.7:
				row.over_16ms += 1
		for k in ["cpu", "gpu", "proc", "phys", "draws", "objs", "prims"]:
			var arr: Array = _perf_s[k]
			var s := 0.0
			for v in arr:
				s += v
			row[k] = s / maxf(arr.size(), 1.0)
		var agl := 0.0
		if is_instance_valid(ch):
			agl = ch.global_position.y - float(world.map.layout.ground_height(ch.global_position.x, ch.global_position.z))
		print("[perf] %-14s %5d fr  avg %6.2f ms (%5.0f fps)  p50 %6.2f  p95 %6.2f  p99 %6.2f  max %6.2f  >16.7ms %4d | render cpu %5.2f gpu %5.2f | process %5.2f physics %5.2f | draws %6.0f objs %6.0f prims %8.0f | agl %.0f" % [
			_perf_phase, n, row.avg_ms, row.fps, row.p50, row.p95, row.p99, row.max, row.over_16ms, row.cpu, row.gpu, row.proc, row.phys,
			row.draws, row.objs, row.prims, agl])
		row.phys_steps = float(Engine.get_physics_frames() - _perf_phys0) / n
		var secs := []
		for k in Prof.acc:
			secs.append([float(Prof.acc[k]) / 1000.0 / n, k])
		secs.sort_custom(func(a, b): return a[0] > b[0])
		var parts := []
		for i in mini(secs.size(), 14):
			parts.append("%s %.2f" % [secs[i][1], secs[i][0]])
			row["sec." + secs[i][1]] = secs[i][0]
		var steps: Array = _perf_s.step
		var st := 0.0
		var smax := 0.0
		for v in steps:
			st += v
			smax = maxf(smax, v)
		row.jolt_step = st / maxf(steps.size(), 1.0)
		print("[perf]   %.2f physics steps/frame; engine physics step avg %.2f ms max %.2f ms; active bodies %d, pairs %d, islands %d" % [row.phys_steps,
			row.jolt_step, smax, PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS),
			PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_COLLISION_PAIRS), PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ISLAND_COUNT)])
		print("[perf]   ms/frame: %s" % ", ".join(parts))
		var pk := []
		for k in Prof.peak:
			pk.append([float(Prof.peak[k]) / 1000.0, k])
		pk.sort_custom(func(a, b): return a[0] > b[0])
		var pparts := []
		for i in mini(pk.size(), 8):
			pparts.append("%s %.1f" % [pk[i][1], pk[i][0]])
		print("[perf]   worst single call (ms): %s" % ", ".join(pparts))
		var nav = load("res://src/ai/bot_brain.gd").nav
		if nav and int(nav.stats.searches) > 0:
			print("[perf]   bot path searches (worker thread): %d, avg %.2f ms, max %.2f ms" % [nav.stats.searches,
				float(nav.stats.ms_total) / int(nav.stats.searches), nav.stats.ms_max])
	_perf_report.append(row)
	_perf_phase = ""
	_perf_spin = 0.0


func _agl() -> float:
	if not is_instance_valid(ch):
		return 0.0
	return ch.global_position.y - float(world.map.layout.ground_height(ch.global_position.x, ch.global_position.z))


func _perf_run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	Prof.on = true
	print("[perf] %s, window %s, shadows %d, ssao %s, volumetric fog %s, render scale %.2f" % [RenderingServer.get_video_adapter_name(),
		str(get_window().size), int(Settings.get_value("graphics", "shadows")), str(Settings.get_value("graphics", "ssao")),
		str(Settings.get_value("graphics", "volumetric_fog")), float(Settings.get_value("graphics", "render_scale"))])
	await _wait(1.0)
	if world.is_dm():
		await _perf_run_dm()
		return
	ctl.pitch = -0.25
	_perf_begin("plane", 0.35)
	await _until(func(): return (Net.tick - int(world.match_server.plane.t0)) > int((float(world.match_server.plane.open_s) + 1.0) * Defs.TICK_RATE), 60.0)
	_perf_end()
	await _hold("jump", 0.2)
	await _until(func(): return ch.mode == Motor.FREEFALL, 5.0)
	ctl.pitch = -0.9
	_perf_begin("freefall", 0.6)
	await _until(func(): return not is_instance_valid(ch) or ch.mode != Motor.FREEFALL, 60.0)
	_perf_end()
	if not is_instance_valid(ch):
		return
	ctl.pitch = -0.3
	_act_press("move_forward")
	_perf_begin("canopy_high", 0.3)
	await _until(func(): return not is_instance_valid(ch) or ch.mode != Motor.CHUTE or _agl() < 45.0, 90.0)
	_perf_end()
	ctl.pitch = -0.2
	_perf_begin("canopy_low", 0.3)
	await _until(func(): return not is_instance_valid(ch) or ch.mode != Motor.CHUTE, 90.0)
	_perf_end()
	_act_release("move_forward")
	if not is_instance_valid(ch) or world.local_char == null:
		return
	await _wait(1.0)
	ctl.pitch = 0.0
	_perf_begin("landed_pan", TAU / 6.0)
	await _wait(6.0)
	_perf_end()
	# Spots in the unscaled layout's coordinates (Layout.MAP_SCALE).
	var k: float = world.map.layout.MAP_SCALE
	for spot in [["market", Vector2(100, -175)], ["looban", Vector2(-118, -262)], ["looban_east", Vector2(300, -24)], ["rail", Vector2(-160, -432)]]:
		var p := _perf_open_spot((spot[1] as Vector2) * k)
		_teleport(Vector3(p.x, float(world.map.layout.ground_height(p.x, p.y)) + 0.3, p.y), 0.0)
		await _wait(1.5)
		_perf_begin(spot[0], TAU / 6.0)
		await _wait(6.0)
		_perf_end()
	var r := _pick_room()
	if not r.is_empty():
		var xf: Transform3D = r.xf
		_teleport(xf.origin + Vector3.UP * 0.15, 0.0)
		ch.light.on = false
		await _tap("flashlight")
		await _wait(1.5)
		_perf_begin("indoor_light", TAU / 6.0)
		await _wait(6.0)
		_perf_end()
	# r3: inside a roofed lane (with the flashlight on), and the densest spot and the market under the artificial sun.
	var lanes: Array = world.map.tunnels.filter(func(x): return x.kind == "lane" and (x.b as Vector2).distance_to(x.a) > 10.0)
	if not lanes.is_empty():
		var tl: Dictionary = lanes[lanes.size() / 2]
		var tp: Vector2 = (tl.a as Vector2).lerp(tl.b, 0.5)
		var td: Vector2 = ((tl.b as Vector2) - (tl.a as Vector2)).normalized()
		_teleport(Vector3(tp.x, float(world.map.layout.ground_height(tp.x, tp.y)) + 0.3, tp.y), atan2(-td.x, -td.y))
		if not ch.light.on:
			await _tap("flashlight")
		await _wait(1.5)
		_perf_begin("tunnel", 0.6)
		await _wait(6.0)
		_perf_end()
	world.map.lighting.forced_time = 450.0
	for spot in [["looban_east_day", Vector2(300, -24)], ["market_day", Vector2(100, -175)]]:
		var p2 := _perf_open_spot((spot[1] as Vector2) * k)
		_teleport(Vector3(p2.x, float(world.map.layout.ground_height(p2.x, p2.y)) + 0.3, p2.y), 0.0)
		await _wait(1.5)
		_perf_begin(spot[0], TAU / 6.0)
		await _wait(6.0)
		_perf_end()
	world.map.lighting.forced_time = -1.0
	if Game.arg("attrib"):
		await _perf_attrib(_perf_open_spot(Vector2(300, -24) * k), Vector2(300, -24) * k)
		await _perf_attrib_air()
	var f := FileAccess.open(out_dir + "/perf.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_perf_report, "  "))
	var worst := 0.0
	for row in _perf_report:
		worst = maxf(worst, float(row.get("avg_ms", 0.0)))
	_check("perf_recorded", _perf_report.size() >= 5, "%d phases, worst average %.2f ms" % [_perf_report.size(), worst])


func _perf_run_dm() -> void:
	## Deathmatch (Lawless Sub): no plane. The spawn with the team around, then the busy places of the map, a room
	## with the flashlight on, and two spots under the artificial sun.
	ctl.pitch = 0.0
	_perf_begin("dm_spawn", TAU / 6.0)
	await _wait(6.0)
	_perf_end()
	var spots := [["dm_intersection", Vector2(-8, 8)], ["dm_houses", Vector2(30, -40)], ["dm_mart_lot", Vector2(-80, 140)],
		["dm_factory_yard", Vector2(140, 135)], ["dm_canal_row", Vector2(-28, -120)]]
	for spot in spots:
		var p := _perf_open_spot(spot[1] as Vector2)
		_teleport(Vector3(p.x, float(world.map.layout.surface_y(p)) + 0.3, p.y), 0.0)
		await _wait(1.5)
		_perf_begin(spot[0], TAU / 6.0)
		await _wait(6.0)
		_perf_end()
	var r := _pick_room()
	if not r.is_empty():
		_teleport((r.xf as Transform3D).origin + Vector3.UP * 0.15, 0.0)
		if not ch.light.on:
			await _tap("flashlight")
		await _wait(1.5)
		_perf_begin("dm_indoor_light", TAU / 6.0)
		await _wait(6.0)
		_perf_end()
	world.map.lighting.forced_time = 450.0
	for spot in [["dm_intersection_day", Vector2(-8, 8)], ["dm_houses_day", Vector2(30, -40)]]:
		var p2 := _perf_open_spot(spot[1] as Vector2)
		_teleport(Vector3(p2.x, float(world.map.layout.surface_y(p2)) + 0.3, p2.y), 0.0)
		await _wait(1.5)
		_perf_begin(spot[0], TAU / 6.0)
		await _wait(6.0)
		_perf_end()
	world.map.lighting.forced_time = -1.0
	var f := FileAccess.open(out_dir + "/perf.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_perf_report, "  "))
	var worst := 0.0
	for row in _perf_report:
		worst = maxf(worst, float(row.get("avg_ms", 0.0)))
	_check("perf_recorded", _perf_report.size() >= 5, "%d phases, worst average %.2f ms" % [_perf_report.size(), worst])


func _perf_hold(phase: String, frames: int = 90) -> void:
	_perf_begin(phase)
	for i in frames:
		await get_tree().process_frame
	_perf_end()


func _chunk_meshes(pred: Callable) -> Array:
	var out := []
	for c in world.map.root.get_children():
		if c.name.begins_with("Chunk_"):
			for m in c.get_children():
				if m is MeshInstance3D and pred.call(m):
					out.append(m)
	return out


func _perf_toggles() -> Array:
	## [name, off, on]: each switches one feature off and back on, for a cost-by-subtraction table.
	var L = world.map.lighting
	var env: Environment = L.env
	var vp := get_viewport()
	var lights := []
	var emitters := []
	for c in world.get_children():
		if c is Light3D:
			lights.append(c)
		elif c is MeshInstance3D:
			emitters.append(c)
	var ints := _chunk_meshes(func(m): return m.visibility_range_begin == 0.0 and m.visibility_range_end <= 60.5)
	var mids := _chunk_meshes(func(m): return m.visibility_range_end == 140.0)
	var exts := _chunk_meshes(func(m): return m.visibility_range_begin == 0.0 and m.visibility_range_end > 200.0)
	var fars := _chunk_meshes(func(m): return m.visibility_range_begin > 0.0)
	var mms = world.map.root.get_children().filter(func(c): return c.name.begins_with("MM_"))
	var terr := [world.map.root.get_node("TerrainMesh"), world.map.root.get_node("Water")]
	return [
		["moon_shadow", func(): L.moon.shadow_enabled = false, func(): L.moon.shadow_enabled = true],
		["local_shadows", func(): _local_shadows(L, false), func(): _local_shadows(L, true)],
		["vol_fog", func(): env.volumetric_fog_enabled = false, func(): env.volumetric_fog_enabled = true],
		["ssao", func(): env.ssao_enabled = false, func(): env.ssao_enabled = true],
		["glow", func(): env.glow_enabled = false, func(): env.glow_enabled = true],
		["taa", func(): vp.use_taa = false, func(): vp.use_taa = true],
		["lights", func(): _set_vis(lights, false), func(): _set_vis(lights, true)],
		["emitters", func(): _set_vis(emitters, false), func(): _set_vis(emitters, true)],
		["int_layer", func(): _set_vis(ints, false), func(): _set_vis(ints, true)],
		["mid_layer", func(): _set_vis(mids, false), func(): _set_vis(mids, true)],
		["ext_layer", func(): _set_vis(exts, false), func(): _set_vis(exts, true)],
		["far_layer", func(): _set_vis(fars, false), func(): _set_vis(fars, true)],
		["multimesh", func(): _set_vis(mms, false), func(): _set_vis(mms, true)],
		["terrain_water", func(): _set_vis(terr, false), func(): _set_vis(terr, true)],
		["characters", func(): world.chars_root.visible = false, func(): world.chars_root.visible = true],
		["scale_0.77", func(): vp.scaling_3d_scale = 0.77, func(): vp.scaling_3d_scale = 1.0],
		["loot", func(): world.map.dyn.set_loot_visible(false), func(): world.map.dyn.set_loot_visible(true)],
		["loot_glint", func(): world.map.dyn.set_item_glint(false), func(): world.map.dyn.set_item_glint(true)],
		["minimap", func(): world.hud.minimap.process_mode = Node.PROCESS_MODE_DISABLED; world.hud.minimap.hide(),
			func(): world.hud.minimap.process_mode = Node.PROCESS_MODE_INHERIT],
	]


func _set_vis(nodes: Array, v: bool) -> void:
	for n in nodes:
		n.visible = v


func _local_shadows(L, on: bool) -> void:
	L._budget_t = 0.0 if on else 1e9
	if not on:
		for s in L._shadowed:
			s.light.shadow_enabled = false


func _perf_attrib(p: Vector2, look: Vector2) -> void:
	_teleport(Vector3(p.x, float(world.map.layout.ground_height(p.x, p.y)) + 0.3, p.y), 0.0)
	await _wait(1.5)
	await _perf_attrib_set("ground")


func _perf_attrib_set(tag: String) -> void:
	await _perf_hold("%s:base" % tag)
	for t in _perf_toggles():
		t[1].call()
		await _wait(0.3)
		await _perf_hold("%s:-%s" % [tag, t[0]])
		t[2].call()
		await _wait(0.3)
	await _perf_hold("%s:base2" % tag)


func _perf_attrib_air() -> void:
	## Canopy and free-fall views from a free camera (the character stays on the ground).
	var cam := Camera3D.new()
	cam.far = 1600.0
	cam.fov = float(Settings.get_value("graphics", "fov"))
	world.add_child(cam)
	var k: float = world.map.layout.MAP_SCALE
	var c := Vector3(-60 * k, 0, -200 * k)
	cam.global_position = c + Vector3(0, 90, 60)
	cam.rotation = Vector3(-0.45, 0, 0)
	cam.current = true
	await _wait(1.0)
	await _perf_attrib_set("canopy90")
	cam.global_position = c + Vector3(0, 230, 120)
	cam.rotation = Vector3(-0.9, 0, 0)
	await _wait(1.0)
	await _perf_attrib_set("freefall230")
	cam.queue_free()


func _perf_open_spot(c: Vector2) -> Vector2:
	## Nearest point with open sky over walkable ground (an alley or a road), searching outward.
	var space = world.get_world_3d().direct_space_state
	var L = world.map.layout
	for ring in 40:
		for k in 16:
			var a := k * TAU / 16.0
			var p := c + Vector2(cos(a), sin(a)) * ring * 0.8
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60, p.y), Vector3(p.x, -10, p.y))
			var hit: Dictionary = space.intersect_ray(q)
			if hit.is_empty():
				continue
			if absf(hit.position.y - L.ground_height(p.x, p.y)) < 0.4 and not L.is_water(p.x, p.y):
				return p
	return c


func _teammates() -> Array:
	var out := []
	for o in world.characters.values():
		if o != ch and o.team == ch.team:
			out.append(o)
	return out


func _pick_room() -> Dictionary:
	var best := {}
	var bd := INF
	for r in world.map.rooms:
		if str(r.type) not in ["bed", "kitchen", "living", "store", "front", "sala"]:
			continue
		var sz: Vector2 = r.size
		if sz.x < 2.4 or sz.y < 2.4:
			continue
		var d := (r.xf as Transform3D).origin.distance_to(ch.global_position)
		if d < bd:
			bd = d
			best = r
	return best


func _teleport(pos: Vector3, yaw: float) -> void:
	ch.global_position = pos
	ch.velocity = Vector3.ZERO
	ctl.yaw = yaw
	ctl.pitch = 0.0


func _look_at(p: Vector3) -> void:
	var to: Vector3 = p - ch.eye_position()
	ctl.yaw = atan2(-to.x, -to.z)
	ctl.pitch = atan2(to.y, Vector2(to.x, to.z).length())


func _check(name: String, ok: bool, detail: String) -> void:
	results.append([name, ok, detail])
	print("[autotest] %s %s: %s" % ["PASS" if ok else "FAIL", name, detail])


func _view_luma() -> float:
	## Mean brightness (0-255) of the middle of the view.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var sz := img.get_size()
	var c := img.get_region(Rect2i(sz.x * 3 / 10, sz.y * 3 / 10, sz.x * 2 / 5, sz.y * 2 / 5))
	c.resize(64, 36)
	var sum := 0.0
	for y in 36:
		for x in 64:
			sum += c.get_pixel(x, y).get_luminance()
	return sum / (64.0 * 36.0) * 255.0


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_shot_n += 1
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [out_dir, _shot_n, name]
	img.save_png(path)
	print("[autotest] shot %s" % path)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	## pos in UI coordinates (the stretched 1920x1080 layout); injected events are in window pixels.
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = get_tree().root.get_final_transform() * pos
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, from: Vector2, to: Vector2, steps: int) -> void:
	for i in steps:
		var ev := InputEventScreenDrag.new()
		var xf := get_tree().root.get_final_transform()
		ev.index = index
		ev.position = xf * from.lerp(to, float(i + 1) / steps)
		ev.relative = xf.basis_xform((to - from) / steps)
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _touch_controls() -> void:
	## The on-screen controls driven by screen touches, as on a phone: the stick moves, a drag on the right turns
	## the view, and the Light button switches the flashlight.
	var sz := get_viewport().get_visible_rect().size
	var p0 = ch.global_position
	var stick := Vector2(sz.x * 0.16, sz.y * 0.72)
	_touch(0, stick, true)
	await _drag(0, stick, stick + Vector2(0, -110), 6)
	await _wait(1.5)
	await _shot("touch_controls")
	_touch(0, stick + Vector2(0, -110), false)
	var moved := Vector2(ch.global_position.x - p0.x, ch.global_position.z - p0.z).length()
	_check("touch_stick_moves", moved > 2.0, "moved %.1f m in 1.5 s" % moved)
	var y0: float = ctl.yaw
	var look := Vector2(sz.x * 0.62, sz.y * 0.45)
	_touch(1, look, true)
	await _drag(1, look, look + Vector2(200, 0), 8)
	_touch(1, look + Vector2(200, 0), false)
	await get_tree().process_frame
	var turned := absf(wrapf(ctl.yaw - y0, -PI, PI))
	_check("touch_look_turns", turned > 0.2, "turned %.2f rad for a 200-unit drag" % turned)
	var was_on: bool = ch.light.on
	var light_pos := Vector2.ZERO
	for btn in ctl.touch.BUTTONS:
		if btn.name == "flashlight":
			light_pos = ctl.touch._centre(btn)
	_touch(2, light_pos, true)
	for i in 3:
		await get_tree().physics_frame
	_touch(2, light_pos, false)
	await _wait(0.5)
	_check("touch_light_button", ch.light.on != was_on, "flashlight %s -> %s" % [was_on, ch.light.on])


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if t > timeout:
			return false
	return true


func _act_press(action: String) -> void:
	_act(action, true)


func _act_release(action: String) -> void:
	_act(action, false)


func _act(action: String, pressed: bool) -> void:
	## A real input event, so both polled actions and _unhandled_input handlers (weapon slots, toggles) see it.
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _tap(action: String) -> void:
	_act(action, true)
	for i in 3:
		await get_tree().physics_frame
	_act(action, false)
	for i in 2:
		await get_tree().physics_frame


func _hold(action: String, s: float, shot_name: String = "") -> void:
	## Holds an action for s seconds, optionally taking a screenshot 70% of the way through.
	_act(action, true)
	if shot_name != "":
		await _wait(s * 0.7)
		await _shot(shot_name)
		await _wait(s * 0.3)
	else:
		await _wait(s)
	_act(action, false)


func _finish() -> void:
	var failed := results.filter(func(r): return not r[1]).size()
	print("[autotest] done: %d checks, %d failed" % [results.size(), failed])
	var f := FileAccess.open(out_dir + "/results.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
	get_tree().quit(1 if failed > 0 else 0)
