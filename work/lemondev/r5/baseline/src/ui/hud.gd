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
var results: Control
var loading: Control
var spect_label: Label
var chat_box: VBoxContainer
var chat_edit: LineEdit
var smartab_vp: SubViewport
var _tab_vis_t := 0.0
var smartab: Control
var _toast_t := 0.0
var _hurt := 0.0
var _prev_health := -1.0
var _was_tab := false
var _prompt_t := 0.0
var minimap: Control
var compass: Control
var _supp := 0.0         # near-miss suppression (Effects.flyby)
var pa_banner: Control   # loudspeaker countdown (audio/announcer.gd drives it)
var _pa_t := 0.0
var frags_label: Label
var _frags_t := 0.0


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
	scope = preload("res://src/ui/scope_overlay.gd").new()
	scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scope.visible = false
	root.add_child(scope)
	reticle = preload("res://src/ui/reticle.gd").new()
	reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reticle)
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
	spect_label.position = Vector2(-300, -70)
	spect_label.size = Vector2(600, 30)
	spect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(spect_label)
	chat_box = UITheme.vbox(2)
	chat_box.position = Vector2(24, 0)
	chat_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_box.position = Vector2(24, -260)
	root.add_child(chat_box)
	# SmarTab screen
	smartab_vp = SubViewport.new()
	smartab_vp.size = Vector2i(720, 720)
	smartab_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	smartab_vp.transparent_bg = false
	smartab_vp.gui_disable_input = false
	add_child(smartab_vp)
	smartab = SmarTabUI.new()
	smartab_vp.add_child(smartab)
	smartab.set_world(world)
	smartab.request.connect(func(req): world.request_inventory(req))
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
	_build_loading()
	Net.lobby_changed.connect(func(): pass)


func set_character(c) -> void:
	ch = c
	if world.controller and world.controller.vm:
		world.controller.vm.set_screen_texture(smartab_vp.get_texture())


func _build_loading() -> void:
	loading = ColorRect.new()
	(loading as ColorRect).color = Color(0.01, 0.012, 0.016)
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var l := UITheme.label("Sitio Kalinaw", 54, Color(0.86, 0.88, 0.86), UITheme.font_condensed)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.position = Vector2(-220, -60)
	loading.add_child(l)
	var s := UITheme.label("Waiting for every player to arrive…", 22, UITheme.TEXT_DIM)
	s.set_anchors_preset(Control.PRESET_CENTER)
	s.position = Vector2(-220, 10)
	loading.add_child(s)
	root.add_child(loading)
	loading.visible = Game.state == "loading"
	Game.state_changed.connect(func(st): loading.visible = st == "loading")


# ------------------------------------------------------------------ events from the world

func on_owner_state() -> void:
	if ch == null:
		return
	var hp: float = ch.health.health
	if _prev_health >= 0.0 and hp < _prev_health - 0.5:
		_hurt = minf(_hurt + (_prev_health - hp) / 40.0, 1.0)
	_prev_health = hp


func on_match_state(info: Dictionary) -> void:
	pass


func add_ping(eid: int, pos: Vector3) -> void:
	minimap.add_ping(eid, pos, ch != null and is_instance_valid(ch) and ch.eid == eid)


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
	toast("You died.")


func set_spectating(t) -> void:
	if t:
		spect_label.text = "Watching %s" % t.pname


