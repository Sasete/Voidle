class_name PlanetModifier
extends RefCounted

enum Effect {
	MINE_OUTPUT_MULT,    ## Multiplies raw mineral output (1.0 = no change)
	MINE_SPEED_MULT,     ## Multiplies mine tick speed
	MAX_DISTRICTS_ADD,   ## Flat add/subtract to max district count
	MAX_SLOTS_ADD,       ## Flat add/subtract to each district's slot count
	ENERGY_COST_MULT,    ## Multiplies energy consumed per tick for all buildings
	BUILD_COST_MULT,     ## Multiplies building purchase cost
}

var display_name: String = ""
var description:  String = ""
var effect:       Effect = Effect.MINE_OUTPUT_MULT
var value:        float  = 1.0   # multiplicative effects: 1.0=neutral; additive: 0=neutral

func is_positive() -> bool:
	match effect:
		Effect.MINE_OUTPUT_MULT:   return value > 1.0
		Effect.MINE_SPEED_MULT:    return value > 1.0
		Effect.MAX_DISTRICTS_ADD:  return value > 0.0
		Effect.MAX_SLOTS_ADD:      return value > 0.0
		Effect.ENERGY_COST_MULT:   return value < 1.0
		Effect.BUILD_COST_MULT:    return value < 1.0
	return true

func value_label() -> String:
	match effect:
		Effect.MINE_OUTPUT_MULT, Effect.MINE_SPEED_MULT, \
		Effect.ENERGY_COST_MULT, Effect.BUILD_COST_MULT:
			var pct: float = (value - 1.0) * 100.0
			return ("%+.0f%%" % pct)
		Effect.MAX_DISTRICTS_ADD, Effect.MAX_SLOTS_ADD:
			return ("%+d" % int(value))
	return ""

# ── Catalogue per planet type ─────────────────────────────────────────────────

static func for_planet(planet_type: PlanetData.Type) -> Array[PlanetModifier]:
	match planet_type:
		PlanetData.Type.TERRAN:
			return _list([
				_m("Fertile Soil",     "Rich biosphere accelerates colonisation.",   Effect.MAX_DISTRICTS_ADD, 2.0),
				_m("Mild Climate",     "Reduced infrastructure upkeep.",             Effect.ENERGY_COST_MULT,  0.85),
			])
		PlanetData.Type.ARID:
			return _list([
				_m("Dust Storms",      "Abrasive atmosphere slows mining equipment.", Effect.MINE_SPEED_MULT,   0.80),
				_m("Solar Exposure",   "High irradiance boosts solar output.",        Effect.ENERGY_COST_MULT,  0.90),
				_m("Sparse Terrain",   "Fewer viable district sites.",               Effect.MAX_DISTRICTS_ADD, -1.0),
			])
		PlanetData.Type.ICE:
			return _list([
				_m("Deep Freeze",      "Heating costs raise energy consumption.",    Effect.ENERGY_COST_MULT,  1.30),
				_m("Cryo Deposits",    "Mineral pockets are dense but slow to reach.", Effect.MINE_OUTPUT_MULT, 1.20),
				_m("Limited Terrain",  "Ice sheets restrict buildable area.",        Effect.MAX_SLOTS_ADD,     -1.0),
			])
		PlanetData.Type.VOLCANIC:
			return _list([
				_m("Geothermal Veins", "Volcanic activity supercharges mining.",     Effect.MINE_SPEED_MULT,   1.50),
				_m("Rich Ore Seams",   "Exceptional mineral concentration.",         Effect.MINE_OUTPUT_MULT,  1.75),
				_m("Unstable Ground",  "Frequent tremors reduce district capacity.", Effect.MAX_DISTRICTS_ADD, -2.0),
				_m("Heat Overhead",    "Cooling systems increase energy draw.",      Effect.ENERGY_COST_MULT,  1.20),
			])
		PlanetData.Type.BARREN:
			return _list([
				_m("Thin Crust",       "Easy access to sub-surface deposits.",       Effect.MINE_SPEED_MULT,   1.20),
				_m("No Atmosphere",    "Vacuum simplifies some extraction methods.", Effect.BUILD_COST_MULT,   0.90),
				_m("Harsh Surface",    "Minimal habitable zones.",                   Effect.MAX_DISTRICTS_ADD, -1.0),
			])
		PlanetData.Type.GAS_GIANT:
			return _list([
				_m("No Surface",       "Surface mining is impossible.",              Effect.MINE_OUTPUT_MULT,  0.0),
				_m("Atmospheric Lift", "Wind energy offsets infrastructure cost.",   Effect.ENERGY_COST_MULT,  0.70),
				_m("Ring Access",      "Ring material supplements construction.",    Effect.BUILD_COST_MULT,   0.80),
			])
		PlanetData.Type.MOON:
			return _list([
				_m("Low Gravity",      "Easier construction, lower energy draw.",    Effect.ENERGY_COST_MULT,  0.75),
				_m("Small Body",       "Limited district count.",                    Effect.MAX_DISTRICTS_ADD, -2.0),
				_m("Compact Crust",    "High-density deposits in small area.",       Effect.MINE_OUTPUT_MULT,  1.30),
			])
		PlanetData.Type.ASTEROID:
			return _list([
				_m("Micro-Gravity",    "Cramped conditions reduce district space.",  Effect.MAX_DISTRICTS_ADD, -3.0),
				_m("Tight Quarters",   "Each district fits fewer buildings.",        Effect.MAX_SLOTS_ADD,     -1.0),
				_m("Metal-Rich Core",  "Exceptional ore concentration.",             Effect.MINE_OUTPUT_MULT,  1.75),
				_m("Fast Extraction",  "Proximity of ore dramatically speeds mining.", Effect.MINE_SPEED_MULT, 2.00),
			])
	return []

static func _list(arr: Array) -> Array[PlanetModifier]:
	var result: Array[PlanetModifier] = []
	for m in arr:
		result.append(m)
	return result

static func _m(name: String, desc: String, eff: Effect, val: float) -> PlanetModifier:
	var m           := PlanetModifier.new()
	m.display_name  = name
	m.description   = desc
	m.effect        = eff
	m.value         = val
	return m

# ── Apply helpers ─────────────────────────────────────────────────────────────

## Combined multiplier for a given effect across all modifiers of a planet.
static func combined(mods: Array[PlanetModifier], eff: Effect) -> float:
	var result := 1.0
	for m: PlanetModifier in mods:
		if m.effect == eff:
			match eff:
				Effect.MAX_DISTRICTS_ADD, Effect.MAX_SLOTS_ADD:
					result += m.value   # additive
				_:
					result *= m.value   # multiplicative
	return result

static func combined_add(mods: Array[PlanetModifier], eff: Effect) -> int:
	var result: int = 0
	for m: PlanetModifier in mods:
		if m.effect == eff:
			result += int(m.value)
	return result
