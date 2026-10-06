class_name RiftCamera
extends Camera3D
## Tilted top-down camera with a fixed rotation (League of Legends style),
## tuned for a fast ship:
## - Look-ahead: the view leads toward where the ship is going and aiming.
## - Speed zoom: pulls back with speed and further while boosting.
## - Light screen shake for impacts and boosts.
##
## The camera only reads the target's position, velocity and aim. It never
## touches gameplay state, so split-screen or a shared co-op camera can
## reuse it later.

## Ship to follow. Reads `velocity`, `aim_direction` and `is_fast()`.
@export var target: ShipController

@export_group("Framing")
## Downward tilt in degrees (90 = straight down).
@export_range(30.0, 89.0) var pitch_deg: float = 58.0
## Distance from the focus point at rest, in metres.
@export var base_distance: float = 34.0
## How quickly the camera catches up to the focus point.
@export var follow_smoothing: float = 7.0

@export_group("Look-ahead")
## Seconds of travel to lead by (focus moves to where the ship will be).
@export var velocity_lead_time: float = 0.35
## Metres to lead toward the aim direction.
@export var aim_lead_distance: float = 5.0
## Cap on the total lead, in metres.
@export var max_lead: float = 11.0
@export var lead_smoothing: float = 3.5

@export_group("Zoom")
## Extra distance at full cruising speed, as a fraction of base_distance.
@export var speed_zoom: float = 0.12
## Extra distance while boosting, as a fraction of base_distance.
@export var boost_zoom: float = 0.16
@export var zoom_smoothing: float = 2.5

@export_group("Shake")
@export var max_shake_offset: float = 0.6
@export var shake_decay: float = 2.2

var _focus: Vector3 = Vector3.ZERO
var _lead: Vector3 = Vector3.ZERO
var _distance: float = 0.0
var _trauma: float = 0.0


func _ready() -> void:
	top_level = true
	rotation = Vector3(-deg_to_rad(pitch_deg), 0.0, 0.0)
	_distance = base_distance
	if target != null:
		_focus = target.global_position
		target.boost_started.connect(func(): add_shake(0.2))
		target.drift_kicked.connect(func(tier): add_shake(0.2 + 0.15 * tier))
		target.rammed.connect(func(_t): add_shake(0.5))
		target.damaged.connect(func(amount, _s): add_shake(clampf(amount / 40.0, 0.1, 0.6)))
	_apply_transform(Vector3.ZERO)


## Adds screen shake. 0.2 is a nudge, 1.0 is a big hit.
func add_shake(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var desired_lead := target.velocity * velocity_lead_time + target.aim_direction * aim_lead_distance
	desired_lead.y = 0.0
	desired_lead = desired_lead.limit_length(max_lead)
	_lead = _lead.lerp(desired_lead, 1.0 - exp(-lead_smoothing * delta))

	var desired_focus := target.global_position + _lead
	_focus = _focus.lerp(desired_focus, 1.0 - exp(-follow_smoothing * delta))

	var speed_frac := clampf(target.speed() / maxf(target.stats.max_speed, 1.0), 0.0, 1.5)
	var desired_distance := base_distance * (1.0 + speed_zoom * speed_frac)
	if target.is_fast():
		desired_distance += base_distance * boost_zoom
	_distance = lerpf(_distance, desired_distance, 1.0 - exp(-zoom_smoothing * delta))

	var shake := Vector3.ZERO
	if _trauma > 0.0:
		var strength := _trauma * _trauma * max_shake_offset
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * strength
		_trauma = maxf(_trauma - shake_decay * delta, 0.0)

	_apply_transform(shake)


func _apply_transform(shake: Vector3) -> void:
	rotation = Vector3(-deg_to_rad(pitch_deg), 0.0, 0.0)
	# The camera's local +Z points back along its view, so stepping out along
	# it keeps the focus point centred.
	global_position = _focus + global_transform.basis.z * _distance + global_transform.basis * shake
