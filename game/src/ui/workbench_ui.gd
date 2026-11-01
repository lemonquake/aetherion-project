extends Control
## r24 weapon workbench: the gun as a 3D model on a turntable (hold and drag to turn it, the wheel zooms), the
## attachments that fit it down the right side, its mounts down the left. Drag an attachment onto the gun (or onto
## its mount on the left): it flies to its mount, snaps on with a burst of green "+" marks, and the numbers below
## change. Hovering an attachment shows what it does (+20% weapon sway resistance, +30 rounds per magazine...) and
## previews the numbers. A fitted attachment comes off with its x, or dragged back to the list.
##
## Two sources feed it: MatchSource (in a match: the guns you carry, attachments in your bag or on your other guns;
## every change is a request to the server, the same ops the SmarTab sends) and LoadoutSource (Game Setup: your
## Deathmatch guns and every attachment they take).

signal closed

const Attach := preload("res://src/weapons/attachments.gd")
const AttachVisual := preload("res://src/weapons/attach_visual.gd")
const ItemModels := preload("res://src/weapons/item_models.gd")

const KIND_NAMES := {"sight": "Sight", "muzzle": "Muzzle", "grip": "Grip", "mag": "Magazine", "stock": "Stock", "light": "Extra"}
const KIND_ORDER := ["sight", "muzzle", "grip", "mag", "stock", "light"]
const GOOD := Color(0.42, 0.95, 0.5)
const BAD := Color(0.98, 0.45, 0.4)
const PLUS := Color(0.35, 1.0, 0.45)


# ------------------------------------------------------------------ sources

class MatchSource:
	## The guns the local player carries. Changes go to the server; the screen follows what the server says.
	var world = null

	func _init(w) -> void:
		world = w

	func _ch():
		var c = world.local_char if world else null
		return c if c != null and is_instance_valid(c) else null

	func models():
		return world.map

	func guns() -> Array:
		var out := []
		var c = _ch()
		if c == null:
			return out
		for s in [1, 2, 3]:
			var w = c.wpn.slots[s]
			if w != null:
				out.append({"key": s, "wid": str(w.id), "att": (w.att as Array).duplicate(), "label": "%d  %s" % [s, Defs.item_name(str(w.id))]})
		return out

	func available(key, wid: String) -> Array:
		## [{id, n, where, from}]: in the bag (n of them), or on another of your guns (from = its slot).
		var out := []
		var c = _ch()
		if c == null:
			return out
		var counts := {}
		for e in c.inv.bag:
			var id := str(e.get("id", ""))
			if Defs.is_attachment(id) and Attach.compatible(wid, id):
				counts[id] = int(counts.get(id, 0)) + int(e.get("n", 1))
		for id in counts:
			out.append({"id": id, "n": int(counts[id]), "where": "In your bag" + (" ×%d" % int(counts[id]) if int(counts[id]) > 1 else ""), "from": 0})
		for s in [1, 2, 3]:
			var w = c.wpn.slots[s]
			if s == int(key) or w == null:
				continue
			for a in w.att:
				if Attach.compatible(wid, str(a)):
					out.append({"id": str(a), "n": 1, "where": "On your %s" % Defs.item_name(str(w.id)), "from": s})
		return out

	func fit(key, _wid: String, entry: Dictionary) -> void:
		if int(entry.get("from", 0)) > 0:
			world.request_inventory({"op": "move_att", "from": int(entry.from), "to": int(key), "att": str(entry.id)})
		else:
			world.request_inventory({"op": "attach", "slot": int(key), "att": str(entry.id)})

	func remove(key, _wid: String, att: String) -> void:
		world.request_inventory({"op": "detach", "slot": int(key), "att": att})

	func remove_hint() -> String:
		return "Goes back to your bag"


class LoadoutSource:
	## Game Setup's Deathmatch guns: every attachment each takes, fitted at once and remembered in the profile.
	var setup = null
	var _models = null

	func _init(game_setup) -> void:
		setup = game_setup

	func models():
		if _models == null:
			_models = ItemModels.new()
		return _models

	func guns() -> Array:
		var lo: Dictionary = Profile.get_loadout()
		var out := []
		for which in ["primary", "secondary"]:
			var wid := str(lo.get(which, ""))
			if wid != "":
				out.append({"key": which, "wid": wid, "att": (lo.get("att_" + which, []) as Array).duplicate(),
					"label": "%s  %s" % ["Primary" if which == "primary" else "Secondary", Defs.item_name(wid)]})
		return out

	func available(_key, wid: String) -> Array:
		var out := []
		for k in Attach.kinds_for(wid):
			for a in Attach.options(wid, k):
				out.append({"id": str(a), "n": -1, "where": "", "from": 0})
		return out

	func fit(key, _wid: String, entry: Dictionary) -> void:
		_put(str(key), Attach.kind(str(entry.id)), str(entry.id))

	func remove(key, _wid: String, att: String) -> void:
		_put(str(key), Attach.kind(att), "")

	func _put(which: String, k: String, att: String) -> void:
		if setup and is_instance_valid(setup) and setup.has_method("fit"):
			setup.fit(which, k, att)
		else:
			Profile.set_attachment(which, k, att)

	func remove_hint() -> String:
		return "Takes it off this gun"


