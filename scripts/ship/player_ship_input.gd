class_name PlayerShipInput
extends Node
## Turns local mouse, keyboard and gamepad input into a ShipIntent.
##
## Control scheme: one thrust button pushes the ship along its nose, and the
## nose turns toward where you point.
## - Mouse + keyboard: the nose turns toward the cursor, and the cannon fires
##   at the cursor. W thrusts, S brakes.
## - Gamepad: the left stick points the nose, the right stick aims the
##   cannon. RT thrusts, LT brakes.
## Whichever device was touched last is in charge of steering and aim.

## Stick deflection needed before stick steering or aim takes over.
@export var stick_threshold: float = 0.3
## The cursor must be at least this far from the ship to steer toward it,
## so the ship doesn't spin when the cursor sits on top of it.
@export var mouse_steer_dead_radius: float = 2.0

var _using_mouse: bool = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		_using_mouse = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > stick_threshold:
		_using_mouse = false
	elif event is InputEventJoypadButton:
		_using_mouse = false


func is_using_mouse() -> bool:
	return _using_mouse


## Builds this tick's intent for `ship`. Called by ShipController.
func get_intent(ship: Node3D) -> ShipIntent:
	var intent := ShipIntent.new()
	intent.thrust = Input.get_action_strength("thrust")
	intent.brake = Input.get_action_strength("brake")
	intent.boost_held = Input.is_action_pressed("boost")
	intent.drift_held = Input.is_action_pressed("drift")
	intent.fire_held = Input.is_action_pressed("fire")

	var steer_stick := Input.get_vector("steer_left", "steer_right", "steer_up", "steer_down")
	var aim_stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if steer_stick.length() >= stick_threshold or aim_stick.length() >= stick_threshold:
		_using_mouse = false

	if _using_mouse:
		var to_cursor := _cursor_offset(ship)
		var dist := to_cursor.length()
		if dist > 0.01:
			intent.aim = to_cursor / dist
			intent.aim_distance = dist
		if dist >= mouse_steer_dead_radius:
			intent.steer = to_cursor / dist
	else:
		# Camera has a fixed yaw of 0, so screen-up is world -Z.
		if steer_stick.length() >= stick_threshold:
			intent.steer = Vector3(steer_stick.x, 0.0, steer_stick.y).normalized()
		if aim_stick.length() >= stick_threshold:
			intent.aim = Vector3(aim_stick.x, 0.0, aim_stick.y).normalized()
	return intent


## Vector from the ship to the cursor's point on the ship's flight plane.
func _cursor_offset(ship: Node3D) -> Vector3:
	var viewport := ship.get_viewport()
	var camera := viewport.get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	var mouse := viewport.get_mouse_position()
	var plane := Plane(Vector3.UP, ship.global_position.y)
	var hit = plane.intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit == null:
		return Vector3.ZERO
	var offset: Vector3 = hit - ship.global_position
	offset.y = 0.0
	return offset
