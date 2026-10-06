class_name Minimap
extends Control
## Top-right rift map, centred on the ship. It starts dark and reveals the
## rift (floors, walls, rocks) around the ship as you fly, so it only shows
## where you've been. Dots on revealed ground: ore rocks in their ore's
## colour, salvage crates, wrecks, and teal squares for augment caches. Hostiles within sensor range are red dots
## sized by threat tier. The extraction beacons always show (the Rift
## Compass knows where they are), and so does the objective (a gold
## diamond). Rift tears show as violet slashes once seen. The map only
## ever shows the section the ship is in; each section keeps its own fog.
## Hidden outside a rift.

@export var ship: ShipController
## Metres from the ship to the edge of the map.
@export var view_radius: float = 100.0
## Flying reveals the map this far around the ship.
@export var reveal_radius: float = 42.0
## Hostiles closer than this show up.
@export var sensor_range: float = 75.0
## Metres per pixel of the stored map (lower = sharper, slower to build).
@export var resolution: float = 2.0

const FLOOR_COLOR := Color(0.22, 0.16, 0.36, 0.9)
const WALL_COLOR := Color(0.8, 0.62, 1.0, 1.0)
const ROCK_COLOR := Color(0.5, 0.44, 0.56, 1.0)
const CRATE_COLOR := Color(1.0, 0.82, 0.3)
const WRECK_COLOR := Color(1.0, 0.5, 0.2)
const EXIT_COLOR := Color(0.35, 1.0, 0.55)
const CACHE_COLOR := Color(0.4, 1.0, 0.9)
const OBJECTIVE_COLOR := Color(1.0, 0.78, 0.3)
const ENEMY_COLOR := Color(1.0, 0.22, 0.18)
const BORDER_COLOR := Color(0.75, 0.56, 0.25)
const TEAR_COLOR := Color(0.88, 0.45, 1.0)

var _run: RiftRun = null
var _gen: RiftGenerator = null
## Section index -> {map, fog, tex, seen, origin}, built when first needed.
var _sections: Dictionary = {}
## The section being drawn (the ship's).
var _section: int = 0
var _map: Image
var _fog: Image
var _tex: ImageTexture
var _origin: Vector2 = Vector2.ZERO
var _last_reveal: Vector3 = Vector3.INF
## {node, color, radius} for things that sit still on the map.
var _objects: Array[Dictionary] = []
## Plain rocks, painted into each section's map when it is built.
var _rocks: Array = []


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false


func _process(_delta: float) -> void:
	if _gen == null:
		_run = get_tree().get_first_node_in_group("rift_run") as RiftRun
		if _run == null or _run.generator == null or _run.generator.cells.is_empty() or ship == null:
			return
		_gen = _run.generator
		_collect(_gen)
		visible = true
	if is_instance_valid(ship):
		var here := _gen.section_of(ship.global_position)
		if here >= 0 and (here != _section or _map == null):
			_use(here)
	if is_instance_valid(ship) and ship.global_position.distance_to(_last_reveal) > 3.0:
		reveal_around(ship.global_position, reveal_radius)
		_last_reveal = ship.global_position
	queue_redraw()


## True once the ship has flown close enough to `world_pos` to map it.
func is_revealed(world_pos: Vector3) -> bool:
	var data := _data_at(world_pos)
	if data.is_empty():
		return false
	var map: Image = data.map
	var px := _to_pixel_in(world_pos, data.origin)
	if px.x < 0 or px.y < 0 or px.x >= map.get_width() or px.y >= map.get_height():
		return false
	return data.seen[px.y * map.get_width() + px.x] == 1