# ------------------------------------------------------------------ state

var source = null
var gun_key = null               # which gun is on the bench (slot number, or "primary"/"secondary")
var _wid := ""
var _shown_att: Array = []       # what the 3D model shows (the source's list once it caught up)
var _filter := ""                # "" = every kind
var _hover := ""                 # attachment id under the mouse (info card, numbers preview)
var _hover_from_fitted := false

var _vpc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _gun_node: Node3D
var _gun_mesh: MeshInstance3D
var _att_root: Node3D
var _yaw := -1.15
var _pitch := 0.22
var _zoom := 1.0
var _turning := false
var _gun_len := 0.8
var _flying := {}                # att id -> MeshInstance3D flying in or out (kept until the source agrees)

var _fx: Control                 # over the 3D view: mount markers while dragging, "+" bursts
var _parts: Array = []           # [pos, vel, life, max_life, size, kind]
var _rings: Array = []           # [pos, life]
var _gun_tabs: HBoxContainer
var _slots_box: VBoxContainer
var _list: VBoxContainer
var _chips: HFlowContainer
var _stats_box: GridContainer
var _info: PanelContainer
var _info_v: VBoxContainer
var _hint: Label
var _title_gun: Label
var _sig := ""


func _init(src, start_key = null) -> void:
	source = src
	gun_key = start_key


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_background()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var col := UITheme.vbox(14)
	margin.add_child(col)
	# Top: title, the guns, Done.
	var top := UITheme.hbox(18)
	col.add_child(top)
	var tv := UITheme.vbox(0)
	tv.add_child(UITheme.label("Workbench", 44, UITheme.TEXT, UITheme.font_condensed))
	_title_gun = UITheme.label("", 20, UITheme.TEXT_DIM)
	tv.add_child(_title_gun)
	top.add_child(tv)
	_gun_tabs = UITheme.hbox(10)
	_gun_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gun_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(_gun_tabs)
	var done := UITheme.primary("Done", close, 180, 60)
	top.add_child(done)
	# Middle: mounts | the gun | attachments.
	var mid := UITheme.hbox(18)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(mid)
	mid.add_child(_build_slots_panel())
	var centre := UITheme.vbox(10)
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(centre)
	centre.add_child(_build_view())
	_hint = UITheme.label("Drag an attachment onto the gun to fit it.  Hold and drag the gun to turn it, scroll to zoom.", 18, UITheme.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(_hint)
	centre.add_child(_build_stats())
	mid.add_child(_build_list_panel())
	# The hover card floats over everything.
	_info = PanelContainer.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.04, 0.05, 0.97), Color(0.35, 1.0, 0.45, 0.35), 8, 16, 12))
	_info.custom_minimum_size = Vector2(380, 0)
	_info_v = UITheme.vbox(4)
	_info.add_child(_info_v)
	_info.visible = false
	_info.z_index = 10
	add_child(_info)
	var guns: Array = source.guns()
	if gun_key == null and not guns.is_empty():
		gun_key = guns[0].key
	_rebuild_all()


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	vec2 px = uv * vec2(1920.0, 1080.0);
	float d = distance(uv, vec2(0.5, 0.42));
	vec3 c = mix(vec3(0.075, 0.09, 0.1), vec3(0.018, 0.022, 0.026), smoothstep(0.0, 0.75, d));
	float g = max(step(fract(px.x / 48.0), 0.025), step(fract(px.y / 48.0), 0.025));
	c += vec3(0.25, 0.9, 0.5) * g * 0.025 * (1.0 - smoothstep(0.1, 0.7, d));
	COLOR = vec4(c, 0.97);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	bg.material = m
	add_child(bg)


