class_name LootDropper
extends Node
## Drops cargo pickups when its parent's Health runs out. Put it next to a
## Health node on enemies; tune what drops per enemy here.

@export var pickup_scene: PackedScene
@export var health: Health
@export var item: ItemDefinition
@export var min_count: int = 1
@export var max_count: int = 3


func _ready() -> void:
	if health != null:
		health.died.connect(func(_source): drop())


func drop() -> void:
	if pickup_scene == null or item == null:
		return
	var body := get_parent() as Node3D
	var count := randi_range(min_count, max_count)
	Pickup.scatter(pickup_scene, body.get_parent(), item, count, body.global_position)
