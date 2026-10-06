class_name RiftRun
extends Node3D
## Runs one trip into a rift: generates it, starts the player at the start
## chunk, and ends the run on extraction or death.
##
## Instability is the run clock. It climbs from 0 to 100% over
## `collapse_time`; as it rises, stray enemies warp in more often (no
## waves, just a growing trickle near the player), and at 100% the rift
## collapses and tears at the hull until you get out or die.
##
## The run also settles the economy: on extraction the hold is sold for
## credits and run augments break down into Void Essence; on death only
## the Secured Locker (the hold's most valuable slot) is sold. Both land in
## the Profile save. Scrap goes to the repair stash instead of being sold,
## and hull damage carries over to the next run.
##
## What kind of site this is (debris field or rift tier) comes from
## Deployment, set on the hangar's star chart. The tutorial run adds the
## dead runner's derelict, which holds the Rift Compass.

signal stage_reached(stage: int, text: String)
signal run_ended(extracted: bool)

@export var generator: RiftGenerator
@export var player: ShipController
@export var game_ui: GameUI
## 0 = a new rift every run; anything else always builds the same rift.
@export var layout_seed: int = 0
## Seconds from entering to full collapse.
@export var collapse_time: float = 300.0
@export var trickle_enemies: Array[PackedScene] = []
## Seconds between stray arrivals at 0% and at 100% instability.
@export var trickle_interval: Vector2 = Vector2(32.0, 6.0)
## Stray enemies arrive this far from the player.
@export var trickle_distance: Vector2 = Vector2(32.0, 48.0)
@export var warp_flash: PackedScene
## Hull damage per second once the rift has collapsed.
@export var collapse_damage: float = 12.0
## Seconds between the ending and the result card.
@export var end_card_delay: float = 1.2
## Dropped by tougher enemies (threat tier 2+) now and then.
@export var augment_cache: PackedScene
@export_range(0.0, 1.0) var cache_drop_chance: float = 0.2
## The tutorial's derelict holding the Rift Compass.
@export var compass_derelict: PackedScene

const STAGES := [
	[0.5, "THE RIFT IS DESTABILISING"],
	[0.75, "RIFT CRITICAL - HOSTILES INBOUND"],
	[0.9, "COLLAPSE IMMINENT - EXTRACT NOW"],
	[1.0, "THE RIFT IS COLLAPSING"],
]

var instability: float = 0.0
var elapsed: float = 0.0
var ended: bool = false
var extracted: bool = false
var stage: int = 0
## The site rules this run uses (a Deployment.SITES entry).
var site: Dictionary = {}
## False in debris fields: no clock, no strays, no collapse.
var has_instability: bool = true
## Something to fly to before the exit (the tutorial derelict), or null.
var objective: Node3D = null

var _trickle_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("rift_run")
	Sfx.music(&"rift")
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	Profile.ensure_loaded()
	var rules := Deployment.site()
	if Deployment.tutorial:
		rules = rules.duplicate()
		rules.name = "The graveyard"
	_apply_site(rules)
	var seed_value := layout_seed if layout_seed != 0 else randi_range(1, 999999)
	_rng.seed = seed_value + 1
	generator.generate(seed_value)
	player.global_position = generator.player_start
	player.reset_physics_interpolation()
	player.destroyed.connect(_on_player_destroyed)
	if player.loadout != null:
		player.loadout.set_upgrades(Profile.upgrade_mods())
	if player.health != null:
		player.health.reset()
		# Unrepaired damage from earlier runs.
		player.health.hull = maxf(player.health.max_hull - Profile.hull_damage, 1.0)
	if Deployment.tutorial:
		_place_derelict()
	get_tree().node_added.connect(_on_node_added)
	for enemy in generator.enemies:
		_on_node_added(enemy)
	for point in generator.extraction_points:
		point.extracted.connect(_on_extracted)
	_trickle_timer = trickle_interval.x