func _build_view() -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, 0.18), Color(1, 1, 1, 0.06), 10, 0, 0))
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Input goes to the overlay above it: a SubViewportContainer hands drops on to its own viewport.
	_vpc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vpc.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.65)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.light_color = Color(1.0, 0.95, 0.88)
	key.rotation = Vector3(-0.75, 0.6, 0.0)
	key.shadow_enabled = true
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.55
	fill.light_color = Color(0.7, 0.82, 1.0)
	fill.rotation = Vector3(-0.3, -2.3, 0.0)
	_vp.add_child(fill)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.45, 1.0, 0.6)
	rim.light_energy = 0.7
	rim.omni_range = 2.6
	rim.position = Vector3(0.0, 0.9, -1.1)
	_vp.add_child(rim)
	# The turntable: a dark disc with a lit green rim under the gun.
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.62
	cm.bottom_radius = 0.66
	cm.height = 0.03
	cm.radial_segments = 64
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.06, 0.07, 0.075)
	dm.roughness = 0.35
	dm.metallic = 0.6
	cm.material = dm
	disc.mesh = cm
	disc.position = Vector3(0, -0.36, 0)   # low enough for a drum magazine hanging under the gun
	_vp.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.645
	tm.outer_radius = 0.66
	tm.rings = 96
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.3, 1.0, 0.5)
	rm.emission_enabled = true
	rm.emission = Color(0.3, 1.0, 0.5)
	rm.emission_energy_multiplier = 2.0
	tm.material = rm
	ring.mesh = tm
	ring.position = Vector3(0, -0.345, 0)
	_vp.add_child(ring)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_gun_node = Node3D.new()
	_pivot.add_child(_gun_node)
	_gun_mesh = MeshInstance3D.new()
	_gun_node.add_child(_gun_mesh)
	_att_root = Node3D.new()
	_gun_node.add_child(_att_root)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	_cam.near = 0.02
	_vp.add_child(_cam)
	_cam.current = true
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_STOP
	_fx.gui_input.connect(_view_input)
	_fx.set_drag_forwarding(Callable(), _can_drop_on_gun, _drop_on_gun)
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.draw.connect(_draw_fx)
	frame.add_child(_fx)
	return frame


func _build_slots_panel() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(320, 0)
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.035, 0.045, 0.85), Color(1, 1, 1, 0.07), 10, 16, 14))
	var v := UITheme.vbox(10)
	p.add_child(v)
	v.add_child(UITheme.label("Mounts", 26, UITheme.TEXT, UITheme.font_condensed))
	_slots_box = UITheme.vbox(8)
	v.add_child(_slots_box)
	return p


func _build_list_panel() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(400, 0)
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.035, 0.045, 0.85), Color(1, 1, 1, 0.07), 10, 16, 14))
	var v := UITheme.vbox(10)
	p.add_child(v)
	v.add_child(UITheme.label("Attachments", 26, UITheme.TEXT, UITheme.font_condensed))
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	v.add_child(_chips)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_list = UITheme.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	# Dropping a fitted attachment back on the list takes it off.
	p.set_drag_forwarding(Callable(), _can_drop_on_list, _drop_on_list)
	return p


func _build_stats() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.035, 0.045, 0.85), Color(1, 1, 1, 0.07), 10, 18, 12))
	_stats_box = GridContainer.new()
	_stats_box.columns = 2
	_stats_box.add_theme_constant_override("h_separation", 24)
	_stats_box.add_theme_constant_override("v_separation", 4)
	p.add_child(_stats_box)
	return p


# ------------------------------------------------------------------ refresh

func _gun() -> Dictionary:
	for g in source.guns():
		if g.key == gun_key:
			return g
	return {}


func _process(dt: float) -> void:
	var g := _gun()
	if g.is_empty():
		var guns: Array = source.guns()
		if guns.is_empty():
			close()
			return
		gun_key = guns[0].key
		_rebuild_all()
		return
	# Follow the source (the server's answer in a match).
	var sig := JSON.stringify([gun_key, g.wid, g.att, source.available(gun_key, str(g.wid)).map(func(e): return [e.id, e.n, e.from])])
	if sig != _sig:
		_rebuild_all()
	_turn(dt)
	if not _flying.is_empty():
		_settle()
	_tick_fx(dt)
	_place_info()


func _rebuild_all() -> void:
	var g := _gun()
	if g.is_empty():
		return
	_sig = JSON.stringify([gun_key, g.wid, g.att, source.available(gun_key, str(g.wid)).map(func(e): return [e.id, e.n, e.from])])
	if str(g.wid) != _wid:
		_wid = str(g.wid)
		_set_gun_model()
	_title_gun.text = "%s  ·  %d of %d mounts used" % [Defs.item_name(_wid), (g.att as Array).size(), Attach.kinds_for(_wid).size()]
	_fill_tabs()
	_fill_slots(g)
	_fill_chips()
	_fill_list(g)
	_fill_stats()
	_sync_att_models(g.att)


