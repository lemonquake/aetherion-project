extends "res://src/ai/limbo/limbo_state.gd"
## LimboAI's LimboHSM (hsm/limbo_hsm.h) in GDScript: a hierarchical state machine. Its child states (LimboState,
## BTState, or LimboHSM for a nested machine) are added with add_child_state(); one of them is active while the machine
## is. Transitions are declared up front, one per (from state, event):
##
##   hsm.add_transition(idle, chase, &"seen")             # from idle on "seen"
##   hsm.add_transition(hsm.ANYSTATE, flee, &"hurt", guard) # from any state (never into itself), if guard() says so
##
## dispatch(event) sends an event to the root, which offers it to the deepest active machine first, then to each
## machine up the chain: a machine consumes it through a handler of its own or a transition out of its active state
## (that state's own transitions before ANYSTATE ones; the target state's guard must allow it too). A transition
## asked for while the root is updating is applied when that update ends (as in LimboAI); otherwise at once.
## The root is driven with initialize(agent, blackboard), set_active(true), then update(delta) as often as wanted.
## An unhandled "finished" event at the root ends the machine (set_active(false)), as in LimboAI.

const ANYSTATE = null

var initial_state = null
var states: Array = []
var active_state = null
var previous_active = null
var _trans := {}            # event -> {from state (or &"*" for any): [to state, guard Callable]}
var _updating := false
var _next_active = null


func _init(p_name: String = "") -> void:
	super(p_name)


func add_child_state(s):
	s._hsm_ref = weakref(self)
	states.append(s)
	if initial_state == null:
		initial_state = s
	return s


func add_transition(from_state, to_state, event: StringName, guard: Callable = Callable()) -> void:
	assert(to_state != null and states.has(to_state), "LimboHSM: a transition must lead to a child state")
	assert(from_state == ANYSTATE or states.has(from_state), "LimboHSM: a transition must start from a child state")
	if not _trans.has(event):
		_trans[event] = {}
	_trans[event][&"*" if from_state == ANYSTATE else from_state] = [to_state, guard]


func initialize(p_agent, p_blackboard) -> void:
	## On the root only, once: every state gets the agent and blackboard, then its _setup().
	_initialize(p_agent, p_blackboard)


func _initialize(p_agent, p_blackboard) -> void:
	assert(not states.is_empty(), "LimboHSM: no states")
	if initial_state == null:
		initial_state = states[0]
	agent = p_agent
	blackboard = p_blackboard
	for s in states:
		s._initialize(p_agent, p_blackboard)
	_setup()


func set_active(on: bool) -> void:
	if on == active:
		return
	if on:
		enter_state()
	else:
		exit_state()


func enter_state() -> void:
	if active:
		return
	super()
	_change_active_state(initial_state)


func exit_state() -> void:
	if not active:
		return
	_change_active_state(null)
	super()


func update(delta: float) -> void:
	## The root's tick: updates the machine (its own callbacks, then the active chain down), then applies a transition
	## dispatched meanwhile.
	_updating = true
	update_state(delta)
	_updating = false
	if _next_active != null:
		var to = _next_active
		_next_active = null
		_change_active_state(to)


func update_state(delta: float) -> void:
	if not active:
		return
	var last = active_state
	super(delta)
	if active_state != null and last == active_state:
		active_state.update_state(delta)


func change_active_state(s) -> void:
	assert(states.has(s), "LimboHSM: not a child state")
	_change_active_state(s)


func _change_active_state(s) -> void:
	if active_state != null:
		active_state.exit_state()
	previous_active = active_state
	active_state = s
	if active_state != null:
		active_state.enter_state()


func get_active_state():
	return active_state


func get_previous_active_state():
	return previous_active


func get_leaf_state():
	## The deepest active state (this machine when nothing is active).
	var s = active_state
	if s == null:
		return self
	while s.has_method("get_leaf_state") and s.active_state != null:
		s = s.active_state
	return s


func active_path() -> String:
	## "bot/play/..." from this machine down the active chain (for logs).
	var out := name
	var s = active_state
	while s != null:
		out += "/" + s.name
		s = s.active_state if s.has_method("get_leaf_state") else null
	return out


func _dispatch(event: StringName, cargo = null) -> bool:
	var consumed := false
	if active_state != null:
		consumed = active_state._dispatch(event, cargo)
	if not consumed:
		consumed = super(event, cargo)
	if not consumed and active_state != null:
		var by = _trans.get(event)
		if by != null:
			var to = null
			var t = by.get(active_state)
			if t != null and (not (t[1] as Callable).is_valid() or bool((t[1] as Callable).call())):
				to = t[0]
			if to == null:
				t = by.get(&"*")
				if t != null and t[0] != active_state and (not (t[1] as Callable).is_valid() or bool((t[1] as Callable).call())):
					to = t[0]
			if to != null and to._allows():
				if not _updating:
					_change_active_state(to)
				elif _next_active == null:
					_next_active = to
				consumed = true
	if not consumed and event == EVENT_FINISHED and get_hsm() == null:
		set_active(false)
	return consumed
