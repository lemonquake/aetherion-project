extends HBoxContainer
## The Locker: dress your character. A turning 3D preview (drag to spin) beside the slots, each slot's items as
## picture cards, colourways and skin tone. Every change is worn at once and saved to the profile (and sent to the
## lobby when you are in one). Used by the main menu and the lobby.

const Outfit := preload("res://src/player/outfit.gd")
const BODY := "res://assets/models/sleep/characters/stranger.glb"

var look: Dictionary = {}
var slot := "jacket"
var _vp: SubViewport
var _model: Node3D
var _skel: Skeleton3D
var _dressed: Array = []
var _spin := 0.35
var _drag := false
var _grid: GridContainer
var _colors: HBoxContainer
var _slot_btns := {}
var _title: Label
var _tones: HBoxContainer


func _ready() -> void:
	Outfit.ensure()
	look = Outfit.normalized(Profile.look)
	add_theme_constant_override("separation", 22)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ---- preview
	var left := UITheme.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	add_child(left)
	var frame := UITheme.panel(null, "panel")
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(frame)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(360, 420)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.gui_input.connect(_preview_input)
	frame.add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X if not Settings.is_mobile() else Viewport.MSAA_2X
	svc.add_child(_vp)
	_build_stage()
	var tools := UITheme.hbox(8)
	tools.add_child(UITheme.icon_button("dice", "Random", _randomize))
	tools.add_child(UITheme.icon_button("refresh", "Reset", _reset))
	var hint := UITheme.label("Drag to turn", 16, UITheme.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.size_flags_vertical = Control.SIZE_FILL
	tools.add_child(hint)
	left.add_child(tools)
	var tone_row := UITheme.hbox(8)
	tone_row.add_child(UITheme.label("Skin tone", 18, UITheme.TEXT_DIM))
	_tones = UITheme.hbox(6)
	tone_row.add_child(_tones)
	left.add_child(tone_row)
	# ---- slots and items
	var right := UITheme.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.25
	add_child(right)
	var slots := HFlowContainer.new()
	slots.add_theme_constant_override("h_separation", 6)
	slots.add_theme_constant_override("v_separation", 6)
	var group := ButtonGroup.new()
	for s in Outfit.slots():
		var b := Button.new()
		b.text = str(s.name)
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "FlatButton"
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 19)
		var sid := str(s.id)
		b.pressed.connect(func(): SoundSys.play_ui("ui_select"); _show_slot(sid))
		slots.add_child(b)
		_slot_btns[sid] = b
	right.add_child(slots)
	_title = UITheme.label("", 26, UITheme.TEXT, UITheme.font_condensed)
	right.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	var crow := UITheme.hbox(10)
	crow.add_child(UITheme.label("Colour", 18, UITheme.TEXT_DIM))
	_colors = UITheme.hbox(8)
	crow.add_child(_colors)
	right.add_child(crow)
	resized.connect(func(): _grid.columns = clampi(int((size.x * 0.55) / 190.0), 2, 6))
	_show_slot(slot)
	_refresh_tones()
	_wear()


# ------------------------------------------------------------------ 3D stage

func _build_stage() -> void:
	var root := Node3D.new()
	_vp.add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.38, 0.45)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.05, 3.35)
	cam.fov = 34.0
	cam.look_at_from_position(cam.position, Vector3(0, 0.92, 0))
	root.add_child(cam)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.66)
	key.light_energy = 1.6
	key.rotation = Vector3(deg_to_rad(-35), deg_to_rad(35), 0)
	key.shadow_enabled = true
	root.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.4, 0.8, 0.85)
	rim.light_energy = 3.0
	rim.omni_range = 6.0
	rim.position = Vector3(-1.6, 2.0, -1.6)
	root.add_child(rim)
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.95, 0.65, 0.3)
	fill.light_energy = 1.2
	fill.omni_range = 6.0
	fill.position = Vector3(1.8, 0.6, 1.8)
	root.add_child(fill)
	var ped := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.62
	cyl.bottom_radius = 0.66
	cyl.height = 0.06
	cyl.radial_segments = 48
	ped.mesh = cyl
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.09, 0.1, 0.11)
	pm.metallic = 0.6
	pm.roughness = 0.35
	ped.material_override = pm
	ped.position = Vector3(0, -0.03, 0)
	root.add_child(ped)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.645
	tm.outer_radius = 0.655
	tm.rings = 48
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = UITheme.ACCENT
	ring.material_override = rm
	root.add_child(ring)
	if ResourceLoader.exists(BODY):
		_model = (load(BODY) as PackedScene).instantiate()
		root.add_child(_model)
		_skel = _find(_model, "Skeleton3D")
		var anim: AnimationPlayer = _find(_model, "AnimationPlayer")
		if anim:
			var clip := "idle_look" if anim.has_animation("idle_look") else "idle"
			if anim.has_animation(clip):
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				anim.play(clip)
		for mi in _all_meshes(_model):
			mi.get_parent().remove_child(mi)
			mi.queue_free()


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _all_meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


