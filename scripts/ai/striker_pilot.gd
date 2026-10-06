class_name StrikerPilot
extends AIPilot
## Void Wasp: hit and run. It boosts in on a slanted line past its target,
## firing as it comes, peels away once it's close or past, and swings back
## round for another pass. Hard to pin down, but it only shoots on the way
## in, so turn and meet it.

## Breaks off the attack run inside this distance.
@export var pass_range: float = 7.0
## Swings back round once this far away again.
@export var retreat_range: float = 30.0
## Longest it spends running away before turning back.
@export var max_retreat_time: float = 2.5
## How far to the side of the target the attack run aims, in metres.
@export var strafe_offset: float = 6.0

var attacking: bool = true

var _retreat_clock: float = 0.0


func _fly(me: ShipController, intent: ShipIntent, delta: float) -> void:
	var dist := _distance(me)
	var dir := _direction(me)
	var side := dir.cross(Vector3.UP) * _orbit_sign
	if attacking:
		# Aim the run at a point beside the target so it flashes past.
		var run_to := target.global_position + side * strafe_offset - me.global_position
		run_to.y = 0.0
		intent.steer = _avoid(me, run_to.normalized())
		intent.thrust = 1.0
		intent.boost_held = dist > fire_range and me.forward().dot(dir) > 0.85
		_aim_with_lead(me, intent, shot_speed)
		intent.fire_held = dist <= fire_range and _burst(delta)
		# Break off once close, or once it has flown past within range.
		if dist < pass_range or (dist < fire_range and me.velocity.dot(dir) < -1.0):
			attacking = false
			_retreat_clock = 0.0
	else:
		_retreat_clock += delta
		intent.steer = _avoid(me, (-dir + side * 0.6).normalized())
		intent.thrust = 1.0
		intent.boost_held = _retreat_clock < 0.6
		if dist > retreat_range or _retreat_clock > max_retreat_time:
			attacking = true
			_orbit_sign = -_orbit_sign # Come back on the other side.
