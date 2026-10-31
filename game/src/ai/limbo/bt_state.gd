extends "res://src/ai/limbo/limbo_state.gd"
## LimboAI's BTState (bt/bt_state.h) in GDScript: a state that runs a behaviour tree. Each update ticks the tree; when the
## tree ends it dispatches success_event or failure_event to the machine (default "finished" / "failed"), and if the
## state is still active the tree starts over on the next update. Leaving the state aborts the tree.

var tree = null
var success_event := &"finished"
var failure_event := &"failed"
var last_status := 0


func _init(p_name: String, root_task, p_success_event: StringName = &"finished", p_failure_event: StringName = &"failed") -> void:
	super(p_name)
	tree = root_task
	success_event = p_success_event
	failure_event = p_failure_event


func _setup() -> void:
	tree.initialize(agent, blackboard)


func _exit() -> void:
	tree.abort()


func _update(delta: float) -> void:
	var st: int = tree.execute(delta)
	last_status = st
	if st == tree.SUCCESS:
		dispatch(success_event)
	elif st == tree.FAILURE:
		dispatch(failure_event)


func running_path() -> String:
	return tree.running_path()
