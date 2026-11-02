extends RefCounted
## (r22) A bot's decision layer, built on the LimboAI architecture (src/ai/limbo: hierarchical state machines, behaviour
## trees, a blackboard with its team's as parent). The brain (bot_brain.gd) keeps the senses and the skills: perception,
## paths, doors, unsticking, aim, the trigger, the house search. This file decides which of them run. Three machines:
##
##   body    every tick, by what the body can do: idle (plane, dead, spectating), airborne (freefall, canopy), downed
##           (crawl), survive (in a walled canal: out by a ladder or over the wall) and play.
##   mind    four times a second while playing: which mode the bot is in. One ordered table of guards picks it (the first
##           that holds wins; nothing falls through by accident):
##             1 directed   a fall-back order (no enemy within 12 m)      6 evacuate   the haze says leave now
##             2 evacuate   the haze is on us and the enemy is not close  7 directed   a radio order
##             3 combat     an enemy in sight                             8 ready      Deathmatch: the first seconds
##             4 recover    bleeding, or hurt with something to treat it  9 directed   a ping, a leader, a noise
##             5 evacuate   on the way out of a house                     10 objective what the role does (the rest)
##           Each mode is a BTState whose tree makes the decisions (pick a spot, start a hold, hunt, sweep...). Its leaves
##           set the activity (the brain's state label). A mode whose tree ends hands over to objective at once.
##   motor   every tick: the activity the label names runs (move, hold, fetch, order, follow, heal, fight). fight is
##           itself a tree, ticked every frame: aim, then the trigger, then the footwork (pro tactics first).
##
## Trees and states call methods of this object (Callables, which do not keep it alive) and nothing points back up, so
## the whole mind goes when its brain does. The brain is held weakly; b is set only while update() runs.
## --bottrace prints describe() each second; --mindlog writes "[mind] <bot> <from> -> <to> (<why>)" to the match log.
## docs/BOT_AI.md has the trees drawn out.

const BT := preload("res://src/ai/limbo/bt.gd")
const Blackboard := preload("res://src/ai/limbo/blackboard.gd")
const LimboState := preload("res://src/ai/limbo/limbo_state.gd")
const LimboHSM := preload("res://src/ai/limbo/limbo_hsm.gd")
const BTState := preload("res://src/ai/limbo/bt_state.gd")
const BotTeam := preload("res://src/ai/bot_team.gd")
const LootSense := preload("res://src/ai/loot_sense.gd")

const THINK_DT := 0.25
const RUNNING := BT.RUNNING
const SUCCESS := BT.SUCCESS
const FAILURE := BT.FAILURE
## The activity each state label runs (anything else walks: roam, hunt, loot, zone, investigate, deploy).
const ACT_OF := {"fight": &"fight", "order": &"order", "heal": &"heal", "fetch": &"fetch", "camp": &"hold",
	"overwatch": &"hold", "follow": &"follow"}

var _wb: WeakRef
var b = null                 # the brain, while update() runs
var bb = null                # this bot's blackboard (parent: its team's, BotTeam.board)
var body = null
var mind = null
var motor = null
var _rank: Array = []        # the mind's guard table: [guard, event], first match wins
var _why := ""               # the guard that chose the mode last
var _label := ""             # the activity label the motor is on
var _way := {}               # survive: the way out of the water (the brain's _water_way)


func _init(brain) -> void:
	_wb = weakref(brain)
	bb = Blackboard.new(BotTeam.board(brain.ch.team))
	_build_body()
	_build_mind()
	_build_motor()
	var me := weakref(brain)
	body.initialize(me, bb)
	mind.initialize(me, bb)
	motor.initialize(me, bb)
	body.set_active(true)
	mind.set_active(true)
	motor.set_active(true)


func update(dt: float) -> void:
	## One server tick (from the brain's think): the body machine by the character's mode, then its state's update.
	b = _wb.get_ref()
	if b == null:
		return
	body.dispatch(_body_event(dt))
	body.update(dt)
	b = null


func describe() -> String:
	## "body/play mind/objective [objective/role/sniper/on the way] motor/move" (for --bottrace).
	var s: String = body.active_path()
	var ms = mind.get_active_state()
	if ms != null:
		s += " mind/" + str(ms.name)
		var rp: String = ms.running_path() if ms.has_method("running_path") else ""
		if rp != "":
			s += " [" + rp + "]"
	var mo = motor.get_active_state()
	if mo != null:
		s += " motor/" + str(mo.name)
	return s


