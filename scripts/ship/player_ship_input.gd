class_name PlayerShipInput
extends Node
## Turns local mouse, keyboard and gamepad input into a ShipIntent.
##
## Control scheme (twin-stick):
## - WASD / left stick: the direction to fly. The nose turns toward it and
##   the engine pushes, so a light stick push is a light throttle.
## - Mouse / right stick: aim the cannon anywhere, independent of flight.
## - Ctrl / LT brakes. Left click / RT fires the cannon, right click / RB
##   fires a torpedo, X / gamepad X jettisons the last cargo slot.
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
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move.length() > 0.1:
		# Camera has a fixed yaw of 0, so screen-up is world -Z.
		intent.steer = Vector3(move.x, 0.0, move.y).normalized()
		intent.thrust = clampf(move.length(), 0.0, 1.0)
	intent.brake = Input.get_action_strength("brake")
	intent.boost_held = Input.is_action_pressed("boost")
	intent.drift_held = Input.is_action_pressed("drift")
	intent.fire_held = Input.is_action_pressed("fire")
	intent.heavy_held = Input.is_action_pressed("fire_heavy")
	intent.jettison = Input.is_action_just_pressed("jettison")
	_read_aim(ship, intent)
	return intent


func _read_aim(ship: Node3D, intent: ShipIntent) -> void:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() >= stick_aim_threshold:
		_using_mouse_aim = false
		intent.aim = Vector3(stick.x, 0.0, stick.y).normalized()
		return
	if not _using_mouse_aim:
		return # Stick released: ZERO keeps the last aim.
	var to_cursor := _cursor_offset(ship)
	var dist := to_cursor.length()
	if dist > 0.5:
		intent.aim = to_cursor / dist
		intent.aim_distance = dist


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
