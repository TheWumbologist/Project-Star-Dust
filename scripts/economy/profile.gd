class_name Profile
extends RefCounted
## The player's permanent save: credits, Void Essence, scrap, hull damage,
## upgrade levels, story progress (Rift Compass, deepest rift tier open)
## and the last run's report. Static, so it survives scene changes without an
## autoload. There are SLOTS save slots, each a JSON file in user://saves/
## (on Windows that's %APPDATA%/Godot/app_userdata/Rift Runners/saves/),
## picked on the save select screen.

## Bumped when the save format changes; older saves can't be loaded.
const SAVE_VERSION := 2
const SLOTS := 3
## Tests point these somewhere else so they never touch the real saves.
static var save_dir: String = "user://saves"
## The single save file from before save slots (milestone 4).
static var legacy_path: String = "user://profile.json"

## The slot in use (1..SLOTS).
static var slot: int = 1
## The file in use.
static var path: String = "user://saves/slot_1.json"

static var credits: int = 0
static var essence: int = 0
## Scrap is kept for repairs instead of being sold on extraction.
static var scrap: int = 0
## Hull points missing; carried from run to run until repaired.
static var hull_damage: float = 0.0
## Found in the tutorial derelict; rifts need it.
static var has_compass: bool = false
## Deepest rift tier unlocked (0 until the Compass is found).
static var max_tier: int = 0
static var upgrades: Dictionary = {}
static var runs: int = 0
static var extractions: int = 0
## Lines describing the last run, shown at the hangar.
static var last_run: PackedStringArray = []

static var _loaded: bool = false

## The player ship's base hull (player_ship.tscn Health.max_hull). The
## economy test checks they match.
const BASE_HULL := 100.0
## Hull points one scrap repairs, and credits per point when out of scrap.
const HULL_PER_SCRAP := 5.0
const CREDITS_PER_HULL := 3
## Fraction of hull the ship is towed home with after being destroyed.
const TOWED_HULL := 0.25

## Permanent upgrades sold at the hangar. Each level adds `amount` to `stat`
## (a fraction when `percent`). Level n costs credits * n and essence * n.
const UPGRADES := [
	{"id": &"hull", "name": "Hull plating", "stat": &"max_hull", "amount": 20.0, "percent": false, "max": 5, "credits": 120, "essence": 0,
		"blurb": "+20 hull per level."},
	{"id": &"shields", "name": "Shield emitters", "stat": &"max_shield", "amount": 15.0, "percent": false, "max": 5, "credits": 120, "essence": 0,
		"blurb": "+15 shields per level."},
	{"id": &"cargo", "name": "Cargo racks", "stat": &"cargo_slots", "amount": 1.0, "percent": false, "max": 4, "credits": 200, "essence": 10,
		"blurb": "+1 cargo slot per level."},
	{"id": &"cannon", "name": "Cannon bore", "stat": &"primary_damage", "amount": 0.15, "percent": true, "max": 5, "credits": 150, "essence": 5,
		"blurb": "+15% cannon damage per level."},
	{"id": &"torpedo", "name": "Torpedo warheads", "stat": &"heavy_damage", "amount": 0.2, "percent": true, "max": 4, "credits": 150, "essence": 8,
		"blurb": "+20% torpedo damage per level."},
	{"id": &"engine", "name": "Engine tuning", "stat": &"max_speed", "amount": 0.06, "percent": true, "max": 3, "credits": 200, "essence": 15,
		"blurb": "+6% top speed per level."},
]


static func ensure_loaded() -> void:
	if not _loaded:
		load_profile()


static func load_profile() -> void:
	reset()
	_loaded = true
	if not FileAccess.file_exists(path):
		return
	var data = _read(path)
	if data.is_empty() or int(data.get("version", 0)) < SAVE_VERSION:
		push_warning("Save at %s is unreadable or from an older version; starting fresh." % path)
		return
	credits = int(data.get("credits", 0))
	essence = int(data.get("essence", 0))
	scrap = int(data.get("scrap", 0))
	hull_damage = float(data.get("hull_damage", 0.0))
	has_compass = bool(data.get("has_compass", false))
	max_tier = int(data.get("max_tier", 0))
	runs = int(data.get("runs", 0))
	extractions = int(data.get("extractions", 0))
	var ups: Dictionary = data.get("upgrades", {})
	for key in ups:
		upgrades[StringName(key)] = int(ups[key])
	last_run = PackedStringArray(data.get("last_run", []))


static func save() -> void:
	var ups := {}
	for key in upgrades:
		ups[String(key)] = upgrades[key]
	var data := {
		"version": SAVE_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"credits": credits,
		"essence": essence,
		"scrap": scrap,
		"hull_damage": hull_damage,
		"has_compass": has_compass,
		"max_tier": max_tier,
		"runs": runs,
		"extractions": extractions,
		"upgrades": ups,
		"last_run": Array(last_run),
	}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Couldn't save the profile to %s" % path)
		return
	file.store_string(JSON.stringify(data, "  "))


