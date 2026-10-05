class_name ShipIntent
extends RefCounted
## What a pilot wants the ship to do this physics tick.
##
## The ship never reads Input directly; it only reads a ShipIntent. A local
## gamepad, mouse and keyboard, a test script, an AI pilot or (later) a co-op
## player's networked input can all produce one.

## World-space direction (XZ plane, normalised) the nose should turn toward,
## or ZERO to hold the current heading.
var steer: Vector3 = Vector3.ZERO
## Main engine, 0..1. The engine only ever pushes along the nose.
var thrust: float = 0.0
## Brake, 0..1.
var brake: float = 0.0
## World-space aim direction on the XZ plane (normalised), or ZERO for "keep
## aiming where you were".
var aim: Vector3 = Vector3.ZERO
## Distance to the aim point (the mouse cursor), or 0 when aiming with a
## stick and there is no specific point. Used to place the reticle.
var aim_distance: float = 0.0
var boost_held: bool = false
var drift_held: bool = false
var fire_held: bool = false
