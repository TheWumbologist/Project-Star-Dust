class_name Health
extends Node
## Hull and shields for anything that can be shot: ships, enemies, rocks.
##
## Shields soak damage first and recharge after a quiet spell; hull only
## comes back through repairs (hub shipwright, repair kits) or a respawn.
## The owner forwards `take_damage(amount, source)` here.

signal damaged(amount: float, source: Node)
signal shield_broken
signal died(source: Node)

@export var max_hull: float = 100.0
@export var max_shield: float = 0.0
## Seconds without taking damage before shields start recharging.
@export var shield_regen_delay: float = 3.0
## Shield points per second while recharging.
@export var shield_regen_rate: float = 20.0

var hull: float = 0.0
var shield: float = 0.0

var _since_hit: float = 0.0


func _ready() -> void:
	reset()


func _physics_process(delta: float) -> void:
	if is_dead() or shield >= max_shield:
		return
	_since_hit += delta
	if _since_hit >= shield_regen_delay:
		shield = minf(shield + shield_regen_rate * delta, max_shield)


func take_damage(amount: float, source: Node = null) -> void:
	if is_dead() or amount <= 0.0:
		return
	_since_hit = 0.0
	var had_shield := shield > 0.0
	var soaked := minf(shield, amount)
	shield -= soaked
	hull = maxf(hull - (amount - soaked), 0.0)
	damaged.emit(amount, source)
	if had_shield and shield <= 0.0:
		shield_broken.emit()
	if hull <= 0.0:
		died.emit(source)


func is_dead() -> bool:
	return hull <= 0.0


func reset() -> void:
	hull = max_hull
	shield = max_shield
	_since_hit = 0.0