func _fill_tabs() -> void:
	for c in _gun_tabs.get_children():
		c.queue_free()
	for g in source.guns():
		var key = g.key
		var b := UITheme.button(str(g.label), func(): _select_gun(key), 0)
		b.toggle_mode = true
		b.button_pressed = key == gun_key
		b.custom_minimum_size = Vector2(200, 52)
		_gun_tabs.add_child(b)


func _select_gun(key) -> void:
	if key == gun_key:
		return
	SoundSys.play_ui("ui_select")
	gun_key = key
	_hover = ""
	_rebuild_all()


func _fill_slots(g: Dictionary) -> void:
	for c in _slots_box.get_children():
		c.queue_free()
	var fitted: Array = g.att
	for k in KIND_ORDER:
		if Attach.options(_wid, k).is_empty():
			continue
		var cur := ""
		for a in fitted:
			if Attach.kind(str(a)) == k:
				cur = str(a)
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(0, 74)
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.add_theme_stylebox_override("panel", UITheme.box(Color(0.35, 1.0, 0.45, 0.07) if cur != "" else Color(1, 1, 1, 0.025),
			Color(0.35, 1.0, 0.45, 0.45) if cur != "" else Color(1, 1, 1, 0.1), 8, 12, 8))
		box.set_meta("kind", k)
		var h := UITheme.hbox(10)
		box.add_child(h)
		var v := UITheme.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(UITheme.label(str(KIND_NAMES[k]), 16, UITheme.TEXT_DIM, UITheme.font_semibold))
		var nm := UITheme.label(Defs.item_name(cur) if cur != "" else "Empty", 20, UITheme.TEXT if cur != "" else Color(1, 1, 1, 0.3))
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(nm)
		h.add_child(v)
		if cur != "":
			var x := UITheme.button("×", func(): _remove(cur), 44)
			x.tooltip_text = "Take it off (%s)" % source.remove_hint().to_lower()
			h.add_child(x)
			box.mouse_entered.connect(func(): _hover = cur; _hover_from_fitted = true; _show_info(cur, ""); _fill_stats())
			box.mouse_exited.connect(func(): if _hover == cur: _hover = ""; _info.visible = false; _fill_stats())
		var a_cur := cur
		box.set_drag_forwarding(func(_p): return _drag_fitted(box, a_cur), func(_p, d): return _can_drop_on_slot(k, d), func(_p, d): _drop_on_slot(d))
		_slots_box.add_child(box)


func _fill_chips() -> void:
	for c in _chips.get_children():
		c.queue_free()
	var kinds := [""]
	for k in KIND_ORDER:
		if not Attach.options(_wid, k).is_empty():
			kinds.append(k)
	if not _filter in kinds:
		_filter = ""
	for k in kinds:
		var kk: String = k
		var b := UITheme.button("All" if kk == "" else str(KIND_NAMES[kk]), func(): _filter = kk; _rebuild_all(), 0)
		b.toggle_mode = true
		b.button_pressed = kk == _filter
		b.add_theme_font_size_override("font_size", 16)
		b.custom_minimum_size = Vector2(0, 38)
		_chips.add_child(b)


func _fill_list(g: Dictionary) -> void:
	for c in _list.get_children():
		c.queue_free()
	var avail: Array = source.available(gun_key, _wid)
	var fitted: Array = g.att
	var by_kind := {}
	for e in avail:
		if str(e.id) in fitted and int(e.get("from", 0)) == 0 and int(e.n) < 0:
			continue   # (loadout) the one already fitted is shown on its mount
		var k := Attach.kind(str(e.id))
		if _filter != "" and k != _filter:
			continue
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(e)
	if by_kind.is_empty():
		var msg := "Nothing in your bag fits this gun." if source is MatchSource else "No attachments for this gun."
		var l := UITheme.label(msg, 18, UITheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		return
	for k in KIND_ORDER:
		if not by_kind.has(k):
			continue
		_list.add_child(UITheme.label(str(KIND_NAMES[k]), 17, UITheme.ACCENT, UITheme.font_semibold))
		for e in by_kind[k]:
			_list.add_child(_card(e, fitted))


func _card(e: Dictionary, fitted: Array) -> Control:
	var id := str(e.id)
	var replaces := Attach.in_slot({"att": fitted}, Attach.kind(id))
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_DRAG
	card.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 8, 12, 8))
	var h := UITheme.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)
	var v := UITheme.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var nm := UITheme.label(Defs.item_name(id), 20, UITheme.TEXT, UITheme.font_semibold)
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(nm)
	var fx := Attach.effects(id, _wid).filter(func(x): return not str(x[0]).begins_with("Weight"))
	var line := ""
	for i in mini(fx.size(), 2):
		line += ("   " if i > 0 else "") + str(fx[i][0])
	var sub := UITheme.label(line, 15, GOOD if not fx.is_empty() and fx[0][1] else UITheme.TEXT_DIM)
	sub.clip_text = true
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(sub)
	var where := str(e.get("where", ""))
	if replaces != "" and replaces != id:
		where = (where + "  ·  " if where != "" else "") + "Replaces " + Defs.item_name(replaces)
	if where != "":
		v.add_child(UITheme.label(where, 14, UITheme.TEXT_DIM))
	var plus := UITheme.label("+", 34, PLUS, UITheme.font_condensed)
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(plus)
	card.mouse_entered.connect(func():
		_hover = id
		_hover_from_fitted = false
		card.add_theme_stylebox_override("panel", UITheme.box(Color(0.35, 1.0, 0.45, 0.08), Color(0.35, 1.0, 0.45, 0.5), 8, 12, 8))
		_show_info(id, replaces)
		_fill_stats())
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 8, 12, 8))
		if _hover == id and not get_viewport().gui_is_dragging():
			_hover = ""
			_info.visible = false
			_fill_stats())
	card.set_drag_forwarding(func(_p): return _drag_card(card, e), Callable(), Callable())
	# A click fits it too (phones, or anyone who would rather not drag).
	card.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
			_fit(e, Vector2.INF))
	return card


