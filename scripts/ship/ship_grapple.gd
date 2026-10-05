class_name ShipGrapple
extends Node3D
## Grapple hook: latch onto a nearby anchor (asteroid) roughly in the aim
## direction and swing around it on a fixed-length rope.
##
## The rope only pulls, never pushes, so the ship orbits the anchor while
## keeping its speed. Press grapple again (or wait out max_attach_time) to
## let go and fling off along the swing. Pulling salvage and light enemies
## comes later; anchors are any node in the "grapple_anchor" group.

signal attached(anchor: Node3D)
signal released

@export var max_range: float = 22.0
## Anchors this far off the aim direction (degrees) are ignored.
@export var aim_cone_deg: float = 50.0
@export var max_attach_time: float = 3.0
## Rope never gets shorter than this beyond the anchor's own radius.
@export var min_rope_slack: float = 2.0
## Small extra speed along the swing each second, so swings feel lively.
@export var swing_assist: float = 6.0
@export var cooldown: float = 0.35
## Visual rope; stretched between ship and anchor each frame.
@export var rope_mesh: MeshInstance3D

var anchor: Node3D = null
var rope_length: float = 0.0

var _attached_time: float = 0.0
var _cooldown_left: float = 0.0


func _ready() -> void:
	if rope_mesh != null:
		rope_mesh.top_level = true
		rope_mesh.visible = false


func is_attached() -> bool:
	return anchor != null


func tick(ship: ShipController, intent: ShipIntent, delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if intent.grapple_pressed:
		if is_attached():
			release()
		elif _cooldown_left <= 0.0:
			var target := find_anchor(ship)
			if target != null:
				_attach(ship, target)

	if is_attached():
		if not is_instance_valid(anchor):
			release()
			return
		_attached_time += delta
		if _attached_time >= max_attach_time:
			release()
			return
		_constrain(ship, delta)

	_update_rope(ship)


## Best anchor in range: closest to the aim direction, then nearest.
func find_anchor(ship: ShipController) -> Node3D:
	var best: Node3D = null
	var best_score := INF
	var cone_cos := cos(deg_to_rad(aim_cone_deg))
	for node in get_tree().get_nodes_in_group("grapple_anchor"):
		var candidate := node as Node3D
		if candidate == null:
			continue
		var offset := candidate.global_position - ship.global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist > max_range + _anchor_radius(candidate) or dist < 0.01:
			continue
		var facing := ship.aim_direction.dot(offset / dist)
		if facing < cone_cos:
			continue
		# Prefer anchors near the crosshair, break ties by distance.
		var score := (1.0 - facing) * 50.0 + dist
		if score < best_score:
			best_score = score
			best = candidate
	return best


func release() -> void:
	if anchor == null:
		return
	anchor = null
	_cooldown_left = cooldown
	if rope_mesh != null:
		rope_mesh.visible = false
	released.emit()


func _attach(ship: ShipController, target: Node3D) -> void:
	anchor = target
	_attached_time = 0.0
	var offset := ship.global_position - target.global_position
	offset.y = 0.0
	rope_length = maxf(offset.length(), _anchor_radius(target) + min_rope_slack)
	attached.emit(target)


## Removes outward velocity once the rope is taut, turning motion into orbit.
func _constrain(ship: ShipController, delta: float) -> void:
	var offset := ship.global_position - anchor.global_position
	offset.y = 0.0
	var dist := offset.length()
	if dist < 0.01:
		return
	var radial := offset / dist
	var tangent := Vector3.UP.cross(radial)
	if ship.velocity.dot(tangent) < 0.0:
		tangent = -tangent
	ship.velocity += tangent * swing_assist * delta

	if dist >= rope_length:
		var outward := ship.velocity.dot(radial)
		if outward > 0.0:
			ship.velocity -= radial * outward
		# Pull the ship back onto the rope so it doesn't creep outwards.
		ship.velocity -= radial * (dist - rope_length) / maxf(delta, 0.001) * 0.5


func _update_rope(ship: ShipController) -> void:
	if rope_mesh == null:
		return
	rope_mesh.visible = is_attached()
	if not is_attached():
		return
	var from := ship.global_position
	var to := anchor.global_position
	to.y = from.y
	var length := from.distance_to(to)
	if length < 0.01:
		return
	rope_mesh.global_position = (from + to) * 0.5
	rope_mesh.look_at(to, Vector3.UP)
	rope_mesh.scale = Vector3(1.0, 1.0, length)


func _anchor_radius(node: Node3D) -> float:
	var r = node.get("anchor_radius")
	return r if r is float else 0.0
