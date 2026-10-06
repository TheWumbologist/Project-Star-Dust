class_name RunEndScreen
extends CanvasLayer
## Full-screen result card shown when a run ends: "SHIP LOST" when the hull
## gives out, "EXTRACTED" when the player escapes a rift with their cargo.

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _stats: Label = %Stats
@onready var _retry: Button = %RetryButton
@onready var _backdrop: ColorRect = %Backdrop

var is_open: bool = false
var _continue_scene: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_retry.pressed.connect(_on_retry)
	%MenuButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.MAIN_MENU))


## Shows the card. `lines` are stat rows such as "Time  4:12". With a
## `continue_scene` the main button goes there instead of retrying.
func show_result(extracted: bool, subtitle: String, lines: PackedStringArray, continue_scene: String = "") -> void:
	_continue_scene = continue_scene
	is_open = true
	visible = true
	_title.text = "EXTRACTED" if extracted else "SHIP LOST"
	_title.add_theme_color_override("font_color", Color(0.55, 1, 0.65) if extracted else Color(1, 0.35, 0.25))
	_backdrop.color = Color(0.02, 0.08, 0.04, 0.0) if extracted else Color(0.12, 0.0, 0.0, 0.0)
	_subtitle.text = subtitle
	_stats.text = "\n".join(lines)
	if continue_scene != "":
		_retry.text = "To the hangar"
	else:
		_retry.text = "Run again" if extracted else "Try again"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	# Fade the backdrop in over the frozen scene.
	var tween := create_tween()
	tween.tween_property(_backdrop, "color:a", 0.75, 0.6)
	_retry.grab_focus()


func _on_retry() -> void:
	if _continue_scene != "":
		Scenes.go(get_tree(), _continue_scene)
	else:
		Scenes.restart(get_tree())
