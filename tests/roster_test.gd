extends SceneTree
## Headless test for the enemy roster (milestone 6c): nine enemies, three
## roles by three tiers, each fighting its own way.
##
## Loads the combat arena with its waves off and the rocks cleared, warps
## each roster enemy in with the arena's number-key spawner, and checks its
## signature behaviour against a (very tough) scripted player ship. Also
## checks the roster tables and how rifts pick enemies by tier. Run from the
## project folder:
##   godot --headless --script res://tests/roster_test.gd
## Exit code 0 = all checks passed.

const SCENE := "res://scenes/test/combat_test.tscn"
const ScriptedInput := preload("res://tests/scripted_input.gd")
const DRONE := preload("res://scenes/enemies/scavenger_drone.tscn")

var _failures: PackedStringArray = []
var _input: ScriptedInput
var _level: Node3D
var _ship: ShipController
var _director: EncounterDirector
var _hits: Array[float] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_level = load(SCENE).instantiate()
	_director = _level.get_node("EncounterDirector") as EncounterDirector
	_director.auto_start = false
	root.add_child(_level)
	current_scene = _level
	await physics_frame
	for rock in _level.get_node("Asteroids").get_children():
		rock.free()

	_ship = _level.get_node("PlayerShip") as ShipController
	_input = ScriptedInput.new()
	_ship.add_child(_input)
	_ship.input_source = _input
	_ship.health.max_hull = 100000.0
	_ship.health.max_shield = 0.0
	_ship.health.reset()
	_ship.damaged.connect(func(amount, _src): _hits.append(amount))

	_test_tables()
	_test_rift_picks()
	await _test_drone()
	await _test_mite()
	await _test_wasp()
	await _test_cutter()
	await _test_lancer()
	await _test_galleon()
	await _test_hauler()
	await _test_ketch()
	await _test_warden()

	Sfx.stop_all()
	await create_timer(1.0, true, false, true).timeout
	if _failures.is_empty():
		print("ROSTER TEST: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("ROSTER TEST FAIL: ", f)
		quit(1)


# --- Tables --------------------------------------------------------------------

func _test_tables() -> void:
	var slots := {}
	var ok := true
	for e in EnemyRoster.ENTRIES:
		slots["%d/%d" % [e.role, e.tier]] = true
		var ship := EnemyRoster.scene_of(e).instantiate() as ShipController
		ok = ok and ship != null and ship.team == 1 and ship.threat_tier == e.tier \
			and ship.get_node_or_null("Health") != null and ship.get_node_or_null("Input") is AIPilot
		if ship != null:
			ship.free()
	_check(EnemyRoster.ENTRIES.size() == 9 and slots.size() == 9, "the roster has 9 enemies, one per role and tier")
	_check(ok, "every roster enemy loads as a hostile ship with a pilot, health and its tier")


func _test_rift_picks() -> void:
	var gen := RiftGenerator.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	gen.enemy_tier_odds.assign([0.0, 0.0, 1.0])
	var pick := gen.roster_pick(DRONE, rng)
	_check(not pick.is_empty() and pick.scene.resource_path.ends_with("void_wasp.tscn") and pick.count >= 2,
		"a drone spawn point in a tier 3 roll gets a pack of void wasps (%d)" % pick.get("count", 0))
	var hauler_point: PackedScene = load("res://scenes/enemies/scrap_hauler.tscn")
	gen.enemy_tier_odds.assign([0.0, 1.0, 0.0])
	pick = gen.roster_pick(hauler_point, rng)
	_check(not pick.is_empty() and pick.scene.resource_path.ends_with("torpedo_ketch.tscn"), "a specialist point in a tier 2 roll gets a torpedo ketch")
	gen.enemy_roles.assign([EnemyRoster.Role.SWARM])
	_check(gen.roster_pick(hauler_point, rng).is_empty(), "roles the site doesn't allow stay empty")
	gen.free()
	# Deeper chunks lean to the higher tiers the site allows.
	var shallow := 0
	var deep := 0
	for i in 2000:
		shallow += 1 if EnemyRoster.roll_tier(rng, [0.5, 0.5, 0.0], 0.0) == 2 else 0
		deep += 1 if EnemyRoster.roll_tier(rng, [0.5, 0.5, 0.0], 1.0) == 2 else 0
	_check(deep > shallow + 100, "deeper chunks roll higher tiers more often (%d vs %d of 2000)" % [deep, shallow])
	var never := true
	for i in 500:
		never = never and EnemyRoster.roll_tier(rng, [1.0, 0.0, 0.0], 1.0) == 1
	_check(never, "tiers with no odds never roll, however deep")
	var debris: Dictionary = Deployment.SITES[0]
	_check(not (EnemyRoster.Role.GUNSHIP in debris.enemy_roles) and debris.enemy_tiers[1] == 0.0, "debris fields only hold tier 1 drones and haulers")


# --- Behaviours ------------------------------------------------------------------------

## Swarm 1: closes in and plinks away.
func _test_drone() -> void:
	var drone := await _spawn(0)
	await _frames(300)
	_check(_damage() > 0.0, "scavenger drone shoots the player (%.0f)" % _damage())
	_clear(drone)


## Swarm 2: rushes in, lights a fuse and blows itself up.
func _test_mite() -> void:
	var mite := await _spawn(1)
	var pilot := mite.input_source as KamikazePilot
	var lit := false
	for i in 480:
		await physics_frame
		if is_instance_valid(mite) and pilot.fuse_left >= 0.0:
			lit = true
		if not is_instance_valid(mite):
			break
	await _frames(5) # The blast lands the tick after.
	_check(lit, "spark mite lights its fuse when close")
	_check(not is_instance_valid(mite) and _damage() >= 10.0, "spark mite blows itself up on the player (%.0f)" % _damage())
	_check(Sfx.history.has(&"fuse"), "the fuse beeps")
	await _frames(30)
	_check(_pickups_near(8.0) == 0, "a self-detonated mite leaves no scrap on its victim")
	# Shot down on the way in, it pops without hurting anyone.
	_hits.clear()
	mite = await _spawn(1)
	mite.take_damage(100.0, _ship)
	await _frames(30)
	_check(not is_instance_valid(mite) and _damage() == 0.0, "a spark mite shot down early pops harmlessly")
	_clear(null)


## Swarm 3: strafing passes, then peels away.
func _test_wasp() -> void:
	var wasp := await _spawn(2)
	var pilot := wasp.input_source as StrikerPilot
	var close := false
	var retreated := false
	for i in 600:
		await physics_frame
		if not is_instance_valid(wasp):
			break
		var d := wasp.global_position.distance_to(_ship.global_position)
		close = close or d < 12.0
		if close and not pilot.attacking:
			retreated = true
	_check(close and retreated, "void wasp makes an attack pass and peels away")
	_check(_damage() > 0.0, "void wasp hits the player on its passes (%.0f)" % _damage())
	_clear(wasp)


## Gunship 1: shotgun volleys.
func _test_cutter() -> void:
	var cutter := await _spawn(3)
	await _frames(360)
	_check(_damage() > 0.0, "pirate cutter shoots the player (%.0f)" % _damage())
	_clear(cutter)


## Gunship 2: shows an aim line, then one heavy shot.
func _test_lancer() -> void:
	var lancer := await _spawn(4)
	var pilot := lancer.input_source as SniperPilot
	var line := pilot.get_node("AimLine") as MeshInstance3D
	var line_seen := false
	var hit_before_line := false
	for i in 600:
		await physics_frame
		if pilot.charge_left >= 0.0 and line.visible:
			line_seen = true
		if not line_seen and _damage() > 0.0:
			hit_before_line = true
		if line_seen and _damage() > 0.0:
			break
	_check(line_seen and not hit_before_line, "corsair lancer shows its aim line before firing")
	_check(_hits.max() >= 20.0 if not _hits.is_empty() else false, "the lance hits a sitting target hard (%.0f)" % (_hits.max() if not _hits.is_empty() else 0.0))
	_check(Sfx.history.has(&"charge") and Sfx.history.has(&"lance"), "the lance charges and fires with its own sounds")
	# A ship that keeps moving dodges: fly a wide circle and count hits.
	_hits.clear()
	var dodged := 0
	var fired: Array = [] # Lambdas capture locals by value; arrays share.
	(lancer.get_node("Lance") as ShipWeapon).fired.connect(func(p): fired.append(p))
	for i in 600:
		_input.steer = Vector3.FORWARD.rotated(Vector3.UP, i * 0.02)
		_input.thrust = 1.0
		await physics_frame
	var shots := fired.size()
	dodged = shots - _hits.filter(func(h): return h >= 20.0).size()
	_check(shots > 0 and dodged > 0, "flying evasively dodges lance shots (%d of %d dodged)" % [dodged, shots])
	_clear(lancer)


## Gunship 3: broadsides out of its sides only.
func _test_galleon() -> void:
	var galleon := await _spawn(5)
	var angles: Array[float] = []
	for name in ["StarboardBattery", "PortBattery"]:
		(galleon.get_node(name) as ShipWeapon).fired.connect(func(p):
			angles.append(rad_to_deg(galleon.forward().angle_to(p.velocity.normalized()))))
	await _frames(900)
	# Within 60 degrees of abeam (volley fan and the ship's own speed included).
	var side_shots := angles.filter(func(a): return a > 30.0 and a < 150.0).size()
	var bad_shots := angles.size() - side_shots
	_check(side_shots >= 5 and bad_shots == 0, "broadside galleon fires broadsides out of its sides (%d side, %d other)" % [side_shots, bad_shots])
	_check(_damage() > 0.0 and Sfx.history.has(&"broadside"), "the broadsides hit and boom (%.0f)" % _damage())
	_clear(galleon)


## Specialist 1: flees and drops mines; mines blow up on the player.
func _test_hauler() -> void:
	var hauler := await _spawn(6)
	var start := hauler.global_position.distance_to(_ship.global_position)
	# Chase it.
	for i in 300:
		var to := hauler.global_position - _ship.global_position
		to.y = 0.0
		_input.steer = to.normalized()
		_input.thrust = 1.0 if to.length() > 10.0 else 0.0
		await physics_frame
	var mines := _level.get_tree().get_nodes_in_group("mines")
	_check(not mines.is_empty(), "a chased scrap hauler drops mines behind it (%d)" % mines.size())
	_check(hauler.global_position.distance_to(_ship.global_position) > 8.0 and hauler.speed() > 3.0, "the scrap hauler runs away (%.0f m from %.0f)" % [hauler.global_position.distance_to(_ship.global_position), start])
	_input.reset()
	_hits.clear()
	var mine: ProximityMine = null
	for i in 60:
		for m in _level.get_tree().get_nodes_in_group("mines"):
			if (m as ProximityMine).is_armed():
				mine = m
		if mine != null:
			break
		await physics_frame
	if mine != null:
		_place(mine.global_position + Vector3(0, 0, 3.0))
		await _frames(60)
		_check(not is_instance_valid(mine) and _damage() > 0.0, "flying near an armed mine sets it off (%.0f)" % _damage())
	else:
		_check(false, "an armed mine is left to fly into")
	# Shooting a mine sets it off from a distance. A fresh, parked hauler
	# drops one on demand.
	if is_instance_valid(hauler):
		hauler.free()
	_place(Vector3.ZERO)
	hauler = _director.spawn_now(EnemyRoster.scene_of(EnemyRoster.ENTRIES[6]), Vector3(0, 0, -40))
	hauler.input_source = null
	await _frames(2)
	var rack := hauler.get_node("MineRack") as ShipWeapon
	var dropped: Array = []
	rack.fired.connect(func(p): dropped.append(p))
	rack.charges = rack.max_charges
	var intent := ShipIntent.new()
	intent.fire_held = true
	rack.tick(hauler, intent, 1.0)
	_check(dropped.size() == 1, "the mine rack drops a mine on demand (%d, %d charges)" % [dropped.size(), rack.charges])
	if dropped.size() == 1:
		var far_mine := dropped[0] as ProximityMine
		hauler.free() # Out of the line of fire.
		await _frames(90) # Let it drift to a stop.
		_hits.clear()
		_place(far_mine.global_position + Vector3(0, 0, 20.0))
		_input.aim = Vector3.FORWARD
		_input.fire = true
		for i in 120:
			await physics_frame
			if not is_instance_valid(far_mine):
				break
		await _frames(5)
		_check(not is_instance_valid(far_mine) and _damage() == 0.0, "shooting a mine sets it off safely from range (%.0f)" % _damage())
	_clear(null)


## Specialist 2: slow homing torpedoes that curve after you.
func _test_ketch() -> void:
	var ketch := await _spawn(7)
	var torps: Array = []
	(ketch.get_node("TorpedoTubes") as ShipWeapon).fired.connect(func(p): torps.append([p, p.velocity.normalized()]))
	var curved := false
	for i in 600:
		# Slide sideways so a straight shot would miss.
		_input.steer = Vector3.RIGHT if i % 240 < 120 else Vector3.LEFT
		_input.thrust = 0.6
		await physics_frame
		for t in torps:
			if is_instance_valid(t[0]) and rad_to_deg(t[1].angle_to(t[0].velocity.normalized())) > 10.0:
				curved = true
	_check(not torps.is_empty(), "torpedo ketch launches torpedoes (%d)" % torps.size())
	_check(curved, "its torpedoes curve after the player")
	# A ship that sits still gets caught.
	_input.reset()
	for i in 420:
		await physics_frame
		if _damage() > 0.0:
			break
	_check(_damage() > 0.0, "the torpedoes catch a ship that stops dodging (%.0f)" % _damage())
	_clear(ketch)


## Specialist 3: repairs allies and blinks away when pressed.
func _test_warden() -> void:
	var warden := await _spawn(8)
	var pilot := warden.input_source as WardenPilot
	var ally := _director.spawn_now(DRONE, warden.global_position + Vector3(6, 0, 0))
	ally.input_source = null
	ally.health.hull = 5.0
	await _frames(120)
	_check(ally.health.hull > 10.0, "rift warden repairs a damaged ally (%.0f hull)" % ally.health.hull)
	_check(pilot.get_node("RepairBeam").visible and pilot.patient == ally, "and draws its repair beam to it")
	# Rush it: it blinks away.
	var blinks := pilot.blinks
	_place(warden.global_position + Vector3(0, 0, 5.0))
	await _frames(30)
	_check(pilot.blinks > blinks and warden.global_position.distance_to(_ship.global_position) > 12.0, "rift warden blinks away when you get close (%.0f m)" % warden.global_position.distance_to(_ship.global_position))
	_check(Sfx.history.has(&"blink"), "the blink has its own sound")
	_clear(warden)


# --- Helpers -------------------------------------------------------------------------

## Warps roster enemy `index` in ahead of a reset player, like pressing 1-9.
func _spawn(index: int) -> ShipController:
	_place(Vector3.ZERO)
	_hits.clear()
	var enemy: ShipController = _level.spawn_roster_enemy(index)
	await _frames(2)
	return enemy


func _clear(_enemy: ShipController) -> void:
	for node in _level.get_tree().get_nodes_in_group("ships"):
		if node != _ship and is_instance_valid(node):
			node.free()
	for node in _level.get_tree().get_nodes_in_group("mines"):
		node.free()
	for node in _level.get_children():
		if node is Projectile or node is Pickup:
			node.free()
	_input.reset()
	_ship.health.reset()


func _damage() -> float:
	var total := 0.0
	for h in _hits:
		total += h
	return total


func _pickups_near(radius: float) -> int:
	var n := 0
	for node in _level.get_children():
		if node is Pickup and node.global_position.distance_to(_ship.global_position) < radius:
			n += 1
	return n


func _place(pos: Vector3) -> void:
	_ship.global_position = pos
	_ship.velocity = Vector3.ZERO
	_ship.rotation = Vector3.ZERO
	_ship.boost_fuel = 1.0
	_ship.reset_physics_interpolation()
	_input.reset()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
