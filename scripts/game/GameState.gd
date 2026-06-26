## GameState — autoload singleton.
## Tracks global progression: credits, unlocks, per-planet progress.
extends Node

signal credits_changed(new_val: float)
signal unlock_changed(key: String, value: bool)
signal planet_progress_changed(seed_val: int)

# ── Economy ──────────────────────────────────────────────────────────────────
var credits: float = 500.0 :
	set(v):
		credits = maxf(v, 0.0)
		credits_changed.emit(credits)

# ── Unlock flags ─────────────────────────────────────────────────────────────
## solar_unlocked: player can enter SolarView (requires SpacePort on home moon/planet)
var solar_unlocked:  bool = false
## galaxy_unlocked: player can enter GalaxyView
var galaxy_unlocked: bool = false
## discovered_asteroid_ids: set of asteroid slot indices visible in SolarView
var discovered_asteroids: Array[int] = []

# ── Per-planet progress ───────────────────────────────────────────────────────
## Keyed by planet seed (int → PlanetProgress)
var _planet_progress: Dictionary = {}

# ── Home planet seed (set at game start) ────────────────────────────────────
var home_planet_seed: int = -1

# ────────────────────────────────────────────────────────────────────────────

## Returns the home PlanetData, always Terran, consistent across sessions.
## Returns the home PlanetData — always Terran, same planet every session.
func get_home_planet() -> PlanetData:
	if home_planet_seed < 0:
		home_planet_seed = randi() % 99999
	var pd := PlanetData.from_seed_as_type(home_planet_seed, PlanetData.Type.TERRAN)
	pd.generate_moons(home_planet_seed)
	pd.set_meta("__is_home", true)
	return pd

func get_planet(seed_val: int) -> PlanetProgress:
	if not _planet_progress.has(seed_val):
		_planet_progress[seed_val] = PlanetProgress.make(seed_val)
	return _planet_progress[seed_val]

func set_unlock(key: String, value: bool) -> void:
	match key:
		"solar":  solar_unlocked  = value
		"galaxy": galaxy_unlocked = value
	unlock_changed.emit(key, value)

func discover_asteroid(slot_idx: int) -> void:
	if slot_idx not in discovered_asteroids:
		discovered_asteroids.append(slot_idx)

func spend_credits(amount: float) -> bool:
	if credits < amount:
		return false
	credits -= amount
	return true

func earn_credits(amount: float) -> void:
	credits += amount

# ── Save / Load ──────────────────────────────────────────────────────────────
const SAVE_PATH := "user://voidle_save.dat"

func save() -> void:
	var data := {
		"credits":              credits,
		"solar_unlocked":       solar_unlocked,
		"galaxy_unlocked":      galaxy_unlocked,
		"discovered_asteroids": discovered_asteroids,
		"home_planet_seed":     home_planet_seed,
		"planet_progress":      {},
	}
	for seed_val in _planet_progress:
		var pp: PlanetProgress = _planet_progress[seed_val]
		data["planet_progress"][str(seed_val)] = {
			"level":            pp.level,
			"districts_used":   pp.districts_used,
			"buildings":        pp.buildings,
			"stored_resources": pp.stored_resources,
			"has_spaceport":    pp.has_spaceport,
		}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(data)

func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var data: Dictionary = file.get_var()
	credits              = data.get("credits",              500.0)
	solar_unlocked       = data.get("solar_unlocked",       false)
	galaxy_unlocked      = data.get("galaxy_unlocked",      false)
	home_planet_seed     = data.get("home_planet_seed",     -1)
	discovered_asteroids = data.get("discovered_asteroids", [])
	for key in data.get("planet_progress", {}).keys():
		var seed_val: int    = int(key)
		var d: Dictionary    = data["planet_progress"][key]
		var pp               := PlanetProgress.make(seed_val)
		pp.level             = d.get("level",          1)
		pp.districts_used    = d.get("districts_used", 0)
		pp.buildings         = d.get("buildings",      [])
		pp.stored_resources  = d.get("stored_resources", {})
		pp.has_spaceport     = d.get("has_spaceport",  false)
		pp.recalculate_limits()
		_planet_progress[seed_val] = pp
	return true

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	credits              = 500.0
	solar_unlocked       = false
	galaxy_unlocked      = false
	discovered_asteroids = []
	home_planet_seed     = -1
	_planet_progress.clear()
