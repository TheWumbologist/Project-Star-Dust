class_name PlayerShipInput
extends Node
## Turns local mouse, keyboard and gamepad input into a ShipIntent.
##
## Aim follows whichever device was touched last: moving the mouse switches
## to cursor aim, pushing the right stick switches to stick aim.

## Right-stick deflection needed before stick aim takes over from the mouse.
@export var stick_aim_threshold: float = 0.3

var _using_mouse_aim: bool = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_using_mouse_aim = true


## Builds this tick's intent for `ship`. Called by ShipController.
func get_intent(ship: Node3D) -> ShipIntent:
	var intent := ShipIntent.new()
	intent.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	intent.boost_pressed = Input.is_action_just_pressed("boost")
	intent.drift_held = Input.is_action_pressed("drift")
	intent.fire_held = Input.is_action_pressed("fire")
	intent.grapple_pressed = Input.is_action_just_pressed("grapple")
	intent.aim = _read_aim(ship)
	return intent


func _read_aim(ship: Node3D) -> Vector3:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() >= stick_aim_threshold:
		_using_mouse_aim = false
		# Camera has a fixed yaw of 0, so screen-up is world -Z.
		return Vector3(stick.x, 0.0, stick.y).normalized()

	if _using_mouse_aim:
		return _mouse_aim(ship)

	# Stick released: keep the last aim (ZERO tells the ship to hold it).
	return Vector3.ZERO


## Projects the cursor onto the ship's flight plane and aims at that point.
func _mouse_aim(ship: Node3D) -> Vector3:
	var viewport := ship.get_viewport()
	var camera := viewport.get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	var mouse := viewport.get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, ship.global_position.y)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return Vector3.ZERO
	var to_cursor: Vector3 = hit - ship.global_position
	to_cursor.y = 0.0
	if to_cursor.length() < 0.5:
		return Vector3.ZERO
	return to_cursor.normalized()
