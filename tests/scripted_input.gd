extends Node
## Stands in for PlayerShipInput in tests: returns whatever intent the test
## sets. `jettison` fires once and then clears itself, like a button press.

var steer := Vector3.ZERO
var thrust := 0.0
var brake := 0.0
var aim := Vector3.ZERO
var aim_distance := 0.0
var boost := false
var drift := false
var fire := false
var heavy := false
var jettison := false


func get_intent(_ship: Node3D) -> ShipIntent:
	var intent := ShipIntent.new()
	intent.steer = steer
	intent.thrust = thrust
	intent.brake = brake
	intent.aim = aim
	intent.aim_distance = aim_distance
	intent.boost_held = boost
	intent.drift_held = drift
	intent.fire_held = fire
	intent.heavy_held = heavy
	intent.jettison = jettison
	jettison = false
	return intent


func reset() -> void:
	steer = Vector3.ZERO
	thrust = 0.0
	brake = 0.0
	aim = Vector3.ZERO
	aim_distance = 0.0
	boost = false
	drift = false
	fire = false
	heavy = false
	jettison = false