func _fill_stats() -> void:
	if _stats_box == null:
		return
	for c in _stats_box.get_children():
		c.queue_free()
	var g := _gun()
	if g.is_empty():
		return
	var now: Array = g.att
	var after: Array = now
	if _hover != "":
		if _hover_from_fitted:
			after = now.filter(func(a): return str(a) != _hover)
		else:
			after = now.filter(func(a): return Attach.kind(str(a)) != Attach.kind(_hover)) + [_hover]
	var base := stats(_wid, [])
	var a := stats(_wid, now)
	var b := stats(_wid, after)
	for i in a.size():
		_stats_box.add_child(_stat_row(a[i], b[i], base[i]))


static func stats(wid: String, att: Array) -> Array:
	## [label, value, lower is better, format] for the numbers the workbench compares.
	var d := Defs.weapon(wid)
	var r: Dictionary = d.get("recoil", {})
	var w := {"id": wid, "att": att}
	var sight := Attach.sight(w)
	return [
		["Vertical recoil", float(r.get("kick_up", 1.0)) * Attach.mult(w, "recoil_up_mult"), true, "%.2f"],
		["Horizontal recoil", float(r.get("kick_side", 1.0)) * Attach.mult(w, "recoil_side_mult"), true, "%.2f"],
		["Recoil recovery", float(r.get("recovery", 10.0)) * Attach.mult(w, "recovery_mult"), false, "%.0f"],
		["Weapon sway", 100.0 * Attach.mult(w, "sway_mult"), true, "%.0f%%"],
		["Aiming time", float(d.get("ads_time", 0.25)) * Attach.mult(w, "ads_time_mult"), true, "%.2f s"],
		["Reload time", float(d.get("reload_time", 2.0)) * Attach.mult(w, "reload_mult"), true, "%.2f s"],
		["Hip-fire spread", float(d.get("spread_hip", 2.0)) * Attach.mult(w, "spread_hip_mult"), true, "%.2f°"],
		["Magazine", float(Attach.mag_cap(w)), false, "%.0f rounds"],
		["Loudness", 100.0 * Attach.mult(w, "loudness_mult"), true, "%.0f%%"],
		["Magnification", float(sight.get("zoom", d.get("sight_zoom", 1.0))), false, "%.1fx"],
	]


