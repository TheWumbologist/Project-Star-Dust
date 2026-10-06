class_name CompassDerelict
extends Area3D
## The dead rift runner's ship from the opening. A gold Rift Compass glows
## in its wreckage; fly into it to salvage the compass. Only the tutorial
## debris field places one.

signal collected

@export var spin_speed: float = 1.1

var taken: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	var compass := get_node_or_null("Compass") as Node3D
	if compass != null:
		compass.rotate_y(spin_speed * delta)
		compass.position.y = 1.8 + sin(Time.get_ticks_msec() * 0.0025) * 0.35


## Hands the compass to `ship` if it's the player's.
func take(ship: ShipController) -> bool:
	if taken or ship == null or ship.team != 0 or not ship.is_alive():
		return false
	taken = true
	var compass := get_node_or_null("Compass")
	if compass != null:
		compass.queue_free()
	var glow := get_node_or_null("CompassGlow") as OmniLight3D
	if glow != null:
		glow.visible = false
	Sfx.play(&"compass")
	collected.emit()
	return true


func _on_body_entered(body: Node) -> void:
	take(body as ShipController)
