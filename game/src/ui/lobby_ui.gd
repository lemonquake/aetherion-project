extends Control
## Lobby: every team as a card with its slots (players, bots-to-come, open seats you can take with one tap), the
## host's Game Setup (teams, squad size, bots, safe zone) and Start, everyone else's Ready, the Locker to change
## outfit before the match, and who else is online.
## r7 Deathmatch (r11: two or three teams, North / East / South Team, rules.json deathmatch.team_names) of up to 7, the host sets the
## team size, everyone sees their loadout and opens Game Setup (src/ui/game_setup.gd) to change their guns.
## r15: the host is whoever hosts the game or, on an official server, the first slot (Net.room_host). Start waits
## until every other human is Ready; alone (or with only bots) it starts at once. Deathmatch has two maps.

const SettingsScreen := preload("res://src/ui/settings_ui.gd")
const MenuBg := preload("res://src/ui/menu_bg.gd")
const Locker := preload("res://src/ui/locker.gd")
const GameSetup := preload("res://src/ui/game_setup.gd")

var _teams: HFlowContainer
var _ready_btn: Button
var _start_btn: Button
var _info: Label
var _title: Label
var _setup: Control
var _setup_box: VBoxContainer
var _locker_layer: Control
var _cfg_key := ""
var _map_offered := false   # (r16) the Home page's Deathmatch map, put to an official lobby once when you host it
var _setup_btn: Button
var _loadout_box: VBoxContainer
var _loadout_key := ""
var _tip: Label
var _compact := false
var _game_setup: Control


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuBg.new("lobby_bg", 0.5))
	var compact := get_viewport_rect().size.x < 1500.0
	_compact = compact or get_viewport_rect().size.y < 800.0   # phones (UI drawn 1.5x) are short as well
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
	_setup_btn = UITheme.icon_button("gun", "Game Setup", open_game_setup)
	head.add_child(_setup_btn)
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
	var side := UITheme.vbox(14)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ssc.add_child(side)
	_loadout_box = UITheme.vbox(8)
	# Phones: your guns first (the match settings scroll below them).
	if _compact:
		side.add_child(_loadout_box)
		side.add_child(_setup_box)
	else:
		side.add_child(_setup_box)
		side.add_child(_loadout_box)
	row.add_child(_setup)
	# Bottom: ready / start
	var bottom := UITheme.hbox(12)
	var tip := UITheme.label("Tap a team to join it. Bots take the seats nobody takes.", 17, UITheme.TEXT_DIM)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip = tip
	bottom.add_child(tip)
	_ready_btn = UITheme.primary("READY", _toggle_ready, 260, 72)
	bottom.add_child(_ready_btn)
	_start_btn = UITheme.primary("START MATCH", func(): Net.request_start(), 320, 72)
	bottom.add_child(_start_btn)
	col.add_child(bottom)
	Net.lobby_changed.connect(_refresh)
	if Net.is_server:
		Net.loadout_received.connect(func(pid: int):
			if Net.players.has(pid):
				print("[ui] loadout_received pid=%d %s %s" % [pid, str(Net.players[pid].get("name", "")), JSON.stringify(Net.players[pid].get("loadout", {}))]))
	# Your saved Deathmatch guns go to the server as soon as you are in the lobby (and again whenever they change),
	# with your laser colour.
	Profile.send_loadout()
	Net.send_prefs()
	_refresh()


