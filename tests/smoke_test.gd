extends SceneTree
## Headless smoke test for the flight test arena.
##
## Loads the real scene, swaps the player's input for scripted intents and
## checks that thrust, boost, drift, shooting, grapple, wind and the camera
## all behave. Run from the project folder:
##   godot --headless --script res://tests/smoke_test.gd
## Exit code 0 = all checks passed.

const SCENE := "res://scenes/test/flight_test.tscn"

var _failures: PackedStringArray = []
var _input: ScriptedInput


## Stands in for PlayerShipInput: returns whatever intent the test sets.
class ScriptedInput extends Node:
	var move := Vector2.ZERO
	var aim := Vector3.ZERO
	var drift := false
	var fire := false
	var _boost_once := false
	var _grapple_once := false

	func press_boost() -> void:
		_boost_once = true

	func press_grapple() -> void:
		_grapple_once = true

	func get_intent(_ship: Node3D) -> ShipIntent:
		var intent := ShipIntent.new()
		intent.move = move
		intent.aim = aim
		intent.drift_held = drift
		intent.fire_held = fire
		intent.boost_pressed = _boost_once
		intent.grapple_pressed = _grapple_once
		_boost_once = false
		_grapple_once = false
		return intent

	func reset() -> void:
		move = Vector2.ZERO
		aim = Vector3.ZERO
		drift = false
		fire = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level: Node3D = load(SCENE).instantiate()
	root.add_child(level)
	current_scene = level
	await physics_frame

	var ship := level.get_node("PlayerShip") as ShipController
	var camera := level.get_node("RiftCamera") as RiftCamera
	_input = ScriptedInput.new()
	ship.add_child(_input)
	ship.input_source = _input

	await _test_thrust(ship)
	await _test_boost(ship)
	await _test_drift(ship)
	await _test_shooting(ship, level)
	await _test_grapple(ship, level)
	await _test_wind(ship)
	await _test_camera(ship, camera)

	if _failures.is_empty():
		print("SMOKE TEST: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("SMOKE TEST FAIL: ", f)
		quit(1)


# --- Checks ------------------------------------------------------------------

func _test_thrust(ship: ShipController) -> void:
	_place(ship, Vector3.ZERO)
	_input.move = Vector2(0, -1)
	await _frames(60)
	_check(ship.global_position.z < -5.0, "thrust up moves the ship north (z=%.2f)" % ship.global_position.z)
	_check(ship.speed() > 12.0, "ship reaches cruising speed (%.1f m/s)" % ship.speed())
	_check(ship.speed() <= ship.stats.max_speed + 0.5, "cruise speed respects the cap (%.1f)" % ship.speed())
	_check(absf(ship.global_position.y) < 0.01, "ship stays on the flight plane")


func _test_boost(ship: ShipController) -> void:
	var meter_before := ship.boost_meter
	_input.press_boost()
	await _frames(3)
	_check(ship.is_boosting(), "boost activates")
	_check(ship.boost_meter < meter_before, "boost spends meter")
	_check(ship.speed() > ship.stats.max_speed + 5.0, "boost exceeds cruise speed (%.1f)" % ship.speed())
	await _frames(90)
	_check(not ship.is_boosting(), "boost wears off")
	_check(ship.speed() <= ship.stats.max_speed + 1.0, "speed settles back to the cap (%.1f)" % ship.speed())


func _test_drift(ship: ShipController) -> void:
	_place(ship, Vector3(0, 0, 60))
	ship.boost_meter = 0.2
	_input.move = Vector2(0, -1)
	await _frames(60)
	var got_perfect := [false]
	var on_perfect := func(): got_perfect[0] = true
	ship.perfect_drift.connect(on_perfect)
	# Hold drift and swing the stick sideways: the nose turns, the ship slides.
	_input.drift = true
	_input.move = Vector2(1, 0)
	await _frames(50)
	_check(ship.is_drifting, "drift engages at speed")
	_input.drift = false
	await _frames(2)
	ship.perfect_drift.disconnect(on_perfect)
	_check(got_perfect[0], "a long sliding drift counts as perfect")
	_check(ship.boost_meter > 0.5, "perfect drift refills boost (%.2f)" % ship.boost_meter)
	_input.reset()


func _test_shooting(ship: ShipController, level: Node) -> void:
	var dummy := level.get_node("Targets/Dummy01") as TargetDummy
	_place(ship, dummy.global_position + Vector3(0, 0, 14))
	_input.aim = Vector3(0, 0, -1)
	_input.fire = true
	await _frames(20)
	_check(dummy.health < dummy.max_health, "cannon shots damage a target (hp %.0f)" % dummy.health)
	await _frames(60)
	_check(not dummy.is_alive(), "sustained fire breaks the target")
	_input.reset()
	await _frames(int(dummy.respawn_time * 60.0) + 10)
	_check(dummy.is_alive() and dummy.health == dummy.max_health, "target respawns at full health")


func _test_grapple(ship: ShipController, level: Node) -> void:
	var asteroid := level.get_node("Asteroids/Asteroid01") as Asteroid
	var start := asteroid.global_position + Vector3(asteroid.anchor_radius + 8.0, 0, 0)
	_place(ship, start)
	_input.aim = Vector3(-1, 0, 0)
	_input.press_grapple()
	await _frames(2)
	_check(ship.grapple.is_attached(), "grapple latches onto an asteroid in the aim cone")
	var rope := ship.grapple.rope_length
	ship.velocity = Vector3(0, 0, -18)
	var max_dist := 0.0
	for i in 60:
		await physics_frame
		var d := Vector2(ship.global_position.x - asteroid.global_position.x,
				ship.global_position.z - asteroid.global_position.z).length()
		max_dist = maxf(max_dist, d)
	_check(max_dist < rope + 1.5, "rope holds the ship in orbit (max %.1f, rope %.1f)" % [max_dist, rope])
	_check(ship.speed() > 10.0, "swinging keeps momentum (%.1f m/s)" % ship.speed())
	_input.press_grapple()
	await _frames(2)
	_check(not ship.grapple.is_attached(), "grapple releases on second press")
	_input.reset()


func _test_wind(ship: ShipController) -> void:
	var stream := root.get_node("FlightTest/WindStreams/WindNorth") as WindStream
	_place(ship, stream.global_position + Vector3(0, 0, 40))
	await _frames(60)
	_check(ship.velocity.z < -8.0, "wind stream pushes the ship along it (vz %.1f)" % ship.velocity.z)


func _test_camera(ship: ShipController, camera: RiftCamera) -> void:
	_place(ship, Vector3(-30, 0, 30))
	await _frames(120)
	var cam_forward := -camera.global_transform.basis.z
	var pitch := rad_to_deg(asin(-cam_forward.y))
	_check(absf(pitch - camera.pitch_deg) < 1.0, "camera keeps its fixed tilt (%.1f deg)" % pitch)
	var on_screen := not camera.is_position_behind(ship.global_position)
	var screen := camera.unproject_position(ship.global_position)
	var size := camera.get_viewport().get_visible_rect().size
	_check(on_screen and Rect2(Vector2.ZERO, size).has_point(screen), "ship is on screen (%s)" % screen)
	var resting := camera.global_position.distance_to(ship.global_position)
	_input.move = Vector2(1, 0)
	await _frames(40)
	_input.press_boost()
	await _frames(20)
	var boosting := camera.global_position.distance_to(ship.global_position)
	_check(boosting > resting + 2.0, "camera pulls back at speed (%.1f -> %.1f)" % [resting, boosting])
	_input.reset()


# --- Helpers -----------------------------------------------------------------

func _place(ship: ShipController, pos: Vector3) -> void:
	ship.global_position = pos
	ship.velocity = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	if ship.grapple != null:
		ship.grapple.release()
	_input.reset()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