func _physics_process(delta: float) -> void:
	if ended:
		return
	elapsed += delta
	if not has_instability:
		return
	instability = clampf(elapsed / maxf(collapse_time, 1.0), 0.0, 1.0)
	while stage < STAGES.size() and instability >= STAGES[stage][0]:
		stage_reached.emit(stage, STAGES[stage][1])
		Sfx.play(&"alarm")
		stage += 1
	if game_ui != null:
		game_ui.screen_fx.instability = smoothstep(0.55, 1.0, instability)

	_trickle_timer -= delta
	if _trickle_timer <= 0.0:
		_trickle_timer = lerpf(trickle_interval.x, trickle_interval.y, instability)
		spawn_stray()

	if instability >= 1.0 and player.is_alive():
		player.take_damage(collapse_damage * delta, null)


## Copies a Deployment site's rules onto the generator and the run.
func _apply_site(rules: Dictionary) -> void:
	site = rules
	has_instability = rules.instability
	if has_instability:
		collapse_time = rules.collapse_time
	generator.main_path_length = rules.main_path
	generator.branch_count = rules.branches
	generator.min_exit_depth = rules.min_exit_depth
	generator.min_exit_spread = rules.min_exit_spread
	generator.spawn_chance_bonus = rules.spawn_bonus
	generator.allow_cutters = rules.cutters
	generator.allow_caches = rules.caches
	generator.allow_void_crystals = rules.void_crystals
	if not rules.caches:
		cache_drop_chance = 0.0


## The tutorial: the dead runner's derelict sits in the deepest chunk that
## isn't an exit, and holds the Rift Compass.
func _place_derelict() -> void:
	if compass_derelict == null:
		return
	var best := Vector2i.ZERO
	for cell in generator.cells:
		if cell in generator.extract_cells or cell == Vector2i.ZERO:
			continue
		if best == Vector2i.ZERO or generator.cells[cell]["depth"] > generator.cells[best]["depth"]:
			best = cell
	var at := generator.cell_center(best)
	_clear_rocks(generator, at, 14.0)
	var derelict := compass_derelict.instantiate() as CompassDerelict
	add_child(derelict)
	derelict.global_position = at
	derelict.collected.connect(_on_compass_collected)
	objective = derelict
	_tutorial_banners()


## Clears loose rocks out of the derelict's spot so it can be reached.
func _clear_rocks(node: Node, at: Vector3, radius: float) -> void:
	for child in node.get_children():
		if child is Asteroid and (child as Node3D).global_position.distance_to(at) < radius + (child as Asteroid).radius:
			node.remove_child(child)
			child.queue_free()
		else:
			_clear_rocks(child, at, radius)


func _tutorial_banners() -> void:
	var hints := [
		[0.6, "THE GRAVEYARD: FIND THE DEAD RUNNER'S DERELICT", 4.0],
		[5.0, "Follow the gold arrow. WASD fly, mouse aim, click to fire", 4.5],
		[10.0, "Shift boosts, Space drifts. Shoot glowing rocks for ore", 4.5],
	]
	for h in hints:
		get_tree().create_timer(h[0], false).timeout.connect(func():
			if not ended and objective != null and game_ui != null:
				game_ui.hud.show_banner(h[1], h[2]))


func _on_compass_collected() -> void:
	objective = null
	Profile.has_compass = true
	Profile.max_tier = maxi(Profile.max_tier, 1)
	Profile.save()
	if game_ui != null:
		game_ui.hud.show_banner("RIFT COMPASS SALVAGED. RIFTS UNLOCKED. NOW GET OUT", 4.0)
		game_ui.camera.add_shake(0.4)


## Seconds left before the rift fully collapses.
func time_to_collapse() -> float:
	return maxf(collapse_time - elapsed, 0.0)


## The extraction beacon closest to `from`, or null.
func nearest_extraction(from: Vector3) -> ExtractionPoint:
	var best: ExtractionPoint = null
	for point in generator.extraction_points:
		if is_instance_valid(point) and (best == null or point.global_position.distance_to(from) < best.global_position.distance_to(from)):
			best = point
	return best


