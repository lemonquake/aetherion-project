extends SceneTree
## Self-test of the LimboAI-style framework (src/ai/limbo): behaviour-tree statuses and composites, decorators, the
## blackboard's scopes, the state machine's transitions, guards, nesting and deferred changes, BTState events, and that
## a machine and its owner are freed when dropped (no reference cycles). Headless, a second:
##   godot --headless --path game -s res://tools/limbo_selftest.gd
## Prints PASS/FAIL per check and "limbo selftest: N passed, M failed"; exits 1 on a failure.

const BT := preload("res://src/ai/limbo/bt.gd")
const Blackboard := preload("res://src/ai/limbo/blackboard.gd")
const LimboState := preload("res://src/ai/limbo/limbo_state.gd")
const LimboHSM := preload("res://src/ai/limbo/limbo_hsm.gd")
const BTState := preload("res://src/ai/limbo/bt_state.gd")

const CHECKS := 29
var passed := 0
var failed := 0
var log: Array = []
var clock := 0.0


class Owner extends RefCounted:
	## Holds a machine whose states and tree call back into it by method (the bot mind's pattern).
	var hsm = null
	var ticks := 0

	func build() -> void:
		var bt := preload("res://src/ai/limbo/bt.gd")
		hsm = preload("res://src/ai/limbo/limbo_hsm.gd").new("root")
		var a = hsm.add_child_state(preload("res://src/ai/limbo/bt_state.gd").new("a", bt.Sequence.new([bt.Condition.new(yes), bt.Action.new(tick)]), &"done", &"done"))
		var b = hsm.add_child_state(preload("res://src/ai/limbo/limbo_state.gd").new("b").call_on_update(upd))
		hsm.add_transition(a, b, &"done", yes)
		hsm.add_transition(hsm.ANYSTATE, a, &"again")
		hsm.initialize(weakref(self), preload("res://src/ai/limbo/blackboard.gd").new())
		hsm.set_active(true)

	func yes() -> bool:
		return true

	func tick(_d: float) -> int:
		ticks += 1
		return 3

	func upd(_d: float) -> void:
		ticks += 10


