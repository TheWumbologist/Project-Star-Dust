class_name RiftGenerator
extends Node3D
## Builds a rift from hand-made chunks at the start of a run.
##
## 1. Lay out a zone graph on a grid from the seed: a main path from the
##    start chunk, plus a few side branches.
## 2. Exits go at the far end of the main path and the deepest branch, and
##    never within `min_exit_depth` chunks of travel or `min_exit_spread`
##    grid cells (as the crow flies) of the start.
## 3. Fill every cell with a chunk that fits (start, exit, or a normal chunk
##    allowed at that depth), rotated a random quarter turn.
## 4. Build walls round every cell, with doorways where cells connect.
## 5. Roll each chunk's enemy spawn points and augment caches.
## Same seed, same rift.

signal generated

@export var start_chunks: Array[PackedScene] = []
@export var extract_chunks: Array[PackedScene] = []
@export var normal_chunks: Array[PackedScene] = []
@export var chunk_size: float = 80.0
## Cells after the start along the main path.
@export var main_path_length: int = 6
@export var branch_count: int = 2
@export var branch_length: Vector2i = Vector2i(1, 2)
## An exit must be at least this many chunks of travel from the start.
@export var min_exit_depth: int = 4
## ...and at least this many grid cells away in a straight line (counting
## across and down), so it isn't just behind the start chunk's wall.
@export var min_exit_spread: int = 3
@export var door_width: float = 26.0
@export var wall_thickness: float = 3.0
@export var floor_material: Material
@export var wall_material: Material
## Where generated enemies go (defaults to this node's parent).
@export var enemies_parent: Node

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## Vector2i cell -> {"depth": int, "chunk": RiftChunk}
var cells: Dictionary = {}
## Pairs of linked cells, stored both ways as "a|b" keys.
var links: Dictionary = {}
var extract_cells: Array[Vector2i] = []
var extraction_points: Array[ExtractionPoint] = []
var enemies: Array[ShipController] = []
var augment_caches: Array[AugmentCache] = []
var player_start: Vector3 = Vector3.ZERO
var layout_seed: int = 0


func generate(seed_value: int) -> void:
	var rng := plan_layout(seed_value)
	_place_chunks(rng)
	_build_walls()
	generated.emit()


## Steps 1 and 2 only: the zone graph and exits, no chunks. Returns the
## RNG so generate() carries on with the same random sequence.
func plan_layout(seed_value: int) -> RandomNumberGenerator:
	layout_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for attempt in 30:
		if _layout(rng):
			break
	_compute_depths()
	_pick_extracts()
	return rng


func cell_center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * chunk_size, 0.0, cell.y * chunk_size)


func cell_at(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / chunk_size), roundi(pos.z / chunk_size))


func is_linked(a: Vector2i, b: Vector2i) -> bool:
	return links.has(_key(a, b))


# --- Layout --------------------------------------------------------------------

func _layout(rng: RandomNumberGenerator) -> bool:
	cells.clear()
	links.clear()
	var path: Array[Vector2i] = [Vector2i.ZERO]
	cells[Vector2i.ZERO] = {}
	for i in maxi(main_path_length, min_exit_depth):
		var next = _free_neighbour(path.back(), rng)
		if next == null:
			return false
		_link(path.back(), next)
		path.append(next)
	if _spread(path.back()) < min_exit_spread:
		return false # Path curled back toward the start; try another.
	extract_cells = [path.back()]
	for b in branch_count:
		var from: Vector2i = path[rng.randi_range(1, maxi(path.size() - 2, 1))]
		var length := rng.randi_range(branch_length.x, branch_length.y)
		var at := from
		for i in length:
			var next = _free_neighbour(at, rng)
			if next == null:
				break
			_link(at, next)
			at = next
		if at != from:
			extract_cells.append(at)
	return true


## A random empty neighbouring cell, or null. Linking it marks it used.
func _free_neighbour(cell: Vector2i, rng: RandomNumberGenerator) -> Variant:
	var options: Array[Vector2i] = []
	for d in DIRS:
		var n: Vector2i = cell + d
		if not cells.has(n):
			options.append(n)
	if options.is_empty():
		return null
	var pick := options[rng.randi() % options.size()]
	cells[pick] = {}
	return pick


func _link(a: Vector2i, b: Vector2i) -> void:
	links[_key(a, b)] = true
	links[_key(b, a)] = true


func _key(a: Vector2i, b: Vector2i) -> String:
	return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]


func _compute_depths() -> void:
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	cells[Vector2i.ZERO]["depth"] = 0
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for d in DIRS:
			var n: Vector2i = cell + d
			if cells.has(n) and is_linked(cell, n) and not cells[n].has("depth"):
				cells[n]["depth"] = cells[cell]["depth"] + 1
				queue.append(n)


## Grid cells between `cell` and the start, across plus down.
func _spread(cell: Vector2i) -> int:
	return absi(cell.x) + absi(cell.y)


