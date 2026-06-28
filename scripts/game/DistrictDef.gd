## Defines a district type: what it's called, where it can be placed,
## what buildings it can contain, and its default placement preference.
class_name DistrictDef
extends Resource

enum Type { CITY, GENERATOR, MINING }

@export var id:           Type
@export var display_name: String
@export var description:  String
@export var icon:         String
@export var placement:    LocationFinder.Placement
@export var base_cost:    float
@export var construction_duration: float = 15.0
## Empty = available on all planet types.
@export var allowed_planet_types: Array[PlanetData.Type] = []
## Which BuildingDef building_ids are available inside this district type.
@export var building_ids: Array[String] = []
## Name pool used for random name suggestions.
@export var name_pool:    Array[String] = []

# ── Registry ─────────────────────────────────────────────────────────────────

static var _cache: Array[DistrictDef] = []

static func all() -> Array[DistrictDef]:
	if not _cache.is_empty():
		return _cache
		
	var dir := DirAccess.open("res://resources/districts")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var res := ResourceLoader.load("res://resources/districts/" + file_name) as DistrictDef
				if res:
					_cache.append(res)
			file_name = dir.get_next()
	return _cache

static func for_planet(planet_type: PlanetData.Type) -> Array[DistrictDef]:
	var result: Array[DistrictDef] = []
	for d: DistrictDef in all():
		if d.allowed_planet_types.is_empty() or planet_type in d.allowed_planet_types:
			result.append(d)
	return result

static func find(district_type: Type) -> DistrictDef:
	for d: DistrictDef in all():
		if d.id == district_type:
			return d
	return null

# ── Factory ───────────────────────────────────────────────────────────────────

## Compute actual placement cost based on how many same-type districts already exist.
## Cost doubles for each additional district of the same type.
static func placement_cost(def: DistrictDef, data: PlanetData) -> float:
	var same_count: int = 0
	for poi: POIData in data.custom_pois:
		if poi.poi_type == def.to_poi_type():
			same_count += 1
	return def.base_cost * pow(2.0, float(same_count))

## Suggest a random name from the pool using planet seed + current district count for variation.
func suggest_name(data: PlanetData) -> String:
	if name_pool.is_empty():
		return display_name
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ (data.custom_pois.size() * 0xA7F3 + id * 0x1234)
	return name_pool[rng.randi() % name_pool.size()]

## Convert DistrictDef.Type → POIData.POIType for placement.
func to_poi_type() -> POIData.POIType:
	match id:
		Type.CITY:      return POIData.POIType.CITY
		Type.GENERATOR: return POIData.POIType.ENERGY
		Type.MINING:    return POIData.POIType.MINING
		_:              return POIData.POIType.CITY
