class_name SniperPilot
extends AIPilot
## Corsair Lancer: hangs back at long range. When it has a clear shot it
## stops, shows a red aim line while the lance charges, and fires one fast,
## heavy shot down that line. The line only creeps after a moving target,
## so changing course (or boosting) during the charge dodges it. Between
## shots it slides round to a new angle.

## Seconds the aim line shows before the shot.
@export var charge_time: float = 1.1
## How fast the line follows the target while charging, degrees per second.
@export var track_rate_deg: float = 22.0
## Seconds between shots.
@export var reload_time: float = 2.6
## Length of the aim line, metres.
@export var line_length: float = 48.0
@export var line_color: Color = Color(1.0, 0.15, 0.1, 0.55)

## Seconds left on the current charge, or < 0 when not charging.
var charge_left: float = -1.0

var _reload: float = 1.0
var _locked_aim: Vector3 = Vector3.FORWARD
var _line: MeshInstance3D
var _line_material: StandardMaterial3D


func _ready() -> void:
	super()
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_material.albedo_color = line_color
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.05, 1.0)
	mesh.material = _line_material
	_line = MeshInstance3D.new()
	_line.name = "AimLine"
	_line.mesh = mesh
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.top_level = true
	_line.visible = false
	add_child(_line)


func _fly(me: ShipController, intent: ShipIntent, delta: float) -> void:
	var dist := _distance(me)
	var dir := _direction(me)
	_reload = maxf(_reload - delta, 0.0)
	if charge_left >= 0.0:
		_charge(me, intent, delta)
		return
	_hold_range(me, intent, dir, dist, preferred_range, orbit_bias)
	intent.steer = _avoid(me, intent.steer)
	_aim_with_lead(me, intent, shot_speed)
	if _reload <= 0.0 and dist <= fire_range and _can_see(me, target):
		charge_left = charge_time
		_locked_aim = intent.aim
		Sfx.play(&"charge", me.global_position)


func _idle(me: ShipController, intent: ShipIntent, delta: float) -> void:
	_reload = maxf(_reload - delta, 0.0)
	if charge_left >= 0.0:
		# Target gone mid-charge: let the shot go anyway.
		_charge(me, intent, delta)


## Holds still, creeps the line after the target and fires when charged.
func _charge(me: ShipController, intent: ShipIntent, delta: float) -> void:
	charge_left -= delta
	intent.brake = 1.0
	if target != null:
		var want := _lead_point(me, shot_speed) - me.global_position
		want.y = 0.0
		if want.length() > 0.1:
			var turn := clampf(_locked_aim.signed_angle_to(want.normalized(), Vector3.UP), -1.0, 1.0) * deg_to_rad(track_rate_deg) * delta
			_locked_aim = _locked_aim.rotated(Vector3.UP, turn).normalized()
	intent.aim = _locked_aim
	_show_line(me, 1.0 - charge_left / charge_time)
	if charge_left <= 0.0:
		intent.fire_held = true
		charge_left = -1.0
		_reload = reload_time
		_orbit_sign = -_orbit_sign # Reposition the other way.
		_line.visible = false


func _show_line(me: ShipController, progress: float) -> void:
	_line.visible = true
	var start := me.global_position + Vector3(0.0, 0.3, 0.0)
	_line.global_transform = Transform3D(Basis.looking_at(_locked_aim, Vector3.UP), start + _locked_aim * line_length * 0.5)
	# Thin and faint at first, thicker and brighter as the shot gets close.
	_line.scale = Vector3(lerpf(0.4, 1.6, progress), 1.0, line_length)
	_line_material.albedo_color.a = lerpf(0.2, 0.85, progress)

