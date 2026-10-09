class_name RiftGenerator
extends Node3D
## Builds a rift from hand-made chunks at the start of a run.
##
## Rifts are cut into sections of 1-3 chunks. Chunks inside a section join
## through open doorways; sections join only through rift tears, portals
## that pull the ship through to the next section. Sections sit far apart
## in space, so each one reads as its own pocket of the rift. The main
## line of sections runs from the start to the exit, and side sections hang
## off it as optional dead ends. Debris fields (use_tears off) are one open
## section, laid out as before.
##
## 1. Lay out a zone graph on a grid from the seed: a main path from the
##    start chunk, plus a few side branches.
## 2. Exits go at the far end of the main path and the deepest branch, and
##    never within `min_exit_depth` chunks of travel or `min_exit_spread`
##    grid cells (as the crow flies) of the start.
## 3. Fill every cell with a chunk that fits (start, exit, or a normal chunk
##    allowed at that depth), rotated a random quarter turn.
## 4. Build walls round every cell, with doorways where cells connect.
## 5. Roll each chunk's enemy spawn points (picking each one's enemy from
##    the EnemyRoster by role and tier) and augment caches.
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

@export_group("Rift tears")
## Split the rift into sections joined by tears. Off = one open layout.
@export var use_tears: bool = true
## Chunks per section (min, max).
@export var section_size: Vector2i = Vector2i(1, 3)
@export var tear_scene: PackedScene
## How far in from the chunk edge a tear sits, in metres.
@export var tear_inset: float = 9.0

@export_group("Site rules")
## Added to every enemy spawn point's chance (negative = emptier).
@export var spawn_chance_bonus: float = 0.0
## Odds of tier 1, 2 and 3 enemies at spawn points (see EnemyRoster).
## Deeper chunks lean toward the higher tiers the site allows.
@export var enemy_tier_odds: Array[float] = [1.0, 0.0, 0.0]
## Roles spawn points may hold (EnemyRoster.Role); points for any other
## role stay empty.
@export var enemy_roles: Array[int] = [0, 1, 2]
@export var allow_caches: bool = true
## Void crystal rocks and crate bonuses (rift loot) are removed when off.
@export var allow_void_crystals: bool = true

const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## Grid cells between section origins. A section reaches at most 2 cells
## from its origin, so neighbours stay at least 3 empty cells apart.
const SECTION_SPACING := 8

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
## One entry per section: {"cells": Array[Vector2i], "side": bool}. The
## main line comes first, in order from the start; side sections follow.
var sections: Array[Dictionary] = []
## Planned tear pairs: {"a": cell, "a_dir": Vector2i, "b": cell, "b_dir": Vector2i}.
var tear_plan: Array[Dictionary] = []
var tears: Array[RiftTear] = []


func generate(seed_value: int) -> void:
	var rng := plan_layout(seed_value)
	_place_chunks(rng)
	_build_walls()
	_place_tears()
	generated.emit()


## Steps 1 and 2 only: the zone graph and exits, no chunks. Returns the
## RNG so generate() carries on with the same random sequence.
func plan_layout(seed_value: int) -> RandomNumberGenerator:
	layout_seed = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	sections.clear()
	tear_plan.clear()
	for attempt in 30:
		if (_layout_sections(rng) if use_tears else _layout(rng)):
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


## Which section a point is in, or -1 outside the rift.
func section_of(pos: Vector3) -> int:
	var cell := cell_at(pos)
	if not cells.has(cell):
		return -1
	return cells[cell].get("section", 0)


## The section holding the (main) exit.
func exit_section() -> int:
	return cells[extract_cells[0]].get("section", 0) if not extract_cells.is_empty() else 0


