## GameState — autoload singleton.
## Tracks global progression: credits, unlocks, per-planet progress.
extends Node

signal credits_changed(new_val: float)
signal save_deleted
signal science_changed(new_val: float)
signal world_ready
signal unlock_changed(key: String, value: bool)
signal planet_progress_changed(seed_val: int)
signal asteroid_discovered(slot: int, count: int)
signal global_resources_changed
signal district_placed(planet_seed: int, district_type_id: int)

# ── Starting Config (edit these to change new-game defaults) ─────────────────
## Starting credits for a new game.
@export var start_credits:        float = 1000.0
## Whether Solar View is unlocked from the start.
@export var start_solar_unlocked: bool  = false
## Whether Galaxy View is unlocked from the start.
@export var start_galaxy_unlocked: bool = false
## Whether the home planet starts colonized.
@export var start_colonized:      bool  = true

# ── Economy ──────────────────────────────────────────────────────────────────
## Global mineral/resource pool shared across all planets and facilities.
var global_resources: Dictionary = {}

func add_resource(resource_id: String, amount: float) -> void:
	global_resources[resource_id] = global_resources.get(resource_id, 0.0) + amount
	global_resources_changed.emit()

func consume_resource(resource_id: String, amount: float) -> bool:
	var have: float = global_resources.get(resource_id, 0.0)
	if have < amount:
		return false
	global_resources[resource_id] = have - amount
	global_resources_changed.emit()
	return true

func get_resource(resource_id: String) -> float:
	return global_resources.get(resource_id, 0.0)

var credits: float = 500.0 :
	set(v):
		credits = maxf(v, 0.0)
		credits_changed.emit(credits)

var science_points: float = 0.0 :
	set(v):
		science_points = maxf(v, 0.0)
		science_changed.emit(science_points)

# ── Unlock flags ─────────────────────────────────────────────────────────────
var solar_unlocked:    bool = false
var moon_unlocked:     bool = false
var galaxy_unlocked:   bool = false
## Seed of the planet currently shown in PlanetaryView. -1 when not in that scene.
var active_planet_seed: int = -1
var discovered_asteroids: Array[int] = []
var asteroid_scan_counts: Dictionary = {}   # slot → int (1-3 asteroids revealed)

# day/night cycle — persists across scene changes, advances in real time
var light_angle:          float = 0.8
var light_last_unix:      int   = 0   # unix timestamp when we last stored the angle

# ── Per-planet progress ───────────────────────────────────────────────────────
var _planet_progress:       Dictionary = {}
var _body_resources:        Dictionary = {}
var known_resources:        Dictionary = {}
var resource_deposit_counts: Dictionary = {}
var unlocked_buildings:     Dictionary = {}

# ── Home location (set once at world generation, then saved) ─────────────────
var home_planet_seed: int  = -1   # seed of the Terran home planet
var home_star_idx:    int  = -1   # which star in home_galaxy is the home system
var home_planet_idx:  int  = -1   # which planet index in that system

# ── Pre-generated world ───────────────────────────────────────────────────────
var home_galaxy: GalaxyData = null
var _home_solar: SolarData  = null

# ────────────────────────────────────────────────────────────────────────────

var _autosave_timer: float = 0.0
const AUTOSAVE_INTERVAL := 60.0

func _ready() -> void:
	load_save()
	if home_planet_seed < 0:
		home_planet_seed = randi_range(1000, 99999)
	_bootstrap_world()

func _process(delta: float) -> void:
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save()

static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func unlock_building(building_id: String) -> void:
	if not unlocked_buildings.has(building_id):
		unlocked_buildings[building_id] = true
		print("Building Unlocked: ", building_id)

func _bootstrap_world() -> void:
	# Galaxy first
	if home_galaxy == null:
		home_galaxy = GalaxyData.from_seed(home_planet_seed ^ 0xABCDEF)

	# Home star is always galaxy.home_idx (index 0, center star)
	if home_star_idx < 0 and home_galaxy != null:
		home_star_idx = home_galaxy.home_idx

	# Build home solar and inject home planet at chosen index
	if _home_solar == null:
		_home_solar = _build_home_solar()

	_seed_starting_resources()
	world_ready.emit()

