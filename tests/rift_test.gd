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
const SEED := 4242

var _failures: PackedStringArray = []
var _input: ScriptedInput


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_main_menu()
	var run := await _load_rift(SEED)
	await _test_layout(run)
	await _test_same_seed(run)
	await _test_minimap(run)
	await _test_instability(run)
	await _test_menus(run)
	await _test_camera(run)
	await _test_extraction(run)
	run.queue_free()
	await process_frame
	run = await _load_rift(SEED + 1)
	await _test_collapse_and_death(run)

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
	var cutter: ShipController = load("res://scenes/enemies/pirate_cutter.tscn").instantiate()
	var drone: ShipController = load("res://scenes/enemies/scavenger_drone.tscn").instantiate()
	_check(cutter.threat_tier > drone.threat_tier, "cutters get bigger map dots than drones")
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
	var exit := run.nearest_extraction(run.player.global_position)
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


func _test_extraction(run: RiftRun) -> void:
	var ship := run.player
	ship.health.max_hull = 100000.0
	ship.health.reset()
	ship.cargo.add(ORE, 3)
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
	ship.take_damage(100000.0, null)
	await create_timer(run.end_card_delay + 1.5).timeout
	var end := run.game_ui.end_screen
	_check(run.ended and not run.extracted, "dying in the rift ends the run")
	_check(end.visible and end.get_node("%Title").text == "SHIP LOST", "the death screen says SHIP LOST")
	_check("collapsed" in end.get_node("%Subtitle").text, "the death screen says the rift collapsed")
	paused = false
	Hitstop.clear()


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
