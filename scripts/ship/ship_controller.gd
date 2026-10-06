class_name ShipController
extends CharacterBody3D
## Arcade flight rules for one ship on a flat XZ plane: the nose turns toward
## the steering direction, one engine pushes along the nose, boost burns fuel
## while held, and drifting lets the ship slide sideways and charge a speed
## kick for when you let go.
##
## The ship reads a ShipIntent each physics tick from `input_source` (any
## node with `get_intent(ship) -> ShipIntent`). It owns no input or camera
## code, so a second player or an AI pilot is just another input source.
## Optional child components the ship drives or exposes: ShipWeapon nodes,
## a Health named "Health" and a CargoHold named "Cargo".

signal boost_started
signal boost_ended
## Emitted when a charged drift is released. tier is 1 or 2.
signal drift_kicked(tier: int)
signal rammed(target: Node)
signal damaged(amount: float, source: Node)
signal destroyed(ship: ShipController)
## Cargo collected from a pickup.
signal picked_up(item: ItemDefinition, count: int)

@export var stats: ShipStats
## Node providing `get_intent(ship)`. Defaults to a child named "Input".
@export var input_source: Node
## Optional visual node that banks and swings out during drifts.
@export var visual_root: Node3D
## Optional turret node that yaws toward the aim direction.
@export var turret: Node3D
## Ships only hurt ships on other teams (0 = player crews, 1 = hostiles).
@export var team: int = 0
## Free the ship when destroyed (enemies). Otherwise it is disabled and
## waits for respawn() (players).
@export var free_on_death: bool = false
## Visual spawned where the ship is destroyed.
@export var death_explosion: PackedScene
## Pickup scene used when jettisoning cargo.
@export var jettison_pickup: PackedScene

## Boost fuel, 0..1.
var boost_fuel: float = 1.0
## Current normalised world aim direction on the XZ plane.
var aim_direction: Vector3 = Vector3.FORWARD
## Distance to the aim point, or 0 when there isn't one (stick aim).
var aim_distance: float = 0.0
var is_drifting: bool = false
## Drift charge built this drift, in seconds of committed sliding.
var drift_charge: float = 0.0
var last_intent: ShipIntent = ShipIntent.new()

var _boosting: bool = false
## After the tank runs dry, boost stays off until the button is released.
var _boost_locked: bool = false
var _recharge_wait: float = 0.0
var _kick_time_left: float = 0.0
var _rammed_this_boost: Array[Node] = []
## Extra acceleration (m/s^2) and speed-cap bonus from wind streams this tick.
var _wind_accel: Vector3 = Vector3.ZERO
var _wind_cap_bonus: float = 0.0

var _alive: bool = true

@onready var health: Health = get_node_or_null("Health") as Health
@onready var cargo: CargoHold = get_node_or_null("Cargo") as CargoHold
## The primary and heavy weapons, if fitted (for HUDs and tests).
@onready var primary: ShipWeapon = _find_weapon(ShipWeapon.Slot.PRIMARY)
@onready var heavy: ShipWeapon = _find_weapon(ShipWeapon.Slot.HEAVY)


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	if stats == null:
		stats = ShipStats.new()
	if input_source == null:
		input_source = get_node_or_null("Input")
	aim_direction = forward()
	add_to_group("ships")
	if health != null:
		health.damaged.connect(func(amount, source): damaged.emit(amount, source))
		health.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	var intent: ShipIntent = ShipIntent.new()
	if input_source != null and input_source.has_method("get_intent"):
		intent = input_source.get_intent(self)
	last_intent = intent

	if intent.aim != Vector3.ZERO:
		aim_direction = intent.aim
		aim_distance = intent.aim_distance

	_update_drift(intent, delta)
	_steer(intent, delta)
	_update_boost(intent, delta)
	_apply_thrust(intent, delta)
	_apply_grip(delta)
	_apply_speed_cap(delta)

	for child in get_children():
		if child is ShipWeapon:
			child.tick(self, intent, delta)
	if intent.jettison and cargo != null:
		_jettison()

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
	return _boosting


