@tool
class_name MineableAsteroid
extends Asteroid
## An asteroid with glowing ore veins. Shooting it chips ore loose as
## pickups (a torpedo blast chips several at once); once the ore is gone
## the rock crumbles.

@export var ore_item: ItemDefinition
## Ore units in the rock.
@export var ore_count: int = 8
## Damage needed to chip one unit loose.
@export var damage_per_ore: float = 12.0
@export var pickup_scene: PackedScene
## Visual spawned when the rock crumbles.
@export var crumble_explosion: PackedScene
## Glowing crystals dotted on the surface, removed as ore runs out.
@export var crystal_count: int = 8

var ore_left: int = 0

var _damage_banked: float = 0.0
var _crystals: Array[MeshInstance3D] = []
var _start_radius: float = 0.0


func _ready() -> void:
	super._ready()
	ore_left = ore_count
	_start_radius = radius
	_build_crystals()


func take_damage(amount: float, source: Node = null) -> void:
	if Engine.is_editor_hint() or ore_left <= 0:
		return
	_damage_banked += amount
	var chips := 0
	while _damage_banked >= damage_per_ore and ore_left - chips > 0:
		_damage_banked -= damage_per_ore
		chips += 1
	if chips == 0:
		return
	ore_left -= chips
	_eject(chips, source)
	_update_crystals()
	if ore_left <= 0:
		_crumble()


func _eject(count: int, source: Node) -> void:
	if pickup_scene == null or ore_item == null:
		return
	# Chips fly off the side facing whoever shot it.
	var dir := Vector3.ZERO
	if source is Node3D:
		dir = source.global_position - global_position
		dir.y = 0.0
	var out := dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var spawn_at := global_position + out * (radius + 0.8)
	Pickup.scatter(pickup_scene, get_parent(), ore_item, count, spawn_at, out, 8.0)


func _crumble() -> void:
	if crumble_explosion != null:
		var boom := crumble_explosion.instantiate() as Explosion
		boom.radius = radius * 1.6
		get_parent().add_child(boom)
		boom.global_position = global_position
	queue_free()


func _build_crystals() -> void:
	var color := ore_item.color if ore_item != null else Color(0.4, 0.9, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.9, 1.8, 0.9)
	mesh.material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) # Same layout every time for a given rock.
	for i in crystal_count:
		var crystal := MeshInstance3D.new()
		crystal.mesh = mesh
		crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Upper half of the sphere, so they show from the tilted camera.
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		add_child(crystal) # Not owned, so the editor never saves these.
		crystal.position = dir * radius * 0.92
		crystal.basis = Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
		_crystals.append(crystal)


func _update_crystals() -> void:
	var keep := ceili(float(ore_left) / maxf(ore_count, 1) * _crystals.size())
	for i in _crystals.size():
		_crystals[i].visible = i < keep
	# Shrink as it is mined out; crystals follow the surface.
	var t := float(ore_left) / maxf(ore_count, 1)
	radius = lerpf(_start_radius * 0.6, _start_radius, t)
	for c in _crystals:
		c.position = c.position.normalized() * radius * 0.92
