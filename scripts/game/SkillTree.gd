## SkillTree — Autoload singleton or script helper for management of incremental upgrades.
## Tracks unlocked skill IDs, levels, calculates modifiers, and defines node graph info.
extends Node

signal skill_unlocked(id: String)

# Global set of purchased/unlocked skill IDs
var unlocked_skills: Array[String] = ["root"]

# Dictionary for upgrade levels (for multi-level upgrades)
# format: { skill_id: current_level_int }
var skill_levels: Dictionary = {}

# Definitions of all nodes in the skill tree graph
class SkillNode:
	var id: String
	var name: String
	var description: String
	var cost: float
	var pos: Vector2
	var parents: Array[String]
	var tier: int
	var effect_desc: String
	var max_level: int # 1 = single purchase, >1 = leveled upgrade

	func _init(p_id: String, p_name: String, p_desc: String, p_cost: float, p_pos: Vector2, p_parents: Array[String], p_tier: int, p_eff: String, p_max_lv: int = 1) -> void:
		id = p_id
		name = p_name
		description = p_desc
		cost = p_cost
		pos = p_pos
		parents = p_parents
		tier = p_tier
		effect_desc = p_eff
		max_level = p_max_lv

# The upgrade graph structure
var nodes: Dictionary = {}

func _init() -> void:
	# Center root (default unlocked, coordinates relative to center (0,0))
	_add_node("root", "Central Core", "The base operation matrix. Provides power routes.", 0.0, Vector2(0, 0), [], 0, "", 1)

	# Tier 1 (connecting from root)
	# Leveled upgrade: Excavation Drills has 10 levels, each adding +5% speed, cost scales up.
	_add_node("solar_efficiency", "Solar Arrays", "Improves solar cell design to absorb more solar energy.", 150.0, Vector2(0, -90), ["root"], 1, "+25% Solar Array output", 1)
	_add_node("mine_speed", "Excavation Drills", "Equips mining facilities with high-torque diamond drills.", 150.0, Vector2(-110, 50), ["root"], 1, "+5% Mining production speed per level", 10)
	_add_node("generator_efficiency", "Thermal Boosters", "Adds heat capture loops to standard Generators.", 250.0, Vector2(110, 50), ["root"], 1, "+30% Generator Energy output", 1)
	
	_add_node("unlock_generator", "Generator Blueprint", "Unlocks the standard mineral-burning Generator.", 200.0, Vector2(200, 0), ["root"], 1, "Unlocks Generator", 1)
	_add_node("unlock_apartments", "Apartments Blueprint", "Unlocks denser residential housing.", 200.0, Vector2(-200, 0), ["root"], 1, "Unlocks Apartments", 1)
	_add_node("unlock_lab", "Research Lab Blueprint", "Unlocks scientific research facilities.", 300.0, Vector2(0, 100), ["root"], 1, "Unlocks Research Lab", 1)

	# Tier 2 (connecting from T1 nodes)
	_add_node("credit_boost", "Market Integration", "Integrates residential areas with local credit exchanges.", 500.0, Vector2(-110, -130), ["solar_efficiency", "mine_speed"], 2, "+25% Residential Block / Apartments credit payout", 1)
	_add_node("deep_mining", "Seismic Sensors", "Deep scans tectonic plates to output higher yields.", 600.0, Vector2(0, -180), ["mine_speed", "generator_efficiency"], 2, "+25% Mine & Deep Drill output amount", 1)
	_add_node("power_transmission", "Superconducting Grid", "Reduces losses inside energy lines.", 650.0, Vector2(110, -130), ["solar_efficiency", "generator_efficiency"], 2, "-15% Energy consumption on all buildings", 1)
	
	_add_node("unlock_power_plant", "Power Plant Blueprint", "Unlocks massive industrial Power Plants.", 600.0, Vector2(300, 0), ["unlock_generator"], 2, "Unlocks Power Plant", 1)
	_add_node("unlock_refinery", "Refinery Blueprint", "Unlocks ore-to-mineral Refineries.", 400.0, Vector2(200, 100), ["unlock_generator"], 2, "Unlocks Refinery", 1)
	_add_node("unlock_deep_drill", "Deep Drill Blueprint", "Unlocks high-yield Deep Drills.", 450.0, Vector2(-100, 150), ["mine_speed"], 2, "Unlocks Deep Drill", 1)
	_add_node("unlock_commercial", "Commercial Blueprint", "Unlocks Trade Hubs for high income.", 500.0, Vector2(-300, 0), ["unlock_apartments"], 2, "Unlocks Commercial Center", 1)
	_add_node("unlock_moon", "Lunar Expansion", "Provides orbital mechanics calculations required to settle on local moons.", 500.0, Vector2(0, 150), ["unlock_lab"], 2, "Unlocks Moon Colonization", 1)
	_add_node("unlock_spaceport", "SpacePort Blueprint", "Unlocks Orbital SpacePorts.", 800.0, Vector2(0, 220), ["unlock_moon"], 3, "Unlocks SpacePort", 1)
	_add_node("unlock_solar", "Interplanetary Travel", "Allows ships to traverse the vast distances between planets.", 1500.0, Vector2(0, 300), ["unlock_spaceport"], 4, "Unlocks Solar System Travel", 1)

	# Tier 3 (connecting from T2 nodes)
	_add_node("omega_core", "Supercharged Grid", "Syncs all colony grids into a single self-correcting neural system.", 1200.0, Vector2(0, -250), ["credit_boost", "power_transmission"], 3, "+20% production speed globally", 1)
	
	_add_node("unlock_luxury_complex", "Luxury Complex Blueprint", "Unlocks premium housing for elites.", 1000.0, Vector2(-400, 0), ["unlock_commercial"], 3, "Unlocks Luxury Complex", 1)

