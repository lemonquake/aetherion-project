extends Control
## Lobby: every team as a card with its slots (players, bots-to-come, open seats you can take with one tap), the
## host's Game Setup (teams, squad size, bots, safe zone) and Start, everyone else's Ready, the Locker to change
## outfit before the match, and who else is online.

const SettingsScreen := preload("res://src/ui/settings_ui.gd")
const MenuBg := preload("res://src/ui/menu_bg.gd")
const Locker := preload("res://src/ui/locker.gd")

var _teams: HFlowContainer
var _ready_btn: Button
var _start_btn: Button
var _info: Label
var _title: Label
var _setup: Control
var _setup_box: VBoxContainer
var _locker_layer: Control
var _cfg_key := ""


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBg.new("lobby_bg", 0.5))
	var compact := get_viewport_rect().size.x < 1500.0
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40 if not compact else 22)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var col := UITheme.vbox(14)
	margin.add_child(col)
	# Header
	var head := UITheme.hbox(14)
	var hv := UITheme.vbox(0)
	hv.add_child(UITheme.label("LOBBY", 18, UITheme.ACCENT, UITheme.font_semibold))
	_title = UITheme.label("", 44 if not compact else 36, UITheme.TEXT, UITheme.font_condensed)
	hv.add_child(_title)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	head.add_child(UITheme.icon_button("locker", "Outfit", _open_locker))
	head.add_child(UITheme.icon_button("settings", "", func(): add_child(SettingsScreen.new()), "FlatButton"))
	head.add_child(UITheme.icon_button("back", "Leave", func(): Game.leave_to_menu()))
	col.add_child(head)
	_info = UITheme.label("", 19, UITheme.TEXT_DIM)
	col.add_child(_info)
	# Teams and setup
	var row := UITheme.hbox(20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(sc)
	_teams = HFlowContainer.new()
	_teams.add_theme_constant_override("h_separation", 12)
	_teams.add_theme_constant_override("v_separation", 12)
	_teams.alignment = FlowContainer.ALIGNMENT_CENTER   # a short last row sits in the middle, not alone at the left
	_teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_teams)
	_setup = UITheme.panel(null, "panel")
	_setup.custom_minimum_size = Vector2(400 if not compact else 360, 0)
	var ssc := ScrollContainer.new()
	ssc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_setup.add_child(ssc)
	_setup_box = UITheme.vbox(12)
	_setup_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ssc.add_child(_setup_box)
	row.add_child(_setup)
	# Bottom: ready / start
	var bottom := UITheme.hbox(12)
	var tip := UITheme.label("Tap a team to join it. Bots take the seats nobody takes.", 17, UITheme.TEXT_DIM)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(tip)
	_ready_btn = UITheme.primary("READY", _toggle_ready, 260, 72)
	bottom.add_child(_ready_btn)
	_start_btn = UITheme.primary("START MATCH", func(): Game.start_match(), 320, 72)
	bottom.add_child(_start_btn)
	col.add_child(bottom)
	Net.lobby_changed.connect(_refresh)
	_refresh()


