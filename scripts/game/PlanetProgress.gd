class_name PlanetProgress
extends Resource

# ── Identity ────────────────────────────────────────────────────────────────
@export var planet_seed: int = 0

# ── Level & Limits ──────────────────────────────────────────────────────────
@export var level: int = 1

## Computed limits — call recalculate_limits() after level change.
@export var max_districts:   int = 4
@export var max_mining_lv:   int = 1
@export var max_generators:  int = 2
@export var max_spaceports:  int = 0   # 0 = locked until researched

# ── Districts ────────────────────────────────────────────────────────────────
@export var districts_used: int = 0

# ── Buildings ────────────────────────────────────────────────────────────────
## Each entry: { "poi_id": String, "type": String, "level": int }
@export var buildings: Array[Dictionary] = []

# ── Resources ────────────────────────────────────────────────────────────────
## { resource_id: String -> amount: float }
@export var stored_resources: Dictionary = {}

# ── Unlock flags ─────────────────────────────────────────────────────────────
@export var has_spaceport:    bool = false
@export var moons_unlocked:   bool = false   # true once orbital access is researched

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
