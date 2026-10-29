extends Control
## Main menu: key art of Sitio Kalinaw under the artificial sun, a top bar (Home, Play, Locker, Profile, Leaderboard,
## your level and XP, Settings) and one page at a time. Home starts a match in one tap; Play hosts a custom game
## (teams, squad size, bots) or joins one from the list (same Wi-Fi/LAN and the stats server) or by address.
## Laid out for a mouse at 1920x1080 and for thumbs on a phone (drawn 1.5x larger there).

const SettingsScreen := preload("res://src/ui/settings_ui.gd")
const MenuBg := preload("res://src/ui/menu_bg.gd")
const Locker := preload("res://src/ui/locker.gd")
const GameSetup := preload("res://src/ui/game_setup.gd")
const PAGES := [["home", "Home", "home"], ["play", "Play", "play"], ["locker", "Locker", "locker"], ["profile", "Profile", "profile"], ["leaderboard", "Leaderboard", "trophy"]]

var _status: Label
var _pages := {}
var _tabs := {}
var _page := "home"
var _body: Control
var _chip_level: Label
var _chip_name: Label
var _chip_bar: ProgressBar
var _online_list: VBoxContainer
var _games_list: VBoxContainer
var _server_pill: Label
var _address: LineEdit
var _create := {"name": "", "teams": 5, "team_size": 4, "bots": true, "zone_speed": 1.0, "game_mode": "classic", "dm_team_size": 10}
var _summary: Label
var _lb_by := "xp"
var _lb_list: VBoxContainer
var _lb_note: Label
var _compact := false


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBg.new("menu_bg", 0.0))
	var vs := get_viewport_rect().size
	_compact = vs.x < 1500.0 or vs.y < 800.0   # phones (UI drawn 1.5x) and small windows
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40 if not _compact else 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var col := UITheme.vbox(18)
	margin.add_child(col)
	col.add_child(_top_bar())
	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	col.add_child(_bottom_bar())
	_create.name = "%s's game" % Settings.player_name()
	_create.game_mode = Profile.game_mode
	_create.dm_team_size = int(Defs.rule("deathmatch.team_size", 10))
	_show("home")
	Profile.changed.connect(_refresh_chip)
	Online.changed.connect(_refresh_online)
	_refresh_chip()
	_refresh_online()
	if Game.arg("ui_tour_r7") and not Game.has_node("UiTourR7"):
		var tour: Node = GameSetup.Tour.new()
		tour.name = "UiTourR7"
		Game.add_child(tour)


# ------------------------------------------------------------------ frame

func _top_bar() -> Control:
	var bar := UITheme.hbox(14)
	var logo := UITheme.vbox(-6)
	var t := UITheme.label("AETHERION", 46 if not _compact else 36, UITheme.TEXT, UITheme.font_condensed)
	t.add_theme_constant_override("outline_size", 0)
	logo.add_child(t)
	if not _compact:
		logo.add_child(UITheme.label("Project by Aljay Leodones", 17, UITheme.ACCENT, UITheme.font_semibold))
	bar.add_child(logo)
	bar.add_child(UITheme.spacer(0, 18 if not _compact else 6))
	var tabs := UITheme.hbox(4)
	var group := ButtonGroup.new()
	for p in PAGES:
		var b := Button.new()
		b.text = "" if _compact and p[0] != "play" else str(p[1])
		b.icon = Icons.texture(str(p[2]), 26, Color.WHITE)
		b.tooltip_text = str(p[1])
		b.toggle_mode = true
		b.button_group = group
		b.theme_type_variation = "FlatButton"
		b.custom_minimum_size = Vector2(56, 56)
		b.add_theme_font_size_override("font_size", 21)
		b.add_theme_constant_override("h_separation", 8)
		var id := str(p[0])
		b.pressed.connect(func(): SoundSys.play_ui("ui_select"); _show(id))
		tabs.add_child(b)
		_tabs[id] = b
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_child(tabs)
	# Your level and XP: tap for the profile.
	var chip := Button.new()
	chip.theme_type_variation = "FlatButton"
	chip.custom_minimum_size = Vector2(250 if not _compact else 200, 60)
	chip.pressed.connect(func(): _show("profile"))
	var ch := UITheme.hbox(10)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ch.offset_left = 8
	ch.offset_right = -8
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.box(Color(0.14, 0.1, 0.05, 0.95), UITheme.ACCENT, 26, 0, 0, 2))
	badge.custom_minimum_size = Vector2(50, 50)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_level = UITheme.label("1", 22, UITheme.ACCENT, UITheme.font_condensed)
	_chip_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chip_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(_chip_level)
	ch.add_child(badge)
	var nv := UITheme.vbox(4)
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	_chip_name = UITheme.label("", 19, UITheme.TEXT, UITheme.font_semibold)
	_chip_name.clip_text = true
	nv.add_child(_chip_name)
	_chip_bar = UITheme.bar(0, 1, UITheme.ACCENT, 7)
	_chip_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nv.add_child(_chip_bar)
	ch.add_child(nv)
	chip.add_child(ch)
	bar.add_child(chip)
	var gear := UITheme.icon_button("settings", "", _open_settings, "FlatButton")
	gear.custom_minimum_size = Vector2(56, 56)
	gear.tooltip_text = "Settings"
	bar.add_child(gear)
	return bar


