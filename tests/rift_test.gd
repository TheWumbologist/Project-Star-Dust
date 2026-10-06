extends SceneTree
## Headless smoke test for milestone 3: the rift run, its menus and the
## start screen.
##
## Builds a rift from a fixed seed and checks the layout, walls, enemies,
## instability, stray arrivals, the edge arrows, extraction, collapse and death,
## plus the pause menu, ship screen and boost camera. Run from the project
## folder:
##   godot --headless --script res://tests/rift_test.gd
## Exit code 0 = all checks passed.

const RIFT := "res://scenes/rift/rift_run.tscn"
const MENU := "res://scenes/ui/main_menu.tscn"
const ScriptedInput := preload("res://tests/scripted_input.gd")
const ORE := preload("res://resources/items/ore.tres")
const SCRAP := preload("res://resources/items/scrap.tres")
const SEED := 4242

var _failures: PackedStringArray = []
var _input: ScriptedInput


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Never touch the real save.
	Profile.path = "user://test_rift_profile.json"
	Profile.save_dir = "user://test_rift_saves"
	Profile.legacy_path = "user://test_rift_legacy.json"
	Sfx.settings_path = "user://test_rift_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.path))
	Profile.load_profile()
	await _test_main_menu()
	await _test_save_select()
	var run := await _load_rift(SEED)
	await _test_layout(run)
	await _test_same_seed(run)
	await _test_minimap(run)
	await _test_instability(run)
	await _test_menus(run)
	await _test_camera(run)
	await _test_augment_cache(run)
	await _test_tears(run)
	await _test_extraction(run)
	run.queue_free()
	await process_frame
	await _test_hangar()
	run = await _load_rift(SEED + 1)
	_check(run.player.health.max_hull > 100.0, "hangar upgrades apply in the next rift (hull %.0f)" % run.player.health.max_hull)
	await _test_collapse_and_death(run)
	run.queue_free()
	await process_frame
	await _test_tutorial()
	await _test_tiers()
	Deployment.tier = 1
	Deployment.tutorial = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.path))

	# Let the audio server release playing sounds before quitting.
	Sfx.stop_all()
	await create_timer(1.0, true, false, true).timeout
	if _failures.is_empty():
		print("RIFT TEST: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("RIFT TEST FAIL: ", f)
		quit(1)


# --- Checks ------------------------------------------------------------------

func _test_main_menu() -> void:
	var menu: Control = load(MENU).instantiate()
	root.add_child(menu)
	await process_frame
	_check(menu.get_node("%RiftButton") is Button and menu.get_node("%QuitButton") is Button, "start screen has Enter the Rift and Quit")
	_check(menu.get_node("%RiftButton").has_focus(), "start screen focuses the first button for gamepads")
	menu.queue_free()
	await process_frame


func _test_save_select() -> void:
	var legacy := FileAccess.open(Profile.legacy_path, FileAccess.WRITE)
	legacy.store_string("{}")
	legacy.close()
	var screen: SaveSelect = load(Scenes.SAVE_SELECT).instantiate()
	root.add_child(screen)
	await process_frame
	_check(not FileAccess.file_exists(Profile.legacy_path) and "removed" in screen.get_node("%Note").text, "the save screen removes the old save and says so")
	_check(not screen.get_node("%ContinueButton").visible, "no Continue without a save")
	_check(screen.slot_button(1).text == "New game" and screen.slot_button(1).has_focus(), "empty slots offer a new game")
	Profile.new_game(2)
	Profile.credits = 321
	Profile.save()
	screen.refresh()
	await process_frame
	_check(screen.get_node("%ContinueButton").visible and "slot 2" in screen.get_node("%ContinueButton").text, "Continue picks the latest save")
	_check(screen.slot_button(2).text == "Play" and "321 credits" in screen.get_node("%Slots/Slot2").get_child(0).text, "a used slot shows its progress")
	_check(not screen.delete(2) and FileAccess.file_exists(Profile.slot_path(2)), "the first Delete press only asks")
	_check("Really" in screen.delete_button(2).text, "Delete asks to confirm")
	_check(screen.delete(2) and Profile.slot_info(2).is_empty(), "the second press deletes the save")
	screen.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.save_dir))
	Profile.path = "user://test_rift_profile.json"
	Profile.load_profile()


