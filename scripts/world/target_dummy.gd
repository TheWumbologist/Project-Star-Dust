class_name TargetDummy
extends AnimatableBody3D
## Practice target: takes damage, flashes, breaks, and respawns.
## Set patrol_distance above 0 to make it slide back and forth for
## leading-shot practice.

signal destroyed(dummy: TargetDummy)

@export var max_health: float = 60.0
@export var respawn_time: float = 3.0
## Distance travelled either side of the start point (0 = stationary).
@export var patrol_distance: float = 0.0
@export var patrol_speed: float = 6.0
## Local direction of patrol travel.
@export var patrol_axis: Vector3 = Vector3.RIGHT
@export var body_mesh: MeshInstance3D
@export var health_label: Label3D

var health: float = 0.0

var _start: Vector3
var _patrol_t: float = 0.0
var _flash: float = 0.0
var _respawn_left: float = 0.0
var _material: StandardMaterial3D
var _base_color: Color


func _ready() -> void:
	add_to_group("damageable")
	health = max_health
	_start = global_position
	if body_mesh != null:
		# Own copy of the material so flashing one dummy doesn't flash all.
		var mat := body_mesh.get_active_material(0)
		if mat is StandardMaterial3D:
			_material = mat.duplicate()
			body_mesh.material_override = _material
			_base_color = _material.albedo_color
	_update_label()


func take_damage(amount: float, _source: Node = null) -> void:
	if not is_alive():
		return
	health = maxf(health - amount, 0.0)
	_flash = 1.0
	_update_label()
	if health <= 0.0:
		_break()


func is_alive() -> bool:
	return _respawn_left <= 0.0


func _physics_process(delta: float) -> void:
	if _respawn_left > 0.0:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_respawn()
		return

	if patrol_distance > 0.0:
		_patrol_t += delta * patrol_speed / patrol_distance
		var axis := (global_transform.basis * patrol_axis).normalized()
		global_position = _start + axis * sin(_patrol_t) * patrol_distance

	if _material != null and _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
		_material.albedo_color = _base_color.lerp(Color.WHITE, _flash)
		_material.emission_energy_multiplier = 1.0 + _flash * 4.0


func _break() -> void:
	_respawn_left = respawn_time
	visible = false
	collision_layer = 0
	destroyed.emit(self)


func _respawn() -> void:
	health = max_health
	visible = true
	collision_layer = 4 # targets
	_flash = 0.0
	if _material != null:
		_material.albedo_color = _base_color
	_update_label()


func _update_label() -> void:
	if health_label != null:
		health_label.text = "%d" % ceili(health)
