class_name UITheme
## Shared look for menus: worn dark-metal panels and buttons with grain (assets/ui, tools/make_ui_textures.py),
## Barlow type, the artificial sun's amber as the accent and a signal teal beside it. Sizes suit a mouse at
## 1920x1080 and a thumb on a phone (the UI is drawn 1.5x there): no touch target under 44 px.

const BG := Color(0.04, 0.045, 0.055, 0.94)
const PANEL := Color(0.065, 0.075, 0.09, 0.86)
const PANEL_LIGHT := Color(0.11, 0.125, 0.145, 0.92)
const LINE := Color(1, 1, 1, 0.08)
const TEXT := Color(0.92, 0.93, 0.9)
const TEXT_DIM := Color(0.6, 0.64, 0.64)
const ACCENT := Color(0.95, 0.64, 0.23)
const ACCENT2 := Color(0.3, 0.78, 0.72)
const WARN := Color(0.96, 0.75, 0.36)
const DANGER := Color(0.92, 0.36, 0.32)
const GOOD := Color(0.48, 0.84, 0.52)
const TEAM_COLORS := [Color(0.95, 0.64, 0.23), Color(0.3, 0.78, 0.72), Color(0.86, 0.38, 0.4), Color(0.55, 0.62, 0.95),
	Color(0.72, 0.85, 0.36), Color(0.82, 0.5, 0.86), Color(0.92, 0.88, 0.5)]
const UI := "res://assets/ui/"

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


static func tex_box(name: String, margin: int, pad_h: int = 14, pad_v: int = 8) -> StyleBox:
	## A nine-slice from assets/ui (falls back to a flat box if the texture is missing).
	var path := UI + name + ".png"
	if not ResourceLoader.exists(path):
		return box(PANEL, LINE, 8, pad_h, pad_v)
	var s := StyleBoxTexture.new()
	s.texture = load(path)
	s.texture_margin_left = margin
	s.texture_margin_right = margin
	s.texture_margin_top = margin
	s.texture_margin_bottom = margin
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	# Tile the middle: stretched, the grain turns into streaks across a big panel.
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return s


