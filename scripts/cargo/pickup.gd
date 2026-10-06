class_name Pickup
extends Area3D
## Loose cargo floating in space. Drifts to a stop, gets pulled toward ships
## that have room for it, and goes into the first hold it touches.

## Emitted on the ship when collected, so HUDs can show "+1 Ore".
signal collected(ship: ShipController, item: ItemDefinition, count: int)

@export var item: ItemDefinition
@export var count: int = 1
## Ships within this range (with room in the hold) pull it in.
@export var magnet_radius: float = 8.0
@export var magnet_accel: float = 80.0
@export var lifetime: float = 45.0
@export var mesh: MeshInstance3D

var velocity: Vector3 = Vector3.ZERO
## Seconds before it can be collected (so jettisoned cargo doesn't come
## straight back).
var pickup_delay: float = 0.0

var _age: float = 0.0
var _spin: Vector3


func _ready() -> void:
	add_to_group("pickups")
	body_entered.connect(_try_collect)
	_spin = Vector3(randf_range(-2, 2), randf_range(-3, 3), randf_range(-2, 2))
	if mesh != null and item != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = item.color
		mat.emission_enabled = true
		mat.emission = item.color
		mat.emission_energy_multiplier = 1.5
		mesh.material_override = mat


func _physics_process(delta: float) -> void:
	_age += delta
	pickup_delay = maxf(pickup_delay - delta, 0.0)
	if _age > lifetime:
		queue_free()
		return
	var ship := _nearest_taker()
	if ship != null:
		var to_ship := ship.global_position - global_position
		to_ship.y = 0.0
		velocity += to_ship.normalized() * magnet_accel * delta
		# Damp sideways motion so it homes instead of orbiting.
		velocity = velocity.lerp(to_ship.normalized() * velocity.length(), 1.0 - exp(-6.0 * delta))
	else:
		velocity *= exp(-1.5 * delta)
	velocity.y = 0.0
	global_position += velocity * delta
	if mesh != null:
		mesh.rotation += _spin * delta
	if ship != null:
		for body in get_overlapping_bodies():
			_try_collect(body)


func _nearest_taker() -> ShipController:
	if pickup_delay > 0.0:
		return null
	var best: ShipController = null
	var best_dist := magnet_radius
	for node in get_tree().get_nodes_in_group("ships"):
		var ship := node as ShipController
		if ship == null or ship.cargo == null or not ship.is_alive():
			continue
		if not ship.cargo.has_room_for(item):
			continue
		var d := ship.global_position.distance_to(global_position)
		if d < best_dist:
			best = ship
			best_dist = d
	return best


func _try_collect(body: Node) -> void:
	if pickup_delay > 0.0 or is_queued_for_deletion():
		return
	var ship := body as ShipController
	if ship == null or ship.cargo == null or not ship.is_alive():
		return
	var added := ship.cargo.add(item, count)
	if added <= 0:
		return
	collected.emit(ship, item, added)
	ship.picked_up.emit(item, added)
	if ship.team == 0:
		Sfx.play(&"pickup")
	count -= added
	if count <= 0:
		queue_free()


## Spawns `amount` single pickups of `loot` at `pos`, flung outward.
static func scatter(scene: PackedScene, parent: Node, loot: ItemDefinition, amount: int, pos: Vector3, dir: Vector3 = Vector3.ZERO, speed: float = 9.0) -> Array[Pickup]:
	var out: Array[Pickup] = []
	for i in amount:
		var p := scene.instantiate() as Pickup
		p.item = loot
		p.count = 1
		var fling := dir
		if fling == Vector3.ZERO:
			fling = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		else:
			fling = fling.rotated(Vector3.UP, randf_range(-0.8, 0.8))
		p.velocity = fling.normalized() * speed * randf_range(0.6, 1.2)
		parent.add_child(p)
		p.global_position = Vector3(pos.x, 0.0, pos.z)
		out.append(p)
	return out
