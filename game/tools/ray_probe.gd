extends Node3D
## Collision probe: builds a map and casts rays straight down over a rectangle, printing the hit height and what it
## hit (collider class, its "what"/"mat" meta). Headless:
##   godot --headless --path game res://tools/ray_probe.tscn -- --map=lawless_sub --rect=-90,-6,-76,6 --step=1

const MapBuilder := preload("res://src/world/map_builder.gd")

var is_server := false
var match_info := {}
var characters := {}
var map = null


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true
	map = MapBuilder.new()
	map.build(self, int(args.get("seed", 1729)), 1, {"map": str(args.get("map", "kalinaw"))})
	await get_tree().physics_frame
	await get_tree().physics_frame
	var r := str(args.get("rect", "-90,-6,-76,6")).split(",")
	var step := float(args.get("step", 1.0))
	var space := get_world_3d().direct_space_state
	var z := float(r[1])
	while z <= float(r[3]) + 0.001:
		var row := []
		var x := float(r[0])
		while x <= float(r[2]) + 0.001:
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, float(args.get("top", 30.0)), z), Vector3(x, -10, z), Defs.MOVE_MASK)
			var h := space.intersect_ray(q)
			if h.is_empty():
				row.append("  none")
			else:
				var c = h.collider
				var tag := str(c.get_meta("what", c.get_meta("mat", c.get_class()))) if c else "?"
				row.append("%6.2f:%s" % [(h.position as Vector3).y, tag.substr(0, 10)])
			x += step
		print("[probe] z=%6.1f  %s" % [z, " ".join(row)])
		z += step
	get_tree().quit()
