class_name RiftCompass
extends Node3D
## The Rift Compass: a glowing needle that orbits the player's ship and
## points to the nearest extraction beacon.

@export var ship: ShipController
## Distance from the ship's centre to the needle.
@export var orbit_radius: float = 4.5

var _run: RiftRun = null


func _ready() -> void:
	top_level = true


func _process(delta: float) -> void:
	if _run == null:
		_run = get_tree().get_first_node_in_group("rift_run") as RiftRun
	visible = ship != null and ship.is_alive() and _run != null and not _run.ended
	if not visible:
		return
	var exit := _run.nearest_extraction(ship.global_position)
	if exit == null:
		visible = false
		return
	var to_exit := exit.global_position - ship.global_position
	to_exit.y = 0.0
	if to_exit.length() < orbit_radius * 2.0:
		visible = false
		return
	var dir := to_exit.normalized()
	global_position = ship.global_position + dir * orbit_radius + Vector3.UP * 0.6
	var yaw := atan2(-dir.x, -dir.z)
	rotation = Vector3(0.0, lerp_angle(rotation.y, yaw, 1.0 - exp(-12.0 * delta)), 0.0)
