extends RefCounted
## r25 checks on a Deathmatch listen host (`--autotest=r25`, `--r25_only=sprint,fire,smoke`), Malasugue Mall:
##   godot --path game -- --host --game_mode=deathmatch --map=malasugue_mall --bots=4 --autostart=1 --autotest=r25 --shots=<dir>
## sprint: sprinting along the Grand Atrium with a gun out: the gun stays drawn and on screen (the muzzle projects
## inside the view), carried low and canted; captured.
## fire: the trigger pulled at a sprint: the sprint ends at once and the body slows to a run (4.4 m/s) while firing,
## rounds go out; after letting go the sprint comes back. Per-tick speeds go to <shots>/r25_measure.json.
## smoke: automatic fire standing still: the shooter's own muzzle smoke puffs (at most one per 0.6 s, out past the
## muzzle flash), captured mid-burst. The runs go along the clearest lane from the start spot.

const R14 := preload("res://src/debug/autotest_r14.gd")

var t = null
var world = null
var h = null
var measure := {}
const AT := Vector3(18.0, 0.0, -10.0)
var DIR := Vector3(-1.0, 0.0, 0.0)   # set to the clearest lane from AT (run)


func _init(autotest) -> void:
	t = autotest
	world = autotest.world
	h = R14.new(autotest)


