@tool
class_name WindStream
extends Area3D
## Stellar wind stream: ships inside are pushed along the stream's local -Z
## and may exceed their normal top speed (the "solar sail" move).
## Rotate the node to aim the stream; set length and width here rather than
## scaling, since physics shapes dislike non-uniform scale.

## Acceleration applied along the stream, in m/s^2.
@export var push_strength: float = 48.0
## Extra top speed allowed while inside the stream.
@export var speed_cap_bonus: float = 24.0
## Instant shove along the stream (m/s) when a ship flies in, so the
## stream grabs you straight away instead of building up.
@export var entry_kick: float = 9.0
@export var length: float = 40.0:
	set(value):
		length = maxf(value, 1.0)
		_apply_size()
@export var width: float = 8.0:
	set(value):
		width = maxf(value, 1.0)
		_apply_size()

var _ships: Array[ShipController] = []


func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var dir := -global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	for ship in _ships:
		if is_instance_valid(ship):
			ship.apply_wind(dir * push_strength, speed_cap_bonus)


func _apply_size() -> void:
	if not is_inside_tree():
		return
	# The shape and mesh are local_to_scene in wind_stream.tscn, so each
	# stream instance owns its copy and can be sized independently.
	var shape_node := get_node_or_null("Collision") as CollisionShape3D
	if shape_node != null and shape_node.shape is BoxShape3D:
		shape_node.shape.size = Vector3(width, 4.0, length)
	var mesh_node := get_node_or_null("Mesh") as MeshInstance3D
	if mesh_node != null and mesh_node.mesh is PlaneMesh:
		mesh_node.mesh.size = Vector2(width, length)


func _on_body_entered(body: Node) -> void:
	if body is ShipController and body not in _ships:
		_ships.append(body)
		var dir := -global_transform.basis.z
		dir.y = 0.0
		body.apply_impulse(dir.normalized() * entry_kick)


func _on_body_exited(body: Node) -> void:
	_ships.erase(body)