func _stat_row(now: Array, after: Array, base: Array) -> Control:
	var h := UITheme.hbox(10)
	h.custom_minimum_size = Vector2(440, 30)
	var l := UITheme.label(str(now[0]), 17, UITheme.TEXT_DIM)
	l.custom_minimum_size = Vector2(132, 0)
	h.add_child(l)
	var v0 := float(now[1])
	var v1 := float(after[1])
	var b := maxf(float(base[1]), 0.001)
	var top := b * 1.7
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(140, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lower := bool(now[2])
	bar.draw.connect(func():
		var W := bar.size.x
		bar.draw_rect(Rect2(0, 0, W, 10), Color(1, 1, 1, 0.07))
		var f0 := clampf(v0 / top, 0.0, 1.0)
		var f1 := clampf(v1 / top, 0.0, 1.0)
		bar.draw_rect(Rect2(0, 0, W * minf(f0, f1), 10), Color(0.85, 0.87, 0.85, 0.85))
		if absf(f1 - f0) > 0.001:
			var better := (v1 < v0) == lower
			bar.draw_rect(Rect2(W * minf(f0, f1), 0, W * absf(f1 - f0), 10), GOOD if better else BAD)
		bar.draw_line(Vector2(W * clampf(b / top, 0.0, 1.0), -2), Vector2(W * clampf(b / top, 0.0, 1.0), 12), Color(1, 1, 1, 0.5), 1.0))
	h.add_child(bar)
	var txt := str(now[3]) % v1
	var val := UITheme.label(txt, 17, UITheme.TEXT)
	val.custom_minimum_size = Vector2(92, 0)
	h.add_child(val)
	if absf(v1 - v0) > 0.0005 * maxf(absf(v0), 1.0):
		var better := (v1 < v0) == lower
		var dl := UITheme.label(("+" if v1 > v0 else "−") + (str(now[3]) % absf(v1 - v0)).replace(" rounds", "").replace(" s", " s"), 16, GOOD if better else BAD, UITheme.font_semibold)
		h.add_child(dl)
	return h


# ------------------------------------------------------------------ the 3D gun

func _set_gun_model() -> void:
	var models = source.models()
	var md: Dictionary = models.item_visual(_wid)
	_gun_mesh.mesh = md.get("mesh")
	_gun_mesh.transform = md.get("xf", Transform3D())
	var sz: Vector3 = md.get("size", Vector3(0.08, 0.1, 0.8))
	_gun_len = maxf(sz.z, 0.2)
	# Centred over the turntable, sized to fill the view whatever the gun.
	var k := 0.9 / _gun_len
	_pivot.scale = Vector3.ONE * k
	_gun_node.position = Vector3(0, -sz.y * 0.5, 0)
	for a in _flying.values():
		if is_instance_valid(a):
			a.queue_free()
	_flying.clear()
	_shown_att = ["?"]   # force the attachments to be built for this gun


func _sync_att_models(att: Array) -> void:
	var want: Array = att.duplicate()
	want.sort()
	if want == _shown_att:
		return
	_shown_att = want
	_gun_mesh.mesh = AttachVisual.gun_mesh(source.models().item_visual(_wid), _wid, att)
	AttachVisual.build(source.models(), _att_root, _wid, att, 1, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	_settle()


func _settle() -> void:
	## A flying copy goes once its flight is over and the gun agrees (has it, or no longer has it); until then the
	## fitted model under it stays hidden. One the server never confirms goes after 2 s.
	var att: Array = _gun().get("att", [])
	var now := Time.get_ticks_msec()
	for id in _flying.keys():
		var n = _flying[id]
		if not is_instance_valid(n):
			_flying.erase(id)
			continue
		var dir: int = n.get_meta("dir", 1)
		var agreed: bool = (dir == 1 and id in att) or (dir == -1 and not id in att)
		if bool(n.get_meta("done", false)) and (agreed or now - int(n.get_meta("t", now)) > 2000):
			n.queue_free()
			_flying.erase(id)
	for c in _att_root.get_children():
		c.visible = not _flying.has(str(c.name))


func _turn(dt: float) -> void:
	if not _turning:
		_yaw += dt * 0.08   # a slow turn by itself
	var dist := 1.9 * _zoom
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_cam.position = Vector3(0, 0.1, dist)
	_cam.look_at(Vector3(0, -0.06, 0), Vector3.UP)


func _view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_turning = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.9, 0.45, 1.8)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom / 0.9, 0.45, 1.8)
	elif ev is InputEventMouseMotion and _turning:
		var rel: Vector2 = (ev as InputEventMouseMotion).relative
		_yaw += rel.x * 0.01
		_pitch = clampf(_pitch + rel.y * 0.006, -0.9, 1.1)
	elif ev is InputEventMagnifyGesture:
		_zoom = clampf(_zoom / (ev as InputEventMagnifyGesture).factor, 0.45, 1.8)


func mount_screen(att: String) -> Vector2:
	## Where an attachment's mount is on the screen (in the 3D view's own coordinates).
	var models = source.models()
	var amd: Dictionary = models.item_visual(att)
	var m: Mesh = amd.get("mesh")
	var centre := m.get_aabb().get_center() if m else Vector3.ZERO
	var local := AttachVisual.mount_xf(models, _wid, att) * centre
	var wp := _gun_node.global_transform * local
	return _cam.unproject_position(wp) * (_vpc.size / Vector2(_vp.size)) if _vp.size.x > 0 else Vector2.ZERO


