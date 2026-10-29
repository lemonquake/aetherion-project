extends RefCounted
## r10 checks on a listen host, measured from captures where they are visual (`--autotest=r10`):
##   godot --path game -- --host --game_mode=deathmatch --bots=19 --autostart=1 --autotest=r10 --shots=<dir> --loadshot=<dir>/loading.png
## loading: the loading screen was drawn during the build (its capture has the bar and text). bridge: the Canal Bridge
## deck is asphalt, not the dirt below (olive pixels). laser: holding the laser puts a beam and a dot on screen (red
## pixels against the same view without it), and the server sees it on (F_LASER). laser_alert: an enemy bot that sees
## the dot may follow the beam back. names: a teammate in view gets a name tag (pixels against names off). minimap:
## teammates show on the minimap. ping: a ping marks the spot looked at, for the HUD and the team's bots. kick: a hit
## punches the view a few degrees and it settles. kerb: running at a kerb at a shallow angle gets on top of it.
## roles: the bots have a mix of roles and squads.

var t = null
var world = null


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("r10_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 30.0)
	await t._wait(1.5)
	if not is_instance_valid(t.ch):
		t._check("r10_spawn", false, "no local character")
		return
	world.map.lighting.forced_time = 450.0
	for b in world.bots.values():
		b._dm_hold = 999.0   # keep the bots at their spawns while the views are measured
	if want.call("loading"):
		_loading()
	if want.call("bridge"):
		await _bridge()
	if want.call("laser"):
		await _laser()
	if want.call("names"):
		await _names()
	if want.call("ping"):
		await _ping()
	if want.call("kick"):
		await _kick()
	if want.call("kerb"):
		await _kerb()
	if want.call("roles"):
		_roles()


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return t.get_viewport().get_texture().get_image()


static func _count(img: Image, rect: Rect2i, pred: Callable) -> int:
	var n := 0
	for y in range(rect.position.y, rect.end.y, 2):
		for x in range(rect.position.x, rect.end.x, 2):
			if pred.call(img.get_pixel(x, y)):
				n += 1
	return n


func _loading() -> void:
	var path := str(Game.arg("loadshot", ""))
	var img := Image.load_from_file(path) if path != "" and FileAccess.file_exists(path) else null
	if img == null:
		t._check("r10_loading_screen", false, "no capture at %s" % path)
		return
	var sz := img.get_size()
	# The bar: accent-coloured pixels along the bottom fifth; text: bright pixels in the lower left.
	var accent := _count(img, Rect2i(0, sz.y * 4 / 5, sz.x, sz.y / 5), func(c: Color): return c.r > 0.75 and c.g > 0.45 and c.g < 0.8 and c.b < 0.4)
	var bright := _count(img, Rect2i(0, sz.y / 2, sz.x / 2, sz.y / 2), func(c: Color): return c.get_luminance() > 0.75)
	t._check("r10_loading_screen", accent > 200 and bright > 200, "bar pixels %d, text pixels %d in %s" % [accent, bright, path])


func _bridge() -> void:
	t._teleport(Vector3(-90.0, 1.2, -2.0), atan2(-1.0, 0.0) + PI)
	t._look_at(Vector3(-70.0, 0.96, 0.0))
	await t._wait(1.2)
	var img := await _grab()
	await t._shot("bridge_deck")
	var sz := img.get_size()
	var r := Rect2i(sz.x / 4, sz.y * 3 / 5, sz.x / 2, sz.y * 2 / 5 - 2)
	# The dirt that showed through was khaki (r-b ~0.18, g-b ~0.13 at mid brightness); sunlit asphalt is near grey and
	# the yellow centre lines are far brighter.
	var olive := _count(img, r, func(c: Color): return c.r - c.b > 0.12 and c.g - c.b > 0.08 and c.get_luminance() > 0.2 and c.get_luminance() < 0.55)
	var total := (r.size.x / 2) * (r.size.y / 2)
	t._check("r10_bridge_no_dirt", float(olive) / total < 0.08, "%d of %d deck pixels olive (dirt through the asphalt)" % [olive, total])


func _laser() -> void:
	var ch = t.ch
	t._teleport(Vector3(-160.0, 1.2, -150.0), 0.0)
	await t._wait(0.6)
	t.ctl.pitch = -0.06
	await t._wait(0.5)
	var off := await _grab()
	t.ctl.laser_toggled = true
	await t._wait(0.6)
	var on := await _grab()
	await t._shot("laser_on")
	var col := Settings.laser_color(str(Settings.get_value("player", "laser_color")))
	# Along the beam's path on screen (its dot to the pointer in the hand): pixels that turned redder with it on.
	var vs: Vector2 = t.get_viewport().get_visible_rect().size
	var k: float = on.get_size().x / vs.x
	var cam: Camera3D = t.ctl.cam
	var bm: Array = world.lasers.beam(ch)
	var a2: Vector2 = cam.unproject_position(bm[1]) * k
	var b2: Vector2 = cam.unproject_position(bm[0]) * k
	var lit := 0
	for i in 60:
		var p: Vector2 = a2.lerp(b2, i / 60.0)
		for dy in range(-3, 4):
			var x := int(p.x)
			var y := int(p.y) + dy
			if x < 0 or y < 0 or x >= on.get_width() or y >= on.get_height():
				continue
			var c1: Color = on.get_pixel(x, y)
			var c0: Color = off.get_pixel(x, y)
			if c1.r - c0.r > 0.12 and c1.r > c1.g * 1.3:
				lit += 1
				break
	var flagged: bool = ch.laser_on and (int(ch.compute_flags()) & Character.F_LASER) != 0
	t._check("r10_laser_visible", lit > 15 and flagged, "%d of 60 samples along the beam turned red with the laser on; server laser_on %s (colour %s)" % [lit, str(flagged), str(col)])
	# An enemy bot near the dot notices it; within a few looks one follows the beam back.
	var dot: Vector3 = world.lasers.beam(ch)[1]
	var foe = null
	for b in world.bots.values():
		if b.ch.team != ch.team:
			foe = b
			break
	var followed := false
	if foe:
		foe.ch.global_position = dot + (ch.global_position - dot).normalized() * 6.0 + Vector3.UP * 0.2
		foe.ch.velocity = Vector3.ZERO
		await t._wait(0.3)
		for i in 40:
			foe._laser_cd = 0.0
			foe.investigate = Vector3.INF
			world._laser_scan(ch)
			if foe.investigate != Vector3.INF and foe.investigate.distance_to(ch.global_position) < 8.0:
				followed = true
				break
	t._check("r10_laser_alerts_enemy", followed, "enemy bot %s (%s) near the dot followed the beam back: %s" % [foe.ch.pname if foe else "-", foe.role if foe else "-", str(followed)])
	t.ctl.laser_toggled = false
	if foe:
		foe.ch.global_position = Vector3(130.0, 1.2, 150.0)
	await t._wait(0.3)


func _mate():
	for b in world.bots.values():
		if b.ch.team == t.ch.team and b.ch.mode == Motor.GROUND:
			return b
	return null


func _names() -> void:
	var mb = _mate()
	if mb == null:
		t._check("r10_ally_names", false, "no teammate bot")
		return
	t._teleport(Vector3(-160.0, 1.2, -150.0), 0.0)
	var front: Vector3 = t.ch.global_position + Vector3(0, 0, -9.0)
	mb.ch.global_position = front
	mb.ch.velocity = Vector3.ZERO
	mb.squad_id = -1
	t._look_at(front + Vector3.UP * 1.4)
	await t._wait(0.8)
	Settings.set_value("gameplay", "ally_names", false)
	await t._wait(0.2)
	var off := await _grab()
	Settings.set_value("gameplay", "ally_names", true)
	await t._wait(0.2)
	var on := await _grab()
	await t._shot("ally_name")
	var cam: Camera3D = t.ctl.cam
	var head := cam.unproject_position(mb.ch.global_position + Vector3.UP * 2.3)
	var vp_scale: float = on.get_size().x / t.get_viewport().get_visible_rect().size.x
	var r := Rect2i(Vector2i((head * vp_scale) - Vector2(160, 50) * vp_scale), Vector2i(Vector2(320, 80) * vp_scale))
	r = r.intersection(Rect2i(Vector2i.ZERO, on.get_size()))
	var diff := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			if (on.get_pixel(x, y) - off.get_pixel(x, y)).get_luminance() > 0.12 or absf(on.get_pixel(x, y).r - off.get_pixel(x, y).r) > 0.15:
				diff += 1
	t._check("r10_ally_names", diff > 40, "%d pixels change above %s's head when names are on" % [diff, mb.ch.pname])
	# The minimap: team-coloured pixels inside its square with a teammate 9 m away.
	var mm: Control = world.hud.minimap
	var tc: Color = UITheme.TEAM_COLORS[t.ch.team % UITheme.TEAM_COLORS.size()]
	var mr := Rect2i(Vector2i(mm.global_position * vp_scale), Vector2i(mm.size * vp_scale)).intersection(Rect2i(Vector2i.ZERO, on.get_size()))
	var team_px := _count(on, mr, func(c: Color): return absf(c.r - tc.r) < 0.12 and absf(c.g - tc.g) < 0.12 and absf(c.b - tc.b) < 0.12)
	t._check("r10_minimap_allies", team_px > 4, "%d team-coloured pixels on the minimap" % team_px)


func _ping() -> void:
	var ch = t.ch
	t._teleport(Vector3(-160.0, 1.2, -150.0), PI * 0.5)
	t.ctl.pitch = -0.15
	await t._wait(0.6)
	var want: Vector3 = world.ping_point(ch)
	var before := int(preload("res://src/ai/bot_team.gd").stats.pings)
	await t._tap("ping")
	var ok: bool = await t._until(func(): return not world.hud.marks.pings.is_empty(), 1.5)
	await t._wait(0.3)
	await t._shot("ping_marker")
	var got: Vector3 = world.hud.marks.pings[0].pos if ok else Vector3.INF
	var answered := int(preload("res://src/ai/bot_team.gd").stats.pings) - before
	t._check("r10_ping_point", ok and got.distance_to(want) < 1.5 and not world.hud.minimap.pings.is_empty(),
		"marker at %s (looked-at spot %s), minimap ping %s" % [str(got.snapped(Vector3.ONE * 0.1)), str(want.snapped(Vector3.ONE * 0.1)), str(not world.hud.minimap.pings.is_empty())])
	t._check("r10_ping_reaches_bots", answered > 0, "%d teammate bots received the ping" % answered)


func _kick() -> void:
	t._teleport(Vector3(-160.0, 1.2, -150.0), 0.0)
	await t._wait(0.5)
	var cam: Camera3D = t.ctl.cam
	var base := cam.global_transform.basis
	t.ctl.on_hit("torso", Vector3(0, 0, 1), 30.0, "")
	var peak := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 600:
		await t.get_tree().process_frame
		var d := rad_to_deg(base.get_rotation_quaternion().angle_to(cam.global_transform.basis.get_rotation_quaternion()))
		peak = maxf(peak, d)
	var settled := rad_to_deg(base.get_rotation_quaternion().angle_to(cam.global_transform.basis.get_rotation_quaternion()))
	t._check("r10_hit_kick", peak > 1.0 and peak < 7.0 and settled < 0.4, "view punched %.1f deg on a 30-damage hit, %.2f deg left after 0.6 s" % [peak, settled])


func _kerb() -> void:
	## Sub Boulevard: carriageway to z = 7, sidewalk (18 cm up) beyond. Run at it 65 degrees off square.
	var ch = t.ch
	var d := Vector3(sin(deg_to_rad(65.0)), 0, cos(deg_to_rad(65.0)))
	t._teleport(Vector3(120.0, 1.1, 5.6), atan2(-d.x, -d.z))
	await t._wait(0.5)
	var y0: float = ch.global_position.y
	t._act_press("move_forward")
	t._act_press("sprint")
	await t._wait(1.6)
	t._act_release("move_forward")
	t._act_release("sprint")
	var p: Vector3 = ch.global_position
	t._check("r10_kerb_shallow", p.z > 7.3 and p.y > y0 + 0.08, "from z 5.6 to %.2f, height %.2f -> %.2f (sidewalk is 0.12 m above the road)" % [p.z, y0, p.y])


func _roles() -> void:
	var roles := {}
	for b in world.bots.values():
		roles[b.role] = int(roles.get(b.role, 0)) + 1
	var BT := preload("res://src/ai/bot_team.gd")
	t._check("r10_bot_roles", roles.size() >= 3, "roles %s; squads formed %d; waypoints %d" % [str(roles), int(BT.stats.squads), BT.spots.size()])