## True while boosting or riding a drift kick (raised speed cap).
func is_fast() -> bool:
	return _boosting or _kick_time_left > 0.0


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Drift charge tier reached so far this drift: 0, 1 or 2.
func drift_tier() -> int:
	if drift_charge >= stats.drift_tier2_time:
		return 2
	if drift_charge >= stats.drift_tier1_time:
		return 1
	return 0


## Called every tick by wind streams the ship is inside.
func apply_wind(accel: Vector3, cap_bonus: float) -> void:
	_wind_accel += accel
	_wind_cap_bonus = maxf(_wind_cap_bonus, cap_bonus)


## Adds boost fuel (drift kicks now; pickups and augments later).
func add_fuel(amount: float) -> void:
	boost_fuel = clampf(boost_fuel + amount, 0.0, 1.0)


## Instant change of velocity, from blasts and other shoves.
func apply_impulse(delta_v: Vector3) -> void:
	velocity += Vector3(delta_v.x, 0.0, delta_v.z)


## Damage from shots, blasts and rams. Ignored without a Health child.
func take_damage(amount: float, source: Node = null) -> void:
	if not _alive or health == null:
		return
	if source is ShipController and source.team == team:
		return
	health.take_damage(amount, source)


func is_alive() -> bool:
	return _alive


## Brings a disabled (destroyed) ship back at `at` with full health.
func respawn(at: Vector3) -> void:
	global_position = Vector3(at.x, 0.0, at.z)
	velocity = Vector3.ZERO
	boost_fuel = 1.0
	_boosting = false
	is_drifting = false
	drift_charge = 0.0
	if health != null:
		health.reset()
	_set_alive(true)
	reset_physics_interpolation()


# --- Flight model ------------------------------------------------------------

func _steer(intent: ShipIntent, delta: float) -> void:
	if intent.steer == Vector3.ZERO:
		return
	var target_yaw := atan2(-intent.steer.x, -intent.steer.z)
	var turn_rate := deg_to_rad(stats.turn_rate_deg)
	if is_drifting:
		turn_rate *= stats.drift_turn_multiplier
	rotation.y = rotate_toward(rotation.y, target_yaw, turn_rate * delta)


func _apply_thrust(intent: ShipIntent, delta: float) -> void:
	var fwd := forward()
	var thrust := clampf(intent.thrust, 0.0, 1.0)
	if _boosting:
		velocity += fwd * stats.boost_acceleration * delta
	elif thrust > 0.05:
		# The engine only pushes up to cruising speed; anything above that
		# comes from boost, drift kicks or wind and bleeds off in
		# _apply_speed_cap.
		if velocity.dot(fwd) < stats.max_speed * thrust + _wind_cap_bonus:
			velocity += fwd * stats.acceleration * thrust * delta
	elif not is_drifting:
		# Drifts keep their momentum; otherwise the ship coasts to a stop.
		velocity *= exp(-stats.coast_drag * delta)

	if intent.brake > 0.05:
		velocity *= exp(-stats.brake_drag * intent.brake * delta)
	velocity += _wind_accel * delta


func _update_boost(intent: ShipIntent, delta: float) -> void:
	_kick_time_left = maxf(_kick_time_left - delta, 0.0)
	if not intent.boost_held:
		_boost_locked = false

	var wants_boost := intent.boost_held and not _boost_locked
	if _boosting:
		boost_fuel = maxf(boost_fuel - stats.boost_drain_rate * delta, 0.0)
		if boost_fuel <= 0.0:
			_boost_locked = true
			_stop_boost()
		elif not wants_boost:
			_stop_boost()
	elif wants_boost and boost_fuel >= stats.boost_min_start_fuel:
		_boosting = true
		_rammed_this_boost.clear()
		velocity += forward() * stats.boost_kick
		boost_started.emit()

	if _boosting:
		_recharge_wait = stats.boost_recharge_delay
	elif _recharge_wait > 0.0:
		_recharge_wait -= delta
	else:
		boost_fuel = minf(boost_fuel + stats.boost_recharge_rate * delta, 1.0)


func _stop_boost() -> void:
	_boosting = false
	boost_ended.emit()


func _update_drift(intent: ShipIntent, delta: float) -> void:
	if intent.drift_held and (is_drifting or speed() >= stats.drift_min_speed):
		is_drifting = true
		# Charge only builds while actually sliding, not just holding the button.
		if _slip_angle_deg() >= stats.drift_charge_min_angle_deg and speed() >= stats.drift_min_speed * 0.5:
			drift_charge += delta
		return

	if is_drifting:
		_release_drift()
	is_drifting = false
	drift_charge = 0.0


