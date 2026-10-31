extends RefCounted
## (r22) Frame time in a big firefight, on a listen host (`--autotest=firefight`):
##   godot --path game -- --host --game_mode=deathmatch --map=freight_delight --bots=11 --autostart=1 --autotest=firefight --shots=<dir>
## The player stands in a busy spot (Freight Delight: the plaza by the videoke; --ff_at=x,y,z --ff_look=x,y,z elsewhere) and
## the bots are placed on waypoints in front of the camera, 6 to 30 m away, frozen and invulnerable. Then they hold the
## trigger of their real guns (the server fires the rounds; flashes, tracers, impacts, casings and sounds follow as in
## play), away from the camera, phase after phase with the camera still:
##   quiet                nobody firing (the scene's own cost)
##   fire_warm, fire      everyone firing (the first one compiles whatever is new)
##   fire_flash_noshadow  muzzle-flash lights without shadows
##   fire_no_flash        no muzzle-flash light at all
##   fire_no_lamp_shadow  the map's lamps without shadows
##   fire_again           as fire (the settings restored)
## Each phase prints a [perf] line (frame time, render cpu/gpu, draws); the rows go to <shots>/firefight.json.
## --ff_phase_s=<s> (default 8), --ff_shooters=<n> (default all bots, up to 10). Vsync is off and the GPU time measured
## (as --autotest=perf); --ff_vsync keeps vsync.

const PHASES := ["quiet", "fire_warm", "fire", "fire_flash_noshadow", "fire_no_flash", "fire_no_lamp_shadow", "fire_again"]

var t = null
var world = null


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func _v3(s: String, d: Vector3) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else d


func run() -> void:
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 60.0)
	await t._wait(2.0)
	var secs := clampf(float(Game.arg("ff_phase_s", "8")), 3.0, 30.0)
	Prof.on = true   # section timers, when tools/prof_instrument.py has put them in
	if Game.arg("ff_vsync") == null:
		# the real cost of a frame, GPU included (as --autotest=perf: vsync off, render time measured)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.viewport_set_measure_render_time(t.get_viewport().get_viewport_rid(), true)
	print("[firefight] %s, window %s, shadows %d, render scale %.2f" % [RenderingServer.get_video_adapter_name(), str(t.get_window().size),
		int(Settings.get_value("graphics", "shadows")), float(Settings.get_value("graphics", "render_scale"))])
	var at := _v3(str(Game.arg("ff_at", "")), Vector3(16.0, 0.0, -3.0))
	var look := _v3(str(Game.arg("ff_look", "")), Vector3(-6.0, 1.2, -6.0))
	t.ch.health.test_invulnerable = true
	t._teleport(at + Vector3.UP * 0.15, 0.0)
	await t._wait(0.5)
	t._look_at(look)
	var fwd := look - at
	fwd.y = 0.0
	fwd = fwd.normalized()
	# The shooters: waypoints on the ground floor in front of the camera, spread out.
	var BT := preload("res://src/ai/bot_team.gd")
	var cand := []
	for i in BT.spots_near(at, 32.0):
		var p: Vector3 = BT.spots[i].p
		var to := p - at
		to.y = 0.0
		if absf(p.y - at.y) > 1.0 or to.length() < 6.0 or to.length() > 30.0 or to.normalized().dot(fwd) < 0.55:
			continue
		cand.append(p)
	var picked := []
	for p in cand:
		var ok := true
		for q in picked:
			if (q as Vector3).distance_to(p) < 3.0:
				ok = false
				break
		if ok:
			picked.append(p)
	var want := mini(int(Game.arg("ff_shooters", "10")), world.bots.size())
	var shooters := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var k := 0
	for eid in world.bots:
		var b = world.bots[eid]
		b.test_idle = true
		b._dm_hold = 9999.0
		var c = b.ch
		c.health.test_invulnerable = true
		if k < mini(want, picked.size()) and c.mode == Motor.GROUND:
			c.global_position = picked[k] + Vector3.UP * 0.1
			c.velocity = Vector3.ZERO
			var aim := fwd.rotated(Vector3.UP, rng.randf_range(-0.45, 0.45))
			b.test_yaw = atan2(-aim.x, -aim.z)
			b.test_pitch = rng.randf_range(-0.12, 0.02)
			shooters.append(b)
			k += 1
	print("[firefight] %d shooters on %d candidate spots, camera at %s looking at %s" % [shooters.size(), picked.size(), str(at), str(look)])
	t._check("firefight_shooters", shooters.size() >= mini(6, want), "%d shooters placed in front of the camera" % shooters.size())
	await t._wait(1.5)
	var rows := []
	var L = world.map.lighting
	for ph in PHASES:
		for b in shooters:
			b.test_fire = ph != "quiet"
			_restock(b.ch)
		world.effects.flash_shadows = ph != "fire_flash_noshadow" and _flash_shadows_default()
		world.effects.test_no_flash = ph == "fire_no_flash"
		t._local_shadows(L, ph != "fire_no_lamp_shadow")
		await t._wait(1.0)
		var shots0 := _shots(shooters)
		t._perf_begin("ff_" + ph)
		if ph == "fire":
			await t._wait(secs * 0.5)
			t._shot("firefight_" + ph)
			await t._wait(secs * 0.5)
		else:
			await t._wait(secs)
		t._perf_end()
		var row: Dictionary = t._perf_report[-1]
		row["rounds"] = _shots(shooters) - shots0
		print("[firefight] %s: %d rounds fired, avg %.2f ms, p95 %.2f, max %.2f, gpu %.2f ms" % [ph, int(row.rounds), float(row.get("avg_ms", 0.0)),
			float(row.get("p95", 0.0)), float(row.get("max", 0.0)), float(row.get("gpu", 0.0))])
		rows.append(row)
	for b in shooters:
		b.test_fire = false
	world.effects.test_no_flash = false
	t._local_shadows(L, true)
	world.effects.flash_shadows = _flash_shadows_default()
	var out := FileAccess.open(t.out_dir + "/firefight.json", FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(rows, "  "))
	var by := {}
	for r in rows:
		by[str(r.phase).trim_prefix("ff_")] = r
	var fired: int = int(by.get("fire", {}).get("rounds", 0))
	t._check("firefight_fired", fired > shooters.size() * 10, "%d rounds in the fire phase" % fired)
	print("[firefight] quiet %.2f ms -> fire %.2f ms (gpu %.2f -> %.2f)" % [float(by.quiet.get("avg_ms", 0.0)), float(by.fire.get("avg_ms", 0.0)),
		float(by.quiet.get("gpu", 0.0)), float(by.fire.get("gpu", 0.0))])


func _flash_shadows_default() -> bool:
	return not Settings.is_mobile() and RenderingServer.get_current_rendering_method() == "forward_plus"


func _restock(c) -> void:
	for s in [1, 2, 3]:
		var w = c.wpn.slots[s]
		if w != null:
			c.inv.add({"id": Defs.ammo_item(str(w.id)), "n": 200}, true)


func _shots(shooters: Array) -> int:
	var n := 0
	for b in shooters:
		n += int(b.ch.wpn.shots)
	return n
