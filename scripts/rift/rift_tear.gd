class_name RiftTear
extends Area3D
## A tear in the rift wall that pulls the player's ship through to its
## partner tear in another section, keeping its speed and pointing it into
## the new section. Tears work both ways. Enemies never follow.
##
## The generator places tears in pairs and fills in partner, section,
## leads_to and inward.

signal traversed(ship: ShipController)

## Arrive this far in front of the partner tear, so you don't fall straight
## back through.
@export var exit_offset: float = 10.0
## Seconds before either end of a pair works again after a trip.
@export var cooldown: float = 1.0
## Ships come out at least this fast.
@export var exit_speed: float = 10.0
@export var flash: PackedScene

var partner: RiftTear = null
## The section this end sits in, and the one its partner sits in.
var section: int = 0
var leads_to: int = 0
## Points from the tear into its chunk.
var inward: Vector3 = Vector3.FORWARD

var _ready_at: int = 0


func _ready() -> void:
	add_to_group("rift_tears")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	var ship := body as ShipController
	if ship == null or ship.team != 0 or not ship.is_alive() or partner == null:
		return
	if Time.get_ticks_msec() < _ready_at:
		return
	# Moving a body from inside its own physics callback is unreliable.
	pull_through.call_deferred(ship)


## Sends `ship` out of the partner tear.
func pull_through(ship: ShipController) -> void:
	if partner == null or not is_instance_valid(ship):
		return
	var until := Time.get_ticks_msec() + roundi(cooldown * 1000.0)
	_ready_at = until
	partner._ready_at = until
	_burst()
	var speed := maxf(ship.velocity.length(), exit_speed)
	var to := partner.global_position + partner.inward * exit_offset
	ship.global_position = Vector3(to.x, ship.global_position.y, to.z)
	ship.velocity = partner.inward * speed
	ship.rotation.y = atan2(-partner.inward.x, -partner.inward.z)
	ship.reset_physics_interpolation()
	var cam := get_viewport().get_camera_3d() as RiftCamera
	if cam != null and cam.target == ship:
		cam.snap()
		cam.add_shake(0.35)
	partner._burst() # The flash carries the warp sound.
	traversed.emit(ship)


func _burst() -> void:
	if flash == null or not is_inside_tree():
		return
	var fx := flash.instantiate() as Node3D
	get_parent().add_child(fx)
	fx.global_position = global_position
