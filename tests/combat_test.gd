extends SceneTree
## Headless smoke test for the combat and mining arena (milestone 2).
##
## Loads the real arena with the wave director paused, swaps the player's
## input for scripted intents, and checks mining, cargo, both weapons, both
## enemy types, shields, death and respawn, and waves. Run from the project
## folder:
##   godot --headless --script res://tests/combat_test.gd
## Exit code 0 = all checks passed.

const SCENE := "res://scenes/test/combat_test.tscn"
const ScriptedInput := preload("res://tests/scripted_input.gd")
const DRONE := preload("res://scenes/enemies/scavenger_drone.tscn")
const CUTTER := preload("res://scenes/enemies/pirate_cutter.tscn")
const PICKUP := preload("res://scenes/cargo/pickup.tscn")
const ORE := preload("res://resources/items/ore.tres")
const SCRAP := preload("res://resources/items/scrap.tres")

var _failures: PackedStringArray = []
var _input: ScriptedInput
var _level: Node3D
var _ship: ShipController
var _director: EncounterDirector


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_level = load(SCENE).instantiate()
	_director = _level.get_node("EncounterDirector") as EncounterDirector
	_director.auto_start = false
	root.add_child(_level)
	current_scene = _level
	await physics_frame

	_ship = _level.get_node("PlayerShip") as ShipController
	_input = ScriptedInput.new()
	_ship.add_child(_input)
	_ship.input_source = _input

	await _test_setup()
	await _test_mining()
	await _test_torpedo()
	await _test_drone()
	await _test_cutter()
	await _test_cargo_limits()
	await _test_death()
	await _test_waves()

	# Let the audio server release playing sounds before quitting.
	Sfx.stop_all()
	await create_timer(1.0, true, false, true).timeout
	if _failures.is_empty():
		print("COMBAT TEST: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("COMBAT TEST FAIL: ", f)
		quit(1)


# --- Checks ------------------------------------------------------------------

func _test_setup() -> void:
	_check(_ship.health != null and _ship.cargo != null, "player ship has hull, shields and a cargo hold")
	_check(_ship.primary != null and _ship.heavy != null, "player ship has a cannon and a torpedo tube")
	var ore_rocks := _ore_rocks()
	_check(ore_rocks.size() == 10, "arena scatters 10 ore asteroids (%d)" % ore_rocks.size())
	var clear := true
	for rock in _level.get_node("Asteroids").get_children():
		if rock is Asteroid and rock.global_position.length() < 18.0:
			clear = false
	_check(clear, "spawn area is clear of asteroids")


func _test_mining() -> void:
	var rock := _nearest_ore_rock()
	var ore_start := rock.ore_left
	var dir := Vector3.BACK
	_place(rock.global_position + dir * (rock.radius + 7.0))
	_input.aim = -dir
	_input.fire = true
	await _frames(45)
	_input.fire = false
	_check(rock.ore_left < ore_start, "cannon fire chips ore off an asteroid (%d -> %d)" % [ore_start, rock.ore_left])
	_check(Sfx.history.has(&"cannon") and Sfx.history.has(&"rock_chip"), "the cannon and chipped rocks make sounds")
	await _frames(120)
	_check(_ship.cargo.count_of(ORE) > 0, "loose ore gets pulled into the hold (%d ore)" % _ship.cargo.count_of(ORE))
	# Keep firing until the rock is mined out.
	_input.fire = true
	for i in 600:
		await physics_frame
		if not is_instance_valid(rock):
			break
	_input.fire = false
	_check(not is_instance_valid(rock), "a mined-out asteroid crumbles")
	await _frames(120)
	_check(_ship.cargo.count_of(ORE) >= ore_start - 2, "most of the rock's ore ends up in the hold (%d of %d)" % [_ship.cargo.count_of(ORE), ore_start])
	_ship.cargo.clear()
	_clear_pickups()


func _test_torpedo() -> void:
	_place(Vector3.ZERO)
	var drone := _director.spawn_now(DRONE, Vector3(0, 0, -20))
	drone.input_source = null # Hold still as a target.
	await _frames(2)
	var charges := _ship.heavy.charges
	_input.aim = Vector3.FORWARD
	_input.aim_distance = 20.0
	_input.heavy = true
	await _frames(2)
	_input.heavy = false
	_check(_ship.heavy.charges == charges - 1, "firing a torpedo uses a charge (%d -> %d)" % [charges, _ship.heavy.charges])
	await _frames(60)
	_check(not is_instance_valid(drone) or not drone.is_alive(), "a torpedo blast destroys a drone")
	_check(Sfx.history.has(&"torpedo") and Sfx.history.has(&"explosion_small"), "torpedoes and blasts make sounds")
	# Blast shoves ships: a cutter survives the hit but gets pushed.
	var cutter := _director.spawn_now(CUTTER, Vector3(4, 0, -20))
	cutter.input_source = null
	await _frames(int(_ship.heavy.charge_time * 60.0) + 5)
	_check(_ship.heavy.charges >= 1, "torpedo charges refill over time")
	var before := cutter.global_position
	_input.aim = (Vector3(3, 0, -20)).normalized()
	_input.aim_distance = Vector3(3, 0, -20).length()
	_input.heavy = true
	await _frames(2)
	_input.heavy = false
	await _frames(50)
	_check(cutter.health.shield < cutter.health.max_shield, "the blast hits the cutter's shield")
	_check(cutter.global_position.distance_to(before) > 1.0, "the blast knocks the cutter back (%.1f m)" % cutter.global_position.distance_to(before))
	cutter.queue_free()
	await _frames(2)
	_input.reset()
	_clear_pickups()


func _test_drone() -> void:
	_place(Vector3.ZERO)
	_ship.health.reset()
	var drone := _director.spawn_now(DRONE, Vector3(0, 0, -30))
	var start := drone.global_position.distance_to(_ship.global_position)
	await _frames(150)
	var now := drone.global_position.distance_to(_ship.global_position)
	_check(now < start - 5.0, "a drone closes in on the player (%.0f -> %.0f m)" % [start, now])
	for i in 360:
		await physics_frame
		if _ship.health.shield < _ship.health.max_shield:
			break
	_check(_ship.health.shield < _ship.health.max_shield, "drone shots hit the player")
	_check(_ship.health.hull == _ship.health.max_hull, "shields soak hits before the hull")
	# Same-team fire does nothing.
	var hp := drone.health.hull
	drone.take_damage(10.0, drone)
	var other := _director.spawn_now(DRONE, Vector3(40, 0, 40))
	drone.take_damage(10.0, other)
	_check(drone.health.hull == hp, "enemies can't hurt each other")
	other.queue_free()
	# Shoot it down and collect the scrap.
	_input.fire = true
	for i in 600:
		if is_instance_valid(drone):
			# Lead the target like a player would.
			var to := drone.global_position - _ship.global_position
			var lead := drone.global_position + drone.velocity * (to.length() / _ship.primary.projectile_speed)
			_input.aim = (lead - _ship.global_position).normalized()
		await physics_frame
		if not is_instance_valid(drone):
			break
	_input.fire = false
	_check(not is_instance_valid(drone), "cannon fire destroys a drone")
	await _frames(5)
	var scrap := _pickups()
	_check(not scrap.is_empty(), "a destroyed drone drops scrap (%d)" % scrap.size())
	for p in scrap:
		if is_instance_valid(p):
			_place(p.global_position)
			await _frames(30)
	_check(_ship.cargo.count_of(SCRAP) > 0, "flying over scrap collects it")
	_check(Sfx.history.has(&"pickup") and Sfx.history.has(&"enemy_shot") and Sfx.history.has(&"hit_shield"), "pickups, enemy guns and shield hits make sounds")
	_ship.cargo.clear()


func _test_cutter() -> void:
	_place(Vector3.ZERO)
	_ship.health.reset()
	var cutter := _director.spawn_now(CUTTER, Vector3(0, 0, -25))
	await _frames(3)
	cutter.take_damage(30.0, _ship)
	_check(cutter.health.hull == cutter.health.max_hull and cutter.health.shield == 10.0, "cutter shields soak damage first")
	cutter.take_damage(20.0, _ship)
	_check(cutter.health.hull == cutter.health.max_hull - 10.0, "damage past the shield reaches the hull")
	await _frames(int((cutter.health.shield_regen_delay + 1.0) * 60.0))
	_check(cutter.health.shield > 0.0, "shields recharge after a quiet spell")
	cutter.take_damage(500.0, _ship)
	await _frames(2)
	_check(not is_instance_valid(cutter), "a cutter can be destroyed")
	await _frames(5)
	_check(_pickups().size() >= 4, "a cutter drops more scrap than a drone (%d)" % _pickups().size())
	_clear_pickups()


func _test_cargo_limits() -> void:
	var hold := _ship.cargo
	hold.clear()
	for i in hold.slot_count:
		hold.add(SCRAP if i % 2 == 0 else ORE, 1000)
	_check(hold.slots.size() == hold.slot_count, "hold fills up slot by slot")
	_check(not hold.has_room_for(ORE), "a full hold has no room")
	_place(Vector3.ZERO)
	var loose := PICKUP.instantiate() as Pickup
	loose.item = ORE
	_level.add_child(loose)
	loose.global_position = Vector3(0, 0, -1)
	await _frames(20)
	_check(is_instance_valid(loose), "a full hold leaves pickups floating")
	loose.queue_free()
	var before := hold.slots.size()
	_input.jettison = true
	await _frames(2)
	_check(hold.slots.size() == before - 1, "jettison throws out the last slot")
	_input.steer = Vector3.FORWARD
	_input.thrust = 1.0
	await _frames(40)
	_input.reset()
	_check(hold.slots.size() == before - 1, "jettisoned cargo doesn't fly straight back in")
	hold.clear()
	_clear_pickups()


func _test_death() -> void:
	_place(Vector3(10, 0, 10))
	_ship.cargo.add(ORE, 5)
	var ui := _level.get_node("GameUI") as GameUI
	var deaths: Array[int] = []
	_ship.destroyed.connect(func(_s): deaths.append(1))
	_ship.take_damage(10000.0, null)
	await _frames(2)
	_check(deaths.size() == 1 and not _ship.is_alive(), "losing all hull destroys the ship")
	await create_timer(ui.death_card_delay + 0.5).timeout
	_check(ui.end_screen.is_open and ui.end_screen.visible, "the death screen appears")
	_check(paused, "the game pauses behind the death screen")
	_check(ui.end_screen.get_node("%Title").text == "SHIP LOST", "the death screen says SHIP LOST")
	# Back to playing for the remaining checks.
	ui.end_screen.visible = false
	ui.end_screen.is_open = false
	paused = false
	Hitstop.clear()
	_ship.respawn(Vector3.ZERO)
	_check(_ship.is_alive() and _ship.health.hull == _ship.health.max_hull, "a ship can be respawned with full hull")


func _test_waves() -> void:
	_place(Vector3.ZERO)
	var started: Array[int] = []
	var cleared: Array[int] = []
	_director.wave_started.connect(func(n): started.append(n))
	_director.wave_cleared.connect(func(n): cleared.append(n))
	_director.start_wave(1)
	await _frames(int((_director.warp_in_time + 0.3) * 60.0))
	_check(started == [1] and _director.alive.size() == 3, "wave 1 warps in 3 drones (%d)" % _director.alive.size())
	for enemy in _director.alive.duplicate():
		enemy.take_damage(1000.0, _ship)
	await _frames(5)
	_check(cleared == [1], "clearing every enemy ends the wave")
	await _frames(int((_director.intermission + _director.warp_in_time + 0.5) * 60.0))
	_check(started == [1, 2] and _director.alive.size() == 5, "the next wave is bigger, with a cutter (%d enemies)" % _director.alive.size())


# --- Helpers -----------------------------------------------------------------

func _ore_rocks() -> Array[MineableAsteroid]:
	var out: Array[MineableAsteroid] = []
	for rock in _level.get_node("Asteroids").get_children():
		if rock is MineableAsteroid and not rock.is_queued_for_deletion():
			out.append(rock)
	return out


func _nearest_ore_rock() -> MineableAsteroid:
	var best: MineableAsteroid = null
	for rock in _ore_rocks():
		if best == null or rock.global_position.length() < best.global_position.length():
			best = rock
	return best


func _pickups() -> Array[Pickup]:
	var out: Array[Pickup] = []
	for p in get_nodes_in_group("pickups"):
		if not p.is_queued_for_deletion():
			out.append(p)
	return out


func _clear_pickups() -> void:
	for p in _pickups():
		p.queue_free()


func _place(pos: Vector3) -> void:
	_ship.global_position = pos
	_ship.velocity = Vector3.ZERO
	_ship.rotation = Vector3.ZERO
	_ship.boost_fuel = 1.0
	_input.reset()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