func run() -> void:
	var only := str(Game.arg("r25_only", "")).split(",", false)
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 40.0)
	await t._wait(1.5)
	h._freeze_zone()
	h._holding = true
	h._keep_holding()
	h._freeze_bots(true)
	t.ch.health.test_invulnerable = true
	DIR = _clear_dir()
	print("[r25] lane from %s toward %s" % [str(AT), str(DIR.snapped(Vector3.ONE * 0.01))])
	await h._gun("smg_9", [])
	for n in ["sprint", "fire", "smoke"]:
		if only.is_empty() or n in only:
			await (Callable(self, "_" + n)).call()
	h._holding = false
	h._freeze_bots(false)
	var f := FileAccess.open(t.out_dir + "/r25_measure.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


func _clear_dir() -> Vector3:
	## Of 24 headings from AT, the one a standing body can run furthest along (up to 25 m) without touching anything.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	q.shape = cap
	q.collision_mask = Defs.MOVE_MASK
	q.exclude = [t.ch.get_rid()]
	var best := Vector3(-1, 0, 0)
	var best_f := -1.0
	for k in 24:
		var a := k * TAU / 24.0
		var d := Vector3(cos(a), 0.0, sin(a))
		q.transform = Transform3D(Basis(), AT + Vector3.UP * 1.05)
		q.motion = d * 25.0
		var r := space.cast_motion(q)
		if r[0] > best_f:
			best_f = r[0]
			best = d
	return best


func _start() -> void:
	for a in ["move_forward", "sprint", "fire", "aim"]:
		t._act_release(a)
	t._teleport(AT + Vector3.UP * 0.1, atan2(-DIR.x, -DIR.z))
	t.ch.health.reset()
	t.ch.stamina = 1.0
	await t._wait(0.6)


func _hspeed(prev: Vector3) -> float:
	var p: Vector3 = t.ch.global_position
	return Vector2(p.x - prev.x, p.z - prev.z).length() * Engine.physics_ticks_per_second


func _sprint() -> void:
	await _start()
	t._act_press("move_forward")
	t._act_press("sprint")
	await t._wait(1.2)
	var vm = t.ctl.vm
	var cam: Camera3D = t.get_viewport().get_camera_3d()
	var mz: Vector3 = vm.muzzle_position()
	var on_screen := false
	var sp := Vector2.ZERO
	if cam and not cam.is_position_behind(mz):
		sp = cam.unproject_position(mz)
		var vr: Rect2 = t.get_viewport().get_visible_rect()
		on_screen = vr.has_point(sp)
	var r := {"sprinting": t.ch.sprinting, "weapon_visible": vm.weapon_root.visible, "carry": snappedf(vm._sprint, 0.01),
		"muzzle_on_screen": on_screen, "muzzle_px": str(sp.round()), "weapon": t.ch.wpn.current_id()}
	t._shot("r25_sprint_gun")
	await t._wait(0.2)
	for a in ["move_forward", "sprint"]:
		t._act_release(a)
	measure["sprint"] = r
	t._check("r25_sprint_gun", bool(r.sprinting) and bool(r.weapon_visible) and on_screen and float(r.carry) > 0.9,
		"sprinting with %s: gun drawn and on screen %s" % [r.weapon, str(r)])


func _fire() -> void:
	await _start()
	t._act_press("move_forward")
	t._act_press("sprint")
	await t._wait(1.4)
	var run := Defs.move("run_speed")
	var sprint := Defs.move("sprint_speed")
	var before := []
	var prev: Vector3 = t.ch.global_position
	for i in 12:
		await t.get_tree().physics_frame
		before.append(_hspeed(prev))
		prev = t.ch.global_position
	var shots0: int = t.ch.wpn.shots
	t._act_press("fire")
	var during := []
	var sprint_ticks := []
	var took := -1
	for i in 60:
		await t.get_tree().physics_frame
		during.append(_hspeed(prev))
		prev = t.ch.global_position
		sprint_ticks.append(t.ch.sprinting)
		if took < 0 and not t.ch.sprinting:
			took = i
		if i == 30:
			t._shot("r25_sprint_fire")
	var shots: int = t.ch.wpn.shots - shots0
	t._act_release("fire")
	var after := []
	for i in 60:
		await t.get_tree().physics_frame
		after.append(_hspeed(prev))
		prev = t.ch.global_position
	var back: bool = t.ch.sprinting
	for a in ["move_forward", "sprint"]:
		t._act_release(a)
	var avg := func(a: Array) -> float:
		var s := 0.0
		for x in a:
			s += float(x)
		return s / maxf(a.size(), 1.0)
	var at_sprint: float = avg.call(before)
	var settled: float = avg.call(during.slice(30))     # the last half second of firing
	var later: float = avg.call(after.slice(45))        # the last quarter second after letting go
	var r := {"sprint_speed_before": snappedf(at_sprint, 0.01), "ticks_to_end_sprint": took, "speed_firing": snappedf(settled, 0.01),
		"rounds": shots, "sprint_again": back, "speed_after": snappedf(later, 0.01),
		"during": during.map(func(x): return snappedf(float(x), 0.01))}
	measure["fire"] = r
	t._check("r25_fire_ends_sprint", at_sprint > sprint * 0.9 and took >= 0 and took <= 2 and settled <= run * 1.03 and shots >= 5,
		"sprint %.2f m/s, trigger pulled: sprint ended after %d ticks, %.2f m/s while firing (run %.1f), %d rounds" % [at_sprint, took, settled, run, shots])
	t._check("r25_sprint_resumes", back and later > run * 1.15, "after letting go: sprinting %s, %.2f m/s" % [str(back), later])


func _smoke() -> void:
	await _start()
	t._look_at(AT + DIR * 12.0 + Vector3.UP * 1.4)
	await t._wait(0.3)
	var fx = world.effects
	var puffs0 := int(fx.particles.emitted.get("muzzle", 0))
	var shots0: int = t.ch.wpn.shots
	t._act_press("fire")
	await t._wait(0.6)
	t._shot("r25_smoke_auto")
	await t._wait(0.6)
	t._act_release("fire")
	await t._wait(0.3)
	var shots: int = t.ch.wpn.shots - shots0
	var puffs := int(fx.particles.emitted.get("muzzle", 0)) - puffs0
	var k: Dictionary = fx.particles.KINDS["muzzle"]
	measure["smoke"] = {"rounds": shots, "puffs": puffs, "per_puff_cards": k.amount, "alpha": k.color.a, "life": k.life}
	# 1.2 s of fire at about 13 rounds a second: the shooter's own puff at most every 0.6 s
	t._check("r25_smoke_light", shots >= 8 and puffs >= 1 and puffs <= int(ceil(1.2 / 0.6)) + 1,
		"%d rounds, %d smoke puffs (%d cards each, alpha %.2f, %.1f s)" % [shots, puffs, int(k.amount), float(k.color.a), float(k.life)])
