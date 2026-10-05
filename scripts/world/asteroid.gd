@tool
class_name Asteroid
extends StaticBody3D
## Grey-box asteroid obstacle.
## Changing radius in the editor resizes the mesh and collider.

@export var radius: float = 3.0:
	set(value):
		radius = maxf(value, 0.5)
		_apply_radius()


func _ready() -> void:
	_apply_radius()


func _apply_radius() -> void:
	if not is_inside_tree():
		return
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.scale = Vector3.ONE * radius
	var shape := get_node_or_null("Collision") as CollisionShape3D
	if shape != null:
		shape.scale = Vector3.ONE * radius