func mode() -> String:
	## The mind's mode now (combat, recover, evacuate, directed, ready, objective).
	var ms = mind.get_active_state()
	return str(ms.name) if ms != null else ""


# ------------------------------------------------------------------ body (every tick)

func _build_body() -> void:
	body = LimboHSM.new("body")
	var idle = body.add_child_state(LimboState.new("idle"))
	var air = body.add_child_state(LimboState.new("airborne").call_on_update(_air))
	var down = body.add_child_state(LimboState.new("downed").call_on_update(_down))
	var wet = body.add_child_state(LimboState.new("survive").call_on_update(_survive))
	var play = body.add_child_state(LimboState.new("play").call_on_update(_play))
	body.initial_state = idle
	for s in [idle, air, down, wet, play]:
		body.add_transition(body.ANYSTATE, s, StringName(s.name))


func _body_event(dt: float) -> StringName:
	var m: int = b.ch.mode
	if m == Motor.PLANE or m == Motor.DEAD or m == Motor.SPECTATE:
		return &"idle"
	if m == Motor.FREEFALL or m == Motor.CHUTE:
		return &"airborne"
	if m == Motor.DOWNED:
		return &"downed"
	b._tally()
	# Down in a walled canal (wading the estero is fine): out first, by a ladder or the nearest dry ground.
	if b._wet_step(dt):
		_way = b._water_way()
		if not _way.is_empty():
			return &"survive"
	return &"play"


func _air(dt: float) -> void:
	b._deploy(b._cmd, dt)


func _down(_dt: float) -> void:
	b._crawl()


func _survive(dt: float) -> void:
	b._escape_water(b._cmd, dt, _way)
	b.yaw = float(b._cmd.yaw)
	b.pitch = float(b._cmd.pitch)


func _play(dt: float) -> void:
	if b._think_tick(dt):
		_think()
	b._replies()
	_act(dt)
	b._finish(dt)


# ------------------------------------------------------------------ mind (four times a second)

func _build_mind() -> void:
	mind = LimboHSM.new("mind")
	var combat = mind.add_child_state(BTState.new("combat", BT.Action.new(_engage, "engage"), &"done", &"done").call_on_exit(_disengage))
	var recover = mind.add_child_state(BTState.new("recover", BT.Action.new(_treat, "treat"), &"done", &"done"))
	var evacuate = mind.add_child_state(BTState.new("evacuate", _evacuate_tree(), &"done", &"done"))
	var directed = mind.add_child_state(BTState.new("directed", _directed_tree(), &"done", &"done"))
	var ready = mind.add_child_state(BTState.new("ready", BT.Action.new(_muster, "muster"), &"done", &"done"))
	var objective = mind.add_child_state(BTState.new("objective", _objective_tree(), &"done", &"done"))
	mind.initial_state = objective
	for s in [combat, recover, evacuate, directed, ready, objective]:
		mind.add_transition(mind.ANYSTATE, s, StringName(s.name))
	# A mode whose tree has nothing to do hands over to the objective (and the next think chooses afresh anyway).
	for s in [combat, recover, evacuate, directed, ready]:
		mind.add_transition(s, objective, &"done")
	_rank = [
		[_g_fall_back, &"directed"],
		[_g_haze_on_us, &"evacuate"],
		[_g_enemy, &"combat"],
		[_g_hurt, &"recover"],
		[_g_leaving, &"evacuate"],
		[_g_haze, &"evacuate"],
		[_g_order, &"directed"],
		[_g_mustering, &"ready"],
		[_g_called, &"directed"],
		[_g_always, &"objective"],
	]


func _think() -> void:
	_sense()
	var ev := _arbitrate()
	var was = mind.get_active_state()
	mind.dispatch(ev)
	var now = mind.get_active_state()
	if now != was:
		_note_change(was, now)
	mind.update(THINK_DT)
	if mind.get_active_state() != now:
		# its tree found nothing to do and handed over (to the objective): think there now, as the old if-chain fell through
		_why = "handover"
		_note_change(now, mind.get_active_state())
		mind.update(THINK_DT)


