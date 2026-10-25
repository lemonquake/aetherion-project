extends Node3D
## Builds the map and saves screenshots from fixed viewpoints. Run with a window (needs the GPU):
##   godot --path game res://tools/map_preview.tscn -- --out=<dir> [--views=a,b] [--bright] [--size=1600x900]

const MapBuilder := preload("res://src/world/map_builder.gd")

var is_server := false
var map = null
var out_dir := "user://preview"
var views := []
var bright := false
var cam: Camera3D

const VIEWS := {
	"overview": [Vector3(140, 160, 260), Vector3(-20, 0, -120)],
	"west_bank": [Vector3(-60, 90, -120), Vector3(-200, 0, -280)],
	"looban_alley": ["street", Vector2(-118, -262), 0.0],
	"looban_alley2": ["street", Vector2(-160, -300), 1.6],
	"river_boardwalk": ["river", -40.0, -1.0],
	"river_east": ["river", 120.0, 1.0],
	"estero": ["estero", -300.0],
	"bridge": [Vector3(-10, 3.2, -205), Vector3(60, 2.0, -190)],
	"rail": [Vector3(-160, 2.6, -432), Vector3(0, 2.0, -440)],
	"market": [Vector3(100, 2.2, -175), Vector3(124, 2.0, -146)],
	"looban_east": ["street", Vector2(300, -24), 0.8],
	"fishing": [Vector3(-330, 3.0, 340), Vector3(-330, 1.0, 420)],
}


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true
	get_tree().create_timer(float(args.get("timeout", 400))).timeout.connect(func(): print("[preview] watchdog timeout"); get_tree().quit(2))
	out_dir = str(args.get("out", out_dir))
	bright = args.has("bright")
	views = str(args.get("views", ",".join(VIEWS.keys()))).split(",")
	var size := str(args.get("size", "1600x900")).split("x")
	get_window().size = Vector2i(int(size[0]), int(size[1]))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var t0 := Time.get_ticks_msec()
	map = MapBuilder.new()
	map.build(self, int(args.get("seed", 1729)), 1)
	var build_ms := Time.get_ticks_msec() - t0
	print("[preview] map built in %d ms: %s" % [build_ms, JSON.stringify(map.stats)])
	if bright:
		map.lighting.env.ambient_light_energy = 6.0
		map.lighting.moon.light_energy = 1.4
	cam = Camera3D.new()
	cam.far = 2000.0
	cam.fov = 75.0
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	for v in views:
		if not VIEWS.has(v):
			continue
		_place(VIEWS[v])
		for i in 45:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s%s.png" % [out_dir, v, "_bright" if bright else ""]
		img.save_png(path)
		print("[preview] saved ", path, " fps ", Engine.get_frames_per_second())
	get_tree().quit()


func _place(spec: Array) -> void:
	if spec[0] is Vector3:
		cam.global_position = spec[0]
		cam.look_at(spec[1], Vector3.UP)
		return
	var L = map.layout
	match str(spec[0]):
		"street":
			var p := _open_spot(spec[1])
			var y: float = _floor_y(p)
			cam.global_position = Vector3(p.x, y + 1.65, p.y)
			cam.rotation = Vector3(-0.05, float(spec[2]), 0)
		"river":
			var z := float(spec[1])
			var side := float(spec[2])
			var x: float = L.river_x(z) + side * (L.river_hw(z) - 0.6)
			cam.global_position = Vector3(x, L.WATER_Y + 1.55 + 1.65, z)
			cam.look_at(Vector3(L.river_x(z + 40.0) + side * (L.river_hw(z + 40.0) - 0.6), L.WATER_Y + 3.0, z + 40.0), Vector3.UP)
		"estero":
			var x2 := float(spec[1])
			var z2: float = L.estero_z(x2) + L.estero_w * 0.5 + 0.7
			cam.global_position = Vector3(x2, L.WATER_Y + 1.5 + 1.65, z2)
			cam.look_at(Vector3(x2 + 30.0, L.WATER_Y + 2.5, L.estero_z(x2 + 30.0) + L.estero_w * 0.5 + 0.7), Vector3.UP)


func _floor_y(p: Vector2) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 60, p.y), Vector3(p.x, -10, p.y))
	var r := space.intersect_ray(q)
	return r.position.y if not r.is_empty() else 1.0


func _open_spot(c: Vector2) -> Vector2:
	## Nearest point with open sky and walkable ground (an alley), searching outward.
	var space := get_world_3d().direct_space_state
	for ring in 40:
		for k in 16:
			var a := k * TAU / 16.0
			var p := c + Vector2(cos(a), sin(a)) * ring * 0.8
			var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40, p.y), Vector3(p.x, -10, p.y))
			var r := space.intersect_ray(q)
			if r.is_empty():
				continue
			if absf(r.position.y - map.layout.ground_height(p.x, p.y)) < 0.4 and not map.layout.is_water(p.x, p.y):
				return p
	return c