## Maps a disc of the rift around `world_pos`.
func reveal_around(world_pos: Vector3, radius: float) -> void:
	var data := _data_at(world_pos)
	if data.is_empty():
		return
	var map: Image = data.map
	var fog: Image = data.fog
	var seen: PackedByteArray = data.seen
	var c := _to_pixel_in(world_pos, data.origin)
	var r := ceili(radius / resolution)
	var w := map.get_width()
	var h := map.get_height()
	var changed := false
	for y in range(maxi(c.y - r, 0), mini(c.y + r + 1, h)):
		for x in range(maxi(c.x - r, 0), mini(c.x + r + 1, w)):
			var i := y * w + x
			if seen[i] == 1 or Vector2i(x - c.x, y - c.y).length_squared() > r * r:
				continue
			seen[i] = 1
			fog.set_pixel(x, y, map.get_pixel(x, y))
			changed = true
	data.seen = seen # Packed arrays are copied on read; store it back.
	if changed:
		(data.tex as ImageTexture).update(fog)


# --- Building the map ------------------------------------------------------------

## Switches the drawn map to section `k`.
func _use(k: int) -> void:
	var data := _data(k)
	_section = k
	_map = data.map
	_fog = data.fog
	_tex = data.tex
	_origin = data.origin
	_last_reveal = Vector3.INF


## The map data for the section under `world_pos`, or {} outside the rift.
func _data_at(world_pos: Vector3) -> Dictionary:
	if _gen == null:
		return {}
	var k := _gen.section_of(world_pos)
	return _data(k) if k >= 0 else {}


func _data(k: int) -> Dictionary:
	if not _sections.has(k):
		_sections[k] = _build(k)
	return _sections[k]


## Rasterises one section (floors, walls with doorways, rocks). It all
## starts hidden under the fog.
func _build(k: int) -> Dictionary:
	var cs := _gen.chunk_size
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for cell in _gen.cells:
		if _gen.cells[cell].get("section", 0) != k:
			continue
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var origin := Vector2((lo.x - 0.5) * cs, (lo.y - 0.5) * cs)
	var w := ceili((hi.x - lo.x + 1) * cs / resolution)
	var h := ceili((hi.y - lo.y + 1) * cs / resolution)
	var map := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var half := cs * 0.5
	var band := _gen.wall_thickness * 0.5 + resolution
	for y in h:
		for x in w:
			var p := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * resolution
			var cell := _gen.cell_at(Vector3(p.x, 0.0, p.y))
			if not _gen.cells.has(cell) or _gen.cells[cell].get("section", 0) != k:
				continue
			var local := p - Vector2(cell.x * cs, cell.y * cs)
			map.set_pixel(x, y, WALL_COLOR if _is_wall(cell, local, half, band) else FLOOR_COLOR)
	for rock in _rocks:
		if is_instance_valid(rock) and _gen.section_of(rock.global_position) == k:
			_paint_disc(map, origin, rock.global_position, rock.radius, ROCK_COLOR)
	var fog := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var seen := PackedByteArray()
	seen.resize(w * h)
	return {"map": map, "fog": fog, "tex": ImageTexture.create_from_image(fog), "seen": seen, "origin": origin}


func _is_wall(cell: Vector2i, local: Vector2, half: float, band: float) -> bool:
	for d: Vector2i in RiftGenerator.DIRS:
		var along_edge: float = local.x * d.x + local.y * d.y # Distance toward that side.
		if along_edge < half - band:
			continue
		var across: float = absf(local.x * d.y + local.y * d.x)
		if not _gen.is_linked(cell, cell + d) or across > _gen.door_width * 0.5:
			return true
	return false


func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is MineableAsteroid:
			var ore: ItemDefinition = child.ore_item
			_objects.append({"node": child, "color": ore.color if ore != null else ROCK_COLOR, "radius": 3.5})
		elif child is Asteroid:
			_rocks.append(child)
		elif child is SalvageCrate:
			_objects.append({"node": child, "color": CRATE_COLOR, "radius": 3.0})
		elif child.scene_file_path == "res://scenes/world/wreck.tscn":
			_objects.append({"node": child, "color": WRECK_COLOR, "radius": 4.5})
		_collect(child)


