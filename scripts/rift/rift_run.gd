class_name RiftRun
extends Node3D
## Runs one trip into a rift: generates it, starts the player at the start
## chunk, and ends the run on extraction or death.
##
## Instability is the run clock. It climbs from 0 to 100% over
## `collapse_time`; as it rises, stray enemies warp in more often (no
## waves, just a growing trickle near the player), and at 100% the rift
## collapses and tears at the hull until you get out or die.

signal stage_reached(stage: int, text: String)
signal run_ended(extracted: bool)

@export var generator: RiftGenerator
@export var player: ShipController
@export var game_ui: GameUI
## 0 = a new rift every run; anything else always builds the same rift.
@export var layout_seed: int = 0
## Seconds from entering to full collapse.
@export var collapse_time: float = 300.0
@export var trickle_enemies: Array[PackedScene] = []
## Seconds between stray arrivals at 0% and at 100% instability.
@export var trickle_interval: Vector2 = Vector2(32.0, 6.0)
## Stray enemies arrive this far from the player.
@export var trickle_distance: Vector2 = Vector2(32.0, 48.0)
@export var warp_flash: PackedScene
## Hull damage per second once the rift has collapsed.
@export var collapse_damage: float = 12.0
## Seconds between the ending and the result card.
@export var end_card_delay: float = 1.2

const STAGES := [
	[0.5, "THE RIFT IS DESTABILISING"],
	[0.75, "RIFT CRITICAL - HOSTILES INBOUND"],
	[0.9, "COLLAPSE IMMINENT - EXTRACT NOW"],
	[1.0, "THE RIFT IS COLLAPSING"],
]

var instability: float = 0.0
var elapsed: float = 0.0
var ended: bool = false
var extracted: bool = false
var stage: int = 0

var _trickle_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("rift_run")
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var seed_value := layout_seed if layout_seed != 0 else randi_range(1, 999999)
	_rng.seed = seed_value + 1
	generator.generate(seed_value)
	player.global_position = generator.player_start
	player.reset_physics_interpolation()
	player.destroyed.connect(_on_player_destroyed)
	for point in generator.extraction_points:
		point.extracted.connect(_on_extracted)
	_trickle_timer = trickle_interval.x


func _physics_process(delta: float) -> void:
	if ended:
		return
	elapsed += delta
	instability = clampf(elapsed / maxf(collapse_time, 1.0), 0.0, 1.0)
	while stage < STAGES.size() and instability >= STAGES[stage][0]:
		stage_reached.emit(stage, STAGES[stage][1])
		stage += 1
	if game_ui != null:
		game_ui.screen_fx.instability = smoothstep(0.55, 1.0, instability)

	_trickle_timer -= delta
	if _trickle_timer <= 0.0:
		_trickle_timer = lerpf(trickle_interval.x, trickle_interval.y, instability)
		spawn_stray()

	if instability >= 1.0 and player.is_alive():
		player.take_damage(collapse_damage * delta, null)


## Seconds left before the rift fully collapses.
func time_to_collapse() -> float:
	return maxf(collapse_time - elapsed, 0.0)


## The extraction beacon closest to `from`, or null.
func nearest_extraction(from: Vector3) -> ExtractionPoint:
	var best: ExtractionPoint = null
	for point in generator.extraction_points:
		if is_instance_valid(point) and (best == null or point.global_position.distance_to(from) < best.global_position.distance_to(from)):
			best = point
	return best


## Warps one stray enemy in somewhere near (but not on top of) the player.
func spawn_stray() -> ShipController:
	if trickle_enemies.is_empty() or not player.is_alive():
		return null
	var pos = _stray_point()
	if pos == null:
		return null
	# Cutters get likelier as the rift destabilises.
	var scene: PackedScene = trickle_enemies[0]
	if trickle_enemies.size() > 1 and _rng.randf() < 0.15 + instability * 0.35:
		scene = trickle_enemies[_rng.randi_range(1, trickle_enemies.size() - 1)]
	if warp_flash != null:
		var flash := warp_flash.instantiate() as Node3D
		add_child(flash)
		flash.global_position = pos
	var enemy := scene.instantiate() as ShipController
	generator.enemies_parent.add_child(enemy)
	enemy.global_position = pos
	enemy.reset_physics_interpolation()
	return enemy


## A clear point inside the rift at trickle distance from the player.
func _stray_point() -> Variant:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 3.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var margin := 8.0
	var half := generator.chunk_size * 0.5 - margin
	for attempt in 20:
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(trickle_distance.x, trickle_distance.y)
		var pos := player.global_position + Vector3.FORWARD.rotated(Vector3.UP, angle) * dist
		pos.y = 0.0
		var cell := generator.cell_at(pos)
		if not generator.cells.has(cell):
			continue
		var local := pos - generator.cell_center(cell)
		if absf(local.x) > half or absf(local.z) > half:
			continue
		query.transform = Transform3D(Basis(), pos)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		return pos
	return null


func _on_extracted(ship: ShipController) -> void:
	if ended or ship != player:
		return
	ended = true
	extracted = true
	# Hand the ship to the beacon: stop flying, then shrink into the beam.
	player.input_source = null
	player.velocity = Vector3.ZERO
	player.collision_layer = 0 # Shots pass through while beaming out.
	if player.visual_root != null:
		var tween := create_tween()
		tween.tween_property(player.visual_root, "scale", Vector3(0.05, 4.0, 0.05), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if game_ui != null:
		game_ui.camera.add_shake(0.5)
	run_ended.emit(true)
	await get_tree().create_timer(end_card_delay, true, false, true).timeout
	player.visible = false
	if game_ui != null:
		game_ui.show_end(true, "You escaped the rift with your cargo.", _extra_lines())


func _on_player_destroyed(_ship: ShipController) -> void:
	if ended:
		return
	ended = true
	run_ended.emit(false)
	await get_tree().create_timer(end_card_delay, true, false, true).timeout
	if game_ui != null:
		var why := "The rift collapsed around you." if instability >= 1.0 else "Your ship broke apart in the rift."
		game_ui.show_end(false, why + " Everything in the hold is lost.", _extra_lines())


func _extra_lines() -> PackedStringArray:
	return [
		"Instability     %d%%" % floori(instability * 100.0),
		"Rift chunks     %d" % generator.cells.size(),
		"Rift seed       %d" % generator.layout_seed,
	]
