class_name ScreenFx
extends CanvasLayer
## Drives the full-screen overlay (shaders/screen_fx.gdshader) and the
## camera's reactions from the player's ship: hit flashes and shake scaled
## by damage, hitstop on big hits and kills, speed streaks while boosting,
## a pulsing red edge at low hull and a purple edge as the rift destabilises.

@export var ship: ShipController
@export var camera: RiftCamera
@export var overlay: ColorRect
## Hull fraction below which the danger pulse starts.
@export var low_hull: float = 0.3
## A single hit at least this big triggers hitstop.
@export var big_hit: float = 15.0

var instability: float = 0.0

var _flash: float = 0.0
var _speed_lines: float = 0.0
var _material: ShaderMaterial


func _ready() -> void:
	if overlay != null:
		_material = overlay.material as ShaderMaterial
	if ship != null:
		bind(ship, camera)


## Points the effects at a ship (and the camera to shake). Call once.
func bind(target: ShipController, cam: RiftCamera) -> void:
	if target == null or target.damaged.is_connected(_on_damaged):
		return
	ship = target
	camera = cam
	ship.damaged.connect(_on_damaged)
	ship.boost_started.connect(func(): _speed_lines = maxf(_speed_lines, 0.6))
	ship.drift_kicked.connect(func(tier): _speed_lines = maxf(_speed_lines, 0.5 + 0.25 * tier))
	ship.rammed.connect(func(_t): Hitstop.freeze(get_tree(), 0.07))
	ship.destroyed.connect(_on_destroyed)
	if ship.health != null:
		ship.health.shield_broken.connect(_on_shield_broken)
	ship.get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	if ship == null or _material == null:
		return
	var fast := ship.is_fast() and ship.is_alive()
	var target_lines := clampf((ship.speed() - ship.stats.max_speed) / 12.0, 0.0, 1.0) if fast else 0.0
	_speed_lines = lerpf(_speed_lines, target_lines, 1.0 - exp(-4.0 * delta))
	_flash = maxf(_flash - delta * 3.0, 0.0)
	var danger := 0.0
	if ship.health != null and ship.is_alive():
		var frac := ship.health.hull / maxf(ship.health.max_hull, 1.0)
		danger = clampf((low_hull - frac) / low_hull, 0.0, 1.0)
	_material.set_shader_parameter("speed_lines", _speed_lines)
	_material.set_shader_parameter("flash", _flash)
	_material.set_shader_parameter("danger", danger)
	_material.set_shader_parameter("instability", instability)


func _on_damaged(amount: float, _source: Node) -> void:
	var shielded := ship.health != null and ship.health.shield > 0.0
	_flash = clampf(0.25 + amount / 30.0, 0.0, 0.9) * (0.6 if shielded else 1.0)
	_material.set_shader_parameter("flash_color", Color(0.4, 0.6, 1.0) if shielded else Color(1.0, 0.15, 0.1))
	if camera != null:
		camera.add_shake(clampf(amount / 25.0, 0.15, 0.9) * (0.6 if shielded else 1.0))
	if amount >= big_hit and not shielded:
		Hitstop.freeze(get_tree(), 0.06)


func _on_shield_broken() -> void:
	if camera != null:
		camera.add_shake(0.6)
	Hitstop.freeze(get_tree(), 0.08)


func _on_destroyed(_s: ShipController) -> void:
	_flash = 1.0
	_material.set_shader_parameter("flash_color", Color(1.0, 0.5, 0.2))
	if camera != null:
		camera.add_shake(1.0)
	# Slow-motion beat before the death screen.
	Hitstop.freeze(get_tree(), 0.9, 0.25)


## Enemies are spawned at runtime; hook their deaths for kill feedback.
func _on_node_added(node: Node) -> void:
	if node is ShipController and node != ship:
		node.destroyed.connect(_on_enemy_destroyed)


func _on_enemy_destroyed(enemy: ShipController) -> void:
	if not is_instance_valid(ship) or not ship.is_alive():
		return
	var near := enemy.global_position.distance_to(ship.global_position) < 45.0
	if camera != null and near:
		camera.add_shake(0.3)
	Hitstop.freeze(get_tree(), 0.045)
