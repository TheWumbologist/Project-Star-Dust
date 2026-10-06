class_name AugmentCache
extends Area3D
## A glowing cache of rift tech. Fly into it to pick one of three augments
## for this run. Chunks place these with a spawn chance; tougher enemies
## sometimes drop one.

## Chance this cache exists when the rift is built (rolled by the generator).
@export_range(0.0, 1.0) var spawn_chance: float = 1.0
@export var choices: int = 3
@export var spin_speed: float = 1.4

var opened: bool = false


func _ready() -> void:
	add_to_group("augment_caches")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	var gem := get_node_or_null("Gem") as Node3D
	if gem != null:
		gem.rotate_y(spin_speed * delta)
		gem.position.y = 0.6 + sin(Time.get_ticks_msec() * 0.003) * 0.3


func _on_body_entered(body: Node) -> void:
	var ship := body as ShipController
	if opened or ship == null or ship.team != 0 or ship.loadout == null or not ship.is_alive():
		return
	var picker := get_tree().get_first_node_in_group("augment_picker") as AugmentPicker
	if picker == null or picker.is_open:
		return
	opened = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	Sfx.play(&"cache")
	picker.open(ship, AugmentCatalog.roll(rng, choices))
	queue_free()