func _test_layout(run: RiftRun) -> void:
	var gen := run.generator
	var count := gen.cells.size()
	_check(count >= 7, "the rift has at least 7 chunks (%d)" % count)
	var reachable := true
	for cell in gen.cells:
		if not gen.cells[cell].has("depth"):
			reachable = false
	_check(reachable, "every chunk is reachable from the start")
	_check(gen.cells[Vector2i.ZERO]["chunk"].kind == RiftChunk.Kind.START, "the start cell holds the start chunk")
	_check(run.player.global_position.distance_to(gen.player_start) < 1.0, "the player starts at the start chunk")
	var exits := gen.extraction_points.size()
	_check(exits >= 1 and exits <= 2, "the rift has 1 or 2 extraction beacons (%d)" % exits)
	var far := true
	for cell in gen.extract_cells:
		if gen.cells[cell]["depth"] < gen.min_exit_depth or absi(cell.x) + absi(cell.y) < gen.min_exit_spread:
			far = false
	_check(far, "extraction is at least %d chunks of travel and %d cells away from the start" % [gen.min_exit_depth, gen.min_exit_spread])
	# The same rule over many layouts, without building chunks.
	var planner := RiftGenerator.new()
	var bad := 0
	for s in range(1, 401):
		planner.plan_layout(s)
		for cell in planner.extract_cells:
			if planner.cells[cell]["depth"] < planner.min_exit_depth or absi(cell.x) + absi(cell.y) < planner.min_exit_spread:
				bad += 1
	planner.free()
	_check(bad == 0, "no exit lands near the start across 400 random layouts (%d bad)" % bad)
	_check(gen.enemies.size() >= 4, "chunks place enemies when the rift is built (%d)" % gen.enemies.size())
	var start_clear := true
	for enemy in gen.enemies:
		if gen.cell_at(enemy.global_position) == Vector2i.ZERO:
			start_clear = false
	_check(start_clear, "the start chunk has no enemies")
	var caches_ok := true
	for cache in gen.augment_caches:
		caches_ok = caches_ok and cache.is_inside_tree()
	print("        (%d augment caches rolled)" % gen.augment_caches.size())
	_check(caches_ok, "rolled augment caches are in the rift")

	# Doorways are open, other edges are walled.
	var space := run.get_world_3d().direct_space_state
	var door_ok := true
	var wall_ok := true
	for cell in gen.cells:
		for d in RiftGenerator.DIRS:
			var from: Vector3 = gen.cell_center(cell)
			var to: Vector3 = from + Vector3(d.x, 0, d.y) * (gen.chunk_size * 0.5 + 4.0)
			# Run along the clear lane through the chunk centre.
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from + Vector3(d.x, 0, d.y) * 30.0, to, 1))
			var is_wall: bool = not hit.is_empty() and not (hit.collider is Asteroid) and not (hit.collider is SalvageCrate)
			if gen.is_linked(cell, cell + d) and is_wall:
				door_ok = false
			if not gen.is_linked(cell, cell + d) and not is_wall:
				wall_ok = false
	_check(door_ok, "connected chunks have an open doorway between them")
	_check(wall_ok, "every other chunk edge is walled off")


func _test_same_seed(run: RiftRun) -> void:
	var twin := await _load_rift(SEED)
	var same := twin.generator.cells.size() == run.generator.cells.size()
	for cell in run.generator.cells:
		if not twin.generator.cells.has(cell):
			same = false
		elif twin.generator.cells[cell]["chunk"].scene_file_path != run.generator.cells[cell]["chunk"].scene_file_path:
			same = false
	_check(same, "the same seed builds the same rift")
	twin.queue_free()
	await process_frame


