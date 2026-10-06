class_name SalvageCrate
extends StaticBody3D
## Breakable cargo crate from a wreck. Shoot or ram it open for salvage.

@export var max_health: float = 30.0
@export var pickup_scene: PackedScene
@export var item: ItemDefinition
@export var count_range: Vector2i = Vector2i(2, 4)
## Optional rarer drop and its chance.
@export var bonus_item: ItemDefinition
@export_range(0.0, 1.0) var bonus_chance: float = 0.0
@export var break_explosion: PackedScene
@export var mesh: MeshInstance3D

var health: float = 0.0

var _flash: float = 0.0
var _overlay: StandardMaterial3D


func _ready() -> void:
	health = max_health
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(1, 1, 1, 0)
	if mesh != null:
		mesh.material_overlay = _overlay


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_overlay.albedo_color.a = _flash * 0.8


func take_damage(amount: float, source: Node = null) -> void:
	if health <= 0.0:
		return
	health -= amount
	_flash = 1.0
	if health <= 0.0:
		_break(source)


func _break(_source: Node) -> void:
	var parent := get_parent()
	if pickup_scene != null and item != null:
		Pickup.scatter(pickup_scene, parent, item, randi_range(count_range.x, count_range.y), global_position)
	if pickup_scene != null and bonus_item != null and randf() < bonus_chance:
		Pickup.scatter(pickup_scene, parent, bonus_item, 1, global_position)
	if break_explosion != null:
		var boom := break_explosion.instantiate() as Explosion
		boom.radius = 3.0
		parent.add_child(boom)
		boom.global_position = global_position
	queue_free()
