class_name EncounterDirector
extends Node3D
## Sends waves of enemies at the arena: a short warning flash where each one
## warps in, then the next wave once the last one is cleared. Waves grow from
## a few scavenger drones to drone packs escorting pirate cutters.

signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal enemy_spawned(enemy: ShipController)

@export var drone_scene: PackedScene
@export var cutter_scene: PackedScene
## Flash shown where an enemy is about to appear.
@export var warp_flash: PackedScene
## Turn off to drive spawns by hand (tests).
@export var auto_start: bool = true
@export var first_wave_delay: float = 4.0
@export var intermission: float = 6.0
@export var warp_in_time: float = 0.8
## Enemies appear this far from the nearest player...
@export var spawn_distance: Vector2 = Vector2(38.0, 55.0)
## ...but inside the arena.
@export var arena_half_size: float = 100.0
@export var max_drones: int = 8
@export var max_cutters: int = 3

var wave: int = 0
var alive: Array[ShipController] = []

var _timer: float = 0.0
var _pending: int = 0
var _running: bool = false


func _ready() -> void:
	add_to_group("encounter_director")
	if auto_start:
		_running = true
		_timer = first_wave_delay


func _physics_process(delta: float) -> void:
	if not _running or _pending > 0:
		return
	if wave > 0 and not alive.is_empty():
		return
	if _timer > 0.0:
		_timer -= delta
		return
	start_wave(wave + 1)


func start_wave(n: int) -> void:
	_running = true
	wave = n
	var drones := mini(2 + n, max_drones)
	var cutters := mini(floori(n / 2.0), max_cutters)
	wave_started.emit(n)
	for i in drones:
		_warp_in(drone_scene)
	for i in cutters:
		_warp_in(cutter_scene)


## Spawns one enemy right away (no warning) at `pos`.
func spawn_now(scene: PackedScene, pos: Vector3) -> ShipController:
	var enemy := scene.instantiate() as ShipController
	get_parent().add_child(enemy)
	enemy.global_position = Vector3(pos.x, 0.0, pos.z)
	enemy.reset_physics_interpolation()
	alive.append(enemy)
	enemy.destroyed.connect(_on_enemy_destroyed)
	enemy.tree_exiting.connect(func(): alive.erase(enemy))
	enemy_spawned.emit(enemy)
	return enemy


func _warp_in(scene: PackedScene) -> void:
	if scene == null:
		return
	var pos := _pick_spawn_point()
	_pending += 1
	if warp_flash != null:
		var flash := warp_flash.instantiate() as Node3D
		get_parent().add_child(flash)
		flash.global_position = pos
	await get_tree().create_timer(warp_in_time, false, true).timeout
	_pending -= 1
	if is_inside_tree():
		spawn_now(scene, pos)


func _on_enemy_destroyed(enemy: ShipController) -> void:
	alive.erase(enemy)
	if alive.is_empty() and _pending == 0:
		_timer = intermission
		wave_cleared.emit(wave)


func _pick_spawn_point() -> Vector3:
	var center := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("ships"):
		if node is ShipController and node.team == 0 and node.is_alive():
			center = node.global_position
			break
	var limit := arena_half_size - 6.0
	var pos := center
	for attempt in 12:
		var angle := randf() * TAU
		pos = center + Vector3.FORWARD.rotated(Vector3.UP, angle) * randf_range(spawn_distance.x, spawn_distance.y)
		if absf(pos.x) < limit and absf(pos.z) < limit:
			break
	pos.x = clampf(pos.x, -limit, limit)
	pos.z = clampf(pos.z, -limit, limit)
	return pos
