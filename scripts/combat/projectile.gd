class_name Projectile
extends Area3D
## A straight-flying shot. Damages the first body it touches that has
## `take_damage(amount, source)`, and stops on world geometry.

@export var lifetime: float = 1.6

var velocity: Vector3 = Vector3.ZERO
var damage: float = 10.0
## Who fired it; never hits its own shooter.
var shooter: Node = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body == shooter:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, shooter)
	queue_free()
