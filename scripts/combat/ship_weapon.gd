class_name ShipWeapon
extends Node3D
## A ship-mounted gun that fires projectiles along the ship's aim,
## independent of heading. The ship ticks every ShipWeapon child it has.
##
## One script covers the slice's weapons through its settings: the primary
## cannon (fast, unlimited), the heavy torpedo tube (few charges that refill
## over time) and enemy guns (bursts, spread). Augments will hook in here.

signal fired(projectile: Projectile)

enum Slot {
	PRIMARY, ## Fires while `fire_held`.
	HEAVY, ## Fires while `heavy_held`.
}

@export var slot: Slot = Slot.PRIMARY
@export var projectile_scene: PackedScene

@export_group("Firing")
## Volleys per second while the trigger is held.
@export var fire_rate: float = 6.0
## Projectiles per volley, fanned across volley_spread_deg.
@export var shots_per_volley: int = 1
@export var volley_spread_deg: float = 0.0
## Random spread either side of the aim, in degrees.
@export var spread_deg: float = 1.5

@export_group("Projectile")
@export var projectile_speed: float = 60.0
@export var damage: float = 10.0
## How much of the ship's own velocity the shot inherits (0..1).
@export var inherit_velocity: float = 0.5
## Spawn distance from the ship centre, so shots clear the hull.
@export var muzzle_offset: float = 2.2
## When true and the pilot aims at a point (mouse), the shot stops there.
@export var detonate_at_aim_point: bool = false

@export_group("Charges")
## Shots before the weapon must recharge; 0 = unlimited.
@export var max_charges: int = 0
## Seconds to refill one charge.
@export var charge_time: float = 4.0

var charges: int = 0

var _cooldown: float = 0.0
var _recharge: float = 0.0


func _ready() -> void:
	charges = max_charges


func tick(ship: ShipController, intent: ShipIntent, delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if max_charges > 0 and charges < max_charges:
		_recharge += delta
		if _recharge >= charge_time:
			_recharge = 0.0
			charges += 1
	if _trigger_held(intent) and can_fire():
		_fire(ship)
		_cooldown = 1.0 / maxf(fire_rate, 0.01)
		if max_charges > 0:
			charges -= 1


func can_fire() -> bool:
	return _cooldown <= 0.0 and projectile_scene != null and (max_charges <= 0 or charges > 0)


## 0..1 progress toward the next charge (1 when full or unlimited).
func charge_progress() -> float:
	if max_charges <= 0 or charges >= max_charges:
		return 1.0
	return _recharge / maxf(charge_time, 0.01)


func _trigger_held(intent: ShipIntent) -> bool:
	return intent.heavy_held if slot == Slot.HEAVY else intent.fire_held


func _fire(ship: ShipController) -> void:
	var aim := ship.aim_direction.rotated(Vector3.UP, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	var count := maxi(shots_per_volley, 1)
	for i in count:
		var offset := 0.0
		if count > 1:
			offset = lerpf(-volley_spread_deg, volley_spread_deg, float(i) / (count - 1)) * 0.5
		_spawn(ship, aim.rotated(Vector3.UP, deg_to_rad(offset)))


func _spawn(ship: ShipController, dir: Vector3) -> void:
	var projectile := projectile_scene.instantiate() as Projectile
	projectile.shooter = ship
	projectile.damage = damage
	projectile.velocity = dir * projectile_speed + ship.velocity * inherit_velocity
	if detonate_at_aim_point and ship.aim_distance > muzzle_offset:
		projectile.max_distance = ship.aim_distance - muzzle_offset
	# Projectiles live in the level, not under the ship, so they don't turn
	# with it and survive if the ship is destroyed.
	ship.get_parent().add_child(projectile)
	projectile.global_position = ship.global_position + dir * muzzle_offset
	projectile.look_at(projectile.global_position + dir, Vector3.UP)
	fired.emit(projectile)
