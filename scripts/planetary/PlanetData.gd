class_name PlanetData
extends Resource

enum Type { TERRAN, ARID, ICE, VOLCANIC, BARREN, GAS_GIANT, MOON, ASTEROID }
enum ShaderType { ROCKY, GAS, MOON, ASTEROID }

static func get_shader_type(type: Type) -> ShaderType:
	match type:
		Type.GAS_GIANT: return ShaderType.GAS
		Type.MOON:      return ShaderType.MOON
		Type.ASTEROID:  return ShaderType.ASTEROID
		_:              return ShaderType.ROCKY

static func get_shader_path(type: Type) -> String:
	match get_shader_type(type):
		ShaderType.GAS:      return "res://shaders/planet_gas.gdshader"
		ShaderType.MOON:     return "res://shaders/planet_moon.gdshader"
		ShaderType.ASTEROID: return "res://shaders/planet_asteroid.gdshader"
		_:                   return "res://shaders/planet_rocky.gdshader"

# Core identity
@export var planet_name: String = "Unknown"
@export var planet_type: Type = Type.TERRAN
@export var seed: int = 0

# Visual parameters — can be overridden after from_seed()
@export var planet_size: float = 1.0          # 0.3 = moon, 1.0 = normal, 1.5 = giant
@export var has_atmosphere: bool = true
@export var atmosphere_density: float = 1.0   # 0 = none, 1 = thick
@export var has_clouds: bool = true
@export var cloud_coverage: float = 0.5       # 0 = clear, 1 = overcast
@export var cloud_speed: float = 0.05
@export var terrain_roughness: float = 1.0    # affects fbm scale
@export var sea_level: float = 0.0
@export var continent_scale: float = 1.0      # 0.3=huge continents, 2.0=archipelago
@export var specular_strength: float = 1.0    # 0=no ocean glint (barren/arid)
@export var city_lights: float = 0.6          # night side glow
@export var irregularity: float = 0.3
@export var custom_pois: Array[POIData] = []
@export var moons: Array[PlanetData] = []

# Ring system
@export var has_rings:   bool  = false
@export var ring_color:  Color = Color(0.85, 0.78, 0.55, 0.65)
@export var ring_inner:  float = 1.25
@export var ring_outer:  float = 1.95

# -----------------------------------------------------------------------
# Factory
# -----------------------------------------------------------------------
static func from_seed(s: int) -> PlanetData:
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var data := PlanetData.new()
	data.seed = s
	data.planet_type = rng.randi() % Type.size() as Type
	data.planet_name  = _generate_name(rng)
	_apply_type_defaults(data, rng)
	return data

static func from_seed_no_minor(s: int) -> PlanetData:
	# Like from_seed but never returns MOON or ASTEROID (for use as a main planet)
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var data := PlanetData.new()
	data.seed = s
	var allowed := [Type.TERRAN, Type.ARID, Type.ICE, Type.VOLCANIC, Type.BARREN, Type.GAS_GIANT]
	data.planet_type = allowed[rng.randi() % allowed.size()]
	data.planet_name  = _generate_name(rng)
	_apply_type_defaults(data, rng)
	return data

func generate_moons(s: int) -> void:
	moons.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = s ^ 0xBEEF
	var max_count: int
	match planet_type:
		Type.GAS_GIANT:                  max_count = 3
		Type.TERRAN, Type.ICE:           max_count = 2
		Type.VOLCANIC, Type.BARREN:      max_count = 1
		_:                               max_count = 0
	var count: int = rng.randi_range(0, max_count)
	const SUFFIXES := ["a", "b", "c", "d"]
	for i in count:
		var moon: PlanetData = make_moon(s * 13 + i * 777 + 1)
		moon.planet_name = planet_name + " " + SUFFIXES[i]
		moons.append(moon)

# Convenience presets — pass a seed so name/micro-variation still differs
static func make_moon(s: int) -> PlanetData:
	var data := PlanetData.new()
	data.seed        = s
	data.planet_type = Type.MOON
	data.planet_name = _generate_name_with_seed(s)
	data.planet_size = 0.45
	data.has_atmosphere   = false
	data.atmosphere_density = 0.0
	data.has_clouds       = false
	data.cloud_coverage   = 0.0
	data.terrain_roughness = 1.3
	return data

static func make_mars(s: int) -> PlanetData:
	var data := PlanetData.new()
	data.seed        = s
	data.planet_type = Type.ARID
	data.planet_name = _generate_name_with_seed(s)
	data.planet_size = 0.75
	data.has_atmosphere   = true
	data.atmosphere_density = 0.3
	data.has_clouds       = false
	data.cloud_coverage   = 0.05
	data.terrain_roughness = 1.1
	return data