func _seed_starting_resources() -> void:
	var home_pp := get_planet(home_planet_seed)
	var home_pd := get_home_planet()

	# Register home planet mineral types (no pre-filled inventory)
	var r1t1 := ResourceData.generate(home_planet_seed, ResourceData.Tag.RAW_MINERAL, 1, 1)
	var r2t1 := ResourceData.generate(home_planet_seed, ResourceData.Tag.RAW_MINERAL, 2, 1)
	for rd: ResourceData in [r1t1, r2t1]:
		var key := rd.resource_id()
		if not known_resources.has(key):
			known_resources[key] = rd

	# Force home planet deposits: R1 always present, R2 injected at low density
	var br := get_body_resources_for(home_pd)
	if not br.resources.has(r2t1.resource_id()):
		br.resources[r2t1.resource_id()] = r2t1

	# Per-mineral density overrides for home planet
	if home_pd != null:
		home_pd.mineral_densities[r1t1.resource_id()] = 0.80
		home_pd.mineral_densities[r2t1.resource_id()] = 0.10

	pass  # orbital district added later via SkillTree unlock

func _build_home_solar() -> SolarData:
	# Use the galaxy star's own seed so the system matches what the galaxy would generate
	var solar_seed: int
	if home_galaxy != null and home_star_idx >= 0 and home_star_idx < home_galaxy.seeds.size():
		solar_seed = home_galaxy.seeds[home_star_idx]
	else:
		solar_seed = home_planet_seed ^ 0x1234
	var sd         := SolarData.from_seed(solar_seed)
	sd.is_home     = true
	if home_galaxy != null and home_star_idx >= 0:
		sd.system_name = home_galaxy.names[home_star_idx]
		sd.star_type   = home_galaxy.types[home_star_idx] as SolarData.StarType

	# Decide home planet index by seed (not necessarily 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = home_planet_seed ^ 0x5678
	home_planet_idx = rng.randi() % maxi(sd.planets.size(), 1)

	# Override that slot with guaranteed Terran planet — always exactly 1 moon
	var home_pd := PlanetData.from_seed_as_type(home_planet_seed, PlanetData.Type.TERRAN)
	home_pd.moons.clear()
	var moon := PlanetData.make_moon(home_planet_seed ^ 0x4D6F6F6E)
	moon.planet_name = home_pd.planet_name + " a"
	home_pd.moons.append(moon)
	home_pd.set_meta("__is_home", true)
	
	sd.planets[home_planet_idx] = home_pd

	# Cache all generated planets in the home system so that tooltips and production
	# work correctly immediately after loading a save file.
	for pd in sd.planets:
		cache_planet_data(pd)
		for m in pd.moons:
			cache_planet_data(m)

	sd.set_meta("__is_home", true)

	# Apply starting config
	credits         = start_credits
	solar_unlocked  = start_solar_unlocked
	galaxy_unlocked = start_galaxy_unlocked

	var home_pp := get_planet(home_planet_seed)
	home_pp.is_colonized = start_colonized

	# Attach starting Capital POI only once (first time world is built)
	if home_pd.custom_pois.is_empty():
		var poi       := POIData.new()
		poi.label      = "Capital"
		poi.poi_type   = POIData.POIType.CITY
		poi.type_tag   = "city"
		poi.placement  = LocationFinder.Placement.LAND
		poi.light_intensity = 2.0
		home_pd.custom_pois.append(poi)

	if home_planet_idx < sd.planets.size():
		sd.planets[home_planet_idx] = home_pd
	else:
		sd.planets.append(home_pd)
		home_planet_idx = sd.planets.size() - 1

	# Tag the solar data with the galaxy reference for back-navigation
	if home_galaxy != null:
		sd.set_meta("__galaxy_data",    home_galaxy)
		sd.set_meta("__galaxy_star_idx", home_star_idx)

	return sd

# ── Accessors ─────────────────────────────────────────────────────────────────

