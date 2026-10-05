class_name ItemDefinition
extends Resource
## One kind of loot, stored as data (one .tres per item) so new items need
## no code. Cargo for now; augments and parts join in the economy milestone.

enum Grade {
	COMMON, ## Scrap and ore: repairs and standard upgrades.
	RIFT, ## Void crystals, rift-forged parts: rifts only.
	ARTIFACT, ## Relics: sell for lots or upgrade the Rift Compass.
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var grade: Grade = Grade.COMMON
## How many fit in one cargo slot.
@export var stack_size: int = 10
## Colour for pickups and cargo slots until there are icons.
@export var color: Color = Color.WHITE
## Credits the fence pays per unit.
@export var value: int = 1
