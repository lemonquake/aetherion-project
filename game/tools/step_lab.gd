extends Node3D
## Step-up lab: a character runs at ledges of rising height from several angles and gaits; prints which ones it gets
## on top of without jumping. Run with a window or headless:
##   godot --headless --path game res://tools/step_lab.tscn [-- --heights=0.1,0.2 --angles=0,40 --gaits=run]

var world = null  # Character looks for world.water_height / world.map; nothing here
var _results := []


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true
	var heights: Array = Array(str(args.get("heights", "0.06,0.1,0.15,0.18,0.22,0.26,0.3,0.34,0.38,0.42,0.46,0.5,0.55")).split(",")).map(func(s): return float(s))
	var angles: Array = Array(str(args.get("angles", "0,35,65")).split(",")).map(func(s): return float(s))
	var gaits: Array = Array(str(args.get("gaits", "walk,run,sprint,crouch")).split(","))
	var floor_body := _box(Vector3(0, -0.5, 0), Vector3(400, 1, 400))
	add_child(floor_body)
	await get_tree().physics_frame
	var summary := {}
	for h in heights:
		for ang in angles:
			for g in gaits:
				var ok: bool = await _trial(float(h), deg_to_rad(float(ang)), str(g))
				_results.append([h, ang, g, ok])
				var k := "%.2f" % float(h)
				if not summary.has(k):
					summary[k] = []
				summary[k].append("%s@%d:%s" % [g, int(ang), "ok" if ok else "BLOCKED"])
	for k in summary:
		print("[step] %s m  %s" % [k, "  ".join(summary[k])])
	get_tree().quit()


func _box(c: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = Defs.PHYS_WORLD
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	b.position = c
	return b


func _trial(h: float, ang: float, gait: String) -> bool:
	# A ledge 6 m wide and 4 m deep whose near face is the plane z = 0, approached at angle ang off its normal.
	var ledge := _box(Vector3(0, h * 0.5 - 0.5 * 0.0, -2.0), Vector3(6.0, h, 4.0))
	ledge.position.y = h * 0.5
	add_child(ledge)
	var ch := Character.new()
	ch.mode = Motor.GROUND
	add_child(ch)
	var dir := Vector3(sin(ang), 0, -cos(ang))
	ch.global_position = Vector3(0, 0.02, 0) - dir * 2.2
	ch.yaw = atan2(-dir.x, -dir.z)
	await get_tree().physics_frame
	var btn := 0
	match gait:
		"walk":
			btn = Motor.B_WALK
		"sprint":
			btn = Motor.B_SPRINT
		"crouch":
			btn = Motor.B_CROUCH
	var on_top := false
	for i in 120:
		await get_tree().physics_frame
		Motor.step(ch, {"seq": i, "mx": 0.0, "my": 1.0, "yaw": ch.yaw, "pitch": 0.0, "btn": btn, "slot": 0}, 1.0 / 60.0)
		var p := ch.global_position
		if OS.get_cmdline_user_args().has("--debug") and i % 6 == 0:
			var ns := []
			for k in ch.get_slide_collision_count():
				ns.append(str(ch.get_slide_collision(k).get_normal().snapped(Vector3.ONE * 0.01)))
			print("  t%d pos %s vel %s floor %s cols %s" % [i, str(p.snapped(Vector3.ONE * 0.01)), str(ch.velocity.snapped(Vector3.ONE * 0.01)), str(ch.is_on_floor()), ", ".join(ns)])
		if p.y > h - 0.03 and p.z < -0.35 and ch.is_on_floor():
			on_top = true
			break
	ch.queue_free()
	ledge.queue_free()
	await get_tree().physics_frame
	return on_top
