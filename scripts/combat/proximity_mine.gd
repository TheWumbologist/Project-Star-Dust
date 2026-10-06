class_name ProximityMine
extends AnimatableBody3D
## A mine dropped by a Scrap Hauler's stern rack. It drifts to a stop,
## arms, and when a hostile ship comes within `trigger_radius` it blinks
## for a moment and blows up. A shot sets it off early, so it can be
## cleared from a safe distance. Sits on the "targets" physics layer:
## player shots hit it, enemy ships fly through it.

@export var trigger_radius: float = 4.5
## Seconds after being dropped before it can go off.
@export var arm_delay: float = 0.8
## Seconds of blinking between triggering and the blast.
@export var fuse_time: float = 0.4
## Fizzles out (no blast) after this long.
@export var lifetime: float = 18.0
@export var blast_radius: float = 6.0
@export var knockback: float = 14.0
@export var explosion_scene: PackedScene
## Blinks while armed, quickly once triggered.
@export var light: Node3D
## Velocity drag per second.
@export var drag: float = 2.5

## Set by the ShipWeapon that drops it.
var shooter: Node = null
var damage: float = 24.0
var velocity: Vector3 = Vector3.ZERO

var _age: float = 0.0
var _fuse: float = -1.0
var _team: int = 1
var _blown: bool = false


func _ready() -> void:
	sync_to_physics = false
	if shooter is ShipController:
		_team = shooter.team
	add_to_group("mines")


func _physics_process(delta: float) -> void:
	if _blown:
		return
	_age += delta
	velocity *= exp(-drag * delta)
	global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
	if _fuse >= 0.0:
		_fuse -= delta
		if light != null:
			light.visible = fmod(_fuse, 0.1) > 0.05
		if _fuse <= 0.0:
			_blow()
		return
	if light != null:
		light.visible = _age >= arm_delay and fmod(_age, 1.0) < 0.5
	if _age >= lifetime:
		queue_free()
		return
	if _age >= arm_delay and _hostile_near():
		_fuse = fuse_time
		Sfx.play(&"fuse", global_position)


func is_armed() -> bool:
	return _age >= arm_delay


## Shots set it off straight away.
func take_damage(_amount: float, _source: Node = null) -> void:
	if not _blown:
		_blow()


func _hostile_near() -> bool:
	for node in get_tree().get_nodes_in_group("ships"):
		var ship := node as ShipController
		if ship != null and ship.team != _team and ship.is_alive() \
				and ship.global_position.distance_to(global_position) <= trigger_radius:
			return true
	return false


func _blow() -> void:
	_blown = true
	if explosion_scene != null:
		var boom := explosion_scene.instantiate() as Explosion
		boom.radius = blast_radius
		boom.damage = damage
		boom.knockback = knockback
		boom.source = shooter if is_instance_valid(shooter) else null
		boom.damage_mask = 2 # The player's ship.
		get_parent().add_child(boom)
		boom.global_position = global_position
	queue_free()
