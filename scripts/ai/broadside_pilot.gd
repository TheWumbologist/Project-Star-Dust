class_name BroadsidePilot
extends AIPilot
## Broadside Galleon: a slow, heavy warship whose guns point out of its
## sides. It circles its target at range so the target sits abeam, and
## each battery (a ShipWeapon with a narrow arc) fires whenever the target
## crosses its side. Now and then it comes about and circles the other way.
## Its bow and stern are blind spots: get in close at either end.

## Seconds between changes of direction (randomised +-30%).
@export var come_about_time: float = 9.0

var _come_about: float = 0.0


func _ready() -> void:
	super()
	_come_about = come_about_time * randf_range(0.7, 1.3)


func _fly(me: ShipController, intent: ShipIntent, delta: float) -> void:
	var dist := _distance(me)
	var dir := _direction(me)
	_come_about -= delta
	if _come_about <= 0.0:
		_come_about = come_about_time * randf_range(0.7, 1.3)
		_orbit_sign = -_orbit_sign
	_hold_range(me, intent, dir, dist, preferred_range, orbit_bias)
	intent.steer = _avoid(me, intent.steer, 14.0)
	_aim_with_lead(me, intent, shot_speed)
	# The batteries only fire when the aim crosses their side.
	intent.fire_held = dist <= fire_range and _burst(delta)
