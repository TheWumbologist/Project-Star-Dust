class_name SkittishPilot
extends AIPilot
## Scrap Hauler: an unarmed salvage barge. It potters about until a
## hostile comes near, then runs, dropping proximity mines out of its
## stern (a ShipWeapon mounted astern) whenever the chaser is behind it.
## Catch it from the side, or shoot the mines before flying through.

## Flees from targets closer than this.
@export var flee_range: float = 40.0
## Drops mines while the target is within this distance behind it.
@export var mine_range: float = 26.0
## Wanders this far from where it started while nothing is around.
@export var wander_radius: float = 12.0

var _home: Vector3 = Vector3.INF
var _wander_to: Vector3 = Vector3.ZERO
var _wander_clock: float = 0.0


func _fly(me: ShipController, intent: ShipIntent, delta: float) -> void:
	var dist := _distance(me)
	var dir := _direction(me)
	if dist > flee_range:
		_idle(me, intent, delta)
		return
	# Run away, curving a little so it doesn't just hit the nearest wall.
	var away := (-dir + dir.cross(Vector3.UP) * _orbit_sign * 0.35).normalized()
	intent.steer = _avoid(me, away, 12.0)
	intent.thrust = 1.0
	intent.boost_held = dist < 12.0
	# The mine rack fires astern; only bother when the chaser is behind.
	intent.fire_held = dist <= mine_range and me.forward().dot(dir) < -0.3


func _idle(me: ShipController, intent: ShipIntent, delta: float) -> void:
	if _home == Vector3.INF:
		_home = me.global_position
	_wander_clock -= delta
	if _wander_clock <= 0.0:
		_wander_clock = randf_range(3.0, 6.0)
		_wander_to = _home + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf() * wander_radius
	var to := _wander_to - me.global_position
	to.y = 0.0
	if to.length() > 2.0:
		intent.steer = _avoid(me, to.normalized())
		intent.thrust = 0.35
