class_name PlanetProgress
extends Resource

# ── Identity ────────────────────────────────────────────────────────────────
@export var planet_seed: int = 0

# ── Level & Limits ──────────────────────────────────────────────────────────
@export var level: int = 1
@export var is_upgrading: bool = false
@export var upgrade_progress: float = 0.0
@export var upgrade_duration: float = 60.0

const BASE_DISTRICTS:        int = 2   # district slots at level 1
const BASE_ORBITAL_DISTRICTS: int = 1  # orbital slots at level 1–5

@export var max_districts:          int = BASE_DISTRICTS
@export var max_orbital_districts:  int = BASE_ORBITAL_DISTRICTS
@export var max_mining_lv:          int = 1
@export var max_generators:         int = 2
@export var max_spaceports:         int = 0

# ── Districts ────────────────────────────────────────────────────────────────
@export var districts_used: int = 0

# ── Buildings ────────────────────────────────────────────────────────────────
## Each entry: { "district_id": String, "building_id": String, "amount": int }
@export var buildings: Array[Dictionary] = []

# ── Resources ────────────────────────────────────────────────────────────────
@export var stored_resources: Dictionary = {}

func has_building(bid: String) -> bool:
	for entry in buildings:
		if entry.get("building_id", "") == bid and not entry.get("constructing", false):
			return true
	return false

# ── Unlock flags ─────────────────────────────────────────────────────────────
@export var is_colonizing:      bool = false
@export var colonize_progress:  float = 0.0
@export var colonize_duration:  float = 30.0

@export var is_colonized:   bool = false
@export var has_spaceport:  bool = false
@export var moons_unlocked: bool = false

# ── District upgrade levels ──────────────────────────────────────────────────
## { district_label -> upgrade_level: int }, default 1
@export var district_levels: Dictionary = {}
## { district_label -> progress: float 0..1 } — districts currently upgrading
@export var district_upgrading: Dictionary = {}

# ────────────────────────────────────────────────────────────────────────────

## Duration in seconds for upgrading a district to the given target level.
static func district_upgrade_duration(target_lv: int) -> float:
	return 5.0 * target_lv

func get_upgrade_cost() -> Dictionary:
	var cost := {}
	var next_lv := level + 1
	match next_lv:
		2:
			cost["credits"] = 250
		3:
			cost["credits"] = 1000
			cost["ANY_T1"]  = 5
		_:
			cost["credits"] = 500 * next_lv
			cost["ANY_T1"]  = 250 * next_lv
			if next_lv > 4:
				cost["ANY_T2"] = 50 * (next_lv - 4)
	return cost

func recalculate_limits() -> void:
	max_districts         = BASE_DISTRICTS + (level - 1)
	max_orbital_districts = ceili(level / 5.0)

	if has_building("cryo_vault"):
		max_districts += 2

	var st = null
	if Engine.has_singleton("SceneTree") and Engine.get_main_loop():
		st = Engine.get_main_loop().root.get_node_or_null("SkillTree")
	if st and st.has_method("get_max_districts_add"):
		max_districts += st.get_max_districts_add()

	max_mining_lv  = 1 + (level - 1)
	max_generators = 2 + (level - 1) * 2
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

func district_slots(poi: POIData) -> int:
	var lv: int = district_levels.get(poi.label, 1)
	return 3 + (lv - 1) * 2

func can_upgrade_district(district_label: String) -> bool:
	var lv: int = district_levels.get(district_label, 1)
	return lv < level and not district_upgrading.has(district_label)

func is_district_upgrading(district_label: String) -> bool:
	return district_upgrading.has(district_label)

func upgrade_district(district_label: String) -> void:
	if can_upgrade_district(district_label):
		district_upgrading[district_label] = 0.0  # progress 0..1

func slots_used_in_district(district_label: String) -> int:
	var total: int = 0
	for b: Dictionary in buildings_in_district(district_label):
		var def := BuildingDef.find(b.get("building_id", ""))
		if def != null:
			total += def.slot_cost * b.get("amount", 1)
	return total

