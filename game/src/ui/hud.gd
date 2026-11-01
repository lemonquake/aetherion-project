extends CanvasLayer
## In-play overlay, kept to a minimum: a small reticle that sits where the weapon actually points, context prompts
## only when something can be used, quiet toasts, a damage vignette, plane/parachute hints, results.
## Also owns the SmarTab viewport whose texture appears on the device in the player's hand.
const DayCycle := preload("res://src/world/day_cycle.gd")

const SmarTabUI := preload("res://src/ui/smartab_ui.gd")
const Interaction := preload("res://src/match/interaction.gd")

var world = null
var ch = null
var tab_held := false
var map_held := false
var root: Control
var reticle: Control
var scope: Control
var prompt: Label
var toast_label: Label
var hint: Label
var vignette: ColorRect
var field_fx: ColorRect          # r12: the forcefield's crackle round the screen while you are in it
var field_label: Label
var death_card: Control          # r13: who killed you, over the camera on your body
var _field_k := 0.0
var treat_label: Label
var _treat_t := -1.0
var _treat_item := ""
var results: Control
var loading: Control
var spect_label: Label
var _spect_eid := -1
var _spect_at := 0
var chat_box: VBoxContainer
var chat_edit: LineEdit
var smartab_vp: SubViewport
var _tab_vis_t := 0.0
var smartab: Control
var item_icons: Node   # r14: item icons rendered from their models (item_icons.gd)
var blast_flash: ColorRect
var _toast_t := 0.0
var _hurt := 0.0
var _prev_health := -1.0
var _was_tab := false
var _prompt_t := 0.0
var minimap: Control
var compass: Control
var marks: Control       # ui/world_marks.gd: teammates' names, pinged spots
var _supp := 0.0         # near-miss suppression (Effects.flyby)
var pa_banner: Control   # loudspeaker countdown (audio/announcer.gd drives it)
var _pa_t := 0.0
var frags_label: Label
var fire_mode_label: Label
var _frags_t := 0.0
## r7 Deathmatch: both teams' names and how many of each are still standing (top centre), a kill feed (top
## right), and spectator controls.
var team_bar: Control = null
var _team_labels: Array = []   # [name Label, count Label] per team
var kill_feed: VBoxContainer = null
var spect_hint: Label
var spect_buttons: Control = null
var _dm_intro_done := false
## (r17) A Deathmatch won on score or time: the team bar shows each team's score, a line under it the goal or the
## clock, and a dead player sees when they come back.
var _goal_label: Label = null
var _goal_text := ""
var _respawn_label: Label = null
var _died_at := -1.0
const MAP_TITLES := {"kalinaw": "Sitio Kalinaw", "lawless_sub": "Lawless Sub", "malasugue_mall": "Malasugue Mall", "freight_delight": "Freight Delight"}