func _sense() -> void:
	## What every guard and tree reads this think, worked out once.
	if not b.order.is_empty() and b._order_expired():
		b.order = {}
	var tc = b.world.characters.get(b.target_eid) if b.target_eid >= 0 else null
	bb.set_var(&"target_d", (tc.global_position as Vector3).distance_to(b.ch.global_position) if tc != null else INF)
	var hz: Dictionary = b._haze()
	bb.set_var(&"haze", hz)
	b._zone_go = bool(hz.go)
	bb.set_var(&"leader", b._leader())


func _arbitrate() -> StringName:
	for r in _rank:
		if bool((r[0] as Callable).call()):
			_why = (r[0] as Callable).get_method()
			return r[1]
	return &"objective"


func _note_change(from, to) -> void:
	if Game.arg("mindlog") == null or not b._logging():
		return
	b.world.match_server.log_event("[mind] %s %s -> %s (%s)" % [b.ch.pname, str(from.name) if from != null else "-",
		str(to.name) if to != null else "-", _why])


# guards, in the order of _rank

func _g_fall_back() -> bool:
	return str(b.order.get("kind", "")) == "fall_back" and float(bb.get_var(&"target_d")) >= 12.0


func _g_haze_on_us() -> bool:
	# caught in the haze with the enemy not close: keep running for the circle (it kills faster than they do)
	var d := float(bb.get_var(&"target_d"))
	return b.target_eid >= 0 and bool(bb.get_var(&"haze").urgent) and d > 15.0 and d < INF


func _g_enemy() -> bool:
	return b.target_eid >= 0


func _g_hurt() -> bool:
	var h = b.ch.health
	return h.bleeding_level() > 0 or (h.health < (60.0 if not b.dm else 50.0) and b.ch.inv.count("first_aid") > 0) \
		or (h.health < 65.0 and b.ch.inv.count("bandage") > 0)


func _g_leaving() -> bool:
	return b._exiting()


func _g_haze() -> bool:
	return bool(bb.get_var(&"haze").go)


func _g_order() -> bool:
	return not b.order.is_empty()


func _g_mustering() -> bool:
	# (following a player who said "Follow me" beats holding)
	return b.dm and b._dm_hold > 0.0 and bb.get_var(&"leader") == null


func _g_called() -> bool:
	return not b._ping.is_empty() or bb.get_var(&"leader") != null or b.investigate != Vector3.INF


func _g_always() -> bool:
	return true


# combat, recover, ready: one leaf each (the fighting itself is the motor's fight tree)

func _engage(_d: float) -> int:
	b.state = "fight"
	b._seen_t += THINK_DT
	return RUNNING


func _disengage() -> void:
	if b != null:
		b._seen_t = 0.0


func _treat(_d: float) -> int:
	b.state = "heal"
	return RUNNING


func _muster(_d: float) -> int:
	b._dm_hold -= THINK_DT
	b.state = "roam"
	b.goal = Vector3.INF
	return RUNNING


static func _when(cond: Callable, action, task_name: String):
	## A guarded branch: the condition is checked again every tick (so a running action stops when it no longer holds).
	return BT.DynamicSequence.new([BT.Condition.new(cond), action], task_name)


func _keep(_d: float) -> int:
	return RUNNING


# evacuate: out of the house first, then run for the circle

func _evacuate_tree():
	return BT.DynamicSelector.new([
		BT.DynamicSequence.new([
			BT.Selector.new([BT.Condition.new(_g_leaving, "already leaving"), BT.Action.new(_find_door, "find the door")]),
			BT.Action.new(_walk_out, "walk out"),
		], "out of the house"),
		BT.Action.new(_run_for_circle, "run for the circle"),
	], "evacuate")


func _find_door(_d: float) -> int:
	return SUCCESS if b._find_exit() and b._leave_house() else FAILURE


func _walk_out(_d: float) -> int:
	return RUNNING if b._exiting() else SUCCESS


func _run_for_circle(_d: float) -> int:
	var hz: Dictionary = bb.get_var(&"haze")
	if b.state != "zone" or b.goal == Vector3.INF or b._goal_raw.distance_to(hz.p) > 25.0:
		b._set_goal(hz.p)
		var phase := int(b.world.match_info.get("zone", {}).get("i", -1))
		if b._leads() and b._haze_said != phase:
			b._haze_said = phase
			b.say("haze", bool(hz.urgent))
	b.state = "zone"
	b.plan = []
	return RUNNING


