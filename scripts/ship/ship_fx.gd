class_name ShipFx
extends Node3D
## Cosmetic feedback for a ship: drift sparks that change colour as the
## drift charges, a hotter engine and longer trail while boosting.
## Purely visual; reads the ship's state and never changes it.

@export var ship: ShipController
@export var engine_glow: MeshInstance3D
@export var trail: GPUParticles3D
@export var sparks: Array[GPUParticles3D] = []

## Spark colours for no charge, tier 1 and tier 2.
@export var spark_colors: Array[Color] = [
	Color(0.85, 0.85, 0.95), Color(0.35, 0.75, 1.0), Color(1.0, 0.55, 0.15)]

var _engine_scale: float = 1.0


# Physics tick, so the engine flame stays in step with physics interpolation.
func _physics_process(delta: float) -> void:
	if ship == null:
		return
	var tier := ship.drift_tier()
	for s in sparks:
		s.emitting = ship.is_drifting and ship.speed() > 4.0
		s.amount_ratio = 0.4 + 0.3 * tier
		var mat := s.process_material as ParticleProcessMaterial
		if mat != null:
			mat.color = spark_colors[clampi(tier, 0, spark_colors.size() - 1)]

	var target := 1.0 + ship.last_intent.thrust * 0.4
	if ship.is_boosting():
		target = 2.2
	_engine_scale = lerpf(_engine_scale, target, 1.0 - exp(-12.0 * delta))
	if engine_glow != null:
		engine_glow.scale = Vector3(1.0, 1.0, _engine_scale)
	if trail != null:
		trail.amount_ratio = 1.0 if ship.is_fast() else 0.5
