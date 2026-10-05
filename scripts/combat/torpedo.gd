class_name Torpedo
extends Projectile
## Heavy shot: blows up on contact or when it reaches the aim point,
## damaging and shoving everything in the blast. Good against drone packs
## and for cracking ore-rich asteroids.

@export var explosion_scene: PackedScene
@export var blast_radius: float = 7.0
## Speed added to ships caught in the blast, in m/s at the centre.
@export var knockback: float = 18.0


func _finish(_hit: Node) -> void:
	_done = true
	if explosion_scene != null:
		var boom := explosion_scene.instantiate() as Explosion
		boom.damage = damage
		boom.radius = blast_radius
		boom.knockback = knockback
		boom.source = shooter if is_instance_valid(shooter) else null
		boom.damage_mask = collision_mask
		get_parent().add_child(boom)
		boom.global_position = global_position
	queue_free()
