class_name FlightHud
extends CanvasLayer
## In-run HUD: hull, shields, boost, torpedoes, cargo hold, speed, flight
## state callouts, and (inside a rift) the instability meter and the way
## to the nearest extraction point. Final UI (brass gauges, parchment) comes
## later. Sections hide when the ship or level lacks the matching part.

@export var ship: ShipController

@onready var _hull_bar: ProgressBar = %HullBar
@onready var _shield_bar: ProgressBar = %ShieldBar
@onready var _boost_bar: ProgressBar = %BoostBar
@onready var _heavy_label: Label = %HeavyLabel
@onready var _cargo_title: Label = %CargoTitle
@onready var _cargo_slots: HBoxContainer = %CargoSlots
@onready var _speed_label: Label = %SpeedLabel
@onready var _state_label: Label = %StateLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _banner: Label = %Banner
@onready var _help_panel: Control = %HelpPanel
@onready var _rift_panel: Control = %RiftPanel
@onready var _instability_label: Label = %InstabilityLabel
@onready var _instability_bar: ProgressBar = %InstabilityBar
@onready var _countdown_label: Label = %CountdownLabel
@onready var _edge_markers: EdgeMarkers = %EdgeMarkers
@onready var _extract_label: Label = %ExtractLabel
@onready var _extract_bar: ProgressBar = %ExtractBar

var _callout_text: String = ""
var _callout_time: float = 0.0
var _banner_time: float = 0.0
var _kills: int = 0
var _shots: int = 0
var _wave: int = 0
var _rift: RiftRun = null
var _bound: bool = false


func _ready() -> void:
	_rift_panel.visible = false
	if ship != null:
		bind(ship)


## Points the HUD at a ship and hooks up its signals. Safe to call once.
func bind(target: ShipController) -> void:
	if _bound or target == null:
		return
	_bound = true
	ship = target
	_edge_markers.ship = ship
	ship.drift_kicked.connect(func(tier): _callout("DRIFT KICK " + "I".repeat(tier)))
	ship.rammed.connect(func(_t): _callout("RAM!"))
	ship.picked_up.connect(func(item, count): _callout("+%d %s" % [count, item.display_name.to_upper()]))
	if ship.primary != null:
		ship.primary.fired.connect(func(_p): _shots += 1)
	if ship.health != null:
		ship.health.shield_broken.connect(func(): _callout("SHIELDS DOWN"))
	if ship.cargo != null:
		ship.cargo.changed.connect(_rebuild_cargo)
		ship.cargo.rejected.connect(func(_i): _callout("HOLD FULL"))
		_rebuild_cargo()
	_hull_bar.get_parent().visible = ship.health != null
	_heavy_label.visible = ship.heavy != null
	_cargo_title.visible = ship.cargo != null
	_cargo_slots.visible = ship.cargo != null

	for dummy in get_tree().get_nodes_in_group("damageable"):
		if dummy.has_signal("destroyed"):
			dummy.destroyed.connect(func(_d): _kills += 1)
	# Enemies spawn at runtime; count their deaths as they appear.
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().get_nodes_in_group("ships"):
		_on_node_added(node)
	var director := get_tree().get_first_node_in_group("encounter_director") as EncounterDirector
	if director != null:
		director.wave_started.connect(_on_wave_started)
		director.wave_cleared.connect(func(n): _show_banner("WAVE %d CLEARED" % n, 2.0))


func _on_node_added(node: Node) -> void:
	if node is ShipController and node != ship and not node.destroyed.is_connected(_on_enemy_destroyed):
		node.destroyed.connect(_on_enemy_destroyed)


func _on_enemy_destroyed(_enemy: ShipController) -> void:
	_kills += 1


func _on_wave_started(n: int) -> void:
	_wave = n
	_show_banner("WAVE %d" % n, 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		_help_panel.visible = not _help_panel.visible


func _process(delta: float) -> void:
	if ship == null:
		return
	if ship.health != null:
		_hull_bar.value = ship.health.hull / maxf(ship.health.max_hull, 1.0) * 100.0
		_shield_bar.value = ship.health.shield / maxf(ship.health.max_shield, 1.0) * 100.0
	_boost_bar.value = ship.boost_fuel * 100.0
	if ship.heavy != null:
		var pips := "#".repeat(ship.heavy.charges) + "-".repeat(ship.heavy.max_charges - ship.heavy.charges)
		_heavy_label.text = "TORPEDOES  [%s]" % pips
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

	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.visible = _banner_time > 0.0

	var wave_text := ("   wave %d" % _wave) if _wave > 0 else ""
	_stats_label.text = "FPS %d   shots %d   kills %d%s" % [
		Engine.get_frames_per_second(), _shots, _kills, wave_text]
	_update_rift()


func _update_rift() -> void:
	if _rift == null:
		_rift = get_tree().get_first_node_in_group("rift_run") as RiftRun
		if _rift == null:
			return
		_rift.stage_reached.connect(func(_stage, text): _show_banner(text, 3.0))
	_rift_panel.visible = true
	var pct := _rift.instability * 100.0
	_instability_label.text = "RIFT INSTABILITY  %d%%" % floori(pct)
	_instability_bar.value = pct
	# The countdown only appears once the rift starts destabilising.
	_countdown_label.visible = _rift.instability >= 0.5 and not _rift.ended
	if _countdown_label.visible:
		var left := _rift.time_to_collapse()
		_countdown_label.text = "COLLAPSE IN  %s" % _format_time(ceilf(left)) if left > 0.0 else "RIFT COLLAPSING"
	var exit := _rift.nearest_extraction(ship.global_position)
	if exit == null:
		_extract_label.text = ""
		_extract_bar.visible = false
		return
	var dist := exit.global_position.distance_to(ship.global_position)
	if exit.progress > 0.0:
		_extract_label.text = "EXTRACTING... hold position"
	else:
		_extract_label.text = "EXTRACTION  %d m  (follow the green arrow)" % roundi(dist)
	_extract_bar.visible = exit.progress > 0.0
	_extract_bar.value = exit.progress * 100.0


func _callout(text: String) -> void:
	_callout_text = text
	_callout_time = 1.2


func _show_banner(text: String, seconds: float) -> void:
	_banner.text = text
	_banner.visible = true
	_banner_time = seconds


func _rebuild_cargo() -> void:
	var hold := ship.cargo
	for child in _cargo_slots.get_children():
		child.queue_free()
	for i in hold.slot_count:
		_cargo_slots.add_child(make_slot_box(hold.slots[i] if i < hold.slots.size() else {}, 46))
	_cargo_title.text = "CARGO  %d/%d slots   worth %d cr" % [hold.slots.size(), hold.slot_count, hold.total_value()]


## A square cargo slot tile; `slot` is a hold entry or {} for empty.
static func make_slot_box(slot: Dictionary, size: float) -> Panel:
	var box := Panel.new()
	box.custom_minimum_size = Vector2(size, size)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.04, 0.85)
	style.set_border_width_all(2)
	style.border_color = Color(0.45, 0.34, 0.18)
	style.set_corner_radius_all(4)
	if not slot.is_empty():
		style.bg_color = Color(slot.item.color, 0.55)
		style.border_color = slot.item.color
		var label := Label.new()
		label.text = "%d" % slot.count
		label.add_theme_font_size_override("font_size", 18)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(label)
		box.tooltip_text = slot.item.display_name
	box.add_theme_stylebox_override("panel", style)
	return box


static func _format_time(seconds: float) -> String:
	return "%d:%02d" % [floori(seconds / 60.0), floori(fmod(seconds, 60.0))]