func setup(w) -> void:
	world = w
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.get_theme()
	add_child(root)
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = """shader_type canvas_item;
uniform float amount = 0.0;
uniform float low = 0.0;
uniform float supp = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.35, 0.85, d);
	float s = smoothstep(0.18, 0.75, d) * supp;
	vec3 col = mix(vec3(0.0), vec3(0.35, 0.0, 0.0), amount / max(amount + s * 0.6, 0.001));
	COLOR = vec4(col, clamp(v * (amount * 0.75 + low * 0.35) + s * 0.55, 0.0, 0.9));
}"""
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vignette.material = vm
	root.add_child(vignette)
	# r12: inside the forcefield the screen edges crackle white, harder the deeper you are; red when it pins you.
	field_fx = ColorRect.new()
	field_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := Shader.new()
	fs.code = """shader_type canvas_item;
render_mode blend_add;
uniform float amount = 0.0;
uniform float pin = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
void fragment() {
	vec2 q = UV - 0.5;
	float d = length(q * vec2(1.6, 1.0));
	float edge = smoothstep(0.32, 0.8, d);
	float tk = mod(floor(TIME * 18.0), 997.0);   // wrapped: a large offset loses float precision (blocky noise)
	float n = vnoise(UV * vec2(9.0, 6.0) + vec2(tk * 1.3, tk * 0.7));
	float arc = (1.0 - smoothstep(0.0, 0.03, abs(n - 0.5))) * smoothstep(0.35, 0.5, vnoise(UV * 3.0 + tk * 0.21));
	float scan = 0.5 + 0.5 * sin(UV.y * 420.0 + TIME * 30.0);
	float a = amount * (edge * (0.45 + 0.25 * scan) + arc * edge * 1.2 + 0.05 * hash(floor(UV * vec2(480.0, 270.0)) + vec2(tk, tk * 0.37)));
	vec3 col = mix(vec3(0.75, 0.86, 1.0), vec3(1.0, 0.25, 0.2), pin);
	COLOR = vec4(col * a, 1.0);
}"""
	var fm := ShaderMaterial.new()
	fm.shader = fs
	field_fx.material = fm
	field_fx.visible = false
	root.add_child(field_fx)
	field_label = Label.new()
	field_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	field_label.position.y = 120
	field_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	field_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	field_label.add_theme_font_size_override("font_size", 22)
	field_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	field_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	field_label.add_theme_constant_override("outline_size", 6)
	field_label.text = "The field is pushing you in. Keep clear of walls."
	field_label.visible = false
	root.add_child(field_label)
	death_card = preload("res://src/ui/death_card.gd").new()
	root.add_child(death_card)
	treat_label = UITheme.label("", 20, Color(0.92, 0.95, 0.92))
	treat_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	treat_label.position = Vector2(-250, -160)
	treat_label.size = Vector2(500, 30)
	treat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	treat_label.visible = false
	root.add_child(treat_label)
	marks = preload("res://src/ui/world_marks.gd").new()
	root.add_child(marks)
	marks.setup(world)
	scope = preload("res://src/ui/scope_overlay.gd").new()
	scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope.visible = false
	scope.set("world", world)
	root.add_child(scope)
	reticle = preload("res://src/ui/reticle.gd").new()
	reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reticle)
	var cook_ring := preload("res://src/ui/cook_ring.gd").new()
	cook_ring.world = world
	root.add_child(cook_ring)
	# r14: a grenade going off close by whites out the view for a moment.
	blast_flash = ColorRect.new()
	blast_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blast_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blast_flash.color = Color(1.0, 0.95, 0.85, 0.0)
	root.add_child(blast_flash)
	prompt = UITheme.label("", 20, Color(0.85, 0.88, 0.86, 0.9))
	prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.position = Vector2(-300, -170)
	prompt.size = Vector2(600, 30)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt)
	toast_label = UITheme.label("", 21, Color(0.86, 0.88, 0.86))
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(-400, 90)
	toast_label.size = Vector2(800, 30)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(toast_label)
	hint = UITheme.label("", 19, Color(0.75, 0.8, 0.78, 0.85))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-400, -110)
	hint.size = Vector2(800, 30)
	if Settings.touch_active():
		hint.size.y = 70
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)
	spect_label = UITheme.label("", 20, Color(0.8, 0.82, 0.8))
	spect_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spect_label.position = Vector2(-500, -70)
	spect_label.size = Vector2(1000, 30)
	spect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(spect_label)
	spect_hint = UITheme.label("", 17, Color(0.72, 0.76, 0.74, 0.9))
	spect_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spect_hint.position = Vector2(-640, -42)
	spect_hint.size = Vector2(1280, 26)
	spect_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(spect_hint)
	kill_feed = UITheme.vbox(4)
	kill_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_feed.position = Vector2(-520, 20)
	kill_feed.size = Vector2(500, 10)
	kill_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	kill_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(kill_feed)
	chat_box = UITheme.vbox(2)
	chat_box.position = Vector2(24, 0)
	chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_box.position = Vector2(24, -260)
	root.add_child(chat_box)
	# SmarTab screen
	# r14: the hologram's picture, transparent where nothing is drawn, sized to the hologram on the window (the UI
	# keeps its 1600 x 960 layout and is scaled into it; its fonts are distance fields, sharp at any scale).
	smartab_vp = SubViewport.new()
	smartab_vp.size = Vector2i(1600, 960)
	smartab_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	smartab_vp.transparent_bg = true
	smartab_vp.gui_disable_input = false
	add_child(smartab_vp)
	smartab = SmarTabUI.new()
	smartab_vp.add_child(smartab)
	smartab.set_world(world)
	item_icons = preload("res://src/ui/item_icons.gd").new()
	add_child(item_icons)
	item_icons.setup(world.map)
	smartab.icons = item_icons
	smartab.request.connect(func(req): world.request_voice(str(req.line)) if str(req.get("op", "")) == "voice" else world.request_inventory(req))
	minimap = preload("res://src/ui/minimap.gd").new()
	minimap.position = Vector2(150, 20) if Settings.touch_active() else Vector2(20, 20)
	minimap.size = Vector2(230, 230)
	root.add_child(minimap)
	minimap.setup(world)
	compass = preload("res://src/ui/compass.gd").new()
	compass.position = minimap.position + Vector2(0, minimap.size.y + 8)
	compass.size = Vector2(minimap.size.x, 40)
	root.add_child(compass)
	compass.setup(world)
	frags_label = UITheme.label("", 18, Color(0.82, 0.86, 0.8, 0.9))
	frags_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	frags_label.position = Vector2(-420, -60)
	frags_label.size = Vector2(400, 28)
	frags_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(frags_label)
	fire_mode_label = UITheme.label("", 23, UITheme.TEXT, UITheme.font_semibold)
	fire_mode_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fire_mode_label.position = Vector2(-420, -100)
	fire_mode_label.size = Vector2(400, 32)
	fire_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fire_mode_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	fire_mode_label.add_theme_constant_override("outline_size", 5)
	root.add_child(fire_mode_label)
	_build_loading()
	Net.lobby_changed.connect(func(): pass)


func set_character(c) -> void:
	ch = c
	if c != null:
		# (r17) back in after a respawn
		_died_at = -1.0
		death_card.hide_report()
		set_spectating(null)
		if spect_buttons:
			spect_buttons.queue_free()
			spect_buttons = null
		if _respawn_label:
			_respawn_label.visible = false
	if world.controller and world.controller.vm:
		world.controller.vm.set_screen_texture(smartab_vp.get_texture())


