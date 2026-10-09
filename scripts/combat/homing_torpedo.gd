class_name HomingTorpedo
extends Torpedo
## A slow torpedo that curves after the nearest hostile ship (the Torpedo
## Ketch's). It turns at a limited rate, so a sharp drift, a boost or a
## rock in the way shakes it off.

## Degrees per second it can turn toward its target.
@export var turn_rate_deg: float = 75.0
## Flies straight for this long after launch.
@export var arm_time: float = 0.3
## Only chases ships within this range.
@export var seek_range: float = 45.0

var _age: float = 0.0
var _team: int = -1


func _ready() -> void:
	super()
	if shooter is ShipController:
		_team = shooter.team


func _physics_process(delta: float) -> void:
	if not _done:
		_age += delta
		if _age >= arm_time:
			_home(delta)
	super(delta)


func _home(delta: float) -> void:
	var prey := _nearest_hostile()
	if prey == null:
		return
	var want := prey.global_position - global_position
	want.y = 0.0
	var speed := velocity.length()
	if want.length() < 0.1 or speed < 0.1:
		return
	var dir := velocity / speed
	var turn := clampf(dir.signed_angle_to(want.normalized(), Vector3.UP), -1.0, 1.0) * deg_to_rad(turn_rate_deg) * delta
	dir = dir.rotated(Vector3.UP, turn)
	velocity = dir * speed
	look_at(global_position + dir, Vector3.UP)


func _nearest_hostile() -> ShipController:
	var best: ShipController = null
	var best_dist := seek_range
	for node in get_tree().get_nodes_in_group("ships"):
		var ship := node as ShipController
		if ship == null or ship.team == _team or not ship.is_alive():
			continue
		var d := ship.global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = ship
	return best