func get_home_solar() -> SolarData:
	return _home_solar

func get_home_planet() -> PlanetData:
	if _home_solar == null or home_planet_idx < 0:
		return null
	return _home_solar.planets[home_planet_idx]

func get_planet(seed_val: int) -> PlanetProgress:
	if not _planet_progress.has(seed_val):
		_planet_progress[seed_val] = PlanetProgress.make(seed_val)
	return _planet_progress[seed_val]

## Returns cached PlanetData for a given seed (set by PlanetaryView when visiting).
var _planet_data_cache: Dictionary = {}   # seed -> PlanetData
func cache_planet_data(pd: PlanetData) -> void:
	_planet_data_cache[pd.seed] = pd
func get_planet_data(seed_val: int) -> PlanetData:
	return _planet_data_cache.get(seed_val, null)

func get_body_resources(body_seed: int,
		rarity_min: int = 1, rarity_max: int = 1) -> BodyResources:
	if not _body_resources.has(body_seed):
		var br := BodyResources.generate(body_seed, rarity_min, rarity_max)
		_body_resources[body_seed] = br
		_register_resources(br)
	return _body_resources[body_seed] as BodyResources

func get_body_resources_for(pd: PlanetData) -> BodyResources:
	var range := BodyResources.rarity_range_for(pd.planet_type)
	var br := get_body_resources(pd.seed, range.x, range.y)
	if pd.mineral_densities.is_empty():
		_populate_mineral_densities(pd, br)
	return br

func _populate_mineral_densities(pd: PlanetData, br: BodyResources) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = pd.seed ^ 0x9999
	var raw_list := br.get_by_tag(ResourceData.Tag.RAW_MINERAL)
	if raw_list.is_empty(): return
	
	var base_density := pd.deposit_density
	var total_weight: float = 0.0
	var weights: Array[float] = []
	for rd in raw_list:
		# Lower rarity = much higher weight. e.g. R1=1.0, R2=0.4, R3=0.16
		var w := 1.0 / pow(2.5, float(rd.rarity - br.rarity_min))
		w *= rng.randf_range(0.8, 1.2)
		weights.append(w)
		total_weight += w
	
	for i in raw_list.size():
		var share := weights[i] / total_weight
		pd.mineral_densities[raw_list[i].resource_id()] = share * base_density * rng.randf_range(0.9, 1.1)

func _register_resources(br: BodyResources) -> void:
	for rd: ResourceData in br.as_array():
		var type_key := rd.resource_id()
		if not known_resources.has(type_key):
			known_resources[type_key] = rd
			resource_deposit_counts[type_key] = 1
		else:
			resource_deposit_counts[type_key] = resource_deposit_counts.get(type_key, 1) + 1

func deposit_count(resource_id: String) -> int:
	return resource_deposit_counts.get(resource_id, 0)

# ── Unlocks ───────────────────────────────────────────────────────────────────

func set_unlock(key: String, value: bool) -> void:
	match key:
		"solar":  solar_unlocked  = value
		"galaxy": galaxy_unlocked = value
	unlock_changed.emit(key, value)

func discover_asteroid(slot_idx: int) -> void:
	var cur: int = asteroid_scan_counts.get(slot_idx, 0)
	if cur >= 3:
		return
	var new_count := cur + 1
	asteroid_scan_counts[slot_idx] = new_count
	if slot_idx not in discovered_asteroids:
		discovered_asteroids.append(slot_idx)
	asteroid_discovered.emit(slot_idx, new_count)

func discover_asteroid_all(slot_idx: int) -> void:
	asteroid_scan_counts[slot_idx] = 3
	if slot_idx not in discovered_asteroids:
		discovered_asteroids.append(slot_idx)
	asteroid_discovered.emit(slot_idx, 3)

# ── Economy ───────────────────────────────────────────────────────────────────

func spend_credits(amount: float) -> bool:
	if credits < amount:
		return false
	credits -= amount
	return true

func earn_credits(amount: float) -> void:
	credits += amount

func add_science(amount: float) -> void:
	science_points += amount