static func make_gas_giant(s: int) -> PlanetData:
	var data := PlanetData.new()
	data.seed        = s
	data.planet_type = Type.GAS_GIANT
	data.planet_name = _generate_name_with_seed(s)
	data.planet_size = 1.6
	data.has_atmosphere   = true
	data.atmosphere_density = 2.0
	data.has_clouds       = true
	data.cloud_coverage   = 1.0
	data.cloud_speed      = 0.12
	data.terrain_roughness = 0.6
	return data

# -----------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------
static func _apply_type_defaults(data: PlanetData, rng: RandomNumberGenerator) -> void:
	match data.planet_type:
		Type.TERRAN:
			data.planet_size        = rng.randf_range(0.85, 1.15)
			data.has_atmosphere     = true
			data.atmosphere_density = rng.randf_range(0.7, 1.2)
			data.has_clouds         = true
			data.cloud_coverage     = rng.randf_range(0.3, 0.7)
			data.continent_scale    = rng.randf_range(0.55, 1.0)  # <1 = bigger landmasses
		Type.ARID:
			data.planet_size        = rng.randf_range(0.7, 1.1)
			data.has_atmosphere     = true
			data.atmosphere_density = rng.randf_range(0.2, 0.6)
			data.has_clouds         = rng.randf() > 0.5
			data.cloud_coverage     = rng.randf_range(0.0, 0.25)
			data.sea_level          = rng.randf_range(0.25, 0.40)
			data.specular_strength  = 0.0
			data.city_lights        = 0.2
		Type.ICE:
			data.planet_size        = rng.randf_range(0.8, 1.2)
			data.has_atmosphere     = true
			data.atmosphere_density = rng.randf_range(0.4, 0.9)
			data.has_clouds         = true
			data.cloud_coverage     = rng.randf_range(0.4, 0.8)
		Type.VOLCANIC:
			data.planet_size        = rng.randf_range(0.8, 1.1)
			data.has_atmosphere     = true
			data.atmosphere_density = rng.randf_range(0.8, 1.5)
			data.has_clouds         = true
			data.cloud_coverage     = rng.randf_range(0.5, 0.9)
			data.cloud_speed        = rng.randf_range(0.08, 0.18)
		Type.BARREN:
			data.planet_size        = rng.randf_range(0.5, 1.0)
			data.has_atmosphere     = rng.randf() > 0.6
			data.atmosphere_density = rng.randf_range(0.0, 0.3)
			data.has_clouds         = false
			data.cloud_coverage     = 0.0
			data.terrain_roughness  = rng.randf_range(1.0, 1.5)
			data.specular_strength  = 0.0
			data.city_lights        = 0.0
		Type.MOON:
			data.planet_size        = rng.randf_range(0.3, 0.55)
			data.has_atmosphere     = false
			data.atmosphere_density = 0.0
			data.has_clouds         = false
			data.cloud_coverage     = 0.0
			data.terrain_roughness  = rng.randf_range(1.2, 1.6)
			data.sea_level          = 0.35  # no ocean
		Type.GAS_GIANT:
			data.planet_size        = rng.randf_range(1.3, 1.8)
			data.has_atmosphere     = true
			data.atmosphere_density = rng.randf_range(1.5, 2.5)
			data.has_clouds         = true
			data.cloud_coverage     = 1.0
			data.cloud_speed        = rng.randf_range(0.08, 0.20)
			data.terrain_roughness  = rng.randf_range(0.4, 0.8)
			# ~55% of gas giants get rings
			if rng.randf() < 0.55:
				data.has_rings  = true
				data.ring_inner = rng.randf_range(1.15, 1.40)
				data.ring_outer = rng.randf_range(1.75, 2.20)
				var hue := rng.randf_range(0.07, 0.14)   # warm tan/gold
				data.ring_color = Color.from_hsv(hue, rng.randf_range(0.15, 0.45), rng.randf_range(0.65, 0.90), rng.randf_range(0.50, 0.72))

