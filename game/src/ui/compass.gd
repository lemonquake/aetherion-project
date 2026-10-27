extends Control
## Horizontal compass under the minimap: the bearing you face in degrees (0 = north, clockwise), with N/NE/E... and
## a number every 15 degrees, so squads can call "north one-twenty" over the radio. Active teammate pings show as
## green marks at their bearing. 120 degrees of the horizon are shown across the strip.

const SPAN_DEG := 120.0
const GREEN := Color(0.35, 1.0, 0.45)
const NAMES := {0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW"}

var world = null
var bearing := 0.0   # last drawn bearing (tests read it)
var _last := -999.0


func setup(w) -> void:
	world = w
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


static func bearing_of(yaw: float) -> float:
	## Facing direction (-sin yaw, -cos yaw) in x/z, with north = -z and east = +x.
	return fposmod(rad_to_deg(-yaw), 360.0)


func _process(_dt: float) -> void:
	var mm = world.hud.minimap if world and world.hud else null
	visible = mm != null and mm.visible
	if not visible:
		return
	var ch = world.local_char
	var b := bearing_of(ch.yaw)
	# Redraw only when the view turned (or pings blink).
	if absf(b - _last) > 0.2 or not mm.pings.is_empty():
		_last = b
		queue_redraw()


func _draw() -> void:
	var ch = world.local_char if world else null
	if ch == null or not is_instance_valid(ch):
		return
	bearing = bearing_of(ch.yaw)
	var font := get_theme_default_font()
	var w := size.x
	var strip_h := 24.0
	var ppd := w / SPAN_DEG   # pixels per degree
	draw_rect(Rect2(0, 0, w, strip_h), Color(0.02, 0.03, 0.03, 0.72))
	var first := int(floor((bearing - SPAN_DEG * 0.5) / 5.0)) * 5
	var d := first
	while d <= bearing + SPAN_DEG * 0.5 + 5.0:
		var x := w * 0.5 + (float(d) - bearing) * ppd
		var deg := posmod(d, 360)
		if deg % 15 == 0:
			var named := NAMES.has(deg)
			var label: String = NAMES[deg] if named else str(deg)
			var fs := 14 if named else 12
			var col := Color(1.0, 0.92, 0.55, 0.95) if deg == 0 else (Color(0.92, 0.94, 0.92, 0.95) if named else Color(0.78, 0.82, 0.8, 0.85))
			var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(x - tw * 0.5, 15.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			draw_line(Vector2(x, strip_h - 6.0), Vector2(x, strip_h), col, 1.5)
		else:
			draw_line(Vector2(x, strip_h - 4.0), Vector2(x, strip_h), Color(0.7, 0.74, 0.72, 0.6), 1.0)
		d += 5
	# Teammate pings at their bearing.
	var mm = world.hud.minimap
	var me := Vector2(ch.global_position.x, ch.global_position.z)
	for p in mm.pings:
		var pp: Vector3 = p.pos
		var to := Vector2(pp.x, pp.z) - me
		if to.length() < 2.0:
			continue
		var pb := fposmod(rad_to_deg(atan2(to.x, -to.y)), 360.0)
		var off := wrapf(pb - bearing, -180.0, 180.0)
		var x2 := clampf(w * 0.5 + off * ppd, 5.0, w - 5.0)
		var a := clampf(float(p.t), 0.0, 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x2, strip_h - 1.0), Vector2(x2 - 5.0, strip_h - 9.0), Vector2(x2 + 5.0, strip_h - 9.0)]),
			Color(GREEN.r, GREEN.g, GREEN.b, a))
	# Centre: a pointer and the exact bearing below it.
	var c := w * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(c, strip_h + 1.0), Vector2(c - 5.0, strip_h + 7.0), Vector2(c + 5.0, strip_h + 7.0)]), Color(1.0, 0.92, 0.55))
	var txt := "%d" % (int(round(bearing)) % 360)
	var tw2 := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_rect(Rect2(c - tw2 * 0.5 - 5.0, strip_h + 7.0, tw2 + 10.0, 17.0), Color(0.02, 0.03, 0.03, 0.8))
	draw_string(font, Vector2(c - tw2 * 0.5, strip_h + 20.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.95, 0.75))
	draw_rect(Rect2(0, 0, w, strip_h), Color(0.8, 0.85, 0.8, 0.45), false, 1.0)