func spend_science(amount: float) -> bool:
	if science_points < amount:
		return false
	science_points -= amount
	return true

## Stub colonize — no ship requirement yet. Returns false if can't afford.
func colonize_planet(planet_seed: int, cost: float = 1000.0) -> bool:
	if not spend_credits(cost):
		return false
	var pp := get_planet(planet_seed)
	pp.is_colonizing = true
	pp.colonize_progress = 0.0
	pp.colonize_duration = 30.0 # 30 seconds
	
	planet_progress_changed.emit(planet_seed)
	return true

func finish_colonization(planet_seed: int) -> void:
	var pp := get_planet(planet_seed)
	pp.is_colonizing = false
	pp.colonize_progress = 1.0
	pp.is_colonized = true
	
	var pd := get_planet_data(planet_seed)
	if pd != null:
		var has_poi := false
		for p in pd.custom_pois:
			if p.poi_type == POIData.POIType.CITY or p.poi_type == POIData.POIType.OUTPOST:
				has_poi = true
				break
		if not has_poi:
			var poi := POIData.new()
			poi.placement = 0 # LocationFinder.Placement.LAND
			if pd.planet_type == PlanetData.Type.MOON:
				poi.label = "Lunar Outpost"
				poi.poi_type = POIData.POIType.OUTPOST
				poi.type_tag = "outpost"
			else:
				poi.label = "Colony"
				poi.poi_type = POIData.POIType.CITY
				poi.type_tag = "city"
			poi.light_intensity = 2.0
			pd.custom_pois.append(poi)

	planet_progress_changed.emit(planet_seed)

# ── Save / Load ───────────────────────────────────────────────────────────────
const SAVE_PATH := "user://voidle_save.dat"

func save() -> void:
	var data := {
		"credits":              credits,
		"science_points":       science_points,
		"solar_unlocked":       solar_unlocked,
		"moon_unlocked":        moon_unlocked,
		"galaxy_unlocked":      galaxy_unlocked,
		"discovered_asteroids": discovered_asteroids,
		"asteroid_scan_counts": asteroid_scan_counts,
		"home_planet_seed":     home_planet_seed,
		"home_star_idx":        home_star_idx,
		"home_planet_idx":      home_planet_idx,
		"unlocked_skills":      get_node("/root/SkillTree").unlocked_skills if has_node("/root/SkillTree") else ["root"],
		"skill_levels":         get_node("/root/SkillTree").skill_levels if has_node("/root/SkillTree") else {},
		"ships":                get_node("/root/ShipManager").serialize() if has_node("/root/ShipManager") else [],
		"planet_progress":      {},
	}
	for seed_val in _planet_progress:
		var pp: PlanetProgress = _planet_progress[seed_val]
		data["planet_progress"][str(seed_val)] = {
			"level":             pp.level,
			"is_upgrading":      pp.is_upgrading,
			"upgrade_progress":  pp.upgrade_progress,
			"upgrade_duration":  pp.upgrade_duration,
			"is_colonizing":     pp.is_colonizing,
			"colonize_progress": pp.colonize_progress,
			"colonize_duration": pp.colonize_duration,
			"is_colonized":      pp.is_colonized,
			"districts_used":    pp.districts_used,
			"district_levels":   pp.district_levels,
			"buildings":         pp.buildings,
			"stored_resources":  pp.stored_resources,
			"has_spaceport":     pp.has_spaceport,
			"moons_unlocked":    pp.moons_unlocked,
		}
	data["global_resources"]    = global_resources
	data["unlocked_buildings"]  = unlocked_buildings
	data["light_angle"]         = light_angle
	data["achievements"]        = AchievementManager.get_save_data()
	data["tutorial_done"]        = TutorialManager._tutorial_done
	data["tutorial_quest_done"]  = TutorialManager._quest_done
	data["tutorial_guided_step"] = TutorialManager._guided_step
	data["tutorial_action_sub"]  = TutorialManager._action_sub
	data["tutorial_quest_step"]  = TutorialManager._quest_step
	data["tutorial_quest_sub"]   = TutorialManager._quest_sub
	data["tutorial_solar_count"] = TutorialManager._solar_count
	data["tutorial_inv_shown"]   = TutorialManager._inventory_shown
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(data)