func _bottom_bar() -> Control:
	var bar := UITheme.hbox(12)
	_server_pill = UITheme.label("", 16, UITheme.TEXT_DIM)
	bar.add_child(Icons_rect("globe", 18, UITheme.TEXT_DIM))
	bar.add_child(_server_pill)
	_status = UITheme.label("", 18, UITheme.WARN)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_status)
	bar.add_child(UITheme.label("Version %s" % ProjectSettings.get_setting("application/config/version"), 15, UITheme.TEXT_DIM * Color(1, 1, 1, 0.7)))
	if not OS.has_feature("mobile"):
		var q := UITheme.icon_button("exit", "Quit", func(): get_tree().quit(), "FlatButton")
		q.custom_minimum_size = Vector2(0, 44)
		bar.add_child(q)
	return bar


static func Icons_rect(name: String, size: int, color: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Icons.texture(name, size, color)
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _show(id: String) -> void:
	_page = id
	if _tabs.has(id):
		_tabs[id].button_pressed = true   # (the group lets the other tabs go)
	for k in _pages:
		_pages[k].visible = k == id
	if not _pages.has(id):
		var p: Control = call("_page_" + id)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_body.add_child(p)
		_pages[id] = p
	if id == "leaderboard":
		_load_leaderboard()
	if id == "profile" and _pages.has("profile"):
		_pages.profile.queue_free()
		_pages.erase("profile")
		var p2: Control = _page_profile()
		p2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_body.add_child(p2)
		_pages.profile = p2


func _refresh_chip() -> void:
	_chip_level.text = str(Profile.level())
	_chip_name.text = Settings.player_name()
	var pr := Profile.progress()
	_chip_bar.max_value = pr[1]
	_chip_bar.value = pr[0]


# ------------------------------------------------------------------ Home

func _page_home() -> Control:
	var dm := Profile.game_mode == "deathmatch"
	var row := UITheme.hbox(30)
	var left := UITheme.vbox(12 if not _compact else 10)
	left.custom_minimum_size = Vector2(580 if not _compact else 480, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	left.add_child(UITheme.label("%s · %s" % [UITheme.MAP_NAMES.get(_map_for(Profile.game_mode), ""), UITheme.MODE_NAMES.get(Profile.game_mode, "")], 20, UITheme.ACCENT, UITheme.font_semibold))
	if not _compact:
		left.add_child(UITheme.label("Choose a mode", 52, UITheme.TEXT, UITheme.font_condensed))
		for m in ["classic", "deathmatch"]:
			left.add_child(_mode_card(m))
		left.add_child(UITheme.spacer(4))
	else:
		var seg := UITheme.segmented([["classic", "Classic"], ["deathmatch", "Deathmatch"]], Profile.game_mode, _set_mode)
		for b in seg.get_children():
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 22)
		left.add_child(seg)
		var d := UITheme.label(MODE_TEXT[Profile.game_mode], 17, UITheme.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(d)
	var quick := UITheme.primary("PLAY NOW", _quick_match, 0, 96 if not _compact else 76)
	quick.add_theme_font_size_override("font_size", 40)
	left.add_child(quick)
	var practice := UITheme.label(("Practice: you and 19 bots, %s against %s, 10 a side. Set up your gear in the lobby, then start." % [UITheme.dm_team_name(0), UITheme.dm_team_name(1)]) if dm
		else "Practice: you and 19 bots in 5 squads of 4. Check your squad in the lobby, then start.", 17, UITheme.TEXT_DIM)
	practice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(practice)
	var r2 := UITheme.hbox(10)
	var find := UITheme.icon_button("globe", "Find a game", func(): _show("play"))
	find.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(find)
	var host := UITheme.icon_button("plus", "Host a game", func(): _show("play"))
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(host)
	if dm and _compact:
		var gs := UITheme.icon_button("gun", "Game Setup", open_game_setup)
		gs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(gs)
	left.add_child(r2)
	if dm and not _compact:
		left.add_child(_loadout_button())
	elif not _compact:
		var locker := UITheme.icon_button("locker", "Customize your character", func(): _show("locker"))
		left.add_child(locker)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	# Right: who is online, your last match.
	var right := UITheme.vbox(14)
	right.custom_minimum_size = Vector2(420 if not _compact else 360, 0)
	row.add_child(right)
	var op := UITheme.panel(null, "panel")
	op.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ov := UITheme.vbox(8)
	op.add_child(ov)
	var oh := UITheme.hbox(8)
	oh.add_child(Icons_rect("users", 24, UITheme.ACCENT2))
	oh.add_child(UITheme.label("Online now", 26, UITheme.TEXT, UITheme.font_condensed))
	ov.add_child(oh)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_online_list = UITheme.vbox(6)
	_online_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_online_list)
	ov.add_child(sc)
	right.add_child(op)
	right.add_child(_last_match_card())
	return row


# ------------------------------------------------------------------ r7: game modes

const MODE_TEXT := {
	"classic": "Battle royale on Sitio Kalinaw. Parachute in, loot weapons and gear, and survive the shrinking haze. Day and night change every 5 minutes. The last team standing wins.",
	"deathmatch": "Two teams of up to 10 on Lawless Sub. Pick a primary and a secondary gun; everyone starts with armour and a heavy-plate helmet. No respawns: the last team standing wins. Loot and swap guns as you go; the haze and day and night still apply.",
}


func _map_for(mode: String) -> String:
	## The map a mode plays on (rules.json game_modes.<mode>.map); --map=<id> overrides it for tests.
	if Game.arg("map"):
		return str(Game.arg("map"))
	return str(Defs.rule("game_modes.%s.map" % mode, "lawless_sub" if mode == "deathmatch" else "kalinaw"))


func _mode_card(m: String) -> Control:
	## A selectable card: icon, name, map and the plain description. The whole card is one button.
	var on := Profile.game_mode == m
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var b := Button.new()
	b.theme_type_variation = "CardButton"
	b.toggle_mode = true
	b.button_pressed = on
	b.tooltip_text = str(UITheme.MODE_NAMES[m])
	b.pressed.connect(func(): SoundSys.play_ui("ui_select"); _set_mode(m))
	pc.add_child(b)
	var mc := MarginContainer.new()
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, 14)
	pc.add_child(mc)
	var h := UITheme.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(h)
	var ic := TextureRect.new()
	ic.texture = Icons.texture("parachute" if m == "classic" else "swords", 44, UITheme.ACCENT if on else UITheme.TEXT_DIM)
	ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := UITheme.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var th := UITheme.hbox(10)
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UITheme.label(str(UITheme.MODE_NAMES[m]), 32, UITheme.TEXT, UITheme.font_condensed)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(t)
	var mp := UITheme.pill(str(UITheme.MAP_NAMES.get(_map_for(m), _map_for(m))), UITheme.ACCENT2, 15)
	mp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(mp)
	v.add_child(th)
	var d := UITheme.label(MODE_TEXT[m], 17, UITheme.TEXT if on else UITheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	return pc


func _loadout_button() -> Control:
	## Deathmatch: your two guns at a glance; opens Game Setup.
	var lo := Profile.get_loadout()
	var b := UITheme.icon_button("gun", "Game Setup:  %s + %s" % [Defs.item_name(str(lo.primary)), Defs.item_name(str(lo.secondary))], open_game_setup)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	return b


func _set_mode(m: String) -> void:
	## The mode for Play Now and Host Game, saved in the profile. Home and Play are rebuilt to match.
	if m == Profile.game_mode and m == str(_create.game_mode):
		return
	Profile.set_game_mode(m)
	_create.game_mode = Profile.game_mode
	_rebuild_pages.call_deferred()


func _rebuild_pages() -> void:
	for k in ["home", "play"]:
		if _pages.has(k):
			_pages[k].queue_free()
			_pages.erase(k)
	_show(_page)


func open_game_setup() -> Control:
	var gs: Control = GameSetup.new()
	gs.closed.connect(func(): if _page in ["home", "play"]: _rebuild_pages())
	add_child(gs)
	return gs


func _apply_mode_config(mode: String, team_size: int) -> void:
	## Every host path sets the mode and map explicitly: Net.shutdown() keeps the config of the last session.
	Net.set_config("game_mode", mode)
	Net.set_config("map", _map_for(mode))
	if mode == "deathmatch":
		Net.set_config("teams", 2)
		Net.set_config("team_size", clampi(team_size, 1, 10))


func _last_match_card() -> Control:
	var p := UITheme.panel(null, "panel_accent")
	var v := UITheme.vbox(6)
	p.add_child(v)
	v.add_child(UITheme.label("Your last match", 22, UITheme.TEXT, UITheme.font_condensed))
	if Profile.history.is_empty():
		var l := UITheme.label("No matches yet. Your level, XP and stats grow with every match you play.", 17, UITheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	else:
		var h: Dictionary = Profile.history[0]
		var r := UITheme.hbox(18)
		for kv in [["Place", "#%d" % int(h.place)], ["Kills", str(int(h.kills))], ["Damage", str(int(h.damage))], ["XP", "+%d" % int(h.xp)]]:
			var c := UITheme.vbox(0)
			c.add_child(UITheme.label(kv[0], 15, UITheme.TEXT_DIM))
			c.add_child(UITheme.label(kv[1], 28, UITheme.ACCENT if kv[0] == "XP" else UITheme.TEXT, UITheme.font_condensed))
			r.add_child(c)
		v.add_child(r)
	return p


func _refresh_online() -> void:
	if _server_pill:
		_server_pill.text = Online.status
	if _online_list and is_instance_valid(_online_list):
		for c in _online_list.get_children():
			c.queue_free()
		var people: Array = Online.online_players
		if people.is_empty():
			var l := UITheme.label("Nobody else is online right now. Games on your Wi-Fi still show under Play.", 17, UITheme.TEXT_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_online_list.add_child(l)
		for p in people.slice(0, 30):
			_online_list.add_child(_person_row(p))
	if _games_list and is_instance_valid(_games_list):
		_fill_games()


func _person_row(p: Dictionary) -> Control:
	var h := UITheme.hbox(8)
	h.add_child(Icons_rect("phone" if str(p.get("platform", "PC")) == "Mobile" else "monitor", 20, UITheme.TEXT_DIM))
	var n := UITheme.label(str(p.get("name", "?")) + ("  (you)" if str(p.get("id", "")) == Profile.id else ""), 19, UITheme.TEXT)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	h.add_child(UITheme.pill("Lv %d" % int(p.get("level", 1)), UITheme.ACCENT, 14))
	var st := UITheme.label(str(p.get("status", "")), 15, UITheme.TEXT_DIM)
	h.add_child(st)
	var gid := str(p.get("game", ""))
	if gid != "" and str(p.get("id", "")) != Profile.id:
		for g in Online.games():
			if str(g.get("game", "")) == gid:
				var addr := str(g.get("address", ""))
				var port := int(g.get("port", Net.DEFAULT_PORT))
				var j := UITheme.button("Join", func(): _join(addr, port), 80)
				j.custom_minimum_size.y = 40
				h.add_child(j)
	return h


# ------------------------------------------------------------------ Play: host or join

func _page_play() -> Control:
	var row := UITheme.hbox(24)
	# Create a game
	var cp := UITheme.panel(null, "panel")
	cp.custom_minimum_size = Vector2(520 if not _compact else 470, 0)
	cp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cp.add_child(sc)
	var cv := UITheme.vbox(14)
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(cv)
	cv.add_child(UITheme.section("Host a game", "Others on your Wi-Fi see it at once; with a stats server, everyone online does."))
	var name := LineEdit.new()
	name.text = str(_create.name)
	name.max_length = 32
	name.custom_minimum_size = Vector2(0, 50)
	name.placeholder_text = "Game name"
	name.text_changed.connect(func(t): _create.name = t)
	cv.add_child(_field("Game name", name))
	cv.add_child(_field("Mode", UITheme.segmented([["classic", "Classic"], ["deathmatch", "Deathmatch"]], str(_create.game_mode), _set_mode)))
	if str(_create.game_mode) == "deathmatch":
		cv.add_child(_field("Players per team (%s and %s)" % [UITheme.dm_team_name(0), UITheme.dm_team_name(1)],
			UITheme.stepper(int(_create.dm_team_size), 1, 10, func(v): _create.dm_team_size = v; _update_summary())))
	else:
		cv.add_child(_field("Teams", UITheme.stepper(int(_create.teams), 2, Net.MAX_TEAMS, func(v): _create.teams = v; _update_summary())))
		cv.add_child(_field("Squad size", UITheme.segmented([[1, "Solo"], [2, "Duo"], [3, "Trio"], [4, "Squad"]], int(_create.team_size), func(v): _create.team_size = v; _update_summary())))
	cv.add_child(UITheme.toggle("Fill empty slots with bots", bool(_create.bots), func(v): _create.bots = v; _update_summary()))
	cv.add_child(_field("Safe zone", UITheme.segmented([[1.0, "Normal"], [1.6, "Fast"], [2.5, "Rapid"]], float(_create.zone_speed), func(v): _create.zone_speed = v)))
	_summary = UITheme.label("", 18, UITheme.ACCENT2)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_summary)
	if str(_create.game_mode) == "deathmatch":
		cv.add_child(_loadout_button())
	var hb := UITheme.primary("HOST GAME", _host_custom, 0, 72)
	cv.add_child(hb)
	_update_summary()
	row.add_child(cp)
	# Open games
	var gp := UITheme.panel(null, "panel")
	gp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var gv := UITheme.vbox(12)
	gp.add_child(gv)
	var gh := UITheme.hbox(10)
	var gt := UITheme.section("Open games", "On your network and on the stats server.")
	gt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gh.add_child(gt)
	var rf := UITheme.icon_button("refresh", "Refresh", func(): Online._hello_t = 0.0; _fill_games())
	rf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gh.add_child(rf)
	gv.add_child(gh)
	var gsc := ScrollContainer.new()
	gsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_games_list = UITheme.vbox(8)
	_games_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gsc.add_child(_games_list)
	gv.add_child(gsc)
	var jr := UITheme.hbox(10)
	jr.add_child(Icons_rect("link", 22, UITheme.TEXT_DIM))
	_address = LineEdit.new()
	_address.placeholder_text = "Join by address, e.g. 192.168.1.20"
	_address.custom_minimum_size = Vector2(0, 50)
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jr.add_child(_address)
	jr.add_child(UITheme.button("Join", func():
		var a := _address.text.strip_edges()
		if a == "":
			show_status("Type the host's address first.")
			return
		var port := Net.DEFAULT_PORT
		if a.contains(":"):
			port = int(a.get_slice(":", 1))
			a = a.get_slice(":", 0)
		_join(a, port), 120))
	gv.add_child(jr)
	row.add_child(gp)
	_fill_games()
	return row


func _field(title: String, c: Control) -> Control:
	var v := UITheme.vbox(4)
	v.add_child(UITheme.label(title, 17, UITheme.TEXT_DIM, UITheme.font_semibold))
	v.add_child(c)
	return v


func _update_summary() -> void:
	if _summary == null:
		return
	if str(_create.game_mode) == "deathmatch":
		var n := int(_create.dm_team_size)
		_summary.text = "Deathmatch on %s: %s against %s, %d a side. %s" % [UITheme.MAP_NAMES.get(_map_for("deathmatch"), ""), UITheme.dm_team_name(0), UITheme.dm_team_name(1), n,
			("Bots fill whatever the humans leave open (%d with just you)." % (2 * n - 1)) if _create.bots else "No bots: only humans play."]
		return
	var slots := int(_create.teams) * int(_create.team_size)
	_summary.text = "Classic on %s: %d teams of %d, %d players. %s" % [UITheme.MAP_NAMES.get(_map_for("classic"), ""), int(_create.teams), int(_create.team_size), slots,
		("Bots fill whatever the humans leave open (%d with just you)." % (slots - 1)) if _create.bots else "No bots: only humans play."]


func _fill_games() -> void:
	for c in _games_list.get_children():
		c.queue_free()
	var gs: Array = Online.games()
	if gs.is_empty():
		var l := UITheme.label("No open games found yet. Host one, or ask a friend for their address.", 18, UITheme.TEXT_DIM)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_games_list.add_child(l)
		return
	for g in gs:
		var p := UITheme.panel(null, "panel_light")
		var h := UITheme.hbox(12)
		p.add_child(h)
		var info := UITheme.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := UITheme.label(str(g.get("name", "Game")), 22, UITheme.TEXT, UITheme.font_semibold)
		title.clip_text = true
		info.add_child(title)
		var sub := UITheme.hbox(8)
		sub.add_child(UITheme.label("Host %s" % str(g.get("host", "?")), 16, UITheme.TEXT_DIM))
		var gm := str(g.get("game_mode", "classic"))
		sub.add_child(UITheme.pill(str(UITheme.MODE_NAMES.get(gm, gm.capitalize())), UITheme.ACCENT if gm == "deathmatch" else UITheme.TEXT_DIM, 15))
		if g.has("map"):
			sub.add_child(UITheme.pill(str(UITheme.MAP_NAMES.get(str(g.map), str(g.map))), UITheme.TEXT_DIM, 15))
		sub.add_child(UITheme.pill("LAN" if g.get("lan", false) else "Online", UITheme.ACCENT2, 13))
		if str(g.get("version", Net.VERSION)) != Net.VERSION:
			sub.add_child(UITheme.pill("Other version", UITheme.DANGER, 13))
		info.add_child(sub)
		h.add_child(info)
		var cnt := UITheme.vbox(0)
		cnt.add_child(UITheme.label("%d / %d" % [int(g.get("players", 0)), int(g.get("max", 0))], 26, UITheme.TEXT, UITheme.font_condensed))
		cnt.add_child(UITheme.label("%d × %d%s" % [int(g.get("teams", 0)), int(g.get("team_size", 0)), " + bots" if g.get("bots", false) else ""], 15, UITheme.TEXT_DIM))
		h.add_child(cnt)
		var addr := str(g.get("address", ""))
		var port := int(g.get("port", Net.DEFAULT_PORT))
		var jb := UITheme.button("Join", func(): _join(addr, port), 110)
		jb.disabled = str(g.get("version", Net.VERSION)) != Net.VERSION or str(g.get("state", "lobby")) != "lobby" and int(g.get("players", 0)) >= int(g.get("max", 0))
		jb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(jb)
		_games_list.add_child(p)


# ------------------------------------------------------------------ Locker, Profile, Leaderboard

func _page_locker() -> Control:
	return Locker.new()


func _page_profile() -> Control:
	var row := UITheme.hbox(24)
	var left := UITheme.panel(null, "panel_accent")
	left.custom_minimum_size = Vector2(440 if not _compact else 380, 0)
	var lv := UITheme.vbox(12)
	left.add_child(lv)
	var top := UITheme.hbox(16)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.box(Color(0.14, 0.1, 0.05, 0.95), UITheme.ACCENT, 48, 0, 0, 3))
	badge.custom_minimum_size = Vector2(96, 96)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bl := UITheme.label(str(Profile.level()), 46, UITheme.ACCENT, UITheme.font_condensed)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	top.add_child(badge)
	var nm := UITheme.vbox(4)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_child(UITheme.label("Level %d" % Profile.level(), 18, UITheme.TEXT_DIM))
	var name := LineEdit.new()
	name.text = Settings.player_name()
	name.max_length = 20
	name.custom_minimum_size = Vector2(0, 50)
	name.text_changed.connect(func(t): Settings.set_value("player", "name", t.strip_edges()); Settings.save_settings(); _refresh_chip())
	nm.add_child(name)
	top.add_child(nm)
	lv.add_child(top)
	# Player setup: the laser pointer colour everyone sees when you point (hold V).
	lv.add_child(UITheme.label("Player setup  ·  laser pointer colour", 17, UITheme.TEXT_DIM, UITheme.font_semibold))
	lv.add_child(SettingsScreen.laser_picker())
	var pr := Profile.progress()
	lv.add_child(UITheme.bar(pr[0], pr[1], UITheme.ACCENT, 14))
	lv.add_child(UITheme.label("%d / %d XP to level %d · %d XP in all" % [pr[0], pr[1], Profile.level() + 1, Profile.xp], 17, UITheme.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	var s: Dictionary = Profile.stats
	var kd := float(s.kills) / maxf(float(s.deaths), 1.0)
	var hrs := float(s.time_s) / 3600.0
	for kv in [["Matches", str(int(s.matches))], ["Wins", str(int(s.wins))], ["Top 5", str(int(s.top5))], ["Kills", str(int(s.kills))], ["Deaths", str(int(s.deaths))],
			["K/D", "%.2f" % kd], ["Damage", str(int(float(s.damage)))], ["Time played", "%.1f h" % hrs], ["Best place", "#%d" % int(s.best_place) if int(s.best_place) > 0 else "—"]]:
		var c := UITheme.vbox(0)
		c.add_child(UITheme.label(kv[0], 15, UITheme.TEXT_DIM))
		c.add_child(UITheme.label(kv[1], 30, UITheme.TEXT, UITheme.font_condensed))
		grid.add_child(c)
	lv.add_child(grid)
	row.add_child(left)
	var right := UITheme.panel(null, "panel")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rv := UITheme.vbox(10)
	right.add_child(rv)
	rv.add_child(UITheme.section("Recent matches"))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := UITheme.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	rv.add_child(sc)
	if Profile.history.is_empty():
		list.add_child(UITheme.label("Play a match and it shows up here.", 18, UITheme.TEXT_DIM))
	for h in Profile.history:
		var r := UITheme.hbox(14)
		var place := UITheme.label("#%d" % int(h.place), 28, UITheme.ACCENT if h.get("won", false) else UITheme.TEXT, UITheme.font_condensed)
		place.custom_minimum_size = Vector2(60, 0)
		r.add_child(place)
		var d := UITheme.label(str(h.get("date", "")).replace("T", "  "), 16, UITheme.TEXT_DIM)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(d)
		r.add_child(UITheme.label("%d kills" % int(h.kills), 18, UITheme.TEXT))
		r.add_child(UITheme.label("%d dmg" % int(h.damage), 18, UITheme.TEXT_DIM))
		r.add_child(UITheme.pill("+%d XP" % int(h.xp), UITheme.ACCENT, 14))
		list.add_child(r)
	row.add_child(right)
	return row


func _page_leaderboard() -> Control:
	var p := UITheme.panel(null, "panel")
	var v := UITheme.vbox(12)
	p.add_child(v)
	var h := UITheme.hbox(12)
	var t := UITheme.section("Leaderboard", "Every player who has played a match reported to the stats server.")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	h.add_child(UITheme.segmented([["xp", "Level"], ["wins", "Wins"], ["kills", "Kills"]], _lb_by, func(by): _lb_by = by; _load_leaderboard()))
	v.add_child(h)
	var head := _lb_row({"rank": "#", "name": "Player", "level": "Level", "wins": "Wins", "kills": "Kills", "kd": "K/D", "matches": "Matches"}, true)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lb_list = UITheme.vbox(4)
	_lb_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_lb_list)
	v.add_child(sc)
	_lb_note = UITheme.label("", 17, UITheme.TEXT_DIM)
	_lb_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_lb_note)
	return p


func _lb_row(r: Dictionary, header: bool = false, me: bool = false) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.95, 0.64, 0.23, 0.16) if me else Color(1, 1, 1, 0.03 if not header else 0.0), Color(0, 0, 0, 0), 6, 12, 6))
	var h := UITheme.hbox(10)
	pc.add_child(h)
	var cols := [["rank", 60], ["name", 0], ["level", 90], ["wins", 90], ["kills", 90], ["kd", 80], ["matches", 100]]
	for c in cols:
		var l := UITheme.label(str(r.get(c[0], "")), 16 if header else 20, UITheme.TEXT_DIM if header else (UITheme.ACCENT if c[0] == _lb_key() else UITheme.TEXT),
			UITheme.font_semibold if header or c[0] == "name" else UITheme.font_regular)
		if c[1] == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
		else:
			l.custom_minimum_size = Vector2(c[1], 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	return pc


func _lb_key() -> String:
	return {"xp": "level", "wins": "wins", "kills": "kills"}.get(_lb_by, "level")


func _load_leaderboard() -> void:
	if _lb_list == null:
		return
	_lb_note.text = "Loading…"
	Online.fetch_leaderboard(_lb_by, func(ok: bool, rows: Array):
		if not is_instance_valid(_lb_list):
			return
		for c in _lb_list.get_children():
			c.queue_free()
		for r in rows:
			_lb_list.add_child(_lb_row(r, false, str(r.get("id", "")) == Profile.id))
		if ok:
			_lb_note.text = "%d players. Your matches count once the host reports them (any game with the stats server reachable)." % rows.size()
		else:
			var me := {"rank": "—", "name": Settings.player_name(), "level": Profile.level(), "wins": int(Profile.stats.wins), "kills": int(Profile.stats.kills),
				"kd": "%.2f" % (float(Profile.stats.kills) / maxf(float(Profile.stats.deaths), 1.0)), "matches": int(Profile.stats.matches)}
			_lb_list.add_child(_lb_row(me, false, true))
			_lb_note.text = "The stats server is not reachable, so only you are listed. Start one on any PC with --master (see the README), or set its address in Settings → Online.")


# ------------------------------------------------------------------ actions

func _quick_match() -> void:
	var err := Net.host(int(Game.arg("port", Net.DEFAULT_PORT)))
	if err != OK:
		show_status("Could not start a local game (error %d)." % err)
		return
	var mode := Profile.game_mode
	Net.set_config("name", "%s's practice" % Settings.player_name())
	_apply_mode_config(mode, int(Defs.rule("deathmatch.team_size", 10)))
	if mode != "deathmatch":
		Net.set_config("teams", 5)
		Net.set_config("team_size", 4)
	Net.set_config("bots", true)
	Profile.send_loadout()
	# The lobby next: teams, Game Setup and the Locker, then START MATCH (it used to start the match at once).
	Game.show_lobby()


func _host_custom() -> void:
	var port := int(Game.arg("port", Net.DEFAULT_PORT))
	var err := Net.host(port)
	if err != OK:
		show_status("Could not open port %d (error %d). Another game may be running." % [port, err])
		return
	Net.set_config("name", str(_create.name).strip_edges() if str(_create.name).strip_edges() != "" else "%s's game" % Settings.player_name())
	var mode := str(_create.game_mode)
	_apply_mode_config(mode, int(_create.dm_team_size))
	if mode != "deathmatch":
		Net.set_config("teams", int(_create.teams))
		Net.set_config("team_size", int(_create.team_size))
	Net.set_config("bots", bool(_create.bots))
	Net.set_config("zone_speed", float(_create.zone_speed))
	Profile.send_loadout()
	Game.show_lobby()


func _join(addr: String, port: int = Net.DEFAULT_PORT) -> void:
	if addr == "":
		return
	var err := Net.join(addr, port)
	if err != OK:
		show_status("Could not start a connection (error %d)." % err)
		return
	show_status("Connecting to %s…" % addr)


func _open_settings() -> void:
	add_child(SettingsScreen.new())


func show_status(text: String) -> void:
	if _status:
		_status.text = text
