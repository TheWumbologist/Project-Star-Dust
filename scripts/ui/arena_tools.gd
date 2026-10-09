class_name ArenaTools
extends CanvasLayer
## Testing tools for the combat arena: two dropdowns along the top of the
## screen that open and close without pausing the game.
##
## - CHEATS (F2): invulnerable, unlimited boost, unlimited torpedoes.
## - SPAWN ENEMY (F3): a table of all nine roster enemies (role across,
##   tier down) with a spinning model of each. Click one to warp it in.
##
## The system cursor shows while the pointer is over the tools, and clicks
## there don't fire the guns (PlayerShipInput skips "blocks_fire" UI).
## Cheat settings survive a restart (R).

## Asks the arena to warp in EnemyRoster.ENTRIES[index].
signal spawn_requested(index: int)

@export var ship: ShipController

const TEXT := Color(0.95, 0.88, 0.75)
const BORDER := Color(0.75, 0.56, 0.25)
const TIER_COLORS := [Color(0.72, 0.85, 0.95), Color(1.0, 0.72, 0.3), Color(1.0, 0.4, 0.35)]
const TIER_NAMES := ["I", "II", "III"]
const THUMB_SIZE := Vector2i(124, 76)
## Degrees per second the thumbnails turn.
const SPIN_SPEED := 40.0

static var invulnerable: bool = false
static var unlimited_boost: bool = false
static var unlimited_torpedoes: bool = false

var _cheats_button: Button
var _spawn_button: Button
var _cheats_panel: PanelContainer
var _spawn_panel: PanelContainer
var _pivots: Array[Node3D] = []
var _viewports: Array[SubViewport] = []
var _cursor_shown: bool = false
## Cheat buttons and the static flag each one shows, kept in step.
var _cheat_buttons: Dictionary = {}


func _ready() -> void:
	layer = 10
	_build()
	_set_spawn_open(false)
	_set_cheats_open(false)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_F2:
		_set_cheats_open(not _cheats_panel.visible)
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_F3:
		_set_spawn_open(not _spawn_panel.visible)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _spawn_panel.visible:
		for pivot in _pivots:
			pivot.rotate_y(deg_to_rad(SPIN_SPEED) * delta)
	if _cheats_panel.visible:
		_sync_cheats()
	_place_dropdowns()
	_update_cursor()


