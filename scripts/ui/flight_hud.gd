class_name FlightHud
extends CanvasLayer
## Debug HUD for the flight test: boost meter, speed, flight state, hits,
## FPS and a controls card. Final UI (brass gauges, parchment) comes later.

@export var ship: ShipController

@onready var _boost_bar: ProgressBar = %BoostBar
@onready var _speed_label: Label = %SpeedLabel
@onready var _state_label: Label = %StateLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _help_panel: Control = %HelpPanel

var _callout_text: String = ""
var _callout_time: float = 0.0
var _kills: int = 0
var _shots: int = 0


func _ready() -> void:
	if ship == null:
		return
	ship.drift_kicked.connect(func(tier): _callout("DRIFT KICK " + "I".repeat(tier)))
	ship.rammed.connect(func(_t): _callout("RAM!"))
	if ship.cannon != null:
		ship.cannon.fired.connect(func(_p): _shots += 1)
	for dummy in get_tree().get_nodes_in_group("damageable"):
		if dummy.has_signal("destroyed"):
			dummy.destroyed.connect(func(_d): _kills += 1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help_panel.visible = not _help_panel.visible


func _process(delta: float) -> void:
	if ship == null:
		return
	_boost_bar.value = ship.boost_fuel * 100.0
	_speed_label.text = "SPEED  %4.1f m/s" % ship.speed()

	var states: PackedStringArray = []
	if ship.is_boosting():
		states.append("BOOST")
	if ship.is_drifting:
		states.append(["DRIFT", "DRIFT  >", "DRIFT  >>"][ship.drift_tier()])
	if _callout_time > 0.0:
		_callout_time -= delta
		states.append(_callout_text)
	_state_label.text = "  ".join(states)

	_stats_label.text = "FPS %d   shots %d   targets broken %d" % [
		Engine.get_frames_per_second(), _shots, _kills]


func _callout(text: String) -> void:
	_callout_text = text
	_callout_time = 1.2