func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var data: Dictionary     = file.get_var()
	credits                  = data.get("credits",              500.0)
	science_points           = data.get("science_points",       0.0)
	solar_unlocked           = data.get("solar_unlocked",       false)
	moon_unlocked            = data.get("moon_unlocked",        false)
	galaxy_unlocked          = data.get("galaxy_unlocked",      false)
	home_planet_seed         = data.get("home_planet_seed",     -1)
	home_star_idx            = data.get("home_star_idx",        -1)
	home_planet_idx          = data.get("home_planet_idx",      -1)
	discovered_asteroids     = data.get("discovered_asteroids", [])
	asteroid_scan_counts     = data.get("asteroid_scan_counts", {})
	
	var st := get_node("/root/SkillTree")
	st.unlocked_skills.clear()
	if data.has("unlocked_skills"):
		for s in data["unlocked_skills"]:
			st.unlocked_skills.append(s)
	else:
		st.unlocked_skills.append("root")
		
	st.skill_levels.clear()
	if data.has("skill_levels"):
		st.skill_levels.merge(data["skill_levels"])

	global_resources    = data.get("global_resources",   {})
	unlocked_buildings  = data.get("unlocked_buildings", {})
	light_angle         = data.get("light_angle",        0.8)

	if data.has("achievements"):
		AchievementManager.load_save(data["achievements"])

	TutorialManager._tutorial_done    = data.get("tutorial_done",        false)
	TutorialManager._quest_done       = data.get("tutorial_quest_done",  false)
	TutorialManager._guided_step      = data.get("tutorial_guided_step", 0)
	TutorialManager._action_sub       = data.get("tutorial_action_sub",  0)
	TutorialManager._quest_step       = data.get("tutorial_quest_step",  0)
	TutorialManager._quest_sub        = data.get("tutorial_quest_sub",   0)
	TutorialManager._solar_count      = data.get("tutorial_solar_count", 0)
	TutorialManager._inventory_shown  = data.get("tutorial_inv_shown",   false)

	if has_node("/root/ShipManager"):
		get_node("/root/ShipManager").deserialize(data.get("ships", []))

	for key in data.get("planet_progress", {}).keys():
		var seed_val: int    = int(key)
		var d: Dictionary    = data["planet_progress"][key]
		var pp               := PlanetProgress.make(seed_val)
		pp.level             = d.get("level",            1)
		pp.is_upgrading      = d.get("is_upgrading",     false)
		pp.upgrade_progress  = d.get("upgrade_progress", 0.0)
		pp.upgrade_duration  = d.get("upgrade_duration", 60.0)
		pp.is_colonizing     = d.get("is_colonizing",    false)
		pp.colonize_progress = d.get("colonize_progress", 0.0)
		pp.colonize_duration = d.get("colonize_duration", 30.0)
		pp.is_colonized      = d.get("is_colonized",     false)
		pp.districts_used    = d.get("districts_used",   0)
		pp.district_levels   = d.get("district_levels",  {})
		pp.buildings         = d.get("buildings",        [])
		pp.has_spaceport     = d.get("has_spaceport",    false)
		pp.moons_unlocked    = d.get("moons_unlocked",   false)
		pp.recalculate_limits()
		_planet_progress[seed_val] = pp
	return true

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	save_deleted.emit()
	credits              = 500.0
	science_points       = 0.0
	solar_unlocked       = false
	galaxy_unlocked      = false
	discovered_asteroids = []
	asteroid_scan_counts = {}
	home_planet_seed     = randi_range(1000, 99999)
	home_star_idx        = -1
	home_planet_idx      = -1
	_home_solar          = null
	home_galaxy          = null
	var st := get_node("/root/SkillTree")
	st.unlocked_skills.clear()
	st.unlocked_skills.append("root")
	st.skill_levels.clear()
	_planet_progress.clear()
	_bootstrap_world()
