extends RefCounted
## LimboAI's BTTask (bt/tasks/bt_task.h) in GDScript: the base of every behaviour-tree task. A task is ticked with
## execute(delta) and answers RUNNING, SUCCESS or FAILURE. Entering (from any status but RUNNING) resets its children and
## calls _enter(); finishing calls _exit(); abort() stops a RUNNING task and its children and makes them FRESH again.
## elapsed counts the seconds a task has been RUNNING (the first tick of a run adds nothing, as in LimboAI).
##
## Children are held by their parent; nothing points back up (RefCounted cycles are never freed), so a tree whose
## agent dies goes with it. Leaves should call methods (Callables of an object), not lambdas that capture their owner.
##
## No class_name (the project loads scripts by path): extend it with
##   extends "res://src/ai/limbo/bt_task.gd"
## and override _setup(), _enter(), _exit(), _tick(delta) -> int and _generate_name().

const FRESH := 0
const RUNNING := 1
const FAILURE := 2
const SUCCESS := 3
const STATUS_NAMES := ["FRESH", "RUNNING", "FAILURE", "SUCCESS"]

var agent = null
var blackboard = null
var children: Array = []
var status := FRESH
var elapsed := 0.0
var custom_name := ""


func initialize(p_agent, p_blackboard) -> void:
	## Once, before the first tick: the agent and blackboard for the whole tree, then _setup() bottom-up.
	agent = p_agent
	blackboard = p_blackboard
	for c in children:
		c.initialize(p_agent, p_blackboard)
	_setup()


func execute(delta: float) -> int:
	if status != RUNNING:
		if status != FRESH:
			for c in children:
				c.abort()
		_enter()
	else:
		elapsed += delta
	status = _tick(delta)
	if status != RUNNING:
		_exit()
		elapsed = 0.0
	return status


func abort() -> void:
	for c in children:
		c.abort()
	if status == RUNNING:
		_exit()
	status = FRESH
	elapsed = 0.0


func add_child(task):
	children.append(task)
	return task


func get_child(i: int):
	return children[i]


func get_child_count() -> int:
	return children.size()


func get_task_name() -> String:
	return custom_name if custom_name != "" else _generate_name()


func get_status() -> int:
	return status


func running_path() -> String:
	## The names of the RUNNING chain from this task down ("objective/role/sniper/on the way"), "" when not running.
	if status != RUNNING:
		return ""
	var s := get_task_name()
	for c in children:
		if c.status == RUNNING:
			return s + "/" + c.running_path()
	return s


func print_tree(depth: int = 0) -> String:
	var s: String = "  ".repeat(depth) + get_task_name() + " [" + str(STATUS_NAMES[status]) + "]\n"
	for c in children:
		s += c.print_tree(depth + 1)
	return s


# ------------------------------------------------------------------ virtuals

func _setup() -> void:
	pass


func _enter() -> void:
	pass


func _exit() -> void:
	pass


func _tick(_delta: float) -> int:
	return SUCCESS


func _generate_name() -> String:
	return "Task"
