class_name Explosion
extends Node3D
## One-shot blast: an expanding flash plus, when damage > 0, one round of
## area damage with falloff (full at the centre, half at the edge) and a
## shove for anything with `apply_impulse`. Also used purely as a visual
## when ships and rocks are destroyed.

@export var radius: float = 6.0
@export var damage: float = 0.0
@export var knockback: float = 0.0
## Physics layers the blast can hurt.
@export_flags_3d_physics var damage_mask: int = 0
@export var duration: float = 0.45
@export var flash: MeshInstance3D
@export var debris: GPUParticles3D
## A flat shockwave ring that races outward past the flash.
@export var ring: MeshInstance3D
## &"auto" picks a small or big blast by radius; &"" is silent.
@export var sound: StringName = &"auto"

## Who caused it; never hurt by its own blast.
var source: Node = null

var _age: float = 0.0
var _applied: bool = false
var _material: StandardMaterial3D
var _ring_material: StandardMaterial3D


func _ready() -> void:
	if flash != null:
		_material = flash.get_active_material(0).duplicate() as StandardMaterial3D
		flash.material_override = _material
	if debris != null:
		debris.emitting = true
	if ring != null:
		_ring_material = ring.get_active_material(0).duplicate() as StandardMaterial3D
		ring.material_override = _ring_material
	if sound == &"auto":
		Sfx.play(&"explosion_big" if radius >= 7.0 else &"explosion_small", global_position)
	elif sound != &"":
		Sfx.play(sound, global_position)


func _physics_process(delta: float) -> void:
	if not _applied:
		_applied = true
		_apply_damage()
	_age += delta
	var t := clampf(_age / duration, 0.0, 1.0)
	if flash != null:
		flash.scale = Vector3.ONE * radius * lerpf(0.3, 1.0, 1.0 - pow(1.0 - t, 3.0))
		if _material != null:
			_material.albedo_color.a = 1.0 - t
	if ring != null:
		var rt := clampf(_age / (duration * 1.3), 0.0, 1.0)
		ring.scale = Vector3.ONE * radius * lerpf(0.2, 1.7, 1.0 - pow(1.0 - rt, 2.0))
		if _ring_material != null:
			_ring_material.albedo_color.a = (1.0 - rt) * 0.8
	# Linger long enough for the debris particles to finish.
	if _age >= maxf(duration, 1.0):
		queue_free()


func _apply_damage() -> void:
	if (damage <= 0.0 and knockback <= 0.0) or damage_mask == 0:
		return
	# Whoever set it off may be gone already (a kamikaze blows itself up).
	if not is_instance_valid(source):
		source = null
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = damage_mask
	query.collide_with_areas = false
	var hit: Array[Node] = []
	for result in get_world_3d().direct_space_state.intersect_shape(query, 64):
		var body := result["collider"] as Node3D
		if body == null or body == source or body in hit:
			continue
		hit.append(body)
		var offset := body.global_position - global_position
		offset.y = 0.0
		var falloff := 1.0 - 0.5 * clampf(offset.length() / radius, 0.0, 1.0)
		if damage > 0.0 and body.has_method("take_damage"):
			body.take_damage(damage * falloff, source)
		if knockback > 0.0 and body.has_method("apply_impulse"):
			var dir := offset.normalized() if offset.length() > 0.1 else Vector3.FORWARD
			body.apply_impulse(dir * knockback * falloff)
