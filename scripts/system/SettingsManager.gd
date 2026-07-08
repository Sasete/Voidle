extends Node

const SETTINGS_PATH = "user://settings.cfg"

var master_volume: float = 1.0
var music_volume:  float = 1.0
var ui_volume:     float = 1.0
var sfx_volume:    float = 1.0
var is_fullscreen: bool = true
var tutorial_ever_done: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	load_settings()
	apply_settings()

func _ensure_buses() -> void:
	for bus_name in ["Music", "UI", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err == OK:
		master_volume      = config.get_value("audio",    "master_volume", 1.0)
		music_volume       = config.get_value("audio",    "music_volume",  1.0)
		ui_volume          = config.get_value("audio",    "ui_volume",     1.0)
		sfx_volume         = config.get_value("audio",    "sfx_volume",    1.0)
		is_fullscreen      = config.get_value("video",    "fullscreen",    true)
		tutorial_ever_done = config.get_value("tutorial", "ever_done",     false)
	else:
		master_volume = 1.0
		music_volume  = 1.0
		ui_volume     = 1.0
		sfx_volume    = 1.0
		is_fullscreen = true

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio",    "master_volume", master_volume)
	config.set_value("audio",    "music_volume",  music_volume)
	config.set_value("audio",    "ui_volume",     ui_volume)
	config.set_value("audio",    "sfx_volume",    sfx_volume)
	config.set_value("video",    "fullscreen",    is_fullscreen)
	config.set_value("tutorial", "ever_done",     tutorial_ever_done)
	config.save(SETTINGS_PATH)

func apply_settings() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music",  music_volume)
	_set_bus_volume("UI",     ui_volume)
	_set_bus_volume("SFX",    sfx_volume)
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _set_bus_volume(bus_name: String, val: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	if val <= 0.001:
		AudioServer.set_bus_volume_db(idx, -80.0)
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_volume_db(idx, linear_to_db(val))
		AudioServer.set_bus_mute(idx, false)

func set_master_volume(val: float) -> void:
	master_volume = clamp(val, 0.0, 1.0)
	apply_settings(); save_settings()

func set_music_volume(val: float) -> void:
	music_volume = clamp(val, 0.0, 1.0)
	apply_settings(); save_settings()

func set_ui_volume(val: float) -> void:
	ui_volume = clamp(val, 0.0, 1.0)
	apply_settings(); save_settings()

func set_sfx_volume(val: float) -> void:
	sfx_volume = clamp(val, 0.0, 1.0)
	apply_settings(); save_settings()

func set_fullscreen(val: bool) -> void:
	is_fullscreen = val
	apply_settings(); save_settings()
