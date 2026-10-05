class_name ShipStats
extends Resource
## Tunable handling numbers for one ship hull.
##
## Kept as a Resource so each hull (starter Sloop, Corsair, ...) is just a
## different .tres file, and so permanent hub parts can later produce a
## modified copy without touching the controller code.

@export_group("Thrust")
## Top cruising speed in metres per second.
@export var max_speed: float = 20.0
## How fast the ship reaches max_speed (m/s per second) at full stick.
@export var acceleration: float = 55.0
## Exponential slowdown per second when the stick is released.
@export var coast_drag: float = 1.6
## Exponential slowdown per second while above the current speed cap.
@export var overspeed_drag: float = 3.0

@export_group("Steering")
## How fast the hull turns toward the stick, in degrees per second.
@export var turn_rate_deg: float = 420.0
## How strongly sideways slide is cancelled (per second). High = grippy.
@export var grip: float = 7.0

@export_group("Boost")
## Instant speed added along the hull's heading when boost fires.
@export var boost_impulse: float = 16.0
## Speed cap while a boost is active.
@export var boost_max_speed: float = 38.0
## How long the raised cap lasts, in seconds.
@export var boost_duration: float = 0.45
## Boost meter cost per burst (meter runs 0..1).
@export var boost_cost: float = 0.34
## Meter refilled per second once recharge starts.
@export var boost_recharge_rate: float = 0.22
## Pause after a boost before the meter starts refilling.
@export var boost_recharge_delay: float = 0.8

@export_group("Drift")
## Grip while drifting. Low values let the ship slide sideways.
@export var drift_grip: float = 0.9
## Turn rate multiplier while drifting, so you can swing the nose round.
@export var drift_turn_multiplier: float = 1.35
## Minimum speed for a drift to count.
@export var drift_min_speed: float = 8.0
## A drift held at least this long, with enough slide angle, is "perfect".
@export var perfect_drift_min_time: float = 0.6
## Average angle between heading and velocity (degrees) a perfect drift needs.
@export var perfect_drift_min_angle_deg: float = 18.0
## Boost meter refilled by a perfect drift.
@export var perfect_drift_refill: float = 0.4

@export_group("Ramming")
## Damage dealt by hitting a target while a boost is active.
@export var ram_damage: float = 35.0
