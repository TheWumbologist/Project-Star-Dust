class_name ShipCannon
extends Node3D
## Broadside cannon that fires along the ship's aim, independent of heading.
##
## Placeholder primary weapon for the flight-feel milestone. The weapon
## system proper (primary / heavy / gadget slots, augment hooks) comes with
## the combat milestone.

signal fired(projectile: Node3D)

@export var projectile_scene: PackedScene
## Shots per second while the fire button is held.
@export var fire_rate: float = 6.0
@export var projectile_speed: float = 60.0
@export var damage: float = 10.0
## How much of the ship's own velocity the shot inherits (0..1).
@export var inherit_velocity: float = 0.5
## Spawn distance from the ship centre, so shots clear the hull.
@export var muzzle_offset: float = 2.2
## Random spread either side of the aim, in degrees.
@export var spread_deg: float = 1.5

var _cooldown: float = 0.0


func tick(ship: ShipController, intent: ShipIntent, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if intent.fire_held and _cooldown <= 0.0 and projectile_scene != null:
		_fire(ship)
		_cooldown = 1.0 / maxf(fire_rate, 0.01)


func _fire(ship: ShipController) -> void:
	var dir := ship.aim_direction.rotated(Vector3.UP, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	var projectile := projectile_scene.instantiate() as Projectile
	projectile.shooter = ship
	projectile.damage = damage
	projectile.velocity = dir * projectile_speed + ship.velocity * inherit_velocity
	# Projectiles live in the level, not under the ship, so they don't turn
	# with it and survive if the ship is destroyed.
	ship.get_parent().add_child(projectile)
	projectile.global_position = ship.global_position + dir * muzzle_offset
	projectile.look_at(projectile.global_position + dir, Vector3.UP)
	fired.emit(projectile)
