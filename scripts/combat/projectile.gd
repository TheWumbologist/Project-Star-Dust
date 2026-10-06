class_name Projectile
extends Area3D
## A fast shot. Each tick it sweeps its collision shape along its path and
## damages the first body in the way that has `take_damage(amount, source)`;
## anything else (asteroids, walls) just stops it. Sweeping rather than
## waiting for overlap signals means fast shots can't skip through thin
## targets, and it hits static rocks too. What it can hit is set by its
## collision mask (player shots vs enemy shots).

@export var lifetime: float = 1.6

var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
## Who fired it; never hits its own shooter.
var shooter: Node = null
## Stop after travelling this far (0 = only lifetime limits it).
var max_distance: float = 0.0

var _travelled: float = 0.0
var _done: bool = false
var _query: PhysicsShapeQueryParameters3D


func _ready() -> void:
	monitoring = false
	var shape_node := get_node_or_null("Collision") as CollisionShape3D
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = shape_node.shape if shape_node != null else SphereShape3D.new()
	_query.collision_mask = collision_mask
	_query.collide_with_areas = false
	if shooter is CollisionObject3D:
		_query.exclude = [shooter.get_rid()]


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := velocity * delta
	if max_distance > 0.0 and _travelled + step.length() > max_distance:
		step = step.normalized() * maxf(max_distance - _travelled, 0.0)

	var space := get_world_3d().direct_space_state
	_query.transform = Transform3D(Basis(), global_position)
	_query.motion = step
	var fraction := space.cast_motion(_query)
	if fraction[1] < 1.0:
		global_position += step * fraction[1]
		_query.transform = Transform3D(Basis(), global_position)
		_query.motion = Vector3.ZERO
		var info := space.get_rest_info(_query)
		_finish(instance_from_id(info["collider_id"]) as Node if info.has("collider_id") else null)
		return

	global_position += step
	_travelled += step.length()
	lifetime -= delta
	if lifetime <= 0.0 or (max_distance > 0.0 and _travelled >= max_distance - 0.01):
		_finish(null)


## Ends the shot. `hit` is the body it struck, or null if it ran out.
func _finish(hit: Node) -> void:
	_done = true
	# The shooter may have been destroyed while the shot was in flight.
	if not is_instance_valid(shooter):
		shooter = null
	if hit != null and hit != shooter and hit.has_method("take_damage"):
		hit.take_damage(damage, shooter)
	queue_free()
