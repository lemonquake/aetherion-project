extends Control
## Game Setup (r7): the two guns a Deathmatch player starts with. A primary (a long gun from rules.json
## deathmatch.primary, slot 1) and a secondary (a handgun from deathmatch.secondary, slot 3), each shown with its
## picture (assets/ui/r7/guns), name, class and calibre. The choice is saved in the profile (Profile.loadout) and sent
## to the server (Net.request_loadout) whenever it changes while in a lobby or match.
## (r22) Each gun's attachments too: one picker per slot kind the gun takes (sight, muzzle, grip, magazine, stock,
## light), remembered per gun in the profile (Profile.att_by_gun) and fitted at spawn by MatchServer._dm_loadout.
## Opened as a full-screen layer from the main menu and from the lobby: GameSetup.new() then add_child; emits `closed`.

signal closed

const MenuBg := preload("res://src/ui/menu_bg.gd")
const Attach := preload("res://src/weapons/attachments.gd")
const KIND_NAMES := {"sight": "Sight", "muzzle": "Muzzle", "grip": "Grip", "mag": "Magazine", "stock": "Stock", "light": "Light"}

var _compact := false
var _att_boxes := {}   # (r22) "primary" / "secondary" -> the box holding that gun's attachment pickers
var _att_key := ""
var _att_cols := 4     # grid columns: label, picker, label, picker (2 on narrow screens)
var _pick := {}
var _cards := {"primary": {}, "secondary": {}}
var _summary: VBoxContainer
var _tabs := {}
var _lists := {}
var _tab := "primary"


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(MenuBg.new("locker_bg", 0.5))
	var vs := get_viewport_rect().size
	_compact = vs.x < 1500.0 or vs.y < 800.0
	# Two label + picker pairs per row when each gun's column is wide enough (wide: half of the left column).
	var att_w := (vs.x - 44.0 - 40.0) if _compact else (vs.x - 80.0 - 20.0 - 560.0 - 36.0 - 28.0) / 2.0
	_att_cols = 4 if att_w >= 470.0 else 2
	_pick = Profile.get_loadout()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 40 if not _compact else 22)
	m.add_theme_constant_override("margin_top", 24 if not _compact else 14)
	m.add_theme_constant_override("margin_bottom", 20 if not _compact else 12)
	add_child(m)
	var col := UITheme.vbox(14 if not _compact else 8)
	m.add_child(col)
	# Header: title, what this is, Done.
	var head := UITheme.hbox(14)
	var hv := UITheme.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UITheme.label("Deathmatch", 18, UITheme.ACCENT, UITheme.font_semibold))
	hv.add_child(UITheme.label("Game Setup", 44 if not _compact else 34, UITheme.TEXT, UITheme.font_condensed))
	head.add_child(hv)
	if not _compact:
		var note := UITheme.label("Pick the two guns you start with and their attachments. Your choice is saved for the next match.", 18, UITheme.TEXT_DIM)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(520, 0)
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(note)
	var done := UITheme.primary("DONE", close, 200 if not _compact else 160, 64 if not _compact else 56)
	done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(done)
	col.add_child(head)
	if _compact:
		_build_compact(col)
	else:
		_build_wide(col)
	_refresh()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# ------------------------------------------------------------------ layouts

func _build_wide(col: VBoxContainer) -> void:
	var row := UITheme.hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	# Left: every primary, grouped by class; (r22) under it the attachments of both guns.
	var left := UITheme.vbox(14)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var lp := UITheme.panel(null, "panel")
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lv := UITheme.vbox(10)
	lp.add_child(lv)
	lv.add_child(UITheme.section("Primary", "A long gun: rifle, submachine gun, marksman or sniper rifle, machine gun or shotgun."))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	var groups := UITheme.vbox(12)
	groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(groups)
	_fill_flow(groups, "primary", Vector2(226, 156))
	left.add_child(lp)
	var ap := UITheme.panel(null, "panel")
	var ah := UITheme.hbox(28)
	ap.add_child(ah)
	for which in ["primary", "secondary"]:
		var b := UITheme.vbox(6)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ah.add_child(b)
		_att_boxes[which] = b
	left.add_child(ap)
	# Right: handguns, then what you start with.
	var right := UITheme.vbox(14)
	right.custom_minimum_size = Vector2(560, 0)
	row.add_child(right)
	var sp := UITheme.panel(null, "panel")
	var sv := UITheme.vbox(10)
	sp.add_child(sv)
	sv.add_child(UITheme.section("Secondary", "A handgun, carried in the handgun slot."))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for id in _ids("secondary"):
		grid.add_child(_card("secondary", id, Vector2(252, 156)))
	sv.add_child(grid)
	right.add_child(sp)
	var kp := UITheme.panel(null, "panel_accent")
	kp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary = UITheme.vbox(8)
	kp.add_child(_summary)
	right.add_child(kp)


