extends Node
## Graphics > Monitor check (r14): for every display and every window mode, choose it the way the settings page does
## (Settings.set_value, nothing saved) and report which display the window ends up on.
##   godot --path game res://tools/monitor_check.tscn


func _ready() -> void:
	var n := DisplayServer.get_screen_count()
	print("[monitor] %d display(s), primary %d" % [n, DisplayServer.get_primary_screen()])
	for i in n:
		print("[monitor]   display %d at %s, %s" % [i, str(DisplayServer.screen_get_position(i)), str(DisplayServer.screen_get_size(i))])
	var ok := true
	for mode in ["borderless", "fullscreen", "windowed"]:
		for m in range(-1, n):
			Settings.set_value("graphics", "monitor", m)
			Settings.set_value("graphics", "window_mode", mode)
			for k in 30:
				await get_tree().process_frame
			var want: int = Settings.monitor()
			var got := DisplayServer.window_get_current_screen()
			var good := got == want
			ok = ok and good
			print("[monitor] %s, monitor %d -> on display %d (want %d), window mode %d, at %s size %s %s" % [mode, m, got, want,
				DisplayServer.window_get_mode(), str(DisplayServer.window_get_position()), str(DisplayServer.window_get_size()), "ok" if good else "WRONG"])
	Settings.set_value("graphics", "monitor", -1)
	Settings.set_value("graphics", "window_mode", "windowed")
	print("[monitor] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