# --- Save slots -------------------------------------------------------------------

static func slot_path(n: int) -> String:
	return "%s/slot_%d.json" % [save_dir, n]


## Switches to slot `n` and loads it (fresh if the slot is empty).
static func select_slot(n: int) -> void:
	slot = n
	path = slot_path(n)
	load_profile()


## Starts a brand new game in slot `n`, overwriting whatever was there.
static func new_game(n: int) -> void:
	slot = n
	path = slot_path(n)
	reset()
	_loaded = true
	save()


static func delete_slot(n: int) -> void:
	var file := slot_path(n)
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	if file == path:
		reset()


## What's in slot `n` without loading it: {} when empty, else credits,
## essence, runs, extractions, has_compass, max_tier, saved_at and
## `compatible` (false for saves from an older version).
static func slot_info(n: int) -> Dictionary:
	var file := slot_path(n)
	if not FileAccess.file_exists(file):
		return {}
	var data := _read(file)
	if data.is_empty() or int(data.get("version", 0)) < SAVE_VERSION:
		return {"compatible": false}
	return {
		"compatible": true,
		"credits": int(data.get("credits", 0)),
		"essence": int(data.get("essence", 0)),
		"runs": int(data.get("runs", 0)),
		"extractions": int(data.get("extractions", 0)),
		"has_compass": bool(data.get("has_compass", false)),
		"max_tier": int(data.get("max_tier", 0)),
		"saved_at": int(data.get("saved_at", 0)),
	}


## The most recently saved loadable slot, or 0 if there is none.
static func latest_slot() -> int:
	var best := 0
	var best_time := -1
	for n in range(1, SLOTS + 1):
		var info := slot_info(n)
		if info.get("compatible", false) and int(info.saved_at) > best_time:
			best = n
			best_time = info.saved_at
	return best


## Deletes the pre-slots save file, which this version can't read.
static func remove_legacy_save() -> bool:
	if not FileAccess.file_exists(legacy_path):
		return false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	return true


static func _read(file: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(file))
	return data if typeof(data) == TYPE_DICTIONARY else {}


## Wipes everything in memory (not on disk until save()).
static func reset() -> void:
	credits = 0
	essence = 0
	scrap = 0
	hull_damage = 0.0
	has_compass = false
	max_tier = 0
	upgrades = {}
	runs = 0
	extractions = 0
	last_run = []


static func level(id: StringName) -> int:
	return upgrades.get(id, 0)


static func upgrade(id: StringName) -> Dictionary:
	for u in UPGRADES:
		if u.id == id:
			return u
	return {}


## Cost of the next level as (credits, essence); (0, 0) when maxed.
static func next_cost(id: StringName) -> Vector2i:
	var u := upgrade(id)
	var next := level(id) + 1
	if u.is_empty() or next > u.max:
		return Vector2i.ZERO
	return Vector2i(u.credits * next, u.essence * next)


static func is_maxed(id: StringName) -> bool:
	var u := upgrade(id)
	return u.is_empty() or level(id) >= u.max


static func can_buy(id: StringName) -> bool:
	var cost := next_cost(id)
	return not is_maxed(id) and credits >= cost.x and essence >= cost.y


static func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	var cost := next_cost(id)
	credits -= cost.x
	essence -= cost.y
	upgrades[id] = level(id) + 1
	save()
	return true


## The bought upgrades as loadout modifiers.
static func upgrade_mods() -> Array:
	var mods := []
	for u in UPGRADES:
		var n := level(u.id)
		if n > 0:
			mods.append({"stat": u.stat, "amount": u.amount * n, "percent": u.percent})
	return mods


## Max hull with upgrades bought.
static func max_hull() -> float:
	var total := BASE_HULL
	for m in upgrade_mods():
		if m.stat == &"max_hull" and not m.percent:
			total += m.amount
	return total


## Scrap needed to fix all hull damage.
static func repair_scrap_cost() -> int:
	return ceili(hull_damage / HULL_PER_SCRAP)


## Repairs with scrap first, then credits for whatever's left. Returns the
## hull points repaired.
static func repair() -> float:
	var before := hull_damage
	var use := mini(scrap, repair_scrap_cost())
	scrap -= use
	hull_damage = maxf(hull_damage - use * HULL_PER_SCRAP, 0.0)
	var afford := mini(ceili(hull_damage), floori(credits / float(CREDITS_PER_HULL)))
	credits -= afford * CREDITS_PER_HULL
	hull_damage = maxf(hull_damage - afford, 0.0)
	save()
	return before - hull_damage


## Credits a repair would cost after spending all usable scrap.
static func repair_credit_cost() -> int:
	var left := maxf(hull_damage - mini(scrap, repair_scrap_cost()) * HULL_PER_SCRAP, 0.0)
	return ceili(left) * CREDITS_PER_HULL


static func sell_scrap(scrap_value: int) -> int:
	var earned := scrap * scrap_value
	credits += earned
	scrap = 0
	save()
	return earned