func _build_compact(col: VBoxContainer) -> void:
	## Phones and small windows: one list at a time, switched with tabs that also show the current pick; (r22) the
	## third tab holds both guns' attachments.
	var tabs := UITheme.hbox(6)
	var group := ButtonGroup.new()
	for kind in ["primary", "secondary", "attachments"]:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "CardButton"
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.button_pressed = kind == _tab
		var k: String = kind
		b.pressed.connect(func(): SoundSys.play_ui("ui_select"); _show_tab(k))
		tabs.add_child(b)
		_tabs[kind] = b
	col.add_child(tabs)
	for kind in ["primary", "secondary", "attachments"]:
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var v := UITheme.vbox(10)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(v)
		if kind == "primary":
			_fill_flow(v, kind, Vector2(226, 156))
		elif kind == "attachments":
			for which in ["primary", "secondary"]:
				var ap := UITheme.panel(null, "panel")
				var b := UITheme.vbox(6)
				ap.add_child(b)
				v.add_child(ap)
				_att_boxes[which] = b
		else:
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 10)
			flow.add_theme_constant_override("v_separation", 10)
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for id in _ids(kind):
				flow.add_child(_card(kind, id, Vector2(226, 156)))
			v.add_child(flow)
			var kit := UITheme.panel(null, "panel_accent")
			_summary = UITheme.vbox(6)
			kit.add_child(_summary)
			v.add_child(kit)
		sc.visible = kind == _tab
		col.add_child(sc)
		_lists[kind] = sc


func _show_tab(kind: String) -> void:
	_tab = kind
	for k in _lists:
		_lists[k].visible = k == kind


func _ids(kind: String) -> Array:
	var dm: Dictionary = Defs.rules.get("deathmatch", {})
	var out := []
	for id in dm.get(kind, []):
		if Defs.is_weapon(str(id)):
			out.append(str(id))
	return out


func _fill_flow(parent: VBoxContainer, kind: String, card_size: Vector2) -> void:
	## One card per gun in the order the rules list them (grouped by class there); each card names its class.
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in _ids(kind):
		flow.add_child(_card(kind, id, card_size))
	parent.add_child(flow)


# ------------------------------------------------------------------ cards

func _card(kind: String, id: String, sz: Vector2) -> Control:
	var w := Defs.weapon(id)
	var b := Button.new()
	b.theme_type_variation = "CardButton"
	b.toggle_mode = true
	b.custom_minimum_size = sz
	b.tooltip_text = "%s · %s · %s" % [str(w.get("name", id)), UITheme.gun_class(id), Defs.calibre_name(id)]
	var v := UITheme.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_top = 8
	v.offset_bottom = -8
	b.add_child(v)
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", UITheme.gun_plate())
	plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pic := TextureRect.new()
	pic.texture = UITheme.gun_picture(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(pic)
	v.add_child(plate)
	var name := UITheme.label(str(w.get("name", id)), 21, UITheme.TEXT, UITheme.font_semibold)
	name.clip_text = true
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name)
	var sub := UITheme.hbox(6)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cl := UITheme.label(UITheme.gun_class(id), 16, UITheme.TEXT_DIM)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.clip_text = true
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_child(cl)
	var cal := UITheme.pill(Defs.calibre_name(id), Defs.ammo_color(id).lightened(0.2), 15)
	cal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_child(cal)
	v.add_child(sub)
	b.pressed.connect(func(): SoundSys.play_ui("ui_select"); choose(kind, id))
	_cards[kind][id] = b
	return b


func choose(kind: String, id: String) -> void:
	## Pick a gun (also used by the UI tour). Saves to the profile and tells the server.
	_pick[kind] = id
	Profile.set_loadout(_pick)
	_pick = Profile.get_loadout()
	_refresh()


func fit(which: String, k: String, att_id: String) -> void:
	## (r22) Fit an attachment in one slot kind of the primary or secondary gun ("" = none; also used by the UI tour).
	## Remembered for that gun in the profile and sent to the server.
	Profile.set_attachment(which, k, att_id)
	_pick = Profile.get_loadout()
	_refresh()


