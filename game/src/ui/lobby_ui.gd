extends Control
## Lobby: players grouped by team, ready state, host's Game Setup (mode, bots), Start and Leave.

const SettingsScreen := preload("res://src/ui/settings_ui.gd")

var _list: VBoxContainer
var _ready_btn: Button
var _start_btn: Button
var _mode: OptionButton
var _bots: CheckBox
var _bot_count: SpinBox
var _info: Label
var _setup: Control


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := preload("res://src/ui/menu_backdrop.gd").new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	add_child(margin)
	var root := UITheme.hbox(28)
	margin.add_child(root)

	var left := UITheme.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	left.add_child(UITheme.label("Aetherion Project by Aljay Leodones", 22, UITheme.TEXT_DIM, UITheme.font_medium))
	left.add_child(UITheme.label("Lobby", 54, UITheme.TEXT, UITheme.font_condensed))
	_info = UITheme.label("", 19, UITheme.TEXT_DIM)
	left.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = UITheme.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var actions := UITheme.hbox(10)
	_ready_btn = UITheme.button("Ready", _toggle_ready, 180)
	actions.add_child(_ready_btn)
	actions.add_child(UITheme.button("Settings", func(): add_child(SettingsScreen.new()), 160))
	actions.add_child(UITheme.button("Leave", func(): Game.leave_to_menu(), 160))
	left.add_child(actions)

	_setup = _build_setup()
	root.add_child(_setup)

	Net.lobby_changed.connect(_refresh)
	_refresh()


func _build_setup() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(420, 0)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := UITheme.vbox(14)
	p.add_child(v)
	v.add_child(UITheme.label("Game Setup", 30, UITheme.TEXT, UITheme.font_semibold))
	var r1 := UITheme.hbox(10)
	r1.add_child(UITheme.label("Teams", 20, UITheme.TEXT_DIM))
	_mode = OptionButton.new()
	for m in ["solo", "duo", "squad"]:
		_mode.add_item({"solo": "Solo (1 player)", "duo": "Duo (2 players)", "squad": "Squad (4 players)"}[m])
		_mode.set_item_metadata(_mode.item_count - 1, m)
	_mode.item_selected.connect(func(i): Net.set_config("mode", _mode.get_item_metadata(i)))
	_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(_mode)
	v.add_child(r1)
	var r2 := UITheme.hbox(10)
	_bots = CheckBox.new()
	_bots.text = "Fill with bots"
	_bots.toggled.connect(func(on): Net.set_config("bots", on))
	r2.add_child(_bots)
	_bot_count = SpinBox.new()
	_bot_count.min_value = 0
	_bot_count.max_value = int(Defs.rule("max_players", 40)) - 1
	_bot_count.value_changed.connect(func(val): Net.set_config("bot_count", int(val)))
	r2.add_child(_bot_count)
	v.add_child(r2)
	v.add_child(UITheme.label("Matches take up to %d players (humans and bots); 20 bots by default." % int(Defs.rule("max_players", 50)), 17, UITheme.TEXT_DIM))
	_start_btn = UITheme.button("Start Match", func(): Game.start_match(), 0)
	v.add_child(_start_btn)
	return p


func _refresh() -> void:
	if not is_inside_tree():
		return
	var host := Net.is_server
	_setup.visible = true
	_mode.disabled = not host
	_bots.disabled = not host
	_bot_count.editable = host
	_start_btn.visible = host
	var mode := str(Net.config.get("mode", "squad"))
	for i in _mode.item_count:
		if _mode.get_item_metadata(i) == mode:
			_mode.select(i)
	_bots.set_pressed_no_signal(bool(Net.config.get("bots", true)))
	_bot_count.set_value_no_signal(int(Net.config.get("bot_count", 20)))
	for c in _list.get_children():
		c.queue_free()
	var size := Net.team_size()
	var teams := {}
	for pid in Net.players:
		var t: int = Net.players[pid].team
		if not teams.has(t):
			teams[t] = []
		teams[t].append(pid)
	var n_teams := maxi(2, ceili(float(maxi(Net.players.size(), 1)) / size) + 1)
	for t in range(n_teams):
		_list.add_child(_team_row(t, teams.get(t, []), size))
	if teams.has(-1):
		_list.add_child(UITheme.label("No team yet (assigned at start)", 20, UITheme.TEXT_DIM, UITheme.font_semibold))
		for pid in teams[-1]:
			_list.add_child(_player_row(pid))
	var me: Dictionary = Net.players.get(Net.local_pid, {})
	_ready_btn.text = "Not ready" if me.get("ready", false) else "Ready"
	_ready_btn.visible = not host
	var humans := 0
	var ready := 0
	for pid in Net.players:
		if not Net.players[pid].bot:
			humans += 1
			if Net.players[pid].ready or pid == 1:
				ready += 1
	_info.text = "%d player%s connected, %d ready.  %s" % [humans, "" if humans == 1 else "s", ready,
		"You are hosting." if host else "Waiting for the host to start."]
	_start_btn.disabled = not host


func _team_row(t: int, members: Array, size: int) -> Control:
	var p := PanelContainer.new()
	var v := UITheme.vbox(4)
	p.add_child(v)
	var head := UITheme.hbox(10)
	head.add_child(UITheme.label("Team %d" % (t + 1), 22, UITheme.ACCENT, UITheme.font_semibold))
	head.add_child(UITheme.label("%d / %d" % [members.size(), size], 18, UITheme.TEXT_DIM))
	var mine: bool = Net.players.get(Net.local_pid, {}).get("team", -2) == t
	if not mine and members.size() < size:
		var b := UITheme.button("Join team", func(): Net.request_team(t), 0)
		b.custom_minimum_size = Vector2(0, 32)
		head.add_child(b)
	v.add_child(head)
	for pid in members:
		v.add_child(_player_row(pid))
	return p


func _player_row(pid: int) -> Control:
	var p: Dictionary = Net.players[pid]
	var h := UITheme.hbox(10)
	var name_text: String = p.name + ("  (you)" if pid == Net.local_pid else "")
	h.add_child(UITheme.label(name_text, 20, UITheme.TEXT if p.connected else UITheme.TEXT_DIM))
	var tag := "Bot" if p.bot else ("Host" if pid == 1 else ("Ready" if p.ready else "Not ready"))
	if not p.bot:
		tag += "  ·  " + str(p.get("platform", "PC"))
	h.add_child(UITheme.label(tag, 17, UITheme.ACCENT if (p.ready or pid == 1) else UITheme.TEXT_DIM))
	return h


func _toggle_ready() -> void:
	var me: Dictionary = Net.players.get(Net.local_pid, {})
	Net.request_set_ready(not me.get("ready", false))
