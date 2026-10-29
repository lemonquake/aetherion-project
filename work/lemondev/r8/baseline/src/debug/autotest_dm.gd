extends RefCounted
## r7 Deathmatch checks on a listen host (`--autotest=dm`):
##   godot --path game -- --host --game_mode=deathmatch --bots=19 --autostart=1 --autotest=dm --shots=<dir> [--dm_only=a,b]
## map: the round is on Lawless Sub, two teams of ten standing. kit: you spawn on the ground at your team's spawn with
## both guns, the plate carrier and the heavy helmet. body: looking straight down in first person nothing of your own
## body shows (the frame is compared with one where your character's visual is hidden). arms: the first-person arms
## come no closer to the camera than 15 cm above the bottom of the view through a whole empty reload (the arm's cut
## end showed). haze: the zone is running on the Deathmatch schedule.

const WeaponState := preload("res://src/weapons/weapon_state.gd")

var t = null
var world = null


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("dm_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 30.0)
	await t._wait(2.0)
	if not is_instance_valid(t.ch):
		t._check("dm_spawned", false, "no local character")
		return
	if want.call("map"):
		_map()
	if want.call("kit"):
		_kit()
	if want.call("body"):
		await _body()
	if want.call("arms"):
		await _arms()
	if want.call("haze"):
		_haze()


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return t.get_viewport().get_texture().get_image()


func _map() -> void:
	var info: Dictionary = world.match_info
	var alive: Dictionary = info.get("alive", {})
	var a0 := int(alive.get(0, alive.get("0", 0)))
	var a1 := int(alive.get(1, alive.get("1", 0)))
	t._check("dm_map", str(world.cfg.get("map", "")) == "lawless_sub" and str(info.get("game_mode", "")) == "deathmatch",
		"map %s, mode %s, %s" % [str(world.cfg.get("map", "")), str(info.get("game_mode", "")), world.map.fingerprint])
	t._check("dm_teams", a0 == 10 and a1 == 10, "alive West %d, East %d" % [a0, a1])


func _kit() -> void:
	var ch = t.ch
	var guns := []
	for s in [1, 2, 3]:  # two long-gun slots and the handgun slot
		var w = ch.wpn.slots[s]
		if w != null:
			guns.append(str(w.id))
	var vest = ch.inv.gear.get("vest")
	var helmet = ch.inv.gear.get("helmet")
	var team := int(Net.players.get(Net.local_pid, {}).get("team", -1))
	var L = world.map.layout
	var near := INF
	for p in L.spawns[clampi(team, 0, 1)]:
		near = minf(near, (p as Vector3).distance_to(ch.global_position))
	t._check("dm_kit", guns.size() == 2 and vest != null and helmet != null and str(vest.id) == "vest_heavy" and str(helmet.id) == "helmet_heavy",
		"guns %s, vest %s, helmet %s" % [str(guns), str(vest.id) if vest else "none", str(helmet.id) if helmet else "none"])
	t._check("dm_spawn_place", near < 25.0, "%.1f m from the nearest spawn point of team %d" % [near, team])


func _body() -> void:
	## Straight down in first person, arms hidden in both frames so only the body can differ.
	var vm = t.ctl.get("vm") if t.ctl else null
	t.ctl.pitch = -1.45
	if vm:
		vm.test_hide_arms = true
	await t._wait(0.6)
	await t._shot("dm_look_down")
	# Only what the camera draws counts: your body's shadow on the ground is meant to be there (it goes when the body
	# is hidden), and the HUD's minimap moves with the bots. Both are switched off for the two frames.
	var suns: Array = t.get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	var had: Array = suns.map(func(l): return (l as DirectionalLight3D).shadow_enabled)
	for l in suns:
		(l as DirectionalLight3D).shadow_enabled = false
	var hud = world.get("hud")
	var hud_was: bool = hud.visible if hud is CanvasLayer else false
	if hud is CanvasLayer:
		hud.visible = false
	await t._wait(0.3)
	var a := await _grab()
	var vis: Node3D = t.ch.visual
	vis.visible = false
	await t._wait(0.15)
	var b := await _grab()
	vis.visible = true
	for i in suns.size():
		(suns[i] as DirectionalLight3D).shadow_enabled = had[i]
	if hud is CanvasLayer:
		hud.visible = hud_was
	if vm:
		vm.test_hide_arms = false
	t.ctl.pitch = 0.0
	var bad := 0
	var box := Rect2i()
	var w := a.get_width()
	var h := a.get_height()
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance()) > 0.08:
				bad += 1
				box = Rect2i(x, y, 1, 1) if box.size == Vector2i.ZERO else box.expand(Vector2i(x, y))
	t._check("dm_no_own_body", bad < 40, "%d sampled pixels change when your own body is hidden (looking straight down; shadows and HUD off)%s"
		% [bad, (" in %s" % str(box)) if bad > 0 else ""])


func _arms() -> void:
	## Through an empty reload of the primary: the elbow and wrist of each arm stay out of the camera's face.
	var vm = t.ctl.get("vm") if t.ctl else null
	if vm == null or vm.arms == null or not vm.arms.ok:
		t._check("dm_arms_clear", false, "no first-person arms")
		return
	var ch = t.ch
	var w = ch.wpn.slots[1]
	if w == null:
		t._check("dm_arms_clear", false, "no primary")
		return
	t.ctl.slot = 1
	await t._wait(1.0)
	w.mag = 0
	w.chamber = false
	await t._tap("reload")
	var cam: Camera3D = t.get_viewport().get_camera_3d()
	var inv := cam.global_transform.affine_inverse()
	var sk: Skeleton3D = vm.arms.skel
	var worst := -INF
	var at := ""
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		await t.get_tree().process_frame
		frames += 1
		inv = cam.global_transform.affine_inverse()
		for s in ["L", "R"]:
			var d: Dictionary = vm.arms.sides[s]
			if bool(d.get("hidden", false)):
				continue
			for b in [d.fore, d.hand]:
				var p: Vector3 = inv * (sk.global_transform * sk.get_bone_global_pose(int(b))).origin
				# In front of the eye by less than 15 cm and high enough to be on screen.
				if p.y > -0.35 and p.z > worst - 0.0001 and p.z > -0.6:
					if p.z > worst:
						worst = p.z
						at = "%s %s at %s" % [s, "elbow" if b == d.fore else "wrist", str(p.snapped(Vector3.ONE * 0.01))]
		if ch.wpn.state != WeaponState.RELOAD and frames > 30:
			break
	t._check("dm_arms_clear", worst < -0.15, "%d frames of an empty reload; closest joint on screen %s (needs z < -0.15 m)" % [frames, at])


func _haze() -> void:
	var z: Dictionary = world.match_info.get("zone", {})
	var phases: Array = Defs.rule("deathmatch.zone.phases", [])
	t._check("dm_haze", not phases.is_empty() and z.has("r1"), "%d Deathmatch phases; zone %s" % [phases.size(), str(z).left(120)])