func _paint_disc(map: Image, origin: Vector2, world_pos: Vector3, radius: float, color: Color) -> void:
	var c := _to_pixel_in(world_pos, origin)
	var r := maxi(roundi(radius / resolution), 1)
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x >= 0 and y >= 0 and x < map.get_width() and y < map.get_height() and Vector2i(x - c.x, y - c.y).length_squared() <= r * r:
				map.set_pixel(x, y, color)


func _to_pixel_in(world_pos: Vector3, origin: Vector2) -> Vector2i:
	return Vector2i(((Vector2(world_pos.x, world_pos.z) - origin) / resolution).floor())


# --- Drawing -----------------------------------------------------------------------

func _draw() -> void:
	if _tex == null or not is_instance_valid(ship):
		return
	var centre := size * 0.5
	var px_per_m := size.x / (view_radius * 2.0)
	var me := Vector2(ship.global_position.x, ship.global_position.z)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.06, 0.78))
	var map_size := Vector2(_map.get_width(), _map.get_height()) * resolution * px_per_m
	draw_texture_rect(_tex, Rect2(centre + (_origin - me) * px_per_m, map_size), false)

	for o in visible_objects():
		draw_circle(_to_map(o.node.global_position, me, px_per_m, centre), o.radius, o.color)
	for cache in get_tree().get_nodes_in_group("augment_caches"):
		if is_revealed(cache.global_position):
			var at := _to_map(cache.global_position, me, px_per_m, centre)
			draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), CACHE_COLOR)
	for tear in _gen.tears:
		if tear.section == _section and is_revealed(tear.global_position):
			var at := _to_map(tear.global_position, me, px_per_m, centre)
			draw_line(at + Vector2(-3, 6), at + Vector2(1, 0), TEAR_COLOR, 2.5, true)
			draw_line(at + Vector2(1, 0), at + Vector2(-1, -2), TEAR_COLOR, 2.5, true)
			draw_line(at + Vector2(-1, -2), at + Vector2(3, -7), TEAR_COLOR, 2.5, true)
	for point in _gen.extraction_points:
		if is_instance_valid(point) and _gen.section_of(point.global_position) == _section:
			var at := _to_map(point.global_position, me, px_per_m, centre)
			draw_circle(at, 7.0, EXIT_COLOR, false, 2.5, true)
			draw_circle(at, 3.0, EXIT_COLOR)
	if is_instance_valid(_run.objective):
		var at := _to_map(_run.objective.global_position, me, px_per_m, centre)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -7), at + Vector2(6, 0), at + Vector2(0, 7), at + Vector2(-6, 0)]), OBJECTIVE_COLOR)
	for node in get_tree().get_nodes_in_group("ships"):
		var other := node as ShipController
		if other == null or other == ship or other.team == ship.team or not other.is_alive():
			continue
		if other.global_position.distance_to(ship.global_position) <= sensor_range:
			draw_circle(_to_map(other.global_position, me, px_per_m, centre), 2.0 + other.threat_tier * 1.5, ENEMY_COLOR)

	# The ship: a small arrow along its nose.
	var f := ship.forward()
	var fwd := Vector2(f.x, f.z).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([
		centre + fwd * 8.0, centre - fwd * 5.0 + side * 5.0, centre - fwd * 2.0, centre - fwd * 5.0 - side * 5.0,
	]), Color(1.0, 0.92, 0.7))
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 2.0)


## Mapped objects still in the rift and on revealed ground. Rocks that
## were mined out or crates that were cracked are dropped from the list.
func visible_objects() -> Array[Dictionary]:
	# Check validity before touching the node: a freed rock can't even be
	# assigned to a typed variable.
	_objects = _objects.filter(func(o): return is_instance_valid(o.node))
	var out: Array[Dictionary] = []
	for o in _objects:
		var node := o.node as Node3D
		if node.is_inside_tree() and is_revealed(node.global_position):
			out.append(o)
	return out


func _to_map(world_pos: Vector3, me: Vector2, px_per_m: float, centre: Vector2) -> Vector2:
	return centre + (Vector2(world_pos.x, world_pos.z) - me) * px_per_m