func _build_loading() -> void:
	loading = ColorRect.new()
	(loading as ColorRect).color = Color(0.01, 0.012, 0.016)
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := str(MAP_TITLES.get(str(Net.config.get("map", "kalinaw")), "Sitio Kalinaw"))
	if Net.is_dm():
		title += "  ·  Deathmatch"
	var l := UITheme.label(title, 54, Color(0.86, 0.88, 0.86), UITheme.font_condensed)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-220, -60)
	loading.add_child(l)
	var s := UITheme.label("Waiting for every player to arrive…", 22, UITheme.TEXT_DIM)
	s.set_anchors_preset(Control.PRESET_CENTER)
	s.position = Vector2(-220, 10)
	loading.add_child(s)
	root.add_child(loading)
	# The full loading screen (ui/loading_screen.gd) covers this; it shows only if that one is missing.
	loading.visible = Game.state == "loading" and Game.loading_screen == null
	Game.state_changed.connect(func(st): loading.visible = st == "loading" and Game.loading_screen == null)


# ------------------------------------------------------------------ events from the world

func on_owner_state() -> void:
	if ch == null:
		return
	var hp: float = ch.health.health
	if _prev_health >= 0.0 and hp < _prev_health - 0.5:
		_hurt = minf(_hurt + (_prev_health - hp) / 40.0, 1.0)
	_prev_health = hp


func on_match_state(info: Dictionary) -> void:
	if str(info.get("game_mode", "classic")) != "deathmatch":
		return
	_ensure_team_bar(info)
	_update_team_bar(info)
	if not _dm_intro_done and str(info.get("phase", "")) == "playing":
		_dm_intro_done = true
		var mine := _my_team()
		var names: Array = info.get("team_names", [])
		if mine >= 0 and mine < names.size() and names.size() >= 2:
			var others := []
			for t in names.size():
				if t != mine:
					others.append(str(names[t]))
			match str(info.get("win_by", "wipe")):
				"wipe":
					toast("You are on the %s. Last team standing earns 1 point. First to %d points wins." % [str(names[mine]), int(info.get("score_limit", 10))])
				"score":
					toast("You are on the %s. First team to %d kills wins. You respawn when you fall." % [str(names[mine]), int(info.get("score_limit", 30))])
				"time":
					toast("You are on the %s. Most kills in %d minutes wins. You respawn when you fall." % [str(names[mine]), int(float(info.get("time_limit", 840.0)) / 60.0)])
				_:
					toast("You are on the %s. Eliminate the %s and stay inside the field." % [str(names[mine]), " and the ".join(others)])


func _my_team() -> int:
	return int(Net.players.get(Net.local_pid, {}).get("team", -1))


func _ensure_team_bar(info: Dictionary) -> void:
	if team_bar:
		return
	var names: Array = info.get("team_names", ["North Team", "East Team", "South Team"])
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.03, 0.62)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UITheme.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	_team_labels = []
	for t in maxi(names.size(), 2):
		var col: Color = UITheme.TEAM_COLORS[t % UITheme.TEAM_COLORS.size()]
		# The final text from the start (" (you)" added later overflowed the bar, which was already sized: "est Team").
		var base := str(names[t]) if t < names.size() else "Team %d" % (t + 1)
		var nm := UITheme.label(base + (" (you)" if t == _my_team() else ""), 24, col, UITheme.font_condensed)
		nm.set_meta("base", base)
		nm.clip_text = false
		# (r24) how many of the team are still standing, always shown under its name
		var alive_l := UITheme.label("", 16, Color(0.85, 0.87, 0.84), UITheme.font_semibold)
		alive_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		alive_l.add_theme_constant_override("outline_size", 4)
		alive_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if t == 0 else HORIZONTAL_ALIGNMENT_LEFT
		var name_col := VBoxContainer.new()
		name_col.add_theme_constant_override("separation", -4)
		name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_col.add_child(nm)
		name_col.add_child(alive_l)
		nm.horizontal_alignment = alive_l.horizontal_alignment
		var cnt := UITheme.label("0", 38, Color(0.95, 0.96, 0.94), UITheme.font_condensed)
		cnt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		cnt.add_theme_constant_override("outline_size", 6)
		cnt.custom_minimum_size = Vector2(44, 0)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if t > 0:
			row.add_child(UITheme.label("vs", 20, UITheme.TEXT_DIM))
		if t == 0:
			row.add_child(name_col)
			row.add_child(cnt)
		else:
			row.add_child(cnt)
			row.add_child(name_col)
		_team_labels.append([nm, cnt, alive_l])
	team_bar = Control.new()
	team_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	team_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	team_bar.position = Vector2(0, 14)
	team_bar.add_child(panel)
	root.add_child(team_bar)
	panel.resized.connect(func(): panel.position = Vector2(-panel.size.x * 0.5, 0))
	# (r17) centred once laid out too: the first resize can land before the connection (the bar sat right of centre)
	(func(): panel.position = Vector2(-panel.size.x * 0.5, 0)).call_deferred()
	if info.has("score"):
		# (r17) under the bar: the score to reach, or the time left
		_goal_label = UITheme.label("", 20, Color(0.92, 0.93, 0.9), UITheme.font_semibold)
		_goal_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_goal_label.add_theme_constant_override("outline_size", 5)
		_goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_goal_label.size = Vector2(900, 32)
		_goal_label.position = Vector2(-450, 62)
		team_bar.add_child(_goal_label)


