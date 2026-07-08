## AchievementManager — tracks and unlocks achievements at runtime.
## Autoloaded. Checks triggers on relevant GameState signals.
## Future: call SteamAPI here when steam_id is set.
extends Node

signal achievement_unlocked(def: AchievementDef)

const DEFS_PATH := "res://resources/achievements/"

var _defs: Array[AchievementDef] = []
var _unlocked: Array[String] = []   # achievement_ids already earned this save

func _ready() -> void:
	_load_defs()
	_connect_signals()

func _load_defs() -> void:
	var dir := DirAccess.open(DEFS_PATH)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res := load(DEFS_PATH + fname)
			if res is AchievementDef:
				_defs.append(res as AchievementDef)
		fname = dir.get_next()

func _connect_signals() -> void:
	GameState.planet_progress_changed.connect(_on_planet_progress_changed)
	GameState.credits_changed.connect(func(_v: float) -> void: _check_float_triggers())
	GameState.science_changed.connect(func(_v: float) -> void: _check_float_triggers())
	GameState.asteroid_discovered.connect(func(_s: int, _c: int) -> void:
		_try_unlock_trigger(AchievementDef.Trigger.FIRST_ASTEROID_SCAN))

func load_save(unlocked_ids: Array) -> void:
	_unlocked = unlocked_ids.duplicate()

func get_save_data() -> Array:
	return _unlocked.duplicate()

func is_unlocked(id: String) -> bool:
	return id in _unlocked

func notify_trigger(trigger: AchievementDef.Trigger, context: Variant = null) -> void:
	for def: AchievementDef in _defs:
		if def.trigger != trigger:
			continue
		if def.achievement_id in _unlocked:
			continue
		var earned := false
		match trigger:
			AchievementDef.Trigger.FIRST_DISTRICT, \
			AchievementDef.Trigger.FIRST_BUILDING, \
			AchievementDef.Trigger.FIRST_ORBITAL, \
			AchievementDef.Trigger.FIRST_ASTEROID_SCAN, \
			AchievementDef.Trigger.FIRST_MOON_COLONY, \
			AchievementDef.Trigger.FIRST_SOLAR_TRAVEL, \
			AchievementDef.Trigger.FIRST_GALAXY_VIEW, \
			AchievementDef.Trigger.FIRST_SURVEY:
				earned = true
			AchievementDef.Trigger.PLANET_LEVEL:
				if context is int and (context as int) >= def.int_value:
					earned = true
			AchievementDef.Trigger.BUILDING_COUNT:
				if context is int and (context as int) >= def.int_value:
					earned = true
			AchievementDef.Trigger.DISTRICT_COUNT:
				if context is int and (context as int) >= def.int_value:
					earned = true
			AchievementDef.Trigger.COLONIZED_PLANETS_COUNT:
				if context is int and (context as int) >= def.int_value:
					earned = true
			AchievementDef.Trigger.SKILL_PURCHASED:
				if context is String and (context as String) == def.string_value:
					earned = true
			AchievementDef.Trigger.CREDITS_TOTAL:
				if GameState.credits >= def.float_value:
					earned = true
			AchievementDef.Trigger.SCIENCE_TOTAL:
				if GameState.science_points >= def.float_value:
					earned = true
			AchievementDef.Trigger.MINERAL_COLLECTED:
				var total: float = 0.0
				for k: String in GameState.global_resources:
					total += GameState.global_resources[k]
				if total >= def.float_value:
					earned = true
		if earned:
			_grant(def)

func _try_unlock_trigger(trigger: AchievementDef.Trigger) -> void:
	notify_trigger(trigger)

func _on_planet_progress_changed(_seed: int) -> void:
	# Count total districts and buildings across all planets
	var total_districts := 0
	var total_buildings  := 0
	var colonized_planets := 0
	for seed: int in GameState._planet_progress:
		var pp: PlanetProgress = GameState._planet_progress[seed]
		var d_count: int = pp.custom_pois_count() if pp.has_method("custom_pois_count") else 0
		total_districts += d_count
		if d_count > 0:
			colonized_planets += 1
		for b: Dictionary in pp.buildings:
			if not b.get("constructing", false):
				total_buildings += 1
	notify_trigger(AchievementDef.Trigger.BUILDING_COUNT, total_buildings)
	notify_trigger(AchievementDef.Trigger.DISTRICT_COUNT, total_districts)
	notify_trigger(AchievementDef.Trigger.COLONIZED_PLANETS_COUNT, colonized_planets)

func _check_float_triggers() -> void:
	notify_trigger(AchievementDef.Trigger.CREDITS_TOTAL)
	notify_trigger(AchievementDef.Trigger.SCIENCE_TOTAL)

func _grant(def: AchievementDef) -> void:
	_unlocked.append(def.achievement_id)
	achievement_unlocked.emit(def)
	AudioManager.play("survey", -2.0)
	# Future: SteamAPI.set_achievement(def.steam_id)
