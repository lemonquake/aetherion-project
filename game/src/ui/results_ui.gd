extends Control
## Kept under Game.UI so players can read the results even when the room returns to its lobby.

var summary: Dictionary


func _init(data: Dictionary = {}) -> void:
	summary = data


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.022, 0.028, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var col := UITheme.vbox(12)
	margin.add_child(col)
	col.add_child(UITheme.label("Match Results", 40, UITheme.TEXT, UITheme.font_condensed))
	var dm := str(summary.get("game_mode", "classic")) == "deathmatch"
	var winner := int(summary.get("winner_team", -1))
	var names: Array = summary.get("team_names", [])
	var winner_text := "Draw" if winner < 0 else "%s wins the match" % str(summary.get("winner_name", "Team %d" % (winner + 1)))
	if not dm:
		winner_text = "Last team standing: %s" % ", ".join(summary.get("winners", [])) if winner >= 0 else "Nobody survived the night."
	var title := UITheme.label(winner_text, 30, UITheme.ACCENT, UITheme.font_condensed)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	if dm and not (summary.get("score", {}) as Dictionary).is_empty():
		var parts := []
		for t in summary.score:
			parts.append("%s: %d" % [str(names[int(t)]) if int(t) < names.size() else "Team %d" % (int(t) + 1), int(summary.score[t])])
		var scores := UITheme.label("  ·  ".join(parts), 24, UITheme.TEXT)
		scores.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(scores)
	col.add_child(UITheme.label("Match length %d:%02d" % [int(summary.get("duration", 0)) / 60, int(summary.get("duration", 0)) % 60], 20, UITheme.TEXT_DIM))
	var xp: Dictionary = summary.get("me_xp", {})
	if not xp.is_empty():
		var xp_text := "+%d XP" % int(xp.get("xp", 0))
		if int(xp.get("level_after", 0)) > int(xp.get("level_before", 0)):
			xp_text += "  ·  Level %d reached" % int(xp.level_after)
		col.add_child(UITheme.label(xp_text, 24, UITheme.ACCENT))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(sc)
	# (r24) The same scoreboard as the one held on ~ during the match: every team, every player's numbers.
	var board := preload("res://src/ui/scoreboard.gd").new()
	board.set_title("Final scoreboard")
	board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sc.add_child(board)
	var tn: Array = names.duplicate()
	if tn.is_empty():
		for r in summary.get("rows", []):
			while tn.size() <= int(r.get("team", 0)):
				tn.append(UITheme.team_name(tn.size()))
	board.show_rows(summary.get("rows", []), {"team_names": tn, "score": summary.get("score", {}), "final": true}, Net.local_pid)
	col.add_child(UITheme.label("You can stay here to review the stats.", 20, UITheme.TEXT_DIM))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 10)
	col.add_child(actions)
	for entry in [["BACK TO MAIN MENU", "menu"], ["RESTART MATCH", "restart"], ["CHANGE GAME MODE", "mode"], ["CHANGE LOADOUT", "loadout"], ["CHANGE TEAM", "team"]]:
		var action := str(entry[1])
		var btn := UITheme.button(str(entry[0]), func(): Game.results_action(action), 240)
		btn.add_theme_font_size_override("font_size", 20)
		btn.custom_minimum_size.y = 56
		if action == "restart" and not Net.is_room_host():
			btn.disabled = true
			btn.tooltip_text = "The host restarts the match."
		if action == "loadout" and not dm:
			btn.disabled = true
			btn.tooltip_text = "Loadouts are available in Deathmatch."
		actions.add_child(btn)


func _row(table: Container, values: Array, widths: Array, color: Color) -> void:
	var row := UITheme.hbox(12)
	for i in values.size():
		var label := UITheme.label(str(values[i]), 20, color)
		label.custom_minimum_size.x = widths[i]
		row.add_child(label)
	table.add_child(row)
