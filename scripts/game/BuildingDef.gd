class_name BuildingDef
extends Resource

enum OutputType { NONE, ENERGY, CREDITS, RAW_MINERAL, REFINED_MINERAL }

@export var building_id:       String   = ""
@export var display_name:      String   = ""
@export var description:       String   = ""
@export var allowed_poi_types: Array[POIData.POIType] = []
@export var base_cost:         float    = 100.0
@export var slot_cost:         int      = 1
@export var min_planet_lv:     int      = 1

## Production
@export var tick_duration:     float      = 30.0   # seconds to fill bar
@export var energy_per_tick:   float      = 0.0    # negative = consume, positive = produce
@export var output_type:       OutputType = OutputType.NONE
@export var output_amount:     float      = 0.0
@export var input_type:        OutputType = OutputType.NONE
@export var input_amount:      float      = 0.0

func output_color() -> Color:
	match output_type:
		OutputType.ENERGY:         return Color(0.95, 0.88, 0.25)
		OutputType.CREDITS:        return Color(0.35, 0.95, 0.55)
		OutputType.RAW_MINERAL:    return Color(0.45, 0.70, 1.00)
		OutputType.REFINED_MINERAL:return Color(0.75, 0.55, 1.00)
	return Color(0.5, 0.5, 0.5)

func output_label() -> String:
	match output_type:
		OutputType.ENERGY:          return "+%.0f ⚡" % output_amount
		OutputType.CREDITS:         return "+%.0f cr" % output_amount
		OutputType.RAW_MINERAL:     return "+%.0f ore" % output_amount
		OutputType.REFINED_MINERAL: return "+%.0f ref" % output_amount
	return ""

# ── Catalogue ─────────────────────────────────────────────────────────────────

static func all() -> Array[BuildingDef]:
	return [
		_make_b("solar_panel",  "Solar Panel",   "Basic energy from sunlight.",
			POIData.POIType.ENERGY,  80.0, 1, 1,
			45.0, 0.0, OutputType.ENERGY, 2.0, OutputType.NONE, 0.0),

		_make_b("generator",    "Generator",     "Reliable mid-tier energy.",
			POIData.POIType.ENERGY, 350.0, 1, 1,
			30.0, 0.0, OutputType.ENERGY, 8.0, OutputType.NONE, 0.0),

		_make_b("power_plant",  "Power Plant",   "High-output energy.",
			POIData.POIType.ENERGY, 1200.0, 2, 2,
			25.0, 0.0, OutputType.ENERGY, 25.0, OutputType.NONE, 0.0),

		_make_b("mine",         "Mine",          "Extracts raw minerals.",
			POIData.POIType.MINING, 150.0, 1, 1,
			40.0, -2.0, OutputType.RAW_MINERAL, 10.0, OutputType.NONE, 0.0),

		_make_b("deep_drill",   "Deep Drill",    "High-yield extraction.",
			POIData.POIType.MINING, 600.0, 2, 2,
			35.0, -5.0, OutputType.RAW_MINERAL, 28.0, OutputType.NONE, 0.0),

		_make_b("refinery",     "Refinery",      "Converts ore to refined goods.",
			POIData.POIType.MINING, 800.0, 2, 2,
			50.0, -8.0, OutputType.REFINED_MINERAL, 5.0, OutputType.RAW_MINERAL, 10.0),

		_make_b("hab_block",    "Hab Block",     "Houses colonists, generates income.",
			POIData.POIType.CITY, 200.0, 1, 1,
			60.0, -3.0, OutputType.CREDITS, 15.0, OutputType.NONE, 0.0),

		_make_b("market",       "Market",        "Boosts credit income.",
			POIData.POIType.CITY, 500.0, 1, 1,
			90.0, -4.0, OutputType.CREDITS, 40.0, OutputType.NONE, 0.0),

		_make_b("spaceport",    "SpacePort",     "Enables ship construction.",
			POIData.POIType.OUTPOST, 2000.0, 2, 2,
			0.0, -12.0, OutputType.NONE, 0.0, OutputType.NONE, 0.0),

		_make_b("lab",          "Research Lab",  "Generates science over time.",
			POIData.POIType.SCIENCE, 700.0, 2, 1,
			80.0, -6.0, OutputType.CREDITS, 25.0, OutputType.NONE, 0.0),

		_make_b("scanner",      "Deep Scanner",  "Reveals hidden deposits.",
			POIData.POIType.SCIENCE, 400.0, 1, 1,
			120.0, -3.0, OutputType.CREDITS, 10.0, OutputType.NONE, 0.0),
	]

static func find(bid: String) -> BuildingDef:
	for b in all():
		if b.building_id == bid:
			return b
	return null

static func for_poi_type(poi_type: POIData.POIType) -> Array[BuildingDef]:
	var result: Array[BuildingDef] = []
	for b in all():
		if poi_type in b.allowed_poi_types:
			result.append(b)
	return result

static func _make_b(bid: String, dname: String, desc: String,
		poi_type: POIData.POIType, cost: float, min_lv: int, slots: int,
		tick: float, energy: float,
		out_type: OutputType, out_amt: float,
		in_type: OutputType, in_amt: float) -> BuildingDef:
	var b               := BuildingDef.new()
	b.building_id        = bid
	b.display_name       = dname
	b.description        = desc
	b.allowed_poi_types  = [poi_type]
	b.base_cost          = cost
	b.min_planet_lv      = min_lv
	b.slot_cost          = slots
	b.tick_duration      = tick
	b.energy_per_tick    = energy
	b.output_type        = out_type
	b.output_amount      = out_amt
	b.input_type         = in_type
	b.input_amount       = in_amt
	return b
