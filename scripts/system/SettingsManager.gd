extends Node

const SETTINGS_PATH = "user://settings.cfg"

var master_volume: float = 1.0 # 0.0 to 1.0
var is_fullscreen: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_settings()

func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_PATH)
	if err == OK:
		master_volume = config.get_value("audio", "master_volume", 1.0)
		is_fullscreen = config.get_value("video", "fullscreen", true)
	else:
		master_volume = 1.0
		is_fullscreen = true

func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("video", "fullscreen", is_fullscreen)
	config.save(SETTINGS_PATH)

func apply_settings() -> void:
	# Audio (assuming AudioServer has Master bus at index 0)
	var db := linear_to_db(master_volume)
	if master_volume <= 0.001:
		db = -80.0
	AudioServer.set_bus_volume_db(0, db)
	AudioServer.set_bus_mute(0, master_volume <= 0.001)

	# Video
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func set_master_volume(val: float) -> void:
	master_volume = clamp(val, 0.0, 1.0)
	apply_settings()
	save_settings()

func set_fullscreen(val: bool) -> void:
	is_fullscreen = val
	apply_settings()
	save_settings()
