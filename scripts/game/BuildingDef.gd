class_name BuildingDef
extends Resource

enum OutputType { NONE, ENERGY, CREDITS, RAW_MINERAL, REFINED_MINERAL, SCIENCE }

@export var building_id:       String   = ""
@export var display_name:      String   = ""
@export var description:       String   = ""
@export var allowed_poi_types: Array[POIData.POIType] = []
@export var base_cost:         float    = 100.0
@export var slot_cost:         int      = 1
@export var min_planet_lv:     int      = 1

## Production
@export var construct_duration: float     = 0.0    # build time; 0 = use tick_duration
@export var tick_duration:     float      = 30.0   # seconds to fill production bar
@export var energy_per_tick:   float      = 0.0    # negative = consume, positive = produce
@export var output_type:       OutputType = OutputType.NONE
@export var output_amount:     float      = 0.0
@export var input_type:        OutputType = OutputType.NONE
@export var input_amount:      float      = 0.0

func output_color() -> Color:
	match output_type:
		OutputType.ENERGY:         return Color(0.95, 0.88, 0.25)
		OutputType.CREDITS:        return Color(0.35, 0.95, 0.55)
		OutputType.RAW_MINERAL:    return Color(0.15, 0.75, 0.50) # Cyan-emerald green for raw mining
		OutputType.REFINED_MINERAL:return Color(0.75, 0.55, 1.00)
		OutputType.SCIENCE:        return Color(0.20, 0.60, 1.00) # Science Blue
	return Color(0.5, 0.5, 0.5)

func output_label() -> String:
	match output_type:
		OutputType.ENERGY:          return "+%.0f ⚡" % output_amount
		OutputType.CREDITS:         return "+%.0f cr" % output_amount
		OutputType.RAW_MINERAL:     return "+%.0f ore" % output_amount
		OutputType.REFINED_MINERAL: return "+%.0f ref" % output_amount
		OutputType.SCIENCE:         return "+%.0f sci" % output_amount
	return ""

@export var logic: BuildingLogic
@export var unlocked_by_default: bool = true

# ── Catalogue ─────────────────────────────────────────────────────────────────

static var _cache: Array[BuildingDef] = []

static func all() -> Array[BuildingDef]:
	if not _cache.is_empty():
		return _cache
		
	var dir := DirAccess.open("res://resources/buildings")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var res := ResourceLoader.load("res://resources/buildings/" + file_name) as BuildingDef
				if res:
					_cache.append(res)
			file_name = dir.get_next()
	return _cache

static func available_buildings() -> Array[BuildingDef]:
	var result: Array[BuildingDef] = []
	for b in all():
		if b.unlocked_by_default or GameState.unlocked_buildings.has(b.building_id):
			result.append(b)
	return result

static func find(bid: String) -> BuildingDef:
	for b in all():
		if b.building_id == bid:
			return b
	return null

static func for_poi_type(poi_type: POIData.POIType) -> Array[BuildingDef]:
	var result: Array[BuildingDef] = []
	for b in available_buildings():
		if poi_type in b.allowed_poi_types:
			result.append(b)
	return result
