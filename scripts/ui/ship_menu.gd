class_name ShipMenu
extends CanvasLayer
## Tab / Back: the ship screen. Pauses the game and shows four pages:
## ship stats, skills (what the ship can do), the augments fitted this run
## and the cargo hold, where cargo can be dumped slot by slot.

signal opened
signal closed

@export var ship: ShipController

@onready var _tabs: TabContainer = %Tabs
@onready var _stats_list: VBoxContainer = %StatsList
@onready var _skills_list: VBoxContainer = %SkillsList
@onready var _augment_grid: GridContainer = %AugmentGrid
@onready var _cargo_list: VBoxContainer = %CargoList
@onready var _cargo_summary: Label = %CargoSummary

var is_open: bool = false
## Set by GameUI while another overlay owns the screen.
var blocked: bool = false

const AUGMENT_SLOTS := 8

## Abilities shown on the Skills page: [name, controls, description, unlocked].
const SKILLS := [
	["Boost", "Shift / A (hold)", "Burns fuel for a big burst of speed. Fuel recharges after a moment off the throttle.", true],
	["Drift", "Space / B or LB (hold)", "Cut grip and slide. Hold a slide to charge it, let go for a speed kick and some fuel back.", true],
	["Ram", "Boost into a target", "Boosting into an enemy or rock hits it hard.", true],
	["Cannon", "Left click / RT", "Rapid-fire broadside. Chips ore loose from crystal asteroids.", true],
	["Torpedo", "Right click / RB", "Explodes on impact or at the cursor. Damages and shoves everything nearby.", true],
	["Jettison", "X / X", "Dump the last cargo slot to make room for something better.", true],
	["Salvage grapple", "Augment", "Grab loot and tear panels off wrecks. Found as an augment later.", false],
	["Shield flare", "Gadget", "Short burst of invulnerability. Unlocks with ship gadgets later.", false],
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	%CloseButton.pressed.connect(close)


# _input, not _unhandled_input: Tab is also the GUI's focus-next key, and
# the focused tab bar would swallow it before it reached us.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ship_menu"):
		if is_open and event.is_action_pressed("pause"):
			close()
			get_viewport().set_input_as_handled()
		return
	if is_open:
		close()
	elif not blocked and ship != null and ship.is_alive():
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	visible = true
	Hitstop.clear()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	_tabs.get_tab_bar().grab_focus()
	opened.emit()


func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	closed.emit()


func refresh() -> void:
	_fill_stats()
	_fill_skills()
	_fill_augments()
	_fill_cargo()


func _fill_stats() -> void:
	_clear(_stats_list)
	var s := ship.stats
	_heading(_stats_list, "SLOOP  (starter hull)")
	if ship.health != null:
		var h := ship.health
		_row(_stats_list, "Hull", "%d / %d" % [ceili(h.hull), roundi(h.max_hull)], "Only repaired at the shipwright.")
		_row(_stats_list, "Shields", "%d / %d" % [ceili(h.shield), roundi(h.max_shield)],
			"Recharge %d/s after %.0fs without a hit." % [roundi(h.shield_regen_rate), h.shield_regen_delay])
	_row(_stats_list, "Top speed", "%d m/s" % roundi(s.max_speed), "Boosting: %d m/s" % roundi(s.boost_max_speed))
	_row(_stats_list, "Acceleration", "%d m/s²" % roundi(s.acceleration), "")
	_row(_stats_list, "Boost fuel", "%d%%" % roundi(ship.boost_fuel * 100.0),
		"Full tank lasts %.1fs." % (1.0 / maxf(s.boost_drain_rate, 0.01)))
	_row(_stats_list, "Ram damage", "%d" % roundi(s.ram_damage), "")
	_heading(_stats_list, "WEAPONS")
	if ship.primary != null:
		var w := ship.primary
		_row(_stats_list, "Cannon", "%d dmg" % roundi(w.damage), "%.0f shots/s" % w.fire_rate)
	if ship.heavy != null:
		var t := ship.heavy
		_row(_stats_list, "Torpedoes", "%d dmg" % roundi(t.damage),
			"%d / %d charges, one every %.0fs" % [t.charges, t.max_charges, t.charge_time])
	if ship.cargo != null:
		_row(_stats_list, "Cargo hold", "%d slots" % ship.cargo.slot_count, "")


func _fill_skills() -> void:
	_clear(_skills_list)
	for skill in SKILLS:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var title := Label.new()
		title.text = ("%s   [%s]" % [skill[0], skill[1]]) if skill[3] else ("%s   (locked: %s)" % [skill[0], skill[1]])
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", Color(1, 0.8, 0.45) if skill[3] else Color(0.55, 0.5, 0.45))
		var desc := Label.new()
		desc.text = skill[2]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 15)
		desc.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7) if skill[3] else Color(0.5, 0.47, 0.42))
		box.add_child(title)
		box.add_child(desc)
		_skills_list.add_child(box)