## Keep the main path's end, plus the deepest branch end (if it is far
## enough from the start to be worth it).
func _pick_extracts() -> void:
	var main_exit: Vector2i = extract_cells[0]
	var best: Vector2i = main_exit
	for cell in extract_cells.slice(1):
		if cells[cell]["depth"] >= min_exit_depth and _spread(cell) >= min_exit_spread and (best == main_exit or cells[cell]["depth"] > cells[best]["depth"]):
			best = cell
	extract_cells = [main_exit]
	if best != main_exit:
		extract_cells.append(best)


# --- Chunks --------------------------------------------------------------------

func _place_chunks(rng: RandomNumberGenerator) -> void:
	var parent := enemies_parent if enemies_parent != null else get_parent()
	var keys: Array = cells.keys()
	keys.sort_custom(func(a, b): return cells[a]["depth"] < cells[b]["depth"] or (cells[a]["depth"] == cells[b]["depth"] and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	var last_scene: PackedScene = null
	for cell in keys:
		var scene: PackedScene
		if cell == Vector2i.ZERO:
			scene = _pick(start_chunks, rng, 0, null)
		elif cell in extract_cells:
			scene = _pick(extract_chunks, rng, cells[cell]["depth"], null)
		else:
			scene = _pick(normal_chunks, rng, cells[cell]["depth"], last_scene)
		last_scene = scene
		var chunk := scene.instantiate() as RiftChunk
		chunk.name = "Chunk_%d_%d" % [cell.x, cell.y]
		add_child(chunk)
		chunk.position = cell_center(cell)
		# Start chunk keeps its authored facing so the player start is stable.
		if cell != Vector2i.ZERO:
			chunk.rotation.y = rng.randi_range(0, 3) * PI * 0.5
		cells[cell]["chunk"] = chunk
		_add_floor(chunk)
		_scan(chunk, rng, parent, cell == Vector2i.ZERO)


func _pick(pool: Array[PackedScene], rng: RandomNumberGenerator, depth: int, avoid: PackedScene) -> PackedScene:
	var options: Array[PackedScene] = []
	var weights: Array[float] = []
	for scene in pool:
		var state := scene.get_state()
		var min_depth := 0
		var weight := 1.0
		for i in state.get_node_property_count(0):
			match state.get_node_property_name(0, i):
				&"min_depth":
					min_depth = state.get_node_property_value(0, i)
				&"weight":
					weight = state.get_node_property_value(0, i)
		if depth >= min_depth and (scene != avoid or pool.size() == 1):
			options.append(scene)
			weights.append(weight)
	if options.is_empty():
		return pool[0]
	return options[rng.rand_weighted(PackedFloat32Array(weights))]


## Rolls enemy spawn points and collects beacons and the player start.
func _scan(node: Node, rng: RandomNumberGenerator, enemy_parent: Node, is_start: bool) -> void:
	for child in node.get_children():
		if child is EnemySpawnPoint:
			var enemy: ShipController = child.spawn(rng, enemy_parent)
			if enemy != null:
				enemies.append(enemy)
		elif child is ExtractionPoint:
			extraction_points.append(child)
		elif child is AugmentCache:
			if rng.randf() >= child.spawn_chance:
				child.free()
				continue
			augment_caches.append(child)
		elif is_start and child.name == &"PlayerStart":
			player_start = (child as Node3D).global_position
		_scan(child, rng, enemy_parent, is_start)


func _add_floor(chunk: RiftChunk) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(chunk_size, chunk_size)
	plane.material = floor_material
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	floor_mesh.mesh = plane
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.add_child(floor_mesh)
	floor_mesh.position = Vector3(0.0, -2.5, 0.0)


# --- Walls ---------------------------------------------------------------------

func _build_walls() -> void:
	var walls := Node3D.new()
	walls.name = "Walls"
	add_child(walls)
	var done := {}
	var half := chunk_size * 0.5
	for cell in cells:
		for d in DIRS:
			var n: Vector2i = cell + d
			var key := _key(cell, n)
			if done.has(key):
				continue
			done[key] = true
			done[_key(n, cell)] = true
			var mid := cell_center(cell) + Vector3(d.x, 0.0, d.y) * half
			var along := Vector3(absf(d.y), 0.0, absf(d.x)) # Edge direction.
			if is_linked(cell, n):
				# Two segments either side of a doorway.
				var seg := (chunk_size - door_width + wall_thickness) * 0.5
				var offset := door_width * 0.5 + seg * 0.5
				_wall(walls, mid + along * offset, along, seg)
				_wall(walls, mid - along * offset, along, seg)
			else:
				_wall(walls, mid, along, chunk_size + wall_thickness)


func _wall(parent: Node3D, center: Vector3, along: Vector3, length: float) -> void:
	var size := Vector3(length, 6.0, wall_thickness) if along.x > 0.5 else Vector3(wall_thickness, 6.0, length)
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = Vector3(size.x, 1.2, size.z)
	visual.material = wall_material
	mesh.mesh = visual
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	parent.add_child(body)
	body.position = center
