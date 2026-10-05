extends Node3D
## Flight-feel test arena (milestone 1). Grey-box only: fly, boost, drift,
## shoot dummies. R / Start restarts.


func _ready() -> void:
	# The ship's aim reticle replaces the system cursor.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
