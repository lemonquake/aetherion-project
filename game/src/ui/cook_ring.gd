extends Control
## r14: while a frag grenade is cooking in the hand, a ring under the crosshair runs down the fuse with the seconds
## left in the middle (red in the last second and a half), and how to throw it.

var world = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cook: float = world.controller.cook_t if world and world.controller else -1.0
	if cook < 0.0:
		return
	var fuse := float(Defs.item("frag_grenade").get("fuse_s", 4.0))
	var left := maxf(fuse - cook, 0.0)
	var k := get_viewport_rect().size.y / 1080.0
	var c := get_viewport_rect().size * 0.5 + Vector2(0, 150) * k
	var r := 44.0 * k
	var hot := left < 1.5
	var col := Color(1.0, 0.3, 0.25) if hot else Color(0.92, 0.95, 0.92)
	draw_circle(c, r + 6.0 * k, Color(0, 0, 0, 0.45))
	draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.18), 5.0 * k, true)
	draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * left / fuse, 64, col, 5.0 * k, true)
	var f := UITheme.font_semibold
	var txt := "%.1f" % left
	var fs := int(30 * k)
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var hint := "Let go to throw  ·  hold Aim to roll it underhand" if not Settings.touch_active() else "Let go to throw"
	var hs := int(18 * k)
	var hw := UITheme.font_medium.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x
	draw_string(UITheme.font_medium, c + Vector2(-hw * 0.5, r + 34.0 * k), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color(1, 1, 1, 0.8))