## Warps one stray enemy in somewhere near (but not on top of) the player.
func spawn_stray() -> ShipController:
	if trickle_enemies.is_empty() or not player.is_alive():
		return null
	var pos = _stray_point()
	if pos == null:
		return null
	# Cutters get likelier as the rift destabilises.
	var scene: PackedScene = trickle_enemies[0]
	if trickle_enemies.size() > 1 and _rng.randf() < 0.15 + instability * 0.35:
		scene = trickle_enemies[_rng.randi_range(1, trickle_enemies.size() - 1)]
	if warp_flash != null:
		var flash := warp_flash.instantiate() as Node3D
		add_child(flash)
		flash.global_position = pos
	var enemy := scene.instantiate() as ShipController
	generator.enemies_parent.add_child(enemy)
	enemy.global_position = pos
	enemy.reset_physics_interpolation()
	return enemy


## A clear point inside the rift at trickle distance from the player.
func _stray_point() -> Variant:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 3.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var margin := 8.0
	var half := generator.chunk_size * 0.5 - margin
	for attempt in 20:
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(trickle_distance.x, trickle_distance.y)
		var pos := player.global_position + Vector3.FORWARD.rotated(Vector3.UP, angle) * dist
		pos.y = 0.0
		var cell := generator.cell_at(pos)
		if not generator.cells.has(cell):
			continue
		var local := pos - generator.cell_center(cell)
		if absf(local.x) > half or absf(local.z) > half:
			continue
		query.transform = Transform3D(Basis(), pos)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		return pos
	return null