func _update_team_bar(info: Dictionary) -> void:
	if _team_labels.is_empty():
		return
	var alive: Dictionary = info.get("alive", {})
	var score: Dictionary = info.get("score", {})
	var mine := _my_team()
	for t in _team_labels.size():
		var n := int(alive.get(t, alive.get(str(t), 0)))
		if info.has("score"):
			n = int(score.get(t, score.get(str(t), 0)))   # (r17) a respawn round counts kills, not who is standing
		var nm: Label = _team_labels[t][0]
		var cnt: Label = _team_labels[t][1]
		cnt.text = str(n)
		var standing := int(alive.get(t, alive.get(str(t), 0)))
		var al: Label = _team_labels[t][2]
		var at := ("%d alive" % standing) if standing > 0 else "Out"
		if al.text != at:
			al.text = at
			al.modulate = Color(1, 1, 1, 1.0) if standing > 0 else Color(1, 0.55, 0.5, 0.9)
		cnt.modulate = Color(1, 1, 1, 1.0 if n > 0 or info.has("score") else 0.45)
		var base: String = nm.get_meta("base", nm.text)
		nm.set_meta("base", base)
		nm.text = base + (" (you)" if t == mine else "")


func add_kill(killer: String, killer_team: int, victim: String, victim_team: int, how: String) -> void:
	## One line of the kill feed: killer in their team colour, the weapon (or the cause), the victim.
	if kill_feed == null:
		return
	var row := UITheme.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := Color(0.8, 0.82, 0.8)
	if killer != "":
		row.add_child(_feed_label(killer, UITheme.TEAM_COLORS[killer_team % UITheme.TEAM_COLORS.size()] if killer_team >= 0 else dim))
	row.add_child(_feed_label("[%s]" % how if how != "" else "killed", Color(0.7, 0.72, 0.7)))
	row.add_child(_feed_label(victim, UITheme.TEAM_COLORS[victim_team % UITheme.TEAM_COLORS.size()] if victim_team >= 0 else dim))
	kill_feed.add_child(row)
	while kill_feed.get_child_count() > 6:
		var old := kill_feed.get_child(0)
		kill_feed.remove_child(old)
		old.queue_free()
	get_tree().create_timer(9.0).timeout.connect(row.queue_free)   # dropped by itself if the row goes first


func _feed_label(text: String, col: Color) -> Label:
	var l := UITheme.label(text, 19, col, UITheme.font_semibold)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


func add_ping(eid: int, pos: Vector3) -> void:
	minimap.add_ping(eid, pos, ch != null and is_instance_valid(ch) and ch.eid == eid)
	marks.add_ping(eid, pos)
	SoundSys.play_local("radio_click", -3.0)


func radio_line(who: String, text: String) -> void:
	## What a teammate bot just said on the radio, bottom left for a few seconds.
	var l := UITheme.label("[Radio] %s: %s" % [who, text], 19, Color(0.62, 0.95, 0.72))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	chat_box.add_child(l)
	while chat_box.get_child_count() > 6:
		var old := chat_box.get_child(0)
		chat_box.remove_child(old)
		old.queue_free()
	get_tree().create_timer(7.0).timeout.connect(l.queue_free)


func blast(strength: float) -> void:
	## r14: a grenade close by: the view whites out (less with Reduce flashes) and the hurt edge flares.
	var a := strength * (0.18 if bool(Settings.get_value("accessibility", "reduce_flashes")) else 0.62)
	blast_flash.color.a = maxf(blast_flash.color.a, a)
	_hurt = minf(_hurt + strength * 0.5, 1.0)


func toast(text: String) -> void:
	toast_label.text = text
	_toast_t = 6.0


func show_container(kind: String, id: int, entries: Array) -> void:
	var page = smartab.page
	smartab.show_container(kind, id, entries)
	if map_held:
		smartab.page = page  # the map stays up; the box is on the Items page when Tab is used next
	if not tab_held and not Input.is_action_pressed("smartab"):
		toast("Tap Phone to see what's inside." if Settings.touch_active() else "Hold TAB to see what's inside.")


func on_local_died() -> void:
	reticle.visible = false
	prompt.text = ""
	field_fx.visible = false
	field_label.visible = false


func show_death_report(info: Dictionary) -> void:
	death_card.show_report(info)
	if world.match_info.has("respawn_s") and str(world.match_info.get("phase", "")) == "playing":
		_died_at = Time.get_ticks_msec() / 1000.0   # (r17) a respawn round: count down to coming back


func set_spectating(t) -> void:
	## Called every frame by the spectator camera: the labels change only when what they say changes (setting a
	## Label's text re-shapes and re-lays it out, every frame for nothing).
	var ctl = world.controller
	var free: bool = ctl != null and ctl.spect_view == ctl.SpectView.FREE and ctl.can_free_camera()
	if t or free:
		var now := Time.get_ticks_msec()
		var key: int = t.eid if t else -2
		if key == _spect_eid and now - _spect_at < 500:
			return
		_spect_eid = key
		_spect_at = now
		var mine := _my_team()
		var mates := 0
		for c in world.characters.values():
			if c.team == mine and c.mode not in [Motor.DEAD, Motor.SPECTATE]:
				mates += 1
		var who := "Free camera"
		if t:
			who = "Watching %s" % t.pname
			if t.team != mine:
				who += " (%s)" % UITheme.team_name(t.team)
			if free:
				who = "Free camera  ·  selected " + str(t.pname)
		var s := who + ("  ·  %d teammate%s still standing" % [mates, "" if mates == 1 else "s"] if mates > 0 else "  ·  your team is out")
		if spect_label.text != s:
			spect_label.text = s
		if Settings.touch_active():
			spect_hint.text = ""
			_ensure_spect_buttons()
		else:
			# r24: the camera view and who can be watched are spectator options too.
			var h := "Click: next    Right click: previous    E: camera (%s)" % ctl.SPECT_VIEW_NAMES[ctl.spect_view] if ctl else ""
			if ctl and ctl.can_watch_enemies():
				h += "    R: watch %s" % ("teammates only" if ctl.spect_all else "everyone")
			if free:
				h += "    Move keys fly, Space up, C down"
			if spect_hint.text != h:
				spect_hint.text = h
	else:
		_spect_eid = -1
		if spect_label.text != "":
			spect_label.text = ""
			spect_hint.text = ""