func build_in_district(district: POIData, building_id: String,
		target_mineral: String = "") -> bool:
	var def := BuildingDef.find(building_id)
	if def == null:
		return false
	if slots_used_in_district(district.label) + def.slot_cost > district_slots(district):
		return false
	
	# Try to find an identical existing building to merge into
	var merge_idx := -1
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if b.get("district_id") == district.label and b.get("building_id") == building_id and not b.get("constructing", false):
			var b_tgt: String = b.get("target_mineral", "")
			if target_mineral == b_tgt or target_mineral == "":
				merge_idx = i
				break
	
	var entry := { "district_id": district.label, "building_id": building_id, "amount": 1, "constructing": true, "uid": str(randi()) }
	if merge_idx != -1:
		entry["merge_into"] = merge_idx
		
	# Mines target a specific raw mineral — caller may supply one, otherwise left blank
	if def.output_type == BuildingDef.OutputType.RAW_MINERAL and target_mineral != "":
		entry["target_mineral"] = target_mineral
		
	buildings.append(entry)
	if building_id == "spaceport":
		has_spaceport = true
	return true

## Stack one more of an existing building — goes through construction before merging.
func stack_building_unchecked(district_label: String, building_id: String, merge_into_entry: Dictionary = {}) -> bool:
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		# If we specified an exact entry, merge into that, otherwise find any matching one
		var match_b = is_same(b, merge_into_entry) if not merge_into_entry.is_empty() else (b.get("district_id") == district_label and b.get("building_id") == building_id)
		if match_b and not b.get("constructing", false):
			var entry := {
				"district_id": district_label,
				"building_id": building_id,
				"amount": 1,
				"constructing": true,
				"merge_into": i,
				"uid": str(randi())
			}
			buildings.append(entry)
			return true
	return false

func upgrade_building(entry: Dictionary) -> bool:
	var idx := building_real_index(entry)
	if idx == -1: return false
	var b := buildings[idx]
	var def := BuildingDef.find(b.get("building_id", ""))
	if def == null: return false
	
	var cur_lv: int = b.get("level", 1)
	var amt: int = b.get("amount", 1)
	var cost := def.get_upgrade_cost(cur_lv, amt)
	
	if GameState.spend_credits(cost):
		b["level"] = cur_lv + 1
		return true
	return false

func split_building(entry: Dictionary, split_amount: int) -> bool:
	var idx := building_real_index(entry)
	if idx == -1: return false
	var b := buildings[idx]
	var current_amt: int = b.get("amount", 1)
	if split_amount <= 0 or split_amount >= current_amt:
		return false
		
	# Reduce current stack
	b["amount"] = current_amt - split_amount
	
	# Create new stack
	var new_stack := b.duplicate(true)
	new_stack["amount"] = split_amount
	new_stack["uid"] = str(randi())
	buildings.append(new_stack)
	return true

func remove_building_stack(entry: Dictionary) -> void:
	var idx = building_real_index(entry)
	if idx >= 0:
		buildings.remove_at(idx)
		for b in buildings:
			if b.has("merge_into"):
				var midx: int = b["merge_into"]
				if midx == idx:
					b.erase("merge_into")
				elif midx > idx:
					b["merge_into"] = midx - 1

func add_resource(resource_id: String, amount: float) -> void:
	GameState.add_resource(resource_id, amount)

## Returns the true array index of an entry using reference equality.
## Avoids the value-equality bug with pp.buildings.find(entry) when two
## entries have identical content (e.g. two Solar Panels in the same district).
func building_real_index(entry: Dictionary) -> int:
	for i in buildings.size():
		if is_same(buildings[i], entry):
			return i
	return -1

func consume_resource(resource_id: String, amount: float) -> bool:
	return GameState.consume_resource(resource_id, amount)

static func make(seed_val: int) -> PlanetProgress:
	var p := PlanetProgress.new()
	p.planet_seed = seed_val
	p.recalculate_limits()
	return p

func get_total_building_levels() -> int:
	var total := 0
	for b in buildings:
		if not b.get("constructing", false):
			total += b.get("level", 1) * b.get("amount", 1)
	return total
