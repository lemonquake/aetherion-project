extends SceneTree
## Measures how long the map layout takes to build (masks and lookup tables).
func _init():
	var Layout = load("res://src/world/layout.gd")
	var t0 := Time.get_ticks_msec()
	var L = Layout.new(1729)
	print("layout build ms: ", Time.get_ticks_msec() - t0)
	t0 = Time.get_ticks_msec()
	var s := 0.0
	for i in 100000:
		s += L.ground_height(randf_range(-500, 500), randf_range(-500, 500))
	print("100k ground_height ms: ", Time.get_ticks_msec() - t0)
	var w := 0
	for iz in 100:
		for ix in 100:
			if L.is_water(-500 + ix * 10, -500 + iz * 10): w += 1
	print("water fraction: ", w / 10000.0)
	quit()