func spect_changed() -> void:
	## The spectator view or watch list changed: rewrite the labels now, not up to half a second later.
	_spect_at = 0


func _ensure_spect_buttons() -> void:
	if spect_buttons:
		return
	var row := UITheme.hbox(16)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.position = Vector2(-340, -150)
	row.size = Vector2(680, 64)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(UITheme.button("Previous", func(): if world.controller: world.controller.spectate_cycle(-1), 150))
	row.add_child(UITheme.button("Next", func(): if world.controller: world.controller.spectate_cycle(1), 150))
	row.add_child(UITheme.button("Camera", func(): if world.controller: world.controller.spectate_next_view(), 150))
	if world.controller and world.controller.can_watch_enemies():
		row.add_child(UITheme.button("Everyone", func(): if world.controller: world.controller.spectate_toggle_all(), 150))
	root.add_child(row)
	spect_buttons = row


func show_results(summary: Dictionary) -> void:
	results = preload("res://src/ui/results_ui.gd").new(summary)
	Game.show_screen(results)


func open_text_chat() -> void:
	if chat_edit:
		return
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Message your team" if Settings.touch_active() else "Message your team (Enter sends, Esc cancels)"
	chat_edit.custom_minimum_size = Vector2(420, 36)
	chat_edit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_edit.position = Vector2(24, -210)
	root.add_child(chat_edit)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	chat_edit.grab_focus()
	chat_edit.text_submitted.connect(func(t):
		if t.strip_edges() != "":
			world.send_text(t.strip_edges())
		_close_chat())
	chat_edit.gui_input.connect(func(e): if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE: _close_chat())


func _close_chat() -> void:
	if chat_edit:
		chat_edit.queue_free()
		chat_edit = null
	Input.mouse_mode = Settings.play_mouse_mode()


func add_chat(from: String, text: String) -> void:
	var l := UITheme.label("%s: %s" % [from, text], 18, Color(0.75, 0.9, 0.8))
	chat_box.add_child(l)
	get_tree().create_timer(12.0).timeout.connect(l.queue_free)


# ------------------------------------------------------------------ per frame

func suppress(amount: float) -> void:
	_supp = minf(_supp + amount * 0.6, 1.0)


func pa_countdown(n: int, kind: String) -> void:
	## The loudspeaker countdown, shown large under the compass: 10 ... 1, then the change itself.
	if pa_banner == null:
		pa_banner = UITheme.vbox(0)
		pa_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
		pa_banner.position = Vector2(-220, 128)
		pa_banner.size = Vector2(440, 120)
		pa_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := UITheme.label("", 22, Color(0.95, 0.85, 0.55), UITheme.font_semibold)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.name = "Cap"
		pa_banner.add_child(cap)
		var num := UITheme.label("", 64, Color(1.0, 0.93, 0.75), UITheme.font_condensed)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		num.add_theme_constant_override("outline_size", 8)
		num.name = "Num"
		pa_banner.add_child(num)
		root.add_child(pa_banner)
	var cap: Label = pa_banner.get_node("Cap")
	var num: Label = pa_banner.get_node("Num")
	if n > 0:
		cap.text = "Sunrise in" if kind == "ignite" else "Lights out in"
		num.text = str(n)
	else:
		cap.text = ""
		num.text = "The sun ignites" if kind == "ignite" else "Lights out"
		num.add_theme_font_size_override("font_size", 48)
	if n > 0:
		num.add_theme_font_size_override("font_size", 64)
	pa_banner.modulate.a = 1.0
	_pa_t = 1.15 if n > 1 else 3.0


func _treat_ui(dt: float) -> void:
	## r12: while treating a wound, what and how long is left (own clock from the moment the server said it began).
	var busy: bool = ch != null and is_instance_valid(ch) and (ch.flags & Character.F_HEAL) != 0
	if not busy:
		_treat_t = -1.0
		treat_label.visible = false
		return
	if _treat_t < 0.0:
		_treat_t = 0.0
		_treat_item = str(ch.health.treatment.get("item", "bandage")) if ch.health else "bandage"
	_treat_t += dt
	var total := float(Defs.item(_treat_item).get("use_time", 2.0))
	treat_label.visible = true
	treat_label.text = "%s  %.1f s" % [{"bandage": "Bandaging", "first_aid": "Using the first aid kit", "splint": "Splinting",
		"painkillers": "Taking painkillers"}.get(_treat_item, "Treating"), maxf(total - _treat_t, 0.0)]