func _test_minimap(run: RiftRun) -> void:
	var map := run.game_ui.hud.get_node("%Minimap") as Minimap
	await process_frame
	_check(map.visible, "the minimap shows in a rift")
	_check(map.is_revealed(run.player.global_position), "the minimap reveals where the ship is")
	var far := run.generator.cell_center(run.generator.extract_cells[0])
	_check(not map.is_revealed(far), "the far exit chunk stays dark until visited")
	map.reveal_around(far, 20.0)
	_check(map.is_revealed(far), "flying somewhere reveals it on the map")
	# Mining a rock out frees it; the map must just drop its dot.
	for cell in run.generator.cells:
		map.reveal_around(run.generator.cell_center(cell), 60.0)
	var before := map.visible_objects().size()
	var rock: MineableAsteroid = null
	for o in map.visible_objects():
		if o.node is MineableAsteroid:
			rock = o.node
	var mined := rock != null
	if mined:
		rock.free()
	map.queue_redraw()
	await process_frame
	await process_frame
	_check(mined and map.visible_objects().size() == before - 1, "a mined-out rock drops off the minimap (%d -> %d)" % [before, map.visible_objects().size()])
	var cutter: ShipController = load("res://scenes/enemies/broadside_galleon.tscn").instantiate()
	var drone: ShipController = load("res://scenes/enemies/scavenger_drone.tscn").instantiate()
	_check(cutter.threat_tier > drone.threat_tier, "tier 3 galleons get bigger map dots than tier 1 drones")
	cutter.free()
	drone.free()


func _test_instability(run: RiftRun) -> void:
	_check(run.instability < 0.05, "instability starts near zero")
	var stages: Array[int] = []
	run.stage_reached.connect(func(s, _t): stages.append(s))
	run.elapsed = run.collapse_time * 0.5 - 0.05
	await _frames(10)
	_check(stages == [0], "half way, the rift warns it is destabilising")
	var hud := run.game_ui.hud
	_check(hud.get_node("%RiftPanel").visible and "50%" in hud.get_node("%InstabilityLabel").text, "the HUD shows rift instability (%s)" % hud.get_node("%InstabilityLabel").text)
	var stray := run.spawn_stray()
	_check(stray != null, "stray enemies can warp in near the player")
	if stray != null:
		var dist := stray.global_position.distance_to(run.player.global_position)
		_check(dist >= run.trickle_distance.x - 0.5 and dist <= run.trickle_distance.y + 0.5, "strays arrive at a distance (%.0f m)" % dist)
		_check(run.generator.cells.has(run.generator.cell_at(stray.global_position)), "strays arrive inside the rift")
	var interval_low := lerpf(run.trickle_interval.x, run.trickle_interval.y, 0.0)
	var interval_high := lerpf(run.trickle_interval.x, run.trickle_interval.y, 1.0)
	_check(interval_high < interval_low, "strays arrive more often as instability rises")
	_check("COLLAPSE IN" in hud.get_node("%CountdownLabel").text and hud.get_node("%CountdownLabel").visible, "half way, a collapse countdown appears (%s)" % hud.get_node("%CountdownLabel").text)
	var markers := hud.get_node("%EdgeMarkers") as EdgeMarkers
	await process_frame
	# In another section the arrow points at the tear that leads toward it.
	var exit := run.way_out(run.player.global_position)
	var cam := run.game_ui.camera
	var exit_marks := markers.markers.filter(func(m): return m.kind == &"exit")
	var on_screen := cam.get_viewport().get_visible_rect().has_point(cam.unproject_position(exit.global_position))
	if on_screen:
		_check(exit_marks.is_empty(), "no edge arrow while the extraction beacon is on screen")
	else:
		# Screen right is world +X and screen down is world +Z (fixed camera yaw).
		var flat := exit.global_position - run.player.global_position
		var want := Vector2(flat.x, flat.z).normalized()
		_check(exit_marks.size() == 1 and exit_marks[0].direction.dot(want) > 0.8, "an edge arrow points to the nearest extraction")
	# An enemy just off screen gets a red edge arrow.
	var probe: ShipController = load("res://scenes/enemies/scavenger_drone.tscn").instantiate()
	probe.input_source = null
	run.generator.enemies_parent.add_child(probe)
	probe.global_position = run.player.global_position + Vector3(70.0, 0.0, 0.0)
	await process_frame
	await process_frame
	var enemy_marks := markers.markers.filter(func(m): return m.kind == &"enemy" and m.direction.x > 0.9)
	_check(not enemy_marks.is_empty(), "off-screen enemies get an edge arrow")
	probe.queue_free()
	await process_frame