static func get_theme() -> Theme:
	if _theme:
		return _theme
	fonts()
	var t := Theme.new()
	t.default_font = font_regular
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", tex_box("panel", 20, 18, 16))
	t.set_stylebox("panel", "Panel", tex_box("panel", 20, 18, 16))
	# Buttons
	t.set_stylebox("normal", "Button", tex_box("button", 12, 18, 10))
	t.set_stylebox("hover", "Button", tex_box("button_hover", 12, 18, 10))
	t.set_stylebox("pressed", "Button", tex_box("button_pressed", 12, 18, 10))
	t.set_stylebox("hover_pressed", "Button", tex_box("button_pressed", 12, 18, 10))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT, 8, 18, 10, 2))
	t.set_stylebox("disabled", "Button", box(Color(0.09, 0.1, 0.11, 0.7), Color(1, 1, 1, 0.04), 8, 18, 10))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 0.92, 0.8))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 0.92, 0.8))
	t.set_color("font_disabled_color", "Button", TEXT_DIM * Color(1, 1, 1, 0.6))
	t.set_font("font", "Button", font_semibold)
	t.set_font_size("font_size", "Button", 21)
	# The big call to action
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var tex: String = {"normal": "button_primary", "hover": "button_primary_hover", "pressed": "button_primary_pressed", "hover_pressed": "button_primary_pressed"}[state]
		t.set_stylebox(state, "PrimaryButton", tex_box(tex, 16, 26, 12))
	t.set_stylebox("focus", "PrimaryButton", box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.8), 10, 26, 12, 2))
	t.set_stylebox("disabled", "PrimaryButton", box(Color(0.3, 0.24, 0.16, 0.7), Color(0, 0, 0, 0), 10, 26, 12))
	t.set_type_variation("PrimaryButton", "Button")
	t.set_color("font_color", "PrimaryButton", Color(0.1, 0.07, 0.03))
	t.set_color("font_hover_color", "PrimaryButton", Color(0.06, 0.04, 0.02))
	t.set_color("font_pressed_color", "PrimaryButton", Color(0.06, 0.04, 0.02))
	t.set_color("font_hover_pressed_color", "PrimaryButton", Color(0.06, 0.04, 0.02))
	t.set_font("font", "PrimaryButton", font_condensed)
	t.set_font_size("font_size", "PrimaryButton", 30)
	# Quiet buttons (tabs, list actions)
	t.set_type_variation("FlatButton", "Button")
	t.set_stylebox("normal", "FlatButton", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 14, 8))
	t.set_stylebox("hover", "FlatButton", box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 6, 14, 8))
	t.set_stylebox("pressed", "FlatButton", tex_box("tab_active", 6, 14, 8))
	t.set_stylebox("hover_pressed", "FlatButton", tex_box("tab_active", 6, 14, 8))
	t.set_stylebox("focus", "FlatButton", box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.3), 6, 14, 8, 1))
	t.set_color("font_color", "FlatButton", TEXT_DIM)
	t.set_color("font_hover_color", "FlatButton", TEXT)
	t.set_color("font_pressed_color", "FlatButton", Color(1, 1, 1))
	t.set_color("font_hover_pressed_color", "FlatButton", Color(1, 1, 1))
	# Cards (outfit items, games): a light panel that lights up when chosen
	t.set_type_variation("CardButton", "Button")
	t.set_stylebox("normal", "CardButton", tex_box("panel_light", 20, 10, 10))
	t.set_stylebox("hover", "CardButton", tex_box("button_hover", 12, 10, 10))
	t.set_stylebox("pressed", "CardButton", box(Color(0.24, 0.18, 0.1, 0.95), ACCENT, 10, 10, 10, 2))
	t.set_stylebox("hover_pressed", "CardButton", box(Color(0.28, 0.21, 0.12, 0.95), ACCENT, 10, 10, 10, 2))
	t.set_stylebox("focus", "CardButton", box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.35), 10, 10, 10, 1))
	t.set_font("font", "CardButton", font_medium)
	t.set_font_size("font_size", "CardButton", 18)
	# Inputs
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.035, 0.045, 0.95), Color(1, 1, 1, 0.12), 8, 12, 8))
	t.set_stylebox("focus", "LineEdit", box(Color(0.03, 0.035, 0.045, 0.95), ACCENT, 8, 12, 8, 2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM * Color(1, 1, 1, 0.7))
	t.set_stylebox("normal", "OptionButton", tex_box("button", 12, 14, 8))
	t.set_stylebox("hover", "OptionButton", tex_box("button_hover", 12, 14, 8))
	t.set_stylebox("pressed", "OptionButton", tex_box("button_pressed", 12, 14, 8))
	t.set_stylebox("panel", "PopupMenu", box(Color(0.06, 0.07, 0.08, 0.98), Color(1, 1, 1, 0.1), 8, 8, 8))
	t.set_stylebox("hover", "PopupMenu", box(Color(0.95, 0.64, 0.23, 0.25), Color(0, 0, 0, 0), 4))
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 3, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT * Color(0.85, 0.85, 0.85), Color(0, 0, 0, 0), 3, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, Color(0, 0, 0, 0), 3, 0, 3))
	t.set_stylebox("panel", "TabContainer", tex_box("panel", 20, 16, 14))
	t.set_stylebox("tab_selected", "TabContainer", tex_box("tab_active", 6, 16, 8))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 16, 8))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 4, 16, 8))
	t.set_color("font_selected_color", "TabContainer", Color(1, 1, 1))
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_font("font", "TabContainer", font_semibold)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.06, 0.06, 0.96), LINE, 6, 10, 8))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_stylebox("scroll", "VScrollBar", box(Color(1, 1, 1, 0.04), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(ACCENT * Color(1, 1, 1, 0.7), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_constant("scrollbar_width", "VScrollBar", 10)
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color(0, 0, 0, 0), 4, 0, 0))
	t.set_color("font_color", "ProgressBar", Color(0, 0, 0, 0))
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


static func button(text: String, cb: Callable, min_w: int = 0, variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 48)
	if variation != "":
		b.theme_type_variation = variation
	# Menu clicks (work/sounds/buttons): back / cancel / close sound different from everything else.
	var back := text.to_lower().begins_with("back") or text.to_lower() in ["cancel", "close", "leave", "quit"]
	b.pressed.connect(func(): SoundSys.play_ui("ui_back" if back else "ui_select"))
	b.pressed.connect(cb)
	return b


static func primary(text: String, cb: Callable, min_w: int = 0, h: int = 72) -> Button:
	var b := button(text, cb, min_w, "PrimaryButton")
	b.custom_minimum_size.y = h
	return b


static func icon_button(icon: String, text: String, cb: Callable, variation: String = "") -> Button:
	## A button with a vector icon (ui/icons.gd) left of its text.
	var b := button(text, cb, 0, variation)
	b.icon = Icons.texture(icon, 26, Color(1, 1, 1))
	b.add_theme_constant_override("h_separation", 10)
	b.expand_icon = false
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


static func panel(content: Control = null, style: String = "panel") -> PanelContainer:
	var p := PanelContainer.new()
	if style != "panel":
		p.add_theme_stylebox_override("panel", tex_box(style, 20, 18, 16))
	if content:
		p.add_child(content)
	return p


static func pill(text: String, color: Color, size: int = 16) -> PanelContainer:
	## A small rounded tag: "LAN", "Mobile", "Host", "Level 7".
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(color.r, color.g, color.b, 0.18), Color(color.r, color.g, color.b, 0.55), 12, 9, 2))
	var l := label(text, size, color.lightened(0.15), font_semibold)
	p.add_child(l)
	return p