func _refresh() -> void:
	for kind in _cards:
		for id in _cards[kind]:
			_cards[kind][id].set_pressed_no_signal(id == str(_pick.get(kind, "")))
	for kind in _tabs:
		if kind == "attachments":
			_tabs[kind].text = "Attachments: %d" % ((_pick.get("att_primary", []) as Array).size() + (_pick.get("att_secondary", []) as Array).size())
		else:
			_tabs[kind].text = "%s: %s" % ["Primary" if kind == "primary" else "Secondary", Defs.item_name(str(_pick.get(kind, "")))]
	if _summary:
		for c in _summary.get_children():
			c.queue_free()
		_fill_summary(_summary, _pick, _compact)
	_fill_attachments.call_deferred()   # deferred: a picker may be the one whose signal got us here


# ------------------------------------------------------------------ attachments (r22)

func _fill_attachments() -> void:
	## One picker per slot kind each chosen gun takes: "None" and every attachment that fits it.
	var key := JSON.stringify(_pick)
	if key == _att_key or not is_inside_tree():
		return
	_att_key = key
	for which in _att_boxes:
		var box: VBoxContainer = _att_boxes[which]
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
		var wid := str(_pick.get(which, ""))
		var head := UITheme.hbox(10)
		var role := UITheme.label("PRIMARY" if which == "primary" else "SECONDARY", 15, UITheme.ACCENT, UITheme.font_semibold)
		role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(role)
		var nm := UITheme.label("%s attachments" % Defs.item_name(wid), 21, UITheme.TEXT, UITheme.font_semibold)
		nm.clip_text = true
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		box.add_child(head)
		var kinds := Attach.kinds_for(wid)
		if kinds.is_empty():
			box.add_child(UITheme.label("This gun takes no attachments.", 17, UITheme.TEXT_DIM))
			continue
		var grid := GridContainer.new()
		grid.columns = _att_cols
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 8)
		box.add_child(grid)
		var fitted: Array = _pick.get("att_" + which, [])
		for k in kinds:
			var l := UITheme.label(str(KIND_NAMES.get(k, str(k).capitalize())), 17, UITheme.TEXT_DIM, UITheme.font_semibold)
			l.custom_minimum_size = Vector2(84, 0)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			grid.add_child(l)
			grid.add_child(_att_picker(which, str(k), fitted))


func _att_picker(which: String, k: String, fitted: Array) -> OptionButton:
	var wid := str(_pick.get(which, ""))
	var ob := OptionButton.new()
	ob.name = "att_%s_%s" % [which, k]
	ob.fit_to_longest_item = false   # the list has the long names; the button stays as wide as its column
	ob.clip_text = true
	ob.custom_minimum_size = Vector2(140, 44)
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_theme_font_size_override("font_size", 17)
	ob.add_item("None")
	ob.set_item_metadata(0, "")
	ob.select(0)
	var cur := ""
	for a in fitted:
		if Attach.kind(str(a)) == k:
			cur = str(a)
	var opts := Attach.options(wid, k)
	for i in opts.size():
		ob.add_item(att_name(str(opts[i])))
		ob.set_item_metadata(i + 1, str(opts[i]))
		if str(opts[i]) == cur:
			ob.select(i + 1)
	if cur != "":
		ob.text = att_short(cur)   # the button shows the short name, the list the full one
		ob.tooltip_text = att_name(cur)
	ob.item_selected.connect(func(i: int): SoundSys.play_ui("ui_select"); fit(which, k, str(ob.get_item_metadata(i))))
	return ob


static func att_name(att_id: String) -> String:
	## An attachment's full name, sights with their magnification: "Red Dot Sight · 1.3x", "6x Rifle Scope".
	var a: Dictionary = Defs.attachments.get(att_id, {})
	var n := str(a.get("name", att_id))
	if str(a.get("kind", "")) == "sight" and not n.contains("x "):
		n += " · %sx" % String.num(float(a.get("zoom", 1.0)), 2)
	return n