func _setup_panel() -> void:
	## Rebuilt only when the configuration changes (the host's own controls must not reset under their finger).
	var host := Net.is_room_host()
	var cfg0 := Net.config.duplicate()
	cfg0.erase("auto_start_in")   # the official countdown ticks every second; the controls need not rebuild for it
	var key := JSON.stringify(cfg0) + str(host)
	if key == _cfg_key:
		return
	_cfg_key = key
	for c in _setup_box.get_children():
		c.queue_free()
	if _compact and _setup_box.get_parent():
		# (r16) phones: the host's controls (map, teams) first; everyone else sees their guns first
		_setup_box.get_parent().move_child(_setup_box, 0 if host else 1)
	var host_name := str(Net.players.get(Net.room_host(), {}).get("name", ""))
	_setup_box.add_child(UITheme.section("Match settings", "" if host else ("Only the host%s can change the map and teams." % ((" (" + host_name + ")") if host_name != "" else ""))))
	var cfg := Net.config
	var dm := _dm()
	var mode_name := str(UITheme.MODE_NAMES.get(str(cfg.get("game_mode", "classic")), "Classic"))
	var map_name := str(UITheme.MAP_NAMES.get(str(cfg.get("map", "kalinaw")), str(cfg.get("map", ""))))
	if host:
		if cfg.get("official", false):
			_setup_box.add_child(_kv_row("Mode", mode_name))   # an official server is listed as one mode
		else:
			_setup_box.add_child(_field("Mode", UITheme.segmented([["classic", "Classic"], ["deathmatch", "Deathmatch"]], str(cfg.get("game_mode", "classic")), _set_mode)))
		var maps: Array = Defs.rule("game_modes.%s.maps" % str(cfg.get("game_mode", "classic")), [])
		if maps.size() > 1:
			var opts := []
			for m in maps:
				opts.append([str(m), str(UITheme.MAP_NAMES.get(str(m), str(m)))])
			_setup_box.add_child(_field("Map", UITheme.segmented(opts, str(cfg.get("map", "")), func(v): Net.request_config("map", v))))
		else:
			_setup_box.add_child(_kv_row("Map", map_name))
		if dm:
			_setup_box.add_child(_field("Teams", UITheme.stepper(Net.dm_teams(), 2, Net.DM_MAX_TEAMS, func(v): Net.request_config("teams", v))))
			_setup_box.add_child(_field("Players per team", UITheme.stepper(Net.team_size(), 1, Net.DM_MAX_TEAM_SIZE, func(v): Net.request_config("team_size", v))))
		else:
			_setup_box.add_child(_field("Teams", UITheme.stepper(int(cfg.get("teams", 5)), 2, Net.MAX_TEAMS, func(v): Net.request_config("teams", v))))
			_setup_box.add_child(_field("Squad size", UITheme.segmented([[1, "Solo"], [2, "Duo"], [3, "Trio"], [4, "Squad"]], Net.team_size(), func(v): Net.request_config("team_size", v))))
		_setup_box.add_child(UITheme.toggle("Fill empty slots with bots", bool(cfg.get("bots", true)), func(v): Net.request_config("bots", v)))
		if dm:
			if str(cfg.get("map", "")) == "malasugue_mall":
				_setup_box.add_child(UITheme.toggle("Enable field", bool(cfg.get("dm_field", false)), func(v): Net.request_config("dm_field", v)))
				_setup_box.add_child(UITheme.label("Same countdown; closes up to 50% each round.", 18, UITheme.TEXT_DIM))
			else:
				_setup_box.add_child(_kv_row("Safe zone", "Fast (fixed in Deathmatch)"))
			# (r17) How the round is won: a team score limit, the best score on the clock, or the last team standing.
			var win := str(cfg.get("dm_win", "wipe"))
			_setup_box.add_child(_field("Win by", UITheme.dm_win_picker(win, func(v): Net.request_config("dm_win", v))))
			if win in ["wipe", "score"]:
				_setup_box.add_child(_field("Points to win" if win == "wipe" else "Kills to win", UITheme.segmented([[10, "10"], [20, "20"], [30, "30"], [50, "50"]], int(cfg.get("dm_score", 10)), func(v): Net.request_config("dm_score", v))))
			elif win == "time":
				_setup_box.add_child(_field("Round length", UITheme.segmented([[10, "10 min"], [14, "14 min"], [30, "30 min"]], int(cfg.get("dm_time", 14)), func(v): Net.request_config("dm_time", v))))
		else:
			_setup_box.add_child(_field("Safe zone", UITheme.segmented([[1.0, "Normal"], [1.6, "Fast"], [2.5, "Rapid"]], float(cfg.get("zone_speed", 1.0)), func(v): Net.request_config("zone_speed", v))))
		if _night_only():
			_setup_box.add_child(_kv_row("Night and day", "Always night on this map"))
		else:
			_setup_box.add_child(_field("Night and day (each)", UITheme.segmented([[120, "2 min"], [300, "5 min"], [600, "10 min"]], int(cfg.get("day_len", 300)), func(v): Net.request_config("day_len", v))))
	else:
		var rows := [["Mode", mode_name], ["Map", map_name]]
		if dm:
			rows.append_array([["Teams", str(Net.dm_teams())], ["Players per team", str(Net.team_size())]])
		else:
			rows.append_array([["Teams", str(int(cfg.get("teams", 5)))], ["Squad size", str(Net.team_size())]])
		rows.append_array([["Bots", "Fill empty slots" if cfg.get("bots", true) else "Off"],
				["Safe zone", ("Disabled" if not cfg.get("dm_field", false) else "Enabled · up to 50%") if dm and str(cfg.get("map", "")) == "malasugue_mall" else "Fast (fixed)" if dm else {1.0: "Normal", 1.6: "Fast", 2.5: "Rapid"}.get(float(cfg.get("zone_speed", 1.0)), "Normal")]])
		if dm:
			rows.append(["Win by", win_text()])
		rows.append(["Night and day", "Always night" if _night_only() else "%d min each" % (int(cfg.get("day_len", 300)) / 60)])
		for kv in rows:
			var h := UITheme.hbox(8)
			var k := UITheme.label(kv[0], 19, UITheme.TEXT_DIM)
			k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(k)
			h.add_child(UITheme.label(kv[1], 21, UITheme.TEXT, UITheme.font_semibold))
			_setup_box.add_child(h)
	var addr := UITheme.label("", 16, UITheme.TEXT_DIM)
	addr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if Net.is_server and not Net.dedicated:
		var ips = Array(IP.get_local_addresses()).filter(func(a): return a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"))
		addr.text = "Players on your network see this game under Play. Address: %s (port %d)." % [", ".join(ips.slice(0, 2)) if not ips.is_empty() else "this PC", Net.port]
	_setup_box.add_child(addr)


func _kv_row(k: String, v: String) -> Control:
	var h := UITheme.hbox(8)
	var kl := UITheme.label(k, 19, UITheme.TEXT_DIM)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(kl)
	h.add_child(UITheme.label(v, 21, UITheme.TEXT, UITheme.font_semibold))
	return h


func _dm() -> bool:
	return str(Net.config.get("game_mode", "classic")) == "deathmatch"


func _night_only() -> bool:
	return str(Net.config.get("map", "")) in Defs.rule("day_cycle.night_only_maps", [])


static func win_text() -> String:
	## (r17) The Deathmatch win rule in words: "First team to 30", "Best score after 14 min", "Last team standing".
	match str(Net.config.get("dm_win", "wipe")):
		"wipe":
			return "Team Wipe: first to %d points" % int(Net.config.get("dm_score", 10))
		"score":
			return "First team to %d kills" % int(Net.config.get("dm_score", 10))
		"time":
			return "Best score after %d min" % int(Net.config.get("dm_time", 14))
	return "Last team standing"


func _set_mode(m: String) -> void:
	## Host: switch the lobby between Classic (5 squads of 4 on Sitio Kalinaw) and Deathmatch (3 teams of 7 on
	## Lawless Sub or Malasugue Mall); Net.set_config resets the map and teams to the mode's defaults. The choice is
	## also remembered for the menu.
	if not Net.is_room_host() or m == str(Net.config.get("game_mode", "classic")):
		return
	Profile.set_game_mode(m)
	Net.request_config("game_mode", m)


func _loadout_panel() -> void:
	## Deathmatch: your two guns (as the server has them once it answered, else as saved here) and the kit.
	var lo: Dictionary = Net.players.get(Net.local_pid, {}).get("loadout", {})
	var confirmed := not lo.is_empty()
	if not confirmed:
		lo = Profile.get_loadout()
	var key := "%s|%s|%s" % [_dm(), JSON.stringify(lo), confirmed]
	if key == _loadout_key:
		return
	_loadout_key = key
	for c in _loadout_box.get_children():
		c.queue_free()
	_loadout_box.visible = _dm()
	if not _dm():
		return
	_loadout_box.add_child(UITheme.section("Your loadout"))
	var guns := UITheme.hbox(8)
	for kind in ["primary", "secondary"]:
		guns.add_child(GameSetup.gun_tile(str(lo.get(kind, "")), "Primary" if kind == "primary" else "Secondary", Vector2(150, 66)))
	_loadout_box.add_child(guns)
	var kit := []
	for g in Defs.rules.get("deathmatch", {}).get("gear", []):
		kit.append(Defs.item_name(str(g)))
	var kl := UITheme.label("Everyone also starts with: %s." % ", ".join(kit), 16, UITheme.TEXT_DIM)
	kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loadout_box.add_child(kl)
	var b := UITheme.icon_button("gun", "Change guns", open_game_setup)
	_loadout_box.add_child(b)


func open_game_setup() -> Control:
	if _game_setup and is_instance_valid(_game_setup):
		return _game_setup
	_game_setup = GameSetup.new()
	_game_setup.closed.connect(func(): _loadout_key = ""; _refresh())
	add_child(_game_setup)
	return _game_setup


func open_results_setup(action: String) -> void:
	if action == "loadout" and _dm():
		open_game_setup()
	elif action == "mode":
		_tip.text = "Choose the game mode in Match settings." if Net.is_room_host() else "The host chooses the game mode in Match settings."
	elif action == "team":
		_tip.text = "Select a team card to change your team."


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
	if not _map_offered and Net.is_room_host() and _dm() and Net.config.get("official", false):
		_map_offered = true
		if Profile.dm_map in Defs.rule("game_modes.deathmatch.maps", []) and Profile.dm_map != str(Net.config.get("map", "")):
			Net.request_config("map", Profile.dm_map)
		for k in Profile.MATCH_OPT_KEYS:   # (r17) and the win rule / night and day length chosen on Home
			if Profile.match_opts.has(k) and str(Profile.match_opts[k]) != str(Net.config.get(k, "")):
				Net.request_config(k, Profile.match_opts[k])
	_setup_panel()
	_loadout_panel()
	var dm := _dm()
	_setup_btn.visible = dm
	_tip.text = "Tap a team to join it. Bots take the seats nobody takes."
	if dm:
		_tip.text += " " + win_text() + ". "
		match str(Net.config.get("dm_win", "wipe")):
			"wipe":
				_tip.text += "Last team standing earns 1 point; everyone returns next round."
			"score", "time":
				_tip.text += "The fallen respawn."

	var mine: Dictionary = Net.players.get(Net.local_pid, {}).get("loadout", {})
	if not mine.is_empty() and JSON.stringify(mine) != str(get_meta("lo_seen", "")):
		set_meta("lo_seen", JSON.stringify(mine))
		print("[ui] lobby shows my loadout (pid %d): %s" % [Net.local_pid, JSON.stringify(mine)])
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
	var host_pid := Net.room_host()
	var room_host := Net.is_room_host()
	_ready_btn.visible = not room_host
	_start_btn.visible = room_host
	var waiting := Net.not_ready()
	_start_btn.disabled = not waiting.is_empty()
	_start_btn.text = "START MATCH" if waiting.is_empty() else "WAITING (%d)" % waiting.size()
	var humans := Net.humans()
	var ready := 0
	for pid in Net.players:
		if not Net.players[pid].bot and (Net.players[pid].ready or pid == host_pid):
			ready += 1
	var bots := maxi(Net.slot_count() - humans, 0) if Net.config.get("bots", true) else 0
	var wait := "Waiting for %s to start." % str(Net.players.get(host_pid, {}).get("name", "the host"))
	if room_host:
		wait = "You are the host: press Start when you are set." if waiting.is_empty() else "Waiting for %s to press Ready." % ", ".join(waiting)
	if Net.config.get("official", false):
		# Official servers: the first slot hosts; an idle host does not hold the server (src/match/official.gd).
		var left := int(Net.config.get("auto_start_in", -1))
		if left >= 0:
			wait += " Official server: starts by itself in %d s." % left
	if dm:
		var tn := []
		for t in Net.dm_teams():
			tn.append(UITheme.dm_team_name(t))
		_info.text = "Deathmatch on %s · %s, %d a side · %d human%s (%d ready) and %d bot%s · %s" % [
			UITheme.MAP_NAMES.get(str(Net.config.get("map", "lawless_sub")), ""), " against ".join(tn), size,
			humans, "" if humans == 1 else "s", ready, bots, "" if bots == 1 else "s", wait]
	else:
		_info.text = "%d human%s (%d ready) and %d bot%s · %d teams of %d · %s" % [humans, "" if humans == 1 else "s", ready, bots, "" if bots == 1 else "s",
			n_teams, size, wait]
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _team_card(t: int, members: Array, size: int, unassigned: Array, free: Array) -> Control:
	var col: Color = UITheme.TEAM_COLORS[t % UITheme.TEAM_COLORS.size()]
	var mine: bool = int(Net.players.get(Net.local_pid, {}).get("team", -2)) == t
	var dm := _dm()
	var row_h := 40 if dm else 44
	var card := Button.new()
	card.theme_type_variation = "CardButton"
	card.toggle_mode = true
	card.button_pressed = mine
	card.custom_minimum_size = Vector2(430 if dm else 300, 74 + size * (row_h + 6) if dm else 74 + size * 52)
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
	var tl := UITheme.label(UITheme.team_name(t), 26, col.lightened(0.1), UITheme.font_condensed)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(UITheme.label("%d / %d" % [members.size(), size], 17, UITheme.TEXT_DIM))
	v.add_child(head)
	for pid in members:
		var sr := _slot_row(pid)
		sr.custom_minimum_size.y = row_h
		v.add_child(sr)
	var bots_on: bool = Net.config.get("bots", true)
	for i in size - members.size():
		var r := UITheme.hbox(8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.custom_minimum_size = Vector2(0, row_h)
		var ic := TextureRect.new()
		ic.texture = Icons.texture("bot" if bots_on else "plus", 22, UITheme.TEXT_DIM * Color(1, 1, 1, 0.7))
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(ic)
		r.add_child(UITheme.label(("Bot (fills at the start)" if dm else "Bot") if bots_on else "Open seat", 19, UITheme.TEXT_DIM * Color(1, 1, 1, 0.75)))
		if not mine and i == 0:
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.add_child(spacer)
			r.add_child(UITheme.label("Tap to switch" if dm and Net.players.get(Net.local_pid, {}).get("team", -1) >= 0 else "Tap to join", 16, UITheme.ACCENT))
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
		var lo: Dictionary = p.get("loadout", {})
		if _dm() and not lo.is_empty():
			var ll := UITheme.label("%s + %s" % [Defs.item_name(str(lo.get("primary", ""))), Defs.item_name(str(lo.get("secondary", "")))], 15, UITheme.TEXT_DIM)
			ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
			r.add_child(ll)
		r.add_child(UITheme.pill("Lv %d" % int(p.get("level", 1)), UITheme.ACCENT, 13))
		if pid == Net.room_host():
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
