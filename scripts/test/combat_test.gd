extends Node3D
## Combat and mining test arena (milestone 2). A debris field: shoot ore out
## of asteroids, fight waves of scavenger drones and pirate cutters, and
## fill the cargo hold. Dying loses your cargo. R / Start restarts.

## Seconds before a destroyed player ship comes back.
@export var respawn_delay: float = 3.0
@export var spawn_point: Marker3D


func _ready() -> void:
	# The ship's aim reticle replaces the system cursor.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	for node in get_tree().get_nodes_in_group("ships"):
		var ship := node as ShipController
		if ship != null and ship.team == 0:
			ship.destroyed.connect(_on_player_destroyed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _on_player_destroyed(ship: ShipController) -> void:
	# Death costs the cargo you were carrying (the extract-or-lose-it rule).
	if ship.cargo != null:
		ship.cargo.clear()
	await get_tree().create_timer(respawn_delay, false, true).timeout
	if is_instance_valid(ship):
		ship.respawn(spawn_point.global_position if spawn_point != null else Vector3.ZERO)
