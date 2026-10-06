class_name AIPilot
extends Node
## Simple enemy brain. Like PlayerShipInput it only produces a ShipIntent,
## so enemies fly with the same rules (and stats resources) as the player.
##
## Behaviour: idle until a hostile ship comes within aggro range, then hold
## a preferred range from it, circling, and shoot with a lead when lined up.
## Different enemies are different settings on this one script.

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
		return intent

	var to_target := target.global_position - me.global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var dir := to_target / maxf(dist, 0.01)

	# Steering: blend approaching/backing off with circling the target.
	var tangent := dir.cross(Vector3.UP) * _orbit_sign
	var range_error := clampf((dist - preferred_range) / maxf(preferred_range, 1.0), -1.0, 1.0)
	var move := dir * range_error + tangent * orbit_bias
	if move.length() > 0.05:
		intent.steer = move.normalized()
		# Full throttle to close or open the gap, a gentler circle once in range
		# so the player can line up shots.
		intent.thrust = clampf(0.35 + absf(range_error) * 0.9 + orbit_bias * 0.3, 0.0, 1.0)
	intent.boost_held = boost_range > 0.0 and dist > boost_range and me.forward().dot(dir) > 0.8

	# Aim with a lead on the target's velocity.
	var time_to_hit := dist / maxf(shot_speed, 1.0)
	var lead_point := target.global_position + target.velocity * time_to_hit * lead_factor
	var aim := lead_point - me.global_position
	aim.y = 0.0
	if aim.length() > 0.1:
		intent.aim = aim.normalized()

	_burst_clock = fmod(_burst_clock + delta, burst_time + burst_pause)
	intent.fire_held = dist <= fire_range and _burst_clock < burst_time
	return intent


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
