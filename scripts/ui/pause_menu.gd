class_name PauseMenu
extends CanvasLayer
## Esc / Start: pauses the run with Resume, Restart, Main menu and Quit.

signal opened
signal closed

@onready var _resume: Button = %ResumeButton

var is_open: bool = false
## Set by GameUI while another overlay (ship screen, run end) owns the screen.
var blocked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume.pressed.connect(close)
	%RestartButton.pressed.connect(func(): Scenes.restart(get_tree()))
	%MenuButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.MAIN_MENU))
	%QuitButton.pressed.connect(func(): Scenes.quit(get_tree()))


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if is_open:
		close()
	elif blocked:
		return # Let the overlay that owns the screen handle it.
	else:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	visible = true
	Hitstop.clear()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resume.grab_focus()
	opened.emit()


func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	closed.emit()
