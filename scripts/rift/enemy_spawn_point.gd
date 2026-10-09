class_name EnemySpawnPoint
extends Marker3D
## Marks where a rift chunk may place an enemy when the rift is generated.
## The roll uses the rift's seed, so a given rift always has the same foes.
##
## `enemy` is a tier 1 enemy from the EnemyRoster: in a rift it stands for
## its role (swarm, gunship or specialist), and the generator swaps in that
## role's enemy for the tier it rolls for the site.

@export var enemy: PackedScene
## Chance this point actually spawns something (0..1).
@export_range(0.0, 1.0) var chance: float = 1.0
## Spacing between ships when the point places a pack.
const PACK_SPACING := 3.5


## `chance_bonus` raises (or lowers) the chance for harder (easier) sites.
## `scene` replaces the authored enemy (the roster's pick); `count` places
## a pack around the point. Returns the ships placed.
func spawn(rng: RandomNumberGenerator, parent: Node, chance_bonus: float = 0.0, scene: PackedScene = null, count: int = 1) -> Array[ShipController]:
	var placed: Array[ShipController] = []
	if scene == null:
		scene = enemy
	if scene == null or rng.randf() > clampf(chance + chance_bonus, 0.0, 1.0):
		return placed
	var turn := rng.randf() * TAU
	for i in maxi(count, 1):
		var ship := scene.instantiate() as ShipController
		parent.add_child(ship)
		var offset := Vector3.ZERO
		if i > 0:
			offset = Vector3.FORWARD.rotated(Vector3.UP, turn + TAU * i / count) * PACK_SPACING
		ship.global_position = Vector3(global_position.x, 0.0, global_position.z) + offset
		ship.rotation.y = rng.randf() * TAU
		ship.reset_physics_interpolation()
		placed.append(ship)
	return placed
