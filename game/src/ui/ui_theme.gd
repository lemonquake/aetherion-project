class_name UITheme
## Shared look for menus: dark translucent panels, Barlow type, a muted signal-green accent.

const BG := Color(0.035, 0.04, 0.045, 0.92)
const PANEL := Color(0.07, 0.08, 0.085, 0.86)
const PANEL_LIGHT := Color(0.11, 0.125, 0.13, 0.9)
const LINE := Color(0.32, 0.36, 0.37, 0.55)
const TEXT := Color(0.86, 0.88, 0.86)
const TEXT_DIM := Color(0.58, 0.62, 0.62)
const ACCENT := Color(0.62, 0.83, 0.66)
const WARN := Color(0.93, 0.72, 0.38)
const DANGER := Color(0.9, 0.42, 0.38)

static var _theme: Theme
static var font_regular: Font
static var font_medium: Font
static var font_semibold: Font
static var font_condensed: Font
static var font_mono: Font


static func fonts() -> void:
	if font_regular:
		return
	font_regular = load("res://assets/fonts/Barlow-Regular.ttf")
	font_medium = load("res://assets/fonts/Barlow-Medium.ttf")
	font_semibold = load("res://assets/fonts/Barlow-SemiBold.ttf")
	font_condensed = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	font_mono = load("res://assets/fonts/ShareTechMono-Regular.ttf")


static func get_theme() -> Theme:
	if _theme:
		return _theme
	fonts()
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 6))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 6))
	# Buttons
	t.set_stylebox("normal", "Button", box(Color(0.12, 0.135, 0.14, 0.92), Color(0.3, 0.33, 0.34, 0.6), 4, 14, 8))
	t.set_stylebox("hover", "Button", box(Color(0.17, 0.2, 0.19, 0.95), ACCENT * Color(1, 1, 1, 0.7), 4, 14, 8))
	t.set_stylebox("pressed", "Button", box(Color(0.22, 0.27, 0.24, 0.95), ACCENT, 4, 14, 8))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT, 4, 14, 8, 2))
	t.set_stylebox("disabled", "Button", box(Color(0.09, 0.1, 0.1, 0.7), Color(0.2, 0.22, 0.22, 0.5), 4, 14, 8))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", TEXT_DIM * Color(1, 1, 1, 0.6))
	t.set_font("font", "Button", font_medium)
	# Inputs
	t.set_stylebox("normal", "LineEdit", box(Color(0.05, 0.06, 0.06, 0.95), Color(0.3, 0.33, 0.34, 0.7), 4, 10, 6))
	t.set_stylebox("focus", "LineEdit", box(Color(0.05, 0.06, 0.06, 0.95), ACCENT, 4, 10, 6))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "OptionButton", box(Color(0.12, 0.135, 0.14, 0.92), Color(0.3, 0.33, 0.34, 0.6), 4, 12, 6))
	t.set_stylebox("hover", "OptionButton", box(Color(0.17, 0.2, 0.19, 0.95), ACCENT * Color(1, 1, 1, 0.7), 4, 12, 6))
	t.set_stylebox("pressed", "OptionButton", box(Color(0.22, 0.27, 0.24, 0.95), ACCENT, 4, 12, 6))
	t.set_stylebox("panel", "PopupMenu", box(Color(0.08, 0.09, 0.095, 0.98), LINE, 4, 6, 6))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.2, 0.26, 0.22, 1.0), Color(0, 0, 0, 0), 2))
	t.set_stylebox("slider", "HSlider", box(Color(0.2, 0.22, 0.22), Color(0, 0, 0, 0), 2, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT * Color(0.8, 0.8, 0.8), Color(0, 0, 0, 0), 2, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, Color(0, 0, 0, 0), 2, 0, 3))
	t.set_stylebox("panel", "TabContainer", box(PANEL, LINE, 6, 14, 12))
	t.set_stylebox("tab_selected", "TabContainer", box(PANEL_LIGHT, ACCENT * Color(1, 1, 1, 0.6), 4, 14, 6))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.06, 0.07, 0.07, 0.8), Color(0, 0, 0, 0), 4, 14, 6))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.12, 0.14, 0.13, 0.9), Color(0, 0, 0, 0), 4, 14, 6))
	t.set_color("font_selected_color", "TabContainer", Color(1, 1, 1))
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_font("font", "TabContainer", font_medium)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.06, 0.06, 0.96), LINE, 4, 8, 6))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_stylebox("scroll", "VScrollBar", box(Color(0.1, 0.11, 0.11, 0.6), Color(0, 0, 0, 0), 3, 0, 0))
	t.set_stylebox("grabber", "VScrollBar", box(Color(0.3, 0.33, 0.33, 0.8), Color(0, 0, 0, 0), 3, 0, 0))
	_theme = t
	return t


static func box(bg: Color, border: Color, radius: int = 4, pad_h: int = 12, pad_v: int = 8, border_w: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.anti_aliasing = true
	return s


static func label(text: String, size: int = 20, color: Color = TEXT, font: Font = null) -> Label:
	fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


static func button(text: String, cb: Callable, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 44)
	# Menu clicks (work/sounds/buttons): back / cancel / close sound different from everything else.
	var back := text.to_lower().begins_with("back") or text.to_lower() in ["cancel", "close", "leave", "quit"]
	b.pressed.connect(func(): SoundSys.play_ui("ui_back" if back else "ui_select"))
	b.pressed.connect(cb)
	return b


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer(h: int = 0, w: int = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c
