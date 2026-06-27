class_name PlanetProgress
extends Resource

# ── Identity ────────────────────────────────────────────────────────────────
@export var planet_seed: int = 0

# ── Level & Limits ──────────────────────────────────────────────────────────
@export var level: int = 1

@export var max_districts:   int = 4
@export var max_mining_lv:   int = 1
@export var max_generators:  int = 2
@export var max_spaceports:  int = 0

# ── Districts ────────────────────────────────────────────────────────────────
@export var districts_used: int = 0

# ── Buildings ────────────────────────────────────────────────────────────────
## Each entry: { "district_id": String, "building_id": String, "amount": int }
@export var buildings: Array[Dictionary] = []

# ── Resources ────────────────────────────────────────────────────────────────
@export var stored_resources: Dictionary = {}

# ── Unlock flags ─────────────────────────────────────────────────────────────
@export var is_colonized:   bool = false
@export var has_spaceport:  bool = false
@export var moons_unlocked: bool = false

# ── District upgrade levels ──────────────────────────────────────────────────
## { district_label -> upgrade_level: int }, default 1
@export var district_levels: Dictionary = {}

# ────────────────────────────────────────────────────────────────────────────

func recalculate_limits() -> void:
	max_districts  = 4  + (level - 1) * 2
	max_mining_lv  = 1  + (level - 1)
	max_generators = 2  + (level - 1) * 2
	max_spaceports = 1 if level >= 2 else 0

func districts_free() -> int:
	return max_districts - districts_used

func can_build(building_type: String) -> bool:
	match building_type:
		"SpacePort": return districts_free() >= 2 and max_spaceports > 0 and not has_spaceport
		_:           return districts_free() >= 1

func buildings_in_district(district_label: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for b: Dictionary in buildings:
		if b.get("district_id", "") == district_label:
			result.append(b)
	return result

func district_slots(district_label: String) -> int:
	var lv: int = district_levels.get(district_label, 1)
	return lv * 2

func upgrade_district(district_label: String) -> void:
	district_levels[district_label] = district_levels.get(district_label, 1) + 1

func slots_used_in_district(district_label: String) -> int:
	var total: int = 0
	for b: Dictionary in buildings_in_district(district_label):
		var def := BuildingDef.find(b.get("building_id", ""))
		if def != null:
			total += def.slot_cost * b.get("amount", 1)
	return total

func build_in_district(district: POIData, building_id: String) -> bool:
	var def := BuildingDef.find(building_id)
	if def == null:
		return false
	if slots_used_in_district(district.label) + def.slot_cost > district_slots(district.label):
		return false
	buildings.append({ "district_id": district.label, "building_id": building_id, "amount": 1, "constructing": true })
	if building_id == "spaceport":
		has_spaceport = true
	return true

func stack_building_unchecked(district_label: String, building_id: String) -> bool:
	for b: Dictionary in buildings:
		if b.get("district_id") == district_label and b.get("building_id") == building_id:
			b["amount"] = b.get("amount", 1) + 1
			return true
	return false

func add_resource(resource_id: String, amount: float) -> void:
	stored_resources[resource_id] = stored_resources.get(resource_id, 0.0) + amount

func consume_resource(resource_id: String, amount: float) -> bool:
	var have: float = stored_resources.get(resource_id, 0.0)
	if have < amount:
		return false
	stored_resources[resource_id] = have - amount
	return true

static func make(seed_val: int) -> PlanetProgress:
	var p := PlanetProgress.new()
	p.planet_seed = seed_val
	p.recalculate_limits()
	return p
