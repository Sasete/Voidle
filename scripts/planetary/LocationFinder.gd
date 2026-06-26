class_name LocationFinder
extends RefCounted

## Dependency-injected placement engine.
## Construct once with planet params, call find() for each POI.
##
## Usage:
##   var lf = LocationFinder.new(seed, sea_level, roughness, continent_scale)
##   var pos: Vector2 = lf.find(LocationFinder.Placement.COAST, -0.5, 0.5)
##   # pos.x = lon_rad, pos.y = lat_rad

enum Placement { LAND, SEA, COAST, ANY }

var _seed:            int
var _sea_level:       float
var _roughness:       float
var _continent_scale: float
var _rng:             RandomNumberGenerator
var _used_lons:       Array[float] = []

func _init(p_seed: int, p_sea_level: float, p_roughness: float,
		p_continent_scale: float = 1.0) -> void:
	_seed            = p_seed
	_sea_level       = p_sea_level
	_roughness       = p_roughness
	_continent_scale = p_continent_scale
	_rng             = RandomNumberGenerator.new()
	_rng.seed        = p_seed ^ 0xC0FFEE

## Returns Vector2(lon_rad, lat_rad) for the requested placement type.
## lat_min / lat_max narrow where on the globe to look (radians, default full globe).
func find(placement: Placement,
		lat_min: float = -1.2, lat_max: float = 1.2) -> Vector2:
	var lat:      float = _rng.randf_range(lat_min, lat_max)
	var base_lon: float = _rng.randf_range(0.0, TAU)
	base_lon = _avoid_used(base_lon)

	var final_lon: float = base_lon
	match placement:
		Placement.LAND:
			final_lon = PlanetNoise.find_land_lon(
				base_lon, lat, _seed, _sea_level, _roughness, _continent_scale)
		Placement.SEA:
			final_lon = PlanetNoise.find_sea_lon(
				base_lon, lat, _seed, _sea_level, _roughness, _continent_scale)
		Placement.COAST:
			final_lon = PlanetNoise.find_coast_lon(
				base_lon, lat, _seed, _sea_level, _roughness, _continent_scale)
		_:
			final_lon = base_lon

	_used_lons.append(final_lon)
	return Vector2(final_lon, lat)

func _avoid_used(base_lon: float) -> float:
	for _attempt in 8:
		var too_close: bool = false
		for used: float in _used_lons:
			if abs(fposmod(base_lon - used + PI, TAU) - PI) < deg_to_rad(38.0):
				too_close = true
				break
		if not too_close:
			return base_lon
		base_lon = fposmod(base_lon + deg_to_rad(52.0), TAU)
	return base_lon
