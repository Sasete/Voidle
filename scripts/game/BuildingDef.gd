class_name BuildingDef
extends Resource

## Which POI types can host this building.
@export var allowed_poi_types: Array[POIData.POIType] = []

@export var building_id:   String = ""
@export var display_name:  String = ""
@export var description:   String = ""

## Base construction cost in credits.
@export var base_cost:     float  = 100.0

## How much planet-local energy this building consumes per tick (negative = produces).
@export var energy_delta:  float  = -1.0   # negative = consumes

## Minimum planet level required to build.
@export var min_planet_lv: int    = 1

## Slots this building occupies in the POI.
@export var slot_cost:     int    = 1

## Unique key used in PlanetProgress.buildings entries.
func id() -> String:
	return building_id

# ── Built-in catalogue ────────────────────────────────────────────────────────

static func all() -> Array[BuildingDef]:
	return [
		_make("solar_panel",   "Solar Panel",       "Provides basic energy.",
			POIData.POIType.ENERGY, 80.0,   2.0, 1, 1),
		_make("generator",     "Generator",         "Reliable mid-tier energy source.",
			POIData.POIType.ENERGY, 350.0,  8.0, 1, 1),
		_make("power_plant",   "Power Plant",       "High-output energy production.",
			POIData.POIType.ENERGY, 1200.0, 25.0, 2, 2),

		_make("mine",          "Mine",              "Extracts raw minerals from the ground.",
			POIData.POIType.MINING, 150.0, -2.0, 1, 1),
		_make("deep_drill",    "Deep Drill",        "High-yield mineral extraction.",
			POIData.POIType.MINING, 600.0, -5.0, 2, 2),
		_make("refinery",      "Refinery",          "Converts raw minerals to refined goods.",
			POIData.POIType.MINING, 800.0, -8.0, 2, 2),

		_make("hab_block",     "Hab Block",         "Houses colonists, generates basic income.",
			POIData.POIType.CITY, 200.0, -3.0, 1, 1),
		_make("market",        "Market",            "Boosts credit income from the colony.",
			POIData.POIType.CITY, 500.0, -4.0, 1, 1),
		_make("spaceport",     "SpacePort",         "Enables ship construction and trade routes.",
			POIData.POIType.OUTPOST, 2000.0, -12.0, 2, 2),

		_make("lab",           "Research Lab",      "Generates science points over time.",
			POIData.POIType.SCIENCE, 700.0, -6.0, 2, 1),
		_make("scanner",       "Deep Scanner",      "Reveals hidden resource deposits.",
			POIData.POIType.SCIENCE, 400.0, -3.0, 1, 1),
	]

static func find(building_id: String) -> BuildingDef:
	for b in all():
		if b.building_id == building_id:
			return b
	return null

static func for_poi_type(poi_type: POIData.POIType) -> Array[BuildingDef]:
	var result: Array[BuildingDef] = []
	for b in all():
		if poi_type in b.allowed_poi_types:
			result.append(b)
	return result

static func _make(bid: String, dname: String, desc: String,
		poi_type: POIData.POIType, cost: float,
		energy: float, min_lv: int, slots: int) -> BuildingDef:
	var b              := BuildingDef.new()
	b.building_id      = bid
	b.display_name     = dname
	b.description      = desc
	b.allowed_poi_types = [poi_type]
	b.base_cost        = cost
	b.energy_delta     = energy
	b.min_planet_lv    = min_lv
	b.slot_cost        = slots
	return b
