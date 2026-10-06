extends SceneTree
## Headless smoke test for the flight test arena.
##
## Loads the real scene, swaps the player's input for scripted intents and
## checks that thrust, steering, boost, drift kicks, shooting, wind, the aim
## reticle and the camera all behave. Run from the project folder:
##   godot --headless --script res://tests/smoke_test.gd
## Exit code 0 = all checks passed.

const SCENE := "res://scenes/test/flight_test.tscn"
const ScriptedInput := preload("res://tests/scripted_input.gd")

var _failures: PackedStringArray = []
var _input: ScriptedInput


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
	await _test_steering(ship)
	await _test_boost(ship)
	await _test_drift(ship)
	await _test_shooting(ship, level)
	await _test_reticle(ship)
	await _test_wind(ship)
	await _test_camera(ship, camera)

	# Let the audio server release playing sounds before quitting.
	Sfx.stop_all()
	await create_timer(0.2, true, false, true).timeout
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
	await _frames(30)
	_check(ship.speed() < 0.1, "ship sits still with no thrust")
	_input.thrust = 1.0
	await _frames(60)
	_check(ship.global_position.z < -5.0, "thrust pushes the ship along its nose (z=%.2f)" % ship.global_position.z)
	_check(ship.speed() > 15.0, "ship reaches cruising speed (%.1f m/s)" % ship.speed())
	_check(ship.speed() <= ship.stats.max_speed + 0.5, "cruise speed respects the cap (%.1f)" % ship.speed())
	_check(absf(ship.global_position.y) < 0.01, "ship stays on the flight plane")
	_input.thrust = 0.0
	_input.brake = 1.0
	await _frames(60)
	_check(ship.speed() < 1.0, "brake stops the ship (%.1f m/s)" % ship.speed())
	_input.reset()


func _test_steering(ship: ShipController) -> void:
	_place(ship, Vector3.ZERO)
	_input.steer = Vector3.RIGHT
	await _frames(5)
	_check(ship.speed() < 0.1, "steering alone turns without moving")
	await _frames(40)
	_check(ship.forward().dot(Vector3.RIGHT) > 0.99, "nose turns to the steering direction")
	_input.thrust = 1.0
	await _frames(40)
	_check(ship.velocity.x > 10.0, "thrust follows the new heading (vx %.1f)" % ship.velocity.x)
	_input.reset()


func _test_boost(ship: ShipController) -> void:
	_place(ship, Vector3(0, 0, 40))
	_input.thrust = 1.0
	await _frames(60)
	_input.boost = true
	await _frames(20)
	_check(ship.is_boosting(), "boost burns while held")
	_check(ship.speed() > ship.stats.max_speed + 5.0, "boost exceeds cruise speed (%.1f)" % ship.speed())
	var fuel_mid := ship.boost_fuel
	await _frames(20)
	_check(ship.boost_fuel < fuel_mid, "holding boost keeps draining fuel")
	_input.boost = false
	await _frames(2)
	_check(not ship.is_boosting(), "releasing the button ends boost early")
	_input.boost = true
	await _frames(2)
	var frames := 0
	while ship.is_boosting() and frames < 600:
		await physics_frame
		frames += 1
	_check(not ship.is_boosting() and ship.boost_fuel <= 0.01, "boost cuts out when the tank is empty (fuel %.2f)" % ship.boost_fuel)
	await _frames(120)
	_check(not ship.is_boosting(), "boost stays off until the button is pressed again")
	_input.boost = false
	await _frames(90)
	_check(ship.speed() <= ship.stats.max_speed + 1.0, "speed settles back to the cap (%.1f)" % ship.speed())
	_check(ship.boost_fuel > 0.0, "fuel recharges after boosting")
	_input.reset()


func _test_drift(ship: ShipController) -> void:
	_place(ship, Vector3(0, 0, 60))
	ship.boost_fuel = 0.2
	_input.thrust = 1.0
	_input.steer = Vector3.FORWARD
	await _frames(60)
	var tiers: Array[int] = []
	var on_kick := func(tier: int): tiers.append(tier)
	ship.drift_kicked.connect(on_kick)
	# Hold drift and swing the nose sideways: the ship slides and charges.
	_input.drift = true
	_input.steer = Vector3.RIGHT
	await _frames(20)
	_check(ship.is_drifting, "drift engages at speed")
	var lateral := absf(ship.velocity.dot(ship.forward().cross(Vector3.UP)))
	_check(lateral > 8.0, "drifting slides sideways (%.1f m/s)" % lateral)
	await _frames(70)
	_check(ship.drift_tier() == 2, "a long slide charges to tier 2 (charge %.2fs)" % ship.drift_charge)
	var speed_before := ship.speed()
	_input.drift = false
	await _frames(2)
	ship.drift_kicked.disconnect(on_kick)
	_check(tiers == [2], "releasing a charged drift fires a tier 2 kick (%s)" % [tiers])
	_check(ship.speed() > speed_before + 10.0, "drift kick adds speed (%.1f -> %.1f)" % [speed_before, ship.speed()])
	_check(ship.velocity.normalized().dot(ship.forward()) > 0.95, "drift kick sends the ship where the nose points")
	_check(ship.boost_fuel > 0.5, "drift kick refills boost fuel (%.2f)" % ship.boost_fuel)
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


func _test_reticle(ship: ShipController) -> void:
	var reticle := ship.get_node("AimReticle") as AimReticle
	_place(ship, Vector3(-20, 0, 0))
	_input.aim = Vector3.RIGHT
	_input.aim_distance = 9.0
	await _frames(3)
	await process_frame
	var expected := ship.global_position + Vector3.RIGHT * 9.0
	_check(reticle.ring.global_position.distance_to(expected) < 0.2, "reticle sits on the cursor point")
	_input.aim_distance = 0.0
	_input.aim = Vector3.BACK
	await _frames(3)
	await process_frame
	expected = ship.global_position + Vector3.BACK * reticle.stick_distance
	_check(reticle.ring.global_position.distance_to(expected) < 0.2, "stick aim puts the reticle a fixed distance out")
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
	_input.thrust = 1.0
	await _frames(40)
	_input.boost = true
	await _frames(30)
	var boosting := camera.global_position.distance_to(ship.global_position)
	_check(boosting > resting + 2.0, "camera pulls back at speed (%.1f -> %.1f)" % [resting, boosting])
	_input.reset()


# --- Helpers -----------------------------------------------------------------

func _place(ship: ShipController, pos: Vector3) -> void:
	ship.global_position = pos
	ship.velocity = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	ship.boost_fuel = 1.0
	_input.reset()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
