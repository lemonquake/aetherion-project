extends RefCounted
## r13 checks on a listen host (`--autotest=r13`, `--r13_only=sounds,voice,laser,killradio,static,death`):
##   godot --path game -- --host --game_mode=deathmatch --bots=20 --autostart=1 --autotest=r13 --shots=<dir>
## sounds: the user's recordings and gunshots load, the AWP has a model. voice: each SmarTab voice command, with
## teammate bots placed round the player: those that answer "affirmative" do it (follow, come, move up, pull back),
## and "negative" when none can. laser: a bot near what the player's laser points at goes to check it and says so; a
## camping bot only looks. killradio: a player's headshot kill is confirmed by a teammate bot ("headshot_kill"), a
## bot's own kill ("kill"), a teammate's death ("down"). static: a transmission's radio static reaches enemies near
## a transmitting radio and nobody else (bots turn to it, the player hears an enemy's); voice chat repeats it while
## the key is held. death (last): the player is shot in the head; the camera
## stays on the body in third person with the killer card and the headshot badge, then spectating follows.
## Measurements go to <shots>/r13_measure.json. `--r13_static=off` turns the radio static off (A/B of its effect on bots).

const BotTeam := preload("res://src/ai/bot_team.gd")

var t = null
var world = null
var measure := {}


func _init(autotest) -> void:
	t = autotest
	world = autotest.world


