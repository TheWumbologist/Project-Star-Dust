class_name ArenaScatter
extends Node3D
## Scatters plain and ore-bearing asteroids across a square arena at load,
## from a seed, keeping a clear zone around the spawn point. A stand-in for
## the rift generator: same seed, same layout.

@export var rock_scene: PackedScene
@export var ore_rock_scene: PackedScene
@export var layout_seed: int = 7
@export var rock_count: int = 22
@export var ore_rock_count: int = 10
## Half the width of the square to fill, in metres.
@export var half_size: float = 95.0
## Keep this radius around the origin free for spawning.
@export var clear_radius: float = 18.0
@export var min_gap: float = 4.0
@export var rock_radius_range: Vector2 = Vector2(2.0, 5.5)
@export var ore_radius_range: Vector2 = Vector2(2.5, 4.0)

var _placed: Array[Vector4] = [] # x, z, radius, unused


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	for i in ore_rock_count:
		_place(ore_rock_scene, rng, ore_radius_range, "Ore%02d" % i)
	for i in rock_count:
		_place(rock_scene, rng, rock_radius_range, "Rock%02d" % i)


func _place(scene: PackedScene, rng: RandomNumberGenerator, radius_range: Vector2, node_name: String) -> void:
	if scene == null:
		return
	var r := rng.randf_range(radius_range.x, radius_range.y)
	for attempt in 30:
		var pos := Vector3(rng.randf_range(-half_size, half_size), 0.0, rng.randf_range(-half_size, half_size))
		if pos.length() < clear_radius + r:
			continue
		var ok := true
		for p in _placed:
			if Vector2(pos.x - p.x, pos.z - p.y).length() < r + p.z + min_gap:
				ok = false
				break
		if not ok:
			continue
		var rock := scene.instantiate() as Asteroid
		rock.name = node_name
		rock.radius = r
		if rock is MineableAsteroid:
			# Bigger rocks hold more ore.
			rock.ore_count = roundi(r * 2.5)
		add_child(rock)
		rock.position = pos
		rock.rotation.y = rng.randf() * TAU
		_placed.append(Vector4(pos.x, pos.z, r, 0.0))
		return