func _add_node(id: String, name: String, desc: String, cost: float, pos: Vector2, parents: Array[String], tier: int, eff: String, max_lv: int = 1) -> void:
	nodes[id] = SkillNode.new(id, name, desc, cost, pos, parents, tier, eff, max_lv)

# Get current level of a node (returns 0 if locked/not started)
func get_skill_level(id: String) -> int:
	if id == "root":
		return 1
	if id not in unlocked_skills:
		return 0
	return skill_levels.get(id, 1)

# Get cost of next level
func get_next_cost(id: String) -> float:
	var node: SkillNode = nodes.get(id, null)
	if node == null:
		return 0.0
	var cur_lv := get_skill_level(id)
	if cur_lv >= node.max_level:
		return 0.0
	# Linear cost scaling: Base cost * (1 + current_level)
	return node.cost * (1.0 + cur_lv)

# Check if a skill can be purchased / upgraded
func can_purchase(id: String) -> bool:
	var node: SkillNode = nodes.get(id, null)
	if node == null:
		return false
		
	var cur_lv := get_skill_level(id)
	if cur_lv >= node.max_level:
		return false

	# If first purchase, check parents
	if cur_lv == 0:
		var parent_ok := false
		for p in node.parents:
			if p in unlocked_skills:
				parent_ok = true
				break
		if not parent_ok and not node.parents.is_empty():
			return false

	var next_cost := get_next_cost(id)
	return GameState.credits >= next_cost

# Buy or upgrade a skill node
func purchase_skill(id: String) -> bool:
	if not can_purchase(id):
		return false
	var next_cost := get_next_cost(id)
	if GameState.spend_credits(next_cost):
		var cur_lv := get_skill_level(id)
		if cur_lv == 0:
			unlocked_skills.append(id)
			skill_levels[id] = 1
			
			if id == "unlock_moon":
				GameState.moon_unlocked = true
			elif id == "unlock_solar":
				GameState.solar_unlocked = true
			elif id.begins_with("unlock_"):
				GameState.unlock_building(id.trim_prefix("unlock_"))
		else:
			skill_levels[id] = cur_lv + 1
			
		skill_unlocked.emit(id)
		GameState.save()
		return true
	return false

# Check if a node is visible (at least one parent is unlocked, or itself unlocked)
func is_visible(id: String) -> bool:
	if id == "root" or id in unlocked_skills:
		return true
	var node: SkillNode = nodes.get(id, null)
	if node == null:
		return false
	for p in node.parents:
		if p in unlocked_skills:
			return true
	return false

# ── Dynamic Modifiers read by GameState/ProductionManager ─────────────────────

func get_solar_mult() -> float:
	return 1.25 if "solar_efficiency" in unlocked_skills else 1.0

func get_mine_speed_mult() -> float:
	var base := 1.0
	if "mine_speed" in unlocked_skills:
		var lv := get_skill_level("mine_speed")
		base += 0.05 * lv
	if "omega_core" in unlocked_skills:
		base += 0.20
	return base

func get_generator_output_mult() -> float:
	return 1.30 if "generator_efficiency" in unlocked_skills else 1.0

func get_credits_mult() -> float:
	return 1.25 if "credit_boost" in unlocked_skills else 1.0

func get_mine_output_mult() -> float:
	return 1.25 if "deep_mining" in unlocked_skills else 1.0

func get_energy_consume_mult() -> float:
	return 0.85 if "power_transmission" in unlocked_skills else 1.0

func get_global_speed_mult() -> float:
	var base := 1.0
	if "omega_core" in unlocked_skills:
		base += 0.20
	return base
