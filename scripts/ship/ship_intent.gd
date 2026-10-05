class_name ShipIntent
extends RefCounted
## What a pilot wants the ship to do this physics tick.
##
## The ship never reads Input directly; it only reads a ShipIntent. A local
## gamepad, mouse and keyboard, a test script, an AI pilot or (later) a co-op
## player's networked input can all produce one.

## Desired travel direction on the ground plane (x = right, y = down screen).
## Length 0..1 is throttle.
var move: Vector2 = Vector2.ZERO
## World-space aim direction on the XZ plane (normalised), or ZERO for "keep
## aiming where you were".
var aim: Vector3 = Vector3.ZERO
var boost_pressed: bool = false
var drift_held: bool = false
var fire_held: bool = false
var grapple_pressed: bool = false