func run() -> void:
	var only := str(Game.arg("r13_only", "")).split(",", false)
	var want := func(n: String) -> bool: return only.is_empty() or n in only
	await t._until(func(): return is_instance_valid(t.ch) and t.ch.mode == Motor.GROUND, 40.0)
	await t._wait(1.5)
	world.map.lighting.forced_time = 450.0
	var ms = world.match_server
	if ms and not ms.zone.is_empty():
		ms.zone = {"i": 0, "state": "wait", "t0": Net.tick, "t1": Net.tick + 100000000, "c0": Vector2.ZERO, "r0": 9000.0, "c1": Vector2.ZERO,
			"r1": 9000.0, "dps": 0.0, "shrink_s": 60.0}
		ms._broadcast()
	for b in world.bots.values():
		b._dm_hold = 9999.0
	if str(Game.arg("r13_static", "on")) == "off":
		Defs.rules.radio.static = false
	for n in ["sounds", "voice", "laser", "killradio", "static", "death"]:
		if want.call(n):
			await (Callable(self, "_" + n)).call()
	var f := FileAccess.open(t.out_dir + "/r13_measure.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(measure, "  "))


# ------------------------------------------------------------------ helpers

func _mates() -> Array:
	var out := []
	for b in world.bots.values():
		if is_instance_valid(b.ch) and b.ch.mode == Motor.GROUND and b.ch.team == t.ch.team:
			out.append(b)
	return out


func _enemies() -> Array:
	var out := []
	for b in world.bots.values():
		if is_instance_valid(b.ch) and b.ch.mode == Motor.GROUND and b.ch.team != t.ch.team:
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
	return Vector3.INF


func _place(b, p: Vector3) -> void:
	if p != Vector3.INF:   # no open spot found: the bot stays where it is
		b.ch.global_position = p
	b.ch.velocity = Vector3.ZERO
	b.order = {}
	b.goal = Vector3.INF
	b.plan = []
	b.path = []
	b.state = "roam"
	b.target_eid = -1
	b.investigate = Vector3.INF
	b._ping = {}
	b._replies_q = []
	BotTeam.leave_squad(b.ch.eid)


func _said(since: int, line: String, eids: Array = []) -> Array:
	## Bots (eids) that said line on the radio since the msec time.
	var out := []
	for r in world.radio_trace:
		if int(r[0]) >= since and str(r[2]) == line and (eids.is_empty() or int(r[1]) in eids):
			out.append(int(r[1]))
	return out


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ------------------------------------------------------------------ sounds

func _sounds() -> void:
	var ids := ["vox_affirmative_0", "vox_negative_0", "vox_enemy_spotted_0", "vox_in_position_0", "vox_man_down_0", "vox_need_help_0",
		"vox_radio_basic_kill_0", "vox_radio_headshot_kill_0", "shot_awp", "shot_sumpak", "shot_kar98", "shot_m24", "death", "step_dirt",
		"impact_flesh_head", "botr_follow_me_m1_0", "botr_lets_go_m1_0", "botr_fall_back_m1_0", "vox_follow_me_0", "vox_follow_me_2",
		"radio_static", "radio_hiss"]
	var missing := []
	for id in ids:
		if SoundSys._pick(id) == null:
			missing.append(id)
	t._check("r13_sounds_load", missing.is_empty(), "%d of %d sound ids load%s" % [ids.size() - missing.size(), ids.size(), ("; missing " + str(missing)) if not missing.is_empty() else ""])
	var md: Dictionary = world.map.item_visual("bolt_awp")
	t._check("r13_awp", str(Defs.weapon("bolt_awp").get("name", "")) == "AWP" and md.get("mesh") != null and str(Defs.weapon("sumpak").get("sound", "")) == "sumpak",
		"AWP defined with a model (%s); the sumpak shoots its own sound" % str(md.get("model", "?")))


# ------------------------------------------------------------------ voice commands

func _voice() -> void:
	var mates := _mates()
	if mates.size() < 4:
		t._check("r13_voice", false, "need 4 teammate bots, have %d" % mates.size())
		return
	var me: Vector3 = t.ch.global_position
	var res := {}
	# Follow me: two bots 14 m off.
	_place(mates[0], _open_spot(me, 14.0, 0.0))
	_place(mates[1], _open_spot(me, 14.0, 1.2))
	for i in range(2, mates.size()):
		_place(mates[i], _open_spot(me, 140.0 + i * 3.0, i * 0.7))   # out of reach of the short commands
	await t._wait(0.5)
	var t0 := Time.get_ticks_msec()
	var d0: float = _flat(mates[0].ch.global_position, me)
	world.request_voice("follow_me")
	await t._wait(5.0)
	var f := BotTeam.human_followers(t.ch.eid)
	var aff := _said(t0, "affirmative")
	var d1: float = _flat(mates[0].ch.global_position, t.ch.global_position)
	res.follow = {"followers": f, "affirmative": aff, "dist": [d0, d1]}
	t._check("r13_voice_follow", f >= 1 and not aff.is_empty() and mates[0].state == "follow",
		"Follow me: %d bots follow, %d said affirmative, nearest bot %.1f -> %.1f m, state %s" % [f, aff.size(), d0, d1, mates[0].state])
	for b in mates:
		BotTeam.leave_squad(b.ch.eid)
	# Need help: a bot 55 m off comes.
	_place(mates[0], _open_spot(me, 55.0, 2.0))
	_place(mates[1], _open_spot(me, 150.0, 2.5))
	await t._wait(0.5)
	t0 = Time.get_ticks_msec()
	d0 = _flat(mates[0].ch.global_position, t.ch.global_position)
	world.request_voice("need_help")
	await t._wait(14.0)
	d1 = _flat(mates[0].ch.global_position, t.ch.global_position)
	aff = _said(t0, "affirmative", [mates[0].ch.eid])
	var inpos := _said(t0, "in_position", [mates[0].ch.eid])
	res.help = {"dist": [d0, d1], "affirmative": aff, "in_position": inpos, "order": str(mates[0].order)}
	t._check("r13_voice_help", not aff.is_empty() and d1 < d0 - 20.0, "Need help!: bot 55 m off said affirmative %s and came %.1f -> %.1f m (in position said %s)" % [str(not aff.is_empty()), d0, d1, str(not inpos.is_empty())])
	# Let's go: two bots by the player move up to where the player looks (25 m ahead).
	for b in mates:
		b.order = {}
	_place(mates[0], _open_spot(me, 4.0, 0.3))
	_place(mates[1], _open_spot(me, 4.0, 3.4))
	var ahead := _open_spot(me, 25.0, 4.7)
	if ahead != Vector3.INF:
		var to = ahead - t.ch.eye_position()
		t.ctl.yaw = atan2(-to.x, -to.z)
		t.ctl.pitch = atan2(to.y, Vector2(to.x, to.z).length())
	await t._wait(0.6)
	t0 = Time.get_ticks_msec()
	var g0: float = _flat(mates[0].ch.global_position, ahead)
	world.request_voice("lets_go")
	await t._wait(9.0)
	var g1: float = _flat(mates[0].ch.global_position, ahead)
	aff = _said(t0, "affirmative")
	res.go = {"to_aim": [g0, g1], "affirmative": aff}
	t._check("r13_voice_go", not aff.is_empty() and g1 < g0 - 10.0, "Let's go!: bot near the player moved toward where the player looks %.1f -> %.1f m, affirmative %s" % [g0, g1, str(not aff.is_empty())])
	# Fall back: bots 30 m ahead pull back to the player.
	for b in mates:
		b.order = {}
	_place(mates[0], _open_spot(me, 30.0, 0.0))
	_place(mates[1], _open_spot(me, 30.0, 0.6))
	await t._wait(0.5)
	t0 = Time.get_ticks_msec()
	d0 = _flat(mates[0].ch.global_position, t.ch.global_position)
	world.request_voice("fall_back")
	await t._wait(10.0)
	d1 = _flat(mates[0].ch.global_position, t.ch.global_position)
	aff = _said(t0, "affirmative")
	res.fall_back = {"dist": [d0, d1], "affirmative": aff}
	t._check("r13_voice_fall_back", not aff.is_empty() and d1 < 12.0, "Fall back!: bot 30 m off said affirmative %s and pulled back to %.1f m" % [str(not aff.is_empty()), d1])
	# Negative: the only bot in reach is in a close fight, so nobody can come.
	for b in mates:
		b.order = {}
		_place(b, _open_spot(me, 160.0 + b.ch.eid % 5, float(b.ch.eid)))
	var en := _enemies()
	if not en.is_empty():
		var fighter = mates[0]
		_place(fighter, _open_spot(me, 20.0, 1.0))
		en[0].test_idle = true
		en[0].ch.global_position = _open_spot(fighter.ch.global_position, 15.0, 0.5)
		await t._wait(0.3)
		fighter.target_eid = en[0].ch.eid
		fighter.test_idle = true   # keeps its target (thinks nothing) for the check
		t0 = Time.get_ticks_msec()
		world.request_voice("need_help")
		fighter.test_idle = false
		fighter._replies()
		await t._wait(2.5)
		for i in 10:
			fighter._replies()
			await t._wait(0.2)
		var neg := _said(t0, "negative")
		res.negative = {"negative": neg, "order": str(fighter.order)}
		t._check("r13_voice_negative", not neg.is_empty() and fighter.order.is_empty(), "Need help! with the only bot in reach in a close fight: it said negative %s and took no order (%s)" % [str(not neg.is_empty()), str(fighter.order)])
		en[0].test_idle = false
		en[0].ch.global_position = _open_spot(me, 200.0, 2.0)
		fighter.target_eid = -1
	measure["voice"] = res


# ------------------------------------------------------------------ lasers

func _laser() -> void:
	var mates := _mates()
	if mates.size() < 2:
		t._check("r13_laser", false, "need 2 teammate bots")
		return
	var me: Vector3 = t.ch.global_position
	var a = mates[0]
	var c = mates[1]
	_place(a, _open_spot(me, 18.0, 0.4))
	_place(c, _open_spot(me, 16.0, 2.4))
	c._dm_hold = 0.0   # (the test's hold would turn a camp back into roaming)
	c._start_hold("camp", 60.0)
	var dot := Vector3.INF
	for k in 12:
		var cand := _open_spot(a.ch.global_position, 14.0, 1.9 + k * 0.5)
		if cand != Vector3.INF and a._walk_clear(a.ch.global_position, cand):
			dot = cand
			break
	await t._wait(0.5)
	# The camper must still be camping when the laser comes (a bot squad forming nearby once made it a follower).
	var c_state0: String = c.state
	if c.state != "camp":
		BotTeam.leave_squad(c.ch.eid)
		c._start_hold("camp", 60.0)
	measure["laser_camper_before"] = c_state0
	a._laser_cd = 0.0
	c._laser_cd = 0.0
	var t0 := Time.get_ticks_msec()
	var c0: Vector3 = c.ch.global_position
	a.on_laser(t.ch, t.ch.eye_position(), dot, 1.0)
	c.on_laser(t.ch, t.ch.eye_position(), dot, 1.0)
	var c_checked: bool = str(c.order.get("kind", "")) == "check"
	var arrived := -1.0
	var tt := 0.0
	while tt < 15.0:
		await t._wait(0.25)
		tt += 0.25
		if arrived < 0.0 and _flat(a.ch.global_position, dot) < 3.0:
			arrived = tt
	var clear := _said(t0, "clear", [a.ch.eid])
	var c_moved: float = _flat(c.ch.global_position, c0)
	var c_dot: float = _flat(c.ch.global_position, dot) - _flat(c0, dot)
	var c_took: bool = str(c.order.get("kind", "")) == "check" or c_checked
	measure["laser"] = {"arrived_s": arrived, "clear": clear, "camper_moved": c_moved, "camper_closer_to_dot": -c_dot, "camper_state": c.state, "camper_took_check": c_took}
	t._check("r13_laser_check", arrived > 0.0 and not clear.is_empty() and not c_took,
		"teammate laser on a spot 14 m from a roaming bot: it got there in %.1f s and said clear %s; the camping bot took the check: %s (it is now %s)" % [arrived, str(not clear.is_empty()), str(c_took), c.state])


# ------------------------------------------------------------------ kill radio

func _kill(victim, attacker, part: String) -> void:
	var res: Dictionary = victim.ch.health.apply_simple(999.0, "gunshot", part, attacker.eid)
	res["hit_part"] = part
	res["hit_dir"] = (victim.ch.global_position - attacker.global_position).normalized()
	world._after_damage(victim.ch, res, attacker.eid)


func _killradio() -> void:
	var mates := _mates()
	var en := _enemies()
	if mates.size() < 3 or en.size() < 2:
		t._check("r13_kill_radio", false, "need 3 teammates and 2 enemies")
		return
	var me: Vector3 = t.ch.global_position
	_place(mates[0], _open_spot(me, 10.0, 0.2))
	en[0].test_idle = true
	en[0].ch.global_position = _open_spot(me, 20.0, 3.0)
	await t._wait(0.5)
	var t0 := Time.get_ticks_msec()
	_kill(en[0], t.ch, "head")
	await t._wait(2.5)
	var hs := _said(t0, "headshot_kill")
	# A bot's own kill, and a teammate going down (placed and done at once: bots nearby would start a real fight).
	en = _enemies()
	mates = _mates()
	_place(mates[1], _open_spot(me, 8.0, 1.5))
	_place(mates[2], _open_spot(me, 12.0, 5.0))
	en[0].test_idle = true
	en[0].ch.global_position = _open_spot(me, 25.0, 4.0)
	await t._wait(0.2)
	var t1 := Time.get_ticks_msec()
	var killer_eid: int = mates[1].ch.eid
	_kill(en[0], mates[1].ch, "torso")
	await t._wait(3.0)
	var bk := _said(t1, "kill", [killer_eid])
	var t2 := Time.get_ticks_msec()
	var foe = null
	for e in _enemies():
		foe = e
		break
	_kill(mates[1], foe.ch if foe != null else t.ch, "torso")
	await t._wait(2.5)
	var down := _said(t2, "down")
	measure["kill_radio"] = {"headshot_kill": hs, "bot_kill": bk, "down": down}
	t._check("r13_kill_radio", not hs.is_empty() and not bk.is_empty() and not down.is_empty(),
		"player's headshot kill confirmed on the radio by a teammate bot %s; a bot's own kill said %s; a teammate's death called (man down) %s" % [str(not hs.is_empty()), str(not bk.is_empty()), str(not down.is_empty())])


# ------------------------------------------------------------------ radio static

func _heard(b, at: Vector3) -> bool:
	return b.investigate != Vector3.INF and (b.investigate as Vector3).distance_to(at) < 2.5


func _static_heard_by_me(since: int) -> int:
	var n := 0
	for e in SoundSys.trace:
		if int(e[0]) >= since and str(e[1]) == "radio_static":
			n += 1
	return n


func _talk(sec: float) -> void:
	## Voice chat from the player: silent 40 ms frames into the server's relay, as the microphone sends them.
	var frame := PackedByteArray()
	frame.resize(320)
	frame.fill(128)
	for k in int(sec / 0.04):
		Game.relay_voice(Net.local_pid, frame)
		await t._wait(0.04)


func _spot_near(centre: Vector3, dists: Array, ang0: float) -> Vector3:
	for d in dists:
		var p := _open_spot(centre, float(d), ang0)
		if p != Vector3.INF:
			return p
	return Vector3.INF


func _static() -> void:
	var mates := _mates()
	var en := _enemies()
	if mates.is_empty() or en.size() < 3:
		t._check("r13_radio_static", false, "need 1 teammate and 3 enemy bots, have %d and %d" % [mates.size(), en.size()])
		return
	var me: Vector3 = t.ch.global_position
	# Everyone far off, so the only radios in reach are the ones placed here.
	var i := 0
	for b in mates + en:
		b.test_idle = true
		_place(b, _open_spot(me, 170.0 + 4.0 * (i % 6), float(i)))
		i += 1
	var m = mates[0]
	var e_near = en[0]
	var e_far = en[1]
	var e_mate = en[2]
	var pm := _spot_near(me, [60.0, 55.0, 65.0, 50.0], 0.3)
	var pn := _spot_near(me, [9.0, 8.0, 10.0, 7.0], 2.0)
	var pf := _spot_near(me, [30.0, 28.0, 33.0, 26.0], 0.3 + PI)
	var pe := _spot_near(pm, [8.0, 7.0, 9.0, 6.0], 1.0) if pm != Vector3.INF else Vector3.INF
	var pm2 := _spot_near(me, [6.0, 5.0, 7.0, 4.5], 4.0)
	if Vector3.INF in [pm, pn, pf, pe, pm2]:
		t._check("r13_radio_static", false, "no open spots round the player: %s" % str([pm, pn, pf, pe, pm2]))
		for b in mates + en:
			b.test_idle = false
		return
	_place(m, pm)
	_place(e_near, pn)
	_place(e_far, pf)
	_place(e_mate, pe)
	await t._wait(0.3)
	var at_me: Vector3 = t.ch.global_position + Vector3.UP * 1.35
	var at_m: Vector3 = m.ch.global_position + Vector3.UP * 1.35
	SoundSys.trace_on = true
	var res := {}
	# 1. A voice command: out of the player's radio and the teammate's, to the enemies near each; the far one and the
	# player (the speaker's own team) get nothing.
	world._voice_t.erase(t.ch.pid)
	world._static_t.clear()
	var t0 := Time.get_ticks_msec()
	world.request_voice("follow_me")
	await t._wait(0.4)
	var cmd_ok: bool = _heard(e_near, at_me) and _heard(e_mate, at_m) and e_far.investigate == Vector3.INF and _static_heard_by_me(t0) == 0
	res.command = {"near": _heard(e_near, at_me), "near_mate_radio": _heard(e_mate, at_m), "far": e_far.investigate != Vector3.INF, "me": _static_heard_by_me(t0)}
	# 2. Voice chat (microphone frames through the server's relay): at key down, again while talking, and not after
	# the frames stop (the server lets the key go 0.3 s after the last one).
	for b in [e_near, e_mate, e_far]:
		b.investigate = Vector3.INF
	world._static_t.clear()
	var t1 := Time.get_ticks_msec()
	await _talk(0.4)
	var down_ok: bool = _heard(e_near, at_me) and _heard(e_mate, at_m)
	e_near.investigate = Vector3.INF
	await _talk(2.0)
	var held_ok: bool = _heard(e_near, at_me)
	var bursts := 0
	for r in world.static_trace:
		if int(r[0]) >= t1 and int(r[1]) == t.ch.eid:
			bursts += 1
	await t._wait(0.6)
	e_near.investigate = Vector3.INF
	await t._wait(2.0)
	var stop_ok: bool = e_near.investigate == Vector3.INF
	res.chat = {"key_down": down_ok, "held": held_ok, "bursts_in_2.4s": bursts, "stops": stop_ok}
	# 3. The player hears an enemy's static (the enemy bot 9 m off calls out), not a teammate's.
	var t2 := Time.get_ticks_msec()
	world._static_t.clear()
	world.server_bot_radio(e_near.ch, "contact", e_near.voice, 0)
	await t._wait(0.5)
	var enemy_heard := _static_heard_by_me(t2)
	_place(m, pm2)
	await t._wait(0.2)
	var t3 := Time.get_ticks_msec()
	world._static_t.clear()
	world.server_bot_radio(m.ch, "contact", m.voice, 0)
	await t._wait(0.5)
	var mate_heard := _static_heard_by_me(t3)
	res.player = {"enemy_static_heard": enemy_heard, "teammate_static_heard": mate_heard}
	SoundSys.trace_on = false
	for b in mates + en:
		b.test_idle = false
	measure["static"] = res
	t._check("r13_static_bots", cmd_ok and down_ok and held_ok and bursts >= 2 and stop_ok,
		"voice command: enemy 9 m off turned to the player's radio %s, enemy next to a teammate 60 m off turned to that radio %s, enemy 30 m off heard nothing %s, the player heard none %s; voice chat: key down %s, still while held %s (%d bursts in 2.4 s), stops after key up %s" % [
		str(res.command.near), str(res.command.near_mate_radio), str(not res.command.far), str(int(res.command.me) == 0), str(down_ok), str(held_ok), bursts, str(stop_ok)])
	t._check("r13_static_player", enemy_heard >= 1 and mate_heard == 0,
		"the player hears an enemy bot's radio static 9 m off (%d) and not a teammate's 6 m off (%d)" % [enemy_heard, mate_heard])


# ------------------------------------------------------------------ death camera and killer card

func _death() -> void:
	var en := _enemies()
	if en.is_empty():
		t._check("r13_death", false, "no enemy bot")
		return
	var k = en[0]
	k.test_idle = true
	var me: Vector3 = t.ch.global_position
	k.ch.global_position = _open_spot(me, 22.0, 0.8)
	await t._wait(0.5)
	var pos: Vector3 = t.ch.global_position
	var res: Dictionary = t.ch.health.apply_simple(999.0, "gunshot", "head", k.ch.eid)
	res["hit_part"] = "head"
	res["hit_dir"] = (pos - k.ch.global_position).normalized()
	world._after_damage(t.ch, res, k.ch.eid)
	var cam: Camera3D = t.ctl.cam
	var card = world.hud.death_card
	var cam_d := []
	for at in [0.35, 1.0, 2.5, 4.5]:
		await t._wait(at - (0.0 if cam_d.is_empty() else float(cam_d[-1][0])))
		cam_d.append([at, snappedf(cam.global_position.distance_to(pos), 0.01), snappedf(cam.global_position.y - pos.y, 0.01)])
		await t._shot("death_%.1f" % at)
	var name_ok: bool = card._name.text == k.ch.pname
	var hs_shown: bool = card._hs_label.visible and card._badge.visible
	await t._wait(2.5)
	var over: bool = not card.visible and t.ctl._death.is_empty()
	measure["death"] = {"cam": cam_d, "name": card._name.text, "killer": k.ch.pname, "detail": card._detail.text, "headshot_badge": hs_shown, "over_after_6s": over}
	var third := true
	for c in cam_d:
		if float(c[0]) >= 1.0 and (float(c[1]) < 1.0 or float(c[1]) > 7.0 or float(c[2]) < 0.8):
			third = false
	t._check("r13_death_camera", third and over, "camera on the body in third person (distance, height): %s; spectating after 6 s: %s" % [str(cam_d), str(over)])
	t._check("r13_death_card", name_ok and hs_shown and str(card._detail.text).contains("m"),
		"card: killed by %s (killer %s), \"%s\", headshot badge %s" % [card._name.text, k.ch.pname, card._detail.text, str(hs_shown)])
	# The card for a body shot and for the field, drawn straight (the player can only die once a match).
	world.hud.show_death_report({"killer": k.ch.pname, "killer_team": k.ch.team, "weapon": "M416", "dist": 37.0, "part_name": "the chest", "headshot": false, "cause": "gunshot"})
	await t._wait(1.2)
	await t._shot("death_card_body")
	world.hud.show_death_report({"killer": "", "cause": "field"})
	await t._wait(1.2)
	await t._shot("death_card_field")
