extends Control
## Lite minimap, top-left: the streets around you (north up), your own arrow, your teammates (team-coloured dots
## facing where they look, with their initial), the edge of the safe area, and spots your team pinged (middle
## mouse; a green diamond for 8 s). Enemies never show. The full map stays on the SmarTab (hold M).

const SPAN := 160.0          # metres shown edge to edge
const PING_TIME := 8.0
const GREEN := Color(0.35, 1.0, 0.45)

var world = null
var tex: Texture2D = null
var pings: Array = []        # [{eid, pos: Vector3, t: seconds left, own: bool}]
var _redraw_t := 0.0


func setup(w) -> void:
	world = w
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true   # the safe-area circle and pings must not draw past the minimap's edge
	if world.map and world.map.map_image:
		tex = ImageTexture.create_from_image(world.map.map_image)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func add_ping(eid: int, pos: Vector3, own: bool) -> void:
	for p in pings:
		if int(p.eid) == eid:
			pings.erase(p)
			break
	pings.append({"eid": eid, "pos": pos, "t": PING_TIME, "own": own})


func _process(dt: float) -> void:
	for i in range(pings.size() - 1, -1, -1):
		pings[i].t = float(pings[i].t) - dt
		if float(pings[i].t) <= 0.0:
			pings.remove_at(i)
	var ch = world.local_char if world else null
	visible = ch != null and is_instance_valid(ch) and ch.mode not in [Motor.DEAD, Motor.SPECTATE] \
		and not (world.hud and world.hud.map_held)
	# Redrawn 15 times a second: plenty for a north-up map and a 2 Hz blink, and cheap on phones.
	_redraw_t -= dt
	if visible and _redraw_t <= 0.0:
		_redraw_t = 1.0 / 15.0
		queue_redraw()


func _draw() -> void:
	var ch = world.local_char
	if ch == null or not is_instance_valid(ch):
		return
	var r := Rect2(Vector2.ZERO, size)
	var c := r.get_center()
	var s := size.x / SPAN        # pixels per metre
	var me := Vector2(ch.global_position.x, ch.global_position.z)
	draw_rect(r, Color(0.02, 0.03, 0.03, 0.78))
	if tex:
		var half: float = world.map.layout.HALF
		var tpm: float = tex.get_width() / (half * 2.0)   # texels per metre
		var src := Rect2((me - Vector2(SPAN, SPAN) * 0.5 + Vector2(half, half)) * tpm, Vector2(SPAN, SPAN) * tpm)
		draw_texture_rect_region(tex, r, src, Color(1.15, 1.2, 1.15, 0.92))
	var to_px := func(p: Vector2) -> Vector2: return c + (p - me) * s
	# Safe area edge.
	if not world.match_info.get("zone", {}).is_empty():
		var circ: Array = world.zone_circle(Net.interp_tick() if not world.is_server else float(Net.tick))
		draw_arc(to_px.call(circ[0]), float(circ[1]) * s, 0, TAU, 128, Color(0.95, 0.95, 0.95, 0.85), 1.5)
	# Teammates.
	var team := int(Net.players.get(Net.local_pid, {}).get("team", -1))
	if team >= 0:
		var tc: Color = UITheme.TEAM_COLORS[team % UITheme.TEAM_COLORS.size()]
		var font := get_theme_default_font()
		for o in world.characters.values():
			if o == ch or o.team != team or o.mode in [Motor.DEAD, Motor.SPECTATE, Motor.PLANE]:
				continue
			var op: Vector2 = to_px.call(Vector2(o.global_position.x, o.global_position.z))
			var oc := tc if o.mode != Motor.DOWNED else Color(1.0, 0.42, 0.38)
			if r.grow(-5.0).has_point(op):
				var of := Vector2(-sin(o.yaw), -cos(o.yaw))
				draw_line(op, op + of * 9.0, Color(oc.r, oc.g, oc.b, 0.9), 2.0)
				draw_circle(op, 5.0, Color(0, 0, 0, 0.6))
				draw_circle(op, 4.0, oc)
				var ini := str(o.pname).substr(0, 1).to_upper()
				draw_string(font, op + Vector2(6, -4), ini, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(oc.r, oc.g, oc.b, 0.95))
			else:
				var dd := (op - c).normalized()
				var ee := c + dd * minf((size.x * 0.5 - 6.0) / maxf(absf(dd.x), 0.001), (size.y * 0.5 - 6.0) / maxf(absf(dd.y), 0.001))
				draw_circle(ee, 3.5, Color(oc.r, oc.g, oc.b, 0.8))
	# Pings: a blinking green diamond at the marked spot, or an arrow on the edge when it is outside the window.
	var blink := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 2.0)
	for p in pings:
		var pp: Vector2 = to_px.call(Vector2((p.pos as Vector3).x, (p.pos as Vector3).z))
		var a := clampf(float(p.t), 0.0, 1.0) * (0.35 + 0.65 * blink)
		var col := Color(GREEN.r, GREEN.g, GREEN.b, a)
		if r.grow(-6.0).has_point(pp):
			draw_colored_polygon(PackedVector2Array([pp + Vector2(0, -6), pp + Vector2(6, 0), pp + Vector2(0, 6), pp + Vector2(-6, 0)]), col)
			draw_arc(pp, 9.0 + blink * 5.0, 0, TAU, 24, Color(GREEN.r, GREEN.g, GREEN.b, a * 0.6), 1.5)
		else:
			var d := (pp - c).normalized()
			var e := c + d * minf((size.x * 0.5 - 8.0) / maxf(absf(d.x), 0.001), (size.y * 0.5 - 8.0) / maxf(absf(d.y), 0.001))
			draw_colored_polygon(PackedVector2Array([e + d * 7.0, e + d.rotated(2.4) * 6.0, e + d.rotated(-2.4) * 6.0]), col)
	# You.
	var f := Vector2(-sin(ch.yaw), -cos(ch.yaw))
	draw_colored_polygon(PackedVector2Array([c + f * 9.0, c + f.rotated(2.5) * 6.5, c + f.rotated(-2.5) * 6.5]), Color(1.0, 0.92, 0.55))
	draw_rect(r, Color(0.8, 0.85, 0.8, 0.5), false, 1.5)
	draw_string(get_theme_default_font(), Vector2(size.x - 16, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.88, 0.85, 0.8))