# directed: an order, a teammate's ping, a leader to follow, a noise to look into

func _directed_tree():
	return BT.DynamicSelector.new([
		_when(_g_order, BT.Action.new(_carry_out, "carry it out"), "order"),
		_when(_has_ping, BT.Action.new(_answer_ping, "answer it"), "ping"),
		_when(_has_leader, BT.Action.new(_keep_up, "keep up"), "follow"),
		_when(_heard, BT.Action.new(_look_into, "go and look"), "investigate"),
	], "directed")


func _carry_out(_d: float) -> int:
	if b.state != "order":
		b._set_goal(b.order.p)
	b.state = "order"
	return RUNNING


func _has_ping() -> bool:
	return not b._ping.is_empty()


func _answer_ping(_d: float) -> int:
	return RUNNING if b._ping_step() else FAILURE


func _has_leader() -> bool:
	return bb.get_var(&"leader") != null


func _keep_up(_d: float) -> int:
	if b.state != "follow":
		b._follow_goal_t = 0.0
	b.state = "follow"
	return RUNNING


func _heard() -> bool:
	return b.investigate != Vector3.INF


func _look_into(_d: float) -> int:
	if b.state in ["camp", "overwatch"] and b.ch.global_position.distance_to(b.investigate) > 18.0:
		# holding a spot: look that way rather than leave it
		b._look_at = b.investigate
		b.investigate = Vector3.INF
		return RUNNING
	if b.state != "investigate":
		b._set_goal(b._inside_zone(b.investigate) if b.dm else b.investigate)
	b.state = "investigate"
	if b.ch.global_position.distance_to(b.investigate) < 4.5 or b.goal == Vector3.INF:
		b.investigate = Vector3.INF
		if b.rng.randf() < 0.35:
			b.say("clear")
	return RUNNING


# objective: carry on with what is under way, get out of a house, gear up, then the role

func _objective_tree():
	return BT.DynamicSelector.new([
		_when(_fetching, BT.Action.new(_keep, "keep at it"), "fetching"),
		_when(_searching, BT.Action.new(_keep, "keep at it"), "searching a house"),
		_when(_holding, BT.Action.new(_keep, "keep at it"), "holding"),
		BT.Action.new(_out_of_house, "out of the house"),
		_when(_may_fetch, BT.Action.new(_fetch, "fetch"), "gear up"),
		_when(_unarmed_classic, BT.Action.new(_loot_houses, "loot houses"), "arm yourself"),
		BT.DynamicSequence.new([BT.Action.new(_rethink, "rethink"), _role_tree()], "role"),
	], "objective")


func _fetching() -> bool:
	return b.state == "fetch" and not b._fetch.is_empty()


func _searching() -> bool:
	return b.state == "loot" and b.plan_i < b.plan.size()


func _holding() -> bool:
	return b.state in ["camp", "overwatch"] and b._hold_t > 0.0 and b._nade_want < 0   # (r28) a grenade to fetch ends a hold


func _out_of_house(_d: float) -> int:
	return RUNNING if b._leave_house() else FAILURE


func _may_fetch() -> bool:
	# Classic: everyone loots until armed; Deathmatch bots start armed and loot only when low on rounds, or (r28) go for
	# a grenade pickup they chose to take
	return not b.dm or not LootSense.armed_ok(b.ch) or b._nade_want >= 0


func _fetch(_d: float) -> int:
	return RUNNING if b._pick_fetch() else FAILURE


func _unarmed_classic() -> bool:
	return not b.dm and not LootSense.armed_ok(b.ch)


func _loot_houses(_d: float) -> int:
	if not (b.state == "roam" and b.goal != Vector3.INF and b.path_i < b.path.size()):
		b._pick_loot_goal()
	return RUNNING


func _rethink(_d: float) -> int:
	b._obj_t -= THINK_DT
	return SUCCESS


# the roles

func _role_tree():
	return BT.DynamicSelector.new([
		_when(_endgame, _endgame_tree(), "endgame"),
		_when(_is.bind("ambusher"), _ambusher_tree(), "ambusher"),
		_when(_is.bind("looter"), _looter_tree(), "looter"),
		_when(_is.bind("sniper"), _sniper_tree(), "sniper"),
		_when(_is.bind("rusher"), _hunter_tree(true), "rusher"),
		_when(_is.bind("stalker"), _hunter_tree(false), "stalker"),
	], "role")


