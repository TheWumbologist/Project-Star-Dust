class_name OneShotParticles
extends GPUParticles3D
## Fires once, then frees itself when the particles have died out. Used
## for impact sparks. `tint` recolours the burst.

@export var tint: Color = Color(1, 0.8, 0.4)


func _ready() -> void:
	var mat := process_material as ParticleProcessMaterial
	if mat != null:
		mat = mat.duplicate()
		mat.color = tint
		process_material = mat
	one_shot = true
	emitting = true
	get_tree().create_timer(lifetime + 0.2, false).timeout.connect(queue_free)
