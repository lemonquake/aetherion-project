extends RefCounted
## LimboAI's behaviour-tree tasks (bt/tasks/composites, decorators, blackboard, utility) in GDScript, built in code:
##
##   const BT := preload("res://src/ai/limbo/bt.gd")
##   var tree = BT.DynamicSelector.new([
##       BT.Sequence.new([BT.Condition.new(func(): return hurt), BT.Action.new(heal, "heal")], "recover"),
##       BT.Action.new(patrol, "patrol"),
##   ], "root")
##   tree.initialize(agent, blackboard)
##   var st: int = tree.execute(delta)      # BT.RUNNING / BT.SUCCESS / BT.FAILURE
##
## Composites run their children in order. Sequence and Selector resume a RUNNING child where it is; the Dynamic ones
## start again from the first child every tick, and a higher child that now succeeds or runs aborts the lower one that
## was running (how a tree reacts at once to a change: the top branch of a DynamicSelector pre-empts the rest).
## Decorators wrap one child; leaves do the work: Condition (a Callable -> bool), Action (a Callable(delta) -> status),
## Wait, SetVar and CheckVar (blackboard). Names follow LimboAI (BTSequence -> BT.Sequence, ...) so a later move to the
## native plugin is mostly renaming. Times are seconds: Wait, Delay and TimeLimit count the deltas they are ticked with;
## Cooldown uses the clock (Time.get_ticks_msec) unless one is given, since it must run on while not ticked.

const Task := preload("res://src/ai/limbo/bt_task.gd")
const FRESH := 0
const RUNNING := 1
const FAILURE := 2
const SUCCESS := 3


# ------------------------------------------------------------------ composites

class Composite extends Task:
	var last_running_idx := 0

	func _init(kids: Array = [], p_name: String = "") -> void:
		for k in kids:
			add_child(k)
		custom_name = p_name

	func _enter() -> void:
		last_running_idx = 0


class Sequence extends Composite:
	## Children in order until one does not succeed; resumes a RUNNING child.
	func _tick(delta: float) -> int:
		var st := SUCCESS
		for i in range(last_running_idx, children.size()):
			st = children[i].execute(delta)
			if st != SUCCESS:
				last_running_idx = i
				break
		return st

	func _generate_name() -> String:
		return "Sequence"


class Selector extends Composite:
	## Children in order until one does not fail; resumes a RUNNING child.
	func _tick(delta: float) -> int:
		var st := FAILURE
		for i in range(last_running_idx, children.size()):
			st = children[i].execute(delta)
			if st != FAILURE:
				last_running_idx = i
				break
		return st

	func _generate_name() -> String:
		return "Selector"


class DynamicSequence extends Composite:
	## Every tick from the first child; a child that now fails stops the run, aborting a later child that was running.
	func _tick(delta: float) -> int:
		var st := SUCCESS
		var i := 0
		while i < children.size():
			st = children[i].execute(delta)
			if st != SUCCESS:
				break
			i += 1
		if last_running_idx > i and last_running_idx < children.size() and children[last_running_idx].status == RUNNING:
			children[last_running_idx].abort()
		last_running_idx = i
		return st

	func _generate_name() -> String:
		return "DynamicSequence"


class DynamicSelector extends Composite:
	## Every tick from the first child: the first that does not fail wins, aborting a later child that was running.
	func _tick(delta: float) -> int:
		var st := FAILURE
		var i := 0
		while i < children.size():
			st = children[i].execute(delta)
			if st != FAILURE:
				break
			i += 1
		if last_running_idx > i and last_running_idx < children.size() and children[last_running_idx].status == RUNNING:
			children[last_running_idx].abort()
		last_running_idx = i
		return st

	func _generate_name() -> String:
		return "DynamicSelector"