## The tear in section `from` that leads one step closer to section `to`,
## or null when they are the same section or not joined.
func next_tear(from: int, to: int) -> RiftTear:
	if from == to or from < 0 or to < 0:
		return null
	# Walk back from the goal so each section knows its step toward it.
	var step := {to: null}
	var queue: Array[int] = [to]
	while not queue.is_empty():
		var at: int = queue.pop_front()
		for tear in tears:
			if tear.leads_to == at and not step.has(tear.section):
				step[tear.section] = tear
				queue.append(tear.section)
	return step.get(from) as RiftTear


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


## Sections joined by tears: a main line from the start to the exit, then
## side sections that hang off it.
func _layout_sections(rng: RandomNumberGenerator) -> bool:
	cells.clear()
	links.clear()
	sections.clear()
	tear_plan.clear()
	var left := maxi(main_path_length, min_exit_depth) + 1 # Plus the start.
	var sizes: Array[int] = []
	while left > 0:
		var n := mini(rng.randi_range(section_size.x, section_size.y), left)
		sizes.append(n)
		left -= n
	if sizes.size() < 2:
		sizes.assign([1, sizes[0] - 1] if sizes[0] > 1 else [1, 1])
	for k in sizes.size():
		var made := _make_section(Vector2i(k * SECTION_SPACING, 0), sizes[k], false, rng)
		if made.is_empty():
			return false
		if k > 0:
			if not _plan_tear(sections[k - 1].cells.back(), made[0], rng):
				return false
	var main_count := sections.size()
	extract_cells = [sections[main_count - 1].cells.back()]
	if _spread(extract_cells[0]) < min_exit_spread:
		return false
	for b in branch_count:
		# Hang it off any main section but the exit's, from a chunk with a
		# free wall for the tear.
		var options: Array[Vector2i] = []
		for k in maxi(main_count - 1, 1):
			for cell in sections[k].cells:
				if _free_sides(cell).size() > 0:
					options.append(cell)
		if options.is_empty():
			break
		var root: Vector2i = options[rng.randi() % options.size()]
		var origin := Vector2i(b * SECTION_SPACING, SECTION_SPACING)
		var made := _make_section(origin, rng.randi_range(branch_length.x, branch_length.y), true, rng)
		if made.is_empty() or not _plan_tear(root, made[0], rng):
			return false
	return true