func _round_ui() -> void:
	## (r17) The goal or the clock under the team bar, and the respawn countdown while dead.
	var info: Dictionary = world.match_info
	if _goal_label and info.has("score"):
		var s := ""
		if str(info.get("win_by", "")) == "time":
			var el := ((Net.interp_tick() if not world.is_server else float(Net.tick)) - float(info.get("t0", 0))) / Defs.TICK_RATE
			var left := maxi(int(ceil(float(info.get("time_limit", 0.0)) - el)), 0)
			s = "%d:%02d left  ·  most kills wins" % [left / 60, left % 60]
		elif str(info.get("win_by", "")) == "wipe":
			s = "Round %d · First to %d points" % [int(info.get("round", 1)), int(info.get("score_limit", 10))]
			if str(info.get("phase", "")) == "round_end":
				var left := maxi(ceili((float(info.get("next_round_at", 0)) - float(Net.tick)) / Defs.TICK_RATE), 0)
				var winner := int(info.get("round_winner", -1))
				var names: Array = info.get("team_names", [])
				s = ("%s +1 point" % str(names[winner]) if winner >= 0 and winner < names.size() else "Round draw") + " · Next round in %d" % left
				_round_banner_show(winner, names, left)
			elif _round_banner:
				_round_banner.visible = false
		else:
			s = "First to %d kills" % int(info.get("score_limit", 30))
		if s != _goal_text:
			_goal_text = s
			_goal_label.text = s
	if _died_at < 0.0:
		return
	if _respawn_label == null:
		_respawn_label = UITheme.label("", 34, Color(0.95, 0.96, 0.94), UITheme.font_condensed)
		_respawn_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_respawn_label.add_theme_constant_override("outline_size", 7)
		_respawn_label.set_anchors_preset(Control.PRESET_CENTER)
		_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_respawn_label.size = Vector2(600, 48)
		_respawn_label.position = Vector2(-300, 120)
		root.add_child(_respawn_label)
	var left_s := float(info.get("respawn_s", 5.0)) - (Time.get_ticks_msec() / 1000.0 - _died_at)
	_respawn_label.visible = info.has("respawn_s") and str(info.get("phase", "")) == "playing"
	var t := "Respawning in %d" % maxi(int(ceil(left_s)), 1) if left_s > 0.0 else "Respawning..."
	if _respawn_label.text != t:
		_respawn_label.text = t


var _round_banner: Control = null
var _round_banner_title: Label
var _round_banner_count: Label


func _round_banner_show(winner: int, names: Array, left: int) -> void:
	## (r24) "<Team> wins the round" in the team's colour, then the seconds to the next round.
	if _round_banner == null:
		_round_banner = UITheme.vbox(2)
		_round_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_round_banner.set_anchors_preset(Control.PRESET_CENTER)
		_round_banner.size = Vector2(1200, 150)
		_round_banner.position = Vector2(-600, -230)
		_round_banner_title = UITheme.label("", 64, UITheme.TEXT, UITheme.font_condensed)
		_round_banner_count = UITheme.label("", 30, Color(0.95, 0.96, 0.94), UITheme.font_semibold)
		for l in [_round_banner_title, _round_banner_count]:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			l.add_theme_constant_override("outline_size", 9)
			_round_banner.add_child(l)
		root.add_child(_round_banner)
	var title := "Nobody wins the round"
	var col := UITheme.TEXT
	if winner >= 0 and winner < names.size():
		title = "%s wins the round" % str(names[winner])
		col = UITheme.TEAM_COLORS[winner % UITheme.TEAM_COLORS.size()]
	if _round_banner_title.text != title:
		_round_banner_title.text = title
		_round_banner_title.add_theme_color_override("font_color", col)
	var c := "Next round in %d" % maxi(left, 1)
	if _round_banner_count.text != c:
		_round_banner_count.text = c
	_round_banner.visible = true


# ------------------------------------------------------------------ r24: the scoreboard (hold ~)

var scoreboard = null
var _board_req_t := 0.0


func _scoreboard_ui(dt: float) -> void:
	var want: bool = Input.is_action_pressed("scoreboard") and not tab_held and not map_held and chat_edit == null \
		and (world.controller == null or not world.controller.paused)
	if not want:
		if scoreboard:
			scoreboard.visible = false
		return
	if scoreboard == null:
		# Centred under the team bar by a full-screen column (a Control's position is not anchor-relative).
		var holder := VBoxContainer.new()
		holder.name = "ScoreboardHolder"
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(UITheme.spacer(96))
		scoreboard = preload("res://src/ui/scoreboard.gd").new()
		scoreboard.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		holder.add_child(scoreboard)
		root.add_child(holder)
	scoreboard.visible = true
	_board_req_t -= dt
	if _board_req_t <= 0.0:
		_board_req_t = 0.5
		world.request_board()
	var info: Dictionary = world.match_info
	var title := "Scoreboard"
	if info.has("round") and str(info.get("win_by", "")) == "wipe":
		title = "Scoreboard  ·  Round %d" % int(info.round)
	scoreboard.set_title(title)
	scoreboard.show_rows(world.board_rows, info, Net.local_pid)


