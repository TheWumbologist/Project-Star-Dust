class_name Hangar
extends Control
## The hub between runs. The shipwright repairs hull damage carried over
## from the last run (scrap first, then credits) and sells permanent
## upgrades; the star chart picks the next site (a debris field or a rift
## tier) and launches it. Before the Rift Compass is found, the chart only
## shows the graveyard where the dead runner's derelict lies.

## Credits paid per unit of scrap when selling it.
const SCRAP_VALUE := 2

@onready var _wallet: Label = %Wallet
@onready var _hull: Label = %Hull
@onready var _repair: Button = %RepairButton
@onready var _sell: Button = %SellScrapButton
@onready var _upgrades: VBoxContainer = %Upgrades
@onready var _chart: VBoxContainer = %StarChart
@onready var _report: Label = %Report


func _ready() -> void:
	Sfx.music(&"hub")
	Hitstop.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Profile.ensure_loaded()
	%MenuButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.MAIN_MENU))
	_repair.pressed.connect(repair)
	_sell.pressed.connect(sell_scrap)
	refresh()
	var focus := site_button(Deployment.tier)
	if focus == null or focus.disabled:
		focus = site_button(0)
	if focus != null:
		focus.grab_focus()


func refresh() -> void:
	_wallet.text = "%d credits    %d Void Essence    %d scrap" % [Profile.credits, Profile.essence, Profile.scrap]
	_report.text = "\n".join(Profile.last_run) if not Profile.last_run.is_empty() else "No runs yet."
	_refresh_shipwright()
	for child in _upgrades.get_children():
		_upgrades.remove_child(child)
		child.queue_free()
	for u in Profile.UPGRADES:
		_upgrades.add_child(_upgrade_row(u))
	_refresh_chart()


## Buys the next level of an upgrade (what the Buy buttons do).
func buy(id: StringName) -> bool:
	var ok := Profile.buy(id)
	refresh()
	return ok


## Fixes as much hull as scrap and credits allow.
func repair() -> float:
	var fixed := Profile.repair()
	refresh()
	return fixed


func sell_scrap() -> int:
	var earned := Profile.sell_scrap(SCRAP_VALUE)
	refresh()
	return earned


## Sends the ship to a star chart site.
func launch(site_tier: int) -> void:
	if not Deployment.is_unlocked(site_tier):
		return
	Deployment.choose(site_tier)
	Scenes.go(get_tree(), Scenes.RIFT)


## The star chart button for a site tier, or null if it isn't listed.
func site_button(site_tier: int) -> Button:
	return _chart.get_node_or_null("Site%d" % site_tier) as Button


func _refresh_shipwright() -> void:
	var max_hull := Profile.max_hull()
	var hull := maxf(max_hull - Profile.hull_damage, 1.0)
	_hull.text = "Hull  %d / %d" % [roundi(hull), roundi(max_hull)]
	_hull.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if Profile.hull_damage > 0.0 else Color(0.6, 1, 0.7))
	if Profile.hull_damage <= 0.0:
		_repair.text = "Hull is sound"
		_repair.disabled = true
	else:
		var scrap := mini(Profile.scrap, Profile.repair_scrap_cost())
		var credits := Profile.repair_credit_cost()
		var parts: PackedStringArray = []
		if scrap > 0:
			parts.append("%d scrap" % scrap)
		if credits > 0:
			parts.append("%d cr" % credits)
		_repair.text = "Repair  " + " + ".join(parts)
		# Partial repairs are fine: whatever can be paid for gets fixed.
		_repair.disabled = Profile.scrap == 0 and Profile.credits < Profile.CREDITS_PER_HULL
	_sell.text = "Sell scrap  +%d cr" % (Profile.scrap * SCRAP_VALUE)
	_sell.disabled = Profile.scrap == 0


func _upgrade_row(u: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var level := Profile.level(u.id)
	var name_label := Label.new()
	name_label.text = u.name
	name_label.custom_minimum_size = Vector2(190, 0)
	var pips := Label.new()
	pips.text = "■".repeat(level) + "□".repeat(u.max - level)
	pips.custom_minimum_size = Vector2(90, 0)
	pips.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	var blurb := Label.new()
	blurb.text = u.blurb
	blurb.custom_minimum_size = Vector2(230, 0)
	blurb.add_theme_font_size_override("font_size", 15)
	blurb.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	var button := Button.new()
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size = Vector2(170, 0)
	if Profile.is_maxed(u.id):
		button.text = "Maxed"
		button.disabled = true
	else:
		var cost := Profile.next_cost(u.id)
		button.text = "Buy  %d cr" % cost.x + ("  %d ess" % cost.y if cost.y > 0 else "")
		button.disabled = not Profile.can_buy(u.id)
	button.pressed.connect(func(): buy(u.id))
	for c in [name_label, pips, blurb, button]:
		row.add_child(c)
	return row


func _refresh_chart() -> void:
	for child in _chart.get_children():
		_chart.remove_child(child)
		child.queue_free()
	if not Profile.has_compass:
		var b := _site_row(0, "The graveyard", "A debris field where a rift runner's ship went dark. Salvage what's left.")
		_chart.add_child(b)
		return
	for s in Deployment.SITES:
		_chart.add_child(_site_row(s.tier, s.name, s.blurb))


func _site_row(site_tier: int, title: String, blurb: String) -> Button:
	var b := Button.new()
	b.name = "Site%d" % site_tier
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(440, 58)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if Deployment.is_unlocked(site_tier):
		b.text = "%s\n%s" % [title, blurb]
		b.pressed.connect(launch.bind(site_tier))
	else:
		b.text = "%s  (locked)\n%s" % [title, Deployment.lock_reason(site_tier)]
		b.disabled = true
	return b