func _physics_process(_delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	if ship.health != null:
		ship.health.invulnerable = invulnerable
	if unlimited_boost:
		ship.boost_fuel = 1.0
	if unlimited_torpedoes and ship.heavy != null:
		ship.heavy.charges = ship.heavy.max_charges


## True while the pointer is over the tools bar or an open dropdown.
func is_pointer_over() -> bool:
	var node: Node = get_viewport().gui_get_hovered_control()
	while node != null and node != self:
		if node.is_in_group("blocks_fire"):
			return true
		node = node.get_parent()
	return false


## Shows the system cursor while it's over the tools. The arena hides it
## everywhere else (the aim reticle stands in for it).
func _update_cursor() -> void:
	if _menu_open():
		_cursor_shown = false
		return
	var over := is_pointer_over()
	if over and Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_cursor_shown = true
	elif not over and _cursor_shown:
		_cursor_shown = false
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _menu_open() -> bool:
	if get_tree().paused:
		return true
	var ui := get_parent().get_node_or_null("GameUI") as GameUI
	return ui != null and (ui.pause_menu.is_open or ui.ship_menu.is_open \
		or ui.augment_picker.is_open or ui.end_screen.is_open)


func _set_cheats_open(open: bool) -> void:
	_cheats_panel.visible = open
	_cheats_button.set_pressed_no_signal(open)
	_refresh_labels()


func _set_spawn_open(open: bool) -> void:
	_spawn_panel.visible = open
	_spawn_button.set_pressed_no_signal(open)
	# Only render the thumbnails while they can be seen.
	for vp in _viewports:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED
	_refresh_labels()


func _refresh_labels() -> void:
	var on := int(invulnerable) + int(unlimited_boost) + int(unlimited_torpedoes)
	var arrow := "  ▲" if _cheats_panel.visible else "  ▼"
	_cheats_button.text = ("CHEATS (%d on)" % on if on > 0 else "CHEATS") + "   F2" + arrow
	arrow = "  ▲" if _spawn_panel.visible else "  ▼"
	_spawn_button.text = "SPAWN ENEMY   F3" + arrow


# --- Building the UI ---------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bar := HBoxContainer.new()
	bar.name = "Bar"
	bar.add_to_group("blocks_fire")
	bar.add_theme_constant_override("separation", 10)
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.position.y = 12.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	# The dropdowns hang below their buttons but aren't inside the bar, so
	# opening one never shifts the buttons around.
	_cheats_button = _header_button(bar)
	_cheats_button.toggled.connect(_set_cheats_open)
	_cheats_panel = _panel(root)
	_build_cheats(_cheats_panel)

	_spawn_button = _header_button(bar)
	_spawn_button.toggled.connect(_set_spawn_open)
	_spawn_panel = _panel(root)
	_build_spawn_table(_spawn_panel)


## Hangs each open dropdown under its button, kept on screen.
func _place_dropdowns() -> void:
	var screen := get_viewport().get_visible_rect().size
	for pair in [[_cheats_panel, _cheats_button], [_spawn_panel, _spawn_button]]:
		var panel: Control = pair[0]
		var button: Control = pair[1]
		if not panel.visible:
			continue
		var at := button.global_position + Vector2(0.0, button.size.y + 4.0)
		if panel == _spawn_panel and _cheats_panel.visible:
			# Both open: keep the table clear of the cheat list.
			at.x = maxf(at.x, _cheats_panel.get_global_rect().end.x + 8.0)
		at.x = clampf(at.x, 8.0, maxf(screen.x - panel.size.x - 8.0, 8.0))
		panel.position = at


func _build_cheats(panel: PanelContainer) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(list)
	_cheat_toggle(list, "Invulnerable", &"invulnerable")
	_cheat_toggle(list, "Unlimited boost", &"unlimited_boost")
	_cheat_toggle(list, "Unlimited torpedoes", &"unlimited_torpedoes")


func _cheat_toggle(list: Control, text: String, flag: StringName) -> void:
	var b := Button.new()
	b.name = "Cheat_" + text.replace(" ", "_")
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.x = 230.0
	b.add_theme_color_override("font_color", TEXT.darkened(0.25))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(Color(0.2, 0.13, 0.08, 0.6), Color(0.4, 0.3, 0.18)))
	b.add_theme_stylebox_override("hover", _box(Color(0.28, 0.18, 0.1, 0.9), TEXT))
	b.add_theme_stylebox_override("pressed", _box(Color(0.55, 0.33, 0.1, 0.95), TIER_COLORS[1]))
	b.add_theme_stylebox_override("hover_pressed", _box(Color(0.62, 0.38, 0.12, 1.0), Color.WHITE))
	b.set_meta(&"label", text)
	b.toggled.connect(func(pressed: bool):
		_set_cheat(flag, pressed)
		_sync_cheats())
	list.add_child(b)
	_cheat_buttons[flag] = b
	_sync_cheats()


static func _cheat(flag: StringName) -> bool:
	match flag:
		&"invulnerable": return invulnerable
		&"unlimited_boost": return unlimited_boost
		&"unlimited_torpedoes": return unlimited_torpedoes
	return false


static func _set_cheat(flag: StringName, on: bool) -> void:
	match flag:
		&"invulnerable": invulnerable = on
		&"unlimited_boost": unlimited_boost = on
		&"unlimited_torpedoes": unlimited_torpedoes = on


## Shows each cheat's current state (they can also be set from code).
func _sync_cheats() -> void:
	for flag in _cheat_buttons:
		var b: Button = _cheat_buttons[flag]
		var on := _cheat(flag)
		b.set_pressed_no_signal(on)
		b.text = "%s   %s" % [b.get_meta(&"label"), "ON" if on else "off"]
	if _spawn_panel != null: # Still building otherwise.
		_refresh_labels()


