class_name AimReticle
extends Node3D
## Ground-plane crosshair and aim line for a ship's cannon.
##
## With the mouse it sits under the cursor (and stands in for the hidden
## system cursor). With a stick it sits a fixed distance out along the aim,
## so right-stick aiming has a clear target point.

@export var ship: ShipController
## Reticle distance when aiming with a stick (no cursor point).
@export var stick_distance: float = 14.0
## Closest the reticle gets to the ship, so it never hides under the hull.
@export var min_distance: float = 3.0
@export var ring: Node3D
## Thin box stretched from the ship to the reticle.
@export var aim_line: Node3D
## Aim line starts this far out from the ship centre.
@export var line_start_offset: float = 2.0


func _ready() -> void:
	top_level = true
	# Follows the cursor every rendered frame, so skip interpolation lag.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(_delta: float) -> void:
	if ship == null:
		return
	var dir := ship.aim_direction
	var dist := ship.aim_distance if ship.aim_distance > 0.0 else stick_distance
	dist = maxf(dist, min_distance)
	var origin := ship.global_position
	var target := origin + dir * dist
	if ring != null:
		ring.global_position = target
	if aim_line != null:
		var start := origin + dir * line_start_offset
		var length := maxf(dist - line_start_offset - 0.9, 0.01)
		aim_line.visible = dist > line_start_offset + 1.0
		aim_line.global_position = start + dir * length * 0.5
		aim_line.global_basis = Basis.looking_at(dir, Vector3.UP)
		aim_line.scale = Vector3(1.0, 1.0, length)
