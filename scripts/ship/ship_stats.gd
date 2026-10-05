class_name ShipStats
extends Resource
## Tunable handling numbers for one ship hull.
##
## Kept as a Resource so each hull (starter Sloop, Corsair, ...) is just a
## different .tres file, and so permanent hub parts can later produce a
## modified copy without touching the controller code.

@export_group("Thrust")
## Top cruising speed in metres per second.
@export var max_speed: float = 22.0
## How fast the main engine reaches max_speed (m/s per second).
@export var acceleration: float = 45.0
## Exponential slowdown per second with the engine off. Low = floaty.
@export var coast_drag: float = 0.7
## Exponential slowdown per second at full brake.
@export var brake_drag: float = 3.5
## Exponential slowdown per second while above the current speed cap.
@export var overspeed_drag: float = 2.0

@export_group("Steering")
## How fast the nose turns toward the steering direction, degrees per second.
@export var turn_rate_deg: float = 380.0
## How strongly sideways slide is cancelled (per second). High = grippy.
@export var grip: float = 6.0

@export_group("Boost")
## Speed kick along the nose the moment boost is pressed.
@export var boost_kick: float = 8.0
## Extra acceleration while boost is held.
@export var boost_acceleration: float = 70.0
## Speed cap while boosting (and briefly after a drift kick).
@export var boost_max_speed: float = 40.0
## Fuel burned per second while boosting (fuel runs 0..1, so 0.5 = 2 s tank).
@export var boost_drain_rate: float = 0.5
## Fuel needed to start a boost, so an empty tank doesn't stutter.
@export var boost_min_start_fuel: float = 0.15
## Fuel refilled per second once recharge starts.
@export var boost_recharge_rate: float = 0.25
## Pause after boosting before fuel starts refilling.
@export var boost_recharge_delay: float = 0.7

@export_group("Drift")
## Grip while drifting. Very low values make the ship slide like ice.
@export var drift_grip: float = 0.35
## Turn rate multiplier while drifting, so the nose swings round hard.
@export var drift_turn_multiplier: float = 1.7
## Minimum speed for a drift to start.
@export var drift_min_speed: float = 8.0
## Slide angle (degrees between nose and travel) that builds drift charge.
@export var drift_charge_min_angle_deg: float = 15.0
## Seconds of charge for a level 1 kick (blue sparks).
@export var drift_tier1_time: float = 0.5
## Seconds of charge for a level 2 kick (orange sparks).
@export var drift_tier2_time: float = 1.2
## Speed kick on release, per tier.
@export var drift_tier1_kick: float = 10.0
@export var drift_tier2_kick: float = 18.0
## Boost fuel refilled on release, per tier.
@export var drift_tier1_fuel: float = 0.15
@export var drift_tier2_fuel: float = 0.35
## How long the raised speed cap lasts after a drift kick, in seconds.
@export var drift_kick_duration: float = 0.7

@export_group("Ramming")
## Damage dealt by hitting a target while boosting.
@export var ram_damage: float = 35.0