func _init() -> void:
	_blackboard()
	_composites()
	_decorators()
	_hsm()
	_bt_state()
	_freeing()
	if passed + failed != CHECKS:
		failed += 1
		print("FAIL checks_ran  %d of %d checks ran (a script error stopped the rest)" % [passed + failed - 1, CHECKS])
	print("limbo selftest: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
		print("PASS ", name)
	else:
		failed += 1
		print("FAIL ", name, "  ", detail)


# ------------------------------------------------------------------ helpers (method callables, like the bot mind)

var _st := 0   # what the scripted action answers
var _flag := false


func _answer(_d: float) -> int:
	log.append("act")
	return _st


func _true() -> bool:
	return true


func _false() -> bool:
	return false


func _flagged() -> bool:
	return _flag


func _note(what: String) -> void:
	log.append(what)


func _note_d(_d: float, what: String) -> int:
	log.append(what)
	return BT.SUCCESS


func _running(_d: float, what: String) -> int:
	log.append(what)
	return BT.RUNNING


func _now() -> float:
	return clock


# ------------------------------------------------------------------ checks

func _blackboard() -> void:
	var team = Blackboard.new()
	var mine = Blackboard.new(team)
	team.set_var(&"intel", 5)
	_check("bb_parent_read", mine.get_var(&"intel") == 5 and mine.has_var(&"intel") and not mine.vars.has(&"intel"))
	mine.set_var(&"intel", 7)
	_check("bb_write_to_owning_scope", team.get_var(&"intel") == 7 and not mine.vars.has(&"intel"))
	mine.set_var(&"own", 1)
	_check("bb_new_var_local", mine.vars.has(&"own") and not team.has_var(&"own") and mine.get_var(&"none", 3) == 3)


func _composites() -> void:
	# Sequence resumes its running child; Selector likewise.
	log.clear()
	_st = BT.RUNNING
	var seq = BT.Sequence.new([BT.Action.new(_note_d.bind("first")), BT.Action.new(_answer)], "seq")
	seq.initialize(null, Blackboard.new())
	var s1: int = seq.execute(0.1)
	var s2: int = seq.execute(0.1)
	_st = BT.SUCCESS
	var s3: int = seq.execute(0.1)
	_check("sequence_resumes", s1 == BT.RUNNING and s2 == BT.RUNNING and s3 == BT.SUCCESS and log == ["first", "act", "act", "act"], str(log))
	# DynamicSelector: a higher branch that turns true pre-empts (aborts) the running lower one.
	log.clear()
	_flag = false
	var low = BT.Action.new(_running.bind("low"), "low", Callable(), _note.bind("low exit"))
	var dyn = BT.DynamicSelector.new([BT.Sequence.new([BT.Condition.new(_flagged), BT.Action.new(_note_d.bind("high"))]), low])
	dyn.initialize(null, Blackboard.new())
	dyn.execute(0.1)
	dyn.execute(0.1)
	_flag = true
	var d3: int = dyn.execute(0.1)
	_check("dynamic_selector_preempts", d3 == BT.SUCCESS and log == ["low", "low", "high", "low exit"] and low.status == BT.FRESH, str(log))
	# Plain Selector does not re-check a higher branch while a lower one runs.
	log.clear()
	_flag = false
	var low2 = BT.Action.new(_running.bind("low"))
	var sel = BT.Selector.new([BT.Sequence.new([BT.Condition.new(_flagged), BT.Action.new(_note_d.bind("high"))]), low2])
	sel.initialize(null, Blackboard.new())
	sel.execute(0.1)
	_flag = true
	sel.execute(0.1)
	_check("selector_resumes_low", log == ["low", "low"], str(log))
	# DynamicSequence: a guard that turns false stops the running action (and aborts it).
	log.clear()
	_flag = true
	var act = BT.Action.new(_running.bind("work"), "work", Callable(), _note.bind("work exit"))
	var ds = BT.DynamicSequence.new([BT.Condition.new(_flagged), act])
	ds.initialize(null, Blackboard.new())
	ds.execute(0.1)
	_flag = false
	var r: int = ds.execute(0.1)
	_check("dynamic_sequence_guard", r == BT.FAILURE and log == ["work", "work exit"], str(log))
	# Parallel: SUCCESS once one child succeeds.
	var par = BT.Parallel.new([BT.Action.new(_running.bind("p1")), BT.Action.new(_note_d.bind("p2"))], 1, 1)
	par.initialize(null, Blackboard.new())
	_check("parallel_first_success", par.execute(0.1) == BT.SUCCESS)
	# running_path names the running chain.
	var rp = BT.Sequence.new([BT.Condition.new(_true, "ok"), BT.Selector.new([BT.Action.new(_running.bind("x"), "go")], "pick")], "root")
	rp.initialize(null, Blackboard.new())
	rp.execute(0.1)
	_check("running_path", rp.running_path() == "root/pick/go", rp.running_path())


func _decorators() -> void:
	var bb = Blackboard.new()
	var inv = BT.Invert.new(BT.Condition.new(_true))
	inv.initialize(null, bb)
	_check("invert", inv.execute(0.1) == BT.FAILURE)
	# TimeLimit fails once the child has run past the limit, aborting it.
	log.clear()
	var tl = BT.TimeLimit.new(BT.Action.new(_running.bind("t"), "t", Callable(), _note.bind("t exit")), 0.25)
	tl.initialize(null, bb)
	var outs := []
	for i in 5:
		outs.append(tl.execute(0.1))
	_check("time_limit", outs == [BT.RUNNING, BT.RUNNING, BT.RUNNING, BT.FAILURE, BT.RUNNING] and log.has("t exit"), str(outs) + str(log))
	# Cooldown on an injected clock.
	clock = 0.0
	var cd = BT.Cooldown.new(BT.Condition.new(_true), 1.0, false, false, _now)
	cd.initialize(null, bb)
	var c1: int = cd.execute(0.1)
	clock = 0.5
	var c2: int = cd.execute(0.1)
	clock = 1.1
	var c3: int = cd.execute(0.1)
	_check("cooldown", c1 == BT.SUCCESS and c2 == BT.FAILURE and c3 == BT.SUCCESS)
	var rep = BT.Repeat.new(BT.Condition.new(_true), 3)
	rep.initialize(null, bb)
	_check("repeat", [rep.execute(0.1), rep.execute(0.1), rep.execute(0.1)] == [BT.RUNNING, BT.RUNNING, BT.SUCCESS])
	var dl = BT.Delay.new(BT.Condition.new(_true), 0.2)
	dl.initialize(null, bb)
	_check("delay", [dl.execute(0.1), dl.execute(0.1), dl.execute(0.1)] == [BT.RUNNING, BT.RUNNING, BT.SUCCESS])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pr = BT.Probability.new(BT.Condition.new(_true), 0.0, rng)
	pr.initialize(null, bb)
	_check("probability_zero", pr.execute(0.1) == BT.FAILURE)
	var asu = BT.AlwaysSucceed.new(BT.Condition.new(_false))
	asu.initialize(null, bb)
	_check("always_succeed", asu.execute(0.1) == BT.SUCCESS)
	var sv = BT.Sequence.new([BT.SetVar.new(&"k", 4), BT.CheckVar.new(&"k", 4)])
	sv.initialize(null, bb)
	_check("set_check_var", sv.execute(0.1) == BT.SUCCESS and bb.get_var(&"k") == 4)


func _hsm() -> void:
	log.clear()
	var root = LimboHSM.new("root")
	var idle = root.add_child_state(LimboState.new("idle").call_on_enter(_note.bind("idle in")).call_on_exit(_note.bind("idle out")))
	var fight = root.add_child_state(LimboState.new("fight").call_on_enter(_note.bind("fight in")).call_on_exit(_note.bind("fight out")))
	var sub = root.add_child_state(LimboHSM.new("sub"))
	var s1 = sub.add_child_state(LimboState.new("s1").call_on_enter(_note.bind("s1 in")))
	var s2 = sub.add_child_state(LimboState.new("s2").call_on_enter(_note.bind("s2 in")))
	sub.add_transition(s1, s2, &"next")
	root.add_transition(root.ANYSTATE, fight, &"seen")
	root.add_transition(root.ANYSTATE, sub, &"sub")
	root.add_transition(fight, idle, &"calm")
	root.add_transition(root.ANYSTATE, idle, &"blocked", _false)
	root.initialize(null, Blackboard.new())
	root.set_active(true)
	_check("hsm_initial", root.get_active_state() == idle and log == ["idle in"], str(log))
	_check("hsm_anystate", root.dispatch(&"seen") and root.get_active_state() == fight)
	_check("hsm_no_self_anystate", not root.dispatch(&"seen") and log.count("fight in") == 1, str(log))
	_check("hsm_guard_blocks", not root.dispatch(&"blocked") and root.get_active_state() == fight)
	_check("hsm_specific", root.dispatch(&"calm") and root.get_active_state() == idle)
	root.dispatch(&"sub")
	_check("hsm_nested_enter", root.get_leaf_state() == s1 and root.active_path() == "root/sub/s1", root.active_path())
	_check("hsm_nested_event", s1.dispatch(&"next") and root.get_leaf_state() == s2)
	# A state guard refuses entry.
	fight.set_guard(_false)
	_check("hsm_state_guard", not root.dispatch(&"seen") and root.get_active_state() == sub)
	fight.set_guard(Callable())
	# A transition asked for during the update is applied when the update ends.
	idle.call_on_update(_ask_seen.bind(idle))
	root.dispatch(&"seen")
	root.dispatch(&"calm")
	log.clear()
	root.update(0.1)
	_check("hsm_deferred", root.get_active_state() == fight and log == ["update idle", "idle out", "fight in"], str(log))
	# An unhandled "finished" at the root ends the machine.
	root.dispatch(&"finished")
	_check("hsm_finished_ends", not root.is_active())


func _ask_seen(_d: float, s) -> void:
	log.append("update " + s.name)
	s.dispatch(&"seen")


func _bt_state() -> void:
	log.clear()
	var root = LimboHSM.new("root")
	var work = root.add_child_state(BTState.new("work", BT.Sequence.new([BT.Action.new(_note_d.bind("step"))]), &"done", &"broke"))
	var rest = root.add_child_state(LimboState.new("rest"))
	root.add_transition(work, rest, &"done")
	root.initialize(null, Blackboard.new())
	root.set_active(true)
	root.update(0.1)
	_check("bt_state_success_event", root.get_active_state() == rest and log == ["step"], str(log))


func _freeing() -> void:
	var o := Owner.new()
	o.build()
	o.hsm.update(0.1)
	o.hsm.update(0.1)
	var w := weakref(o)
	var wh := weakref(o.hsm)
	var ws := weakref(o.hsm.states[0])
	var ticks := o.ticks
	o = null
	_check("freed_with_owner", w.get_ref() == null and wh.get_ref() == null and ws.get_ref() == null and ticks == 11,
		"owner %s hsm %s state %s ticks %d" % [str(w.get_ref()), str(wh.get_ref()), str(ws.get_ref()), ticks])