func _field_overlay(dt: float) -> void:
	var target := 0.0
	var pin := 0.0
	if ch and is_instance_valid(ch) and ch.mode in [Motor.GROUND, Motor.DOWNED]:
		var tick := Net.interp_tick() if not world.is_server else float(Net.tick)
		var fi := Field.at(world, ch.global_position, tick)
		if bool(fi.on) and not Field.legacy_haze and (Field.test_only.is_empty() or ch.eid in Field.test_only):
			target = clampf(0.45 + float(fi.pen) * 0.25, 0.45, 1.0)
		pin = clampf(ch.field_pin / (Field.CRUSH_PIN_S * 3.0), 0.0, 1.0)   # (r17) the squeeze builds over ~0.6 s
	_field_k = move_toward(_field_k, target, dt * 3.0)
	field_fx.visible = _field_k > 0.01
	field_label.visible = _field_k > 0.3
	if field_fx.visible:
		var m := field_fx.material as ShaderMaterial
		m.set_shader_parameter("amount", _field_k)
		m.set_shader_parameter("pin", pin)


func _process(dt: float) -> void:
	_toast_t -= dt
	toast_label.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if pa_banner:
		_pa_t -= dt
		pa_banner.modulate.a = clampf(_pa_t / 0.25, 0.0, 1.0)
	_hurt = move_toward(_hurt, 0.0, dt * 0.6)
	if blast_flash.color.a > 0.0:
		blast_flash.color.a = move_toward(blast_flash.color.a, 0.0, dt * 0.9)
	var low := 0.0
	if ch and is_instance_valid(ch):
		low = clampf((40.0 - ch.health.health) / 40.0, 0.0, 1.0)
	(vignette.material as ShaderMaterial).set_shader_parameter("amount", _hurt)
	(vignette.material as ShaderMaterial).set_shader_parameter("low", low)
	_supp = move_toward(_supp, 0.0, dt * 0.7)
	(vignette.material as ShaderMaterial).set_shader_parameter("supp", _supp)
	_field_overlay(dt)
	_treat_ui(dt)
	_round_ui()
	_scoreboard_ui(dt)
	# The SmarTab screen renders only while the device is up, plus its lowering animation.
	_tab_vis_t = 0.8 if (tab_held or map_held) else maxf(_tab_vis_t - dt, 0.0)
	# The hologram fills most of the view: the score and kill feed would sit on top of its edges (the minimap and
	# compass hide themselves).
	for n in [team_bar, kill_feed]:
		if n:
			n.visible = not (tab_held or map_held)
	smartab_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _tab_vis_t > 0.0 else SubViewport.UPDATE_DISABLED
	if _tab_vis_t > 0.0 and world.controller and world.controller.vm:
		var k := clampf(float(world.controller.vm.panel_px_h) / 960.0, 0.5, 1.6)
		var want := Vector2i(int(round(1600.0 * k)), int(round(960.0 * k)))
		if smartab_vp.size != want:
			smartab_vp.size = want
			smartab.scale = Vector2(k, k)
	if ch == null or not is_instance_valid(ch):
		reticle.visible = false
		hint.text = ""
		fire_mode_label.text = ""
		return
	_tab_input()
	var show_mode: bool = not Settings.touch_active() and ch.mode == Motor.GROUND and not tab_held \
		and ch.wpn.has_selector(ch.wpn.current_id())
	fire_mode_label.text = "Fire mode: %s   [%s]" % [ch.wpn.fire_mode_label(), Settings.binding_label("fire_mode")] if show_mode else ""
	# Reticle: only with a weapon raised, not while the SmarTab is up or sprinting.
	reticle.visible = ch.wpn.current_id() != "" and not tab_held and ch.mode == Motor.GROUND and not ch.sprinting
	reticle.set("ch", ch)
	reticle.set("cam", world.controller.cam if world.controller else null)
	scope.set("ch", ch if not tab_held else null)
	scope.set("cam", world.controller.cam if world.controller else null)
	# Frag grenades carried, with the key that throws them (4 times a second).
	_frags_t -= dt
	var nf := -1 if _frags_t > 0.0 else 0
	if nf == 0 and ch.inv:
		_frags_t = 0.25
		for e in ch.inv.bag:
			if str(e.id) == "frag_grenade":
				nf += int(e.n)
	if nf >= 0:
		frags_label.text = ("Frag grenades: %d  (hold %s to cook, let go to throw)" % [nf, "Frag" if Settings.touch_active() else Settings.binding_label("throw_grenade")]) if nf > 0 and ch.mode == Motor.GROUND else ""
	# Context prompt
	_prompt_t -= dt
	if _prompt_t <= 0.0:
		_prompt_t = 0.1
		prompt.text = _prompt_text()
	match ch.mode:
		Motor.PLANE:
			var pl: Dictionary = world.match_info.get("plane", {})
			var t := (Net.interp_tick() - float(pl.get("t0", 0))) / Defs.TICK_RATE if not world.is_server else (Net.tick - float(pl.get("t0", 0))) / Defs.TICK_RATE
			if t < float(pl.get("open_s", 0.0)):
				var waiting_hint := "Jump in %d s. Tap Phone, then Map for the flight path." if Settings.touch_active() else "Not over the settlement yet: you can jump in %d s.  Hold M to see the flight path."
				hint.text = waiting_hint % int(ceil(float(pl.get("open_s", 0.0)) - t))
			else:
				var jump_hint := "Tap Jump to leave the plane (%d s left). Tap Phone, then Map for the flight path." if Settings.touch_active() else "Space: jump with your team (%d s left).  Hold M to see the flight path."
				hint.text = jump_hint % maxi(int(float(pl.get("close_s", 0.0)) - t), 0)
		Motor.FREEFALL:
			hint.text = "Steer with the move stick. Tap Jump to open the canopy (it also opens automatically)." if Settings.touch_active() else "Steer with WASD.  Space opens the canopy (it opens by itself low down)."
		Motor.CHUTE:
			hint.text = "Move stick: up speeds up, down brakes, left/right turns. Tap Jump just before landing to flare." if Settings.touch_active() else "W faster, S brake, A/D turn.  Tap Space just before touching down to flare."
		Motor.DOWNED:
			hint.text = "You are down. A teammate can revive you by holding Use." if Settings.touch_active() else "You are down. A teammate can revive you (hold E)."
		_:
			hint.text = ""


