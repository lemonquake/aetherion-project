"""r24 HUD: the ~ scoreboard, how many are standing on each Deathmatch team (always), the round-win banner with the
countdown to the next round, and the shorter round break."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p24_util import patch

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game')

patch(os.path.join(R, 'src', 'core', 'settings.gd'), [
    ('''	"smartab_prev": ["Q", "joy:11"], "smartab_next": ["E", "joy:10"],
''', '''	"smartab_prev": ["Q", "joy:11"], "smartab_next": ["E", "joy:10"], "scoreboard": ["QuoteLeft", "joy:4"],
'''),
])

patch(os.path.join(R, 'src', 'ui', 'settings_ui.gd'), [
    ('''"text_chat": "Team text", ''', '''"text_chat": "Team text", "scoreboard": "Scoreboard (hold)", '''),
])

patch(os.path.join(R, 'data', 'rules.json'), [
    ('''    "round_break_s": 4.0
''', '''    "round_break_s": 3.0, "_round_break_s": "r24: the winner is announced, then the next round starts 3 s later (with a countdown)."
'''),
])

patch(os.path.join(R, 'src', 'ui', 'hud.gd'), [
    # Team bar: the number of players standing under every team's name.
    ('''		var nm := UITheme.label(base + (" (you)" if t == _my_team() else ""), 24, col, UITheme.font_condensed)
		nm.set_meta("base", base)
		nm.clip_text = false
''', '''		var nm := UITheme.label(base + (" (you)" if t == _my_team() else ""), 24, col, UITheme.font_condensed)
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
'''),
    ('''		if t == 0:
			row.add_child(nm)
			row.add_child(cnt)
		else:
			row.add_child(cnt)
			row.add_child(nm)
		_team_labels.append([nm, cnt])
''', '''		if t == 0:
			row.add_child(name_col)
			row.add_child(cnt)
		else:
			row.add_child(cnt)
			row.add_child(name_col)
		_team_labels.append([nm, cnt, alive_l])
'''),
    ('''		var nm: Label = _team_labels[t][0]
		var cnt: Label = _team_labels[t][1]
		cnt.text = str(n)
''', '''		var nm: Label = _team_labels[t][0]
		var cnt: Label = _team_labels[t][1]
		cnt.text = str(n)
		var standing := int(alive.get(t, alive.get(str(t), 0)))
		var al: Label = _team_labels[t][2]
		var at := ("%d alive" % standing) if standing > 0 else "Out"
		if al.text != at:
			al.text = at
			al.modulate = Color(1, 1, 1, 1.0) if standing > 0 else Color(1, 0.55, 0.5, 0.9)
'''),
    # The round winner, big in the middle of the screen, and the countdown to the next round.
    ('''				s = ("%s +1 point" % str(names[winner]) if winner >= 0 and winner < names.size() else "Round draw") + " · Next round in %d" % left
''', '''				s = ("%s +1 point" % str(names[winner]) if winner >= 0 and winner < names.size() else "Round draw") + " · Next round in %d" % left
				_round_banner_show(winner, names, left)
			elif _round_banner:
				_round_banner.visible = false
'''),
    ('''func _field_overlay(dt: float) -> void:
''', '''var _round_banner: Control = null
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
	var want := Input.is_action_pressed("scoreboard") and not tab_held and not map_held and chat_edit == null \\
		and (world.controller == null or not world.controller.paused)
	if not want:
		if scoreboard:
			scoreboard.visible = false
		return
	if scoreboard == null:
		scoreboard = preload("res://src/ui/scoreboard.gd").new()
		scoreboard.set_anchors_preset(Control.PRESET_CENTER_TOP)
		root.add_child(scoreboard)
		scoreboard.resized.connect(func(): scoreboard.position = Vector2(-scoreboard.size.x * 0.5, 110))
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
	scoreboard.position = Vector2(-scoreboard.size.x * 0.5, 110)


func _field_overlay(dt: float) -> void:
'''),
    ('''	_treat_ui(dt)
	_round_ui()
''', '''	_treat_ui(dt)
	_round_ui()
	_scoreboard_ui(dt)
'''),
])
