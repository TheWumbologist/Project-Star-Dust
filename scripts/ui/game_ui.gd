class_name GameUI
extends Node
## Everything drawn over a run: HUD, screen effects, pause menu, ship screen
## and the end-of-run card. Drop one into a level and point it at the
## player's ship and camera.
##
## Without a RiftRun in the level (the test arenas), losing the ship ends
## the run here; inside a rift, RiftRun decides how the run ends.

@export var ship: ShipController
@export var camera: RiftCamera
## Seconds of slow-motion after the ship is destroyed before the card.
@export var death_card_delay: float = 1.0

@onready var hud: FlightHud = $FlightHud
@onready var screen_fx: ScreenFx = $ScreenFx
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var ship_menu: ShipMenu = $ShipMenu
@onready var end_screen: RunEndScreen = $RunEndScreen
@onready var augment_picker: AugmentPicker = $AugmentPicker

var kills: int = 0
var elapsed: float = 0.0


func _ready() -> void:
	ship_menu.ship = ship
	hud.bind(ship)
	screen_fx.bind(ship, camera)
	pause_menu.opened.connect(func(): ship_menu.blocked = true)
	pause_menu.closed.connect(func(): ship_menu.blocked = false)
	ship_menu.opened.connect(func(): pause_menu.blocked = true)
	ship_menu.closed.connect(func(): pause_menu.blocked = false)
	augment_picker.opened.connect(_set_menus_blocked.bind(true))
	augment_picker.closed.connect(_set_menus_blocked.bind(false))
	augment_picker.picked.connect(_on_augment_picked)
	get_tree().node_added.connect(_on_node_added)
	if ship != null:
		ship.destroyed.connect(_on_ship_destroyed)


func _process(delta: float) -> void:
	if ship != null and ship.is_alive() and not end_screen.is_open:
		elapsed += delta


func _set_menus_blocked(blocked: bool) -> void:
	pause_menu.blocked = blocked
	ship_menu.blocked = blocked


func _on_augment_picked(augment: AugmentDefinition) -> void:
	if augment != null:
		hud._callout("AUGMENT: " + augment.display_name.to_upper())


func _on_node_added(node: Node) -> void:
	if node is ShipController and node != ship:
		node.destroyed.connect(func(_s): kills += 1)


func _on_ship_destroyed(_s: ShipController) -> void:
	if get_tree().get_first_node_in_group("rift_run") != null:
		return
	await get_tree().create_timer(death_card_delay, true, false, true).timeout
	show_end(false, "Your cargo is lost to the void.")


## Locks the menus and shows the end-of-run card with this run's numbers.
## With `continue_scene`, the card's main button goes there (the hangar)
## instead of restarting.
func show_end(extracted: bool, subtitle: String, extra: PackedStringArray = [], continue_scene: String = "") -> void:
	if end_screen.is_open:
		return
	if pause_menu.is_open:
		pause_menu.close()
	if ship_menu.is_open:
		ship_menu.close()
	if augment_picker.is_open:
		augment_picker.choose(null)
	pause_menu.blocked = true
	ship_menu.blocked = true
	var cargo_value := ship.cargo.total_value() if ship.cargo != null else 0
	var lines: PackedStringArray = [
		"Time            %s" % FlightHud._format_time(elapsed),
		"Enemies sunk    %d" % kills,
		("Cargo banked    %d cr" if extracted else "Cargo lost      %d cr") % cargo_value,
	]
	lines.append_array(extra)
	Hitstop.clear()
	end_screen.show_result(extracted, subtitle, lines, continue_scene)
