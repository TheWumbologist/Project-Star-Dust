class_name AugmentDefinition
extends Resource
## A run augment: a temporary ship modifier found in augment caches. It
## lasts for one run. Extract and it is broken down into Void Essence;
## die and it is lost. Stacks with copies of itself.

enum Rarity { COMMON, RARE, EPIC }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var rarity: Rarity = Rarity.COMMON
## Which ship stat it changes (see ShipLoadout.STATS).
@export var stat: StringName = &""
## How much: a fraction (0.25 = +25%) when `percent`, else a flat amount.
@export var amount: float = 0.0
@export var percent: bool = true
## Void Essence it breaks down into when you extract with it.
@export var essence_value: int = 5


func rarity_name() -> String:
	return ["Common", "Rare", "Epic"][rarity]


func rarity_color() -> Color:
	return [Color(0.8, 0.85, 0.9), Color(0.35, 0.7, 1.0), Color(0.85, 0.45, 1.0)][rarity]


## Pick weight: commons turn up most.
func weight() -> float:
	return [6.0, 3.0, 1.0][rarity]


func as_mod() -> Dictionary:
	return {"stat": stat, "amount": amount, "percent": percent}