func _is(role: String) -> bool:
	match role:
		"ambusher":
			return b.role == "looter" and b.dm   # (r21) Deathmatch looters have no houses to search
		"looter":
			return b.role == "looter" and not b.dm
	return b.role == role


func _hunting_on() -> bool:
	return b.state == "hunt" and b.goal != Vector3.INF and b._obj_t > 0.0


func _roaming_on() -> bool:
	return b.state == "roam" and b.goal != Vector3.INF and b._obj_t > 0.0


func _at_objective(reach: float) -> bool:
	return b.state == "roam" and b._obj != Vector3.INF and b.goal == Vector3.INF and b.ch.global_position.distance_to(b._obj) < reach


func _hold(_d: float, kind: String) -> int:
	if kind == "camp":
		b._start_hold("camp", b.rng.randf_range(25.0, 50.0) * (0.5 + b.patience) * b._sk_hold)
	else:
		b._start_hold("overwatch", b.rng.randf_range(40.0, 80.0) * (0.5 + b.patience) * b._sk_hold)
	return RUNNING


func _ambusher_tree():
	## r21 Deathmatch looter: takes a hiding spot (a popular one first), crouches there watching its approach, and after
	## a while moves to another (r22: never the same one, nor one beside it, for three minutes).
	return BT.DynamicSequence.new([
		BT.AlwaysSucceed.new(BT.Action.new(_hold_over, "hold over")),
		BT.DynamicSelector.new([
			_when(_at_objective.bind(3.0), BT.Action.new(_hold.bind("camp"), "camp"), "in place"),
			BT.AlwaysFail.new(BT.Action.new(_walk_ended_short, "walk ended short")),
			_when(_roaming_on, BT.Action.new(_keep, "keep going"), "on the way"),
			BT.Action.new(_take_hiding_spot, "take a hiding spot"),
		], "ambush"),
	], "ambusher")


func _hold_over(_d: float) -> int:
	if b.state == "camp":
		b.state = "roam"
		b._obj = Vector3.INF
		b._obj_t = 0.0
	return SUCCESS


func _walk_ended_short(_d: float) -> int:
	if b.state == "roam" and b._obj != Vector3.INF and b.goal == Vector3.INF:
		b._obj = Vector3.INF   # the walk ended short of it: pick again
	return SUCCESS


func _take_hiding_spot(_d: float) -> int:
	var sp: int = b._pick_spot("hide")
	if sp < 0:
		sp = b._pick_spot("cover")
	if sp < 0:
		b._hunt_target(false)
		return RUNNING
	b._head_for_spot(sp, 40.0)
	if b._leads() and Time.get_ticks_msec() - b._chat_t > 60000 and b.rng.randf() < 0.5:
		b._chat_t = Time.get_ticks_msec()
		b.say("sneaking")
	return RUNNING


func _looter_tree():
	## Classic looter: house after house (the search plan and the camp inside are the house's plan steps).
	return BT.DynamicSequence.new([
		BT.AlwaysSucceed.new(BT.Action.new(_camp_over, "camp over")),
		BT.DynamicSelector.new([
			_when(_roaming_on, BT.Action.new(_keep, "keep going"), "on the way"),
			BT.Action.new(_next_house, "next house"),
		], "houses"),
	], "looter")


func _camp_over(_d: float) -> int:
	if b.state == "camp":
		b.state = "roam"   # done holding: out of the door and on to the next house
	return SUCCESS


func _next_house(_d: float) -> int:
	b._pick_loot_goal()
	b._obj_t = 8.0
	return RUNNING


func _sniper_tree():
	return BT.DynamicSelector.new([
		_when(_hunting_on, BT.Action.new(_keep, "keep going"), "hunting"),
		_when(_at_objective.bind(4.0), BT.Action.new(_hold.bind("overwatch"), "overwatch"), "in position"),
		_when(_roaming_on, BT.Action.new(_keep, "keep going"), "on the way"),
		BT.Action.new(_take_sniping_spot, "take a sniping spot"),
	], "sniper")


func _take_sniping_spot(_d: float) -> int:
	var sp: int = b._pick_spot("snipe")
	if sp < 0:
		sp = b._pick_spot("cover")
	if sp < 0:
		b._hunt_target(false)
		return RUNNING
	b._head_for_spot(sp, 25.0)
	if b._leads() and Time.get_ticks_msec() - b._chat_t > 60000:
		b._chat_t = Time.get_ticks_msec()
		b.say("sniping")
	return RUNNING


