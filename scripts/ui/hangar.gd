class_name Hangar
extends Control
## Between runs: shows the wallet and last run, sells permanent upgrades,
## and launches the next rift. A stand-in for the full hub (shipwright,
## star chart) in milestone 5.

@onready var _wallet: Label = %Wallet
@onready var _upgrades: VBoxContainer = %Upgrades
@onready var _report: Label = %Report


func _ready() -> void:
	Hitstop.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Profile.ensure_loaded()
	%LaunchButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.RIFT))
	%MenuButton.pressed.connect(func(): Scenes.go(get_tree(), Scenes.MAIN_MENU))
	refresh()
	%LaunchButton.grab_focus()


func refresh() -> void:
	_wallet.text = "%d credits    %d Void Essence" % [Profile.credits, Profile.essence]
	_report.text = "\n".join(Profile.last_run) if not Profile.last_run.is_empty() else "No runs yet."
	for child in _upgrades.get_children():
		_upgrades.remove_child(child)
		child.queue_free()
	for u in Profile.UPGRADES:
		_upgrades.add_child(_upgrade_row(u))


## Buys the next level of an upgrade (what the Buy buttons do).
func buy(id: StringName) -> bool:
	var ok := Profile.buy(id)
	refresh()
	return ok


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
