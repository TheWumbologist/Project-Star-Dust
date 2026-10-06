extends Node3D
## Combat and mining test arena (milestone 2). A debris field: shoot ore out
## of asteroids, fight waves of scavenger drones and pirate cutters, and
## fill the cargo hold. Waves are a testing aid; real rifts place their
## enemies when generated. R restarts; Esc opens the pause menu.
##
## Number keys 1-9 warp in one of the nine roster enemies (see
## EnemyRoster) ahead of the ship, to try each one out.

## Seconds the roster hint banner stays up at the start.
const HINT_TIME := 6.0


func _ready() -> void:
	Sfx.music(&"rift")
	# The ship's aim reticle replaces the system cursor.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var ui := get_node_or_null("GameUI") as GameUI
	if ui != null:
		ui.hud.show_banner.call_deferred("Keys 1-9 warp in roster enemies", HINT_TIME)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		Scenes.restart(get_tree())
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var n := key.physical_keycode - KEY_1
		if n >= 0 and n < EnemyRoster.ENTRIES.size():
			spawn_roster_enemy(n)
			get_viewport().set_input_as_handled()


## Warps in roster enemy `index` (0-8) about 30 m ahead of the player.
func spawn_roster_enemy(index: int) -> ShipController:
	var entry: Dictionary = EnemyRoster.ENTRIES[index]
	var director := get_node("EncounterDirector") as EncounterDirector
	var player := get_node("PlayerShip") as ShipController
	var at := player.global_position + player.forward() * 30.0
	at.x = clampf(at.x, -director.arena_half_size + 8.0, director.arena_half_size - 8.0)
	at.z = clampf(at.z, -director.arena_half_size + 8.0, director.arena_half_size - 8.0)
	if director.warp_flash != null:
		var flash := director.warp_flash.instantiate() as Node3D
		add_child(flash)
		flash.global_position = at
	var ui := get_node_or_null("GameUI") as GameUI
	if ui != null:
		ui.hud.show_banner("%s  (tier %d %s)  %s" % [entry.name.to_upper(), entry.tier,
			EnemyRoster.Role.keys()[entry.role].to_lower(), entry.blurb], 4.0)
	return director.spawn_now(EnemyRoster.scene_of(entry), at)
