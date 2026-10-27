extends Node
## Entry scene. Waits one frame so every autoload is ready, then hands over to Game.


func _ready() -> void:
	await get_tree().process_frame
	Game.boot()
