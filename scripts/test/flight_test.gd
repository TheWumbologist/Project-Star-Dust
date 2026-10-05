extends Node3D
## Flight-feel test arena (milestone 1). Grey-box only: fly, boost, drift,
## grapple asteroids, shoot dummies. R / Start restarts.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
