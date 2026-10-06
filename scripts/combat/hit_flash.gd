class_name HitFlash
extends Node
## Flashes a ship's meshes white when its hull is hit, and its shield bubble
## when shields soak the hit. Purely visual.

@export var health: Health
@export var body_meshes: Array[MeshInstance3D] = []
## Optional bubble shown briefly while shields absorb damage.
@export var shield_mesh: MeshInstance3D

var _hull_flash: float = 0.0
var _shield_flash: float = 0.0
var _overlay: StandardMaterial3D
var _shield_mat: StandardMaterial3D


func _ready() -> void:
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(1, 1, 1, 0)
	for m in body_meshes:
		m.material_overlay = _overlay
	if shield_mesh != null:
		_shield_mat = shield_mesh.get_active_material(0).duplicate() as StandardMaterial3D
		shield_mesh.material_override = _shield_mat
		shield_mesh.visible = false
	if health != null:
		health.damaged.connect(_on_damaged)


func _on_damaged(_amount: float, _source: Node) -> void:
	if health.shield > 0.0 and shield_mesh != null:
		_shield_flash = 1.0
	else:
		_hull_flash = 1.0


func _process(delta: float) -> void:
	_hull_flash = maxf(_hull_flash - delta * 6.0, 0.0)
	_overlay.albedo_color.a = _hull_flash * 0.8
	if shield_mesh != null:
		_shield_flash = maxf(_shield_flash - delta * 4.0, 0.0)
		shield_mesh.visible = _shield_flash > 0.0
		if _shield_mat != null:
			_shield_mat.albedo_color.a = _shield_flash * 0.5
