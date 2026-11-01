extends PanelContainer
## r24 scoreboard: one table per team (its colour, round points or kills, how many are still standing), a row per
## player with kills / deaths / assists, damage dealt and received, headshot kills and deaths, grenade kills and
## deaths. Held on ~ during a match (hud.gd), and shown on the results screen when the match is won.

const COLS := [["Player", 290], ["K", 46], ["D", 46], ["A", 46], ["Damage dealt", 128], ["Damage received", 150],
	["Headshot kills", 132], ["Headshot deaths", 140], ["Grenade kills", 124], ["Grenade deaths", 132]]
const KEYS := ["kills", "deaths", "assists", "damage", "taken", "hs_kills", "hs_deaths", "nade_kills", "nade_deaths"]

var _body: VBoxContainer
var _title: Label
var _sig := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UITheme.box(Color(0.025, 0.03, 0.038, 0.93), Color(1, 1, 1, 0.1), 8, 22, 16))
	var v := UITheme.vbox(10)
	add_child(v)
	_title = UITheme.label("Scoreboard", 30, UITheme.TEXT, UITheme.font_condensed)
	v.add_child(_title)
	_body = UITheme.vbox(3)
	v.add_child(_body)


func set_title(t: String) -> void:
	_title.text = t


func show_rows(rows: Array, info: Dictionary, my_pid: int = -1) -> void:
	## rows: match_server.board() rows (or the summary's). info: team_names, score, alive (match state or summary).
	var sig := JSON.stringify([rows, info.get("score", {}), info.get("alive", {})])
	if sig == _sig:
		return   # nothing changed: keep the labels (re-laying them out every half second for nothing)
	_sig = sig
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var names: Array = info.get("team_names", [])
	var teams := {}
	for r in rows:
		var t := int(r.get("team", -1))
		if not teams.has(t):
			teams[t] = []
		teams[t].append(r)
	var order := teams.keys()
	order.sort()
	var score: Dictionary = info.get("score", {})
	var alive: Dictionary = info.get("alive", {})
	for t in order:
		var list: Array = teams[t]
		list.sort_custom(func(a, b): return int(a.kills) > int(b.kills) or (int(a.kills) == int(b.kills) and int(a.damage) > int(b.damage)))
		var col: Color = UITheme.TEAM_COLORS[maxi(t, 0) % UITheme.TEAM_COLORS.size()]
		var head := UITheme.hbox(18)
		if _body.get_child_count() > 0:
			_body.add_child(UITheme.spacer(8))
		var tname := str(names[t]) if t >= 0 and t < names.size() else UITheme.team_name(t)
		head.add_child(UITheme.label(tname, 24, col, UITheme.font_condensed))
		var pts = score.get(t, score.get(str(t), null))
		if pts != null:
			head.add_child(UITheme.label("Score %d" % int(pts), 20, UITheme.TEXT))
		var standing := 0
		for r in list:
			standing += 1 if r.get("alive", false) else 0
		var al = alive.get(t, alive.get(str(t), standing))
		if not info.get("final", false):
			head.add_child(UITheme.label("%d of %d alive" % [int(al), list.size()], 20, UITheme.GOOD if int(al) > 0 else UITheme.DANGER))
		_body.add_child(head)
		_body.add_child(_row(COLS.map(func(c): return c[0]), UITheme.TEXT_DIM, 15, Color(0, 0, 0, 0)))
		for r in list:
			var vals := [str(r.name) + (" (bot)" if r.get("bot", false) else "")]
			for k in KEYS:
				vals.append(str(int(r.get(k, 0))))
			var mine := int(r.get("pid", -2)) == my_pid
			var fg := UITheme.TEXT if r.get("alive", true) or info.get("final", false) else UITheme.TEXT_DIM
			_body.add_child(_row(vals, UITheme.ACCENT if mine else fg, 17, Color(col, 0.16) if mine else Color(1, 1, 1, 0.03)))


func _row(vals: Array, fg: Color, size: int, bg: Color) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UITheme.box(bg, Color(0, 0, 0, 0), 4, 10, 1, 0))
	var h := UITheme.hbox(8)
	p.add_child(h)
	for i in vals.size():
		var l := UITheme.label(str(vals[i]), size, fg, UITheme.font_semibold if i == 0 else null)
		l.custom_minimum_size.x = COLS[i][1]
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if i > 0:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(l)
	return p
