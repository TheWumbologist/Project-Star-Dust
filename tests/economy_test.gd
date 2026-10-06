extends SceneTree
## Headless test for milestone 4's economy pieces: augments and the ship
## loadout maths, the augment catalog, and the Profile save with its
## upgrade shop. Run from the project folder:
##   godot --headless --script res://tests/economy_test.gd
## Exit code 0 = all checks passed.

const SHIP := "res://scenes/ship/player_ship.tscn"
const SLOOP := preload("res://resources/ships/sloop_stats.tres")

var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.path = "user://test_economy_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.path))
	await _test_loadout()
	_test_catalog()
	_test_profile()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.path))
	if _failures.is_empty():
		print("ECONOMY TEST: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("ECONOMY TEST FAIL: ", f)
		quit(1)


func _test_loadout() -> void:
	var ship: ShipController = load(SHIP).instantiate()
	root.add_child(ship)
	await process_frame
	var lo := ship.loadout
	_check(lo != null, "the player ship has a loadout")
	var dmg := ship.primary.damage
	var speed := ship.stats.max_speed
	var tubes := ship.heavy.max_charges
	var hull := ship.health.max_hull
	var slots := ship.cargo.slot_count

	lo.add_augment(_aug("overcharged_cannons"))
	lo.add_augment(_aug("overcharged_cannons"))
	_check(is_equal_approx(ship.primary.damage, dmg * 1.5), "two Overcharged Cannons stack to +50%% (%.1f)" % ship.primary.damage)
	lo.add_augment(_aug("slipstream_fins"))
	_check(is_equal_approx(ship.stats.max_speed, speed * 1.15), "Slipstream Fins add 15%% top speed")
	_check(is_equal_approx(SLOOP.max_speed, speed), "the shared sloop stats resource is never changed")
	ship.heavy.charges = 0
	lo.add_augment(_aug("extra_tube"))
	_check(ship.heavy.max_charges == tubes + 1 and ship.heavy.charges == 1, "Extra Tube adds a loaded torpedo tube")
	ship.health.hull = hull - 50.0
	lo.add_augment(_aug("reinforced_plating"))
	_check(is_equal_approx(ship.health.max_hull, hull + 30.0) and is_equal_approx(ship.health.hull, hull - 20.0), "Reinforced Plating adds 30 hull and patches 30 on the spot")
	lo.add_augment(_aug("afterburner_injectors"))
	_check(is_equal_approx(ship.stats.boost_drain_rate, SLOOP.boost_drain_rate * 0.7), "Afterburner Injectors cut boost burn by 30%")
	_check(lo.essence_value() == 5 + 5 + 25 + 12 + 5 + 5, "fitted augments are worth their essence (%d)" % lo.essence_value())

	lo.set_upgrades([{"stat": &"cargo_slots", "amount": 2.0, "percent": false}, {"stat": &"primary_damage", "amount": 0.3, "percent": true}])
	_check(ship.cargo.slot_count == slots + 2, "cargo rack upgrades add hold slots")
	_check(is_equal_approx(ship.primary.damage, dmg * 1.8), "upgrades and augments add together (%.1f)" % ship.primary.damage)

	while lo.has_free_slot():
		lo.add_augment(_aug("battering_prow"))
	_check(not lo.add_augment(_aug("battering_prow")) and lo.augments.size() == lo.augment_slots, "augment slots fill up at %d" % lo.augment_slots)
	ship.queue_free()
	await process_frame


func _test_catalog() -> void:
	_check(AugmentCatalog.ALL.size() == 10, "there are 10 augments")
	var stats_ok := true
	for a in AugmentCatalog.ALL:
		stats_ok = stats_ok and ShipLoadout.STATS.has(a.stat) and a.display_name != ""
	_check(stats_ok, "every augment changes a stat the loadout knows")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var commons := 0
	var epics := 0
	for i in 400:
		var roll := AugmentCatalog.roll(rng, 3)
		if roll.size() != 3 or roll[0] == roll[1] or roll[1] == roll[2] or roll[0] == roll[2]:
			_check(false, "a cache roll repeated an augment")
			return
		for a in roll:
			if a.rarity == AugmentDefinition.Rarity.COMMON:
				commons += 1
			elif a.rarity == AugmentDefinition.Rarity.EPIC:
				epics += 1
	_check(commons > epics * 4, "commons turn up far more than epics (%d vs %d)" % [commons, epics])


func _test_profile() -> void:
	Profile.load_profile()
	_check(Profile.credits == 0 and Profile.upgrades.is_empty(), "a new profile starts empty")
	_check(not Profile.buy(&"hull"), "you can't buy without credits")
	Profile.credits = 1000
	Profile.essence = 20
	_check(Profile.next_cost(&"hull") == Vector2i(120, 0), "hull level 1 costs 120 credits")
	_check(Profile.buy(&"hull") and Profile.buy(&"hull"), "buying two hull levels")
	_check(Profile.credits == 1000 - 120 - 240, "each level costs more (%d left)" % Profile.credits)
	_check(Profile.buy(&"cargo") and Profile.essence == 10, "cargo racks also cost essence")
	_check(not Profile.can_buy(&"engine"), "engine tuning waits for 15 essence")
	var mods := Profile.upgrade_mods()
	var hull_mod := mods.filter(func(m): return m.stat == &"max_hull")
	_check(hull_mod.size() == 1 and is_equal_approx(hull_mod[0].amount, 40.0), "two hull levels give +40 hull")
	Profile.last_run = PackedStringArray(["EXTRACTED", "Hold sold +10 cr"])
	Profile.save()
	var credits := Profile.credits
	Profile.reset()
	Profile.load_profile()
	_check(Profile.credits == credits and Profile.level(&"hull") == 2 and Profile.level(&"cargo") == 1, "the profile survives a save and load")
	_check(Profile.last_run.size() == 2, "the last run report is saved too")
	Profile.upgrades[&"hull"] = 5
	_check(Profile.is_maxed(&"hull") and not Profile.can_buy(&"hull") and Profile.next_cost(&"hull") == Vector2i.ZERO, "maxed upgrades can't be bought")


func _aug(id: String) -> AugmentDefinition:
	return load("res://resources/augments/%s.tres" % id)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
