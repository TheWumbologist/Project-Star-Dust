class_name EnemyRoster
extends RefCounted
## The rift's hostiles: three roles, each with a tier 1, 2 and 3 enemy that
## fights its own way (9 in all).
##
##   Role        Tier 1            Tier 2            Tier 3
##   Swarm       Scavenger Drone   Spark Mite        Void Wasp
##   Gunship     Pirate Cutter     Corsair Lancer    Broadside Galleon
##   Specialist  Scrap Hauler      Torpedo Ketch     Rift Warden
##
## Rift chunks place spawn points holding a tier 1 enemy; that enemy only
## says which role the point is for. When a rift is generated, each point
## rolls a tier from the site's odds (deeper chunks lean harder) and gets
## that role's enemy for the tier, so a chunk built once plays differently
## in every tier of rift. Strays that warp in mid-run are picked the same
## way.

enum Role {
	SWARM, ## Small, fast and numerous.
	GUNSHIP, ## Pirate crews with cannons.
	SPECIALIST, ## Odd jobs: mines, torpedoes, repairs.
}

## One entry per enemy. `pack` is how many a spawn point places (min, max);
## `cache` scales the run's augment cache drop chance when it dies.
const ENTRIES := [
	{"id": &"scavenger_drone", "name": "Scavenger Drone", "role": Role.SWARM, "tier": 1,
		"scene": "res://scenes/enemies/scavenger_drone.tscn", "pack": Vector2i(1, 1), "cache": 0.0,
		"blurb": "Circles you and plinks away. Weak alone."},
	{"id": &"spark_mite", "name": "Spark Mite", "role": Role.SWARM, "tier": 2,
		"scene": "res://scenes/enemies/spark_mite.tscn", "pack": Vector2i(2, 3), "cache": 0.0,
		"blurb": "Kamikaze. Rushes in, lights a fuse and blows up. Shoot it or drift clear."},
	{"id": &"void_wasp", "name": "Void Wasp", "role": Role.SWARM, "tier": 3,
		"scene": "res://scenes/enemies/void_wasp.tscn", "pack": Vector2i(2, 3), "cache": 0.4,
		"blurb": "Hit and run. Strafes past firing, peels away, comes back."},
	{"id": &"pirate_cutter", "name": "Pirate Cutter", "role": Role.GUNSHIP, "tier": 1,
		"scene": "res://scenes/enemies/pirate_cutter.tscn", "pack": Vector2i(1, 1), "cache": 1.0,
		"blurb": "Shielded raider. Shotgun volleys at mid range."},
	{"id": &"corsair_lancer", "name": "Corsair Lancer", "role": Role.GUNSHIP, "tier": 2,
		"scene": "res://scenes/enemies/corsair_lancer.tscn", "pack": Vector2i(1, 1), "cache": 1.2,
		"blurb": "Sniper. Hangs back, shows a red aim line, then fires one heavy lance. Keep moving."},
	{"id": &"broadside_galleon", "name": "Broadside Galleon", "role": Role.GUNSHIP, "tier": 3,
		"scene": "res://scenes/enemies/broadside_galleon.tscn", "pack": Vector2i(1, 1), "cache": 2.5,
		"blurb": "Slow, armoured warship. Turns side-on and fires full broadsides. Get to its bow or stern."},
	{"id": &"scrap_hauler", "name": "Scrap Hauler", "role": Role.SPECIALIST, "tier": 1,
		"scene": "res://scenes/enemies/scrap_hauler.tscn", "pack": Vector2i(1, 1), "cache": 1.0,
		"blurb": "Unarmed barge full of scrap. Runs away and drops mines behind it."},
	{"id": &"torpedo_ketch", "name": "Torpedo Ketch", "role": Role.SPECIALIST, "tier": 2,
		"scene": "res://scenes/enemies/torpedo_ketch.tscn", "pack": Vector2i(1, 1), "cache": 1.2,
		"blurb": "Lobs slow homing torpedoes. Boost or drift to shake them."},
	{"id": &"rift_warden", "name": "Rift Warden", "role": Role.SPECIALIST, "tier": 3,
		"scene": "res://scenes/enemies/rift_warden.tscn", "pack": Vector2i(1, 1), "cache": 2.0,
		"blurb": "Rift-touched medic. Beams repairs into its allies and blinks away when pressed. Kill it first."},
]

static var _scenes: Dictionary = {}


## The entry for a role and tier (1-3).
static func entry(role: int, tier: int) -> Dictionary:
	for e in ENTRIES:
		if e.role == role and e.tier == tier:
			return e
	return {}


## The entry whose scene is at `path`, or {} for enemies not on the roster.
static func entry_for_path(path: String) -> Dictionary:
	for e in ENTRIES:
		if e.scene == path:
			return e
	return {}


static func scene_of(e: Dictionary) -> PackedScene:
	if e.is_empty():
		return null
	if not _scenes.has(e.scene):
		_scenes[e.scene] = load(e.scene)
	return _scenes[e.scene]


## Rolls a tier from `weights` (odds of tier 1, 2, 3). `depth` (0..1, how
## deep in the rift) shifts the odds toward higher tiers that the site
## allows at all.
static func roll_tier(rng: RandomNumberGenerator, weights: Array, depth: float = 0.0) -> int:
	var odds := PackedFloat32Array()
	for k in 3:
		var w: float = weights[k] if k < weights.size() else 0.0
		odds.append(w * (1.0 + clampf(depth, 0.0, 1.0) * 0.8 * k) if w > 0.0 else 0.0)
	var total := 0.0
	for w in odds:
		total += w
	if total <= 0.0:
		return 1
	return rng.rand_weighted(odds) + 1