static func section(title: String, sub: String = "") -> VBoxContainer:
	var v := vbox(2)
	v.add_child(label(title, 30, TEXT, font_condensed))
	if sub != "":
		var s := label(sub, 17, TEXT_DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(s)
	return v


static func stepper(value: int, lo: int, hi: int, on_change: Callable, fmt: String = "%d") -> HBoxContainer:
	## [-] value [+]: big targets for a thumb.
	var h := hbox(6)
	var l := label(fmt % value, 26, TEXT, font_condensed)
	l.custom_minimum_size = Vector2(70, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var minus := button("–", func(): pass, 52)
	var plus := button("+", func(): pass, 52)
	var set_v := func(v: int):
		v = clampi(v, lo, hi)
		l.text = fmt % v
		l.set_meta("v", v)
		minus.disabled = v <= lo
		plus.disabled = v >= hi
		on_change.call(v)
	l.set_meta("v", value)
	minus.pressed.connect(func(): set_v.call(int(l.get_meta("v")) - 1))
	plus.pressed.connect(func(): set_v.call(int(l.get_meta("v")) + 1))
	minus.disabled = value <= lo
	plus.disabled = value >= hi
	h.add_child(minus)
	h.add_child(l)
	h.add_child(plus)
	return h


static func segmented(options: Array, current, on_change: Callable) -> HBoxContainer:
	## One choice from a few ([[value, label]]): buttons in a row, the chosen one lit.
	var h := hbox(4)
	var group := ButtonGroup.new()
	for o in options:
		var b := Button.new()
		b.text = str(o[1])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(64, 48)
		b.theme_type_variation = "CardButton"
		b.button_pressed = o[0] == current
		var val = o[0]
		b.pressed.connect(func(): SoundSys.play_ui("ui_select"); on_change.call(val))
		h.add_child(b)
	return h


static func toggle(text: String, on: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.custom_minimum_size = Vector2(0, 48)
	c.add_theme_font_size_override("font_size", 20)
	c.toggled.connect(func(v): SoundSys.play_ui("ui_select"); on_change.call(v))
	return c


static func bar(value: float, max_value: float, color: Color = ACCENT, h: int = 10) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = max_value
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, h)
	var fill := box(color, Color(0, 0, 0, 0), 4, 0, 0)
	p.add_theme_stylebox_override("fill", fill)
	return p


static func grain(parent: Control, alpha: float = 0.05) -> void:
	## Film grain over a screen (the tile repeats).
	var g := TextureRect.new()
	g.texture = load(UI + "grain.png")
	g.stretch_mode = TextureRect.STRETCH_TILE
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.modulate = Color(1, 1, 1, alpha)
	parent.add_child(g)