func _fly(att: String, dir: int) -> void:
	## dir 1: in from beside its mount, snapping on; -1: off the gun and away.
	var models = source.models()
	var amd: Dictionary = models.item_visual(att)
	if amd.get("mesh") == null:
		return
	if _flying.has(att) and is_instance_valid(_flying[att]):
		_flying[att].queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = amd.mesh
	mi.set_meta("dir", dir)
	mi.set_meta("t", Time.get_ticks_msec())
	_gun_node.add_child(mi)
	_flying[att] = mi
	var to := AttachVisual.mount_xf(models, _wid, att)
	var away := Vector3.ZERO
	match Attach.kind(att):
		"sight":
			away = Vector3(0, 0.3, 0)
		"muzzle":
			away = Vector3(0, 0.05, -0.4)
		"stock":
			away = Vector3(0, 0.08, 0.4)
		_:
			away = Vector3(0, -0.3, 0.05)
	var from := Transform3D(Basis(Vector3.UP, 1.4) * to.basis, to.origin + away)
	var a := from if dir == 1 else to
	var b := to if dir == 1 else from
	mi.transform = a
	_settle()
	var tw := create_tween()
	tw.tween_method(func(u: float): if is_instance_valid(mi): mi.transform = a.interpolate_with(b, u), 0.0, 1.0, 0.42 if dir == 1 else 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if dir == 1 else Tween.EASE_IN)
	if dir == 1:
		# The snap: a short bounce, then the burst of green "+".
		tw.tween_method(func(u: float): if is_instance_valid(mi): mi.transform = to.scaled_local(Vector3.ONE * (1.0 + sin(u * PI) * 0.12)), 0.0, 1.0, 0.14)
		tw.tween_callback(func(): _burst(mount_screen(att)); SoundSys.play_local("attach", -2.0))
	else:
		tw.tween_callback(func(): if is_instance_valid(mi): mi.visible = false)
	tw.tween_callback(func(): if is_instance_valid(mi): mi.set_meta("done", true); _settle())


# ------------------------------------------------------------------ drag and drop

func _drag_card(card: Control, e: Dictionary):
	var prev := PanelContainer.new()
	prev.add_theme_stylebox_override("panel", UITheme.box(Color(0.04, 0.07, 0.05, 0.95), Color(0.35, 1.0, 0.45, 0.8), 8, 12, 8))
	prev.add_child(UITheme.label("+  " + Defs.item_name(str(e.id)), 20, PLUS, UITheme.font_semibold))
	card.set_drag_preview(prev)
	_hover = str(e.id)
	_hover_from_fitted = false
	_fill_stats()
	return {"wb_att": e}


func _drag_fitted(box: Control, att: String):
	if att == "":
		return null
	var prev := PanelContainer.new()
	prev.add_theme_stylebox_override("panel", UITheme.box(Color(0.08, 0.04, 0.04, 0.95), Color(0.98, 0.45, 0.4, 0.8), 8, 12, 8))
	prev.add_child(UITheme.label("−  " + Defs.item_name(att), 20, BAD, UITheme.font_semibold))
	box.set_drag_preview(prev)
	return {"wb_fitted": att}


func _can_drop_on_gun(_p: Vector2, d) -> bool:
	return d is Dictionary and d.has("wb_att") and Attach.compatible(_wid, str(d.wb_att.id))


func _drop_on_gun(p: Vector2, d) -> void:
	_fit(d.wb_att, p)


func _can_drop_on_slot(k: String, d) -> bool:
	return d is Dictionary and d.has("wb_att") and Attach.kind(str(d.wb_att.id)) == k and Attach.compatible(_wid, str(d.wb_att.id))


func _drop_on_slot(d) -> void:
	_fit(d.wb_att, Vector2.INF)


func _can_drop_on_list(_p: Vector2, d) -> bool:
	return d is Dictionary and d.has("wb_fitted")


func _drop_on_list(_p: Vector2, d) -> void:
	_remove(str(d.wb_fitted))


func _fit(e: Dictionary, _at: Vector2) -> void:
	var id := str(e.id)
	var g := _gun()
	if g.is_empty() or id in (g.att as Array) and int(e.get("from", 0)) == 0:
		return
	var old := Attach.in_slot(g, Attach.kind(id))
	if old != "" and old != id:
		_fly(old, -1)
	_fly(id, 1)
	source.fit(gun_key, _wid, e)
	_hover = ""
	_info.visible = false


func _remove(att: String) -> void:
	_fly(att, -1)
	SoundSys.play_local("attach", -6.0, 0.8)
	source.remove(gun_key, _wid, att)
	_hover = ""
	_info.visible = false


# ------------------------------------------------------------------ effects over the 3D view