func _test_menus(run: RiftRun) -> void:
	var ui := run.game_ui
	_press("pause")
	await process_frame
	_check(paused and ui.pause_menu.visible, "Esc opens the pause menu and pauses the game")
	_check(Sfx.current_music() == &"rift", "the rift plays its music")
	var music_slider: HSlider = ui.pause_menu.get_node("%MusicSlider")
	music_slider.value = 0.3
	_check(is_equal_approx(Sfx.music_volume, 0.3) and AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) < -9.0, "the pause menu's music slider sets the music volume")
	var cfg := ConfigFile.new()
	_check(cfg.load(Sfx.settings_path) == OK and is_equal_approx(cfg.get_value("audio", "music", 0.0), 0.3), "volumes are saved")
	Sfx.set_volumes(0.6, 0.8)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Sfx.settings_path))
	_press("ship_menu")
	await process_frame
	_check(not ui.ship_menu.visible, "the ship screen can't open over the pause menu")
	_press("pause")
	await process_frame
	_check(not paused and not ui.pause_menu.visible, "Esc again resumes")

	run.player.cargo.add(ORE, 7)
	_press("ship_menu")
	await process_frame
	_check(paused and ui.ship_menu.visible, "Tab opens the ship screen and pauses the game")
	_tab_key()
	await process_frame
	_check(not ui.ship_menu.visible and not paused, "pressing the real Tab key closes the ship screen again")
	_tab_key()
	await process_frame
	_check(ui.ship_menu.visible, "and Tab opens it once more")
	var tabs := ui.ship_menu.get_node("%Tabs") as TabContainer
	_check(tabs.get_tab_count() == 4, "ship screen has Ship, Skills, Augments and Cargo pages")
	_check(ui.ship_menu.get_node("%StatsList").get_child_count() > 5, "the Ship page lists stats")
	var cargo_rows := ui.ship_menu.get_node("%CargoList").get_child_count()
	_check(cargo_rows == run.player.cargo.slot_count, "the Cargo page shows every hold slot (%d)" % cargo_rows)
	ui.ship_menu._jettison(0)
	_check(run.player.cargo.count_of(ORE) == 0, "jettison on the Cargo page dumps that slot")
	_press("pause")
	await process_frame
	_check(not paused and not ui.ship_menu.visible and not ui.pause_menu.visible, "Esc closes the ship screen without opening the pause menu")
	_clear_pickups()


func _test_camera(run: RiftRun) -> void:
	var cam := run.game_ui.camera
	_install_input(run.player)
	var base := cam.fov
	_input.steer = Vector3.FORWARD
	_input.thrust = 1.0
	_input.boost = true
	await _frames(30)
	_check(cam.fov > base + 4.0, "boosting widens the camera (%.0f -> %.0f deg)" % [base, cam.fov])
	_input.reset()
	await _frames(60)


func _test_augment_cache(run: RiftRun) -> void:
	var ui := run.game_ui
	var ship := run.player
	var cache: AugmentCache = run.augment_cache.instantiate()
	run.add_child(cache)
	cache.global_position = ship.global_position + Vector3(12, 0, 0)
	await _frames(2)
	_check(not ui.augment_picker.is_open, "the cache waits for the ship")
	var damage := ship.primary.damage
	ship.global_position = cache.global_position
	ship.velocity = Vector3.ZERO
	await _frames(4)
	_check(ui.augment_picker.is_open and paused, "flying into a cache opens the augment picker and pauses")
	var offered := ui.augment_picker.offered
	var distinct := offered.size() == 3 and offered[0] != offered[1] and offered[1] != offered[2] and offered[0] != offered[2]
	_check(distinct, "the cache offers three different augments")
	_press("pause")
	await process_frame
	await process_frame
	_check(not ui.pause_menu.visible, "Esc doesn't open the pause menu over the picker")
	ui.augment_picker.choose(load("res://resources/augments/overcharged_cannons.tres"))
	await process_frame
	_check(not paused and not ui.augment_picker.is_open, "picking an augment resumes the run")
	_check(ship.loadout.augments.size() == 1, "the picked augment is fitted")
	_check(is_equal_approx(ship.primary.damage, damage * 1.25), "Overcharged Cannons adds 25%% cannon damage (%.1f -> %.1f)" % [damage, ship.primary.damage])
	_check(not is_instance_valid(cache) or cache.is_queued_for_deletion(), "an opened cache is used up")
	_press("ship_menu")
	await process_frame
	var tile := ui.ship_menu.get_node("%AugmentGrid").get_child(0)
	_check(tile is VBoxContainer and "Overcharged" in tile.get_child(0).text, "the ship screen lists fitted augments")
	_press("ship_menu")
	await process_frame


