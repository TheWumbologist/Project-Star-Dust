class_name Hitstop
extends RefCounted
## Tiny freeze-frames for impact: big hits, kills and shield breaks briefly
## slow the whole game, which sells weight far more than numbers do.

static var _until_msec: int = 0
static var _generation: int = 0


## Slows time to `time_scale` for `seconds` of real time. A new stop that
## ends later replaces the current one; shorter ones are ignored.
static func freeze(tree: SceneTree, seconds: float, time_scale: float = 0.05) -> void:
	if tree == null or tree.paused:
		return
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	if until <= _until_msec:
		return
	_until_msec = until
	_generation += 1
	var mine := _generation
	Engine.time_scale = time_scale
	# Timers ignore time scale here, so the stop lasts real time. Only the
	# latest stop may end it.
	tree.create_timer(seconds, true, false, true).timeout.connect(func(): Hitstop._release(mine))


static func _release(generation: int) -> void:
	if generation == _generation:
		clear()


## Puts time back to normal right away (scene changes, menus).
static func clear() -> void:
	_until_msec = 0
	Engine.time_scale = 1.0
