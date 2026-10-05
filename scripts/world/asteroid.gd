@tool
class_name Asteroid
extends StaticBody3D
## Grey-box asteroid: an obstacle and a grapple anchor.
## Changing anchor_radius in the editor resizes the mesh and collider.

@export var anchor_radius: float = 3.0:
	set(value):
		anchor_radius = maxf(value, 0.5)
		_apply_radius()
@export var is_grapple_anchor: bool = true


func _ready() -> void:
	_apply_radius()
	if is_grapple_anchor and not Engine.is_editor_hint():
		add_to_group("grapple_anchor")


func _apply_radius() -> void:
	if not is_inside_tree():
		return
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3.ONE * anchor_radius
	var shape := get_node_or_null("Collision") as CollisionShape3D
	if shape != null:
		shape.scale = Vector3.ONE * anchor_radius