## Rifts come in sections joined by tears that pull you through.
func _test_tears(run: RiftRun) -> void:
	var gen := run.generator
	var ship := run.player
	var main := gen.sections.filter(func(sec): return not sec.side)
	_check(main.size() >= 2, "the rift is cut into sections (%d main, %d side)" % [main.size(), gen.sections.size() - main.size()])
	var sizes_ok := true
	for sec in gen.sections:
		sizes_ok = sizes_ok and sec.cells.size() >= 1 and sec.cells.size() <= 3
	_check(sizes_ok, "each section is 1 to 3 chunks")
	_check(gen.tears.size() == 2 * (gen.sections.size() - 1), "sections are joined by pairs of tears (%d tears)" % gen.tears.size())
	var pairs_ok := true
	for tear in gen.tears:
		pairs_ok = pairs_ok and tear.partner != null and tear.partner.partner == tear and tear.partner.section != tear.section and tear.leads_to == tear.partner.section
	_check(pairs_ok, "every tear has a partner in another section")
	_check(gen.section_of(gen.player_start) == 0 and gen.exit_section() == main.size() - 1, "you start in the first section and the exit is in the last")
	# No doorway crosses a section border.
	var sealed := true
	for cell in gen.cells:
		for d in RiftGenerator.DIRS:
			if gen.is_linked(cell, cell + d) and gen.cells[cell + d].section != gen.cells[cell].section:
				sealed = false
	_check(sealed, "sections only connect through tears")
	# The same rules over many layouts, without building chunks.
	var planner := RiftGenerator.new()
	var bad := 0
	for s in range(1, 301):
		planner.plan_layout(s)
		var used := {}
		for t in planner.tear_plan:
			for end in [[t.a, t.a_dir], [t.b, t.b_dir]]:
				var key := "%s %s" % end
				if used.has(key) or planner.is_linked(end[0], end[0] + end[1]):
					bad += 1
				used[key] = true
		for cell in planner.cells:
			if not planner.cells[cell].has("depth"):
				bad += 1
		if planner.sections.size() != planner.branch_count + planner.sections.filter(func(sec): return not sec.side).size():
			bad += 1
	planner.free()
	_check(bad == 0, "tears sit on walled sides and reach every chunk across 300 layouts (%d bad)" % bad)

	# Fly into the first tear on the way out.
	ship.global_position = gen.player_start
	ship.reset_physics_interpolation()
	await _frames(2)
	var tear := run.way_out(ship.global_position) as RiftTear
	_check(tear != null and tear.section == 0, "from the start, the way out is a rift tear")
	await process_frame
	_check("RIFT TEAR" in run.game_ui.hud.get_node("%ExtractLabel").text, "the HUD points to the tear (%s)" % run.game_ui.hud.get_node("%ExtractLabel").text)
	if tear == null:
		return
	var trips: Array = []
	tear.traversed.connect(func(s): trips.append(s))
	ship.velocity = Vector3.ZERO
	ship.global_position = tear.global_position
	await _frames(6)
	var other := tear.partner
	_check(trips.size() == 1 and gen.section_of(ship.global_position) == other.section, "flying into a tear pulls you through to the next section")
	_check(ship.global_position.distance_to(other.global_position) < other.exit_offset + 3.0, "you come out by the partner tear")
	_check(ship.velocity.dot(other.inward) > 0.0, "you come out heading into the new section")
	var cam := run.game_ui.camera
	_check(Vector2(cam.global_position.x - ship.global_position.x, cam.global_position.z - ship.global_position.z).length() < 40.0, "the camera jumps with the ship")
	var map := run.game_ui.hud.get_node("%Minimap") as Minimap
	await process_frame
	_check(map._section == other.section and map.is_revealed(ship.global_position), "the minimap switches to the new section")
	# Straight back in: the tear needs a moment before it works again.
	ship.global_position = other.global_position
	ship.velocity = Vector3.ZERO
	await _frames(3)
	_check(gen.section_of(ship.global_position) == other.section, "a tear doesn't bounce you straight back")
	ship.global_position = other.global_position + other.inward * 20.0
	await create_timer(other.cooldown + 0.2).timeout
	ship.global_position = other.global_position
	await _frames(6)
	_check(gen.section_of(ship.global_position) == tear.section, "tears work both ways")