func _tab_input() -> void:
	if tab_held and not _was_tab:
		SoundSys.play_local("smartab_up", -4.0)
		if map_held:
			smartab.open_page("Map")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not tab_held and _was_tab:
		SoundSys.play_local("smartab_down", -6.0)
		smartab.close_container()
		if chat_edit == null and not world.controller.paused:
			Input.mouse_mode = Settings.play_mouse_mode()
	_was_tab = tab_held


func _input(event: InputEvent) -> void:
	if not tab_held or world.controller == null or world.controller.vm == null:
		return
	if event.is_action_pressed("smartab_prev"):
		smartab.next_page(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("smartab_next"):
		smartab.next_page(1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouse:
		var uv: Vector2 = world.controller.vm.screen_uv(event.position)
		var off := uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0
		# Off the hologram: presses do nothing; moves and releases still reach it (at its edge), so a drag carried
		# past the edge ends instead of sticking to the cursor.
		if off and (uv == Vector2(-1, -1) or (event is InputEventMouseButton and event.pressed)):
			return
		uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
		var ev: InputEventMouse = event.duplicate()
		ev.position = uv * Vector2(smartab_vp.size)
		ev.global_position = ev.position
		smartab_vp.push_input(ev)
		get_viewport().set_input_as_handled()


const Attach := preload("res://src/weapons/attachments.gd")
const BOX_NAMES := {"lootbox_balikbayan": "balikbayan box", "lootbox_bin": "storage bin", "lootbox_ammocan": "ammo can",
	"lootbox_footlocker": "footlocker", "lootbox_toolbox": "toolbox", "lootbox_medcase": "first aid case", "lootbox_riflecase": "rifle case",
	"lootbox_cooler": "icebox"}


func _prompt_text() -> String:
	if tab_held or ch.mode != Motor.GROUND or world.interaction == null:
		return ""
	var t: Dictionary = world.interaction.target(ch, {"yaw": ch.yaw, "pitch": ch.pitch})
	if t.is_empty():
		if ch.held_prop_id >= 0:
			return "Fire: throw    Grab: put down" if Settings.touch_active() else "Left mouse: throw    %s: put down" % Settings.binding_label("grab")
		return ""
	var key := "Use" if Settings.touch_active() else Settings.binding_label("interact")
	match str(t.kind):
		"door":
			var d = t.obj
			if d.locked:
				return "%s  Try the door (barred)" % key if not d.is_inside(ch.global_position) else "%s  Lift the bar" % key
			return "%s  %s door" % [key, "Close" if absf(d.target) > 0.05 else "Open"]
		"shutter":
			return "%s  %s shutter" % [key, "Close" if absf(t.obj.target) > 0.05 else "Open"]
		"item":
			var it: Dictionary = world.map.dyn.items.get(int(t.id), {})
			if it.is_empty():
				return ""
			var iid := str(it.entry.id)
			var label := Defs.item_name(iid)
			if int(it.entry.get("n", 1)) > 1:
				label += " (%d)" % int(it.entry.n)
			if Defs.is_weapon(iid) or iid.begins_with("ammo_"):
				label += "  [%s]" % Defs.calibre_name(iid)
			if Defs.is_attachment(iid):
				var up: Array = Attach.best_slot_upgrade(ch.wpn.slots, iid)
				if int(up[0]) >= 0:
					label += ", fits your " + Defs.item_name(str(ch.wpn.slots[int(up[0])].id))
			elif iid.begins_with("ammo_"):
				for s in [1, 2, 3]:
					var wv = ch.wpn.slots[s]
					if wv != null and Defs.ammo_item(str(wv.id)) == iid:
						label += ", for your " + Defs.item_name(str(wv.id))
						break
			return "%s  Take %s" % [key, label]
		"container":
			var c: Dictionary = world.map.dyn.containers[int(t.id)]
			if c.has("box"):
				var b: Dictionary = world.map.dyn.loot_boxes[int(c.box)]
				return "%s  Search the %s%s" % [key, BOX_NAMES.get(str(b.name), "box"), " (opened)" if b.open else ""]
			return "%s  Search" % key
		"corpse":
			return "%s  Search the body" % key
		"prop":
			var p: Dictionary = world.map.dyn.props[int(t.id)]
			var s: Dictionary = world.map.models.spec(str(p.name))
			var m := float(s.get("mass", 5.0))
			if m > float(Defs.rule("interaction.push_mass_limit", 120.0)):
				return ""
			var gk := "Grab" if Settings.touch_active() else Settings.binding_label("grab")
			return "%s  %s" % [gk, "Drag" if m > float(Defs.rule("interaction.carry_mass_limit", 22.0)) else "Pick up"]
		"revive":
			return "Hold %s  Revive" % key
	return ""

