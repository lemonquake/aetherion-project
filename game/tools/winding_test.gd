extends Node3D
## Renders one GeoSink box and one quad from fixed sides and prints whether each face is visible (front-face check).
const Materials := preload("res://src/world/materials.gd")
const GeoSink := preload("res://src/world/geo_sink.gd")

func _ready() -> void:
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(2))
	var mats := Materials.new()
	var sink := GeoSink.new(mats, self)
	sink.box(Transform3D(Basis(), Vector3(0, 0, 0)), Vector3(1, 1, 1), "plywood", {"collide": false})
	sink.quad(Vector3(5, 0, 0), Vector3(6, 0, 0), Vector3(6, 0, -1), Vector3(5, 0, -1), "plywood", {})
	sink.quad(Vector3(8, 0, -1), Vector3(9, 0, -1), Vector3(9, 0, 0), Vector3(8, 0, 0), "plywood", {})
	sink.finish()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(1, 0, 1)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 2.0
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for spec in [["+X", Vector3(3, 0, 0), Vector3.ZERO], ["-X", Vector3(-3, 0, 0), Vector3.ZERO], ["+Y", Vector3(0.01, 3, 0), Vector3.ZERO],
			["+Z", Vector3(0, 0, 3), Vector3.ZERO], ["-Z", Vector3(0, 0, -3), Vector3.ZERO], ["quad_top", Vector3(5.5, 3, -0.49), Vector3(5.5, 0, -0.5)], ["quad2_top", Vector3(8.5, 3, -0.49), Vector3(8.5, 0, -0.5)]]:
		cam.global_position = spec[1]
		cam.look_at(spec[2], Vector3.UP if spec[0] != "+Y" and spec[0] != "quad_top" and spec[0] != "quad2_top" else Vector3.FORWARD)
		for i in 5:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var c := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		print("view ", spec[0], " centre pixel ", c, " -> ", "MAGENTA (culled/missing)" if c.r > 0.9 and c.b > 0.9 and c.g < 0.2 else "visible")
	get_tree().quit()
