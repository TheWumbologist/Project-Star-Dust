class_name AIPilot
extends Node
## Simple enemy brain. Like PlayerShipInput it only produces a ShipIntent,
## so enemies fly with the same rules (and stats resources) as the player.
##
## Behaviour: idle until a hostile ship comes within aggro range, then hold
## a preferred range from it, circling, and shoot with a lead when lined up.
## Many enemies are just different settings on this script; the ones that
## fight differently (kamikazes, snipers, broadsides...) extend it and
## override _fly(). See EnemyRoster for the full line-up.

## Start chasing hostiles within this range.
@export var aggro_range: float = 45.0
## Give up when the target gets this far away.
@export var leash_range: float = 80.0
## Distance the pilot tries to hold from its target.
@export var preferred_range: float = 14.0
## How hard it circles the target, 0 (straight at it) to 1 (pure orbit).
@export_range(0.0, 1.0) var orbit_bias: float = 0.6
## Fire when the target is within this range.
@export var fire_range: float = 26.0
## Seconds of target travel to lead shots by (scaled by distance).
@export var lead_factor: float = 1.0
## Projectile speed used for leading; match the ship's weapon.
@export var shot_speed: float = 40.0
## Boost to close the gap when farther than this (0 = never boost).
@export var boost_range: float = 0.0
## Only notice targets it can see (rocks and rift walls block the view).
## Once chasing, it keeps after the target until the leash breaks.
@export var needs_line_of_sight: bool = true
## Fire bursts: shoot for this long, then pause for burst_pause.
@export var burst_time: float = 1.0
@export var burst_pause: float = 0.8

var target: ShipController = null

var _orbit_sign: float = 1.0
var _burst_clock: float = 0.0
var _retarget: float = 0.0
## Boost hysteresis: seconds left to keep burning / to wait before the next
## burn. Each new burn kicks the ship forward, so flickering it would stack
## kicks far past the speed cap.
var _boost_hold: float = 0.0
var _boost_rest: float = 0.0


func _ready() -> void:
	_orbit_sign = -1.0 if randf() < 0.5 else 1.0
	_burst_clock = randf() * (burst_time + burst_pause)


func get_intent(ship: Node3D) -> ShipIntent:
	var me := ship as ShipController
	var intent := ShipIntent.new()
	var delta := me.get_physics_process_delta_time()
	_retarget -= delta
	if _retarget <= 0.0 or not _valid(target, me, leash_range):
		_retarget = 0.5
		target = _find_target(me)
	if target == null:
		_idle(me, intent, delta)
	else:
		_fly(me, intent, delta)
	intent.boost_held = _gate_boost(intent.boost_held, delta)
	return intent


## Steering and trigger for this tick, with a live `target`. Override for
## other fighting styles; the default holds range, circles and shoots.
func _fly(me: ShipController, intent: ShipIntent, delta: float) -> void:
	var dist := _distance(me)
	var dir := _direction(me)
	_hold_range(me, intent, dir, dist, preferred_range, orbit_bias)
	intent.boost_held = boost_range > 0.0 and dist > boost_range and me.forward().dot(dir) > 0.8
	_aim_with_lead(me, intent, shot_speed)
	intent.fire_held = dist <= fire_range and _burst(delta)


## What to do with no target in reach. The default drifts to a stop.
func _idle(_me: ShipController, _intent: ShipIntent, _delta: float) -> void:
	pass


# --- Helpers for pilots --------------------------------------------------------

## Flat distance to the target.
func _distance(me: Node3D) -> float:
	var to := target.global_position - me.global_position
	to.y = 0.0
	return to.length()


## Flat unit direction to the target.
func _direction(me: Node3D) -> Vector3:
	var to := target.global_position - me.global_position
	to.y = 0.0
	return to / maxf(to.length(), 0.01)


## Blends approaching/backing off with circling the target.
func _hold_range(_me: ShipController, intent: ShipIntent, dir: Vector3, dist: float, want: float, orbit: float) -> void:
	var tangent := dir.cross(Vector3.UP) * _orbit_sign
	var range_error := clampf((dist - want) / maxf(want, 1.0), -1.0, 1.0)
	var move := dir * range_error + tangent * orbit
	if move.length() > 0.05:
		intent.steer = move.normalized()
		# Full throttle to close or open the gap, a gentler circle once in range
		# so the player can line up shots.
		intent.thrust = clampf(0.35 + absf(range_error) * 0.9 + orbit * 0.3, 0.0, 1.0)


## Where the target will be when a shot at `speed` gets there.
func _lead_point(me: Node3D, speed: float) -> Vector3:
	var time_to_hit := _distance(me) / maxf(speed, 1.0)
	return target.global_position + target.velocity * time_to_hit * lead_factor


## Aims at the target's lead point.
func _aim_with_lead(me: Node3D, intent: ShipIntent, speed: float) -> void:
	var aim := _lead_point(me, speed) - me.global_position
	aim.y = 0.0
	if aim.length() > 0.1:
		intent.aim = aim.normalized()


## Bends `steer` away from walls and rocks dead ahead (looks `look` metres
## out), so fleeing or charging ships don't grind along the rift walls.
func _avoid(me: ShipController, steer: Vector3, look: float = 9.0) -> Vector3:
	if steer == Vector3.ZERO:
		return steer
	var space := me.get_world_3d().direct_space_state
	if _clear_line(space, me, steer, look):
		return steer
	for turn in [0.6, -0.6, 1.2, -1.2, 1.9, -1.9]:
		var bent := steer.rotated(Vector3.UP, turn * _orbit_sign)
		if _clear_line(space, me, bent, look):
			return bent
	return -steer


func _clear_line(space: PhysicsDirectSpaceState3D, me: ShipController, dir: Vector3, length: float) -> bool:
	var query := PhysicsRayQueryParameters3D.create(me.global_position, me.global_position + dir * length, 1)
	return space.intersect_ray(query).is_empty()


## Turns a pilot's raw "boost now" into burns of at least half a second
## with a rest between them.
func _gate_boost(wanted: bool, delta: float) -> bool:
	_boost_hold = maxf(_boost_hold - delta, 0.0)
	_boost_rest = maxf(_boost_rest - delta, 0.0)
	if _boost_hold > 0.0:
		if _boost_hold <= delta:
			_boost_rest = 0.8
		return true
	if wanted and _boost_rest <= 0.0:
		_boost_hold = 0.5
		return true
	return false


## Advances the burst clock; true while in the firing part of a burst.
func _burst(delta: float) -> bool:
	_burst_clock = fmod(_burst_clock + delta, burst_time + burst_pause)
	return _burst_clock < burst_time


func _find_target(me: ShipController) -> ShipController:
	var best: ShipController = null
	var best_dist := aggro_range
	for node in me.get_tree().get_nodes_in_group("ships"):
		var other := node as ShipController
		if not _valid(other, me, best_dist):
			continue
		if needs_line_of_sight and other != target and not _can_see(me, other):
			continue
		best = other
		best_dist = me.global_position.distance_to(other.global_position)
	return best


func _valid(other: ShipController, me: ShipController, max_range: float) -> bool:
	return other != null and is_instance_valid(other) and other != me \
		and other.team != me.team and other.is_alive() \
		and me.global_position.distance_to(other.global_position) <= max_range


func _can_see(me: ShipController, other: ShipController) -> bool:
	var query := PhysicsRayQueryParameters3D.create(me.global_position, other.global_position, 1)
	return me.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
