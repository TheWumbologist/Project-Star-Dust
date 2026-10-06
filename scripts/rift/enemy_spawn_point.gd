class_name EnemySpawnPoint
extends Marker3D
## Marks where a rift chunk may place an enemy when the rift is generated.
## The roll uses the rift's seed, so a given rift always has the same foes.

@export var enemy: PackedScene
## Chance this point actually spawns something (0..1).
@export_range(0.0, 1.0) var chance: float = 1.0


## `chance_bonus` raises (or lowers) the chance for harder (easier) sites.
func spawn(rng: RandomNumberGenerator, parent: Node, chance_bonus: float = 0.0) -> ShipController:
	if enemy == null or rng.randf() > clampf(chance + chance_bonus, 0.0, 1.0):
		return null
	var ship := enemy.instantiate() as ShipController
	parent.add_child(ship)
	ship.global_position = Vector3(global_position.x, 0.0, global_position.z)
	ship.rotation.y = rng.randf() * TAU
	ship.reset_physics_interpolation()
	return ship
