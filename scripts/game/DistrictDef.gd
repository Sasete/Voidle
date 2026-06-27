## Defines a district type: what it's called, where it can be placed,
## what buildings it can contain, and its default placement preference.
class_name DistrictDef
extends RefCounted

enum Type { CITY, GENERATOR, MINING }

var id:           Type
var display_name: String
var description:  String
var icon:         String
var placement:    LocationFinder.Placement
var base_cost:    float
## Empty = available on all planet types.
var allowed_planet_types: Array[PlanetData.Type] = []
## Which BuildingDef building_ids are available inside this district type.
var building_ids: Array[String] = []
## Name pool used for random name suggestions.
var name_pool:    Array[String] = []

# ── Registry ─────────────────────────────────────────────────────────────────

static var _all: Array[DistrictDef] = []

static func all() -> Array[DistrictDef]:
	if _all.is_empty():
		_build_registry()
	return _all

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

static func _make(
		p_id: Type, name: String, desc: String, icon: String,
		placement: LocationFinder.Placement, cost: float,
		allowed: Array[PlanetData.Type],
		buildings: Array[String],
		names: Array[String]) -> DistrictDef:
	var d := DistrictDef.new()
	d.id           = p_id
	d.display_name = name
	d.description  = desc
	d.icon         = icon
	d.placement    = placement
	d.base_cost    = cost
	d.allowed_planet_types = allowed
	d.building_ids = buildings
	d.name_pool    = names
	return d

static func _build_registry() -> void:
	_all = [
		_make(
			Type.CITY,
			"City",
			"Residential and commercial hub. Generates credits and houses population.",
			"⬡",
			LocationFinder.Placement.LAND,
			500.0,
			[PlanetData.Type.TERRAN, PlanetData.Type.ARID, PlanetData.Type.ICE,
			 PlanetData.Type.MOON],
			["market", "housing", "spaceport"],
			["New Carthage", "Iron Shore", "Veylan", "Kelast", "Dusk Harbor",
			 "Aelstrom", "Fort Virion", "Mirelith", "Sunfall", "Coldmere",
			 "Outpost Hera", "New Delos", "Vanta Port", "Ashfield", "Creston"]
		),
		_make(
			Type.GENERATOR,
			"Generator Facility",
			"Power plant complex. Produces energy for the colony grid.",
			"⚡",
			LocationFinder.Placement.ANY,
			300.0,
			[],   # available on all planet types
			["solar_array", "fusion_reactor", "geothermal_tap"],
			["Prometheus Array", "Grid Station Alpha", "Helios Platform",
			 "Solara Base", "Arc Station", "Photon Plant", "Voltex Hub",
			 "Enerion Core", "Tesla Relay", "Surge Complex", "Dawn Array"]
		),
		_make(
			Type.MINING,
			"Mining Facility",
			"Extracts raw minerals from local deposits.",
			"⛏",
			LocationFinder.Placement.ANY,
			250.0,
			[PlanetData.Type.TERRAN, PlanetData.Type.ARID, PlanetData.Type.ICE,
			 PlanetData.Type.VOLCANIC, PlanetData.Type.BARREN,
			 PlanetData.Type.MOON, PlanetData.Type.ASTEROID],
			["mining_drill", "deep_drill", "ore_processor"],
			["Deepvein Complex", "Stratum Site Alpha", "Iron Reach",
			 "Core Station", "Bedrock Post", "Shaft Prime", "Mineral Yard",
			 "Excavation Base", "Ironfall", "Quarry One", "Veindepth"]
		),
	]

## Convert DistrictDef.Type → POIData.POIType for placement.
func to_poi_type() -> POIData.POIType:
	match id:
		Type.CITY:      return POIData.POIType.CITY
		Type.GENERATOR: return POIData.POIType.ENERGY
		Type.MINING:    return POIData.POIType.MINING
		_:              return POIData.POIType.CITY
