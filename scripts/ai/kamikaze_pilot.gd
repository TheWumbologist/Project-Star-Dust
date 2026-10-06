class_name KamikazePilot
extends AIPilot
## Spark Mite: weaves straight at its target, boosting once lined up, and
## lights its fuse when close. When the fuse burns down it blows itself up,
## hurting everything nearby. Shoot it on the way in (it pops harmlessly)
## or drift clear while the fuse blinks.

## Lights the fuse inside this distance.
@export var fuse_range: float = 6.0
## Seconds from fuse to blast: the player's window to get out.
@export var fuse_time: float = 0.75
@export var blast_radius: float = 7.0
@export var blast_damage: float = 30.0
@export var blast_knockback: float = 16.0
@export var blast_scene: PackedScene
## Blinks while the fuse burns.
@export var fuse_light: Node3D
## How far either side of the straight line it weaves on the way in.
@export_range(0.0, 1.0) var weave: float = 0.4

## Seconds left on the fuse, or < 0 before it's lit.
var fuse_left: float = -1.0

var _clock: float = 0.0


func _fly(me: ShipController, intent: ShipIntent, delta: float) -> void:
	var dist := _distance(me)
	var dir := _direction(me)
	_clock += delta
	if fuse_left < 0.0 and dist <= fuse_range:
		fuse_left = fuse_time
		Sfx.play(&"fuse", me.global_position)
	var sway := dir.cross(Vector3.UP) * sin(_clock * 5.0) * weave * clampf(dist / 20.0, 0.0, 1.0)
	intent.steer = _avoid(me, (dir + sway).normalized())
	intent.thrust = 1.0
	intent.boost_held = fuse_left < 0.0 and dist > 10.0 and me.forward().dot(dir) > 0.9
	_burn_fuse(me, delta)


func _idle(me: ShipController, intent: ShipIntent, delta: float) -> void:
	# A lit fuse keeps burning even if the target got away.
	if fuse_left >= 0.0:
		intent.thrust = 0.6
		_burn_fuse(me, delta)


func _burn_fuse(me: ShipController, delta: float) -> void:
	if fuse_left < 0.0:
		return
	fuse_left -= delta
	if fuse_light != null:
		# Blinks faster as it runs out.
		fuse_light.visible = fmod(fuse_left, lerpf(0.06, 0.2, fuse_left / fuse_time)) > 0.03
	if fuse_left <= 0.0:
		_detonate(me)


func _detonate(me: ShipController) -> void:
	fuse_left = -1.0
	if blast_scene != null:
		var boom := blast_scene.instantiate() as Explosion
		boom.radius = blast_radius
		boom.damage = blast_damage
		boom.knockback = blast_knockback
		boom.source = me
		boom.damage_mask = 2 | 4 # The player's ship and shootable targets.
		me.get_parent().add_child(boom)
		boom.global_position = me.global_position
	# Its own blast replaces the usual death puff, and it leaves no scrap
	# (it would land right on top of its victim).
	me.death_explosion = null
	var loot := me.get_node_or_null("Loot") as LootDropper
	if loot != null:
		loot.item = null
	if me.health != null:
		me.health.take_damage(me.health.hull + me.health.shield + 1.0, null)