class Parallel extends Composite:
	## Every child each tick: SUCCESS once num_successes_required have succeeded, FAILURE once num_failures_required
	## have failed (or, without repeat, when all are done and neither count was reached). With repeat, finished
	## children run again.
	var num_successes_required := 1
	var num_failures_required := 1
	var repeat := false

	func _init(kids: Array = [], successes: int = 1, failures: int = 1, p_repeat: bool = false, p_name: String = "") -> void:
		super(kids, p_name)
		num_successes_required = successes
		num_failures_required = failures
		repeat = p_repeat

	func _tick(delta: float) -> int:
		var ok := 0
		var bad := 0
		var out := RUNNING
		for c in children:
			var st: int
			if not repeat and (c.status == FAILURE or c.status == SUCCESS):
				st = c.status
			else:
				st = c.execute(delta)
			if st == FAILURE:
				bad += 1
				if bad >= num_failures_required and out == RUNNING:
					out = FAILURE
			elif st == SUCCESS:
				ok += 1
				if ok >= num_successes_required and out == RUNNING:
					out = SUCCESS
		if not repeat and ok + bad == children.size() and out == RUNNING:
			out = FAILURE
		return out

	func _exit() -> void:
		for c in children:
			if c.status == RUNNING:
				c.abort()

	func _generate_name() -> String:
		return "Parallel"


# ------------------------------------------------------------------ decorators

class Decorator extends Task:
	func _child():
		return children[0]

	func _generate_name() -> String:
		return "Decorator"


class Invert extends Decorator:
	func _init(child) -> void:
		add_child(child)

	func _tick(delta: float) -> int:
		var st: int = children[0].execute(delta)
		return SUCCESS if st == FAILURE else (FAILURE if st == SUCCESS else st)

	func _generate_name() -> String:
		return "Invert"


class AlwaysSucceed extends Decorator:
	func _init(child) -> void:
		add_child(child)

	func _tick(delta: float) -> int:
		return RUNNING if children[0].execute(delta) == RUNNING else SUCCESS

	func _generate_name() -> String:
		return "AlwaysSucceed"


class AlwaysFail extends Decorator:
	func _init(child) -> void:
		add_child(child)

	func _tick(delta: float) -> int:
		return RUNNING if children[0].execute(delta) == RUNNING else FAILURE

	func _generate_name() -> String:
		return "AlwaysFail"


class Cooldown extends Decorator:
	## After the child succeeds (or fails, with trigger_on_failure) it is not run again for duration seconds: the
	## decorator fails meanwhile. Measured on clock (a Callable -> seconds), by default the real time.
	var duration := 1.0
	var trigger_on_failure := false
	var clock := Callable()
	var _ready_at := -INF

	func _init(child, p_duration: float, p_trigger_on_failure: bool = false, start_cooled: bool = false, p_clock: Callable = Callable()) -> void:
		add_child(child)
		duration = p_duration
		trigger_on_failure = p_trigger_on_failure
		clock = p_clock
		if start_cooled:
			_ready_at = _now() + duration

	func _now() -> float:
		return float(clock.call()) if clock.is_valid() else Time.get_ticks_msec() / 1000.0

	func _tick(delta: float) -> int:
		if _now() < _ready_at:
			return FAILURE
		var st: int = children[0].execute(delta)
		if st == SUCCESS or (trigger_on_failure and st == FAILURE):
			_ready_at = _now() + duration
		return st

	func _generate_name() -> String:
		return "Cooldown %.1fs" % duration


class TimeLimit extends Decorator:
	## The child has limit seconds of running; past that it is aborted and this fails.
	var limit := 1.0

	func _init(child, p_limit: float) -> void:
		add_child(child)
		limit = p_limit

	func _tick(delta: float) -> int:
		if elapsed <= limit:
			return children[0].execute(delta)
		children[0].abort()
		return FAILURE

	func _generate_name() -> String:
		return "TimeLimit %.1fs" % limit


