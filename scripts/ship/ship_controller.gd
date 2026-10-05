class_name ShipController
extends CharacterBody3D
## Arcade flight rules for one ship: thrust, steering inertia, boost, drift
## and ramming, on a flat XZ plane.
##
## The ship reads a ShipIntent each physics tick from `input_source` (any
## node with `get_intent(ship) -> ShipIntent`). It owns no input or camera
## code, so a second player or an AI pilot is just another input source.
## Weapons and the grapple are child components that the ship drives.

signal boost_fired
signal perfect_drift
signal rammed(target: Node)

@export var stats: ShipStats
## Node providing `get_intent(ship)`. Defaults to a child named "Input".
@export var input_source: Node
## Optional visual node that rolls into turns and drifts.
@export var visual_root: Node3D
## Optional turret node that yaws toward the aim direction.
@export var turret: Node3D

## Boost meter, 0..1.
var boost_meter: float = 1.0
## Current normalised world aim direction on the XZ plane.
var aim_direction: Vector3 = Vector3.FORWARD
var is_drifting: bool = false
var last_intent: ShipIntent = ShipIntent.new()

var _boost_time_left: float = 0.0
var _recharge_wait: float = 0.0
var _drift_time: float = 0.0
var _drift_angle_sum: float = 0.0
var _rammed_this_boost: Array[Node] = []
## Extra acceleration (m/s^2) and speed-cap bonus from wind streams this tick.
var _wind_accel: Vector3 = Vector3.ZERO
var _wind_cap_bonus: float = 0.0

@onready var cannon: ShipCannon = get_node_or_null("Cannon") as ShipCannon
@onready var grapple: ShipGrapple = get_node_or_null("Grapple") as ShipGrapple


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if stats == null:
		stats = ShipStats.new()
	if input_source == null:
		input_source = get_node_or_null("Input")
	aim_direction = forward()


func _physics_process(delta: float) -> void:
	var intent: ShipIntent = ShipIntent.new()
	if input_source != null and input_source.has_method("get_intent"):
		intent = input_source.get_intent(self)
	last_intent = intent

	if intent.aim != Vector3.ZERO:
		aim_direction = intent.aim

	_steer(intent, delta)
	_apply_thrust(intent, delta)
	_update_boost(intent, delta)
	_update_drift(intent, delta)
	_apply_grip(delta)
	_apply_speed_cap(delta)

	if grapple != null:
		grapple.tick(self, intent, delta)
	if cannon != null:
		cannon.tick(self, intent, delta)

	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0
	_handle_ram_collisions()
	_update_visuals(delta)

	_wind_accel = Vector3.ZERO
	_wind_cap_bonus = 0.0


# --- Public API ------------------------------------------------------------

## The hull's nose direction on the XZ plane.
func forward() -> Vector3:
	return -global_transform.basis.z


func is_boosting() -> bool:
	return _boost_time_left > 0.0


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Called every tick by wind streams the ship is inside.
func apply_wind(accel: Vector3, cap_bonus: float) -> void:
	_wind_accel += accel
	_wind_cap_bonus = maxf(_wind_cap_bonus, cap_bonus)


## Adds boost meter (perfect drifts now; pickups and augments later).
func add_boost(amount: float) -> void:
	boost_meter = clampf(boost_meter + amount, 0.0, 1.0)


# --- Flight model ------------------------------------------------------------

func _steer(intent: ShipIntent, delta: float) -> void:
	var desired := Vector3.ZERO
	if _is_grappled():
		# Swinging: the nose follows the orbit so grip doesn't fight the rope.
		if speed() < 1.0:
			return
		desired = Vector3(velocity.x, 0.0, velocity.z).normalized()
	elif intent.move.length() >= 0.1:
		desired = Vector3(intent.move.x, 0.0, intent.move.y).normalized()
	else:
		return
	var target_yaw := atan2(-desired.x, -desired.z)
	var turn_rate := deg_to_rad(stats.turn_rate_deg)
	if is_drifting:
		turn_rate *= stats.drift_turn_multiplier
	rotation.y = rotate_toward(rotation.y, target_yaw, turn_rate * delta)


