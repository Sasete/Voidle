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
		# ── Energy ──────────────────────────────────────────────────────────────
		# Solar: free energy, no fuel
		_make_b("solar_panel",    "Solar Panel",      "Free energy from sunlight; no fuel needed.",
			POIData.POIType.ENERGY,   80.0, 1, 1,
			20.0, 0.0, OutputType.ENERGY,  2.0, OutputType.NONE, 0.0),

		# Generator: burns minerals at cycle START + END; slow speed = more fuel-efficient
		_make_b("generator",      "Generator",        "Burns minerals for reliable mid-tier energy.",
			POIData.POIType.ENERGY,  350.0, 1, 1,
			14.0, 0.0, OutputType.ENERGY,  8.0, OutputType.RAW_MINERAL, 3.0),

		_make_b("power_plant",    "Power Plant",      "High-output plant; consumes more fuel per cycle.",
			POIData.POIType.ENERGY, 1200.0, 2, 2,
			12.0, 0.0, OutputType.ENERGY, 25.0, OutputType.RAW_MINERAL, 8.0),

		# ── Mining ──────────────────────────────────────────────────────────────
		_make_b("mine",           "Mine",             "Extracts raw minerals from local deposits.",
			POIData.POIType.MINING,  150.0, 1, 1,
			18.0, -2.0, OutputType.RAW_MINERAL, 10.0, OutputType.NONE, 0.0),

		_make_b("deep_drill",     "Deep Drill",       "High-yield extraction at higher energy cost.",
			POIData.POIType.MINING,  600.0, 2, 2,
			15.0, -5.0, OutputType.RAW_MINERAL, 28.0, OutputType.NONE, 0.0),

		_make_b("refinery",       "Refinery",         "Converts raw ore to refined minerals.",
			POIData.POIType.MINING,  800.0, 2, 2,
			24.0, -8.0, OutputType.REFINED_MINERAL, 5.0, OutputType.RAW_MINERAL, 10.0),

		# ── City — tiered income buildings ──────────────────────────────────────
		_make_b("residential",    "Residential Block","Basic housing; fast cycles, light income.",
			POIData.POIType.CITY,    100.0, 1, 1,
			22.0, -2.0, OutputType.CREDITS, 15.0, OutputType.NONE, 0.0),

		_make_b("apartments",     "Apartments",       "Denser housing; higher income per slot.",
			POIData.POIType.CITY,    250.0, 1, 1,
			20.0, -4.0, OutputType.CREDITS, 30.0, OutputType.NONE, 0.0),

		_make_b("commercial",     "Commercial Center","Trade hub with good mid-tier returns.",
			POIData.POIType.CITY,    500.0, 1, 1,
			40.0, -6.0, OutputType.CREDITS, 65.0, OutputType.NONE, 0.0),

		_make_b("luxury_complex", "Luxury Complex",   "Premium residency; slow cycle, large payout.",
			POIData.POIType.CITY,   1200.0, 2, 2,
			80.0, -12.0, OutputType.CREDITS, 160.0, OutputType.NONE, 0.0),

		# ── Outpost ─────────────────────────────────────────────────────────────
		_make_b("spaceport",      "SpacePort",        "Enables ship construction and trade routes.",
			POIData.POIType.OUTPOST, 2000.0, 2, 2,
			0.0, -12.0, OutputType.NONE, 0.0, OutputType.NONE, 0.0),

		# ── Science ─────────────────────────────────────────────────────────────
		_make_b("lab",            "Research Lab",     "Generates research and bonus credits.",
			POIData.POIType.SCIENCE,  700.0, 2, 1,
			35.0, -6.0, OutputType.CREDITS, 25.0, OutputType.NONE, 0.0),

		_make_b("scanner",        "Deep Scanner",     "Reveals hidden deposits across the system.",
			POIData.POIType.SCIENCE,  400.0, 1, 1,
			55.0, -3.0, OutputType.CREDITS, 10.0, OutputType.NONE, 0.0),
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