func _test_extraction(run: RiftRun) -> void:
	# Clear the hostiles: mite blasts and mines shove the ship out of the ring.
	for e in run.generator.enemies:
		if is_instance_valid(e):
			e.free()
	for mine in get_nodes_in_group("mines"):
		mine.free()
	var ship := run.player
	ship.health.max_hull = 100000.0
	ship.health.reset()
	ship.cargo.clear()
	ship.cargo.add(ORE, 3)
	ship.cargo.add(SCRAP, 4)
	ship.health.hull = ship.health.max_hull - 30.0
	var credits_before := Profile.credits
	var results: Array[bool] = []
	run.run_ended.connect(func(e): results.append(e))
	var exit := run.nearest_extraction(ship.global_position)
	ship.global_position = exit.global_position
	ship.velocity = Vector3.ZERO
	await create_timer(exit.channel_time * 0.5).timeout
	_check(exit.progress > 0.2 and not run.ended, "holding position in the ring charges extraction (%.0f%%)" % (exit.progress * 100.0))
	await create_timer(exit.channel_time * 0.5 + 0.3).timeout
	_check(results == [true] and run.extracted, "finishing the charge extracts")
	await create_timer(run.end_card_delay + 0.5).timeout
	var end := run.game_ui.end_screen
	_check(end.visible and end.get_node("%Title").text == "EXTRACTED", "the result card says EXTRACTED")
	_check("Cargo banked" in end.get_node("%Stats").text, "the result card shows the cargo banked")
	_check(Profile.credits == credits_before + 3 * ORE.value, "extracting sells the hold for credits (%d)" % Profile.credits)
	_check(Profile.scrap == 4, "scrap goes to the shipwright's stash, not the market (%d)" % Profile.scrap)
	_check(Profile.hull_damage >= 30.0 and Profile.hull_damage < 200.0, "hull damage carries over to the next run (%.0f)" % Profile.hull_damage)
	_check(Profile.essence == ship.loadout.essence_value() and Profile.essence > 0, "augments break down into Void Essence (%d)" % Profile.essence)
	_check(end.get_node("%RetryButton").text == "To the hangar", "the card leads on to the hangar")
	var saved := Profile.credits
	Profile.load_profile()
	_check(Profile.credits == saved and Profile.extractions == 1, "the payout is saved to disk")
	paused = false


func _test_collapse_and_death(run: RiftRun) -> void:
	var ship := run.player
	var stages: Array[int] = []
	run.stage_reached.connect(func(s, _t): stages.append(s))
	run.elapsed = run.collapse_time
	ship.health.shield = 0.0
	var hull := ship.health.hull
	await _frames(30)
	_check(stages.has(3), "at 100% the rift collapses")
	_check(ship.health.hull < hull, "a collapsed rift tears at the hull (%.0f -> %.0f)" % [hull, ship.health.hull])
	ship.cargo.clear()
	ship.cargo.add(ORE, 2)
	ship.cargo.add(load("res://resources/items/void_crystal.tres"), 2)
	var credits_before := Profile.credits
	ship.take_damage(100000.0, null)
	await create_timer(run.end_card_delay + 1.5).timeout
	_check(Profile.credits == credits_before + 2 * 25, "the Secured Locker pays out the most valuable slot only (%d -> %d)" % [credits_before, Profile.credits])
	var end := run.game_ui.end_screen
	_check(run.ended and not run.extracted, "dying in the rift ends the run")
	_check(end.visible and end.get_node("%Title").text == "SHIP LOST", "the death screen says SHIP LOST")
	_check("collapsed" in end.get_node("%Subtitle").text, "the death screen says the rift collapsed")
	_check(is_equal_approx(Profile.hull_damage, ship.health.max_hull * 0.75), "a lost ship is towed home at 25%% hull (damage %.0f)" % Profile.hull_damage)
	_check("Towed home" in end.get_node("%Stats").text or "Towed home" in "\n".join(Profile.last_run), "the report says the ship was towed home")
	paused = false
	Hitstop.clear()


