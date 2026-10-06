class_name ExtractionPoint
extends Area3D
## Extraction beacon. Hold position inside the ring for `channel_time`
## seconds to escape the rift with your cargo. Leaving the ring drains the
## progress, so a fight at the beacon is a real choice.

signal extracted(ship: ShipController)

@export var channel_time: float = 4.0
@export var ring: Node3D
@export var beam: MeshInstance3D

## 0..1 extraction progress for whoever is in the ring.
var progress: float = 0.0
var active: bool = true

var _beam_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("extraction_points")
	if beam != null:
		_beam_mat = beam.get_active_material(0).duplicate() as StandardMaterial3D
		beam.material_override = _beam_mat


func _physics_process(delta: float) -> void:
	if not active:
		return
	var pilot := _player_inside()
	if pilot != null:
		progress = minf(progress + delta / channel_time, 1.0)
		if progress >= 1.0:
			active = false
			extracted.emit(pilot)
	else:
		progress = maxf(progress - delta * 2.0 / channel_time, 0.0)


func _process(delta: float) -> void:
	if ring != null:
		ring.rotation.y += delta * (0.6 + progress * 6.0)
	if beam != null:
		beam.scale = Vector3(1.0 + progress * 1.5, 1.0, 1.0 + progress * 1.5)
	if _beam_mat != null:
		_beam_mat.albedo_color.a = 0.25 + progress * 0.6


func _player_inside() -> ShipController:
	for body in get_overlapping_bodies():
		var ship := body as ShipController
		if ship != null and ship.team == 0 and ship.is_alive():
			return ship
	return null