static func _generate_name_with_seed(s: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = s ^ 0xABCD
	return _generate_name(rng)

static func _generate_name(rng: RandomNumberGenerator) -> String:
	var prefixes: Array[String] = ["Kep", "Ves", "Nar", "Tal", "Oru", "Vel", "Zan", "Myr", "Sol", "Cor", "Ix", "Ath"]
	var suffixes: Array[String] = ["ara", "eon", "ius", "oth", "ax", "is", "una", "or", "el", "yn", "an", "os"]
	var designators: Array[String] = ["-I", "-II", "-III", "-IV", "-V", "-b", "-c", "-d"]
	var n: String = prefixes[rng.randi() % prefixes.size()] + suffixes[rng.randi() % suffixes.size()]
	if rng.randf() > 0.4:
		n += designators[rng.randi() % designators.size()]
	return n

# -----------------------------------------------------------------------
# Colors per type
# -----------------------------------------------------------------------
static func get_colors(type: Type) -> Dictionary:
	match type:
		Type.TERRAN:
			return {
				"color_deep_ocean": Vector3(0.05, 0.13, 0.30),
				"color_ocean":      Vector3(0.08, 0.20, 0.46),
				"color_shallow":    Vector3(0.12, 0.33, 0.50),
				"color_sand":       Vector3(0.52, 0.46, 0.26),
				"color_grass":      Vector3(0.18, 0.40, 0.15),
				"color_forest":     Vector3(0.09, 0.26, 0.11),
				"color_mountain":   Vector3(0.36, 0.32, 0.26),
				"color_snow":       Vector3(0.86, 0.89, 0.93),
				"color_cloud":      Vector3(0.86, 0.89, 0.94),
				"color_atmosphere": Vector3(0.26, 0.50, 0.90),
			}
		Type.ARID:
			return {
				"color_deep_ocean": Vector3(0.25, 0.18, 0.08),
				"color_ocean":      Vector3(0.38, 0.26, 0.10),
				"color_shallow":    Vector3(0.50, 0.36, 0.16),
				"color_sand":       Vector3(0.68, 0.52, 0.22),
				"color_grass":      Vector3(0.55, 0.40, 0.18),
				"color_forest":     Vector3(0.42, 0.30, 0.14),
				"color_mountain":   Vector3(0.50, 0.38, 0.26),
				"color_snow":       Vector3(0.72, 0.62, 0.44),
				"color_cloud":      Vector3(0.80, 0.72, 0.55),
				"color_atmosphere": Vector3(0.75, 0.50, 0.25),
			}
		Type.ICE:
			return {
				"color_deep_ocean": Vector3(0.08, 0.18, 0.38),
				"color_ocean":      Vector3(0.30, 0.50, 0.72),
				"color_shallow":    Vector3(0.55, 0.72, 0.88),
				"color_sand":       Vector3(0.75, 0.85, 0.92),
				"color_grass":      Vector3(0.82, 0.90, 0.95),
				"color_forest":     Vector3(0.70, 0.80, 0.88),
				"color_mountain":   Vector3(0.88, 0.92, 0.96),
				"color_snow":       Vector3(0.95, 0.97, 1.00),
				"color_cloud":      Vector3(0.92, 0.95, 1.00),
				"color_atmosphere": Vector3(0.55, 0.72, 0.95),
			}
		Type.VOLCANIC:
			return {
				"color_deep_ocean": Vector3(0.10, 0.04, 0.02),
				"color_ocean":      Vector3(0.30, 0.08, 0.02),
				"color_shallow":    Vector3(0.55, 0.18, 0.04),
				"color_sand":       Vector3(0.22, 0.18, 0.16),
				"color_grass":      Vector3(0.18, 0.14, 0.12),
				"color_forest":     Vector3(0.14, 0.10, 0.08),
				"color_mountain":   Vector3(0.30, 0.26, 0.22),
				"color_snow":       Vector3(0.80, 0.50, 0.20),
				"color_cloud":      Vector3(0.40, 0.30, 0.20),
				"color_atmosphere": Vector3(0.55, 0.25, 0.10),
			}
		Type.MOON:
			return {
				"color_deep_ocean": Vector3(0.28, 0.26, 0.24),
				"color_ocean":      Vector3(0.36, 0.34, 0.30),
				"color_shallow":    Vector3(0.44, 0.42, 0.38),
				"color_sand":       Vector3(0.56, 0.54, 0.50),
				"color_grass":      Vector3(0.48, 0.46, 0.42),
				"color_forest":     Vector3(0.38, 0.36, 0.32),
				"color_mountain":   Vector3(0.64, 0.62, 0.58),
				"color_snow":       Vector3(0.80, 0.80, 0.78),
				"color_cloud":      Vector3(0.70, 0.70, 0.68),
				"color_atmosphere": Vector3(0.50, 0.50, 0.48),
			}
		Type.BARREN:
			return {
				"color_deep_ocean": Vector3(0.22, 0.18, 0.16),
				"color_ocean":      Vector3(0.28, 0.22, 0.18),
				"color_shallow":    Vector3(0.36, 0.28, 0.22),
				"color_sand":       Vector3(0.48, 0.38, 0.30),
				"color_grass":      Vector3(0.40, 0.32, 0.26),
				"color_forest":     Vector3(0.34, 0.28, 0.22),
				"color_mountain":   Vector3(0.55, 0.46, 0.38),
				"color_snow":       Vector3(0.70, 0.65, 0.60),
				"color_cloud":      Vector3(0.50, 0.45, 0.40),
				"color_atmosphere": Vector3(0.40, 0.35, 0.28),
			}
		_:  # GAS_GIANT
			return {
				"color_deep_ocean": Vector3(0.50, 0.32, 0.18),
				"color_ocean":      Vector3(0.62, 0.44, 0.24),
				"color_shallow":    Vector3(0.72, 0.58, 0.38),
				"color_sand":       Vector3(0.80, 0.68, 0.50),
				"color_grass":      Vector3(0.68, 0.52, 0.36),
				"color_forest":     Vector3(0.58, 0.40, 0.26),
				"color_mountain":   Vector3(0.74, 0.60, 0.44),
				"color_snow":       Vector3(0.92, 0.88, 0.82),
				"color_cloud":      Vector3(0.88, 0.82, 0.72),
				"color_atmosphere": Vector3(0.72, 0.55, 0.35),
			}

# -----------------------------------------------------------------------
# POI generation
# -----------------------------------------------------------------------
static func get_poi_templates(type: Type) -> Array[Dictionary]:
	var L := LocationFinder.Placement.LAND
	var S := LocationFinder.Placement.SEA
	var C := LocationFinder.Placement.COAST
	match type:
		Type.TERRAN:
			return [
				{"label": "Capital",  "placement": L, "lat_range": [-0.5, 0.5], "light_intensity": 2.0},
				{"label": "Mine",     "placement": L, "lat_range": [-0.6, 0.6], "light_intensity": 0.8},
				{"label": "Outpost",  "placement": L, "lat_range": [-0.8, 0.8], "light_intensity": 0.6},
				{"label": "Port",     "placement": C, "lat_range": [-0.4, 0.4], "light_intensity": 1.2},
				{"label": "Ruins",    "placement": L, "lat_range": [-0.7, 0.7], "light_intensity": 0.2},
			]
		Type.ARID:
			return [
				{"label": "Citadel",   "placement": L, "lat_range": [-0.4, 0.4], "light_intensity": 1.5},
				{"label": "Sand Mine", "placement": L, "lat_range": [-0.6, 0.6], "light_intensity": 0.7},
				{"label": "Oasis",     "placement": L, "lat_range": [-0.3, 0.3], "light_intensity": 0.5},
				{"label": "Bunker",    "placement": L, "lat_range": [-0.7, 0.7], "light_intensity": 0.4},
			]
		Type.VOLCANIC:
			return [
				{"label": "Forge",     "placement": L, "lat_range": [-0.5, 0.5], "light_intensity": 1.8},
				{"label": "Crater",    "placement": L, "lat_range": [-0.7, 0.7], "light_intensity": 0.3},
				{"label": "Vent Mine", "placement": L, "lat_range": [-0.4, 0.4], "light_intensity": 1.0},
			]
		Type.ICE:
			return [
				{"label": "Ice Base",    "placement": L, "lat_range": [-0.6, 0.6], "light_intensity": 1.2},
				{"label": "Drill Rig",   "placement": L, "lat_range": [-0.5, 0.5], "light_intensity": 0.9},
				{"label": "Observatory", "placement": L, "lat_range": [0.3, 0.8],  "light_intensity": 0.6},
			]
		Type.MOON, Type.BARREN:
			return [
				{"label": "Crater Base", "placement": L, "lat_range": [-0.6, 0.6], "light_intensity": 0.5},
				{"label": "Survey Post", "placement": L, "lat_range": [-0.7, 0.7], "light_intensity": 0.3},
			]
		_:
			return [
				{"label": "Station", "placement": S, "lat_range": [-0.5, 0.5], "light_intensity": 0.6},
				{"label": "Depot",   "placement": L, "lat_range": [-0.6, 0.6], "light_intensity": 0.5},
			]

static func generate_pois(type: Type, planet_seed: int, sea_level: float = 0.0,
		roughness: float = 1.0, continent_scale: float = 1.0) -> Array[Dictionary]:
	var lf       := LocationFinder.new(planet_seed, sea_level, roughness, continent_scale)
	var templates := get_poi_templates(type)
	var result:   Array[Dictionary] = []

	for tmpl in templates:
		var lat_min: float = tmpl["lat_range"][0]
		var lat_max: float = tmpl["lat_range"][1]
		var placement: LocationFinder.Placement = tmpl.get("placement", LocationFinder.Placement.LAND)
		var pos: Vector2 = lf.find(placement, lat_min, lat_max)

		result.append({
			"lon_deg": rad_to_deg(pos.x),
			"lat_deg": rad_to_deg(pos.y),
			"label":   tmpl["label"],
			"data":    {"type": tmpl["label"], "light_intensity": tmpl.get("light_intensity", 1.0)},
		})

	return result