func _setup_panel() -> void:
	## Rebuilt only when the configuration changes (the host's own controls must not reset under their finger).
	var host := Net.is_server
	var key := JSON.stringify(Net.config) + str(host)
	if key == _cfg_key:
		return
	_cfg_key = key
	for c in _setup_box.get_children():
		c.queue_free()
	_setup_box.add_child(UITheme.section("Game Setup", "Only the host can change these." if not host else ""))
	var cfg := Net.config
	if host:
		_setup_box.add_child(_field("Teams", UITheme.stepper(int(cfg.get("teams", 5)), 2, Net.MAX_TEAMS, func(v): Net.set_config("teams", v))))
		_setup_box.add_child(_field("Squad size", UITheme.segmented([[1, "Solo"], [2, "Duo"], [3, "Trio"], [4, "Squad"]], Net.team_size(), func(v): Net.set_config("team_size", v))))
		_setup_box.add_child(UITheme.toggle("Fill empty slots with bots", bool(cfg.get("bots", true)), func(v): Net.set_config("bots", v)))
		_setup_box.add_child(_field("Safe zone", UITheme.segmented([[1.0, "Normal"], [1.6, "Fast"], [2.5, "Rapid"]], float(cfg.get("zone_speed", 1.0)), func(v): Net.set_config("zone_speed", v))))
	else:
		for kv in [["Teams", str(int(cfg.get("teams", 5)))], ["Squad size", str(Net.team_size())], ["Bots", "Fill empty slots" if cfg.get("bots", true) else "Off"],
				["Safe zone", {1.0: "Normal", 1.6: "Fast", 2.5: "Rapid"}.get(float(cfg.get("zone_speed", 1.0)), "Normal")]]:
			var h := UITheme.hbox(8)
			var k := UITheme.label(kv[0], 19, UITheme.TEXT_DIM)
			k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(k)
			h.add_child(UITheme.label(kv[1], 21, UITheme.TEXT, UITheme.font_semibold))
			_setup_box.add_child(h)
	var addr := UITheme.label("", 16, UITheme.TEXT_DIM)
	addr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if host:
		var ips = Array(IP.get_local_addresses()).filter(func(a): return a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"))
		addr.text = "Players on your network see this game under Play. Address: %s (port %d)." % [", ".join(ips.slice(0, 2)) if not ips.is_empty() else "this PC", Net.port]
	_setup_box.add_child(addr)


func _field(title: String, c: Control) -> Control:
	var v := UITheme.vbox(4)
	v.add_child(UITheme.label(title, 17, UITheme.TEXT_DIM, UITheme.font_semibold))
	v.add_child(c)
	return v


func _refresh() -> void:
	if not is_inside_tree():
		return
	var host := Net.is_server
	_title.text = str(Net.config.get("name", "")) if str(Net.config.get("name", "")) != "" else "Custom game"
	_setup_panel()
	for c in _teams.get_children():
		c.queue_free()
	var size := Net.team_size()
	var n_teams := clampi(int(Net.config.get("teams", 5)), 1, Net.MAX_TEAMS)
	var teams := {}
	var unassigned := []
	for pid in Net.players:
		var t: int = Net.players[pid].team
		if t < 0 or t >= n_teams:
			unassigned.append(pid)
		else:
			if not teams.has(t):
				teams[t] = []
			teams[t].append(pid)
	# Players with no team yet show where they would go: the first team with room.
	var free := []
	for t in n_teams:
		for i in size - (teams.get(t, []) as Array).size():
			free.append(t)
	for t in n_teams:
		_teams.add_child(_team_card(t, teams.get(t, []), size, unassigned, free))
	var me: Dictionary = Net.players.get(Net.local_pid, {})
	_ready_btn.text = "NOT READY" if me.get("ready", false) else "READY"
	_ready_btn.visible = not host
	_start_btn.visible = host
	var humans := Net.humans()
	var ready := 0
	for pid in Net.players:
		if not Net.players[pid].bot and (Net.players[pid].ready or pid == 1):
			ready += 1
	var bots := maxi(Net.slot_count() - humans, 0) if Net.config.get("bots", true) else 0
	_info.text = "%d human%s (%d ready) and %d bot%s · %d teams of %d · %s" % [humans, "" if humans == 1 else "s", ready, bots, "" if bots == 1 else "s",
		n_teams, size, "You are hosting." if host else "Waiting for the host to start."]


func _team_card(t: int, members: Array, size: int, unassigned: Array, free: Array) -> Control:
	var col: Color = UITheme.TEAM_COLORS[t % UITheme.TEAM_COLORS.size()]
	var mine: bool = int(Net.players.get(Net.local_pid, {}).get("team", -2)) == t
	var card := Button.new()
	card.theme_type_variation = "CardButton"
	card.toggle_mode = true
	card.button_pressed = mine
	card.custom_minimum_size = Vector2(300, 74 + size * 52)
	card.disabled = members.size() >= size and not mine
	card.pressed.connect(func():
		SoundSys.play_ui("ui_select")
		if not mine:
			Net.request_team(t)
		else:
			card.set_pressed_no_signal(true))
	var v := UITheme.vbox(6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 10
	v.offset_bottom = -10
	card.add_child(v)
	var head := UITheme.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stripe := ColorRect.new()
	stripe.color = col
	stripe.custom_minimum_size = Vector2(6, 30)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(stripe)
	var tl := UITheme.label("Team %d" % (t + 1), 26, col.lightened(0.1), UITheme.font_condensed)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(UITheme.label("%d / %d" % [members.size(), size], 17, UITheme.TEXT_DIM))
	v.add_child(head)
	for pid in members:
		v.add_child(_slot_row(pid))
	var bots_on: bool = Net.config.get("bots", true)
	for i in size - members.size():
		var r := UITheme.hbox(8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.custom_minimum_size = Vector2(0, 44)
		var ic := TextureRect.new()
		ic.texture = Icons.texture("bot" if bots_on else "plus", 22, UITheme.TEXT_DIM * Color(1, 1, 1, 0.7))
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(ic)
		r.add_child(UITheme.label("Bot" if bots_on else "Open seat", 19, UITheme.TEXT_DIM * Color(1, 1, 1, 0.75)))
		if not mine and i == 0:
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.add_child(spacer)
			r.add_child(UITheme.label("Tap to join", 16, UITheme.ACCENT))
		v.add_child(r)
	return card


func _slot_row(pid: int) -> Control:
	var p: Dictionary = Net.players[pid]
	var r := UITheme.hbox(8)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.custom_minimum_size = Vector2(0, 44)
	var ic := TextureRect.new()
	ic.texture = Icons.texture("bot" if p.bot else ("phone" if str(p.get("platform", "PC")) == "Mobile" else "monitor"), 22, UITheme.TEXT)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(ic)
	var name := UITheme.label(str(p.name) + ("  (you)" if pid == Net.local_pid else ""), 20, UITheme.TEXT if p.connected else UITheme.TEXT_DIM, UITheme.font_semibold)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	r.add_child(name)
	if not p.bot:
		r.add_child(UITheme.pill("Lv %d" % int(p.get("level", 1)), UITheme.ACCENT, 13))
		if pid == 1:
			r.add_child(UITheme.pill("Host", UITheme.ACCENT2, 13))
		elif p.ready:
			r.add_child(UITheme.pill("Ready", UITheme.GOOD, 13))
	return r


func _toggle_ready() -> void:
	var me: Dictionary = Net.players.get(Net.local_pid, {})
	Net.request_set_ready(not me.get("ready", false))


func _open_locker() -> void:
	if _locker_layer and is_instance_valid(_locker_layer):
		return
	_locker_layer = Control.new()
	_locker_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_locker_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_locker_layer)
	_locker_layer.add_child(MenuBg.new("locker_bg", 0.5))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 28)
	_locker_layer.add_child(m)
	var v := UITheme.vbox(12)
	m.add_child(v)
	var h := UITheme.hbox(10)
	var t := UITheme.label("Locker", 44, UITheme.TEXT, UITheme.font_condensed)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(UITheme.primary("DONE", func(): _locker_layer.queue_free(), 180, 60))
	v.add_child(h)
	v.add_child(Locker.new())
