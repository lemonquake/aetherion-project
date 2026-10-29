extends Node
## --ui_tour=<dir> [--ui_sizes=1920x1080,3840x2160]: captures every menu page, a hosted lobby and the Locker at each
## window size, then quits. With --mobile it is the phone layout (UI drawn 1.5x). Prints "[ui] shot <path>" lines and
## "[ui] PASS|FAIL <check>" for controls that fall outside the screen.

var out := ""


func _ready() -> void:
	out = str(Game.arg("ui_tour"))
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	var sizes: Array = str(Game.arg("ui_sizes", "1920x1080")).split(",")
	var fails := 0
	for s in sizes:
		var wh := (s as String).split("x")
		var ws := Vector2i(int(wh[0]), int(wh[1]))
		get_window().size = ws
		await _frames(20)
		var tag := "%s%s" % [s, "_mobile" if Settings.is_mobile() else ""]
		Game.show_menu()
		await _frames(10)
		var menu = Game.screen
		for page in ["home", "play", "locker", "profile", "leaderboard"]:
			menu._show(page)
			await _wait(1.2 if page == "locker" else 0.5)
			await _shot("%s_menu_%s" % [tag, page])
			fails += _check_bounds(Game.screen, "%s menu %s" % [tag, page])
		Net.host()
		Net.set_config("name", "Tour lobby")
		Game.show_lobby()
		await _wait(0.6)
		await _shot("%s_lobby" % tag)
		fails += _check_bounds(Game.screen, "%s lobby" % tag)
		Game.screen._open_locker()
		await _wait(1.2)
		await _shot("%s_lobby_locker" % tag)
		Game.leave_to_menu()
		await _wait(0.3)
	print("[ui] done, %d layout problems" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _check_bounds(root: Control, where: String) -> int:
	## Buttons and inputs that end up partly off screen (clipped) are layout failures.
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var bad := []
	for c in _controls(root):
		if not c.is_visible_in_tree() or not (c is BaseButton or c is LineEdit):
			continue
		var r: Rect2 = c.get_global_rect()
		if r.size.x < 2 or r.size.y < 2:
			continue
		var clip := _clipper(c)
		if clip:
			# Inside a scroll area only what the area shows counts (the rest is scrolled, not clipped).
			if not clip.get_global_rect().intersects(r):
				continue
			r = clip.get_global_rect().intersection(r)
		if r.position.x < -1 or r.position.y < -1 or r.end.x > vs.x + 1 or r.end.y > vs.y + 1:
			bad.append("%s at %s" % [str(c.get("text") if c.get("text") else c.name), str(r)])
	print("[ui] %s %s: %s" % ["PASS" if bad.is_empty() else "FAIL", where, "all controls on screen" if bad.is_empty() else "; ".join(bad.slice(0, 6))])
	return 0 if bad.is_empty() else 1


func _clipper(c: Control) -> Control:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _controls(n: Node) -> Array:
	var outl := []
	if n is Control:
		outl.append(n)
	for ch in n.get_children():
		outl.append_array(_controls(ch))
	return outl


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [out, name]
	img.save_png(p)
	print("[ui] shot %s (%dx%d)" % [p, img.get_width(), img.get_height()])
