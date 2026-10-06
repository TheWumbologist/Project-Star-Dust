extends Control
## Start screen: go to the hangar (and from there into a rift), open a
## test arena, or quit.

@onready var _rift_button: Button = %RiftButton


func _ready() -> void:
	Hitstop.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	%RiftButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.HANGAR))
	%CombatButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.COMBAT_ARENA))
	%FlightButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.FLIGHT_ARENA))
	%QuitButton.pressed.connect(func(): Scenes.quit(get_tree()))
	# Gamepad and keyboard navigation start on the first button.
	_rift_button.grab_focus()