static func att_short(att_id: String) -> String:
	## A short name for buttons and summaries: "6x Scope", "Red Dot", "Ext. Mag", "Suppressor".
	var a: Dictionary = Defs.attachments.get(att_id, {})
	var n := str(a.get("name", att_id))
	match str(a.get("kind", "")):
		"mag":
			var ext := bool(a.get("ext", false))
			var quick := float(a.get("reload_mult", 1.0)) < 1.0
			return "Ext. Quick Mag" if ext and quick else ("Ext. Mag" if ext else ("Quick Mag" if quick else n))
		"sight":
			for w in [" Rifle Scope", " Prism Scope", " Sniper Scope", " Variable Scope"]:
				n = n.replace(w, " Scope")
			return n.replace(" Vision Scope", " Vision").replace(" Thermal Scope", " Thermal").trim_suffix(" Sight")
	for pre in ["Pistol/SMG ", "Rifle ", "Shotgun "]:
		n = n.trim_prefix(pre)
	return n


static func att_list(ids: Array) -> String:
	## Every fitted attachment by its short name: "6x Scope · Compensator · Ext. Mag".
	var names := []
	for a in ids:
		names.append(att_short(str(a)))
	return " · ".join(names) if not names.is_empty() else "No attachments"


static func att_brief(ids: Array) -> String:
	## A few words for the lobby and the menu: "6x Scope · Ext. Mag", or "+3 attachments" when there are more than two.
	if ids.size() > 2:
		return "+%d attachments" % ids.size()
	return att_list(ids) if not ids.is_empty() else ""


static func kit_lines() -> Array:
	## What everyone starts with besides the guns: [[icon, text]].
	var dm: Dictionary = Defs.rules.get("deathmatch", {})
	var out := []
	for g in dm.get("gear", []):
		out.append(["shield", Defs.item_name(str(g))])
	for e in dm.get("extras", []):
		if e is Array and e.size() >= 2:
			out.append(["plus", "%d × %s" % [int(e[1]), Defs.item_name(str(e[0]))]])
	out.append(["gun", "Spare magazines: %d primary, %d secondary" % [int(dm.get("spare_mags_primary", 3)), int(dm.get("spare_mags_secondary", 2))]])
	return out