class Repeat extends Decorator:
	## The child times times in a row (a run per tick); with abort_on_failure a failure ends it as FAILURE.
	var times := 1
	var abort_on_failure := false
	var _done := 0

	func _init(child, p_times: int, p_abort_on_failure: bool = false) -> void:
		add_child(child)
		times = p_times
		abort_on_failure = p_abort_on_failure

	func _enter() -> void:
		_done = 0

	func _tick(delta: float) -> int:
		var st: int = children[0].execute(delta)
		if st == RUNNING:
			return RUNNING
		if st == FAILURE and abort_on_failure:
			return FAILURE
		_done += 1
		return SUCCESS if _done >= times else RUNNING

	func _generate_name() -> String:
		return "Repeat x%d" % times


class RepeatUntilFailure extends Decorator:
	func _init(child) -> void:
		add_child(child)

	func _tick(delta: float) -> int:
		return SUCCESS if children[0].execute(delta) == FAILURE else RUNNING

	func _generate_name() -> String:
		return "RepeatUntilFailure"


class Probability extends Decorator:
	## Runs the child with chance p (decided when it is entered); otherwise fails.
	var p := 0.5
	var rng: RandomNumberGenerator = null
	var _go := false

	func _init(child, p_p: float, p_rng: RandomNumberGenerator = null) -> void:
		add_child(child)
		p = p_p
		rng = p_rng

	func _enter() -> void:
		_go = (rng.randf() if rng != null else randf()) < p

	func _tick(delta: float) -> int:
		return children[0].execute(delta) if _go else FAILURE

	func _generate_name() -> String:
		return "Probability %.2f" % p


class Delay extends Decorator:
	## Waits seconds, then runs the child.
	var seconds := 1.0

	func _init(child, p_seconds: float) -> void:
		add_child(child)
		seconds = p_seconds

	func _tick(delta: float) -> int:
		if elapsed < seconds:
			return RUNNING
		return children[0].execute(delta)

	func _generate_name() -> String:
		return "Delay %.1fs" % seconds


# ------------------------------------------------------------------ leaves

class Condition extends Task:
	## fn() -> bool: SUCCESS when true.
	var fn := Callable()

	func _init(p_fn: Callable, p_name: String = "") -> void:
		fn = p_fn
		custom_name = p_name

	func _tick(_delta: float) -> int:
		return SUCCESS if bool(fn.call()) else FAILURE

	func _generate_name() -> String:
		return "Condition"


class Action extends Task:
	## fn(delta) -> status, with optional on_enter() / on_exit() (the exit also runs when the action is aborted).
	var fn := Callable()
	var on_enter := Callable()
	var on_exit := Callable()

	func _init(p_fn: Callable, p_name: String = "", p_on_enter: Callable = Callable(), p_on_exit: Callable = Callable()) -> void:
		fn = p_fn
		custom_name = p_name
		on_enter = p_on_enter
		on_exit = p_on_exit

	func _enter() -> void:
		if on_enter.is_valid():
			on_enter.call()

	func _exit() -> void:
		if on_exit.is_valid():
			on_exit.call()

	func _tick(delta: float) -> int:
		return int(fn.call(delta))

	func _generate_name() -> String:
		return "Action"


class Wait extends Task:
	var seconds := 1.0

	func _init(p_seconds: float, p_name: String = "") -> void:
		seconds = p_seconds
		custom_name = p_name

	func _tick(_delta: float) -> int:
		return SUCCESS if elapsed >= seconds else RUNNING

	func _generate_name() -> String:
		return "Wait %.1fs" % seconds


class SetVar extends Task:
	var var_name := &""
	var value = null

	func _init(p_var: StringName, p_value) -> void:
		var_name = p_var
		value = p_value

	func _tick(_delta: float) -> int:
		blackboard.set_var(var_name, value)
		return SUCCESS

	func _generate_name() -> String:
		return "Set %s" % var_name


class CheckVar extends Task:
	var var_name := &""
	var value = null

	func _init(p_var: StringName, p_value) -> void:
		var_name = p_var
		value = p_value

	func _tick(_delta: float) -> int:
		return SUCCESS if blackboard.get_var(var_name) == value else FAILURE

	func _generate_name() -> String:
		return "Check %s" % var_name