func _on_extracted(ship: ShipController) -> void:
	if ended or ship != player:
		return
	ended = true
	extracted = true
	# Hand the ship to the beacon: stop flying, then shrink into the beam.
	player.input_source = null
	player.velocity = Vector3.ZERO
	player.collision_layer = 0 # Shots pass through while beaming out.
	if player.visual_root != null:
		var tween := create_tween()
		tween.tween_property(player.visual_root, "scale", Vector3(0.05, 4.0, 0.05), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if game_ui != null:
		game_ui.camera.add_shake(0.5)
	Sfx.play(&"extracted")
	var lines := settle(true)
	run_ended.emit(true)
	await get_tree().create_timer(end_card_delay, true, false, true).timeout
	player.visible = false
	if game_ui != null:
		game_ui.show_end(true, "You escaped the rift with your cargo.", lines, Scenes.HANGAR)


func _on_player_destroyed(_ship: ShipController) -> void:
	if ended:
		return
	ended = true
	var lines := settle(false)
	run_ended.emit(false)
	await get_tree().create_timer(end_card_delay, true, false, true).timeout
	if game_ui != null:
		var why := "The rift collapsed around you." if instability >= 1.0 else "Your ship broke apart in the rift."
		game_ui.show_end(false, why + " The hold is lost, all but the Secured Locker.", lines, Scenes.HANGAR)


## Pays out the run into the Profile and saves it. Returns the report
## lines for the end card (also kept for the hangar).
func settle(escaped: bool) -> PackedStringArray:
	Profile.ensure_loaded()
	var lines: PackedStringArray = []
	var augments: Array[AugmentDefinition] = []
	if player.loadout != null:
		augments = player.loadout.augments
	var payout: float = site.get("payout", 1.0)
	if escaped:
		var credits := 0
		var scrap := 0
		var slots: Array = player.cargo.slots if player.cargo != null else []
		for slot in slots:
			if slot.item.id == &"scrap":
				scrap += slot.count
			else:
				credits += roundi(slot.count * slot.item.value * payout)
		var essence := player.loadout.essence_value() if player.loadout != null else 0
		Profile.credits += credits
		Profile.scrap += scrap
		Profile.essence += essence
		Profile.extractions += 1
		lines.append("Hold sold        +%d cr%s" % [credits, ("  (tier bonus x%.1f)" % payout) if payout > 1.0 else ""])
		lines.append("Scrap stashed    +%d" % scrap)
		lines.append("Augments (%d)     +%d essence" % [augments.size(), essence])
		Profile.hull_damage = maxf(player.health.max_hull - player.health.hull, 0.0) if player.health != null else 0.0
		# Getting out of the deepest open tier opens the next one.
		var t: int = site.get("tier", 1)
		if t >= 1 and t == Profile.max_tier and t < Deployment.SITES.size() - 1:
			Profile.max_tier = t + 1
			lines.append("NEW: rift tier %s unlocked on the star chart" % ["I", "II", "III"][t])
	else:
		var locker := secured_locker_slot()
		if locker.is_empty():
			lines.append("Secured Locker   empty")
		elif locker.item.id == &"scrap":
			Profile.scrap += locker.count
			lines.append("Secured Locker   %d Scrap  stashed" % locker.count)
		else:
			var value := roundi(locker.count * locker.item.value * payout)
			Profile.credits += value
			lines.append("Secured Locker   %d %s  +%d cr" % [locker.count, locker.item.display_name, value])
		lines.append("Augments lost    %d" % augments.size())
		# Towed home as a wreck.
		var max_hull := player.health.max_hull if player.health != null else Profile.BASE_HULL
		Profile.hull_damage = max_hull * (1.0 - Profile.TOWED_HULL)
		lines.append("Towed home at %d%% hull" % roundi(Profile.TOWED_HULL * 100.0))
	Profile.runs += 1
	lines.append("Credits          %d    Essence  %d" % [Profile.credits, Profile.essence])
	lines.append_array(_extra_lines())
	Profile.last_run = PackedStringArray([("EXTRACTED" if escaped else "SHIP LOST")]) + lines
	Profile.save()
	return lines


## The hold slot the Secured Locker keeps on death: the most valuable one.
func secured_locker_slot() -> Dictionary:
	var best := {}
	if player.cargo == null:
		return best
	for slot in player.cargo.slots:
		if best.is_empty() or slot.count * slot.item.value > best.count * best.item.value:
			best = slot
	return best


func _on_node_added(node: Node) -> void:
	var enemy := node as ShipController
	if enemy != null and enemy != player and enemy.team != player.team and not enemy.destroyed.is_connected(_on_enemy_destroyed):
		enemy.destroyed.connect(_on_enemy_destroyed)
		_scale_enemy(enemy)


## Deeper tiers make every hostile tougher and hit harder.
func _scale_enemy(enemy: ShipController) -> void:
	var hp: float = site.get("enemy_health", 1.0)
	var dmg: float = site.get("enemy_damage", 1.0)
	if is_equal_approx(hp, 1.0) and is_equal_approx(dmg, 1.0):
		return
	# This can run before the enemy's _ready, so find parts by node.
	var health := enemy.get_node_or_null("Health") as Health
	if health != null:
		health.max_hull *= hp
		health.max_shield *= hp
		health.reset()
	for child in enemy.get_children():
		if child is ShipWeapon:
			child.damage *= dmg


## Tougher enemies sometimes leave an augment cache behind.
func _on_enemy_destroyed(enemy: ShipController) -> void:
	if ended or augment_cache == null or enemy.threat_tier < 2 or _rng.randf() >= cache_drop_chance:
		return
	var cache := augment_cache.instantiate() as Node3D
	var at := enemy.global_position
	add_child.call_deferred(cache)
	cache.set_deferred("position", Vector3(at.x, 0.0, at.z))


func _extra_lines() -> PackedStringArray:
	var lines: PackedStringArray = ["Site             %s" % site.get("name", "Rift")]
	if has_instability:
		lines.append("Instability      %d%%" % floori(instability * 100.0))
	lines.append("Rift seed        %d" % generator.layout_seed)
	return lines
