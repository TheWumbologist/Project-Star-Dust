class_name SaveSelect
extends Control
## Pick a save before going to the hangar: continue the latest one, load
## any slot, start a new game in a slot, or delete one. Deleting asks
## twice. Saves from older versions can't be loaded, only overwritten or
## deleted; the pre-slots save file is removed when this screen opens.

@onready var _slots: VBoxContainer = %Slots
@onready var _continue: Button = %ContinueButton
@onready var _note: Label = %Note

## Slot whose Delete button was pressed once and is waiting for a confirm.
var _confirm_delete: int = 0


func _ready() -> void:
	Hitstop.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Profile.remove_legacy_save():
		_note.text = "Your old save from an earlier version couldn't be read here, so it was removed."
	%BackButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.MAIN_MENU))
	_continue.pressed.connect(func(): play(Profile.latest_slot()))
	refresh()
	if _continue.visible:
		_continue.grab_focus()
	else:
		var first := slot_button(1)
		if first != null:
			first.grab_focus()


func refresh() -> void:
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	for n in range(1, Profile.SLOTS + 1):
		_slots.add_child(_slot_row(n))
	var latest := Profile.latest_slot()
	_continue.visible = latest > 0
	_continue.text = "Continue  (slot %d)" % latest


## Loads slot `n` (or starts a new game there if it's empty or unreadable)
## and goes to the hangar.
func play(n: int) -> void:
	if n <= 0:
		return
	if Profile.slot_info(n).get("compatible", false):
		Profile.select_slot(n)
	else:
		Profile.new_game(n)
	Scenes.go(get_tree(), Scenes.HANGAR)


## Starts over in slot `n`, wiping it, and goes to the hangar.
func new_game(n: int) -> void:
	Profile.new_game(n)
	Scenes.go(get_tree(), Scenes.HANGAR)


## First press arms the delete, the second one deletes.
func delete(n: int) -> bool:
	if _confirm_delete != n:
		_confirm_delete = n
		refresh()
		return false
	_confirm_delete = 0
	Profile.delete_slot(n)
	refresh()
	return true


## The main button (Play or New game) of slot `n`.
func slot_button(n: int) -> Button:
	return _slots.get_node_or_null("Slot%d/Play" % n) as Button


func delete_button(n: int) -> Button:
	return _slots.get_node_or_null("Slot%d/Delete" % n) as Button


func _slot_row(n: int) -> Control:
	var info := Profile.slot_info(n)
	var row := HBoxContainer.new()
	row.name = "Slot%d" % n
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(1060, 0)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 17)
	var play_button := Button.new()
	play_button.name = "Play"
	play_button.custom_minimum_size = Vector2(200, 0)
	play_button.add_theme_font_size_override("font_size", 18)
	var delete_button_ := Button.new()
	delete_button_.name = "Delete"
	delete_button_.custom_minimum_size = Vector2(170, 0)
	delete_button_.add_theme_font_size_override("font_size", 16)

	if info.is_empty():
		label.text = "Slot %d   Empty" % n
		label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.52))
		play_button.text = "New game"
		play_button.pressed.connect(new_game.bind(n))
		delete_button_.text = "Delete"
		delete_button_.disabled = true
	elif not info.compatible:
		label.text = "Slot %d   Old save from an earlier version (can't be loaded)" % n
		label.add_theme_color_override("font_color", Color(1, 0.55, 0.4))
		play_button.text = "New game"
		play_button.pressed.connect(new_game.bind(n))
	else:
		label.text = "Slot %d   %s\n%d credits   %d essence   %d runs, %d extracted   Saved %s" % [
			n, _progress(info), info.credits, info.essence, info.runs, info.extractions, _when(info.saved_at)]
		label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.78))
		play_button.text = "Play"
		play_button.pressed.connect(play.bind(n))
	if not info.is_empty():
		delete_button_.text = "Really delete?" if _confirm_delete == n else "Delete"
		if _confirm_delete == n:
			delete_button_.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	delete_button_.pressed.connect(delete.bind(n))
	for c in [label, play_button, delete_button_]:
		row.add_child(c)
	return row


func _progress(info: Dictionary) -> String:
	if not info.has_compass:
		return "Tutorial: find the Rift Compass"
	return "Rift tier %s open" % ["I", "II", "III"][clampi(info.max_tier, 1, 3) - 1]


func _when(unix: int) -> String:
	if unix <= 0:
		return "-"
	var t := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().bias) * 60)
	return "%04d-%02d-%02d %02d:%02d" % [t.year, t.month, t.day, t.hour, t.minute]
