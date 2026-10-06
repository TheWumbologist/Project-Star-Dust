class_name EdgeMarkers
extends Control
## Arrows pinned to the screen edge that point at things outside the view:
## a big green chevron for the nearest extraction beacon (the Rift Compass
## reading), a gold one for the current objective (the tutorial derelict),
## and small red ones for nearby hostile ships. Nothing is drawn
## for things already on screen.

@export var ship: ShipController
## Gap between the arrows and the screen edge, in pixels.
@export var margin: float = 40.0
## Hostiles farther than this get no arrow.
@export var enemy_range: float = 85.0
@export var exit_color: Color = Color(0.35, 1.0, 0.55, 0.9)
@export var enemy_color: Color = Color(1.0, 0.3, 0.22, 0.85)
@export var objective_color: Color = Color(1.0, 0.78, 0.3, 0.95)

## What was drawn last frame, for tests: [{kind, screen_pos, direction}].
var markers: Array[Dictionary] = []

var _run: RiftRun = null
var _start_frame: int = 0


func _ready() -> void:
	_start_frame = Engine.get_process_frames()


func _process(_delta: float) -> void:
	markers.clear()
	var cam := get_viewport().get_camera_3d()
	# The camera's projection isn't set up until it has drawn a frame.
	if ship == null or cam == null or not ship.is_alive() or Engine.get_process_frames() - _start_frame < 3:
		queue_redraw()
		return
	if _run == null:
		_run = get_tree().get_first_node_in_group("rift_run") as RiftRun
	if _run != null and not _run.ended:
		var exit := _run.nearest_extraction(ship.global_position)
		if exit != null:
			_mark(cam, exit.global_position, &"exit")
		if is_instance_valid(_run.objective):
			_mark(cam, _run.objective.global_position, &"objective")
	for node in get_tree().get_nodes_in_group("ships"):
		var other := node as ShipController
		if other == null or other == ship or other.team == ship.team or not other.is_alive():
			continue
		if other.global_position.distance_to(ship.global_position) <= enemy_range:
			_mark(cam, other.global_position, &"enemy")
	queue_redraw()


## Adds an edge marker for `world_pos` if it is off screen.
func _mark(cam: Camera3D, world_pos: Vector3, kind: StringName) -> void:
	var rect := get_viewport_rect()
	var depth := -(cam.global_transform.affine_inverse() * world_pos).z
	if absf(depth) < 0.01:
		return # On the camera plane, where projecting it is undefined.
	var behind := depth < 0.0
	var p := cam.unproject_position(world_pos)
	if not behind and rect.grow(-margin * 0.5).has_point(p):
		return
	var centre := rect.size * 0.5
	var dir := (p - centre)
	if behind:
		dir = -dir
	if dir.length_squared() < 1.0:
		return
	dir = dir.normalized()
	# Slide out from the centre until the arrow meets the inset edge.
	var half := centre - Vector2(margin, margin)
	var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	markers.append({"kind": kind, "screen_pos": centre + dir * t, "direction": dir})


func _draw() -> void:
	for m in markers:
		var big: bool = m.kind != &"enemy"
		# Short and wide: a flat chevron pointing outward.
		var depth := 16.0 if big else 12.0
		var width := 46.0 if big else 28.0
		var notch := 6.0 if big else 3.5
		var col: Color = enemy_color
		if m.kind == &"exit":
			col = exit_color
		elif m.kind == &"objective":
			col = objective_color
		draw_set_transform(m.screen_pos, m.direction.angle(), Vector2.ONE)
		var pts := PackedVector2Array([
			Vector2(depth * 0.5, 0.0),
			Vector2(-depth * 0.5, -width * 0.5),
			Vector2(-depth * 0.5 + notch, 0.0),
			Vector2(-depth * 0.5, width * 0.5),
		])
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0, 0, 0, col.a * 0.7), 4.0, true)
		draw_colored_polygon(pts, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