func _apply_thrust(intent: ShipIntent, delta: float) -> void:
	var throttle := clampf(intent.move.length(), 0.0, 1.0)
	if throttle > 0.05:
		# Engines only push up to cruising speed; anything above that comes
		# from boost or wind and bleeds off in _apply_speed_cap.
		var cruise_cap := stats.max_speed * throttle + _wind_cap_bonus
		if velocity.dot(forward()) < cruise_cap:
			velocity += forward() * stats.acceleration * throttle * delta
	elif not _is_grappled():
		velocity *= exp(-stats.coast_drag * delta)
	velocity += _wind_accel * delta


func _update_boost(intent: ShipIntent, delta: float) -> void:
	_boost_time_left = maxf(_boost_time_left - delta, 0.0)

	if intent.boost_pressed and boost_meter >= stats.boost_cost:
		boost_meter -= stats.boost_cost
		_boost_time_left = stats.boost_duration
		_recharge_wait = stats.boost_recharge_delay
		_rammed_this_boost.clear()
		# Boost along the stick if held, otherwise along the nose.
		var dir := forward()
		if intent.move.length() > 0.1:
			dir = Vector3(intent.move.x, 0.0, intent.move.y).normalized()
		velocity += dir * stats.boost_impulse
		boost_fired.emit()

	if _recharge_wait > 0.0:
		_recharge_wait -= delta
	else:
		boost_meter = minf(boost_meter + stats.boost_recharge_rate * delta, 1.0)


func _update_drift(intent: ShipIntent, delta: float) -> void:
	var can_drift := intent.drift_held and speed() >= stats.drift_min_speed
	if can_drift:
		is_drifting = true
		_drift_time += delta
		_drift_angle_sum += _slip_angle_deg() * delta
		return

	if is_drifting:
		# Drift just ended: reward a long, committed slide.
		var avg_angle := _drift_angle_sum / maxf(_drift_time, 0.001)
		if _drift_time >= stats.perfect_drift_min_time and avg_angle >= stats.perfect_drift_min_angle_deg:
			add_boost(stats.perfect_drift_refill)
			perfect_drift.emit()
	is_drifting = false
	_drift_time = 0.0
	_drift_angle_sum = 0.0


## Cancels sideways velocity relative to the hull. Low grip = drift.
func _apply_grip(delta: float) -> void:
	var fwd := forward()
	var right := fwd.cross(Vector3.UP)
	var along := velocity.dot(fwd)
	var lateral := velocity.dot(right)
	var grip := stats.drift_grip if is_drifting else stats.grip
	lateral *= exp(-grip * delta)
	velocity = fwd * along + right * lateral


func _apply_speed_cap(delta: float) -> void:
	var cap := stats.boost_max_speed if is_boosting() else stats.max_speed
	cap += _wind_cap_bonus
	var spd := speed()
	if spd > cap:
		var new_speed := lerpf(spd, cap, 1.0 - exp(-stats.overspeed_drag * delta))
		velocity = velocity * (new_speed / spd)


func _is_grappled() -> bool:
	return grapple != null and grapple.is_attached()


## Angle in degrees between the hull's nose and its actual travel direction.
func _slip_angle_deg() -> float:
	if speed() < 0.5:
		return 0.0
	var vel_dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
	return rad_to_deg(forward().angle_to(vel_dir))


func _handle_ram_collisions() -> void:
	if not is_boosting():
		return
	for i in get_slide_collision_count():
		var target := get_slide_collision(i).get_collider() as Node
		if target == null or target in _rammed_this_boost:
			continue
		if target.has_method("take_damage"):
			_rammed_this_boost.append(target)
			target.take_damage(stats.ram_damage, self)
			rammed.emit(target)


func _update_visuals(delta: float) -> void:
	if turret != null:
		turret.global_rotation.y = atan2(-aim_direction.x, -aim_direction.z)
	if visual_root != null:
		# Bank into the slide so drifts read clearly from the high camera.
		var right := forward().cross(Vector3.UP)
		var lateral := velocity.dot(right) / maxf(stats.max_speed, 1.0)
		var target_roll := clampf(-lateral, -1.0, 1.0) * deg_to_rad(28.0)
		visual_root.rotation.z = lerpf(visual_root.rotation.z, target_roll, 1.0 - exp(-8.0 * delta))