static func _fill_summary(box: VBoxContainer, pick: Dictionary, compact: bool) -> void:
	box.add_child(UITheme.label("You start with", 28, UITheme.TEXT, UITheme.font_condensed))
	var lines := []
	if not compact:
		var guns := UITheme.hbox(10)
		for kind in ["primary", "secondary"]:
			guns.add_child(gun_tile(str(pick.get(kind, "")), "Primary" if kind == "primary" else "Secondary", Vector2(250, 112), pick.get("att_" + kind, []), true))
		box.add_child(guns)
	else:
		# (r22) the guns are on the tabs; their attachments are listed here
		for kind in ["primary", "secondary"]:
			var att: Array = pick.get("att_" + kind, [])
			if not att.is_empty():
				lines.append(["gun", "%s: %s" % [Defs.item_name(str(pick.get(kind, ""))), att_list(att)]])
	for kl in lines + kit_lines():
		var h := UITheme.hbox(10)
		var ic := TextureRect.new()
		ic.texture = Icons.texture(str(kl[0]), 22, UITheme.ACCENT2)
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		h.add_child(ic)
		var l := UITheme.label(str(kl[1]), 18, UITheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		box.add_child(h)


static func gun_tile(id: String, role: String, pic_size: Vector2, att: Array = [], full: bool = false) -> Control:
	## A gun's picture with its role ("Primary") and name underneath: the lobby's loadout summary uses it too.
	## (r22) With its attachments: all of them (`full`, wrapped) or in brief (one clipped line, only when there are any).
	var v := UITheme.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", UITheme.gun_plate())
	var pic := TextureRect.new()
	pic.texture = UITheme.gun_picture(id)
	pic.custom_minimum_size = pic_size
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(pic)
	v.add_child(plate)
	v.add_child(UITheme.label(role, 15, UITheme.TEXT_DIM))
	var n := UITheme.label("%s · %s" % [Defs.item_name(id), Defs.calibre_name(id)], 20, UITheme.TEXT, UITheme.font_semibold)
	n.clip_text = true
	v.add_child(n)
	if full or not att.is_empty():
		var al := UITheme.label(att_list(att) if full else att_brief(att), 16, UITheme.ACCENT2 if not att.is_empty() else UITheme.TEXT_DIM)
		if full:
			al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			al.clip_text = true
		v.add_child(al)
	return v


# ------------------------------------------------------------------ UI tour for the r7 screens

class Tour extends Node:
	## --ui_tour_r7=<dir> [--ui_sizes=1920x1080,3840x2160] [--port=N] (with --mobile: the phone layout): captures the
	## home page in both modes, Play in Deathmatch, Game Setup (before and after picking), a hosted Deathmatch lobby and
	## Game Setup over it, then quits. Use --profile=<name> so the tour's picks do not touch your own profile. Prints
	## "[ui] shot <path>", "[ui] PASS|FAIL <check>" and "[ui] r7 done, N problems".
	var out := ""
	var fails := 0

	func _ready() -> void:
		out = str(Game.arg("ui_tour_r7"))
		DirAccess.make_dir_recursive_absolute(out)
		_run.call_deferred()

	func _run_client(port: int) -> void:
		## --r7_client=<port>: a second process joins a Deathmatch host on this PC (started with --host
		## --game_mode=deathmatch --port=<port>): the LAN list shows the mode, the saved loadout reaches the server on
		## joining, a team switch works, and a change made in Game Setup reaches the server too.
		await _wait(1.0)
		var menu = Game.screen
		menu._show("play")
		var seen := {}
		for i in 40:
			for g in Online.games():
				if int(g.get("port", 0)) == port:
					seen = g
			if not seen.is_empty():
				break
			menu._fill_games()
			await _wait(0.5)
		await _wait(0.5)
		await _snap("client_play_list", Game.screen)
		print("[ui] %s server list shows the host's mode: %s" % ["PASS" if str(seen.get("game_mode", "")) == "deathmatch" else "FAIL",
			JSON.stringify({"game_mode": seen.get("game_mode", "?"), "map": seen.get("map", "?"), "teams": seen.get("teams", 0), "team_size": seen.get("team_size", 0)})])
		fails += 0 if str(seen.get("game_mode", "")) == "deathmatch" else 1
		menu._join("127.0.0.1", port)
		for i in 40:
			if Game.state == "lobby" and Net.players.has(Net.local_pid):
				break
			await _wait(0.25)
		await _wait(1.5)
		var want: Dictionary = Profile.get_loadout()
		var got: Dictionary = Net.players.get(Net.local_pid, {}).get("loadout", {})
		var ok := JSON.stringify(got) == JSON.stringify(want)
		print("[ui] %s client loadout on joining reached the server: want %s, lobby shows %s" % ["PASS" if ok else "FAIL", JSON.stringify(want), JSON.stringify(got)])
		fails += 0 if ok else 1
		var t0 := int(Net.players.get(Net.local_pid, {}).get("team", -1))
		Net.request_team(1 if t0 != 1 else 0)
		await _wait(1.0)
		var t1 := int(Net.players.get(Net.local_pid, {}).get("team", -1))
		print("[ui] %s team switch: %d -> %d" % ["PASS" if t1 != t0 and t1 >= 0 else "FAIL", t0, t1])
		fails += 0 if t1 != t0 and t1 >= 0 else 1
		await _snap("client_lobby", Game.screen)
		var gs = Game.screen.open_game_setup()
		await _wait(0.6)
		gs.choose("primary", "lmg_m249")
		await _wait(1.0)
		await _snap("client_game_setup", gs)
		var got2: Dictionary = Net.players.get(Net.local_pid, {}).get("loadout", {})
		print("[ui] %s loadout change reached the server: %s" % ["PASS" if str(got2.get("primary", "")) == "lmg_m249" else "FAIL", JSON.stringify(got2)])
		fails += 0 if str(got2.get("primary", "")) == "lmg_m249" else 1
		gs.close()
		await _wait(0.5)
		await _snap("client_lobby_after", Game.screen)
		await _wait(float(Game.arg("r7_client_hold", 0.0)))
		print("[ui] r7 client done, %d problems" % fails)
		get_tree().quit(1 if fails > 0 else 0)

	func _run() -> void:
		if Game.arg("r7_client"):
			await _run_client(int(Game.arg("r7_client")))
			return
		var sizes: Array = str(Game.arg("ui_sizes", "1920x1080")).split(",")
		for s in sizes:
			var wh := (s as String).split("x")
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))
			await _frames(20)
			var tag := "%s%s" % [s, "_mobile" if Settings.is_mobile() else ""]
			Profile.set_game_mode("classic")
			Game.show_menu()
			await _wait(0.6)
			var menu = Game.screen
			await _snap("%s_home_classic" % tag, Game.screen)
			menu._set_mode("deathmatch")
			await _wait(0.5)
			await _snap("%s_home_deathmatch" % tag, Game.screen)
			menu._show("play")
			await _wait(0.5)
			await _snap("%s_play_deathmatch" % tag, Game.screen)
			var gs = menu.open_game_setup()
			await _wait(0.8)
			await _snap("%s_game_setup" % tag, gs)
			gs.choose("primary", "smg_vector")
			gs.choose("secondary", "pistol_deagle")
			# (r22) attachments: a scope and an extended magazine on the primary, a red dot and a magazine on the
			# handgun; then a gun change and back must bring the primary's setup back.
			gs.fit("primary", "muzzle", "")
			gs.fit("primary", "sight", "scope_3x")
			gs.fit("primary", "mag", "mag_ext_light")
			gs.fit("secondary", "sight", "sight_reddot")
			gs.fit("secondary", "mag", "mag_extquick_light")
			var want_att: Array = ["scope_3x", "mag_ext_light"]
			var att0: Array = Profile.get_loadout().att_primary
			gs.choose("primary", "rifle_m416")
			gs.choose("primary", "smg_vector")
			var att1: Array = Profile.get_loadout().att_primary
			var ok_att := att0.filter(func(a): return a in want_att) == want_att and att1 == att0
			print("[ui] %s %s attachments remembered per gun: %s -> %s" % ["PASS" if ok_att else "FAIL", tag, JSON.stringify(att0), JSON.stringify(att1)])
			fails += 0 if ok_att else 1
			if gs._compact:
				gs._show_tab("attachments")
				await _wait(0.4)
				await _snap("%s_game_setup_attachments" % tag, gs)
				gs._show_tab("secondary")
			await _wait(0.4)
			await _snap("%s_game_setup_picked" % tag, gs)
			gs.close()
			await _wait(0.3)
			menu._host_custom()
			await _wait(1.0)
			await _snap("%s_lobby_deathmatch" % tag, Game.screen)
			var want: Dictionary = Profile.get_loadout()
			var got: Dictionary = Net.players.get(Net.local_pid, {}).get("loadout", {})
			var ok: bool = JSON.stringify(got) == JSON.stringify(want) and str(Net.config.get("game_mode", "")) == "deathmatch" and int(Net.config.get("teams", 0)) == 2
			print("[ui] %s %s lobby: game_mode=%s map=%s teams=%d team_size=%d loadout on server=%s" % ["PASS" if ok else "FAIL", tag,
				str(Net.config.get("game_mode", "")), str(Net.config.get("map", "")), int(Net.config.get("teams", 0)), Net.team_size(), JSON.stringify(got)])
			fails += 0 if ok else 1
			var lgs = Game.screen.open_game_setup()
			await _wait(0.8)
			await _snap("%s_lobby_game_setup" % tag, lgs)
			lgs.close()
			Game.leave_to_menu()
			await _wait(0.4)
		print("[ui] r7 done, %d problems" % fails)
		get_tree().quit(1 if fails > 0 else 0)

	func _snap(name: String, root: Control) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := "%s/%s.png" % [out, name]
		img.save_png(p)
		print("[ui] shot %s (%dx%d)" % [p, img.get_width(), img.get_height()])
		fails += _check_bounds(root, name)

	func _check_bounds(root: Control, where: String) -> int:
		## Buttons and inputs partly off screen (clipped) are layout failures; inside a scroll area only what it shows counts.
		var vs: Vector2 = get_viewport().get_visible_rect().size
		var bad := []
		for c in _controls(root):
			if not c.is_visible_in_tree() or not (c is BaseButton or c is LineEdit):
				continue
			var r: Rect2 = c.get_global_rect()
			if r.size.x < 2 or r.size.y < 2:
				continue
			var p: Node = c.get_parent()
			while p and not (p is ScrollContainer):
				p = p.get_parent()
			if p:
				if not (p as Control).get_global_rect().intersects(r):
					continue
				r = (p as Control).get_global_rect().intersection(r)
			if r.position.x < -1 or r.position.y < -1 or r.end.x > vs.x + 1 or r.end.y > vs.y + 1:
				bad.append("%s at %s" % [str(c.get("text") if c.get("text") else c.name), str(r)])
		print("[ui] %s %s: %s" % ["PASS" if bad.is_empty() else "FAIL", where, "all controls on screen" if bad.is_empty() else "; ".join(bad.slice(0, 6))])
		return 0 if bad.is_empty() else 1

	func _controls(n: Node) -> Array:
		var o := []
		if n is Control:
			o.append(n)
		for ch in n.get_children():
			o.append_array(_controls(ch))
		return o

	func _frames(n: int) -> void:
		for i in n:
			await get_tree().process_frame

	func _wait(s: float) -> void:
		await get_tree().create_timer(s).timeout
