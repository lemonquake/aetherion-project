extends Control
## In-match menu. The match keeps running (it is multiplayer): Resume, Settings, Leave match.

signal closed

const SettingsScreen := preload("res://src/ui/settings_ui.gd")


func _ready() -> void:
	theme = UITheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var v := UITheme.vbox(12)
	v.custom_minimum_size = Vector2(360, 0)
	c.add_child(v)
	v.add_child(UITheme.label("Aetherion Project by Aljay Leodones", 20, UITheme.TEXT_DIM))
	v.add_child(UITheme.label("Paused", 44, UITheme.TEXT, UITheme.font_condensed))
	v.add_child(UITheme.label("The match continues while this menu is open.", 17, UITheme.TEXT_DIM))
	v.add_child(UITheme.button("Resume", _resume, 360))
	v.add_child(UITheme.button("Settings", func(): add_child(SettingsScreen.new()), 360))
	v.add_child(UITheme.button("Leave match", func(): Game.leave_to_menu(), 360))


func _resume() -> void:
	closed.emit()
	queue_free()