func _burst(at: Vector2) -> void:
	for i in 14:
		var a := randf() * TAU
		var sp := randf_range(70.0, 220.0)
		_parts.append([at + Vector2(cos(a), sin(a)) * 6.0, Vector2(cos(a), sin(a) - 0.6) * sp, 0.0, randf_range(0.6, 1.0), randf_range(22.0, 40.0)])
	_rings.append([at, 0.0])


func _tick_fx(dt: float) -> void:
	for i in range(_parts.size() - 1, -1, -1):
		var p: Array = _parts[i]
		p[2] = float(p[2]) + dt
		p[1] = (p[1] as Vector2) * pow(0.08, dt) + Vector2(0, -40.0) * dt
		p[0] = (p[0] as Vector2) + (p[1] as Vector2) * dt
		if float(p[2]) > float(p[3]):
			_parts.remove_at(i)
	for i in range(_rings.size() - 1, -1, -1):
		_rings[i][1] = float(_rings[i][1]) + dt
		if float(_rings[i][1]) > 0.6:
			_rings.remove_at(i)
	_fx.queue_redraw()


func _draw_fx() -> void:
	var font: Font = UITheme.font_condensed
	for r in _rings:
		var u: float = float(r[1]) / 0.6
		_fx.draw_arc(r[0], 18.0 + u * 90.0, 0.0, TAU, 48, Color(PLUS, (1.0 - u) * 0.8), 3.0 * (1.0 - u) + 1.0, true)
	for p in _parts:
		var u: float = float(p[2]) / float(p[3])
		var s: float = float(p[4]) * (0.6 + 0.6 * sin(minf(u * 3.0, 1.0) * PI * 0.5))
		_fx.draw_string(font, (p[0] as Vector2) - Vector2(s * 0.3, -s * 0.35), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, int(s), Color(PLUS, 1.0 - u * u))
	# While an attachment is dragged: its mount on the gun pulses, with what dropping it does.
	if get_viewport().gui_is_dragging():
		var d = get_viewport().gui_get_drag_data()
		if d is Dictionary and d.has("wb_att") and Attach.compatible(_wid, str(d.wb_att.id)):
			var id := str(d.wb_att.id)
			var at := mount_screen(id)
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
			_fx.draw_circle(at, 10.0, Color(PLUS, 0.9))
			_fx.draw_arc(at, 22.0 + pulse * 10.0, 0.0, TAU, 40, Color(PLUS, 0.85 - pulse * 0.4), 3.0, true)
			var old := Attach.in_slot(_gun(), Attach.kind(id))
			var t := "%s mount" % str(KIND_NAMES.get(Attach.kind(id), "")) + ("  ·  replaces %s" % Defs.item_name(old) if old != "" and old != id else "")
			_fx.draw_string(UITheme.font_semibold, at + Vector2(30, -26), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(PLUS, 0.95))


# ------------------------------------------------------------------ the hover card

func _show_info(id: String, replaces: String) -> void:
	for c in _info_v.get_children():
		c.queue_free()
	var a: Dictionary = Defs.attachments.get(id, {})
	_info_v.add_child(UITheme.label(Defs.item_name(id), 24, UITheme.TEXT, UITheme.font_condensed))
	_info_v.add_child(UITheme.label(str(KIND_NAMES.get(Attach.kind(id), "")) + " attachment", 15, UITheme.ACCENT, UITheme.font_semibold))
	if a.has("desc"):
		var dl := UITheme.label(str(a.desc), 17, UITheme.TEXT_DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(350, 0)
		_info_v.add_child(dl)
	_info_v.add_child(UITheme.spacer(4))
	for e in Attach.effects(id, _wid):
		var good: bool = e[1]
		var row := UITheme.hbox(8)
		row.add_child(UITheme.label("▲" if good else "▼", 14, GOOD if good else BAD))
		var l := UITheme.label(str(e[0]), 18, GOOD if good else BAD)
		if str(e[0]).begins_with("Weight"):
			l.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		row.add_child(l)
		_info_v.add_child(row)
	if replaces != "" and replaces != id:
		_info_v.add_child(UITheme.label("Replaces your %s" % Defs.item_name(replaces), 15, UITheme.WARN))
	_info.visible = true
	_info.reset_size()


func _place_info() -> void:
	if not _info.visible:
		return
	var m := get_local_mouse_position()
	var p := m + Vector2(28, 18)
	if p.x + _info.size.x > size.x - 12:
		p.x = m.x - _info.size.x - 28
	p.y = clampf(p.y, 12, size.y - _info.size.y - 12)
	_info.position = p


# ------------------------------------------------------------------ closing

func _input(ev: InputEvent) -> void:
	# _input, not _unhandled_input: the player controller would take Esc as "pause" first.
	if ev.is_action_pressed("menu") or ev.is_action_pressed("workbench") or ev.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit()
	queue_free()
