class_name Deployment
extends RefCounted
## Where the next run goes, picked on the hangar's star chart and read by
## RiftRun when the level loads. Static so it survives the scene change.
##
## Tier 0 is a debris field: small, no instability, no augments, no void
## crystals, drones only, and one open area with no rift tears; it's where
## scrap for repairs comes from. Tiers
## 1-3 are rifts: bigger, tougher enemies, a faster collapse and a bigger
## payout the deeper you go. The first run of a new save is the tutorial
## debris field, where the Rift Compass is salvaged.

## The site picked for the next run (an index into SITES).
static var tier: int = 1
## True for the very first run: the derelict holding the Rift Compass.
static var tutorial: bool = false

const SITES := [
	{"tier": 0, "name": "Debris field", "blurb": "Wreck-strewn shallows. No instability, no augments. Scrap and ore for repairs.",
		"main_path": 4, "branches": 1, "min_exit_depth": 3, "min_exit_spread": 2,
		"instability": false, "collapse_time": 0.0, "enemy_health": 1.0, "enemy_damage": 0.8, "spawn_bonus": -0.35,
		"cutters": false, "caches": false, "void_crystals": false, "payout": 1.0, "tears": false},
	{"tier": 1, "name": "Rift, tier I", "blurb": "A young rift. Five minutes to collapse.",
		"main_path": 6, "branches": 2, "min_exit_depth": 4, "min_exit_spread": 3,
		"instability": true, "collapse_time": 300.0, "enemy_health": 1.0, "enemy_damage": 1.0, "spawn_bonus": 0.0,
		"cutters": true, "caches": true, "void_crystals": true, "payout": 1.0, "tears": true},
	{"tier": 2, "name": "Rift, tier II", "blurb": "Deeper and meaner. Hostiles hit harder. Loot pays +30%.",
		"main_path": 7, "branches": 2, "min_exit_depth": 5, "min_exit_spread": 3,
		"instability": true, "collapse_time": 280.0, "enemy_health": 1.35, "enemy_damage": 1.25, "spawn_bonus": 0.15,
		"cutters": true, "caches": true, "void_crystals": true, "payout": 1.3, "tears": true},
	{"tier": 3, "name": "Rift, tier III", "blurb": "A dying rift. Brutal, fast collapse. Loot pays +60%.",
		"main_path": 8, "branches": 3, "min_exit_depth": 5, "min_exit_spread": 4,
		"instability": true, "collapse_time": 260.0, "enemy_health": 1.75, "enemy_damage": 1.5, "spawn_bonus": 0.3,
		"cutters": true, "caches": true, "void_crystals": true, "payout": 1.6, "tears": true},
]


## Settings for the picked site.
static func site() -> Dictionary:
	return SITES[clampi(tier, 0, SITES.size() - 1)]


## Picks the next run. Tutorial runs are forced until the Compass is found.
static func choose(new_tier: int) -> void:
	tutorial = not Profile.has_compass
	tier = 0 if tutorial else clampi(new_tier, 0, SITES.size() - 1)


static func is_unlocked(site_tier: int) -> bool:
	if site_tier == 0:
		return true
	return Profile.has_compass and site_tier <= Profile.max_tier


## Why a site is locked, for the star chart.
static func lock_reason(site_tier: int) -> String:
	if not Profile.has_compass:
		return "Needs a Rift Compass"
	return "Extract from tier %s first" % ["I", "II", "III"][site_tier - 2]