func _hunter_tree(open: bool):
	## Rushers hunt across the open at a sprint; stalkers by cover waypoints off to one side (a flank).
	return BT.DynamicSelector.new([
		_when(_hunting_on, BT.Action.new(_keep, "keep going"), "on the way"),
		BT.Action.new(_hunt.bind(open), "pick a hunt"),
	], "hunt")


func _hunt(_d: float, open: bool) -> int:
	b._hunt_target(open)
	return RUNNING


# the endgame (Deathmatch, a side down to a few, or a long quiet): short holds at most, a sweep in between

func _endgame() -> bool:
	return b._end


func _endgame_tree():
	## Fresh word of an enemy (a sighting, a callout, the team's hint) is hunted down; otherwise the bot sweeps the map
	## with its team, stalest cell first, with one short hold now and then (snipers and ambushers, at a spot of their
	## kind the sweep brought them to).
	return BT.DynamicSelector.new([
		_when(_sweep_under_way, BT.Action.new(_keep, "keep going"), "on the way"),
		_when(_at_sweep_spot, BT.Action.new(_short_hold, "short hold"), "short hold"),
		BT.AlwaysFail.new(BT.Action.new(_end_leg, "leg over")),
		_when(_far_word, BT.Action.new(_after_word, "after it"), "word of an enemy"),
		BT.Action.new(_sweep, "sweep"),
	], "endgame")


func _far_word() -> bool:
	var it: Vector3 = b._intel()
	return it != Vector3.INF and b.ch.global_position.distance_to(it) > 10.0


func _sweep_under_way() -> bool:
	# on the way (a sweep leg gives way to word of an enemy)
	return b.state == "hunt" and b.goal != Vector3.INF and b._obj_t > 0.0 \
		and (b._obj == Vector3.INF or b.ch.global_position.distance_to(b._obj) > 3.0) and not (b._sweeping and _far_word())


func _at_sweep_spot() -> bool:
	if not (b._sweeping and b._spot_i >= 0 and b._spot_i < BotTeam.spots.size() and b.role in ["looter", "sniper"] and b._hold_ok()):
		return false
	var s: Dictionary = BotTeam.spots[b._spot_i]
	if b.ch.global_position.distance_to(s.p) >= 3.5:
		return false
	var kind := str(s.kind)
	return (b.role == "sniper" and kind in ["snipe", "cover"]) or (b.role == "looter" and kind in ["hide", "cover"])


func _short_hold(_d: float) -> int:
	var s: Dictionary = BotTeam.spots[b._spot_i]
	BotTeam.sweep_done(b.ch.team, b.ch.eid)
	b._look_at = (s.p as Vector3) + Vector3((s.dir as Vector2).x, 0, (s.dir as Vector2).y) * 25.0 + Vector3.UP * 1.2
	if b.role == "sniper":
		b._start_hold("overwatch", b._sk_end_watch * b.rng.randf_range(0.6, 1.0))
	else:
		b._start_hold("camp", b._sk_end_camp * b.rng.randf_range(0.6, 1.0))
	return RUNNING


func _end_leg(_d: float) -> int:
	if b._sweeping:
		BotTeam.sweep_done(b.ch.team, b.ch.eid)
		b._sweeping = false
	return SUCCESS


func _after_word(_d: float) -> int:
	b._hunt_target(b.role == "rusher")
	return RUNNING


func _sweep(_d: float) -> int:
	b._sweep()
	return RUNNING


# ------------------------------------------------------------------ motor (every tick)

func _build_motor() -> void:
	motor = LimboHSM.new("motor")
	var move = motor.add_child_state(LimboState.new("move").call_on_update(_m_move))
	var hold = motor.add_child_state(LimboState.new("hold").call_on_update(_m_hold))
	var fetch = motor.add_child_state(LimboState.new("fetch").call_on_update(_m_fetch))
	var order = motor.add_child_state(LimboState.new("order").call_on_update(_m_order))
	var follow = motor.add_child_state(LimboState.new("follow").call_on_update(_m_follow))
	var heal = motor.add_child_state(LimboState.new("heal").call_on_update(_m_heal))
	var fight = motor.add_child_state(BTState.new("fight", _combat_tree(), &"fought", &"lost"))
	motor.initial_state = move
	for s in [move, hold, fetch, order, follow, heal, fight]:
		motor.add_transition(motor.ANYSTATE, s, StringName(s.name))


