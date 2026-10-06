class_name AugmentCatalog
extends RefCounted
## Every augment in the game, and weighted rolls for caches.

const ALL: Array[AugmentDefinition] = [
	preload("res://resources/augments/overcharged_cannons.tres"),
	preload("res://resources/augments/rapid_loader.tres"),
	preload("res://resources/augments/reinforced_plating.tres"),
	preload("res://resources/augments/shield_capacitor.tres"),
	preload("res://resources/augments/afterburner_injectors.tres"),
	preload("res://resources/augments/battering_prow.tres"),
	preload("res://resources/augments/heavy_payload.tres"),
	preload("res://resources/augments/extra_tube.tres"),
	preload("res://resources/augments/drift_coils.tres"),
	preload("res://resources/augments/slipstream_fins.tres"),
]


## `count` different augments, commons likeliest.
static func roll(rng: RandomNumberGenerator, count: int) -> Array[AugmentDefinition]:
	var pool := ALL.duplicate()
	var out: Array[AugmentDefinition] = []
	while out.size() < count and not pool.is_empty():
		var weights := PackedFloat32Array()
		for a in pool:
			weights.append(a.weight())
		var i := rng.rand_weighted(weights)
		out.append(pool[i])
		pool.remove_at(i)
	return out
