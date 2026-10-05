@tool
class_name Asteroid
extends StaticBody3D
## Grey-box asteroid obstacle.
## Changing radius in the editor resizes the mesh and collider. It resizes
## their resources (local to each instance) rather than scaling child nodes,
## so the editor doesn't save scale overrides into the scene.

@export var radius: float = 3.0:
	set(value):
		radius = maxf(value, 0.5)
		_apply_radius()


func _ready() -> void:
	_apply_radius()


func _apply_radius() -> void:
	if not is_inside_tree():
		return
	var mesh_node := get_node_or_null("Mesh") as MeshInstance3D
	if mesh_node != null and mesh_node.mesh is SphereMesh:
		mesh_node.mesh.radius = radius
		mesh_node.mesh.height = radius * 2.0
	var shape_node := get_node_or_null("Collision") as CollisionShape3D
	if shape_node != null and shape_node.shape is SphereShape3D:
		shape_node.shape.radius = radius