func _fill_augments() -> void:
	_clear(_augment_grid)
	var loadout := ship.loadout
	var fitted: Array[AugmentDefinition] = []
	if loadout != null:
		fitted = loadout.augments
	var slots := loadout.augment_slots if loadout != null else AUGMENT_SLOTS
	for i in slots:
		if i < fitted.size():
			_augment_grid.add_child(_augment_tile(fitted[i]))
		else:
			var slot := FlightHud.make_slot_box({}, 72)
			slot.tooltip_text = "Empty augment slot. Fly into augment caches in the rift to fill it."
			_augment_grid.add_child(slot)


func _augment_tile(a: AugmentDefinition) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(150, 72)
	box.tooltip_text = "%s (%s)\n%s\nBreaks down into %d Void Essence if you extract." % [a.display_name, a.rarity_name(), a.description, a.essence_value]
	var title := Label.new()
	title.text = a.display_name
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", a.rarity_color())
	var desc := Label.new()
	desc.text = a.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(150, 0)
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.8, 0.76, 0.68))
	box.add_child(title)
	box.add_child(desc)
	return box


func _fill_cargo() -> void:
	_clear(_cargo_list)
	if ship.cargo == null:
		return
	var hold := ship.cargo
	for i in hold.slot_count:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var slot: Dictionary = hold.slots[i] if i < hold.slots.size() else {}
		row.add_child(FlightHud.make_slot_box(slot, 44))
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if slot.is_empty():
			label.text = "Empty"
			label.add_theme_color_override("font_color", Color(0.5, 0.47, 0.42))
			row.add_child(label)
		else:
			var item: ItemDefinition = slot.item
			label.text = "%s  x%d   (%d cr)" % [item.display_name, slot.count, slot.count * item.value]
			row.add_child(label)
			var dump := Button.new()
			dump.text = "Jettison"
			dump.add_theme_font_size_override("font_size", 16)
			dump.pressed.connect(_jettison.bind(i))
			row.add_child(dump)
		_cargo_list.add_child(row)
	_cargo_summary.text = "%d / %d slots used   ·   worth %d credits at the fence   ·   lost if the ship is destroyed" % [
		hold.slots.size(), hold.slot_count, hold.total_value()]


func _jettison(index: int) -> void:
	ship.jettison_slot(index)
	_fill_cargo()


func _heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(1, 0.75, 0.35))
	parent.add_child(label)


func _row(parent: Control, name_text: String, value: String, note: String) -> void:
	var row := HBoxContainer.new()
	var n := Label.new()
	n.text = name_text
	n.custom_minimum_size = Vector2(170, 0)
	var v := Label.new()
	v.text = value
	v.custom_minimum_size = Vector2(130, 0)
	v.add_theme_color_override("font_color", Color(1, 0.92, 0.75))
	var d := Label.new()
	d.text = note
	d.add_theme_font_size_override("font_size", 15)
	d.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	row.add_child(n)
	row.add_child(v)
	row.add_child(d)
	parent.add_child(row)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
