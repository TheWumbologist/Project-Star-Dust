extends Control
## Start screen: pick a save (and from there the hangar and the rifts), open a
## test arena, or quit.

@onready var _rift_button: Button = %RiftButton


func _ready() -> void:
	Sfx.music(&"hub")
	Hitstop.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%RiftButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.SAVE_SELECT))
	%CombatButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.COMBAT_ARENA))
	%FlightButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.FLIGHT_ARENA))
	%QuitButton.pressed.connect(func(): Scenes.quit(get_tree()))
	# Gamepad and keyboard navigation start on the first button.
	_rift_button.grab_focus()