func _process(dt: float) -> void:
	if _model and not _drag:
		_spin += dt * 0.25
	if _model:
		_model.rotation.y = _spin


func _preview_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
	elif ev is InputEventScreenTouch:
		_drag = ev.pressed
	elif ev is InputEventMouseMotion and _drag:
		_spin += ev.relative.x * 0.012
	elif ev is InputEventScreenDrag:
		_spin += ev.relative.x * 0.012


func _wear() -> void:
	for n in _dressed:
		if is_instance_valid(n):
			n.queue_free()
	_dressed = Outfit.dress(_skel, look, 1, GeometryInstance3D.SHADOW_CASTING_SETTING_ON) if _skel else []


# ------------------------------------------------------------------ choices

func _show_slot(sid: String) -> void:
	slot = sid
	if _slot_btns.has(sid):
		_slot_btns[sid].button_pressed = true
	var s: Dictionary = {}
	for x in Outfit.slots():
		if str(x.id) == sid:
			s = x
	_title.text = str(s.get("name", sid))
	for c in _grid.get_children():
		c.queue_free()
	var group := ButtonGroup.new()
	for it in s.get("items", []):
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "CardButton"
		b.custom_minimum_size = Vector2(170, 200)
		b.button_pressed = str(look.get(sid, "none")) == str(it.id)
		var v := UITheme.vbox(4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_left = 8
		v.offset_right = -8
		v.offset_top = 8
		v.offset_bottom = -8
		var pic := TextureRect.new()
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var thumb := "res://assets/ui/gear/%s_%s.png" % [sid, str(it.id)]
		if ResourceLoader.exists(thumb):
			pic.texture = load(thumb)
		else:
			pic.texture = Icons.texture("locker" if str(it.id) != "none" else "none", 64, UITheme.TEXT_DIM)
			pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		v.add_child(pic)
		var name := UITheme.label(str(it.name), 17, UITheme.TEXT, UITheme.font_semibold)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.clip_text = true
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(name)
		b.add_child(v)
		var iid := str(it.id)
		b.pressed.connect(func(): SoundSys.play_ui("ui_select"); _pick(iid))
		_grid.add_child(b)
	_refresh_colors()


func _pick(iid: String) -> void:
	look[slot] = iid
	look[slot + "_c"] = 0
	_changed()
	_refresh_colors()


func _refresh_colors() -> void:
	for c in _colors.get_children():
		c.queue_free()
	var it: Dictionary = Outfit.item(slot, str(look.get(slot, "none")))
	var cols: Array = it.get("colors", [])
	for i in cols.size():
		_colors.add_child(_swatch(Color.html(str(cols[i])), i == int(look.get(slot + "_c", 0)), func(): look[slot + "_c"] = i; _changed(); _refresh_colors()))
	if cols.is_empty():
		_colors.add_child(UITheme.label("—", 18, UITheme.TEXT_DIM))


func _refresh_tones() -> void:
	for c in _tones.get_children():
		c.queue_free()
	var tones: Array = Outfit.data.get("skin_tones", [])
	for i in tones.size():
		var t := Color.html(str(tones[i].mult))
		var col := Color(Outfit.skin_color.linear_to_srgb().r * t.r, Outfit.skin_color.linear_to_srgb().g * t.g, Outfit.skin_color.linear_to_srgb().b * t.b)
		_tones.add_child(_swatch(col, i == int(look.get("skin", 0)), func(): look.skin = i; _changed(); _refresh_tones()))


func _swatch(c: Color, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(48, 48)
	var sb := UITheme.box(c, UITheme.ACCENT if on else Color(1, 1, 1, 0.25), 24, 0, 0, 3 if on else 1)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func(): SoundSys.play_ui("ui_select"); cb.call())
	return b


func _changed() -> void:
	look = Outfit.normalized(look)
	Profile.set_look(look)
	_wear()


func _randomize() -> void:
	look = Outfit.random_look(randi())
	_changed()
	_show_slot(slot)
	_refresh_tones()


func _reset() -> void:
	look = Outfit.default_look()
	_changed()
	_show_slot(slot)
	_refresh_tones()
