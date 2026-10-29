extends Node
## Shows the loading screen alone for a capture: godot --path game res://tools/loading_preview.tscn -- --out=<png> [--sync]

func _ready() -> void:
	if "--host" in OS.get_cmdline_user_args():
		Net.host(27499)
	if "--lobby" in OS.get_cmdline_user_args():
		Game.show_lobby()
		await get_tree().create_timer(1.5).timeout
		if not "--keep" in OS.get_cmdline_user_args():
			Game.show_screen(null)
	var ls = load("res://src/ui/loading_screen.gd").new("Lawless Sub", "Deathmatch · 10 a side")
	Game.loading_screen = ls
	Game.add_child(ls)
	var out := "user://loading_preview.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	if "--sync" in OS.get_cmdline_user_args():
		if "--late" in OS.get_cmdline_user_args() and not "--keep" in OS.get_cmdline_user_args():
			await get_tree().create_timer(1.0).timeout
		if "--keep" in OS.get_cmdline_user_args():
			Game.show_screen(null)   # queued for deletion, still in the tree during the loop
		if "--world" in OS.get_cmdline_user_args():
			var w := Node3D.new()
			Game.add_child(w)
			var cam := Camera3D.new()
			w.add_child(cam)
		ls.sync = true
		var t0 := Time.get_ticks_msec()
		var f := 0.0
		while Time.get_ticks_msec() - t0 < 2500:
			f += 0.0005
			ls.progress(minf(f, 0.62), "Building houses (%d of 256)" % int(f * 256))
			OS.delay_usec(2000)
		get_viewport().get_texture().get_image().save_png(out)
		print("[preview] sync shot ", out)
		get_tree().quit()
		return
	ls.progress(0.62, "Building houses (159 of 256)")
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("[preview] shot ", out)
	get_tree().quit()
