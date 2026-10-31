extends RefCounted
## LimboAI's LimboState (hsm/limbo_state.h) in GDScript: one state of a hierarchical state machine (limbo_hsm.gd). It is
## entered and exited by its machine and updated every time the machine is, while active. Behaviour goes in the
## virtuals _setup(), _enter(), _exit(), _update(delta), or in callables (call_on_enter / call_on_exit / call_on_update,
## which return the state, for chaining). dispatch(event) asks the machine to change state: the event goes to the root
## and down to the deepest active machine first (limbo_hsm.gd). A guard (set_guard) can refuse a transition into this
## state. add_event_handler(event, c) lets a state consume an event itself (c returns true when it did).

const EVENT_FINISHED := &"finished"

var name := ""
var _hsm_ref: WeakRef = null   # the machine this state belongs to (weak: the machine holds its states)
var agent = null
var blackboard = null
var active := false
var _on_enter := Callable()
var _on_exit := Callable()
var _on_update := Callable()
var _guard := Callable()
var _handlers := {}


func _init(p_name: String = "") -> void:
	name = p_name


func call_on_enter(c: Callable):
	_on_enter = c
	return self


func call_on_exit(c: Callable):
	_on_exit = c
	return self


func call_on_update(c: Callable):
	## c(delta)
	_on_update = c
	return self


func set_guard(c: Callable):
	_guard = c
	return self


func add_event_handler(event: StringName, c: Callable):
	_handlers[event] = c
	return self


func is_active() -> bool:
	return active


func get_hsm():
	## The machine this state belongs to, or null (the root).
	return _hsm_ref.get_ref() if _hsm_ref != null else null


func get_root():
	var s = self
	var up = get_hsm()
	while up != null:
		s = up
		up = s.get_hsm()
	return s


func dispatch(event: StringName, cargo = null) -> bool:
	return get_root()._dispatch(event, cargo)


# ------------------------------------------------------------------ the machine's side (LimboAI's native half)

func _initialize(p_agent, p_blackboard) -> void:
	agent = p_agent
	blackboard = p_blackboard
	_setup()


func enter_state() -> void:
	if active:
		return
	active = true
	_enter()
	if _on_enter.is_valid():
		_on_enter.call()


func exit_state() -> void:
	if not active:
		return
	_exit()
	if _on_exit.is_valid():
		_on_exit.call()
	active = false


func update_state(delta: float) -> void:
	_update(delta)
	if _on_update.is_valid():
		_on_update.call(delta)


func _dispatch(event: StringName, cargo = null) -> bool:
	if _handlers.has(event):
		var c: Callable = _handlers[event]
		return bool(c.call() if cargo == null else c.call(cargo))
	return false


func _allows() -> bool:
	return not _guard.is_valid() or bool(_guard.call())


# ------------------------------------------------------------------ virtuals

func _setup() -> void:
	pass


func _enter() -> void:
	pass


func _exit() -> void:
	pass


func _update(_delta: float) -> void:
	pass
