extends Control
## Marks drawn over the 3D view: teammates' names over their heads (Settings > Gameplay > Teammate names), and the
## spots your team pinged (middle mouse): a diamond with who marked it and how far it is, held at the edge of the
## screen with an arrow when it is behind you or off to the side.

const PING_TIME := 8.0
const PING_COL := Color(0.35, 1.0, 0.45)

var world = null
var pings: Array = []        # [{eid, pos: Vector3, t, who}]


func setup(w) -> void:
	world = w
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func add_ping(eid: int, pos: Vector3) -> void:
	for p in pings:
		if int(p.eid) == eid:
			pings.erase(p)
			break
	var c = world.characters.get(eid)
	pings.append({"eid": eid, "pos": pos, "t": PING_TIME, "who": str(c.pname) if c else ""})


func _process(dt: float) -> void:
	for i in range(pings.size() - 1, -1, -1):
		pings[i].t = float(pings[i].t) - dt
		if float(pings[i].t) <= 0.0:
			pings.remove_at(i)
	queue_redraw()


func _my_team() -> int:
	return int(Net.players.get(Net.local_pid, {}).get("team", -1))


func _draw() -> void:
	if world == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var font: Font = UITheme.font_semibold if UITheme.font_semibold else get_theme_default_font()
	var vs := size
	var team := _my_team()
	var local = world.local_char
	if bool(Settings.get_value("gameplay", "ally_names")) and team >= 0 and not (world.hud and world.hud.map_held):
		var tc: Color = UITheme.TEAM_COLORS[team % UITheme.TEAM_COLORS.size()]
		# Nearest first; a tag that would overlap one already drawn is left out (a squad bunched up reads as a pile of
		# names otherwise).
		var mates := []
		for c0 in world.characters.values():
			if c0 == local or c0.team != team or c0.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
				continue
			mates.append(c0)
		var cpos := cam.global_position
		mates.sort_custom(func(a, b): return cpos.distance_squared_to(a.global_position) < cpos.distance_squared_to(b.global_position))
		var taken: Array[Rect2] = []
		for c in mates:
			var head: Vector3 = c.get_global_transform_interpolated().origin + Vector3.UP * (c.height() + 0.32)
			if cam.is_position_behind(head):
				continue
			var d := cam.global_position.distance_to(head)
			if d > 320.0 or d < 1.2:
				continue
			var sp := cam.unproject_position(head)
			if sp.x < -50 or sp.y < -50 or sp.x > vs.x + 50 or sp.y > vs.y + 50:
				continue
			var a := clampf(1.0 - (d - 150.0) / 170.0, 0.35, 1.0)
			var fs := int(clampf(22.0 - d * 0.04, 14.0, 22.0))
			var label := str(c.pname)
			var col := Color(tc.r, tc.g, tc.b, a)
			if c.mode == Motor.DOWNED:
				label += "  (down)"
				col = Color(1.0, 0.42, 0.38, a)
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := sp + Vector2(-w * 0.5, -10.0)
			var box := Rect2(at + Vector2(-2, -fs), Vector2(w + 4, fs + 6))
			var clash := false
			for tr in taken:
				if tr.intersects(box):
					clash = true
					break
			if clash:
				continue
			taken.append(box)
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.75 * a))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			# A small chevron pointing down at the head.
			draw_colored_polygon(PackedVector2Array([sp + Vector2(-5, -4), sp + Vector2(5, -4), sp + Vector2(0, 2)]), col)
	var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.5)
	for p in pings:
		var pos: Vector3 = p.pos
		var a2 := clampf(float(p.t), 0.0, 1.0)
		var col2 := Color(PING_COL.r, PING_COL.g, PING_COL.b, a2)
		var behind := cam.is_position_behind(pos)
		var sp2 := cam.unproject_position(pos)
		if behind:
			sp2 = vs - sp2   # mirrored: points the way to turn
		var margin := 40.0
		var inside := not behind and sp2.x > margin and sp2.y > margin and sp2.x < vs.x - margin and sp2.y < vs.y - margin
		var d2 := cam.global_position.distance_to(pos)
		if not inside:
			var c0 := vs * 0.5
			var dirv := (sp2 - c0)
			if dirv.length() < 1.0:
				dirv = Vector2(0, 1)
			dirv = dirv.normalized()
			var k := minf((vs.x * 0.5 - margin) / maxf(absf(dirv.x), 0.001), (vs.y * 0.5 - margin) / maxf(absf(dirv.y), 0.001))
			sp2 = c0 + dirv * k
			draw_colored_polygon(PackedVector2Array([sp2 + dirv * 16.0, sp2 + dirv.rotated(2.3) * 11.0, sp2 + dirv.rotated(-2.3) * 11.0]), col2)
		var r := 11.0 + (1.0 - blink) * 3.0
		var dia := PackedVector2Array([sp2 + Vector2(0, -r), sp2 + Vector2(r, 0), sp2 + Vector2(0, r), sp2 + Vector2(-r, 0)])
		draw_colored_polygon(dia, Color(col2.r, col2.g, col2.b, 0.35 * a2))
		dia.append(dia[0])
		draw_polyline(dia, col2, 2.5)
		draw_circle(sp2, 2.5, col2)
		var txt := "%d m" % int(round(d2))
		if str(p.who) != "":
			txt = "%s  ·  %s" % [str(p.who), txt]
		var fs2 := 17
		var w2 := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
		var tp := sp2 + Vector2(-w2 * 0.5, -r - 8.0)
		draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 4, Color(0, 0, 0, 0.8 * a2))
		draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, col2)
