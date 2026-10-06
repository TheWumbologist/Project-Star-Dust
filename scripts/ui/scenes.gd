class_name Scenes
extends RefCounted
## Where the game's top-level scenes live, and the one safe way to switch
## between them (unpauses and resets any hitstop first).

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const RIFT := "res://scenes/rift/rift_run.tscn"
const HANGAR := "res://scenes/ui/hangar.tscn"
const COMBAT_ARENA := "res://scenes/test/combat_test.tscn"
const FLIGHT_ARENA := "res://scenes/test/flight_test.tscn"


static func go(tree: SceneTree, path: String) -> void:
	_reset(tree)
	tree.change_scene_to_file(path)


static func restart(tree: SceneTree) -> void:
	_reset(tree)
	tree.reload_current_scene()


static func quit(tree: SceneTree) -> void:
	_reset(tree)
	tree.quit()


static func _reset(tree: SceneTree) -> void:
	Hitstop.clear()
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
