"""r24: the results screen shows the full scoreboard (per team, K/D/A, damage, headshots, grenades)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p24_util import patch

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game')

patch(os.path.join(R, 'src', 'core', 'settings.gd'), [
    ('''"scoreboard": ["QuoteLeft", "joy:4"],''', '''"scoreboard": ["QuoteLeft", ""],'''),
])

patch(os.path.join(R, 'src', 'ui', 'results_ui.gd'), [
    ('''	var table := UITheme.vbox(6)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(table)
	var widths := [340, 200, 90, 110, 130]
	_row(table, ["Player", "Team", "Kills", "Damage" if dm else "Downs", "Time alive"], widths, UITheme.TEXT_DIM)
	for r in summary.get("rows", []):
		var team := int(r.get("team", -1))
		var team_text := str(names[team]) if team >= 0 and team < names.size() else "Team %d" % (team + 1)
		_row(table, [str(r.name) + (" (bot)" if r.get("bot", false) else ""), team_text, str(r.get("kills", 0)),
			str(int(r.get("damage", 0))) if dm else str(r.get("downs", 0)), "%d:%02d" % [int(r.get("time", 0)) / 60, int(r.get("time", 0)) % 60]],
			widths, UITheme.ACCENT if r.get("winner", false) else UITheme.TEXT)
''', '''	# (r24) The same scoreboard as the one held on ~ during the match: every team, every player's numbers.
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
'''),
])
