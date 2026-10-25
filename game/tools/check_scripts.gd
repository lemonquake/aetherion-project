extends Node
## Loads every script under res://src and res://tools and reports which fail to compile.
##   godot --headless --path game res://tools/check_scripts.tscn


func _ready() -> void:
	var files := []
	_walk("res://src", files)
	_walk("res://tools", files)
	var bad := 0
	for f in files:
		var s = load(f)
		if s == null or (s is GDScript and not s.can_instantiate() and not (s as GDScript).is_abstract()):
			print("FAIL ", f)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)


func _walk(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_walk(dir + "/" + sub, out)