func show_results(summary: Dictionary) -> void:
	if results:
		results.queue_free()
	results = PanelContainer.new()
	results.set_anchors_preset(Control.PRESET_CENTER)
	results.custom_minimum_size = Vector2(760, 520)
	results.position = Vector2(-380, -260)
	var v := UITheme.vbox(8)
	results.add_child(v)
	v.add_child(UITheme.label("Match Results", 40, UITheme.TEXT, UITheme.font_condensed))
	var winners: Array = summary.get("winners", [])
	var win_text := "Last team standing: %s" % ", ".join(winners) if not winners.is_empty() else "Nobody survived the night."
	v.add_child(UITheme.label(win_text, 24, UITheme.ACCENT))
	v.add_child(UITheme.label("Match length %d:%02d" % [int(summary.duration) / 60, int(summary.duration) % 60], 18, UITheme.TEXT_DIM))
	if summary.has("me_xp") and not (summary.me_xp as Dictionary).is_empty():
		# Your XP for this match, and a level reached.
		var mx: Dictionary = summary.me_xp
		var me: Dictionary = summary.get("me", {})
		var xr := UITheme.hbox(14)
		xr.add_child(UITheme.label("+%d XP" % int(mx.xp), 34, UITheme.ACCENT, UITheme.font_condensed))
		xr.add_child(UITheme.label("place #%d · %d kills · %d damage" % [int(me.get("place", 0)), int(me.get("kills", 0)), int(me.get("damage", 0))], 18, UITheme.TEXT_DIM))
		if int(mx.level_after) > int(mx.level_before):
			xr.add_child(UITheme.pill("Level %d reached" % int(mx.level_after), UITheme.ACCENT, 18))
		v.add_child(xr)
	var head := UITheme.hbox(10)
	for col in [["Player", 300], ["Team", 80], ["Kills", 80], ["Downs", 80], ["Survived", 120]]:
		var l := UITheme.label(col[0], 18, UITheme.TEXT_DIM)
		l.custom_minimum_size = Vector2(col[1], 0)
		head.add_child(l)
	v.add_child(head)
	for r in summary.get("rows", []).slice(0, 12):
		var h := UITheme.hbox(10)
		var vals := [[str(r.name) + (" (bot)" if r.bot else ""), 300], [str(int(r.team) + 1), 80], [str(r.kills), 80], [str(r.downs), 80], ["%d:%02d" % [int(r.time) / 60, int(r.time) % 60], 120]]
		for val in vals:
			var l2 := UITheme.label(val[0], 19, UITheme.ACCENT if r.winner else UITheme.TEXT)
			l2.custom_minimum_size = Vector2(val[1], 0)
			h.add_child(l2)
		v.add_child(h)
	v.add_child(UITheme.label("Returning to the lobby shortly.", 18, UITheme.TEXT_DIM))
	root.add_child(results)


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
	get_tree().create_timer(12.0).timeout.connect(func(): if is_instance_valid(l): l.queue_free())


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


func _process(dt: float) -> void:
	_toast_t -= dt
	toast_label.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if pa_banner:
		_pa_t -= dt
		pa_banner.modulate.a = clampf(_pa_t / 0.25, 0.0, 1.0)
	_hurt = move_toward(_hurt, 0.0, dt * 0.6)
	var low := 0.0
	if ch and is_instance_valid(ch):
		low = clampf((40.0 - ch.health.health) / 40.0, 0.0, 1.0)
	(vignette.material as ShaderMaterial).set_shader_parameter("amount", _hurt)
	(vignette.material as ShaderMaterial).set_shader_parameter("low", low)
	_supp = move_toward(_supp, 0.0, dt * 0.7)
	(vignette.material as ShaderMaterial).set_shader_parameter("supp", _supp)
	# The SmarTab screen renders only while the device is up, plus its lowering animation.
	_tab_vis_t = 0.8 if (tab_held or map_held) else maxf(_tab_vis_t - dt, 0.0)
	smartab_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _tab_vis_t > 0.0 else SubViewport.UPDATE_DISABLED
	if ch == null or not is_instance_valid(ch):
		reticle.visible = false
		hint.text = ""
		return
	_tab_input()
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
		frags_label.text = ("Frag grenades: %d  (%s to throw)" % [nf, "Frag" if Settings.touch_active() else Settings.binding_label("throw_grenade")]) if nf > 0 and ch.mode == Motor.GROUND else ""
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
		if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
			return
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
