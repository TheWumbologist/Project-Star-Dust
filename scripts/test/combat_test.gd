extends Node3D
## Combat and mining test arena (milestone 2). A debris field: shoot ore out
## of asteroids, fight waves of scavenger drones and pirate cutters, and
## fill the cargo hold. Waves are a testing aid; real rifts place their
## enemies when generated. R restarts; Esc opens the pause menu.


func _ready() -> void:
	# The ship's aim reticle replaces the system cursor.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		Scenes.restart(get_tree())
