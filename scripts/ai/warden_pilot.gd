class_name WardenPilot
extends AIPilot
## Rift Warden: a rift-touched support ship. It keeps behind its allies
## (from the target's point of view), beams repairs into the most damaged
## one in reach, and lobs slow void orbs at the target. When it's hurt
## badly or the target gets close, it blinks: vanishes in a flash and
## reappears some way off. Kill it first, or the fight drags on.

## Repairs allies within this distance.
@export var beam_range: float = 18.0
## Hull (and shield) restored per second to the beamed ally.
@export var heal_rate: float = 9.0
@export var beam_color: Color = Color(0.4, 1.0, 0.75, 0.7)
## Blinks after losing this share of its max hull since the last blink...
@export_range(0.0, 1.0) var blink_damage_share: float = 0.25
## ...or when the target comes this close.
@export var blink_when_closer: float = 9.0
@export var blink_cooldown: float = 5.0
## Where it may blink to: this far from the target (min, max).
@export var blink_distance: Vector2 = Vector2(16.0, 24.0)
@export var flash_scene: PackedScene

## The ally being repaired, or null.
var patient: ShipController = null
var blinks: int = 0

var _blink_wait: float = 2.0
var _hull_at_blink: float = -1.0
var _beam: MeshInstance3D
var _beam_material: StandardMaterial3D


func _ready() -> void:
	super()
	_beam_material = StandardMaterial3D.new()
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_material.albedo_color = beam_color
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.12
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 1
	mesh.material = _beam_material
	_beam = MeshInstance3D.new()
	_beam.name = "RepairBeam"
	_beam.mesh = mesh
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.visible = false
	add_child(_beam)


func _fly(me: ShipController, intent: ShipIntent, delta: float) -> void:
	_support(me, delta)
	var dist := _distance(me)
	var dir := _direction(me)
	var ally := _nearest_ally(me, 40.0)
	if ally != null:
		# Tuck in behind the ally, on the far side from the target.
		var behind := ally.global_position - target.global_position
		behind.y = 0.0
		var spot := ally.global_position + behind.normalized() * 9.0
		var to := spot - me.global_position
		to.y = 0.0
		if to.length() > 3.0:
			intent.steer = _avoid(me, to.normalized())
			intent.thrust = clampf(to.length() / 10.0, 0.3, 1.0)
	else:
		_hold_range(me, intent, dir, dist, preferred_range, orbit_bias)
		intent.steer = _avoid(me, intent.steer)
	_aim_with_lead(me, intent, shot_speed)
	intent.fire_held = dist <= fire_range and _burst(delta)
	_maybe_blink(me, dist, delta)


func _idle(me: ShipController, _intent: ShipIntent, delta: float) -> void:
	_support(me, delta)


## Repairs the most damaged ally in reach and draws the beam to it.
func _support(me: ShipController, delta: float) -> void:
	if patient == null or not is_instance_valid(patient) or not patient.is_alive() \
			or patient.global_position.distance_to(me.global_position) > beam_range \
			or patient.health.hull >= patient.health.max_hull:
		patient = _most_damaged_ally(me)
	if patient == null:
		_beam.visible = false
		return
	var h := patient.health
	h.hull = minf(h.hull + heal_rate * delta, h.max_hull)
	h.shield = minf(h.shield + heal_rate * delta, h.max_shield)
	var a := me.global_position + Vector3(0.0, 0.4, 0.0)
	var b := patient.global_position + Vector3(0.0, 0.4, 0.0)
	var length := a.distance_to(b)
	_beam.visible = length > 0.5
	if _beam.visible:
		# A cylinder stands along Y: point Y down the beam.
		var y := (b - a) / length
		var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		_beam.global_transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)
		_beam_material.albedo_color.a = beam_color.a * (0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.02))


func _maybe_blink(me: ShipController, dist: float, delta: float) -> void:
	_blink_wait -= delta
	if me.health == null:
		return
	if _hull_at_blink < 0.0:
		_hull_at_blink = me.health.hull
	var hurt := _hull_at_blink - me.health.hull >= me.health.max_hull * blink_damage_share
	if _blink_wait > 0.0 or not (hurt or dist < blink_when_closer):
		return
	var spot = _blink_spot(me)
	if spot == null:
		return
	_flash(me, me.global_position)
	me.global_position = spot
	me.velocity = Vector3.ZERO
	me.reset_physics_interpolation()
	_flash(me, spot)
	Sfx.play(&"blink", spot)
	_blink_wait = blink_cooldown
	_hull_at_blink = me.health.hull
	blinks += 1


## A clear spot at blink distance from the target, inside the rift.
func _blink_spot(me: ShipController) -> Variant:
	var space := me.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 2.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	for attempt in 12:
		var pos := target.global_position + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(blink_distance.x, blink_distance.y)
		pos.y = 0.0
		query.transform = Transform3D(Basis(), pos)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		# Don't blink through a wall into somewhere it can't fly out of.
		var ray := PhysicsRayQueryParameters3D.create(me.global_position, pos, 1)
		if space.intersect_ray(ray).is_empty():
			return pos
	return null


func _flash(me: ShipController, at: Vector3) -> void:
	if flash_scene == null:
		return
	var flash := flash_scene.instantiate() as Node3D
	if flash is Explosion:
		flash.sound = &""
	me.get_parent().add_child(flash)
	flash.global_position = at


func _nearest_ally(me: ShipController, within: float) -> ShipController:
	var best: ShipController = null
	for node in me.get_tree().get_nodes_in_group("ships"):
		var other := node as ShipController
		if other == null or other == me or other.team != me.team or not other.is_alive():
			continue
		var d := other.global_position.distance_to(me.global_position)
		if d < within:
			within = d
			best = other
	return best


func _most_damaged_ally(me: ShipController) -> ShipController:
	var best: ShipController = null
	var worst := 1.0
	for node in me.get_tree().get_nodes_in_group("ships"):
		var other := node as ShipController
		if other == null or other == me or other.team != me.team or not other.is_alive() or other.health == null:
			continue
		if other.global_position.distance_to(me.global_position) > beam_range:
			continue
		var share := other.health.hull / maxf(other.health.max_hull, 1.0)
		if share < worst:
			worst = share
			best = other
	return best
