class_name ShipLoadout
extends Node
## Works out a ship's live numbers from its base parts plus modifiers:
## permanent upgrades bought at the hangar and augments picked up this run.
## Lives as a "Loadout" child of the ship. Base values are captured the
## first time it applies, and the ship's stats resource is duplicated so
## the shared .tres is never changed.

signal changed

## Modifier stats this understands, and what they touch.
const STATS := {
	&"max_speed": "Top speed (and boost top speed)",
	&"boost_drain": "Boost fuel burn",
	&"drift_kick": "Drift kick speed",
	&"ram_damage": "Ram damage",
	&"primary_damage": "Cannon damage",
	&"primary_fire_rate": "Cannon fire rate",
	&"heavy_damage": "Torpedo damage",
	&"heavy_charges": "Torpedo charges",
	&"max_hull": "Hull",
	&"max_shield": "Shields",
	&"cargo_slots": "Cargo slots",
}

## How many augments a ship can run with.
@export var augment_slots: int = 8

var augments: Array[AugmentDefinition] = []
## Mods from permanent upgrades: [{stat, amount, percent}].
var upgrade_mods: Array = []

var _ship: ShipController
var _captured: bool = false
var _base_stats: ShipStats
var _base := {}


func _ready() -> void:
	_ship = get_parent() as ShipController


func has_free_slot() -> bool:
	return augments.size() < augment_slots


func add_augment(augment: AugmentDefinition) -> bool:
	if augment == null or not has_free_slot():
		return false
	augments.append(augment)
	apply()
	return true


func set_upgrades(mods: Array) -> void:
	upgrade_mods = mods
	apply()


## Void Essence the current augments would break down into.
func essence_value() -> int:
	var total := 0
	for a in augments:
		total += a.essence_value
	return total


## Re-derives every number from the base values and all modifiers.
func apply() -> void:
	if _ship == null:
		_ship = get_parent() as ShipController
	_capture()
	var add := {}
	var mul := {}
	var mods: Array = upgrade_mods.duplicate()
	for a in augments:
		mods.append(a.as_mod())
	for m in mods:
		if m.percent:
			mul[m.stat] = mul.get(m.stat, 1.0) + m.amount
		else:
			add[m.stat] = add.get(m.stat, 0.0) + m.amount
	var v := func(stat: StringName, base: float) -> float:
		return maxf(base * mul.get(stat, 1.0) + add.get(stat, 0.0), 0.0)

	var s := _base_stats.duplicate() as ShipStats
	s.max_speed = v.call(&"max_speed", _base_stats.max_speed)
	s.boost_max_speed = _base_stats.boost_max_speed * mul.get(&"max_speed", 1.0) + add.get(&"max_speed", 0.0)
	s.boost_drain_rate = v.call(&"boost_drain", _base_stats.boost_drain_rate)
	s.drift_tier1_kick = v.call(&"drift_kick", _base_stats.drift_tier1_kick)
	s.drift_tier2_kick = v.call(&"drift_kick", _base_stats.drift_tier2_kick)
	s.ram_damage = v.call(&"ram_damage", _base_stats.ram_damage)
	_ship.stats = s

	if _ship.primary != null:
		_ship.primary.damage = v.call(&"primary_damage", _base.primary_damage)
		_ship.primary.fire_rate = v.call(&"primary_fire_rate", _base.primary_fire_rate)
	if _ship.heavy != null:
		_ship.heavy.damage = v.call(&"heavy_damage", _base.heavy_damage)
		var charges := roundi(v.call(&"heavy_charges", _base.heavy_charges))
		_ship.heavy.charges += maxi(charges - _ship.heavy.max_charges, 0) # New tubes come loaded.
		_ship.heavy.max_charges = charges
		_ship.heavy.charges = mini(_ship.heavy.charges, charges)
	if _ship.health != null:
		var h := _ship.health
		var hull := v.call(&"max_hull", _base.max_hull) as float
		var shield := v.call(&"max_shield", _base.max_shield) as float
		# Extra capacity arrives full; less capacity trims what's there.
		h.hull = minf(h.hull + maxf(hull - h.max_hull, 0.0), hull)
		h.shield = minf(h.shield + maxf(shield - h.max_shield, 0.0), shield)
		h.max_hull = hull
		h.max_shield = shield
	if _ship.cargo != null:
		_ship.cargo.slot_count = roundi(v.call(&"cargo_slots", _base.cargo_slots))
		_ship.cargo.changed.emit()
	changed.emit()


func _capture() -> void:
	if _captured:
		return
	_captured = true
	_base_stats = _ship.stats.duplicate() as ShipStats
	if _ship.primary != null:
		_base.primary_damage = _ship.primary.damage
		_base.primary_fire_rate = _ship.primary.fire_rate
	if _ship.heavy != null:
		_base.heavy_damage = _ship.heavy.damage
		_base.heavy_charges = float(_ship.heavy.max_charges)
	if _ship.health != null:
		_base.max_hull = _ship.health.max_hull
		_base.max_shield = _ship.health.max_shield
	if _ship.cargo != null:
		_base.cargo_slots = float(_ship.cargo.slot_count)
