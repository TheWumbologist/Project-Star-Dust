class_name Sfx
extends Node
## Sound effects and music. Call the static functions from anywhere:
##   Sfx.play(&"cannon", global_position)   # positional, in the world
##   Sfx.play(&"pickup")                     # flat, for UI and the player
##   Sfx.music(&"rift")                      # crossfades to a music loop
## The first call creates one pool node under the scene tree's root, so
## there's no autoload to set up. It survives scene changes and keeps
## playing while the game is paused (menus click too).
##
## Sounds live in assets/_ai_generated/audio/ as sfx_<name>__AI.wav and
## music_<name>__AI.wav (placeholders made by tools/make_sounds.py). Drop
## a replacement over a file, or add a name to OVERRIDES, to swap one.
## Volumes are saved in user://settings.cfg.

const DIR := "res://assets/_ai_generated/audio/"
## name -> res:// path, for sounds that don't follow the naming pattern.
const OVERRIDES := {}
## Tests point this somewhere else so they never touch the real settings.
static var settings_path: String = "user://settings.cfg"
## Voices for world sounds and for flat (UI / player) sounds.
const WORLD_VOICES := 20
const FLAT_VOICES := 8
## The same sound won't restart more often than this (seconds), so a
## burst of hits doesn't turn into a wall of noise.
const MIN_GAP := 0.045
## Per-sound volume trims in dB.
const TRIM := {
	&"cannon": -9.0, &"enemy_shot": -11.0, &"rock_chip": -8.0, &"hit_shield": -6.0,
	&"hit_hull": -5.0, &"pickup": -7.0, &"ui_click": -10.0, &"ui_confirm": -6.0,
	&"boost": -6.0, &"explosion_small": -3.0, &"broadside": -5.0, &"lance": -3.0,
	&"fuse": -5.0, &"charge": -7.0, &"mine_drop": -6.0, &"blink": -4.0,
}

static var music_volume: float = 0.6
static var sfx_volume: float = 0.8
## Sounds played so far, newest last (tests read this).
static var history: Array[StringName] = []

static var _pool: Sfx = null
static var _settings_loaded: bool = false

var _world: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _next_world: int = 0
var _next_flat: int = 0
var _last_played: Dictionary = {}
var _streams: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_name: StringName = &""
var _fade: Tween
var _pending_music: StringName = &""


## Plays a sound effect. With `at`, it plays in the world there (panned
## and quieter with distance); without, it plays flat.
static func play(sound: StringName, at: Vector3 = Vector3.INF, volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var pool := _get_pool()
	if pool != null:
		pool._play(sound, at, volume_db, pitch_jitter)


## Crossfades to a music loop (&"rift", &"hub"); &"" fades music out.
static func music(track: StringName) -> void:
	var pool := _get_pool()
	if pool != null:
		pool._play_music(track)


## Stops every sound and drops the music. The audio server lets go of
## the streams a few frames later, so quit after that (Scenes.quit does).
static func stop_all() -> void:
	if is_instance_valid(_pool):
		_pool._stop_players()


static func current_music() -> StringName:
	if not is_instance_valid(_pool):
		return &""
	return _pool._pending_music if _pool._pending_music != &"" else _pool._music_name


## Linear 0..1 volumes; saved for next time.
static func set_volumes(music_linear: float, sfx_linear: float) -> void:
	music_volume = clampf(music_linear, 0.0, 1.0)
	sfx_volume = clampf(sfx_linear, 0.0, 1.0)
	_apply_volumes()
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.save(settings_path)


static func load_settings() -> void:
	_settings_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		music_volume = clampf(cfg.get_value("audio", "music", music_volume), 0.0, 1.0)
		sfx_volume = clampf(cfg.get_value("audio", "sfx", sfx_volume), 0.0, 1.0)
	_apply_volumes()


static func _apply_volumes() -> void:
	_ensure_buses()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_volume, 0.0001)))


static func _ensure_buses() -> void:
	for bus in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, &"Master")


static func _get_pool() -> Sfx:
	if is_instance_valid(_pool):
		return _pool
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	if not _settings_loaded:
		load_settings()
	_pool = Sfx.new()
	_pool.name = "SfxPool"
	tree.root.add_child.call_deferred(_pool)
	_pool._build()
	return _pool


func _build() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in WORLD_VOICES:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 40.0
		p.max_distance = 150.0
		p.attenuation_filter_cutoff_hz = 9000.0
		_world.append(p)
		add_child(p)
	for i in FLAT_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		_flat.append(p)
		add_child(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m in [_music_a, _music_b]:
		m.bus = &"Music"
		m.volume_db = -80.0
		add_child(m)


func _enter_tree() -> void:
	# Every button in the game clicks.
	get_tree().node_added.connect(_on_node_added)


# Stop everything on the way out, or the audio server keeps the playing
# streams alive past shutdown.
func _exit_tree() -> void:
	_stop_players()


func _stop_players() -> void:
	_music_name = &""
	_pending_music = &""
	if _fade != null and _fade.is_valid():
		_fade.kill()
	for p in get_children():
		if p is AudioStreamPlayer or p is AudioStreamPlayer3D:
			p.stop()
			p.stream = null
	_streams.clear()


func _ready() -> void:
	if _pending_music != &"":
		var track := _pending_music
		_pending_music = &""
		_play_music(track)


func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button != null and not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	_play(&"ui_click", Vector3.INF, 0.0, 0.0)


func _play(sound: StringName, at: Vector3, volume_db: float, pitch_jitter: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -10.0)) < MIN_GAP:
		return
	var stream := _stream(sound)
	if stream == null:
		return
	_last_played[sound] = now
	history.append(sound)
	if history.size() > 64:
		history.pop_front()
	var db: float = volume_db + float(TRIM.get(sound, 0.0))
	var pitch := 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	if at == Vector3.INF or not is_inside_tree():
		var p := _flat[_next_flat]
		_next_flat = (_next_flat + 1) % _flat.size()
		p.stream = stream
		p.volume_db = db
		p.pitch_scale = pitch
		if p.is_inside_tree():
			p.play()
		else:
			p.autoplay = true
	else:
		var p := _world[_next_world]
		_next_world = (_next_world + 1) % _world.size()
		p.stream = stream
		p.volume_db = db
		p.pitch_scale = pitch
		p.global_position = at
		p.play()


func _stream(sound: StringName) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path: String = OVERRIDES.get(sound, DIR + "sfx_%s__AI.wav" % sound)
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if stream == null:
		push_warning("Sfx: no sound called '%s' (%s)" % [sound, path])
	_streams[sound] = stream
	return stream


func _play_music(track: StringName) -> void:
	if not is_inside_tree():
		_pending_music = track # Still being added; start once it's in.
		return
	if track == _music_name:
		return
	_music_name = track
	var incoming := _music_b if _music_a.playing and _music_a.volume_db > -40.0 else _music_a
	var outgoing := _music_a if incoming == _music_b else _music_b
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(outgoing, "volume_db", -80.0, 1.5)
	if track != &"":
		var path := DIR + "music_%s__AI.wav" % track
		if ResourceLoader.exists(path):
			incoming.stream = load(path)
			incoming.volume_db = -40.0
			incoming.play()
			_fade.tween_property(incoming, "volume_db", 0.0, 2.0)
