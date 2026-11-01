"""r24: the workbench opens with K in a match (a Gear button on phones) and from Game Setup."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from p24_util import patch

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game')

patch(os.path.join(R, 'src', 'core', 'settings.gd'), [
    ('''"scoreboard": ["QuoteLeft", ""],''', '''"scoreboard": ["QuoteLeft", ""], "workbench": ["K", ""],'''),
])
patch(os.path.join(R, 'src', 'ui', 'settings_ui.gd'), [
    ('''"scoreboard": "Scoreboard (hold)", ''', '''"scoreboard": "Scoreboard (hold)", "workbench": "Weapon workbench (attachments)", '''),
])
patch(os.path.join(R, 'src', 'ui', 'touch_controls.gd'), [
    ('''	{"name": "fire_mode", "action": "fire_mode", "label": "Auto", "pos": Vector2(-540, 245), "r": 58.0, "mode": "tap"},
''', '''	{"name": "fire_mode", "action": "fire_mode", "label": "Auto", "pos": Vector2(-540, 245), "r": 58.0, "mode": "tap"},
	{"name": "workbench", "action": "workbench", "label": "Gear", "pos": Vector2(-680, 245), "r": 54.0, "mode": "tap"},
'''),
])
patch(os.path.join(R, 'src', 'player', 'player_controller.gd'), [
    ('''const PauseMenu := preload("res://src/ui/pause_menu.gd")
''', '''const PauseMenu := preload("res://src/ui/pause_menu.gd")
const Workbench := preload("res://src/ui/workbench_ui.gd")
'''),
    ('''var _pause_ui: Control = null
''', '''var _pause_ui: Control = null
var workbench: Control = null    # (r24) the attachment workbench while it is open (K)
'''),
    ('''	if _pause_ui and is_instance_valid(_pause_ui):
		if _pause_ui.get_parent():
			_pause_ui.get_parent().remove_child(_pause_ui)
		_pause_ui.queue_free()
	_pause_ui = null
	paused = false''', '''	for ui in [_pause_ui, workbench]:
		if ui and is_instance_valid(ui):
			if ui.get_parent():
				ui.get_parent().remove_child(ui)
			ui.queue_free()
	_pause_ui = null
	workbench = null
	paused = false'''),
    ('''	if event.is_action_pressed("text_chat") and world.hud:
		world.hud.open_text_chat()
''', '''	if event.is_action_pressed("text_chat") and world.hud:
		world.hud.open_text_chat()
	if event.is_action_pressed("workbench") and ch != null and not tab_held:
		open_workbench()


func open_workbench() -> void:
	## (r24) The attachment workbench over the match (which goes on): the player stands still while it is open.
	if workbench and is_instance_valid(workbench):
		return
	var start = slot if slot in [1, 2, 3] and ch.wpn.slots[slot] != null else null
	workbench = Workbench.new(Workbench.MatchSource.new(world), start)
	Game.ui.add_child(workbench)
	paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	workbench.closed.connect(func():
		workbench = null
		paused = false
		if not results:
			Input.mouse_mode = Settings.play_mouse_mode())
'''),
])