func _test_hangar() -> void:
	Profile.credits = 1000
	var hangar: Hangar = load(Scenes.HANGAR).instantiate()
	root.add_child(hangar)
	await process_frame
	var chart := hangar.get_node("%StarChart")
	_check(chart.get_child_count() == 1 and hangar.site_button(0) != null, "before the Rift Compass the star chart only shows the graveyard")
	_check(hangar.site_button(0).has_focus(), "the hangar focuses the star chart")
	_check(str(Profile.credits) in hangar.get_node("%Wallet").text and "scrap" in hangar.get_node("%Wallet").text, "the hangar shows credits, essence and scrap")
	_check("EXTRACTED" in hangar.get_node("%Report").text, "the hangar shows the last run")
	_check(hangar.buy(&"hull") and Profile.level(&"hull") == 1 and Profile.credits == 1000 - 120, "buying hull plating spends credits and saves the level")
	_check(not hangar.buy(&"engine") or Profile.essence >= 15, "upgrades that need essence wait for it")

	# Shipwright: 4 scrap fixes 20 hull, the other 20 costs 60 cr.
	Profile.hull_damage = 40.0
	Profile.scrap = 4
	Profile.credits = 500
	hangar.refresh()
	var repair: Button = hangar.get_node("%RepairButton")
	_check("4 scrap" in repair.text and "60 cr" in repair.text and not repair.disabled, "the repair button prices scrap then credits (%s)" % repair.text)
	hangar.repair()
	_check(Profile.hull_damage == 0.0 and Profile.scrap == 0 and Profile.credits == 440, "repairing spends scrap first, then credits")
	_check(repair.disabled, "a sound hull needs no repair")
	Profile.hull_damage = 300.0
	Profile.credits = 30
	hangar.repair()
	_check(Profile.credits == 0 and is_equal_approx(Profile.hull_damage, 290.0), "short on money, the shipwright repairs what you can pay for")
	Profile.hull_damage = 0.0
	Profile.scrap = 10
	_check(hangar.sell_scrap() == 20 and Profile.scrap == 0 and Profile.credits == 20, "spare scrap sells for 2 cr each")

	# With the compass: every site shows, deeper tiers locked until earned.
	Profile.has_compass = true
	Profile.max_tier = 1
	hangar.refresh()
	await process_frame
	_check(chart.get_child_count() == Deployment.SITES.size(), "with the compass the star chart lists the debris field and all rift tiers")
	_check(not hangar.site_button(1).disabled and hangar.site_button(2).disabled and hangar.site_button(3).disabled, "only unlocked tiers can be launched")
	_check("tier I" in hangar.site_button(2).text, "locked tiers say what opens them (%s)" % hangar.site_button(2).text.replace("\n", " / "))
	Profile.has_compass = false
	Profile.max_tier = 0
	Profile.save()
	hangar.queue_free()
	await process_frame


