class_name ShipWeapon
extends Node3D
## A ship-mounted gun that fires projectiles along the ship's aim,
## independent of heading. The ship ticks every ShipWeapon child it has.
##
## One script covers the slice's weapons through its settings: the primary
## cannon (fast, unlimited), the heavy torpedo tube (few charges that refill
## over time) and enemy guns (bursts, spread). Augments will hook in here.

## `projectile` is usually a Projectile; mine racks fire ProximityMines.
signal fired(projectile: Node3D)

enum Slot {
	PRIMARY, ## Fires while `fire_held`.
	HEAVY, ## Fires while `heavy_held`.
}

@export var slot: Slot = Slot.PRIMARY
@export var projectile_scene: PackedScene
## Sound per shot; empty picks one (torpedo, player cannon or enemy gun).
@export var fire_sound: StringName = &""

@export_group("Firing")
## Volleys per second while the trigger is held.
@export var fire_rate: float = 6.0
## Projectiles per volley, fanned across volley_spread_deg.
@export var shots_per_volley: int = 1
@export var volley_spread_deg: float = 0.0
## Random spread either side of the aim, in degrees.
@export var spread_deg: float = 1.5
## Where the gun points, in degrees clockwise from the nose (90 = starboard
## side, -90 = port, 180 = astern). Only matters with a narrow arc or a
## fixed direction.
@export var mount_angle_deg: float = 0.0
## Only fires while the aim is within this many degrees of the mount
## (180 = any direction). Broadside batteries use a narrow arc.
@export_range(0.0, 180.0) var arc_deg: float = 180.0
## Shoots straight along the mount instead of at the aim (mines dropped
## astern).
@export var fixed_direction: bool = false

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
	if _trigger_held(intent) and can_fire() and in_arc(ship):
		_fire(ship)
		_cooldown = 1.0 / maxf(fire_rate, 0.01)
		if max_charges > 0:
			charges -= 1


func can_fire() -> bool:
	return _cooldown <= 0.0 and projectile_scene != null and (max_charges <= 0 or charges > 0)


## The direction the gun points, from the ship's heading.
func mount_direction(ship: ShipController) -> Vector3:
	return ship.forward().rotated(Vector3.UP, -deg_to_rad(mount_angle_deg))


## True when the ship's aim is inside this gun's firing arc.
func in_arc(ship: ShipController) -> bool:
	if arc_deg >= 180.0 or fixed_direction:
		return true
	return rad_to_deg(mount_direction(ship).angle_to(ship.aim_direction)) <= arc_deg


## 0..1 progress toward the next charge (1 when full or unlimited).
func charge_progress() -> float:
	if max_charges <= 0 or charges >= max_charges:
		return 1.0
	return _recharge / maxf(charge_time, 0.01)


func _trigger_held(intent: ShipIntent) -> bool:
	return intent.heavy_held if slot == Slot.HEAVY else intent.fire_held


func _fire(ship: ShipController) -> void:
	var base := mount_direction(ship) if fixed_direction else ship.aim_direction
	var aim := base.rotated(Vector3.UP, deg_to_rad(randf_range(-spread_deg, spread_deg)))
	var count := maxi(shots_per_volley, 1)
	for i in count:
		var offset := 0.0
		if count > 1:
			offset = lerpf(-volley_spread_deg, volley_spread_deg, float(i) / (count - 1)) * 0.5
		_spawn(ship, aim.rotated(Vector3.UP, deg_to_rad(offset)))


func _spawn(ship: ShipController, dir: Vector3) -> void:
	# Anything with shooter, damage and velocity properties can be fired.
	var projectile := projectile_scene.instantiate() as Node3D
	projectile.set("shooter", ship)
	projectile.set("damage", damage)
	projectile.set("velocity", dir * projectile_speed + ship.velocity * inherit_velocity)
	if detonate_at_aim_point and ship.aim_distance > muzzle_offset:
		projectile.set("max_distance", ship.aim_distance - muzzle_offset)
	# Projectiles live in the level, not under the ship, so they don't turn
	# with it and survive if the ship is destroyed.
	ship.get_parent().add_child(projectile)
	projectile.global_position = ship.global_position + dir * muzzle_offset
	projectile.look_at(projectile.global_position + dir, Vector3.UP)
	fired.emit(projectile)
	Sfx.play(_sound_for(ship), global_position)


func _sound_for(ship: ShipController) -> StringName:
	if fire_sound != &"":
		return fire_sound
	if slot == Slot.HEAVY:
		return &"torpedo"
	return &"cannon" if ship.team == 0 else &"enemy_shot"