## The roster as a table: roles across, tiers down.
func _build_spawn_table(panel: PanelContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 1 + EnemyRoster.Role.size()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(grid)
	grid.add_child(_label("", 13, TEXT))
	for role_name in EnemyRoster.Role.keys():
		var head := _label(role_name, 14, BORDER)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(head)
	for tier in 3:
		var row_head := _label(TIER_NAMES[tier], 16, TIER_COLORS[tier])
		row_head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(row_head)
		for role in EnemyRoster.Role.size():
			grid.add_child(_tile(_entry_index(role, tier + 1)))


func _entry_index(role: int, tier: int) -> int:
	for i in EnemyRoster.ENTRIES.size():
		var e: Dictionary = EnemyRoster.ENTRIES[i]
		if e.role == role and e.tier == tier:
			return i
	return -1


func _tile(index: int) -> Control:
	var entry: Dictionary = EnemyRoster.ENTRIES[index]
	var tier_color: Color = TIER_COLORS[entry.tier - 1]
	var button := Button.new()
	button.name = "Spawn_%s" % entry.id
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "%s: %s" % [entry.name, entry.blurb]
	button.custom_minimum_size = Vector2(THUMB_SIZE.x + 12, THUMB_SIZE.y + 50)
	button.add_theme_stylebox_override("normal", _box(Color(0.2, 0.13, 0.08, 0.9), tier_color.darkened(0.5)))
	button.add_theme_stylebox_override("hover", _box(Color(0.32, 0.21, 0.12, 0.95), tier_color))
	button.add_theme_stylebox_override("pressed", _box(Color(0.45, 0.3, 0.15, 1.0), Color.WHITE))
	button.pressed.connect(func(): spawn_requested.emit(index))

	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)
	stack.add_child(_thumbnail(entry))
	var title := _label(entry.name, 13, TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var sub := _label("key %d" % (index + 1), 11, tier_color)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(sub)
	return button


## A small 3D view of the enemy's model, lit and framed on its own.
func _thumbnail(entry: Dictionary) -> Control:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.custom_minimum_size = THUMB_SIZE
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	box.add_child(vp)
	_viewports.append(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.8, 0.9)
	env.ambient_light_energy = 1.1
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.4
	vp.add_child(sun)

	var pivot := Node3D.new()
	vp.add_child(pivot)
	_pivots.append(pivot)
	var model := _model_of(entry)
	var radius := 1.0
	if model != null:
		pivot.add_child(model)
		var bounds := _bounds(model, model.transform)
		model.position -= bounds.get_center()
		radius = maxf(bounds.size.length() * 0.5, 0.5)
	pivot.rotation_degrees.y = 30.0

	var cam := Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	# Same tilt as the game camera: looking down from above and behind.
	var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 0.7
	var eye := Vector3(0.0, 0.75, 0.66).normalized() * dist
	cam.transform = Transform3D(Basis.looking_at(-eye), eye)
	return box


## A copy of just the enemy scene's model (its "Visual" node), without the
## AI, weapons or physics.
func _model_of(entry: Dictionary) -> Node3D:
	var ship_node := EnemyRoster.scene_of(entry).instantiate()
	var visual := ship_node.get_node_or_null("Visual") as Node3D
	var copy: Node3D = visual.duplicate() if visual != null else null
	ship_node.free()
	return copy


func _bounds(node: Node, xform: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if node is VisualInstance3D:
		out = xform * (node as VisualInstance3D).get_aabb()
		first = false
	for child in node.get_children():
		var child3d := child as Node3D
		if child3d == null:
			continue
		var b := _bounds(child3d, xform * child3d.transform)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


func _header_button(parent: Control) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(Color(0.12, 0.08, 0.05, 0.82), BORDER))
	b.add_theme_stylebox_override("hover", _box(Color(0.25, 0.16, 0.08, 0.9), TIER_COLORS[1]))
	b.add_theme_stylebox_override("pressed", _box(Color(0.32, 0.2, 0.1, 0.95), TIER_COLORS[1]))
	b.add_theme_stylebox_override("hover_pressed", _box(Color(0.38, 0.24, 0.12, 0.95), Color.WHITE))
	parent.add_child(b)
	return b


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_to_group("blocks_fire")
	p.add_theme_stylebox_override("panel", _box(Color(0.12, 0.08, 0.05, 0.86), BORDER))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 6.0
	s.content_margin_bottom = 6.0
	return s
