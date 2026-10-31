extends RefCounted
## LimboAI's Blackboard (blackboard/blackboard.h) in GDScript: named variables shared by the tasks and states of an
## agent, with an optional parent scope. A bot's own blackboard has its team's as parent (BotTeam.board), so a bot reads
## what the team knows (its intel callout) the same way it reads what it knows itself.
##
## Lookups climb the scopes: get_var/has_var find the nearest scope that has the variable; set_var writes to the scope
## that already has it, else creates it here (LimboAI's rule for a variable not declared by a plan).

var vars := {}
var _parent = null


func _init(parent = null) -> void:
	_parent = parent


func get_parent():
	return _parent


func set_parent(parent) -> void:
	_parent = parent


func top():
	## The outermost scope.
	var bb = self
	while bb._parent != null:
		bb = bb._parent
	return bb


func get_var(var_name: StringName, default = null):
	var bb = self
	while bb != null:
		if bb.vars.has(var_name):
			return bb.vars[var_name]
		bb = bb._parent
	return default


func set_var(var_name: StringName, value) -> void:
	var bb = self
	while bb != null:
		if bb.vars.has(var_name):
			bb.vars[var_name] = value
			return
		bb = bb._parent
	vars[var_name] = value


func has_var(var_name: StringName) -> bool:
	var bb = self
	while bb != null:
		if bb.vars.has(var_name):
			return true
		bb = bb._parent
	return false


func erase_var(var_name: StringName) -> void:
	## Only from this scope (like LimboAI).
	vars.erase(var_name)


func clear() -> void:
	vars.clear()