## The first run: the graveyard debris field and the dead runner's compass.
func _test_tutorial() -> void:
	Deployment.choose(2)
	_check(Deployment.tutorial and Deployment.tier == 0, "without the compass every launch is the tutorial debris field")
	var run := await _load_rift(SEED + 2)
	await _frames(5)
	_check(not run.has_instability, "debris fields have no instability")
	run.elapsed = 1000.0
	await _frames(3)
	_check(run.instability == 0.0 and run.stage == 0, "the debris field never collapses")
	_check(get_nodes_in_group("augment_caches").is_empty(), "debris fields hold no augment caches")
	var cutters := 0
	for e in run.generator.enemies:
		if is_instance_valid(e) and e.threat_tier >= 2:
			cutters += 1
	_check(cutters == 0, "debris fields have no pirate cutters")
	var crystals := 0
	for rock in root.find_children("*", "StaticBody3D", true, false):
		if rock is MineableAsteroid and rock.ore_item.grade != ItemDefinition.Grade.COMMON:
			crystals += 1
	_check(crystals == 0, "debris fields have no void crystals")
	_check(run.game_ui.hud.get_node("%InstabilityLabel").text == "THE GRAVEYARD" and not run.game_ui.hud.get_node("%InstabilityBar").visible, "the HUD names the site and hides the rift clock")
	var derelict := run.objective as CompassDerelict
	_check(derelict != null, "the tutorial places the dead runner's derelict")
	if derelict == null:
		return
	var exits: Array = []
	for p in run.generator.extraction_points:
		exits.append(run.generator.cell_at(p.global_position))
	_check(not run.generator.cell_at(derelict.global_position) in exits, "the derelict isn't in an exit chunk")
	_check(run.generator.tears.is_empty() and run.generator.sections.is_empty(), "debris fields are one open area, no rift tears")
	_check("DERELICT" in run.game_ui.hud.get_node("%ExtractLabel").text, "the HUD points to the derelict first")
	var ship := run.player
	ship.global_position = derelict.global_position
	ship.velocity = Vector3.ZERO
	await _frames(6)
	_check(Profile.has_compass and Profile.max_tier == 1, "flying into the derelict salvages the Rift Compass and opens tier I")
	_check(run.objective == null and "EXTRACTION" in run.game_ui.hud.get_node("%ExtractLabel").text, "then the HUD points to the exit")
	Profile.load_profile()
	_check(Profile.has_compass, "the compass is saved")
	# Extracting from the deepest open tier unlocks the next one.
	run.site = Deployment.SITES[1]
	var lines := run.settle(true)
	_check(Profile.max_tier == 2 and "unlocked" in "\n".join(lines), "extracting from tier I unlocks tier II")
	run.queue_free()
	await process_frame


## Deeper rifts scale enemies up.
func _test_tiers() -> void:
	Deployment.choose(3)
	_check(not Deployment.tutorial and Deployment.tier == 3, "with the compass the chart sends you where you picked")
	var run := await _load_rift(SEED + 3)
	await _frames(2)
	_check(run.has_instability and is_equal_approx(run.collapse_time, 260.0), "tier III collapses sooner (%.0f s)" % run.collapse_time)
	var scaled := true
	var tiers := {}
	for e in run.generator.enemies:
		if not is_instance_valid(e):
			continue
		tiers[e.threat_tier] = true
		var sample: Node = load(e.scene_file_path).instantiate()
		var base: float = sample.get_node("Health").max_hull
		sample.free()
		scaled = scaled and is_equal_approx(e.health.max_hull, base * run.site.enemy_health)
	_check(scaled and run.site.enemy_health > 1.0, "tier III enemies are tougher (x%.2f hull)" % run.site.enemy_health)
	_check(tiers.has(2) or tiers.has(3), "tier III rifts field tier 2-3 roster enemies (%s)" % str(tiers.keys()))
	var stray := run.spawn_stray()
	await _frames(2)
	if stray != null:
		var stray_sample: Node = load(stray.scene_file_path).instantiate()
		var stray_base: float = stray_sample.get_node("Health").max_hull
		stray_sample.free()
		_check(stray.health.max_hull > stray_base, "stray arrivals are scaled too")
	run.queue_free()
	await process_frame


# --- Helpers -----------------------------------------------------------------

func _load_rift(seed_value: int) -> RiftRun:
	var run: RiftRun = load(RIFT).instantiate()
	run.layout_seed = seed_value
	root.add_child(run)
	current_scene = run
	await physics_frame
	await physics_frame
	return run


func _install_input(ship: ShipController) -> void:
	if _input == null or not is_instance_valid(_input):
		_input = ScriptedInput.new()
		ship.add_child(_input)
	ship.input_source = _input


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


## A real Tab key press, which the GUI also wants for focus changes.
func _tab_key() -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_TAB
		ev.physical_keycode = KEY_TAB
		ev.pressed = down
		Input.parse_input_event(ev)


func _clear_pickups() -> void:
	for p in get_nodes_in_group("pickups"):
		p.queue_free()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