## A section of `count` chunks walked out from `origin`. Returns its cells.
func _make_section(origin: Vector2i, count: int, side: bool, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var k := sections.size()
	var made: Array[Vector2i] = [origin]
	cells[origin] = {"section": k}
	for i in count - 1:
		var next = _free_neighbour(made.back(), rng)
		if next == null:
			return []
		cells[next]["section"] = k
		_link(made.back(), next)
		made.append(next)
	sections.append({"cells": made, "side": side})
	return made


## Walled sides of a cell not already holding a tear.
func _free_sides(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in DIRS:
		if is_linked(cell, cell + d):
			continue
		var used := false
		for t in tear_plan:
			if (t.a == cell and t.a_dir == d) or (t.b == cell and t.b_dir == d):
				used = true
		if not used:
			out.append(d)
	return out


func _plan_tear(a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> bool:
	var sides_a := _free_sides(a)
	var sides_b := _free_sides(b)
	if sides_a.is_empty() or sides_b.is_empty():
		return false
	tear_plan.append({"a": a, "a_dir": sides_a[rng.randi() % sides_a.size()], "b": b, "b_dir": sides_b[rng.randi() % sides_b.size()]})
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
		# Tears count as one step, like a doorway.
		for t in tear_plan:
			for pair in [[t.a, t.b], [t.b, t.a]]:
				if pair[0] == cell and not cells[pair[1]].has("depth"):
					cells[pair[1]]["depth"] = cells[cell]["depth"] + 1
					queue.append(pair[1])


## Grid cells between `cell` and the start, across plus down.
func _spread(cell: Vector2i) -> int:
	return absi(cell.x) + absi(cell.y)


## Keep the main path's end, plus the deepest branch end (if it is far
## enough from the start to be worth it).
func _pick_extracts() -> void:
	if use_tears:
		return # One exit, at the end of the last section.
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
	var max_depth := 1
	for cell in keys:
		max_depth = maxi(max_depth, cells[cell]["depth"])
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
		_scan(chunk, rng, parent, cell == Vector2i.ZERO, float(cells[cell]["depth"]) / max_depth)


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


## The roster's enemy for a spawn point (or stray) holding `hint`: the same
## role, with a tier rolled from the site's odds. `depth` (0..1) leans it
## tougher. Returns {"scene", "count"}, or {} when the role isn't allowed
## here. Enemies not on the roster come back unchanged.
func roster_pick(hint: PackedScene, rng: RandomNumberGenerator, depth: float = 0.0) -> Dictionary:
	if hint == null:
		return {}
	var e := EnemyRoster.entry_for_path(hint.resource_path)
	if e.is_empty():
		return {"scene": hint, "count": 1}
	if not (int(e.role) in enemy_roles):
		return {}
	var pick := EnemyRoster.entry(e.role, EnemyRoster.roll_tier(rng, enemy_tier_odds, depth))
	return {"scene": EnemyRoster.scene_of(pick), "count": rng.randi_range(pick.pack.x, pick.pack.y)}


## Rolls enemy spawn points and collects beacons and the player start.
func _scan(node: Node, rng: RandomNumberGenerator, enemy_parent: Node, is_start: bool, depth: float) -> void:
	for child in node.get_children():
		if child is EnemySpawnPoint:
			var pick := roster_pick(child.enemy, rng, depth)
			if not pick.is_empty():
				enemies.append_array(child.spawn(rng, enemy_parent, spawn_chance_bonus, pick.scene, pick.count))
		elif child is ExtractionPoint:
			extraction_points.append(child)
		elif child is MineableAsteroid and not allow_void_crystals and child.ore_item != null \
				and child.ore_item.grade != ItemDefinition.Grade.COMMON:
			child.free()
			continue
		elif child is SalvageCrate and not allow_void_crystals:
			child.bonus_chance = 0.0
		elif child is AugmentCache:
			if not allow_caches or rng.randf() >= child.spawn_chance:
				child.free()
				continue
			augment_caches.append(child)
		elif is_start and child.name == &"PlayerStart":
			player_start = (child as Node3D).global_position
		_scan(child, rng, enemy_parent, is_start, depth)


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


# --- Tears ---------------------------------------------------------------------

func _place_tears() -> void:
	tears.clear()
	if tear_scene == null:
		return
	var holder := Node3D.new()
	holder.name = "Tears"
	add_child(holder)
	for t in tear_plan:
		var a := _tear_at(holder, t.a, t.a_dir)
		var b := _tear_at(holder, t.b, t.b_dir)
		a.partner = b
		b.partner = a
		a.leads_to = b.section
		b.leads_to = a.section


func _tear_at(holder: Node3D, cell: Vector2i, dir: Vector2i) -> RiftTear:
	var tear := tear_scene.instantiate() as RiftTear
	tear.name = "Tear_%d_%d_%d_%d" % [cell.x, cell.y, dir.x, dir.y]
	holder.add_child(tear)
	var out := Vector3(dir.x, 0.0, dir.y)
	tear.position = cell_center(cell) + out * (chunk_size * 0.5 - tear_inset)
	tear.inward = -out
	tear.section = cells[cell].get("section", 0)
	tears.append(tear)
	_clear_around(cells[cell]["chunk"], tear.global_position, 7.0)
	return tear


## Frees loose rocks that would block a tear.
func _clear_around(node: Node, at: Vector3, radius: float) -> void:
	for child in node.get_children():
		if child is Asteroid and (child as Node3D).global_position.distance_to(at) < radius + (child as Asteroid).radius:
			child.free()
			continue
		_clear_around(child, at, radius)


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
