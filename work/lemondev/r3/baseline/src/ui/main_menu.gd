extends Control
## Main menu: title, player name, Play (host / join / practice), Settings, Quit.

const SettingsScreen := preload("res://src/ui/settings_ui.gd")

var _status: Label
var _play_panel: Control
var _address: LineEdit
var _name: LineEdit
var _main_buttons: Control
var _bg: Control


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg = preload("res://src/ui/menu_backdrop.gd").new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	add_child(margin)

	var col := UITheme.vbox(14)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	col.add_child(UITheme.spacer(40))
	var title := UITheme.label("Aetherion Project", 84, Color(0.92, 0.93, 0.9), UITheme.font_condensed)
	col.add_child(title)
	var by := UITheme.label("by Aljay Leodones", 30, UITheme.TEXT_DIM, UITheme.font_medium)
	col.add_child(by)
	col.add_child(UITheme.spacer(36))

	var row := UITheme.hbox(10)
	row.add_child(UITheme.label("Name", 20, UITheme.TEXT_DIM))
	_name = LineEdit.new()
	_name.text = Settings.player_name()
	_name.max_length = 20
	_name.custom_minimum_size = Vector2(260, 40)
	_name.text_changed.connect(func(t): Settings.set_value("player", "name", t.strip_edges()); Settings.save_settings())
	row.add_child(_name)
	col.add_child(row)
	col.add_child(UITheme.spacer(12))

	_main_buttons = UITheme.vbox(10)
	_main_buttons.custom_minimum_size = Vector2(320, 0)
	_main_buttons.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_main_buttons.add_child(UITheme.button("Play", _toggle_play, 320))
	_main_buttons.add_child(UITheme.button("Settings", _open_settings, 320))
	_main_buttons.add_child(UITheme.button("Quit", func(): get_tree().quit(), 320))
	# The Play choices open beside the buttons, not under them: on a phone (UI drawn larger) there is no room below.
	var actions := UITheme.hbox(28)
	_main_buttons.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	actions.add_child(_main_buttons)
	_play_panel = _build_play_panel()
	_play_panel.visible = false
	_play_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	actions.add_child(_play_panel)
	col.add_child(actions)

	_status = UITheme.label("", 20, UITheme.WARN)
	col.add_child(_status)

	var foot := UITheme.label("Night falls on Sitio Kalinaw. Keep your light low and listen.", 18, UITheme.TEXT_DIM)
	foot.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	col.add_child(foot)
	var ver := UITheme.label("Version %s" % ProjectSettings.get_setting("application/config/version"), 16, UITheme.TEXT_DIM * Color(1, 1, 1, 0.7))
	col.add_child(ver)


func _build_play_panel() -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.custom_minimum_size = Vector2(560, 0)
	var v := UITheme.vbox(12)
	p.add_child(v)
	v.add_child(UITheme.label("Play", 28, UITheme.TEXT, UITheme.font_semibold))
	var host_row := UITheme.hbox(10)
	host_row.add_child(UITheme.button("Host a game", _host, 220))
	host_row.add_child(UITheme.label("Others join your address on port %d." % Net.DEFAULT_PORT, 17, UITheme.TEXT_DIM))
	v.add_child(host_row)
	var join_row := UITheme.hbox(10)
	join_row.add_child(UITheme.button("Join a game", _join, 220))
	_address = LineEdit.new()
	_address.placeholder_text = "Host address, e.g. 192.168.1.20"
	_address.text = "127.0.0.1"
	_address.custom_minimum_size = Vector2(280, 40)
	join_row.add_child(_address)
	v.add_child(join_row)
	var prac := UITheme.hbox(10)
	prac.add_child(UITheme.button("Practice with bots", _practice, 220))
	prac.add_child(UITheme.label("Solo match on this device.", 17, UITheme.TEXT_DIM))
	v.add_child(prac)
	return p


func _toggle_play() -> void:
	_play_panel.visible = not _play_panel.visible


func _host() -> void:
	var err := Net.host()
	if err != OK:
		show_status("Could not open port %d (error %d). Another game may be running." % [Net.DEFAULT_PORT, err])
		return
	Game.show_lobby()


func _practice() -> void:
	var err := Net.host()
	if err != OK:
		show_status("Could not start a local game (error %d)." % err)
		return
	Net.set_config("mode", "solo")
	Net.set_config("bots", true)
	Net.set_config("bot_count", 11)
	Game.show_lobby()


func _join() -> void:
	var addr := _address.text.strip_edges()
	if addr == "":
		show_status("Enter the host's address first.")
		return
	var err := Net.join(addr)
	if err != OK:
		show_status("Could not start a connection (error %d)." % err)
		return
	show_status("Connecting to %s…" % addr)


func _open_settings() -> void:
	var s: Control = SettingsScreen.new()
	add_child(s)


func show_status(text: String) -> void:
	if _status:
		_status.text = text
