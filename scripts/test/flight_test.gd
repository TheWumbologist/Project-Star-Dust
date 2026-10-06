extends Node3D
## Flight-feel test arena (milestone 1). Grey-box only: fly, boost, drift,
## shoot dummies. R restarts; Esc opens the pause menu.


func _ready() -> void:
	Sfx.music(&"rift")
	# The ship's aim reticle replaces the system cursor.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		Scenes.restart(get_tree())