func _act(dt: float) -> void:
	if b.state != _label:
		_label = b.state
		motor.dispatch(ACT_OF.get(_label, &"move"))
	motor.update(dt)


func _m_move(dt: float) -> void:
	if b._detour >= 0:
		b._detour_step(b._cmd, dt)
	else:
		b._move(b._cmd, dt, false)
		if b._preaim_t > 0.0:
			b._pre_aim(b._cmd, dt)
	b._loot_actions(b._cmd, dt)


func _m_hold(dt: float) -> void:
	b._hold_step(b._cmd, dt)
	b._upkeep(b._cmd, dt)


func _m_fetch(dt: float) -> void:
	b._fetch_step(b._cmd, dt)


func _m_order(dt: float) -> void:
	b._order_step(b._cmd, dt)
	b._upkeep(b._cmd, dt)


func _m_follow(dt: float) -> void:
	b._follow_step(b._cmd, dt)
	b._upkeep(b._cmd, dt)


func _m_heal(dt: float) -> void:
	b._cmd.btn |= Motor.B_HEAL if b.ch.health.treatment.is_empty() and b.rng.randf() < 0.2 else 0
	b._move(b._cmd, dt, true)


# the fight, every tick

func _combat_tree():
	## aim -> unarmed: get away | armed: the trigger, then the footwork (pro tactics first, else by temperament).
	return BT.DynamicSequence.new([
		BT.Action.new(_f_aim, "aim"),
		BT.DynamicSelector.new([
			_when(_f_unarmed, BT.Action.new(_f_flee, "get away"), "unarmed"),
			BT.DynamicSequence.new([
				BT.Action.new(_f_trigger, "trigger"),
				BT.DynamicSelector.new([
					_when(_f_pro, BT.DynamicSequence.new([
						BT.Action.new(_f_read, "read the fight"),
						BT.DynamicSelector.new([
							_when(_f_reloading_exposed, BT.Action.new(_f_back_off, "out of the line of fire"), "reloading"),
							_when(_f_rushing, BT.Action.new(_f_rush, "close in"), "rush"),
							_when(_f_long_gun, BT.Action.new(_f_range, "keep range"), "long gun"),
							_when(_f_opening, BT.Action.new(_f_push, "push"), "opening"),
							BT.Action.new(_f_strafe, "strafe"),
						], "tactics"),
					], "pro"), "pro"),
					BT.Action.new(_f_temperament, "by temperament"),
				], "footwork"),
			], "armed"),
		], "act"),
	], "combat")


func _f_aim(dt: float) -> int:
	return SUCCESS if b._fight_aim(b._cmd, dt) else FAILURE


func _f_unarmed() -> bool:
	return b.ch.wpn.current_id() == ""


func _f_flee(_d: float) -> int:
	b._fight_flee(b._cmd)
	return RUNNING


func _f_trigger(dt: float) -> int:
	b._fight_trigger(b._cmd, dt)
	return SUCCESS


func _f_pro() -> bool:
	return b._sk_tactics


func _f_read(dt: float) -> int:
	b._pro_tick(dt)
	return SUCCESS


func _f_reloading_exposed() -> bool:
	return b._pro_reloading_exposed()


func _f_back_off(_d: float) -> int:
	b._pro_back_off(b._cmd)
	return RUNNING


func _f_rushing() -> bool:
	return b._rush


func _f_rush(_d: float) -> int:
	b._pro_rush(b._cmd)
	return RUNNING


func _f_long_gun() -> bool:
	return b._f_cls in ["marksman", "precision"]


func _f_range(_d: float) -> int:
	b._pro_range(b._cmd)
	return RUNNING


func _f_opening() -> bool:
	return b._push and b._f_d > 4.0 and b._f_cls in ["smg", "rifle", "shotgun", "lmg"]


func _f_push(_d: float) -> int:
	b._pro_push(b._cmd)
	return RUNNING


func _f_strafe(_d: float) -> int:
	b._pro_strafe(b._cmd)
	return RUNNING


func _f_temperament(_d: float) -> int:
	b._fight_temperament(b._cmd)
	return RUNNING