## Drift released: snap the momentum onto the nose and kick by charge tier.
func _release_drift() -> void:
	var tier := drift_tier()
	if tier == 0:
		return
	var kick := stats.drift_tier2_kick if tier == 2 else stats.drift_tier1_kick
	var fuel := stats.drift_tier2_fuel if tier == 2 else stats.drift_tier1_fuel
	# Like a slingshot: keep the speed you carried, but send it where the nose
	# points now, plus the kick.
	velocity = forward() * (speed() + kick)
	_kick_time_left = stats.drift_kick_duration
	add_fuel(fuel)
	drift_kicked.emit(tier)


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
	var cap := stats.boost_max_speed if is_fast() else stats.max_speed
	cap += _wind_cap_bonus
	var spd := speed()
	if spd > cap:
		var new_speed := lerpf(spd, cap, 1.0 - exp(-stats.overspeed_drag * delta))
		velocity = velocity * (new_speed / spd)


## Angle in degrees between the hull's nose and its actual travel direction.
func _slip_angle_deg() -> float:
	if speed() < 0.5:
		return 0.0
	var vel_dir := Vector3(velocity.x, 0.0, velocity.z).normalized()
	return rad_to_deg(forward().angle_to(vel_dir))


func _handle_ram_collisions() -> void:
	if not _boosting:
		return
	for i in get_slide_collision_count():
		var target := get_slide_collision(i).get_collider() as Node
		if target == null or target in _rammed_this_boost:
			continue
		if target is ShipController and target.team == team:
			continue
		if target.has_method("take_damage"):
			_rammed_this_boost.append(target)
			target.take_damage(stats.ram_damage, self)
			rammed.emit(target)


func _update_visuals(delta: float) -> void:
	if turret != null:
		turret.global_rotation.y = atan2(-aim_direction.x, -aim_direction.z)
	if visual_root == null:
		return
	# Lean into the turn and swing the nose further into it than the physics
	# heading, so drifts read clearly from the high camera. Sliding right
	# means the nose is turned left of travel, so both go positive.
	var right := forward().cross(Vector3.UP)
	var lateral := clampf(velocity.dot(right) / maxf(stats.max_speed, 1.0), -1.0, 1.0)
	var bank := deg_to_rad(45.0 if is_drifting else 22.0)
	var swing := deg_to_rad(18.0) if is_drifting else 0.0
	var blend := 1.0 - exp(-8.0 * delta)
	visual_root.rotation.z = lerpf(visual_root.rotation.z, lateral * bank, blend)
	visual_root.rotation.y = lerpf(visual_root.rotation.y, lateral * swing, blend)


# --- Damage, death and cargo -----------------------------------------------------

func _on_died(_source: Node) -> void:
	if death_explosion != null:
		var boom := death_explosion.instantiate() as Node3D
		get_parent().add_child(boom)
		boom.global_position = global_position
	_set_alive(false)
	destroyed.emit(self)
	if free_on_death:
		queue_free()


func _set_alive(alive: bool) -> void:
	_alive = alive
	visible = alive
	# Layers are kept in the scene; toggling the shape keeps them intact.
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", not alive)
	if not alive:
		velocity = Vector3.ZERO
		if _boosting:
			_stop_boost()


## Throws the last cargo slot out behind the ship.
func _jettison() -> void:
	jettison_slot(cargo.slots.size() - 1)


## Throws cargo slot `index` out behind the ship (from the ship screen too).
func jettison_slot(index: int) -> void:
	if jettison_pickup == null or cargo == null:
		return
	var slot := cargo.take_slot(index)
	if slot.is_empty():
		return
	for p in Pickup.scatter(jettison_pickup, get_parent(), slot.item, slot.count, global_position - forward() * 2.5, -forward(), 7.0):
		p.velocity += velocity * 0.5
		p.pickup_delay = 2.0


func _find_weapon(slot: ShipWeapon.Slot) -> ShipWeapon:
	for child in get_children():
		if child is ShipWeapon and child.slot == slot:
			return child
	return null
