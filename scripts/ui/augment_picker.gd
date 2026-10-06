class_name AugmentPicker
extends CanvasLayer
## Opened by an augment cache: pauses the run and offers a few augments as
## cards. Pick one to fit it for the rest of the run, or leave them all.

signal opened
signal closed
## Emitted with the chosen augment, or null when the player left them.
signal picked(augment: AugmentDefinition)

const THEME := preload("res://resources/ui/menu_theme.tres")

var is_open: bool = false
var offered: Array[AugmentDefinition] = []

var _ship: ShipController
var _root: Control
var _cards: HBoxContainer
var _note: Label
var _leave: Button


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("augment_picker")
	_build()
	visible = false


# Swallow Esc and Tab while choosing so no other menu opens underneath.
func _input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or event.is_action_pressed("ship_menu")):
		get_viewport().set_input_as_handled()


func open(ship: ShipController, augments: Array[AugmentDefinition]) -> void:
	_ship = ship
	offered = augments
	is_open = true
	visible = true
	Hitstop.clear()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for child in _cards.get_children():
		child.queue_free()
	var full := ship.loadout == null or not ship.loadout.has_free_slot()
	_note.text = "Augment slots full (%d). Leave these or come back with room." % ship.loadout.augment_slots if full \
		else "Augments last this run. Extract and they break down into Void Essence; die and they're lost."
	var first: Button = null
	for a in augments:
		var card := _card(a, full)
		_cards.add_child(card)
		if first == null:
			first = card
	if first != null and not full:
		first.grab_focus()
	else:
		_leave.grab_focus()
	opened.emit()


## Fits `augment` (or nothing, when null) and resumes the run.
func choose(augment: AugmentDefinition) -> void:
	if not is_open:
		return
	if augment != null and _ship != null and _ship.loadout != null:
		_ship.loadout.add_augment(augment)
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	picked.emit(augment)
	closed.emit()


func _card(a: AugmentDefinition, disabled: bool) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(250, 190)
	card.disabled = disabled
	card.text = ""
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.95)
	style.set_border_width_all(3)
	style.border_color = a.rarity_color()
	style.set_corner_radius_all(8)
	card.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.12, 0.24, 0.98)
	hover.set_border_width_all(5)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("focus", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.add_theme_stylebox_override("disabled", style)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	var rarity := _label(a.rarity_name().to_upper(), 14, a.rarity_color())
	var title := _label(a.display_name, 22, Color(1, 0.92, 0.75))
	var desc := _label(a.description, 17, Color(0.85, 0.82, 0.75))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var essence := _label("Breaks down into %d essence" % a.essence_value, 13, Color(0.7, 0.55, 1.0))
	for l in [rarity, title, desc, essence]:
		box.add_child(l)
	card.add_child(box)
	card.pressed.connect(choose.bind(a))
	return card


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _build() -> void:
	_root = Control.new()
	_root.theme = THEME
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var title := _label("AUGMENT CACHE", 34, Color(0.45, 1.0, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_note = _label("", 16, Color(0.85, 0.8, 0.7))
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_note)
	_cards = HBoxContainer.new()
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards.add_theme_constant_override("separation", 18)
	col.add_child(_cards)
	var leave := Button.new()
	leave.name = "LeaveButton"
	leave.text = "Leave them"
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(choose.bind(null))
	col.add_child(leave)
	_leave = leave

